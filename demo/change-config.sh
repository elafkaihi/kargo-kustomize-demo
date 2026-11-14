#!/usr/bin/env bash
# Change the shared podinfo config and push it. The project's Warehouse sees
# the commit and creates new Freight carrying it.
#   demo/change-config.sh "Kustomize config v2"
. "$(dirname "$0")/../scripts/lib.sh"
cd "$ROOT"

MSG=${1:?usage: change-config.sh <ui message> [values file]}
FILE=${2:-gitops-kustomize/base/values.yaml}
[[ "$(yq '.ui.message' "$FILE")" != "$MSG" ]] || die "$FILE already says \"$MSG\": pick a new message"
yq -i ".ui.message = \"$MSG\"" "$FILE"
git add "$FILE"
git commit -q -m "config: ui.message = \"$MSG\" ($FILE)" -- "$FILE"
GIT_AUTH=(-c "http.https://github.com/.extraheader=AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 -w0)")
git "${GIT_AUTH[@]}" pull -q --rebase --autostash origin main
git "${GIT_AUTH[@]}" push -q origin main
ok "pushed $(git rev-parse --short HEAD): ui.message = \"$MSG\". New Freight appears within ~1 minute"
