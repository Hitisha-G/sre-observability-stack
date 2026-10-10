# KubePodCrashLooping

**Severity:** warning · **Team:** platform · **Rule file:** `prometheus/rules/kube-pods.yml`

Fires when a container has been in `CrashLoopBackOff` for more than 15 minutes
(`sre:kube_pod_crashloop == 1`).

## Impact

The pod keeps restarting and is not serving traffic. If every replica of a
Deployment is affected, the workload is effectively down; otherwise capacity
is reduced and remaining replicas carry extra load.

## Triage

```bash
NS=<namespace>; POD=<pod>; CTR=<container>

# Restart count, last state, exit code, and reason
kubectl -n "$NS" describe pod "$POD"

# Logs from the crashed attempt, not the current one
kubectl -n "$NS" logs "$POD" -c "$CTR" --previous --tail=200

# Recent events in the namespace (image pulls, probes, OOM, scheduling)
kubectl -n "$NS" get events --sort-by=.lastTimestamp | tail -20
```

## Common causes

| Signal | Likely cause | Next step |
| --- | --- | --- |
| Exit code `137`, reason `OOMKilled` | Memory limit too low or a leak | Compare usage to `resources.limits.memory`; raise the limit or fix the leak |
| Exit code `1` with a stack trace | Application error on startup | Check config, env vars, and secrets referenced by the pod |
| Liveness probe failures in events | Probe too aggressive or wrong path/port | Increase `initialDelaySeconds` or add a `startupProbe` |
| `CreateContainerConfigError` before the loop | Missing ConfigMap or Secret | `kubectl -n "$NS" get cm,secret` and verify the referenced names |
| Started right after a rollout | Bad image or config in the new revision | `kubectl -n "$NS" rollout undo deploy/<name>` |

## Mitigation

1. If a recent rollout caused it, roll back first and investigate afterwards.
2. If it is resource-related, patch the limit temporarily and open a follow-up
   to right-size it.
3. Silence the alert in Alertmanager only with a linked ticket and an expiry.

## Verify

The alert resolves once the container stays `Running` and the recording rule
returns no series for that pod:

```promql
sre:kube_pod_crashloop{namespace="<namespace>", pod="<pod>"}
```
