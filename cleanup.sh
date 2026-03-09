#!/bin/bash

# Cleanup script for Self-Healing Kubernetes Applications

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info "Starting cleanup of Self-Healing Kubernetes Applications..."

# Delete namespace (this will delete everything in it)
print_info "Deleting namespace 'self-healing'..."
kubectl delete namespace self-healing --ignore-not-found=true

# Delete CRD (this persists outside namespace)
print_info "Deleting Custom Resource Definition..."
kubectl delete crd appmonitors.healing.example.com --ignore-not-found=true

# Delete ClusterRole and ClusterRoleBinding
print_info "Deleting cluster-wide RBAC resources..."
kubectl delete clusterrole appmonitor-operator --ignore-not-found=true
kubectl delete clusterrolebinding appmonitor-operator --ignore-not-found=true

print_info "Waiting for namespace deletion to complete..."
kubectl wait --for=delete namespace/self-healing --timeout=60s || print_warning "Namespace deletion timeout (may still be cleaning up)"

print_info "Cleanup complete!"
print_info "All resources have been removed from the cluster."
