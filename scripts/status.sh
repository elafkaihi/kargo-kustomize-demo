#!/usr/bin/env bash
# One-screen view of the pipeline: what each Stage runs and how verification went.
. "$(dirname "$0")/lib.sh"

# "alias  image  chart  config-commit" for a Freight-like JSON object.
SUMMARY='"\(.alias // "-")\t\(.images[0].tag // "-")\t\(.charts[0].version // "-")\t\((.commits[0].id // "-")[0:7])"'

show_project() {
  printf '%-18s %-24s %-7s %-7s %-8s %-20s %-12s %s\n' STAGE FREIGHT IMAGE CHART CONFIG STATE VERIFICATION ARGO-CD
  for s in "${STAGES[@]}"; do
    st=$(k -n "$PROJECT" get stage "$s" -o json)
    cur=$(jq -r '.status.freightHistory[0].items // {} | to_entries[0].value.name // ""' <<<"$st")
    if [[ -n $cur ]]; then
      IFS=$'\t' read -r alias img chart cfg < <(k -n "$PROJECT" get freight "$cur" -o json | jq -r "$SUMMARY")
    else
      alias=- img=- chart=- cfg=-
    fi
    state=$(jq -r '[.status.conditions[]? | select(.type=="Ready") | .reason][0] // "-"' <<<"$st")
    verif=$(jq -r '.status.freightHistory[0].verificationHistory[0].phase // "-"' <<<"$st")
    app=$(k -n argocd get application "$(app_of "$s")" -o jsonpath='{.status.sync.status}/{.status.health.status}')
    printf '%-18s %-24s %-7s %-7s %-8s %-20s %-12s %s\n' "$s" "$alias" "$img" "$chart" "$cfg" "$state" "$verif" "$app"
  done
  echo
  echo "Freight (newest first):"
  printf '  %-24s %-7s %-7s %-8s %s\n' ALIAS IMAGE CHART CONFIG "VERIFIED IN"
  all_freight | jq -r ".[] | $SUMMARY + \"\t\" + ((.status.verifiedIn // {}) | keys | join(\", \") | if . == \"\" then \"-\" else . end)" |
    while IFS=$'\t' read -r alias img chart cfg verified; do
      printf '  %-24s %-7s %-7s %-8s %s\n' "$alias" "$img" "$chart" "$cfg" "$verified"
    done
}

show_project
