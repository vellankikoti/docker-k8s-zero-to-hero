# Shared helpers for the Unit 4 Kubernetes scripts. Source it:  . "$(dirname "$0")/k8s-lib.sh"
say()  { printf '\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m• %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m✖ %s\033[0m\n' "$*" >&2; exit 1; }

K8S_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../k8s" && pwd)"
COURSE_ROOT="$(cd "$K8S_DIR/../.." && pwd)"
JENKINS_ADMIN_PASSWORD=${JENKINS_ADMIN_PASSWORD:-z2h-jenkins}
GITEA_USER=z2h
GITEA_PASSWORD=z2h-gitea-pass

need_cluster() {
  command -v kubectl >/dev/null 2>&1 || die "kubectl is not installed. See 00-setup/README.md"
  kubectl get --raw /readyz >/dev/null 2>&1 || die "Can't reach a cluster. Check: kubectl config current-context"
}
need_helm() {
  command -v helm >/dev/null 2>&1 || die "helm is not installed. macOS: brew install helm · Windows: winget install Helm.Helm · Linux: https://helm.sh/docs/intro/install/"
}

# Call the Jenkins API from INSIDE the Jenkins Pod (no port-forward needed).  jenkins_api METHOD PATH [curl args...]
# (The script runs under the Pod's plain `sh`, so it is POSIX: no bash-only syntax.)
jenkins_api() {
  local method=$1 path=$2; shift 2
  kubectl -n cicd exec jenkins-0 -c jenkins -- sh -c '
    PW=$1; M=$2; P=$3; shift 3
    J=http://localhost:8080; JAR=$(mktemp)
    CRUMB=$(curl -s -c "$JAR" -b "$JAR" -u "admin:$PW" "$J/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,%22:%22,//crumb)")
    curl -s -g -c "$JAR" -b "$JAR" -u "admin:$PW" -H "$CRUMB" -X "$M" "$J/$P" "$@"
    rm -f "$JAR"' sh "$JENKINS_ADMIN_PASSWORD" "$method" "$path" "$@"
}
