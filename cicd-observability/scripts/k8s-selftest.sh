#!/usr/bin/env bash
# k8s-selftest.sh: an end-to-end test of the Unit 4 Kubernetes platform + Project 1, on YOUR cluster. About 15 minutes.
#
#   ./cicd-observability/scripts/k8s-selftest.sh            installs the platform if needed, then runs everything
#   ./cicd-observability/scripts/k8s-selftest.sh --keep     leave the test app repo and releases in place afterwards
#
# It creates a throwaway app repo in a temp folder, pushes it to the in-cluster Git server, and drives Jenkins through its API:
#   build + test + scan + Kaniko + push → staging → production (blue/green) → a BUGGY canary (must be rolled back automatically)
#   → a healthy canary (must be promoted). It prints one ✔ or ✖ per check and exits 1 if anything failed.
# Run it on a throwaway cluster (kind / Docker Desktop / minikube), never on a shared one.
set -uo pipefail
. "$(dirname "$0")/k8s-lib.sh"
KEEP=0; [ "${1:-}" = "--keep" ] && KEEP=1
pass=0; fail=0
check() {  # check "label" command...
  local label=$1; shift
  if "$@" >/tmp/k8s-selftest.out 2>&1; then printf '  \033[1;32m✔\033[0m %s\n' "$label"; pass=$((pass+1))
  else printf '  \033[1;31m✖\033[0m %s\n' "$label"; sed 's/^/      /' /tmp/k8s-selftest.out | tail -8; fail=$((fail+1)); fi
}
need_cluster; need_helm

# ---- helpers to drive Jenkins ----
next_build() { jenkins_api GET "job/chai-stall/job/ci-cd/api/json?tree=nextBuildNumber" | sed -n 's/.*"nextBuildNumber":\([0-9]*\).*/\1/p'; }
wait_build() {  # wait_build N SECONDS → prints the result; approves the production gate if the build pauses there
  local n=$1 t=$2 i r d
  for ((i=0; i<t; i+=5)); do
    r=$(jenkins_api GET "job/chai-stall/job/ci-cd/$n/api/json?tree=building,result" 2>/dev/null)
    if echo "$r" | grep -q '"building":false' && echo "$r" | grep -q '"result":"'; then echo "$r" | sed -n 's/.*"result":"\([A-Z_]*\)".*/\1/p'; return; fi
    d=$(jenkins_api GET "job/chai-stall/job/ci-cd/$n/wfapi/nextPendingInputAction" 2>/dev/null)
    id=$(echo "$d" | sed -n 's/.*"id":"\([a-f0-9]*\)".*/\1/p')
    [ -n "$id" ] && jenkins_api POST "job/chai-stall/job/ci-cd/$n/input/$id/proceedEmpty" >/dev/null
    sleep 5
  done
  echo TIMEOUT
}
run_build() {  # run_build "query string"   → prints the result
  local n; n=$(next_build); jenkins_api POST "job/chai-stall/job/ci-cd/buildWithParameters?$1" >/dev/null; wait_build "$n" 900
}
weights() { kubectl -n stall-prod get httproute chai -o jsonpath='{.spec.rules[0].backendRefs[0].weight} {.spec.rules[0].backendRefs[1].weight}'; }
single_colour() { case "$(weights)" in "100 0"|"0 100") return 0 ;; *) return 1 ;; esac; }
prod_has_release() { kubectl -n stall-prod get deploy -o name | grep -q 'chai-'; }
staging_ready() { kubectl -n stall-staging get deploy chai-stall -o jsonpath='{.status.readyReplicas}' | grep -qE '^[1-9]'; }
in_registry() { kubectl -n cicd exec deploy/registry -- wget -qO- http://localhost:5000/v2/chai-stall/tags/list | grep -q '"tags"'; }
seed_made_ci_cd() { jenkins_api GET 'job/chai-stall/api/json?tree=jobs[name]' | grep -q '"ci-cd"'; }
ns_enforces_restricted() { [ "$(kubectl get ns stall-prod -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')" = restricted ]; }
can() { [ "$(kubectl auth can-i "$@" --as=system:serviceaccount:cicd:jenkins-agent)" = yes ]; }
cannot() { ! can "$@"; }
root_pod_refused() { kubectl run rootpod --image=nginx -n stall-prod --dry-run=server 2>&1 | grep -q 'violates PodSecurity'; }


say "1/6 Platform"
"$(dirname "$0")/k8s-up.sh" >/dev/null || die "k8s-up.sh failed: run it by hand to see why"
"$(dirname "$0")/forward.sh" start >/dev/null 2>&1
check "namespaces enforce Pod Security restricted" ns_enforces_restricted
check "the pipeline's ServiceAccount may deploy to stall-prod" can create deployments -n stall-prod
check "...but not to kube-system (least privilege)" cannot create deployments -n kube-system
check "Pod Security rejects a root Pod in production" root_pod_refused

say "2/6 Your app repo → Git server → Jenkins"
WORK=$(mktemp -d)/chai-stall
"$(dirname "$0")/new-app-repo.sh" "$WORK" >/dev/null || die "new-app-repo.sh failed: run it by hand to see why"
check "the seed job created chai-stall/ci-cd" seed_made_ci_cd

say "3/6 First build (Jenkins learns the pipeline's parameters from it; the result does not matter)"
n=$(next_build); jenkins_api POST "job/chai-stall/job/ci-cd/build" >/dev/null; r=$(wait_build "$n" 900); echo "   build #$n finished: $r"

say "4/6 Full pipeline, blue/green, no approval (scan in report mode so a slow or offline network cannot fail it)"
r=$(run_build "SCAN_MODE=report&REQUIRE_APPROVAL=false&STRATEGY=bluegreen")
check "the pipeline finished SUCCESS (got: $r)" test "$r" = SUCCESS
check "the image is in the registry" in_registry
check "staging runs the new version" staging_ready
check "production has a release" prod_has_release
check "all production traffic is on one colour (weights: $(weights))" single_colour

say "5/6 A BUGGY canary must be rolled back by the pipeline itself"
before=$(weights)
r=$(run_build "SCAN_MODE=skip&REQUIRE_APPROVAL=false&STRATEGY=canary&CANARY_PERCENT=40&INJECT_BUG=true")
check "the buggy canary build FAILED (got: $r)" test "$r" = FAILURE
check "traffic is back on a single colour (was: $before, now: $(weights))" single_colour

say "6/6 A HEALTHY canary must be promoted"
r=$(run_build "SCAN_MODE=skip&REQUIRE_APPROVAL=false&STRATEGY=canary&CANARY_PERCENT=40")
check "the healthy canary build SUCCEEDED (got: $r)" test "$r" = SUCCESS
check "all traffic is on one colour again (weights: $(weights))" single_colour

[ "$KEEP" = 1 ] || { rm -rf "$(dirname "$WORK")"; }
echo; printf '\033[1m%d passed, %d failed\033[0m\n' "$pass" "$fail"
[ "$fail" -eq 0 ] && echo "The Kubernetes edition of Unit 4 works on this cluster." || echo "Send the ✖ lines above (and 'kubectl -n cicd get pods') to whoever maintains this track."
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
