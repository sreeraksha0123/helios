#!/usr/bin/env bash
# Installs Helios into the current kube-context, staging profile.
# Target: < 1 hour, including chaos-suite installation for scheduled tests.
set -euo pipefail
IMAGE_TAG="${1:-${IMAGE_TAG:-staging}}"

./scripts/setup-dev.sh   # staging reuses the dev bootstrap, then layers on:

echo "==> Installing Chaos Mesh"
helm repo add chaos-mesh https://charts.chaos-mesh.org >/dev/null
helm repo update >/dev/null
helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-mesh --create-namespace \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock \
  --wait --timeout 5m

echo "==> Applying chaos experiments and schedules"
kubectl apply -f chaos/experiments/
kubectl apply -f chaos/schedules/

echo "==> Applying values overlay for staging (values-staging.yaml, if present)"
if [ -f charts/helios-platform/values-staging.yaml ]; then
  helm upgrade helios-platform charts/helios-platform \
    -f charts/helios-platform/values-staging.yaml --reuse-values --wait
fi

echo "Staging environment ready. Run ./scripts/chaos-run.sh to trigger the suite on demand."
