# MTTR Measurement and Improvement

## How MTTR is defined here

For each pod, `helios:incident_resolution_seconds` (defined in
`charts/helios-infrastructure/templates/prometheus/rules-mttr.yaml`) is the
time between the pod's most recent transition to `Ready: false` and its next
transition to `Ready: true`. This is rolled up per namespace into:

- `helios:mttr_seconds_1h` — rolling 1-hour average (a "right now" figure)
- `helios:mttr_seconds_7d` — rolling 7-day average (a stable baseline)
- `helios:mttr_improvement_ratio` — `(mttr_seconds_7d − mttr_seconds_1h) / mttr_seconds_7d`,
  i.e. a positive value means recent recoveries are faster than the 7-day
  baseline; negative means they've gotten slower (and the
  `HeliosMTTRRegression` alert fires if the regression exceeds 50%).

## Why this number needs a real cluster to be meaningful

This repository ships the instrumentation (recording rules, dashboards,
`scripts/validate-self-healing.sh`) and the remediation logic that should
*produce* MTTR improvement (the self-healing operator's pod-restart and
auto-rollback policies, HPA/VPA capacity response, chaos-driven continuous
exercise of those paths) — but an actual improvement percentage is a
property of your specific cluster's failure history, workload, and how long
the system has been running with these remediation paths active. There is
no cluster available in the environment that generated this repository to
run it against and produce a real before/after number.

## Producing a real number

1. Deploy Helios (`docs/setup-guide.md`) **without** the self-healing
   operator (`--set selfHealingOperator.enabled=false`) and let the chaos
   suite run for at least a few days. Record `helios:mttr_seconds_7d` from
   Prometheus — this is your baseline (Kubernetes-native recovery only:
   ReplicaSet recreation, kubelet restarts).
2. Re-enable the operator (`--set selfHealingOperator.enabled=true`,
   `helm upgrade`) and let the chaos suite run for another few days.
3. Compare the new `helios:mttr_seconds_7d` to the baseline from step 1.
   The percentage difference is your real, cluster-specific MTTR
   improvement figure — put it in the "MTTR Tracking" Grafana dashboard's
   time range set to span both windows to see the transition visually.

## Single-sample smoke test

For a quick sanity check (not a substitute for the above):

```bash
./scripts/validate-self-healing.sh
cat /tmp/helios-mttr-report.json
```

This deletes one live pod and times recovery once. `chaos-test.yml` runs
this in CI mode (`--ci`) against staging on a schedule and fails the build
if recovery exceeds 90 seconds, catching regressions before they reach
production rather than measuring long-term trend.

## Interpreting `mean_time_to_resolve` vs. incident count

A namespace with a very low `helios:mttr_seconds_1h` but a high incident
rate (visible on the "Chaos Engineering" dashboard's experiment panel, or
via `helios:pod_restart_rate_5m`) is recovering fast but failing often —
that's a different problem (root-cause the failure trigger) than a namespace
with a high MTTR and low incident rate (recovery itself is slow). Read both
numbers together rather than optimizing MTTR in isolation.
