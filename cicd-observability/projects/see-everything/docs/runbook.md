# 📖 Chai Stall Runbook (Kubernetes)

> For whoever is on call. Each section matches the `Runbook:` link inside an alert email. **Stop the pain first, find the cause later.**
> Open the doors once: `./cicd-observability/scripts/forward.sh start observability`

**The first 60 seconds, for any alert**
1. Grafana → *Chai Stall: Service Overview*. What is red? Since when?
2. What **changed** just before? `helm history chai-stall -n stall-demo` and `kubectl -n stall-demo get events --sort-by=.lastTimestamp | tail`. Changes cause most incidents.
3. Say it out loud in the incident channel: *"I am looking at X, I think Y."*

---

## nobody-can-order
**Alert:** `ChaiStallDown` (critical) · **Meaning:** Prometheus sees no ready instance at all.

```bash
kubectl -n stall-demo get deploy,pods          # 0/2? Pending? CrashLoopBackOff? ImagePullBackOff?
kubectl -n stall-demo describe pod -l app.kubernetes.io/name=chai-stall | tail -20
helm history chai-stall -n stall-demo
```
**Fix:** a bad release → `helm rollback chai-stall -n stall-demo` (back to the previous revision). Replicas at 0 → `helm upgrade` with the right `replicaCount`.
**Confirm:** `kubectl -n stall-demo get deploy` shows 2/2, the `[RESOLVED]` email arrives. This is SEV1: wake a second person while you work.

---

## high-error-rate
**Alerts:** `OrderSLOFastBurn` (critical), `OrderSLOSlowBurn` (warning) · **Meaning:** orders fail faster than the 99% SLO allows; the error budget is burning.

1. Dashboard → *Order error ratio* and *Burn rate*. Is it one Pod or all? `sum by (pod) (rate(http_requests_total{status=~"5.."}[1m]))`
2. Logs (Grafana → Explore → Loki): `{service="chai-stall"} | json | level="error"`. Same message every time? Click a `trace_id`: Jaeger shows where the request broke.
3. **What changed?** `helm history chai-stall -n stall-demo`; the `Version running` panel; `curl localhost:8083/api/info` shows the `chaos` settings.

**Fix:** a bad release → `helm rollback chai-stall -n stall-demo`. Investigate afterwards.
**Confirm:** the ratio is back at 0 and `[RESOLVED]` arrives. The slow-burn alert may follow for ~30 minutes while its long window drains: expected, not a new incident.

---

## slow-orders
**Alert:** `ChaiStallHighLatency` (warning) · **Meaning:** the p95 order latency is over 500 ms.

1. Dashboard → *Order latency (p50/p95/p99)*: all Pods or one? Did *In-flight requests* grow (saturation)?
2. A trace in Jaeger shows the span's duration. `kubectl -n stall-demo top pods` (needs metrics-server) shows CPU pressure.
3. Changed recently? `helm history`. Under load: is the HPA allowed to add Pods?

**Fix:** roll back a slow release; add replicas for real load (`helm upgrade ... --set replicaCount=4`).

---

## replicas-missing
**Alerts:** `ChaiStallReplicasUnavailable`, `ChaiStallPodRestarting` (warning) · **Meaning:** Kubernetes cannot keep all Pods Ready. Users may not notice yet, because healthy old Pods still serve. **That is exactly why this alert exists.**

```bash
kubectl -n stall-demo get pods                       # which state? this is the whole diagnosis:
#   ImagePullBackOff / ErrImagePull   → wrong image name or tag      (Scenario S1.2)
#   CrashLoopBackOff                  → the app dies at start: read   kubectl -n stall-demo logs POD --previous   (S1.3)
#   Pending                           → no room / no volume           kubectl -n stall-demo describe pod POD
#   Running but 0/1 Ready             → readiness probe failing       (S5.1)
```
**Fix:** correct the cause in the Helm values and upgrade, or `helm rollback chai-stall -n stall-demo`.
**Confirm:** `kubectl -n stall-demo rollout status deploy/chai-stall`; the alert clears.

---

## After the incident
Copy [`postmortem-template.md`](postmortem-template.md), fill it in within two working days, and give every action an owner and a date. The graph, the logs and the trace you just used are the evidence for the timeline.
