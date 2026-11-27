# 🐳 CI/CD and observability, Docker Compose edition (no cluster needed)

Two end-to-end projects for this track. Each phase ends with a `./scripts/verify.sh N` check.

| Project | The skill | You build | Time |
|---|---|---|---|
| [**Ship It**](ship-it/README.md) | CI/CD pipelines with Jenkins and GitHub Actions or GitLab CI, with automated build and deployment stages | Jenkins (as code) → tests, scans, image build, registry → staging → approval → production with recreate / rolling / blue-green / canary and automatic rollback; the same pipeline on GitHub Actions | 2–3 h |
| [**See Everything**](see-everything/README.md) | Prometheus monitoring, Alertmanager alerts and Grafana dashboards for application observability | Prometheus + Alertmanager + Grafana + Loki + Jaeger around a live app: golden signals, SLO burn-rate alerts, tested rules, dashboards as code, an email for every incident, runbook and postmortem | 2–3 h |

They are designed to join: in [See Everything, Phase 7](see-everything/README.md) you watch Ship It's canary release on See Everything's dashboard.

Run them one at a time on a small laptop (about 2 GB of memory each). Start with `./cicd-observability/scripts/doctor.sh`.
