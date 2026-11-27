# 🏁 Project 1: Ship It: a CI/CD Factory on Kubernetes (Lab Exercise 7)

> **Syllabus lab exercise 7:** *Create CI/CD pipelines using Jenkins and GitHub Actions or GitLab CI with automated build and deployment stages.*
>
> ⏱ 2–3 hours · 🟡→🔴 · Needs: your course cluster (kind / Docker Desktop / minikube / Killercoda), `kubectl`, `helm`, about 3 GB of free memory, and [K05](../../../kubernetes/05-services/README.md) to [K16](../../../kubernetes/16-pod-security/README.md) under your belt. No cluster? Use the [Docker Compose edition](../../compose-edition/README.md).
>
> **After every phase run `./cicd-observability/projects/project-1-ship-it/scripts/verify.sh N`**: it asks the cluster and prints ✔ or ✖ with a hint.

## 🎯 The mission
The Chai Stall is deployed by an engineer typing `kubectl apply`. It broke production twice last month. **Build the factory that ships it, inside your cluster**: a commit is tested, scanned, built into an image, published, deployed to staging, approved by a human, and released to production with a strategy that **rolls itself back**. Then prove that every gate stops a different kind of bad change.

```mermaid
flowchart LR
  DEV[👩‍💻 git push] --> GT[(Gitea<br/>namespace cicd)]
  GT -->|webhook| JK
  subgraph JK [Jenkins · namespace cicd · one build Pod per run]
    T[🧪 test] --> C[⚡ secret scan ‖ chart + API-server check] --> B[📦 Kaniko build] --> S[🔍 Trivy] --> PU
  end
  PU[(registry<br/>:5000 / NodePort 30500)] --> ST[🧱 stall-staging<br/>helm release chai-stall]
  ST --> AP{🙋 approval}
  AP --> RT{{🚦 Gateway + HTTPRoute<br/>weights}}
  RT -->|"100/0 · 0/100 · 80/20"| BL[chai-blue]
  RT --> GR[chai-green]
  GR -.canary check fails.-> RB[↩ weights back, build red]
```

## 🧩 Every piece is something you already know
| In this project | You met it in | Where it shows |
|---|---|---|
| a build agent that is a **Pod**, deleted afterwards | K02, K20 | `kubectl -n cicd get pods -w` while a build runs |
| the pipeline may deploy to two namespaces and **nowhere else** | K14 RBAC | `kubectl auth can-i … --as=system:serviceaccount:cicd:jenkins-agent` |
| registry and Git server with **volumes** | K10 PVCs | `kubectl -n cicd get pvc` |
| the app's **probes, limits, PDB, securityContext** | K08, K09, K17, K16 | [`chart/chai-stall`](../../k8s/chart/chai-stall/templates/deployment.yaml) |
| namespaces **enforce `restricted`** | K16 Pod Security | a root Pod is refused by the API server |
| **rolling update**, **Recreate** | K06 | `strategy:` in the chart |
| **blue/green** and **canary** by traffic **weights** | K05, K12 | `kubectl -n stall-prod get httproute chai -o yaml` |
| a release that fails **prints why, then rolls back** (`helm rollback`, weights) | K06 `rollout undo` | `helm history` |
| secrets as env from a **Secret** | K07 | `jenkins-lab-secrets` |
| a failing pipeline step ≈ a scenario you solved | S1–S6 | the [scenario map](#-when-the-pipeline-fails-it-is-a-scenario-you-have-solved) at the end |

## 📋 The phases

| # | Phase | You prove | Time |
|---|---|---|---|
| 0 | Pre-flight | the cluster and tools are ready | 5 m |
| 1 | **Install the platform** | registry, Git server, Jenkins, Gateway run in your cluster | 15 m |
| 2 | **Your repo → Git server → Jenkins** | a push reaches Jenkins; jobs are generated from Git | 10 m |
| 3 | **The first green pipeline** | test → build → scan → push → staging → production | 25 m |
| 4 | **Ship a feature, test-first** | a `git push` reaches production by itself | 25 m |
| 5 | **Release four ways** | recreate, rolling, blue/green, canary + automatic rollback | 30 m |
| 6 | **Break it on purpose** | seven gates, seven different failures | 30 m |
| 7 | Extend the factory | your own check, button, stage | 20 m |
| 8 | The same pipeline on GitHub Actions / GitLab CI | a second CI runs it | 30 m |
| 9 | Clean up | | 5 m |

---

## Phase 0: Pre-flight (5 min)
```bash
./cicd-observability/scripts/doctor.sh --k8s
kubectl config current-context        # must be your THROWAWAY course cluster (kind-… / docker-desktop / minikube)
kubectl get nodes                     # all Ready
```
Fix every ✖. A classic: the context points at a cluster that is not yours. (No default StorageClass is only a note: `k8s-up.sh` then falls back to plain Pod storage for the registry and Git server, see the troubleshooting table.)

> 💡 Cluster too small? The platform needs about 3 GB. Docker Desktop: Settings → Resources → 6 GB+. No Gateway controller yet? Phase 1 installs one (the K12 one).

## Phase 1: Install the platform (15 min)
```bash
./cicd-observability/scripts/k8s-up.sh
./cicd-observability/projects/project-1-ship-it/scripts/verify.sh 1
```
It takes 5 to 10 minutes (images, Jenkins plugins). While you wait, read what it installs: [`k8s/platform/`](../../k8s/platform/):

| File | What it creates | Lab |
|---|---|---|
| `00-namespaces.yaml` | `cicd`, `stall-staging`, `stall-prod`; the last two **enforce Pod Security `restricted`** | K16 |
| `rbac.yaml` | ServiceAccount `jenkins-agent` and a Role in each stall namespace | K14 |
| `registry.yaml` | the image registry (PVC + two Services: cluster DNS and NodePort 30500) | K05, K10 |
| `gitea.yaml` | a Git server for *your* app repo | K04 |
| `jenkins-values.yaml` | Jenkins by Helm: **configured as code**, secrets from a Secret | K19, K20 |
| `prod-gateway.yaml` | production's `Gateway` + `HTTPRoute` | K12 |

### Look around (10 min): the cluster tells you everything
```bash
kubectl get pods -A | grep -vE 'kube-system|Running|Completed'     # nothing listed = all healthy
kubectl -n cicd get pods,svc,pvc
kubectl get ns --show-labels | grep -E 'cicd|stall'                # see the pod-security labels
```
Now two things you already know, in a new setting:
```bash
# 1. least privilege (K14): what may the PIPELINE'S ServiceAccount do?
kubectl auth can-i create deployments -n stall-prod  --as=system:serviceaccount:cicd:jenkins-agent    # yes
kubectl auth can-i create deployments -n kube-system --as=system:serviceaccount:cicd:jenkins-agent    # no

# 2. Pod Security (K16): the production namespace refuses a normal Pod
kubectl run rootpod --image=nginx -n stall-prod --dry-run=server
```
Read the refusal: *violates PodSecurity "restricted:latest"*. **Every image the pipeline ships must satisfy this**, or production will refuse it. That rule is your first, free, always-on security gate.

> 🔤 **One registry, two names.** Build Pods push to `registry.cicd.svc.cluster.local:5000` (cluster DNS). The node's kubelet cannot resolve cluster DNS, so it pulls from `localhost:30500` (the NodePort). Same bytes, same digest, two addresses. When an image "can't be pulled", ask first *who is pulling, and from where?* (Scenario S1.2.)

## Phase 2: Your repo → Git server → Jenkins (10 min)
Open the doors into the cluster, then create **your own** copy of the app:
```bash
./cicd-observability/scripts/forward.sh start
./cicd-observability/scripts/new-app-repo.sh
./cicd-observability/projects/project-1-ship-it/scripts/verify.sh 2
```
| Door | URL | Login |
|---|---|---|
| Jenkins | http://localhost:8081 | `admin` / `z2h-jenkins` |
| Git server | http://localhost:3001 | `z2h` / `z2h-gitea-pass` |
| Inbox | http://localhost:8025 | none |
| Staging | http://localhost:8082 | none |
| Production | http://localhost:8090 | none |

### 🧭 Who owns what (so nothing ever needs copying)
| | **The platform** (installed by `k8s-up.sh`) | **Your repo** (`~/chai-stall`) |
|---|---|---|
| What | the **logic of every pipeline stage** ([`k8s/pipeline/`](../../k8s/pipeline/): `stage.sh`, `k8s-deploy.sh`, `diagnose.sh`, …), the Jenkins and cluster setup | your **code** (`app/`), your **chart** (`chart/`), and the **shape** of your pipeline (`Jenkinsfile`: which stages, in which container, when) |
| Where it lives | a ConfigMap `z2h-pipeline`, mounted at `/opt/z2h` in every build Pod | your Git repository |
| Who changes it | the course, for everyone | you |
| To get a fix | `git pull` in the course repo, then **`./cicd-observability/scripts/k8s-up.sh`** (the one command you already know) | nothing: it is yours |

So a bug fix in how a stage works reaches everyone with one command and **no file is ever copied into your repo**. The same split exists in companies: a platform team owns the shared pipeline logic, product teams own their code and a small pipeline definition.

### 🌐 Using Killercoda or iximuz Labs (a browser lab)?
In a browser lab the cluster and your terminal live in a remote VM, so `http://localhost:8081` in *your* browser is **not** that VM. Two things make it work:

1. **`forward.sh start` detects the lab** (you are the user `laborant`) and listens on **all interfaces** instead of only `127.0.0.1`, because the lab's "open a port" feature reaches the VM from outside and cannot see a loopback-only listener. (Force it with `forward.sh start --lab`; force local-only with `--local`.)
2. **Expose each port with your lab's port feature** and open the link it gives you:

| Door | Port to expose | Killercoda |
|---|---|---|
| Jenkins | `8081` | menu → **Traffic / Ports** → enter `8081` |
| Git server | `3001` | same, `3001` |
| Inbox | `8025` | same, `8025` |
| Staging | `8082` | same, `8082` (after the first pipeline run) |
| Production | `8090` | same, `8090` |

In **iximuz Labs** use the lab's own port-exposing panel with the same port numbers. Inside the lab terminal nothing changes: `curl`, `git push` and `kubectl` keep using `http://localhost:PORT`.

> Jenkins and Gitea were tested behind a proxy that changes the client address (Jenkins would otherwise answer **403 "No valid crumb"** to every *Build Now* click: the platform sets `excludeClientIPFromCrumb`). A yellow "reverse proxy set up is broken" notice in Jenkins' bell menu can appear in a lab; it is cosmetic and can be dismissed. If a page loads but a button fails, tell us which one.

> 📌 **Your app repo is not the course repo.** `new-app-repo.sh` made `~/chai-stall` and pushed it to the Git server *inside your cluster*. You commit and push **there**. No GitHub account, no tokens, and **nothing you do can touch the shared course repository.** (This also removes the old "which branch is Jenkins building?" confusion: Jenkins always builds `main` of `chai-stall`.)

```bash
cd ~/chai-stall && git log --oneline && git remote -v        # an ordinary Git repository with one commit
ls                                                           # app/  chart/  ci/  jenkins/  Jenkinsfile  Jenkinsfile.dynamic  pipeline-config.json
```
In **Gitea** (http://localhost:3001/z2h/chai-stall) look at *Settings → Webhooks*: one webhook points at Jenkins. In **Jenkins** open the **chai-stall** folder: `ci-cd`, `dynamic-checks`, `secrets-demo` and the `ops-*` buttons. Nobody clicked "New Item": the seed job read [`jenkins/jobs/*.groovy`](app-repo/jenkins/jobs/pipelines.groovy) from your repo and created them (Lab C03).

## Phase 3: The first green pipeline (25 min)
In a second terminal, watch the cluster work:
```bash
kubectl -n cicd get pods -w
```
In Jenkins open **chai-stall → ci-cd → Build Now**. (The first build only teaches Jenkins the pipeline's parameters; from the next one the button says **Build with Parameters**.)

**Watch the Pod appear.** A Pod named after the build starts with **five containers** (`jnlp` plus the four from [`ci/pod.yaml`](app-repo/ci/pod.yaml): `python`, `tools`, `kaniko`, `trivy`) and disappears when the build ends. Open one while it runs:
```bash
kubectl -n cicd describe pod -l jenkins=slave | grep -E 'Image:|Service Account|Containers:' 
```
The pipeline's stages, in [`Jenkinsfile`](app-repo/Jenkinsfile) (each stage's logic is in the platform's [`stage.sh`](../../k8s/pipeline/stage.sh): open it, it is short):

`Checkout → Test → [Secret scan ‖ Chart: lint + ask the API server] → Build image (Kaniko) → Scan image (Trivy) → Record the artifact → Deploy to staging → Approval → Release to production`

Things to notice:
- **Chart: lint + ask the API server** renders the Helm chart and sends it to the real API server with `--dry-run=server`: *the cluster itself* validates it (including Pod Security) **before** anything is built.
- **Kaniko** builds the image *without* a Docker daemon or the Docker socket, then pushes it to the registry. (The Compose edition mounted the Docker socket, which is root on the host; here, no.)
- **Deploy to staging** is `helm upgrade --install --wait`, then `helm test`. If the release is not healthy within 3 minutes, the build log first prints **the evidence** (Helm's message, the Deployment and Pods, the events, why each Pod is unhappy, what the containers printed: [`diagnose.sh`](../../k8s/pipeline/diagnose.sh)) and **only then rolls back**. (A plain `--atomic` rolls back first and deletes the very Pods you would need to look at.)
- At **Approval** the pipeline stops and waits for you. Press **Ship it**.

> ⚠️ **If "Scan image (Trivy)" fails**, open its log. If the message is about **downloading the vulnerability database**, the build Pod cannot reach the internet host the scanner needs (`mirror.gcr.io` / `ghcr.io`): common in locked-down labs. In `enforce` mode that is the gate failing *closed*, which is correct. Run **Build with Parameters** and choose:
> - `SCAN_MODE=report`: the scan runs and shows findings, but **nothing it reports (or fails to do) blocks the build**. A scanner that cannot start prints a ⚠ line and the pipeline continues.
> - `SCAN_MODE=skip`: do not scan at all (labs only, never real life).
>
> Either way the rest of the pipeline (staging, approval, production) runs, so you can keep going while the network question is sorted out.

When it is green:
```bash
./cicd-observability/projects/project-1-ship-it/scripts/verify.sh 3
./cicd-observability/projects/project-1-ship-it/scripts/verify.sh 4
curl -s localhost:8082/api/info          # staging
curl -s localhost:8090/api/info          # production, through the Gateway
kubectl get deploy,pods,svc -n stall-staging
kubectl get deploy,pods,svc,httproute -n stall-prod
helm list -A
```
Open the build page: **Build Artifacts → `build-info.json`** holds the version, the image, its **digest** and the commit. That one file answers "what exactly runs in production, and where did it come from?" (Lab C04). Run it again with **Build with Parameters** and `REQUIRE_APPROVAL` unticked: no stop at all. That is continuous *deployment*; the first run was continuous *delivery*.

## Phase 4: Ship a feature, test-first (25 min)
The festival is coming: add **vada** (₹8). In **your** repo, the way a real team does: failing test first, then the code.

**4a. 🔴 Red: push only the test.**
```bash
cd ~/chai-stall
cat > app/tests/test_menu.py <<'EOF'
"""The menu has vada (a new item for the festival season)."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import app  # noqa: E402


class MenuTests(unittest.TestCase):
    def test_vada_is_on_the_menu_for_8_rupees(self):
        self.assertEqual(app.MENU.get("vada"), 8)


if __name__ == "__main__":
    unittest.main()
EOF
git add -A && git commit -m "test: vada should be on the menu" && git push
```
Nothing else to press: the **webhook** starts a build within seconds. Watch `kubectl -n cicd get pods -w`: a build Pod appears, runs the tests, and the build goes **red at *Test***. Nothing was built, pushed or deployed: the stages after it were skipped. A broken change was stopped by a machine.

**4b. 🟢 Green: make it pass.**
```bash
sed -i.bak 's/"biscuit": 5}/"biscuit": 5, "vada": 8}/' app/app.py && rm app/app.py.bak
python3 -m unittest discover -s app/tests 2>&1 | tail -3        # passes on your laptop first (skip if python3 is not installed)
git commit -am "feat: add vada to the menu" && git push
```
The build goes through to **Approval**. Press **Ship it**, then:
```bash
curl -s -X POST 'localhost:8090/order?item=vada'               # {"ok": true, "item": "vada", "price_inr": 8, ...}
kubectl -n stall-prod get pods -o wide                         # the Pods that serve it
helm history chai-blue -n stall-prod                           # which revision is that? (or chai-green)
```
✔ Your `git push` reached production, and you never typed a deploy command.

<details><summary>🧯 No build started after the push?</summary>

1. Gitea → your repo → **Settings → Webhooks → the hook → Recent Deliveries**: a red delivery shows the reason.
2. Jenkins also **polls every ~2 minutes** as a safety net. Wait, or press **Build Now**.
3. `git remote -v` must show `localhost:3001`; `./cicd-observability/scripts/forward.sh status` must show the Git server door open.
</details>

## Phase 5: Release four ways (30 min)
Use **Build with Parameters**; set `REQUIRE_APPROVAL` off to move faster. Keep `kubectl -n stall-prod get pods -w` open in a terminal and **watch the Pods**: that is the strategy, made visible.

| Try | Parameters | What you will see |
|---|---|---|
| **Blue/Green** | `STRATEGY=bluegreen` | the new version appears in the *idle* colour (`chai-green`), `helm test` passes, then the weights flip: `kubectl -n stall-prod get httproute chai -o jsonpath='{.spec.rules[0].backendRefs[*].weight}'` |
| **Rolling** | `STRATEGY=rolling` | the live release is updated **in place**, Pod by Pod: a new Pod appears, becomes Ready, an old one terminates (`maxSurge 1, maxUnavailable 0`, Lab K06) |
| **Recreate** | `STRATEGY=recreate` | **all** old Pods terminate first, then new ones start: **an outage**. Prove it: `while true; do curl -s -o /dev/null -w '%{http_code} ' localhost:8090/api/info; sleep 0.3; done` and count the non-200s |
| **A good canary** | `STRATEGY=canary`, `CANARY_PERCENT=40` | 40% of traffic goes to the idle colour; the check judges *that colour's own* answers; the canary is **promoted** |
| **A bad canary** | `STRATEGY=canary`, **`INJECT_BUG` ticked**, `CANARY_PERCENT=40` | the check reports ~30% errors, the pipeline **sets the weights back by itself** and the build is red |

For the bad canary read the console: `chai-green…: 12 failed of 40 requests = 30% (limit 5%)`, then `canary removed: 100% of traffic back to chai-blue`. Confirm:
```bash
kubectl -n stall-prod get httproute chai -o jsonpath='{range .spec.rules[0].backendRefs[*]}{.name}={.weight} {end}'; echo
helm list -n stall-prod                                      # both releases exist; only one gets traffic
./cicd-observability/projects/project-1-ship-it/scripts/verify.sh 5
```
Use the **ops-\* buttons** (Jenkins → chai-stall → **Operations**) for manual control: `ops-status`, `ops-rollback`, `ops-promote`, `ops-retire` (scale the idle colour to 0). They run [`k8s/pipeline/k8s-deploy.sh`](../../k8s/pipeline/k8s-deploy.sh) as the pipeline's own ServiceAccount.

**Read the script once** (about 190 lines of `helm` and `kubectl`): *every* strategy is a handful of Kubernetes commands you already know. There is no magic in a deployment strategy: it is **which weights, when**.

## Phase 6: Break it on purpose (30 min)
A pipeline you have never seen *fail* is a pipeline you do not trust. Break it, one way at a time, in `~/chai-stall`, watch the right gate stop it, then undo with `git revert --no-edit HEAD && git push`.

| # | Break | How | Which gate stops it | The Unit 3 scenario it echoes |
|---|---|---|---|---|
| A | a **failing test** | Phase 4a | *Test* stage | |
| B | a **leaked secret** | `printf '\nAPI_KEY = "AKIAABCDEFGHIJKLMNOP"\n' >> app/app.py && git commit -am oops && git push` | *Secret scan* | S4.2 (secrets) |
| C | a manifest the cluster would **reject** | delete the `securityContext:` block (the Pod-level one) from `chart/chai-stall/templates/deployment.yaml`, commit, push | *Chart: lint + ask the API server*: `violates PodSecurity "restricted"` | S4.5 / K16 |
| D | an image that **runs as root** | `sed -i.bak '/^USER 10001/d' app/Dockerfile && rm app/Dockerfile.bak`, commit, push | *Deploy to staging*: the Pod stays `CreateContainerConfigError: container has runAsNonRoot and image will run as root`; the pipeline prints the evidence and rolls the release back | **S4.5** (the exact one) |
| E | a **typo in the image name** | in `Jenkinsfile` change `PULL_REPO = 'localhost:30500/chai-stall'` to `'localhost:30500/chai-stal'` | *Deploy to staging*: `ImagePullBackOff`; the log prints the evidence (`Failed to pull image …`), then the release rolls back | **S1.2** |
| F | a **buggy release** | Phase 5, bad canary | *Release to production*: automatic rollback | S5.4 |
| G | **too many permissions asked** | no commit needed: `kubectl -n kube-system get pods --as=system:serviceaccount:cicd:jenkins-agent` | the API server: `forbidden` for ServiceAccount `jenkins-agent` | **S4.4** / K14 |

**For C, D, E, G do the forensics like an on-call engineer, with `kubectl`:**
```bash
kubectl -n stall-staging get pods                              # what state?
kubectl -n stall-staging describe pod <name> | tail -15        # the event that explains it
kubectl -n stall-staging get events --sort-by=.lastTimestamp | tail
helm history chai-stall -n stall-staging                       # Helm's own record: "failed", then "rolled back"
```
Which gate caught each, and *when*? The earlier a gate catches something, the cheaper it is: C costs seconds, D and E cost minutes, F costs a few percent of users. Rank your seven.

## Phase 7: Extend the factory (20 min)
Do **at least two**:
1. **A new dynamic check.** Add `{"name": "no TODOs", "container": "tools", "cmd": "! grep -rn TODO app/app.py"}` to `pipeline-config.json`, push, run **dynamic-checks**: a new parallel stage appears without touching the Jenkinsfile. ([C03](../../C03-job-dsl-dynamic/README.md))
2. **A new button.** The `ops-*` buttons come from the list in `jenkins/jobs/ops.groovy`. Add `'analyse'` (an action `k8s-deploy.sh` already has), push, run **00-seed**: a new **ops-analyse** job appears. (Adding a brand-new *action* means changing platform logic: `k8s/pipeline/k8s-deploy.sh` in the course repo, then `k8s-up.sh`.)
3. **Autoscaling (K13).** Set `autoscaling.enabled: true` in `chart/chai-stall/values-prod.yaml` (needs metrics-server: `./scripts/install-metrics-server.sh`), push, release, then `kubectl -n stall-prod get hpa -w`.
4. **A drain that cannot hurt (K17).** With `podDisruptionBudget.enabled`, run `kubectl drain <worker> --ignore-daemonsets --delete-emptydir-data` while you `curl` production in a loop: zero failures, because the PDB keeps one Pod up. `kubectl uncordon <worker>` afterwards.
5. **A NetworkPolicy (K15).** Production already enables the chart's policy. From a throwaway Pod in `default`, `kubectl run t --rm -it --image=curlimages/curl -n default -- curl -m 3 chai-blue.stall-prod`: it is refused. From `stall-staging` or `cicd`: allowed. Why?
6. **A new stage.** Add a stage after *Record the artifact* that fails the build if the image is larger than 150 MB (`ls -l out/image.tar`).

## Phase 8: The same pipeline on GitHub Actions or GitLab CI (30 min)
Jenkins is one CI. Most teams today run **Git-hosted CI**. Follow [**C01**](../../C01-git-based-ci/README.md) Steps 2 to 4 with your fork: [`.github/workflows/unit4-ci.yml`](../../../.github/workflows/unit4-ci.yml) runs tests on three Python versions, unit-tests the alert rules, builds and scans the image and publishes it to GHCR, with deploy jobs behind **environments** and approvals. For GitLab, copy [`ci-examples/gitlab-ci.yml`](../../ci-examples/gitlab-ci.yml). Where the Jenkins pipeline ends with `helm upgrade` into *your* cluster, a hosted runner needs credentials to reach a cluster: that is the one real step you would add in a company (a short-lived token or OIDC, never a kubeconfig in a variable).

**Deliverable:** a green and a red run, and this table filled in:

| Concept | Jenkins (this project) | GitHub Actions | GitLab CI |
|---|---|---|---|
| pipeline file | `Jenkinsfile` | | |
| a parallel step | `parallel { }` | | |
| a manual approval | `input` | | |
| a secret | credential bound to env | | |
| a build artifact | `archiveArtifacts` | | |
| the build environment | a Pod from `ci/pod.yaml` | | |

<details><summary>Check the table</summary>

| Concept | Jenkins | GitHub Actions | GitLab CI |
|---|---|---|---|
| pipeline file | `Jenkinsfile` | `.github/workflows/*.yml` | `.gitlab-ci.yml` |
| a parallel step | `parallel { }` | jobs without `needs`, `strategy.matrix` | same stage, `parallel:matrix` |
| a manual approval | `input` | `environment` with required reviewers | `when: manual` |
| a secret | `withCredentials` / env from a Secret | `secrets.NAME` | masked CI/CD variable |
| a build artifact | `archiveArtifacts` | `actions/upload-artifact` | `artifacts: paths:` |
| the build environment | a Pod from `ci/pod.yaml` | `runs-on:` (a fresh VM) | `image:` + a runner |
</details>

## Phase 9: Clean up (5 min)
Want to **watch your releases on a dashboard and be paged when they fail**? Do [Project 2](../project-2-see-everything/README.md) *before* cleaning up.
```bash
./cicd-observability/scripts/forward.sh stop
./cicd-observability/scripts/k8s-down.sh
rm -rf ~/chai-stall                  # your repo copy (optional)
```

---

## 🔥 When the pipeline fails, it is a scenario you have solved
| The pipeline says… | Look with… | It is… |
|---|---|---|
| build Pod stays `Pending` | `kubectl -n cicd describe pod` ("Insufficient cpu/memory") | **S1.1** requests too big for the cluster |
| `ImagePullBackOff` for `localhost:30500/...` | `kubectl describe pod`; is the registry up? right tag? who pulls from where? | **S1.2** |
| release `CrashLoopBackOff` | `kubectl logs --previous` | **S1.3** |
| `helm test` can't reach the Service | `kubectl get endpoints` | **S3.1** no endpoints (selector ≠ labels) |
| `CreateContainerConfigError … runAsNonRoot` | `kubectl describe pod` | **S4.5** |
| `Forbidden … serviceaccount jenkins-agent` | `kubectl auth can-i … --as=…` | **S4.4** RBAC |
| registry/Gitea Pod `Pending` with a PVC | `kubectl get pvc,sc` | **S4.3** no StorageClass |
| rollout never finishes | `kubectl rollout status` / `helm history` | **S5.4** bad rollout |
| Pod `OOMKilled` | `kubectl describe pod` (`Last State`) | **S5.5** |
| `exceeded quota` | `kubectl describe quota` | **S6.2** |
| `kubectl apply` "worked" but nothing changed | wrong namespace / context | **S6.1** |

## ✅ Definition of done (self-assessment)
- [ ] The platform runs in **my cluster**; I can say what every Pod in `cicd` is for
- [ ] A `git push` to **my** repo reached production without me typing a deploy command
- [ ] I watched a build **Pod appear and disappear**, and I know which container did which stage
- [ ] I can explain the two registry names, and why the node uses `localhost:30500`
- [ ] I used `helm history`, `helm rollback` or the weights to go back, and checked with `kubectl`
- [ ] I saw the pipeline fail for a test, a secret, a rejected manifest, a root image, a bad image name and a bad canary, and matched each to a scenario
- [ ] I measured an outage (recreate) against none (rolling, blue/green)
- [ ] The same code ran through a Git-hosted CI
- [ ] `verify.sh` prints all ✔

## 🧯 Troubleshooting
| Symptom | Cause and fix |
|---|---|
| `k8s-up.sh` says "no default StorageClass" | normal on kubeadm / Killercoda-style clusters. It switches the registry and Git server to `emptyDir` (no volume needed). They then lose their data if their Pod restarts: re-run the pipeline / `new-app-repo.sh`. For real volumes, install a StorageClass (Lab K10) and run `k8s-up.sh` again |
| `k8s-up.sh` hangs on the registry / `kubectl -n cicd get pvc` shows `Pending` | you ran an older `k8s-up.sh` without a StorageClass: press Ctrl+C, `git pull`, run `k8s-up.sh` again (Scenario S4.3) |
| `k8s-up.sh` is slow | the first run pulls ~2 GB of images and Jenkins plugins: wait; `kubectl -n cicd get pods` shows progress |
| `k8s-up.sh`: Jenkins "did not finish installing" | `kubectl -n cicd logs jenkins-0 -c jenkins \| tail -30` (plugins download needs internet); run the script again |
| build Pod `ImagePullBackOff` for `gcr.io/kaniko-project/...` | the node cannot reach gcr.io: check the node's internet / proxy (on kind, `./scripts/load-image.sh` can preload images) |
| `forward.sh start` shows `○ jenkins stopped` (or production) | it now prints kubectl's own reason and a hint under each stopped door. Usual causes: the Pod is not Ready yet (`kubectl -n cicd get pods`: `jenkins-0` must be `2/2 Running`), or that local port is taken. Fix it, then run `forward.sh start` again. Logs: `/tmp/z2h-unit4-forward-<name>.log` |
| In a Killercoda / iximuz lab the URLs do not open | the lab's browser cannot see `127.0.0.1` inside the VM. `forward.sh start --lab` (automatic for user `laborant`) listens on `0.0.0.0`; then expose the port with the lab's port feature (see the box in Phase 2) |
| Jenkins answers **403 No valid crumb** to *Build Now* behind a proxy / lab | an older install: run `./cicd-observability/scripts/k8s-up.sh` again (it sets `excludeClientIPFromCrumb`; Jenkins reloads its config by itself, or `kubectl -n cicd delete pod jenkins-0`) |
| a fix was merged into the course repo but your pipeline still behaves the old way | stage logic is platform-owned: `git pull` in the course repo, then `./cicd-observability/scripts/k8s-up.sh` (it republishes the ConfigMap `z2h-pipeline`; the next build uses it). Only a change to the *shape* of the pipeline (the `Jenkinsfile` itself) needs a new repo: `new-app-repo.sh ~/chai-stall2` |
| `Deploy to staging` is red | the log now prints **the evidence before rolling back**: scroll to the `──── ` sections (Helm's message, Deployment and Pods, events, ReplicaSet conditions, container logs). `ReplicaSet conditions: FailedCreate … violates PodSecurity` = the namespace refused the Pod (S4.5); `Failed to pull image` = S1.2; `0/1 nodes are available` = S1.1 |
| `forward.sh` says staging was skipped | normal before the first pipeline run: nothing is deployed in `stall-staging` yet |
| `new-app-repo.sh`: cannot reach `localhost:3001` | `./cicd-observability/scripts/forward.sh start`; is port 3001 used by something else? |
| `git push` asks for a password | the remote has the lab login in the URL (`git remote -v`); if you cloned another way use `z2h` / `z2h-gitea-pass` |
| Jenkins build: `No Kubernetes cloud was found` | Jenkins was installed without the chart's defaults: re-run `k8s-up.sh` |
| `Scan image (Trivy)` is red | open the stage's log: usually the scanner cannot download its database from `mirror.gcr.io` / `ghcr.io` (a lab with restricted egress). Re-run with `SCAN_MODE=report` (never blocks) or `skip`. A *finding* (a CRITICAL CVE) is different: fix it by building on a newer base image |
| `helm upgrade` times out in staging | the Pod is not Ready: `kubectl -n stall-staging describe pod`; the build log already shows the evidence (the `──── ` sections) and the release was rolled back; see the scenario table above |
| production `curl` returns nothing | is the door open (`forward.sh status`)? is the Gateway proxy up (`kubectl -n envoy-gateway-system get pods`)? is any release in `stall-prod`? |
| Canary check says `000` for every request | the build Pod cannot reach `chai-<colour>.stall-prod.svc.cluster.local`: the NetworkPolicy must allow namespace `cicd` (it does by default); did you edit it? |
| Start over | `./cicd-observability/scripts/k8s-down.sh -y && ./cicd-observability/scripts/k8s-up.sh` |
| Test the whole thing automatically | `./cicd-observability/scripts/k8s-selftest.sh` (about 15 minutes) |

## 💼 For your CV / portfolio
> *Built a Kubernetes-native CI/CD platform: Jenkins (Configuration as Code, Job DSL, declarative pipelines with per-build Pods), Gitea webhooks, daemonless image builds with Kaniko, an in-cluster registry, Helm releases with atomic rollback, Pod Security `restricted` and least-privilege RBAC as deployment gates, and blue/green, rolling, recreate and canary releases driven by Gateway API traffic weights with automated canary analysis and rollback.*

➡️ Next: [🏁 Project 2: See Everything](../project-2-see-everything/README.md)
