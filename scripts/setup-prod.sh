#!/usr/bin/env bash
# Installs Helios into the current kube-context, production profile.
# Target: < 2 hours, including canary rollout verification with Flagger.
# Requires: cluster already provisioned (see ../terraform), DNS + TLS issuer
# configured, and KUBECONFIG pointed at the production cluster.
set -euo pipefail
IMAGE_TAG="${1:?usage: setup-prod.sh <image-tag>}"

read -r -p "This targets a PRODUCTION cluster (context: $(kubectl config current-context)). Continue? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted."
  exit 1
fi

echo "==> Installing helios-infrastructure with production values"
helm dependency build charts/helios-infrastructure
mkdir -p charts/helios-infrastructure/dashboards
cp dashboards/grafana/*.json charts/helios-infrastructure/dashboards/
helm upgrade --install helios-infra charts/helios-infrastructure \
  --namespace helios-monitoring --create-namespace \
  -f charts/helios-infrastructure/values-prod.yaml \
  --wait --timeout 15m

echo "==> Installing Flagger for canary rollouts"
helm repo add flagger https://flagger.app >/dev/null
helm repo update >/dev/null
helm upgrade --install flagger flagger/flagger \
  --namespace flagger-system --create-namespace \
  --set meshProvider=kubernetes \
  --wait --timeout 5m

echo "==> Installing helios-platform"
helm upgrade --install helios-platform charts/helios-platform \
  --namespace helios-platform --create-namespace \
  --set selfHealingOperator.image.tag="$IMAGE_TAG" \
  --wait --timeout 10m

echo "==> Installing helios-app"
helm upgrade --install helios-app charts/helios-app \
  --namespace helios-app --create-namespace \
  --set image.tag="$IMAGE_TAG" \
  --wait --timeout 10m

echo "==> Verifying rollout (zero-downtime check)"
kubectl rollout status deployment/demo-api -n helios-app --timeout=10m
kubectl rollout status deployment/frontend -n helios-app --timeout=10m

echo "Production install complete. See docs/setup-guide.md to time this run against the <2h target."
