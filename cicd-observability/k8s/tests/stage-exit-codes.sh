#!/usr/bin/env bash
# stage-exit-codes.sh: regression tests for the exit codes of the pipeline's deploy stage. No cluster needed.
#
# The rule being protected: the stage's result must reflect the HEALTH OF THE RELEASE, nothing else. A real incident:
# "helm test --logs" failed because the (passing) test Pod had already been deleted, so a healthy release was reported
# as failed and rolled back. These tests stand in for helm and kubectl and check every combination.
#   ./cicd-observability/k8s/tests/stage-exit-codes.sh
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
STAGE="$HERE/pipeline/stage.sh"
command -v dash >/dev/null 2>&1 && SH=dash || SH=sh        # the stage runs under plain POSIX sh in the build Pod
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/ws/chart/chai-stall"

cat > "$T/bin/helm" <<'STUB'
#!/bin/sh
# A stand-in for helm. Behaviour is chosen with environment variables.
case "$1" in
  upgrade)  [ "${UPGRADE:-ok}" = ok ] && exit 0; echo "Error: UPGRADE FAILED: context deadline exceeded" >&2; exit 1 ;;
  test)
    case "$*" in *--logs*) echo 'Error: unable to get pod logs for chai-stall-smoke: pods "chai-stall-smoke" not found' >&2; exit 1 ;; esac
    [ "${SMOKE:-pass}" = pass ] && { echo "Phase: Succeeded"; exit 0; }; echo "Error: 1 test failed" >&2; exit 1 ;;
  history)  if [ "${REVISIONS:-2}" = 1 ]; then echo '[{"revision":1}]'; else echo '[{"revision":1},{"revision":2}]'; fi ;;
  rollback) echo "ROLLED-BACK" >> "$CALLS" ;;
  uninstall) echo "UNINSTALLED" >> "$CALLS" ;;
  *) exit 0 ;;
esac
STUB
cat > "$T/bin/kubectl" <<'STUB'
#!/bin/sh
case "$*" in *" logs "*) echo 'Error from server (NotFound): pods "chai-stall-smoke" not found' >&2; exit 1 ;; esac
exit 0
STUB
cat > "$T/bin/trivy" <<'STUB'
#!/bin/sh
# A stand-in for trivy. DB=ok|down chooses whether the database can be downloaded; FINDING=1 makes a scan report a CRITICAL.
case "$*" in
  --version) echo "Version: stub" ;;
  *--download-db-only*) [ "${DB:-ok}" = ok ] && exit 0; echo 'FATAL init error: failed to download vulnerability DB' >&2; echo '	* Get "https://mirror.gcr.io/v2/": dial tcp: i/o timeout' >&2; exit 1 ;;
  *) echo scanned >> "$CALLS"; [ "${FINDING:-0}" = 1 ] && case "$*" in *"--exit-code 1"*) exit 1 ;; esac; exit 0 ;;
esac
STUB
chmod +x "$T/bin/"*
mkdir -p "$T/ws/out"; : > "$T/ws/out/image.tar"

fail=0
check() {  # check "label" EXPECTED_EXIT "env..." [grep-pattern-that-must-appear-in-calls] [stage]
  label=$1; want=$2; envs=$3; calls_want=${4:-}; stage=${5:-deploy-staging}
  CALLS="$T/calls"; : > "$CALLS"
  env PATH="$T/bin:$PATH" WORKSPACE="$T/ws" TAG=1.0.4 SCAN_MODE=report PULL_REPO=localhost:30500/chai-stall CALLS="$CALLS" $envs \
    $SH "$STAGE" "$stage" > "$T/out" 2>&1
  got=$?
  ok=1
  [ "$got" = "$want" ] || ok=0
  if [ -n "$calls_want" ] && ! grep -q "$calls_want" "$CALLS"; then ok=0; fi
  if [ $ok = 1 ]; then printf '  \033[1;32m✔\033[0m %s\n' "$label"
  else printf '  \033[1;31m✖\033[0m %s (exit %s, wanted %s; calls: %s)\n' "$label" "$got" "$want" "$(tr '\n' ' ' < "$CALLS")"; sed 's/^/      /' "$T/out" | tail -5; fail=1; fi
}

echo "deploy-staging exit codes ($SH):"
check "healthy release, smoke test passes, test Pod already deleted  -> success, NO rollback" 0 "SMOKE=pass"
! grep -q "ROLLED-BACK\|UNINSTALLED" "$T/calls" || { echo "  ✖ a healthy release was rolled back"; fail=1; }
check "smoke test FAILS (revision 2)                                 -> failure and rollback" 1 "SMOKE=fail REVISIONS=2" ROLLED-BACK
check "smoke test FAILS (first release)                              -> failure and uninstall" 1 "SMOKE=fail REVISIONS=1" UNINSTALLED
check "helm upgrade FAILS (never became healthy)                     -> failure and rollback" 1 "UPGRADE=fail REVISIONS=2" ROLLED-BACK
if grep -q "Evidence, collected BEFORE rolling back" "$T/out"; then printf '  \033[1;32m✔\033[0m a failure prints its evidence first\n'; else echo "  ✖ no evidence printed on failure"; fail=1; fi
echo "scan exit codes:"
check "enforce, database reachable, clean image            -> success" 0 "SCAN_MODE=enforce DB=ok" scanned scan
check "enforce, database reachable, CRITICAL finding       -> failure" 1 "SCAN_MODE=enforce DB=ok FINDING=1" scanned scan
check "enforce, NO database reachable                      -> failure (fails closed, says why)" 1 "SCAN_MODE=enforce DB=down" "" scan
grep -q "no vulnerability database is reachable" "$T/out" || { echo "  ✖ enforce+no DB did not explain itself"; fail=1; }
check "report, NO database reachable                       -> success, says it did not scan" 0 "SCAN_MODE=report DB=down" "" scan
grep -q "NOT scanned" "$T/out" || { echo "  ✖ report+no DB did not say the image was not scanned"; fail=1; }
check "report, database reachable, CRITICAL finding        -> success (never blocks)" 0 "SCAN_MODE=report DB=ok FINDING=1" scanned scan
[ $fail = 0 ] && echo "all stage exit-code tests passed" || echo "SOME TESTS FAILED"
exit $fail
