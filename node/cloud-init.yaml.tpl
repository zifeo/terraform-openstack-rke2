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
    After=local-fs-pre.target
    Before=local-fs.target
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
      curl -sfL https://get.rke2.io | sh -
    fi
%{ if is_server ~}
    %{~ for k, v in manifests_files ~}
- path: /opt/rke2/manifests/${k}
  permissions: "0600"
  owner: root:root
  encoding: gz+b64
  content: ${v}
    %{~ endfor ~}
- path: /usr/local/bin/customize-chart.sh
  permissions: "0755"
  owner: root:root
  content: |
    #!/bin/bash
    CHART_FILE=$1
    CHART_NAME=$(basename $CHART_FILE .yaml)
    DELTA=$2
    TAR_FILE=chart.tar
    FILE=values.yaml
    TAR_OPTS="--owner=0 --group=0 --mode=gou-s+r --numeric-owner --no-acls --no-selinux --no-xattrs"
    echo "Customizing $CHART_FILE with $DELTA"
    cat $CHART_FILE | yq -r .spec.chartContent | base64 -d | gunzip - > $TAR_FILE
    tar -xOf $TAR_FILE $CHART_NAME/$FILE > $FILE
    yq -i e '. *= load("'$DELTA'")' $FILE
    tar --delete -b 8192 -f $TAR_FILE $CHART_NAME/$FILE
    tar --transform="s|.*|$CHART_NAME/$FILE|" $TAR_OPTS -vrf $TAR_FILE $FILE
    gzip -9 $TAR_FILE
    cat $TAR_FILE.gz | base64 -w 0 > $TAR_FILE.gz.b64
    yq -i e '.spec.chartContent = load_str("'$TAR_FILE'.gz.b64")' $CHART_FILE
    rm $TAR_FILE.gz $TAR_FILE.gz.b64 $FILE
- path: /usr/local/bin/customize-charts.sh
  permissions: "0755"
  owner: root:root
  content: |
    #!/bin/bash
    CHARTS_DIR=$1
    ls $CHARTS_DIR
    for patch in /opt/rke2/manifests/patches/*; do
      patch_name=$(basename "$patch")
      if [ -f "$CHARTS_DIR/$patch_name" ] && [ "$(yq e 'length' "$CHARTS_DIR/$patch_name")" -ne "0" ]; then
        /usr/local/bin/customize-chart.sh "$CHARTS_DIR/$patch_name" "$patch"
      fi
    done
- path: /etc/modules-load.d/ipvs.conf
  permissions: "0644"
  owner: root:root
  content: |
    # loads kernel modules for kube-vip
    ip_vs
    ip_vs_rr
- path: /opt/rke2/kube-vip.yaml
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
        image: ghcr.io/kube-vip/kube-vip:v0.7.2
        imagePullPolicy: IfNotPresent
        args:
        - manager
        env:
        - name: vip_arp
          value: "true"
        - name: port
          value: "6443"
        - name: vip_interface
          value: "${vip_interface}"
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
          value: "5"
        - name: vip_renewdeadline
          value: "3"
        - name: vip_retryperiod
          value: "1"
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
            cpu: 25m
            memory: 32Mi
          limits:
            memory: 32Mi
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
    cluster-cidr: "${cluster_cidr}"
    service-cidr: "${service_cidr}"
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
    disable-kube-proxy: ${ff_with_kubeproxy ? "false" : "true"}
    disable: rke2-ingress-nginx
    cni: "${cni}"
    node-taint:
      - CriticalAddonsOnly=true:NoExecute  
  %{ for k, v in node_taints ~}
    - "${k}=${v}"
  %{ endfor ~}  
  node-label:
      - node.kubernetes.io/exclude-from-external-load-balancers=true
  %{ for k, v in node_labels ~}
    - ${k}=${v}
  %{ endfor ~}
%{~ else ~}
- path: /etc/rancher/rke2/config.yaml
  permissions: "0600"
  owner: root:root
  content: |
    token: "${rke2_token}"
    server: https://${internal_vip}:9345
    node-ip: ${node_ip}
    cloud-provider-name: external
    %{~ if length(node_taints) > 0 ~}
    node-taint:
      %{ for k, v in node_taints ~}
      - "${k}=${v}"
      %{ endfor ~}
    %{~ endif ~}
    %{~ if length(node_labels) > 0 ~}
    node-label:
      %{ for k, v in node_labels ~}
      - "${k}=${v}"
      %{ endfor ~}
    %{~ endif ~}
%{~ endif ~}
%{ if registries != null }
- path: /etc/rancher/rke2/registries.yaml
  permissions: "0600"
  owner: root:root
  content: |
    ${ indent(4, yamlencode(registries)) }
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
  - >
    for MNT in /mnt; do
      RETRIES=0; MAX_RETRIES=30;
      until mountpoint -q "$MNT"; do
        RETRIES=$((RETRIES + 1));
        if [ $RETRIES -ge $MAX_RETRIES ]; then
          echo "ERROR: $MNT not mounted after $MAX_RETRIES retries.";
          exit 1;
        fi;
        echo "$MNT not mounted yet, retrying in 10 seconds...";
        sleep 5;
      done;
      echo "$MNT mounted successfully.";
    done;
  %{~ if is_server ~}
  - systemctl restart systemd-modules-load.service # ensure ipvs is loaded
  - echo 'alias kubectl="sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml"' >> /home/${system_user}/.bashrc
  - rm -rf /var/lib/rancher/rke2/server/manifests # single-node cleanup
  - systemctl enable rke2-server.service
  - systemctl start rke2-server.service
  - until [ -d /var/lib/rancher/rke2/agent/pod-manifests/ ]; do echo "Waiting for $(hostname) static pods"; sleep 1; done
  - mv -v /opt/rke2/kube-vip.yaml /var/lib/rancher/rke2/agent/pod-manifests/kube-vip.yaml
  - ls /var/lib/rancher/rke2/agent/pod-manifests
  - wget https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64.tar.gz -O - | tar xz && mv yq_linux_amd64 /usr/bin/yq
  - until [ -d /var/lib/rancher/rke2/data/v*/charts ]; do echo "Waiting for $(hostname) charts data"; sleep 1; done
  - /usr/local/bin/customize-charts.sh $(realpath /var/lib/rancher/rke2/data/v*/charts)
  - until [ -d /var/lib/rancher/rke2/server/manifests ]; do echo "Waiting for $(hostname) manifests"; sleep 1; done
  - /usr/local/bin/customize-charts.sh /var/lib/rancher/rke2/server/manifests
  - mv -v /opt/rke2/manifests/*.yaml /var/lib/rancher/rke2/server/manifests
  - ls /var/lib/rancher/rke2/server/manifests
  - until systemctl is-active -q rke2-server.service; do echo "Waiting for $(hostname) rke2 to start"; sleep 3; journalctl -u rke2-server.service --since "3 second ago"; done
  %{~ else ~}
  - systemctl enable rke2-agent.service
  - systemctl start rke2-agent.service
  - until systemctl is-active -q rke2-agent.service; do echo "Waiting for $(hostname) rke2 to start"; sleep 3; journalctl -u rke2-agent.service --since "3 second ago"; done
  %{~ endif ~}
