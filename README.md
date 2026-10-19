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
    kube-volumes.yml        # PVCs filling up (trend-based) or almost full
    kube-statefulsets.yml   # StatefulSets short of ready replicas with a stalled rollout
grafana/
  dashboards/               # JSON dashboards checked into git
otel/
  collector-config.yaml     # OTLP → Prometheus / Tempo path
.github/workflows/          # lint rules, validate dashboards
docs/
  runbooks/                 # short pages linked from alerts
```

Default demo region mindset matches India-friendly labs (`ap-south-1` style naming in examples). Nothing here requires a live cluster to start reading the configs.

## Alert catalog

Every alert carries `severity`, `team`, and `component` labels, a `summary` annotation, and a `runbook_url` that points at a page in this repo. `for` is how long the condition must hold before the alert fires.

| Alert | Rule pack | Severity | For | Runbook |
| --- | --- | --- | --- | --- |
| KubePodCrashLooping | `kube-pods.yml` | warning | 15m | [kube-pod-crash-looping](docs/runbooks/kube-pod-crash-looping.md) |
| KubePodNotReady | `kube-pods.yml` | warning | 15m | [kube-pod-not-ready](docs/runbooks/kube-pod-not-ready.md) |
| KubeDeploymentReplicasMismatch | `kube-deployments.yml` | critical | 15m | [kube-deployment-replicas-mismatch](docs/runbooks/kube-deployment-replicas-mismatch.md) |
| KubeDeploymentRolloutStuck | `kube-deployments.yml` | warning | 15m | [kube-deployment-rollout-stuck](docs/runbooks/kube-deployment-rollout-stuck.md) |
| KubeNodeNotReady | `kube-nodes.yml` | critical | 10m | [kube-node-not-ready](docs/runbooks/kube-node-not-ready.md) |
| KubeNodeDiskPressure | `kube-nodes.yml` | warning | 5m | [kube-node-disk-pressure](docs/runbooks/kube-node-disk-pressure.md) |
| KubeNodeMemoryPressure | `kube-nodes.yml` | warning | 5m | [kube-node-memory-pressure](docs/runbooks/kube-node-memory-pressure.md) |
| KubeNodePIDPressure | `kube-nodes.yml` | warning | 5m | [kube-node-pid-pressure](docs/runbooks/kube-node-pid-pressure.md) |
| KubeHpaMaxedOut | `kube-hpa.yml` | warning | 15m | [kube-hpa-maxed-out](docs/runbooks/kube-hpa-maxed-out.md) |
| KubeJobFailed | `kube-jobs.yml` | warning | 5m | [kube-job-failed](docs/runbooks/kube-job-failed.md) |
| KubePersistentVolumeFillingUp | `kube-volumes.yml` | warning | 1h | [kube-persistent-volume-filling-up](docs/runbooks/kube-persistent-volume-filling-up.md) |
| KubePersistentVolumeAlmostFull | `kube-volumes.yml` | critical | 5m | [kube-persistent-volume-filling-up](docs/runbooks/kube-persistent-volume-filling-up.md) |
| KubeStatefulSetReplicasMismatch | `kube-statefulsets.yml` | warning | 15m | [kube-statefulset-replicas-mismatch](docs/runbooks/kube-statefulset-replicas-mismatch.md) |

Critical alerts mean user-facing impact is likely now (a node is gone, a Deployment is short of replicas, a volume is about to stop accepting writes). Warnings are things to fix during working hours before they turn critical.

## Running the checks locally

The `Makefile` mirrors the CI jobs, so a green `make ci` locally should mean a green push.

| Target | What it checks | Needs |
| --- | --- | --- |
| `make lint` | shellcheck on `tests/*.sh` | `shellcheck` |
| `make test` | every alert has severity, team, and component labels, a summary, a runbook_url, and a non-empty `for:`; alert names are unique | `bash`, `python3` + PyYAML |
| `make runbooks` | every in-repo `runbook_url` points at a file that exists | `bash` |
| `make coverage` | every rule file under `prometheus/rules/` has a matching `tests/promtool/*.test.yml` | `bash` |
| `make rules` | `promtool check rules` for PromQL and rule syntax; lint findings such as duplicate rules fail the run | `promtool` |
| `make promtool-test` | promtool unit tests that replay series and assert which alerts fire; set `PROMTOOL_JUNIT=out.xml` for a JUnit report (CI uploads it as an artifact) | `promtool` |

`promtool` ships in the Prometheus release tarball; drop it on your `PATH` or run the last two targets through `docker run --rm -v "$PWD":/w -w /w --entrypoint promtool prom/prometheus ...`.

### Adding an alert

1. Add the rule to the matching pack in `prometheus/rules/` (or a new `kube-<thing>.yml`).
2. Write a runbook in `docs/runbooks/` and point `runbook_url` at it.
3. Add firing and non-firing cases to `tests/promtool/<pack>.test.yml`.
4. Add a row to the alert catalog above, then run `make ci`.

## Status

Alert rules cover kube-pods, kube-deployments, kube-nodes, kube-hpa, kube-jobs, kube-volumes, and kube-statefulsets, each with a runbook and promtool unit tests (see the catalog above). Compose stack, dashboards, and more rule packs land in follow-up commits.
