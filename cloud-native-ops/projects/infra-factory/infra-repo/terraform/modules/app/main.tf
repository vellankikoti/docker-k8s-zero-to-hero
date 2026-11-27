# The application: the SAME Helm chart the pipeline uses, released by Terraform. Terraform decides WHERE and HOW BIG;
# the chart decides what a Chai Stall IS (probes, limits, securityContext).
terraform {
  required_providers {
    helm = { source = "hashicorp/helm" }
  }
}

resource "helm_release" "chai_stall" {
  name      = "chai-stall"
  namespace = var.namespace
  chart     = var.chart_path
  wait      = var.wait
  timeout   = 300
  atomic    = false # on a failure we want to SEE the Pods, not have Helm delete the evidence (Lab O03)
  lint      = true

  values = [yamlencode({
    env = var.env # not used by the chart: it lets the policy check know which environment this is
    image = {
      repository = var.image_repo
      tag        = var.image_tag
    }
    replicaCount = var.replicas
    autoscaling = {
      enabled                        = var.autoscaling.enabled
      minReplicas                    = var.autoscaling.min
      maxReplicas                    = var.autoscaling.max
      targetCPUUtilizationPercentage = var.autoscaling.cpu
    }
    podDisruptionBudget = { enabled = var.env == "prod" }
    commonLabels        = var.common_labels
    serviceMonitor      = { enabled = var.monitoring, interval = "10s", labels = { release = "kube-prometheus-stack" } }
    otlpEndpoint        = var.otlp_endpoint
  })]
}
