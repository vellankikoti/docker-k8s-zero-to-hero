#!/usr/bin/env bash
# verify.sh [PHASE]: did you really do it? ✔ or ✖ for each check of a phase (or all of them).
#   ./scripts/verify.sh       everything
#   ./scripts/verify.sh 4     only phase 4
want=${1:-all}; fails=0
ok()  { printf '  \033[1;32m✔\033[0m %s\n' "$*"; }
bad() { printf '  \033[1;31m✖\033[0m %s\n      hint: %s\n' "$1" "$2"; fails=$((fails+1)); }
phase() { [ "$want" = all ] || [ "$want" = "$1" ]; }
prom() { curl -sG localhost:9090/api/v1/query --data-urlencode "query=$1"; }

if phase 1; then echo "Phase 1: the platform is up"
  up=$(prom 'count(up == 1)' | grep -o '"value":\[[^]]*\]' | grep -o '"[0-9]*"\]' | tr -d '"]')
  [ "${up:-0}" -ge 5 ] && ok "Prometheus is scraping $up healthy targets" || bad "only ${up:-0} healthy targets (want 5)" "docker compose ps ; open http://localhost:9090/targets"
  curl -sf localhost:3000/api/health >/dev/null && ok "Grafana answers on :3000" || bad "Grafana is not answering" "docker compose logs grafana | tail"
fi
if phase 2; then echo "Phase 2: METRICS flow"
  prom 'orders_total' | grep -q '"item"' && ok "business metric orders_total has data" || bad "no orders_total" "is the loadgen running?  docker compose up -d loadgen"
  prom 'sli:order_errors:ratio_rate5m' | grep -q '"value"' && ok "the SLI recording rule produces data" || bad "recording rule is empty" "wait 30 seconds, then: docker compose logs prometheus | tail"
fi
if phase 3; then echo "Phase 3: LOGS flow"
  curl -sG localhost:3100/loki/api/v1/query_range --data-urlencode 'query={service=~"chai-.*"} | json' --data-urlencode 'limit=1' | grep -q '"values"' \
    && ok "Loki holds the app's JSON logs" || bad "no logs in Loki" "docker compose logs alloy | tail ; the app containers need the label logging=true"
fi
if phase 4; then echo "Phase 4: TRACES flow"
  curl -s localhost:16686/api/services | grep -q chai-stall && ok "Jaeger knows the service chai-stall" || bad "Jaeger has no traces" "docker compose logs chai-1 | head ; check OTEL_EXPORTER_OTLP_ENDPOINT"
fi
if phase 5; then echo "Phase 5: DASHBOARD as code"
  curl -s -u admin:z2h-grafana "localhost:3000/api/search?query=Chai" | grep -q 'chai-stall' && ok "dashboard 'Chai Stall: Service Overview' was provisioned from a file" || bad "dashboard missing" "docker compose restart grafana"
fi
if phase 6; then echo "Phase 6: INCIDENT happened and you were told"
  m=$(curl -s localhost:8025/api/v1/messages)
  echo "$m" | grep -q 'FIRING' && ok "an alert email with [FIRING] reached the inbox" || bad "no [FIRING] email yet" "break something: curl -X POST 'localhost:8091/chaos?error_rate=0.5' (and 8092), wait ~90 s"
  echo "$m" | grep -q 'RESOLVED' && ok "and a [RESOLVED] email followed" || bad "no [RESOLVED] email yet" "heal it: curl -X POST localhost:8091/chaos/reset (and 8092), wait ~2-3 minutes"
fi
echo; [ $fails -eq 0 ] && echo "All checks for '$want' passed." || echo "$fails check(s) need attention."
exit $([ $fails -eq 0 ] && echo 0 || echo 1)
