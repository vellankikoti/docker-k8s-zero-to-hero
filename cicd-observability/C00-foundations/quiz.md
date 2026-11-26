# C00 Quiz: CI/CD, Observability, SLOs

30 questions. Say your answer out loud (or write it down) **before** you open the answer.

## Part A: CI/CD (10)

<details><summary>1. What is the difference between continuous delivery and continuous deployment?</summary>

In **delivery** every passing change is *ready* to release and a human presses the final button. In **deployment** every passing change is released automatically, with no human step.
</details>

<details><summary>2. Why should you "build once, promote the same artifact"?</summary>

Rebuilding for production can pull a different dependency version or base image, so production would run something nobody tested. Build one image, test it in staging, then promote that exact image (same digest) to production.
</details>

<details><summary>3. Your pipeline takes 25 minutes and developers have started ignoring it. What is the first thing to look at?</summary>

Order and parallelism. Put the fast checks (lint, unit tests, secret scan) first so the common failures show up in under a minute; run independent checks in parallel; cache dependencies; and move slow tests later or to a nightly run.
</details>

<details><summary>4. Why is "the pipeline is defined in a web UI" a problem?</summary>

It cannot be reviewed, versioned, diffed, copied to another project or recovered after a crash. Pipeline as Code (a `Jenkinsfile`, workflow YAML) puts it in Git with the rest of the system.
</details>

<details><summary>5. Name three things a pipeline gate should be able to stop.</summary>

Any of: failing tests, a committed secret, a critical vulnerability in the image, an image that runs as root or has no health check, a failed smoke test, a canary whose error rate is too high, or no human approval.
</details>

<details><summary>6. In Jenkins, what is the difference between the controller and an agent?</summary>

The **controller** stores configuration, schedules builds, and serves the UI; it should do no heavy work. **Agents** (executors on them) run the actual build steps. Keeping them apart protects the controller and lets you add capacity.
</details>

<details><summary>7. What does the <code>post</code> section of a declarative pipeline do?</summary>

It runs after the stages, with conditions: `always`, `success`, `failure`, `unstable`, `changed`. Use it for cleanup, notifications and archiving, which must happen even when a stage fails.
</details>

<details><summary>8. What is a "dynamic pipeline"?</summary>

One whose stages or jobs are generated at run time from data (a JSON file, a list of services, the changed folders) instead of being written one by one. Adding a check becomes a data change, not a pipeline rewrite.
</details>

<details><summary>9. What is Job DSL for?</summary>

Defining Jenkins **jobs** as code (Groovy). A "seed" job runs the DSL and creates or updates all the other jobs, so the Jenkins setup is reproducible and reviewable.
</details>

<details><summary>10. Why does the lab's Jenkins container run as root and mount the Docker socket, and why is that unsafe in real life?</summary>

It makes the lab simple: Jenkins can build, push and deploy through your Docker engine. But anyone who can run a build can then run any container on the host, which is the same as root on the host. Real setups use ephemeral build agents, rootless builders (Kaniko, BuildKit) or a separate build cluster.
</details>

## Part B: Security and artifacts (5)

<details><summary>11. Why are image tags a weak way to identify an artifact, and what is stronger?</summary>

A tag (`1.0.3`, `latest`) is a movable label: someone can push a different image under the same tag. A **digest** (`sha256:...`) is a hash of the content: it cannot point at anything else. Deploy by digest when it matters.
</details>

<details><summary>12. Jenkins masks a secret as <code>****</code> in the log. Name a way it still leaks.</summary>

Printing it transformed (reversed, split, with spaces between letters), writing it to a file that is archived, passing it on a command line others can read, sending it to a service, or Groovy string interpolation that puts it in the process list. Masking is a seatbelt, not a safe.
</details>

<details><summary>13. A developer committed a password to Git and then deleted it in the next commit. Is it safe?</summary>

No. It is still in the history and in every clone. **Rotate (change) the secret first**, then clean the history if you must. The leak is not "fixed" by deleting the file.
</details>

<details><summary>14. What does "least privilege" mean for a pipeline?</summary>

The job gets only the permissions and secrets it needs, only for the steps that need them, for as short a time as possible (for example `permissions: contents: read` in GitHub Actions, credentials bound to one `withCredentials` block).
</details>

<details><summary>15. What does a container image scan find, and what does it not find?</summary>

It finds **known** vulnerabilities (CVEs) in OS packages and libraries, and sometimes misconfigurations. It does not find your own logic bugs, new unknown vulnerabilities, or secrets in your application's behaviour.
</details>

## Part C: Deployment strategies (5)

<details><summary>16. Which strategy has downtime, and when is that acceptable?</summary>

**Recreate** (stop old, start new). Acceptable for development/staging, or an app that cannot run two versions at once and can tolerate a short maintenance window.
</details>

<details><summary>17. Why does a rolling update need a readiness check?</summary>

Otherwise the platform would send traffic to a new replica before it is ready, and retire an old one too early. The check says when it is safe to move to the next replica.
</details>

<details><summary>18. What is the main cost of blue/green, and its main benefit?</summary>

Cost: double the capacity while both run. Benefit: the old version is still running and warm, so rollback is an instant switch back.
</details>

<details><summary>19. A canary gets 10% of traffic and 30% of the canary's requests fail. What is the failure rate users see, and what should happen?</summary>

About 3% overall (10% × 30%), which can hide inside normal noise. Judge the canary on **its own** error rate (30%), not the blended one, and roll back automatically.
</details>

<details><summary>20. Why is a deploy-time smoke test deterministic (readyz, info) rather than "place one order"?</summary>

A smoke test must give the same answer every time for a healthy release. One random order against a release with a 20% bug passes 80% of the time, so it would be flaky. Gradual traffic analysis (a canary check with many requests) is the right tool for subtle bugs.
</details>

## Part D: Observability (6)

<details><summary>21. Monitoring vs observability, in one sentence each.</summary>

Monitoring answers questions you decided to ask in advance (dashboards, alerts). Observability lets you answer questions you did not anticipate, from the telemetry the system already emits.
</details>

<details><summary>22. Which pillar do you alert on, and why?</summary>

**Metrics**: they are cheap, numeric, and fast to evaluate, so rules can run every few seconds. Logs and traces are for finding the cause after the alert.
</details>

<details><summary>23. Why query <code>rate(http_requests_total[1m])</code> instead of <code>http_requests_total</code>?</summary>

A counter only goes up, so its raw value is meaningless for "how busy now". `rate()` turns it into "per second over the last minute" and also handles counter resets on restart.
</details>

<details><summary>24. Why is the p95 latency better than the average?</summary>

Averages hide pain: 95 fast requests and 5 very slow ones average out to "fine". The p95 says "95% of requests were this fast or faster", so slow tails show up.
</details>

<details><summary>25. What is cardinality, and how can it hurt Prometheus?</summary>

The number of distinct label combinations. A label with unbounded values (user id, raw URL) creates a new time series for every value and can exhaust memory. That is why the Chai Stall maps unknown paths to `path="other"`.
</details>

<details><summary>26. Why does Prometheus <em>pull</em> metrics, and what do you get for free?</summary>

Pull means Prometheus controls timing and knows the full list of targets, so a target that stops answering is detected immediately: `up == 0`. No extra "heartbeat" code is needed.
</details>

## Part E: SLOs and incidents (4)

<details><summary>27. Explain SLI, SLO and SLA to a non-technical manager in one line each.</summary>

SLI: what we measure. SLO: the target we promise ourselves. SLA: the promise we make to customers, with a penalty.
</details>

<details><summary>28. A 99.9% SLO over 30 days: how much downtime is allowed?</summary>

About **43 minutes** (0.1% of 43,200 minutes).
</details>

<details><summary>29. Why alert on burn rate instead of "error rate above 1%"?</summary>

A burn rate ties the alert to the **error budget**: a big spike pages immediately (fast burn); a small steady leak opens a ticket (slow burn); and a tiny blip that costs nothing does neither. Two windows (short and long) reduce false alarms.
</details>

<details><summary>30. Your service is broken and you suspect last hour's release. What do you do first, and why?</summary>

**Mitigate**: roll back. Restoring service is the priority; diagnosing is for afterwards, with the evidence you preserved. Then write a blameless postmortem.
</details>
