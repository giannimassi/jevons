# Critic Review - Iteration 3

Review Date: 2026-02-13
Reviewer: Critic Agent
Scope: Parser, Sync, Dashboard, Store, Daemon, CLI Helpers
Previous Challenges Addressed: 16 (all from iteration 1-2)

## Findings

### 1. Parser: Buffer size mismatch could cause different failure modes (MEDIUM)

**File:** `internal/parser/parser.go:55` and `parser.go:135`

**Issue:** The scanner buffer is initialized with `scanner.Buffer(make([]byte, 0, 1024*1024), 10*1024*1024)` which sets initial capacity to 1MB and max to 10MB. However, when lines exceed 10MB, the shell script (using jq) will fail differently than Go.

**Shell behavior:** jq has no explicit line-length limit and will typically succeed or OOM on extremely large lines.

**Go behavior:** `bufio.Scanner` will return an error "token too long" when a line exceeds the max buffer size.

**Evidence:** No test validates behavior with lines approaching or exceeding 10MB. Real-world session logs with massive embedded base64 data or very long tool outputs could hit this limit.

**Impact:** Sync could silently skip large session files in Go but process them in shell (or vice versa if jq OOMs first). No error is returned to the user — the file is just skipped via `continue` on line 65 and 145.

**Recommendation:** Add test with a >10MB line and document the limit, OR increase buffer to match jq's practical limits, OR return an explicit error instead of silently continuing when parsing fails.

---

### 2. Parser: Dedup logic has a subtle race condition edge case (LOW)

**File:** `internal/parser/parser.go:89-91` and `parser.go:170-172`

**Issue:** The dedup signature comparison logic is:

```go
if sig == lastSig && !pendingHuman {
    lastSig = sig
    continue
}
```

The shell version (line 340 of shell script) has identical logic:

```jq
if (.last_sig == $sig and (.pending_human | not)) then
    .last_sig = $sig
    | .pending_human = false
```

**The edge case:** If a session file has:
1. Human message
2. Assistant response A (sig: 100|50|20|10)
3. Assistant response B (sig: 100|50|20|10, identical usage)
4. Another assistant response C (sig: 100|50|20|10)

After response A, `pendingHuman=false` and `lastSig="100|50|20|10"`.

Response B: `sig == lastSig && !pendingHuman` → skip, emit nothing.
Response C: `sig == lastSig && !pendingHuman` → skip, emit nothing.

**BUT** there's no test for consecutive assistant messages with identical signatures. The `duplicate_sig_session.jsonl` fixture only tests human→assistant→assistant→human→assistant, not human→assistant→assistant→assistant.

**Impact:** Extremely low. This is the correct behavior (dedup works as designed), but there's no explicit test proving it handles 3+ consecutive identical signatures correctly.

**Recommendation:** Add a test fixture with 3+ consecutive assistant messages with identical signatures to prove dedup correctly skips all but the first.

---

### 3. Sync: projects.json grouping prefers first non-unknown path, not the "most canonical" (LOW)

**File:** `internal/sync/sync.go:229-236`

**Issue:** When multiple sessions map to the same slug but different paths (e.g., `/Users/alice/project` and `/Users/bob/project`), the code picks the first non-`/unknown/` path encountered after sorting.

**Shell behavior (line 570-574):**
```jq
path: (
    (map(.path) | map(select(startswith("/unknown/") | not)) | first)
    // .[0].path
)
```

Same behavior — picks first non-unknown.

**The edge case:** If a project is developed by multiple users or has been moved across machines, the chosen path is arbitrary (depends on sort order of slug+path, which is alphabetical).

Example:
- Session A: slug `my-app`, path `/Users/alice/my-app`
- Session B: slug `my-app`, path `/Users/bob/my-app`
- Session C: slug `my-app`, path `/unknown/my-app`

After sorting by slug then path:
1. `/Users/alice/my-app`
2. `/Users/bob/my-app`
3. `/unknown/my-app`

Result: `/Users/alice/my-app` is chosen (alphabetically first).

**Impact:** Low. This is parity-correct with shell, but the chosen path might not be the "most recent" or "most canonical" project location. The dashboard will show an arbitrary user's path.

**Test gap:** No test validates behavior when multiple non-unknown paths exist for the same slug.

**Recommendation:** Add a test that creates multiple sessions with the same slug but different non-unknown paths, verify that the alphabetically first path is chosen (documenting this as expected behavior).

---

### 4. Sync: No validation that sort order matches shell's LC_ALL=C (MEDIUM)

**File:** `internal/sync/sync.go:65-80` and `83-98`

**Issue:** The Go sort uses `<` comparison on strings, which is locale-dependent in theory (though Go's default string comparison is byte-wise, matching `LC_ALL=C`).

**Shell behavior (line 550, 557):**
```bash
LC_ALL=C sort -t $'\t' -k1,1n -k2,2 -k3,3 -k4,4 -k12,12
```

The `LC_ALL=C` ensures byte-wise ASCII ordering.

**Go behavior:** `sort.SliceStable` with string comparisons uses Go's built-in string comparison, which is byte-wise (UTF-8 code point order).

**The gap:** No test proves that Go's sort produces identical output to `LC_ALL=C sort` when fields contain non-ASCII characters (e.g., project slugs with Unicode, session IDs with emoji).

**Impact:** If a user has project paths or slugs with non-ASCII characters, the sort order MIGHT differ between shell and Go (though in practice, both are byte-wise, so they should match).

**Evidence:** No test fixture has non-ASCII characters in `project_slug`, `session_id`, or `ts_iso`.

**Recommendation:** Add a test with non-ASCII characters (e.g., project slug `my-app-🚀`, session ID `测试-session`) and verify events are sorted identically to shell (or document that non-ASCII ordering is undefined and might differ).

---

### 5. Store: UnmarshalTokenEvent doesn't validate field count exactly (LOW)

**File:** `internal/store/tsv.go:29-30`

**Issue:**
```go
if len(fields) < 12 {
    return model.TokenEvent{}, fmt.Errorf("expected 12 fields, got %d", len(fields))
}
```

This only checks for `< 12`, not `!= 12`. If a TSV line has **more than 12 fields** (e.g., 13 fields due to corruption or a tab in the signature), the parser will silently ignore the extra fields and parse the first 12.

**Impact:** Low. The shell script's jq parsing would also ignore extra fields (it reads by field index). But the error message is misleading — it says "expected 12 fields" but actually means "expected at least 12 fields".

**Test gap:** No test for a line with >12 fields (e.g., `"1\tiso\tslug\tsid\t100\t50\t20\t10\t150\t180\ttext\tsig\textra"`).

**Recommendation:** Either:
- Change to `!= 12` for strict validation, OR
- Update error message to "expected 12 fields, got %d" → "expected at least 12 fields, got %d"

Add a test for >12 fields to document the behavior.

---

### 6. Dashboard: No test for concurrent requests (LOW)

**File:** `internal/dashboard/dashboard_test.go:41-116`

**Issue:** The HTTP server test (`TestServerRoutes`) makes sequential requests. There's no test proving the server handles concurrent requests correctly.

**Real-world scenario:** The dashboard HTML makes multiple parallel fetches on page load:
- `/events.tsv`
- `/live-events.tsv`
- `/projects.json`
- `/account.json`
- `/sync-status.json`

All within milliseconds of each other.

**Impact:** Low. `http.FileServer` is concurrency-safe by design, but there's no test proving it works correctly when multiple files are requested simultaneously.

**Recommendation:** Add a test that spawns multiple goroutines making concurrent requests to different paths, verify all return 200 and correct content.

---

### 7. Daemon: Heartbeat staleness calculation has an off-by-one edge case (LOW)

**File:** `internal/daemon/daemon.go:128-131`

**Issue:**
```go
healthyLimit := interval * 12
if healthyLimit < 300 {
    healthyLimit = 300
}
```

**Edge case:** If `interval = 25`, then `healthyLimit = 25 * 12 = 300`. The `< 300` check doesn't trigger, so `healthyLimit = 300`.

But if `interval = 24`, then `healthyLimit = 24 * 12 = 288`, which triggers the minimum, so `healthyLimit = 300`.

This means intervals 1-24 all have a 300-second staleness window, but interval 25 also has exactly 300 seconds. The minimum should probably be `<= 300` to ensure intervals >25 actually get longer windows.

**Shell behavior (lines not shown in excerpt, but presumed similar):** Need to check shell script's heartbeat logic.

**Impact:** Very low. Only affects staleness detection for intervals 25-30 seconds (rare usage pattern).

**Recommendation:** Check shell script's logic and align. If shell uses `< 300`, keep it for parity. If shell uses `<= 300`, update Go to match.

---

### 8. Daemon: IsPIDRunning returns false on permission errors, masking real issues (MEDIUM)

**File:** `internal/daemon/daemon.go:148-158`

**Issue:**
```go
proc, err := os.FindProcess(pid)
if err != nil {
    return false
}
err = proc.Signal(syscall.Signal(0))
return err == nil
```

**Problem:** On Unix systems, `os.FindProcess` **never** returns an error — it always returns a `Process` object, even if the PID doesn't exist. The actual check happens in `Signal(0)`.

However, `Signal(0)` can fail for multiple reasons:
- PID doesn't exist (correct: return false)
- **Permission denied** (PID exists but owned by another user, e.g., root process)
- **ESRCH** (no such process)

The current code treats all errors as "not running", which means a running daemon owned by root would be reported as "not running".

**Shell behavior:** Uses `kill -0 $pid` which has the same ambiguity (permission denied vs. not running).

**Impact:** If a user runs sync as root and then checks status as a non-root user, `IsSyncRunning` will incorrectly report "not running" even though the daemon is active.

**Test gap:** No test for permission-denied scenarios (hard to test portably).

**Recommendation:** Either:
- Document this limitation (parity with shell), OR
- Parse the specific error and distinguish "permission denied" (treat as running) from "no such process" (treat as not running)

For MVP parity, documenting is sufficient.

---

### 9. CLI: readEventsFromTSV silently skips unmarshal errors (MEDIUM)

**File:** `internal/cli/helpers.go:60-68`

**Issue:**
```go
for scanner.Scan() {
    line := strings.TrimSpace(scanner.Text())
    if line == "" {
        continue
    }
    event, err := store.UnmarshalTokenEvent(line)
    if err != nil {
        continue  // ← Silent skip
    }
    events = append(events, event)
}
```

**Problem:** If the TSV file is corrupted (e.g., a field has a non-numeric value where an int64 is expected), the line is silently skipped. No error is returned to the caller, and the user has no indication that data was lost.

**Real-world scenario:**
- User manually edits `events.tsv` and introduces a typo
- Sync produces a malformed TSV due to a bug
- File is truncated mid-write due to disk full

**Impact:** `jevons total` and `jevons graph` would silently report incorrect totals without warning the user that some events were skipped.

**Shell behavior:** The shell script's `awk` processing would also skip malformed lines silently (most awk scripts don't validate input rigorously).

**Recommendation:** Either:
- Log a warning when skipping a line (e.g., `log.Warnf("skipping malformed event at line %d: %v", lineNum, err)`), OR
- Accumulate errors and return a summary (e.g., "parsed 100 events, skipped 3 due to errors")

For MVP parity, this is acceptable as-is, but it's a footgun for users.

---

### 10. Parser: promptPreview truncation is byte-based, not rune-based (LOW, but potential UX bug)

**File:** `internal/parser/parser.go:323-326`

**Issue:**
```go
if len(cleaned) > 180 {
    return cleaned[:177] + "..."
}
```

**Problem:** `len(cleaned)` returns the byte length, not the rune (character) length. If `cleaned` contains multi-byte UTF-8 characters (e.g., emoji, CJK characters), slicing at byte index 177 might split a multi-byte sequence, producing invalid UTF-8.

**Example:**
- Input: 60 emoji characters (each 4 bytes) = 240 bytes
- `len(cleaned) = 240` → triggers truncation
- `cleaned[:177]` → slices mid-emoji, producing `�` (replacement character) at the end

**Shell behavior (line ~420 of shell script, not shown in excerpts):** Need to check if jq's substring slicing is byte-based or character-based. Jq's `.[0:177]` is **character-based**, not byte-based.

**Impact:** Low for MVP (most prompts are ASCII), but could cause dashboard rendering glitches if users have prompts with lots of emoji/CJK.

**Test gap:** No test with multi-byte UTF-8 characters in prompt text.

**Recommendation:** Either:
- Use `utf8.RuneCountInString(cleaned)` and rune-based slicing (matches jq), OR
- Document that truncation is byte-based (different from shell)

For parity, should match jq's character-based behavior.

---

### 11. Sync: No atomic write for events.tsv and live-events.tsv (MEDIUM)

**File:** `internal/sync/sync.go:182-190` and `193-201`

**Issue:** Events are written directly to the final paths:
```go
func writeEventsTSV(path string, events []model.TokenEvent) error {
    var b strings.Builder
    b.WriteString(store.EventsTSVHeader)
    b.WriteByte('\n')
    for _, e := range events {
        b.WriteString(store.MarshalTokenEvent(e))
        b.WriteByte('\n')
    }
    return os.WriteFile(path, []byte(b.String()), 0644)
}
```

**Problem:** `os.WriteFile` is **not atomic**. If the write is interrupted (disk full, process killed, system crash), the file could be left in a partially-written state.

**Shell behavior (lines 553, 559):**
```bash
} > "$tmp_events_sorted"
mv "$tmp_events_sorted" "$events_file"
```

The shell writes to a temp file and then **atomically** renames it with `mv` (rename is atomic on Unix).

**Impact:** If sync is interrupted mid-write, the Go version leaves a corrupt `events.tsv`, while the shell version leaves the old `events.tsv` intact (the temp file is orphaned but the production file is untouched).

**Real-world scenario:**
- Sync is running in a loop
- User runs `jevons total` while sync is writing `events.tsv`
- Go version: `total` might read a half-written file and return incorrect results
- Shell version: `total` reads the old complete file (rename hasn't happened yet)

**Recommendation:** Change `writeEventsTSV` and `writeLiveEventsTSV` to write to a temp file and then `os.Rename()` atomically (matching shell behavior).

---

### 12. Parser: No test for session files with missing .jsonl extension (LOW)

**File:** `internal/sync/sync.go:142`

**Issue:** The glob pattern is:
```go
pattern := filepath.Join(sourceDir, "*", "*.jsonl")
```

This only matches `*.jsonl` files. If a user accidentally creates a session file without the extension (e.g., `~/.claude/projects/my-app/session-001`), it will be silently ignored.

**Shell behavior (line 545):**
```bash
find "$source_root" -mindepth 2 -maxdepth 2 -type f -name '*.jsonl'
```

Same behavior — only `.jsonl` files.

**Impact:** Low. This is correct behavior (ignore non-.jsonl files), but there's no test documenting it.

**Recommendation:** Add a test that creates a non-.jsonl file in the source directory and verifies it's not processed.

---

## Summary

**HIGH severity:** 0
**MEDIUM severity:** 4 (issues 1, 4, 8, 11)
**LOW severity:** 8 (issues 2, 3, 5, 6, 7, 9, 10, 12)

**Top priorities for iteration 3:**
1. **Issue 11 (MEDIUM):** Non-atomic TSV writes — could corrupt data if sync is interrupted
2. **Issue 1 (MEDIUM):** Large line handling differs from shell — should document or fix
3. **Issue 10 (LOW but UX impact):** Prompt truncation should be character-based, not byte-based (parity with jq)
4. **Issue 4 (MEDIUM):** No validation that sort order matches LC_ALL=C with non-ASCII characters

**Issues that are parity-correct but worth documenting:**
- Issue 8 (IsPIDRunning permission handling)
- Issue 9 (silent line skipping in CLI helpers)
- Issue 3 (arbitrary path selection for projects.json)
