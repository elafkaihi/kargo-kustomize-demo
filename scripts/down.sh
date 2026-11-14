#!/usr/bin/env bash
# Delete the k3d cluster. The GitHub repo and .secrets/ are kept.
. "$(dirname "$0")/lib.sh"

if k3d cluster list -o json | jq -e --arg c "$CLUSTER" '.[] | select(.name == $c)' >/dev/null; then
  k3d cluster delete "$CLUSTER"
fi
rm -f "$KUBECONFIG"
ok "cluster $CLUSTER removed"
