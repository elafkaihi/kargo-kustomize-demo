#!/usr/bin/env bash
# Promote Freight to a Stage (the CLI twin of the "Promote" button).
# FREIGHT may be a Freight name, its alias, or an image tag; default: the newest Freight.
#   scripts/promote.sh dev
#   scripts/promote.sh prod-eu 6.16.0
. "$(dirname "$0")/lib.sh"

STAGE=${1:?usage: promote.sh <stage> [freight-name|alias|image-tag]}
FREIGHT=$(resolve_freight "${2:-}")
[[ -n "$FREIGHT" ]] || die "no Freight matching '${2:-newest}' (has the Warehouse seen it yet?)"

k create -f - <<EOF
apiVersion: kargo.akuity.io/v1alpha1
kind: Promotion
metadata:
  generateName: $STAGE-
  namespace: $PROJECT
spec:
  stage: $STAGE
  freight: $FREIGHT
EOF
