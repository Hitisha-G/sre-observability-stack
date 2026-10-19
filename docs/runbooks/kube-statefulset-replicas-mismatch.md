# KubeStatefulSetReplicasMismatch

**Severity:** warning · **Team:** platform · **Rule file:** `prometheus/rules/kube-statefulsets.yml`

Fires when a StatefulSet has fewer ready pods than `spec.replicas` for 15
minutes **and** `status.updatedReplicas` has not changed in the last 10
minutes. StatefulSets update one ordinal at a time and wait for each pod to be
ready before moving on, so a pod that never becomes ready blocks the whole
rollout. The progress check keeps a slow but healthy rolling update quiet.

The alert reads `sre:kube_statefulset_replicas_not_ready` (desired minus ready,
clamped at zero), so `{{ $value }}` is the number of missing pods.

## Impact

Stateful workloads usually run with quorum or replication: one missing pod
often means reduced redundancy, and a second failure can mean lost quorum
(etcd, ZooKeeper, Kafka controllers) or a database with no standby. The
rollout will not continue past the stuck ordinal until it is fixed.

## Triage

```bash
NS=<namespace>; STS=<statefulset>

kubectl -n "$NS" get statefulset "$STS" -o wide
kubectl -n "$NS" rollout status statefulset "$STS" --timeout=5s
kubectl -n "$NS" get pods -l "$(kubectl -n "$NS" get sts "$STS" -o jsonpath='{.spec.selector.matchLabels}' | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")')" -o wide

# The highest-ordinal pod that is not Ready is usually the one blocking
kubectl -n "$NS" describe pod "$STS-<ordinal>"
kubectl -n "$NS" logs "$STS-<ordinal>" --previous --tail=100

# Volume problems show up on the claim, not the pod
kubectl -n "$NS" get pvc -l "$(kubectl -n "$NS" get sts "$STS" -o jsonpath='{.spec.selector.matchLabels}' | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")')"
kubectl -n "$NS" get events --field-selector involvedObject.name="$STS-<ordinal>" --sort-by=.lastTimestamp
```

## Common causes

| Signal | Likely cause | Next step |
| --- | --- | --- |
| Pod `Pending`, event `FailedScheduling` with volume node affinity conflict | The pod's PV is in another AZ than the nodes with free capacity | Add capacity in that AZ or use a topology-aware StorageClass |
| Pod `ContainerCreating`, event `FailedAttachVolume` / `Multi-Attach error` | EBS volume still attached to the old node | Wait for detach, or cordon and drain the old node if it is gone |
| `CrashLoopBackOff` after an image change | New version fails on existing data or config | Roll back the image; see [kube-pod-crash-looping](kube-pod-crash-looping.md) |
| Running but readiness probe failing | Replica cannot join the cluster or catch up on replication | Check app logs for peer discovery or replication errors |
| `podManagementPolicy: OrderedReady` and a lower ordinal is down | Higher ordinals wait for lower ones | Fix the lowest not-ready ordinal first |

## Mitigation

1. If the rollout introduced the problem, revert the spec change in git (or
   `kubectl -n "$NS" rollout undo statefulset "$STS"` in an emergency). With
   the default `RollingUpdate` strategy you may also need to delete the stuck
   pod so the controller recreates it on the old revision.
2. For volume attach or AZ problems, fix the node or capacity issue; do not
   delete the PVC, since that deletes the pod's data.
3. For quorum systems, confirm the remaining members are healthy before
   restarting anything else in the set.

## Verify

```promql
sre:kube_statefulset_replicas_not_ready{namespace="<namespace>", statefulset="<statefulset>"}
```

```bash
kubectl -n "$NS" rollout status statefulset "$STS"
```

The alert resolves once every desired replica is ready.
