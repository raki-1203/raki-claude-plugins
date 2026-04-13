.PHONY: init lint test

init:
	git config core.hooksPath .githooks
	@echo "✅ git hooks 설정 완료 (pre-push: lint + test + 자동 버전 bump)"

lint:
	./lint.sh

test:
	./test.sh
