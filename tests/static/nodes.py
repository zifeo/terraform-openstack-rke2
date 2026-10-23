from __future__ import annotations

import base64
import gzip
import json
import shutil
import subprocess
from pathlib import Path
from typing import Dict

import yaml

ROOT = Path(__file__).resolve().parents[2]
FIXTURE_DIR = ROOT / "tests" / "cloud-init"
NODE_DIR = ROOT / "node"

RUNTIME_CLASSES = (
    '{gvisor = {handler = "runsc", runtime_type = "io.containerd.runsc.v1", options = {'
    'TypeUrl = "io.containerd.runsc.v1.options", ConfigPath = "/etc/containerd/runsc.toml"}},'
    ' kata = {handler = "kata", runtime_type = "io.containerd.kata.v2", options = {}}}'
)

# tofu -var values per node profile rendered by tests/cloud-init/main.tf
PROFILES = {
    "server-bootstrap": {"is_server": "true", "gpu_enabled": "false", "bootstrap": "true", "node_ip": "10.0.0.11"},
    "server-join": {"is_server": "true", "gpu_enabled": "false", "bootstrap": "false", "node_ip": "10.0.0.12"},
    "server-first-join": {"is_server": "true", "gpu_enabled": "false", "is_first": "true", "node_ip": "10.0.0.11"},
    "server-s3": {
        "is_server": "true",
        "gpu_enabled": "false",
        "s3": '{endpoint = "s3.fixture.invalid", access_key = "fixture-s3-key", access_secret = "fixture-s3-secret", bucket = "fixture"}',
    },
    "server-no-tolerations": {"is_server": "true", "gpu_enabled": "false", "daemonset_tolerations": "[]"},
    "server-gateway-api": {"is_server": "true", "gpu_enabled": "false", "ff_gateway_api_crd": "true"},
    "agent-keys": {"is_server": "false", "gpu_enabled": "false", "ssh_authorized_keys": "[\"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixture ed25519@fixture\", \"ssh-rsa AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA rsa@fixture\"]"},
    "server-prebuilt": {"is_server": "true", "gpu_enabled": "false", "bootstrap": "true", "node_ip": "10.0.0.11", "image_prebuilt": "true"},
    "agent": {"is_server": "false", "gpu_enabled": "false"},
    "agent-prebuilt": {"is_server": "false", "gpu_enabled": "false", "image_prebuilt": "true"},
    "agent-gpu": {"is_server": "false", "gpu_enabled": "true"},
    "agent-runtime-classes": {"is_server": "false", "gpu_enabled": "false", "runtime_classes": RUNTIME_CLASSES},
    "server-runtime-classes": {"is_server": "true", "gpu_enabled": "false", "runtime_classes": RUNTIME_CLASSES},
}


def tofu(*args: str) -> str:
    binary = shutil.which("tofu")
    if binary is None:
        raise RuntimeError("tofu is required for tests/static")
    result = subprocess.run([binary, f"-chdir={FIXTURE_DIR}", *args], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"tofu {args[0]} failed:\n{result.stderr}")
    return result.stdout


def render_profile(variables: Dict[str, str], state: Path) -> dict:
    """tofu outputs of the fixture: {"rendered": user_data string, "manifests": {name: content}, ...}."""
    # the version every profile renders, which the fixture requires
    variables = {"rke2_version": "v1.37.1+rke2r1", **variables}
    var_args = [arg for key, value in variables.items() for arg in ("-var", f"{key}={value}")]
    tofu("apply", "-auto-approve", "-input=false", f"-state={state}", *var_args)
    outputs = json.loads(tofu("output", "-json", f"-state={state}"))
    return {key: value["value"] for key, value in outputs.items()}


def write_files(rendered: str) -> Dict[str, str]:
    """Decoded cloud-init write_files content by path."""
    files = {}
    for entry in yaml.safe_load(rendered).get("write_files", []):
        content = entry.get("content", "")
        if entry.get("encoding") == "gz+b64":
            content = gzip.decompress(base64.b64decode(content)).decode()
        files[entry["path"]] = content
    return files


def runcmd(rendered: str) -> list[str]:
    return [c if isinstance(c, str) else " ".join(c) for c in yaml.safe_load(rendered)["runcmd"]]


def runcmd_index(commands: list[str], needle: str) -> int:
    matches = [i for i, c in enumerate(commands) if needle in c]
    assert len(matches) == 1, f"{needle!r} in {len(matches)} runcmd entries"
    return matches[0]


def rke2_start(commands: list[str]) -> int:
    """The runcmd entry that starts rke2, server or agent."""
    matches = [i for i, c in enumerate(commands) if "systemctl start rke2-server.service" in c or "systemctl start rke2-agent.service" in c]
    assert len(matches) == 1, f"rke2 started in {len(matches)} runcmd entries"
    return matches[0]
