# Self-Healing Kubernetes Applications

A comprehensive demonstration of Kubernetes self-healing mechanisms including readiness/liveness probes, Horizontal Pod Autoscaling, Pod Disruption Budgets, and a custom Kubernetes Operator for advanced application health management.

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Documentation](#detailed-documentation)
- [Testing Self-Healing](#testing-self-healing)
- [Monitoring](#monitoring)
- [Cleanup](#cleanup)

## 🎯 Overview

This project demonstrates four layers of self-healing in Kubernetes:

1. **Container-Level**: Startup, Liveness, and Readiness probes
2. **Pod-Level**: ReplicaSet automatic pod recreation
3. **Application-Level**: Horizontal Pod Autoscaling (HPA) and Pod Disruption Budgets (PDB)
4. **Custom-Level**: Kubernetes Operator with custom remediation strategies

## ✨ Features

### Health Probes
- ✅ **Startup Probes** - For slow-starting applications
- ✅ **Liveness Probes** - Automatic container restart on failure
- ✅ **Readiness Probes** - Traffic management based on health

### Kubernetes Native
- ✅ **ReplicaSet** - Maintains desired pod count
- ✅ **Deployment** - Rolling updates with zero downtime
- ✅ **HPA** - Auto-scaling based on CPU/Memory
- ✅ **PDB** - Ensures availability during disruptions

### Custom Operator
- ✅ **AppMonitor CRD** - Custom resource definition
- ✅ **Three Remediation Strategies**:
  - Restart: Rolling restart of deployments
  - Scale: Increase replica count
  - Notify: Webhook notifications
- ✅ **Status Tracking** - Real-time health status updates

### Production Ready
- ✅ Resource limits and requests
- ✅ Security contexts (non-root users)
- ✅ Pod anti-affinity rules
- ✅ Network policies
- ✅ Prometheus monitoring integration

## 📁 Project Structure

```
self-healing-k8s/
├── 📄 README.md                          # This file
├── 📄 BUILD_AND_DEPLOY.md               # Detailed deployment guide
├── 📄 ARCHITECTURE.md                    # Architecture documentation
├── 🔧 deploy.sh                          # Automated deployment script
├── 🔧 test-scenarios.sh                  # Testing script (10 scenarios)
├── 🔧 cleanup.sh                         # Cleanup script
│
├── 📁 namespace/
│   └── namespace.yaml                    # Namespace definition
│
├── 📁 basic-app/                         # Simple application (no probes)
│   ├── configmap.yaml                    # Application configuration
│   ├── deployment.yaml                   # Basic deployment
│   └── service.yaml                      # Service definition
│
├── 📁 advanced-app/                      # Advanced self-healing app
│   ├── deployment-with-probes.yaml       # Full probe configuration
│   ├── service.yaml                      # Service definition
│   ├── hpa.yaml                          # Horizontal Pod Autoscaler
│   └── pdb.yaml                          # Pod Disruption Budget
│
├── 📁 operator/                          # Custom Kubernetes Operator
│   ├── crd.yaml                          # Custom Resource Definition
│   ├── rbac.yaml                         # RBAC configuration
│   ├── operator-deployment.yaml          # Operator deployment + code
│   └── custom-resource-example.yaml      # AppMonitor CR examples
│
├── 📁 monitoring/                        # Prometheus integration
│   ├── servicemonitor.yaml               # ServiceMonitor resource
│   └── alerts.yaml                       # PrometheusRule alerts
│
├── 📁 application-code/                  # Sample Python application
│   ├── app.py                            # Flask app with health endpoints
│   ├── requirements.txt                  # Python dependencies
│   └── Dockerfile                        # Container image definition
│
└── 📁 examples/
    └── complete-example.yaml             # Fully documented example
```

## 📦 Prerequisites

### Required
- **Kubernetes cluster** (v1.24+)
  - Minikube, Kind, Docker Desktop, or cloud-managed cluster (GKE, EKS, AKS)
- **kubectl** - Configured to access your cluster
- **Bash shell** - For running scripts

### Optional
- **Docker** - For building custom application images
- **Metrics Server** - Required for HPA (auto-scaling)
- **Prometheus Operator** - For monitoring integration

### Install Metrics Server (for HPA)
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

## 🚀 Quick Start

### 1. Clone and Setup
```bash
# Navigate to project directory
cd self-healing-k8s

# Make scripts executable
chmod +x deploy.sh test-scenarios.sh cleanup.sh
```

### 2. Deploy Everything
```bash
# Deploy all components
./deploy.sh
```

This script will:
- ✅ Create the namespace
- ✅ Deploy basic application
- ✅ Deploy advanced application with probes
- ✅ Configure HPA and PDB
- ✅ Install Custom Resource Definition
- ✅ Deploy the operator
- ✅ Create AppMonitor resources
- ✅ Setup monitoring (if Prometheus Operator is available)

### 3. Verify Deployment
```bash
# Check all resources
kubectl get all -n self-healing

# Check custom resources
kubectl get appmonitors -n self-healing

# Check pod status
kubectl get pods -n self-healing -w
```

### 4. Run Tests
```bash
# Execute all test scenarios
./test-scenarios.sh
```

## 📚 Detailed Documentation

### For Deployment Instructions
See [BUILD_AND_DEPLOY.md](BUILD_AND_DEPLOY.md) for:
- Manual deployment steps
- Building custom images
- Configuration options
- Troubleshooting guide

### For Architecture Details
See [ARCHITECTURE.md](ARCHITECTURE.md) for:
- System architecture diagrams
- Self-healing mechanisms explained
- Probe configuration best practices
- Operator design patterns
- Performance optimization
- Security considerations

### For Complete Examples
See [examples/complete-example.yaml](examples/complete-example.yaml) for:
- Fully documented YAML with inline comments
- Production-ready configuration
- All self-healing features in one file

## 🧪 Testing Self-Healing

### Automated Testing
Run the comprehensive test suite:
```bash
./test-scenarios.sh
```

This includes 10 test scenarios:
1. ✅ Liveness Probe Test (pod restart)
2. ✅ Readiness Probe Test (traffic removal)
3. ✅ Pod Deletion Test (auto-recreation)
4. ✅ Resource Limits Test
5. ✅ Custom Operator Test
6. ✅ HPA Autoscaling Test
7. ✅ Pod Disruption Budget Test
8. ✅ Rolling Update Test
9. ✅ Self-Healing Events Summary
10. ✅ Operator Functionality Check

### Manual Testing

#### Test 1: Liveness Probe (Pod Restart)
```bash
# Get pod name
POD=$(kubectl get pods -n self-healing -l app=advanced-app -o jsonpath='{.items[0].metadata.name}')

# Kill main process (triggers liveness probe failure)
kubectl exec -n self-healing $POD -- kill 1

# Watch pod restart
kubectl get pods -n self-healing -w
```

#### Test 2: Readiness Probe (Traffic Removal)
```bash
POD=$(kubectl get pods -n self-healing -l app=advanced-app -o jsonpath='{.items[0].metadata.name}')

# Check endpoints before
kubectl get endpoints -n self-healing advanced-app-service

# Make pod unhealthy (fails readiness probe)
kubectl exec -n self-healing $POD -- touch /tmp/unhealthy

# Wait 10 seconds, then check endpoints (pod should be removed)
kubectl get endpoints -n self-healing advanced-app-service

# Restore health
kubectl exec -n self-healing $POD -- rm /tmp/unhealthy
```

#### Test 3: Pod Deletion (Auto-Recreation)
```bash
POD=$(kubectl get pods -n self-healing -l app=advanced-app -o jsonpath='{.items[0].metadata.name}')

# Delete pod
kubectl delete pod -n self-healing $POD

# Watch new pod being created
kubectl get pods -n self-healing -w
```

#### Test 4: Autoscaling (HPA)
```bash
# Generate load
kubectl run -n self-healing load-generator \
  --image=busybox:1.28 \
  --restart=Never \
  -- /bin/sh -c "while sleep 0.01; do wget -q -O- http://advanced-app-service; done"

# Watch HPA scale up
kubectl get hpa -n self-healing --watch

# Cleanup
kubectl delete pod load-generator -n self-healing
```

#### Test 5: Custom Operator Remediation
```bash
# Watch operator logs
kubectl logs -n self-healing -l app=appmonitor-operator -f

# Manually scale down to trigger operator
kubectl scale deployment advanced-app -n self-healing --replicas=1

# Check AppMonitor status
kubectl get appmonitors -n self-healing -o wide
```

## 📊 Monitoring

### Check Status
```bash
# View all resources
kubectl get all -n self-healing

# Watch pods in real-time
kubectl get pods -n self-healing -w

# Check AppMonitor status
kubectl get appmonitors -n self-healing

# View recent events
kubectl get events -n self-healing --sort-by='.lastTimestamp' | tail -20
```

### View Logs
```bash
# Application logs
kubectl logs -n self-healing -l app=advanced-app --tail=50 -f

# Operator logs
kubectl logs -n self-healing -l app=appmonitor-operator --tail=50 -f

# Specific pod logs
kubectl logs -n self-healing <pod-name>
```

### Access Application
```bash
# Port forward to access locally
kubectl port-forward -n self-healing svc/advanced-app-service 8080:80

# In another terminal, test endpoints
curl http://localhost:8080
curl http://localhost:8080/health
curl http://localhost:8080/status
```

### Check Resource Usage
```bash
# Pod resource usage (requires metrics-server)
kubectl top pods -n self-healing

# Node resource usage
kubectl top nodes
```

### Prometheus Metrics
If Prometheus Operator is installed:
```bash
# Check ServiceMonitor
kubectl get servicemonitor -n self-healing

# Check PrometheusRule
kubectl get prometheusrule -n self-healing
```

## 🧹 Cleanup

### Quick Cleanup
```bash
# Use cleanup script (removes everything)
./cleanup.sh
```

### Manual Cleanup
```bash
# Delete namespace (removes most resources)
kubectl delete namespace self-healing

# Delete cluster-wide resources
kubectl delete crd appmonitors.healing.example.com
kubectl delete clusterrole appmonitor-operator
kubectl delete clusterrolebinding appmonitor-operator
```

## 🔧 Configuration

### Customize Probe Timing
Edit `advanced-app/deployment-with-probes.yaml`:
```yaml
livenessProbe:
  initialDelaySeconds: 10  # Wait before first check
  periodSeconds: 10        # Check interval
  timeoutSeconds: 5        # Timeout per check
  failureThreshold: 3      # Failures before restart
```

### Customize Autoscaling
Edit `advanced-app/hpa.yaml`:
```yaml
spec:
  minReplicas: 3           # Minimum pods
  maxReplicas: 10          # Maximum pods
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        averageUtilization: 70  # Scale at 70% CPU
```

### Customize Operator Behavior
Edit `operator/custom-resource-example.yaml`:
```yaml
spec:
  checkIntervalSeconds: 30      # Health check frequency
  failureThreshold: 3           # Failures before action
  remediationStrategy: restart  # restart | scale | notify
  scaleUpReplicas: 2           # Pods to add (scale strategy)
```

## 🐛 Troubleshooting

### Pods Not Starting
```bash
# Describe pod to see events
kubectl describe pod <pod-name> -n self-healing

# Check logs
kubectl logs <pod-name> -n self-healing

# Common issues:
# - Image pull errors
# - Resource constraints
# - Probe misconfiguration
```

### HPA Not Working
```bash
# Check metrics-server is running
kubectl get pods -n kube-system -l k8s-app=metrics-server

# Verify metrics are available
kubectl top pods -n self-healing

# Check HPA status
kubectl describe hpa advanced-app-hpa -n self-healing
```

### Operator Not Working
```bash
# Check CRD exists
kubectl get crd appmonitors.healing.example.com

# Check operator pod
kubectl get pods -n self-healing -l app=appmonitor-operator

# View operator logs
kubectl logs -n self-healing -l app=appmonitor-operator --tail=100

# Check RBAC permissions
kubectl auth can-i list deployments \
  --as=system:serviceaccount:self-healing:appmonitor-operator
```

## 📖 Additional Resources

### Kubernetes Documentation
- [Configure Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Pod Disruption Budgets](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)
- [Custom Resources](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/)
- [Operator Pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)

### Project Files
- [BUILD_AND_DEPLOY.md](BUILD_AND_DEPLOY.md) - Comprehensive deployment guide
- [ARCHITECTURE.md](ARCHITECTURE.md) - Detailed architecture documentation
- [examples/complete-example.yaml](examples/complete-example.yaml) - Annotated example

## 🤝 Contributing

Feel free to extend this project with:
- Additional remediation strategies
- More sophisticated health checks
- Integration with other monitoring systems
- Advanced scheduling scenarios
- Chaos engineering tests


## 💡 Key Takeaways

1. **Multiple Layers**: Combine native Kubernetes features with custom logic
2. **Probes Are Critical**: Proper configuration prevents cascading failures
3. **Resource Limits**: Essential for HPA and stability
4. **Operators Extend K8s**: Build domain-specific healing logic
5. **Test Everything**: Use the provided test scenarios regularly

---

**Happy Self-Healing! 🚀**

For questions or issues, refer to the troubleshooting section or detailed documentation files.
