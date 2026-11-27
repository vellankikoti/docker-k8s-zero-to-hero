#!/usr/bin/env bash
# verify.sh [ENV...] [--drift]: is the infrastructure factory set up, and does each environment match what the code says?
#   verify.sh              check the platform (state store, runner permissions, terraform, image) and every environment that exists
#   verify.sh dev prod     check just these
#   verify.sh dev --drift  also run a plan: any difference between code and cluster is reported
# Changes nothing.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
need_cluster
WANT=(); DRIFT=0
for a in "$@"; do case "$a" in --drift) DRIFT=1 ;; dev|staging|prod) WANT+=("$a") ;; *) die "unknown argument: $a" ;; esac; done
fail=0
chk() { local label=$1 hint=$2; shift 2; if "$@" >/dev/null 2>&1; then printf '  \033[1;32m✔\033[0m %s\n' "$label"; else printf '  \033[1;31m✖\033[0m %s\n      → %s\n' "$label" "$hint"; fail=$((fail+1)); fi; }
can() { [ "$(kubectl auth can-i "$@" --as=system:serviceaccount:cicd:terraform-runner 2>/dev/null)" = yes ]; }

echo "Platform"
chk "terraform is installed" "$REPO/scripts/install-terraform.sh" command -v terraform
chk "the state store exists (namespace tfstate)" "run up.sh" kubectl get ns tfstate
chk "the pipeline's runner may create namespaces" "run up.sh" can create namespaces
chk "...but may NOT touch nodes (least privilege)" "the ClusterRole terraform-runner is too wide" bash -c '! kubectl auth can-i delete nodes --as=system:serviceaccount:cicd:terraform-runner | grep -q yes'
chk "...and may NOT read Secrets in kube-system" "the ClusterRole terraform-runner is too wide" bash -c '! kubectl auth can-i get secrets -n kube-system --as=system:serviceaccount:cicd:terraform-runner | grep -q yes'
chk "the Chai Stall image is in the registry" "./cicd-observability/scripts/ensure-image.sh" bash -c "kubectl -n cicd exec deploy/registry -- wget -qO- http://localhost:5000/v2/chai-stall/tags/list | grep -q 1.0.0"

[ ${#WANT[@]} -eq 0 ] && for e in $ENVS; do kubectl get ns "$(ns_of $e)" >/dev/null 2>&1 && WANT+=("$e"); done
for e in "${WANT[@]:-}"; do
  [ -n "$e" ] || continue
  n=$(ns_of "$e"); echo "Environment: $e (namespace $n)"
  chk "state is stored in the cluster (Secret tfstate-default-iac-$e)" "apply it: $REPO/scripts/tf.sh $e plan && $REPO/scripts/tf.sh $e apply" kubectl -n tfstate get secret "tfstate-default-iac-$e"
  chk "the namespace names an owner and a cost centre" "labels z2h/owner and z2h/cost-center are missing: someone edited by hand? (run with --drift)" bash -c "kubectl get ns $n -o jsonpath='{.metadata.labels}' | grep -q 'z2h/owner' && kubectl get ns $n -o jsonpath='{.metadata.labels}' | grep -q 'z2h/cost-center'"
  chk "Pod Security 'restricted' is enforced" "kubectl get ns $n --show-labels" bash -c "[ \"\$(kubectl get ns $n -o jsonpath='{.metadata.labels.pod-security\\.kubernetes\\.io/enforce}')\" = restricted ]"
  chk "a fair-share quota and container defaults exist" "kubectl -n $n get resourcequota,limitrange" bash -c "kubectl -n $n get resourcequota environment-budget && kubectl -n $n get limitrange container-defaults"
  chk "default-deny network policy exists" "kubectl -n $n get networkpolicy" kubectl -n "$n" get networkpolicy default-deny-ingress
  chk "the Helm release chai-stall is deployed" "HELM_DRIVER=configmap helm ls -n $n   (the release records are ConfigMaps)" bash -c "helm status chai-stall -n $n | grep -q 'STATUS: deployed'"
  want=$(kubectl -n "$n" get deploy chai-stall -o jsonpath='{.spec.replicas}' 2>/dev/null)
  chk "all $want Pod(s) are Ready" "kubectl -n $n describe pod | tail -20 ; image reachable? ./cicd-observability/scripts/ensure-image.sh" bash -c "[ -n '$want' ] && [ \"\$(kubectl -n $n get deploy chai-stall -o jsonpath='{.status.readyReplicas}')\" = '$want' ]"
  chk "the app answers (through the API server's service proxy)" "kubectl -n $n logs deploy/chai-stall" bash -c "kubectl get --raw /api/v1/namespaces/$n/services/chai-stall:80/proxy/readyz | grep -qi ok"
  if [ "$e" = prod ]; then
    chk "production has an autoscaler and a PodDisruptionBudget" "kubectl -n $n get hpa,pdb" bash -c "kubectl -n $n get hpa chai-stall && kubectl -n $n get pdb chai-stall"
  fi
  if [ "$DRIFT" = 1 ]; then
    chk "no drift: the cluster matches the code" "someone changed it by hand: $REPO/scripts/tf.sh $e drift shows what; $REPO/scripts/tf.sh $e plan && apply puts it back" "$REPO/scripts/tf.sh" "$e" drift
  fi
done
echo
if [ "$fail" -eq 0 ]; then ok "Everything checks out."; exit 0; fi
printf '\033[1;31m%d check(s) failed.\033[0m\n' "$fail"; exit 1
