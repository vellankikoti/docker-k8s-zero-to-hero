#!/usr/bin/env bash
# verify.sh [PHASE]: did you really do it? Prints ✔ or ✖ for each check of a phase (or all of them).
#   ./scripts/verify.sh          check everything so far
#   ./scripts/verify.sh 3        check only phase 3
cd "$(dirname "$0")/.." || exit 1
want=${1:-all}
J=http://localhost:8080
PW=$(sed -n 's/^JENKINS_ADMIN_PASSWORD=//p' .env 2>/dev/null); PW=${PW:-z2h-jenkins}
fails=0
ok()  { printf '  \033[1;32m✔\033[0m %s\n' "$*"; }
bad() { printf '  \033[1;31m✖\033[0m %s\n      hint: %s\n' "$1" "$2"; fails=$((fails+1)); }
phase() { [ "$want" = all ] || [ "$want" = "$1" ]; }
jq_() { curl -sg -u "admin:$PW" "$J/$1"; }

if phase 1; then echo "Phase 1: the factory is running"
  curl -sf localhost:5001/v2/ >/dev/null && ok "registry answers on :5001" || bad "registry is not answering" "docker compose up -d   (in ship-it/)"
  curl -sf -o /dev/null $J/login && ok "Jenkins answers on :8080" || bad "Jenkins is not answering" "docker compose logs jenkins | tail -30   (first start takes ~1 minute)"
  docker inspect chai-router >/dev/null 2>&1 && ok "the production router container exists" || bad "no chai-router container" "docker compose up -d"
  watched=$(sed -n 's/^REPO_BRANCH=\*\///p' .env 2>/dev/null); watched=${watched:-main}; current=$(git branch --show-current)
  if [ "$watched" = "$current" ]; then ok "Jenkins builds the branch you are on ('$current')"
  else bad "Jenkins builds '$watched' but you are on '$current': your commits are invisible to it" "./scripts/use-branch.sh   (no push needed)"; fi
fi
if phase 2; then echo "Phase 2: Jenkins was configured and the jobs were generated, all from Git"
  jq_ "api/json?tree=jobs[name]" | grep -q '"00-seed"' && ok "the seed job exists (made by Configuration as Code)" || bad "no 00-seed job" "docker compose logs jenkins | grep -i casc"
  jq_ "job/chai-stall/api/json?tree=jobs[name]" | grep -q '"ci-cd"' && ok "the seed job generated chai-stall/ci-cd (Job DSL)" || bad "chai-stall/ci-cd does not exist" "open Jenkins, run 00-seed, read its console output"
  jq_ "job/chai-stall/api/json?tree=jobs[name]" | grep -q '"ops-rollback"' && ok "the loop generated the ops-* jobs" || bad "no ops-* jobs" "run 00-seed again"
fi
if phase 3; then echo "Phase 3: a pipeline built, tested and published an artifact"
  r=$(jq_ "job/chai-stall/job/ci-cd/lastSuccessfulBuild/api/json?tree=number,artifacts[fileName]")
  echo "$r" | grep -q build-info.json && ok "a successful build archived build-info.json" || bad "no successful ci-cd build with artifacts yet" "run chai-stall/ci-cd: Build with Parameters (SCAN_MODE=report if the scan cannot download its database)"
  tags=$(curl -s localhost:5001/v2/chai-stall/tags/list); echo "$tags" | grep -q '"tags":\["' && ok "the registry holds image tags: $tags" || bad "the registry has no chai-stall image" "the 'Push to registry' stage must pass"
fi
if phase 4; then echo "Phase 4: staging and production serve the new version"
  curl -sf localhost:8081/api/info | grep -q version && ok "staging answers on :8081 ($(curl -s localhost:8081/api/info | grep -o '"version": "[^"]*"'))" || bad "staging is not answering" "run ci-cd until the 'Deploy to staging' stage passes"
  curl -sf localhost:8090/api/info | grep -q version && ok "production answers on :8090 ($(curl -s localhost:8090/api/info | grep -o '"version": "[^"]*"'))" || bad "production is not answering" "answer the Approval stage with 'Ship it'"
fi
if phase 5; then echo "Phase 5: you know all four strategies"
  n=$(curl -s localhost:5001/v2/chai-stall/tags/list | grep -o '"[0-9][0-9.]*"' | wc -l)
  [ "$n" -ge 2 ] && ok "at least two versions have been released ($n tags)" || bad "only $n image tag(s)" "run the pipeline a second time"
  failed=$(jq_ "job/chai-stall/job/ci-cd/api/json?tree=builds[result]" | grep -c FAILURE)
  [ "$failed" -ge 1 ] && ok "you have seen a pipeline FAIL on purpose ($failed failed build(s)): that is the point of a gate" || bad "no failed build yet" "run ci-cd with STRATEGY=canary and INJECT_BUG=true"
  deploy=$(deploy/deploy.sh state 2>/dev/null); echo "      router state: $deploy"
fi
echo; [ $fails -eq 0 ] && echo "All checks for '$want' passed." || echo "$fails check(s) need attention."
exit $([ $fails -eq 0 ] && echo 0 || echo 1)
