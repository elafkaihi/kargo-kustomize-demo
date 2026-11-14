#!/usr/bin/env bash
# Recover from demo/break.sh by shipping a newer, good release ("roll forward").
# Promote the new Freight to dev, then staging: both verify green.
#   demo/fix.sh [good-tag]                         (default: 6.17.0)
. "$(dirname "$0")/../scripts/lib.sh"

"$ROOT/scripts/release.sh" "${1:-6.17.0}"
