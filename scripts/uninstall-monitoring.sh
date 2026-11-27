#!/usr/bin/env bash
# Remove Prometheus + Grafana (installed by install-monitoring.sh), including the CRDs the chart adds. Never hangs.
#
# Why it used to hang: the Prometheus operator puts a "finalizer" on its Prometheus and Alertmanager objects, meaning
# "do not delete me until I have cleaned up". Once the operator is uninstalled nobody can clean up, so deleting the CRDs
# waited forever. The order here is: ask the operator to clean up FIRST (while it still runs), then remove it, and as a last
# resort clear the finalizers ourselves (safe: the thing that would have used them is gone).
set -u
command -v helm >/dev/null 2>&1 || { echo "helm isn't installed, so nothing was installed with it." >&2; exit 0; }
say() { printf '▶ %s\n' "$*"; }
CRS="prometheuses.monitoring.coreos.com,alertmanagers.monitoring.coreos.com,thanosrulers.monitoring.coreos.com,prometheusagents.monitoring.coreos.com"

say "Asking the operator to clean up its Prometheus and Alertmanager (up to 60 s)"
kubectl delete "$CRS" --all -A --ignore-not-found --wait=false >/dev/null 2>&1
for _ in $(seq 1 12); do
  [ -z "$(kubectl get "$CRS" -A -o name 2>/dev/null)" ] && break
  sleep 5
done

say "Removing the Helm release"
helm uninstall kube-prometheus-stack -n monitoring >/dev/null 2>&1 && echo "✔ release removed" || echo "(no release found)"

left=$(kubectl get "$CRS" -A -o jsonpath='{range .items[*]}{.kind}{" "}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null)
if [ -n "$left" ]; then
  say "The operator is gone but some objects still wait for it: clearing their finalizers"
  echo "$left" | while read -r kind ns name; do
    kubectl -n "$ns" patch "$kind.monitoring.coreos.com" "$name" --type=merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
  done
fi

say "Removing the namespace and the CRDs the chart added (Helm never deletes CRDs)"
kubectl delete namespace monitoring --ignore-not-found --wait=false >/dev/null 2>&1
for crd in $(kubectl get crd -o name 2>/dev/null | grep 'monitoring.coreos.com'); do kubectl delete "$crd" --wait=false >/dev/null 2>&1 || true; done
for _ in $(seq 1 12); do
  kubectl get crd -o name 2>/dev/null | grep -q 'monitoring.coreos.com' || break
  sleep 5
done
if kubectl get crd -o name 2>/dev/null | grep -q 'monitoring.coreos.com'; then
  echo "• some CRDs are still terminating: $(kubectl get crd -o name | grep monitoring.coreos.com | sed 's#.*/##' | tr '\n' ' ')"
  echo "  If the cluster's kube-controller-manager is crash-looping, namespaces cannot finish either. Check: kubectl -n kube-system get pods"
else
  echo "✔ monitoring removed (metrics-server is left in place)"
fi
