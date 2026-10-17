# Local helpers for sre-observability-stack (mirrors GitHub Actions ci jobs).

RULES_DIR := prometheus/rules
TEST_DIR := tests

.PHONY: help lint test runbooks coverage rules promtool-test ci

help:
	@printf '%s\n' \
		'Targets:' \
		'  make lint      - shellcheck test scripts' \
		'  make test      - alert rule schema unit checks' \
		'  make runbooks  - verify in-repo runbook_url targets exist' \
		'  make coverage  - every rule file has a promtool test file' \
		'  make rules     - promtool check rules (needs promtool on PATH)' \
		'  make promtool-test - promtool unit tests under tests/promtool/' \
		'  make ci        - lint + test + runbooks + coverage + rules + promtool-test'

lint:
	shellcheck $(TEST_DIR)/*.sh

test:
	bash $(TEST_DIR)/alert_rules_schema_test.sh

runbooks:
	bash $(TEST_DIR)/runbook_links_test.sh

coverage:
	bash $(TEST_DIR)/promtool_coverage_test.sh

rules:
	promtool check rules $(RULES_DIR)/*.yml

promtool-test:
	promtool test rules $(TEST_DIR)/promtool/*.test.yml

ci: lint test runbooks coverage rules promtool-test
