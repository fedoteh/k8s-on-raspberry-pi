#!/usr/bin/env bash
set -euo pipefail

INV="${INV:-$(cd "$(dirname "$0")" && pwd)/inventory.env}"
BOOTSTRAP_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGES_DIR="$BOOTSTRAP_DIR/stages"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <host> <stage> [stage...]"
  echo "Example: $0 pi-002.local 10-os 20-cgroups 30-swapoff"
  exit 1
fi

HOST="$1"; shift
STAGES=("$@")

# shellcheck disable=SC1090
source "$INV"

SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$HOME/.ssh/known_hosts")

run_stage() {
  local stage="$1"
  local file="$STAGES_DIR/${stage}.sh"

  if [[ ! -f "$file" ]]; then
    echo "Stage not found: $file"
    exit 1
  fi

  echo
  echo "==> [$HOST] stage: $stage"

  # push + run
  scp "${SSH_OPTS[@]}" "$file" "${SSH_USER}@${HOST}:/tmp/${stage}.sh" >/dev/null

  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${HOST}" \
    "export CONTROL_PLANE_HOST='${CONTROL_PLANE_HOST}' CONTROL_PLANE_IP='${CONTROL_PLANE_IP}' \
            POD_CIDR='${POD_CIDR}' CILIUM_PODCIDR_LIST='${CILIUM_PODCIDR_LIST}' CILIUM_MASK_SIZE='${CILIUM_MASK_SIZE}' \
            K8S_DEB_CHANNEL='${K8S_DEB_CHANNEL}' K8S_VERSION_PKG='${K8S_VERSION_PKG}' \
     && sudo bash /tmp/${stage}.sh"
}

for s in "${STAGES[@]}"; do
  run_stage "$s"
done

echo
echo "==> [$HOST] done."
