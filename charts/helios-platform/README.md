# helios-platform

Deploys the self-healing operator and shared platform primitives
(namespace, RBAC, NetworkPolicy, PodDisruptionBudget, ResourceQuota,
ConfigMap). See `../../controllers/` for the operator source and
`../../docs/architecture.md` for how it fits with helios-infrastructure and
helios-app.

## Install

```bash
helm upgrade --install helios-platform ./charts/helios-platform \
  --set selfHealingOperator.image.tag=$(git rev-parse --short HEAD)
```
