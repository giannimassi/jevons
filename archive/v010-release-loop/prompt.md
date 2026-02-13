# Jevons v0.1.0 Release & v0.2 Roadmap — Adaptive Loop Prompt

## Section 1 — Task Description

Ship `jevons` v0.1.0 as a distributable product and design the v0.2+ feature roadmap. The Go Parity MVP is complete (2,740 lines, 104 subtests, format-compatible with the shell reference). The remaining release work includes: GoReleaser cross-platform builds, GitHub Actions CI, Homebrew tap, install script, smoke tests, migration validation, and release documentation. In parallel, research and design v0.2+ features including multi-provider support, cost tracking, dashboard improvements, and extensibility architecture.

**Reference documents**:
- `docs/RELEASE_EXECUTION_PLAN.md` — Phase 2-4 release plan
- `docs/RELEASE_AND_PACKAGING_STRATEGY.md` — distribution strategy
- `docs/GO_PORT_PLAN.md` — completed Go port context

## Section 2 — Task Objective

The `jevons` binary must be packaged for cross-platform distribution with automated CI, installable via Homebrew and install script, validated by smoke tests and migration checks, documented for release — AND the v0.2 feature roadmap must be designed with a provider abstraction and at least one implementation-ready feature spec.

## Section 3 — Context Loading

Every iteration, read these files FIRST (in order):

1. `challenges.md` — **CRITICAL: OPEN challenges block convergence**
2. `convergence.md` — current assessment of all criteria
3. `track-health.md` — track statuses and agent allocation history
4. Track output files: `track-ci-build.md`, `track-distribution.md`, `track-release-qa.md`, `track-release-docs.md`, `track-feature-research.md`, `track-feature-arch.md`
5. Key reference files:
   - `docs/RELEASE_EXECUTION_PLAN.md` (phase 2-4 plan)
   - `docs/RELEASE_AND_PACKAGING_STRATEGY.md` (distribution strategy)
   - `CLAUDE.md` (project instructions)
   - `Makefile` (existing build targets)
   - `.goreleaser.yml` (if it exists)
   - `.github/workflows/` (if they exist)

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

### T1: CI & Build Pipeline (`GoReleaser`, `.github/workflows/`)

**Scope**: Configure GoReleaser for cross-platform builds, set up GitHub Actions release workflow, inject version info via ldflags, produce checksums.

**Output file**: `track-ci-build.md`

**Sub-questions**:
1. What GoReleaser config is needed for darwin/linux × amd64/arm64?
2. How should the GitHub Actions workflow trigger (tag push, manual dispatch, or both)?
3. How do we handle checksums and artifact signing?
4. What ldflags should inject version info so `jevons --version` works?
5. How do we validate builds compile and run on each target platform?

### T2: Distribution Channels (Homebrew, install script)

**Scope**: Set up Homebrew tap repo and formula, create install script for non-Homebrew users, validate clean-machine installation.

**Output file**: `track-distribution.md`

**Sub-questions**:
1. How do we set up a Homebrew tap repo and formula?
2. What does the formula need (binary download URL pattern, checksums, test block)?
3. What should the install script look like (curl | bash, platform detection)?
4. How do we handle version detection in the install script?
5. How do we validate clean-machine installation?

### T3: Release QA & Smoke Tests

**Scope**: Automated smoke tests against release artifacts, migration validation from shell-era data, scenario matrix for install paths.

**Output file**: `track-release-qa.md`

**Sub-questions**:
1. What smoke tests should run against release artifacts (`sync`, `web`, `status`, `doctor`)?
2. How do we validate migration from shell-era data files?
3. What's the scenario matrix (fresh install, upgrade, data migration)?
4. How do we automate these in CI (matrix strategy, test containers)?
5. What manual QA steps are needed before v0.1.0?

### T4: Release Documentation

**Scope**: Write RELEASING.md, SUPPORT.md, CHANGELOG.md, v0.1.0 release notes template.

**Output file**: `track-release-docs.md`

**Sub-questions**:
1. What should RELEASING.md cover (versioning policy, cut process, rollback)?
2. What's the support policy for v0.x (core features vs optional adapters)?
3. What changelog format should we use (keep-a-changelog)?
4. What should v0.1.0 release notes contain?
5. How do we template release notes for future versions?

### T5: Feature Research (v0.2+)

**Scope**: Survey and assess v0.2+ feature candidates — multi-provider support, cost tracking, dashboard improvements, config files, notifications, community features.

**Output file**: `track-feature-research.md`

**Sub-questions**:
1. What other AI tools write parseable session logs? (Cursor, Copilot, Windsurf, Aider, etc.)
2. What would cost/pricing integration look like for different providers?
3. What dashboard improvements would be most valuable? (better charts, filtering, data export)
4. Should we add a config file? What format (TOML, YAML) and what settings?
5. What notifications/alerts might be useful? (budget alerts, usage anomalies)
6. What community/adoption features could help? (sharing, benchmarking, team dashboards)

### T6: Feature Architecture (v0.2+)

**Scope**: Design extension points for v0.2+ features — provider abstraction interface, event model changes, dashboard extensibility, migration path from v0.1 to v0.2.

**Output file**: `track-feature-arch.md`

**Sub-questions**:
1. What's the provider interface contract (log discovery, parsing, event mapping)?
2. How do we register providers (compiled-in vs runtime plugin)?
3. What changes to the event model (`pkg/model/event.go`) are needed for multi-provider?
4. How does the dashboard need to change for multi-provider data?
5. What's the migration path from v0.1 to v0.2 data format?

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
| 1 | `.goreleaser.yml` produces binaries for darwin/{amd64,arm64} and linux/{amd64,arm64} | FAIL |
| 2 | GitHub Actions release workflow triggers on tag push and produces release artifacts with checksums | FAIL |
| 3 | Version info injected at build time via ldflags — `jevons --version` prints correct version | FAIL |
| 4 | Homebrew formula defined with test block that runs `jevons doctor` | FAIL |
| 5 | Install script downloads correct platform binary and validates checksum | FAIL |
| 6 | Smoke tests pass on release artifacts: `sync`, `web` (start+stop), `status`, `doctor` | FAIL |
| 7 | Migration validation confirms Go binary reads shell-era data without errors | FAIL |
| 8 | `RELEASING.md` documents versioning policy, cut process, and rollback procedure | FAIL |
| 9 | `CHANGELOG.md` exists with v0.1.0 entries following keep-a-changelog format | FAIL |
| 10 | `make release-dry-run` produces all artifacts locally without errors | FAIL |
| 11 | Feature research covers ≥5 v0.2 candidates with feasibility and effort ratings | FAIL |
| 12 | Provider abstraction interface designed with concrete Claude implementation | FAIL |
| 13 | v0.2 feature roadmap prioritized with complexity estimates | FAIL |
| 14 | At least one v0.2 feature has an implementation-ready design doc | FAIL |

**Hard blockers (override convergence regardless of criteria scores):**
1. **OPEN challenges block convergence.** If `challenges.md` has ANY challenge with Status: OPEN, you CANNOT output the completion promise.
2. **Minimum iteration floor.** The completion promise CANNOT be output before iteration 4.
3. **Suspicious convergence.** If >50% of criteria flip from FAIL/PARTIAL to PASS in a single iteration, dispatch a critic agent to validate each flip before accepting them.

**CRITICAL: Stale convergence check.** Before evaluating criteria, re-read `challenges.md` and count OPEN challenges (including informal/unstructured entries). If the count is non-zero, ALL previous convergence is invalidated — regardless of what `convergence.md` currently says. The previous iteration's assessment is a log, not an authority. Always re-evaluate from scratch.

**Convergence evaluation:**
- All 14 PASS AND no OPEN challenges AND iteration ≥ 4 → output `<promise>SHIPPED</promise>`
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
14. **Depth over breadth** in research phases — cite sources, distinguish fact from inference.
15. **Decreasing resolution** in planning — detail now, directional later. Every milestone must produce a runnable product.
16. **Proportional engineering** — don't over-engineer prototypes. Add robustness iteratively.
17. **Commit proactively** after each logical unit of work. Use conventional commit messages.
18. **Go conventions**: use `go vet`, `go fmt`, `go mod tidy` after changes. Table-driven tests with `testify`. Never use `git add .` or `git add -A`.
19. **Format compatibility is critical** — v0.1.0 must preserve the existing TSV/JSON data schema. No breaking changes without documented migration.
20. **Release gates are non-negotiable** — all 6 gates from RELEASE_EXECUTION_PLAN.md must pass before tagging v0.1.0.
