#!/usr/bin/env bash
# verify.sh [--wait SECONDS]: does the See Everything stack WORK? One ✔ or ✖ per link in the chain. Changes nothing.
#
#   verify.sh              check now
#   verify.sh --wait 360   keep retrying each check for up to 6 minutes (first start-up needs a few minutes of data)
#
# Follows one customer order all the way: app → Prometheus → rules → Alertmanager → Grafana → Loki → Jaeger → inbox.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
need_cluster
trap grafana_close EXIT
WAIT=0; [ "${1:-}" = "--wait" ] && WAIT=${2:-300}
DEADLINE=$(( $(date +%s) + WAIT ))
fail=0
check() {  # check "label" "what to do if it fails" command...
  local label=$1 hint=$2; shift 2
  while ! "$@" >/dev/null 2>&1; do
    if [ "$(date +%s)" -ge "$DEADLINE" ]; then printf '  \033[1;31m✖\033[0m %s\n      → %s\n' "$label" "$hint"; fail=$((fail+1)); return; fi
    sleep 5
  done
  printf '  \033[1;32m✔\033[0m %s\n' "$label"
}
gt0() { local v; v=$("$@"); [ -n "$v" ] && awk -v v="$v" 'BEGIN{exit !(v>0)}'; }

app_ready()     { [ "$(kubectl -n "$DEMO_NS" get deploy "$RELEASE" -o jsonpath='{.status.readyReplicas}')" = "$(kubectl -n "$DEMO_NS" get deploy "$RELEASE" -o jsonpath='{.spec.replicas}')" ]; }
targets_up()    { [ "$(prom_value 'count(up{job="chai-stall"} == 1)')" = 2 ]; }
getting_data()  { gt0 prom_value 'sum(rate(http_requests_total{job="chai-stall"}[1m]))'; }
rules_loaded()  { api "$PROM_SVC/api/v1/rules" | grep -q 'OrderSLOFastBurn' && api "$PROM_SVC/api/v1/rules" | grep -q 'ChaiStallReplicasUnavailable'; }
sli_computed()  { [ -n "$(prom_value 'sli:order_errors:ratio_rate5m')" ]; }
am_has_email()  { api "$AM_SVC/api/v2/status" | grep -q 'oncall@z2h.local'; }
mailpit_up()    { api "$MAIL_SVC/api/v1/messages" | grep -q 'messages_count'; }
dashboard_in()  { grafana_ready && grafana_get "/api/search?query=Chai" | grep -q 'Service Overview'; }
datasources_in(){ local d; grafana_ready || return 1; d=$(grafana_get "/api/datasources"); echo "$d" | grep -q '"uid":"loki"' && echo "$d" | grep -q '"uid":"jaeger"' && echo "$d" | grep -q '"uid":"prometheus"'; }
loki_has_logs() { api "$LOKI_SVC/loki/api/v1/query_range?limit=1&query=$(urlenc '{service="chai-stall"}')&since=10m" | grep -q '"values":\[\['; }
jaeger_has()    { api "$JAEGER_SVC/api/services" | grep -q 'chai-stall'; }
dashboard_data(){ gt0 prom_value 'sum(rate(orders_total[1m]))'; }

echo "The app"
check "the Chai Stall is Ready ($DEMO_NS/$RELEASE)" "kubectl -n $DEMO_NS get pods ; kubectl -n $DEMO_NS describe pod -l app.kubernetes.io/name=chai-stall" app_ready
echo "Metrics"
check "Prometheus scrapes both Pods (ServiceMonitor works)" "kubectl -n monitoring get servicemonitor,pods ; the chart must be installed with serviceMonitor.enabled=true" targets_up
check "orders are flowing (the little customer is working)" "kubectl -n $DEMO_NS get pods -l app=loadgen ; kubectl -n $DEMO_NS logs deploy/loadgen" getting_data
check "the business metric orders_total has data" "the app exposes /metrics: kubectl -n $DEMO_NS port-forward svc/$RELEASE 8083:80 and open /metrics" dashboard_data
echo "Rules and alerts"
check "alert rules are loaded into Prometheus (PrometheusRule)" "kubectl -n observability get prometheusrule chai-stall -o yaml ; kubectl -n monitoring logs deploy/kube-prometheus-stack-operator | tail" rules_loaded
check "the SLI recording rule produces a number" "wait a minute for the first evaluation, or check the rule in Prometheus → Status → Rules" sli_computed
check "Alertmanager will email oncall@z2h.local" "kubectl -n monitoring get secret alertmanager-kube-prometheus-stack-alertmanager -o yaml | head" am_has_email
check "the Mailpit inbox answers" "kubectl -n mail get pods" mailpit_up
echo "Dashboards, logs, traces"
check "Grafana has the dashboard 'Chai Stall: Service Overview'" "kubectl -n monitoring get cm chai-stall-dashboard ; kubectl -n monitoring logs deploy/kube-prometheus-stack-grafana -c grafana-sc-dashboard | tail" dashboard_in
check "Grafana knows Prometheus, Loki and Jaeger" "kubectl -n monitoring get cm see-everything-datasources ; kubectl -n monitoring logs deploy/kube-prometheus-stack-grafana -c grafana-sc-datasources | tail" datasources_in
check "Loki has the Chai Stall's log lines (Alloy ships them)" "kubectl -n observability logs deploy/alloy | tail ; kubectl -n observability get pods" loki_has_logs
check "Jaeger has traces from the Chai Stall" "is the release using otlpEndpoint? helm get values $RELEASE -n $DEMO_NS ; kubectl -n observability logs deploy/jaeger | tail" jaeger_has

echo
if [ "$fail" -eq 0 ]; then ok "Everything works: you can see metrics, logs, traces, alerts and the inbox."; exit 0; fi
printf '\033[1;31m%d check(s) failed.\033[0m First look at: kubectl get pods -A | grep -vE "Running|Completed"\n' "$fail"; exit 1
