#cloud-config

resize_rootfs: True
growpart:
  mode: auto
  devices:
    - /
    - /mnt
fs_setup:
  - label: None
    filesystem: ext4
    device: ${rke2_device}
mounts:
  - ["${rke2_device}", "/mnt", "ext4", "defaults,nofail", "0", "2" ]
  - ["/mnt/rke2", "/var/lib/rancher/rke2", "none", "defaults,bind", "0", "0"]
  - ["/mnt/kubelet", "/var/lib/kubelet", "none", "defaults,bind", "0", "0"]

package_update: true
package_upgrade: true
package_reboot_if_required: true
packages:
  - fail2ban
  - unattended-upgrades
  - apt-listchanges
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
- path: /usr/local/bin/wait-for-node-ready.sh
  permissions: "0755"
  owner: root:root
  content: |
    #!/bin/sh
    until (curl -sL http://localhost:10248/healthz) && [ $(curl -sL http://localhost:10248/healthz) = "ok" ];
      do sleep 10 && echo "Waiting for $(hostname) kubelet to be ready"; done;
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
- path: /opt/manifests/${k}
  permissions: "0600"
  owner: root:root
  encoding: gz+b64
  content: ${v}
    %{~ endfor ~}
  %{~ endif ~}
- path: /etc/rancher/rke2/config.yaml
  permissions: "0600"
  owner: root:root
  content: |
    token: "${rke2_token}"
    %{~ if !bootstrap ~}
    server: https://${bootstrap_ip}:9345
    %{~ endif ~}
    node-ip: ${node_ip}
    cloud-provider-name: external
    advertise-address: ${node_ip}
    write-kubeconfig-mode: "0640"
    tls-san:
      ${ indent(6, yamlencode(san)) }
    kube-apiserver-arg: "kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname"
    %{~ if s3_endpoint != "" ~}
    etcd-s3: true
    etcd-s3-endpoint: ${s3_endpoint}
    etcd-s3-access-key: ${s3_access_key}
    etcd-s3-secret-key: ${s3_access_secret}
    etcd-s3-bucket: ${s3_bucket}
    etcd-snapshot-compress: true
    %{~ endif ~}
    disable-cloud-controller: true
    disable: rke2-ingress-nginx
    disable-kube-proxy: true
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
    server: https://${bootstrap_ip}:9345
    node-ip: ${node_ip}
    cloud-provider-name: external
    ${indent(4,rke2_conf)}
%{~ endif ~}

runcmd:
  %{~ for key in authorized_keys ~}
  - echo "${key}" >> /home/${system_user}/.ssh/authorized_keys
  %{~ endfor ~}
  - /usr/local/bin/install-or-upgrade-rke2.sh
  - echo 'alias crictl="sudo /var/lib/rancher/rke2/bin/crictl -r unix:///run/k3s/containerd/containerd.sock"' >> /home/${system_user}/.bashrc
  %{~ if is_server ~}
  - echo 'alias kubectl="sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml"' >> /home/${system_user}/.bashrc
  - rm -rf /var/lib/rancher/rke2/server/manifests
  - systemctl enable rke2-server.service
  - systemctl start rke2-server.service
  - [ sh, -c, 'until [ -f /etc/rancher/rke2/rke2.yaml ]; do echo Waiting for $(hostname) rke2 to start && sleep 10; done;' ]
  - [ sh, -c, 'until [ -x /var/lib/rancher/rke2/bin/kubectl ]; do echo Waiting for $(hostname) kubectl bin && sleep 10; done;' ]
  - mv -v /opt/manifests/* /var/lib/rancher/rke2/server/manifests || echo "No manifest files"
  - ls /var/lib/rancher/rke2/server/manifests
  %{~ else ~}
  - systemctl enable rke2-agent.service
  - systemctl start rke2-agent.service
  - [ sh, -c, 'until systemctl is-active -q rke2-agent.service; do echo Waiting for $(hostname) rke2 to start && sleep 10; done;' ]
  %{~ endif ~}
