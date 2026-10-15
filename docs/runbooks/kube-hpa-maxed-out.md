# KubeHpaMaxedOut

**Severity:** warning · **Team:** platform · **Rule file:** `prometheus/rules/kube-hpa.yml`

Fires when a HorizontalPodAutoscaler has been running at its `maxReplicas`
ceiling for more than 15 minutes (`sre:kube_hpa_at_max_replicas == 1`).
HPAs pinned with `minReplicas == maxReplicas` are excluded because they sit at
max by design.

## Impact

The workload cannot scale out any further. If demand keeps rising, existing
pods absorb the extra load, so expect higher latency, CPU throttling, and
eventually errors or OOM kills. It is often an early warning before
SLO-facing alerts fire.

## Triage

```bash
NS=<namespace>; HPA=<hpa>

# Current vs desired vs min/max, plus the metrics driving the decision
kubectl -n "$NS" get hpa "$HPA"
kubectl -n "$NS" describe hpa "$HPA"

# Conditions: ScalingLimited=True with reason TooManyReplicas confirms the ceiling
kubectl -n "$NS" get hpa "$HPA" \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'

# Which workload is it scaling, and how loaded are its pods?
kubectl -n "$NS" get hpa "$HPA" -o jsonpath='{.spec.scaleTargetRef.kind}/{.spec.scaleTargetRef.name}{"\n"}'
kubectl -n "$NS" top pods
```

## Common causes

| Signal | Likely cause | Next step |
| --- | --- | --- |
| Traffic or queue depth genuinely up | Real demand above planned capacity | Raise `maxReplicas` if the cluster has room |
| CPU high but traffic flat | Regression in the latest release (hot loop, missing cache) | Compare with previous revision; roll back if needed |
| Target utilization set too low | HPA scales out at modest load | Revisit `averageUtilization` targets |
| Pod requests far below real usage | Utilization percentages inflated | Right-size container `resources.requests` |
| New replicas `Pending` | Cluster out of capacity | Check node autoscaler and node pressure alerts |

## Mitigation

1. If the load is legitimate and nodes have headroom, raise `maxReplicas`
   (in git, not with a live `kubectl edit`) and let the HPA scale out.
2. If a bad release is burning CPU, roll it back:
   `kubectl -n "$NS" rollout undo deploy/<deployment>`.
3. If replicas cannot schedule, add node capacity first; raising
   `maxReplicas` alone will only create `Pending` pods.
4. For sustained growth, update capacity planning and the HPA targets
   together so the ceiling reflects expected peak load.

## Verify

The alert resolves once current replicas drop below the ceiling:

```promql
sre:kube_hpa_at_max_replicas{namespace="<namespace>", horizontalpodautoscaler="<hpa>"}
```

```bash
kubectl -n "$NS" get hpa "$HPA" -w
```
