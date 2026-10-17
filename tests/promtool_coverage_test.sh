#!/usr/bin/env bash
# Fail when an alert rule file has no matching promtool unit test file.
# prometheus/rules/<name>.yml must be paired with tests/promtool/<name>.test.yml
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rules_dir="${RULES_DIR:-$repo_root/prometheus/rules}"
tests_dir="${PROMTOOL_TEST_DIR:-$repo_root/tests/promtool}"

shopt -s nullglob
rule_files=("$rules_dir"/*.yml "$rules_dir"/*.yaml)

if [[ ${#rule_files[@]} -eq 0 ]]; then
  echo "no rule files found under $rules_dir" >&2
  exit 1
fi

missing=0
for rule in "${rule_files[@]}"; do
  name="$(basename "$rule")"
  name="${name%.*}"
  if [[ -f "$tests_dir/$name.test.yml" ]]; then
    echo "ok   $name -> tests/promtool/$name.test.yml"
  else
    echo "MISS $name has no tests/promtool/$name.test.yml" >&2
    missing=$((missing + 1))
  fi
done

if [[ $missing -gt 0 ]]; then
  echo "$missing rule file(s) without promtool unit tests" >&2
  exit 1
fi

echo "all ${#rule_files[@]} rule file(s) have promtool unit tests"
