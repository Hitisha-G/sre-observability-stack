# KubeDeploymentReplicasMismatch

**Severity:** critical · **Team:** platform · **Rule file:** `prometheus/rules/kube-deployments.yml`

Fires when a Deployment has had fewer available replicas than desired for more
than 15 minutes (`sre:kube_deployment_replicas_unavailable > 0`). The recording
rule clamps at zero so a surge rollout (available above desired) does not look
like a mismatch.

## Impact

The Deployment is under capacity. Traffic may be served by fewer pods than the
spec requires; if every replica is unavailable, the workload is down. Rollouts
can stall in a partial state, and HPA or other controllers may keep scaling
against an unhealthy baseline.

## Triage

```bash
NS=<namespace>; DEP=<deployment>

# Desired vs available / ready / updated
kubectl -n "$NS" get deploy "$DEP" -o wide
kubectl -n "$NS" describe deploy "$DEP"

# ReplicaSets and which revision is active
kubectl -n "$NS" get rs -l "$(kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.selector.matchLabels}' | tr -d '{}" ' | tr ',' '\n' | paste -sd, -)" -o wide 2>/dev/null || \
  kubectl -n "$NS" get rs -o wide | grep "$DEP"

# Pods owned by this Deployment
kubectl -n "$NS" get pods -l app="$DEP" -o wide 2>/dev/null || \
  kubectl -n "$NS" get pods -o wide | grep "$DEP"

# Recent events for the Deployment and its pods
kubectl -n "$NS" get events --field-selector involvedObject.name="$DEP" \
  --sort-by=.lastTimestamp | tail -20
```

## Common causes

| Signal | Likely cause | Next step |
| --- | --- | --- |
| New ReplicaSet stuck, old still serving | Bad image, probe, or config on new revision | Inspect failing pods; roll back if needed |
| Pods `CrashLoopBackOff` / OOMKilled | App or resource limits | Correlate with `KubePodCrashLooping`; raise limits or fix the binary |
| Pods `Pending` / unschedulable | Cluster capacity or affinity | Check node pressure and scheduling events |
| `ProgressDeadlineExceeded` | Rollout hung past progressDeadlineSeconds | Fix blockers or roll back; then re-deploy |
| Available below desired after scale-up | New replicas cannot become Ready | Check readiness probes, PDBs, and PVC binding |
| Mismatch only during deploy, then clears | Normal surge window shorter than `for: 15m` | Confirm; if noisy, tune surge or the alert `for` |

## Mitigation

1. If a bad revision is active, roll back:
   `kubectl -n "$NS" rollout undo deploy/"$DEP"`.
2. For capacity issues, add nodes or temporarily lower requests so new pods can
   schedule; then restore sane requests.
3. Fix readiness/liveness probes or missing Secrets/ConfigMaps that keep pods
   from becoming Ready.
4. Silence in Alertmanager only with a linked ticket and an expiry while you
   work the fix.

## Verify

The alert resolves once available replicas meet or exceed desired and the
recording rule returns no positive series for that Deployment:

```promql
sre:kube_deployment_replicas_unavailable{namespace="<namespace>", deployment="<deployment>"}
```

Confirm the rollout finished:

```bash
kubectl -n "$NS" rollout status deploy/"$DEP"
```
