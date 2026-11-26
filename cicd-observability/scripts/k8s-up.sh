#!/usr/bin/env bash
# k8s-up.sh: install the Unit 4 CI/CD platform on the cluster your kubectl points at. Safe to run again.
#
#   ./cicd-observability/scripts/k8s-up.sh               everything
#   ./cicd-observability/scripts/k8s-up.sh --no-gateway  skip Envoy Gateway (you cannot do blue/green or canary without it)
#
# Installs: namespaces (with Pod Security), RBAC, an image registry, a Git server (Gitea), a mail catcher, Jenkins (Helm),
# and the Gateway API controller + production Gateway.  Needs: kubectl, helm, ~3 GB free memory, internet for images.
set -euo pipefail
. "$(dirname "$0")/k8s-lib.sh"
CHART_VERSION="5.11.0"
WITH_GATEWAY=1; [ "${1:-}" = "--no-gateway" ] && WITH_GATEWAY=0

need_cluster; need_helm
say "Cluster: $(kubectl config current-context)"
kubectl get storageclass 2>/dev/null | grep -q '(default)' || warn "no default StorageClass: the registry and Git server volumes may stay Pending (Lab K10)"

say "Namespaces (with Pod Security) and permissions"
kubectl apply -f "$K8S_DIR/platform/00-namespaces.yaml" -f "$K8S_DIR/platform/rbac.yaml" >/dev/null

say "Mail catcher, image registry and Git server"
kubectl apply -f "$COURSE_ROOT/kubernetes/20-projects/mailpit.yaml" >/dev/null
kubectl apply -f "$K8S_DIR/platform/registry.yaml" -f "$K8S_DIR/platform/gitea.yaml" >/dev/null
kubectl -n cicd create secret generic jenkins-lab-secrets \
  --from-literal=deploy-token="s3cr3t-deploy-token-42" --from-literal=gitea-password="$GITEA_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n cicd rollout status deploy/registry --timeout=5m >/dev/null || die "the registry did not start. Look: kubectl -n cicd get pods ; kubectl -n cicd describe pod -l app=registry"
kubectl -n cicd rollout status deploy/gitea --timeout=5m >/dev/null || die "Gitea did not start. Look: kubectl -n cicd logs deploy/gitea"
kubectl -n mail rollout status deploy/mailpit --timeout=3m >/dev/null || warn "mailpit is not ready yet"

say "Creating the Git server's login ($GITEA_USER)"
out=$(kubectl -n cicd exec deploy/gitea -- gitea admin user create --username "$GITEA_USER" --password "$GITEA_PASSWORD" \
  --email "z2h@stall.local" --admin --must-change-password=false 2>&1 || true)
echo "$out" | grep -qE "successfully created|already exists" || warn "unexpected answer from Gitea: $out"

say "Installing Jenkins ${CHART_VERSION} (3 to 5 minutes the first time: it downloads plugins)"
helm repo add jenkins https://charts.jenkins.io >/dev/null 2>&1 || true
helm repo update jenkins >/dev/null
helm upgrade --install jenkins jenkins/jenkins --version "$CHART_VERSION" -n cicd \
  -f "$K8S_DIR/platform/jenkins-values.yaml" --wait --timeout 10m >/dev/null \
  || die "Jenkins did not finish installing. Look: kubectl -n cicd get pods ; kubectl -n cicd logs jenkins-0 -c jenkins | tail -30"

if [ "$WITH_GATEWAY" = 1 ]; then
  say "Gateway API controller (Envoy Gateway) and production's Gateway + HTTPRoute"
  "$COURSE_ROOT/scripts/install-gateway.sh"
  kubectl apply -f "$K8S_DIR/platform/prod-gateway.yaml" >/dev/null
fi

ok "Platform is up."
cat <<MSG

  Open the doors (one command, leaves port-forwards running in the background):
      ./cicd-observability/scripts/forward.sh start
  Then create YOUR copy of the app and push it to the in-cluster Git server:
      ./cicd-observability/scripts/new-app-repo.sh
  Check everything:   kubectl get pods -A | grep -vE 'Running|Completed'     (nothing should be listed)
MSG
