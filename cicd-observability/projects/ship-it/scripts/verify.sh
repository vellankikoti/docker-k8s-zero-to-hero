#!/usr/bin/env bash
# verify.sh [PHASE]: did you really do it? ✔ or ✖ (with a hint) for each check of a phase, or all of them.
#   ./verify.sh        everything so far          ./verify.sh 3     only phase 3
# It asks the CLUSTER (kubectl), so it works whatever port-forwards you have open.
cd "$(dirname "$0")/../../.." || exit 1
. scripts/k8s-lib.sh
want=${1:-all}; fails=0
okc()  { printf '  \033[1;32m✔\033[0m %s\n' "$*"; }
bad()  { printf '  \033[1;31m✖\033[0m %s\n      hint: %s\n' "$1" "$2"; fails=$((fails+1)); }
phase() { [ "$want" = all ] || [ "$want" = "$1" ]; }
need_cluster

if phase 1; then echo "Phase 1: the platform runs in the cluster"
  for ns in cicd stall-staging stall-prod; do
    lvl=$(kubectl get ns "$ns" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)
    [ -n "$lvl" ] && okc "namespace $ns exists and enforces Pod Security '$lvl'" || bad "namespace $ns is missing (or has no Pod Security label)" "./cicd-observability/scripts/k8s-up.sh"
  done
  for d in registry gitea jenkins; do
    if [ "$d" = jenkins ]; then r=$(kubectl -n cicd get sts jenkins -o jsonpath='{.status.readyReplicas}' 2>/dev/null); else r=$(kubectl -n cicd get deploy "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null); fi
    [ "${r:-0}" -ge 1 ] && okc "$d is Ready" || bad "$d is not Ready" "kubectl -n cicd get pods ; kubectl -n cicd describe pod -l app=$d"
  done
  kubectl -n stall-prod get httproute chai >/dev/null 2>&1 && okc "production's Gateway route exists (blue/green and canary need it)" || bad "no HTTPRoute 'chai' in stall-prod" "./cicd-observability/scripts/k8s-up.sh   (without --no-gateway)"
  kubectl -n cicd get cm z2h-pipeline -o jsonpath='{.data.stage\.sh}' 2>/dev/null | grep -q deploy_staging \
    && okc "the platform's pipeline scripts are published (ConfigMap z2h-pipeline, mounted at /opt/z2h in every build Pod)" \
    || bad "the pipeline scripts are not published" "./cicd-observability/scripts/k8s-up.sh"
  can=$(kubectl auth can-i create deployments -n stall-prod --as=system:serviceaccount:cicd:jenkins-agent 2>/dev/null)
  cant=$(kubectl auth can-i create deployments -n kube-system --as=system:serviceaccount:cicd:jenkins-agent 2>/dev/null)
  [ "$can" = yes ] && [ "$cant" = no ] && okc "least privilege: the pipeline may deploy to stall-prod (yes) but not to kube-system (no)" || bad "the pipeline's permissions are wrong (stall-prod: $can, kube-system: $cant)" "kubectl apply -f cicd-observability/k8s/platform/rbac.yaml"
fi
if phase 2; then echo "Phase 2: your repo, the Git server and Jenkins are connected"
  jobs=$(jenkins_api GET "job/chai-stall/api/json?tree=jobs[name]" 2>/dev/null)
  echo "$jobs" | grep -q '"ci-cd"' && okc "the seed job generated chai-stall/ci-cd (Job DSL)" || bad "chai-stall/ci-cd does not exist" "./cicd-observability/scripts/new-app-repo.sh   (it pushes your repo and runs the seed job)"
  echo "$jobs" | grep -q '"ops-rollback"' && okc "the loop generated the ops-* buttons" || bad "no ops-* jobs" "run 00-seed again in Jenkins"
  curl -s -m 3 -u "$GITEA_USER:$GITEA_PASSWORD" localhost:3001/api/v1/repos/$GITEA_USER/chai-stall 2>/dev/null | grep -q '"name":"chai-stall"' \
    && okc "your repo is on the Git server (localhost:3001)" || bad "cannot see your repo on the Git server" "./cicd-observability/scripts/forward.sh start"
fi
if phase 3; then echo "Phase 3: a pipeline built, tested and published an artifact"
  r=$(jenkins_api GET "job/chai-stall/job/ci-cd/lastSuccessfulBuild/api/json?tree=number,artifacts[fileName]" 2>/dev/null)
  echo "$r" | grep -q build-info.json && okc "a successful build archived build-info.json" || bad "no successful ci-cd build yet" "Jenkins → chai-stall → ci-cd → Build with Parameters (SCAN_MODE=report if the scanner cannot download its database)"
  tags=$(kubectl -n cicd exec deploy/registry -- wget -qO- http://localhost:5000/v2/chai-stall/tags/list 2>/dev/null)
  echo "$tags" | grep -q '"tags":\["' && okc "the registry holds: $tags" || bad "the registry has no chai-stall image" "the 'Build image (Kaniko)' stage must pass"
fi
if phase 4; then echo "Phase 4: staging and production run the new version"
  v=$(kubectl -n stall-staging get deploy chai-stall -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
  [ -n "$v" ] && okc "staging runs $v" || bad "nothing is deployed in stall-staging" "run ci-cd until 'Deploy to staging' passes"
  prod=$(kubectl -n stall-prod get deploy -o jsonpath='{range .items[*]}{.metadata.name}{"="}{.spec.template.spec.containers[0].image}{" "}{end}' 2>/dev/null)
  [ -n "$prod" ] && okc "production runs: $prod" || bad "nothing is deployed in stall-prod" "answer the Approval stage with 'Ship it'"
  ready=$(kubectl -n stall-prod get deploy -o jsonpath='{range .items[*]}{.status.readyReplicas}{" "}{end}' 2>/dev/null)
  [ -n "${ready// /}" ] && okc "ready replicas in production: $ready" || bad "no ready Pods in production" "kubectl -n stall-prod get pods"
fi
if phase 5; then echo "Phase 5: you have used the strategies"
  n=$(kubectl -n cicd exec deploy/registry -- wget -qO- http://localhost:5000/v2/chai-stall/tags/list 2>/dev/null | grep -o '"1\.0\.[0-9]*"' | wc -l)
  [ "$n" -ge 2 ] && okc "at least two versions have been built ($n tags)" || bad "only $n image tag(s)" "run the pipeline a second time"
  failed=$(jenkins_api GET "job/chai-stall/job/ci-cd/api/json?tree=builds[result]" 2>/dev/null | grep -o FAILURE | wc -l)
  [ "$failed" -ge 1 ] && okc "you have seen a pipeline FAIL on purpose ($failed failed build(s))" || bad "no failed build yet" "run ci-cd with STRATEGY=canary and INJECT_BUG ticked"
  hist=$(helm list -n stall-prod -q 2>/dev/null | wc -l); okc "helm releases in production: $hist ($(helm list -n stall-prod -q 2>/dev/null | tr '\n' ' '))"
  echo "      traffic weights: $(kubectl -n stall-prod get httproute chai -o jsonpath='blue={.spec.rules[0].backendRefs[0].weight} green={.spec.rules[0].backendRefs[1].weight}' 2>/dev/null)"
fi
echo; [ $fails -eq 0 ] && echo "All checks for '$want' passed." || echo "$fails check(s) need attention."
exit $([ $fails -eq 0 ] && echo 0 || echo 1)
