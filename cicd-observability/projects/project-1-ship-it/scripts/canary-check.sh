#!/usr/bin/env bash
# canary-check.sh [REQUESTS=200] [MAX_ERROR_PERCENT=5]: automated canary analysis.
# Sends orders through the router, then compares the error rate of the canary slot to the limit.
# Exit 0 = the canary is healthy, 1 = bad (the pipeline then rolls back).
n=${1:-200}; limit=${2:-5}; url=${ROUTER_URL:-http://localhost:8090}
eval "$("$(dirname "$0")/../deploy/deploy.sh" state)"
[ -n "${OTHER:-}" ] && [ "${WEIGHT:-0}" -gt 0 ] || { echo "no canary is running"; exit 0; }
canary="chai-$OTHER"; total=0; bad=0
for _ in $(seq 1 "$n"); do
  out=$(curl -s -o /dev/null -D- -m 3 -X POST "$url/order" | tr -d '\r')
  slot=$(echo "$out" | awk '/^X-Slot/{print $2}'); code=$(echo "$out" | awk '/^HTTP/{print $2}')
  [ "$slot" = "$canary" ] || continue
  total=$((total+1)); [ "$code" = 200 ] || bad=$((bad+1))
done
[ "$total" -gt 0 ] || { echo "the canary received no traffic"; exit 1; }
pct=$(( bad * 100 / total ))
echo "canary $canary: $bad failed of $total requests = ${pct}% (limit ${limit}%)"
[ "$pct" -le "$limit" ]
