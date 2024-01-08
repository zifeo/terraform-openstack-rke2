apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-metrics-server
  namespace: kube-system
spec:
  valuesContent: |-
    nodeSelector:
      node-role.kubernetes.io/master: "true"
    tolerations:
      - effect: NoExecute
        key: CriticalAddonsOnly
        operator: "Exists"
