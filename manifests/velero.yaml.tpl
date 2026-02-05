apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: velero
  namespace: kube-system
spec:
  chart: velero
  repo: https://vmware-tanzu.github.io/helm-charts
  version: 11.3.2
  targetNamespace: velero
  valuesContent: |-
    image:
      repository: docker.io/velero/velero
      tag: v1.17.1
      pullPolicy: IfNotPresent
    initContainers:
      - name: velero-plugin-for-openstack
        image: docker.io/lirt/velero-plugin-for-openstack:v0.8.0
        imagePullPolicy: IfNotPresent
        volumeMounts:
          - mountPath: /target
            name: plugins
    tolerations:
      - key: node-role.kubernetes.io/control-plane
        effect: NoSchedule
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        memory: 256Mi
    kubectl:
      image:
        repository: docker.io/bitnamilegacy/kubectl
        tag: "1.29-debian-11"
    configuration:
      namespace: velero
      features: EnableCSI
      defaultBackupTTL: 72h
      backupStorageLocation:
        - name: default
          provider: community.openstack.org/openstack
          bucket: ${bucket_velero}
          config:
            cloud: self
            region: ${region}
      volumeSnapshotLocation:
        - name: default
          provider: csi
      extraEnvVars:
        - name: OS_AUTH_URL
          value: "${auth_url}/v3"
        - name: OS_APPLICATION_CREDENTIAL_ID
          value: "${app_id}"
        - name: OS_APPLICATION_CREDENTIAL_NAME
          value: "${app_name}"
        - name: OS_APPLICATION_CREDENTIAL_SECRET
          value: "${app_secret}"
        - name: OS_CLOUD
          value: self
    credentials:
      # for community.openstack.org/openstack
      secretContents:
        clouds.yaml: |
          clouds:
            self:
              region_name: ${region}
              auth:
                auth_url: ${auth_url}/v3
                application_credential_id: ${app_id}
                application_credential_name: ${app_name}
                application_credential_secret: ${app_secret}
    extraVolumes:
      - name: cloud-config-velero
        secret:
          secretName: velero
          items:
          - key: clouds.yaml
            path: clouds.yaml
    extraVolumeMounts:
      - name: cloud-config-velero
        mountPath: /etc/openstack/clouds.yaml
        readOnly: true
        subPath: clouds.yaml
    backupsEnabled: true
    snapshotsEnabled: true
    deployNodeAgent: true
    nodeAgent:
      podVolumePath: /var/lib/kubelet/pods
      containerSecurityContext:
        privileged: false
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          memory: 256Mi
