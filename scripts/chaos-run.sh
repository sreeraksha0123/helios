#!/usr/bin/env bash
# Applies (or re-applies) the chaos experiment suite and prints their status.
# Run this on-demand, or let .github/workflows/chaos-test.yml schedule it.
set -euo pipefail

echo "==> Applying chaos experiments"
kubectl apply -f chaos/experiments/
kubectl apply -f chaos/schedules/

echo "==> Current PodChaos experiments"
kubectl get podchaos -n helios-app -o wide || true
echo "==> Current NetworkChaos experiments"
kubectl get networkchaos -n helios-app -o wide || true
echo "==> Current StressChaos experiments"
kubectl get stresschaos -n helios-app -o wide || true

echo "Chaos suite applied. Watch: kubectl get events -n helios-app --watch"
