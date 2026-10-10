# KubeNodePIDPressure

**Severity:** warning · **Team:** platform · **Rule file:** `prometheus/rules/kube-nodes.yml`

Fires when a node's `PIDPressure` condition has been `True` for more than
5 minutes (`sre:kube_node_pid_pressure == 1`).

## Impact

The kubelet cannot allocate process IDs for new pods or containers. Workloads
that need to start or restart fail while existing processes keep running. A
runaway fork storm on the node can starve every namespace sharing that host.

## Triage

```bash
NODE=<node>

# Confirm PIDPressure and related conditions
kubectl get node "$NODE" -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'

# Allocatable and capacity for pods / PIDs when exposed
kubectl describe node "$NODE" | sed -n '/Conditions:/,/Addresses:/p;/Allocated resources:/,/Events:/p'

# Pods on the node (look for high container counts or CrashLoops)
kubectl get pods -A --field-selector spec.nodeName="$NODE" -o wide

# Recent node and eviction events
kubectl get events -A --field-selector involvedObject.kind=Node,involvedObject.name="$NODE" \
  --sort-by=.lastTimestamp | tail -20
```

If you can reach the host:

```bash
# Process and thread counts
ps -eLf | wc -l
cat /proc/sys/kernel/pid_max
# Top process creators
ps -eo user,pid,ppid,nlwp,cmd --sort=-nlwp | head -25
journalctl -u kubelet --since "30 min ago" | grep -iE 'pid|fork|process' | tail -50
```

## Common causes

| Signal | Likely cause | Next step |
| --- | --- | --- |
| One pod with thousands of threads | Runaway fork or thread leak | Delete or scale that pod; fix the app limits |
| Many short-lived Job pods | Burst of Jobs on one node | Spread Jobs or raise node PID capacity |
| Low `podPidsLimit` / cgroup pid max | Node reserved too few PIDs | Raise kubelet `--pod-max-pids` or instance size |
| Several nodes at once | Cluster-wide process storm | Cordon affected nodes and scale the node group |

## Mitigation

1. Cordon the node: `kubectl cordon "$NODE"`.
2. Identify and stop the highest `nlwp` / fork offenders (prefer non-critical
   workloads first).
3. If pressure does not clear, drain and replace the node:
   `kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data`, then
   terminate the instance so the node group replaces it.
4. Follow up with `--pod-max-pids`, larger nodes, or app-level process limits so
   the same node type does not trip PIDPressure again.

## Verify

The alert resolves once `PIDPressure` is false and the recording rule returns
`0` for the node:

```promql
sre:kube_node_pid_pressure{node="<node>"}
```

Remember to `kubectl uncordon "$NODE"` if you kept the original node.
