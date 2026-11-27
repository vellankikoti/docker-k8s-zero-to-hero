#!/usr/bin/env bash
# new-infra-repo.sh [DIR]: create YOUR OWN copy of the infrastructure repository, push it to the in-cluster Git server, and
# create the Jenkins job that runs it.   (needs the full CI/CD platform: ./cicd-observability/scripts/k8s-up.sh)
#
#   new-infra-repo.sh              creates ~/infra
#   new-infra-repo.sh ~/work/infra any folder that does not exist yet
set -euo pipefail
. "$(dirname "$0")/lib.sh"
DIR=${1:-$HOME/infra}
need_cluster
[ ! -e "$DIR" ] || die "$DIR already exists. Pick another folder, or delete it first (rm -rf $DIR)."
kubectl -n cicd get deploy/gitea >/dev/null 2>&1 && kubectl -n cicd get sts/jenkins >/dev/null 2>&1 \
  || die "the pipeline needs Jenkins and the Git server. Install the platform first: ./cicd-observability/scripts/k8s-up.sh"
kubectl get ns tfstate >/dev/null 2>&1 || die "run ./cloud-native-ops/projects/infra-factory/scripts/up.sh first (it creates the state store and the runner's permissions)"

say "Opening the doors (Git server localhost:3001)"
"$COURSE_ROOT/cicd-observability/scripts/forward.sh" start >/dev/null 2>&1 || true
for _ in $(seq 1 30); do curl -sf -o /dev/null http://localhost:3001/api/healthz && break; sleep 2; done
curl -sf -o /dev/null http://localhost:3001/api/healthz || die "cannot reach the Git server on localhost:3001. Run: ./cicd-observability/scripts/forward.sh start"

say "Building your repository in $DIR"
mkdir -p "$DIR"
cp -r "$REPO/." "$DIR/"
rm -rf "$DIR"/.terraform-* "$DIR"/.plans
mkdir -p "$DIR/chart"; cp -r "$COURSE_ROOT/cicd-observability/k8s/chart/chai-stall" "$DIR/chart/chai-stall"
cd "$DIR"
git init -q -b main
git config user.name  "$(git config --global user.name  2>/dev/null || echo 'Chai Dev')"
git config user.email "$(git config --global user.email 2>/dev/null || echo 'dev@stall.local')"
git add -A && git commit -qm "Initial commit: the Chai Stall's infrastructure as code"

API=http://localhost:3001/api/v1
say "Creating the repository on the Git server"
curl -s -u "$GITEA_USER:$GITEA_PASSWORD" -H 'Content-Type: application/json' -d '{"name":"infra","default_branch":"main","private":false}' "$API/user/repos" >/dev/null || true
curl -s -u "$GITEA_USER:$GITEA_PASSWORD" "$API/repos/$GITEA_USER/infra" | grep -q '"name":"infra"' || die "could not create the repository on the Git server"
git remote add origin "http://$GITEA_USER:$GITEA_PASSWORD@localhost:3001/$GITEA_USER/infra.git"
if ! out=$(git push -q -u --force origin main 2>&1); then echo "$out" >&2; die "could not push to the Git server. Is the port-forward alive? ./cicd-observability/scripts/forward.sh status"; fi

say "Creating the Jenkins job 'infra-terraform' (a pipeline that reads the Jenkinsfile from your repository)"
XML=$(cat <<'XML'
<flow-definition plugin="workflow-job">
  <description>Terraform: fmt + validate, plan, policy check, approval, apply, verify. Reads the Jenkinsfile of the "infra" repository.</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps">
    <scm class="hudson.plugins.git.GitSCM" plugin="git">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>http://gitea.cicd.svc.cluster.local:3000/z2h/infra.git</url>
          <credentialsId>gitea</credentialsId>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches><hudson.plugins.git.BranchSpec><name>*/main</name></hudson.plugins.git.BranchSpec></branches>
      <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
      <submoduleCfg class="empty-list"/>
      <extensions/>
    </scm>
    <scriptPath>Jenkinsfile</scriptPath>
    <lightweight>false</lightweight>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
XML
)
for _ in $(seq 1 40); do jenkins_api GET "api/json" 2>/dev/null | grep -q '"jobs"' && break; sleep 3; done
code=$(jenkins_api POST "createItem?name=infra-terraform" -H 'Content-Type: application/xml' --data-binary "$XML" -o /dev/null -w '%{http_code}')
case "$code" in
  200) : ;;
  400) jenkins_api GET "job/infra-terraform/api/json" 2>/dev/null | grep -q '"name":"infra-terraform"' || die "Jenkins refused the job (HTTP 400)" ;;   # already exists: fine
  *)   die "Jenkins answered HTTP $code when creating the job. Open http://localhost:8081 (admin / $JENKINS_ADMIN_PASSWORD)" ;;
esac
# The first run only teaches Jenkins the parameters, so the "Build with Parameters" button appears.
jenkins_api POST "job/infra-terraform/build" >/dev/null 2>&1 || true

ok "Your infrastructure repository is ready:  cd $DIR"
cat <<MSG

  Git server   http://localhost:3001/$GITEA_USER/infra            (login $GITEA_USER / $GITEA_PASSWORD)
  Jenkins      http://localhost:8081/job/infra-terraform          (login admin / $JENKINS_ADMIN_PASSWORD)
               wait for the first run to finish (it only registers the parameters), then "Build with Parameters".
MSG
