# Go Port Plan

**Status: COMPLETE** — All milestones achieved. Go binary produces format-compatible output with the shell script across 104 subtests.

## Why Port

Shell works for fast iteration, but Go gives:

- single static binary distribution
- better long-term maintainability
- stronger testability and typed parsing
- cleaner background service control

## Project Structure

```text
cmd/jevons/
  main.go              # CLI entrypoint (10 lines)
internal/
  cli/                 # cobra commands: sync, web, status, total, graph, doctor
  sync/                # sync pipeline (discover → parse → sort → dedupe → write)
  parser/              # JSONL session log parser with state machine dedup
  store/               # TSV event marshal/unmarshal
  daemon/              # background sync loop, heartbeat, PID management
  dashboard/           # embedded HTML dashboard + HTTP server
    assets/
      index.html       # 1,518-line dashboard extracted from shell script
web/
  static assets (embedded)
pkg/
  model/               # TokenEvent, LiveEvent, Config types
```

Total: 2,740 lines of Go across 22 files.

## Migration Milestones

1. ~~Recreate sync parser + store in Go (format-compatible output).~~ **DONE** — `internal/parser/` + `internal/store/` with 47 parser subtests
2. ~~Recreate status/heartbeat and daemon lifecycle.~~ **DONE** — `internal/daemon/` with heartbeat, PID, health checks
3. ~~Reuse existing dashboard JS/CSS/HTML initially.~~ **DONE** — extracted verbatim from shell lines 795-2314
4. ~~Embed web assets in binary (`embed`).~~ **DONE** — `//go:embed assets/index.html` in `dashboard.go`
5. ~~Add `doctor` command and release automation.~~ **DONE** — `jevons doctor` checks source/data dirs, GoReleaser stub

## Compatibility Contract

- Preserves existing data schema (`events.tsv`, `live-events.tsv`, `projects.json`, `sync-status.json`).
- CLI subcommands equivalent to shell (`web`, `sync`, `status`, `graph`, `total`) plus new `doctor`.
- `make test-parity` validates Go output matches shell output.

## Testing Strategy

- Unit tests for parser edge-cases and dedupe behavior (47 subtests).
- Integration tests for sync output determinism (idempotent re-sync, empty source, non-JSONL exclusion).
- TSV format validation (header order, field counts, extra-fields tolerance).
- Dashboard HTTP route tests (200s, 404s).
- Daemon lifecycle tests (heartbeat writes, state parsing).
- 9 fixture JSONL files covering: basic sessions, tool_use, empty, malformed, dedup, hyphenated repos, missing cwd, tool_result starts, triple consecutive dedup.

## What's Next

See [Release Execution Plan](RELEASE_EXECUTION_PLAN.md) for Phase 2+ (packaging, distribution, v0.1.0 release).
