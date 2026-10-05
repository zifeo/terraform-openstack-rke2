"""Rendered auto-deploy manifests must be valid YAML down to the HelmChart valuesContent.

rke2's deploy controller re-applies every manifest each cycle as soon as one file fails to parse,
so a single broken template turns into a cluster-wide helm upgrade loop.
"""

import pytest
import yaml

from nodes import write_files

SERVER_PROFILES = ["server-bootstrap", "server-no-tolerations"]

# HelmChart name -> path of the daemonset tolerations inside valuesContent
TOLERATIONS_PATH = {
    "openstack-cinder-csi": ("csi", "plugin", "nodePlugin", "tolerations"),
    "velero": ("nodeAgent", "tolerations"),
}


# chart values merged by customize-charts.sh, not manifests for the deploy controller
VALUES_PREFIX = "patches/"


def _documents(manifests):
    for name, content in manifests.items():
        if name.startswith(VALUES_PREFIX):
            continue
        for doc in yaml.safe_load_all(content):
            if doc is not None:
                yield name, doc


def _dig(node, path):
    for key in path:
        node = node[key]
    return node


@pytest.mark.parametrize("profile", SERVER_PROFILES)
def test_manifests_parse(renders, profile):
    errors = []
    for name, content in renders[profile]["manifests"].items():
        try:
            docs = [d for d in yaml.safe_load_all(content) if d is not None]
        except yaml.YAMLError as err:
            errors.append(f"{name}: {err}")
            continue
        if name.startswith(VALUES_PREFIX):
            if len(docs) != 1 or not isinstance(docs[0], dict):
                errors.append(f"{name}: chart values must be a single mapping")
            continue
        for doc in docs:
            if not isinstance(doc, dict) or not {"apiVersion", "kind"} <= doc.keys():
                errors.append(f"{name}: document without apiVersion/kind")
            elif doc["kind"] == "HelmChart" and "valuesContent" in doc["spec"]:
                try:
                    if not isinstance(yaml.safe_load(doc["spec"]["valuesContent"]), dict):
                        errors.append(f"{name}: valuesContent is not a mapping")
                except yaml.YAMLError as err:
                    errors.append(f"{name}: valuesContent: {err}")
    assert not errors, "\n".join(errors)


@pytest.mark.parametrize("profile", SERVER_PROFILES)
def test_tolerations_placement(renders, profile):
    expected = renders[profile]["daemonset_tolerations"]
    found = {}
    for _, doc in _documents(renders[profile]["manifests"]):
        name = doc["metadata"]["name"]
        if doc["kind"] == "HelmChart" and name in TOLERATIONS_PATH:
            found[name] = _dig(yaml.safe_load(doc["spec"]["valuesContent"]), TOLERATIONS_PATH[name])
    assert found.keys() == TOLERATIONS_PATH.keys()
    for name, tolerations in found.items():
        assert tolerations == expected, f"{name} tolerations"


def test_user_data_carries_manifests(renders):
    files = write_files(renders["server-bootstrap"]["rendered"])
    shipped = {p.removeprefix("/opt/rke2/manifests/"): c for p, c in files.items() if p.startswith("/opt/rke2/manifests/")}
    assert shipped == renders["server-bootstrap"]["manifests"]


def test_agents_get_no_manifests(renders):
    files = write_files(renders["agent"]["rendered"])
    assert not [p for p in files if p.startswith("/opt/rke2/manifests/")]


# ingress and Gateway API live outside rke2: a bundled copy competes with them on upgrades
RKE2_DISABLED_CHARTS = {"rke2-ingress-nginx", "rke2-traefik", "rke2-gateway-api-crd"}


@pytest.mark.parametrize("profile", ["server-bootstrap", "server-join"])
def test_servers_disable_bundled_ingress_charts(renders, profile):
    config = yaml.safe_load(write_files(renders[profile]["rendered"])["/etc/rancher/rke2/config.yaml"])
    assert RKE2_DISABLED_CHARTS <= set(config.get("disable", []))
