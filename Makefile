.POSIX:

SHELL_FILES = bin/cc-vitamins bin/ccv lib/format.sh lib/sessions.sh lib/cost.sh lib/accounts.sh install.sh tests/run.sh tests/fake-claude

.PHONY: test lint check

test:
	@sh tests/run.sh

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -s sh $(SHELL_FILES) && echo "shellcheck: clean"; \
	else \
		echo "shellcheck not installed; skipping lint"; \
	fi

check: lint test
