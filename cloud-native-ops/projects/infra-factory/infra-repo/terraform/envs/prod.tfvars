# prod: two Pods at least, the autoscaler may add more, a PodDisruptionBudget protects it during maintenance.
env         = "prod"
replicas    = 2
autoscaling = { enabled = true, min = 2, max = 5, cpu = 70 }
quota       = { pods = 12, requests_cpu = "2", requests_memory = "2Gi", limits_memory = "4Gi" }
