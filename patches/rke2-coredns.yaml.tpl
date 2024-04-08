
%{ if operator_replica > 1 }
nodeSelector:
  node-role.kubernetes.io/master: "true"
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "100m" # because of autoscaler
    memory: "128Mi"
autoscaler:
  enabled: false
%{ endif }
