# Track: v0.2+ Feature Research

- **Repo:** jevons
- **Last Updated:** 2026-02-13
- **Research Constraint:** Limited to public knowledge and codebase analysis (web search unavailable)

---

## 1. AI Tool Session Log Formats

This section documents session log storage for 5 AI coding tools. Research is based on general knowledge of these products; **specific implementation details marked as UNCERTAIN require validation before implementation**.

### 1.1 Claude Code (BASELINE — Current Support)

**Status:** ✅ Fully supported in v0.1.0

**Storage Location:**
- `~/.claude/projects/<project-slug>/*.jsonl`
- Each project (directory or repo) gets a slug-based folder
- Each session creates a timestamped JSONL file

**Data Available:**
- Token counts: input, output, cache_read, cache_create
- Timestamps (ISO and epoch)
- Session metadata: project slug, session ID
- Content type (user/assistant messages, tool use)
- Full conversation history (messages, tool calls, results)

**Log Format:**
- JSONL (JSON Lines) — one event per line
- State-machine format: each line represents a turn or event in the session
- Dedup strategy uses composite signatures (timestamp + content hash)

**Accessibility:**
- ✅ Fully local, no auth required
- Plain text JSONL readable by standard tools

**Feasibility for Jevons:**
- ✅ **Already implemented** — serves as reference for other providers

**Reference:**
- See `internal/parser/parser.go` (lines 44-120) for current implementation

---

### 1.2 Cursor

**Storage Location (UNCERTAIN):**
- Likely: `~/Library/Application Support/Cursor/` (macOS)
- Likely: `%APPDATA%/Cursor/` (Windows)
- Likely: `~/.config/Cursor/` (Linux)
- **UNCERTAIN:** Exact subdirectory structure unknown

**Data Available (UNCERTAIN):**
- Cursor is a VS Code fork with AI features (likely uses SQLite like VS Code)
- May track: model usage, completions accepted/rejected, token counts
- Likely has: timestamps, file context, completion text
- **UNCERTAIN:** Whether token-level billing data is stored locally

**Log Format (UNCERTAIN):**
- **Best guess:** SQLite database (VS Code pattern)
- Alternative possibility: JSON or JSONL logs
- **UNCERTAIN:** Schema structure, table names, dedup strategy

**Accessibility:**
- Likely local, but format unknown
- If SQLite, requires database driver (`database/sql` + `github.com/mattn/go-sqlite3`)
- **UNCERTAIN:** Whether logs are encrypted or require auth

**Feasibility for Jevons:**
- **Medium to Hard** — depends entirely on log format
- If SQLite with readable schema: Medium (1-2 days for parser)
- If proprietary/encrypted format: Hard or Impossible
- **Blocker:** Need to inspect actual Cursor installation to determine feasibility

**Next Steps:**
1. Install Cursor and run a test session
2. Inspect `~/Library/Application Support/Cursor/` for log files
3. If SQLite, dump schema with `sqlite3 <db> .schema`
4. Verify token usage data is present and accessible

---

### 1.3 GitHub Copilot

**Storage Location (UNCERTAIN):**
- Likely: Extension data directory within VS Code/JetBrains settings
- VS Code: `~/.config/Code/User/globalStorage/github.copilot/`
- JetBrains: `~/Library/Application Support/JetBrains/<IDE>/github-copilot/`
- **UNCERTAIN:** Exact paths vary by IDE

**Data Available (UNCERTAIN):**
- Copilot is primarily a completion engine (not full conversation logs)
- May track: suggestions shown, acceptances, rejections
- **UNCERTAIN:** Whether token counts are stored locally
- **LIKELY:** Token usage tracked server-side only (GitHub's billing system)

**Log Format (UNCERTAIN):**
- Likely: Telemetry logs in JSON format
- May not include detailed token counts (those live on GitHub's servers)
- **UNCERTAIN:** Whether local logs are sufficient for usage tracking

**Accessibility:**
- Local files accessible if they exist
- **MAJOR UNCERTAINTY:** Whether local logs contain billing-relevant data
- GitHub's billing dashboard is the primary source of truth for Copilot usage

**Feasibility for Jevons:**
- **Hard to Unknown** — depends on whether local logs have token data
- If local logs only track UI events (suggestions/acceptances): Not feasible without API integration
- If local logs include token counts: Medium (parse JSON telemetry)
- **Likely blocker:** Copilot may not expose token-level data locally

**Next Steps:**
1. Install Copilot in VS Code and run test sessions
2. Inspect extension data directory for logs
3. Check if token counts appear in local files or only in GitHub dashboard
4. If local data insufficient, assess GitHub API integration (out of scope for v0.2)

**Note:** Copilot's model is fundamentally different from Claude Code/Cursor — it's autocomplete-focused, not session-based chat. This may require a different mental model for "usage" (completions per hour vs tokens per session).

---

### 1.4 Windsurf (Codeium)

**Storage Location (UNCERTAIN):**
- Windsurf is Codeium's standalone IDE (Electron-based, like Cursor)
- Likely: `~/Library/Application Support/Windsurf/` (macOS)
- Likely: `%APPDATA%/Windsurf/` (Windows)
- Likely: `~/.config/Windsurf/` (Linux)
- **UNCERTAIN:** Exact subdirectory structure unknown

**Data Available (UNCERTAIN):**
- Codeium offers free unlimited usage (different billing model than Claude/Cursor)
- May track: completions, chat sessions, model invocations
- **UNCERTAIN:** Whether token counts are logged (less important for a free product)
- Likely has: timestamps, session IDs, file context

**Log Format (UNCERTAIN):**
- **Best guess:** JSON or JSONL logs (similar to Cursor/VS Code patterns)
- Alternative: SQLite database
- **UNCERTAIN:** Schema structure, what metrics are tracked

**Accessibility:**
- Likely local and unencrypted
- **UNCERTAIN:** Whether usage data is detailed enough for tracking

**Feasibility for Jevons:**
- **Medium to Hard** — depends on log format and data richness
- If JSON/JSONL with session data: Medium (1-2 days)
- If minimal telemetry (just ping/heartbeat): Not useful for usage tracking
- **Question:** Since Codeium is free, is token tracking relevant? Users may care more about "sessions" or "requests" than tokens.

**Next Steps:**
1. Install Windsurf and run test sessions
2. Inspect application support directory for logs
3. Determine what metrics are tracked (tokens vs requests vs completions)
4. Assess whether data format is worth supporting in v0.2

---

### 1.5 Aider

**Storage Location (KNOWN):**
- Aider is a CLI tool that uses `.aider*` files in the working directory
- Chat history: `.aider.chat.history.md` (markdown format, human-readable)
- Session metadata: Likely in-memory or ephemeral (CLI tool, not persistent service)
- **KNOWN:** Aider uses LiteLLM for model routing, which logs to `~/.litellm/` (if configured)

**Data Available:**
- Aider's `.aider.chat.history.md` contains full conversation text
- **UNCERTAIN:** Whether token counts are stored locally
- LiteLLM can log token usage if configured, but:
  - Not enabled by default
  - Requires explicit user setup
  - Logs to separate directory from Aider itself

**Log Format:**
- Chat history: Markdown (not structured data)
- LiteLLM logs (if enabled): JSON
- **CHALLENGE:** Extracting token counts from markdown requires parsing LLM response headers or inferring from text length (unreliable)

**Accessibility:**
- ✅ Fully local, plain text
- But: Markdown is not a structured format for token tracking

**Feasibility for Jevons:**
- **Medium to Hard**
- If LiteLLM logging is enabled: Medium (parse JSON logs, similar to Claude)
- If only markdown history: Hard (unreliable token estimation, no true billing data)
- **Complexity:** Aider's session model is different — it's project-local (`.aider*` files in each repo) rather than centralized (like `~/.claude/projects`)

**Next Steps:**
1. Run Aider with LiteLLM logging enabled
2. Check if `~/.litellm/` or `.aider.chat.history.md` contains token counts
3. Assess whether markdown parsing is feasible or if LiteLLM integration is required
4. Consider whether Aider's distributed session model (per-project files) fits Jevons' centralized architecture

**Note:** Aider's philosophy is different — it's stateless and ephemeral by default. Users may not expect or want centralized usage tracking. This may be a P2/P3 feature rather than v0.2.

---

## 2. Feature Candidates

### 2.1 Multi-Provider Support (Provider Abstraction + Second Provider)

**Description:**
Refactor Jevons to support multiple AI tools via a provider interface. Move Claude-specific parsing into a pluggable provider, implement a second provider (Cursor or Aider).

**Effort:** L (1 week)
- Provider interface design: 1 day
- Refactor Claude into provider: 2 days
- Implement second provider: 3 days (depends on log format complexity)
- Testing and integration: 1 day

**Dependencies:**
- None (foundational for all other v0.2+ features)

**Priority:** P0 (v0.2 must-have)

**Notes:**
- Already designed in `track-feature-arch.md` (Section 1-2)
- Critical path for v0.2 — everything else builds on this
- Choose second provider based on research findings (Cursor most likely if logs are accessible)

---

### 2.2 Cost/Pricing Tracking

**Description:**
Add $/token pricing per provider and model. Calculate costs in addition to token counts. Display total spend in dashboard and CLI.

**Effort:** M (2-3 days)
- Define pricing table format (JSON or hardcoded): 0.5 day
- Add `Cost` field to `TokenEvent`, update TSV schema: 0.5 day
- Implement pricing calculator per provider: 1 day
- Update dashboard to show cost view (toggle between tokens/cost): 1 day

**Dependencies:**
- Provider abstraction (each provider has different pricing)
- `Provider` field in `TokenEvent` (needed to look up pricing)

**Priority:** P1 (v0.2 nice-to-have)

**Notes:**
- Pricing changes over time — need to decide: hardcode current prices, or support historical pricing?
- For v0.2, hardcoded current prices are sufficient
- v0.3+ could add a `pricing.json` config with date-based pricing history
- **Challenge:** Claude has different prices for prompt caching vs non-cached tokens — current event model tracks `cache_read`/`cache_create` separately, so this is feasible

---

### 2.3 Dashboard Improvements (Provider Filter, Color Coding, Scope Tree)

**Description:**
Add UI elements to filter and visualize multi-provider data:
- Provider filter dropdown (All / Claude / Cursor / etc.)
- Color-coded chart segments per provider
- Scope tree grouped by provider (optional top-level grouping)

**Effort:** M (2-3 days)
- Provider filter dropdown: 1 day
- Color coding and legend: 0.5 day
- Scope tree grouping toggle: 1 day

**Dependencies:**
- Provider abstraction (needs `provider` column in TSV)
- Multi-provider data to test with (needs second provider implementation)

**Priority:** P1 (v0.2 nice-to-have)

**Notes:**
- Already designed in `track-feature-arch.md` (Section 4)
- Can be implemented in parallel with second provider (mock data for testing)
- Visual polish that makes multi-provider data usable

---

### 2.4 Config File Support (jevons.toml)

**Description:**
Add a config file (`~/.config/jevons/config.toml` or `jevons.toml` in cwd) to control:
- Per-provider settings (source directories, enabled/disabled)
- Dashboard settings (port, refresh interval)
- Sync settings (interval, log level)

**Effort:** M (2-3 days)
- Define TOML schema: 0.5 day
- Implement config loader (use `github.com/BurntSushi/toml`): 1 day
- Integrate with existing CLI flags (config < flags for overrides): 1 day
- Documentation and examples: 0.5 day

**Dependencies:**
- Provider abstraction (to configure per-provider settings)

**Priority:** P2 (v0.3+)

**Notes:**
- Not critical for v0.2 — environment variables and CLI flags are sufficient for early adopters
- Becomes important when users want to disable providers or customize source directories
- **Design question:** Config file location — `~/.config/jevons/config.toml` (XDG standard) vs `jevons.toml` in cwd (project-local)?
  - Recommendation: Support both, prioritize cwd > ~/.config > defaults

---

### 2.5 Notifications/Alerts

**Description:**
CLI or desktop notifications for usage thresholds:
- Daily/weekly/monthly budget alerts (token or cost)
- Anomaly detection (unusual spike in usage)
- Low-priority: Desktop notifications (requires platform-specific code)

**Effort:** M (2-3 days) for CLI, L (1 week+) for desktop
- CLI alerts (check during sync, print warning): 1 day
- Budget threshold config: 0.5 day
- Anomaly detection (simple heuristic: >2x daily average): 1 day
- Desktop notifications: 3+ days (platform-specific, low ROI)

**Dependencies:**
- Cost tracking (for budget alerts)
- Config file (to set thresholds)

**Priority:** P2 (v0.3+)

**Notes:**
- CLI alerts are easy and useful (print warning during sync)
- Desktop notifications are complex (macOS: AppleScript, Linux: libnotify, Windows: toast) and may not be worth it for a CLI tool
- **Recommendation:** v0.2 focus on CLI alerts, defer desktop notifications to v0.4+

---

### 2.6 Data Export (CSV, JSON API)

**Description:**
Export aggregated data in standard formats:
- `jevons export --format csv --range 7d > usage.csv` (for Excel/analysis)
- `jevons export --format json --range 7d` (for scripting/automation)
- Optional: HTTP API endpoint (`GET /api/events?range=7d&format=json`) for integrations

**Effort:** S (1 day) for CLI, M (2 days) for API
- CSV export: 0.5 day (trivial — TSV is already CSV-like)
- JSON export: 0.5 day (read TSV, marshal to JSON)
- HTTP API endpoint: 2 days (add routes, authentication, CORS)

**Dependencies:**
- None (reads existing TSV data)

**Priority:** P2 (v0.3+)

**Notes:**
- CSV export is trivial and useful (almost free)
- JSON export is easy (already have JSON marshaling for events)
- HTTP API is more complex — do users need it? Most use cases covered by dashboard
- **Recommendation:** v0.2 add CSV/JSON export commands, defer API to v0.4+ if demand exists

---

### 2.7 Team/Shared Dashboards

**Description:**
Aggregate usage data from multiple users (team dashboard):
- Multiple users sync to a shared data directory
- Dashboard shows per-user breakdown
- Requires user identification (config or environment variable)

**Effort:** L (1 week)
- Add `user` field to events: 1 day
- Multi-user data directory layout: 1 day
- Dashboard aggregation and filtering: 2 days
- Testing and documentation: 1 day

**Dependencies:**
- Provider abstraction (not strictly required, but cleaner with it)
- Config file (to set user ID)

**Priority:** P3 (v0.4+)

**Notes:**
- Complex feature with many open questions:
  - How do users identify themselves? (config file, env var, CLI flag?)
  - Shared storage: NFS mount, cloud sync (Dropbox), or Git-based?
  - Privacy: do users want to share prompt previews with their team?
- **Recommendation:** Defer to v0.4+ when there's real demand. Individual usage tracking is the 90% use case.

---

## 3. v0.2 Feature Roadmap

### Phase 1: Internal Refactoring (v0.2-alpha)

**Goal:** Provider abstraction with zero user-visible changes. All 104 existing tests still pass.

**Duration:** 1 week

**Tasks:**
1. Define `Provider` interface (`internal/provider/provider.go`)
2. Implement provider registry (`internal/provider/registry.go`)
3. Refactor Claude parser into `internal/provider/claude/claude.go`
4. Add `Provider` field to `TokenEvent` and update TSV schema (v1 -> v2 with backward compat)
5. Refactor sync pipeline to use `provider.All()` loop
6. Run full test suite + parity tests to verify no regressions

**Success Criteria:**
- `make test` passes (104 subtests)
- `make test-parity` shows identical output between v0.1 and v0.2-alpha
- `jevons sync && jevons web` works exactly as before

**Deliverables:**
- Provider interface merged to main
- TSV format v2 with backward compat (reads v1, writes v2)
- Claude provider as first implementation

---

### Phase 2: Dashboard + First Provider Additions (v0.2-beta)

**Goal:** Dashboard supports multi-provider data. Add second provider (Cursor or Aider, based on research).

**Duration:** 1 week

**Tasks:**
1. Research second provider's log format (Cursor preferred, Aider fallback)
2. Implement second provider (parse logs, extract tokens)
3. Update dashboard to parse v2 TSV (13 columns)
4. Add provider filter dropdown to dashboard
5. Add color coding and legend per provider
6. Test with real data from both providers

**Success Criteria:**
- Second provider successfully syncs data
- Dashboard displays both providers' data with filters and colors
- `jevons status` shows per-provider stats

**Deliverables:**
- Second provider implementation (Cursor or Aider)
- Dashboard UI with provider filter and color coding
- Updated documentation

**Risks:**
- Second provider's log format may be harder than expected (see Section 4)
- If Cursor logs are encrypted/proprietary, fall back to Aider

---

### Phase 3: Config + Polish (v0.2)

**Goal:** Ship v0.2 with config file support and cost tracking (stretch goal).

**Duration:** 1 week

**Tasks:**
1. Implement config file loader (`jevons.toml`)
2. Add per-provider config (source dirs, enabled/disabled)
3. (Stretch) Add cost tracking if time permits
4. Update documentation and examples
5. Release v0.2

**Success Criteria:**
- Config file works with defaults and overrides
- Users can disable providers or customize source directories
- v0.2 ships with at least 2 providers

**Deliverables:**
- Config file support
- (Stretch) Cost tracking
- v0.2 release

---

### Phase 4: Advanced Features (v0.3+)

**Goal:** Add cost tracking (if not in v0.2), alerts, export commands.

**Duration:** 2-3 weeks (spread across multiple releases)

**Tasks:**
1. Cost tracking (if deferred from v0.2)
2. Budget alerts (CLI warnings during sync)
3. CSV/JSON export commands
4. Third provider (Copilot or Windsurf, based on demand)
5. Incremental sync (performance optimization)

**Success Criteria:**
- Cost tracking shows accurate $/usage
- Alerts warn users when approaching budget limits
- Export commands work for scripting/automation

**Deliverables:**
- v0.3: Cost tracking + alerts
- v0.4: Export + third provider
- v0.5: Incremental sync

---

## 4. Risk Assessment

### 4.1 Biggest Unknowns

1. **Log format accessibility (Cursor, Windsurf, Copilot)**
   - **Risk:** High
   - **Impact:** Could block second provider implementation
   - **Mitigation:** Research actual log formats before committing to a provider. If Cursor is inaccessible, pivot to Aider (known format).

2. **Token data availability (Copilot, Windsurf)**
   - **Risk:** Medium
   - **Impact:** Tools may not log token counts locally (only server-side)
   - **Mitigation:** Prioritize tools that log detailed usage locally (Claude, Cursor likely, Copilot unlikely).

3. **Provider diversity (different session models)**
   - **Risk:** Medium
   - **Impact:** Aider's per-project files vs Claude's centralized logs require different discovery logic
   - **Mitigation:** Provider interface is flexible enough to handle this (see `Discover()` method).

---

### 4.2 Features with Highest Implementation Risk

1. **Second provider implementation (Cursor/Windsurf)**
   - **Risk:** High
   - **Reason:** Log format is unknown until we inspect actual installations
   - **Worst case:** Logs are encrypted, proprietary, or missing token data
   - **Mitigation:** Build interface first, test with Claude, then add second provider. If blocked, ship v0.2 with interface + Claude only, add providers in v0.2.1+.

2. **Cost tracking**
   - **Risk:** Medium
   - **Reason:** Pricing changes over time, different models have different prices
   - **Complexity:** Need to track model used per event (not currently in TSV schema)
   - **Mitigation:** Start with hardcoded current prices for common models. Add model tracking to TSV schema if needed.

3. **Team dashboards**
   - **Risk:** High
   - **Reason:** Many open questions (storage, privacy, user ID)
   - **Mitigation:** Defer to v0.4+. Not critical for v0.2.

---

### 4.3 What Could Block the v0.2 Roadmap

**Blocker 1: No viable second provider**
- **Scenario:** Cursor, Windsurf, and Copilot all have inaccessible/unusable log formats
- **Probability:** Medium (25%)
- **Impact:** v0.2 ships with provider interface but only Claude implementation
- **Mitigation:** Aider is a fallback (known format, but may require LiteLLM integration)

**Blocker 2: TSV schema migration breaks backward compat**
- **Scenario:** Field-count detection fails, users lose historical data
- **Probability:** Low (10%)
- **Impact:** Critical — loss of user data
- **Mitigation:** Extensive testing with v0.1 data before release. Provide rollback instructions.

**Blocker 3: Provider interface too rigid**
- **Scenario:** Second provider reveals that the interface design is wrong
- **Probability:** Medium (30%)
- **Impact:** Major refactor mid-v0.2 development
- **Mitigation:** Design interface based on knowledge of multiple tools (not just Claude). Test with mock providers before implementing real ones.

---

## 5. Research Next Steps

Before implementing v0.2, validate these assumptions:

### Required Research (Blocking v0.2)

1. **Cursor log format:**
   - Install Cursor IDE
   - Run test sessions (completions + chat)
   - Inspect `~/Library/Application Support/Cursor/` for logs
   - Document: format (SQLite/JSON/other), schema, token data availability

2. **Aider log format:**
   - Install Aider CLI
   - Run test sessions with LiteLLM logging enabled
   - Check `.aider.chat.history.md` and `~/.litellm/` for token data
   - Document: whether LiteLLM integration is required

### Optional Research (Informing v0.3+)

3. **Copilot log format:**
   - Install Copilot in VS Code
   - Run test sessions
   - Inspect extension data directory for logs
   - Determine if local logs contain token counts (or if API integration is needed)

4. **Windsurf log format:**
   - Install Windsurf IDE
   - Run test sessions
   - Inspect application support directory for logs
   - Determine if token tracking is relevant (given free tier model)

---

## 6. Recommendation Summary

### For v0.2 (Ship in 3-4 weeks)

**Must-have (P0):**
- Provider interface + registry
- Claude provider (refactored from existing code)
- TSV schema v2 with `provider` column
- Backward compatibility with v0.1 data

**Should-have (P1):**
- Second provider (Cursor if accessible, Aider as fallback)
- Dashboard provider filter and color coding

**Nice-to-have (P2, cut if time-constrained):**
- Config file support (can defer to v0.2.1)
- Cost tracking (can defer to v0.3)

### For v0.3+ (Future Releases)

- Cost tracking and budget alerts
- CSV/JSON export commands
- Third provider (based on demand)
- Incremental sync (performance)
- Team dashboards (if there's demand)

### Decision Points

**Week 1 (Research):**
- By end of week: Know whether Cursor logs are usable
- Decision: Cursor or Aider as second provider?

**Week 2-3 (Implementation):**
- By end of week 2: Provider interface + Claude implementation complete
- By end of week 3: Second provider working or pivoted to Aider

**Week 4 (Polish):**
- Dashboard updates
- Config file (stretch)
- Release v0.2

**Fallback Plan:**
If second provider is blocked, ship v0.2 with:
- Provider interface
- Claude provider only
- Documented path for adding providers in v0.2.1+

This is still valuable — it unblocks third-party contributions and sets up the architecture for future expansion.

---

## 7. Open Questions

1. **Should jevons support API-based providers (e.g., OpenAI API logs)?**
   - Current focus is local log files from IDE tools
   - But: users may also want to track direct API usage (scripts, experiments)
   - Decision: Defer to v0.3+. v0.2 focuses on IDE tools.

2. **Should jevons track non-token metrics (completions, requests, sessions)?**
   - Copilot's model is completion-based, not token-based
   - Different providers may have different "units" of usage
   - Decision: v0.2 stays focused on tokens. v0.3+ can add provider-specific metrics.

3. **Should jevons be a daemon or on-demand CLI?**
   - Current model: background sync daemon + web server
   - Alternative: on-demand sync only (no daemon)
   - Decision: Keep current model. Daemon provides continuous monitoring.

4. **Should jevons integrate with billing APIs (Claude API, GitHub API)?**
   - Pros: Accurate cost data, no local log parsing
   - Cons: Requires auth, network dependency, privacy concerns
   - Decision: v0.2 stays local-only. API integration is a v0.4+ feature if demanded.

---

## 8. Success Metrics for v0.2

How do we know v0.2 is successful?

**Technical:**
- At least 2 providers working (Claude + one other)
- All v0.1 tests pass
- Backward compatibility verified (v0.1 data readable)

**User Experience:**
- Dashboard shows multi-provider data with filters
- Config file or CLI flags to enable/disable providers
- Documentation updated with examples for each provider

**Adoption:**
- Users report successful syncs with second provider
- No data loss or corruption reports
- Feature requests for third provider (indicates v0.2 is useful)

---

**End of Research Document**
