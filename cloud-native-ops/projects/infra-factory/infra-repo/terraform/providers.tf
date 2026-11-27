# Both providers talk to the cluster named by kubeconfig. On your laptop that is your own kubectl login;
# in the pipeline scripts/mk-kubeconfig.sh writes one from the build Pod's ServiceAccount token. Nothing else changes.
variable "kubeconfig" {
  description = "Path to the kubeconfig file."
  type        = string
  default     = "~/.kube/config"
}

provider "kubernetes" {
  config_path = var.kubeconfig
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig
  }
  helm_driver = "configmap" # keep release records in ConfigMaps: the runner needs no cluster-wide access to Secrets
}
