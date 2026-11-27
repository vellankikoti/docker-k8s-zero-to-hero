# staging: shaped like prod, smaller. A release proves itself here.
env      = "staging"
replicas = 2
quota    = { pods = 8, requests_cpu = "1", requests_memory = "1Gi", limits_memory = "2Gi" }
