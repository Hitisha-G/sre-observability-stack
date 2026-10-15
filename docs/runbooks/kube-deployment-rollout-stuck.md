# KubeDeploymentRolloutStuck

**Severity:** warning · **Team:** platform · **Rule file:** `prometheus/rules/kube-deployments.yml`

Fires when a Deployment rollout has not made progress for more than 15 minutes.
Either of two signals is enough:

- `sre:kube_deployment_generation_lag > 0` — `metadata.generation` is ahead of
  `status.observedGeneration`, so the controller has not acted on the latest spec.
- `kube_deployment_status_condition{condition="Progressing", status="false"}` —
  the controller gave up after `progressDeadlineSeconds`
  (reason `ProgressDeadlineExceeded`).

## Impact

The new revision is not fully rolled out. Old pods may still be serving the
previous version, a config or security fix may not be live, and later deploys
queue up behind the stuck one. Capacity can also be reduced if new pods are
failing while old ones are scaled down. Pair with `KubeDeploymentReplicasMismatch`
to judge whether users are affected.

## Triage

```bash
NS=<namespace>; DEP=<deployment>

# Generation vs observedGeneration, and the Progressing condition
kubectl -n "$NS" get deploy "$DEP" \
  -o jsonpath='{.metadata.generation}{" observed="}{.status.observedGeneration}{"\n"}'
kubectl -n "$NS" get deploy "$DEP" \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'

# Rollout state and history
kubectl -n "$NS" rollout status deploy/"$DEP" --timeout=10s
kubectl -n "$NS" rollout history deploy/"$DEP"

# Is the rollout paused?
kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.paused}{"\n"}'

# New vs old ReplicaSets and recent events
kubectl -n "$NS" get rs -o wide | grep "$DEP"
kubectl -n "$NS" get events --field-selector involvedObject.name="$DEP" \
  --sort-by=.lastTimestamp | tail -20
```

## Common causes

| Signal | Likely cause | Next step |
| --- | --- | --- |
| `Progressing=False`, reason `ProgressDeadlineExceeded` | New pods never become Ready (bad image, probe, config) | Inspect new ReplicaSet pods; roll back if needed |
| `spec.paused: true` | Someone ran `kubectl rollout pause` | Confirm intent, then `kubectl rollout resume` |
| Generation lag persists, no events | kube-controller-manager down or unhealthy | Check control-plane health and controller-manager logs |
| New pods `Pending` | Quota, capacity, or affinity blocks scheduling | Check `ResourceQuota`, node pressure, scheduling events |
| `ImagePullBackOff` on new pods | Wrong tag or registry auth | Fix image reference or pull secret |
| Rollout blocked by PDB / maxUnavailable=0 | Surge pods cannot schedule, old pods cannot be evicted | Add capacity or adjust surge / PDB settings |

## Mitigation

1. If the new revision is bad, roll back:
   `kubectl -n "$NS" rollout undo deploy/"$DEP"`.
2. If the rollout was paused intentionally, either resume it or silence the
   alert with a linked ticket and an expiry.
3. For control-plane lag, restore kube-controller-manager health first; the
   generation lag clears once it reconciles.
4. Fix the blocker (quota, image, probe, capacity) and re-apply the manifest.

## Verify

The alert resolves once the controller has observed the latest generation and
`Progressing` is back to `True`:

```promql
sre:kube_deployment_generation_lag{namespace="<namespace>", deployment="<deployment>"}
kube_deployment_status_condition{namespace="<namespace>", deployment="<deployment>", condition="Progressing", status="false"}
```

Confirm the rollout finished:

```bash
kubectl -n "$NS" rollout status deploy/"$DEP"
```
