# A "landing zone": the namespace and every rule around it, so an app can only land somewhere that is safe, fair and labelled.
terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes" }
  }
}

locals {
  labels = {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "chai-stall"
    "z2h/env"                      = var.env
    "z2h/owner"                    = var.owner
    "z2h/cost-center"              = var.cost_center
  }
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.name
    labels = merge(local.labels, {
      "pod-security.kubernetes.io/enforce" = "restricted" # Lab K16: no root, no privileged Pods in here
    })
  }
}

# Fair share (Lab K09): the whole namespace may not use more than this, so a runaway dev app cannot starve prod's neighbours.
resource "kubernetes_resource_quota_v1" "this" {
  metadata {
    name      = "environment-budget"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }
  # After creating a quota, the provider waits until the cluster has filled in its usage numbers. The default patience is 30 s,
  # which a busy cluster can exceed ("Quotas don't match after creation"). Give it five minutes; up.sh also checks the controller first.
  timeouts {
    create = "5m"
  }
  spec {
    hard = {
      "pods"            = var.quota.pods
      "requests.cpu"    = var.quota.requests_cpu
      "requests.memory" = var.quota.requests_memory
      "limits.memory"   = var.quota.limits_memory
    }
  }
}

# Defaults for a container that forgot to say what it needs (Lab K09), so nothing ever runs with no limits at all.
resource "kubernetes_limit_range_v1" "this" {
  metadata {
    name      = "container-defaults"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }
  spec {
    limit {
      type    = "Container"
      default = { memory = "128Mi" }
      default_request = {
        cpu    = "25m"
        memory = "48Mi"
      }
    }
  }
}

# Default deny (Lab K15): nobody may talk to our Pods unless a rule below says so.
resource "kubernetes_network_policy_v1" "default_deny" {
  metadata {
    name      = "default-deny-ingress"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy_v1" "allow_known_neighbours" {
  metadata {
    name      = "allow-known-neighbours"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    ingress {
      from {
        pod_selector {} # Pods of this same namespace
      }
      dynamic "from" {
        for_each = var.ingress_from_namespaces
        content {
          namespace_selector {
            match_labels = { "kubernetes.io/metadata.name" = from.value }
          }
        }
      }
    }
  }
}

# Least privilege for people (Lab K14): the on-call group may look and scale, never delete or read Secrets.
resource "kubernetes_role_v1" "operator" {
  metadata {
    name      = "app-operator"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log", "services", "events"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "deployments/scale"]
    verbs      = ["get", "list", "watch", "patch", "update"]
  }
}

resource "kubernetes_role_binding_v1" "operator" {
  metadata {
    name      = "app-operator"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.operator.metadata[0].name
  }
  subject {
    kind      = "Group"
    name      = "chai-oncall-${var.env}"
    api_group = "rbac.authorization.k8s.io"
  }
}
