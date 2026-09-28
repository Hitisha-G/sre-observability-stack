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
  rules/                    # recording + alerting rules
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

Scaffolding the repo and CI first. Compose stack, rule packs, and sample dashboards land in follow-up commits.
