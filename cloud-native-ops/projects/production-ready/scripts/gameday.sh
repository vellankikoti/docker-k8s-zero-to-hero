#!/usr/bin/env bash
# gameday.sh DRILL: break things on purpose, and CHECK that the system behaves. Every drill ends with a clear ✔ or ✖.
#
#   gameday.sh list
#   gameday.sh policy     the API server refuses 4 unsafe changes                       (S: admission, S4 security)
#   gameday.sh restore    wipe the ledger, restore the backup, count the orders         (the GitLab 2017 story)
#   gameday.sh skew       one Pod on an old version is detected                         (the Knight Capital 2012 story)
#   gameday.sh rush       the Diwali rush: the autoscaler adds Pods, load is shared
#   gameday.sh kill       kill a Pod in the middle of the rush: customers barely notice
#   gameday.sh all        every drill, in that order
set -uo pipefail
. "$(dirname "$0")/lib.sh"
need_cluster
FAILS=0
pass() { printf '  \033[1;32m✔ %s\033[0m\n' "$*"; }
miss() { printf '  \033[1;31m✖ %s\033[0m\n' "$*"; FAILS=$((FAILS+1)); }
expect_denied() { local label=$1; shift; if out=$("$@" --dry-run=server 2>&1); then miss "$label: it was ALLOWED (the policy is missing)"; else pass "$label: refused ($(echo "$out" | grep -o 'denied request: .*' | cut -c17-90))"; fi; }

drill_policy() {
  say "Drill: the API server's rules (admission policy)"
  expect_denied "an image with no version" kubectl -n "$PROD_NS" create deployment d1 --image=nginx
  expect_denied "an image tagged latest" kubectl -n "$PROD_NS" create deployment d2 --image=nginx:latest
  expect_denied "a container with no resource limits" kubectl -n "$PROD_NS" create deployment d3 --image=nginx:1.27
  expect_denied "production scaled to zero (the one-typo outage)" kubectl -n "$PROD_NS" scale deploy chai-stall --replicas=0
}

drill_restore() {
  say "Drill: lose the data, get it back (backups you never restored are only hope)"
  "$HERE/scripts/ledger.sh" seed 1000 >/dev/null; "$HERE/scripts/ledger.sh" backup >/dev/null || { miss "the backup itself failed"; return; }
  "$HERE/scripts/ledger.sh" disaster >/dev/null
  [ "$("$HERE/scripts/ledger.sh" count)" = 0 ] && pass "the disaster happened: the ledger is empty" || miss "the ledger was not wiped"
  "$HERE/scripts/ledger.sh" restore >/dev/null || { miss "the restore failed"; return; }
  n=$("$HERE/scripts/ledger.sh" count)
  [ "$n" = 1000 ] && pass "restored: the ledger holds $n orders again" || miss "after the restore the ledger holds '$n' orders, expected 1000"
}

drill_skew() {
  say "Drill: one Pod on an old version"
  kubectl -n "$PROD_NS" delete pod rogue --ignore-not-found >/dev/null 2>&1
  kubectl apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata: { name: rogue, namespace: $PROD_NS, labels: { app.kubernetes.io/name: chai-stall, app: rogue } }
spec:
  securityContext: { runAsNonRoot: true, runAsUser: 10001, seccompProfile: { type: RuntimeDefault } }
  containers:
    - name: old
      image: localhost:30500/chai-stall:0.9.0-old
      securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: [ALL] } }
      resources: { requests: { cpu: 5m, memory: 8Mi }, limits: { memory: 32Mi } }
YAML
  if "$HERE/scripts/skew.sh" "$PROD_NS" >/dev/null 2>&1; then miss "skew.sh did not notice the old Pod"; else pass "skew.sh noticed two versions running side by side"; fi
  kubectl -n "$PROD_NS" delete pod rogue --wait=false >/dev/null
  for _ in $(seq 1 20); do kubectl -n "$PROD_NS" get pod rogue >/dev/null 2>&1 || break; sleep 2; done
  "$HERE/scripts/skew.sh" "$PROD_NS" >/dev/null 2>&1 && pass "after removing it, every Pod runs the same version" || miss "skew remains after removing the rogue Pod"
}

drill_rush() {
  say "Drill: the Diwali rush"
  "$HERE/scripts/rush.sh" --seconds 90 --workers 4 || { miss "the rush did not run"; return; }
  # shellcheck disable=SC1091
  . /tmp/z2h-rush.last
  [ "${RUSH_OK:-0}" -gt 0 ] && pass "$RUSH_OK orders were placed" || miss "no order succeeded"
  total=$(( ${RUSH_OK:-0} + ${RUSH_FAILED:-0} ))
  [ "$total" -gt 0 ] && [ $(( ${RUSH_FAILED:-0} * 100 / total )) -le 1 ] && pass "at most 1% of orders failed ($RUSH_FAILED of $total)" || miss "more than 1% failed ($RUSH_FAILED of $total)"
  r=$(kubectl -n "$PROD_NS" get hpa chai-stall -o jsonpath='{.status.currentReplicas}')
  [ "${r:-0}" -ge 2 ] && pass "the autoscaler is holding $r Pods (it adds more above 70% CPU and removes them again when the rush ends)" || miss "fewer than 2 Pods"
}

drill_kill() {
  say "Drill: a Pod dies in the middle of the rush"
  ( "$HERE/scripts/rush.sh" --seconds 60 --workers 3 >/tmp/z2h-rush-kill.out 2>&1 ) &
  bg=$!
  sleep 25
  victim=$(kubectl -n "$PROD_NS" get pods -l app.kubernetes.io/name=chai-stall -o jsonpath='{.items[0].metadata.name}')
  kubectl -n "$PROD_NS" delete pod "$victim" --wait=false >/dev/null && printf '  💀 killed %s\n' "$victim"
  wait "$bg" || true
  # shellcheck disable=SC1091
  . /tmp/z2h-rush.last
  total=$(( ${RUSH_OK:-0} + ${RUSH_FAILED:-0} ))
  if [ "$total" -gt 0 ] && [ $(( ${RUSH_FAILED:-0} * 100 / total )) -le 1 ]; then pass "$RUSH_FAILED of $total orders failed: the Service stopped sending to the dying Pod, the Deployment replaced it"
  else miss "$RUSH_FAILED of $total orders failed (more than 1%)"; fi
  kubectl -n "$PROD_NS" rollout status deploy/chai-stall --timeout=120s >/dev/null && pass "the Deployment is whole again" || miss "the Deployment did not recover"
}

case "${1:-list}" in
  list) sed -n '2,12p' "$0" ;;
  policy) drill_policy ;;
  restore) drill_restore ;;
  skew) drill_skew ;;
  rush) drill_rush ;;
  kill) drill_kill ;;
  all) drill_policy; drill_restore; drill_skew; drill_rush; drill_kill ;;
  *) sed -n '2,12p' "$0"; exit 1 ;;
esac
echo
[ "$FAILS" -eq 0 ] && { ok "drill passed"; exit 0; } || { printf '\033[1;31m%d check(s) failed.\033[0m\n' "$FAILS"; exit 1; }
