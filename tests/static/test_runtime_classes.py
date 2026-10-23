"""Per-pool RuntimeClasses: the containerd handler on the pool's nodes and the RuntimeClass that selects them."""

import tomllib

import yaml
from nodes import rke2_start, runcmd, runcmd_index, write_files

STAGED = "/opt/rke2/containerd/runtime-classes.toml"
DROP_IN = "/var/lib/rancher/rke2/agent/etc/containerd/config-v3.toml.d/runtime-classes.toml"


def test_handlers_registered_before_rke2_starts(renders):
    rendered = renders["agent-runtime-classes"]["rendered"]
    config = tomllib.loads(write_files(rendered)[STAGED])
    assert config["version"] == 3
    assert config["plugins"]["io.containerd.cri.v1.runtime"]["containerd"]["runtimes"] == {
        "runsc": {"runtime_type": "io.containerd.runsc.v1",
                  "options": {"TypeUrl": "io.containerd.runsc.v1.options", "ConfigPath": "/etc/containerd/runsc.toml"}},
        "kata": {"runtime_type": "io.containerd.kata.v2"},
    }
    commands = runcmd(rendered)
    mounts = runcmd_index(commands, 'wait_for "rke2 data mounts"')
    install = runcmd_index(commands, DROP_IN)
    start = rke2_start(commands)
    assert mounts < install < start


def test_no_handler_without_runtime_classes(renders):
    rendered = renders["agent"]["rendered"]
    assert STAGED not in write_files(rendered)
    assert DROP_IN not in rendered


def test_runtime_classes_select_their_pool(renders):
    manifests = renders["server-runtime-classes"]["manifests"]
    scheduling = {"nodeSelector": {"example.com/pool": "sandboxed"},
                  "tolerations": [{"key": "example.com/pool", "operator": "Equal", "value": "sandboxed", "effect": "NoSchedule"}]}
    for name, handler in (("gvisor", "runsc"), ("kata", "kata")):
        assert yaml.safe_load(manifests[f"runtimeclass-{name}.yaml"]) == {
            "apiVersion": "node.k8s.io/v1", "kind": "RuntimeClass", "metadata": {"name": name}, "handler": handler,
            "scheduling": scheduling,
        }
