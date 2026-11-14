# Shared settings for every script. Source it; don't run it.
# shellcheck shell=bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$ROOT/bin:$PATH"

# --- Pinned versions ---------------------------------------------------------
CERT_MANAGER_CHART=v1.21.2
KPS_CHART=92.16.2                  # kube-prometheus-stack
ARGO_ROLLOUTS_CHART=2.43.8         # Argo Rollouts v1.10.1
ARGOCD_CHART=10.11.6               # Argo CD v3.5.6
KARGO_CHART=1.12.5                 # Kargo v1.12.5

# --- Demo settings -------------------------------------------------------------
CLUSTER=kargo-demo
# One Kargo project deploys the app from gitops-kustomize/ (base + overlays).
PROJECT=kargo-kustomize
# Docker subnet for the k3d network. Default is a benchmarking range (RFC 2544)
# because corporate VPNs often route all of 10/8, 172.16/12 and 192.168/16,
# which makes the cluster unreachable from the host.
K3D_SUBNET="${K3D_SUBNET:-198.18.0.0/24}"
STAGES=(dev staging prod-eu prod-us)
# Argo CD app = namespace for a Stage.
app_of() { echo "kz-$1"; }
BASELINE_TAG=6.15.0                # image every environment runs after `make up`
BASELINE_CHART=6.15.0              # chart version every environment runs after `make up`
UPSTREAM_IMAGE="${IMAGE_SOURCE:-ghcr.io/stefanprodan/podinfo}"
PUSH_REGISTRY=localhost:5000       # host side of the in-cluster registry
CLUSTER_IMAGE=10.43.200.200:5000/podinfo
UPSTREAM_CHART_REPO=https://stefanprodan.github.io/podinfo
PUSH_CHARTS=localhost:5001         # host side of the in-cluster chart repo
CANONICAL_REPO_URL=https://github.com/elafkaihi/kargo-kustomize-demo.git

# --- Isolation: never touch the user's default kubeconfig/context ---------------
export KUBECONFIG="$ROOT/.kube/config"
CTX="k3d-$CLUSTER"
k() { kubectl --context "$CTX" "$@"; }
h() { helm --kube-context "$CTX" "$@"; }

# --- Local secrets (.env is gitignored) ----------------------------------------
if [[ -f "$ROOT/.env" ]]; then
  set -a; . "$ROOT/.env"; set +a
fi
GITHUB_USER="${GITHUB_USER:?set GITHUB_USER in .env (see .env.example)}"
REPO_NAME="${REPO_NAME:-kargo-kustomize-demo}"
GIT_REPO_URL="https://github.com/$GITHUB_USER/$REPO_NAME.git"
SECRETS_DIR="$ROOT/.secrets"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERR\033[0m %s\n' "$*" >&2; exit 1; }

# Replace the canonical repo URL in a manifest with this checkout's repo URL (forks).
render() { sed "s#$CANONICAL_REPO_URL#$GIT_REPO_URL#g" "$@"; }

# wait_for <description> <timeout-seconds> <command...>
wait_for() {
  local what=$1 timeout=$2; shift 2
  local start=$SECONDS
  until "$@" >/dev/null 2>&1; do
    (( SECONDS - start > timeout )) && die "timed out after ${timeout}s waiting for: $what"
    sleep 5
  done
  ok "$what"
}

# All Freight, newest first, as a JSON array.
all_freight() {
  k -n "$PROJECT" get freight -o json | jq '.items | sort_by(.metadata.creationTimestamp) | reverse'
}

# Resolve a Freight from its name, its alias, or an image tag (newest match);
# no argument means the newest Freight. Prints "" if nothing matches.
resolve_freight() {
  all_freight | jq -r --arg a "${1:-}" '
    if $a == "" then .[0].metadata.name
    else (map(select(.metadata.name == $a or .alias == $a)) + map(select(.images[0].tag == $a)))[0].metadata.name
    end // ""'
}

# Newest Freight carrying a given podinfo image tag ("" if none yet).
freight_for_tag() { resolve_freight "$1"; }

freight_verified_in() { # <freight> <stage>
  k -n "$PROJECT" get freight "$1" -o json | jq -e --arg s "$2" '.status.verifiedIn[$s] != null'
}

# Image tag of the Freight currently in a Stage ("-" if none).
stage_tag() {
  k -n "$PROJECT" get stage "$1" -o json |
    jq -r '.status.freightHistory[0].items // {} | to_entries[0].value.images[0].tag // "-"'
}
