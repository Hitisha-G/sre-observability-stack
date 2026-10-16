# sre-observability-stack

Practical SRE observability foundation: metrics, logs, traces, and alerting wired for Kubernetes workloads.

Aimed at platform / SRE workflows — local compose for demos, Helm values for cluster installs, and CI that keeps dashboards and alert rules reviewable.

## Goals

- One place to version Prometheus / Grafana / Alertmanager config
- OpenTelemetry collector examples that export to the same stack
- Alert rule packs with runbook links, not just threshold noise
- CI checks so invalid PromQL or broken dashboard JSON fail the push

## Planned layout

```
docker-compose.yml          # local Prometheus + Grafana + Alertmanager (next)
helm/                       # chart values overlays for cluster installs
prometheus/
  rules/                    # alerting rule packs by workload type
    kube-pods.yml           # CrashLoopBackOff and pod not-ready (Job pods excluded)
    kube-deployments.yml    # replica mismatch and rollout alerts
    kube-nodes.yml          # NotReady, DiskPressure, MemoryPressure, PIDPressure
    kube-hpa.yml            # HPA running at its maxReplicas ceiling
    kube-jobs.yml           # Jobs that reached the terminal Failed condition
grafana/
  dashboards/               # JSON dashboards checked into git
otel/
  collector-config.yaml     # OTLP → Prometheus / Tempo path
.github/workflows/          # lint rules, validate dashboards
docs/
  runbooks/                 # short pages linked from alerts
```

Default demo region mindset matches India-friendly labs (`ap-south-1` style naming in examples). Nothing here requires a live cluster to start reading the configs.

## Status

Alert rules cover kube-pods, kube-deployments, kube-nodes, kube-hpa, and kube-jobs. Runbooks live in `docs/runbooks/`, including [KubePodCrashLooping](docs/runbooks/kube-pod-crash-looping.md), [KubePodNotReady](docs/runbooks/kube-pod-not-ready.md), [KubeNodeNotReady](docs/runbooks/kube-node-not-ready.md), [KubeNodeMemoryPressure](docs/runbooks/kube-node-memory-pressure.md), [KubeNodePIDPressure](docs/runbooks/kube-node-pid-pressure.md), and [KubeNodeDiskPressure](docs/runbooks/kube-node-disk-pressure.md), plus [KubeDeploymentReplicasMismatch](docs/runbooks/kube-deployment-replicas-mismatch.md), [KubeDeploymentRolloutStuck](docs/runbooks/kube-deployment-rollout-stuck.md), [KubeHpaMaxedOut](docs/runbooks/kube-hpa-maxed-out.md), and [KubeJobFailed](docs/runbooks/kube-job-failed.md). Every rule pack now has promtool unit tests under `tests/promtool/` (run `make promtool-test`), including NotReady, Ready=unknown, and pressure-condition cases for kube-nodes. Compose stack, dashboards, and more rule packs land in follow-up commits.
