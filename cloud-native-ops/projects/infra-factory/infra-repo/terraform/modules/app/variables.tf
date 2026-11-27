variable "namespace" { type = string }
variable "env" { type = string }
variable "chart_path" { type = string }
variable "image_repo" { type = string }
variable "image_tag" { type = string }
variable "replicas" { type = number }
variable "wait" { type = bool }
variable "otlp_endpoint" { type = string }

variable "autoscaling" {
  type = object({
    enabled = bool
    min     = number
    max     = number
    cpu     = number
  })
}
