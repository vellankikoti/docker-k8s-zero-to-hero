#!/usr/bin/env bash
# iac-test.sh: a maintainer's end-to-end test of the infra-factory against YOUR cluster (a throwaway one). About 3 minutes.
#   ./cloud-native-ops/projects/infra-factory/tests/iac-test.sh
# It runs the REAL Terraform against the REAL API server, as the pipeline's ServiceAccount (so the RBAC is tested too), but
# does not wait for Pods (TF_VAR_wait_for_pods=false), so it works on a cluster whose nodes cannot start containers.
# Needs: kubectl, terraform, docker (for conftest), python3. Refuses to run unless you type the cluster's context name.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/scripts/lib.sh"
REPO="$HERE/infra-repo"
need_cluster
command -v terraform >/dev/null || die "terraform is not installed ($REPO/scripts/install-terraform.sh)"
if [ "${IAC_TEST_OK:-}" != "$(kubectl config current-context)" ]; then
  die "this test creates and destroys namespaces iac-dev/iac-prod. Re-run with:  IAC_TEST_OK=$(kubectl config current-context) $0"
fi
export TF_VAR_wait_for_pods=false
pass=0; fail=0
t() { local label=$1; shift; if "$@" >/tmp/iac-test.out 2>&1; then printf '  \033[1;32m✔\033[0m %s\n' "$label"; pass=$((pass+1)); else printf '  \033[1;31m✖\033[0m %s\n' "$label"; sed 's/^/      /' /tmp/iac-test.out | tail -8; fail=$((fail+1)); fi; }
not() { ! "$@"; }
CT=(docker run --rm -v "$REPO":/p -w /p openpolicyagent/conftest:v0.62.0)
tf() { "$REPO/scripts/tf.sh" "$@"; }

say "platform"
"$HERE/scripts/cleanup.sh" -y >/dev/null 2>&1
kubectl apply -f "$HERE/platform/00-tfstate-and-runner.yaml" >/dev/null || die "cannot create the state store"
kubectl get ns cicd >/dev/null 2>&1 || kubectl create ns cicd >/dev/null
kubectl apply -f "$HERE/platform/00-tfstate-and-runner.yaml" >/dev/null

say "as the pipeline's ServiceAccount"
SA=$(mktemp -d); kubectl -n cicd create token terraform-runner --duration=1h > "$SA/token"
kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > "$SA/ca.crt" 2>/dev/null
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
[ -s "$SA/ca.crt" ] || { warn "this kubeconfig has no embedded CA: running as your own user instead of the ServiceAccount"; RUNNER=""; }
if [ -s "$SA/ca.crt" ]; then SA_DIR="$SA" API_SERVER="$SERVER" sh "$REPO/scripts/mk-kubeconfig.sh" "$SA/kubeconfig" >/dev/null && export KUBECONFIG_PATH="$SA/kubeconfig"; fi

say "terraform"
t "fmt and validate" tf dev check
t "plan dev" tf dev plan
t "policy passes on a good plan" "${CT[@]}" test --policy policy .plans/dev.json
t "policy unit tests pass" "${CT[@]}" verify --policy policy
t "apply dev" tf dev apply
t "the state is a Secret with a lock Lease" bash -c "kubectl -n tfstate get secret tfstate-default-iac-dev && kubectl -n tfstate get lease lock-tfstate-default-iac-dev"
t "no drift right after apply" tf dev drift
kubectl -n iac-dev patch resourcequota environment-budget --type=merge -p '{"spec":{"hard":{"pods":"60"}}}' >/dev/null
t "a hand-edit is detected (exit 2)" bash -c "'$REPO/scripts/tf.sh' dev drift; [ \$? -eq 2 ]"
t "re-apply removes the hand-edit" bash -c "'$REPO/scripts/tf.sh' dev plan && '$REPO/scripts/tf.sh' dev apply && '$REPO/scripts/tf.sh' dev drift"
printf 'replicas = 1\nautoscaling = { enabled = true, min = 2, max = 20, cpu = 70 }\n' > /tmp/iac-bad.tfvars
EXTRA_VAR_FILE=/tmp/iac-bad.tfvars tf prod plan >/dev/null 2>&1
t "policy REFUSES a 1-replica prod with a runaway autoscaler" not "${CT[@]}" test --policy policy .plans/prod.json
TF_VAR_image_tag=latest tf dev plan >/dev/null 2>&1
t "policy REFUSES the image tag 'latest'" not "${CT[@]}" test --policy policy .plans/dev.json
t "plan + apply prod" bash -c "'$REPO/scripts/tf.sh' prod plan && '$REPO/scripts/tf.sh' prod apply"
t "prod has an autoscaler and a PodDisruptionBudget" kubectl -n iac-prod get hpa/chai-stall pdb/chai-stall
t "the runner cannot touch nodes" not kubectl auth can-i delete nodes --as=system:serviceaccount:cicd:terraform-runner
t "destroy dev and prod" bash -c "'$REPO/scripts/tf.sh' dev destroy && '$REPO/scripts/tf.sh' prod destroy"
t "nothing is left behind" not bash -c "kubectl get ns iac-dev iac-prod 2>/dev/null | grep -q iac"
unset KUBECONFIG_PATH
"$HERE/scripts/cleanup.sh" -y >/dev/null 2>&1
rm -rf "$SA" /tmp/iac-bad.tfvars
echo; printf '\033[1m%d passed, %d failed\033[0m\n' "$pass" "$fail"; exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
