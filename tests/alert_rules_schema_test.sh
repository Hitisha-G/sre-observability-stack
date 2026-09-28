#!/usr/bin/env bash
# Unit checks for Prometheus alert rule packs under prometheus/rules/.
# Every alerting rule must carry severity + team labels and a runbook_url.
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

if yaml is None:
    for path in files:
        text = path.read_text()
        for token in ("severity:", "team:", "runbook_url:", "summary:"):
            if token in text:
                ok(f"{path.name} contains {token}")
            else:
                bad(f"{path.name} missing {token}")
        if "alert:" in text:
            ok(f"{path.name} defines at least one alert")
            alerts += text.count("\n      - alert:") + text.count("\n- alert:")
        else:
            bad(f"{path.name} defines at least one alert")
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
                runbook = ann.get("runbook_url", "")
                if isinstance(runbook, str) and runbook.startswith("http"):
                    ok(f"{name}: runbook_url present")
                else:
                    bad(f"{name}: runbook_url must be an http(s) link")
                if ann.get("summary"):
                    ok(f"{name}: summary present")
                else:
                    bad(f"{name}: summary annotation required")

if alerts == 0:
    bad("at least one alerting rule defined")
else:
    ok(f"checked {alerts} alerting rule(s)")

print(f"RESULT: {pass_n} passed, {fail_n} failed")
sys.exit(1 if fail_n else 0)
PY
