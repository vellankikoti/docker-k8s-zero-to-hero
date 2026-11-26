# Lab C01: Git-based CI: GitHub Actions and GitLab CI

> ⏱ 60 min · 🟢→🟡 · Needs: [C00](../C00-foundations/README.md), Docker, and (for Steps 3 and 4) a free GitHub account. GitLab is optional.

## 🎯 What you'll learn
- What a CI pipeline actually does, by running every stage **by hand** first
- Read and change a real **GitHub Actions** workflow: triggers, jobs, matrix, cache, artifacts, environments, permissions
- Read the same pipeline as **GitLab CI**: stages, `rules`, `needs`, templates, child pipelines
- Watch a **gate** stop a bad change

## 🧠 Concept in 60 seconds

A Git-based CI tool watches your repository. When something happens (a push, a pull request) it starts a **runner** (a fresh, disposable machine), checks out your commit, and runs the steps in a YAML file that lives **in the same repository**.

```mermaid
flowchart LR
  A[git push] --> B[GitHub / GitLab<br/>reads the pipeline file]
  B --> C[allocates a runner<br/>fresh VM or container]
  C --> D[checkout → test → build → scan → publish]
  D --> E{all green?}
  E -->|yes| F[✅ check on the commit<br/>merge allowed]
  E -->|no| G[❌ merge blocked]
```

## 🧪 Hands-on

### Step 1: Be the robot (10 min)
A pipeline just automates commands you could type. Type them once, so nothing later is magic. From the repository root:
```bash
cd cicd-observability/app

# 1. TEST: the same command CI runs
python3 -m unittest discover -s tests -v

# 2. BUILD: make an image, stamp it with a version
docker build --build-arg APP_VERSION=1.0.0-local -t chai-stall:local .

# 3. RUN + SMOKE TEST: does the thing we built actually work?
docker run -d --name chai -p 8085:8080 chai-stall:local
curl -s localhost:8085/api/info
curl -s -X POST 'localhost:8085/order?item=chai'
curl -s localhost:8085/metrics | grep -E '^(orders_total|app_info)'

# 4. CLEAN UP the robot's mess
docker rm -f chai
```
Expected: `Ran 8 tests ... OK`, then JSON with `"version": "1.0.0-local"`, then `orders_total{item="chai"} 1`.

> 🤔 **Predict:** if you broke `app.py` (add a syntax error), which of the four steps would notice first? *(Step 1: the tests cannot even import the file. Step 2 would still build a broken image happily. That is why test comes before build.)*

Every pipeline in this track is these four steps, plus gates and plumbing.

### Step 2: Fork the repository and switch Actions on (5 min)
GitHub Actions only runs on a repository **you** own, so fork this one:
1. On GitHub, open the repository and press **Fork**.
2. In your fork, open the **Actions** tab and press **I understand my workflows, go ahead and enable them**.
3. Clone your fork (full clone, not `--depth`) and make a branch:
```bash
git clone https://github.com/<your-username>/docker-k8s-zero-to-hero.git
cd docker-k8s-zero-to-hero
git switch -c my-first-ci
```

### Step 3: Read the workflow (10 min)
Open [`.github/workflows/unit4-ci.yml`](../../.github/workflows/unit4-ci.yml) and match each part to the table:

| In the file | What it does | Why it matters |
|---|---|---|
| `on: push / pull_request / workflow_dispatch` + `paths:` | **when** it runs; only if the app, rules or this file changed | no wasted runs; a button to start it by hand |
| `permissions: contents: read` | the token can only read code | **least privilege**: a compromised step cannot push |
| `concurrency: cancel-in-progress` | a newer push cancels the older run | saves time and minutes |
| `jobs.test.strategy.matrix.python` | **three jobs in parallel**, one per Python version | find "works on 3.12, breaks on 3.11" early |
| `jobs.alert-rules` | runs `promtool check` and **unit-tests the alert rules** | alerts are code and deserve tests (see [C07](../C07-alerting-grafana/README.md)) |
| `needs: [test, alert-rules]` | build waits for both | the order of the belt |
| `permissions: packages: write` on `build` only | only this job may publish | scoped per job |
| `docker/build-push-action` with `cache-from: type=gha` | build with layer cache | faster builds |
| a `docker run aquasec/trivy … --exit-code 1` step | **fails the build on CRITICAL vulnerabilities** | a gate |
| `secrets.GITHUB_TOKEN` | a token created for this run, gone when it ends | no stored password to leak |
| `if: github.ref == 'refs/heads/main'` | push the image and deploy only from `main` | pull requests build but never publish |
| `upload-artifact` | keeps `build-info.json` for download | **artifact** management |
| `environment: production` | a named target; add **required reviewers** to make it wait for a human | continuous *delivery*'s button |

### Step 4: Make the robot say yes, then no (15 min)
**Yes.** Make a harmless change, push, and watch it run:
```bash
echo "# $(date)" >> cicd-observability/app/Dockerfile       # a comment: harmless but changes the app folder
git add -A && git commit -m "ci: trigger the workflow" && git push -u origin my-first-ci
```
Open a pull request from `my-first-ci` into **your fork's** `main`. In the PR you will see **checks** appear: *Unit tests (Python 3.11 / 3.12 / 3.13)*, *Check and unit-test the Prometheus alert rules*, then *Build, scan and publish*. Open one and read the log: it is Step 1's commands, run for you.

**No.** Now break something on purpose, in the same branch:
```bash
sed -i.bak 's/"chai": 10/"chai": 10\//' cicd-observability/app/app.py      # a syntax error in the menu
git commit -am "oops" && git push
```
(`sed -i.bak` works on Linux and macOS; delete `app.py.bak` afterwards.) The three test jobs turn ❌ in seconds, **the build job never starts** (`needs`), and GitHub shows "Merging is blocked" if you enabled branch protection (Settings → Branches → Add rule → *Require status checks*). Fix it:
```bash
git revert --no-edit HEAD && git push
```
✔ Checks go green again. You just saw the whole point of CI: the bad change was stopped by a machine, before a human had to notice.

**Release.** Merge the PR into your fork's `main`. This time the **build** job logs in to GHCR and pushes `ghcr.io/<you>/chai-stall:1.0.<run number>`, and the two **deploy** jobs run. Under **Settings → Environments → production → Required reviewers**, add yourself, push another change, and watch the production job **wait** for you. That is a human approval gate, with an audit trail.

> The deploy jobs here only start the image on the runner and smoke-test it; a real team would put `kubectl set image` or `helm upgrade` there. See [K20](../../kubernetes/20-projects/README.md) for one that talks to a cluster.

### Step 5: The same pipeline in GitLab CI (10 min)
Open [`ci-examples/gitlab-ci.yml`](../ci-examples/gitlab-ci.yml). Same ideas, different words:

| Idea | GitHub Actions | GitLab CI |
|---|---|---|
| File | `.github/workflows/*.yml` | `.gitlab-ci.yml` at the repo root |
| Parallel copies | `strategy.matrix` | `parallel: matrix:` |
| Order | `needs:` between jobs | `stages:` **and** `needs:` (a shortcut that skips waiting for the whole stage) |
| Reuse | reusable workflows / composite actions | hidden jobs (`.python`) + `extends:` + `include:` |
| When to run | `on:` + `if:` | `workflow: rules:` and per-job `rules:` |
| Manual gate | `environment` with reviewers | `when: manual` |
| Files between jobs | `upload-artifact` / `download-artifact` | `artifacts: paths:` (automatic to later jobs) |
| Built-in credentials | `GITHUB_TOKEN` | `CI_REGISTRY_USER` / `CI_REGISTRY_PASSWORD` |
| Docker builds | runner has Docker | `services: docker:dind` (a Docker engine as a sidecar) |

To try it (optional): create a free project on gitlab.com (**New project → Import project → Repository by URL**, paste your fork's URL), copy the file to the project root as `.gitlab-ci.yml`, commit, and open **Build → Pipelines**. If you have no GitLab account, reading the file against the table above is still worth ten minutes.

**Dynamic child pipelines** (the GitLab counterpart of [C03](../C03-job-dsl-dynamic/README.md)): [`gitlab-dynamic.yml`](../ci-examples/gitlab-dynamic.yml) has one job that *writes* a pipeline file (`child.yml`) and a second that *runs* it with `trigger: include: artifact`. Add a name to the `for check in ...` list and a new job appears.

## 🏭 In production
- **Pin your actions** to a full commit SHA (not just `@v4`) for anything that handles secrets; a moved tag is a supply-chain attack.
- Use **self-hosted or ephemeral runners** for private networks and big builds, and treat them as untrusted: never let a pull request from a fork reach your secrets (GitHub withholds them by default for exactly this reason).
- **Cache** dependencies and Docker layers; the fastest step is the one that does not run.
- Protect `main`: require the checks, require a review, forbid force-push.
- Keep the pipeline **fast** (under ~10 minutes for the feedback that matters): split long suites, run them in parallel.

## 🏆 Challenge
Add a **fourth** check to the workflow that fails the run if anyone commits something that looks like an AWS key. Hint: the repository already has the script; you only need a job that runs it.

<details><summary>Check your answer</summary>

Add a job next to `test`:
```yaml
  secret-scan:
    name: Secret scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./cicd-observability/compose-edition/project-1-ship-it/scripts/secret-scan.sh cicd-observability/app
```
and add `secret-scan` to the `needs:` list of `build`. Test it: add `KEY = "AKIAABCDEFGHIJKLMNOP"` to `app.py`; the job fails and the build never starts. (Real teams use gitleaks or GitHub's built-in secret scanning, which also checks history.)
</details>

## ✅ Checkpoint
<details><summary>1. Why does the <code>build</code> job say <code>needs: [test, alert-rules]</code>?</summary>

So a broken change never gets built, scanned or published. `needs` is the belt: a failed station stops everything after it, and saves minutes.
</details>

<details><summary>2. A pull request from a stranger's fork runs your workflow. Why can it not read your secrets?</summary>

Because the workflow runs *their* code. If it could read your secrets, any pull request could print them. GitHub withholds secrets (and gives a read-only token) to workflows triggered by fork pull requests.
</details>

<details><summary>3. What is the difference between <code>actions/checkout@v4</code> and <code>@&lt;commit sha&gt;</code>?</summary>

`@v4` is a moving tag the action's author controls; `@<sha>` is immutable. Pinning to a SHA means a compromised or changed tag cannot silently change what runs in your pipeline.
</details>

## 🧹 Cleanup
```bash
docker rm -f chai 2>/dev/null; docker rmi chai-stall:local 2>/dev/null
git switch main && git branch -D my-first-ci          # only if you no longer need the experiment
```

➡️ Next: [C02 · Jenkins architecture and Pipeline as Code](../C02-jenkins-pipelines/README.md)
