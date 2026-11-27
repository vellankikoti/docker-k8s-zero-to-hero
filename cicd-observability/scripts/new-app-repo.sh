#!/usr/bin/env bash
# new-app-repo.sh [DIR]: create YOUR OWN copy of the Chai Stall repository, push it to the in-cluster Git server,
# connect it to Jenkins (a webhook) and generate the Jenkins jobs from it.
#
#   ./cicd-observability/scripts/new-app-repo.sh              creates ~/chai-stall
#   ./cicd-observability/scripts/new-app-repo.sh ~/work/stall any folder that does not exist yet
#
# Your repo is SEPARATE from the course repository: committing and pushing there can never affect the shared course repo.
set -euo pipefail
. "$(dirname "$0")/k8s-lib.sh"
DIR=${1:-$HOME/chai-stall}
need_cluster
[ ! -e "$DIR" ] || die "$DIR already exists. Pick another folder, or delete it first (rm -rf $DIR)."
kubectl -n cicd get deploy/gitea >/dev/null 2>&1 || die "the platform is not installed. Run: ./cicd-observability/scripts/k8s-up.sh"

say "Opening the Git server door (localhost:3001)"
"$(dirname "$0")/forward.sh" start >/dev/null 2>&1 || true
for _ in $(seq 1 30); do curl -sf -o /dev/null http://localhost:3001/api/healthz && break; sleep 2; done
curl -sf -o /dev/null http://localhost:3001/api/healthz || die "cannot reach the Git server on localhost:3001. Run: ./cicd-observability/scripts/forward.sh start"

say "Building your repository in $DIR"
mkdir -p "$DIR/chart"
cp -r "$COURSE_ROOT/cicd-observability/app" "$DIR/app"
find "$DIR/app" -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true
cp -r "$K8S_DIR/chart/chai-stall" "$DIR/chart/chai-stall"
cp -r "$COURSE_ROOT/cicd-observability/projects/project-1-ship-it/app-repo/." "$DIR/"
cat > "$DIR/README.md" <<'MD'
# chai-stall (your repository)
Your own Chai Stall service and its pipeline. `git push` here and Jenkins builds, tests and ships it.
- `app/`: the service and its tests · `chart/`: its Helm chart (probes, limits, security) · `ci/pod.yaml`: the build Pod
- `Jenkinsfile`: the SHAPE of the pipeline (which stages, which container, when) · `jenkins/jobs/`: the Jenkins jobs, as code
- How each stage WORKS is platform logic (`stage.sh`, `k8s-deploy.sh`) mounted at /opt/z2h in every build Pod: it is
  updated for you by the course (git pull, then k8s-up.sh), so nothing here needs copying or refreshing.
MD
cd "$DIR"
git init -q -b main
git config user.name  "$(git config --global user.name  2>/dev/null || echo 'Chai Dev')"
git config user.email "$(git config --global user.email 2>/dev/null || echo 'dev@stall.local')"
git add -A && git commit -qm "Initial commit: the Chai Stall"

API=http://localhost:3001/api/v1
say "Creating the repository on the Git server and connecting it to Jenkins"
curl -s -u "$GITEA_USER:$GITEA_PASSWORD" -H 'Content-Type: application/json' \
  -d '{"name":"chai-stall","default_branch":"main","private":false}' "$API/user/repos" >/dev/null || true
curl -s -u "$GITEA_USER:$GITEA_PASSWORD" "$API/repos/$GITEA_USER/chai-stall" | grep -q '"name":"chai-stall"' || die "could not create the repository on the Git server"
hooks=$(curl -s -u "$GITEA_USER:$GITEA_PASSWORD" "$API/repos/$GITEA_USER/chai-stall/hooks")
if ! echo "$hooks" | grep -q notifyCommit; then
  curl -s -u "$GITEA_USER:$GITEA_PASSWORD" -H 'Content-Type: application/json' -o /dev/null \
    -d '{"type":"gitea","active":true,"events":["push"],"config":{"url":"http://jenkins.cicd.svc.cluster.local:8080/git/notifyCommit?url=http://gitea.cicd.svc.cluster.local:3000/z2h/chai-stall.git","content_type":"json"}}' \
    "$API/repos/$GITEA_USER/chai-stall/hooks"
fi
git remote add origin "http://$GITEA_USER:$GITEA_PASSWORD@localhost:3001/$GITEA_USER/chai-stall.git"
# This script makes a FRESH repository, so it replaces whatever an earlier run left on the Git server (your lab Git
# server only: never the course repo). Without --force a second run would be rejected ("fetch first"), and that
# used to be hidden: Jenkins then kept building the OLD copy.
if git ls-remote --exit-code origin main >/dev/null 2>&1; then
  warn "the Git server already has a copy of chai-stall from an earlier run: replacing it with this fresh one"
fi
if ! out=$(git push -q -u --force origin main 2>&1); then
  echo "$out" >&2
  die "could not push to the Git server (http://localhost:3001). Is the port-forward alive? ./cicd-observability/scripts/forward.sh status"
fi

say "Asking Jenkins to read jenkins/jobs/*.groovy and create the jobs (the seed job)"
for _ in $(seq 1 40); do jenkins_api GET "api/json" 2>/dev/null | grep -q '"00-seed"' && break; sleep 3; done
jenkins_api POST "job/00-seed/build" >/dev/null
for _ in $(seq 1 40); do
  r=$(jenkins_api GET "job/00-seed/lastBuild/api/json?tree=building,result" 2>/dev/null || true)
  echo "$r" | grep -q '"building":false' && break; sleep 3
done
echo "$r" | grep -q '"result":"SUCCESS"' || die "the seed job did not succeed. Open Jenkins (http://localhost:8081) → 00-seed → Console Output"

ok "Your repository is ready:  cd $DIR"
cat <<MSG

  Git server   http://localhost:3001/$GITEA_USER/chai-stall     (login $GITEA_USER / $GITEA_PASSWORD)
  Jenkins      http://localhost:8081  →  chai-stall  →  ci-cd    (login admin / $JENKINS_ADMIN_PASSWORD)

  From now on:  edit in $DIR, 'git commit', 'git push'  →  Jenkins builds it. No GitHub account, no risk to the course repo.
MSG
