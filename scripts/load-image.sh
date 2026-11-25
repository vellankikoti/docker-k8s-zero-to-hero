#!/usr/bin/env bash
# Make locally built images available to the Kubernetes cluster in your current kubectl context.
#
#   ./scripts/load-image.sh z2h/api:1.0 z2h/frontend:1.0
#
# Supports:
#   - Docker Desktop (kubeadm mode: images are already shared; kind mode: imported into each node)
#   - kind           (kind load docker-image)
#   - minikube       (minikube image load)
#   - any cluster whose nodes are local Docker containers
#   - Killercoda / kubeadm VMs: imports into containerd on this node via ctr, then on every other
#     node over ssh (Killercoda's controlplane can ssh to node01 without a password)
set -euo pipefail

if [ $# -eq 0 ]; then
  echo "usage: $0 IMAGE [IMAGE...]   e.g. $0 z2h/api:1.0 z2h/frontend:1.0"
  exit 1
fi

say() { printf '\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m✖ %s\033[0m\n' "$*"; exit 1; }

CTX="$(kubectl config current-context 2>/dev/null || true)"
[ -n "$CTX" ] || die "kubectl has no current context. Is a cluster running?"
say "kubectl context: $CTX"

for img in "$@"; do
  command -v docker >/dev/null && docker image inspect "$img" >/dev/null 2>&1 \
    || [ "$CTX" = "kubernetes-admin@kubernetes" ] \
    || die "Image $img not found locally. Build it first, e.g. docker build -t $img apps/api"
done

NODES="$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')"

# Import an image into every node that is a local Docker container (kind, Docker Desktop kind mode).
import_into_node_containers() {
  local img=$1 imported=0
  for node in $NODES; do
    if docker inspect "$node" >/dev/null 2>&1; then
      say "importing $img into node container $node"
      docker save "$img" | docker exec -i "$node" ctr -n k8s.io images import --all-platforms - >/dev/null
      imported=1
    fi
  done
  return $((1 - imported))
}

for img in "$@"; do
  case "$CTX" in
    docker-desktop)
      if [ "$NODES" = "docker-desktop" ]; then
        ok "$img: Docker Desktop (kubeadm) shares the Docker image store, nothing to do"
      else
        import_into_node_containers "$img" || die "could not find Docker Desktop node containers"
        ok "$img loaded into Docker Desktop (kind mode)"
      fi
      ;;
    kind-*)
      kind load docker-image "$img" --name "${CTX#kind-}"
      ok "$img loaded into kind cluster ${CTX#kind-}"
      ;;
    minikube)
      minikube image load "$img"
      ok "$img loaded into minikube"
      ;;
    *)
      if command -v docker >/dev/null && import_into_node_containers "$img" 2>/dev/null; then
        ok "$img loaded into node containers"
      elif command -v ctr >/dev/null; then
        # e.g. Killercoda / kubeadm VMs where you are root on the node.
        # A Pod can land on ANY node, so the image must be in containerd on every one of them.
        tarball="$(mktemp "${TMPDIR:-/tmp}/z2h-image.XXXXXX")"
        if command -v docker >/dev/null && docker image inspect "$img" >/dev/null 2>&1; then
          docker save "$img" -o "$tarball"
        elif ctr -n k8s.io images ls -q | grep -qE "(^|/)${img}\$"; then
          ctr -n k8s.io images export "$tarball" "$(ctr -n k8s.io images ls -q | grep -E "(^|/)${img}\$" | head -1)"
        else
          rm -f "$tarball"
          die "No local image $img to import. Build it on this node first (see 00-setup, Killercoda section)."
        fi
        ctr -n k8s.io images import "$tarball" >/dev/null
        ok "$img imported into containerd on $(hostname)"
        missed=""
        for node in $NODES; do
          [ "$node" = "$(hostname)" ] && continue
          if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$node" true 2>/dev/null; then
            say "copying $img to $node over ssh"
            ssh -o BatchMode=yes "$node" 'ctr -n k8s.io images import -' < "$tarball" >/dev/null
            ok "$img imported into containerd on $node"
          else
            missed="$missed $node"
          fi
        done
        rm -f "$tarball"
        if [ -n "$missed" ]; then
          printf '\033[1;33m! could not reach%s over ssh: Pods scheduled there will be stuck in ErrImagePull.\033[0m\n' "$missed"
          printf '  Copy it by hand:  docker save %s | ssh <node> ctr -n k8s.io images import -\n' "$img"
        fi
      else
        die "Unknown cluster type. Push $img to a registry the cluster can pull from (see Lab D10)."
      fi
      ;;
  esac
done
