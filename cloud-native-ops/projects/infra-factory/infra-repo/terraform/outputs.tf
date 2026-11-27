output "namespace" {
  value = module.environment.namespace
}

output "release" {
  value = module.app.release_name
}

output "image" {
  value = "${var.image_repository}:${var.image_tag}"
}

output "next_steps" {
  value = "kubectl -n ${module.environment.namespace} get deploy,pods,hpa,resourcequota"
}
