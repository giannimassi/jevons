# Jevons Go Parity MVP — Adaptive Loop Prompt

## Section 1 — Task Description

Port the Jevons shell script (`claude-usage-tracker.sh`, 2715 lines) to a working Go CLI. The shell implementation is the fully functional reference — it reads AI session JSONL logs, extracts token usage events into TSV event stores, and serves an HTML dashboard.

The Go CLI skeleton exists (`cmd/jevons/`, `internal/`, `pkg/model/`) with proper architecture and data models, but ALL commands are stubs. Zero core logic has been implemented.

**Scope**: Go Parity MVP — implement `sync`, `web`, `status`, `total`, `graph` commands with format-compatible output, embedded dashboard, background daemon, and comprehensive tests.

**Reference implementation**: `claude-usage-tracker.sh` in repo root.

## Section 2 — Task Objective

The Go binary `jevons` must be able to sync JSONL session logs into TSV event stores, serve the existing dashboard over HTTP with background sync, and report usage totals — producing output format-compatible with the shell implementation.

## Section 3 — Context Loading

Every iteration, read these files FIRST (in order):

1. `challenges.md` — **CRITICAL: OPEN challenges block convergence**
2. `convergence.md` — current assessment of all criteria
3. `track-health.md` — track statuses and agent allocation history
4. Track output files: `track-parser.md`, `track-sync.md`, `track-dashboard.md`, `track-daemon.md`, `track-cli.md`, `track-testing.md`
5. Key source files for reference:
   - `claude-usage-tracker.sh` (shell reference implementation)
   - `CLAUDE.md` (project instructions)
   - `docs/GO_PORT_PLAN.md` (migration milestones)
   - `pkg/model/event.go`, `pkg/model/config.go` (existing data models)
   - `internal/store/tsv.go` (existing TSV serialization)
   - `internal/cli/*.go` (existing command stubs)

## Section 4 — Phase 0: Agent Allocation

### Phase 0: Agent Allocation (MANDATORY — run BEFORE dispatching any agents)

This phase decides WHERE to spend agent budget this iteration. Never skip it.

### Phase 0 Fast Path (check BEFORE full allocation)

Before running the full track health assessment, check for early exits:

1. **All COMPLETE**: If track-health.md shows ALL tracks were COMPLETE last iteration
   → Skip Phase 0 entirely. Go straight to convergence evaluation.

2. **Single active track**: If only 1 track changed status since last iteration (others stable)
   → Skip full allocation. Dispatch agents only to that track + 1 critic. Log abbreviated allocation.

3. **No state change**: If track-health.md last iteration statuses match current file sizes/checksums
   → Skip allocation. Re-dispatch same agents as last iteration with note "no state change, exploring different angles."

4. **Convergence imminent**: If ≥80% criteria are PASS and remaining are PARTIAL (not FAIL)
   → Reduce to 1-2 targeted agents for remaining PARTIAL criteria + 1 critic. Don't spray agents across done tracks.

If none of these apply → proceed with full Phase 0.

**Step 1: Assess track health.**

Read `track-health.md`. For each track, classify its current status:

| Status | Meaning | Action |
|--------|---------|--------|
| **NEW** | No output file yet, or file is a stub (<20 lines) | Dispatch 2-3 agents with different angles |
| **HOT** | Significant new content added last iteration (new sections, new insights, new sub-questions opened) | Dispatch 3+ agents (continue, explore new sub-questions, AND one to challenge/verify findings) |
| **WARM** | Some new content but incremental, not breakthroughs | Dispatch 2 agents with different perspectives |
| **COOLING** | No new substantive findings for 1 iteration (only minor edits) | Dispatch 2 agents with DIFFERENT angles than before |
| **COMPLETE** | No new findings for 2+ iterations AND corresponding convergence criteria are PASS | Do NOT dispatch agents. Track is done. |
| **STUCK** | No new findings for 2+ iterations BUT convergence criteria still PARTIAL/FAIL | Dispatch 2-3 agents with explicitly DIFFERENT approaches. Note in track-health what was already tried. |

**Sizing principle: err on the side of more agents.** Redundancy is a feature — multiple agents on the same problem with different viewpoints surface blind spots. The cost of an idle agent is low; the cost of a missing perspective is high.

**Step 2: Check for emergent tracks.**

If previous iterations surfaced important areas outside existing tracks, create ad-hoc tracks.

**Step 3: Write allocation plan to `track-health.md`.**

Append BEFORE dispatching agents:

## Iteration N

| Track | Status | Agents | Rationale |
|-------|--------|--------|-----------|

Total agents this iteration: X

**Step 4: Dispatch agents.**

Each agent's prompt must include:
- The specific track and sub-questions to investigate
- What has ALREADY been found (point to existing output file)
- What is MISSING or needs deeper investigation
- For STUCK tracks: what approaches were already tried and failed

### Agent Context Scoping

When building agent prompts, scope context to what each role needs:

| Agent Role | Required Context | Skip |
|---|---|---|
| Track work agent | Their track's output + challenges tagged to their track + goal + their criteria status | Other tracks' outputs |
| Critic agent | ALL track outputs + convergence.md + challenges.md | Track-health allocation history |
| Convergence evaluator | convergence.md + challenges.md + track output summaries (first/last 20 lines per file) | Full outputs, history |
| Phase 0 allocator (self) | track-health.md + file sizes of output files | Full output contents |

**Exception:** Cross-track dependencies include the referenced track's output too.

### Model & Reasoning Tiers

| Agent Role | Model | Rationale |
|---|---|---|
| Track work agent (research/explore) | sonnet | Reading + synthesis |
| Track work agent (implementation) | sonnet | Code gen |
| Track work agent (architecture) | opus | Deep reasoning needed |
| Critic agent | sonnet | Pattern matching |
| Phase 0 / convergence (self) | — | No extra call needed |

Override: STUCK tracks after 2+ iterations → escalate to opus for one iteration.
When dispatching via Task tool, set `model: "sonnet"` unless the task needs opus.

## Section 4.5 — Phase 1: Challenge Resolution & Critic Phase

### Phase 1: Challenge Resolution & Critic (MANDATORY — run AFTER Phase 0, BEFORE dispatching work agents)

**Step 1: Process challenges.**

Read `challenges.md`. Challenges can be in ANY format — structured entries with `## Challenge N:` headers, informal bullet lists, freeform paragraphs, or rough notes. Your job is to:
1. Identify every challenge or concern, regardless of format
2. Normalize any informal entries into the structured format (`## Challenge N: Title` / `**Status:** OPEN` / description) so they're trackable. Assign the next available number.
3. For every challenge with Status: OPEN:
   - Determine which track(s) the challenge affects
   - Add specific sub-tasks to those tracks' agent prompts that directly address the challenge
   - A challenge is ADDRESSED only when there is concrete evidence resolving it
   - Do NOT mark a challenge ADDRESSED by merely restating or acknowledging it
   - When marking ADDRESSED, write a **resolution summary** directly under the challenge: what was done, what evidence supports it, where to find details (file:section references). This is the audit trail — a reader should understand the resolution without digging through output files.

**Step 2: Run Critic agents.**

Dispatch 2-3 critic agents BEFORE work agents, each with a different lens (e.g., correctness, feasibility, missing alternatives, security, simplicity). Each critic agent must:
- Read ALL current output files
- Identify: surface-level claims lacking evidence, unsupported assertions, missing alternatives, internal contradictions
- For each issue found, either:
  - Add it as a new challenge in `challenges.md`
  - Add it as a specific sub-task in the relevant track's agent prompt
- Critics must be adversarial — their job is to find weaknesses, not confirm quality

**Step 3: Verify challenge coverage.**

Before dispatching work agents, verify every OPEN challenge maps to at least one agent's prompt. Document any that can't be addressed this iteration.

## Section 5 — Tracks

### T1: JSONL Parser (`internal/parser/`)

**Scope**: Port the shell's jq-based JSONL parsing to Go. Extract token usage events from `~/.claude/projects/<slug>/*.jsonl` session files.

**Output file**: `track-parser.md`

**Sub-questions**:
1. How does the shell extract `input`, `output`, `cache_read`, `cache_create` fields from JSONL message objects? (Lines 260-500 of shell script)
2. What is the dedup signature format and how is it computed?
3. How are content types detected (text, tool_use, tool_result)?
4. How are human prompts vs tool responses distinguished for LiveEvent prompt preview?
5. What edge cases exist — hyphenated repo names, missing `cwd` records, empty sessions, malformed JSON?
6. What is the `billable` and `total_with_cache` calculation formula?

### T2: Sync Pipeline (`internal/sync/`)

**Scope**: Orchestrate the full sync pipeline: discover session files → parse each → deduplicate → write TSV + JSON output files.

**Output file**: `track-sync.md`

**Sub-questions**:
1. How does session file discovery work — what glob pattern, directory structure?
2. What's the dedup strategy when re-syncing the same files? How does incremental sync work?
3. How is `projects.json` generated (slug → path manifest)?
4. What's the format and content of `sync-status.json`?
5. How are events sorted in the output TSV (by epoch)?
6. How does `account.json` generation work (from `~/.claude.json`)?

### T3: Dashboard & Web Server (`internal/dashboard/`, `web/`)

**Scope**: Extract dashboard HTML/CSS/JS from shell script, place static assets in `web/`, embed via `go:embed`, implement HTTP server.

**Output file**: `track-dashboard.md`

**Sub-questions**:
1. Can we extract the dashboard HTML verbatim from shell lines 792-2315?
2. What data endpoints does the dashboard fetch (relative paths to TSV/JSON)?
3. What's the right `go:embed` strategy — single HTML file or split assets?
4. Does the dashboard need dynamic generation (e.g., injecting config) or is it purely static?
5. What HTTP routes does the server need to handle?
6. How does `jevons web-stop` work (PID-based shutdown)?

### T4: Daemon & Status (`internal/daemon/`)

**Scope**: Background sync loop with heartbeat monitoring, PID management, start/stop lifecycle, status reporting.

**Output file**: `track-daemon.md`

**Sub-questions**:
1. What's the heartbeat file format (`epoch,interval,pid,status`)?
2. How does `sync_heartbeat_state()` work in the shell?
3. How does the shell manage background processes (nohup, PID files)?
4. What health checks exist — PID liveness (`kill -0`), HTTP probe?
5. How does graceful shutdown work?
6. How does `jevons status` compose sync health + web health into a report?

### T5: CLI Commands (`internal/cli/`)

**Scope**: Implement `total` and `graph` commands, wire all CLI stubs to real implementations.

**Output file**: `track-cli.md`

**Sub-questions**:
1. What awk logic does `cmd_total` use for time-range filtering and aggregation?
2. What's the ASCII graph rendering algorithm in `cmd_graph`?
3. How does `--range` filtering work (parsing `24h`, `7d`, etc. into epoch bounds)?
4. What JSON output format does `total` produce?
5. What metrics does `graph` support (billable, input, output, cache)?
6. How do the existing cobra command stubs need to be modified?

### T6: Testing & Fixtures

**Scope**: Comprehensive test suite — unit tests for parser, integration tests for sync, test fixtures from real session data.

**Output file**: `track-testing.md`

**Sub-questions**:
1. What edge cases need fixture data (hyphenated repos, missing cwd, empty sessions)?
2. How do we create realistic but anonymized test fixtures?
3. What's the table-driven test structure for parser functions?
4. How do we validate format compatibility between shell and Go output?
5. What integration test validates the full sync pipeline deterministically?
6. How do we test the HTTP server and daemon lifecycle?

## Section 6 — Mode-Specific Requirements

### Research Phase
Each track produces a findings file. After all tracks are substantive, produce a synthesis document that summarizes key findings, identifies connections between tracks, recommends a path forward, and lists remaining unknowns.

### Planning Phase
The plan must use **decreasing resolution**: high detail for the first milestone (exact files, structs, APIs, agent assignments), moderate detail for the next milestone (approach, key decisions, open questions), and directional only for everything further out (goals, unknowns).

Every milestone must produce a **working, runnable, validatable product** — not components that only work when combined. If a user can't run something after a milestone, it's not a milestone.

The plan must include: Summary, Architecture overview, First milestone in full detail (data models, interfaces, agent orchestration, testing strategy), and a Roadmap of subsequent milestones at decreasing resolution.

Agent team design: include dedicated adversarial/reviewer roles, define autonomous review workflows, ensure concurrent dev + test, and define testing methodology upfront.

Match engineering effort to the current phase — don't over-engineer prototypes. Add robustness iteratively.

### Implementation Phase
Build working, tested code. Each milestone must produce a runnable product.

Agent teams must include: implementers, test writers, and at least one critic/reviewer agent. Define testing methodology upfront (frameworks, how to mock, how agents self-validate).

Every agent must compile, vet/lint, and test after making changes. Failing validation blocks progress.

If implementation hits wrong assumptions, pause and run a focused research loop (using the same adaptive allocation) before continuing. Update the plan with what you learned.

After each iteration, update implementation-log.md with: what was built, tests pass/fail, what's left, any deviations from plan.

## Section 7 — Convergence Criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | `internal/parser/` can parse a real JSONL session file and extract TokenEvent structs with correct field values | FAIL |
| 2 | Parser generates identical dedup signatures as the shell script for the same input | FAIL |
| 3 | Parser correctly distinguishes human prompts from tool responses and extracts prompt previews for LiveEvent | FAIL |
| 4 | `internal/sync/` discovers all session files under the configured source directory | FAIL |
| 5 | `jevons sync` produces `events.tsv` with correct TSV format matching shell output (same columns, same sort order) | FAIL |
| 6 | `jevons sync` produces `live-events.tsv`, `projects.json`, and `sync-status.json` in expected formats | FAIL |
| 7 | Deduplication works correctly — re-running sync on the same data produces no duplicate rows | FAIL |
| 8 | Dashboard HTML/CSS/JS is extracted from shell script and embedded via `go:embed` in the binary | FAIL |
| 9 | `jevons web` starts an HTTP server that serves the dashboard and data files (TSV, JSON) | FAIL |
| 10 | `jevons web --interval N` runs a background sync loop with heartbeat file | FAIL |
| 11 | `jevons status` correctly reports sync and web server health using heartbeat and PID checks | FAIL |
| 12 | `jevons total --range 24h` outputs correct JSON aggregation of token usage | FAIL |
| 13 | `jevons graph --metric billable --range 24h` renders an ASCII graph | FAIL |
| 14 | Table-driven unit tests exist for parser (including edge cases: hyphenated repos, missing cwd, empty sessions) with testify | FAIL |
| 15 | Integration test validates sync pipeline produces deterministic output from fixture data | FAIL |
| 16 | `make build && make vet && make test` all pass cleanly | FAIL |

**Hard blockers (override convergence regardless of criteria scores):**
1. **OPEN challenges block convergence.** If `challenges.md` has ANY challenge with Status: OPEN, you CANNOT output the completion promise.
2. **Minimum iteration floor.** The completion promise CANNOT be output before iteration 4.
3. **Suspicious convergence.** If >50% of criteria flip from FAIL/PARTIAL to PASS in a single iteration, dispatch a critic agent to validate each flip before accepting them.

**CRITICAL: Stale convergence check.** Before evaluating criteria, re-read `challenges.md` and count OPEN challenges (including informal/unstructured entries). If the count is non-zero, ALL previous convergence is invalidated — regardless of what `convergence.md` currently says. The previous iteration's assessment is a log, not an authority. Always re-evaluate from scratch.

**Convergence evaluation:**
- All 16 PASS AND no OPEN challenges AND iteration ≥ 4 → output `<promise>SHIPPED</promise>`
- Any PARTIAL/FAIL → identify weakest areas, inform Phase 0 allocation for next iteration

## Section 8 — Rules

1. **Phase 0 is mandatory.** Never skip allocation. Never dispatch agents without updating track-health.md.
2. **Phase 1 is mandatory.** Never skip challenge resolution and the critic phase. Process challenges and dispatch critics BEFORE work agents.
3. **Challenges are hard blockers.** OPEN challenges in `challenges.md` prevent convergence. Address them with evidence, not acknowledgment.
4. **Critics are adversarial.** Critic agents exist to find weaknesses. A critic that says "everything looks good" has failed.
5. **Minimum iteration floor applies.** No completion promise before iteration 4.
6. **Don't repeat work.** Check output files before dispatching. Point agents at GAPS.
7. **Differentiate complete from stuck.** Rich output + no new findings = COMPLETE. Thin output + no new findings = STUCK.
8. **Update files, don't just think.** If it's not in a file, it doesn't count.
9. **Be honest in self-assessment.** Don't PASS criteria to escape the loop.
10. **Each iteration must make measurable progress.** If stuck, try a different approach.
11. **Working code over perfect code** — test as you go, every agent self-validates (compile, vet, lint, test).
12. **Embedded research when assumptions break** — pause and run a focused research loop before continuing. Update the plan.
13. **Larger teams with dedicated critics and reviewers** — implementers and test writers work in parallel, critics review before merging.
14. **Depth over breadth** in research phases — cite sources (shell script line numbers), distinguish fact from inference.
15. **Decreasing resolution** in planning — detail now, directional later. Every milestone must produce a runnable product.
16. **Proportional engineering** — don't over-engineer prototypes. Add robustness iteratively.
17. **Commit proactively** after each logical unit of work. Use conventional commit messages.
18. **Go conventions**: use `go vet`, `go fmt`, `go mod tidy` after changes. Table-driven tests with `testify`. Never use `git add .` or `git add -A`.
19. **Format compatibility is critical** — the Go binary must produce TSV/JSON files readable by the existing dashboard without changes.
