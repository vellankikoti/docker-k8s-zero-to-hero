# 🏁 Project 1: Ship It: a CI/CD Factory (Lab Exercise 7)

> **Syllabus lab exercise 7:** *Create CI/CD pipelines using Jenkins and GitHub Actions or GitLab CI with automated build and deployment stages.*
>
> ⏱ 2–3 hours · 🟡→🔴 · Needs: Docker + Compose, ~2 GB free memory, ports 8080 / 5001 / 8081 / 8090 free. Best after labs [C01](../../C01-git-based-ci/README.md) to [C05](../../C05-images-and-deployment/README.md): each phase says which lab explains it.
>
> **After every phase run `./scripts/verify.sh N`**: it prints ✔ or ✖ with a hint. Nobody has to guess whether it worked.

## 🎯 The mission
A tea stall's app, the **Chai Stall**, is deployed by an engineer typing commands. It broke production twice last month. **Your job: build the factory that ships it**, so that a commit is automatically tested, scanned, built, published, deployed to staging, approved by a human, and released to production with a strategy that can **roll itself back**. And prove each gate really stops a bad change.

```mermaid
flowchart LR
  DEV[👩‍💻 git commit] --> JK
  subgraph JK [Jenkins · configured as code]
    T[🧪 test] --> P[⚡ secret scan ‖ syntax] --> B[📦 build + image policy] --> S[🔍 vuln scan] --> PU[(registry :5001)]
  end
  PU --> ST[🧱 staging :8081<br/>recreate]
  ST --> AP{🙋 approval}
  AP --> RT{{🚦 router :8090}}
  RT -->|blue/green · canary · rolling| PROD[🏭 production]
  PROD -.canary check fails.-> RB[↩ automatic rollback]
  DEV -.same code, other CI.-> GH[GitHub Actions · GitLab CI]
```

By the end you will have: **Jenkins from code** (Configuration as Code + Job DSL), a **pipeline in a `Jenkinsfile`** with parameters, parallel checks, approval and a post-deploy gate, an **image registry**, **four deployment strategies**, three **security gates**, and the **same pipeline running on GitHub Actions** as well.

## 📋 The phases

| # | Phase | You prove | Time | Lab |
|---|---|---|---|---|
| 0 | Pre-flight | your machine is ready | 5 m | |
| 1 | Boot the factory | registry, Jenkins, router run | 10 m | [C02](../../C02-jenkins-pipelines/README.md) |
| 2 | Jenkins configures itself | jobs are generated from Git | 10 m | [C02](../../C02-jenkins-pipelines/README.md), [C03](../../C03-job-dsl-dynamic/README.md) |
| 3 | The first green pipeline | build → test → scan → push → deploy | 25 m | [C02](../../C02-jenkins-pipelines/README.md), [C04](../../C04-artifacts-secrets-security/README.md) |
| 4 | **Ship a feature, test-first** | a commit reaches production on its own | 25 m | [C02](../../C02-jenkins-pipelines/README.md) |
| 5 | **Release four ways** | recreate, rolling, blue/green, canary + auto-rollback | 25 m | [C05](../../C05-images-and-deployment/README.md) |
| 6 | **Break it on purpose** | each gate stops a different bad change | 20 m | [C04](../../C04-artifacts-secrets-security/README.md) |
| 7 | Extend the factory | your own check, your own button | 20 m | [C03](../../C03-job-dsl-dynamic/README.md) |
| 8 | The same pipeline on GitHub Actions / GitLab CI | a second CI runs it | 30 m | [C01](../../C01-git-based-ci/README.md) |
| 9 | Clean up (and optionally watch it) | | 5 m | [Project 2, Phase 7](../project-2-see-everything/README.md) |

---

## Phase 0: Pre-flight (5 min)
From the repository root:
```bash
./cicd-observability/scripts/doctor.sh
git branch --show-current          # remember this branch name
git status --short                 # should be clean (commit or stash anything of yours)
```
Fix every ✖ it prints. **Two classics:** a *shallow* clone (`git fetch --unshallow` fixes it), and a port already in use (stop the other program).

## Phase 1: Boot the factory (10 min)
```bash
cd cicd-observability/projects/project-1-ship-it
cp .env.example .env
```
Open `.env`. If the branch you printed in Phase 0 is **not** `main`, edit the line: `REPO_BRANCH=*/your-branch-name`. This is the branch Jenkins will watch. Then:
```bash
docker compose up -d --build            # 3-5 minutes the first time: it downloads Jenkins and installs plugins
./scripts/verify.sh 1
```
Expected: three ✔ (registry :5001, Jenkins :8080, router). Jenkins is ready ~1 minute after the containers start: if verify says ✖, wait and retry. Log in at **http://localhost:8080** with `admin` / `z2h-jenkins`.

<details><summary>🧯 Image build fails with "PKIX path building failed"?</summary>

You are behind a proxy that re-signs HTTPS. Put your company root certificate in `jenkins/extra-ca/` as `corp.crt`, then `docker compose build jenkins`. See [`extra-ca/README.md`](jenkins/extra-ca/README.md).
</details>

## Phase 2: Jenkins configures itself (10 min)
You did not click through a setup wizard: the whole controller is in [`jenkins/casc/jenkins.yaml`](jenkins/casc/jenkins.yaml). Now let it create its own jobs:

1. In Jenkins open **00-seed → Build Now**. Open the build → **Console Output**; read the `GeneratedJob{…}` lines at the end.
2. Back on the dashboard, open the **chai-stall** folder: `ci-cd`, `dynamic-checks`, `secrets-demo`, and the `ops-*` buttons (see the **Operations** view).
```bash
./scripts/verify.sh 2
```
**Understand it (answer in your own words, then peek):** *"Why is the seed job the only job anyone ever created by hand?"*
<details><summary>Peek</summary>

Because everything else is described in `jenkins/jobs/*.groovy` and re-created from Git on demand. If Jenkins is destroyed, `docker compose up -d` plus one seed run restores everything: no hand-made configuration to lose.
</details>

## Phase 3: The first green pipeline (25 min)
Open **chai-stall → ci-cd → Build Now**. (The first build registers the parameters; from the next one the button reads **Build with Parameters**.) Watch the **Stage View** and the **Console Output**. The pipeline runs, in order:

`Checkout → Test → [Secret scan ‖ Syntax check] → Build image (+ image policy) → Scan image → Push to registry → Deploy to staging → Approval → Release to production`

Things to notice as it runs:
- Stages run **in parallel** where they can (secret scan ‖ syntax check).
- **Push to registry** logs in with a credential, and the password appears as `****` (C04).
- At **Approval** the pipeline *stops and waits for you*. Click the **Input requested** box and **Ship it**.

> ⚠️ **If "Scan image" fails** with a message about downloading a database, the scanner cannot reach the internet. That is the gate failing *closed*, which is correct. Run **Build with Parameters** and set `SCAN_MODE=report` (the scan runs and shows findings without failing the build).

When the build is green:
```bash
curl -s localhost:8081/api/info          # staging
curl -s localhost:8090/api/info          # production, through the router
./scripts/verify.sh 3
./scripts/verify.sh 4
```
Open the build page: under **Build Artifacts** is `build-info.json` (version, image, **digest**, commit). Run `./scripts/registry-digest.sh 1.0.1` (use your version) and match the digest. 🎉 You have shipped.

**Run it a second time** with **Build with Parameters**, `REQUIRE_APPROVAL` **unticked**: no stop at all. *That* is continuous deployment; the first run was continuous delivery.

## Phase 4: Ship a feature, test-first (25 min)
The festival is coming: add **vada** (₹8) to the menu, **the way a real team would**: write the failing test first, watch the pipeline refuse it, then make it pass.

Work on the branch Jenkins watches (the one in `.env`). From the repository root:

**4a. 🔴 Red: commit only the test.**
```bash
cat > cicd-observability/app/tests/test_menu.py <<'EOF'
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
git add -A && git commit -m "test: vada should be on the menu"
```
Do **not** press anything. Within ~2 minutes Jenkins notices the commit and starts a build. **It fails at *Test*** (red), and every later stage is skipped: **nothing was built, pushed or deployed.** Open the console and find the failing assertion. A broken change was stopped by a machine, before a human saw it.

**4b. 🟢 Green: make it pass.**
```bash
sed -i.bak 's/"biscuit": 5}/"biscuit": 5, "vada": 8}/' cicd-observability/app/app.py && rm cicd-observability/app/app.py.bak
python3 -m unittest discover -s cicd-observability/app/tests 2>&1 | tail -3        # passes on your laptop first
git commit -am "feat: add vada to the menu"
```
(If `python3` is not installed locally, skip the middle line: the pipeline runs the tests anyway.) Wait for the build, press **Ship it** at *Approval* when it arrives, and then:
```bash
curl -s -X POST 'localhost:8090/order?item=vada'          # {"ok": true, "item": "vada", "price_inr": 8, ...}
```
✔ Your commit is live in production, with a new version number, and **you never typed a deploy command**.

> 🤔 **Which parts of that were "CI" and which "CD"?** *(Checkout, test, scan, build, push = CI. Staging deploy, approval, production = CD.)*

## Phase 5: Release four ways (25 min)
Use **Build with Parameters** (set `REQUIRE_APPROVAL` off to move faster). Each build needs a *new commit or just a re-run*; re-running the same commit is fine: the version is the build number.

| Try | Parameters | What you should see |
|---|---|---|
| **Blue/green** | `STRATEGY=bluegreen` | the new version appears in the idle colour, then traffic flips: `curl -si localhost:8090/api/info \| grep -E "X-Slot|version"` |
| **Rolling** | `STRATEGY=rolling` | three replicas replaced one by one; `curl localhost:8090/roll/api/info` |
| **A good canary** | `STRATEGY=canary`, `CANARY_PERCENT=40` | the check passes, the canary is **promoted** |
| **A bad canary** | `STRATEGY=canary`, **`INJECT_BUG` ticked**, `CANARY_PERCENT=40` | the check reports ~30% errors, the pipeline **rolls back by itself** and the build is red |

For the bad canary, read the console: you will find `canary chai-…: N failed of M requests = 30% (limit 5%)` followed by `rollback`. Then confirm users were never left on the bad version:
```bash
./deploy/deploy.sh status                                   # canary weight back to 0%
./scripts/traffic-test.sh http://localhost:8090 10          # failed=0
./scripts/verify.sh 5
```
Use the **ops-* buttons** (Operations view) for manual control: **ops-status**, **ops-rollback**, **ops-promote**.

**Prove zero downtime** for yourself: in one terminal `./scripts/traffic-test.sh http://localhost:8090/roll 25`, then run a **rolling** build. Count the `x` characters. Now do the same against staging (`http://localhost:8081`) during a build's *Deploy to staging* stage (which is a *recreate*). The difference between the two is the reason strategies exist.

## Phase 6: Break it on purpose (20 min)
A pipeline you have not seen *fail* is a pipeline you do not trust. Break it three ways and watch a **different** gate stop each one. Make each break as a commit on the branch Jenkins watches, then undo it with `git reset --hard HEAD~1` (**commit or stash your real work first**: this removes the one bad commit you just made and anything uncommitted).

| # | Break | How | Which stage turns red | What it proves |
|---|---|---|---|---|
| A | A **failing test** | you did it in Phase 4a | *Test* | broken code never builds |
| B | A **leaked secret** | `printf '\nAPI_KEY = "AKIAABCDEFGHIJKLMNOP"\n' >> cicd-observability/app/app.py && git commit -am "oops"` | *Checks in parallel → Secret scan* | secrets stop at the gate (C04) |
| C | An **unsafe image** | `sed -i.bak '/^USER 10001/d' cicd-observability/app/Dockerfile && rm cicd-observability/app/Dockerfile.bak && git commit -am "run as root"` | *Build image* (image-policy: "runs as root") | policy as code (C04) |
| D | A **buggy release** | Phase 5, bad canary | *Release to production* (auto-rollback) | the last gate: real traffic |

After each one: look at the console, find **the exact line** that explains the failure, undo the commit, and let the pipeline go green again. Then answer: *which of these four would a human reviewer most likely have missed?* (Usually B and D.)

## Phase 7: Extend the factory (20 min)
Make it yours. Do **at least two**:
1. **A new dynamic check.** Add a fourth entry to [`pipeline-config.json`](pipeline-config.json) (for example `{"name": "no TODOs", "cmd": "! grep -rn TODO cicd-observability/app/app.py"}`), commit, run **chai-stall → dynamic-checks**. A new parallel stage appears without touching the Jenkinsfile. ([C03](../../C03-job-dsl-dynamic/README.md))
2. **A new button.** Add `'state'` to the list in [`jenkins/jobs/deploy_jobs.groovy`](jenkins/jobs/deploy_jobs.groovy), commit, run **00-seed**: a new **ops-state** job appears.
3. **A new stage.** In the [`Jenkinsfile`](Jenkinsfile) add a stage after *Push to registry* that prints the image **digest** in a big banner, or fails the build if the image is larger than 150 MB (`docker image inspect -f '{{.Size}}' $FULL_IMAGE`).
4. **A new gate.** Make *Release to production* fail if `deploy.sh status` shows that more than one container is unhealthy.
5. **A new parameter.** `VERSION_SUFFIX` (see the C02 challenge).

<details><summary>Hint for #3 (size gate)</summary>

```groovy
stage('Image size gate') {
  steps {
    sh '''
      SIZE=$(docker image inspect -f '{{.Size}}' $FULL_IMAGE)
      echo "image size: $((SIZE/1024/1024)) MB"
      [ "$SIZE" -lt 157286400 ] || { echo "image is over 150 MB"; exit 1; }
    '''
  }
}
```
</details>

## Phase 8: The same pipeline on GitHub Actions or GitLab CI (30 min)
Jenkins is one CI. Most teams today run **Git-hosted CI**. Follow [**C01**](../../C01-git-based-ci/README.md) Steps 2 to 4 with your fork:
- GitHub: [`.github/workflows/unit4-ci.yml`](../../../.github/workflows/unit4-ci.yml) runs tests on three Python versions, unit-tests the Prometheus alert rules, builds and scans the image, and publishes to GHCR on `main`; deploy jobs use **environments** (add yourself as a *required reviewer* on `production` to get an approval gate).
- GitLab: copy [`ci-examples/gitlab-ci.yml`](../../ci-examples/gitlab-ci.yml) to a GitLab project's root as `.gitlab-ci.yml`.

**Deliverable:** a screenshot or link of one **green** and one **red** run (use the broken-test trick from C01). Then fill in this table for your own understanding:

| Concept | Jenkins (this project) | GitHub Actions | GitLab CI |
|---|---|---|---|
| pipeline file | `Jenkinsfile` | | |
| a parallel step | `parallel { }` | | |
| a manual approval | `input` | | |
| a secret | `withCredentials` | | |
| a build artifact | `archiveArtifacts` | | |

<details><summary>Check the table</summary>

| Concept | Jenkins | GitHub Actions | GitLab CI |
|---|---|---|---|
| pipeline file | `Jenkinsfile` | `.github/workflows/*.yml` | `.gitlab-ci.yml` |
| a parallel step | `parallel { }` | jobs without `needs`, or `strategy.matrix` | jobs in the same stage, `parallel:matrix` |
| a manual approval | `input` | `environment` with required reviewers | `when: manual` |
| a secret | `withCredentials` | `secrets.NAME` | CI/CD variables (masked/protected) |
| a build artifact | `archiveArtifacts` | `actions/upload-artifact` | `artifacts: paths:` |
</details>

## Phase 9: Clean up, and what next (5 min)
Want to **watch your releases on a dashboard**? Do [Project 2, Phase 7](../project-2-see-everything/README.md) *before* cleaning up: it points Prometheus at the containers you just deployed and lets you see a canary in Grafana.

When you are done:
```bash
./deploy/deploy.sh clean       # the app containers the pipeline deployed
docker compose down -v         # Jenkins, registry, router, and all their data
```

---

## ✅ Definition of done (self-assessment)
Tick them honestly. Each one is something you **did**, not read:
- [ ] Jenkins runs from code; I destroyed nothing by hand-configuring it
- [ ] `ci-cd` goes green end to end, and I can explain every stage
- [ ] A commit reached production **without me running a deploy command**
- [ ] I saw the pipeline **fail** for a test, a secret, an unsafe image, and a bad canary
- [ ] I measured downtime for recreate vs rolling vs blue/green
- [ ] I can find, for any running container, **the commit and digest it came from** (`build-info.json`)
- [ ] The same code ran through a Git-hosted CI (GitHub Actions or GitLab CI)
- [ ] `./scripts/verify.sh` prints all ✔

## 🧯 Troubleshooting
| Symptom | Cause and fix |
|---|---|
| `verify.sh 1` ✖ for Jenkins | still starting: `docker compose logs jenkins \| tail`; wait for "fully up and running" |
| Image build fails: `PKIX path building failed` | corporate proxy: [`jenkins/extra-ca/`](jenkins/extra-ca/README.md) |
| Seed job: `Couldn't find any revision to build` | `REPO_BRANCH` in `.env` does not match your branch, **or** your clone is shallow (`git fetch --unshallow`). After editing `.env` run `docker compose up -d` then the seed again |
| Seed job: `references a local directory, which may be insecure` | you changed the Jenkins image options; `ALLOW_LOCAL_CHECKOUT` must stay on for the lab ([Dockerfile](jenkins/Dockerfile)) |
| You edited a job file and nothing changed | you must **commit**: Jenkins reads Git, not your working folder |
| No build starts after a commit | polling runs every ~2 min; commit on the watched branch; or press **Build Now** |
| `Scan image` fails (database download) | no internet to the scanner: `SCAN_MODE=report` |
| `Deploy to staging`: `network 'shipit' not found` | the stack is not up: `docker compose up -d` |
| `port is already allocated` | another program uses 8080/5001/8081/8090: `doctor.sh` tells you which |
| Canary check says "no traffic" | run it from the host with the router up (`curl localhost:8090/api/info`); inside Jenkins it uses `ROUTER_URL` (already set in Compose) |
| Everything is slow / containers killed | Docker has too little memory: give it 4 GB+ (Docker Desktop → Settings → Resources) |
| Start over | `./deploy/deploy.sh clean; docker compose down -v; docker compose up -d --build` |

## 💼 For your CV / portfolio
> *Built a CI/CD platform with Jenkins (Configuration as Code, Job DSL, declarative pipelines) and GitHub Actions: automated test, secret and vulnerability scanning, image build and registry publishing; blue/green, rolling and canary deployments with automated canary analysis and rollback; policy-as-code image gates.*

Put the repo link, a screenshot of the Stage View with a red canary rollback, and the architecture diagram above in your README.

➡️ Next: [🏁 Project 2: See Everything](../project-2-see-everything/README.md)
