# Helpers shared by the See Everything scripts. Source it:  . "$(dirname "$0")/lib.sh"
# Everything talks to the cluster through the API server's service proxy, so no port-forward needs to be running.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/../../scripts/k8s-lib.sh"

DEMO_NS=${DEMO_NS:-stall-demo}
RELEASE=${RELEASE:-chai-stall}
CHART="$COURSE_ROOT/cicd-observability/k8s/chart/chai-stall"
IMAGE_TAG=${IMAGE_TAG:-$CHAI_IMAGE_TAG}
PROM_SVC="/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:9090/proxy"
AM_SVC="/api/v1/namespaces/monitoring/services/kube-prometheus-stack-alertmanager:9093/proxy"
LOKI_SVC="/api/v1/namespaces/observability/services/loki:3100/proxy"
JAEGER_SVC="/api/v1/namespaces/observability/services/jaeger:16686/proxy"
MAIL_SVC="/api/v1/namespaces/mail/services/mailpit:8025/proxy"
GRAFANA_PW=${GRAFANA_PW:-z2h-grafana}

api() { kubectl get --raw "$1" 2>/dev/null; }                       # api /path  → body, or nothing on failure
urlenc() { python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1"; }
# prom_value 'promql' → the first number of the answer (empty if no data)
prom_value() { api "$PROM_SVC/api/v1/query?query=$(urlenc "$1")" | sed -n 's/.*"value":\[[0-9.]*,"\([^"]*\)"\].*/\1/p' | head -1; }
# prom_alert NAME STATE → success if an alert with that name is in that state (firing | pending)
prom_alert() { api "$PROM_SVC/api/v1/alerts" | grep -o "\"alertname\":\"$1\"[^}]*}[^]]*\"state\":\"$2\"" >/dev/null; }
mail_count() { api "$MAIL_SVC/api/v1/messages" | sed -n 's/.*"messages_count":\([0-9]*\).*/\1/p' | head -1; }
mail_has() { api "$MAIL_SVC/api/v1/messages?limit=50" | grep -q "$1"; }
# Grafana needs a login, which the API server's service proxy cannot send, and the Grafana image has no wget/curl to run inside.
# So: open ONE short-lived port-forward on a free local port (kubectl picks it) and call it with curl.
GF_PF_PID=""; GF_PORT=""
grafana_open() {
  local log; log=$(mktemp)
  kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana :80 --address 127.0.0.1 >"$log" 2>&1 &
  GF_PF_PID=$!; GF_PORT=""
  for _ in $(seq 1 15); do
    GF_PORT=$(sed -n 's/^Forwarding from 127.0.0.1:\([0-9]*\) ->.*/\1/p' "$log" | head -1)
    [ -n "$GF_PORT" ] && return 0
    kill -0 "$GF_PF_PID" 2>/dev/null || break
    sleep 1
  done
  GF_PORT=""; return 1
}
grafana_ready() { { [ -n "$GF_PORT" ] && kill -0 "$GF_PF_PID" 2>/dev/null; } || grafana_open; }   # call from the main shell, never inside $( )
grafana_close() { [ -z "$GF_PF_PID" ] || kill "$GF_PF_PID" 2>/dev/null || true; }
grafana_get() {  # grafana_get /api/path   (after grafana_ready)
  curl -s -m 10 -u "admin:$GRAFANA_PW" "http://127.0.0.1:$GF_PORT$1"
}

# release_app [extra helm args]  → (re)install the demo Chai Stall exactly as values-app.yaml says. Used by up.sh and the game day.
release_app() {
  helm upgrade --install "$RELEASE" "$CHART" -n "$DEMO_NS" -f "$HERE/values-app.yaml" \
    --set image.tag="$IMAGE_TAG" "$@" >/dev/null
}
