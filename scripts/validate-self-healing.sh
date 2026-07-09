#!/usr/bin/env bash
# End-to-end validation: forces a pod failure, watches Kubernetes/Helios
# remediate it, and records the time to recovery as an MTTR sample.
# Usage: ./scripts/validate-self-healing.sh [--ci]
set -euo pipefail

CI_MODE=false
[[ "${1:-}" == "--ci" ]] && CI_MODE=true

NAMESPACE="helios-app"
TARGET_APP="demo-api"
REPORT_FILE="/tmp/helios-mttr-report.json"

echo "==> [1/4] Confirming baseline: $TARGET_APP pods are Ready"
kubectl wait --for=condition=Ready pod -l app="$TARGET_APP" -n "$NAMESPACE" --timeout=60s

echo "==> [2/4] Recording HPA replica count before load"
BEFORE_REPLICAS=$(kubectl get hpa "${TARGET_APP}-hpa" -n "$NAMESPACE" -o jsonpath='{.status.currentReplicas}')
echo "    current replicas: $BEFORE_REPLICAS"

echo "==> [3/4] Injecting a pod failure and timing recovery"
TARGET_POD=$(kubectl get pod -l app="$TARGET_APP" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')
START_TS=$(date +%s)
kubectl delete pod "$TARGET_POD" -n "$NAMESPACE" --wait=false
kubectl wait --for=condition=Ready pod -l app="$TARGET_APP" -n "$NAMESPACE" --timeout=120s
END_TS=$(date +%s)
MTTR_SECONDS=$((END_TS - START_TS))
echo "    recovered in ${MTTR_SECONDS}s"

echo "==> [4/4] Recording HPA replica count after"
AFTER_REPLICAS=$(kubectl get hpa "${TARGET_APP}-hpa" -n "$NAMESPACE" -o jsonpath='{.status.currentReplicas}')

cat > "$REPORT_FILE" <<EOF
{
  "target_app": "$TARGET_APP",
  "namespace": "$NAMESPACE",
  "mttr_seconds": $MTTR_SECONDS,
  "replicas_before": $BEFORE_REPLICAS,
  "replicas_after": $AFTER_REPLICAS,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo ""
echo "Report written to $REPORT_FILE:"
cat "$REPORT_FILE"

if [ "$MTTR_SECONDS" -gt 90 ]; then
  echo "WARNING: recovery took longer than 90s; investigate before trusting the MTTR dashboard."
  $CI_MODE && exit 1
fi
echo "Self-healing validation passed."
