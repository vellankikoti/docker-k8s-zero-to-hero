#!/usr/bin/env bash
# cleanup.sh [-y] [--keep-environments]: remove everything production-ready created. Safe to run any time, any number of times.
#   --keep-environments   keep dev/prod (Terraform) and remove only the policies, ledger, night shift and drill leftovers
set -uo pipefail
. "$(dirname "$0")/lib.sh"
YES=0; KEEP=0
for a in "$@"; do case "$a" in -y) YES=1 ;; --keep-environments) KEEP=1 ;; *) die "unknown option: $a" ;; esac; done
kubectl get --raw /readyz >/dev/null 2>&1 || { warn "Can't reach the cluster: nothing to clean up."; exit 0; }
if [ "$YES" = 0 ]; then printf 'This removes the policies, the ledger, the night shift%s. Continue? [y/N] ' "$([ "$KEEP" = 0 ] && echo ', AND the dev and prod environments')"; read -r a; [ "$a" = y ] || [ "$a" = Y ] || exit 0; fi

say "Drill leftovers"
kubectl -n "$PROD_NS" delete job rush --ignore-not-found >/dev/null 2>&1 || true
kubectl -n "$PROD_NS" delete pod rogue --ignore-not-found --wait=false >/dev/null 2>&1 || true
say "Night shift"
for ns in iac-dev iac-staging iac-prod; do kubectl -n "$ns" delete rolebinding night-shift --ignore-not-found >/dev/null 2>&1 || true; done
kubectl delete clusterrolebinding z2h-night-shift-find --ignore-not-found >/dev/null 2>&1 || true
kubectl delete clusterrole z2h-night-shift-find z2h-night-shift-scale --ignore-not-found >/dev/null 2>&1 || true
say "Admission policies (done first: they must not block the removal below)"
for p in z2h-image-needs-a-version z2h-containers-need-resources z2h-workloads-need-owner-labels z2h-prod-never-scaled-to-zero z2h-prod-never-scaled-to-zero-scale; do
  kubectl delete validatingadmissionpolicybinding "$p" --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete validatingadmissionpolicy "$p" --ignore-not-found >/dev/null 2>&1 || true
done
say "The ledger and the night shift's namespace"
kubectl delete ns chai-ledger chai-ops --ignore-not-found --wait=false >/dev/null 2>&1 || true
if [ "$KEEP" = 0 ]; then
  say "The environments (through Terraform) and the state store"
  "$INFRA/scripts/cleanup.sh" -y || true
fi
say "Waiting for the namespaces to finish disappearing (up to 2 minutes)"
for _ in $(seq 1 24); do
  left=$(kubectl get ns chai-ledger chai-ops $([ "$KEEP" = 0 ] && echo "iac-dev iac-staging iac-prod tfstate") -o name 2>/dev/null | tr '\n' ' ')
  [ -z "$left" ] && break; sleep 5
done
[ -z "${left:-}" ] && ok "Clean: production-ready is gone." || warn "still terminating: $left (it finishes by itself; check: kubectl get ns)"
