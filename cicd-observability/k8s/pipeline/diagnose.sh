#!/usr/bin/env bash
# diagnose.sh NAMESPACE RELEASE: print everything an on-call engineer would look at when a release does not become healthy.
# The pipeline runs it BEFORE it rolls the release back (a rollback deletes the evidence), so the build log says WHY.
#   what Helm thinks · what the cluster has · the events · why each Pod is unhappy · what the containers printed
ns=${1:?usage: diagnose.sh NAMESPACE RELEASE}; rel=${2:?usage: diagnose.sh NAMESPACE RELEASE}
sel="app.kubernetes.io/instance=$rel"
sec() { printf '\n\033[1;33m──── %s\033[0m\n' "$*"; }

sec "helm status / history"
helm status "$rel" -n "$ns" 2>&1 | head -12
helm history "$rel" -n "$ns" 2>&1 | tail -5

sec "what exists (Deployment, ReplicaSet, Pods, Service)"
kubectl -n "$ns" get deploy,rs,pods,svc,endpointslices.discovery.k8s.io -l "$sel" -o wide 2>&1 | cut -c1-200

sec "recent events in the namespace (newest last): look for FailedCreate, FailedScheduling, Failed, BackOff"
kubectl -n "$ns" get events --sort-by=.lastTimestamp 2>&1 | tail -15 | cut -c1-220

sec "ReplicaSet conditions (a Pod Security / quota refusal shows up HERE, not on the Pods)"
kubectl -n "$ns" get rs -l "$sel" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .status.conditions[*]}  {.type}={.status}: {.message}{"\n"}{end}{end}' 2>&1 | cut -c1-260

for pod in $(kubectl -n "$ns" get pods -l "$sel" -o name 2>/dev/null); do
  sec "$pod: why is it not Ready? (describe, Events and State only)"
  kubectl -n "$ns" describe "$pod" 2>&1 | grep -E "^(Status|Reason|Message|Node):|State:|Reason:|Exit Code|Last State|Image:|Ready:|Warning|Failed|Back-off|pull|Pull" | head -20 | cut -c1-220
  sec "$pod: what the containers printed"
  kubectl -n "$ns" logs "$pod" --all-containers --tail=25 2>&1 | cut -c1-200
done

sec "the helm test Pod (if it ran)"
kubectl -n "$ns" get pod "$rel-smoke" -o wide 2>&1 | cut -c1-200
kubectl -n "$ns" logs "$rel-smoke" --tail=25 2>&1 | cut -c1-200
exit 0
