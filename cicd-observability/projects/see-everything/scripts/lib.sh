# Helpers shared by the See Everything scripts. Source it:  . "$(dirname "$0")/lib.sh"
# Everything talks to the cluster through the API server's service proxy, so no port-forward needs to be running.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/../../scripts/k8s-lib.sh"

DEMO_NS=${DEMO_NS:-stall-demo}
RELEASE=${RELEASE:-chai-stall}
CHART="$COURSE_ROOT/cicd-observability/k8s/chart/chai-stall"
IMAGE_TAG=${IMAGE_TAG:-1.0.0}
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
grafana_get() {  # grafana_get /api/path  (runs inside the Grafana Pod, with the lab password)
  local auth; auth=$(printf 'admin:%s' "$GRAFANA_PW" | base64 | tr -d '\n')
  kubectl -n monitoring exec deploy/kube-prometheus-stack-grafana -c grafana -- wget -qO- --header="Authorization: Basic $auth" "http://localhost:3000$1" 2>/dev/null
}

# release_app [extra helm args]  → (re)install the demo Chai Stall exactly as values-app.yaml says. Used by up.sh and the game day.
release_app() {
  helm upgrade --install "$RELEASE" "$CHART" -n "$DEMO_NS" -f "$HERE/values-app.yaml" \
    --set image.tag="$IMAGE_TAG" "$@" >/dev/null
}
