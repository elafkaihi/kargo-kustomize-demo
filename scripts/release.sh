#!/usr/bin/env bash
# Publish a podinfo release to the demo registry: copies the upstream image tag.
# The Warehouse picks it up within ~1 minute.
#   scripts/release.sh 6.16.0
. "$(dirname "$0")/lib.sh"

TAG=${1:?usage: release.sh <podinfo-tag>}
log "Releasing podinfo $TAG ($UPSTREAM_IMAGE:$TAG -> $PUSH_REGISTRY/podinfo:$TAG)"
docker pull -q "$UPSTREAM_IMAGE:$TAG" >/dev/null
docker tag "$UPSTREAM_IMAGE:$TAG" "$PUSH_REGISTRY/podinfo:$TAG"
docker push -q "$PUSH_REGISTRY/podinfo:$TAG" >/dev/null
ok "pushed $CLUSTER_IMAGE:$TAG"
