# O00 · Foundations: why we build infrastructure from code

> ⏱ 40 min · 🟢 Beginner · No commands needed (but you will want a cluster open for the "try it" boxes)

By now you can run an app (Docker), run it well (Kubernetes) and ship it (CI/CD, observability). This track answers the next question every team asks: **"how do we make 3 identical environments, change them safely, and still sleep at night?"**

## 1. The problem: ClickOps
Imagine opening three chai stalls by phoning the carpenter, the electrician and the plumber each time and *explaining* what you want. Stall 2 gets one more socket. Stall 3 has a different tap. A year later nobody knows why.
That is **ClickOps**: building infrastructure by clicking and typing commands. It does not scale, it cannot be reviewed, and it cannot be repeated.

## 2. The idea: Infrastructure as Code (IaC)
Write the **blueprint** instead. A text file that says *"3 stalls, each with a counter, a socket, a tap"*. A tool reads it and builds exactly that.
- **Declarative**: you describe the end result (*"I want 3 replicas"*), not the steps. Kubernetes manifests already work like this (Lab K00): *desired state*. Terraform brings the same idea to **everything around** Kubernetes.
- **Versioned**: it lives in Git. Who changed the quota, when, and why? `git log` answers.
- **Repeatable**: dev, staging and prod come from the same blueprint, with different numbers.
- **Reviewable**: a colleague reads the *plan* before anything is built.

| Tool | What it is good at | You already used it for |
|---|---|---|
| `kubectl apply` | the objects *inside* a cluster | all the K-labs |
| **Helm** | packaging an app: templates + values | the Chai Stall chart |
| **Terraform** | the *environment* around apps: namespaces, quotas, networks, access, clusters, clouds | **this track** |
| Pipelines (Jenkins) | running all of it the same way, every time, with approvals | Ship It |

*Terraform vs Helm:* Helm answers "what is a Chai Stall?" (Deployment, Service, probes). Terraform answers "where does it live, how big, who may touch it, and is the place safe?". They work together: the infra-factory project uses **Terraform to release the Helm chart**.

## 3. The Terraform vocabulary (learn these 8 words)
| Word | In chai-stall words |
|---|---|
| **provider** | the translator to a platform (Kubernetes, AWS, GCP, Helm…). Without it Terraform knows nothing |
| **resource** | one thing to build: a namespace, a quota |
| **variable** | a number you choose per environment (replicas, quota) |
| **output** | a value to show afterwards (the namespace name) |
| **module** | a reusable recipe: "a landing zone". Written once, used for dev, staging and prod |
| **plan** | the architect's drawing: *what I WILL do*. Reading it is the whole safety of Terraform |
| **apply** | build what the plan said |
| **state** | the architect's notebook of what is already built. Lose it, and he builds a second stall next to the first |
Two companions: **drift** (someone changed the building by hand, so the blueprint and the stall disagree) and **policy** (the inspector who reads the drawing before you build).

## 4. The cloud-native workflow, end to end
```
 idea ─▶ change the blueprint in Git ─▶ pull request ─▶ pipeline: fmt, validate, PLAN
                                                              │
                                              policy check ◀──┘   (conftest / OPA: "no 'latest', every namespace has an owner")
                                                  │
                                       a human reads the plan and approves   (always for prod)
                                                  │
                                            APPLY the same plan ─▶ verify ─▶ measure (DORA) ─▶ learn
```
Three principles run through every project in this track:
1. **Everything is a file in Git** (the blueprint, the policy, the pipeline, the dashboard, the runbook).
2. **A human approves what a machine will do**, and the machine does exactly what was approved (saved plans).
3. **The system protects itself** (least privilege, policy, backups, limits), because people are tired at 3 a.m.

## 5. Reliability: what "production" really means
A service is reliable when users can depend on it **and** you can change it often. The tools you will meet:
- **Redundancy**: 2+ copies (Lab K04), spread out (K17), with a **PodDisruptionBudget**.
- **Self-healing and probes** (K08): the cluster restarts what is sick and stops sending traffic to what is not ready.
- **Autoscaling and load balancing** (K13, K05): capacity follows demand.
- **SLOs and error budgets** (C09): "99% of orders succeed" is a *promise*; the 1% you may fail is a *budget* to spend on shipping change.
- **Backups with a tested restore**, and two numbers: **RPO** (how much data can we lose?) and **RTO** (how long can we be down?).
- **Guardrails** that limit the blast radius of a mistake.
- **Practice**: game days, case files, blameless postmortems.

## 6. Managed Kubernetes in one paragraph
On a laptop you run the control plane yourself. In the cloud (EKS, GKE, AKS) the provider runs it and you manage **node pools**, **upgrades**, **identity (IAM mapped to RBAC)**, **cloud load balancers** and **storage classes**. Your manifests, Helm charts and Terraform modules stay the same; what changes is *who patches the control plane* and *how the cluster itself is created* (which is also a Terraform job). See [O06](../O06-managed-kubernetes/README.md).

## 7. How the work is measured (DORA)
Four numbers that research teams use to compare delivery performance: **deployment frequency**, **lead time for changes**, **change failure rate**, **time to restore**. Fast *and* safe go together: teams that ship small changes often break less and recover sooner. You will compute them from real release history in [Production Ready](../projects/production-ready/README.md).

## 8. Your map
| Lab | Topic | Hands-on in |
|---|---|---|
| [O01](../O01-terraform-first-steps/README.md) | first Terraform, variables, secrets | a scratch folder (15 min) |
| [O02](../O02-state-modules-environments/README.md) | state, modules, environments, drift | [Infra Factory](../projects/infra-factory/README.md) |
| [O03](../O03-iac-in-cicd/README.md) | pipelines for infrastructure, policy, image lifecycle | [Infra Factory](../projects/infra-factory/README.md) |
| [O04](../O04-scale-balance-survive/README.md) | autoscaling, load balancing, reliability | [Production Ready](../projects/production-ready/README.md) |
| [O05](../O05-backup-security-cost/README.md) | backup, secrets, policy, cost, DORA | [Production Ready](../projects/production-ready/README.md) |
| [O06](../O06-managed-kubernetes/README.md) | managed Kubernetes (EKS / GKE / AKS) | reading + a Terraform sketch |

## ✅ Quick check (answers at the bottom)
1. Why is a *plan* safer than "just run it"?  2. What is lost if the state is lost?  3. Why does production need a person to approve, even with a pipeline?  4. What is the difference between RPO and RTO?  5. Why does the policy check run *before* apply?
<details><summary>Answers</summary>
1. You read what will happen *before* it happens; the same saved plan is then applied, so what you reviewed is what runs.
2. Terraform no longer knows what it built: it would try to create everything again (or you must import it by hand).
3. A pipeline repeats mistakes quickly; a human catches "wait, that deletes prod".
4. RPO = how much data you may lose (time between backups). RTO = how long recovery may take.
5. It is cheaper and safer to refuse a bad change at the drawing than to clean up after it.
</details>
