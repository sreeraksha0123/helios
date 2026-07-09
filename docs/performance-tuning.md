# Performance Tuning

## Prometheus

- `retention: 30d` and a 50Gi PVC are the defaults in
  `charts/helios-infrastructure/values.yaml`; on a busy cluster with high
  cardinality (many namespaces × many pods × many custom metrics), increase
  the PVC size before you increase retention — Prometheus will OOM or fail
  to compact long before it runs out of days if the working set doesn't fit
  in the configured storage.
- If you're running more than a handful of clusters, or want retention
  beyond 30-60 days, enable Thanos (`thanos.enabled: true`) and point
  `objectStorageConfig` at a bucket — see the comment in
  `charts/helios-infrastructure/values.yaml`. This moves long-term data out
  of local PVCs entirely.
- The recording rules in `rules-mttr.yaml` run on a 30s interval
  (`interval: 30s` in the rule group). If your cluster has thousands of
  pods, consider widening this to 1m to reduce query load, at the cost of
  coarser MTTR granularity.

## Grafana

- Two replicas by default; both read from the same PVC-backed SQLite unless
  you configure an external database (Postgres/MySQL) via
  `grafana.database` in `values.yaml` — for HA beyond a single node, an
  external DB is required (SQLite doesn't support concurrent writers across
  pods).

## HPA / VPA / KEDA tuning

- The default HPA `behavior` block (`charts/helios-app/templates/hpa.yaml`)
  scales up aggressively (0s stabilization, +4 pods per 30s) and scales down
  conservatively (120s stabilization, −1 pod per 60s) — this favors
  availability over cost during load spikes. Flip these if your workload is
  cost-sensitive and can tolerate slower response to load.
- Running VPA in `Auto` mode alongside an HPA on CPU can fight itself (VPA
  right-sizing requests changes the CPU percentage the HPA sees). This repo
  scopes VPA to `demo-api` only, where the HPA's primary trigger is the
  custom `http_requests_per_second` metric rather than CPU utilization —
  if you add VPA to a CPU-triggered HPA target, use `updateMode: "Off"`
  (recommendation-only) instead of `"Auto"`.
- KEDA's `pollingInterval` (not set explicitly here, defaults to 30s) is a
  meaningful cost/responsiveness tradeoff for Prometheus-based triggers —
  every poll is a Prometheus query.

## Loki

- `retention_period: 336h` (14 days) in `values.yaml` is deliberately short
  relative to Prometheus's 30d — logs are much higher volume than metrics.
  Extend it only after confirming your PVC/object-storage budget for Loki
  specifically.
- Promtail's `extraRelabelConfigs` add `app`/`namespace`/`container`/
  `severity` labels. Avoid adding more high-cardinality labels (e.g. request
  IDs, user IDs) as Loki labels — put those in the log line body instead and
  filter with LogQL (`|=`, `| json`), since Loki indexes by label set and
  high-cardinality labels blow up the index.

## Self-healing operator

- `RequeueAfter: 30 * time.Second` in the reconciler
  (`controllers/controllers/selfhealing_controller.go`) means every pod is
  re-checked at least every 30s even without a new watch event. On a
  cluster with tens of thousands of pods this is a meaningful constant load
  — consider sharding the operator by namespace (multiple Deployments, each
  with a namespace-scoped `--namespace` flag you'd need to add) rather than
  running one cluster-wide instance if you're operating at that scale.
