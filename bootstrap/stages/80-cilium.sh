#!/usr/bin/env bash
set -euo pipefail

# Expects env:
#   CONTROL_PLANE_IP=192.168.86.25
#   CILIUM_PODCIDR_LIST=10.244.0.0/16
#   CILIUM_MASK_SIZE=24
# Optional:
#   K8S_SERVICE_PORT=6443

CONTROL_PLANE_IP="${CONTROL_PLANE_IP:-}"
CILIUM_PODCIDR_LIST="${CILIUM_PODCIDR_LIST:-${POD_CIDR:-10.244.0.0/16}}"
CILIUM_MASK_SIZE="${CILIUM_MASK_SIZE:-24}"
K8S_SERVICE_PORT="${K8S_SERVICE_PORT:-6443}"

if [[ -z "$CONTROL_PLANE_IP" ]]; then
  echo "CONTROL_PLANE_IP is required (set it in inventory.env)."
  exit 1
fi

if ! command -v helm >/dev/null; then
  echo "helm not found. Install helm first."
  exit 1
fi

if ! command -v kubectl >/dev/null; then
  echo "kubectl not found."
  exit 1
fi

helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1 || true
helm repo update >/dev/null

helm upgrade --install cilium cilium/cilium \
  --namespace kube-system \
  --create-namespace \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost="$CONTROL_PLANE_IP" \
  --set k8sServicePort="$K8S_SERVICE_PORT" \
  --set cni.binPath=/usr/lib/cni \
  --set cni.confPath=/etc/cni/net.d \
  --set ipam.mode=cluster-pool \
  --set ipam.operator.clusterPoolIPv4PodCIDRList="$CILIUM_PODCIDR_LIST" \
  --set ipam.operator.clusterPoolIPv4MaskSize="$CILIUM_MASK_SIZE"

echo "Waiting for cilium rollout..."
kubectl -n kube-system rollout status ds/cilium --timeout=5m

echo
echo "(Optional) remove kube-proxy if you want it gone:"
echo "  kubectl -n kube-system delete ds kube-proxy"
echo "  kubectl -n kube-system delete configmap kube-proxy"
