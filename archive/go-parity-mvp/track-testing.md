# Track T6: Testing & Fixtures

## Status: COMPLETE

## Test Suite Summary

37 tests across 5 packages, all passing.

### Parser tests (18): `internal/parser/parser_test.go`
- ParseSessionFile: basic, tool_use, empty, malformed, dedup signature
- ParseSessionFileLive: prompt previews for basic and tool_use sessions
- ExtractProjectPath: with cwd, without cwd, empty
- parseEpoch: fractional Z, no fractional, timezone offset, empty, invalid
- isHumanPrompt: string, text block, all tool_result, mixed, empty, null
- cleanText: tabs/newlines, multiple spaces, leading/trailing

### Sync tests (3): `internal/sync/sync_test.go`
- TestSyncRun: full pipeline with fixture data
- TestSyncIdempotent: re-sync stability
- TestSyncEmptySource: nonexistent source directory

### Daemon tests (3): `internal/daemon/daemon_test.go`
- TestDaemonRunAndHeartbeat: lifecycle + heartbeat
- TestReadHeartbeatState: parsing (no file, invalid, fresh, stale)
- TestEnsureDataDirs: directory creation

### Store tests (3): `internal/store/tsv_test.go`
- MarshalUnmarshalTokenEvent: round-trip for basic and zero-cache events
- UnmarshalTokenEventErrors: too few fields, bad epoch, bad input
- MarshalLiveEvent: serialization with prompt preview

### CLI tests (13): `internal/cli/helpers_test.go`
- rangeToSeconds: 11 valid ranges + 2 error cases

### Fixtures
6 JSONL fixture files in `internal/parser/testdata/`:
- basic_session.jsonl, tool_use_session.jsonl, empty_session.jsonl
- malformed_session.jsonl, duplicate_sig_session.jsonl, cwd_session.jsonl

### Make targets
`make build && make vet && make test` all pass cleanly.
