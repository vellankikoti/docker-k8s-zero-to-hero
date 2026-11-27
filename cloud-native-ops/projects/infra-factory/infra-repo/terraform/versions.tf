terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.35" }
    helm       = { source = "hashicorp/helm", version = "~> 2.17" }
  }

  # Remote state: Terraform's memory of what it built lives in a Secret INSIDE the cluster (namespace "tfstate"), with a
  # Lease as the lock, so two people (or a person and the pipeline) can never apply at the same moment.
  # Which Secret: chosen per environment by  -backend-config=envs/<env>.backend.hcl  (scripts/tf.sh does this for you).
  backend "kubernetes" {}
}
