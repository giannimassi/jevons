# Go Port Plan

## Why Port

Shell works for fast iteration, but Go gives:

- single static binary distribution
- better long-term maintainability
- stronger testability and typed parsing
- cleaner background service control

## Proposed Structure

```text
cmd/claude-usage/
  main.go
internal/
  sync/
  parser/
  store/
  dashboard/
  adapters/
web/
  static assets (embedded)
```

## Migration Milestones

1. Recreate sync parser + store in Go (format-compatible output).
2. Recreate status/heartbeat and daemon lifecycle.
3. Reuse existing dashboard JS/CSS/HTML initially.
4. Embed web assets in binary (`embed`).
5. Add `doctor` command and release automation.

## Compatibility Contract

- Preserve existing data schema initially (`events.tsv`, `live-events.tsv`, `projects.json`, `sync-status.json`).
- Keep CLI subcommands equivalent where practical (`web`, `sync`, `status`, `graph`, `total`).

## Testing Strategy

- Unit tests for parser edge-cases and dedupe behavior.
- Integration tests for sync output determinism.
- E2E tests for scope selection and empty-state UX.
- Regression fixtures for hyphenated repo names and missing `cwd` records.
