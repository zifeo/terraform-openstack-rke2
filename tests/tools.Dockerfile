# same userland as the nodes: Ubuntu 26.04 (uutils coreutils, GNU tar/gzip), its cloud-init schema, the yq release pinned in node/cloud-init.yaml.tpl
# checkov:skip=CKV_DOCKER_2:runs one test script per docker run --rm, no service to health check
# checkov:skip=CKV_DOCKER_3:root like the nodes, and it writes into host directories mounted by the tests
FROM ubuntu:26.04
ARG YQ_VERSION=v4.54.1
RUN apt-get update -qq \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends cloud-init shellcheck wget ca-certificates \
  && rm -rf /var/lib/apt/lists/*
RUN wget -q "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_$(dpkg --print-architecture)" -O /usr/bin/yq \
  && chmod +x /usr/bin/yq
