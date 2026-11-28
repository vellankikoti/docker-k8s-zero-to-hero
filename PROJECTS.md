# 🏁 The four projects: start here

Four hands-on projects that build on the Docker and Kubernetes tracks. Each one is run the same way as the Kubernetes scenarios: **start it → check it → break it → clean it up.** Every script prints ✔ or ✖, and every ✖ names the command to look with.

| # | Project | You build | Time | Needs |
|---|---|---|---|---|
| 1 | [**Ship It**](cicd-observability/projects/ship-it/README.md) | a CI/CD factory: Git → Jenkins → registry → staging → production, with rollback | 2–3 h | ~3 GB free |
| 2 | [**See Everything**](cicd-observability/projects/see-everything/README.md) | metrics, logs, traces and alert emails for a live app, then break it on purpose | ~2 h | ~2.5 GB free |
| 3 | [**Infra Factory**](cloud-native-ops/projects/infra-factory/README.md) | Terraform builds dev, staging and prod; a policy refuses bad plans; a pipeline asks before it applies | ~2.5 h | ~1.5 GB free |
| 4 | [**Production Ready**](cloud-native-ops/projects/production-ready/README.md) | autoscaling, load balancing, admission rules, a backup you restore, night-shift cost saving, DORA | ~2.5 h | ~3 GB free |

## The 5 rules (they prevent almost every problem we have seen)
1. **One project at a time.** Run the project's `cleanup.sh` before starting the next. A small lab (two nodes of ~2 GB) cannot hold two.
2. **Start from a healthy cluster:** `kubectl get nodes` shows Ready, and `kubectl -n kube-system get pods` shows everything `Running`. Every `up.sh` checks this and tells you what to fix.
3. **Kubernetes 1.30 or newer** (the admission rules in project 4 need it).
4. **Run `git pull` first**, then the commands in the order below. Do not skip the check step.
5. **If a line shows ✖:** read the `→` hint under it. Still stuck? Copy that line and everything after it.

## The path, project by project

### 1 · Ship It (CI/CD)
```bash
./cicd-observability/scripts/doctor.sh --k8s           # ready?
./cicd-observability/scripts/k8s-up.sh                 # start: Jenkins, Git server, registry (~15 min)
./cicd-observability/scripts/forward.sh start          # open the doors: Jenkins :8081, Git :3001
./cicd-observability/scripts/new-app-repo.sh           # your own repo, pushed to the in-cluster Git server
```
Then open Jenkins (http://localhost:8081, admin / `z2h-jenkins`) → **chai-stall → ci-cd → Build with Parameters** and follow [the project's phases](cicd-observability/projects/ship-it/README.md#-the-phases).
**Check:** `./cicd-observability/projects/ship-it/scripts/verify.sh 3` · **Clean up:** `./cicd-observability/scripts/k8s-down.sh -y`

### 2 · See Everything (observability)
```bash
./cicd-observability/projects/see-everything/scripts/up.sh          # start (~8 min); it checks itself at the end
./cicd-observability/scripts/forward.sh start observability         # Grafana :3000, Prometheus :9090, inbox :8025
```
**Break it:** `./cicd-observability/projects/see-everything/scripts/gameday.sh list`, then
`gameday.sh start errors` → `gameday.sh watch OrderSLOFastBurn` (about 4 minutes) → `gameday.sh recover`.
**Check:** `./cicd-observability/projects/see-everything/scripts/verify.sh` · **Clean up:** `./cicd-observability/projects/see-everything/scripts/cleanup.sh -y`

### 3 · Infra Factory (Terraform)
```bash
./cloud-native-ops/projects/infra-factory/scripts/up.sh             # start (~3 min): installs Terraform for you, no sudo
cd cloud-native-ops/projects/infra-factory/infra-repo
./scripts/tf.sh dev plan          # read what WILL happen
./scripts/tf.sh dev apply         # build exactly that
../scripts/verify.sh dev          # prove it
```
**Break it:** change the quota by hand with `kubectl`, then `./scripts/tf.sh dev drift` (finds it) and plan + apply (puts it back). Step-by-step in the [README](cloud-native-ops/projects/infra-factory/README.md).
**Clean up:** `./cloud-native-ops/projects/infra-factory/scripts/cleanup.sh -y`

### 4 · Production Ready (operations)
```bash
./cloud-native-ops/projects/production-ready/scripts/up.sh          # start (~8 min): builds dev + prod with Terraform, policies, backup
./cloud-native-ops/projects/production-ready/scripts/verify.sh --full 2>&1 | tee /tmp/verify-full.txt     # check + all drills (~5 min)
```
**Break it:** `gameday.sh list` (in the same folder): `rush`, `kill`, `policy`, `restore`, `skew`.
**Clean up:** `./cloud-native-ops/projects/production-ready/scripts/cleanup.sh -y`

## What has been run on a real cluster, and what has not
| Project | Confirmed on a real cluster | Not yet confirmed |
|---|---|---|
| Ship It | platform, Git → build → scan → push → staging deploy | the approval, production release, blue/green and canary stages |
| See Everything | install, every check, the `errors` incident with its alert email and recovery | the other four incidents (`slow`, `crashloop`, `bad-image`, `outage`) |
| Infra Factory | Terraform: plan, apply, state, policy, drift, destroy | the Jenkins pipeline (`up.sh --pipeline`) |
| Production Ready | install, every check, rush, Pod kill | the backup-restore, policy and skew drills as the last step of `verify.sh --full` (they printed "drill passed") |

If you run one of the "not yet confirmed" parts and it fails, send the first ✖ line and everything after it: that is how every other bug in this list was found and fixed.
