# Track T3: Dashboard & Web Server

## Status: COMPLETE

## Implementation

### Dashboard HTML
- Extracted 1518 lines from shell script (lines 795-2314) to `internal/dashboard/assets/index.html`
- Embedded via `//go:embed assets/index.html`
- Served at `/dashboard/` path prefix

### HTTP Server
File: `internal/dashboard/dashboard.go` (55 lines)

Routes:
- `/dashboard/` → embedded HTML (stripped prefix)
- `/` → data files from DataRoot (events.tsv, projects.json, etc.)

### Features
- `Server.Start()`: creates net.Listener, starts serving in goroutine
- `Server.Stop(ctx)`: graceful shutdown via http.Server.Shutdown
- Dashboard fetches TSV/JSON via relative paths from same HTTP server
