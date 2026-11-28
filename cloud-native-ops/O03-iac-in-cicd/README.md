# O03 · Infrastructure in the pipeline: plan, policy, approve, apply

> ⏱ 60 min · 🟡→🔴 · Needs: [O02](../O02-state-modules-environments/README.md) and the full platform (`./cloud-native-ops/projects/infra-factory/scripts/up.sh --pipeline`)
> **Topics:** CI/CD-driven infrastructure deployment · automated provisioning and change management · container image lifecycle · configuration and secret management across environments · operational security.

## 1. Why a pipeline at all?
By hand, "apply" depends on **who** runs it, **from which laptop**, with **which credentials**, at **what mood**. A pipeline gives you one place, one identity, one record.
```
 commit ─▶ fmt + validate ─▶ PLAN (saved) ─▶ POLICY ─▶ 🙋 approve ─▶ APPLY (the saved plan) ─▶ verify
```
- **Saved plan.** `plan` writes a file; `apply` takes *that file*. Between the review and the apply, nothing can change what runs. ([`tf.sh`](../projects/infra-factory/infra-repo/scripts/tf.sh) refuses to apply without one.)
- **Policy as code.** Rules in a language ([Rego](../projects/infra-factory/infra-repo/policy/plan.rego)) read the plan and say no *before* anything is built.
- **Approval.** Always for prod ([`Jenkinsfile`](../projects/infra-factory/infra-repo/Jenkinsfile)), whatever the checkbox says.
- **Least privilege.** The build Pod runs as ServiceAccount `terraform-runner`: [`00-tfstate-and-runner.yaml`](../projects/infra-factory/platform/00-tfstate-and-runner.yaml) lists what it may do. It **can** create namespaces; it **cannot** touch nodes or read Secrets elsewhere.

## 2. Hands-on: the pipeline (30 min)
Follow Step 6 of [Infra Factory](../projects/infra-factory/README.md#-step-6-the-pipeline-30-minutes-needs-the-full-platform). Do these five builds and **say out loud what you expect before each**:
1. `plan-only` on `dev`: what does the log show? What changed in the cluster? *(nothing)*
2. `plan-and-apply` on `dev`: where does it pause? What would happen if nobody clicks?
3. `IMAGE_TAG=latest`: which stage fails? Was anything built? Was a human bothered?
4. hand-edit the quota, then `drift-check`: what does the failure message contain?
5. `plan-and-apply` on `prod`: why is approval asked even if you unticked the box?

## 3. Container image lifecycle automation
An image has a life: **build → test → scan → tag → publish → deploy → (roll back) → retire.** Each arrow should be automatic and each tag immutable.
| Stage | Where it is automated | Rule |
|---|---|---|
| build | [Ship It](../../cicd-observability/projects/ship-it/README.md) pipeline (Kaniko, no Docker socket) | the version is `1.0.<build number>`: unique, never reused |
| scan | Trivy stage (`SCAN_MODE`) | CRITICAL findings block in `enforce` mode |
| deploy | **this pipeline**: `IMAGE_TAG` is a parameter, Terraform releases that tag | `latest` is refused by the plan policy **and** the admission policy |
| roll back | put the old tag back in Git/parameter and run again | a rollback is just another deploy: same checks, same trail |
| retire | the registry deletes tags older than N builds | keep what production ran in the last 90 days |
Try it: `./cicd-observability/scripts/ensure-image.sh 1.5.1`, then run the job with `IMAGE_TAG=1.5.1`, watch a rolling update, then run it with `IMAGE_TAG=1.5.0`: that *is* a rollback.

## 4. Config and secrets across environments
**Configuration** (not secret) belongs in Git, per environment: `envs/dev.tfvars`, Helm values. **Secrets** do not. The ladder, from worst to best:
| Level | Example | Verdict |
|---|---|---|
| a password in the code | `token = "abc123"` in `main.tf` | ❌ it is in Git forever |
| a Terraform variable from the environment | `TF_VAR_admin_token` set in the pipeline | OK for a lab; **the state still stores it in clear text** (O01) |
| a Kubernetes Secret created by hand | `kubectl create secret` | not reviewable, not repeatable |
| **a secret manager + a controller in the cluster** | External Secrets / Sealed Secrets / SOPS: Git holds an *encrypted* or *reference* form; the cluster decrypts | ✔ what teams use |
In this lab's Jenkins the `deploy-token` credential is injected from a Kubernetes Secret by JCasC ([C04](../../cicd-observability/C04-artifacts-secrets-security/README.md): masked in logs, still leakable by `echo`). Whatever you choose: **rotate** (change regularly), **scope** (one purpose each), **audit** (who read it).

## 5. Change management, in plain words
A *change request* answers: **what, why, who approved, how do we undo it, how do we know it worked?** In this pipeline each answer is a file or a button: the **plan** (what), the **commit message** (why), the **Approval stage** (who), the **previous tag/state** (undo), the **Verify stage** and the drift check (it worked). That *is* change management, with no paperwork.

## ✅ You can now
Explain saved plans, policy gates, approvals and least-privilege runners · automate an image's life by tag · place a secret on the right rung of the ladder.
**Next:** [O04 scale, balance, survive](../O04-scale-balance-survive/README.md).
