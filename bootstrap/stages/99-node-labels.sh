#!/usr/bin/env bash
set -euo pipefail

if ! command -v kubectl >/dev/null; then
  echo "kubectl not found."
  exit 1
fi

# Allow override via env if you ever add nodes:
#   WORKER_NODES="pi-002 pi-003 pi-004"
WORKER_NODES="${WORKER_NODES:-pi-002 pi-003}"

for n in $WORKER_NODES; do
  echo "Labeling ${n} as worker..."
  kubectl label node "$n" node-role.kubernetes.io/worker=worker --overwrite
done

echo "Done."
kubectl get nodes
