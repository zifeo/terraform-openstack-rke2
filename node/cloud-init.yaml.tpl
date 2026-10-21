#cloud-config
# rke2's secrets ${secrets_sha256}: pushed by tofu, read by rke2 when it starts, so a change replaces the node

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

# the host key tofu pins before it pushes the node's secrets over SSH
ssh_deletekeys: true
# the one type tofu provides: cloud-init generates only those it lacks
ssh_genkeytypes: [ed25519]
ssh_keys:
  ed25519_private: |
    ${indent(4, host_key.private)}
  ed25519_public: ${host_key.public}

%{ if !image_prebuilt ~}
package_update: true
package_upgrade: true
# GPU nodes always reboot manually after driver install; do not let cloud-init auto-reboot and race that path. Non-GPU nodes keep the usual behavior.
package_reboot_if_required: ${!gpu.enabled}
%{ endif ~}
%{ if !image_prebuilt || gpu.enabled ~}
packages:
%{ endif ~}
%{ if !image_prebuilt ~}
  - fail2ban
  - unattended-upgrades
  - apt-listchanges
  - ncdu
  - htop
  - curl
  - logrotate
  - nfs-common
  - fio
%{ endif ~}
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
%{ if !is_server ~}
# Cinder CSI's node plugin reads it from the node (hostMount); a server's, with the controller's credentials, comes
# from tofu over SSH
- path: /etc/config/cloud.conf
  permissions: "0644"
  owner: root:root
  content: |
    ${indent(4, cinder_node)}
%{ endif ~}
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
- path: /etc/systemd/system/rke2-${is_server ? "server" : "agent"}.service.d/mounts.conf
  content: |
    # on reboot nothing orders rke2 after mnt.mount: without this rke2 may write to the root disk, later hidden by the mount
    [Unit]
    RequiresMountsFor=/var/lib/rancher/rke2 /var/lib/kubelet
- path: /etc/systemd/system/rke2-${is_server ? "server" : "agent"}.service.d/metadata-guard.conf
  content: |
    # on reboot too: no pod runs before the guard, nor without it should its rules fail to load
    [Unit]
    Requires=rke2-metadata-guard.service
    After=rke2-metadata-guard.service
- path: /usr/local/bin/install-or-upgrade-rke2.sh
  permissions: "0755"
  owner: root:root
  content: |
    #!/bin/sh
    export INSTALL_RKE2_VERSION=${rke2_version}
    which rke2 >/dev/null 2>&1 && RKE2_VERSION=$(rke2 --version | head -1 | cut -f 3 -d " ")
    if ([ -z "$RKE2_VERSION" ]) || ([ -n "$INSTALL_RKE2_VERSION" ] && [ "$INSTALL_RKE2_VERSION" != "$RKE2_VERSION" ]); then
      # the installer of the release it installs, not get.rke2.io's, which follows rke2's main branch. Its own curl has no
      # timeout: a stalled download would hold the node for good, so the release is fetched here, a transfer under
      # 1 KB/s for 60 s retried, and the installer checks it against the release's sha256sum
      arch=$(dpkg --print-architecture)
      release=https://github.com/rancher/rke2/releases/download/${replace(rke2_version, "+", "%2B")}
      fetch() { curl -fsSL --retry 5 --retry-all-errors --connect-timeout 10 --speed-limit 1024 --speed-time 60 -o "$1" "$2"; }
      mkdir -p /tmp/rke2-artifacts &&
        fetch /tmp/rke2-install.sh "https://raw.githubusercontent.com/rancher/rke2/${replace(rke2_version, "+", "%2B")}/install.sh" &&
        fetch "/tmp/rke2-artifacts/sha256sum-$arch.txt" "$release/sha256sum-$arch.txt" &&
        fetch "/tmp/rke2-artifacts/rke2.linux-$arch.tar.gz" "$release/rke2.linux-$arch.tar.gz" &&
        INSTALL_RKE2_ARTIFACT_PATH=/tmp/rke2-artifacts sh /tmp/rke2-install.sh || { echo "Failed to download or install rke2"; exit 1; }
    fi
# rke2 turns graceful node shutdown off: without it, a server's kube-apiserver holds every reboot for the time systemd
# gives a container to stop. Installed into kubelet.conf.d, on the rke2 volume, once it is mounted.
- path: /opt/rke2/kubelet/50-graceful-shutdown.conf
  permissions: "0600"
  owner: root:root
  content: |
%{ if kubelet_config == null ~}
    apiVersion: kubelet.config.k8s.io/v1beta1
    kind: KubeletConfiguration
    shutdownGracePeriod: 30s
    shutdownGracePeriodCriticalPods: 10s
%{ else ~}
    ${indent(4, kubelet_config)}
%{ endif ~}
%{ if length(runtime_classes) > 0 ~}
# handlers of the pool's RuntimeClasses, whose runtimes come with the image; rke2 imports config-v3.toml.d into the
# containerd config it generates on every start. Installed on the rke2 volume once it is mounted.
- path: /opt/rke2/containerd/runtime-classes.toml
  permissions: "0600"
  owner: root:root
  content: |
    version = 3
%{ for rc in runtime_classes ~}

    [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.${rc.handler}]
      runtime_type = ${jsonencode(rc.runtime_type)}
%{ if length(rc.options) > 0 ~}

    [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.${rc.handler}.options]
%{ for k, v in rc.options ~}
      ${k} = ${jsonencode(v)}
%{ endfor ~}
%{ endif ~}
%{ endfor ~}
%{ endif ~}
- path: /usr/local/bin/cloud-init-wait.sh
  permissions: "0755"
  owner: root:root
  content: |
    #!/bin/bash
    # sleep, then attempts: tofu gives up on a node after 10 minutes, cloud-init then says what it waited for
    wait_for() {
      _wf_desc="$1"; _wf_test="$2"; _wf_sleep="$3"; _wf_max="$4"; _wf_n=0
      until eval "$_wf_test"; do
        _wf_n=$((_wf_n + 1))
        if [ "$_wf_max" -gt 0 ] && [ "$_wf_n" -ge "$_wf_max" ]; then
          echo "FATAL: $_wf_desc not ready after $_wf_max attempts on $(hostname) - node unusable, aborting cloud-init"
          exit 1
        fi
        echo "Waiting for $(hostname): $_wf_desc ($_wf_n/$_wf_max)"
        sleep "$_wf_sleep"
      done
    }
    # rke2 links bin and writes .extracted only once the current runtime is fully extracted
    _rke2_data_dir() {
      _rd=$(dirname "$(readlink -f /var/lib/rancher/rke2/bin)") && [ -f "$_rd/.extracted" ] && echo "$_rd"
    }
    _charts_ready() {
      [ -d "$1" ] || return 1
      _cr_miss=""
      for _cr_p in /opt/rke2/manifests/patches/*; do
        [ -e "$_cr_p" ] || continue
        [ -f "$1/$(basename "$_cr_p")" ] || _cr_miss=1
      done
      [ -z "$_cr_miss" ]
    }
    _data_charts_ready() { _dcr=$(_rke2_data_dir) && _charts_ready "$_dcr/charts"; }
%{ if is_server ~}
# rke2 starts only once etcd's and kube-apiserver's pod sandboxes are its manifests', polling every 20 s and removing
# any other it finds (pkg/executor/staticpod/spw.go): those of the previous boot cost a server 40 to 60 s per reboot.
# Ordered after rke2, it stops before it, once the kubelet's graceful shutdown stopped the pods and while containerd runs
- path: /etc/systemd/system/rke2-static-pods-cleanup.service
  permissions: "0644"
  owner: root:root
  content: |
    [Unit]
    Description=Removes etcd's and kube-apiserver's pod sandboxes at shutdown
    After=rke2-server.service

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=/bin/true
    ExecStop=/bin/sh -c 'c="/var/lib/rancher/rke2/bin/crictl -r unix:///run/k3s/containerd/containerd.sock"; for p in $($c pods -q --label component=etcd) $($c pods -q --label component=kube-apiserver); do $c stopp "$p" && $c rmp "$p"; done'

    [Install]
    WantedBy=multi-user.target
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
- path: /etc/modules-load.d/kube-vip.conf
  content: |
    ip_vs
    ip_vs_rr
- path: /etc/sysctl.d/90-kube-vip.conf
  content: |
    # set before kube-vip starts, as it cannot write /proc/sys: its masquerade needs it. Forwarding, rke2 turns on
    net.ipv4.vs.conntrack = 1
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
      # as rke2's control plane pods: at priority 0, the scheduler preempts its mirror pod for any critical pod short of
      # memory, the kubelet recreates it at once and rejects that pod, over and over
      priorityClassName: system-cluster-critical
      containers:
      - name: kube-vip
        # the iptables variant: masquerade adds its rule with the iptables binary, which the plain image lacks
        image: ghcr.io/kube-vip/kube-vip-iptables:v1.3.0@sha256:23477ad40d2c411236eac50088cd92fe9f289ae01433da18f695da3282d00ff1
        imagePullPolicy: IfNotPresent
        args:
        - manager
        env:
        - name: vip_arp
          value: "true"
        - name: port
          value: "6443"
        - name: vip_subnet
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
        # IPVS spreads the VIP's API connections over every server. lb_fwdmethod local sent them all to the holder's
        # own kube-apiserver; masquerade forwards them, with conntrack following them (90-kube-vip.conf), else UFW
        # drops the client's FIN as invalid and a client reusing the port meets the stale IPVS entry
        - name: lb_enable
          value: "true"
        - name: lb_port
          value: "6443"
        - name: lb_fwdmethod
          value: masquerade
        # its default nftables path makes the nat table's POSTROUTING a filter chain, adds no masquerade there and
        # leaves no room for Cilium's
        - name: egress_withnftables
          value: "false"
        - name: address
          value: "${internal_vip}"
        - name: prometheus_server
          value: ":2112"
        - name: k8s_config_file
          value: /etc/kubernetes/admin.conf
        resources:
          requests:
            cpu: 25m
            memory: 64Mi
          limits:
            memory: 128Mi
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
          type: File
%{ if is_first ~}
# the first server starting the cluster alone holds the VIP, as no server answers on it yet: the floating IP, on the
# VIP from the start, reaches it for tofu's secrets push. Released before rke2 starts kube-vip, which takes it over
- path: /usr/local/bin/rke2-vip-claim
  permissions: "0755"
  owner: root:root
  content: |
    #!/bin/bash
    set -euo pipefail
    vip=${internal_vip}
    dev=$(ip -o -4 addr show | awk -v ip=${node_ip} '{ split($4, a, "/") } a[1] == ip { print $2; exit }')
    [ -n "$dev" ] || { echo "rke2-vip-claim: no interface holds ${node_ip}" >&2; exit 1; }
    case "$1" in
      claim)
        # only a server that starts the cluster alone, as its instance metadata says on the config drive (bootstrap, or
        # a single server): a first server replaced later joins a cluster whose kube-vip holds the VIP
        bootstrap=$(cloud-init query ds.meta_data.meta.rke2_bootstrap) || {
          echo "rke2-vip-claim: no rke2_bootstrap in the instance metadata" >&2
          exit 1
        }
        case "$bootstrap" in
          true) ;;
          false) echo "rke2-vip-claim: this server joins a cluster, whose kube-vip holds $vip"; exit 0 ;;
          *) echo "rke2-vip-claim: rke2_bootstrap is $bootstrap" >&2; exit 1 ;;
        esac
        # a connection makes the kernel ask who has the VIP: a server holding it answers, whatever its firewall
        timeout 5 bash -c "exec 3<>/dev/tcp/$vip/9345" 2>/dev/null || true
        if ip -4 neigh show "$vip" dev "$dev" | grep -q lladdr; then
          echo "rke2-vip-claim: a server holds $vip already"
          exit 0
        fi
        ip -4 addr add "$vip/32" dev "$dev"
        touch /run/rke2-vip-claimed
        echo "rke2-vip-claim: $vip held until rke2 starts"
        ;;
      release)
        [ -e /run/rke2-vip-claimed ] || exit 0
        ip -4 addr del "$vip/32" dev "$dev"
        rm /run/rke2-vip-claimed
        ;;
      *) echo "usage: rke2-vip-claim claim|release" >&2; exit 2 ;;
    esac
%{ endif ~}
- path: /etc/rancher/rke2/config.yaml
  permissions: "0600"
  owner: root:root
  content: |
    %{~ if !is_first ~}
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
    %{~ if s3 != null ~}
    etcd-s3: true
    etcd-s3-endpoint: "${s3.endpoint}"
    etcd-s3-bucket: "${s3.bucket}"
    %{~ if s3.region != null ~}
    etcd-s3-region: "${s3.region}"
    %{~ endif ~}
    %{~ if s3.retention != null ~}
    etcd-s3-retention: ${s3.retention}
    %{~ endif ~}
    %{~ endif ~}
    %{~ if backup_schedule != null ~}
    etcd-snapshot-schedule-cron: "${backup_schedule}"
    %{~ endif ~}
    %{~ if backup_retention != null ~}
    etcd-snapshot-retention: "${backup_retention}"
    %{~ endif ~}
    etcd-snapshot-compress: true
    %{~ if control_plane_requests != "" ~}
    control-plane-resource-requests: "${control_plane_requests}"
    %{~ endif ~}
    %{~ if control_plane_limits != "" ~}
    control-plane-resource-limits: "${control_plane_limits}"
    %{~ endif ~}
    disable-cloud-controller: true
    disable-kube-proxy: ${kube_proxy ? "false" : "true"}
    # disable alone keeps rke2-traefik-crd and its Traefik CRDs
    ingress-controller: none
    disable:
      - rke2-ingress-nginx
      - rke2-traefik
      - rke2-security-responder
      # its RuntimeClasses name runtimes whether the nodes have them (crun, nvidia-experimental): the module deploys
      # those its pools run
      - rke2-runtimeclasses
      %{~ if !ff_gateway_api_crd ~}
      # Gateway API CRDs belong to the gateway implementation installed outside rke2,
      # otherwise an rke2 upgrade can move them ahead of what that implementation reads
      - rke2-gateway-api-crd
      %{~ endif ~}
    cni: cilium
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
# the one key tofu pins: a package upgrade adds RSA and ECDSA keys, which clients preferring them would be shown instead.
# sshd reads it on every connection, ssh.socket starting one per connection
- path: /etc/ssh/sshd_config.d/10-rke2-host-key.conf
  content: |
    HostKey /etc/ssh/ssh_host_ed25519_key
%{ if kube_proxy ~}
# node ports on the agents' addresses only, as Cilium's (patches/rke2-cilium.yaml.tpl): kube-proxy's DNAT comes before
# UFW, which then forwards them
- path: /etc/rancher/rke2/config.yaml.d/60-kube-proxy-nodeports.yaml
  permissions: "0600"
  owner: root:root
  content: |
    kube-proxy-arg+:
      - "nodeport-addresses=${nodeport_cidr}"
%{ endif ~}
- path: /etc/rke2-metadata-guard.nft
  content: |
    # pods' packets enter the node through their veth: under the Cilium policy, whatever runs in the cluster.
    # Host-network pods' leave through output, as the node's own: nothing on the node reads it either, cloud-init and
    # the Cinder node plugin taking the config drive, the cloud controller never asking. Before any DNAT, so that a
    # test redirecting the metadata sees the same drop.
    table inet rke2_metadata_guard
    flush table inet rke2_metadata_guard
    table inet rke2_metadata_guard {
      chain prerouting {
        type filter hook prerouting priority -300; policy accept;
        ip daddr 169.254.169.254 counter drop
        ip6 daddr fe80::a9fe:a9fe counter drop
      }
      chain output {
        type filter hook output priority -300; policy accept;
        ip daddr 169.254.169.254 counter drop
        ip6 daddr fe80::a9fe:a9fe counter drop
      }
    }
- path: /etc/systemd/system/rke2-metadata-guard.service
  content: |
    [Unit]
    Description=Keeps pods off the instance metadata, which serves the node's user_data
    Before=rke2-server.service rke2-agent.service

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=/usr/sbin/nft -f /etc/rke2-metadata-guard.nft

    [Install]
    WantedBy=multi-user.target
- path: /usr/local/bin/rke2-node-config
  permissions: "0755"
  content: |
    ${indent(4, node_config_script)}
- path: /etc/systemd/system/rke2-node-config.service
  content: |
    [Unit]
    Description=SSH keys and firewall of the node, from what tofu pushes

    [Service]
    Type=oneshot
    ExecStart=/usr/bin/python3 /usr/local/bin/rke2-node-config ${system_user}
runcmd:
  %{~ if is_first ~}
  # first, as tofu waits for this server on the VIP to push its secrets
  - /usr/local/bin/rke2-vip-claim claim || exit 1
  %{~ endif ~}
  - mkdir -p /mnt /var/lib/rancher/rke2 /var/lib/kubelet /etc/rancher/rke2/config.yaml.d
  - |
    # Kubelet must create Node.spec.providerID so OCCM LB SG reconcile never sees an empty ID.
    printf '%s\n' 'kubelet-arg+:' "  - \"provider-id=openstack:///$(cat /var/lib/cloud/data/instance-id)\"" > /etc/rancher/rke2/config.yaml.d/99-openstack-provider-id.yaml
    chmod 0600 /etc/rancher/rke2/config.yaml.d/99-openstack-provider-id.yaml
  - systemctl daemon-reload
  - systemctl enable mnt.mount var-lib-rancher-rke2.mount var-lib-kubelet.mount
  - systemctl start mnt.mount var-lib-rancher-rke2.mount var-lib-kubelet.mount
  - bash -c 'source /usr/local/bin/cloud-init-wait.sh && wait_for "rke2 data mounts" "mountpoint -q /mnt && mountpoint -q /var/lib/rancher/rke2 && mountpoint -q /var/lib/kubelet" 5 30' || exit 1
  - install -D -m 0600 /opt/rke2/kubelet/50-graceful-shutdown.conf /var/lib/rancher/rke2/agent/etc/kubelet.conf.d/50-graceful-shutdown.conf || exit 1
  # before rke2 listens: a node that cannot read its keys and firewall does not start
  - systemctl daemon-reload
  - systemctl enable --now rke2-metadata-guard.service || exit 1
  # NFSv4 mounts, ReadWriteMany volumes' included, need no portmapper: only NFSv3 asks rpcbind, listening on 0.0.0.0:111
  - systemctl mask --now rpcbind.socket rpcbind.service || exit 1
%{ if length(runtime_classes) > 0 ~}
  - install -D -m 0600 /opt/rke2/containerd/runtime-classes.toml /var/lib/rancher/rke2/agent/etc/containerd/config-v3.toml.d/runtime-classes.toml || exit 1
%{ endif ~}
  - /usr/local/bin/install-or-upgrade-rke2.sh || exit 1
  - systemctl daemon-reload
  - grep -qxF 'alias crictl="sudo /var/lib/rancher/rke2/bin/crictl -r unix:///run/k3s/containerd/containerd.sock"' /home/${system_user}/.bashrc || echo 'alias crictl="sudo /var/lib/rancher/rke2/bin/crictl -r unix:///run/k3s/containerd/containerd.sock"' >> /home/${system_user}/.bashrc
  - grep -qxF 'alias ctr="sudo /var/lib/rancher/rke2/bin/ctr --address /run/k3s/containerd/containerd.sock --namespace k8s.io"' /home/${system_user}/.bashrc || echo 'alias ctr="sudo /var/lib/rancher/rke2/bin/ctr --address /run/k3s/containerd/containerd.sock --namespace k8s.io"' >> /home/${system_user}/.bashrc
  %{~ if is_server ~}
  - grep -qxF 'alias kubectl="sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml"' /home/${system_user}/.bashrc || echo 'alias kubectl="sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml"' >> /home/${system_user}/.bashrc
  - systemctl enable --now rke2-static-pods-cleanup.service || exit 1
  # kube-vip's IPVS modules, then the sysctls they bring
  - systemctl restart systemd-modules-load.service || exit 1
  - systemctl restart systemd-sysctl.service || exit 1
  # a persisted volume holds the previous instance's manifests, its kube-vip among them
  - rm -rf /var/lib/rancher/rke2/server/manifests && rm -f /var/lib/rancher/rke2/agent/pod-manifests/kube-vip.yaml
  - >
    YQ_VERSION=v4.54.1; YQ_ARCH=$(dpkg --print-architecture);
    case "$YQ_ARCH" in
      amd64) YQ_SHA256=e68a456f90c577af3fe4960184b3a3cf5c461e0348407c10f107da3a5fec8972 ;;
      arm64) YQ_SHA256=8c27f6e7476fb5acefb9352e3d30f6bc2dc93f1956eb92e8da727173fb7ec6d3 ;;
      *) echo "ERROR: no yq checksum for $YQ_ARCH"; exit 1 ;;
    esac;
    yq --version 2>/dev/null | grep -qF "version $YQ_VERSION" || for i in $(seq 1 10); do
      wget -T 30 https://github.com/mikefarah/yq/releases/download/$YQ_VERSION/yq_linux_$YQ_ARCH.tar.gz -O /tmp/yq.tar.gz && echo "$YQ_SHA256  /tmp/yq.tar.gz" | sha256sum -c - && tar xzf /tmp/yq.tar.gz -C /tmp && mv /tmp/yq_linux_$YQ_ARCH /usr/bin/yq && break;
      sleep 5;
    done;
    rm -f /tmp/yq.tar.gz;
    yq --version 2>/dev/null | grep -qF "version $YQ_VERSION" || { echo "ERROR: yq $YQ_VERSION install/checksum failed"; exit 1; };
  # tokens and keys come over SSH from tofu, never through user_data: a server without its token would start a
  # cluster of its own
  - bash -c 'source /usr/local/bin/cloud-init-wait.sh && wait_for "secrets from tofu" "[ -s /etc/rancher/rke2/config.yaml.d/50-secrets.yaml ]" 5 360' || exit 1
  # the firewall and SSH keys came first, applied before rke2 starts
  - systemctl start rke2-node-config.service || exit 1
  - systemctl enable rke2-server.service
  - systemctl start rke2-server.service
  - bash -c 'source /usr/local/bin/cloud-init-wait.sh && wait_for "static pod manifests dir" "[ -d /var/lib/rancher/rke2/agent/pod-manifests/ ]" 1 300' || exit 1
  %{~ if is_first ~}
  # held while rke2 starts, the others joining through it; released before kube-vip, which takes it over, so that no
  # two hold it
  - /usr/local/bin/rke2-vip-claim release || exit 1
  %{~ endif ~}
  - mv -v /opt/rke2/kube-vip.yaml /var/lib/rancher/rke2/agent/pod-manifests/kube-vip.yaml || exit 1
  - ls /var/lib/rancher/rke2/agent/pod-manifests
  # rke2 recopies data/<digest>/charts into server/manifests on every start: patch the source too
  - bash -c 'source /usr/local/bin/cloud-init-wait.sh && wait_for "rke2 data charts" _data_charts_ready 1 300 && /usr/local/bin/customize-charts.sh "$(_rke2_data_dir)/charts"' || exit 1
  - bash -c 'source /usr/local/bin/cloud-init-wait.sh && wait_for "chart manifests" "_charts_ready /var/lib/rancher/rke2/server/manifests" 1 300' || exit 1
  - /usr/local/bin/customize-charts.sh /var/lib/rancher/rke2/server/manifests || exit 1
  - >
    for f in /opt/rke2/manifests/*.yaml; do [ -e "$f" ] || continue; mv -v -t /var/lib/rancher/rke2/server/manifests "$f" || exit 1; done;
  - ls /var/lib/rancher/rke2/server/manifests
  - bash -c 'source /usr/local/bin/cloud-init-wait.sh && wait_for "rke2-server active" "systemctl is-active -q rke2-server.service" 3 200' || exit 1
  %{~ if is_first ~}
  - systemctl restart rke2-server.service # force deploy controller to re-read patched server/manifests
  - bash -c 'source /usr/local/bin/cloud-init-wait.sh && wait_for "rke2-server active after restart" "systemctl is-active -q rke2-server.service" 3 200' || exit 1
  %{~ endif ~}
  %{~ else ~}
  # the token comes over SSH from tofu, never through user_data
  - bash -c 'source /usr/local/bin/cloud-init-wait.sh && wait_for "secrets from tofu" "[ -s /etc/rancher/rke2/config.yaml.d/50-secrets.yaml ]" 5 360' || exit 1
  # the firewall and SSH keys came first, applied before rke2 starts
  - systemctl start rke2-node-config.service || exit 1
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
  - bash -c 'source /usr/local/bin/cloud-init-wait.sh && wait_for "rke2-agent active" "systemctl is-active -q rke2-agent.service" 5 120' || exit 1
  %{~ endif ~}
