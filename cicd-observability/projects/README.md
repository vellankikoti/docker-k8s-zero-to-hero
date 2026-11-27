# 🏁 Projects (Kubernetes edition)

Two end-to-end projects for this track. They run **inside the Kubernetes cluster you already know**, so every step uses something you already know. Each phase ends with a `verify.sh N` check.

| Project | The skill | You build | Time |
|---|---|---|---|
| [**Ship It**](ship-it/README.md) | CI/CD pipelines with Jenkins and GitHub Actions or GitLab CI, with automated build and deployment stages | Gitea + Jenkins (as code, build Pods) + Kaniko + registry → Helm releases in `stall-staging` / `stall-prod` (Pod Security `restricted`, least-privilege RBAC) → rolling, recreate, blue/green and canary with automatic rollback | 2–3 h |
| [**See Everything**](see-everything/README.md) | Prometheus, Alertmanager and Grafana for application observability | *(next)* Prometheus Operator, SLO alerts, dashboards as code, logs, traces, a game day | 2–3 h |

Start with `./cicd-observability/scripts/doctor.sh --k8s`.

**No cluster?** The same projects exist for plain Docker: [`compose-edition/`](../compose-edition/README.md).
