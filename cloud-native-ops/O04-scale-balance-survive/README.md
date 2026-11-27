# O04 · Scale, balance, survive

> ⏱ 60 min · 🟡→🔴 · Needs: [Production Ready](../projects/production-ready/README.md) started (`scripts/up.sh`)
> **Topics:** auto-scaling and load balancing · reliability engineering principles · deployment automation across environments.

## 1. The three promises of a reliable service
1. **It keeps working when a part fails** (redundancy + self-healing).
2. **It keeps working when demand grows** (scaling + load balancing).
3. **You can change it without breaking it** (safe rollouts, rollback).
Each one is a feature you already used. Here you **combine** them and *measure* whether they hold.

## 2. Load balancing, made visible
A **Service** is a stable address in front of changing Pods; it spreads connections across the ready ones (Lab K05).
```bash
S=cloud-native-ops/projects/production-ready/scripts
$S/rush.sh --seconds 20 --workers 2
```
Under *"Who served them"* you see each Pod's name with a count. **Equal numbers = the load is shared.** Now ask: *what if only one Pod were ready?* *(all traffic goes to it, and it may fall over: that is why probes decide who is "ready", Lab K08)*

## 3. Autoscaling: a thermostat for Pods
The HorizontalPodAutoscaler watches CPU and adjusts the replica count between a **min** and a **max**:
```bash
kubectl -n iac-prod get hpa chai-stall -o yaml | sed -n '/spec:/,/status:/p'
```
Terraform wrote it (`envs/prod.tfvars`: min 2, max 5, target 70%). Three honest rules for autoscaling:
- **Set requests honestly.** The HPA compares usage with the *request*. Request too little and it scales early; too much and it never scales (and you pay for it).
- **The max is a safety belt.** Without one, a bug that burns CPU also burns your budget. The plan policy refuses a max above 10.
- **It reacts in minutes, not seconds.** For sudden spikes keep a floor (min 2) that already survives the first minute.
Watch it work: `rush.sh --seconds 120 --workers 6` in one terminal, `kubectl -n iac-prod get hpa,pods -w` in another. *Vertical* scaling (bigger Pods) and *cluster* scaling (more nodes) are the other two knobs; on a managed cloud the cluster autoscaler adds nodes when Pods cannot be placed ([O06](../O06-managed-kubernetes/README.md)).

## 4. Surviving failure: the four ideas that work together
| Idea | What it does | You can see it with |
|---|---|---|
| **ReplicaSet** | replaces a dead Pod | `gameday.sh kill` |
| **Readiness probe + Service** | stops sending traffic to a Pod that is not ready or is shutting down | the failed-order count stays ~0 |
| **PodDisruptionBudget** | a planned drain may not take the last Pods | `kubectl -n iac-prod get pdb` |
| **Spread** (anti-affinity, several nodes) | one node dying does not take all copies | Lab K17 |
```bash
cloud-native-ops/projects/production-ready/scripts/gameday.sh kill
```
Read the ✔/✖ lines. Then break the *premise*: scale `iac-dev` (one Pod) and kill it during a rush. A handful of failures appear. **That difference is the value of redundancy**, and the reason prod's minimum is 2.

## 5. Reliability principles (the short list)
- **Design for failure**: assume every part will fail; decide *what then?* in advance.
- **Timeouts and retries with limits**: a call that waits forever holds a thread forever; a retry storm turns a hiccup into an outage.
- **Graceful degradation**: if the payment service is slow, still show the menu.
- **Limit the blast radius**: quotas, PDBs, the "never scale prod to zero" admission policy.
- **Observe, with SLOs**: you cannot improve what you do not measure ([See Everything](../../cicd-observability/projects/see-everything/README.md), [C09](../../cicd-observability/C09-slo-incident-response/README.md)).
- **Practise**: game days beat optimism.

## 6. One blueprint across environments (deployment automation)
dev, staging and prod differ **only in numbers** ([`envs/`](../projects/infra-factory/infra-repo/terraform/envs/)). Promote a version by running the same job per environment: dev → staging → prod, with approval before prod. Two rules: **the same artifact moves forward** (the image tag; never rebuild per environment), and **config is the only thing that changes**.

## ✅ You can now
Show load being shared · explain what makes an autoscaler honest · name the four ideas that make a Pod's death a non-event · state the reliability principles in your own words.
**Next:** [O05 backup, security, cost](../O05-backup-security-cost/README.md).
