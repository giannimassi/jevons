# Support

## Core Features (fully supported)

These features work out of the box with no external dependencies beyond the binary:

- **Session log parsing** — reads JSONL session logs from `~/.claude/projects`
- **Token aggregation** — deduplicates and aggregates token events into TSV stores
- **Dashboard** — embedded HTML dashboard served over HTTP
- **CLI commands** — `sync`, `web`, `status`, `total`, `graph`
- **Doctor** — environment diagnostics and auto-fix

## Optional Features

These features depend on external tools or services and are never required for core functionality:

- Additional AI provider adapters (future)
- MCP server integrations (future)
- Browser auto-launch for dashboard

Optional features are detected at runtime. Missing optional dependencies are reported as informational, never as errors.

## Compatibility

### Data Format

- The `v0.x` series preserves backward compatibility with data files produced by the shell implementation (`events.tsv`, `live-events.tsv`, `projects.json`, `sync-status.json`)
- Breaking schema changes will be documented in CHANGELOG and accompanied by migration tooling

### Platform Support

| Platform | Status |
|----------|--------|
| macOS (Apple Silicon) | Primary |
| macOS (Intel) | Supported |
| Linux (amd64) | Supported |
| Linux (arm64) | Supported |
| Windows | Not currently supported |

### Go Version

- Minimum Go version is specified in `go.mod`
- Generally tracks the two most recent Go releases

## Reporting Issues

File issues at the GitHub repository. Include:

- `jevons doctor` output
- OS and architecture
- Steps to reproduce
