#!/usr/bin/env bash
# Install Jenkins on your cluster with Helm, ready to build and deploy into the same cluster.
# Lab K20 uses it. Safe to run again: it upgrades in place.
#
#   ./scripts/install-jenkins.sh
#
# Needs: kubectl, helm, about 1.5 GB of free memory. The first start downloads plugins: 3 to 5 minutes.
set -euo pipefail

CHART_VERSION="5.11.0"            # one place to change when you want a newer release
HERE="$(cd "$(dirname "$0")" && pwd)"
LAB="$HERE/../kubernetes/20-projects"

say()  { printf '\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m✖ %s\033[0m\n' "$*"; exit 1; }

command -v kubectl >/dev/null 2>&1 || die "kubectl isn't installed. See 00-setup."
kubectl get --raw /readyz >/dev/null 2>&1 || die "Can't reach a cluster. Check: kubectl config current-context"
command -v helm >/dev/null 2>&1 || die "helm isn't installed. macOS: brew install helm · Windows: winget install Helm.Helm · Linux: https://helm.sh/docs/intro/install/"

say "Creating the mail catcher, the namespaces and the deployer permissions"
kubectl apply -f "$LAB/mailpit.yaml" >/dev/null
kubectl apply -f "$LAB/rbac.yaml" >/dev/null

say "Adding the Jenkins chart repository"
_i=0; until curl -fsS -m 30 -o /dev/null https://charts.jenkins.io/index.yaml 2>/tmp/z2h-chart.err; do
  _i=$((_i+1)); [ "$_i" -lt 3 ] || die "cannot reach https://charts.jenkins.io (the Jenkins chart). This lab blocks it or has no internet: $(tail -1 /tmp/z2h-chart.err). Try again in a minute, or use another lab/cluster."
  sleep 3
done

say "Installing Jenkins ${CHART_VERSION} into namespace jenkins (3 to 5 minutes the first time)"
helm upgrade --install jenkins jenkins --repo https://charts.jenkins.io --version "$CHART_VERSION" --namespace jenkins \
  -f "$LAB/jenkins-values.yml" --wait --timeout 10m >/dev/null \
  || die "The install did not finish. Look: kubectl get pods -n jenkins   and   kubectl logs -n jenkins statefulset/jenkins -c jenkins"

ok "Jenkins is running in namespace jenkins."
printf '   Open it:   kubectl port-forward -n jenkins svc/jenkins 8081:8080    then http://localhost:8081  (admin / z2h-jenkins)\n'
printf '   Inbox:     kubectl port-forward -n mail svc/mailpit 8025:8025          then http://localhost:8025\n'
