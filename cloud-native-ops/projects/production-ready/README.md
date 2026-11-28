# 🏁 Production Ready: run the Chai Stall like a real business

> ⏱ about 2.5 hours (the ⭐ steps are a 60-minute live path) · 🔴 Advanced · Needs: any cluster from the Kubernetes labs (Kubernetes **1.30 or newer**), `kubectl`, `helm`, `python3`, `curl`, 3 GB free memory
> **The goal:** take an app that *works* and make it **scale, survive, stay safe, stay backed up, stay affordable, and be measurable.** This is the project that joins everything: Terraform builds it, the pipeline ships it, Prometheus watches it, Kubernetes runs it.

> ⚠️ **Memory:** see-everything (~2.5 GB) and production-ready (~3 GB) are **not meant to run at the same time on a small lab** (two nodes of ~2 GB each cannot hold both). Run one, `cleanup.sh` it, then the other. If the cluster's `kube-controller-manager` or `kube-scheduler` starts crash-looping, the cluster ran out of memory: every `up.sh` checks for that and tells you what to do.

## 🧠 The idea, in one Diwali
Your chai stall works fine on a normal day. Then Diwali comes: **20× the customers**, a cousin accidentally throws away the order book, someone sets the price of chai to ₹1, and the accountant asks why you pay for the stall at 3 a.m. when nobody is there.

| The Diwali problem | The production answer | You will run |
|---|---|---|
| 20× customers | **autoscaling** + **load balancing**: more counters open by themselves, customers are spread evenly | `rush.sh` |
| a counter collapses mid-rush | **self-healing** + a **PodDisruptionBudget**: a replacement opens, the others keep serving | `gameday.sh kill` |
| the order book is thrown away | **backup and restore**, tested: a copy every 5 minutes, and you have *practised* getting it back | `gameday.sh restore` |
| "chai at ₹1" / a tired typo | **policy enforcement**: the rule-keeper (the API server) refuses unsafe changes, whoever you are | `gameday.sh policy` |
| paying for an empty stall at night | **cost automation**: dev and staging close at 10 pm and open at 7 am; every rupee has a name on it | `night-shift.sh`, `cost-report.py` |
| "are we getting better at this?" | **DORA metrics**: how often we ship, how fast, how often it breaks, how fast we recover | `dora.py` |
| "how do big companies fail?" | **case files**: four real incidents, and the lock each one lacked | [`docs/case-files.md`](docs/case-files.md) |

```
        Terraform ──builds──▶ iac-dev, iac-prod  (quota · network rules · RBAC · the Chai Stall · autoscaler · PDB)
            │                      ▲  ▲
   pipeline │ (Infra Factory)      │  └── API server policies: no 'latest', limits required, owner labels required, prod never scaled to 0
            ▼                      │
   customers ──▶ Service ──▶ Pod · Pod · Pod  ◀── HPA adds/removes Pods by CPU          Prometheus + Grafana  (See Everything)
                                                                                          watch it all, email you
   ledger (Redis + disk) ──every 5 min──▶ backup disk ──restore──▶ ledger               night shift: dev off 22:00, on 07:00
```

## 🧰 Step 0: build it all ⭐ (8 minutes, checks itself)
```bash
git pull
./cloud-native-ops/projects/production-ready/scripts/up.sh
```
It runs the Infra Factory basics, installs `metrics-server`, builds **dev** and **prod** with Terraform (after the policy check), applies the admission policies, creates the ledger with its backup, switches on the night shift, and **ends by checking itself**. You want:
```
✔ Production-ready: scaled, balanced, protected, backed up, and measured.
```
*Want monitoring too?* Run the [See Everything](../../../cicd-observability/projects/see-everything/README.md) `up.sh` first, then this one: it notices Prometheus and turns the scraping on by itself.

Everything below also works piece by piece. **Every drill prints ✔ or ✖**, so you never have to guess whether it worked.

## 📈 Step 1: the Diwali rush ⭐ (10 minutes)
Open a second terminal and watch: `kubectl -n iac-prod get hpa,pods -w`. In the first:
```bash
./cloud-native-ops/projects/production-ready/scripts/rush.sh --seconds 90 --workers 4
```
Four customers order as fast as they can for 90 seconds. Read the output:
- **the autoscaler line** (every 15 s): CPU climbs above the 70% target, *"2 Pods now, 4 wanted"*. The HPA is a thermostat for Pods (Lab K13).
- **who served them**: a list of Pod names with counts. Close numbers = the Service **spreads the load** (Lab K05). This is load balancing, made visible.
- **failed: 0**: no customer saw an error.

*Why does prod scale so easily?* The chart asks for `25m` of CPU per Pod, so 70% is only `17m`: the lab scales quickly on purpose. Open [`envs/prod.tfvars`](../infra-factory/infra-repo/terraform/envs/prod.tfvars): *min 2, max 5*. Who decided prod may never go beyond 10? The policy file from the Infra Factory.

## 💀 Step 2: a counter dies in the middle of the rush ⭐ (5 minutes)
```bash
./cloud-native-ops/projects/production-ready/scripts/gameday.sh kill
```
It starts a rush, **kills a Pod** at second 25, and checks that at most 1% of orders failed and that the Deployment is whole again. Why is it nearly clean? (1) there are **2+ Pods**, (2) the **Service** stops sending to a Pod that is going away, (3) the **ReplicaSet** starts a replacement, (4) the **PodDisruptionBudget** stops a voluntary drain from taking the last ones. Four ideas you met in Labs K04, K05, K17, now working together.
*Try it where it hurts:* scale `iac-dev` to its single Pod and kill it during a rush. A handful of failures: *that* is why prod has two.

## 🛡️ Step 3: the rule-keeper ⭐ (10 minutes)
```bash
./cloud-native-ops/projects/production-ready/scripts/gameday.sh policy
```
Four unsafe changes, four refusals:
```
✔ an image with no version: refused (every image needs a version tag, and it must not be 'latest' ...)
✔ production scaled to zero (the one-typo outage): refused (production may not be scaled to zero ...)
```
Read [`manifests/00-policies.yaml`](manifests/00-policies.yaml). Each rule is **one line of CEL** plus a message a human can act on. They are **built into Kubernetes** (`ValidatingAdmissionPolicy`, 1.30+): nothing to install, and they bind **only** to namespaces with a `z2h/owner` label, so your other labs are never affected.
**Roll a rule out the grown-up way:** change one binding's `validationActions: [Deny]` to `[Warn, Audit]`, apply, and run the failing command again: the change **goes through**, with a visible warning. That is how you introduce a rule without breaking everyone's Monday. Put it back to `[Deny]` when you are done.
**Two locks on one door:** the plan-time check (conftest, Infra Factory Step 4) and this admission check protect the same things at different moments. The first is cheap and early; the second cannot be bypassed.

## 💾 Step 4: lose everything, get it back ⭐ (10 minutes)
```bash
S=./cloud-native-ops/projects/production-ready/scripts
$S/ledger.sh seed 1000       # the order book holds 1000 orders
$S/ledger.sh backup          # a backup now (a Job made from the CronJob), and it CHECKS the file
$S/ledger.sh disaster        # "someone ran the wrong command": FLUSHALL. Count: 0.
$S/ledger.sh restore         # stop the ledger, put the newest good backup back, start it, count
```
The count returns to **1000**. Or run all of it as a drill that checks the number: `gameday.sh restore`.
Now think like the owner: the backup runs every 5 minutes, so you may lose **up to 5 minutes** of orders. That number is your **RPO**. The restore took about a minute: that is your **RTO**. Write both on the wall. Which one would you like to be smaller, and what would it cost? (Read [case file 2](docs/case-files.md): five backups, none restorable.)
Open [`10-ledger.yaml`](manifests/10-ledger.yaml) and find the three safety habits: the backup **checks its own output**, the old copies are **pruned** (only the newest 5 stay), and `concurrencyPolicy: Forbid` **never runs two at once**.

## 💸 Step 5: money and the night shift (10 minutes)
```bash
S=./cloud-native-ops/projects/production-ready/scripts
$S/cost-report.py                      # per cost centre: what each environment reserves, and what that would cost
$S/night-shift.sh run-down             # tonight's shutdown, NOW: dev goes to 0 Pods (it remembers how many)
$S/night-shift.sh status
$S/night-shift.sh run-up               # tomorrow morning: back to what it was
```
The cost report only works because **every workload carries `z2h/owner` and `z2h/cost-center` labels** (put there by Terraform, **required** by the admission policy): an unlabelled namespace is named in the report as *"nobody is billed"*. That is **FinOps** in one sentence: *make cost visible, give it a name, then automate the saving.*
The night shift is a **CronJob in Indian time** (`timeZone: Asia/Kolkata`): 22:00 down, 07:00 up. Its permissions are **only** in `iac-dev` and `iac-staging`: `kubectl auth can-i patch deployments/scale -n iac-prod --as=system:serviceaccount:chai-ops:night-shift` says **no**, and the admission policy would refuse anyway. (The rupee rates are an illustrative rate card; change them with `--cpu-rate` and `--mem-rate`.)
*Right-sizing:* once `metrics-server` has data, the report shows how much of the reserved CPU is **used**. Reserved but unused is money paid for nothing. Lower the requests, or let the autoscaler decide.

## 📊 Step 6: are we getting better? DORA ⭐ (10 minutes)
Ship a few changes first, so there is history. For example, from the Infra Factory:
```bash
cd cloud-native-ops/projects/infra-factory/infra-repo
TF_VAR_image_tag=1.5.0 ./scripts/tf.sh prod plan && ./scripts/tf.sh prod apply     # a deployment is one Helm revision
cd - >/dev/null
./cloud-native-ops/projects/production-ready/scripts/dora.py --ns iac-prod --days 30
```
```
  Deployment frequency   0.20 per day       high
  Change failure rate    0%                 elite
  Time to restore        not enough data yet
```
The four numbers research teams use to compare delivery performance:
| Metric | The question | Where we read it |
|---|---|---|
| **Deployment frequency** | how often do we ship? | Helm revisions per day |
| **Lead time for changes** | commit → running in production | `--git ~/infra`: commit time to the next good deploy |
| **Change failure rate** | how many deployments fail or are rolled back? | revisions with status `failed` or `Rollback` |
| **Time to restore** | after a failure, how long until a good release runs? | failed revision → next good one |
Break something on purpose to see the numbers move: `helm upgrade` with a broken value (HELM_DRIVER=configmap), then roll back, then run `dora.py` again. The bands (elite/high/…) are a **rough guide**; the habit that matters is looking at the **trend** every sprint. Frequent small changes make deploys safer, not riskier: that is the whole DORA finding.

## 🕵️ Step 7: how real companies fail ⭐ (15 minutes)
Read [`docs/case-files.md`](docs/case-files.md): Knight Capital (one server on old code), GitLab (five backups, none restorable), Amazon S3 (one typo), Cloudflare (a rule that ate every CPU). For each, find the project's *lock* that practises the missing safeguard (`gameday.sh skew`, `restore`, `policy`, and the canary in Ship It). Then run the whole thing:
```bash
./cloud-native-ops/projects/production-ready/scripts/gameday.sh all       # ~5 minutes: every drill, with ✔/✖
./cloud-native-ops/projects/production-ready/scripts/verify.sh --full     # everything, plus the drills
```

## 🧯 When something is not right
| You see | What it means |
|---|---|
| `up.sh` stops in step 1 | read the line it printed: it is the Infra Factory's `up.sh` (Terraform, registry, image). Fix that first |
| the autoscaler shows `<unknown>/70%` | metrics-server needs ~1 minute, and your Pods must have CPU `requests` (they do). `kubectl top pods -A` |
| a policy refuses a legitimate change | read the message: it says which rule and why. Fix the change, or change the policy **in Git**, never by editing live |
| `the ledger did not start` | `kubectl -n chai-ledger get pods,pvc`: a `Pending` PVC means no StorageClass (Scenario S4.3); `up.sh` falls back to plain Pod storage and tells you |
| `rush.sh` says no Service | build the environments first (Step 0) |
| Kubernetes older than 1.30 | the admission policies need 1.30+; everything else works |

## 🧹 Clean up
```bash
./cloud-native-ops/projects/production-ready/scripts/cleanup.sh                     # policies, ledger, night shift AND the Terraform environments
./cloud-native-ops/projects/production-ready/scripts/cleanup.sh --keep-environments # only the extras; keep dev and prod
```
It removes the admission policies **first** (so they cannot block their own removal), destroys the environments **through Terraform**, and checks that the namespaces are really gone.

## ✅ What you can now say in an interview
*"I make a service production-ready on Kubernetes: autoscaling and a PodDisruptionBudget, admission policies for guardrails, tested backup and restore with stated RPO and RTO, cost visibility and scheduled shutdowns for non-prod, and DORA metrics read from release history. I rehearse failures with game days and write case files."*
