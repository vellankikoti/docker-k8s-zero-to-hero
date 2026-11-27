#!/usr/bin/env bash
# up.sh [--pipeline]: get ready to build infrastructure with Terraform. Safe to run again.
#
#   up.sh              terraform + a light platform (image registry) + the state store + the runner's permissions   (~3 min)
#   up.sh --pipeline   also the full CI/CD platform (Jenkins + Git server) and YOUR infra repository with its Jenkins job
set -euo pipefail
. "$(dirname "$0")/lib.sh"
PIPELINE=0; [ "${1:-}" = "--pipeline" ] && PIPELINE=1
need_cluster

say "1/5 Terraform on this machine"
if ! command -v terraform >/dev/null 2>&1; then
  "$REPO/scripts/install-terraform.sh"
  export PATH="$HOME/.local/bin:$PATH"
  command -v terraform >/dev/null 2>&1 || die "terraform was installed in ~/.local/bin but is not on your PATH. Run:  export PATH=\"\$HOME/.local/bin:\$PATH\"   then run this again"
else ok "$(terraform version | head -1)"; fi

say "2/5 The platform (image registry, mail catcher$([ "$PIPELINE" = 1 ] && echo ', Jenkins, Git server'))"
need_helm
if [ "$PIPELINE" = 1 ]; then
  kubectl -n cicd get sts jenkins >/dev/null 2>&1 && ok "full platform already installed" || "$COURSE_ROOT/cicd-observability/scripts/k8s-up.sh"
else
  kubectl -n cicd get deploy registry >/dev/null 2>&1 && ok "registry already there" || "$COURSE_ROOT/cicd-observability/scripts/k8s-up.sh" --lite
fi

say "3/5 The Chai Stall image (built inside the cluster the first time)"
"$COURSE_ROOT/cicd-observability/scripts/ensure-image.sh" 1.0.0

say "4/5 The state store (namespace tfstate) and the pipeline runner's permissions"
out=$(kubectl apply -f "$HERE/platform/00-tfstate-and-runner.yaml" 2>&1) || die "kubectl apply failed: $out"

if [ "$PIPELINE" = 1 ]; then
  say "5/5 Your infra repository and its Jenkins job"
  [ -e "$HOME/infra" ] && warn "$HOME/infra already exists: skipping (delete it to create a fresh one)" || "$HERE/scripts/new-infra-repo.sh"
else
  say "5/5 Checking"
fi
"$HERE/scripts/verify.sh" || die "something is not ready: read the ✖ lines above"

cat <<MSG

  Build your first environment, by hand (Lab O01):
      cd cloud-native-ops/projects/infra-factory/infra-repo
      ./scripts/tf.sh dev plan          # read it: Terraform tells you everything it WILL do
      ./scripts/tf.sh dev apply         # do exactly that
      $HERE/scripts/verify.sh dev       # prove it
  Remove everything again:  $HERE/scripts/cleanup.sh
MSG
