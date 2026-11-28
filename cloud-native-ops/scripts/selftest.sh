#!/usr/bin/env bash
# selftest.sh: a maintainer's check that this track is consistent. No stack needs to be running.
#   ./cloud-native-ops/scripts/selftest.sh
# Checks: script syntax, Terraform formatting + validity, the policy's unit tests (conftest), the cost/DORA tools, YAML,
# the manifests (against your cluster's API server if one answers, as a dry run), and every Markdown link.
cd "$(dirname "$0")/../.." || exit 1
fails=0
ok()  { printf '  \033[1;32m✔\033[0m %s\n' "$*"; }
bad() { printf '  \033[1;31m✖\033[0m %s\n' "$*"; fails=$((fails+1)); }
run() { local label=$1; shift; if "$@" >/tmp/co-selftest.out 2>&1; then ok "$label"; else bad "$label"; sed 's/^/      /' /tmp/co-selftest.out | tail -15; fi; }
C=cloud-native-ops
IR=$C/projects/infra-factory/infra-repo

echo "Shell scripts"
for f in $(find $C -name '*.sh'); do run "bash -n $f" bash -n "$f"; done
for f in $IR/scripts/tf.sh $IR/scripts/mk-kubeconfig.sh $IR/scripts/install-terraform.sh; do
  command -v dash >/dev/null && run "$f is valid POSIX sh (it runs in the Terraform container, which has no bash)" dash -n "$f"
done
echo "Python tools"
run "cost and DORA unit tests" bash -c "cd $C/projects/production-ready && python3 -m unittest discover -s tests"
echo "Jenkins config"
# Jenkins 2.580+ refuses to START when JCasC contains this removed setting ("Invalid configuration elements for DefaultCrumbIssuer").
run "Jenkins values do not use the removed excludeClientIPFromCrumb setting" bash -c '! grep -v "^ *#" cicd-observability/k8s/platform/jenkins-values.yaml | grep -q "excludeClientIPFromCrumb"'
echo "YAML"
run "yaml files parse" python3 - <<'PY'
import glob, yaml
files = glob.glob("cloud-native-ops/**/*.y*ml", recursive=True)
for f in files:
    list(yaml.safe_load_all(open(f)))
print(len(files), "files")
PY
echo "Terraform"
run "Terraform's default image_tag equals CHAI_IMAGE_TAG (one tag, everywhere)" bash -c "t=\$(sed -n 's/^export CHAI_IMAGE_TAG=\${CHAI_IMAGE_TAG:-\(.*\)}/\1/p' cicd-observability/scripts/k8s-lib.sh); grep -A3 'variable \"image_tag\"' $IR/terraform/variables.tf | grep -q \"default     = \\\"\$t\\\"\""
if command -v terraform >/dev/null; then
  run "terraform fmt + validate" "$IR/scripts/tf.sh" dev check
else echo "  • terraform not installed: skipped ($IR/scripts/install-terraform.sh)"; fi
if command -v helm >/dev/null; then
  run "helm lint the chart with Terraform's values" bash -c "helm lint cicd-observability/k8s/chart/chai-stall --set image.tag=selftest --set-json 'commonLabels={\"z2h/owner\":\"t\"}'"
fi
echo "Policy"
if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  run "conftest verify (the plan policy's own tests)" docker run --rm -v "$PWD/$IR":/p -w /p openpolicyagent/conftest:v0.62.0 verify --policy policy
else echo "  • docker not available: skipped the policy unit tests"; fi
echo "Manifests against the API server (dry run)"
if command -v kubectl >/dev/null && kubectl get --raw /readyz >/dev/null 2>&1; then
  for f in $C/projects/production-ready/manifests/00-policies.yaml; do
    run "kubectl apply --dry-run=server $(basename "$f")" kubectl apply --dry-run=server -f "$f"
  done
  # these create their own namespace (or live in one that may not exist yet), which a server dry run cannot see: check their schema client-side
  for f in $C/projects/infra-factory/platform/00-tfstate-and-runner.yaml $C/projects/production-ready/manifests/10-ledger.yaml $C/projects/production-ready/manifests/20-night-shift.yaml; do
    run "kubectl apply --dry-run=client $(basename "$f")" kubectl apply --dry-run=client --validate=true -f "$f"
  done
else echo "  • no cluster reachable: skipped (iac-test.sh runs the real Terraform against a cluster)"; fi
echo "Docs"
run "markdown links" python3 scripts/link-check.py
echo; [ $fails -eq 0 ] && echo "selftest: all good" || echo "selftest: $fails problem(s)"
exit $([ $fails -eq 0 ] && echo 0 || echo 1)
