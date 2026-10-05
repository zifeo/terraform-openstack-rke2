# same userland as the nodes: GNU tar/gzip, the yq release pinned in node/cloud-init.yaml.tpl, Ubuntu 22.04 cloud-init schema
FROM ubuntu:22.04
ARG YQ_VERSION=v4.40.5
RUN apt-get update -qq \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends cloud-init shellcheck wget ca-certificates \
  && rm -rf /var/lib/apt/lists/*
RUN wget -q "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_$(dpkg --print-architecture)" -O /usr/bin/yq \
  && chmod +x /usr/bin/yq
