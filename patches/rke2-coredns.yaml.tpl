resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "100m" # because of autoscaler
    memory: "128Mi"
autoscaler:
  min: ${operator_replica}
  resources:
    requests:
      cpu: "20m"
      memory: "10Mi"
    limits:
      memory: "10Mi"
