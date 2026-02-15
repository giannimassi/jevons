.PHONY: help build test vet fmt clean test-shell lint-shell test-parity test-smoke test-migration test-e2e release-dry-run

BINARY := jevons
BUILD_DIR := bin
GO_MODULE := ./cmd/jevons

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Build Go binary
	go build -o $(BUILD_DIR)/$(BINARY) $(GO_MODULE)

test: ## Run Go tests
	go test ./...

vet: ## Run go vet
	go vet ./...

fmt: ## Run go fmt
	go fmt ./...

clean: ## Remove build artifacts
	rm -rf $(BUILD_DIR) dist

test-shell: ## Run shell UI regression tests
	./tests/claude-usage-ui-regression.sh

lint-shell: ## Lint shell scripts with shellcheck
	shellcheck claude-usage-tracker.sh

test-parity: build ## Compare Go sync output against shell sync output
	@echo "=== Running shell sync ==="
	@mkdir -p /tmp/jevons-parity/shell /tmp/jevons-parity/go
	CLAUDE_USAGE_DATA_DIR=/tmp/jevons-parity/shell ./claude-usage-tracker.sh sync
	@echo "=== Running Go sync ==="
	CLAUDE_USAGE_DATA_DIR=/tmp/jevons-parity/go ./$(BUILD_DIR)/$(BINARY) sync
	@echo "=== Comparing events.tsv headers ==="
	@head -1 /tmp/jevons-parity/shell/events.tsv > /tmp/jevons-parity/shell-header.txt
	@head -1 /tmp/jevons-parity/go/events.tsv > /tmp/jevons-parity/go-header.txt
	@diff /tmp/jevons-parity/shell-header.txt /tmp/jevons-parity/go-header.txt && echo "  Headers match ✓" || echo "  Headers DIFFER ✗"
	@echo "=== Comparing event counts ==="
	@echo "  Shell events: $$(wc -l < /tmp/jevons-parity/shell/events.tsv)"
	@echo "  Go events:    $$(wc -l < /tmp/jevons-parity/go/events.tsv)"
	@echo "=== Comparing live-events.tsv headers ==="
	@head -1 /tmp/jevons-parity/shell/live-events.tsv > /tmp/jevons-parity/shell-live-header.txt
	@head -1 /tmp/jevons-parity/go/live-events.tsv > /tmp/jevons-parity/go-live-header.txt
	@diff /tmp/jevons-parity/shell-live-header.txt /tmp/jevons-parity/go-live-header.txt && echo "  Headers match ✓" || echo "  Headers DIFFER ✗"
	@echo "=== Comparing projects.json ==="
	@diff <(jq -S . /tmp/jevons-parity/shell/projects.json) <(jq -S . /tmp/jevons-parity/go/projects.json) && echo "  Projects match ✓" || echo "  Projects DIFFER ✗"
	@echo "=== Done ==="
	@rm -rf /tmp/jevons-parity

test-smoke: build ## Run smoke tests against local build
	@chmod +x tests/smoke-test.sh
	./tests/smoke-test.sh ./bin/jevons

test-migration: build ## Run migration validation (requires shell script + jq)
	@chmod +x tests/migration-test.sh
	./tests/migration-test.sh ./bin/jevons

test-e2e: build ## Run Playwright E2E tests for the dashboard
	npx playwright test --config tests/e2e/playwright.config.ts

release-dry-run: ## Run GoReleaser locally (snapshot, no publish)
	goreleaser release --snapshot --clean --skip=publish
