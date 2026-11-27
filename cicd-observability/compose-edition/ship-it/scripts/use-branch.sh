#!/usr/bin/env bash
# use-branch.sh [BRANCH]: tell Jenkins which Git branch to build, and make it take effect. Run it from anywhere.
#
#   ./scripts/use-branch.sh              use the branch you are on right now
#   ./scripts/use-branch.sh practice     use a named branch
#
# It (1) writes REPO_BRANCH into .env, (2) restarts Jenkins so it reads it, (3) re-runs the 00-seed job,
# which re-creates the pipelines pointing at that branch. Safe to run again at any time.
#
# Why you need this: Jenkins builds a *branch of Git*, not your working folder. If you commit on "practice"
# but Jenkins is watching "main", your change is invisible to it. No push is needed: Jenkins reads your
# local repository directly (it is mounted into the container).
set -euo pipefail
cd "$(dirname "$0")/.."

say() { printf '\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m✖ %s\033[0m\n' "$*" >&2; exit 1; }

branch=${1:-$(git branch --show-current)}
[ -n "$branch" ] || die "you are on a detached HEAD. Name a branch: ./scripts/use-branch.sh practice"
git show-ref --verify --quiet "refs/heads/$branch" || die "there is no local branch '$branch'. Create it first: git switch -c $branch"
[ -f .env ] || cp .env.example .env

say "Jenkins will build branch '$branch'"
if grep -q '^REPO_BRANCH=' .env; then sed -i.bak "s#^REPO_BRANCH=.*#REPO_BRANCH=*/$branch#" .env && rm -f .env.bak
else echo "REPO_BRANCH=*/$branch" >> .env; fi
grep '^REPO_BRANCH=' .env

PW=$(sed -n 's/^JENKINS_ADMIN_PASSWORD=//p' .env); PW=${PW:-z2h-jenkins}
J=http://localhost:8080

say "Restarting Jenkins so it reads the new setting (about a minute)"
docker compose up -d jenkins >/dev/null
for _ in $(seq 1 60); do curl -sf -o /dev/null "$J/login" && break; sleep 3; done
curl -sf -o /dev/null "$J/login" || die "Jenkins did not come back. Look: docker compose logs jenkins | tail -30"
sleep 8   # let the jobs finish loading

say "Running the 00-seed job (it re-creates the pipelines for this branch)"
jar=$(mktemp); trap 'rm -f "$jar"' EXIT
crumb=$(curl -s -c "$jar" -b "$jar" -u "admin:$PW" "$J/crumbIssuer/api/json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['crumbRequestField']+':'+d['crumb'])") \
  || die "could not log in to Jenkins as admin. Is JENKINS_ADMIN_PASSWORD in .env the one Jenkins started with?"
code=$(curl -s -o /dev/null -w '%{http_code}' -c "$jar" -b "$jar" -u "admin:$PW" -H "$crumb" -X POST "$J/job/00-seed/build")
[ "$code" = 201 ] || die "could not start 00-seed (HTTP $code)"
for _ in $(seq 1 40); do
  r=$(curl -s -u "admin:$PW" "$J/job/00-seed/lastBuild/api/json?tree=building,result" || true)
  echo "$r" | grep -q '"building":false' && break; sleep 3
done
echo "$r" | grep -q '"result":"SUCCESS"' || die "the seed job did not succeed. Open $J/job/00-seed/lastBuild/console"
ok "Done. Jenkins now builds '$branch'. Commit on this branch, then run chai-stall/ci-cd (or wait ~2 minutes for the poll)."
