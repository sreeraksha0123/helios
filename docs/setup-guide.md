# Setup Guide

## Prerequisites

- `kubectl` >= 1.28, `helm` >= 3.14
- A Kubernetes cluster (kind for local dev, or a real cluster for
  staging/production — see `terraform/` for an EKS example)
- For local dev: `kind`, Docker

## Local (kind) — target: under 30 minutes

```bash
./hack/local-setup.sh          # creates the kind cluster + metrics-server
./scripts/setup-dev.sh         # installs helios-infrastructure, -platform, -app
```

`setup-dev.sh` does five things: adds the upstream Helm repos, builds chart
dependencies, and installs `helios-infrastructure`, `helios-platform`, and
`helios-app` in that order (each waits for its own rollout before the next
step starts, so failures surface immediately instead of cascading).

Verify:

```bash
kubectl get pods -n helios-monitoring
kubectl get pods -n helios-platform
kubectl get pods -n helios-app
kubectl port-forward -n helios-monitoring svc/helios-grafana 3000:80
# open http://localhost:3000, default dashboards are pre-loaded via the
# Grafana sidecar (see charts/helios-infrastructure/templates/grafana/dashboards-configmap.yaml)
```

## Staging — target: under 1 hour

```bash
./scripts/setup-staging.sh <image-tag>
```

This runs `setup-dev.sh` first, then layers on Chaos Mesh and applies the
chaos experiment suite (`chaos/experiments/`, `chaos/schedules/`) so
scheduled chaos runs (`.github/workflows/chaos-test.yml`) have something to
target. If `charts/helios-platform/values-staging.yaml` exists, it's applied
as an overlay — use it for staging-specific resource limits, replica counts,
or ingress hosts.

## Production — target: under 2 hours

```bash
./scripts/setup-prod.sh <image-tag>
```

Requires a confirmation prompt (it checks `kubectl config current-context`
and asks you to confirm before touching anything). In addition to the
infrastructure/platform/app installs, it installs Flagger so
`.github/workflows/cd.yml`'s `deploy-production` job progresses as a canary,
and runs `kubectl rollout status` against both `demo-api` and `frontend` to
confirm zero-downtime delivery before declaring success.

### Timing this yourself

The "< 2 hours" target is a design target for the tooling (parallel-safe
Helm installs, `--wait` on every step so failures are caught immediately
rather than requiring manual debugging later, and reused dev/staging
bootstrap logic), not a number we can certify without a real cluster to run
it against. To get a real number for your environment:

```bash
time ./scripts/setup-prod.sh $(git rev-parse --short HEAD)
```

## CI/CD

- `.github/workflows/ci.yml` — lints all Helm charts (`helm lint` +
  `helm template` dry-render), lints chaos/workflow YAML, runs `go vet`/
  `go test` across all four Go modules, and builds+pushes container images
  to `ghcr.io` on every push to `main`/`develop`.
- `.github/workflows/cd.yml` — copies the canonical dashboards into the
  infra chart, re-lints, deploys to staging automatically on `main`, and
  deploys to production only via manual `workflow_dispatch` with
  `environment: production` (so it goes through GitHub's environment
  protection rules/required reviewers if you configure them).
- `.github/workflows/chaos-test.yml` — runs the chaos suite against staging
  on weekday mornings and uploads the resulting MTTR report as a build
  artifact.
- `.github/workflows/security-scan.yml` — Trivy image scans (uploaded as
  SARIF to GitHub code scanning) and Checkov policy checks against the
  rendered platform/app manifests.

### Secrets the workflows expect

| Secret | Used by | Purpose |
|---|---|---|
| `STAGING_KUBECONFIG` | cd.yml, chaos-test.yml | base64-encoded kubeconfig for the staging cluster |
| `PROD_KUBECONFIG` | cd.yml | base64-encoded kubeconfig for the production cluster |
| `GITHUB_TOKEN` | ci.yml (auto-provided) | push to `ghcr.io` |

## Uninstall

```bash
helm uninstall helios-app -n helios-app
helm uninstall helios-platform -n helios-platform
helm uninstall helios-infra -n helios-monitoring
kubectl delete namespace helios-app helios-platform helios-monitoring
```
