.PHONY: help build test vet fmt clean test-shell lint-shell

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
