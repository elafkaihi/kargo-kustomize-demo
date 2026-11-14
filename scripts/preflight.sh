#!/usr/bin/env bash
# Run before going on stage. Exits non-zero if anything the demo depends on is unhealthy.
. "$(dirname "$0")/lib.sh"
set +e
FAILED=0
check() { # <description> <command...>
  local what=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$what"; else warn "$what"; FAILED=1; fi
}

# Argo CD app = namespace, for every Stage.
APPS=()
for s in "${STAGES[@]}"; do APPS+=("$(app_of "$s")"); done

log "Cluster"
check "k3d context $CTX reachable" k get --raw /readyz
for ns in registry chartmuseum cert-manager monitoring argo-rollouts argocd kargo "${APPS[@]}"; do
  check "pods Ready in $ns" bash -c "
    kubectl --context $CTX -n $ns get pods -o json | jq -e '
      [.items[] | select(.status.phase != \"Succeeded\")] as \$p |
      (\$p | length > 0) and all(\$p[]; any(.status.conditions[]?; .type == \"Ready\" and .status == \"True\"))'"
done

log "Endpoints"
check "Argo CD UI  http://localhost:8080" curl -fsS -o /dev/null http://localhost:8080
check "Kargo UI    http://localhost:8081" curl -fsS -o /dev/null http://localhost:8081
check "Prometheus  http://localhost:9090" curl -fsS -o /dev/null http://localhost:9090/-/ready
check "Registry    http://localhost:5000" curl -fsS -o /dev/null http://localhost:5000/v2/
check "Chart repo  http://localhost:5001" curl -fsS -o /dev/null http://localhost:5001/health

log "Argo CD"
for a in "${APPS[@]}"; do
  check "$a Synced/Healthy" bash -c \
    "kubectl --context $CTX -n argocd get application $a -o jsonpath='{.status.sync.status}/{.status.health.status}' | grep -qx Synced/Healthy"
done

log "Kargo"
check "Warehouse podinfo Ready" k -n "$PROJECT" wait --for=condition=Ready warehouse/podinfo --timeout=5s
for s in "${STAGES[@]}"; do
  check "Stage $s Ready" k -n "$PROJECT" wait --for=condition=Ready "stage/$s" --timeout=5s
done
check "Git credentials secret present" k -n "$PROJECT" get secret github-creds

log "Prometheus"
for s in "${APPS[@]}"; do
  check "podinfo target up in $s" bash -c \
    "curl -fsS --get http://localhost:9090/api/v1/query --data-urlencode 'query=min(up{namespace=\"$s\",service=\"podinfo\"})' | jq -e '.data.result[0].value[1] == \"1\"'"
  check "traffic flowing in $s (req/s > 0)" bash -c \
    "curl -fsS --get http://localhost:9090/api/v1/query --data-urlencode 'query=sum(rate(http_request_duration_seconds_count{namespace=\"$s\",path!~\".*(healthz|readyz|metrics).*\"}[1m]))' | jq -e '(.data.result[0].value[1] | tonumber) > 0'"
done
check "kube-state-metrics data (needed by verification)" bash -c \
  "curl -fsS --get http://localhost:9090/api/v1/query --data-urlencode 'query=count(kube_pod_container_info{container=\"podinfo\"})' | jq -e '(.data.result[0].value[1] | tonumber) > 0'"

echo
"$ROOT/scripts/status.sh"
echo
if (( FAILED )); then die "preflight found problems (see !! lines above)"; fi
ok "all green, ready to demo"
