# dev: small, cheap, one Pod. Break things here first.
env      = "dev"
replicas = 1
quota    = { pods = 6, requests_cpu = "500m", requests_memory = "512Mi", limits_memory = "1Gi" }
