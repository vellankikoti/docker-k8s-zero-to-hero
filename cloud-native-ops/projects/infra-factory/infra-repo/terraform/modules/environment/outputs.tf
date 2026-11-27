output "namespace" {
  description = "The namespace name. Depending on this output makes everything else wait for the namespace to exist."
  value       = kubernetes_namespace_v1.this.metadata[0].name
}
