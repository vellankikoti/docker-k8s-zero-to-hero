#!/usr/bin/env bash
# canary-check.sh URL [REQUESTS=100] [MAX_ERROR_PERCENT=5]: send orders straight to ONE Service and measure its own error rate.
# Judging the canary on its own traffic (not the blended total) is what makes a small canary detectable.
url=${1:?usage: canary-check.sh URL [REQUESTS] [MAX_PERCENT]}; n=${2:-100}; limit=${3:-5}
total=0; bad=0
for _ in $(seq 1 "$n"); do
  code=$(curl -s -o /dev/null -m 3 -w '%{http_code}' -X POST "$url/order?item=chai" || echo 000)
  total=$((total+1)); [ "$code" = 200 ] || bad=$((bad+1))
done
pct=$(( bad * 100 / total ))
echo "$url: $bad failed of $total requests = ${pct}% (limit ${limit}%)"
[ "$pct" -le "$limit" ]
