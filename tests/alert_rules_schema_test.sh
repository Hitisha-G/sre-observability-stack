#!/usr/bin/env bash
# Unit checks for Prometheus alert rule packs under prometheus/rules/.
# Every alerting rule must carry severity, team, and component labels plus a runbook_url.
# Also enforces PromQL hygiene: non-empty for:, unique alert names, and CrashLoop waiting_reason.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RULES_DIR="$ROOT/prometheus/rules"

shopt -s nullglob
RULE_FILES=("$RULES_DIR"/*.yml "$RULES_DIR"/*.yaml)
if [[ "${#RULE_FILES[@]}" -eq 0 ]]; then
  echo "FAIL: no rule files under prometheus/rules/" >&2
  exit 1
fi

python3 - "$RULES_DIR" <<'PY'
import pathlib
import re
import sys

rules_dir = pathlib.Path(sys.argv[1])

try:
    import yaml
except ImportError:
    yaml = None

pass_n = 0
fail_n = 0


def ok(label: str) -> None:
    global pass_n
    print(f"PASS: {label}")
    pass_n += 1


def bad(label: str) -> None:
    global fail_n
    print(f"FAIL: {label}", file=sys.stderr)
    fail_n += 1


files = sorted(list(rules_dir.glob("*.yml")) + list(rules_dir.glob("*.yaml")))
if not files:
    bad("rules directory has yaml files")
else:
    ok(f"found {len(files)} rules file(s)")

alerts = 0
alert_names: list[tuple[str, str]] = []
crashloop_expr = None

if yaml is None:
    for path in files:
        text = path.read_text()
        for token in ("severity:", "team:", "component:", "runbook_url:", "summary:"):
            if token in text:
                ok(f"{path.name} contains {token}")
            else:
                bad(f"{path.name} missing {token}")
        if "alert:" in text:
            ok(f"{path.name} defines at least one alert")
            alerts += text.count("\n      - alert:") + text.count("\n- alert:")
        else:
            bad(f"{path.name} defines at least one alert")
        for m in re.finditer(r"(?m)^\s+- alert:\s*(\S+)\s*$", text):
            alert_names.append((m.group(1), path.name))
        if "for:" not in text:
            bad(f"{path.name}: every alerting rule needs a for: duration")
        else:
            ok(f"{path.name}: contains for: duration")
        if "KubePodCrashLooping" in text:
            # Capture expr block roughly for regression checks below.
            crashloop_expr = text
else:
    for path in files:
        data = yaml.safe_load(path.read_text()) or {}
        groups = data.get("groups") or []
        if groups:
            ok(f"{path.name}: has groups")
        else:
            bad(f"{path.name}: has groups")
            continue
        for group in groups:
            for rule in group.get("rules") or []:
                if "alert" not in rule:
                    continue
                alerts += 1
                name = rule["alert"]
                alert_names.append((name, path.name))
                labels = rule.get("labels") or {}
                ann = rule.get("annotations") or {}
                sev = labels.get("severity")
                if sev in ("warning", "critical", "info"):
                    ok(f"{name}: severity={sev}")
                else:
                    bad(f"{name}: severity must be warning|critical|info")
                if labels.get("team"):
                    ok(f"{name}: team set")
                else:
                    bad(f"{name}: team label required")
                if labels.get("component"):
                    ok(f"{name}: component set")
                else:
                    bad(f"{name}: component label required")
                runbook = ann.get("runbook_url", "")
                if isinstance(runbook, str) and runbook.startswith("http"):
                    ok(f"{name}: runbook_url present")
                else:
                    bad(f"{name}: runbook_url must be an http(s) link")
                if ann.get("summary"):
                    ok(f"{name}: summary present")
                else:
                    bad(f"{name}: summary annotation required")

                # PromQL hygiene: every alert must pend for a non-empty duration.
                for_dur = rule.get("for")
                if isinstance(for_dur, str) and for_dur.strip():
                    ok(f"{name}: for={for_dur.strip()}")
                else:
                    bad(f"{name}: non-empty for: duration required")

                if name == "KubePodCrashLooping":
                    crashloop_expr = rule.get("expr") or ""

# Unique alert names across rule packs.
seen: dict[str, str] = {}
dupes = False
for name, src in alert_names:
    if name in seen:
        bad(f"duplicate alert name {name} in {src} (also {seen[name]})")
        dupes = True
    else:
        seen[name] = src
if alert_names and not dupes:
    ok(f"alert names unique ({len(seen)} across rule files)")

# Regression guard: CrashLoop must use waiting_reason, not restart rate/increase.
if crashloop_expr is None:
    bad("KubePodCrashLooping alert must be defined")
else:
    expr = crashloop_expr if isinstance(crashloop_expr, str) else str(crashloop_expr)
    if "kube_pod_container_status_waiting_reason" in expr:
        ok("KubePodCrashLooping: uses kube_pod_container_status_waiting_reason")
    else:
        bad("KubePodCrashLooping: must use kube_pod_container_status_waiting_reason")
    if "CrashLoopBackOff" in expr:
        ok("KubePodCrashLooping: matches CrashLoopBackOff reason")
    else:
        bad("KubePodCrashLooping: must match CrashLoopBackOff reason")
    # Reject latching patterns that keep firing after the pod recovers.
    restart_latch = re.search(
        r"(increase|rate)\s*\(\s*kube_pod_container_status_restarts_total",
        expr,
        re.IGNORECASE,
    )
    if restart_latch:
        bad("KubePodCrashLooping: must not use increase()/rate() on restart counts")
    else:
        ok("KubePodCrashLooping: does not use increase()/rate() on restart counts")

if alerts == 0:
    bad("at least one alerting rule defined")
else:
    ok(f"checked {alerts} alerting rule(s)")

print(f"RESULT: {pass_n} passed, {fail_n} failed")
sys.exit(1 if fail_n else 0)
PY
