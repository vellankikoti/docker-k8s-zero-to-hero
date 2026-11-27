# CI/CD and observability on Kubernetes: shared platform files

| Folder | What | Used by |
|---|---|---|
| [`platform/`](platform/) | namespaces (Pod Security), RBAC, registry, Git server (Gitea), Jenkins Helm values, production Gateway + HTTPRoute | `scripts/k8s-up.sh` |
| [`pipeline/`](pipeline/) | **the logic of every pipeline stage** (`stage.sh`, `k8s-deploy.sh`, `diagnose.sh`, `canary-check.sh`, `secret-scan.sh`), published to the cluster as the ConfigMap `z2h-pipeline` and mounted at `/opt/z2h` in every build Pod. Platform-owned: a fix reaches everyone with `git pull` + `k8s-up.sh`, nothing is copied into learners' repos | `scripts/k8s-up.sh` |
| [`chart/chai-stall/`](chart/chai-stall/) | the Helm chart of the Chai Stall: Deployment (probes, limits, `restricted` securityContext), Service, PDB, optional HPA / NetworkPolicy / ServiceMonitor, a `helm test` Pod | the pipeline (Ship It), the observability projects (See Everything) |

Entry points live in [`../scripts/`](../scripts/): `k8s-up.sh`, `k8s-down.sh`, `forward.sh`, `new-app-repo.sh`, `k8s-selftest.sh`.
The learner's own app repository is assembled from [`../projects/ship-it/app-repo/`](../projects/ship-it/app-repo/), [`../app/`](../app/) and `chart/chai-stall/`.
