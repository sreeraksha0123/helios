#!/usr/bin/env bash
# Installs Helios into the current kube-context, dev profile.
# Target: < 30 minutes on a small (kind/minikube/3-node) cluster.
set -euo pipefail

NAMESPACE_MONITORING="helios-monitoring"
NAMESPACE_PLATFORM="helios-platform"
NAMESPACE_APP="helios-app"
IMAGE_TAG="${IMAGE_TAG:-dev}"

echo "==> [1/5] Adding Helm repositories"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo add jetstack https://charts.jetstack.io >/dev/null
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null
helm repo update >/dev/null

echo "==> [2/5] Building chart dependencies"
helm dependency build charts/helios-infrastructure

echo "==> [3/5] Installing helios-infrastructure (Prometheus, Grafana, Loki, cert-manager, ingress-nginx)"
mkdir -p charts/helios-infrastructure/dashboards
cp dashboards/grafana/*.json charts/helios-infrastructure/dashboards/
helm upgrade --install helios-infra charts/helios-infrastructure \
  --namespace "$NAMESPACE_MONITORING" --create-namespace \
  --set kube-prometheus-stack.grafana.adminPassword="dev-only-not-secure" \
  --wait --timeout 10m

echo "==> [4/5] Installing helios-platform (self-healing operator)"
helm upgrade --install helios-platform charts/helios-platform \
  --namespace "$NAMESPACE_PLATFORM" --create-namespace \
  --set selfHealingOperator.image.tag="$IMAGE_TAG" \
  --wait --timeout 5m

echo "==> [5/5] Installing helios-app (demo-api, demo-worker, frontend + HPA/VPA/KEDA)"
helm upgrade --install helios-app charts/helios-app \
  --namespace "$NAMESPACE_APP" --create-namespace \
  --set image.tag="$IMAGE_TAG" \
  --wait --timeout 5m

echo ""
echo "Helios (dev) is installed."
echo "Grafana:    kubectl port-forward -n $NAMESPACE_MONITORING svc/helios-grafana 3000:80"
echo "Prometheus: kubectl port-forward -n $NAMESPACE_MONITORING svc/helios-prom-kube-promet-prometheus 9090:9090"
