# The whole environment, in two lines you can read: a place for the app to live (with rules), and the app itself.
locals {
  namespace = "iac-${var.env}"
}

module "environment" {
  source      = "./modules/environment"
  name        = local.namespace
  env         = var.env
  owner       = var.owner
  cost_center = var.cost_center
  quota       = var.quota
}

module "app" {
  source        = "./modules/app"
  namespace     = module.environment.namespace # using the output makes Terraform create the namespace FIRST
  env           = var.env
  chart_path    = var.chart_path
  image_repo    = var.image_repository
  image_tag     = var.image_tag
  replicas      = var.replicas
  autoscaling   = var.autoscaling
  wait          = var.wait_for_pods
  otlp_endpoint = var.otlp_endpoint
}
