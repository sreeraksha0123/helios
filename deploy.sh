#!/bin/bash

# Self-Healing Kubernetes Application Deployment Script
# This script deploys all components of the self-healing demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please install kubectl first."
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi

print_info "Starting deployment of Self-Healing Kubernetes Applications..."

# Step 1: Create namespace
print_info "Creating namespace..."
kubectl apply -f namespace/namespace.yaml
sleep 2

# Step 2: Deploy basic application
print_info "Deploying basic application..."
kubectl apply -f basic-app/configmap.yaml
kubectl apply -f basic-app/deployment.yaml
kubectl apply -f basic-app/service.yaml
sleep 3

# Step 3: Deploy advanced application with probes
print_info "Deploying advanced application with probes..."
kubectl apply -f advanced-app/deployment-with-probes.yaml
kubectl apply -f advanced-app/service.yaml
kubectl apply -f advanced-app/pdb.yaml
sleep 3

# Step 4: Deploy HPA (requires metrics-server)
if kubectl get apiservice v1beta1.metrics.k8s.io &> /dev/null; then
    print_info "Deploying Horizontal Pod Autoscaler..."
    kubectl apply -f advanced-app/hpa.yaml
else
    print_warning "Metrics server not found. Skipping HPA deployment."
    print_warning "To enable HPA, install metrics-server: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
fi

# Step 5: Deploy Operator
print_info "Deploying Custom Resource Definition..."
kubectl apply -f operator/crd.yaml
sleep 2

print_info "Deploying Operator RBAC..."
kubectl apply -f operator/rbac.yaml
sleep 2

print_info "Deploying Operator..."
kubectl apply -f operator/operator-deployment.yaml
sleep 5

# Step 6: Deploy Custom Resources
print_info "Deploying AppMonitor Custom Resources..."
kubectl apply -f operator/custom-resource-example.yaml
sleep 2

# Step 7: Deploy monitoring (optional)
if kubectl get crd servicemonitors.monitoring.coreos.com &> /dev/null; then
    print_info "Deploying ServiceMonitor and PrometheusRule..."
    kubectl apply -f monitoring/servicemonitor.yaml
    kubectl apply -f monitoring/alerts.yaml
else
    print_warning "Prometheus Operator not found. Skipping monitoring deployment."
    print_warning "To enable monitoring, install Prometheus Operator first."
fi

# Wait for deployments to be ready
print_info "Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/basic-app -n self-healing || print_warning "basic-app deployment timeout"
kubectl wait --for=condition=available --timeout=120s deployment/advanced-app -n self-healing || print_warning "advanced-app deployment timeout"
kubectl wait --for=condition=available --timeout=120s deployment/appmonitor-operator -n self-healing || print_warning "operator deployment timeout"

# Display status
print_info "\n========================================="
print_info "Deployment Complete!"
print_info "=========================================\n"

print_info "Checking deployment status..."
kubectl get all -n self-healing

print_info "\nChecking Custom Resources..."
kubectl get appmonitors -n self-healing

print_info "\n========================================="
print_info "Next Steps:"
print_info "=========================================\n"

echo "1. Watch pods:"
echo "   kubectl get pods -n self-healing -w"
echo ""
echo "2. Test liveness probe (pod will restart):"
echo "   POD=\$(kubectl get pods -n self-healing -l app=advanced-app -o jsonpath='{.items[0].metadata.name}')"
echo "   kubectl exec -n self-healing \$POD -- kill 1"
echo ""
echo "3. Check events:"
echo "   kubectl get events -n self-healing --sort-by='.lastTimestamp'"
echo ""
echo "4. View logs:"
echo "   kubectl logs -n self-healing -l app=advanced-app --tail=50 -f"
echo ""
echo "5. Access application (port-forward):"
echo "   kubectl port-forward -n self-healing svc/advanced-app-service 8080:80"
echo "   curl http://localhost:8080"
echo ""
echo "6. Check AppMonitor status:"
echo "   kubectl get appmonitors -n self-healing -o wide"
echo "   kubectl describe appmonitor advanced-app-monitor -n self-healing"
echo ""

print_info "Deployment script completed successfully!"
