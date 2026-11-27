#!/usr/bin/env bash
# cleanup.sh [-y] [--keep-platform]: remove everything the infra-factory created. Safe to run any time, any number of times.
#   Destroys each environment THROUGH TERRAFORM (so the state agrees), then removes the state store and the runner's permissions.
#   --keep-platform  destroy only the environments; keep tfstate and the runner's permissions
set -uo pipefail
. "$(dirname "$0")/lib.sh"
YES=0; KEEP=0
for a in "$@"; do case "$a" in -y) YES=1 ;; --keep-platform) KEEP=1 ;; *) die "unknown option: $a" ;; esac; done
kubectl get --raw /readyz >/dev/null 2>&1 || { warn "Can't reach the cluster: nothing to clean up."; exit 0; }
if [ "$YES" = 0 ]; then printf 'This destroys the dev, staging and prod environments (namespaces iac-*) and the Terraform state. Continue? [y/N] '; read -r a; [ "$a" = y ] || [ "$a" = Y ] || exit 0; fi

for e in $ENVS; do
  n=$(ns_of "$e")
  if kubectl -n tfstate get secret "tfstate-default-iac-$e" >/dev/null 2>&1 && command -v terraform >/dev/null 2>&1; then
    say "terraform destroy: $e"
    TF_VAR_wait_for_pods=false "$REPO/scripts/tf.sh" "$e" destroy >/dev/null 2>&1 || warn "terraform could not destroy $e cleanly: removing what is left by hand"
  fi
  # whatever Terraform could not remove (or never knew about: a half-finished apply, no terraform installed)
  helm uninstall chai-stall -n "$n" >/dev/null 2>&1 || true
  kubectl delete ns "$n" --ignore-not-found --wait=false >/dev/null 2>&1 || true
done

if [ "$KEEP" = 0 ]; then
  say "Removing the state store and the runner's permissions"
  kubectl delete ns tfstate --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kubectl delete clusterrolebinding terraform-runner --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete clusterrole terraform-runner --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n cicd delete sa terraform-runner --ignore-not-found >/dev/null 2>&1 || true
  helm uninstall chai-stall -n iac-dev >/dev/null 2>&1 || true
fi
rm -rf "$REPO"/.plans "$REPO"/.terraform-* 2>/dev/null || true

say "Waiting for the namespaces to disappear (up to 2 minutes)"
for _ in $(seq 1 24); do
  left=$(kubectl get ns iac-dev iac-staging iac-prod tfstate -o name 2>/dev/null | tr '\n' ' ')
  [ -z "$left" ] && break
  [ "$KEEP" = 1 ] && [ "$left" = "namespace/tfstate " ] && break
  sleep 5
done
[ -z "${left:-}" ] && ok "Clean: nothing from the infra-factory is left in the cluster." || warn "still terminating: $left (it finishes by itself; check: kubectl get ns)"
