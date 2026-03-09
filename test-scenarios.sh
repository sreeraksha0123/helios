#!/bin/bash

# Self-Healing Test Scenarios
# This script demonstrates various self-healing capabilities

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}=========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=========================================${NC}\n"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to get a pod name
get_pod() {
    kubectl get pods -n self-healing -l app=advanced-app -o jsonpath='{.items[0].metadata.name}'
}

# Function to wait and show status
wait_and_show() {
    local seconds=$1
    local message=$2
    print_info "$message (waiting ${seconds}s)..."
    for i in $(seq 1 $seconds); do
        echo -n "."
        sleep 1
    done
    echo ""
}

print_header "Self-Healing Kubernetes Test Scenarios"

# Test 1: Liveness Probe - Pod Restart
print_header "Test 1: Liveness Probe Test"
print_info "This test will kill the main process in a pod to trigger liveness probe failure"
print_info "Expected: Pod should automatically restart"

POD=$(get_pod)
print_info "Target pod: $POD"

print_info "Current pod status:"
kubectl get pod $POD -n self-healing

print_info "Killing main process (PID 1)..."
kubectl exec -n self-healing $POD -- kill 1 || true

wait_and_show 30 "Waiting for pod to restart"

print_info "New pod status:"
kubectl get pods -n self-healing -l app=advanced-app

print_info "Recent events:"
kubectl get events -n self-healing --field-selector involvedObject.name=$POD --sort-by='.lastTimestamp' | tail -10

# Test 2: Readiness Probe - Traffic Removal
print_header "Test 2: Readiness Probe Test"
print_info "This test will make a pod fail readiness checks"
print_info "Expected: Pod will be removed from service endpoints but not restarted"

POD=$(get_pod)
print_info "Target pod: $POD"

print_info "Endpoints before:"
kubectl get endpoints advanced-app-service -n self-healing

print_info "Creating /tmp/unhealthy file to fail readiness probe..."
kubectl exec -n self-healing $POD -- touch /tmp/unhealthy

wait_and_show 20 "Waiting for readiness probe to fail"

print_info "Endpoints after (pod should be removed):"
kubectl get endpoints advanced-app-service -n self-healing

print_info "Pod status (should be Running but not Ready):"
kubectl get pod $POD -n self-healing

print_info "Removing unhealthy marker to restore readiness..."
kubectl exec -n self-healing $POD -- rm -f /tmp/unhealthy

wait_and_show 15 "Waiting for pod to become ready again"

print_info "Endpoints restored:"
kubectl get endpoints advanced-app-service -n self-healing

print_info "Pod status (should be Running and Ready):"
kubectl get pod $POD -n self-healing

# Test 3: Pod Deletion - Automatic Recreation
print_header "Test 3: Pod Deletion Test"
print_info "This test will delete a pod to trigger automatic recreation"
print_info "Expected: Deployment controller will create a new pod"

POD=$(get_pod)
print_info "Target pod: $POD"

print_info "Current pods:"
kubectl get pods -n self-healing -l app=advanced-app

print_info "Deleting pod..."
kubectl delete pod $POD -n self-healing

wait_and_show 25 "Waiting for new pod to be created"

print_info "New pods:"
kubectl get pods -n self-healing -l app=advanced-app

print_info "Deployment status:"
kubectl get deployment advanced-app -n self-healing

# Test 4: Resource Pressure - Pod Eviction and Recreation
print_header "Test 4: Resource Limits Test"
print_info "Checking if pods respect resource limits"

print_info "Pod resource specifications:"
kubectl get pod $(get_pod) -n self-healing -o jsonpath='{.spec.containers[0].resources}' | jq .

# Test 5: Custom Operator - AppMonitor
print_header "Test 5: Custom Operator (AppMonitor) Test"
print_info "Checking AppMonitor resources and their status"

print_info "AppMonitor resources:"
kubectl get appmonitors -n self-healing

print_info "\nDetailed AppMonitor status:"
for am in $(kubectl get appmonitors -n self-healing -o jsonpath='{.items[*].metadata.name}'); do
    echo -e "\n${YELLOW}AppMonitor: $am${NC}"
    kubectl get appmonitor $am -n self-healing -o jsonpath='{.status}' | jq .
done

# Test 6: Horizontal Pod Autoscaler
print_header "Test 6: Horizontal Pod Autoscaler Test"

if kubectl get hpa advanced-app-hpa -n self-healing &> /dev/null; then
    print_info "Current HPA status:"
    kubectl get hpa advanced-app-hpa -n self-healing
    
    print_info "\nCurrent pod count:"
    kubectl get pods -n self-healing -l app=advanced-app --no-headers | wc -l
    
    print_info "\nTo test autoscaling, generate load with:"
    echo "kubectl run -n self-healing load-generator --image=busybox:1.28 --restart=Never -- /bin/sh -c \"while sleep 0.01; do wget -q -O- http://advanced-app-service; done\""
    echo ""
    echo "Then watch the HPA scale up:"
    echo "kubectl get hpa advanced-app-hpa -n self-healing --watch"
    echo ""
    echo "Clean up load generator:"
    echo "kubectl delete pod load-generator -n self-healing"
else
    print_warning "HPA not found. Install metrics-server to enable autoscaling."
fi

# Test 7: Pod Disruption Budget
print_header "Test 7: Pod Disruption Budget Test"
print_info "Checking PDB configuration"

if kubectl get pdb advanced-app-pdb -n self-healing &> /dev/null; then
    print_info "Current PDB status:"
    kubectl get pdb advanced-app-pdb -n self-healing
    
    print_info "\nPDB details:"
    kubectl describe pdb advanced-app-pdb -n self-healing | grep -A 5 "Status:"
else
    print_warning "PDB not found"
fi

# Test 8: Rolling Update
print_header "Test 8: Rolling Update Test"
print_info "This test demonstrates zero-downtime rolling updates"

print_info "Current deployment image:"
kubectl get deployment advanced-app -n self-healing -o jsonpath='{.spec.template.spec.containers[0].image}'
echo ""

print_info "\nTo test rolling update, run:"
echo "kubectl set image deployment/advanced-app -n self-healing app=hashicorp/http-echo:0.2.4"
echo ""
echo "Watch the rolling update:"
echo "kubectl rollout status deployment/advanced-app -n self-healing"
echo ""
echo "Rollback if needed:"
echo "kubectl rollout undo deployment/advanced-app -n self-healing"

# Test 9: Check Self-Healing Events
print_header "Test 9: Self-Healing Events Summary"
print_info "Reviewing recent self-healing events"

print_info "Pod restarts in the last hour:"
kubectl get pods -n self-healing -o json | jq -r '.items[] | "\(.metadata.name): \(.status.containerStatuses[0].restartCount) restarts"'

print_info "\nRecent events (last 20):"
kubectl get events -n self-healing --sort-by='.lastTimestamp' | tail -20

# Test 10: Operator Logs
print_header "Test 10: Operator Functionality Check"
print_info "Checking operator logs for reconciliation activity"

OPERATOR_POD=$(kubectl get pods -n self-healing -l app=appmonitor-operator -o jsonpath='{.items[0].metadata.name}')

if [ ! -z "$OPERATOR_POD" ]; then
    print_info "Operator pod: $OPERATOR_POD"
    print_info "\nRecent operator logs:"
    kubectl logs -n self-healing $OPERATOR_POD --tail=30
else
    print_warning "Operator pod not found"
fi

# Summary
print_header "Test Summary"

print_info "Deployment Status:"
kubectl get deployment -n self-healing

print_info "\nPod Status:"
kubectl get pods -n self-healing

print_info "\nService Status:"
kubectl get svc -n self-healing

print_info "\nAppMonitor Status:"
kubectl get appmonitors -n self-healing 2>/dev/null || print_warning "No AppMonitors found"

print_header "Testing Complete!"

print_info "\nUseful Commands:"
echo ""
echo "Monitor pods in real-time:"
echo "  kubectl get pods -n self-healing -w"
echo ""
echo "Stream logs from all pods:"
echo "  kubectl logs -n self-healing -l app=advanced-app -f --tail=50"
echo ""
echo "Describe a specific pod:"
echo "  kubectl describe pod <pod-name> -n self-healing"
echo ""
echo "Check pod resource usage:"
echo "  kubectl top pods -n self-healing"
echo ""
echo "View all events:"
echo "  kubectl get events -n self-healing --sort-by='.lastTimestamp'"
echo ""

print_info "All tests completed successfully!"
