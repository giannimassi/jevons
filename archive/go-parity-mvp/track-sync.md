# Track T2: Sync Pipeline

## Status: COMPLETE

## Implementation

File: `internal/sync/sync.go` (300 lines)

### Pipeline
1. `discoverSessionFiles`: glob `sourceDir/*/*.jsonl`, sorted
2. For each file: extract slug (dirname), sessionID (basename minus .jsonl), projectPath (cwd or /unknown/)
3. Parse events + live events via parser package
4. Sort by (epoch, ts_iso, slug, sessionID, signature)
5. Deduplicate by full TSV line
6. Write: events.tsv, live-events.tsv, projects.json, account.json, sync-status.json

### Output files
- `events.tsv`: header + sorted deduped events
- `live-events.tsv`: header + sorted deduped live events with prompt_preview
- `projects.json`: array of {slug, path}, grouped by slug, prefers non-/unknown/ paths
- `account.json`: extracted from ~/.claude.json oauthAccount fields
- `sync-status.json`: {last_sync_epoch, last_sync_iso, source_root, session_files, event_rows, live_event_rows}

### Tests: 3 passing
- TestSyncRun: full pipeline with fixture data
- TestSyncIdempotent: re-sync produces same counts
- TestSyncEmptySource: handles nonexistent source directory
