# helios-app

Sample microservices application used to exercise Helios's autoscaling and
resiliency features:

- **demo-api** — Go HTTP service exposing `/api/*`, HPA (CPU + memory +
  `http_requests_per_second`), VPA in `Auto` mode, and a KEDA `ScaledObject`
  driven by a Prometheus query.
- **demo-worker** — background consumer, CPU-based HPA only.
- **frontend** — Go HTTP service serving the demo UI, HPA on CPU, exposed via
  Ingress at `Values.frontend.ingress.host`.

All three deployments use `RollingUpdate` (`maxSurge: 25%`,
`maxUnavailable: 0`), readiness/liveness probes, a `preStop` hook for graceful
shutdown, an init container that waits for cluster DNS, pod anti-affinity,
and topology spread constraints — this is what makes the zero-downtime
deployment and chaos-experiment claims meaningful (see
`../../docs/architecture.md` and `../../scripts/validate-self-healing.sh`).

## Install

```bash
helm upgrade --install helios-app ./charts/helios-app \
  --set image.tag=$(git rev-parse --short HEAD) \
  --namespace helios-app --create-namespace
```

## Load-test the HPA

```bash
kubectl run load-generator --rm -i --tty --image=busybox:1.36 -- \
  /bin/sh -c "while true; do wget -q -O- http://demo-api.helios-app:8080/api/work; done"
kubectl get hpa -n helios-app -w
```
