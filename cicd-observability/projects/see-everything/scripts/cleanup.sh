#!/usr/bin/env bash
# cleanup.sh [-y] [--keep-monitoring]: remove everything up.sh created. Safe to run any time, any number of times.
#
#   cleanup.sh                     removes the demo app, Loki/Jaeger/Alloy, the rules, the dashboard AND Prometheus/Grafana
#   cleanup.sh --keep-monitoring   keeps the kube-prometheus-stack (other labs use it); removes only what this project added
#   -y                             do not ask first
# Leaves alone: the image registry and the mail catcher (other projects use them; remove them with k8s-down.sh).
set -uo pipefail
. "$(dirname "$0")/lib.sh"
KEEP=0; YES=0
for a in "$@"; do case "$a" in -y) YES=1 ;; --keep-monitoring) KEEP=1 ;; *) die "unknown option: $a" ;; esac; done
kubectl get --raw /readyz >/dev/null 2>&1 || { warn "Can't reach the cluster: nothing to clean up."; exit 0; }
if [ "$YES" = 0 ]; then
  printf 'This removes the demo app, logs, traces, rules and dashboard%s. Continue? [y/N] ' "$([ "$KEEP" = 0 ] && echo ", AND Prometheus/Grafana")"
  read -r a; [ "$a" = y ] || [ "$a" = Y ] || exit 0
fi
"$COURSE_ROOT/cicd-observability/scripts/forward.sh" stop >/dev/null 2>&1 || true

say "Removing the demo app and what we added to the monitoring stack"
helm uninstall "$RELEASE" -n "$DEMO_NS" >/dev/null 2>&1 || true
kubectl delete prometheusrule chai-stall -n observability --ignore-not-found >/dev/null 2>&1 || true
kubectl -n monitoring delete cm chai-stall-dashboard see-everything-datasources --ignore-not-found >/dev/null 2>&1 || true
kubectl delete ns stall-demo observability --ignore-not-found --wait=false >/dev/null 2>&1 || true
kubectl delete clusterrole alloy-log-reader --ignore-not-found >/dev/null 2>&1 || true
kubectl delete clusterrolebinding alloy-log-reader --ignore-not-found >/dev/null 2>&1 || true

if [ "$KEEP" = 0 ]; then
  say "Removing Prometheus, Alertmanager and Grafana"
  "$COURSE_ROOT/scripts/uninstall-monitoring.sh" >/dev/null 2>&1 || true
fi

say "Waiting for the namespaces to finish disappearing (up to 2 minutes)"
for _ in $(seq 1 24); do
  kubectl get ns stall-demo observability >/dev/null 2>&1 || break
  sleep 5
done
left=$(kubectl get ns stall-demo observability -o name 2>/dev/null | tr '\n' ' ')
[ -z "$left" ] && ok "Clean: the See Everything project is gone." || warn "still terminating: $left (it finishes by itself; check: kubectl get ns)"
