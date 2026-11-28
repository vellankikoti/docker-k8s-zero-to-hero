#!/usr/bin/env bash
# up.sh: build the whole production-ready setup. Safe to run again. About 8 minutes the first time.
#
#   1  the infra-factory basics (Terraform, registry, image, state store)       <- Project "Infra Factory"
#   2  metrics-server (the autoscaler needs numbers to react to)
#   3  environments dev and prod, built by Terraform                              (prod: 2+ Pods, autoscaler, PodDisruptionBudget)
#   4  admission policies: the API server refuses unsafe changes
#   5  the ledger (Redis) with an automatic backup
#   6  the night shift: dev and staging are switched off at night
#   7  checks everything
set -euo pipefail
. "$(dirname "$0")/lib.sh"
need_cluster; need_helm
cluster_healthy
need_memory 1500 "Production Ready" chai-ledger

say "1/7 Infra Factory basics"
"$INFRA/scripts/up.sh"
export PATH="$HOME/.local/bin:$PATH"

say "2/7 metrics-server (CPU numbers for the autoscaler, kubectl top)"
"$COURSE_ROOT/scripts/install-metrics-server.sh"

say "3/7 Environments dev and prod, from Terraform"
if kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
  export TF_VAR_monitoring=true; ok "Prometheus is installed: the apps will be scraped (ServiceMonitor)"
else
  export TF_VAR_monitoring=false; warn "no Prometheus in this cluster: monitoring is off. Install it with the See Everything project, then run this script again."
fi
for e in dev prod; do
  say "planning $e (the first time, Terraform downloads its providers: about a minute, with no output)"
  "$INFRA/infra-repo/scripts/tf.sh" "$e" plan >/dev/null
  docker_ok=0; command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 && docker_ok=1
  if [ "$docker_ok" = 1 ]; then
    docker run --rm -v "$INFRA/infra-repo":/p -w /p openpolicyagent/conftest:v0.62.0 test --policy policy ".plans/$e.json" >/dev/null 2>&1 \
      || { docker run --rm -v "$INFRA/infra-repo":/p -w /p openpolicyagent/conftest:v0.62.0 test --policy policy ".plans/$e.json" || true; die "the policy check refused the $e plan (above)"; }
  fi
  # Not silent: the app is released with "wait until the Pods are Ready" (up to 5 minutes). Terraform prints
  # "Still creating... [30s elapsed]" while it waits, so you can see it is working, not stuck.
  say "building $e (waits until its Pods are Ready: up to 5 minutes; open another terminal and run:  kubectl -n iac-$e get pods -w )"
  if ! "$INFRA/infra-repo/scripts/tf.sh" "$e" apply; then
    printf '\033[1;31m✖ the evidence, before you do anything else:\033[0m\n'
    kubectl -n "iac-$e" get pods -o wide 2>&1 | head -10
    kubectl -n "iac-$e" get events --sort-by=.lastTimestamp 2>&1 | tail -8
    kubectl -n "iac-$e" describe pod -l app.kubernetes.io/name=chai-stall 2>&1 | grep -E "Image:|Reason|Message|Exit Code|OOMKilled|Failed|Back-off|Events:" | head -14
    printf '\033[1;31m✖ what the container itself printed before it died (the real reason for a CrashLoopBackOff):\033[0m\n'
    kubectl -n "iac-$e" logs -l app.kubernetes.io/name=chai-stall --previous --tail=25 2>&1 | head -40
    die "terraform apply failed for $e (above). ImagePullBackOff = the image is missing: ./cicd-observability/scripts/ensure-image.sh. Pending = the cluster is full: kubectl describe node"
  fi
  ok "$e is built"
done

say "4/7 Admission policies (the API server's own rules)"
out=$(kubectl apply -f "$HERE/manifests/00-policies.yaml" 2>&1) || die "the cluster does not accept admission policies (needs Kubernetes 1.30 or newer): $out"

say "5/7 The ledger and its backup"
NO_SC=0; kubectl get storageclass 2>/dev/null | grep -q '(default)' || NO_SC=1
out=$(kubectl apply -f "$HERE/manifests/10-ledger.yaml" 2>&1) || die "kubectl apply failed: $out"
if [ "$NO_SC" = 1 ]; then
  warn "this cluster has no default StorageClass, so volumes would stay Pending (Scenario S4.3). Using plain Pod storage instead:"
  warn "the ledger and its backups survive a Pod restart only on THIS node's lifetime. Fine for learning; install a StorageClass for real."
  kubectl -n chai-ledger patch deploy ledger --type=json -p '[{"op":"replace","path":"/spec/template/spec/volumes/0","value":{"name":"data","emptyDir":{}}}]' >/dev/null
  kubectl -n chai-ledger patch cronjob ledger-backup --type=json -p '[{"op":"replace","path":"/spec/jobTemplate/spec/template/spec/volumes/0","value":{"name":"backup","emptyDir":{}}}]' >/dev/null
  kubectl -n chai-ledger delete pvc ledger-data ledger-backups --ignore-not-found --wait=false >/dev/null
fi
kubectl -n chai-ledger rollout status deploy/ledger --timeout=3m >/dev/null || die "the ledger did not start: kubectl -n chai-ledger get pods,pvc"
"$HERE/scripts/ledger.sh" seed 1000 >/dev/null
"$HERE/scripts/ledger.sh" backup

say "6/7 Night shift"
"$HERE/scripts/night-shift.sh" enable

say "7/7 Checking it all"
"$HERE/scripts/verify.sh" --wait 240
cat <<MSG

  Now run the drills, one by one (each says what it expects and CHECKS the result):
      $HERE/scripts/gameday.sh list
  The reports:  $HERE/scripts/cost-report.py     $HERE/scripts/dora.py
  Remove everything:  $HERE/scripts/cleanup.sh
MSG
