# Build and Deploy Guide

## Prerequisites

### Required Tools
- Docker (for building custom application image)
- kubectl (configured to access your cluster)
- A Kubernetes cluster (v1.24+)
  - Minikube
  - Kind
  - GKE, EKS, AKS
  - On-premises cluster

### Optional Tools
- Metrics Server (for HPA)
- Prometheus Operator (for monitoring)

## Quick Start (Using Pre-built Images)

The deployment uses public container images by default, so you can deploy immediately:

```bash
# Make scripts executable
chmod +x deploy.sh test-scenarios.sh cleanup.sh

# Deploy everything
./deploy.sh

# Run tests
./test-scenarios.sh

# Cleanup when done
./cleanup.sh
```

## Building Custom Application Image (Optional)

If you want to build and use your own Python application image:

### Step 1: Build the Docker Image

```bash
cd application-code

# Build the image
docker build -t your-registry/self-healing-app:v1.0 .

# Test locally
docker run -p 8080:8080 your-registry/self-healing-app:v1.0

# Test endpoints
curl http://localhost:8080/health
curl http://localhost:8080/ready
curl http://localhost:8080/startup
```

### Step 2: Push to Registry

```bash
# Login to your registry
docker login your-registry

# Push the image
docker push your-registry/self-healing-app:v1.0
```

### Step 3: Update Deployment

Edit `advanced-app/deployment-with-probes.yaml` and replace the image:

```yaml
spec:
  containers:
  - name: app
    image: your-registry/self-healing-app:v1.0  # Update this line
```

## Manual Deployment Steps

If you prefer to deploy manually:

### 1. Create Namespace

```bash
kubectl apply -f namespace/namespace.yaml
```

### 2. Deploy Basic Application

```bash
kubectl apply -f basic-app/
```

### 3. Deploy Advanced Application

```bash
kubectl apply -f advanced-app/deployment-with-probes.yaml
kubectl apply -f advanced-app/service.yaml
kubectl apply -f advanced-app/pdb.yaml
```

### 4. Deploy HPA (requires metrics-server)

```bash
# Install metrics-server if not present
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Deploy HPA
kubectl apply -f advanced-app/hpa.yaml
```

### 5. Deploy Custom Operator

```bash
# Create CRD
kubectl apply -f operator/crd.yaml

# Create RBAC resources
kubectl apply -f operator/rbac.yaml

# Deploy operator
kubectl apply -f operator/operator-deployment.yaml

# Create custom resources
kubectl apply -f operator/custom-resource-example.yaml
```

### 6. Deploy Monitoring (optional)

```bash
# Only if Prometheus Operator is installed
kubectl apply -f monitoring/servicemonitor.yaml
kubectl apply -f monitoring/alerts.yaml
```

## Verification

### Check All Resources

```bash
kubectl get all -n self-healing
```

### Check Custom Resources

```bash
kubectl get appmonitors -n self-healing
kubectl describe appmonitor advanced-app-monitor -n self-healing
```

### Check Logs

```bash
# Application logs
kubectl logs -n self-healing -l app=advanced-app --tail=50

# Operator logs
kubectl logs -n self-healing -l app=appmonitor-operator --tail=50
```

### Access Application

```bash
# Port forward to access locally
kubectl port-forward -n self-healing svc/advanced-app-service 8080:80

# In another terminal
curl http://localhost:8080
curl http://localhost:8080/health
curl http://localhost:8080/metrics
```

## Testing Self-Healing Features

### Test 1: Liveness Probe (Pod Restart)

```bash
POD=$(kubectl get pods -n self-healing -l app=advanced-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n self-healing $POD -- kill 1
kubectl get pods -n self-healing -w
```

### Test 2: Readiness Probe (Traffic Removal)

```bash
POD=$(kubectl get pods -n self-healing -l app=advanced-app -o jsonpath='{.items[0].metadata.name}')

# Make pod unready
kubectl exec -n self-healing $POD -- touch /tmp/unhealthy

# Check endpoints (pod should be removed)
kubectl get endpoints -n self-healing advanced-app-service

# Restore readiness
kubectl exec -n self-healing $POD -- rm /tmp/unhealthy
```

### Test 3: Pod Deletion (Auto Recreation)

```bash
POD=$(kubectl get pods -n self-healing -l app=advanced-app -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod -n self-healing $POD
kubectl get pods -n self-healing -w
```

### Test 4: HPA (Autoscaling)

```bash
# Generate load
kubectl run -n self-healing load-generator \
  --image=busybox:1.28 \
  --restart=Never \
  -- /bin/sh -c "while sleep 0.01; do wget -q -O- http://advanced-app-service; done"

# Watch scaling
kubectl get hpa -n self-healing --watch

# Cleanup
kubectl delete pod load-generator -n self-healing
```

### Test 5: Operator Remediation

```bash
# Manually scale down to trigger operator
kubectl scale deployment advanced-app -n self-healing --replicas=1

# Watch operator logs
kubectl logs -n self-healing -l app=appmonitor-operator -f

# Check AppMonitor status
kubectl get appmonitors -n self-healing -o wide
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl describe pod <pod-name> -n self-healing

# Check events
kubectl get events -n self-healing --sort-by='.lastTimestamp'

# Check logs
kubectl logs <pod-name> -n self-healing
```

### Operator Not Working

```bash
# Check CRD is installed
kubectl get crd appmonitors.healing.example.com

# Check RBAC
kubectl get clusterrole appmonitor-operator
kubectl get clusterrolebinding appmonitor-operator

# Check operator logs
kubectl logs -n self-healing -l app=appmonitor-operator
```

### HPA Not Scaling

```bash
# Check metrics-server is running
kubectl get pods -n kube-system -l k8s-app=metrics-server

# Check HPA status
kubectl describe hpa advanced-app-hpa -n self-healing

# Check metrics are available
kubectl top pods -n self-healing
```

### Probes Failing

```bash
# Check probe configuration
kubectl get pod <pod-name> -n self-healing -o yaml | grep -A 10 livenessProbe

# Manually test endpoints
kubectl exec -n self-healing <pod-name> -- wget -O- localhost:8080/health
```

## Cleanup

```bash
# Use cleanup script
./cleanup.sh

# Or manually
kubectl delete namespace self-healing
kubectl delete crd appmonitors.healing.example.com
kubectl delete clusterrole appmonitor-operator
kubectl delete clusterrolebinding appmonitor-operator
```

## Advanced Configuration

### Customize Probe Timing

Edit `advanced-app/deployment-with-probes.yaml`:

```yaml
livenessProbe:
  httpGet:
    path: /live
    port: 8080
  initialDelaySeconds: 10  # Wait before first check
  periodSeconds: 10        # Check every 10 seconds
  timeoutSeconds: 5        # Timeout after 5 seconds
  failureThreshold: 3      # Fail after 3 attempts
```

### Customize Operator Behavior

Edit `operator/custom-resource-example.yaml`:

```yaml
spec:
  checkIntervalSeconds: 30      # How often to check
  failureThreshold: 3           # Failures before action
  remediationStrategy: restart  # restart, scale, or notify
  scaleUpReplicas: 2           # For scale strategy
```

### Resource Limits

Edit deployments to adjust resource limits:

```yaml
resources:
  requests:
    memory: "64Mi"
    cpu: "100m"
  limits:
    memory: "128Mi"
    cpu: "500m"
```

## Production Considerations

1. **Use proper image tags** - Don't use `latest`
2. **Set resource limits** - Prevent resource exhaustion
3. **Configure PDB** - Ensure availability during updates
4. **Enable monitoring** - Use Prometheus and Grafana
5. **Set up alerting** - Get notified of issues
6. **Use secrets** - For sensitive configuration
7. **Enable network policies** - Restrict pod communication
8. **Regular backups** - Of critical data and configurations
9. **Test disaster recovery** - Practice failure scenarios
10. **Document runbooks** - For common operations

## References

- [Kubernetes Probes Documentation](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Kubernetes Operators](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)
- [HPA Documentation](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Pod Disruption Budgets](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)
