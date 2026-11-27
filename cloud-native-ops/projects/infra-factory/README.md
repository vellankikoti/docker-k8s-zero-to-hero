# 🏁 Infra Factory: build whole environments with Terraform, ship them with a pipeline

> ⏱ about 2.5 hours (the ⭐ steps are a 50-minute live path) · 🟡→🔴 · Needs: any cluster from the Kubernetes labs, `kubectl`, `helm`, `python3`, `curl`, and (for Step 6) 3 GB free memory
> **The goal:** create `dev`, `staging` and `prod` **from code**, see exactly what will change *before* it changes, let a robot refuse dangerous plans, catch someone who edits the cluster by hand, and run all of it from a **pipeline with an approval button**.

## 🧠 The idea, in one chai franchise
You run one chai stall. It works. Now you want **three**: a practice stall (dev), a trial stall (staging), the real one (prod).

- **ClickOps** = you walk to each site and tell the workers what to build. Each stall comes out a little different. Nobody remembers who told whom what.
- **Infrastructure as Code** = you hand over **one written blueprint**. Same blueprint, three sites, three sizes. The blueprint sits in Git, so you can read who changed what and when.
- **`terraform plan`** = the architect shows you the drawing **before** a single brick is laid: *"I will add 8 things, change 1, destroy 0."* You approve the drawing, **then** it is built.
- **State** = the architect's notebook of what is already built. If the notebook is lost, he starts building a second stall next to the first. So the notebook lives somewhere safe, and only one person may write in it at a time (**the lock**).
- **Drift** = a worker quietly makes the counter bigger "just this once". The blueprint no longer matches the stall. A drift check finds it.
- **Policy** = a building inspector who reads the drawing and says "no fire exit, I will not allow this" **before** you build.

```
 your repo (the blueprint)
     │  git push
     ▼
 Jenkins pipeline ── fmt+validate ── plan ── policy check ── 🙋 approve ── apply ── verify
     │                                  │         │
     │                                  ▼         ▼
     │                              saved plan   conftest says NO to "latest" images, ownerless namespaces,
     │                                           1-replica prod, runaway autoscalers
     ▼
 Terraform ──▶ your cluster:  iac-dev │ iac-staging │ iac-prod     (each: namespace + quota + network rules + RBAC + the Chai Stall)
     │
     └── state in a Secret in the cluster (namespace tfstate), with a lock
```

## 🧰 Step 0: get ready ⭐ (3 minutes)
```bash
git pull
./cloud-native-ops/projects/infra-factory/scripts/up.sh
```
It installs the `terraform` command if you do not have it (no sudo, SHA-256 checked), a light platform (image registry), builds the Chai Stall image **inside your cluster**, and creates the **state store** and the **runner's permissions**. It ends by checking itself. You want all ✔.

## 🏗️ Step 1: your first environment, by hand ⭐ (10 minutes)
```bash
cd cloud-native-ops/projects/infra-factory/infra-repo
./scripts/tf.sh dev plan          # 1. the drawing
```
Read it. Every `+` is something new. Count the lines at the bottom: *"Plan: 8 to add, 0 to change, 0 to destroy."* Which 8? *(a namespace, a quota, container defaults, two network rules, a role, a binding, the app.)*
```bash
./scripts/tf.sh dev apply         # 2. build exactly that drawing
../scripts/verify.sh dev          # 3. PROVE it: every line should be ✔
```
Look at what you built, with the tools you already know:
```bash
kubectl get ns iac-dev --show-labels          # owner, cost-center, env: who answers, who pays (Lab K03)
kubectl -n iac-dev get resourcequota,limitrange,networkpolicy,role,rolebinding,deploy,svc
helm ls -n iac-dev                            # empty? the release records are ConfigMaps: HELM_DRIVER=configmap helm ls -n iac-dev
```
*Why `HELM_DRIVER=configmap`?* The pipeline's robot may not read Secrets cluster-wide (least privilege, Lab K14), and Helm normally stores releases in Secrets. So here it uses ConfigMaps. A real design decision, written in [`providers.tf`](infra-repo/terraform/providers.tf).

## 📖 Step 2: read the blueprint ⭐ (10 minutes)
| File | What it says |
|---|---|
| [`terraform/main.tf`](infra-repo/terraform/main.tf) | the whole environment in two blocks: *a place* (module `environment`) and *the app* (module `app`) |
| [`modules/environment/main.tf`](infra-repo/terraform/modules/environment/main.tf) | the **landing zone**: namespace (Pod Security `restricted`), quota, defaults, default-deny network, an on-call role |
| [`modules/app/main.tf`](infra-repo/terraform/modules/app/main.tf) | the app = the **same Helm chart** the pipeline uses; Terraform decides where and how big |
| [`envs/dev.tfvars`](infra-repo/terraform/envs/dev.tfvars) vs [`prod.tfvars`](infra-repo/terraform/envs/prod.tfvars) | **only the numbers differ**: replicas, autoscaling, quota. One blueprint, three sizes. |
| [`versions.tf`](infra-repo/terraform/versions.tf) | the **backend**: where the notebook (state) lives |

**Look inside the notebook (state) and its lock:**
```bash
kubectl -n tfstate get secret,lease           # tfstate-default-iac-dev  (the state)   lock-tfstate-default-iac-dev  (the lock)
./scripts/tf.sh dev status                    # every resource Terraform remembers
```
Why a **module**? `environment` is written once and used for dev, staging and prod. Why a **Secret in the cluster** for state? A laptop file is lost with the laptop and cannot be locked; here it is shared, backed up with the cluster, and locked.

## ✏️ Step 3: change something safely, then catch a hand-edit ⭐ (10 minutes)
**A planned change.** Give dev more room: edit [`envs/dev.tfvars`](infra-repo/terraform/envs/dev.tfvars) and change `pods = 6` to `pods = 8`.
```bash
./scripts/tf.sh dev plan          # "Plan: 0 to add, 1 to change": only the quota. Nothing else is touched.
./scripts/tf.sh dev apply
```
**A hand-edit (ClickOps).** Someone "just fixes it quickly":
```bash
kubectl -n iac-dev patch resourcequota environment-budget --type=merge -p '{"spec":{"hard":{"pods":"60"}}}'
./scripts/tf.sh dev drift         # exit code 2 and a diff:   "pods" = "60" -> "8"
./scripts/tf.sh dev plan && ./scripts/tf.sh dev apply        # the blueprint wins; the hand-edit is undone
./scripts/tf.sh dev drift         # ✔ no drift
```
In real teams a scheduled job runs the drift check every night and tells a human. In Step 6 the pipeline has a `drift-check` action that does exactly this.

## 🛂 Step 4: the building inspector ⭐ (10 minutes)
The rules are in [`policy/plan.rego`](infra-repo/policy/plan.rego): no namespace without an **owner** and **cost-center**, no image tagged `latest`, prod needs **≥ 2 replicas and a PodDisruptionBudget**, the autoscaler **ceiling is 10**. They read the plan as JSON:
```bash
./scripts/tf.sh dev plan
docker run --rm -v "$PWD":/p -w /p openpolicyagent/conftest:v0.62.0 test --policy policy .plans/dev.json
```
You should see `8 tests, 7 passed, 1 warning, 0 failures`. Now try to break the rules **in a throwaway experiment file** (nothing committed):
```bash
printf 'replicas = 1\nautoscaling = { enabled = true, min = 2, max = 20, cpu = 70 }\n' > /tmp/bad.tfvars
EXTRA_VAR_FILE=/tmp/bad.tfvars ./scripts/tf.sh prod plan
docker run --rm -v "$PWD":/p -w /p openpolicyagent/conftest:v0.62.0 test --policy policy .plans/prod.json
```
```
FAIL - ... production must run at least 2 replicas
FAIL - ... autoscaling maxReplicas 20 is above the allowed 10
```
**Nothing was built.** The inspector stopped it at the drawing. Also run the policy's own unit tests: `docker run --rm -v "$PWD":/p -w /p openpolicyagent/conftest:v0.62.0 verify --policy policy`.
Then add **your own rule**: for example *"a namespace named `iac-prod` must have a ResourceQuota with at least 4 pods"*. Write it, add a test, run both.

## 🚀 Step 5: dev → staging → prod ⭐ (10 minutes)
```bash
for e in staging prod; do ./scripts/tf.sh $e plan && ./scripts/tf.sh $e apply; done
../scripts/verify.sh                 # checks every environment that exists
kubectl get ns -l app.kubernetes.io/managed-by=terraform --show-labels | cut -c1-120
```
Compare `kubectl -n iac-dev get deploy` with `kubectl -n iac-prod get deploy,hpa,pdb`. Same chart, different tfvars: prod has 2+ Pods, an **autoscaler** and a **PodDisruptionBudget**. That is the whole promise of IaC: *the environments differ only where you wrote down that they differ*.

## 🏭 Step 6: the pipeline (30 minutes, needs the full platform)
Now let a robot do it, with a human approval in the middle.
```bash
./cloud-native-ops/projects/infra-factory/scripts/up.sh --pipeline     # Jenkins + Git server + YOUR ~/infra repo + the job
./cicd-observability/scripts/forward.sh start                         # opens Jenkins (8081) and the Git server (3001)
```
Open Jenkins http://localhost:8081 (admin / `z2h-jenkins`) → **infra-terraform**. The first run only registers the parameters; then **Build with Parameters**.

| Try | Parameters | What you see |
|---|---|---|
| a safe look | `TARGET_ENV=dev` `ACTION=plan-only` | plan in the log, policy ✔, nothing changed |
| a real change | `TARGET_ENV=dev` `ACTION=plan-and-apply` | plan → policy → **⏸ Approval** → apply → verify |
| the inspector says no | `IMAGE_TAG=latest` | **Policy check fails**; nothing applied, no approval asked |
| catch a hand-edit | patch the quota by hand, then `ACTION=drift-check` | the build **fails** and prints the diff |
| a new version | `IMAGE_TAG=1.0.1` (first: `./cicd-observability/scripts/ensure-image.sh 1.0.1`) | a rolling update through Terraform |

Read the pipeline: [`infra-repo/Jenkinsfile`](infra-repo/Jenkinsfile). It runs the **same** `scripts/tf.sh` you ran by hand, in a Pod whose identity is `terraform-runner`: [`platform/00-tfstate-and-runner.yaml`](platform/00-tfstate-and-runner.yaml) shows what it may and may not do (it can build namespaces; it **cannot** touch nodes or read Secrets elsewhere: `verify.sh` proves both). Change something in `~/infra`, `git commit`, `git push`, and run the job again: **change management with a trail**.

**The image's life** is part of this loop too: *build* (Kaniko, in the Ship It project) → *tag* (a version, never `latest`) → *scan* (Trivy) → *deploy by tag* (this pipeline) → *roll back by tag* (put the old tag back in Git, run again).

## 🧯 When something is not right
| You see | What it means |
|---|---|
| `terraform: command not found` | `./cloud-native-ops/projects/infra-factory/infra-repo/scripts/install-terraform.sh`, then the `export PATH` line it prints |
| `namespaces "tfstate" not found` | you skipped `up.sh` |
| `Error acquiring the state lock` | another apply is running (or one was killed). Look: `kubectl -n tfstate get lease`. If you are sure nothing runs: `kubectl -n tfstate delete lease lock-tfstate-default-iac-dev` |
| `apply` says *no saved plan* | by design: run `plan` first. A saved plan is single-use, so what you reviewed is what runs |
| pods stay `ImagePullBackOff` | the image is missing: `./cicd-observability/scripts/ensure-image.sh` |
| `forbidden` when the **pipeline** runs | the runner lacks a permission the code now needs: add it to `platform/00-tfstate-and-runner.yaml` **in a reviewed change**, not by hand |
| the Jenkins job is missing | `up.sh --pipeline` creates it; or re-run `scripts/new-infra-repo.sh ~/infra2` |

## 🧹 Clean up
```bash
./cloud-native-ops/projects/infra-factory/scripts/cleanup.sh              # destroys every environment THROUGH Terraform, then removes the state store and the runner's permissions
./cloud-native-ops/projects/infra-factory/scripts/cleanup.sh --keep-platform   # only the environments
```
It checks that the namespaces are really gone. (`rm -rf ~/infra` removes your repo copy; the Git server's copy goes with `k8s-down.sh`.)

## ✅ What you can now say in an interview
*"I define environments as Terraform modules with per-environment variables and remote, locked state. Plans are saved, policy-checked with OPA/conftest, approved by a human and applied from a pipeline running under a least-privilege identity. I detect drift on a schedule."*
