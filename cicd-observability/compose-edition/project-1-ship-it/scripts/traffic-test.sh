#!/usr/bin/env bash
# traffic-test.sh URL [SECONDS=20]: send ~10 requests/second to URL/api/info and report what happened.
# Use it while you deploy, to SEE whether users noticed: failed requests and which versions answered.
#   ./scripts/traffic-test.sh http://localhost:8090 30
#   ./scripts/traffic-test.sh http://localhost:8090/roll 30
url=${1:?usage: traffic-test.sh URL [SECONDS]}; secs=${2:-20}
ok=0; fail=0; tmp=$(mktemp); end=$((SECONDS + secs))
echo "sending requests to $url/api/info for ${secs}s ..."
while [ $SECONDS -lt $end ]; do
  body=$(curl -s -m 2 -w '\n%{http_code}' "$url/api/info" 2>/dev/null || true)
  code=$(echo "$body" | tail -1)
  if [ "$code" = 200 ]; then
    ok=$((ok+1)); echo "$body" | grep -o '"version": "[^"]*"' >> "$tmp"; printf '.'
  else
    fail=$((fail+1)); printf 'x'
  fi
  sleep 0.1
done
echo
echo "ok=$ok failed=$fail"
echo "versions that answered:"; sort "$tmp" | uniq -c | sed 's/"version": //'
rm -f "$tmp"
[ "$fail" -eq 0 ]
