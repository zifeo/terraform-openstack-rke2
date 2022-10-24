apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: snapshot-controller
  namespace: kube-system
spec:
  chart: snapshot-controller
  repo: https://piraeus.io/helm-charts
  version: 1.6.0
  targetNamespace: kube-system
  bootstrap: True
  valuesContent: |-
    resources:
      requests:
        cpu: 50m
        memory: 64Mi

    nodeSelector:
      node-role.kubernetes.io/master: "true"

    tolerations:
      - effect: NoExecute
        key: CriticalAddonsOnly
        operator: "Exists"
