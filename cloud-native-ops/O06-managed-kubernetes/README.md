# O06 · Managed Kubernetes: the same cluster, someone else runs the control plane

> ⏱ 30 min · 🟡 · Read-only: needs no cloud account, and **nothing here is executed by the lab scripts** (a cloud costs money and needs your own account). Everything you learned transfers; this page shows what changes.

## 1. What the provider takes over
| | On your laptop (kind, minikube) | Managed (EKS · GKE · AKS) |
|---|---|---|
| control plane (API server, etcd, scheduler) | you (or the tool) | **the provider**: patched, backed up, highly available |
| nodes | one container or VM | **node pools** you size, upgrade and replace |
| creating the cluster | one command | a **Terraform module** (so the cluster itself is code too) |
| load balancer (`Service type=LoadBalancer`) | needs MetalLB or a port-forward | a **real cloud load balancer**, created by the cluster, billed hourly |
| storage (`StorageClass`) | local path | cloud disks (EBS, Persistent Disk, Azure Disk) |
| identity | your kubeconfig | **cloud IAM mapped to RBAC** (who may `kubectl`), and **workload identity** (which Pod may read which bucket) |
| autoscaling | HPA only | HPA **plus** a cluster autoscaler that adds nodes when Pods cannot be placed |
Your **Deployments, Services, Helm charts, policies, PDBs and Terraform modules do not change.** That is the point of Kubernetes.

## 2. Day-2 operations: the jobs that remain yours
- **Upgrades.** Kubernetes ships about three minor versions a year; each is supported for roughly 12–14 months. Plan: upgrade the **control plane** first, then **node pools**, one version at a time, **dev → staging → prod**. A **PodDisruptionBudget** is what lets nodes be replaced without downtime (Lab K17).
- **Right-sizing and cost.** Node pools are the biggest bill. Tag them, scale non-prod to zero at night ([night shift](../projects/production-ready/README.md)), use spot/preemptible nodes for work that can restart.
- **Security.** Private API endpoint, least-privilege IAM, image scanning, admission policies (you have these), secrets from a cloud secret manager.
- **Observability.** The provider gives you control-plane logs; **you** still run [Prometheus, logs and traces](../../cicd-observability/projects/see-everything/README.md) for your apps.
- **Backups.** The provider backs up the control plane. **Your data** (volumes, databases) is yours.

## 3. The cluster as Terraform (a sketch, not run by the lab)
The same workflow as [Infra Factory](../projects/infra-factory/README.md): variables, a module, a plan, a policy check, an approval, an apply. Roughly (module versions change: use the registry page of the module you choose):
```hcl
# GKE (Google Cloud) — a regional cluster with a small node pool
module "gke" {
  source     = "terraform-google-modules/kubernetes-engine/google"
  project_id = var.project_id
  name       = "chai-${var.env}"
  region     = var.region
  network    = module.vpc.network_name
  subnetwork = module.vpc.subnets_names[0]
  ip_range_pods = "pods"
  ip_range_services = "services"
  node_pools = [{ name = "default", machine_type = "e2-standard-2", min_count = 1, max_count = 3, auto_upgrade = true }]
}
```
```hcl
# EKS (AWS) — the community module
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = "chai-${var.env}"
  cluster_version = "1.31"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets
  eks_managed_node_groups = { default = { instance_types = ["t3.medium"], min_size = 1, max_size = 3, desired_size = 2 } }
}
```
Afterwards, the **same** `kubernetes` and `helm` providers from this track point at the new cluster (`config_path` or the module's outputs), and `tf.sh` works unchanged.

## 4. Three habits before you ever click "create cluster"
1. **Set a budget alert first.** A forgotten cluster is the most common surprise bill.
2. **Create it from code** (above) so the **destroy** is one command too.
3. **Practise on the free tier or a throwaway project**, never on the account that holds anything important.

## ✅ You can now
Say what a managed service takes off your plate and what stays yours · list the day-2 jobs · read a cluster-as-code module and know where it plugs into the rest of this track.
