# Helios — Self-Healing Kubernetes Observability Platform

Helios is a cloud-native observability and resiliency platform for Kubernetes.
It combines a Prometheus/Grafana/Loki monitoring stack, HPA/VPA/KEDA
autoscaling, Helm-based CI/CD, and Chaos Mesh–driven chaos experiments with
automated remediation to demonstrate a measurable self-healing workflow.

> **Read this first:** this repository is a complete, runnable **scaffold** —
> Helm charts, manifests, a Go operator, CI/CD workflows, chaos experiments,
> dashboards, and scripts are all real and internally consistent. It has been
> validated with `helm lint`, `helm template`, `go vet`, and YAML/JSON syntax
> checks in this environment. It has **not** been deployed against a live
> cluster here (no cluster is available in this sandbox), so cluster-specific
> values (storage classes, ingress hostnames, cloud provider settings, secret
> values) will need to be adjusted to your environment. Numbers like "under 2
> hours setup" or "measured MTTR improvement" are targets the tooling is built
> to hit and measure, not results already produced against a real cluster —
> see `docs/setup-guide.md` and `docs/mttr-improvement.md` for how to run the
> validation scripts yourself and produce real numbers for your environment.

## Architecture

```
                        ┌─────────────────────────────┐
                        │        Ingress (nginx)       │
                        └──────────────┬───────────────┘
              ┌────────────────────────┼────────────────────────┐
        ┌─────▼─────┐            ┌─────▼─────┐             ┌─────▼─────┐
        │  Grafana  │            │Prometheus │             │   Loki    │
        │           │◄───────────┤  Operator │             │  (logs)   │
        └───────────┘   metrics  └─────┬─────┘             └─────▲─────┘
                                        │ scrape                  │ push
                              ┌─────────▼─────────┐       ┌───────┴──────┐
                              │  helios-app pods   │◄──────┤  Promtail    │
                              │  (demo-api/worker/ │       │  DaemonSet   │
                              │   frontend) + HPA  │       └──────────────┘
                              └─────────┬──────────┘
                                        │ watched by
                              ┌─────────▼──────────┐
                              │ Self-Healing        │
                              │ Operator (Go)        │───► remediation actions
                              └─────────┬────────────┘      + MTTR metrics
                                        │
                              ┌─────────▼──────────┐
                              │   Chaos Mesh         │  injects pod/node/net
                              │ experiments+schedule │  failures on a cadence
                              └───────────────────────┘
```

See `docs/architecture.md` for the full component breakdown.

## Repository layout

```
helios/
├── charts/                 # Helm charts: infrastructure, platform, app
├── .github/workflows/      # CI, CD, chaos-test, security-scan pipelines
├── chaos/                  # Chaos Mesh experiments, schedules, remediation
├── controllers/            # Go self-healing operator
├── dashboards/             # Grafana + Loki dashboard JSON
├── scripts/                # setup/deploy/chaos/validation scripts
├── apps/                   # demo-api, demo-worker, frontend (Go services)
├── terraform/              # optional cluster provisioning (EKS example)
├── docs/                   # architecture, setup, chaos, MTTR docs
└── hack/                   # local kind cluster for dev/testing
```

## Quick start (local, kind)

```bash
./hack/local-setup.sh          # creates a local kind cluster
./scripts/setup-dev.sh         # installs Helios into it
./scripts/validate-self-healing.sh   # runs the self-healing smoke test
```

For staging/production targets, see `docs/setup-guide.md`.

## The three claims this repo is built to satisfy

1. **Monitoring + autoscaling** — `charts/helios-infrastructure` (Prometheus
   Operator, Grafana, Loki) and `charts/helios-app` (HPA/VPA/KEDA) — see
   `docs/architecture.md`.
2. **CI/CD with GitHub Actions + Helm** — `.github/workflows/*.yml` and
   `charts/*` — see `docs/setup-guide.md`.
3. **Chaos engineering + automated remediation** — `chaos/*` and
   `controllers/selfhealing_controller.go` — see `docs/chaos-engineering.md`
   and `docs/mttr-improvement.md`.

## License

MIT — see individual chart `README.md` files for third-party chart
dependencies (kube-prometheus-stack, loki-stack, chaos-mesh), which carry
their own upstream licenses.
