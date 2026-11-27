#!/usr/bin/env bash
# night-shift.sh ACTION: close dev and staging at night, open them in the morning (cost optimisation by automation).
#   enable      install the two CronJobs and give them the right to scale in dev and staging ONLY
#   disable     remove the CronJobs and the permissions
#   run-down    do tonight's shutdown NOW (to see it work)       run-up   do tomorrow morning's start NOW
#   status      what is scheduled, and what the Deployments are doing
set -euo pipefail
. "$(dirname "$0")/lib.sh"
need_cluster
targets() { kubectl get ns -l 'z2h/env in (dev,staging)' -o jsonpath='{.items[*].metadata.name}'; }
case "${1:-}" in
  enable)
    out=$(kubectl apply -f "$HERE/manifests/20-night-shift.yaml" 2>&1) || die "kubectl apply failed: $out"
    for ns in $(targets); do kubectl -n "$ns" create rolebinding night-shift --clusterrole=z2h-night-shift-scale --serviceaccount=chai-ops:night-shift --dry-run=client -o yaml | kubectl apply -f - >/dev/null; done
    ok "night shift is on for: $(targets | tr ' ' ', ')  (22:00 down, 07:00 up, India time)" ;;
  disable)
    kubectl delete cronjob night-shift-down night-shift-up -n chai-ops --ignore-not-found >/dev/null
    for ns in $(targets); do kubectl -n "$ns" delete rolebinding night-shift --ignore-not-found >/dev/null; done
    ok "night shift is off (the CronJobs and their permissions are gone)" ;;
  run-down|run-up)
    which=${1#run-}; kubectl -n chai-ops delete job "night-shift-$which-now" --ignore-not-found >/dev/null
    kubectl -n chai-ops create job "night-shift-$which-now" --from="cronjob/night-shift-$which" >/dev/null
    kubectl -n chai-ops wait --for=condition=complete "job/night-shift-$which-now" --timeout=120s >/dev/null 2>&1 \
      || { kubectl -n chai-ops logs "job/night-shift-$which-now" --tail=20 >&2 || true; die "night-shift-$which failed (log above)"; }
    ok "night-shift-$which finished"; kubectl -n chai-ops delete job "night-shift-$which-now" --wait=false >/dev/null
    for ns in $(targets); do kubectl -n "$ns" get deploy -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,REPLICAS:.spec.replicas,REMEMBERED:.metadata.annotations.z2h/replicas-before-night"; done ;;
  status)
    kubectl -n chai-ops get cronjob 2>/dev/null || echo "night shift is not installed (night-shift.sh enable)"
    for ns in $(targets); do kubectl -n "$ns" get deploy -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,REPLICAS:.spec.replicas,REMEMBERED:.metadata.annotations.z2h/replicas-before-night"; done ;;
  *) sed -n '2,8p' "$0"; exit 1 ;;
esac
