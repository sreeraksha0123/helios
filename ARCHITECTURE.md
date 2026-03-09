# Architecture Overview

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                           │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              Namespace: self-healing                        │ │
│  │                                                              │ │
│  │  ┌──────────────────┐      ┌──────────────────┐           │ │
│  │  │  Basic App       │      │  Advanced App    │           │ │
│  │  │  Deployment      │      │  Deployment      │           │ │
│  │  │  (2 replicas)    │      │  (3 replicas)    │           │ │
│  │  │                  │      │                  │           │ │
│  │  │  ┌────┐ ┌────┐  │      │  ┌────┐ ┌────┐  │           │ │
│  │  │  │Pod1│ │Pod2│  │      │  │Pod1│ │Pod2│  │           │ │
│  │  │  └────┘ └────┘  │      │  └────┘ └────┘  │           │ │
│  │  │                  │      │     ┌────┐      │           │ │
│  │  │  No probes       │      │     │Pod3│      │           │ │
│  │  └──────────────────┘      │     └────┘      │           │ │
│  │                            │                  │           │ │
│  │                            │  ┌──────────┐   │           │ │
│  │                            │  │ Startup  │   │           │ │
│  │                            │  │ Liveness │   │           │ │
│  │                            │  │ Readiness│   │           │ │
│  │                            │  └──────────┘   │           │ │
│  │                            └──────────────────┘           │ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────┐   │ │
│  │  │          AppMonitor Operator                      │   │ │
│  │  │                                                    │   │ │
│  │  │  ┌────────────────────────────────────────────┐  │   │ │
│  │  │  │  Controller Loop                           │  │   │ │
│  │  │  │  - Watches AppMonitor CRs                  │  │   │ │
│  │  │  │  - Monitors deployment health              │  │   │ │
│  │  │  │  - Triggers remediation                    │  │   │ │
│  │  │  │  - Updates status                          │  │   │ │
│  │  │  └────────────────────────────────────────────┘  │   │ │
│  │  └──────────────────────────────────────────────────┘   │ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────┐   │ │
│  │  │          Custom Resources (CRs)                   │   │ │
│  │  │                                                    │   │ │
│  │  │  AppMonitor: advanced-app-monitor                │   │ │
│  │  │    - Target: advanced-app                        │   │ │
│  │  │    - Strategy: restart                           │   │ │
│  │  │                                                    │   │ │
│  │  │  AppMonitor: basic-app-monitor                   │   │ │
│  │  │    - Target: basic-app                           │   │ │
│  │  │    - Strategy: scale                             │   │ │
│  │  └──────────────────────────────────────────────────┘   │ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────┐   │ │
│  │  │    Horizontal Pod Autoscaler (HPA)               │   │ │
│  │  │    - Min replicas: 3                             │   │ │
│  │  │    - Max replicas: 10                            │   │ │
│  │  │    - CPU target: 70%                             │   │ │
│  │  │    - Memory target: 80%                          │   │ │
│  │  └──────────────────────────────────────────────────┘   │ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────┐   │ │
│  │  │    Pod Disruption Budget (PDB)                   │   │ │
│  │  │    - Min available: 2                            │   │ │
│  │  │    - Prevents excessive disruption               │   │ │
│  │  └──────────────────────────────────────────────────┘   │ │
│  │                                                            │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │         Control Plane Components                        │ │
│  │                                                          │ │
│  │  - API Server                                           │ │
│  │  - Controller Manager (ReplicaSet, Deployment)         │ │
│  │  - Scheduler                                            │ │
│  │  - Metrics Server (for HPA)                            │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

## Self-Healing Mechanisms

### 1. Container-Level Self-Healing

#### Liveness Probe
- **Purpose**: Detects if a container is alive
- **Action**: Restarts the container if probe fails
- **Use Case**: Deadlocks, infinite loops, unresponsive processes

```yaml
livenessProbe:
  httpGet:
    path: /live
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 10
  failureThreshold: 3
```

**Flow:**
```
Container Running → Liveness Check → Failed → Retry (3x) → Restart Container
```

#### Readiness Probe
- **Purpose**: Determines if container can accept traffic
- **Action**: Removes pod from service endpoints if probe fails
- **Use Case**: Temporary unavailability, initialization, maintenance

```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
  failureThreshold: 2
```

**Flow:**
```
Container Running → Readiness Check → Failed → Remove from Service → Keep Checking
                                    → Success → Add to Service
```

#### Startup Probe
- **Purpose**: Indicates when application has started
- **Action**: Disables liveness/readiness until startup succeeds
- **Use Case**: Slow-starting applications

```yaml
startupProbe:
  httpGet:
    path: /startup
    port: 8080
  periodSeconds: 5
  failureThreshold: 12  # 60 seconds total
```

**Flow:**
```
Container Start → Startup Check → Failed → Retry (12x) → Kill Container
                                → Success → Enable Liveness/Readiness
```

### 2. Pod-Level Self-Healing

#### ReplicaSet Controller
- **Purpose**: Maintains desired number of pod replicas
- **Action**: Creates new pods if any are deleted or failed
- **Automatic**: Built-in Kubernetes functionality

**Flow:**
```
Pod Deleted/Failed → Controller Detects → Creates New Pod → Schedules → Running
```

#### Deployment Controller
- **Purpose**: Manages rolling updates and rollbacks
- **Action**: Ensures smooth updates with zero downtime
- **Features**: 
  - RollingUpdate strategy
  - MaxSurge and MaxUnavailable controls
  - Automatic rollback on failure

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 1
```

**Flow:**
```
Update Triggered → Create New Pod → Wait Ready → Delete Old Pod → Repeat
                                  → Failure → Rollback
```

### 3. Application-Level Self-Healing

#### Horizontal Pod Autoscaler (HPA)
- **Purpose**: Scales pods based on resource utilization
- **Action**: Adds/removes pods automatically
- **Metrics**: CPU, Memory, Custom metrics

```yaml
metrics:
- type: Resource
  resource:
    name: cpu
    target:
      type: Utilization
      averageUtilization: 70
```

**Flow:**
```
High Load → Metrics Exceed Target → Scale Up Pods → Load Distributed
Low Load → Metrics Below Target → Scale Down Pods → Resources Saved
```

#### Pod Disruption Budget (PDB)
- **Purpose**: Ensures minimum availability during voluntary disruptions
- **Action**: Prevents too many pods from being evicted simultaneously
- **Use Case**: Node maintenance, cluster upgrades

```yaml
spec:
  minAvailable: 2
```

**Flow:**
```
Eviction Request → Check PDB → Allowed → Evict Pod
                             → Denied → Wait for Safe Time
```

### 4. Custom Self-Healing (Operator Pattern)

#### AppMonitor Operator
- **Purpose**: Custom health monitoring and remediation
- **Action**: Executes custom healing strategies
- **Strategies**:
  - **Restart**: Rolling restart of deployment
  - **Scale**: Increase replica count
  - **Notify**: Send alerts to external systems

**Architecture:**
```
┌─────────────────────────────────────────────────┐
│           AppMonitor Operator                    │
│                                                   │
│  ┌────────────────────────────────────────────┐ │
│  │  Watch Loop                                 │ │
│  │  - Monitor AppMonitor CRs                   │ │
│  │  - Detect changes (ADDED, MODIFIED, DELETED)│ │
│  └────────────────────────────────────────────┘ │
│                     ↓                            │
│  ┌────────────────────────────────────────────┐ │
│  │  Reconciliation Loop                        │ │
│  │  1. Get target deployment                   │ │
│  │  2. Check health status                     │ │
│  │  3. Compare with thresholds                 │ │
│  │  4. Execute remediation if needed           │ │
│  │  5. Update CR status                        │ │
│  └────────────────────────────────────────────┘ │
│                     ↓                            │
│  ┌────────────────────────────────────────────┐ │
│  │  Remediation Actions                        │ │
│  │  - Restart: Update deployment annotation    │ │
│  │  - Scale: Increase replicas                 │ │
│  │  - Notify: POST to webhook                  │ │
│  └────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

**Custom Resource Example:**
```yaml
apiVersion: healing.example.com/v1
kind: AppMonitor
metadata:
  name: my-app-monitor
spec:
  targetDeployment: my-app
  healthCheckEndpoint: /health
  failureThreshold: 3
  remediationStrategy: restart
status:
  state: Healthy
  consecutiveFailures: 0
  lastCheckTime: "2025-01-15T10:30:00Z"
```

## Component Interactions

### Scenario 1: Pod Crashes

```
1. Container crashes
   ↓
2. Kubelet detects (liveness probe fails)
   ↓
3. Kubelet restarts container
   ↓
4. Startup probe begins checking
   ↓
5. Startup succeeds → Liveness/Readiness enabled
   ↓
6. Readiness succeeds → Added to service
```

### Scenario 2: Node Failure

```
1. Node becomes unreachable
   ↓
2. Node marked as NotReady
   ↓
3. Pods marked for eviction (5 min timeout)
   ↓
4. PDB checked → Ensure minimum availability
   ↓
5. ReplicaSet controller creates new pods
   ↓
6. Scheduler places pods on healthy nodes
   ↓
7. New pods start and become ready
```

### Scenario 3: High Load

```
1. Application load increases
   ↓
2. CPU/Memory metrics rise
   ↓
3. Metrics Server collects data
   ↓
4. HPA evaluates metrics
   ↓
5. Target threshold exceeded
   ↓
6. HPA increases replica count
   ↓
7. New pods created and scheduled
   ↓
8. Load distributed across pods
```

### Scenario 4: Custom Remediation

```
1. AppMonitor checks deployment health
   ↓
2. Detects fewer ready replicas than desired
   ↓
3. Consecutive failures reach threshold
   ↓
4. Operator executes remediation strategy
   ↓
5a. Restart: Adds annotation to trigger rollout
5b. Scale: Increases replica count
5c. Notify: Sends webhook notification
   ↓
6. Updates AppMonitor status
   ↓
7. Creates Kubernetes event
```

## Failure Detection Timeline

```
Time (s)  │ Event
──────────┼────────────────────────────────────────────────
0         │ Container starts
5         │ Readiness probe begins
10        │ Liveness probe begins
15        │ First readiness check (if slow start)
20        │ Container ready, added to service
30        │ First health check by AppMonitor
45        │ Liveness check succeeds
60        │ Regular monitoring continues
───────────────────────────────────────────────

--- FAILURE OCCURS ---

65        │ Application becomes unresponsive
70        │ Liveness probe fails (attempt 1)
80        │ Liveness probe fails (attempt 2)
90        │ Liveness probe fails (attempt 3)
90        │ Container restart triggered
95        │ New container starts
100       │ Startup probe begins
115       │ Startup succeeds
120       │ Readiness succeeds, back in service
```

## Resource Hierarchy

```
Namespace: self-healing
  │
  ├── Deployments
  │   ├── basic-app (2 replicas)
  │   ├── advanced-app (3 replicas)
  │   └── appmonitor-operator (1 replica)
  │
  ├── ReplicaSets (managed by Deployments)
  │   ├── basic-app-xxxxx
  │   ├── advanced-app-xxxxx
  │   └── appmonitor-operator-xxxxx
  │
  ├── Pods (managed by ReplicaSets)
  │   ├── basic-app-xxxxx-yyyyy
  │   ├── advanced-app-xxxxx-yyyyy (x3)
  │   └── appmonitor-operator-xxxxx-yyyyy
  │
  ├── Services
  │   ├── basic-app-service
  │   └── advanced-app-service
  │
  ├── ConfigMaps
  │   ├── basic-app-config
  │   └── operator-controller (operator code)
  │
  ├── HorizontalPodAutoscaler
  │   └── advanced-app-hpa
  │
  ├── PodDisruptionBudget
  │   └── advanced-app-pdb
  │
  ├── AppMonitors (Custom Resources)
  │   ├── advanced-app-monitor
  │   ├── basic-app-monitor
  │   └── critical-app-monitor
  │
  └── RBAC
      ├── ServiceAccount: appmonitor-operator
      ├── Role: appmonitor-operator-leader-election
      └── RoleBinding: appmonitor-operator-leader-election

Cluster-Wide Resources:
  ├── CustomResourceDefinition
  │   └── appmonitors.healing.example.com
  │
  ├── ClusterRole
  │   └── appmonitor-operator
  │
  └── ClusterRoleBinding
      └── appmonitor-operator
```

## Probe Configuration Best Practices

### Probe Type Selection

| Probe Type | When to Use | Configuration Priority |
|------------|-------------|----------------------|
| **Startup** | Slow-starting apps (>30s) | High `failureThreshold` |
| **Liveness** | Detect deadlocks/hangs | Conservative thresholds |
| **Readiness** | Control traffic routing | Aggressive detection |

### Timing Guidelines

```yaml
# Fast-starting application (<10s)
startupProbe:
  failureThreshold: 6      # 30s total (6 * 5s)
  periodSeconds: 5

livenessProbe:
  initialDelaySeconds: 10
  periodSeconds: 10
  failureThreshold: 3      # 30s to restart

readinessProbe:
  initialDelaySeconds: 5
  periodSeconds: 5
  failureThreshold: 2      # 10s to remove from service
```

```yaml
# Slow-starting application (>60s)
startupProbe:
  failureThreshold: 30     # 150s total (30 * 5s)
  periodSeconds: 5

livenessProbe:
  initialDelaySeconds: 0   # Disabled during startup
  periodSeconds: 15
  failureThreshold: 3

readinessProbe:
  initialDelaySeconds: 0
  periodSeconds: 10
  failureThreshold: 3
```

## Operator Design Patterns

### Controller Pattern

```python
while True:
    # Watch for changes
    for event in watch_custom_resources():
        if event.type in ['ADDED', 'MODIFIED']:
            reconcile(event.object)
```

### Reconciliation Logic

```python
def reconcile(app_monitor):
    # 1. Get current state
    deployment = get_deployment(app_monitor.spec.targetDeployment)
    
    # 2. Determine desired state
    is_healthy = check_health(deployment)
    
    # 3. Take action if needed
    if not is_healthy:
        failures += 1
        if failures >= threshold:
            execute_remediation(app_monitor.spec.strategy)
            failures = 0
    else:
        failures = 0
    
    # 4. Update status
    update_status(app_monitor, is_healthy, failures)
```

### Remediation Strategies

#### Strategy 1: Restart
```python
def restart_deployment(name, namespace):
    # Trigger rolling restart by updating annotation
    deployment = get_deployment(name, namespace)
    deployment.spec.template.metadata.annotations['restartedAt'] = now()
    update_deployment(deployment)
```

#### Strategy 2: Scale
```python
def scale_deployment(name, namespace, additional_replicas):
    deployment = get_deployment(name, namespace)
    current = deployment.spec.replicas
    deployment.spec.replicas = current + additional_replicas
    update_deployment(deployment)
```

#### Strategy 3: Notify
```python
def notify_webhook(webhook_url, data):
    requests.post(webhook_url, json={
        'resource': data.name,
        'status': 'unhealthy',
        'failures': data.failures,
        'timestamp': now()
    })
```

## Monitoring and Observability

### Key Metrics to Monitor

#### Pod Health Metrics
```
- kube_pod_status_phase{phase="Running|Pending|Failed"}
- kube_pod_container_status_restarts_total
- kube_pod_container_status_ready
- kube_pod_status_ready
```

#### Probe Metrics
```
- prober_probe_total{result="successful|failed"}
- prober_probe_duration_seconds
```

#### Deployment Metrics
```
- kube_deployment_status_replicas
- kube_deployment_status_replicas_available
- kube_deployment_status_replicas_unavailable
```

#### HPA Metrics
```
- kube_hpa_status_current_replicas
- kube_hpa_status_desired_replicas
- kube_hpa_spec_max_replicas
- kube_hpa_spec_min_replicas
```

### Logging Strategy

#### Application Logs
```json
{
  "timestamp": "2025-01-15T10:30:00Z",
  "level": "INFO",
  "pod": "advanced-app-xxxxx-yyyyy",
  "message": "Health check succeeded",
  "probe": "liveness",
  "duration_ms": 12
}
```

#### Operator Logs
```json
{
  "timestamp": "2025-01-15T10:30:00Z",
  "level": "WARNING",
  "operator": "appmonitor-operator",
  "resource": "advanced-app-monitor",
  "message": "Health check failed",
  "failures": 2,
  "threshold": 3
}
```

### Event Tracking

```bash
# View all self-healing events
kubectl get events -n self-healing \
  --field-selector reason=Unhealthy,BackOff,FailedScheduling,FailedMount

# Specific event types
kubectl get events -n self-healing \
  --field-selector involvedObject.kind=Pod,reason=Killing
```

## Security Considerations

### RBAC Configuration

```yaml
# Operator needs minimal permissions
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: appmonitor-operator
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch", "update", "patch"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch", "delete"]
- apiGroups: ["healing.example.com"]
  resources: ["appmonitors"]
  verbs: ["get", "list", "watch", "update"]
```

### Pod Security

```yaml
# Run as non-root user
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
```

### Network Policies

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: advanced-app-netpol
spec:
  podSelector:
    matchLabels:
      app: advanced-app
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector: {}
    ports:
    - protocol: TCP
      port: 8080
```

## Performance Optimization

### Resource Requests and Limits

```yaml
# Conservative for stability
resources:
  requests:
    memory: "64Mi"   # Minimum guaranteed
    cpu: "100m"      # 0.1 CPU core
  limits:
    memory: "128Mi"  # Maximum allowed (2x request)
    cpu: "500m"      # 0.5 CPU core (5x request)
```

### Probe Tuning

```yaml
# Balance between fast detection and stability
livenessProbe:
  periodSeconds: 10        # Check every 10s
  timeoutSeconds: 5        # 5s to respond
  failureThreshold: 3      # 30s before restart
  successThreshold: 1      # 1 success to recover
```

### HPA Configuration

```yaml
behavior:
  scaleUp:
    stabilizationWindowSeconds: 0    # Scale up immediately
    policies:
    - type: Percent
      value: 100
      periodSeconds: 15               # Double pods in 15s
  scaleDown:
    stabilizationWindowSeconds: 300  # Wait 5 min before scaling down
    policies:
    - type: Percent
      value: 50
      periodSeconds: 15               # Reduce by 50% in 15s
```

## Disaster Recovery

### Backup Strategy

```bash
# Backup all resources
kubectl get all,configmap,secret,pdb,hpa -n self-healing -o yaml > backup.yaml

# Backup CRDs and CRs
kubectl get crd appmonitors.healing.example.com -o yaml > crd-backup.yaml
kubectl get appmonitors -n self-healing -o yaml > cr-backup.yaml
```

### Recovery Procedures

#### Scenario 1: Complete Namespace Loss
```bash
# Restore namespace and resources
kubectl apply -f backup.yaml
kubectl apply -f crd-backup.yaml
kubectl apply -f cr-backup.yaml
```

#### Scenario 2: Operator Failure
```bash
# Operator will be recreated by deployment
# Check operator logs
kubectl logs -n self-healing -l app=appmonitor-operator

# Restart operator if needed
kubectl rollout restart deployment/appmonitor-operator -n self-healing
```

#### Scenario 3: Cluster Failure
```bash
# Redeploy to new cluster
./deploy.sh

# Restore any stateful data
kubectl apply -f data-backup.yaml
```

## Testing Strategies

### Unit Testing
- Test probe endpoints independently
- Mock Kubernetes API calls in operator
- Verify remediation logic

### Integration Testing
```bash
# Test probe behavior
./test-scenarios.sh

# Test operator remediation
kubectl scale deployment advanced-app --replicas=1
kubectl get appmonitors -n self-healing --watch
```

### Chaos Testing
```bash
# Random pod deletion
kubectl delete pod -n self-healing $(kubectl get pods -n self-healing -o name | shuf -n 1)

# Node drain simulation
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Network partition
kubectl exec <pod> -- iptables -A OUTPUT -j DROP
```

## Troubleshooting Guide

### Common Issues

#### Issue 1: Pods Constantly Restarting
```bash
# Check probe configuration
kubectl describe pod <pod-name> -n self-healing

# Common causes:
# - initialDelaySeconds too short
# - Probe endpoint not ready in time
# - Resource limits too restrictive
```

#### Issue 2: HPA Not Scaling
```bash
# Verify metrics-server
kubectl top nodes
kubectl top pods -n self-healing

# Check HPA status
kubectl describe hpa advanced-app-hpa -n self-healing

# Common causes:
# - Metrics-server not installed
# - Resource requests not set
# - Insufficient cluster capacity
```

#### Issue 3: Operator Not Working
```bash
# Check CRD exists
kubectl get crd appmonitors.healing.example.com

# Check RBAC
kubectl auth can-i list deployments --as=system:serviceaccount:self-healing:appmonitor-operator

# Check operator logs
kubectl logs -n self-healing -l app=appmonitor-operator --tail=100
```

## Conclusion

This architecture provides multiple layers of self-healing:

1. **Container Level**: Liveness, readiness, and startup probes
2. **Pod Level**: ReplicaSet ensures desired count
3. **Application Level**: HPA scales based on load, PDB ensures availability
4. **Custom Level**: Operator provides domain-specific healing logic

Each layer operates independently but works together to provide comprehensive application resilience.
