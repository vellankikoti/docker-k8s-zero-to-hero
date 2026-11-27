#!/usr/bin/env bash
# rush.sh [--ns NS] [--seconds 90] [--workers 4]: the Diwali rush. Several customers order as fast as they can for a while.
# Prints: how many orders worked and failed, WHICH Pods served them (that is load balancing, visible), and how the
# autoscaler reacted. Run inside the cluster as a Job, so it uses the real Service, exactly like a real customer.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
NS=$PROD_NS; SECS=90; WORKERS=4
while [ $# -gt 0 ]; do case "$1" in --ns) NS=$2; shift 2 ;; --seconds) SECS=$2; shift 2 ;; --workers) WORKERS=$2; shift 2 ;; *) die "unknown option: $1" ;; esac; done
need_cluster
kubectl -n "$NS" get svc chai-stall >/dev/null 2>&1 || die "no Service chai-stall in $NS. Build the environment first (infra-factory: tf.sh prod apply)"
kubectl -n "$NS" delete job rush --ignore-not-found >/dev/null
say "The rush starts: $WORKERS customers, $SECS seconds, against http://chai-stall in $NS"
kubectl apply -f - >/dev/null <<YAML
apiVersion: batch/v1
kind: Job
metadata: { name: rush, namespace: $NS, labels: { app: rush } }
spec:
  parallelism: $WORKERS
  completions: $WORKERS
  backoffLimit: 0
  ttlSecondsAfterFinished: 600
  template:
    metadata: { labels: { app: rush } }
    spec:
      restartPolicy: Never
      securityContext: { runAsNonRoot: true, runAsUser: 100, runAsGroup: 101, seccompProfile: { type: RuntimeDefault } }
      containers:
        - name: customer
          image: curlimages/curl:8.11.1
          command:
            - sh
            - -c
            - |
              end=\$((\$(date +%s) + $SECS)); ok=0; bad=0
              while [ \$(date +%s) -lt \$end ]; do
                out=\$(curl -s -m 3 -X POST "http://chai-stall/order?item=chai" || true)
                case "\$out" in
                  *'"ok": true'*) ok=\$((ok+1)); echo "\$out" | sed -n 's/.*"served_by": "\([^"]*\)".*/SERVED \1/p' ;;
                  *) bad=\$((bad+1)) ;;
                esac
              done
              echo "RESULT ok=\$ok failed=\$bad"
          securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: [ALL] } }
          resources: { requests: { cpu: 5m, memory: 8Mi }, limits: { memory: 32Mi } }
YAML
for i in $(seq 1 $((SECS / 15 + 8))); do
  sleep 15
  printf '  %s   autoscaler: ' "$(date +%H:%M:%S)"
  kubectl -n "$NS" get hpa chai-stall -o jsonpath='{.status.currentReplicas} Pods now, {.status.desiredReplicas} wanted, cpu {.status.currentMetrics[0].resource.current.averageUtilization}% (it adds Pods above {.spec.metrics[0].resource.target.averageUtilization}%)' 2>/dev/null || printf 'no autoscaler here'
  echo
  [ "$(kubectl -n "$NS" get job rush -o jsonpath='{.status.succeeded}' 2>/dev/null)" = "$WORKERS" ] && break
done
kubectl -n "$NS" wait --for=condition=complete job/rush --timeout=60s >/dev/null 2>&1 || warn "the Job did not finish cleanly: kubectl -n $NS logs job/rush"
logs=$(kubectl -n "$NS" logs -l app=rush --tail=-1 2>/dev/null || true)
okn=$(echo "$logs" | sed -n 's/^RESULT ok=\([0-9]*\) failed=.*/\1/p' | awk '{s+=$1} END{print s+0}')
badn=$(echo "$logs" | sed -n 's/^RESULT ok=[0-9]* failed=\([0-9]*\)/\1/p' | awk '{s+=$1} END{print s+0}')
echo; ok "orders placed: ${okn:-0}   failed: ${badn:-0}"
echo "Who served them (load balancing):"; echo "$logs" | grep '^SERVED' | sort | uniq -c | sort -rn | sed 's/SERVED/  Pod/'
echo "Pods now: $(kubectl -n "$NS" get deploy chai-stall -o jsonpath='{.status.readyReplicas}')/$(kubectl -n "$NS" get deploy chai-stall -o jsonpath='{.spec.replicas}') ready"
echo "RUSH_OK=${okn:-0} RUSH_FAILED=${badn:-0}" > /tmp/z2h-rush.last
