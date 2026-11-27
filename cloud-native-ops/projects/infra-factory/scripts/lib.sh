# Helpers for the infra-factory scripts. Source it:  . "$(dirname "$0")/lib.sh"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/../../../cicd-observability/scripts/k8s-lib.sh"
REPO="$HERE/infra-repo"
export HELM_DRIVER=configmap        # the Terraform runner keeps Helm's release records in ConfigMaps (see providers.tf)
ENVS="dev staging prod"
ns_of() { echo "iac-$1"; }
