# 📖 Chai Stall Runbook

> For the on-call engineer. Each section matches an alert's `Runbook:` link. **Mitigate first, diagnose later.**
> Everything below works from `cicd-observability/compose-edition/project-2-see-everything/`.

**First 60 seconds for any alert**
1. Open the dashboard: http://localhost:3000 → *Chai Stall: Service Overview*. What is red? When did it start?
2. Did anything **change** just before? (`docker compose ps`, the Jenkins build history, `git log -5`). Changes cause most incidents.
3. Say out loud (or in the incident channel): *"I'm looking at X, I think Y."*

---

## instance-down
**Alert:** `ChaiStallInstanceDown` (critical) · **Meaning:** Prometheus cannot scrape one instance; customers are being served by fewer instances (or none).

**Check**
```bash
docker compose ps                                  # is the container Up? Restarting? Exited?
docker compose logs --tail 30 chai-1               # why did it stop? (replace chai-1 with the instance_name from the alert)
curl -s localhost:8091/healthz                     # does it answer at all? (8091 = chai-1, 8092 = chai-2)
```
Prometheus: `up{job="chai-stall"}` shows which targets are `0`.

**Fix**
- Exited or crashed: `docker compose start chai-1` (add `--build` if the image is missing).
- Restart loop: read the logs; if a recent release caused it, **roll back** (see *Rolling back* below).
- Both instances down: this is **SEV1**. Page a second person.

**Confirm:** `up` returns 1 for both, the `[RESOLVED]` email arrives, *Instances up* shows 2.

---

## high-error-rate
**Alerts:** `OrderSLOFastBurn` (critical), `OrderSLOSlowBurn` (warning) · **Meaning:** orders are failing faster than the 99% SLO allows; the error budget is burning.

**Check**
1. Dashboard → *Order error ratio*, *Burn rate*. Is it one instance or both? (`sum by (instance_name) (rate(http_requests_total{status=~"5.."}[1m]))`)
2. Logs of the failing requests (Grafana → Explore → Loki):
   ```
   {service=~"chai-.*"} | json | level="error"
   ```
   Same message every time? Same route? Click a `trace_id` → the trace shows where the request failed.
3. **What changed?** A new version (`app_info{version}` on the dashboard, or the Jenkins history), or injected chaos:
   `curl -s localhost:8091/api/info` (shows `"chaos"` settings).

**Fix**
- A bad release → **roll back first**, investigate later.
- Chaos left on (practice incident): `curl -X POST localhost:8091/chaos/reset` and `:8092`.

**Confirm:** the error ratio on the dashboard returns to 0; `[RESOLVED]` arrives. The *slow-burn* alert may follow for ~30 minutes as its long window drains: that is expected, not a new incident.

---

## slow-orders
**Alert:** `ChaiStallHighLatency` (warning) · **Meaning:** p95 order latency above 500 ms for 30 s.

**Check**
1. Dashboard → *Order latency p50/p95/p99* and *In-flight requests* (saturation). Is p50 also up (everything slow) or only p99 (a slow tail)?
2. Traces: Grafana → Explore → Jaeger (or http://localhost:16686), service `chai-stall`, *Min Duration* `500ms`. Which span is slow?
3. Is one instance slower? `histogram_quantile(0.95, sum by (le, instance_name) (rate(http_request_duration_seconds_bucket{path="/order"}[1m])))`
4. Logs: `{service=~"chai-.*"} | json | duration_ms > 500`

**Fix:** restart the slow instance, scale out, or roll back the release. (Practice incident: `curl -X POST localhost:8091/chaos/reset`.)

---

## no-orders
**Alert:** `OrdersStopped` (warning), if you added it in C07 · **Meaning:** zero orders for a minute.

**Check:** is the load generator running (`docker compose ps loadgen`)? Is the front door reachable (`curl -s localhost:8091/readyz`)? Real traffic stopped at 3 a.m. is normal; stopped at lunchtime is not.

---

## Rolling back a release
Project 1's router keeps the previous version running:
```bash
cd ../project-1-ship-it
./deploy/deploy.sh status
./deploy/deploy.sh rollback          # canary -> 0%, or blue/green -> flip back
./scripts/traffic-test.sh http://localhost:8090 10      # prove users are fine again
```

## Escalation
| When | Who |
|---|---|
| You cannot find the cause in 15 minutes | the second on-call (say what you checked) |
| More than one service is affected | incident commander |
| Customers' money or data is involved | team lead immediately |

## After the incident
Write a **blameless postmortem** within two working days: [`postmortem-template.md`](postmortem-template.md).
