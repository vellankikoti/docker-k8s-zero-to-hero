# Helpers for the production-ready scripts. Source it:  . "$(dirname "$0")/lib.sh"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/../../../cicd-observability/scripts/k8s-lib.sh"
INFRA="$HERE/../infra-factory"
PROD_NS=iac-prod
export HELM_DRIVER=configmap
