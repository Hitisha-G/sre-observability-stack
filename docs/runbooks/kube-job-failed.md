# KubeJobFailed

**Severity:** warning · **Team:** platform · **Rule file:** `prometheus/rules/kube-jobs.yml`

Fires when a Kubernetes Job has held the terminal `Failed` condition for more
than 5 minutes (`sre:kube_job_failed == 1`, from
`kube_job_failed{condition="true"}`). A Job only reaches `Failed` after it
exhausts `backoffLimit` or runs past `activeDeadlineSeconds`; pods that fail and
are retried successfully do not trigger this alert.

## Impact

The work the Job was meant to do did not happen: a backup, migration, report,
or batch run is missing. Kubernetes will not retry it. For CronJobs, the next
scheduled run may succeed, but anything depending on this run (restores,
downstream data, reconciliations) is now stale.

## Triage

```bash
NS=<namespace>; JOB=<job_name>

# Status, completions, and the failure reason on the Job condition
kubectl -n "$NS" get job "$JOB"
kubectl -n "$NS" get job "$JOB" \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'

# Owning CronJob, if any
kubectl -n "$NS" get job "$JOB" -o jsonpath='{.metadata.ownerReferences[*].kind}/{.metadata.ownerReferences[*].name}{"\n"}'

# Pods created by the Job, newest last, and logs from the last attempt
kubectl -n "$NS" get pods -l job-name="$JOB" --sort-by=.metadata.creationTimestamp
kubectl -n "$NS" logs -l job-name="$JOB" --tail=100 --prefix
kubectl -n "$NS" describe pods -l job-name="$JOB" | grep -A5 -E 'State:|Last State:|Events:'
```

## Common causes

| Signal | Likely cause | Next step |
| --- | --- | --- |
| Condition reason `BackoffLimitExceeded`, non-zero exit in logs | Application error, bad input, or failing dependency (DB, API, bucket) | Fix the root cause from logs before rerunning |
| Condition reason `DeadlineExceeded` | Run slower than `activeDeadlineSeconds` (data growth, slow dependency) | Check run duration trend; raise the deadline or split the work |
| Container `OOMKilled` | Memory limit too low for the data size | Raise `resources.limits.memory` or batch the input |
| Pods never started (`ImagePullBackOff`, `CreateContainerConfigError`) | Bad image tag, missing Secret or ConfigMap | Fix the reference in git and recreate the Job |
| Pods `Pending` until the deadline | No schedulable capacity or unmatched nodeSelector/tolerations | Check node pressure alerts and scheduling events |

## Mitigation

1. Fix the cause first; rerunning a Job that fails deterministically only
   burns the backoff budget again.
2. Rerun a standalone Job by recreating it from its manifest (Jobs are
   immutable): `kubectl -n "$NS" delete job "$JOB"` then re-apply from git.
3. Rerun a CronJob immediately without waiting for the schedule:
   `kubectl -n "$NS" create job "$JOB-manual-$(date +%s)" --from=cronjob/<cronjob>`.
4. If the work is not idempotent (migrations, payouts), confirm partial
   progress before rerunning.

## Verify

The alert resolves once the failed Job is replaced by a successful run and
removed (manually or via `failedJobsHistoryLimit` / `ttlSecondsAfterFinished`):

```promql
sre:kube_job_failed{namespace="<namespace>", job_name="<job_name>"}
```

```bash
kubectl -n "$NS" get jobs --sort-by=.metadata.creationTimestamp
```
