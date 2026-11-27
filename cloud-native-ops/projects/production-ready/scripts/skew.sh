#!/usr/bin/env bash
# skew.sh [NS]: do ALL the Pods of an app run the SAME version? One Pod on an old version is how a company lost
# about $440 million in 45 minutes (docs/case-files.md). Exit 1 if two versions run side by side for good.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
NS=${1:-$PROD_NS}; need_cluster
imgs=$(kubectl -n "$NS" get pods -l app.kubernetes.io/name=chai-stall -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}')
[ -n "$imgs" ] || { warn "no Chai Stall Pods in $NS"; exit 0; }
echo "$imgs" | awk -F'\t' '{printf "  %-45s %s\n", $1, $2}'
n=$(echo "$imgs" | cut -f2 | sort -u | wc -l)
if [ "$n" -gt 1 ]; then printf '\033[1;31m✖ %d different versions are running in %s at the same time.\033[0m A rollout in progress is fine; one that stays like this is not.\n' "$n" "$NS"; exit 1; fi
ok "every Pod in $NS runs the same image"
