# 🏁 Unit 4 Projects (Kubernetes edition)

Two end-to-end projects for the Unit 4 lab exercises. They run **inside the cluster you built in Units 2 and 3**, so every step uses something you already know. Each phase ends with a `verify.sh N` check.

| Project | Syllabus lab exercise | You build | Time |
|---|---|---|---|
| [**1 · Ship It**](project-1-ship-it/README.md) | **7**: CI/CD pipelines with Jenkins and GitHub Actions or GitLab CI, with automated build and deployment stages | Gitea + Jenkins (as code, build Pods) + Kaniko + registry → Helm releases in `stall-staging` / `stall-prod` (Pod Security `restricted`, least-privilege RBAC) → rolling, recreate, blue/green and canary with automatic rollback | 2–3 h |
| [**2 · See Everything**](project-2-see-everything/README.md) | **8**: Prometheus, Alertmanager and Grafana for application observability | *(next)* Prometheus Operator, SLO alerts, dashboards as code, logs, traces, a game day | 2–3 h |

Start with `./cicd-observability/scripts/doctor.sh --k8s`.

**No cluster?** The same projects exist for plain Docker: [`compose-edition/`](../compose-edition/README.md).
