apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-cilium
  namespace: kube-system
spec:
  valuesContent: |-
    kubeProxyReplacement: strict
    k8sServiceHost: ${apiserver_host}
    k8sServicePort: ${apiserver_post}
    cni:
      chainingMode: "none"
