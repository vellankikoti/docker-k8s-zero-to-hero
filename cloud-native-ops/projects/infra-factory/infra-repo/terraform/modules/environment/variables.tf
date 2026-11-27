variable "name" { type = string }
variable "env" { type = string }
variable "owner" { type = string }
variable "cost_center" { type = string }

variable "quota" {
  type = object({
    pods            = number
    requests_cpu    = string
    requests_memory = string
    limits_memory   = string
  })
}

variable "ingress_from_namespaces" {
  description = "Namespaces whose Pods may talk to ours (the Gateway, Prometheus, the CI/CD tools)."
  type        = list(string)
  default     = ["envoy-gateway-system", "monitoring", "cicd"]
}
