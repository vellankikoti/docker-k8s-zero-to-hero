# ☁️ Track 4: Cloud-Native DevOps, Infrastructure as Code and Production Operations

**From "it runs on my cluster" to "I can rebuild it from a file, change it safely, scale it, back it up, secure it, count its cost, and prove how well my team delivers".**

You will build whole environments with **Terraform**, ship them with a **pipeline that asks before it acts**, then make the app **production-ready**: autoscaling, load balancing, admission policies, tested backups, a night shift that saves money, and DORA metrics read from real release history. Everything runs **on a Kubernetes cluster you already have** (kind, minikube, Docker Desktop, Killercoda, iximuz). No cloud account, no bill.

```
  🧱 a text file builds dev, staging and prod: same blueprint, three sizes
  🔍 terraform plan = the architect's drawing, read BEFORE a single brick is laid
  🛂 a robot inspector refuses "latest" images and ownerless namespaces before anything is built
  💾 wipe the order book, restore the backup, count the orders: 1000 again
  🔥 Diwali rush: the autoscaler opens counters, a Pod is killed mid-rush, customers barely notice
  🕵️ four real company disasters, and the one lock that would have saved each
```

## 🎯 Who this is for
You can run `kubectl apply` ([K04](../kubernetes/04-deployments/README.md)) and have seen a pipeline ([Ship It](../cicd-observability/projects/ship-it/README.md)). Never used Terraform? Perfect: [O01](O01-terraform-first-steps/README.md) starts from zero in 40 minutes.

## 🗺️ The journey
| Lab | You will… | Wow moment |
|---|---|---|
| [**O00** ⭐](O00-foundations/README.md) | **foundations**: IaC, the Terraform vocabulary, the cloud-native workflow, reliability, DORA | 🏗️ "the blueprint is the backup" |
| [**O01**](O01-terraform-first-steps/README.md) | **Terraform first steps**: plan, apply, drift, a Secret that is not secret | 🔍 read a plan like a detective |
| [**O02**](O02-state-modules-environments/README.md) | **state, modules, environments**; `import`, `moved` | 🔒 the lock refuses a second writer |
| [**O03**](O03-iac-in-cicd/README.md) | **infrastructure in a pipeline**: saved plans, policy, approval, image lifecycle, secrets | 🛂 the inspector says no to `latest` |
| [**O04**](O04-scale-balance-survive/README.md) | **autoscaling, load balancing, reliability** | 💀 kill a Pod mid-rush |
| [**O05**](O05-backup-security-cost/README.md) | **backup, security layers, cost, DORA, failure analysis** | 💾 get the order book back |
| [**O06**](O06-managed-kubernetes/README.md) | **managed Kubernetes** (EKS · GKE · AKS), day-2 operations | ☁️ the same workflow, a bigger cluster |
| [🏁 **Infra Factory**](projects/infra-factory/README.md) | **Terraform + a pipeline** provision environments and deploy a containerised app | 🚀 a commit builds prod, after a human says yes |
| [🏁 **Production Ready**](projects/production-ready/README.md) | the **end-to-end project**: CI/CD + Kubernetes + monitoring + policy + backup + cost + DORA | 🪔 survive the Diwali rush |

**Suggested path:** O00 → O01 → O02 → *Infra Factory* (steps 0–5) → O03 → *Infra Factory* (step 6) → O04 → O05 → *Production Ready* → O06.
In a hurry? Do the two projects: each one has a ⭐ live path.

## 🧩 How the whole course connects (use this when you teach it)
| You already know… | …and here it becomes |
|---|---|
| K03 labels, K09 quotas | the **cost-centre labels** and **ResourceQuota** the Terraform module puts on every namespace |
| K13 HPA, K17 PDB | the **autoscaler and budget** Terraform adds to prod; `rush.sh` and `gameday.sh kill` prove them |
| K14 RBAC | the **pipeline's robot** (`terraform-runner`) and the **night shift**, each limited to what it needs |
| K15 NetworkPolicy, K16 Pod Security | the **default-deny** and `restricted` rules in every environment |
| K10 volumes | the **ledger** and its backup disk |
| Ship It (C-track) | the **image** the infra pipeline deploys by tag; the **canary** in case file 4 |
| See Everything | **Prometheus scraping** the prod app (turned on by Terraform) and the alerts that watch it |
| the 60 scenarios | the **drills**: each game-day failure echoes one (`gameday.sh`) |

## 🏁 Run the two projects (the commands, in order)
**Open a terminal in the course folder (the one with `cicd-observability/` and `cloud-native-ops/` inside) and stay there: every command below runs from it.** **Rules that prevent most problems:** run **one project at a time** and run its `cleanup` before the next (a small lab cannot hold two) · start from a healthy cluster (`kubectl get nodes` Ready, `kubectl -n kube-system get pods` all Running; every `up.sh` checks this) · Kubernetes **1.30 or newer** · `git pull` first · if a line shows ✖, read its `→` hint, and if you are stuck, copy that line and everything after it.

### Infra Factory (Terraform): about 1.5 GB free
```bash
./cloud-native-ops/projects/infra-factory/scripts/up.sh             # start (~3 min): installs Terraform for you, no sudo
TF=./cloud-native-ops/projects/infra-factory/infra-repo/scripts/tf.sh      # a short name for the long path
$TF dev plan          # read what WILL happen
$TF dev apply         # build exactly that
./cloud-native-ops/projects/infra-factory/scripts/verify.sh dev          # prove it
```
**Break it:** change the quota by hand with `kubectl`, then `$TF dev drift` finds it, and plan + apply puts it back (steps in the [project README](projects/infra-factory/README.md)).
**Clean up:** `./cloud-native-ops/projects/infra-factory/scripts/cleanup.sh -y`

### Production Ready (operations): about 3 GB free
```bash
./cloud-native-ops/projects/production-ready/scripts/up.sh          # start (~8 min): dev + prod with Terraform, policies, backup
./cloud-native-ops/projects/production-ready/scripts/verify.sh --full 2>&1 | tee /tmp/verify-full.txt     # check + all drills (~5 min)
```
**Break it:**
```bash
GD=./cloud-native-ops/projects/production-ready/scripts/gameday.sh
$GD list          # then: $GD rush | kill | policy | restore | skew
```
**Clean up:** `./cloud-native-ops/projects/production-ready/scripts/cleanup.sh -y`

**Confirmed on a real cluster so far:** Terraform (plan, apply, state, policy, drift, destroy) and Production Ready (install, every check, rush, Pod kill). Not yet confirmed: the Infra Factory Jenkins pipeline (`up.sh --pipeline`).

## 🧰 Before you start
```bash
git clone https://github.com/vellankikoti/docker-k8s-zero-to-hero.git     # skip if you already have it
cd docker-k8s-zero-to-hero
kubectl get nodes                                                          # your cluster answers
```
Terraform is installed for you (no sudo, checksum-verified) by the first `up.sh`. Docker is needed only for the policy checker `conftest` (`$TF dev policy`); without it the scripts tell you what to do.
**Cluster size:** Infra Factory about 1.5 GB free memory; Production Ready about 3 GB; See Everything (CI/CD track) about 2.5 GB. **Run one project at a time on a small lab** (two nodes of ~2 GB cannot hold two of them): `cleanup.sh` one before starting the next. Kubernetes **1.30+** for the admission policies.

## ✅ Every script checks itself, and cleans up after itself
| Script | What it does |
|---|---|
| `projects/*/scripts/up.sh` | installs, then **runs `verify.sh`** so you know it works, not just that it was applied |
| `projects/*/scripts/verify.sh` | one ✔ or ✖ per fact, and the exact command to look with when it is ✖. Changes nothing |
| `projects/*/scripts/cleanup.sh` | removes everything, **through Terraform where Terraform built it**, checks the namespaces are really gone, safe to run twice |
| `gameday.sh` | each drill breaks something on purpose and **checks** the system behaved |

## 🧪 How we test this track
`./cloud-native-ops/scripts/selftest.sh` checks formatting and validity of every Terraform file, the policy's unit tests (conftest), the cost and DORA tools, every script's syntax and every link. `./cloud-native-ops/projects/infra-factory/tests/iac-test.sh` runs the **real Terraform against a real API server as the pipeline's ServiceAccount**: plan, policy pass and refusal, apply, drift detected and repaired, destroy. See the PR notes for what was run on a live cluster and what was not.

## 📁 What is where
```
cloud-native-ops/
├── O00 … O06                      the labs
└── projects/
    ├── infra-factory/             Terraform modules, policies, pipeline, scripts       (infra-repo/ is the repo you push to Git)
    └── production-ready/          admission policies, ledger + backup, night shift, rush, cost, DORA, case files
```
