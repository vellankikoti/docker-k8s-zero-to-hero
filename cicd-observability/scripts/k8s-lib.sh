# Shared helpers for the Kubernetes scripts. Source it:  . "$(dirname "$0")/k8s-lib.sh"
# Tools we install for you without sudo (terraform) live in ~/.local/bin. A new shell may not have that folder on its PATH yet:
# every script adds it for itself, so "installed but not found" can never happen.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac; export PATH
say()  { printf '\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m• %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m✖ %s\033[0m\n' "$*" >&2; exit 1; }

K8S_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../k8s" && pwd)"
COURSE_ROOT="$(cd "$K8S_DIR/../.." && pwd)"
# The tag of the Chai Stall image that ensure-image.sh builds for the labs (Terraform's variable image_tag must match: selftest checks).
# It is NOT 1.0.x on purpose: the Ship It pipeline publishes 1.0.<build number>, and two different images must never share a tag
# (nodes keep an image they already have under that tag and never look again).
export CHAI_IMAGE_TAG=${CHAI_IMAGE_TAG:-1.5.0}
JENKINS_ADMIN_PASSWORD=${JENKINS_ADMIN_PASSWORD:-z2h-jenkins}
GITEA_USER=z2h
GITEA_PASSWORD=z2h-gitea-pass

need_cluster() {
  command -v kubectl >/dev/null 2>&1 || die "kubectl is not installed. See 00-setup/README.md"
  kubectl get --raw /readyz >/dev/null 2>&1 || die "Can't reach a cluster. Check: kubectl config current-context"
}
# cluster_healthy: is the cluster's OWN brain working? If kube-controller-manager or kube-scheduler is crash-looping, Pods are never
# scheduled and ResourceQuotas are never computed, so every install "hangs" for a reason that has nothing to do with our scripts.
# The usual cause on a small lab VM is memory: the heavy monitoring stack landed on the control-plane node and starved it.
# (Managed clusters and k3s have no such Pods in kube-system: the loop finds nothing and passes.)
cluster_healthy() {
  local bad="" c ready mem
  for c in kube-controller-manager kube-scheduler; do
    ready=$(kubectl -n kube-system get pods -l "component=$c" -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null || true)
    [ -z "$ready" ] && continue
    echo "$ready" | grep -q true || bad="$bad $c"
  done
  if [ -n "$bad" ]; then
    printf '\033[1;31m✖ the cluster'"'"'s own control plane is unhealthy:%s is not Ready.\033[0m\n' "$bad" >&2
    cat >&2 <<MSG
  Nothing can work properly until it recovers: Pods are not scheduled and quotas are not computed, so installs would hang.
  Look:     kubectl -n kube-system get pods ; kubectl top nodes
  Usual cause: the control-plane node ran out of memory (heavy Pods were placed on it). Free memory, then wait until those Pods are Running:
     • remove the biggest tenant:   ./cicd-observability/projects/see-everything/scripts/cleanup.sh -y
     • on a lab with a worker node, keep new workloads off the control plane:
         kubectl taint nodes <control-plane-node-name> node-role.kubernetes.io/control-plane=:NoSchedule
     • then:  kubectl -n kube-system get pods -w     (Ctrl+C when kube-controller-manager and kube-scheduler show 1/1 Running)
MSG
    exit 1
  fi
  # (kubectl top fails on a cluster without metrics-server: that is normal here, and under "set -e" must never end the script)
  mem=$(kubectl top nodes --no-headers 2>/dev/null | awk '{p=$5; gsub("%","",p); if (p+0 >= 90) printf "%s (%s memory) ", $1, $5}' || true)
  [ -z "$mem" ] || warn "these nodes are almost out of memory: $mem. If an install hangs, free memory first (see-everything/scripts/cleanup.sh)."
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
