# Track T5: CLI Commands

## Status: COMPLETE

## Implementation

### Commands implemented
- `sync`: calls `sync.Run(cfg)`, prints `sync_ok` line
- `web`: starts dashboard server + background sync daemon, handles SIGINT/SIGTERM
- `status`: reports sync status (heartbeat, PID), last sync JSON, events path
- `total`: reads events.tsv, filters by range, outputs aggregated JSON
- `graph`: reads events.tsv, buckets by time, renders ASCII bar chart
- `doctor`: checks source/data dirs, events.tsv, shell deps, optional --fix

### Helpers
File: `internal/cli/helpers.go`
- `rangeToSeconds`: maps 1h/3h/6h/12h/24h/30h/48h/7d/14d/30d/all to seconds
- `readEventsFromTSV`: reads TSV file, skips header, unmarshal events

### Tests: 13 passing
- rangeToSeconds: all valid ranges + error cases (13 table entries)

### Verified against real data
- `jevons sync`: processed 340 session files, 8926 events
- `jevons total --range all`: correct JSON output
- `jevons graph --range all --metric billable`: renders ASCII graph
- `jevons status`: shows heartbeat and sync status
