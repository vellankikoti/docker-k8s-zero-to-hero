#!/usr/bin/env bash
# up.sh: install everything the See Everything project needs on the cluster your kubectl points at. Safe to run again.
#
#   ./cicd-observability/projects/see-everything/scripts/up.sh
#
# What you get (about 8 minutes the first time, 2.5 GB of free memory):
#   the Chai Stall (2 Pods, namespace stall-demo) + a little customer that orders all day
#   Prometheus + Alertmanager + Grafana (+ kube-state-metrics)        namespace monitoring   (the K19 stack)
#   Loki (logs) + Alloy (log shipper) + Jaeger (traces)                namespace observability
#   Mailpit: the inbox where Alertmanager's emails land                namespace mail
# It ends by running verify.sh, so you know it WORKS, not just that it was applied.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
need_cluster; need_helm
cluster_healthy

say "1/7 Image registry and mail catcher (the light version of the CI/CD platform)"
if ! kubectl -n cicd get deploy registry >/dev/null 2>&1; then "$COURSE_ROOT/cicd-observability/scripts/k8s-up.sh" --lite
else ok "registry already there"; fi

say "2/7 The Chai Stall image, built inside the cluster (skipped when it is already in the registry)"
"$COURSE_ROOT/cicd-observability/scripts/ensure-image.sh" "$IMAGE_TAG"

say "3/7 Prometheus, Alertmanager and Grafana (Helm chart kube-prometheus-stack; 3 to 6 minutes the first time)"
MONITORING_EXTRA_VALUES="$HERE/values-monitoring.yaml" "$COURSE_ROOT/scripts/install-monitoring.sh"

say "4/7 Namespaces, logs (Loki + Alloy) and traces (Jaeger)"
apply() { local out; out=$(kubectl apply "$@" 2>&1) || { echo "$out" >&2; die "kubectl apply failed: see above"; }; }
apply -f "$HERE/manifests/00-namespaces.yaml"
apply -f "$HERE/manifests/10-logs-and-traces.yaml"

say "5/7 Alert rules, Grafana datasources and the dashboard (all as code: files in this folder)"
apply -f "$HERE/manifests/20-rules.yaml" -f "$HERE/manifests/30-grafana-datasources.yaml"
kubectl -n monitoring create configmap chai-stall-dashboard --from-file=chai-stall.json="$HERE/dashboards/chai-stall.json" \
  --dry-run=client -o yaml | kubectl label --local -f - grafana_dashboard=1 -o yaml | kubectl apply -f - >/dev/null \
  || die "could not publish the dashboard"

say "6/7 The Chai Stall itself (Helm release $RELEASE in $DEMO_NS) and its customer"
release_app --wait --timeout 5m || die "the Chai Stall did not become Ready. Look: kubectl -n $DEMO_NS get pods ; kubectl -n $DEMO_NS describe pod -l app.kubernetes.io/name=chai-stall"
apply -f "$HERE/manifests/40-loadgen.yaml"

say "7/7 Checking that it all WORKS (verify.sh waits up to 6 minutes for the first numbers)"
"$HERE/scripts/verify.sh" --wait 360

cat <<MSG

  Open the doors (leaves port-forwards running in the background):
      ./cicd-observability/scripts/forward.sh start observability
  Then:  Grafana http://localhost:3000 (admin / z2h-grafana) → Dashboards → "Chai Stall: Service Overview"
         Jaeger  http://localhost:16686      Inbox  http://localhost:8025      Prometheus  http://localhost:9090
  Break something on purpose (the game day):   ./cicd-observability/projects/see-everything/scripts/gameday.sh list
  Remove everything again:                     ./cicd-observability/projects/see-everything/scripts/cleanup.sh
MSG
