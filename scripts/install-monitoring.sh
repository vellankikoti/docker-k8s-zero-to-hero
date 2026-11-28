#!/usr/bin/env bash
# Install Prometheus + Grafana (the kube-prometheus-stack Helm chart) in the namespace "monitoring".
# Lab K19 teaches it; several scenarios have an optional "See it in monitoring" tip that uses it. Safe to run again: it upgrades in place.
#
#   ./scripts/install-monitoring.sh
#
# Needs: kubectl, helm (3.8 or newer, or 4), a cluster with about 2 GB of free memory.
set -euo pipefail

CHART_VERSION="93.1.2"            # one place to change when you want a newer release
RELEASE="kube-prometheus-stack"
NS="monitoring"
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/progress.sh"
VALUES="$HERE/../kubernetes/19-observability/monitoring-values.yml"
# Optional: a second values file layered on top (the See Everything project adds Loki and Jaeger to Grafana this way).
EXTRA=()
[ -n "${MONITORING_EXTRA_VALUES:-}" ] && EXTRA=(-f "$MONITORING_EXTRA_VALUES")
# Small lab? Smaller requests/limits and shorter retention (set MONITORING_SMALL=1, or let a project's up.sh decide).
[ "${MONITORING_SMALL:-0}" = 1 ] && EXTRA+=(-f "$HERE/../kubernetes/19-observability/monitoring-values-small.yml")

say()  { printf '\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m✖ %s\033[0m\n' "$*"; exit 1; }

command -v kubectl >/dev/null 2>&1 || die "kubectl isn't installed. See 00-setup."
kubectl get --raw /readyz >/dev/null 2>&1 || die "Can't reach a cluster. Check: kubectl config current-context"
if ! command -v helm >/dev/null 2>&1; then
  die "helm isn't installed. macOS: brew install helm · Windows: winget install Helm.Helm · Linux: https://helm.sh/docs/intro/install/ . Then run this again."
fi

# The tour (K01) and the autoscaling lab use metrics-server too, so make sure it is there.
"$HERE/install-metrics-server.sh"

# Alertmanager sends its emails to a mail catcher (lab K20). Create it first so the address exists.
kubectl apply -f "$HERE/../kubernetes/20-projects/mailpit.yaml" >/dev/null

say "Adding the prometheus-community chart repository"
_i=0; until curl -fsS -m 30 -o /dev/null https://prometheus-community.github.io/helm-charts/index.yaml 2>/tmp/z2h-chart.err; do
  _i=$((_i+1)); [ "$_i" -lt 3 ] || die "cannot reach https://prometheus-community.github.io (the Prometheus chart). This lab blocks it or has no internet: $(tail -1 /tmp/z2h-chart.err). Try again in a minute, or use another lab/cluster."
  sleep 3
done

# Helm (client-go) prints harmless "watch ended ... http2: client connection lost" lines while it waits. They scare people and
# mean nothing, so keep helm's messages in a file and show them only if the install really fails.
HELM_LOG=$(mktemp); trap 'rm -f "$HELM_LOG"' EXIT
say "Installing kube-prometheus-stack ${CHART_VERSION} into namespace ${NS} (the first time takes a few minutes)"
helm upgrade --install "$RELEASE" kube-prometheus-stack --repo https://prometheus-community.github.io/helm-charts \
  --version "$CHART_VERSION" --namespace "$NS" --create-namespace \
  -f "$VALUES" ${EXTRA[@]+"${EXTRA[@]}"} --wait --timeout 10m >/dev/null 2>"$HELM_LOG" &
HELM_PID=$!
progress_while "$HELM_PID" "$NS" "Prometheus stack"
wait "$HELM_PID" \
  || { grep -v 'reflector.go' "$HELM_LOG" | tail -15 >&2; die "The install did not finish. Look: kubectl get pods -n ${NS}   and   helm status ${RELEASE} -n ${NS}"; }

PROM="/api/v1/namespaces/${NS}/services/${RELEASE}-prometheus:9090/proxy/api/v1/query?query=up"
say "Waiting for Prometheus to answer its first query"
for _ in $(seq 1 60); do
  if kubectl get --raw "$PROM" 2>/dev/null | grep -q '"status":"success"'; then
    ok "Prometheus and Grafana are running in namespace ${NS}."
    printf '   Grafana:    kubectl port-forward -n %s svc/%s-grafana 3000:80      then http://localhost:3000  (admin / z2h-grafana)\n' "$NS" "$RELEASE"
    printf '   Prometheus: kubectl port-forward -n %s svc/%s-prometheus 9090:9090  then http://localhost:9090\n' "$NS" "$RELEASE"
    exit 0
  fi
  sleep 3
done
die "Prometheus is installed but not answering yet. Wait a minute and run this again."
