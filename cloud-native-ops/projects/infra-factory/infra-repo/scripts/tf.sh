#!/bin/sh
# tf.sh ENV ACTION: one entry point for Terraform, used by you AND by the pipeline, so both do exactly the same thing.
#
#   tf.sh dev plan          show what would change; save the plan to .plans/dev.tfplan (+ .json for the policy check)
#   tf.sh dev apply         apply THAT saved plan (what you reviewed is what runs). No saved plan? it refuses.
#   tf.sh dev drift         has someone changed things by hand? exit 0 = no, exit 2 = yes (and shows what)
#   tf.sh dev output        print the outputs
#   tf.sh dev destroy       remove everything this environment created
#   tf.sh dev check         terraform fmt -check + validate (no cluster needed)
#   tf.sh dev status        what does the state remember?
#   tf.sh dev policy        the inspector: check the saved plan against policy/ (after 'plan'). Uses conftest, or Docker if you have it
#   tf.sh dev policy-test   run the policy's own unit tests
#
# ENV is dev, staging or prod. Environment variables you may set:
#   EXTRA_VAR_FILE    one more .tfvars file for an experiment (it wins over envs/<env>.tfvars)
#   KUBECONFIG_PATH   which cluster (default: $KUBECONFIG or ~/.kube/config)
#   TF_VAR_*          any Terraform variable, e.g.  TF_VAR_image_tag=1.0.3  ./scripts/tf.sh dev plan
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ENV=${1:-}; ACTION=${2:-}
say()  { printf '\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m✖ %s\033[0m\n' "$*" >&2; exit 1; }
case "$ENV" in dev|staging|prod) ;; *) sed -n '2,17p' "$0"; die "ENV must be dev, staging or prod";; esac
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac; export PATH   # where install-terraform.sh puts it
case "$ACTION" in policy|policy-test) ;; *) command -v terraform >/dev/null 2>&1 || die "terraform is not installed. One command:  $HERE/scripts/install-terraform.sh";; esac

KC=${KUBECONFIG_PATH:-${KUBECONFIG:-$HOME/.kube/config}}
KC=${KC%%:*}                                                    # if KUBECONFIG lists several files, use the first
[ -f "$KC" ] || [ "$ACTION" = check ] || [ "$ACTION" = policy ] || [ "$ACTION" = policy-test ] || die "no kubeconfig at $KC. Point kubectl at your cluster first (kubectl get nodes must work)."

# The chart: your repo carries its own copy (chart/chai-stall); the course folder is the fallback.
if [ -d "$HERE/chart/chai-stall" ]; then CHART="$HERE/chart/chai-stall"
else CHART="$(cd "$HERE/../../../../cicd-observability/k8s/chart/chai-stall" 2>/dev/null && pwd)" || die "cannot find the Helm chart"; fi

export TF_DATA_DIR="$HERE/.terraform-$ENV"                      # one working copy per environment: switching never confuses the backend
export TF_IN_AUTOMATION=1
export TF_VAR_kubeconfig="$KC"
export TF_VAR_chart_path="$CHART"
PLANS="$HERE/.plans"; mkdir -p "$PLANS"
# Extra settings for an experiment, without editing the committed files:  EXTRA_VAR_FILE=/tmp/my.tfvars ./scripts/tf.sh dev plan
VARS="-var-file=envs/$ENV.tfvars"; [ -z "${EXTRA_VAR_FILE:-}" ] || VARS="$VARS -var-file=$EXTRA_VAR_FILE"
cd "$HERE/terraform"

init() {
  terraform init -input=false -no-color -reconfigure -backend-config="envs/$ENV.backend.hcl" -backend-config="config_path=$KC" >/dev/null \
    || { terraform init -input=false -no-color -reconfigure -backend-config="envs/$ENV.backend.hcl" -backend-config="config_path=$KC" | tail -20; die "terraform init failed (above). A 'namespaces \"tfstate\" not found' error means up.sh has not been run yet."; }
}

case "$ACTION" in
  check)
    terraform fmt -check -recursive -diff || die "formatting: run  terraform fmt -recursive  in $HERE/terraform"
    terraform init -input=false -backend=false -no-color >/dev/null
    terraform validate -no-color
    ok "formatted and valid" ;;
  plan)
    init; say "Plan for $ENV"
    terraform plan -input=false -no-color $VARS -out="$PLANS/$ENV.tfplan"
    terraform show -json "$PLANS/$ENV.tfplan" > "$PLANS/$ENV.json"
    chmod a+r "$PLANS/$ENV.tfplan" "$PLANS/$ENV.json" 2>/dev/null || true       # so the policy container can read it whatever your umask
    ok "plan saved: $PLANS/$ENV.tfplan  (next, the inspector:  $HERE/scripts/tf.sh $ENV policy)" ;;
  apply)
    [ -f "$PLANS/$ENV.tfplan" ] || die "no saved plan for $ENV. Run  tf.sh $ENV plan  first, read it, then apply: what you reviewed is what runs."
    init; say "Applying the saved plan for $ENV"
    terraform apply -input=false -no-color "$PLANS/$ENV.tfplan"
    rm -f "$PLANS/$ENV.tfplan" "$PLANS/$ENV.json"               # a plan is single-use: it describes the cluster as it was
    ok "applied" ;;
  drift)
    init; say "Is $ENV exactly as the code says? (plan -detailed-exitcode)"
    rc=0; terraform plan -input=false -no-color -detailed-exitcode $VARS || rc=$?
    case $rc in 0) ok "no drift: the cluster matches the code"; exit 0 ;;
                2) printf '\033[1;33m• DRIFT: someone changed the cluster by hand (or the code changed). See the plan above.\033[0m\n'; exit 2 ;;
                *) die "terraform could not compute the plan (exit $rc)" ;; esac ;;
  policy|policy-test)
    # conftest = the building inspector. Use it if installed, else the same version in Docker.
    if command -v conftest >/dev/null 2>&1; then CT="conftest"
    elif command -v docker >/dev/null 2>&1; then CT="docker run --rm --user $(id -u):$(id -g) -v $HERE:/p:ro -w /p openpolicyagent/conftest:v0.62.0"
    else die "the policy check needs conftest or Docker. Install Docker (the course labs have it), or conftest: https://www.conftest.dev/install/"; fi
    cd "$HERE"
    if [ "$ACTION" = policy-test ]; then $CT verify --policy policy
    else
      [ -f ".plans/$ENV.json" ] || die "no plan for $ENV yet. Run  $HERE/scripts/tf.sh $ENV plan  first."
      say "Policy check for $ENV"
      $CT test --policy policy ".plans/$ENV.json" && ok "the inspector approves the plan"
    fi ;;
  output)  init; terraform output -no-color ;;
  status)  init; terraform state list -no-color ;;
  destroy)
    init; say "Destroying everything in $ENV"
    terraform destroy -input=false -no-color -auto-approve $VARS
    ok "destroyed" ;;
  *) sed -n '2,17p' "$0"; die "unknown action: ${ACTION:-<none>}" ;;
esac
