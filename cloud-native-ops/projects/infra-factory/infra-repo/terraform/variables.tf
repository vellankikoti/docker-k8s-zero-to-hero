variable "env" {
  description = "Which environment this is: dev, staging or prod. Becomes part of the namespace name and a label on everything."
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.env)
    error_message = "env must be dev, staging or prod."
  }
}

variable "owner" {
  description = "Who answers when it breaks (a team, not a person). Required: the policy refuses a namespace without one."
  type        = string
  default     = "chai-platform-team"
}

variable "cost_center" {
  description = "Who pays for it. Required for the same reason."
  type        = string
  default     = "cc-1042-chai"
}

variable "image_tag" {
  description = "The Chai Stall image version to run, as built by the image pipeline. Never 'latest'."
  type        = string
  default     = "1.0.0"
}

variable "image_repository" {
  description = "Where the nodes pull the image from (the in-cluster registry's NodePort)."
  type        = string
  default     = "localhost:30500/chai-stall"
}

variable "replicas" {
  description = "How many Pods (the starting number; the autoscaler may change it)."
  type        = number
  default     = 1
}

variable "autoscaling" {
  description = "Let the HorizontalPodAutoscaler add Pods under load (needs metrics-server)."
  type = object({
    enabled = bool
    min     = number
    max     = number
    cpu     = number
  })
  default = { enabled = false, min = 1, max = 3, cpu = 70 }
}

variable "quota" {
  description = "The most this environment may use. A fair-share rule for the whole namespace (Lab K09)."
  type = object({
    pods            = number
    requests_cpu    = string
    requests_memory = string
    limits_memory   = string
  })
  default = { pods = 10, requests_cpu = "1", requests_memory = "1Gi", limits_memory = "2Gi" }
}

variable "chart_path" {
  description = "Folder of the Helm chart. scripts/tf.sh fills this in."
  type        = string
  default     = "./chart/chai-stall"
}

variable "wait_for_pods" {
  description = "Make 'apply' wait until the Pods are Ready (true on a real cluster; tests without a kubelet set false)."
  type        = bool
  default     = true
}

variable "monitoring" {
  description = "Let Prometheus scrape the app (creates a ServiceMonitor; needs the Prometheus Operator, see the See Everything project)."
  type        = bool
  default     = false
}

variable "otlp_endpoint" {
  description = "Send traces here (empty = off). The See Everything project's Jaeger is http://jaeger.observability.svc.cluster.local:4318"
  type        = string
  default     = ""
}
