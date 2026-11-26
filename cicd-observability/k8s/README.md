# Unit 4 on Kubernetes: shared platform files

| Folder | What | Used by |
|---|---|---|
| [`platform/`](platform/) | namespaces (Pod Security), RBAC, registry, Git server (Gitea), Jenkins Helm values, production Gateway + HTTPRoute | `scripts/k8s-up.sh` |
| [`chart/chai-stall/`](chart/chai-stall/) | the Helm chart of the Chai Stall: Deployment (probes, limits, `restricted` securityContext), Service, PDB, optional HPA / NetworkPolicy / ServiceMonitor, a `helm test` Pod | the pipeline (Project 1), the observability projects (Project 2) |

Entry points live in [`../scripts/`](../scripts/): `k8s-up.sh`, `k8s-down.sh`, `forward.sh`, `new-app-repo.sh`, `k8s-selftest.sh`.
The learner's own app repository is assembled from [`../projects/project-1-ship-it/app-repo/`](../projects/project-1-ship-it/app-repo/), [`../app/`](../app/) and `chart/chai-stall/`.
