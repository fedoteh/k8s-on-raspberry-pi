#!/usr/bin/env bash
set -euo pipefail

if ! command -v kubectl >/dev/null; then
  echo "kubectl not found."
  exit 1
fi

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

kubectl -n kube-system patch deployment metrics-server \
  --type='json' \
  -p='[
    {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"},
    {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-preferred-address-types=InternalIP,Hostname,InternalDNS"}
  ]' || true

kubectl -n kube-system rollout status deploy/metrics-server --timeout=5m
echo "metrics-server ready."
