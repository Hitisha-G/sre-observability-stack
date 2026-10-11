# KubeNodeDiskPressure

**Severity:** warning · **Team:** platform · **Rule file:** `prometheus/rules/kube-nodes.yml`

Fires when a node's `DiskPressure` condition has been `True` for more than
5 minutes (`sre:kube_node_disk_pressure == 1`).

## Impact

The kubelet evicts pods to free filesystem space on the node (usually the
image or container writable layer filesystem). New pods may fail to pull
images or start. Workloads that rely on emptyDir or local logs can lose data
when those volumes are cleaned up during eviction.

## Triage

```bash
NODE=<node>

# Confirm DiskPressure and related conditions
kubectl get node "$NODE" -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'

# Allocatable ephemeral storage and current allocation hints
kubectl describe node "$NODE" | sed -n '/Conditions:/,/Addresses:/p;/Allocated resources:/,/Events:/p'

# Pods on the node (look for large emptyDir / logs / image layers)
kubectl get pods -A --field-selector spec.nodeName="$NODE" -o wide

# Eviction and disk-related events
kubectl get events -A --field-selector involvedObject.kind=Node,involvedObject.name="$NODE" \
  --sort-by=.lastTimestamp | tail -20
```

If you can reach the host:

```bash
df -h
du -xh /var/lib/containerd /var/lib/docker /var/log 2>/dev/null | sort -h | tail -30
journalctl -u kubelet --since "30 min ago" | grep -iE 'evict|disk|filesystem|image' | tail -50
```

## Common causes

| Signal | Likely cause | Next step |
| --- | --- | --- |
| Full `/var/lib/containerd` or Docker root | Unused images and layers | Prune unused images; tighten GC thresholds |
| Large emptyDir or hostPath volumes | App writing unbounded local data | Move data to a PVC; add size limits on emptyDir |
| Log volume filling up | Verbose app or system logs | Rotate/truncate logs; ship logs off-node |
| Several nodes at once | Shared storage or image pull storm | Check registry/mirror and node-group disk size |
| Pressure after a big rollout | Many new image layers retained | Raise disk size or reduce concurrent pulls |

## Mitigation

1. Cordon the node: `kubectl cordon "$NODE"`.
2. Free space safely: prune unused images on the node, truncate runaway logs,
   or delete non-critical pods that hold large emptyDir volumes.
3. If pressure does not clear, drain and replace the node:
   `kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data`, then
   terminate the instance so the node group replaces it.
4. Follow up with larger root volumes, image GC tuning, or moving stateful
   writes onto PVCs so the same node type does not trip DiskPressure again.

## Verify

The alert resolves once `DiskPressure` is false and the recording rule
returns `0` for the node:

```promql
sre:kube_node_disk_pressure{node="<node>"}
```

Remember to `kubectl uncordon "$NODE"` if you kept the original node.
