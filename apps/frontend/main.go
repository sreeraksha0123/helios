// frontend serves a minimal status page that calls demo-api and reports
// health — enough to make Ingress -> frontend -> demo-api a real,
// observable request path for the RED-method dashboard and chaos
// experiments to act on.
package main

import (
	"fmt"
	"io"
	"log"
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
)

func init() {
	prometheus.MustRegister(requestsTotal, requestDuration)
}

const appName = "frontend"

func namespace() string {
	if ns := os.Getenv("POD_NAMESPACE"); ns != "" {
		return ns
	}
	return "helios-app"
}

func apiURL() string {
	if u := os.Getenv("API_URL"); u != "" {
		return u
	}
	return "http://demo-api:8080"
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func instrument(next http.HandlerFunc) http.HandlerFunc {
	ns := namespace()
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next(rec, r)
		requestDuration.WithLabelValues(appName, ns).Observe(time.Since(start).Seconds())
		requestsTotal.WithLabelValues(appName, ns, strconv.Itoa(rec.status)).Inc()
	}
}

func indexHandler(w http.ResponseWriter, r *http.Request) {
	client := http.Client{Timeout: 3 * time.Second}
	resp, err := client.Get(apiURL() + "/api/work")
	if err != nil {
		w.WriteHeader(http.StatusBadGateway)
		fmt.Fprintf(w, "Helios demo frontend — backend unreachable: %v\n", err)
		return
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	fmt.Fprintf(w, "Helios demo frontend\nbackend status: %d\nbackend response: %s\n", resp.StatusCode, body)
}

func healthzHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/", instrument(indexHandler))
	mux.HandleFunc("/healthz", healthzHandler)
	mux.Handle("/metrics", promhttp.Handler())

	log.Printf("frontend listening on :%s (backend %s)", port, apiURL())
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatal(err)
	}
}
