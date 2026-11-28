#!/usr/bin/env bash
# k8s-down.sh: remove the CI/CD platform and everything the pipeline deployed. Asks first (-y to skip).
set -euo pipefail
. "$(dirname "$0")/k8s-lib.sh"
need_cluster; need_helm
if [ "${1:-}" != "-y" ]; then
  printf 'This deletes namespaces cicd, stall-staging, stall-prod (Jenkins, registry, Git server, all releases). Continue? [y/N] '
  read -r a; [ "$a" = y ] || [ "$a" = Y ] || exit 0
fi
"$(dirname "$0")/forward.sh" stop >/dev/null 2>&1 || true
for ns in stall-staging stall-prod; do
  for r in $(helm list -n "$ns" -q 2>/dev/null); do helm uninstall "$r" -n "$ns" >/dev/null 2>&1 || true; done
done
helm uninstall jenkins -n cicd >/dev/null 2>&1 || true
kubectl delete ns cicd stall-staging stall-prod --ignore-not-found --wait=false >/dev/null
# Wait until they are REALLY gone, so the next k8s-up.sh does not hit "namespace is being terminated".
say "Waiting for the namespaces to finish deleting (usually under a minute)"
NS_WAIT=${NS_WAIT:-300} wait_ns_settled cicd stall-staging stall-prod
ok "Removed. Envoy Gateway and the mail catcher are left in place:"
echo "   kubectl delete ns mail envoy-gateway-system   # if you want those gone too"
