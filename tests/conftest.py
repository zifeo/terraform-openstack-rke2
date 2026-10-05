from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Callable, Dict

import pytest

TESTS_DIR = Path(__file__).resolve().parent
ROOT = TESTS_DIR.parent
TOOLS_IMAGE = "terraform-openstack-rke2-tests:tools"


@pytest.fixture(scope="session")
def tools() -> Callable[..., subprocess.CompletedProcess]:
    """Runs a bash script in the node-like tools container; mounts maps host paths to container paths."""
    build = subprocess.run(
        ["docker", "build", "-q", "-t", TOOLS_IMAGE, "-f", str(TESTS_DIR / "tools.Dockerfile"), str(TESTS_DIR)],
        capture_output=True,
        text=True,
    )
    if build.returncode:
        pytest.fail(f"tools image build failed:\n{build.stderr}")

    def run(script: str, mounts: Dict[Path, str], check: bool = True) -> subprocess.CompletedProcess:
        cmd = ["docker", "run", "--rm"]
        for host, container in mounts.items():
            cmd += ["-v", f"{host}:{container}"]
        cmd += [TOOLS_IMAGE, "bash", "-euo", "pipefail", "-c", script]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if check and result.returncode:
            pytest.fail(f"tools container exited {result.returncode}:\n{result.stdout}\n{result.stderr}")
        return result

    return run
