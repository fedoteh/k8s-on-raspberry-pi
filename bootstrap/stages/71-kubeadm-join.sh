#!/usr/bin/env bash
set -euo pipefail

# Expects ONE of:
#   KUBEADM_JOIN_CMD="kubeadm join ... --token ... --discovery-token-ca-cert-hash sha256:..."
# OR:
#   /tmp/kubeadm-join.cmd containing the join command (one line)
#
# Tip:
#   You can generate it on pi-001 and copy it to your laptop, then set it in inventory.env temporarily.

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)."
  exit 1
fi

if [[ -f /etc/kubernetes/kubelet.conf ]]; then
  echo "This node already appears to be joined (/etc/kubernetes/kubelet.conf exists). Skipping."
  exit 0
fi

JOIN_CMD="${KUBEADM_JOIN_CMD:-}"

if [[ -z "$JOIN_CMD" && -f /tmp/kubeadm-join.cmd ]]; then
  JOIN_CMD="$(cat /tmp/kubeadm-join.cmd)"
fi

if [[ -z "$JOIN_CMD" ]]; then
  echo "No join command found."
  echo "Provide KUBEADM_JOIN_CMD env var OR create /tmp/kubeadm-join.cmd on the node."
  exit 1
fi

echo "Joining cluster..."
# shellcheck disable=SC2086
$JOIN_CMD
echo "Joined."
