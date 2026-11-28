# 🏁 See Everything: metrics, logs, traces and alerts, inside your cluster

> ⏱ about 2 hours (the ⭐ steps are a 40-minute live path) · 🟡→🔴 · Needs: any cluster you already used for the Kubernetes labs (kind, minikube, Docker Desktop, Killercoda, iximuz), 2.5 GB free memory, `kubectl`, `helm`, `python3`
> **The goal:** watch a real app with Prometheus, Alertmanager and Grafana; add logs (Loki) and traces (Jaeger); then **break it five ways and get the email before a customer complains.**

> ⚠️ **Memory:** see-everything (~2.5 GB) and production-ready (~3 GB) are **not meant to run at the same time on a small lab** (two nodes of ~2 GB each cannot hold both). Run one, `cleanup.sh` it, then the other. If the cluster's `kube-controller-manager` or `kube-scheduler` starts crash-looping, the cluster ran out of memory: every `up.sh` checks for that and tells you what to do.

> 🧭 **Before you begin (30 seconds, same for every project)**
> 1. Open a terminal **in the course folder** (the one that contains `cicd-observability/` and `cloud-native-ops/`). Check with `ls`. Every command below is written to run from there, so you never need `cd`.
> 2. `kubectl get nodes` must show every node **Ready**. If it errors, fix your cluster first (kind, minikube, Docker Desktop, Killercoda or iximuz all work).
> 3. Run **one project at a time**. Finished? Run its `cleanup.sh` before starting another.
> 4. Every step ends with a ✔ or ✖ line. If you see a ✖, read the `→` hint under it. Still stuck? Copy that line and what is printed after it, and ask.
> 5. In a browser lab (Killercoda, iximuz) pages like Grafana open through the lab's **port / Traffic** panel, not `localhost`; each step says which port.
> 6. 📝 **This is a demo, not production.** On a small lab the scripts print a *DEMO MODE* warning about memory and carry on, with small resource requests chosen for learning. A real cluster would give each of these tools more room (for example Jenkins about 2 GB, Prometheus several GB) and would run them on separate nodes. If a Pod stays Pending or keeps restarting, memory is the reason: free some or use a bigger cluster.

## 🧠 The idea, in one chai stall
A chai stall owner who can't see his stall is guessing. Give him five things:

| What the owner has | In our cluster | It answers |
|---|---|---|
| 📒 **the ledger**: orders today, how long each took | **Prometheus** (metrics) | *how much? how fast? how many failed?* |
| 📓 **the diary**: "10:42 sugar finished, customer angry" | **Loki** (logs) | *what exactly happened?* |
| 🎫 **the token's journey**: counter → kitchen → handover | **Jaeger** (traces) | *where did THIS order get stuck?* |
| 📢 **the whistle**: the neighbour shouts when the stall is empty | **Alertmanager** + the **inbox** | *tell me before the customer does* |
| 🪧 **the notice board**: everything on one wall | **Grafana** | *the whole picture, at a glance* |

You already met these as *kubectl* tricks in the 60 scenarios (`get pods`, `logs`, `describe`, `events`). Here the cluster **keeps** that evidence, draws it, and **calls you**.

```
 customer ──▶ Chai Stall (2 Pods) ──/metrics──▶ Prometheus ──rules──▶ Alertmanager ──▶ 📬 inbox (Mailpit)
                    │  │                              │
                    │  └─ traces (OTLP) ─▶ Jaeger     └──▶ Grafana ◀── Loki ◀── Alloy ◀── Pod logs
                    └──── logs (stdout) ───────────────────────────────────────────────┘
```
Everything runs from files in this folder: the rules, the dashboard and the datasources are **code**, applied with `kubectl`, reviewed in git.

## 🧰 Step 0: start it ⭐ (8 minutes, then it checks itself)
**First time on this machine?** Get the course (if the folder already exists, git says so and you can ignore that) and go into it. Do NOT use `--depth`: Jenkins needs the full history.
```bash
git clone https://github.com/vellankikoti/docker-k8s-zero-to-hero.git
cd docker-k8s-zero-to-hero
git pull
```
Then start it:
```bash
./cicd-observability/projects/see-everything/scripts/up.sh
```
It installs a light registry + inbox, builds the Chai Stall image **inside your cluster**, installs Prometheus, Alertmanager and Grafana (the same chart as lab K19), adds Loki, Alloy and Jaeger, publishes the rules and the dashboard, releases the app with Helm, starts a tiny customer, and **ends by running `verify.sh`**. You want to see this at the end:

```
✔ Everything works: you can see metrics, logs, traces, alerts and the inbox.
```
If a line shows ✖, it prints the exact `kubectl` command to look with. Run `./cicd-observability/projects/see-everything/scripts/verify.sh --wait 300` to retry. Not sure what a step does? Every script is short and commented: read it.

**Only after `up.sh` has finished and printed the ✔ line above**, open the doors (they stay open in the background). If you run this too early it tells you so and stops; nothing is broken, just run `up.sh` first:
```bash
./cicd-observability/scripts/forward.sh start observability
```
The last lines show a table: every door, its port, and ✔ when it answers. On your own computer open `http://localhost:PORT`.
**In Killercoda / iximuz** the script detects the lab and listens on every interface; then open the lab's port panel (Killercoda: menu → **Traffic / Ports**), type the port and open the link:

| Door | Port |
|---|---|
| Grafana (the notice board) | `3000` |
| Prometheus | `9090` |
| Alertmanager | `9093` |
| Jaeger (traces) | `16686` |
| Inbox (Mailpit) | `8025` |
| The Chai Stall app | `8083` |

A **502 Bad Gateway** from the lab link means the door is closed or listening on `127.0.0.1` only: run `./cicd-observability/scripts/forward.sh stop` then `./cicd-observability/scripts/forward.sh start observability --lab`.

## 🔭 Step 1: the notice board ⭐ (5 minutes)
Open **Grafana** http://localhost:3000 (in a lab: port 3000; login admin / `z2h-grafana`) → **Dashboards → Chai Stall: Service Overview**. Set refresh **5s**, range **15 minutes**.
Read it top to bottom: *Is it up?* → *Traffic, errors, latency* → *The SLO* → *Logs*. Those are the **four golden signals** (traffic, errors, latency, saturation). One look should tell you "fine" or "not fine".

## 📒 Step 2: ask Prometheus yourself (10 minutes)
http://localhost:9090 → *Graph*. Try these, one at a time, and say what each means in chai-stall words:
```promql
up{job="chai-stall"}                                            # 1 per Pod that answers
sum(rate(http_requests_total{job="chai-stall"}[1m]))            # orders per second
sum by (item) (rate(orders_total[1m]))                          # the BUSINESS metric: which item sells?
histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{path="/order"}[5m])))   # p95: 19 of 20 customers wait less than this
kube_deployment_status_replicas_available{namespace="stall-demo"}   # the cluster's own numbers (kube-state-metrics)
```
*How does Prometheus know the Pods exist?* → `kubectl -n stall-demo get servicemonitor chai-stall -o yaml`. A **ServiceMonitor** says "scrape every Service with these labels". Scale the app (`kubectl -n stall-demo scale deploy chai-stall --replicas=3`) and watch `up` grow **without touching Prometheus**. Put it back with `--replicas=2`.

## 📢 Step 3: alerts as code ⭐ (10 minutes)
Open [`manifests/20-rules.yaml`](manifests/20-rules.yaml): one `PrometheusRule` object. The Prometheus Operator loads it by itself; **no file to mount, no restart**. Read the four groups: `sli` (recording rules), `symptoms`, `slo` (burn rates), `capacity` (the cluster's view).

**Test the rules without a cluster**, the way a team does in CI:
```bash
./cicd-observability/projects/see-everything/tests/run.sh      # needs Docker; unit-tests every alert with fake data
```
**Change one rule and watch it arrive.** The alert `ChaiStallHighLatency` fires when orders are slower than **500 ms**. We will change that to **200 ms** by editing the file, not the cluster.

1. **See what the cluster has now** (look for `> 0.5`):
```bash
kubectl -n observability get prometheusrule chai-stall -o yaml | grep "order_latency_p95:5m >"
```
2. **Edit the file, then apply it:**
```bash
F=cicd-observability/projects/see-everything/manifests/20-rules.yaml
sed -i.bak 's/job:order_latency_p95:5m > 0.5/job:order_latency_p95:5m > 0.2/' $F
kubectl apply -f $F
```
3. **Check it arrived** (wait ~30 seconds, then run step 1 again; it must now say `> 0.2`). Prometheus picks the file up on its own, which you can see in the browser too:
   - open Prometheus (http://localhost:9090, or your lab's port 9090 link),
   - top menu **Alerts**, find `ChaiStallHighLatency`, click it to open: the *expression* now shows `> 0.2`.
   (Older Prometheus versions: **Status → Rules** instead.)
4. **Undo:**
```bash
mv $F.bak $F && kubectl apply -f $F
```
That is the whole GitOps idea: **the file is the truth**; change the file, apply, and the cluster follows. Nothing was restarted.

> Seeing nothing in Prometheus? First check the door is open: `./cicd-observability/scripts/forward.sh status`. Then check the rule exists: `kubectl -n observability get prometheusrule`.

## 📓 Step 4: logs and traces ⭐ (10 minutes)
1. Grafana → **Explore** → pick **Loki** → `{service="chai-stall"} | json`. Every line the Pods printed, kept for 48 h, even after a Pod dies.
2. Narrow to trouble: `{service="chai-stall"} | json | level="error"` (quiet now; the game day fills it).
3. Open Jaeger http://localhost:16686 → service `chai-stall` → *Find Traces*. One bar per order: where did the time go?
4. The bridge: in a log line that has a `trace_id`, click it. Grafana jumps to **that exact request in Jaeger**. That is how you go from "something failed" to "*this* is where".

## 🔥 Step 5: the game day ⭐ (25 minutes)
Now break it, five ways. Each incident is a **Helm release change**, so putting it back is one honest command.
```bash
./cicd-observability/projects/see-everything/scripts/gameday.sh list
```
| Incident | You cause it | The first signal | Kubernetes scenario it echoes |
|---|---|---|---|
| `errors` | a bad release: 30% of orders fail | 🔔 `OrderSLOFastBurn` email, error ratio up, error logs with trace ids | S5.4 the bad rollout |
| `slow` | every order takes 800 ms | 🔔 `ChaiStallHighLatency`, p95 climbs, long bars in Jaeger | S5.2 slow start |
| `crashloop` | a typo in config: Pods crash at start | 🔔 `ChaiStallPodRestarting`, `CrashLoopBackOff` | S1.3 the crash loop |
| `bad-image` | a typo in the image tag | 🔔 `ChaiStallReplicasUnavailable`, `ImagePullBackOff` | S1.2 the image typo |
| `outage` | replicas set to 0 | 🔔 `ChaiStallDown` (critical), requests drop to 0 | a Deployment scaled away |

Run **one at a time**, with the dashboard and the inbox (http://localhost:8025) open:
```bash
GD=./cicd-observability/projects/see-everything/scripts/gameday.sh
$GD start errors                  # 1. cause it
$GD watch OrderSLOFastBurn        # 2. waits until the alert FIRES and its email lands (about 4 minutes: it prints progress every 30 s)
#    now investigate like on call: dashboard → logs → click a trace_id → helm history chai-stall -n stall-demo
$GD recover                       # 3. one helm upgrade puts everything back; a [RESOLVED] email follows
```
**Predict first**, for each: *which panel moves first? will users notice? which kubectl command would show the cause?* Notice `bad-image`: the old Pods keep serving (rolling update, `maxUnavailable: 0`), so **users feel nothing**, yet the alert still fires. That is why you alert on the cluster's view too, not only on customer pain.

The runbook the emails link to: [`docs/runbook.md`](docs/runbook.md). After one incident, write a postmortem from [`docs/postmortem-template.md`](docs/postmortem-template.md).

## 🎯 Step 6: the error budget (10 minutes)
The SLO says **99% of orders succeed**, so you may fail 1%. Start `errors` and read three panels: *Burn rate* (how many times faster than allowed), *Error budget remaining*, *Error ratio vs the SLO line*. At 30% failure the burn rate is ~30: the budget of a whole month is gone in about a day. That is why the fast-burn alert **pages**, and the slow-burn one only **emails**. Recover, then ask: *would you ship a risky release when the budget is nearly spent?*

## 🧑‍🍳 Step 7: make it yours
Pick one, do it with files in this folder, run `tests/run.sh` and `verify.sh`:
- A new alert: `ChaiStallNoOrders`, firing when `rate(orders_total[5m]) == 0` for 5 minutes (a stall can be *up* and still sell nothing).
- A new dashboard panel: orders per item as a bar gauge. Edit `dashboards/chai-stall.json`, run `up.sh` again (it re-publishes the dashboard).
- Point the same stack at **your own app** from the Canteen Rush project: give its Service a `/metrics` and a ServiceMonitor.

## 🧯 When something is not right
| You see | Look here |
|---|---|
| `up.sh` stops at the registry | `kubectl -n cicd get pods,pvc`: a `Pending` PVC means no StorageClass (Scenario S4.3); `k8s-up.sh` falls back to plain Pod storage and tells you |
| image build fails | `kubectl -n cicd logs job/build-chai-image`: a pull error means this cluster cannot reach Docker Hub |
| Grafana has no dashboard | `kubectl -n monitoring get cm chai-stall-dashboard`; `kubectl -n monitoring logs deploy/kube-prometheus-stack-grafana -c grafana-sc-dashboard` |
| `Prometheus scrapes both Pods` is ✖ | `kubectl -n stall-demo get servicemonitor`; Prometheus → *Status → Targets* |
| no logs in Loki | `kubectl -n observability logs deploy/alloy | tail`: usually a permissions or Loki-not-ready message |
| no email | Alertmanager http://localhost:9093 → *Status*: is the `email` receiver there? `kubectl -n mail get pods` |
| cluster feels slow | this stack wants ~2.5 GB. Close other projects: `./cicd-observability/projects/see-everything/scripts/cleanup.sh` |

## 🧹 Clean up
```bash
./cicd-observability/projects/see-everything/scripts/cleanup.sh              # removes everything this project added, AND Prometheus/Grafana
./cicd-observability/projects/see-everything/scripts/cleanup.sh --keep-monitoring   # keeps Prometheus/Grafana for the Kubernetes monitoring lab
```
It waits until the namespaces are really gone and tells you if anything is still terminating. The registry and the inbox stay (other projects use them); `./cicd-observability/scripts/k8s-down.sh` removes those.

## ✅ What you can now say in an interview
*"I run Prometheus, Alertmanager, Grafana, Loki and Jaeger on Kubernetes with the Prometheus Operator. Rules, dashboards and datasources are code in git, unit-tested with promtool. I define SLOs with burn-rate alerts, and I practise incidents on purpose with a game day."*
