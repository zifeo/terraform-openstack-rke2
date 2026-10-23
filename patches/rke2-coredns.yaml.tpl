resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "100m" # because of autoscaler
    memory: "128Mi"
autoscaler:
  min: ${agent_replica}
  # its two replicas from two nodes on would leave one Pending on a single agent: min decides
  preventSinglePointFailure: false
# the agents only: a replica on a server stays a kube-dns backend until its node turns NotReady (50 s) when it dies, and
# none answers while every server is down. One per agent (the chart's anti-affinity), so a rollout frees an agent first
tolerations: []
rollingUpdate:
  maxUnavailable: 1
  maxSurge: 0
# two drains at once never take every replica; a single replica still drains
podDisruptionBudget:
  maxUnavailable: 1
