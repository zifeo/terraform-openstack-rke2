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

# tofu -var values per node profile rendered by tests/cloud-init/main.tf
PROFILES = {
    "server-bootstrap": {"is_server": "true", "gpu_enabled": "false", "bootstrap": "true", "node_ip": "10.0.0.11"},
    "server-join": {"is_server": "true", "gpu_enabled": "false", "bootstrap": "false", "node_ip": "10.0.0.12"},
    "server-no-tolerations": {"is_server": "true", "gpu_enabled": "false", "daemonset_tolerations": "[]"},
    "agent": {"is_server": "false", "gpu_enabled": "false"},
    "agent-gpu": {"is_server": "false", "gpu_enabled": "true"},
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
