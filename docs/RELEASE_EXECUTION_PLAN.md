# Release Execution Plan

## Objective

Execute packaging and release work from the current shell implementation toward a distributable `jevons` product, culminating in `v0.1.0`.

## Timeframe and Assumptions

- Start date: 2026-02-11
- Target initial public release: week of 2026-03-09
- Current repo has no release automation, no Homebrew tap config, and no Git remote configured.
- Ownership below uses placeholders where assignment is not yet confirmed.

## Roles and Owners

- Product owner: `TBD`
- Runtime/CLI owner (Go port): `TBD`
- Release engineering owner (CI, artifacts, checksums, signing): `TBD`
- QA owner (scenario matrix + smoke + migration validation): `TBD`
- Distribution owner (Homebrew tap + install docs): `TBD`

## Phase Plan

### Phase 0: Repo and Release Foundations (2026-02-11 to 2026-02-14)

Owner: Product owner + Release engineering owner

Scope:
- Finalize canonical GitHub repository and configure `origin`.
- Establish release policy docs and basic project metadata.
- Define `v0.x` compatibility and support boundaries.

Deliverables:
- `RELEASING.md` with versioning, cut process, rollback notes.
- `SUPPORT.md` (or equivalent) with core vs optional adapter support policy.
- Issue and milestone structure for `v0.1.0`.

Exit criteria:
- Repository is ready for automated release wiring.
- Release responsibilities and approval path are explicit.

### Phase 1: Go Parity MVP (2026-02-15 to 2026-02-22) — COMPLETE

Owner: Runtime/CLI owner

**Completed 2026-02-13** (ahead of schedule).

Scope:
- Implement Go CLI parity for core commands: `sync`, `web`, `status`.
- Preserve current data schema compatibility:
  - `events.tsv`
  - `live-events.tsv`
  - `projects.json`
  - `sync-status.json`
- Reuse existing dashboard assets first, then embed assets in binary.
- Add `doctor` and `doctor --fix` baseline checks.

Deliverables:
- Buildable Go CLI (`jevons`) with parity for core workflows.
- All 6 commands implemented: `sync`, `web`, `status`, `total`, `graph`, `doctor`.
- 2,740 lines of Go across 22 files.
- 24 top-level tests / 104 subtests, all passing.
- 28 critic challenges filed and resolved across 4 iterations.
- `make test-parity` validates format compatibility with shell reference.

Exit criteria:
- ~~Core CLI workflows operate end-to-end in Go.~~ **MET**
- ~~Existing shell-generated data can be read and used without migration breakage.~~ **MET**

### Phase 2: Packaging and Artifact Pipeline (2026-02-23 to 2026-03-01)

Owner: Release engineering owner

Scope:
- Implement automated cross-platform builds.
- Produce checksums and signed artifacts.
- Add CI release workflow with mandatory smoke and migration checks.

Deliverables:
- Release artifacts for:
  - `darwin/amd64`
  - `darwin/arm64`
  - `linux/amd64`
  - `linux/arm64`
- Checksums file published with every release.
- Automated smoke test execution:
  - `jevons sync`
  - `jevons web`
  - `jevons status`
- Migration validation from prior data files.

Exit criteria:
- One command can produce and publish reproducible release artifacts.
- CI fails hard on smoke/migration regressions.

### Phase 3: Distribution and Release Candidate (2026-03-02 to 2026-03-08)

Owner: Distribution owner + QA owner

Scope:
- Stand up Homebrew tap + formula workflow.
- Add install-script path for non-Homebrew users.
- Execute clean-machine install validation.

Deliverables:
- Homebrew install path: `brew install <tap>/jevons`
- Documented install script path for macOS/Linux.
- RC notes with known limitations and support matrix.

Exit criteria:
- Install and first-run experience succeeds on fresh environments.
- `doctor` provides actionable diagnostics for setup issues.

### Phase 4: `v0.1.0` Cut and Post-Release Stabilization (week of 2026-03-09)

Owner: Product owner + Release engineering owner

Scope:
- Cut tagged release and publish notes.
- Monitor install failures and high-severity regressions.
- Prepare `v0.1.1` patch window if needed.

Deliverables:
- Published `v0.1.0` release notes.
- Triage log for first-week issues.
- Patch plan with severity-based SLA.

Exit criteria:
- No open release-blocking defects remain.
- Distribution channels are functioning and monitored.

## Release Gates (`v0.1.0`)

All gates must pass before tagging:

1. Packaging gate
- Cross-platform artifacts exist for all target OS/arch pairs.
- Checksums published and verifiable.

2. Install gate
- Homebrew install works on clean macOS test environments.
- Install script works on clean macOS and Linux test environments.

3. Runtime gate
- `sync`, `web`, and `status` smoke tests pass on release artifacts.
- Dashboard launches and serves expected UI routes.

4. Compatibility gate
- Existing shell-era data files are read correctly by Go binary.
- No schema-breaking changes without documented migration.

5. Diagnostics gate
- `doctor` reports core prerequisites accurately.
- Optional adapters are reported as optional and never block core use.

6. Quality gate
- Unit tests pass for parser and dedupe edge cases.
- Integration and scenario-matrix checks pass, including adversarial and empty-data cases.

## Milestones and Checkpoints

- 2026-02-14: Phase 0 review and owner lock.
- 2026-02-22: Go parity MVP demo (`sync`/`web`/`status` + `doctor` baseline).
- 2026-03-01: Release pipeline dry run with signed artifacts and checksums.
- 2026-03-08: RC sign-off for distribution channels.
- 2026-03-09: `v0.1.0` release decision.

## Risks and Mitigations

- Risk: Go parity slips due to edge-case parser behavior.
  - Mitigation: lock regression fixtures early and require deterministic sync snapshots.
- Risk: Homebrew and install-script paths diverge in behavior.
  - Mitigation: one shared smoke script run against both install methods.
- Risk: Optional adapters introduce hidden hard dependencies.
  - Mitigation: enforce non-blocking adapter checks via `doctor` and startup health output.
