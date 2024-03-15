apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: velero
  namespace: kube-system
spec:
  chart: velero
  repo: https://vmware-tanzu.github.io/helm-charts
  version: 2.32.6 # 3.1.0
  targetNamespace: velero
  valuesContent: |-
    image:
      repository: velero/velero
      tag: v1.9.4
      pullPolicy: IfNotPresent
    initContainers:
      - name: velero-plugin-for-openstack
        image: lirt/velero-plugin-for-openstack:v0.4.1
        imagePullPolicy: IfNotPresent
        volumeMounts:
          - mountPath: /target
            name: plugins
      - name: velero-plugin-for-csi
        image: velero/velero-plugin-for-csi:v0.4.0
        imagePullPolicy: IfNotPresent
        volumeMounts:
          - mountPath: /target
            name: plugins
    nodeSelector:
      node-role.kubernetes.io/master: "true"
    tolerations:
      - effect: NoExecute
        key: CriticalAddonsOnly
        operator: "Exists"
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: null
        memory: null
    kubectl:
      image:
        repository: docker.io/bitnami/kubectl
        tag: "1.29-debian-11"
    configuration:
      provider: mixed
      namespace: velero
      features: EnableCSI
      defaultBackupTTL: 72h
      defaultResticPruneFrequency: 72h
      backupStorageLocation:
        name: default
        provider: community.openstack.org/openstack
        bucket: ${bucket_velero}
        config:
          cloud: self
          region: ${region}
          resticRepoPrefix: swift:${bucket_restic}:/restic     
      volumeSnapshotLocation:
        name: default
        provider: csi
      extraEnvVars:
        # for restic (no support for clouds.yaml, https://restic.readthedocs.io/en/latest/030_preparing_a_new_repo.html#openstack-swift)
        OS_AUTH_URL: ${auth_url}/v3
        OS_APPLICATION_CREDENTIAL_ID: ${app_id}
        OS_APPLICATION_CREDENTIAL_NAME: ${app_name}
        OS_APPLICATION_CREDENTIAL_SECRET: ${app_secret}
        # for community.openstack.org/openstack (env vars do not work and take precedence over clouds.yaml unless cloud set)
        OS_CLOUD: self
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

    deployRestic: true
    # will be replace by 
    # deployNodeAgent: true
    # nodeAgent:
    restic:
      podVolumePath: /var/lib/kubelet/pods
      privileged: false
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: null
          memory: null
