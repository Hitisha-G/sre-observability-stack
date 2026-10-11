# KubePodNotReady

**Severity:** warning · **Team:** platform · **Rule file:** `prometheus/rules/kube-pods.yml`

Fires when a non-Job pod has stayed in `Pending`, `Unknown`, or `Failed` phase
for more than 15 minutes (`sre:kube_pod_not_ready > 0`). Job-owned pods are
excluded: a Failed Job pod is the Job controller's concern, not a stuck
workload.

## Impact

The pod is not serving traffic and will not become ready until the underlying
cause is fixed. Deployments and StatefulSets lose a replica; if every replica
is stuck, the workload is effectively down. Pending pods may also hold
scheduling capacity that other workloads need.

## Triage

```bash
NS=<namespace>; POD=<pod>

# Phase, conditions, and recent events
kubectl -n "$NS" get pod "$POD" -o wide
kubectl -n "$NS" describe pod "$POD"

# Owner and whether this is unexpectedly Job-like
kubectl -n "$NS" get pod "$POD" -o jsonpath='{.metadata.ownerReferences[*].kind}{"\n"}'

# Namespace events (scheduling, image pulls, probes, volume mounts)
kubectl -n "$NS" get events --field-selector involvedObject.name="$POD" \
  --sort-by=.lastTimestamp | tail -20
```

## Common causes

| Signal | Likely cause | Next step |
| --- | --- | --- |
| `Pending` with `FailedScheduling` | Insufficient CPU/memory or taints | Check node capacity and pod requests; adjust requests or add nodes |
| `Pending` with `Unschedulable` / PVC | Bound volume or topology mismatch | Inspect PVC/PV and storage class; verify zone affinity |
| `ImagePullBackOff` / `ErrImagePull` | Bad image tag or registry auth | Fix image reference or imagePullSecrets |
| `CreateContainerConfigError` | Missing ConfigMap or Secret | Create or rename the referenced config object |
| Phase `Failed` with OOM or exit | Container exited and restartPolicy is `Never` | Inspect last state; fix the app or use a controller that restarts |
| Phase `Unknown` | Node or kubelet unreachable | Correlate with `KubeNodeNotReady`; check the node |

## Mitigation

1. If the pod is stuck after a bad rollout, roll back the owning Deployment or
   StatefulSet and investigate the revision afterwards.
2. For scheduling pressure, temporarily lower requests or cordon unhealthy
   nodes so the scheduler can place the pod elsewhere.
3. Delete the stuck pod only when a controller will recreate it and you have
   confirmed the root cause will not immediately repeat.
4. Silence the alert in Alertmanager only with a linked ticket and an expiry.

## Verify

The alert resolves once the pod leaves Pending/Unknown/Failed (or is deleted)
and the recording rule returns no series for that pod:

```promql
sre:kube_pod_not_ready{namespace="<namespace>", pod="<pod>"}
```
