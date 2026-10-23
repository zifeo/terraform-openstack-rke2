"""Kubelet graceful node shutdown, which rke2 leaves off, installed on every node before rke2 starts."""

import pytest
from nodes import rke2_start, runcmd, runcmd_index, write_files


@pytest.mark.parametrize("profile", ["server-bootstrap", "server-join", "agent", "agent-gpu"])
def test_graceful_node_shutdown_on_every_node(renders, profile):
    rendered = renders[profile]["rendered"]
    assert "/opt/rke2/kubelet/50-graceful-shutdown.conf" in write_files(rendered)
    commands = runcmd(rendered)
    mounts = runcmd_index(commands, 'wait_for "rke2 data mounts"')
    install = runcmd_index(commands, "/var/lib/rancher/rke2/agent/etc/kubelet.conf.d/50-graceful-shutdown.conf")
    start = rke2_start(commands)
    assert mounts < install < start
