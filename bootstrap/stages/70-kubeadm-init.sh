#!/usr/bin/env bash
set -euo pipefail

# Expects env (from run.sh / inventory.env):
#   CONTROL_PLANE_IP=192.168.86.25
#   POD_CIDR=10.244.0.0/16
#   K8S_VERSION_PKG=1.35.0-1.1  (optional; if set, we'll try to derive v1.35.0)
#
# Optional override:
#   K8S_VERSION=v1.35.0

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)."
  exit 1
fi

CONTROL_PLANE_IP="${CONTROL_PLANE_IP:-}"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"

# Prefer explicit K8S_VERSION, else attempt to derive from K8S_VERSION_PKG, else fallback.
K8S_VERSION="${K8S_VERSION:-}"
if [[ -z "$K8S_VERSION" ]]; then
  if [[ -n "${K8S_VERSION_PKG:-}" ]]; then
    # Example: 1.35.0-1.1 -> v1.35.0
    K8S_VERSION="v${K8S_VERSION_PKG%%-*}"
  else
    K8S_VERSION="v1.35.0"
  fi
fi

if [[ -z "$CONTROL_PLANE_IP" ]]; then
  echo "CONTROL_PLANE_IP is required (set it in inventory.env)."
  exit 1
fi

if [[ -f /etc/kubernetes/admin.conf ]]; then
  echo "Control plane already initialized (/etc/kubernetes/admin.conf exists). Skipping."
  exit 0
fi

echo "Initializing control plane..."
kubeadm init \
  --kubernetes-version "$K8S_VERSION" \
  --apiserver-advertise-address "$CONTROL_PLANE_IP" \
  --pod-network-cidr "$POD_CIDR"

echo
echo "NOTE: kubeadm init done."
echo "Next (on the control-plane, as your normal user):"
echo "  mkdir -p \$HOME/.kube"
echo "  sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config"
echo "  sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config"
