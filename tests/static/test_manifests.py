"""Rendered auto-deploy manifests must be valid YAML down to the HelmChart valuesContent.

rke2's deploy controller re-applies every manifest each cycle as soon as one file fails to parse,
so a single broken template turns into a cluster-wide helm upgrade loop.
"""

import pytest
import yaml

from nodes import rke2_start, runcmd, runcmd_index, write_files

SERVER_PROFILES = ["server-bootstrap", "server-no-tolerations"]

# HelmChart name -> path of the daemonset tolerations inside valuesContent
TOLERATIONS_PATH = {
    "openstack-cinder-csi": ("csi", "plugin", "nodePlugin", "tolerations"),
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


# ingress, Gateway API and telemetry live outside rke2: a bundled copy competes with them on upgrades; RuntimeClasses
# come from the pools
RKE2_DISABLED_CHARTS = {"rke2-ingress-nginx", "rke2-traefik", "rke2-gateway-api-crd", "rke2-security-responder", "rke2-runtimeclasses"}


def _server_config(renders, profile) -> dict:
    return yaml.safe_load(write_files(renders[profile]["rendered"])["/etc/rancher/rke2/config.yaml"])


def _secrets(renders, profile) -> dict:
    """What tofu pushes over SSH as config.yaml.d/50-secrets.yaml."""
    return yaml.safe_load(renders[profile]["secrets"]["config"])


def test_agents_join_with_their_own_token(renders):
    """An agent gets the agents' token, not the servers', which gives the cluster's CA; tofu pushes either apart, as
    49-token.yaml, prefixed with the hash of the CA the bastion's rke2 made, so that a node joining checks it."""
    server, agent = renders["server-bootstrap"]["secrets"], renders["agent"]["secrets"]
    assert agent["token"] == _secrets(renders, "server-bootstrap")["agent-token"] != server["token"]
    assert _secrets(renders, "agent") == {} and "token" not in _secrets(renders, "server-bootstrap")
    assert (server["token_user"], agent["token_user"]) == ("server", "node")


SECRETS = ["fixture-server-token", "fixture-agent-token", "fixture-s3-key", "fixture-s3-secret", "fixture-app-secret"]


@pytest.mark.parametrize("profile", ["server-bootstrap", "server-join", "server-s3", "agent", "agent-gpu"])
def test_user_data_holds_no_secret(renders, profile):
    """Nova keeps user_data and serves it to anything that reaches the metadata: the tokens, the snapshots' key and the
    cloud credentials come over SSH instead, and rke2 starts only once they are there."""
    rendered = renders[profile]["rendered"]
    assert not [s for s in SECRETS if s in rendered]
    config = yaml.safe_load(write_files(rendered)["/etc/rancher/rke2/config.yaml"])
    assert not {"token", "agent-token", "etcd-s3-access-key", "etcd-s3-secret-key"} & config.keys()
    assert "/etc/rancher/rke2/registries.yaml" not in write_files(rendered)
    commands = runcmd(rendered)
    assert runcmd_index(commands, "config.yaml.d/50-secrets.yaml") < rke2_start(commands)


@pytest.mark.parametrize("profile", ["server-bootstrap", "agent"])
def test_sshd_shows_only_the_pinned_host_key(renders, profile):
    """tofu checks the node's ed25519 key: an upgrade of openssh-server adds RSA and ECDSA ones, which Go's SSH client,
    tofu's, prefers."""
    rendered = yaml.safe_load(renders[profile]["rendered"])
    assert set(rendered["ssh_keys"]) == {"ed25519_private", "ed25519_public"} and rendered["ssh_genkeytypes"] == ["ed25519"]
    dropin = write_files(renders[profile]["rendered"])["/etc/ssh/sshd_config.d/10-rke2-host-key.conf"]
    assert dropin.split() == ["HostKey", "/etc/ssh/ssh_host_ed25519_key"]




def test_storage_classes_take_the_node_zone_on_request(renders):
    """availability nova by default; "" drops it, so that a region with several zones creates the volume in the zone
    of the pod's node (EU-WEST-PAR has no zone nova)."""
    manifests = renders["server-bootstrap"]["manifests"]
    assert yaml.safe_load(manifests["csi-cinder-delete.yaml"])["parameters"] == {"availability": "nova"}
    assert yaml.safe_load(manifests["zoned.yaml"])["parameters"] == {"type": "high-speed"}


def test_the_snapshots_key_comes_with_the_secrets(renders):
    pushed = _secrets(renders, "server-s3")
    assert (pushed["etcd-s3-access-key"], pushed["etcd-s3-secret-key"]) == ("fixture-s3-key", "fixture-s3-secret")
    config = _server_config(renders, "server-s3")
    assert config["etcd-s3"] is True and config["etcd-s3-bucket"] == "fixture"


@pytest.mark.parametrize("profile", ["server-bootstrap", "server-join"])
def test_servers_disable_bundled_charts(renders, profile):
    config = _server_config(renders, profile)
    # disable only drops rke2-traefik: rke2-traefik-crd and its Traefik CRDs need ingress-controller none
    assert config["ingress-controller"] == "none"
    assert RKE2_DISABLED_CHARTS <= set(config["disable"])


def test_gateway_api_crd_opt_in(renders):
    disabled = set(_server_config(renders, "server-gateway-api")["disable"])
    assert "rke2-gateway-api-crd" not in disabled
    assert RKE2_DISABLED_CHARTS - {"rke2-gateway-api-crd"} <= disabled


def test_helmcharts_retry_on_failure(renders):
    """helm-controller runs Helm v4: on a field conflict the default reinstall policy uninstalls the chart."""
    charts = [doc for _, doc in _documents(renders["server-bootstrap"]["manifests"]) if doc["kind"] == "HelmChart"]
    assert charts
    for doc in charts:
        spec = doc["spec"]
        assert (spec.get("failurePolicy"), spec.get("forceConflicts")) == ("retry", True), doc["metadata"]["name"]






def test_cloud_credentials_stay_out_of_the_manifests(renders):
    """etcd and its snapshots keep a HelmChart's values as written, a Secret encrypted; the servers' manifests come
    with user_data. tofu applies the Secrets through the API instead."""
    for name, content in renders["server-bootstrap"]["manifests"].items():
        assert "fixture-app-secret" not in content, name
    secrets = {d["metadata"]["name"]: d for d in yaml.safe_load_all(renders["server-bootstrap"]["cluster_secrets"])}
    assert set(secrets) == {"rke2-occm-cloud-config"}
    for doc in secrets.values():
        assert doc["kind"] == "Secret" and "fixture-app-secret" in doc["stringData"]["cloud.conf"]


def _cinder_values(renders) -> dict:
    [chart] = [d for _, d in _documents(renders["server-bootstrap"]["manifests"]) if d["metadata"]["name"] == "openstack-cinder-csi"]
    return yaml.safe_load(chart["spec"]["valuesContent"])


@pytest.mark.parametrize("profile", ["agent", "agent-gpu"])
def test_agents_hold_no_cloud_credential(renders, profile):
    """The chart gives its node plugin, on every agent, the controller's Secret: it reads the node's file instead, which
    on agents holds what the node plugin reads and no credential (cinder-csi-plugin 1.37 needs none there)."""
    assert _cinder_values(renders)["secret"] == {"enabled": False, "hostMount": True}
    conf = write_files(renders[profile]["rendered"])["/etc/config/cloud.conf"]
    assert "[BlockStorage]" in conf and "[Global]" not in conf and "application-credential" not in conf
    assert renders[profile]["secrets"]["cinder"] is None


@pytest.mark.parametrize("profile", ["server-bootstrap", "server-join"])
def test_servers_get_the_cinder_credentials_over_ssh(renders, profile):
    """The controller runs on the servers: their file, the credentials and what the node plugin reads, comes with the
    secrets tofu pushes, not with user_data."""
    assert "/etc/config/cloud.conf" not in write_files(renders[profile]["rendered"])
    conf = renders[profile]["secrets"]["cinder"]
    assert "application-credential-secret = fixture-app-secret" in conf and "[BlockStorage]" in conf


@pytest.mark.parametrize("profile", ["server-bootstrap", "agent"])
def test_nodes_drop_pods_packets_to_the_instance_metadata(renders, profile):
    """The guard is up before rke2 starts, and on every later boot rke2 waits for it, and does not start without it.
    What it drops, the e2e proves on the nodes."""
    rendered = renders[profile]["rendered"]
    files = write_files(rendered)
    commands = runcmd(rendered)
    assert runcmd_index(commands, "enable --now rke2-metadata-guard.service") < rke2_start(commands)
    role = "agent" if profile == "agent" else "server"
    dropin = files[f"/etc/systemd/system/rke2-{role}.service.d/metadata-guard.conf"]
    assert "Requires=rke2-metadata-guard.service" in dropin and "After=rke2-metadata-guard.service" in dropin




def _without_host_key(renders, profile) -> dict:
    doc = yaml.safe_load(renders[profile]["rendered"])
    doc.pop("ssh_keys")
    return doc


def test_bootstrap_false_replaces_no_server(renders):
    """The first server's user_data is the same whether it bootstraps or joins: bootstrap = false only pushes that
    server its join, which a first server replaced later gets before rke2 starts."""
    assert _without_host_key(renders, "server-bootstrap") == _without_host_key(renders, "server-first-join")
    digest = [r["rendered"].splitlines()[1] for r in (renders["server-bootstrap"], renders["server-first-join"])]
    assert digest[0] == digest[1] and digest[0].startswith("# rke2's secrets ")
    assert renders["server-bootstrap"]["secrets"]["join"] == ""
    assert renders["server-first-join"]["secrets"]["join"] == 'server: "https://10.0.0.10:9345"\n'
    config = yaml.safe_load(write_files(renders["server-first-join"]["rendered"])["/etc/rancher/rke2/config.yaml"])
    assert "server" not in config
