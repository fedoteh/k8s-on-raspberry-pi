#!/usr/bin/env bash
set -euo pipefail

swapoff -a || true

# mask zram swap if present
systemctl mask dev-zram0.swap 2>/dev/null || true
systemctl mask rpi-zram-writeback.timer 2>/dev/null || true
systemctl mask rpi-zram-writeback.service 2>/dev/null || true

echo "Swap disabled. Reboot recommended."
