# Lab C04: Artifacts, Secrets and Pipeline Security

> ⏱ 60 min · 🟡→🔴 · Needs: the Project 1 stack running with at least two successful `ci-cd` builds ([C02](../C02-jenkins-pipelines/README.md)).

## 🎯 What you'll learn
- What an **artifact** is, where each kind lives (registry, Jenkins), and why **tags lie but digests do not**
- How Jenkins stores **secrets**, how it **masks** them, and exactly how a secret still **leaks**
- How to keep secrets out of Git (**Configuration as Code + environment**)
- The security gates in the pipeline: **secret scan**, **image policy**, **vulnerability scan**
- Why a CI server is the **most valuable target** in your company, and how to shrink the blast radius

## 🧠 Concept in 60 seconds

A pipeline **produces** things (artifacts) and **uses** powerful things (secrets). Both need care.

```mermaid
flowchart LR
  subgraph produce [Artifacts: what the pipeline MAKES]
    IMG[container image<br/>localhost:5001/chai-stall:1.0.7<br/>digest sha256:…]
    REC[build-info.json<br/>test-output.txt]
  end
  subgraph use [Secrets: what the pipeline USES]
    TOK[deploy token]
    REG[registry password]
  end
  PIPE[pipeline] --> IMG
  PIPE --> REC
  TOK -->|injected for 5 lines, masked| PIPE
  REG --> PIPE
  GATES{{🛡 gates: secret scan · image policy · vuln scan}} --> IMG
```

**Why CI is the crown jewel.** A pipeline can read your source, hold production credentials, and push code to production. Whoever controls it controls all three. Attackers know: most modern supply-chain attacks go through the build system, not the app.

## 🧪 Hands-on

### Step 1: Artifacts in the registry: tags lie, digests don't (10 min)
```bash
cd cicd-observability/projects/project-1-ship-it
curl -s localhost:5001/v2/chai-stall/tags/list                 # every version the pipeline has published
./scripts/registry-digest.sh 1.0.1                             # the content fingerprint behind a tag
```
(Use a tag that exists in *your* list.) The pipeline records this digest for every build. Open Jenkins → **chai-stall → ci-cd →** a successful build → **Build Artifacts → build-info.json**:
```json
{"version":"1.0.1","image":"localhost:5001/chai-stall:1.0.1","digest":"localhost:5001/chai-stall@sha256:99a1…","commit":"f722dbb","build":"1"}
```
That one file answers "what exactly is running, and where did it come from?": the version, the commit, and the immutable digest.

Now see why the digest matters. **Someone re-pushes the same tag with different contents**:
```bash
BEFORE=$(./scripts/registry-digest.sh 1.0.1); echo "before: $BEFORE"
docker build -q --build-arg APP_VERSION=EVIL -t localhost:5001/chai-stall:1.0.1 ../../app >/dev/null
docker push -q localhost:5001/chai-stall:1.0.1 >/dev/null
AFTER=$(./scripts/registry-digest.sh 1.0.1);  echo "after:  $AFTER"
```
The **tag still says `1.0.1`, the content is different**. The registry accepted it without complaint. Anything that deploys "`1.0.1`" now runs different code, and nothing noticed. But the digest the pipeline recorded still points at the **original**:
```bash
docker rmi localhost:5001/chai-stall:1.0.1 >/dev/null
docker pull -q localhost:5001/chai-stall@${BEFORE}
docker inspect --format '{{.Config.Env}}' localhost:5001/chai-stall@${BEFORE} | grep -o 'APP_VERSION=[^ ]*'
```
You get back the real `APP_VERSION=1.0.1`. **Deploy by digest** (`image@sha256:...`) when integrity matters, and use registry features that make tags immutable (GitHub Container Registry, ECR, Harbor all have them). This is also *why C00 says "promote the same artifact"*: you promote a digest, not a hope.

> Put things back in order: run **ci-cd** once more so a fresh, legitimate image takes the next tag.

### Step 2: Artifacts in Jenkins (5 min)
In the `Push to registry` stage:
```groovy
archiveArtifacts artifacts: 'build-info.json, test-output.txt', fingerprint: true
```
- `archiveArtifacts` stores the files with the build (download them from the build page; they expire per `buildDiscarder`).
- `fingerprint: true` records the files' MD5 so Jenkins can answer *"which builds produced or used this exact file?"* (click **See fingerprints** on the build).
- It is for **small** outputs (reports, manifests, binaries of a few MB). Container images and big binaries belong in a registry or an artifact repository (Nexus, Artifactory, GitHub Packages), never in Jenkins.

### Step 3: Secrets: where they live (10 min)
Open **Manage Jenkins → Credentials → System → Global credentials**. You see `deploy-token` and `registry-creds`. Click `deploy-token → Update`: the secret shows only as "Concealed". Where did it come from? Look at the file:
```bash
grep -n -B2 -A3 "deploy-token" jenkins/casc/jenkins.yaml
cat .env.example | grep DEPLOY_TOKEN
git check-ignore -v .env                                    # .env is ignored by Git
```
The YAML says `secret: "${DEPLOY_TOKEN:-change-me-in-dot-env}"`: **a reference, not a value**. The value comes from `.env` on *your* machine, which Git ignores. So the repository can be public and the Jenkins config reviewed by everyone without exposing a secret. This is the pattern: **configuration in Git, secrets in a vault** (here a local file; in production Vault, AWS Secrets Manager, Kubernetes Secrets, GitHub/GitLab secret stores).

### Step 4: Masking, and how it fails (10 min)
Run **chai-stall → secrets-demo → Build Now**, open the console. The job ([`pipelines.groovy`](../projects/project-1-ship-it/jenkins/jobs/pipelines.groovy)) binds the secret to `$TOKEN` and prints four things:
```
1) printing it directly:   ****
2) length of the secret:   22
3) the same secret, reversed: 24-nekot-yolped-t3rc3s
4) outside the block:       [nothing here]
```
- **1)** Jenkins **masked** the exact value: good.
- **3)** The same secret, **reversed**, sailed straight through. Masking only catches the *exact* string (and a few encodings such as base64). Splitting it, adding spaces between letters, or encoding it another way defeats it. Anyone who can edit a pipeline can read any secret that pipeline can use.
- **4)** Outside the `withCredentials` block, the variable does not exist: the secret's scope was five lines.

Lessons that follow:
1. Treat masking as a **seatbelt, not a safe**.
2. **Restrict who can change pipelines** and require review (branch protection): that, not masking, is the real protection.
3. Give each credential the **narrowest scope** (one folder, one job) and make the secret itself **low power** (a deploy token for staging only; short-lived; easy to rotate).
4. Prefer **short-lived** credentials issued per build (OIDC to a cloud, Vault leases) over long-lived passwords.

Also notice **how** the registry login is done in the real [`Jenkinsfile`](../projects/project-1-ship-it/Jenkinsfile):
```groovy
withCredentials([usernamePassword(credentialsId: 'registry-creds', usernameVariable: 'REG_USER', passwordVariable: 'REG_PASS')]) {
  sh '''
    export DOCKER_CONFIG="$WORKSPACE/.docker"
    echo "$REG_PASS" | docker login -u "$REG_USER" --password-stdin $REGISTRY   # password via stdin, never on the command line
    docker push ...
    docker logout $REGISTRY
  '''
}
```
Three habits in six lines: the password goes through **stdin** (command lines are visible to every process via `ps`); credentials are kept in a **throwaway `DOCKER_CONFIG`** instead of the shared home folder; and the pipeline **logs out** after.

Single quotes matter too. `sh 'echo $TOKEN'` lets the **shell** read the variable (safe). `sh "echo $TOKEN"` lets **Groovy** paste the secret into the script text first, where it can appear in logs and process lists. Jenkins even warns about it. Use single quotes for secrets.

### Step 5: Gate 1: the secret scan (5 min)
A secret that reaches Git is a leaked secret. [`secret-scan.sh`](../projects/project-1-ship-it/scripts/secret-scan.sh) is a 20-line version of what gitleaks and GitHub secret scanning do. See it work locally:
```bash
printf 'AWS_KEY = "AKIAABCDEFGHIJKLMNOP"\n' > /tmp/leak.py
./scripts/secret-scan.sh /tmp/leak.py ; echo "exit code: $?"
```
It prints the offending line and exits `1`. Now let the **pipeline** catch one. On your branch:
```bash
cd ../../..
printf '\nAPI_KEY = "AKIAABCDEFGHIJKLMNOP"\n' >> cicd-observability/app/app.py
git commit -am "oops, a key"
```
Wait for the poll (or **Build Now**). In the stage view, **Checks in parallel → Secret scan** turns red, and nothing after it runs: no image is built, nothing is pushed or deployed. Then clean up the local experiment:
```bash
git reset --hard HEAD~1            # local only: removes your "oops" commit. CAREFUL: it also discards any uncommitted work, so commit or stash yours first
```
> ⚠️ **The most important rule of this lab.** Had that been a *real* key and you had pushed it, deleting it in the next commit would **not** make you safe: the key is in the history and in every clone. **Rotate the key first** (make the old one worthless), clean up later. The scan is a safety net that catches it *before* the push (in a pre-commit hook) or *before the merge* (in CI); it cannot un-leak a published secret.

### Step 6: Gate 2: image policy (5 min)
[`image-policy.sh`](../projects/project-1-ship-it/scripts/image-policy.sh) is **policy as code**: house rules for images, checked on every build.
```bash
./scripts/image-policy.sh localhost:5001/chai-stall:1.0.2                 # passes: non-root, healthcheck, version
printf 'FROM alpine\nCMD ["sleep","1"]\n' | docker build -q -t bad:test - >/dev/null
./scripts/image-policy.sh bad:test; echo "exit code: $?"                  # fails three ways
docker rmi bad:test >/dev/null
```
Compare with [`app/Dockerfile`](../app/Dockerfile): `USER 10001` (non-root), `HEALTHCHECK`, a pinned base tag. These are the D11 hardening habits ([D11](../../docker/11-limits-security/README.md)), now **enforced** rather than hoped for.

### Step 7: Gate 3: the vulnerability scan (5 min)
In the `Scan image` stage, **Trivy** runs *as a container* against the image we just built and fails the build on a **CRITICAL** CVE:
```groovy
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache/ \
  aquasec/trivy:0.58.1 image --no-progress --severity CRITICAL --exit-code $EXIT $FULL_IMAGE
```
The three `SCAN_MODE` values are a real-world dial: **enforce** (fail the build), **report** (tell the team, do not block), **skip** (never in real life). Teams usually start in *report* to see how noisy it is, fix the backlog, then switch to *enforce*. Run it by hand to see what it finds:
```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache/ \
  aquasec/trivy:0.58.1 image --no-progress --severity HIGH,CRITICAL localhost:5001/chai-stall:1.0.2
```
Read the table: *Library/Package*, *Vulnerability ID*, *Installed version*, *Fixed version*. "Fixed version" tells you the fix is usually "rebuild on a newer base image". (Needs internet for its first database download, about 1 minute. If your network blocks it, the pipeline's gate **fails closed**: use `SCAN_MODE=report`.)

### Step 8: The elephant in the room: the Docker socket (5 min)
Remember this line in [`docker-compose.yml`](../projects/project-1-ship-it/docker-compose.yml)?
```yaml
- /var/run/docker.sock:/var/run/docker.sock       # Jenkins drives YOUR Docker engine
```
It is what lets Jenkins build and deploy, **and** it is a master key. Prove it: from inside Jenkins, start a container that mounts the *host's* whole filesystem:
```bash
docker exec shipit-jenkins-1 docker run --rm -v /:/host alpine cat /host/etc/os-release
docker exec shipit-jenkins-1 docker run --rm -v /:/host alpine cat /host/etc/hostname
```
You just read a file from outside the Jenkins container, from the Docker host (on Docker Desktop that is its Linux VM). **Anyone who can run a pipeline step can do this**, which means anyone who can edit a `Jenkinsfile` has root on the host. That is the price of this lab's simplicity. Real setups:

| Instead of the socket | Why it is safer |
|---|---|
| **Ephemeral agents** (a fresh VM or Pod per build, destroyed after) | a compromised build dies with its machine |
| **Rootless builders**: Kaniko, BuildKit, Buildah | build images without a privileged daemon |
| **Docker-in-Docker on a throwaway runner** (GitLab's `docker:dind`) | the "host" is disposable |
| **Separate build and deploy credentials** | the machine that builds cannot also reach production |

## 🏭 In production: a short security checklist
- [ ] Pipeline files and `jobs/*.groovy` change **only through reviewed pull requests**. Protected branches.
- [ ] Secrets come from a **vault** or the platform's secret store, never from the repository, never in `Dockerfile` `ENV`/`ARG` (they stay in image layers!).
- [ ] Secrets are **scoped** (per folder/job/environment) and **short-lived** where possible; rotation is a button, not a project.
- [ ] Builds run on **ephemeral, unprivileged agents**; the controller runs no builds.
- [ ] Every image is **scanned**, **non-root**, **pinned** (base image by digest), and deployed **by digest**; images are **signed** (cosign) and an **SBOM** is stored with them.
- [ ] Jenkins and its plugins are **updated** on a schedule; the UI is behind SSO and HTTPS; anonymous access is off (it is, in this lab: `allowAnonymousRead: false`).
- [ ] Logs and artifacts are treated as sensitive: they get read by many people.
- [ ] **Audit trail**: who approved, what was deployed, from which commit (`build-info.json` is a start).

## 🏆 Challenge
Find the **three** security mistakes in this snippet, then fix it:
```groovy
stage('Deploy') {
  steps {
    sh "docker login -u admin -p ${env.REG_PASSWORD} registry.example.com"
    sh "docker run -d -e DB_PASSWORD=hunter2hunter2 registry.example.com/shop:latest"
  }
}
```
<details><summary>Check your answer</summary>

1. **Groovy-interpolated secret** in double quotes (`${env.REG_PASSWORD}`) and **`-p` on the command line**: the password lands in the script text, the logs and `ps`. Fix: `withCredentials(...)`, single-quoted `sh`, and `--password-stdin`.
2. **A hard-coded password** (`DB_PASSWORD=hunter2hunter2`) in the repository: it is in Git history forever. Fix: store it in the credentials store / a vault and inject it at run time; rotate the one that leaked.
3. **`:latest`**: a moving tag; you cannot say what is running or roll back to "the previous latest". Fix: deploy the exact version or, better, the digest recorded by the build (`shop@sha256:...`).
(Bonus: the secret scan would have flagged `DB_PASSWORD=...` only if it were quoted like a Python string; real scanners use many more patterns.)
</details>

## ✅ Checkpoint
<details><summary>1. A colleague says "we deploy <code>chai-stall:1.0.7</code>, so we know exactly what is running". What is the flaw?</summary>

A tag is mutable: someone can push different content under it. The digest is immutable. Record and deploy the digest (and make tags immutable in the registry).
</details>

<details><summary>2. Why is a secret in <code>.env</code> (git-ignored) better than the same secret in <code>jenkins.yaml</code>?</summary>

The YAML is committed and reviewed by many people; a value there is in the history forever. `.env` never enters Git. The YAML holds only the *reference* (`${DEPLOY_TOKEN}`).
</details>

<details><summary>3. The scan stage cannot download its database and the build fails. Is that a bug?</summary>

No: it **fails closed**. A gate that silently passes when it cannot check anything is worse than no gate, because it gives false confidence. Choose `report` or `skip` *knowingly*, for a lab, not as the default.
</details>

## 🧹 Cleanup
```bash
docker rmi bad:test 2>/dev/null; rm -f /tmp/leak.py
```
Leave the stack running for C05.

➡️ Next: [C05 · Image builds and deployment strategies](../C05-images-and-deployment/README.md)
