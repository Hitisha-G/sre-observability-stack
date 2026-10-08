# KubeNodeNotReady

**Severity:** critical · **Team:** platform · **Rule file:** `prometheus/rules/kube-nodes.yml`

Fires when a node's `Ready` condition has been `False` or `Unknown` for more
than 10 minutes (`sre:kube_node_not_ready == 1`).

- `Ready=False`: the kubelet is reporting, but says the node is unhealthy
  (container runtime down, network plugin not ready, resource pressure).
- `Ready=Unknown`: the control plane has stopped hearing from the kubelet
  entirely (instance stopped, network partition, kubelet crashed).

## Impact

The scheduler stops placing new pods on the node. After the default
`tolerationSeconds` (300s) for `node.kubernetes.io/not-ready` and
`node.kubernetes.io/unreachable`, pods are evicted and rescheduled elsewhere,
so the cluster loses that node's capacity. Workloads with a single replica,
local volumes, or tight PodDisruptionBudgets may go down until it recovers.

## Triage

```bash
NODE=<node>

# Conditions, last heartbeat, taints, and allocated resources
kubectl describe node "$NODE"

# Which condition is unhealthy and why
kubectl get node "$NODE" -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'

# Pods still bound to the node
kubectl get pods -A --field-selector spec.nodeName="$NODE" -o wide

# Node-level events (kubelet restarts, pressure, network)
kubectl get events -A --field-selector involvedObject.kind=Node,involvedObject.name="$NODE" \
  --sort-by=.lastTimestamp | tail -20
```

If you can reach the host (SSM Session Manager on EKS, or SSH):

```bash
systemctl status kubelet containerd
journalctl -u kubelet --since "30 min ago" | tail -100
df -h /var/lib/kubelet /var/lib/containerd
```

## Common causes

| Signal | Likely cause | Next step |
| --- | --- | --- |
| `Ready=Unknown`, reason `NodeStatusUnknown` | Instance stopped, terminated, or network partitioned | Check the EC2 instance state and its Auto Scaling group activity |
| `Ready=False`, reason mentions `PLEG is not healthy` | Container runtime hung or overloaded | Restart `containerd`, then `kubelet`; look for runaway pod counts |
| `NetworkPluginNotReady` / CNI errors | VPC CNI or other CNI daemonset not running on the node | `kubectl -n kube-system get pods -o wide \| grep "$NODE"` and check the CNI pod logs |
| `DiskPressure` or `MemoryPressure` also true | Node out of disk or memory | See [KubeNodeDiskPressure](kube-node-disk-pressure.md); prune images or resize the volume |
| Kubelet certificate errors in the journal | Expired or rotated client certificate | Restart kubelet so it re-bootstraps, or replace the node |
| Many nodes at once | Control-plane or AZ-wide issue, not the node | Check API server health and the cloud provider status page before touching nodes |

## Mitigation

1. Cordon the node so nothing new lands on it while you investigate:
   `kubectl cordon "$NODE"`.
2. If the host is reachable, restart the container runtime and kubelet.
3. If it does not recover within a few minutes, drain and replace it rather
   than nursing it back:
   `kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data`, then
   terminate the instance and let the node group bring up a fresh one.
4. If several nodes are affected together, stop and escalate; replacing nodes
   will not fix a control-plane or network outage.

## Verify

The alert resolves once the node reports `Ready=True` and the recording rule
returns `0` for it:

```promql
sre:kube_node_not_ready{node="<node>"}
```

Remember to `kubectl uncordon "$NODE"` if you kept the original node.
