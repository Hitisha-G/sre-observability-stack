# Local helpers for sre-observability-stack (mirrors GitHub Actions ci jobs).

RULES_DIR := prometheus/rules
TEST_DIR := tests
# Set to a file path to write promtool unit test results as JUnit XML.
PROMTOOL_JUNIT ?=

.PHONY: help lint yaml test runbooks coverage rules promtool-test ci

help:
	@printf '%s\n' \
		'Targets:' \
		'  make lint      - shellcheck test scripts' \
		'  make yaml      - yamllint rule, test, and workflow files' \
		'  make test      - alert rule schema unit checks' \
		'  make runbooks  - verify in-repo runbook_url targets exist' \
		'  make coverage  - every rule file has a promtool test file' \
		'  make rules     - promtool check rules, lint findings fail (needs promtool)' \
		'  make promtool-test - promtool unit tests (PROMTOOL_JUNIT=out.xml for JUnit)' \
		'  make ci        - lint + yaml + test + runbooks + coverage + rules + promtool-test'

lint:
	shellcheck $(TEST_DIR)/*.sh

yaml:
	yamllint --strict prometheus $(TEST_DIR) .github

test:
	bash $(TEST_DIR)/alert_rules_schema_test.sh

runbooks:
	bash $(TEST_DIR)/runbook_links_test.sh

coverage:
	bash $(TEST_DIR)/promtool_coverage_test.sh

rules:
	promtool check rules --lint=all --lint-fatal $(RULES_DIR)/*.yml

promtool-test:
	promtool test rules $(if $(PROMTOOL_JUNIT),--junit=$(PROMTOOL_JUNIT)) $(TEST_DIR)/promtool/*.test.yml

ci: lint yaml test runbooks coverage rules promtool-test
