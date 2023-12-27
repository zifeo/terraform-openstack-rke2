#cloud-config

resize_rootfs: True
growpart:
  mode: auto
  devices:
    - /
    - ${rke2_device}
  ignore_growroot_disabled: false
fs_setup:
  - label: None
    filesystem: ext4
    device: ${rke2_device}
# no mounts as managed by systemd

package_update: true
package_upgrade: true
package_reboot_if_required: true
packages:
  - fail2ban
  - unattended-upgrades
  - apt-listchanges
  - apt-transport-https
  - ncdu
  - htop
  - curl
  - jq
  - logrotate
  - nfs-client
  - fio

users:
  - default

ntp:
  enabled: true

write_files:
- path: /etc/logrotate.conf
  append: true
  permissions: "0644"
  owner: root:root
  content: | 
    maxsize 500M
- path: /etc/systemd/system/mnt.mount
  content: |
    [Unit]
    After=local-fs.target
    [Mount]
    What=${rke2_device}
    Where=/mnt
    Type=ext4
    Options=defaults
    [Install]
    WantedBy=multi-user.target
- path: /etc/systemd/system/var-lib-rancher-rke2.mount
  content: |
    [Unit]
    Requires=mnt.mount
    After=mnt.mount
    [Mount]
    What=/mnt/rke2
    Where=/var/lib/rancher/rke2
    Type=none
    Options=bind
    [Install]
    WantedBy=multi-user.target
- path: /etc/systemd/system/var-lib-kubelet.mount
  content: |
    [Unit]
    Requires=mnt.mount
    After=mnt.mount
    [Mount]
    What=/mnt/kubelet
    Where=/var/lib/kubelet
    Type=none
    Options=bind
    [Install]
    WantedBy=multi-user.target
- path: /usr/local/bin/install-or-upgrade-rke2.sh
  permissions: "0755"
  owner: root:root
  content: |
    #!/bin/sh
    export INSTALL_RKE2_VERSION=${rke2_version}
    which rke2 >/dev/null 2>&1 && RKE2_VERSION=$(rke2 --version | head -1 | cut -f 3 -d " ")
    if ([ -z "$RKE2_VERSION" ]) || ([ -n "$INSTALL_RKE2_VERSION" ] && [ "$INSTALL_RKE2_VERSION" != "$RKE2_VERSION" ]); then
      RKE2_ROLE=$(curl -s http://169.254.169.254/openstack/2012-08-10/meta_data.json | jq -r '.meta.rke2_role')
      RKE2_SERVICE="rke2-$RKE2_ROLE.service"
      echo "Installing RKE2 $INSTALL_RKE2_VERSION with $RKE2_ROLE role"
      curl -sfL https://get.rke2.io | sh -
    fi
%{ if is_server ~}
  %{~ if is_first ~}
    %{~ for k, v in manifests_files ~}
- path: /opt/rke2/manifests/${k}
  permissions: "0600"
  owner: root:root
  encoding: gz+b64
  content: ${v}
    %{~ endfor ~}
  %{~ endif ~}
- path: /etc/modules-load.d/ipvs.conf
  permissions: "0644"
  owner: root:root
  content: |
    # loads kernel modules for kube-vip
    ip_vs
    ip_vs_rr
- path: /opt/rke2/kube-vip.yml
  permissions: "0600"
  owner: root:root
  content: |
    apiVersion: v1
    kind: Pod
    metadata:
      name: kube-vip
      namespace: kube-system
    spec:
      containers:
      - name: kube-vip
        image: ghcr.io/kube-vip/kube-vip:v0.6.4
        imagePullPolicy: IfNotPresent
        args:
        - manager
        env:
        - name: vip_arp
          value: "true"
        - name: port
          value: "6443"
        - name: vip_interface
          value: ens3
        - name: vip_cidr
          value: "32"
        - name: cp_enable
          value: "true"
        - name: cp_namespace
          value: kube-system
        - name: vip_ddns
          value: "false"
        - name: svc_enable
          value: "false"
        - name: vip_leaderelection
          value: "true"
        - name: vip_leasename
          value: plndr-cp-lock
        - name: vip_leaseduration
          value: "15"
        - name: vip_renewdeadline
          value: "10"
        - name: vip_retryperiod
          value: "2"
        - name: enable_node_labeling
          value: "true"
        - name: lb_enable
          value: "true"
        - name: lb_port
          value: "6443"
        - name: lb_fwdmethod
          value: local
        - name: address
          value: "${internal_vip}"
        - name: prometheus_server
          value: ":2112"
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            memory: 64Mi
        securityContext:
          capabilities:
            add:
            - NET_ADMIN
            - NET_RAW
        volumeMounts:
        - mountPath: /etc/kubernetes/admin.conf
          name: kubeconfig
      restartPolicy: Always
      hostAliases:
      - hostnames:
        - kubernetes
        ip: 127.0.0.1
      hostNetwork: true
      volumes:
      - name: kubeconfig
        hostPath:
          path: /etc/rancher/rke2/rke2.yaml
- path: /etc/rancher/rke2/config.yaml
  permissions: "0600"
  owner: root:root
  content: |
    token: "${rke2_token}"
    %{~ if !bootstrap ~}
    server: "https://${internal_vip}:9345"
    %{~ endif ~}
    node-ip: "${node_ip}"
    cloud-provider-name: external
    advertise-address: "${node_ip}"
    write-kubeconfig-mode: "0640"
    tls-san:
      ${ indent(6, yamlencode(san)) }
    kube-apiserver-arg: "kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname"
    %{~ if s3.endpoint != "" ~}
    etcd-s3: true
    etcd-s3-endpoint: "${s3.endpoint}"
    etcd-s3-access-key: "${s3.access_key}"
    etcd-s3-secret-key: "${s3.access_secret}"
    etcd-s3-bucket: "${s3.bucket}"
      %{~ if backup_schedule != null ~}
    etcd-snapshot-schedule-cron: ${backup_schedule}
      %{~ endif ~}
      %{~ if backup_retention != null ~}
    etcd-snapshot-retention: ${backup_retention}
      %{~ endif ~}
    etcd-snapshot-compress: true
    %{~ endif ~}
    %{~ if control_plane_requests != "" ~}
    control-plane-resource-requests: "${control_plane_requests}"
    %{~ endif ~}
    %{~ if control_plane_limits != "" ~}
    control-plane-resource-limits: "${control_plane_limits}"
    %{~ endif ~}
    disable-cloud-controller: true
    disable-kube-proxy: true
    disable: rke2-ingress-nginx
    cni: cilium
    node-label:
      - node.kubernetes.io/exclude-from-external-load-balancers=true
    node-taint:
      - CriticalAddonsOnly=true:NoExecute
    ${indent(4,rke2_conf)}
%{~ else ~}
- path: /etc/rancher/rke2/config.yaml
  permissions: "0600"
  owner: root:root
  content: |
    token: "${rke2_token}"
    server: https://${internal_vip}:9345
    node-ip: ${node_ip}
    cloud-provider-name: external
    ${indent(4,rke2_conf)}
%{~ endif ~}

runcmd:
  - mkdir -p /mnt /var/lib/rancher/rke2 /var/lib/kubelet
  - systemctl daemon-reload
  - systemctl enable mnt.mount var-lib-rancher-rke2.mount var-lib-kubelet.mount
  - systemctl start mnt.mount var-lib-rancher-rke2.mount var-lib-kubelet.mount
  %{~ for key in authorized_keys ~}
  - echo "${key}" >> /home/${system_user}/.ssh/authorized_keys
  %{~ endfor ~}
  - /usr/local/bin/install-or-upgrade-rke2.sh
  - echo 'alias crictl="sudo /var/lib/rancher/rke2/bin/crictl -r unix:///run/k3s/containerd/containerd.sock"' >> /home/${system_user}/.bashrc
  - echo 'alias ctr="sudo /var/lib/rancher/rke2/bin/ctr --address /run/k3s/containerd/containerd.sock --namespace k8s.io"' >> /home/${system_user}/.bashrc
  %{~ if is_server ~}
  - systemctl restart systemd-modules-load.service
  - echo 'alias kubectl="sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml"' >> /home/${system_user}/.bashrc
  - rm -rf /var/lib/rancher/rke2/server/manifests # single-node cleanup
  - systemctl enable rke2-server.service
  - systemctl start rke2-server.service
  - [ sh, -c, 'until [ -d /var/lib/rancher/rke2/agent/pod-manifests/ ]; do echo Waiting for $(hostname) static pods && sleep 5; done;' ]
  - mv -v /opt/rke2/kube-vip.yml /var/lib/rancher/rke2/agent/pod-manifests/kube-vip.yml
  - ls /var/lib/rancher/rke2/agent/pod-manifests
  - mv -v /opt/rke2/manifests/* /var/lib/rancher/rke2/server/manifests || echo "No manifest files"
  - ls /var/lib/rancher/rke2/server/manifests
  - [ sh, -c, 'until systemctl is-active -q rke2-server.service; do echo Waiting for $(hostname) rke2 to start && sleep 10; done;' ]
  %{~ else ~}
  - systemctl enable rke2-agent.service
  - systemctl start rke2-agent.service
  - [ sh, -c, 'until systemctl is-active -q rke2-agent.service; do echo Waiting for $(hostname) rke2 to start && sleep 10; done;' ]
  %{~ endif ~}
