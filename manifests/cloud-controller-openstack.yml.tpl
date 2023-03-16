apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: openstack-cloud-controller-manager
  namespace: kube-system
spec:
  chart: openstack-cloud-controller-manager
  repo: https://kubernetes.github.io/cloud-provider-openstack
  version: 1.4.0
  targetNamespace: kube-system
  bootstrap: true
  valuesContent: |-
    image:
      repository: docker.io/k8scloudprovider/openstack-cloud-controller-manager
      tag: "v1.26.2"
    nodeSelector:
      node-role.kubernetes.io/master: "true"
    tolerations:
      - effect: NoExecute
        key: CriticalAddonsOnly
        operator: "Exists"
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
    cloudConfig:
      global:
        auth-url: ${auth_url}
        application-credential-name: ${app_name}
        application-credential-id: ${app_id}
        application-credential-secret: ${app_secret}
        region: ${region}
        tenant-id: ${project_id}
      loadBalancer:
        %{~ if floating_network_id != null ~}
        floating-network-id: ${floating_network_id}
        %{~ endif ~}
        subnet-id: ${subnet_id}
        network-id: ${network_id}
        lb-provider: octavia
        manage-security-groups: true
        max-shared-lb: 10
    controllerExtraArgs: |-
      - --use-service-account-credentials=false
    cluster:
      name: ${cluster_name}