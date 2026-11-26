#!/usr/bin/env bash
# doctor.sh: "am I ready for Unit 4?" Run it from anywhere, before you start.
#   ./cicd-observability/scripts/doctor.sh          Docker Compose edition
#   ./cicd-observability/scripts/doctor.sh --k8s    Kubernetes edition (checks kubectl, helm, your cluster)
set -uo pipefail
MODE=docker; [ "${1:-}" = "--k8s" ] && MODE=k8s
pass=0; fail=0; warn=0
ok()   { printf '  \033[1;32m✔\033[0m %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf '  \033[1;31m✖\033[0m %s\n' "$*"; fail=$((fail+1)); }
note() { printf '  \033[1;33m•\033[0m %s\n' "$*"; warn=$((warn+1)); }
h()    { printf '\n\033[1m%s\033[0m\n' "$*"; }
HERE="$(cd "$(dirname "$0")/.." && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"

if [ "$MODE" = k8s ]; then
  h "Kubernetes tools"
  command -v kubectl >/dev/null && ok "kubectl: $(kubectl version --client 2>/dev/null | head -1)" || bad "kubectl is not installed: see 00-setup/README.md"
  command -v helm >/dev/null && ok "helm: $(helm version --short 2>/dev/null)" || bad "helm is not installed. macOS: brew install helm · Windows: winget install Helm.Helm · Linux: https://helm.sh/docs/intro/install/"
  command -v git >/dev/null && ok "git: $(git --version | cut -d' ' -f3)" || bad "git is not installed"
  command -v curl >/dev/null && ok "curl" || bad "curl is not installed"
  h "Your cluster"
  if kubectl get --raw /readyz >/dev/null 2>&1; then
    ok "can reach the cluster (context: $(kubectl config current-context))"
    nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    notready=$(kubectl get nodes --no-headers 2>/dev/null | grep -vc ' Ready' || true)
    if [ "${nodes:-0}" -eq 0 ]; then bad "the cluster has no nodes: kubectl get nodes"
    elif [ "${notready:-0}" -eq 0 ]; then ok "all $nodes node(s) Ready"
    else bad "$notready of $nodes node(s) not Ready: kubectl get nodes"; fi
    kubectl get storageclass 2>/dev/null | grep -q '(default)' && ok "a default StorageClass exists (the registry and Git server need volumes, Lab K10)" || note "no default StorageClass (common on kubeadm labs). k8s-up.sh will use plain Pod storage (emptyDir) for the registry and Git server: fine for a lab, but images/repos are lost if those Pods restart (Scenario S4.3 explains PVCs)"
    case "$(kubectl config current-context)" in
      kind-*|docker-desktop|minikube|*killercoda*|*kubernetes-admin*) ok "the context looks like a course/lab cluster" ;;
      *) note "context '$(kubectl config current-context)' does not look like a throwaway lab cluster: make sure it is YOURS and safe to experiment on" ;;
    esac
    kubectl top nodes >/dev/null 2>&1 && ok "metrics-server works (kubectl top)" || note "metrics-server is not installed: only needed for autoscaling and Project 2 (./scripts/install-metrics-server.sh)"
  else
    bad "cannot reach a cluster. Start one (00-setup) and check: kubectl config current-context"
  fi
  h "Free ports on your laptop (for the port-forwards)"
  used() { (command -v ss >/dev/null && ss -ltn 2>/dev/null | grep -q ":$1 ") || (command -v lsof >/dev/null && lsof -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1); }
  for spec in 8081:Jenkins 3001:Git-server 8025:inbox 8082:staging 8090:production 3000:Grafana 9090:Prometheus 9093:Alertmanager 16686:Jaeger; do
    p=${spec%%:*}; n=${spec##*:}
    if used "$p"; then note "port $p ($n) is in use: fine if it is a port-forward from this lab (./cicd-observability/scripts/forward.sh status)"; else ok "port $p free ($n)"; fi
  done
  printf '\n\033[1m%d passed, %d warnings, %d problems\033[0m\n' "$pass" "$warn" "$fail"
  [ "$fail" -eq 0 ] && echo "You are ready. Next: ./cicd-observability/scripts/k8s-up.sh" || echo "Fix the ✖ lines above, then run this again."
  exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
fi

h "Tools"
command -v docker >/dev/null && ok "docker: $(docker --version | cut -d, -f1)" || bad "docker is not installed: see 00-setup/README.md"
docker info >/dev/null 2>&1 && ok "the Docker engine is running" || bad "the Docker engine is not running: start Docker Desktop (or: sudo systemctl start docker)"
if docker compose version >/dev/null 2>&1; then
  cv=$(docker compose version --short | sed 's/^v//'); maj=${cv%%.*}; rest=${cv#*.}; min=${rest%%.*}
  if [ "$maj" -gt 2 ] || { [ "$maj" -eq 2 ] && [ "$min" -ge 24 ]; }; then ok "docker compose: $cv"; else bad "docker compose $cv is too old: Project 1 needs 2.24 or newer. Update Docker Desktop (or the compose plugin)"; fi
else bad "the 'docker compose' plugin is missing"; fi
command -v git >/dev/null && ok "git: $(git --version | cut -d' ' -f3)" || bad "git is not installed"
command -v python3 >/dev/null && ok "python3: $(python3 --version | cut -d' ' -f2) (only needed to run the app's tests outside Docker)" || note "python3 not found: fine, you can run everything in containers"
command -v curl >/dev/null && ok "curl" || bad "curl is not installed"

h "Your clone of the repository"
if [ "$(git -C "$ROOT" rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then
  bad "your clone is shallow (cloned with --depth). Jenkins cannot build from it. Fix: git fetch --unshallow"
else ok "full clone (not shallow)"; fi
[ -n "$(git -C "$ROOT" branch --show-current 2>/dev/null)" ] && ok "on branch: $(git -C "$ROOT" branch --show-current) (Jenkins builds the branch named in project-1-ship-it/.env, default main)" || note "detached HEAD"

h "Free ports (a '✖' means something else is already using it)"
used() { (command -v ss >/dev/null && ss -ltn 2>/dev/null | grep -q ":$1 ") || (command -v lsof >/dev/null && lsof -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1); }
for spec in 8080:Jenkins 5001:registry 8081:staging 8090:production-router 3000:Grafana 9090:Prometheus 9093:Alertmanager 8025:inbox 16686:Jaeger 3100:Loki 8091:chai-1 8092:chai-2; do
  p=${spec%%:*}; n=${spec##*:}
  if used "$p"; then
    if docker ps --format '{{.Ports}}' 2>/dev/null | grep -q ":$p->"; then note "port $p ($n) is used by one of your running containers: fine if it is this lab's"
    else bad "port $p ($n) is already in use by another program"; fi
  else ok "port $p free ($n)"; fi
done

h "Memory"
if [ -r /proc/meminfo ]; then
  mb=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo)
  [ "$mb" -ge 6000 ] && ok "${mb} MB of RAM" || note "${mb} MB of RAM: Project 1 needs about 2 GB and Project 2 about 2 GB. Run them one at a time."
else
  d=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0); mb=$((d/1024/1024))
  [ "$mb" -ge 6000 ] && ok "Docker has ${mb} MB" || note "Docker has ${mb} MB: raise it in Docker Desktop -> Settings -> Resources, or run the projects one at a time"
fi

printf '\n\033[1m%d passed, %d warnings, %d problems\033[0m\n' "$pass" "$warn" "$fail"
[ "$fail" -eq 0 ] && echo "You are ready. Start with cicd-observability/README.md" || echo "Fix the ✖ lines above, then run this again."
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
