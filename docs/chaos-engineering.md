# Chaos Engineering Guide

## Philosophy

Every experiment in `chaos/experiments/` targets only the `helios-app`
namespace, runs on a fixed schedule (not just on-demand), and has a bounded
duration. The goal isn't to prove the system never fails — it's to keep a
constant, low-grade failure rate flowing through the remediation paths
(kubelet restarts, HPA, the self-healing operator, NetworkPolicy) so that
those paths are continuously exercised rather than only tested once during
initial rollout.

## The experiment suite

| Experiment | File | Target | Cadence | Duration |
|---|---|---|---|---|
| Pod failure | `chaos/experiments/pod-failure.yaml` | one `demo-api` pod | hourly | 30s |
| Network partition | `chaos/experiments/network-partition.yaml` | all `demo-api` pods | every 3h | 45s |
| Node-style stress | `chaos/experiments/node-failure.yaml` | one `demo-worker` pod | every 6h | 60s |
| CPU stress | `chaos/experiments/cpu-stress.yaml` | 50% of `demo-api` pods | every 2h | 2m |
| Weekly pod failure | `chaos/schedules/weekly-chaos.yaml` | all `helios-app` pods | Sat 02:00 | 30s |
| Weekly network delay | `chaos/schedules/weekly-chaos.yaml` | all `helios-app` pods | Sat 02:30 | 1m |

`node-failure.yaml` uses Chaos Mesh's `StressChaos` against pods rather than
shutting down an actual node — that keeps the experiment portable across
clusters/cloud providers without needing cloud-specific node-termination
integration. If you want literal node termination (e.g. via AWS
`TerminateInstances` calls), Chaos Mesh's `AWSChaos` resource covers that on
EKS specifically; it's not included here to keep the base suite portable.

## Running the suite

```bash
./scripts/chaos-run.sh
kubectl get events -n helios-app --watch
```

Or let `.github/workflows/chaos-test.yml` run it against staging on a
schedule and upload the resulting MTTR report.

## What to look for

1. **Pod-failure experiment** — the pod should be recreated by its
   ReplicaSet within seconds; check that `helios:pod_restart_rate_5m` (on
   the "Self-Healing" Grafana dashboard) shows the spike and recovery.
2. **Network-partition experiment** — `frontend`'s error rate (RED-method
   dashboard) should rise for the ~45s duration of the partition, then
   return to baseline immediately after Chaos Mesh tears down its iptables
   rules — no manual action required, since the Kubernetes Service/Endpoint
   objects were never actually changed.
3. **CPU/memory stress experiments** — watch the HPA-status dashboard for a
   scale-up event as the stressed pods' CPU utilization crosses the 70%
   target; this is the autoscaling response to a resource-pressure failure
   mode rather than a pod-death failure mode.

## Validating end-to-end

```bash
./scripts/validate-self-healing.sh
```

This deletes a live `demo-api` pod, times how long it takes for a
replacement to become Ready, and writes the result to
`/tmp/helios-mttr-report.json`. It's a synthetic, single-sample check — for
a statistically meaningful MTTR figure, let the scheduled experiments run
for at least a few days and read `helios:mttr_seconds_7d` from Prometheus
(see `docs/mttr-improvement.md`).

## Extending the suite

Chaos Mesh supports many more experiment kinds than are enabled by default
(`IOChaos`, `DNSChaos`, `HTTPChaos`, `KernelChaos`, `TimeChaos`). Add new
YAML files under `chaos/experiments/` following the same pattern — scoped
`selector.namespaces`, a bounded `duration`, and a `scheduler.cron` rather
than a one-shot run — and they'll be picked up automatically by
`scripts/chaos-run.sh` (`kubectl apply -f chaos/experiments/`).
