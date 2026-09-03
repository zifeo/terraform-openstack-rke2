## template: jinja
#cloud-config

resize_rootfs: True
growpart:
  mode: auto
  devices:
    - /
  ignore_growroot_disabled: false
fs_setup:
  - label: rke2_data
    filesystem: ext4
    device: ${rke2_device}
# no mounts as managed by systemd

package_update: true
package_upgrade: true
# GPU nodes always reboot manually after driver install; do not let cloud-init auto-reboot and race that path. Non-GPU nodes keep the usual behavior.
package_reboot_if_required: !${gpu.enabled}
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
%{ if gpu.enabled && !gpu.driver.preinstalled }
  %{ if gpu.driver.version != null }
  - ${gpu.driver.package}=${gpu.driver.version}
  %{ else }
  - ${gpu.driver.package}
  %{ endif }
%{ endif }
%{ if gpu.enabled }
  %{ if gpu.toolkit_version != null }
  - ${gpu.toolkit_package}=${gpu.toolkit_version}
  %{ else }
  - ${gpu.toolkit_package}
  %{ endif }
%{ endif }

users:
  - default

ntp:
  enabled: true

%{ if gpu.enabled ~}
# Add NVIDIA container toolkit apt repo before package installs (bootcmd runs early).
bootcmd:
  - |
    set -e
    KEYRING=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    LIST=/etc/apt/sources.list.d/nvidia-container-toolkit.list
    if [ ! -f "$LIST" ]; then
      mkdir -p /usr/share/keyrings
      fetch() { curl -fsSL "$1" 2>/dev/null || wget -qO- "$1"; }
      fetch https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o "$KEYRING"
      fetch https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
        | sed "s#deb https://#deb [signed-by=$KEYRING] https://#g" > "$LIST"
    fi
%{ endif ~}

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
    What=/dev/disk/by-label/rke2_data
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
      curl -sfL https://get.rke2.io -o /tmp/rke2-install.sh && sh /tmp/rke2-install.sh || { echo "Failed to download or install rke2"; exit 1; }
    fi
- path: /usr/local/bin/cloud-init-wait.sh
  permissions: "0755"
  owner: root:root
  content: |
    #!/bin/bash
    wait_for() {
      _wf_desc="$1"; _wf_test="$2"; _wf_sleep="$3"; _wf_max="$4"; _wf_n=0
      until eval "$_wf_test"; do
        _wf_n=$((_wf_n + 1))
        if [ "$_wf_n" -ge "$_wf_max" ]; then
          echo "FATAL: $_wf_desc not ready after $_wf_max attempts on $(hostname) - node unusable, aborting cloud-init"
          exit 1
        fi
        echo "Waiting for $(hostname): $_wf_desc ($_wf_n/$_wf_max)"
        sleep "$_wf_sleep"
      done
    }
    _charts_ready() {
      _cr_miss=""
      for _cr_p in /opt/rke2/manifests/patches/*; do
        [ -e "$_cr_p" ] || continue
        [ -f "/var/lib/rancher/rke2/server/manifests/$(basename "$_cr_p")" ] || _cr_miss=1
      done
      [ -z "$_cr_miss" ]
    }
# Pre-set Node.spec.providerID at registration so the OpenStack CCM never sees an
# empty ProviderID when reconciling load-balancer security groups for a new node.
# `v1.instance_id` is the Nova instance UUID, rendered by cloud-init's jinja
- path: /etc/rancher/rke2/config.yaml.d/00-openstack-provider-id.yaml
  permissions: "0600"
  owner: root:root
  content: |
    kubelet-arg+:
      - "provider-id=openstack:///{{ v1.instance_id }}"
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
  encoding: gz+b64
  content: ${customize_chart_script}
- path: /usr/local/bin/customize-charts.sh
  permissions: "0755"
  owner: root:root
  encoding: gz+b64
  content: ${customize_charts_script}
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
    %{~ if s3.region != null ~}
    etcd-s3-region: "${s3.region}"
    %{~ endif ~}
      %{~ if backup_schedule != null ~}
    etcd-snapshot-schedule-cron: "${backup_schedule}"
      %{~ endif ~}
      %{~ if backup_retention != null ~}
    etcd-snapshot-retention: "${backup_retention}"
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
    disable:
      - rke2-ingress-nginx
      - rke2-traefik
    cni: "${cni}"
    node-taint:
      - "node-role.kubernetes.io/control-plane:NoSchedule"
    %{~ for t in node_taints ~}
      - "${t}"
    %{~ endfor ~}
    node-label:
      - "node.kubernetes.io/exclude-from-external-load-balancers=true"
    %{~ for k, v in node_labels ~}
      - "${k}=${v}"
    %{~ endfor ~}
    %{~ if rke2_conf != "" ~}
    ${ indent(4, rke2_conf) }
    %{~ endif ~}
%{~ else ~}
- path: /etc/rancher/rke2/config.yaml
  permissions: "0600"
  owner: root:root
  content: |
    token: "${rke2_token}"
    server: https://${internal_vip}:9345
    node-ip: "${node_ip}"
    cloud-provider-name: external
    %{~ if length(node_taints) > 0 ~}
    node-taint:
    %{~ for t in node_taints ~}
      - "${t}"
    %{~ endfor ~}
    %{~ endif ~}
    %{~ if length(node_labels) > 0 ~}
    node-label:
    %{~ for k, v in node_labels ~}
      - "${k}=${v}"
    %{~ endfor ~}
    %{~ endif ~}
    %{~ if rke2_conf != "" ~}
    ${ indent(4, rke2_conf) }
    %{~ endif ~}
%{~ endif ~}
%{~ if registries != null ~}
- path: /etc/rancher/rke2/registries.yaml
  permissions: "0600"
  owner: root:root
  content: |
    ${ indent(4, yamlencode(registries)) }
%{~ endif ~}
%{~ if gpu.enabled ~}
- path: /usr/local/bin/setup-gpu.sh
  permissions: "0755"
  owner: root:root
  content: |
    #!/bin/bash
    set -euo pipefail

    # RKE2 auto-registers nvidia when the runtime is on PATH; do not add
    # runtimes.nvidia via config.toml.tmpl (duplicates the key, containerd fails).
    mkdir -p /var/lib/rancher/rke2/agent/etc/containerd
    rm -f /var/lib/rancher/rke2/agent/etc/containerd/config.toml.tmpl \
          /var/lib/rancher/rke2/agent/etc/containerd/config-v3.toml.tmpl

    if [ -f /var/lib/gpu-setup-done ]; then
      echo "GPU setup already completed, skipping..."
      exit 0
    fi

    echo "=== Setting up NVIDIA GPU runtime ==="

    echo "Loading NVIDIA kernel modules..."
    # After a driver install + reboot, modules can take a moment to become available.
    NVIDIA_MODPROBE_OK=0
    for i in $(seq 1 30); do
      if modprobe nvidia; then
        NVIDIA_MODPROBE_OK=1
        break
      fi
      echo "Waiting for nvidia module ($i/30)..."
      sleep 2
    done
    if [ "$NVIDIA_MODPROBE_OK" -ne 1 ]; then
      echo "ERROR: failed to load nvidia kernel module"
      exit 1
    fi
    modprobe nvidia_uvm || true

    echo "Locating nvidia-container-runtime..."
    if ! command -v nvidia-container-runtime >/dev/null 2>&1; then
      echo "ERROR: nvidia-container-runtime not found; is ${gpu.toolkit_package} installed?"
      exit 1
    fi
    RUNTIME_BIN="$(command -v nvidia-container-runtime)"
    NVIDIA_BIN_DIR="$(dirname "$RUNTIME_BIN")"
    test -x "$RUNTIME_BIN"

    # nvidia-container-runtime must be on the rke2-agent service PATH; systemd does not expand $PATH, so set an absolute PATH that includes the toolkit.
    echo "Configuring rke2-agent PATH..."
    mkdir -p /etc/default
    DEFAULT_PATH="$NVIDIA_BIN_DIR:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    if [ -f /etc/default/rke2-agent ] && grep -qs "^PATH=" /etc/default/rke2-agent; then
      # Ensure toolkit dir is first on PATH without duplicating entries.
      sed -i "s|^PATH=.*|PATH=$DEFAULT_PATH|" /etc/default/rke2-agent
    else
      echo "PATH=$DEFAULT_PATH" >> /etc/default/rke2-agent
    fi

    touch /var/lib/gpu-setup-done
    echo "=== GPU setup complete ==="

- path: /etc/systemd/system/gpu-setup.service
  content: |
    [Unit]
    Description=NVIDIA GPU Runtime Setup
    Before=rke2-agent.service
    # Idempotency is handled inside setup-gpu.sh so this unit can still satisfy
    # Requires= on later boots (ConditionPathExists skips break Requires).

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=/usr/local/bin/setup-gpu.sh

    [Install]
    WantedBy=multi-user.target

- path: /etc/systemd/system/rke2-agent.service.d/gpu-setup.conf
  content: |
    [Unit]
    After=gpu-setup.service
    Requires=gpu-setup.service

%{ endif }

runcmd:
  - mkdir -p /mnt /var/lib/rancher/rke2 /var/lib/kubelet
  - systemctl daemon-reload
  - systemctl enable mnt.mount var-lib-rancher-rke2.mount var-lib-kubelet.mount
  - systemctl start mnt.mount var-lib-rancher-rke2.mount var-lib-kubelet.mount
  %{~ for key in authorized_keys ~}
  - grep -qxF "${key}" /home/${system_user}/.ssh/authorized_keys || echo "${key}" >> /home/${system_user}/.ssh/authorized_keys
  %{~ endfor ~}
  - /usr/local/bin/install-or-upgrade-rke2.sh
  - systemctl daemon-reload
  - grep -qxF 'alias crictl="sudo /var/lib/rancher/rke2/bin/crictl -r unix:///run/k3s/containerd/containerd.sock"' /home/${system_user}/.bashrc || echo 'alias crictl="sudo /var/lib/rancher/rke2/bin/crictl -r unix:///run/k3s/containerd/containerd.sock"' >> /home/${system_user}/.bashrc
  - grep -qxF 'alias ctr="sudo /var/lib/rancher/rke2/bin/ctr --address /run/k3s/containerd/containerd.sock --namespace k8s.io"' /home/${system_user}/.bashrc || echo 'alias ctr="sudo /var/lib/rancher/rke2/bin/ctr --address /run/k3s/containerd/containerd.sock --namespace k8s.io"' >> /home/${system_user}/.bashrc
  - bash -c 'source /usr/local/bin/cloud-init-wait.sh && wait_for "/mnt mountpoint" "mountpoint -q /mnt" 5 30'
  %{~ if is_server ~}
  - systemctl restart systemd-modules-load.service # ensure ipvs is loaded
  - grep -qxF 'alias kubectl="sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml"' /home/${system_user}/.bashrc || echo 'alias kubectl="sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml"' >> /home/${system_user}/.bashrc
  - if ! systemctl is-active -q rke2-server.service; then rm -rf /var/lib/rancher/rke2/server/manifests; fi # clear stale manifests only on a fresh/inactive node
  - >
    YQ_SHA256="bccbf5ce1717ea5cec9662446b8bfa5863747ffb0a49a32e4c8dd23ada5c26fa";
    for i in $(seq 1 10); do
      wget -T 30 https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64.tar.gz -O /tmp/yq_linux_amd64.tar.gz && echo "$YQ_SHA256  /tmp/yq_linux_amd64.tar.gz" | sha256sum -c - && tar xzf /tmp/yq_linux_amd64.tar.gz -C /tmp && mv /tmp/yq_linux_amd64 /usr/bin/yq && break;
      sleep 5;
    done;
    rm -f /tmp/yq_linux_amd64.tar.gz;
    command -v yq >/dev/null || { echo "ERROR: yq install/checksum failed"; exit 1; };
  - systemctl enable rke2-server.service
  - systemctl start rke2-server.service
  - bash -c 'source /usr/local/bin/cloud-init-wait.sh && wait_for "chart manifests" _charts_ready 1 60'
  - /usr/local/bin/customize-charts.sh /var/lib/rancher/rke2/server/manifests
  - >
    for f in /opt/rke2/manifests/*.yaml; do [ -e "$f" ] || continue; mv -v "$f" /var/lib/rancher/rke2/server/manifests; done;
  - ls /var/lib/rancher/rke2/server/manifests
  - bash -c 'source /usr/local/bin/cloud-init-wait.sh && wait_for "static pod manifests dir" "[ -d /var/lib/rancher/rke2/agent/pod-manifests/ ]" 1 60'
  - mv -v /opt/rke2/kube-vip.yaml /var/lib/rancher/rke2/agent/pod-manifests/kube-vip.yaml
  - ls /var/lib/rancher/rke2/agent/pod-manifests
  - bash -c 'source /usr/local/bin/cloud-init-wait.sh && wait_for "rke2-server active" "systemctl is-active -q rke2-server.service" 3 60'
  %{~ if bootstrap ~}
  - systemctl restart rke2-server.service # force deploy controller to re-read patched server/manifests (bootstrap only)
  - bash -c 'source /usr/local/bin/cloud-init-wait.sh && wait_for "rke2-server active after restart" "systemctl is-active -q rke2-server.service" 3 60'
  %{~ endif ~}
  %{~ else ~}
  - |
%{ if gpu.enabled }
    systemctl daemon-reload
    systemctl enable gpu-setup.service
%{ if !gpu.driver.preinstalled }
    # Always reboot once after driver install so the kernel module is available;
    if [ -f /var/lib/gpu-reboot-attempted ]; then
      if ! modprobe -q nvidia; then
        echo "FATAL: nvidia module still not loadable after reboot"
        exit 1
      fi
    else
      touch /var/lib/gpu-reboot-attempted
      systemctl enable rke2-agent.service
      echo "NVIDIA driver installed - rebooting; gpu-setup.service and rke2-agent.service start on next boot"
      reboot
      sleep 300
      exit 0
    fi
%{ endif }
    systemctl start gpu-setup.service
%{ endif }
    systemctl enable rke2-agent.service
    systemctl start rke2-agent.service
  - bash -c 'source /usr/local/bin/cloud-init-wait.sh && wait_for "rke2-agent active" "systemctl is-active -q rke2-agent.service" 5 120'
  %{~ endif ~}
