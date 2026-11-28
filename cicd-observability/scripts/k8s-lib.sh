# Shared helpers for the Kubernetes scripts. Source it:  . "$(dirname "$0")/k8s-lib.sh"
# Tools we install for you without sudo (terraform) live in ~/.local/bin. A new shell may not have that folder on its PATH yet:
# every script adds it for itself, so "installed but not found" can never happen.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac; export PATH
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/progress.sh"      # progress_while: long waits report progress
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
# keep_off_control_plane: kubeadm's own rule is "workloads never run on the control plane" (a NoSchedule taint). Many labs
# (Killercoda, iximuz) remove it, and then a 2 GB control-plane node that also hosts Prometheus runs out of memory:
# kube-controller-manager and kube-scheduler crash-loop and the API server stops answering. So, on a cluster that HAS a worker node:
#   1. put the standard NoSchedule taint back on the control-plane node (system Pods and DaemonSets tolerate it);
#   2. move OUR Pods (monitoring, observability, cicd, mail, stall-*, iac-*, chai-*, tfstate) that already sit there to a worker.
# If the workers are full, our Pods stay Pending: visible and harmless, instead of a frozen cluster.
# Only small (< 4 GiB) control planes on multi-node clusters are touched; single-node and big clusters are left alone. Opt out: KEEP_CONTROL_PLANE_AS_IS=1. Undo: kubectl taint nodes NODE node-role.kubernetes.io/control-plane:NoSchedule-
keep_off_control_plane() {
  local cps workers n taints mem
  cps=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o name 2>/dev/null | sed 's|^node/||' || true)
  [ -n "$cps" ] || return 0
  workers=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' --no-headers 2>/dev/null | grep -c ' Ready' || true)
  [ "${workers:-0}" -ge 1 ] || return 0
  [ "${KEEP_CONTROL_PLANE_AS_IS:-0}" = 1 ] && return 0          # opt out: leave my cluster exactly as it is
  for n in $cps; do
    # Only a SMALL control plane needs protecting (under 4 GiB). Big ones are the owner's choice: never touch them.
    mem=$(kubectl get node "$n" -o jsonpath='{.status.allocatable.memory}' 2>/dev/null || true)
    case "$mem" in
      *Ki) [ "${mem%Ki}" -ge 4194304 ] 2>/dev/null && continue ;;
      *Mi) [ "${mem%Mi}" -ge 4096 ] 2>/dev/null && continue ;;
      *Gi) [ "${mem%Gi}" -ge 4 ] 2>/dev/null && continue ;;
    esac
    taints=$(kubectl get node "$n" -o jsonpath='{range .spec.taints[*]}{.key}={.effect}{"\n"}{end}' 2>/dev/null || true)
    if ! echo "$taints" | grep -q '^node-role.kubernetes.io/control-plane=NoSchedule$'; then
      kubectl taint node "$n" node-role.kubernetes.io/control-plane:PreferNoSchedule- >/dev/null 2>&1 || true   # drop an older soft taint
      if kubectl taint node "$n" node-role.kubernetes.io/control-plane=:NoSchedule --overwrite >/dev/null 2>&1; then
        warn "control-plane node $n had no taint, so heavy Pods could land on it and starve the cluster. Restored the standard one (undo: kubectl taint nodes $n node-role.kubernetes.io/control-plane:NoSchedule-)"
      fi
    fi
    # Move our Pods that already sit on the control plane (controller-owned, no volumes pinned to this node) to a worker.
    kubectl get pods -A -o json --field-selector "spec.nodeName=$n" 2>/dev/null | python3 -c '
import json, re, sys
ours = re.compile(r"^(monitoring|observability|cicd|mail|tfstate|stall-.*|iac-.*|chai-.*)$")
for p in json.load(sys.stdin).get("items", []):
    m, sp = p["metadata"], p["spec"]
    owners = [o["kind"] for o in m.get("ownerReferences", [])]
    if not ours.match(m["namespace"]) or not owners or "DaemonSet" in owners or "Node" in owners: continue
    if any("persistentVolumeClaim" in v for v in sp.get("volumes", [])): continue
    print(m["namespace"], m["name"])
' 2>/dev/null | while read -r ns pod; do
      kubectl -n "$ns" delete pod "$pod" --wait=false >/dev/null 2>&1 && warn "moving $ns/$pod off the control plane node"
    done || true
  done
}

# need_memory MIB WHAT [NAMESPACE]: compare the free memory on the nodes that may run our Pods with what the project normally wants.
# These are DEMO labs: a shortfall is a WARNING and the install goes on (the control plane is protected by keep_off_control_plane,
# so a squeezed worker means slow or Pending Pods, never a frozen API server). Want the old hard stop?  STRICT_MEMORY_CHECK=1
# Skipped when NAMESPACE already exists (a re-run) or SKIP_MEMORY_CHECK=1.
# mem_report → "FREE_MIB|node1 N MiB free of M; ..." for the nodes that may run our Pods (Ready, not NoSchedule). Never fails.
mem_report() {
  { kubectl get nodes -o json 2>/dev/null; echo '@@'; kubectl top nodes --no-headers 2>/dev/null || true; echo '@@'; kubectl get pods -A -o json 2>/dev/null; } | python3 -c '
import json, re, sys
nodes_j, top_t, pods_j = sys.stdin.read().split("@@\n")
if not nodes_j.strip(): sys.exit(0)
def mib(q):
    m = re.match(r"^([0-9.]+)([A-Za-z]*)$", str(q))
    if not m: return 0.0
    v, u = float(m.group(1)), m.group(2)
    return v * {"": 1/1048576, "Ki": 1/1024, "Mi": 1, "Gi": 1024, "Ti": 1048576, "k": 1000/1048576, "M": 1000000/1048576, "G": 1e9/1048576}.get(u, 0)
nodes = json.loads(nodes_j)["items"]
used = {}
for l in top_t.splitlines():
    f = l.split()
    if len(f) >= 5: used[f[0]] = mib(f[3])
req = {}
try:
    for p in json.loads(pods_j)["items"]:
        n = p["spec"].get("nodeName")
        if not n or p["status"].get("phase") in ("Succeeded", "Failed"): continue
        req[n] = req.get(n, 0) + sum(mib(c.get("resources", {}).get("requests", {}).get("memory", "0")) for c in p["spec"]["containers"])
except Exception: pass
free, rows = 0.0, []
for n in nodes:
    name = n["metadata"]["name"]
    ready = any(c["type"] == "Ready" and c["status"] == "True" for c in n["status"].get("conditions", []))
    blocked = any(t.get("effect") == "NoSchedule" for t in n["spec"].get("taints", [])) or n["spec"].get("unschedulable")
    if not ready or blocked: continue
    alloc = mib(n["status"]["allocatable"]["memory"])
    f = alloc - (used[name] if name in used else req.get(name, 0))
    free += max(f, 0); rows.append("%s %d MiB free of %d" % (name, max(f, 0), alloc))
print("%d|%s" % (free, "; ".join(rows)))
' 2>/dev/null || true
}
# small_lab → success if this cluster is SMALL (under ~2.6 GB free for us), so projects pick their smaller demo sizes.
# Force either way: SMALL_LAB=1 or SMALL_LAB=0.
small_lab() {
  case "${SMALL_LAB:-auto}" in 1) return 0 ;; 0) return 1 ;; esac
  local free; free=$(mem_report | cut -d'|' -f1)
  [ -n "$free" ] && [ "$free" -lt 2600 ] 2>/dev/null
}

need_memory() {
  [ "${SKIP_MEMORY_CHECK:-0}" = 1 ] && return 0
  if [ -n "${3:-}" ] && kubectl get ns "$3" >/dev/null 2>&1; then return 0; fi
  local out rc=0
  out=$(mem_report)
  [ -z "$out" ] || [ "${out%%|*}" -ge "$1" ] 2>/dev/null || rc=1
  [ "$rc" -ne 0 ] || return 0
  if [ "${STRICT_MEMORY_CHECK:-0}" = 1 ]; then
    printf '\033[1;31m✖ this cluster is too small for %s right now.\033[0m\n' "${2:-this project}" >&2
    echo "  Needs about $1 MiB free; the cluster has: ${out#*|}  (${out%%|*} MiB in total). Remove other projects (their cleanup.sh) or use a bigger cluster." >&2
    exit 1
  fi
  warn "DEMO MODE: ${2:-this project} normally wants about $1 MiB free; this cluster has ${out%%|*} MiB (${out#*|}). Going on anyway: a lab is not production."
  warn "If a Pod stays Pending or restarts, memory is the reason: free some (cleanup.sh of another project) or use a bigger cluster. Strict mode: STRICT_MEMORY_CHECK=1"
  return 0
}

# wait_ns_settled NS...: a namespace that is still Terminating (a cleanup that has not finished) cannot receive anything new:
# "unable to create new content in namespace X because it is being terminated". Wait for it, say what is going on, then stop clearly.
wait_ns_settled() {
  local n t=0 left
  while :; do
    left=""
    for n in "$@"; do
      [ "$(kubectl get ns "$n" -o jsonpath='{.status.phase}' 2>/dev/null || true)" = Terminating ] && left="$left $n"
    done
    [ -z "$left" ] && return 0
    [ "$t" -lt "${NS_WAIT:-300}" ] || break
    [ "$t" -gt 0 ] || warn "a previous removal is still finishing:$left. Waiting for it (up to ${NS_WAIT:-300} s) instead of failing."
    sleep 5; t=$((t+5)); [ $((t%30)) -ne 0 ] || printf '   ⏳ still deleting:%s (%s s so far)\n' "$left" "$t" >&2
  done
  for n in $left; do
    warn "$n is stuck deleting: $(kubectl get ns "$n" -o jsonpath='{range .status.conditions[*]}{.message}{"; "}{end}' 2>/dev/null | cut -c1-300)"
  done
  die "namespace(s)$left are still being deleted after ${NS_WAIT:-300} s. Look: kubectl get pods,pvc -n <namespace>  (a Pod or volume stuck Terminating blocks it). Then run this again."
}

# cluster_healthy: is the cluster's OWN brain working? If kube-controller-manager or kube-scheduler is crash-looping, Pods are never
# scheduled and ResourceQuotas are never computed, so every install "hangs" for a reason that has nothing to do with our scripts.
# The usual cause on a small lab VM is memory: the heavy monitoring stack landed on the control-plane node and starved it.
# (Managed clusters and k3s have no such Pods in kube-system: the loop finds nothing and passes.)
cluster_healthy() {
  local bad="" c ready mem
  keep_off_control_plane || true
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
