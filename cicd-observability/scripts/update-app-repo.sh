#!/usr/bin/env bash
# update-app-repo.sh [DIR]: bring YOUR app repo's pipeline files up to date with the course repo, then commit and push.
#
#   git pull                                                        (in the course repo: get the newest course files)
#   ./cicd-observability/scripts/update-app-repo.sh                 updates ~/chai-stall
#   ./cicd-observability/scripts/update-app-repo.sh ~/work/stall    any other folder
#
# Your app repo is a COPY made by new-app-repo.sh, so a pipeline fix merged into the course repo does not reach it by itself.
# This copies only the PIPELINE files: Jenkinsfile, Jenkinsfile.dynamic, pipeline-config.json, ci/, deploy/, jenkins/
# and the Helm chart in chart/. It NEVER touches app/ (your code and tests).
#   Edited the chart or a Jenkinsfile yourself (Project 1, Phases 6-7)? Those edits are overwritten: git shows the diff
#   before it is committed, and `git revert` brings them back.
set -euo pipefail
. "$(dirname "$0")/k8s-lib.sh"
DIR=${1:-$HOME/chai-stall}
[ -d "$DIR/.git" ] || die "$DIR is not a Git repository. Create your repo first: ./cicd-observability/scripts/new-app-repo.sh"
SRC="$COURSE_ROOT/cicd-observability/projects/project-1-ship-it/app-repo"
[ -d "$SRC" ] || die "cannot find the course's pipeline files at $SRC. Run this from a clone of the course repository."

cd "$DIR"
if [ -n "$(git status --porcelain)" ]; then
  die "you have uncommitted changes in $DIR. Commit or stash them first (git status), then run this again."
fi

say "Copying the newest pipeline files from the course repo into $DIR (never app/)"
for f in Jenkinsfile Jenkinsfile.dynamic pipeline-config.json; do cp "$SRC/$f" "$DIR/$f"; done
for d in ci deploy jenkins; do mkdir -p "$DIR/$d"; cp -r "$SRC/$d/." "$DIR/$d/"; done
rm -rf "$DIR/chart/chai-stall"; mkdir -p "$DIR/chart"; cp -r "$K8S_DIR/chart/chai-stall" "$DIR/chart/chai-stall"
chmod +x "$DIR"/ci/*.sh "$DIR"/deploy/*.sh 2>/dev/null || true

if [ -z "$(git status --porcelain)" ]; then ok "Already up to date: nothing to commit."; exit 0; fi
git status --short | sed 's/^/   /'
git add -A
git commit -qm "Update the pipeline files from the course repo"
ok "Committed. Pushing to the Git server (Jenkins will start a build)"
if ! out=$(git push -q -u origin "$(git branch --show-current)" 2>&1); then
  echo "$out" >&2
  die "the push failed. Is the port-forward alive?  ./cicd-observability/scripts/forward.sh status   (to replace the whole repo instead: new-app-repo.sh)"
fi

# The job definitions (jenkins/jobs/*.groovy) may have changed: re-run the seed job if the cluster is reachable.
if kubectl -n cicd get pod jenkins-0 >/dev/null 2>&1; then
  say "Re-running Jenkins' seed job so any new or changed jobs appear"
  jenkins_api POST "job/00-seed/build" >/dev/null 2>&1 || warn "could not start the seed job: open Jenkins → 00-seed → Build Now"
fi
ok "Done. Watch the build: Jenkins → chai-stall → ci-cd"
