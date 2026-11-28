#!/usr/bin/env bash
# verify.sh [--wait SECONDS] [--full]: is everything built, protected, backed up and measurable? Changes nothing
# (except --full, which also runs every drill from gameday.sh: it breaks things on purpose and puts them back).
set -uo pipefail
. "$(dirname "$0")/lib.sh"
need_cluster
WAIT=0; FULL=0
while [ $# -gt 0 ]; do case "$1" in --wait) WAIT=${2:-120}; shift 2 ;; --full) FULL=1; shift ;; *) die "unknown option: $1" ;; esac; done
DEADLINE=$(( $(date +%s) + WAIT )); fail=0; FAILED=""
chk() { local label=$1 hint=$2; shift 2
  while ! "$@" >/dev/null 2>&1; do
    if [ "$(date +%s)" -ge "$DEADLINE" ]; then printf '  \033[1;31m✖\033[0m %s\n      → %s\n' "$label" "$hint"; fail=$((fail+1)); FAILED="$FAILED\n   ✖ $label"; return; fi; sleep 5
  done; printf '  \033[1;32m✔\033[0m %s\n' "$label"; }
can_not() { [ "$(kubectl auth can-i "$@" 2>/dev/null)" != yes ]; }
denied() { ! kubectl "$@" --dry-run=server >/dev/null 2>&1; }

echo "Environments (built by Terraform)"
envout=$("$INFRA/scripts/verify.sh" dev prod 2>&1 || true)
echo "$envout" | sed '/check(s) failed/,$d' | grep -vE '^$|Everything checks'      # its own summary would repeat what follows
fail=$((fail + $(echo "$envout" | sed '/check(s) failed/,$d' | grep -c '^  ✖' || true)))
FAILED="$FAILED$(echo "$envout" | sed '/check(s) failed/,$d' | grep '^  ✖' | sed 's/^ */\n   /')"
echo "Autoscaling and load balancing"
chk "metrics-server answers" "./scripts/install-metrics-server.sh" kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes
chk "the autoscaler sees real CPU numbers" "kubectl -n $PROD_NS describe hpa chai-stall | tail -8   (metrics-server needs a minute)" \
    bash -c "[ -n \"\$(kubectl -n $PROD_NS get hpa chai-stall -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}')\" ]"
chk "the Service has at least 2 ready endpoints (load is shared)" "kubectl -n $PROD_NS get endpointslices" \
    bash -c "[ \$(kubectl -n $PROD_NS get endpoints chai-stall -o jsonpath='{.subsets[0].addresses[*].ip}' | wc -w) -ge 2 ]"
chk "every Pod runs the same version (no skew)" "$HERE/scripts/skew.sh" "$HERE/scripts/skew.sh"
echo "Policy enforcement (the API server says no)"
chk "an image without a version is refused" "kubectl get validatingadmissionpolicy,validatingadmissionpolicybinding" \
    denied -n "$PROD_NS" create deployment t1 --image=nginx
chk "production cannot be scaled to zero" "kubectl get validatingadmissionpolicy z2h-prod-never-scaled-to-zero-scale" \
    denied -n "$PROD_NS" scale deploy chai-stall --replicas=0
chk "other namespaces are untouched by these rules" "the bindings must select only namespaces with a z2h/owner label" \
    kubectl -n default create deployment t2 --image=nginx --dry-run=server
echo "Backup and recovery"
chk "the ledger is running and holds orders" "kubectl -n chai-ledger get pods ; $HERE/scripts/ledger.sh seed" bash -c "[ \"\$('$HERE/scripts/ledger.sh' count)\" -gt 0 ]"
chk "an automatic backup is scheduled" "kubectl -n chai-ledger get cronjob" kubectl -n chai-ledger get cronjob ledger-backup
echo "Cost and metrics"
chk "night shift is scheduled, and may scale dev but NOT prod" "$HERE/scripts/night-shift.sh enable" bash -c \
    "kubectl -n chai-ops get cronjob night-shift-down && [ \"\$(kubectl auth can-i patch deployments/scale -n iac-dev --as=system:serviceaccount:chai-ops:night-shift)\" = yes ] && [ \"\$(kubectl auth can-i patch deployments/scale -n $PROD_NS --as=system:serviceaccount:chai-ops:night-shift)\" != yes ]"
chk "the cost report runs and names a cost centre" "$HERE/scripts/cost-report.py" bash -c "'$HERE/scripts/cost-report.py' | grep -q cc-"
chk "the DORA report runs" "$HERE/scripts/dora.py --ns $PROD_NS" "$HERE/scripts/dora.py" --ns "$PROD_NS"
if [ "$FULL" = 1 ]; then
  echo "Drills (they break things on purpose)"
  "$HERE/scripts/gameday.sh" all || { fail=$((fail+1)); FAILED="$FAILED\n   ✖ a drill failed (its ✖ lines are above)"; }
fi
echo
if [ "$fail" -eq 0 ]; then ok "Production-ready: scaled, balanced, protected, backed up, and measured."; exit 0; fi
printf '\033[1;31m%d check(s) failed:\033[0m' "$fail"; printf '%b\n' "$FAILED"
echo "   Some checks need a minute after a change (the autoscaler's CPU numbers, new endpoints): run this again before digging."
exit 1
