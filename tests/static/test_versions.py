"""Pinned versions must agree across RKE2.yaml, patch snapshots, manifests, cloud-init and the README."""

import re
import tomllib
import urllib.request

import pytest
import yaml

from nodes import ROOT, write_files

README = (ROOT / "README.md").read_text()
SNAPSHOTS_DIR = ROOT / "tests" / "patches" / "snapshots"

# README component row -> manifest that pins the same chart version
CHART_ROWS = {
    "OpenStack Cloud Controller": "manifests/cloud-controller-openstack.yaml.tpl",
    "OpenStack Cinder": "manifests/csi-cinder.yaml.tpl",
}


def _readme_row(component: str) -> str:
    match = re.search(rf"^\|\s*{re.escape(component)}\s*\|\s*\[v?([^\]]+)\]", README, re.MULTILINE)
    assert match, f"README has no '{component}' row"
    return match.group(1)


def _rke2_versions() -> list:
    return yaml.safe_load((ROOT / "RKE2.yaml").read_text())["versions"]


def _kube_vip_container(renders) -> dict:
    pod = yaml.safe_load(write_files(renders["server-bootstrap"]["rendered"])["/opt/rke2/kube-vip.yaml"])
    return pod["spec"]["containers"][0]






def test_snapshots_cover_tested_versions():
    snapshots = sorted(p.name for p in SNAPSHOTS_DIR.iterdir() if p.is_dir())
    expected = sorted(v.replace("+", "-") for v in _rke2_versions())
    assert snapshots == expected, "RKE2.yaml versions and tests/patches/snapshots dirs differ"


def test_readme_rke2_versions_are_tested():
    documented = {_readme_row("RKE2")} | set(re.findall(r'rke2_version\s*=\s*"([^"]+)"', README))
    untested = documented - {v.lstrip("v") for v in _rke2_versions()} - set(_rke2_versions())
    assert not untested, f"README documents rke2 versions absent from RKE2.yaml: {sorted(untested)}"


@pytest.mark.parametrize("component, manifest", CHART_ROWS.items())
def test_readme_chart_versions(component, manifest):
    pinned = re.search(r"^\s*version:\s*(\S+)", (ROOT / manifest).read_text(), re.MULTILINE).group(1)
    assert _readme_row(component) == pinned, f"README {component} differs from {manifest}"


def test_yq_pins_agree():
    """customize-chart.sh is tested with the yq of the tools image and of mise: both must be the release the nodes install."""
    node = re.search(r"YQ_VERSION=(v[0-9.]+);", (ROOT / "node" / "cloud-init.yaml.tpl").read_text()).group(1)
    image = re.search(r"ARG YQ_VERSION=(v[0-9.]+)", (ROOT / "tests" / "tools.Dockerfile").read_text()).group(1)
    with (ROOT / "mise.toml").open("rb") as f:
        pinned = "v" + tomllib.load(f)["tools"]["yq"]
    assert node == image == pinned, f"node {node}, tools image {image}, mise {pinned}"


def test_readme_kube_vip_version(renders):
    image = _kube_vip_container(renders)["image"]
    # pinned by digest, the tag kept for the README
    tag, digest = image.split("@")
    assert digest.startswith("sha256:") and len(digest) == len("sha256:") + 64
    assert _readme_row("Kube-vip") == tag.rsplit(":", 1)[1].lstrip("v")


def test_kube_vip_env_names_exist_upstream(renders):
    """kube-vip ignores unknown env vars, so a renamed setting (vip_cidr -> vip_subnet) silently falls back to defaults."""
    container = _kube_vip_container(renders)
    tag = container["image"].split("@")[0].rsplit(":", 1)[1]
    url = f"https://raw.githubusercontent.com/kube-vip/kube-vip/{tag}/pkg/kubevip/config_envvar.go"
    with urllib.request.urlopen(url, timeout=30) as response:
        known = set(re.findall(r'=\s*"([a-z0-9_]+)"', response.read().decode()))
    unknown = sorted({e["name"] for e in container["env"]} - known)
    assert not unknown, f"kube-vip {tag} does not read: {unknown}"
