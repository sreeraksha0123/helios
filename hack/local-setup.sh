#!/usr/bin/env bash
# Creates a local kind cluster suitable for running the full Helios stack
# (3 nodes so PodDisruptionBudgets / anti-affinity have something to spread
# across). Requires kind + kubectl + helm installed locally.
set -euo pipefail

CLUSTER_NAME="helios-local"

if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "kind cluster '$CLUSTER_NAME' already exists, skipping creation."
else
  echo "==> Creating kind cluster '$CLUSTER_NAME'"
  kind create cluster --config "$(dirname "$0")/kind-config.yaml"
fi

echo "==> Installing metrics-server (kind doesn't ship one, and HPA needs it)"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

echo "==> kind cluster ready. Next: ./scripts/setup-dev.sh"
