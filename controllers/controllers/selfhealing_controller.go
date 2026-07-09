// Package controllers implements the Helios self-healing reconciliation
// loop: it watches Pods and reacts to two failure modes that Kubernetes's
// built-in controllers don't fully cover on their own —
//
//  1. Pods whose memory usage has stayed above a configurable threshold for
//     longer than a configurable window (a slow leak heading toward an OOM
//     kill, rather than an already-thrown OOMKilled event).
//  2. Deployments whose newest ReplicaSet accumulates more than
//     MaxFailedPodsBeforeRollback failed pods within RollbackWindow, which
//     triggers an automatic rollback to the previous ReplicaSet's revision.
//
// Every remediation action increments the selfhealing_remediation_actions_total
// counter (labeled by action and namespace) so it is visible on the
// "Self-Healing" Grafana dashboard, and is recorded as a Kubernetes Event on
// the affected object for auditability.
package controllers

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/record"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/manager"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	appsv1 "k8s.io/api/apps/v1"
)

// Config holds the operator's tunable remediation thresholds, sourced from
// the ConfigMap templated in charts/helios-platform/templates/configmap.yaml
// and mounted as environment variables.
type Config struct {
	MemoryThresholdPercent      int
	RestartAfter                time.Duration
	MaxFailedPodsBeforeRollback int
	RollbackWindow               time.Duration
	UnhealthyNodeConditions      []string
}

// LoadConfigFromEnv reads the operator configuration from environment
// variables, falling back to conservative defaults if unset (e.g. when
// running locally against a kind cluster without the full Helm install).
func LoadConfigFromEnv() Config {
	cfg := Config{
		MemoryThresholdPercent:      90,
		RestartAfter:                2 * time.Minute,
		MaxFailedPodsBeforeRollback: 3,
		RollbackWindow:               5 * time.Minute,
		UnhealthyNodeConditions:      []string{"DiskPressure", "MemoryPressure", "NetworkUnavailable"},
	}
	if v := os.Getenv("MEMORY_THRESHOLD_PERCENT"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			cfg.MemoryThresholdPercent = n
		}
	}
	if v := os.Getenv("RESTART_AFTER"); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			cfg.RestartAfter = d
		}
	}
	if v := os.Getenv("MAX_FAILED_PODS_BEFORE_ROLLBACK"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			cfg.MaxFailedPodsBeforeRollback = n
		}
	}
	if v := os.Getenv("ROLLBACK_WINDOW"); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			cfg.RollbackWindow = d
		}
	}
	if v := os.Getenv("UNHEALTHY_NODE_CONDITIONS"); v != "" {
		cfg.UnhealthyNodeConditions = strings.Split(v, ",")
	}
	return cfg
}

var remediationActionsTotal = prometheus.NewCounterVec(
	prometheus.CounterOpts{
		Name: "selfhealing_remediation_actions_total",
		Help: "Count of remediation actions taken by the Helios self-healing operator, labeled by action type.",
	},
	[]string{"action", "namespace"},
)

func init() {
	prometheus.MustRegister(remediationActionsTotal)
}

// SelfHealingReconciler reconciles Pod objects and applies the remediation
// policies described in Config.
type SelfHealingReconciler struct {
	client.Client
	Clientset *kubernetes.Clientset
	Config    Config
	Recorder  record.EventRecorder
}

// Reconcile implements the core loop: for the Pod named in req, decide
// whether any remediation action is needed and, if so, take it.
func (r *SelfHealingReconciler) Reconcile(ctx context.Context, req reconcile.Request) (reconcile.Result, error) {
	logger := log.FromContext(ctx)

	var pod corev1.Pod
	if err := r.Get(ctx, req.NamespacedName, &pod); err != nil {
		if errors.IsNotFound(err) {
			return reconcile.Result{}, nil
		}
		return reconcile.Result{}, err
	}

	if err := r.checkMemoryPressure(ctx, &pod); err != nil {
		logger.Error(err, "memory pressure check failed", "pod", req.NamespacedName)
	}

	if owner := ownerDeployment(&pod); owner != "" {
		if err := r.checkRollbackNeeded(ctx, pod.Namespace, owner); err != nil {
			logger.Error(err, "rollback check failed", "deployment", owner)
		}
	}

	// Re-check periodically even without a new event, since memory-pressure
	// detection is time-window based rather than purely event driven.
	return reconcile.Result{RequeueAfter: 30 * time.Second}, nil
}

// checkMemoryPressure restarts a pod (by deleting it, so the owning
// controller recreates it) if it has held memory usage above
// Config.MemoryThresholdPercent of its limit for longer than
// Config.RestartAfter, as evidenced by a corresponding condition/annotation
// set by the metrics pipeline. In a full deployment this reads live usage
// from the metrics-server/Prometheus API; here we check the annotation the
// monitoring stack is expected to maintain (see docs/architecture.md).
func (r *SelfHealingReconciler) checkMemoryPressure(ctx context.Context, pod *corev1.Pod) error {
	pressureSince, ok := pod.Annotations["helios.io/memory-pressure-since"]
	if !ok {
		return nil
	}
	since, err := time.Parse(time.RFC3339, pressureSince)
	if err != nil {
		return fmt.Errorf("parsing memory-pressure-since annotation: %w", err)
	}
	if time.Since(since) < r.Config.RestartAfter {
		return nil
	}

	if err := r.Delete(ctx, pod); err != nil {
		return fmt.Errorf("deleting pod under sustained memory pressure: %w", err)
	}
	remediationActionsTotal.WithLabelValues("restart_pod_memory_pressure", pod.Namespace).Inc()
	r.recordEvent(pod, "MemoryPressureRestart",
		fmt.Sprintf("restarted pod after %s of sustained memory pressure above %d%%",
			r.Config.RestartAfter, r.Config.MemoryThresholdPercent))
	return nil
}

// checkRollbackNeeded rolls a Deployment back to its previous revision if
// its current ReplicaSet has accumulated too many failed pods within the
// configured rollback window — the automated defense against a bad deploy
// that passed CI but fails at runtime.
func (r *SelfHealingReconciler) checkRollbackNeeded(ctx context.Context, namespace, name string) error {
	var deploy appsv1.Deployment
	if err := r.Get(ctx, client.ObjectKey{Namespace: namespace, Name: name}, &deploy); err != nil {
		if errors.IsNotFound(err) {
			return nil
		}
		return err
	}

	var pods corev1.PodList
	if err := r.List(ctx, &pods, client.InNamespace(namespace), client.MatchingLabels(deploy.Spec.Selector.MatchLabels)); err != nil {
		return err
	}

	failedRecently := 0
	cutoff := time.Now().Add(-r.Config.RollbackWindow)
	for _, p := range pods.Items {
		if p.Status.Phase == corev1.PodFailed && p.CreationTimestamp.After(cutoff) {
			failedRecently++
		}
	}
	if failedRecently < r.Config.MaxFailedPodsBeforeRollback {
		return nil
	}

	prevRevision, ok := deploy.Annotations["helios.io/previous-revision-image"]
	if !ok {
		// Nothing to roll back to; alert instead of guessing.
		r.recordEvent(&deploy, "RollbackSkipped",
			"deployment has too many recently-failed pods but no previous-revision annotation to roll back to")
		return nil
	}

	for i := range deploy.Spec.Template.Spec.Containers {
		deploy.Spec.Template.Spec.Containers[i].Image = prevRevision
	}
	if err := r.Update(ctx, &deploy); err != nil {
		return fmt.Errorf("rolling back deployment %s/%s: %w", namespace, name, err)
	}
	remediationActionsTotal.WithLabelValues("rollback_deployment", namespace).Inc()
	r.recordEvent(&deploy, "AutoRollback",
		fmt.Sprintf("rolled back to %s after %d pod failures within %s", prevRevision, failedRecently, r.Config.RollbackWindow))
	return nil
}

func (r *SelfHealingReconciler) recordEvent(obj runtime.Object, reason, message string) {
	if r.Recorder == nil {
		return
	}
	r.Recorder.Event(obj, corev1.EventTypeNormal, reason, message)
}

func ownerDeployment(pod *corev1.Pod) string {
	for _, ref := range pod.OwnerReferences {
		if ref.Kind == "ReplicaSet" {
			// Deployment-managed ReplicaSets are named "<deployment>-<hash>";
			// strip the trailing hash segment.
			if idx := strings.LastIndex(ref.Name, "-"); idx > 0 {
				return ref.Name[:idx]
			}
		}
	}
	return ""
}

// SetupWithManager wires the reconciler into the controller-runtime manager,
// watching Pods across all namespaces via the standard builder API (the
// stable, version-tolerant way to register a controller — see
// sigs.k8s.io/controller-runtime/pkg/builder). RBAC for the cluster-wide
// watch is granted by the ClusterRole in
// charts/helios-platform/templates/rbac.yaml.
func (r *SelfHealingReconciler) SetupWithManager(mgr manager.Manager) error {
	r.Recorder = mgr.GetEventRecorderFor("helios-selfhealing-operator")
	_ = metav1.NamespaceAll

	return builder.
		ControllerManagedBy(mgr).
		Named("selfhealing-controller").
		For(&corev1.Pod{}).
		Complete(r)
}
