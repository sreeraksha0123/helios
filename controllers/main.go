// Command selfhealing-operator watches Pods, Nodes, and Deployments in the
// cluster and takes corrective action when it detects the failure modes
// that Kubernetes's own controllers don't handle out of the box: pods
// creeping toward an OOM without being killed, a Deployment whose newest
// ReplicaSet is failing repeatedly, and nodes reporting sustained pressure
// conditions. It exposes Prometheus metrics on :8080/metrics that feed the
// "Self-Healing" and "MTTR Tracking" Grafana dashboards.
package main

import (
	"flag"
	"net/http"
	"os"

	"github.com/prometheus/client_golang/prometheus/promhttp"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"

	"github.com/helios-platform/selfhealing-operator/controllers"
)

func main() {
	var metricsAddr string
	var healthAddr string
	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8080", "address the metrics endpoint binds to")
	flag.StringVar(&healthAddr, "health-probe-bind-address", ":8081", "address the health probe endpoint binds to")
	flag.Parse()

	logger := zap.New(zap.UseDevMode(os.Getenv("LOG_LEVEL") == "debug"))
	ctrl.SetLogger(logger)

	cfg, err := rest.InClusterConfig()
	if err != nil {
		logger.Error(err, "unable to load in-cluster config; falling back to KUBECONFIG")
		cfg, err = ctrl.GetConfig()
		if err != nil {
			logger.Error(err, "unable to load any kubeconfig")
			os.Exit(1)
		}
	}

	clientset, err := kubernetes.NewForConfig(cfg)
	if err != nil {
		logger.Error(err, "unable to create clientset")
		os.Exit(1)
	}

	// The manager's built-in metrics server is disabled (BindAddress "0")
	// because this operator serves its own /metrics endpoint via promhttp
	// below, alongside a simple /healthz handler.
	mgrOpts := ctrl.Options{}
	mgrOpts.Metrics.BindAddress = "0"
	mgrOpts.HealthProbeBindAddress = healthAddr

	mgr, err := ctrl.NewManager(cfg, mgrOpts)
	if err != nil {
		logger.Error(err, "unable to start manager")
		os.Exit(1)
	}

	reconciler := &controllers.SelfHealingReconciler{
		Client:    mgr.GetClient(),
		Clientset: clientset,
		Config:    controllers.LoadConfigFromEnv(),
	}
	if err := reconciler.SetupWithManager(mgr); err != nil {
		logger.Error(err, "unable to set up SelfHealingReconciler")
		os.Exit(1)
	}

	// Serve Prometheus metrics + a liveness/readiness probe alongside the
	// controller-runtime manager.
	go func() {
		mux := http.NewServeMux()
		mux.Handle("/metrics", promhttp.Handler())
		mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte("ok"))
		})
		if err := http.ListenAndServe(metricsAddr, mux); err != nil {
			logger.Error(err, "metrics server exited")
			os.Exit(1)
		}
	}()

	logger.Info("starting self-healing operator", "metricsAddr", metricsAddr)
	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		logger.Error(err, "manager exited with error")
		os.Exit(1)
	}
}
