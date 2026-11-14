#!/usr/bin/env bash
# Publish a podinfo Helm chart version to the demo chart repo (copied from upstream).
# The Warehouse picks it up within ~1 minute and creates new Freight.
#   scripts/release-chart.sh 6.17.0
. "$(dirname "$0")/lib.sh"

VERSION=${1:?usage: release-chart.sh <chart-version>}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
log "Releasing podinfo chart $VERSION ($UPSTREAM_CHART_REPO -> http://$PUSH_CHARTS)"
helm pull podinfo --repo "$UPSTREAM_CHART_REPO" --version "$VERSION" -d "$tmp" >/dev/null
# 409 = already uploaded: fine, the script is idempotent.
code=$(curl -s -o "$tmp/resp" -w '%{http_code}' --data-binary "@$tmp/podinfo-$VERSION.tgz" "http://$PUSH_CHARTS/api/charts")
[[ $code == 201 || $code == 409 ]] || die "chart upload failed ($code): $(cat "$tmp/resp")"
ok "chart podinfo $VERSION available at http://10.43.200.201:8080"
