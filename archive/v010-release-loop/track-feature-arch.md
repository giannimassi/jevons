# Track T6: Provider Abstraction Architecture (v0.2)

- **Repo:** jevons (github.com/giannimassi/jevons)
- **Branch:** main
- **Last Updated:** 2026-02-13

---

## 1. Provider Interface Definition

### Current State

The sync pipeline (`internal/sync/sync.go`) hardcodes two Claude-specific operations:

1. **Discovery** — `discoverSessionFiles()` globs `~/.claude/projects/*/*.jsonl` (line 136-148)
2. **Parsing** — `parser.ParseSessionFile()` and `parser.ParseSessionFileLive()` decode Claude Code's JSONL state-machine format with Claude-specific dedup heuristics (lines 44-120 of `internal/parser/parser.go`)

These two concerns — "where are the logs?" and "what do the logs mean?" — are the natural seam for the provider interface.

### Proposed Interface

```go
// internal/provider/provider.go
package provider

import "github.com/giannimassi/jevons/pkg/model"

// SessionFile identifies a single session log file discovered by a provider.
type SessionFile struct {
    Path        string // absolute filesystem path to the log file
    ProjectSlug string // project identifier (e.g., directory name for Claude, workspace for Cursor)
    SessionID   string // unique session identifier within the project
}

// Provider discovers and parses session logs from a specific AI tool.
type Provider interface {
    // Name returns a short, stable identifier for this provider.
    // Used in TSV data, CLI flags, and dashboard filters.
    // Examples: "claude", "cursor", "copilot", "windsurf"
    Name() string

    // Discover returns all session log files this provider knows about.
    // The sourceDir argument is the configured base directory (e.g., ~/.claude/projects).
    // Providers that use a different base path may ignore sourceDir and use their own
    // default, but must respect it when non-empty for testability.
    Discover(sourceDir string) ([]SessionFile, error)

    // Parse reads a single session file and returns token events.
    // The SessionFile provides context (slug, session ID) so the parser
    // doesn't need to re-derive them from the path.
    Parse(sf SessionFile) ([]model.TokenEvent, error)

    // ParseLive reads a single session file and returns live events with prompt previews.
    // Providers that don't support prompt previews should return events with
    // PromptPreview set to "-".
    ParseLive(sf SessionFile) ([]model.LiveEvent, error)

    // ExtractProjectPath attempts to read the working directory / project path
    // from a session file. Returns empty string if not available.
    ExtractProjectPath(path string) string
}
```

### Design Decisions

**Why `SessionFile` as a struct instead of bare path?** The current code derives `slug` and `sessionID` from path conventions (`filepath.Base(filepath.Dir(sf))` and `strings.TrimSuffix`). This works for Claude's `projects/<slug>/<session>.jsonl` layout but won't generalize. Different providers store sessions differently — Cursor uses SQLite, Copilot uses structured directories with different naming. Passing a `SessionFile` struct lets each provider's `Discover()` method set these identifiers using its own conventions, and `Parse()` receives them without path-parsing assumptions.

**Why `ParseLive` as a separate method?** The current codebase already separates `ParseSessionFile` and `ParseSessionFileLive` because live parsing requires tracking prompt text across user/assistant turns. This is inherently stateful and provider-specific (different tools structure user messages differently). Keeping them separate avoids forcing providers that don't support prompt previews to implement complex logic — they just return `PromptPreview: "-"`.

**Why `sourceDir` as a parameter to `Discover`?** Testability. The current code reads `cfg.SourceDir` which defaults to `~/.claude/projects`. Passing it as a parameter lets tests supply a temp directory. Providers that use their own fixed paths (e.g., Cursor reads from `~/Library/Application Support/Cursor/`) can use the parameter as an override or ignore it and document their default.

**Why not a generic `Options map[string]any` parameter?** It's tempting to add a config bag for provider-specific settings. But for v0.2 with only 1-2 providers, concrete parameters are simpler to test and document. If v0.3 needs per-provider config, we can add a `Configure(opts map[string]string) error` method then.

---

## 2. Registration Mechanism

### Recommendation: Compiled-in Registry (v0.2)

```go
// internal/provider/registry.go
package provider

import "fmt"

// registry holds all registered providers, keyed by Name().
var registry = make(map[string]Provider)

// Register adds a provider to the global registry. Panics on duplicate names.
// Called from init() functions in provider packages.
func Register(p Provider) {
    name := p.Name()
    if _, exists := registry[name]; exists {
        panic(fmt.Sprintf("provider already registered: %s", name))
    }
    registry[name] = p
}

// Get returns a provider by name, or nil if not found.
func Get(name string) Provider {
    return registry[name]
}

// All returns all registered providers.
func All() []Provider {
    result := make([]Provider, 0, len(registry))
    for _, p := range registry {
        result = append(result, p)
    }
    return result
}

// Names returns sorted names of all registered providers.
func Names() []string {
    names := make([]string, 0, len(registry))
    for name := range registry {
        names = append(names, name)
    }
    sort.Strings(names)
    return names
}
```

### Provider Registration via Import

```go
// internal/provider/claude/claude.go
package claude

import "github.com/giannimassi/jevons/internal/provider"

func init() {
    provider.Register(&Claude{})
}

type Claude struct{}

func (c *Claude) Name() string { return "claude" }
// ... Discover, Parse, ParseLive, ExtractProjectPath
// (these are refactored from the current parser and sync packages)
```

Activation via blank import in the CLI entrypoint:

```go
// cmd/jevons/main.go
package main

import (
    "github.com/giannimassi/jevons/internal/cli"
    _ "github.com/giannimassi/jevons/internal/provider/claude"
    // _ "github.com/giannimassi/jevons/internal/provider/cursor"  // future
)
```

### Why Not Plugin-Based or Config-Driven?

- **Go plugins (`.so`)**: Fragile, platform-specific, not supported on all OS/arch combos, version-coupling issues between plugin and host. Massively over-engineered for a local CLI tool with 2-5 providers.
- **Config-driven factory**: Adds a config file schema, a factory dispatcher, and runtime error handling for misspelled provider names — all for a problem that doesn't exist yet. When Jevons has 10+ providers and users want to enable/disable them without recompiling, revisit this. For v0.2, `init()` + blank imports is the Go standard pattern (see `database/sql` drivers, `image` format decoders).

---

## 3. Event Model Changes

### TokenEvent: Add `Provider` Field

```go
// pkg/model/event.go
type TokenEvent struct {
    TSEpoch        int64  `json:"ts_epoch"`
    TSISO          string `json:"ts_iso"`
    Provider       string `json:"provider"`       // NEW: "claude", "cursor", etc.
    ProjectSlug    string `json:"project_slug"`
    SessionID      string `json:"session_id"`
    Input          int64  `json:"input"`
    Output         int64  `json:"output"`
    CacheRead      int64  `json:"cache_read"`
    CacheCreate    int64  `json:"cache_create"`
    Billable       int64  `json:"billable"`
    TotalWithCache int64  `json:"total_with_cache"`
    ContentType    string `json:"content_type"`
    Signature      string `json:"signature"`
}
```

### TSV Format Change

Add `provider` as column 3 (after `ts_iso`, before `project_slug`):

**v0.1 (12 columns):**
```
ts_epoch  ts_iso  project_slug  session_id  input  output  cache_read  cache_create  billable  total_with_cache  content_type  signature
```

**v0.2 (13 columns):**
```
ts_epoch  ts_iso  provider  project_slug  session_id  input  output  cache_read  cache_create  billable  total_with_cache  content_type  signature
```

Position 3 is chosen so that the new column sits logically between the "when" fields (epoch, ISO) and the "what" fields (project, session). This groups related concerns.

### Store Changes

```go
// internal/store/tsv.go

const EventsTSVHeader = "ts_epoch\tts_iso\tprovider\tproject_slug\tsession_id\tinput\toutput\tcache_read\tcache_create\tbillable\ttotal_with_cache\tcontent_type\tsignature"

func MarshalTokenEvent(e model.TokenEvent) string {
    return fmt.Sprintf("%d\t%s\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%s",
        e.TSEpoch, e.TSISO, e.Provider, e.ProjectSlug, e.SessionID,
        e.Input, e.Output, e.CacheRead, e.CacheCreate,
        e.Billable, e.TotalWithCache, e.ContentType, e.Signature,
    )
}

func UnmarshalTokenEvent(line string) (model.TokenEvent, error) {
    fields := strings.Split(line, "\t")
    // Detect format version by field count
    switch len(fields) {
    case 12: // v0.1 format — no provider column
        return unmarshalV1(fields)
    case 13: // v0.2 format — has provider column
        return unmarshalV2(fields)
    default:
        return model.TokenEvent{}, fmt.Errorf("expected 12 or 13 fields, got %d", len(fields))
    }
}

func unmarshalV1(fields []string) (model.TokenEvent, error) {
    // Parse the 12-column format, set Provider to "claude" (backfill default)
    e, err := parseFields(fields[0], fields[1], fields[2], fields[3],
        fields[4], fields[5], fields[6], fields[7],
        fields[8], fields[9], fields[10], fields[11])
    if err != nil {
        return e, err
    }
    e.Provider = "claude" // all v0.1 data is Claude
    return e, nil
}

func unmarshalV2(fields []string) (model.TokenEvent, error) {
    // Parse the 13-column format, Provider is fields[2]
    e, err := parseFields(fields[0], fields[1], fields[3], fields[4],
        fields[5], fields[6], fields[7], fields[8],
        fields[9], fields[10], fields[11], fields[12])
    if err != nil {
        return e, err
    }
    e.Provider = fields[2]
    return e, nil
}
```

The same pattern applies to `LiveEvent` (14 columns in v0.2 vs 13 in v0.1).

### Backward Compatibility

- **Reading v0.1 data**: Field-count detection in `UnmarshalTokenEvent` handles this automatically. v0.1 rows (12 fields) get `Provider: "claude"`.
- **Writing always uses v0.2**: Once synced with v0.2, TSV files get the new header and 13-column rows. This is fine because jevons always rewrites the full TSV on sync (it's not append-only).
- **No header-based detection needed**: The header line changes too, but since we detect by field count per row, stale header lines are harmless.

---

## 4. Dashboard Changes

### Current State

The dashboard (`internal/dashboard/assets/index.html`) is a single-page app that fetches `events.tsv`, `live-events.tsv`, `projects.json`, and `account.json` via relative HTTP paths. It parses TSV client-side in JavaScript.

### Required Changes

**4a. TSV Parsing Update**

The JavaScript TSV parser must handle both 12-column (v0.1 backcompat) and 13-column (v0.2) rows. Since the dashboard is regenerated on each `web` start, we only need to support the v0.2 header going forward — the Go store will have already migrated the data.

```javascript
// Column index constants
const COL = hasProviderCol
    ? { epoch: 0, iso: 1, provider: 2, slug: 3, session: 4, input: 5, ... }
    : { epoch: 0, iso: 1, provider: -1, slug: 2, session: 3, input: 4, ... };
```

Simpler approach: since jevons rewrites TSV fully on sync, by the time the dashboard reads it, the data is always in v0.2 format. The JS parser just needs to handle 13 columns.

**4b. Provider Filter**

Add a provider dropdown/pill bar next to the existing time-range selector:

- "All" (default) shows aggregate across providers
- Individual provider names as toggleable pills
- Multi-select: user can compare Claude + Cursor side by side
- Populated dynamically from unique values in the `provider` column

**4c. Chart Color Coding**

Assign each provider a distinct color. The chart stacking should show provider breakdown:

| Provider | Color suggestion |
|----------|-----------------|
| claude   | `#0f766e` (current teal accent) |
| cursor   | `#7c3aed` (purple) |
| copilot  | `#2563eb` (blue) |
| windsurf | `#ea580c` (orange) |

For v0.2, a simple legend below the chart is sufficient. Stacked bar/area charts can come in v0.3 when there's real multi-provider data to test with.

**4d. Live Table Provider Column**

Add a "Provider" column to the live events table, positioned after the timestamp column. Use a colored badge/pill for visual distinction:

```html
<td><span class="provider-badge provider-claude">claude</span></td>
```

**4e. Scope Tree**

The existing scope tree groups events by project slug (directory path). For v0.2, add a top-level grouping option: group by provider first, then by project. This is a UI toggle, not a data model change.

---

## 5. Migration Path

### v0.2 Reads v0.1 Data (Required)

This is guaranteed by the field-count detection in `UnmarshalTokenEvent` (see Section 3). The first sync after upgrading to v0.2 will:

1. Read existing v0.1 `events.tsv` (12 columns) — technically jevons doesn't read the existing TSV during sync; it re-parses all JSONL source files and rewrites the TSV from scratch
2. Parse all JSONL files using the registered Claude provider
3. Write new `events.tsv` with v0.2 header (13 columns), all rows having `provider: "claude"`

Since the sync pipeline always does a full rebuild from source JSONL files (not incremental append), migration is automatic. There's no need to read and transform the old TSV — it gets overwritten.

### Backfill Strategy

Because sync re-parses all source files, backfill is inherent:

- All existing Claude Code session files in `~/.claude/projects/` get parsed by the Claude provider
- Every resulting `TokenEvent` has `Provider: "claude"` set by the provider
- The TSV is rewritten in full with the new format

No separate migration tool or version-detection file is needed for v0.2.

### What If Incremental Sync Is Added Later?

If a future version adds incremental sync (append-only, track last-synced position per file), then we'd need:

- A `version` line at the top of the TSV (e.g., `#v2` comment) or a separate `data-version.json`
- A one-time migration that reads v0.1 rows, adds the `provider` column, and rewrites

But that's not needed for v0.2 since full-rebuild sync is the current and planned model.

---

## 6. Alternative Design Considered

### Alternative: Separate Data Stores Per Provider

Instead of adding a `provider` column to a unified `events.tsv`, each provider would write to its own file:

```
$DATA_ROOT/events-claude.tsv
$DATA_ROOT/events-cursor.tsv
$DATA_ROOT/live-events-claude.tsv
$DATA_ROOT/live-events-cursor.tsv
```

**Pros:**
- Zero schema change to the existing TSV format — v0.1 and v0.2 files are identical in structure
- Providers can be synced independently (one provider failing doesn't block others)
- Easy to delete all data for a single provider
- No backward-compatibility concern — existing `events.tsv` just becomes `events-claude.tsv`

**Cons (why rejected):**
- **Dashboard complexity explodes**: The dashboard must fetch N files instead of 1, merge them client-side, handle clock skew between files, and maintain sort order across providers. The current single-file-fetch-and-parse is simple and fast.
- **CLI commands (`total`, `graph`) must merge files**: Every command that reads events must now glob `events-*.tsv`, parse them all, merge, and sort. This duplicates the "merge N sorted streams" logic in every consumer.
- **Cross-provider queries are harder**: "Show me total usage across all providers for the last 24h" requires opening and scanning all files. With a unified store, it's one file scan.
- **Dedup across providers is ambiguous**: If the same API call somehow appears in two providers' logs (unlikely but possible with shared backends), dedup must span files.
- **File proliferation**: With N providers and 2 file types (events + live-events), you get 2N files plus the need for a manifest to know which providers have data.

The unified-store approach (adding a `provider` column) costs one extra column per row and a minor schema bump, but keeps every consumer simple: one file, one parse, one sort. The tradeoff clearly favors the unified approach for a local tool where the total data volume is small (tens of thousands of rows, not millions).

### Also Considered: Event Bus / Observer Pattern

A pub/sub or event-bus pattern where providers publish events and consumers (TSV writer, dashboard, alerter) subscribe.

**Why rejected**: Jevons is a batch-sync tool, not a streaming pipeline. It reads all source files, produces a sorted deduplicated TSV, and exits (or repeats on a timer). An event bus adds concurrency, ordering, backpressure, and delivery-guarantee complexity for a problem that's "read files, write file." The batch model is correct for the current architecture and would only change if jevons added real-time streaming (watching files for changes), which is not on the v0.2 roadmap.

---

## 7. v0.2 Feature Roadmap

| Feature | Priority | Complexity | Dependencies | Notes |
|---------|----------|------------|--------------|-------|
| Provider interface + Claude impl | P0 | Medium | None | Refactor existing code behind the interface. ~2 days. |
| `Provider` field in TokenEvent + TSV v2 | P0 | Low | Provider interface | Mechanical: add field, update marshal/unmarshal, field-count detection. ~0.5 day. |
| Provider registry (compiled-in) | P0 | Low | Provider interface | Registry + blank import pattern. ~0.5 day. |
| Sync pipeline uses providers | P0 | Medium | All P0 above | Refactor `sync.Run` to iterate `provider.All()` instead of hardcoding. ~1 day. |
| Dashboard: parse v0.2 TSV | P1 | Low | TSV v2 | Update JS column indices. ~0.5 day. |
| Dashboard: provider filter | P1 | Medium | Dashboard v0.2 parse | Dropdown/pills, filter events by provider. ~1 day. |
| Dashboard: provider color coding | P1 | Low | Provider filter | Color map, legend, chart segments. ~0.5 day. |
| Config file support (jevons.toml) | P2 | Medium | None | Per-provider source dirs, enabled/disabled providers, port, interval. ~1.5 days. |
| Second provider: Cursor | P2 | High | Provider interface, config | New parser for Cursor's log format (likely SQLite or different JSON schema). Research needed. ~3 days. |
| Cost tracking ($/token pricing) | P2 | Medium | Provider field | Provider-specific pricing tables, cost column in events, dashboard cost view. ~2 days. |
| Dashboard: scope tree by provider | P2 | Medium | Provider filter | Top-level grouping toggle. ~1 day. |
| Budget alerts (CLI) | P3 | Medium | Cost tracking | Daily/weekly/monthly budget thresholds, `jevons alert` command. ~1.5 days. |
| Budget alerts (dashboard) | P3 | Medium | Budget alerts CLI | Visual budget bar, notification badge. ~1 day. |
| Third provider: Copilot | P3 | High | Provider interface | Research GitHub Copilot's local log format. May not have token-level data. ~3 days. |
| Incremental sync | P3 | High | None | Track last-synced offset per file, append-only TSV. Big perf win for large histories. ~3 days. |

### Recommended Implementation Order

**Phase 1 (v0.2-alpha):** Provider interface + Claude implementation + TokenEvent changes + sync refactor. This is purely internal refactoring — zero user-visible behavior change. Ship it, verify all 104 existing tests still pass, run parity tests.

**Phase 2 (v0.2-beta):** Dashboard v0.2 parsing + provider filter + color coding. Now the UI is ready for multi-provider data even though only Claude exists.

**Phase 3 (v0.2):** Config file + second provider (Cursor). This is the first real test of the abstraction. If the interface needs adjustment, better to discover it here than after shipping a "stable" v0.2.

**Phase 4 (v0.3+):** Cost tracking, budget alerts, more providers, incremental sync.

---

## Appendix: File Changes Summary

Files that will be **created**:
```
internal/provider/provider.go       # Provider interface + SessionFile type
internal/provider/registry.go       # Register/Get/All/Names functions
internal/provider/claude/claude.go  # Claude provider implementation
internal/provider/claude/claude_test.go
```

Files that will be **modified**:
```
pkg/model/event.go                  # Add Provider field to TokenEvent
internal/store/tsv.go               # Updated headers, marshal/unmarshal with field-count detection
internal/sync/sync.go               # Refactor to use provider.All() loop
internal/dashboard/assets/index.html # v0.2 TSV parsing, provider filter/colors
cmd/jevons/main.go                  # Add blank import for Claude provider
```

Files that will be **moved/absorbed** (code relocated, not deleted):
```
internal/parser/parser.go           # Core logic moves to internal/provider/claude/claude.go
                                    # parser.go may remain as a thin wrapper for backward compat,
                                    # or be removed if no external consumers depend on it
```
