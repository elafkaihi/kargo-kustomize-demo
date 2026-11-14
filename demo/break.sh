#!/usr/bin/env bash
# Publish a BAD podinfo release: same app, but every request returns HTTP 500.
# Promote the new Freight to dev: verification fails, and Kargo refuses to
# promote it any further.
#   demo/break.sh [bad-tag] [built-from-tag]      (default: 6.16.1 built from 6.16.0)
. "$(dirname "$0")/../scripts/lib.sh"

TAG=${1:-6.16.1}
BASE=${2:-6.16.0}
log "Building bad release $TAG (from $UPSTREAM_IMAGE:$BASE, fault injection always on)"
docker build -q --build-arg "BASE=$UPSTREAM_IMAGE:$BASE" -t "$PUSH_REGISTRY/podinfo:$TAG" "$ROOT/demo/bad-image" >/dev/null
docker push -q "$PUSH_REGISTRY/podinfo:$TAG" >/dev/null
ok "pushed $CLUSTER_IMAGE:$TAG. New Freight appears within ~1 minute; promote it to dev"
