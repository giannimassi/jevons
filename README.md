# Jevons

Local AI usage monitor and dashboard. Reads session logs from AI coding tools (Claude, Codex, and others), aggregates token consumption into event stores, and serves an interactive HTML dashboard.

Named after [Jevons paradox](https://en.wikipedia.org/wiki/Jevons_paradox) — as AI tools get more efficient, we use them more.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Quick Start

```bash
# build from source
git clone https://github.com/giannimassi/jevons.git
cd jevons
make build

# start dashboard with background sync
./bin/jevons web --port 8765 --interval 15

# or one-shot sync + CLI reporting
./bin/jevons sync
./bin/jevons total --range 24h
./bin/jevons graph --metric billable --range 7d
```

Dashboard: `http://127.0.0.1:8765/dashboard/index.html`

## Commands

```bash
jevons sync                              # one-shot sync of session logs → TSV
jevons web --port 8765 --interval 15     # start dashboard + background sync
jevons web-stop                          # stop web server
jevons status                            # show sync and web server health
jevons total --range 24h                 # JSON token usage aggregation
jevons graph --metric billable --range 7d # ASCII usage graph
jevons doctor                            # environment diagnostics
```

## Build & Test

```bash
make build          # build binary to bin/jevons
make test           # run Go tests (104 subtests)
make vet            # go vet
make fmt            # go fmt
make test-parity    # compare Go output against shell reference
make test-shell     # run shell UI regression tests
make clean          # remove build artifacts
```

## Data Flow

```
~/.claude/projects/<slug>/*.jsonl   (source: AI session logs)
        │
        ▼  jevons sync
$DATA_ROOT/events.tsv               (deduplicated token events, sorted by epoch)
$DATA_ROOT/live-events.tsv          (same + prompt preview column)
$DATA_ROOT/projects.json            (slug→path manifest)
$DATA_ROOT/account.json             (from ~/.claude.json)
$DATA_ROOT/sync-status.json         (last sync metadata)
        │
        ▼  jevons web
http://127.0.0.1:8765/dashboard/    (interactive HTML dashboard)
```

Default data directory: `~/dev/.claude-usage` (override with `CLAUDE_USAGE_DATA_DIR`).

## Shell Script (Legacy)

The original shell implementation (`claude-usage-tracker.sh`, 2715 lines) remains in the repo as the reference. It requires `bash`, `jq`, `curl`, `python3`, `awk`, and `sort`. The Go binary is format-compatible and produces identical output.

## Docs

- [Go Port Plan](docs/GO_PORT_PLAN.md)
- [Release & Packaging Strategy](docs/RELEASE_AND_PACKAGING_STRATEGY.md)
- [Release Execution Plan](docs/RELEASE_EXECUTION_PLAN.md)

## License

[MIT](LICENSE)
