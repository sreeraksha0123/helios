# Helios Architecture

## Component overview

| Layer | Component | Chart / Path | Purpose |
|---|---|---|---|
| Observability | Prometheus Operator | `charts/helios-infrastructure` (kube-prometheus-stack dep) | Metrics collection, alerting, recording rules |
| Observability | Grafana | `charts/helios-infrastructure` (kube-prometheus-stack dep) | Dashboards (`dashboards/grafana/*.json`) |
| Observability | Loki + Promtail | `charts/helios-infrastructure` (loki-stack dep) | Log aggregation, labeled by namespace/pod/container/app/severity |
| Ingress/TLS | ingress-nginx, cert-manager | `charts/helios-infrastructure` | Exposes Grafana/Prometheus/frontend, TLS via Let's Encrypt |
| Platform | Self-Healing Operator | `charts/helios-platform`, source in `controllers/` | Detects and remediates slow-failure modes; emits MTTR metrics |
| Application | demo-api, demo-worker, frontend | `charts/helios-app`, source in `apps/` | Sample workload exercising HPA/VPA/KEDA and RED-method metrics |
| Resiliency | Chaos Mesh experiments | `chaos/` | Injects pod failure, network partition, CPU/memory stress on a schedule |
| Delivery | GitHub Actions + Helm | `.github/workflows/`, `charts/` | CI (lint/test/build), CD (staged rollout), scheduled chaos runs, security scans |

## Request path

```
client → Ingress (nginx) → frontend Service → frontend Pods
                                   │
                                   ▼  (HTTP call to /api/work)
                          demo-api Service → demo-api Pods
```

`demo-api` and `frontend` both expose `/metrics` (Prometheus format, RED
method: rate, errors, duration) and `/healthz`. Promtail tails their stdout
and labels log lines with `namespace`, `pod`, `container`, `app`, and
`severity` so they're queryable in the Loki-based "Log Explorer" dashboard.

## Autoscaling stack

- **HPA** (`charts/helios-app/templates/hpa.yaml`) scales `demo-api`,
  `demo-worker`, and `frontend` on CPU utilization; `demo-api` additionally
  scales on memory and on a custom `http_requests_per_second` metric via the
  Prometheus Adapter (bundled with kube-prometheus-stack).
- **VPA** (`vpa.yaml`) runs in `Auto` mode on `demo-api`, right-sizing CPU/
  memory requests over time — this is what actually improves bin-packing and
  therefore cluster resiliency to node pressure, complementing the HPA's
  horizontal response to load.
- **KEDA** (`keda-scaledobject.yaml`) adds a second, independent scaling
  signal (a raw Prometheus query) for event-driven scenarios where HPA's
  built-in metrics pipeline isn't expressive enough.

Together these three are the "autonomous load adaptation" the resiliency
claim asks for: HPA reacts within seconds to load spikes, VPA tunes the
steady-state resource footprint over hours/days, and KEDA lets you add
arbitrary Prometheus-driven triggers without hand-rolling a custom metrics
adapter query for each one.

## Self-healing operator

Source: `controllers/main.go` + `controllers/controllers/selfhealing_controller.go`.

It reconciles on every Pod change and applies two remediation policies:

1. **Sustained memory pressure → pod restart.** If a pod carries a
   `helios.io/memory-pressure-since` annotation (set by the monitoring
   pipeline once usage crosses `MEMORY_THRESHOLD_PERCENT` of its limit) for
   longer than `RESTART_AFTER`, the operator deletes the pod so its owning
   controller recreates it — catching slow leaks before they hit an OOM
   kill and cause a harder failure.
2. **Repeated pod failures on a Deployment → automatic rollback.** If a
   Deployment's current ReplicaSet accumulates more than
   `MAX_FAILED_PODS_BEFORE_ROLLBACK` failed pods within `ROLLBACK_WINDOW`,
   the operator rewrites the container image to the value recorded in the
   `helios.io/previous-revision-image` annotation (set by
   `scripts/deploy.sh` on every successful deploy) — an automated defense
   against a build that passed CI but fails at runtime.

Every action increments `selfhealing_remediation_actions_total{action,namespace}`
and is written as a Kubernetes Event, both of which feed the "Self-Healing"
Grafana dashboard.

## MTTR measurement

`charts/helios-infrastructure/templates/prometheus/rules-mttr.yaml` defines
recording rules that compute, per namespace:

- `helios:incident_resolution_seconds` — time between a pod going
  not-Ready and its next Ready transition.
- `helios:mttr_seconds_1h` / `helios:mttr_seconds_7d` — rolling averages.
- `helios:mttr_improvement_ratio` — `(7d − 1h) / 7d`, i.e. how much faster
  recovery has gotten recently relative to the two-week baseline.

See `docs/mttr-improvement.md` for how to produce a real number for your
cluster with `scripts/validate-self-healing.sh`.

## Chaos engineering

`chaos/experiments/` defines four always-on Chaos Mesh experiments (pod
failure hourly, network partition every 3h, node-style CPU/memory stress
every 6h, targeted CPU stress every 2h), each scoped to `helios-app` via
label selectors so they never touch `helios-monitoring` or
`helios-platform`. `chaos/schedules/weekly-chaos.yaml` layers a broader,
less predictable weekly exercise on top. `chaos/automation/remediation.yaml`
documents how each remediation path (kubelet restart, self-healing
operator, HPA/VPA, NetworkPolicy) responds to each experiment type.

## Zero-downtime delivery

All three `helios-app` Deployments use `RollingUpdate` with
`maxSurge: 25%`, `maxUnavailable: 0`, readiness/liveness probes, a 5s
`preStop` sleep (so in-flight requests drain before SIGTERM), and an
init container that waits for cluster DNS before the main container starts.
`.github/workflows/cd.yml` verifies this by asserting
`kubectl rollout status` succeeds within a timeout after every deploy; for a
harder guarantee in production, `scripts/setup-prod.sh` installs Flagger so
`deploy-production` progresses as a canary rather than an all-at-once
rolling update.

## What's intentionally out of scope by default

- **Istio/Linkerd** — not installed by default to keep the base stack
  lighter; `chaos/automation/remediation.yaml` notes where to add it if you
  want active retry/circuit-breaking during network-partition experiments.
- **Thanos** — `kube-prometheus-stack.prometheus.thanos.enabled` is `false`
  by default because it requires an object-storage bucket/secret specific
  to your cloud provider; flip it on and point it at your bucket for
  long-term/multi-cluster metrics storage.
- **Cluster Autoscaler** — cloud-provider specific; the Terraform module in
  `terraform/` tags an EKS node group for it, but the manifest itself isn't
  portable across providers, so it isn't templated into the Helm charts.
