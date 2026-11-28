# O05 · Backup, security, cost and measurement

> ⏱ 75 min · 🟡→🔴 · Needs: [Production Ready](../projects/production-ready/README.md) started (`./cloud-native-ops/projects/production-ready/scripts/up.sh`)
> **Topics:** backup and recovery automation · operational security and policy enforcement · cost optimisation through automation · DevOps metrics (DORA) · real-world failure analysis.

## 1. Backups: two numbers and one test
| Term | Question | Chai stall | In our project |
|---|---|---|---|
| **RPO** (recovery point objective) | how much data may we lose? | "the last 5 minutes of orders" | the backup schedule (5 min) |
| **RTO** (recovery time objective) | how long may we be down? | "back before lunch rush" | the restore takes ~1 minute |
Three rules, each from a real disaster ([case file 2](../projects/production-ready/docs/case-files.md)):
1. **A backup you never restored is a hope.** Practise the restore on a schedule.
2. **The backup checks itself.** Ours refuses to call a file a backup unless it exists and starts with the Redis marker.
3. **A failed backup must shout.** (Add an alert on the CronJob's failures: *"kube_job_status_failed{namespace="chai-ledger"} > 0"*.)
Do it:
```bash
S=cloud-native-ops/projects/production-ready/scripts
$S/ledger.sh seed 1000 && $S/ledger.sh backup && $S/ledger.sh disaster && $S/ledger.sh restore
```
Then ask: where do the backups live? *(a second disk in the same cluster: fine for a lab, not for real)*. A real design copies them **off the cluster** (object storage, another region) and **encrypts** them. Kubernetes objects themselves are "backed up" by Git + Terraform: the **blueprint is the backup** of everything stateless; only *data* needs the other kind. (Tools such as Velero add namespace-level backup of objects and volumes; learn them after this one works.)

## 2. Operational security, in layers
| Layer | The control | Where you met it |
|---|---|---|
| who may do what | **RBAC**, least privilege | the runner, the night shift (`auth can-i`) |
| what a Pod may be | **Pod Security `restricted`** | every namespace here |
| who may talk to whom | **NetworkPolicy**, default deny | `modules/environment` |
| what may enter the cluster | **admission policy** (CEL) | [`00-policies.yaml`](../projects/production-ready/manifests/00-policies.yaml) |
| what may be planned | **policy as code** on the plan (OPA/conftest) | [`plan.rego`](../projects/infra-factory/infra-repo/policy/plan.rego) |
| what may run | **image scanning**, version tags only | Trivy, `z2h-image-needs-a-version` |
| where secrets live | a **secret manager** + a controller (O03) | ladder in O03 |
Policy enforcement has two moments: **early and cheap** (the plan) and **late and unbypassable** (admission). Do the drill: `gameday.sh policy`. Then try the grown-up rollout: set one binding to `[Warn, Audit]`, retry the forbidden command (it passes, with a warning), set it back to `[Deny]`.

## 3. Cost optimisation: make it visible, then automate
FinOps in three sentences: **tag everything** (owner + cost centre), **show the bill by tag**, **automate the saving**.
```bash
$S/cost-report.py          # reservations per cost centre in ₹/month, and what could be saved
$S/night-shift.sh run-down && $S/night-shift.sh status && $S/night-shift.sh run-up
```
Where money hides, in order of size: **idle non-prod** (night shift, weekends), **over-reserved requests** (right-size: the report shows used vs asked), **too many replicas "just in case"** (use the autoscaler), **forgotten environments** (a `cleanup` habit, a TTL label). Notice what made the report possible: the **owner and cost-centre labels** are *required* by policy, so they can never be forgotten.

## 4. DORA: are we getting better?
```bash
$S/dora.py --ns iac-prod --days 30 --git ~/infra
```
| Metric | Elite teams roughly | The trap |
|---|---|---|
| deployment frequency | several per day | counting deploys that change nothing |
| lead time for changes | under a day | measuring from "merge", not "first commit" |
| change failure rate | under ~5–15% | hiding failures by not rolling back |
| time to restore | under an hour | not noticing the failure at all (see alerts: [See Everything](../../cicd-observability/projects/see-everything/README.md)) |
Metrics describe **a system, not people**: never use them to rank engineers. Use them to ask *"what slowed us down this month?"*

## 5. Failure analysis: the habit that compounds
Read the four [case files](../projects/production-ready/docs/case-files.md), then write one for **your own** drill failure in five lines: *what happened · chain of small causes · what the system allowed · the missing lock · the drill that practises it.* A good postmortem is **blameless** ("how did the system let a tired person do that?") and ends with actions that have **owners and dates**.

## ✅ You can now
State RPO/RTO for a service · run and verify a restore · list the layers of security and say which stops what · read a cost report and automate a saving · compute and interpret DORA.
**Next:** [O06 managed Kubernetes](../O06-managed-kubernetes/README.md), then the final drill: `gameday.sh all`.
