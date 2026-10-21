#!/usr/bin/env python3
"""What a node takes from the file tofu pushes over SSH with its secrets (CONFIG), and pushes again in place when it
changes, without replacing the node (node/metadata/main.tf says why not from the instance metadata).

- ssh_keys: the SSH keys besides the instance's keypair, in a block of authorized_keys;
- firewall: what UFW lets in, a "protocol port source" rule each, nothing else. It resets UFW the first time, then adds
  and deletes only its own rules.

cloud-init runs it once the file is there, before rke2 starts, and tofu after each push. It reads and checks everything
before it changes anything, changes only what differs, and fails without changing anything when the file is missing or
invalid.
Usage: rke2-node-config <user whose authorized_keys it manages>"""

import ipaddress
import json
import os
import pathlib
import pwd
import re
import subprocess
import sys

CONFIG = pathlib.Path("/etc/rancher/rke2-node-config.json")
APPLIED = pathlib.Path("/var/lib/rke2-node-config/firewall")
BEGIN = "# BEGIN rke2-node-config: ssh_authorized_keys besides the keypair, from tofu"
END = "# END rke2-node-config"
# a key and its comment, no options: a line of the block can neither restrict a key nor close the block early
RULE = re.compile(r"(?P<protocol>tcp|udp|any) (?P<port>\d+(:\d+)?|any) (?P<source>\S+)")
KEY = re.compile(
    r"(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)"
    r" [A-Za-z0-9+/]+={0,2}( [^\x00-\x1f\x7f]*)?"
)


def strings(config: dict, name: str) -> list[str]:
    value = config.get(name)
    if not isinstance(value, list) or not all(isinstance(v, str) for v in value):
        raise ValueError(f"{name} is not a list of strings")
    return value


def ssh_keys(config: dict) -> list[str]:
    keys = strings(config, "ssh_keys")
    invalid = [k[:40] for k in keys if not KEY.fullmatch(k)]
    if invalid:
        raise ValueError(f"not public keys: {invalid}")
    return keys


def with_keys(current: str, keys: list[str]) -> str:
    """authorized_keys with the block replaced by keys, every other line kept."""
    lines, inside = [], False
    # only newlines end a line for sshd: splitlines() would also break on a carriage return inside a comment
    for line in current.removesuffix("\n").split("\n") if current else []:
        # another tool may have rewritten the file with CRLF; the block's own lines hold no control character
        if line.removesuffix("\r") == BEGIN:
            inside = True
        elif line.removesuffix("\r") == END:
            inside = False
        elif not inside:
            lines.append(line)
    if keys:
        lines += [BEGIN, *keys, END]
    return "".join(f"{line}\n" for line in lines)


def apply_ssh_keys(user: str, keys: list[str]) -> None:
    account = pwd.getpwnam(user)
    path = pathlib.Path(account.pw_dir) / ".ssh" / "authorized_keys"
    current = path.read_text() if path.exists() else ""
    wanted = with_keys(current, keys)
    if wanted == current:
        return
    path.parent.mkdir(mode=0o700, exist_ok=True)
    partial = path.with_name(".authorized_keys.rke2-node-config")
    partial.unlink(missing_ok=True)
    # root writing in the user's directory: never through a link the user left there
    fd = os.open(partial, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as f:
        os.fchown(f.fileno(), account.pw_uid, account.pw_gid)
        f.write(wanted)
    partial.replace(path)
    print(f"{len(keys)} ssh keys in {path}", flush=True)


def rules(config: dict) -> list[list[str]]:
    lines = strings(config, "firewall")
    if not lines:
        raise ValueError("no firewall rule: the node would let nothing in")
    wanted = []
    for line in lines:
        match = RULE.fullmatch(line)
        ports = [int(p) for p in re.findall(r"\d+", match["port"])] if match else []
        # what ufw would refuse once it is reset, after which it would stay off
        if (
            not match
            or (match["protocol"] == "any") != (match["port"] == "any")
            or any(not 1 <= p <= 65535 for p in ports)
            or (len(ports) == 2 and ports[0] >= ports[1])
        ):
            raise ValueError(f"not a firewall rule: {line[:60]!r}")
        network = ipaddress.ip_network(match["source"], strict=False)
        # as ufw stores it, or a later delete would miss: the network, a host without its /32
        source = str(network.network_address) if network.prefixlen == network.max_prefixlen else str(network)
        port = [] if match["protocol"] == "any" else ["to", "any", "port", match["port"], "proto", match["protocol"]]
        rule = ["allow", "from", source, *port]
        # once each: a second delete of the same rule would fail every run
        if rule not in wanted:
            wanted.append(rule)
    return wanted


def ufw(*args: str) -> str:
    return subprocess.run(["ufw", *args], check=True, capture_output=True, text=True).stdout


def applied() -> list[list[str]] | None:
    try:
        return json.loads(APPLIED.read_text())
    except (OSError, ValueError):
        return None


def apply_firewall(wanted: list[list[str]]) -> None:
    before = applied()
    if before is not None and "Status: active" in ufw("status"):
        # adds before it deletes, and never turns UFW off: no moment without the rules both versions agree on
        for rule in wanted:
            if rule not in before:
                ufw(*rule)
        for rule in before:
            if rule not in wanted:
                ufw("delete", *rule)
    else:
        ufw("--force", "reset")
        ufw("default", "deny", "incoming")
        ufw("default", "allow", "outgoing")
        # pods reach each other through the node
        ufw("default", "allow", "routed")
        # on before the rules: should ufw still refuse one, it is left filtering, not off
        ufw("--force", "enable")
        for rule in wanted:
            ufw(*rule)
    if wanted != before:
        APPLIED.parent.mkdir(parents=True, exist_ok=True)
        partial = APPLIED.with_name(f".{APPLIED.name}")
        partial.write_text(json.dumps(wanted))
        partial.replace(APPLIED)
        print("firewall", wanted, flush=True)


def main(user: str) -> None:
    config = json.loads(CONFIG.read_text())
    keys = ssh_keys(config)
    wanted = rules(config)
    apply_ssh_keys(user, keys)
    apply_firewall(wanted)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__.splitlines()[-1])
    main(sys.argv[1])
