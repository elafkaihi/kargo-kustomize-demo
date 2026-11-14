#!/usr/bin/env bash
# One-command setup: k3d cluster -> platform -> Git repo -> Argo CD apps -> Kargo pipeline.
# Safe to re-run. Ends with every environment on podinfo $BASELINE_TAG.
. "$(dirname "$0")/lib.sh"
cd "$ROOT"

# ---------------------------------------------------------------- 0. checks
log "Checking prerequisites"
for t in docker k3d kubectl helm kustomize gh git jq yq kargo openssl; do
  command -v "$t" >/dev/null || die "missing tool: $t (run: make tools)"
done
docker info >/dev/null 2>&1 || die "docker is not running"
[[ -n "${GITHUB_TOKEN:-}" ]] || die "GITHUB_TOKEN is not set (put it in .env, see .env.example)"
export GH_TOKEN="$GITHUB_TOKEN"
ok "tools present, docker running, GitHub token available"

# ---------------------------------------------------------------- 1. cluster
mkdir -p "$ROOT/.kube" "$SECRETS_DIR"
if ! k3d cluster list -o json | jq -e --arg c "$CLUSTER" '.[] | select(.name == $c)' >/dev/null; then
  log "Creating k3d cluster $CLUSTER"
  k3d cluster create --config cluster/k3d.yaml --subnet "$K3D_SUBNET" \
    --kubeconfig-update-default=false --kubeconfig-switch-context=false
fi
LB_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "k3d-$CLUSTER-serverlb")
if command -v ip >/dev/null && ! ip route get "$LB_IP" | grep -q ' dev br-'; then
  die "the host routes $LB_IP away from Docker ($(ip route get "$LB_IP" | head -1)). A VPN probably routes this subnet: set K3D_SUBNET in .env to a free range, then run make down && make up"
fi
k3d kubeconfig get "$CLUSTER" > "$KUBECONFIG"
chmod 600 "$KUBECONFIG"
wait_for "cluster API reachable" 120 k get --raw /readyz
wait_for "node Ready" 120 k wait --for=condition=Ready node --all --timeout=5s

# ---------------------------------------------------------------- 2. registry + chart repo + baseline
log "Installing demo image registry and chart repo"
k apply -f platform/registry.yaml -f platform/chartmuseum.yaml >/dev/null
k -n registry rollout status deploy/registry --timeout=180s >/dev/null
k -n chartmuseum rollout status deploy/chartmuseum --timeout=180s >/dev/null
wait_for "registry reachable on $PUSH_REGISTRY" 60 curl -fsS "http://$PUSH_REGISTRY/v2/"
wait_for "chart repo reachable on $PUSH_CHARTS" 60 curl -fsS "http://$PUSH_CHARTS/health"
"$ROOT/scripts/release.sh" "$BASELINE_TAG"
"$ROOT/scripts/release-chart.sh" "$BASELINE_CHART"

# ---------------------------------------------------------------- 3. platform charts
log "Installing cert-manager $CERT_MANAGER_CHART"
h upgrade --install cert-manager cert-manager --repo https://charts.jetstack.io \
  --version "$CERT_MANAGER_CHART" -n cert-manager --create-namespace \
  --set crds.enabled=true --wait --timeout 5m >/dev/null

log "Installing kube-prometheus-stack $KPS_CHART"
h upgrade --install kps kube-prometheus-stack --repo https://prometheus-community.github.io/helm-charts \
  --version "$KPS_CHART" -n monitoring --create-namespace \
  -f platform/kube-prometheus-stack-values.yaml --wait --timeout 10m >/dev/null

log "Installing Argo Rollouts $ARGO_ROLLOUTS_CHART (for AnalysisTemplate/AnalysisRun)"
h upgrade --install argo-rollouts argo-rollouts --repo https://argoproj.github.io/argo-helm \
  --version "$ARGO_ROLLOUTS_CHART" -n argo-rollouts --create-namespace --wait --timeout 5m >/dev/null

log "Installing Argo CD $ARGOCD_CHART"
h upgrade --install argocd argo-cd --repo https://argoproj.github.io/argo-helm \
  --version "$ARGOCD_CHART" -n argocd --create-namespace \
  -f platform/argocd-values.yaml --wait --timeout 10m >/dev/null

log "Installing Kargo $KARGO_CHART"
if [[ ! -s "$SECRETS_DIR/kargo-admin-password" ]]; then
  openssl rand -base64 48 | tr -d '=+/' | head -c 24 > "$SECRETS_DIR/kargo-admin-password"
  openssl rand -base64 48 | tr -d '=+/' | head -c 32 > "$SECRETS_DIR/kargo-signing-key"
  chmod 600 "$SECRETS_DIR"/*
fi
KARGO_HASH=$(kargo hash-password --password "$(cat "$SECRETS_DIR/kargo-admin-password")")
h upgrade --install kargo oci://ghcr.io/akuity/kargo-charts/kargo \
  --version "$KARGO_CHART" -n kargo --create-namespace \
  -f platform/kargo-values.yaml \
  --set-string api.adminAccount.passwordHash="$KARGO_HASH" \
  --set-string api.adminAccount.tokenSigningKey="$(cat "$SECRETS_DIR/kargo-signing-key")" \
  --wait --timeout 10m >/dev/null
ok "platform installed"

# ---------------------------------------------------------------- 4. Git repo
log "Preparing GitHub repo $GITHUB_USER/$REPO_NAME"
gh repo view "$GITHUB_USER/$REPO_NAME" >/dev/null 2>&1 ||
  gh repo create "$GITHUB_USER/$REPO_NAME" --private >/dev/null
[[ -d .git ]] || git init -q -b main
git remote get-url origin >/dev/null 2>&1 || git remote add origin "$GIT_REPO_URL"
GIT_AUTH=(-c "http.https://github.com/.extraheader=AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 -w0)")
if git "${GIT_AUTH[@]}" ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
  git "${GIT_AUTH[@]}" pull -q --rebase --autostash origin main   # pick up Kargo's promotion commits
fi
git "${GIT_AUTH[@]}" push -q -u origin main
ok "repo pushed: ${GIT_REPO_URL%.git}"

# ---------------------------------------------------------------- 5. Argo CD apps
log "Giving Argo CD read access to the (private) repo"
k -n argocd create secret generic gitops-repo \
  --from-literal=type=git \
  --from-literal=url="$GIT_REPO_URL" \
  --from-literal=username="$GITHUB_USER" \
  --from-literal=password="$GITHUB_TOKEN" \
  --dry-run=client -o yaml | k apply -f - >/dev/null
k -n argocd label secret gitops-repo argocd.argoproj.io/secret-type=repository --overwrite >/dev/null

log "Creating Argo CD Applications"
# create, not apply: after the first promotion Kargo owns each app's targetRevision.
render argocd/applications-kustomize.yaml | k create -f - 2>&1 | grep -v -e AlreadyExists -e created || true
# The apps read env/kz-<stage> branches that only exist after a first promotion,
# so they turn Healthy during the baseline rollout below.

# ---------------------------------------------------------------- 6. Kargo pipelines
log "Creating Kargo projects, credentials, and pipelines"
k apply -f kargo/common/analysis-template.yaml >/dev/null
setup_project() { # <project> <dir under kargo/>
  local project=$1 dir=$2
  k apply -f "kargo/$dir/project.yaml" >/dev/null
  wait_for "project namespace $project" 60 k get namespace "$project"
  k -n "$project" create secret generic github-creds \
    --from-literal=repoURL="$GIT_REPO_URL" \
    --from-literal=username="$GITHUB_USER" \
    --from-literal=password="$GITHUB_TOKEN" \
    --dry-run=client -o yaml | k apply -f - >/dev/null
  k -n "$project" label secret github-creds kargo.akuity.io/cred-type=git --overwrite >/dev/null
  k apply -f "kargo/$dir/promotion-task.yaml" >/dev/null
  render "kargo/$dir/warehouse.yaml" "kargo/$dir/stages.yaml" | k apply -f - >/dev/null
  k -n "$project" annotate warehouse podinfo kargo.akuity.io/refresh="$(date +%s)" --overwrite >/dev/null
}
setup_project kargo-kustomize kustomize

# Promote the baseline Freight through every Stage of a project, in order.
# First run only: a Stage that already has Freight is never touched (no downgrades on re-runs).
baseline_rollout() { # <project>
  PROJECT=$1
  wait_for "[$PROJECT] Freight for podinfo $BASELINE_TAG discovered" 180 bash -c \
    "KARGO_PROJECT=$PROJECT; . '$ROOT/scripts/lib.sh'; [[ -n \$(freight_for_tag $BASELINE_TAG) ]]"
  local freight; freight=$(freight_for_tag "$BASELINE_TAG")
  # The first deploy into a brand-new namespace can fail verification only
  # because Prometheus hasn't discovered the new target yet (empty results).
  # So if a baseline verification fails, re-verify that Stage once.
  verified() { # <stage>
    local id
    wait_for "[$PROJECT] baseline verification finished in $1" 600 bash -c "
      KARGO_PROJECT=$PROJECT; . '$ROOT/scripts/lib.sh'
      freight_verified_in $freight $1 || k -n $PROJECT get stage $1 -o json |
        jq -e '.status.freightHistory[0].verificationHistory[0].phase | IN(\"Failed\", \"Error\")'"
    freight_verified_in "$freight" "$1" >/dev/null && { ok "[$PROJECT] baseline verified in $1"; return; }
    id=$(k -n "$PROJECT" get stage "$1" -o json | jq -r '.status.freightHistory[0].verificationHistory[0].id')
    warn "[$PROJECT] $1: first verification failed (new namespace, metrics not scraped yet?); re-verifying once"
    k -n "$PROJECT" annotate stage "$1" kargo.akuity.io/reverify="$id" --overwrite >/dev/null
    sleep 10
    wait_for "[$PROJECT] baseline verified in $1 (retry)" 600 freight_verified_in "$freight" "$1"
  }
  promote_baseline() {
    if [[ "$(stage_tag "$1")" == "-" ]]; then
      KARGO_PROJECT=$PROJECT "$ROOT/scripts/promote.sh" "$1" "$freight" >/dev/null
    fi
  }
  promote_baseline dev
  verified dev
  promote_baseline staging
  verified staging
  promote_baseline prod-eu
  promote_baseline prod-us
  verified prod-eu
  verified prod-us
}
log "Promoting the baseline through the pipeline (each Stage verifies)"
baseline_rollout kargo-kustomize

# ---------------------------------------------------------------- done
cat <<EOF

$(printf '\033[1;32m')Demo is ready.$(printf '\033[0m')

$("$ROOT/scripts/status.sh")

  Argo CD     http://localhost:8080   admin / $(k -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
  Kargo       http://localhost:8081   admin / (make passwords, stored in .secrets/kargo-admin-password)
  Prometheus  http://localhost:9090
  Git repo    ${GIT_REPO_URL%.git}

  kubectl:    export KUBECONFIG=$KUBECONFIG
  Next:       make preflight, then follow docs/DEMO.md
EOF
