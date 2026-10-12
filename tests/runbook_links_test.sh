#!/usr/bin/env bash
# CI guard: every alert runbook_url that points at this repo must resolve to a tracked file.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RULES_DIR="$ROOT/prometheus/rules"
REPO_SLUG="Hitisha-G/sre-observability-stack"
PREFIX="https://github.com/${REPO_SLUG}/blob/main/"

shopt -s nullglob
RULE_FILES=("$RULES_DIR"/*.yml "$RULES_DIR"/*.yaml)
if [[ ${#RULE_FILES[@]} -eq 0 ]]; then
  echo "FAIL: no rule files under prometheus/rules/" >&2
  exit 1
fi

python3 - "$ROOT" "$PREFIX" "${RULE_FILES[@]}" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
prefix = sys.argv[2]
files = [pathlib.Path(p) for p in sys.argv[3:]]

try:
    import yaml
except ImportError:
    yaml = None

pass_n = 0
fail_n = 0
checked = 0


def ok(label: str) -> None:
    global pass_n
    print(f"PASS: {label}")
    pass_n += 1


def bad(label: str) -> None:
    global fail_n
    print(f"FAIL: {label}", file=sys.stderr)
    fail_n += 1


urls: list[tuple[str, str]] = []
url_re = re.compile(r"runbook_url:\s*[\"']?(\S+?)[\"']?\s*$", re.M)

for path in files:
    if yaml is not None:
        data = yaml.safe_load(path.read_text()) or {}
        for group in data.get("groups") or []:
            for rule in group.get("rules") or []:
                if "alert" not in rule:
                    continue
                ann = rule.get("annotations") or {}
                url = ann.get("runbook_url")
                if isinstance(url, str) and url.strip():
                    urls.append((rule["alert"], url.strip()))
    else:
        text = path.read_text()
        for m in url_re.finditer(text):
            urls.append((path.name, m.group(1)))

if not urls:
    bad("at least one runbook_url annotation found")
else:
    ok(f"found {len(urls)} runbook_url annotation(s)")

for alert, url in urls:
    checked += 1
    if not url.startswith(prefix):
        # External runbooks are allowed; only enforce in-repo links.
        ok(f"{alert}: external runbook ({url})")
        continue
    rel = url[len(prefix) :]
    target = root / rel
    if target.is_file():
        ok(f"{alert}: {rel} exists")
    else:
        bad(f"{alert}: missing file for {rel}")

print(f"RESULT: {pass_n} passed, {fail_n} failed ({checked} links checked)")
sys.exit(1 if fail_n else 0)
PY
