#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y containerd containernetworking-plugins

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# idempotent replace
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl enable --now containerd
systemctl restart containerd
