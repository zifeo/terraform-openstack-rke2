"""Renders the patched packaged charts with helm and checks the patched values actually reach the manifests."""

import re
import shutil
from pathlib import Path

import yaml

from helpers import chart_archive, merge_patch, run

# a limit near the working set makes the kernel evict the binary's page cache and re-read it from disk in a loop
MIN_MEMORY_LIMIT = 32 * 1024**2

_POD = ("spec", "template", "spec")
_AGENT_ENV = _POD + ("containers", "name=cilium-agent", "env")

# (kind, name, path, expected) for the values rendered with helpers.RENDER_VARS.
# "name=x" selects the list item named x; expected None only checks presence.
EXPECTED = {
    "rke2-cilium": [
        ("ConfigMap", "cilium-config", ("data", "kube-proxy-replacement"), "true"),
        ("ConfigMap", "cilium-config", ("data", "cluster-name"), "fixture"),
        ("ConfigMap", "cilium-config", ("data", "cluster-id"), "1"),
        ("DaemonSet", "cilium", _AGENT_ENV + ("name=KUBERNETES_SERVICE_HOST", "value"), "127.0.0.1"),
        ("DaemonSet", "cilium", _AGENT_ENV + ("name=KUBERNETES_SERVICE_PORT", "value"), "6443"),
        ("Deployment", "cilium-operator", ("spec", "replicas"), 2),
        ("Deployment", "cilium-operator", _POD + ("nodeSelector", "node-role.kubernetes.io/control-plane"), "true"),
    ],
    "rke2-coredns": [
        ("Deployment", "rke2-coredns-rke2-coredns", _POD + ("containers", 0, "resources", "limits", "memory"), "128Mi"),
        ("ConfigMap", "rke2-coredns-rke2-coredns-autoscaler", ("data", "linear"), None),
    ],
}

# rke2 passes these to every packaged chart at install time (documented rke2 defaults)
RKE2_GLOBALS = {
    "global.clusterCIDR": "10.42.0.0/16",
    "global.clusterCIDRv4": "10.42.0.0/16",
    "global.clusterDNS": "10.43.0.10",
    "global.clusterDomain": "cluster.local",
    "global.rke2DataDir": "/var/lib/rancher/rke2",
    "global.serviceCIDR": "10.43.0.0/16",
}

_UNITS = {"Ki": 1024, "Mi": 1024**2, "Gi": 1024**3, "k": 1000, "M": 1000**2, "G": 1000**3}


def _bytes(quantity: str) -> float:
    number, unit = re.fullmatch(r"([0-9.]+)([A-Za-z]*)", str(quantity)).groups()
    return float(number) * _UNITS.get(unit, 1)


def _get(doc, path: tuple):
    node = doc
    for key in path:
        if isinstance(key, str) and key.startswith("name="):
            node = next(item for item in node if item.get("name") == key.removeprefix("name="))
        else:
            node = node[key]
    return node


def _containers(doc):
    spec = doc.get("spec", {})
    pod = spec.get("template", {}).get("spec") or spec.get("jobTemplate", {}).get("spec", {}).get("template", {}).get("spec")
    for container in (pod or {}).get("containers", []) + (pod or {}).get("initContainers", []):
        yield container


def _render(chart: str, chart_file: Path, patch: Path, version: str, work: Path) -> list:
    for name, content in chart_archive(chart_file).items():
        (work / "src" / name).parent.mkdir(parents=True, exist_ok=True)
        (work / "src" / name).write_bytes(content)
    upstream = work / "upstream-values.yaml"
    shutil.copy(work / "src" / chart / "values.yaml", upstream)
    merge_patch(upstream, patch, work / "src" / chart / "values.yaml")
    kube_version = version.split("+")[0].lstrip("v")
    sets = [arg for key, value in RKE2_GLOBALS.items() for arg in ("--set-string", f"{key}={value}")]
    out = run([shutil.which("helm") or "helm", "template", chart, str(work / "src" / chart),
               "--namespace", "kube-system", "--kube-version", kube_version, *sets]).stdout
    return [d for d in yaml.safe_load_all(out) if d]


def test_helm_render(version, concrete_patches, charts_cache, tmp_path):
    problems = []
    for chart, patch in concrete_patches.items():
        docs = _render(chart, charts_cache[version] / f"{chart}.yaml", patch, version, tmp_path / chart)
        by_id = {(d["kind"], d["metadata"]["name"]): d for d in docs}

        for kind, name, path, expected in EXPECTED.get(chart, []):
            doc = by_id.get((kind, name))
            if doc is None:
                problems.append(f"{chart}: {kind}/{name} not rendered")
                continue
            try:
                actual = _get(doc, path)
            except (KeyError, IndexError, TypeError, StopIteration):
                problems.append(f"{chart}: {kind}/{name} has no {path}")
                continue
            if expected is not None and actual != expected:
                problems.append(f"{chart}: {kind}/{name} {path} = {actual!r}, expected {expected!r}")

        for doc in docs:
            for c in _containers(doc):
                res = c.get("resources") or {}
                limit = (res.get("limits") or {}).get("memory")
                request = (res.get("requests") or {}).get("memory")
                where = f"{chart}: {doc['kind']}/{doc['metadata']['name']}/{c['name']}"
                if limit and _bytes(limit) < MIN_MEMORY_LIMIT:
                    problems.append(f"{where} memory limit {limit} below {MIN_MEMORY_LIMIT // 1024**2}Mi")
                if limit and request and _bytes(limit) < _bytes(request):
                    problems.append(f"{where} memory limit {limit} below request {request}")
    assert not problems, f"helm render checks failed for {version}:\n" + "\n".join(problems)
