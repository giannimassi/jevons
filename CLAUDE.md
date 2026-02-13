# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Jevons — a local AI usage monitor and dashboard that reads session logs from AI coding tools (starting with `~/.claude/projects/*.jsonl`), aggregates token consumption into TSV event stores, and serves an HTML dashboard. Named after Jevons paradox. The Go CLI (`jevons`) is the primary implementation; the original shell script (`claude-usage-tracker.sh`) remains as a reference.

## Commands

### Go CLI

```bash
make build                          # build binary to bin/jevons
./bin/jevons sync                   # one-shot sync
./bin/jevons web --port 8765        # start dashboard
./bin/jevons web-stop               # stop web server
./bin/jevons status                 # show status
./bin/jevons doctor                 # environment diagnostics
./bin/jevons total --range 24h      # CLI totals
./bin/jevons graph --metric billable --range 24h  # ASCII graph
```

### Shell (legacy reference)

```bash
./claude-usage-tracker.sh web --interval 15 --port 8765
./claude-usage-tracker.sh sync
./claude-usage-tracker.sh status
./claude-usage-tracker.sh total --range 24h
./claude-usage-tracker.sh graph --metric billable --range 24h
./claude-usage-tracker.sh web-stop
```

### Build & test

```bash
make build          # build Go binary
make test           # run Go tests (104 subtests)
make vet            # go vet
make fmt            # go fmt
make test-parity    # compare Go vs shell output
make test-shell     # run shell UI regression tests
make clean          # remove build artifacts
```

### Running shell tests

UI regression tests require `agent-browser`, `jq`, and `curl`:

```bash
./tests/claude-usage-ui-regression.sh [port]
```

## Architecture

### Data flow

```
~/.claude/projects/<slug>/*.jsonl   (source: AI session logs)
        │
        ▼  sync
$DATA_ROOT/events.tsv               (deduplicated token events, sorted by epoch)
$DATA_ROOT/live-events.tsv          (same + prompt preview column)
$DATA_ROOT/projects.json            (slug→path manifest)
$DATA_ROOT/account.json             (from ~/.claude.json)
$DATA_ROOT/sync-status.json         (last sync metadata)
        │
        ▼  dashboard
$DATA_ROOT/dashboard/index.html     (generated at startup, served over HTTP)
```

### Key environment variables

| Variable | Default | Purpose |
|---|---|---|
| `CLAUDE_USAGE_DATA_DIR` | `~/dev/.claude-usage` | Where events, dashboard, PIDs, and logs live |
| `CLAUDE_USAGE_SOURCE_DIR` | `~/.claude/projects` | Where AI session JSONL files are read from |

### Go project structure

```
cmd/jevons/          # CLI entrypoint
internal/
  cli/               # cobra command definitions
  sync/              # sync pipeline
  parser/            # JSONL session log parser
  store/             # TSV event store
  daemon/            # background sync loop, heartbeat
  dashboard/         # dashboard generation and embedding
web/                 # static dashboard assets (for embedding)
pkg/model/           # shared data types (events, config)
```

### Shell script structure (claude-usage-tracker.sh)

- **Lines 1–260**: Config, helpers, path resolution, `range_to_seconds`
- **Lines 260–500**: `extract_events_from_session_file` / `extract_live_events_from_session_file` — jq-heavy JSONL parsing with dedup signatures
- **Lines 500–640**: `cmd_sync` — full sync pipeline (read all sessions → dedupe → write TSV + JSON)
- **Lines 640–790**: Sync loop daemon, start/stop/status, heartbeat
- **Lines 792–2315**: `ensure_dashboard_html` — the entire embedded HTML dashboard (CSS, JS, chart rendering, scope tree, live table, account popover)
- **Lines 2316–2680**: Web server lifecycle, `cmd_total`, `cmd_graph` (awk-based ASCII), `cmd_live`
- **Lines 2680–2715**: `main` dispatch

### Dashboard (embedded HTML)

Single-page app generated into `$DATA_ROOT/dashboard/index.html`. Fetches TSV/JSON files from the same HTTP server via relative paths. Key features: time-range selector, metric/graph-mode picker, scope tree with directory filtering, live prompt table, account popover.

### Daemon model

- Sync loop: background process writing heartbeat file (`epoch,interval,pid,status`), checked via `sync_heartbeat_state()`
- Web server: Go HTTP server (Go CLI) or Python `http.server` (shell legacy)
- Health checks use both PID liveness (`kill -0`) and HTTP probe

## Dependencies

### Shell runtime
`bash`, `jq`, `curl`, `python3` (for `http.server`), `awk`, `sort`

### Go build
Go 1.23+, `cobra` (CLI framework)

## Data format

Events TSV columns: `ts_epoch, ts_iso, project_slug, session_id, input, output, cache_read, cache_create, billable, total_with_cache, content_type, signature`

Live events add a `prompt_preview` column after `session_id`.

Dedup uses a composite signature to avoid double-counting when re-syncing the same session files.
