// demo-api is a minimal HTTP service used to exercise Helios's HPA, KEDA,
// and chaos-engineering paths. It exposes:
//
//	GET  /healthz  — liveness/readiness probe target
//	GET  /api/work — does a small amount of CPU work and returns JSON;
//	                 useful as an HPA/KEDA load-test target
//	GET  /metrics  — Prometheus metrics (request count, duration, in-flight)
package main

import (
	"encoding/json"
	"log"
	"math/rand"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	requestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{Name: "http_requests_total", Help: "Total HTTP requests."},
		[]string{"app", "namespace", "status"},
	)
	requestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{Name: "http_request_duration_seconds", Help: "Request duration in seconds."},
		[]string{"app", "namespace"},
	)
	inFlight = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{Name: "http_requests_in_flight", Help: "In-flight HTTP requests."},
		[]string{"app", "namespace"},
	)
)

func init() {
	prometheus.MustRegister(requestsTotal, requestDuration, inFlight)
}

const appName = "demo-api"

func namespace() string {
	if ns := os.Getenv("POD_NAMESPACE"); ns != "" {
		return ns
	}
	return "helios-app"
}

func instrument(next http.HandlerFunc) http.HandlerFunc {
	ns := namespace()
	return func(w http.ResponseWriter, r *http.Request) {
		inFlight.WithLabelValues(appName, ns).Inc()
		defer inFlight.WithLabelValues(appName, ns).Dec()

		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next(rec, r)

		requestDuration.WithLabelValues(appName, ns).Observe(time.Since(start).Seconds())
		requestsTotal.WithLabelValues(appName, ns, strconv.Itoa(rec.status)).Inc()
	}
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func healthzHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}

// workHandler burns a small, bounded amount of CPU so it's suitable as an
// HPA/KEDA load-test target without being able to wedge the process.
func workHandler(w http.ResponseWriter, r *http.Request) {
	iterations := 200000 + rand.Intn(300000)
	acc := 0.0
	for i := 0; i < iterations; i++ {
		acc += float64(i) * 1.0000001
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"status":     "ok",
		"iterations": iterations,
		"result":     acc,
	})
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", healthzHandler)
	mux.HandleFunc("/api/work", instrument(workHandler))
	mux.Handle("/metrics", promhttp.Handler())

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	log.Printf("demo-api listening on :%s", port)
	if err := srv.ListenAndServe(); err != nil {
		log.Fatal(err)
	}
}
