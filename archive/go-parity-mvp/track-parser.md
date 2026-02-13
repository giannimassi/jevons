# Track T1: JSONL Parser

## Status: COMPLETE

## Implementation

File: `internal/parser/parser.go` (280 lines)

### Key design decisions
- State machine approach matching shell script: tracks `pendingHuman` and `lastSig`
- Uses `json.RawMessage` for polymorphic content fields (string vs array)
- 10MB scanner buffer to handle large JSONL lines
- Fractional seconds stripped via string manipulation before `time.Parse(RFC3339)`
- Dedup: skip if signature matches lastSig AND no human prompt between

### Functions implemented
- `ParseSessionFile(path, slug, sessionID)` → `[]model.TokenEvent`
- `ParseSessionFileLive(path, slug, sessionID)` → `[]model.LiveEvent`
- `ExtractProjectPath(path)` → string (reads cwd field)
- Internal helpers: `parseEpoch`, `isHumanPrompt`, `contentType`, `promptPreview`, `cleanText`

### Parity with shell script
- Lines 273-366: `extract_events_from_session_file` → `ParseSessionFile`
- Lines 369-501: `extract_live_events_from_session_file` → `ParseSessionFileLive`
- Lines 259-271: `project_path_from_session_file` → `ExtractProjectPath`

### Tests: 18 passing
- Table-driven: basic, tool_use, empty, malformed, dedup signature, cwd extraction
- Epoch parsing: fractional Z, no fractional, timezone offset, empty, invalid
- isHumanPrompt: string, text block, all tool_result, mixed, empty, null
- cleanText: tabs/newlines, multiple spaces, leading/trailing whitespace
