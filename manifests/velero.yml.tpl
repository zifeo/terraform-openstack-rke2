apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: velero
  namespace: kube-system
spec:
  chart: velero
  repo: https://vmware-tanzu.github.io/helm-charts
  version: 2.32.4
  targetNamespace: kube-system
  valuesContent: |-
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
        memory: 256Mi

    configuration:
      provider: mixed

      backupStorageLocation:
        provider: community.openstack.org/openstack
        bucket: ${bucket_velero}
        config:
          cloud: self
          region: ${region}
          resticRepoPrefix: swift:${bucket_restic}:/restic
          
      volumeSnapshotLocation:
        provider: csi

      features: EnableCSI

    credentials:
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

    restic:
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          memory: 256Mi
