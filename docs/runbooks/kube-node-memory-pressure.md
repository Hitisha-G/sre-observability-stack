# KubeNodeMemoryPressure

**Severity:** warning · **Team:** platform · **Rule file:** `prometheus/rules/kube-nodes.yml`

Fires when a node's `MemoryPressure` condition has been `True` for more than
5 minutes (`sre:kube_node_memory_pressure == 1`).

## Impact

The kubelet starts evicting pods to reclaim memory. New pods that request
memory may fail to schedule on this node. Workloads without enough spare
replicas elsewhere can lose capacity or go down until pressure clears.

## Triage

```bash
NODE=<node>

# Confirm MemoryPressure and related conditions
kubectl get node "$NODE" -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'

# Allocatable memory vs capacity and current usage hints
kubectl describe node "$NODE" | sed -n '/Conditions:/,/Addresses:/p;/Allocated resources:/,/Events:/p'

# Pods on the node sorted by memory requests (spot the heavy ones)
kubectl get pods -A --field-selector spec.nodeName="$NODE" -o wide

# Eviction and OOM-related events
kubectl get events -A --field-selector involvedObject.kind=Node,involvedObject.name="$NODE" \
  --sort-by=.lastTimestamp | tail -20
```

If you can reach the host:

```bash
free -h
ps aux --sort=-%mem | head -20
journalctl -u kubelet --since "30 min ago" | grep -iE 'evict|memory|oom' | tail -50
```

## Common causes

| Signal | Likely cause | Next step |
| --- | --- | --- |
| High pod memory requests vs allocatable | Node oversubscribed | Cordon, drain large pods, or scale the node group |
| Many `OOMKilled` pods on the node | Leaky or under-limited containers | Raise limits or fix the leak; see CrashLoop runbook if they restart |
| DaemonSets + system reserved too low | Host OS / kubelet starved | Tune `--system-reserved` / `--kube-reserved` or use a larger instance |
| Sudden spike after a rollout | New revision uses more memory | Roll back or reduce replica count on that node |
| Several nodes at once | Cluster-wide memory demand | Scale out node groups before draining individuals |

## Mitigation

1. Cordon the node: `kubectl cordon "$NODE"`.
2. Identify and delete or reschedule the heaviest pods (prefer non-critical
   workloads first).
3. If pressure does not clear, drain and replace the node:
   `kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data`, then
   terminate the instance so the node group replaces it.
4. Follow up with right-sizing requests/limits or larger instance types so the
   same node type does not trip MemoryPressure again.

## Verify

The alert resolves once `MemoryPressure` is false and the recording rule
returns `0` for the node:

```promql
sre:kube_node_memory_pressure{node="<node>"}
```

Remember to `kubectl uncordon "$NODE"` if you kept the original node.
