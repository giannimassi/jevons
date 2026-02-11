# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Go CLI skeleton with cobra (`sync`, `web`, `status`, `doctor`, `total`, `graph` commands)
- Project renamed from `claude-usage` to `jevons`
- MIT license
- Release policy docs (RELEASING.md, SUPPORT.md)
- Makefile with build and test targets
- GoReleaser configuration stub

### Shell Era (pre-Go port)
- Session log parser reading `~/.claude/projects/*.jsonl`
- Token event aggregation with deduplication into TSV stores
- Background sync daemon with heartbeat monitoring
- Embedded HTML dashboard with time-range selector, metric picker, scope tree, live prompt table
- CLI commands: `sync`, `web`, `web-stop`, `status`, `total`, `graph`, `live`
- UI regression test suite (`tests/claude-usage-ui-regression.sh`)
