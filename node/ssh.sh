#!/bin/bash
# ssh.sh <command>: runs command on the node, through the bastion if any, with OpenSSH, each hop's host key checked;
# stdin goes to the command. Waits up to 10 minutes for the node to answer: a booting node may still present its
# image's host key until cloud-init installs the pinned one.
# Not tofu's SSH: OpenTofu checks its bastion against the target's host key (communicator/ssh/provisioner.go,
# bastion_host_key ignored), which an agent's own key never matches.
# Environment: HOST, HOST_KEY, SSH_USER, and BASTION, BASTION_KEY, BASTION_USER unless HOST is reached directly.
# RERUN=1: a command that reads no stdin is run again when the node drops the connection (255), as cloud-init's
# package_reboot_if_required and the GPU drivers reboot it, at most twice.
set -euo pipefail
dir=$(mktemp -d)
trap 'rm -f "$dir/config" "$dir/known_hosts" && rmdir "$dir"' EXIT
printf '%s %s\n' "$HOST" "$HOST_KEY" >"$dir/known_hosts"
: >"$dir/config"
if [ -n "${BASTION:-}" ]; then
  printf '%s %s\n' "$BASTION" "$BASTION_KEY" >>"$dir/known_hosts"
  printf 'Host bastion\n  HostName %s\n  User %s\nHost node\n  ProxyJump bastion\n' "$BASTION" "$BASTION_USER" >"$dir/config"
fi
cat >>"$dir/config" <<EOF
Host node
  HostName $HOST
  User $SSH_USER
Host *
  UserKnownHostsFile $dir/known_hosts
  StrictHostKeyChecking yes
  BatchMode yes
  ConnectTimeout 10
  # a node rebooting under the session may never reset it: dead after a minute without answer, 255
  ServerAliveInterval 15
  ServerAliveCountMax 4
EOF

reachable() {
  local deadline=$(($(date +%s) + 600)) error
  until error=$(ssh -F "$dir/config" node true </dev/null 2>&1); do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "no SSH to $HOST${BASTION:+ through $BASTION} after 10 minutes: $(tail -n 1 <<<"$error")" >&2
      exit 1
    fi
    sleep 5
  done
}

reachable
if [ "${RERUN:-}" != 1 ]; then
  exec ssh -F "$dir/config" node "$1"
fi
for attempt in 1 2 3; do
  code=0
  ssh -F "$dir/config" node "$1" </dev/null || code=$?
  [ "$code" = 255 ] || exit "$code"
  echo "$HOST dropped the connection, attempt $attempt: waiting for it again" >&2
  sleep 10
  reachable
done
exit 255
