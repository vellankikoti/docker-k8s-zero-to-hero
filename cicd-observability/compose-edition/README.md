# 🐳 Unit 4, Docker Compose edition (no cluster needed)

Two end-to-end projects for the Unit 4 lab exercises. Each phase ends with a `./scripts/verify.sh N` check.

| Project | Syllabus lab exercise | You build | Time |
|---|---|---|---|
| [**1 · Ship It**](project-1-ship-it/README.md) | **7**: CI/CD pipelines with Jenkins and GitHub Actions or GitLab CI, with automated build and deployment stages | Jenkins (as code) → tests, scans, image build, registry → staging → approval → production with recreate / rolling / blue-green / canary and automatic rollback; the same pipeline on GitHub Actions | 2–3 h |
| [**2 · See Everything**](project-2-see-everything/README.md) | **8**: Prometheus monitoring, Alertmanager alerts and Grafana dashboards for application observability | Prometheus + Alertmanager + Grafana + Loki + Jaeger around a live app: golden signals, SLO burn-rate alerts, tested rules, dashboards as code, an email for every incident, runbook and postmortem | 2–3 h |

They are designed to join: in [Project 2, Phase 7](project-2-see-everything/README.md) you watch Project 1's canary release on Project 2's dashboard.

Run them one at a time on a small laptop (about 2 GB of memory each). Start with `./cicd-observability/scripts/doctor.sh`.
