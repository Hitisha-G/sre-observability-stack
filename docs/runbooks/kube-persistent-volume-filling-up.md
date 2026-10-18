# KubePersistentVolumeFillingUp / KubePersistentVolumeAlmostFull

**Severity:** warning / critical · **Team:** platform · **Rule file:** `prometheus/rules/kube-volumes.yml`

Both alerts read `sre:kube_pvc_available_ratio`, the free fraction of a
PersistentVolumeClaim from the kubelet's `kubelet_volume_stats_*` metrics.

- **KubePersistentVolumeFillingUp** (warning) fires when a PVC has less than
  15% free **and** a linear projection of the last 6h says it will be full
  within 4 days, held for 1h. A volume that is low but not growing stays quiet.
- **KubePersistentVolumeAlmostFull** (critical) fires when a PVC has less than
  3% free for 5 minutes, regardless of trend.

`ReadOnlyMany` claims are excluded from both, since nothing can write to them.

## Impact

When the volume fills, writes fail: databases go read-only or crash, queues
stop accepting messages, and apps that log to the volume can fail health
checks. Recovery after the disk is full is slower than acting on the warning.

## Triage

```bash
NS=<namespace>; PVC=<persistentvolumeclaim>

# Size, storage class, and whether the class allows online expansion
kubectl -n "$NS" get pvc "$PVC" -o wide
SC="$(kubectl -n "$NS" get pvc "$PVC" -o jsonpath='{.spec.storageClassName}')"
kubectl get storageclass "$SC" -o jsonpath='{.allowVolumeExpansion}{"\n"}'

# Which pod mounts it, then what is using the space
kubectl -n "$NS" get pods -o json \
  | jq -r --arg pvc "$PVC" '.items[] | select(any(.spec.volumes[]?; .persistentVolumeClaim.claimName == $pvc)) | .metadata.name'
kubectl -n "$NS" exec <pod> -- df -h <mount-path>
kubectl -n "$NS" exec <pod> -- sh -c 'du -xh <mount-path> 2>/dev/null | sort -h | tail -20'
```

Growth rate over the last day, in bytes per hour:

```promql
deriv(kubelet_volume_stats_available_bytes{namespace="<namespace>", persistentvolumeclaim="<pvc>"}[1d]) * 3600
```

## Common causes

| Signal | Likely cause | Next step |
| --- | --- | --- |
| Steady growth over days | Normal data growth outpacing the original size | Expand the PVC and revisit sizing |
| Sudden step up | Bulk import, backfill, or a one-off dump written to the volume | Confirm with the owning team, clean up or expand |
| Many small files under a log or tmp path | Logs or temp files not rotated | Add rotation or move logs to stdout |
| Database WAL / binlog directory is large | Replication slot or replica lagging, archiving broken | Fix replication or archiving before deleting anything |
| Old snapshots or backups on the same volume | Retention job not running | Restore retention, move backups to object storage |

## Mitigation

1. If the StorageClass has `allowVolumeExpansion: true`, grow the claim in
   git and apply it, or patch it directly in an emergency:
   `kubectl -n "$NS" patch pvc "$PVC" -p '{"spec":{"resources":{"requests":{"storage":"<new-size>"}}}}'`.
   Most CSI drivers (EBS gp3 included) expand online; some need a pod restart
   to resize the filesystem.
2. If expansion is not allowed, free space by removing data the owning team
   confirms is safe to delete, then plan a migration to a larger volume.
3. Never delete database WAL or binlog files by hand; fix the replica or
   archiving that is holding them.

## Verify

Both alerts resolve once free space is back above the thresholds:

```promql
sre:kube_pvc_available_ratio{namespace="<namespace>", persistentvolumeclaim="<pvc>"}
```

```bash
kubectl -n "$NS" get pvc "$PVC"
```
