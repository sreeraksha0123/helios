// demo-worker is a background consumer with no external queue dependency —
// it simulates picking work off a queue at a configurable rate, so it can
// be CPU-stressed by chaos experiments (see chaos/experiments/node-failure.yaml)
// and observed scaling via its own CPU-based HPA.
package main

import (
	"log"
	"math/rand"
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var jobsProcessedTotal = prometheus.NewCounter(prometheus.CounterOpts{
	Name: "worker_jobs_processed_total",
	Help: "Total jobs processed by demo-worker.",
})

func init() {
	prometheus.MustRegister(jobsProcessedTotal)
}

func processJob() {
	iterations := 50000 + rand.Intn(150000)
	acc := 0.0
	for i := 0; i < iterations; i++ {
		acc += float64(i) * 1.0000001
	}
	_ = acc
	jobsProcessedTotal.Inc()
}

func main() {
	// Expose /healthz and /metrics on :8081 while the main loop runs.
	go func() {
		mux := http.NewServeMux()
		mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte("ok"))
		})
		mux.Handle("/metrics", promhttp.Handler())
		log.Println("demo-worker health/metrics listening on :8081")
		if err := http.ListenAndServe(":8081", mux); err != nil {
			log.Fatal(err)
		}
	}()

	log.Println("demo-worker started")
	for {
		processJob()
		time.Sleep(500 * time.Millisecond)
	}
}
