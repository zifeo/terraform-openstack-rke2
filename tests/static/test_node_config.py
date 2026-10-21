"""rke2-node-config: on every node, applied before rke2; the config tofu pushes it; what it does with it."""

import importlib.util
import json
import os
import pwd
from types import SimpleNamespace

import pytest
from nodes import PROFILES, ROOT, rke2_start, runcmd, runcmd_index, write_files

SCRIPT = ROOT / "node" / "rke2-node-config.py"
spec = importlib.util.spec_from_file_location("rke2_node_config", SCRIPT)
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)


@pytest.mark.parametrize("profile", ["server-bootstrap", "agent"])
def test_every_node_gets_it(renders, profile):
    """Applied once tofu's push is there, before rke2 starts; nothing reads the instance metadata every minute."""
    files = write_files(renders[profile]["rendered"])
    assert files["/usr/local/bin/rke2-node-config"].strip() == SCRIPT.read_text().strip()
    assert not [f for f in files if f.endswith(".timer")]
    commands = runcmd(renders[profile]["rendered"])
    applied = runcmd_index(commands, "systemctl start rke2-node-config.service")
    assert runcmd_index(commands, "config.yaml.d/50-secrets.yaml") < applied < rke2_start(commands)


def test_keys_come_with_the_push_not_user_data_nor_the_metadata(renders):
    """Without port security another node could answer for the instance metadata: it carries nothing a node acts on."""
    keys = json.loads(PROFILES["agent-keys"]["ssh_authorized_keys"])
    assert not any(k in renders["agent-keys"]["rendered"] for k in keys)
    assert agent.ssh_keys(renders["agent-keys"]["node_config"]) == keys
    assert agent.ssh_keys(renders["agent"]["node_config"]) == []
    for profile in ("agent-keys", "server-bootstrap"):
        assert set(renders[profile]["metadata"]) == {"rke2_version", "rke2_role", "rke2_bootstrap"}


def test_every_node_has_its_firewall_pushed(renders):
    """The security groups' rules, which UFW keeps without port security: outside, servers take SSH and the API."""
    server, agent_ = (agent.rules(renders[p]["node_config"]) for p in ("server-bootstrap", "agent"))
    for rules in (server, agent_):
        assert ["allow", "from", "10.0.0.0/24", "to", "any", "port", "10250", "proto", "tcp"] in rules
        assert ["allow", "from", "10.0.0.0/24", "to", "any", "port", "30000:32767", "proto", "tcp"] in rules
    assert ["allow", "from", "10.42.0.0/16"] in agent_
    # pods reach a server, its supervisor and etcd excepted: no pod speaks to them
    pods = [r[6] for r in server if r[2] == "10.42.0.0/16"]
    assert pods == ["1:2378", "2381:9344", "9346:65535", "1:65535"]
    assert ["allow", "from", "192.0.2.0/24", "to", "any", "port", "6443", "proto", "tcp"] in server
    assert ["allow", "from", "0.0.0.0/0", "to", "any", "port", "22", "proto", "tcp"] in server
    assert not any(r[2] in ("192.0.2.0/24", "0.0.0.0/0") for r in agent_)
    assert ["allow", "from", "10.0.0.0/24", "to", "any", "port", "2379", "proto", "tcp"] not in agent_
    unit = write_files(renders["agent"]["rendered"])["/etc/systemd/system/rke2-node-config.service"]
    assert "/usr/local/bin/rke2-node-config ubuntu\n" in unit


def config(firewall=("any any 10.0.0.0/24",), ssh_keys=()) -> dict:
    return {"ssh_keys": list(ssh_keys), "firewall": list(firewall)}


@pytest.mark.parametrize("key", [
    'command="sh" ssh-ed25519 AAAA a',
    "# END rke2-node-config",
    "not-a-key AAAA",
    # sshd reads one line where splitlines() would see three, one of them closing the block
    "ssh-ed25519 AAAA x\r# END rke2-node-config\rssh-ed25519 EVIL",
])
def test_only_public_keys(key):
    with pytest.raises(ValueError):
        agent.ssh_keys(config(ssh_keys=("ssh-ed25519 AAAA ok", key)))


def test_the_block_keeps_every_other_line():
    current = "ssh-ed25519 KEYPAIR cloud-init\n"
    once = agent.with_keys(current, ["ssh-ed25519 A a", "ssh-rsa B b"])
    assert once == f"ssh-ed25519 KEYPAIR cloud-init\n{agent.BEGIN}\nssh-ed25519 A a\nssh-rsa B b\n{agent.END}\n"
    assert agent.with_keys(once, ["ssh-rsa B b"]) == f"ssh-ed25519 KEYPAIR cloud-init\n{agent.BEGIN}\nssh-rsa B b\n{agent.END}\n"
    assert agent.with_keys(once, []) == current
    # rewritten with CRLF by another tool: the block is still found, the other lines are kept as they are
    crlf = once.replace("\n", "\r\n")
    assert agent.with_keys(crlf, []) == "ssh-ed25519 KEYPAIR cloud-init\r\n"




def test_rules_as_ufw_stores_them():
    """Each protocol and port form, and as ufw keeps them: the network of a range and a host without /32, which a rule
    written otherwise could never be deleted by."""
    rules = config(firewall=("tcp 6443 192.0.2.0/24", "udp 30000:32767 10.0.0.0/24", "any any 10.42.0.0/16"))
    assert agent.rules(rules) == [
        ["allow", "from", "192.0.2.0/24", "to", "any", "port", "6443", "proto", "tcp"],
        ["allow", "from", "10.0.0.0/24", "to", "any", "port", "30000:32767", "proto", "udp"],
        ["allow", "from", "10.42.0.0/16"],
    ]
    assert agent.rules(config(firewall=("any any 10.0.0.7/24", "tcp 6443 192.0.2.1/32"))) == [
        ["allow", "from", "10.0.0.0/24"],
        ["allow", "from", "192.0.2.1", "to", "any", "port", "6443", "proto", "tcp"],
    ]
    # once each: a second delete of the same rule would fail every run
    assert agent.rules(config(firewall=("any any 10.0.0.0/24", "any any 10.0.0.0/24"))) == [["allow", "from", "10.0.0.0/24"]]


@pytest.fixture
def node(tmp_path, monkeypatch):
    """The pushed file, a home for the user, and a ufw that records what it is asked."""
    pushed = tmp_path / "rke2-node-config.json"
    pushed.write_text(json.dumps(config(firewall=("any any 10.0.0.0/24", "tcp 6443 192.0.2.0/24"))))
    home = tmp_path / "home"
    (home / ".ssh").mkdir(parents=True)
    authorized = home / ".ssh" / "authorized_keys"
    authorized.write_text("ssh-ed25519 KEYPAIR cloud-init\n")
    me = pwd.getpwuid(os.getuid())
    account = SimpleNamespace(pw_dir=str(home), pw_uid=me.pw_uid, pw_gid=me.pw_gid)
    monkeypatch.setattr(agent.pwd, "getpwnam", lambda user: account)
    monkeypatch.setattr(agent, "CONFIG", pushed)
    monkeypatch.setattr(agent, "APPLIED", tmp_path / "applied")
    calls, active = [], [False]

    def ufw(*args):
        calls.append(list(args))
        if args[:2] == ("--force", "enable"):
            active[0] = True
        if args[:2] == ("--force", "reset"):
            active[0] = False
        return "Status: active" if active[0] and args == ("status",) else "Status: inactive"

    monkeypatch.setattr(agent, "ufw", ufw)
    return pushed, calls, authorized


def test_follows_what_tofu_pushes(node):
    pushed, calls, authorized = node
    agent.main("user")
    assert calls[0:5] == [
        ["--force", "reset"], ["default", "deny", "incoming"], ["default", "allow", "outgoing"],
        ["default", "allow", "routed"], ["--force", "enable"],
    ], "on before its rules: a rule ufw refuses must leave it filtering"
    assert authorized.read_text() == "ssh-ed25519 KEYPAIR cloud-init\n"
    calls.clear()
    agent.main("user")
    assert calls == [["status"]], "unchanged rules must not be applied again"
    pushed.write_text(json.dumps(config(
        firewall=("any any 10.0.0.0/24", "tcp 6443 198.51.100.0/24"), ssh_keys=("ssh-ed25519 ADDED added",)
    )))
    calls.clear()
    agent.main("user")
    assert calls == [
        ["status"],
        ["allow", "from", "198.51.100.0/24", "to", "any", "port", "6443", "proto", "tcp"],
        ["delete", "allow", "from", "192.0.2.0/24", "to", "any", "port", "6443", "proto", "tcp"],
    ], "a change adds, then deletes, and never resets"
    assert authorized.read_text() == f"ssh-ed25519 KEYPAIR cloud-init\n{agent.BEGIN}\nssh-ed25519 ADDED added\n{agent.END}\n"
    assert authorized.stat().st_mode & 0o777 == 0o600


@pytest.mark.parametrize("pushed", [
    "{}",
    json.dumps({"ssh_keys": []}),
    json.dumps({"firewall": ["any any 10.0.0.0/24"]}),
    json.dumps(config(firewall=())),
    json.dumps(config(firewall=("tcp 6443 any",))),
    json.dumps(config(firewall=("tcp any 10.0.0.0/24",))),
    json.dumps(config(firewall=("any 22 10.0.0.0/24",))),
    json.dumps(config(firewall=("tcp 65536 10.0.0.0/24",))),
    json.dumps(config(firewall=("tcp 0 10.0.0.0/24",))),
    json.dumps(config(firewall=("tcp 32767:30000 10.0.0.0/24",))),
    json.dumps(config(firewall=("icmp 0 10.0.0.0/24",))),
    json.dumps({"ssh_keys": "ssh-ed25519 AAAA a", "firewall": ["any any 10.0.0.0/24"]}),
    json.dumps({"ssh_keys": [], "firewall": [1]}),
])
def test_invalid_config_changes_nothing(node, pushed):
    path, calls, authorized = node
    agent.main("user")
    calls.clear()
    path.write_text(pushed)
    with pytest.raises(ValueError):
        agent.main("user")
    assert calls == [] and authorized.read_text() == "ssh-ed25519 KEYPAIR cloud-init\n"


def test_changes_nothing_without_the_file(node):
    path, calls, authorized = node
    path.unlink()
    with pytest.raises(OSError):
        agent.main("user")
    assert calls == [] and authorized.read_text() == "ssh-ed25519 KEYPAIR cloud-init\n"
