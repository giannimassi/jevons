# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Go CLI parity MVP** — full port of shell script to Go binary (`jevons`)
- JSONL session log parser with state machine dedup (`internal/parser/`, 366 lines)
- Sync pipeline: discover → parse → sort → dedupe → write TSV/JSON (`internal/sync/`, 323 lines)
- Background sync daemon with heartbeat monitoring (`internal/daemon/`, 191 lines)
- Embedded HTML dashboard via `go:embed` (`internal/dashboard/`)
- CLI commands: `sync`, `web`, `web-stop`, `status`, `total`, `graph`, `doctor`
- Atomic file writes for TSV output (write-to-temp + rename)
- Rune-based prompt preview truncation (UTF-8 safe)
- `make test-parity` target to validate Go vs shell output compatibility
- Comprehensive test suite: 24 top-level tests / 104 subtests across 6 packages
- 9 test fixture files covering edge cases (empty sessions, malformed JSON, dedup, tool_result starts, hyphenated repos)
- Project renamed from `claude-usage` to `jevons`
- MIT license
- Release policy docs (RELEASING.md, SUPPORT.md)
- Makefile with build, test, vet, fmt, and parity targets
- GoReleaser configuration stub

### Shell Era (pre-Go port)
- Session log parser reading `~/.claude/projects/*.jsonl`
- Token event aggregation with deduplication into TSV stores
- Background sync daemon with heartbeat monitoring
- Embedded HTML dashboard with time-range selector, metric picker, scope tree, live prompt table
- CLI commands: `sync`, `web`, `web-stop`, `status`, `total`, `graph`, `live`
- UI regression test suite (`tests/claude-usage-ui-regression.sh`)
