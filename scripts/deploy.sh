#!/usr/bin/env bash
# Deploys a specific image tag to a target environment. Used by
# .github/workflows/cd.yml, but safe to run manually:
#   ./scripts/deploy.sh staging abc1234
set -euo pipefail
ENVIRONMENT="${1:?usage: deploy.sh <staging|production> <image-tag>}"
IMAGE_TAG="${2:?usage: deploy.sh <staging|production> <image-tag>}"

VALUES_FILE="charts/helios-app/values-${ENVIRONMENT}.yaml"
EXTRA_ARGS=()
if [ -f "$VALUES_FILE" ]; then
  EXTRA_ARGS+=(-f "$VALUES_FILE")
fi

echo "==> Deploying image tag '$IMAGE_TAG' to '$ENVIRONMENT'"

helm upgrade --install helios-platform charts/helios-platform \
  --namespace helios-platform --create-namespace \
  --set selfHealingOperator.image.tag="$IMAGE_TAG" \
  --wait --timeout 10m

helm upgrade --install helios-app charts/helios-app \
  --namespace helios-app --create-namespace \
  --set image.tag="$IMAGE_TAG" \
  "${EXTRA_ARGS[@]}" \
  --wait --timeout 10m

echo "==> Recording current image as previous-revision for auto-rollback"
kubectl annotate deployment demo-api -n helios-app \
  helios.io/previous-revision-image="ghcr.io/helios/demo-api:${IMAGE_TAG}" --overwrite
kubectl annotate deployment frontend -n helios-app \
  helios.io/previous-revision-image="ghcr.io/helios/frontend:${IMAGE_TAG}" --overwrite

echo "Deploy to $ENVIRONMENT complete."
