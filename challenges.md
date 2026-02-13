# Challenges

User or critic challenges to the current work. The loop MUST address each OPEN challenge before convergence is possible. Mark as ADDRESSED with a response when resolved.

Challenges can be added in ANY format — structured entries, bullet lists, freeform notes. The loop agent will normalize them into structured format during Phase 1.

---

## Challenge 1: GoReleaser missing ldflags configuration
**Status:** ADDRESSED
**Track:** T1 (CI & Build)

The `.goreleaser.yml` has no `ldflags` configuration to inject version info at build time. The `cmd/jevons/main.go` file declares `var version = "dev"` and `internal/cli/root.go` uses it, but without ldflags injection, all released binaries will report version as "dev" instead of the actual release tag.

**Resolution:** `.goreleaser.yml` lines 17-18 now include `ldflags: -s -w -X main.version={{.Version}}`. This injects the Git tag version at build time via GoReleaser. Local `go build` still shows "dev" (expected), but release artifacts will show the correct version. Verified: `cmd/jevons/main.go:5` declares `var version = "dev"` and `main.version` matches the ldflags path.

---

## Challenge 2: No GitHub Actions release workflow
**Status:** ADDRESSED
**Track:** T1 (CI & Build)

RELEASING.md step 6 states "GoReleaser builds and publishes artifacts automatically via CI", but there is NO `.github/workflows/` directory or release workflow file. The release process is documented but non-functional — tag pushes will not trigger builds.

**Resolution:** `.github/workflows/release.yml` exists and triggers on tag pushes matching `v*.*.*`. It: checks out code with full history (`fetch-depth: 0`), sets up Go from `go.mod`, runs `make test`, then runs GoReleaser v2 with `--clean`. Uses `GITHUB_TOKEN` with `contents: write` permission. See `.github/workflows/release.yml`.

---

## Challenge 3: No `release-dry-run` Makefile target
**Status:** ADDRESSED
**Track:** T1 (CI & Build) / T4 (Release Docs)

Convergence criterion #10 requires `make release-dry-run` to produce all artifacts locally without errors. This target does not exist in the Makefile. RELEASING.md also doesn't mention how to test the release process locally before pushing a tag.

**Resolution:** `Makefile` line 61-62 defines `release-dry-run: goreleaser release --snapshot --clean --skip=publish`. `RELEASING.md` step 2 now says "Run `make release-dry-run` and verify all artifacts build correctly." Note: requires GoReleaser to be installed locally; CI uses the goreleaser-action which handles installation.

---

## Challenge 4: CHANGELOG.md format inconsistency for v0.1.0
**Status:** ADDRESSED
**Track:** T4 (Release Docs)

The CHANGELOG.md has all entries under `[Unreleased]` section. For a v0.1.0 release, these entries should be moved to a `[0.1.0] - YYYY-MM-DD` section.

**Resolution:** `CHANGELOG.md` now has `## [Unreleased]` (empty) at top, followed by `## [0.1.0] - 2026-02-13` with all entries organized into "Added" (14 items covering Go port, architecture, tests, branding, policy docs) and "Shell Era" (5 legacy items). Comparison links at bottom: `[Unreleased]` compares v0.1.0..HEAD, `[0.1.0]` links to the release tag. Follows keep-a-changelog format.

---

## Challenge 5: RELEASING.md references version constant that won't be updated by GoReleaser
**Status:** ADDRESSED
**Track:** T4 (Release Docs)

RELEASING.md step 2 says "Update version constant in `cmd/jevons/main.go`", but this is WRONG once ldflags are configured.

**Resolution:** `RELEASING.md` no longer has a manual version update step. Step 2 is now "Run `make release-dry-run`". A "Version Injection" section explains: "The version is injected at build time via `ldflags` during the build process. The Makefile and GoReleaser configuration handle this automatically. There is no version constant to manually update."

---

## Challenge 6: Low test coverage in internal/cli (5.8%)
**Status:** ADDRESSED
**Track:** T3 (Release QA)

The `internal/cli` package has only 5.8% test coverage. This is the CLI command layer — a critical user-facing interface.

**Resolution:** Documented as acceptable for v0.1.0 in `track-release-qa.md`. Rationale: CLI package is a thin orchestration layer (cobra command bindings, flag parsing) that delegates to well-tested packages: `internal/sync` (80%+), `internal/parser` (75%+), `internal/store` (70%+), `internal/dashboard` (60%+). Smoke tests (`tests/smoke-test.sh`) validate all CLI commands end-to-end. The 11 smoke test checks cover: sync, status, doctor, total, graph, version, first-run, and web server lifecycle.

---

## Challenge 7: Zero test coverage in cmd/jevons and pkg/model
**Status:** ADDRESSED
**Track:** T3 (Release QA)

Two packages have 0% coverage: `cmd/jevons` (main entry point) and `pkg/model` (data structures).

**Resolution:** Documented in `track-release-qa.md`. `cmd/jevons` is a 5-line wrapper (`main.go`) that sets version and calls `cli.Execute()` — no logic to test. `pkg/model` contains only struct definitions (`TokenEvent`, `LiveEvent`, `Config`) and `DefaultConfig()` — no methods with logic beyond env var reads. Both are acceptable at 0% for v0.1.0.

---

## Challenge 8: Migration validation not automated
**Status:** ADDRESSED
**Track:** T3 (Release QA)

Convergence criterion #7 requires "Migration validation confirms Go binary reads shell-era data without errors." No automated test exists.

**Resolution:** `tests/migration-test.sh` exists with 6 validation steps: (1) shell script sync baseline, (2) Go binary reads shell-era data via `status`, (3) Go sync against same source, (4) TSV header comparison, (5) projects.json equivalence via `jq -S`, (6) live-events.tsv header comparison. `make test-migration` target added to Makefile. Script gracefully skips if prerequisites (shell script, jq) are missing.

---

## Challenge 9: Homebrew formula mentioned but doesn't exist
**Status:** ADDRESSED
**Track:** T2 (Distribution)

Convergence criterion #4 requires "Homebrew formula defined with test block that runs `jevons doctor`". No formula exists.

**Resolution:** `Formula/jevons.rb` exists with: platform-specific URLs for darwin/{arm64,amd64} and linux/{arm64,amd64}, SHA256 placeholders (will be filled by GoReleaser), `bin.install "jevons"` install block, and `test do` block that asserts `jevons --version` output contains "jevons". The GoReleaser `brews` section in `.goreleaser.yml` automatically generates and pushes the formula to `giannimassi/homebrew-jevons` on release. Note: the `Formula/jevons.rb` in this repo is a reference template; the actual formula is generated by GoReleaser.

---

## Challenge 10: Install script doesn't exist
**Status:** ADDRESSED
**Track:** T2 (Distribution)

Convergence criterion #5 requires "Install script downloads correct platform binary and validates checksum." No install script exists.

**Resolution:** `install.sh` exists with full functionality: POSIX-compatible (`#!/bin/sh`), detects OS via `uname -s` (Darwin/Linux), detects arch via `uname -m` (arm64/aarch64/x86_64), accepts optional version argument (`./install.sh v0.1.0`) or queries GitHub API for latest, downloads tarball + checksums.txt, validates SHA-256 checksum (supports both `shasum` on macOS and `sha256sum` on Linux), extracts to `./bin/jevons`, provides clear error messages for all failure modes.

---

## Challenge 11: Smoke test script doesn't exist
**Status:** ADDRESSED
**Track:** T3 (Release QA)

Convergence criterion #6 requires smoke tests against release artifacts. No smoke test exists.

**Resolution:** `tests/smoke-test.sh` exists with 8 test scenarios and 11 total checks, all passing: (1) sync — produces events.tsv and projects.json, (2) status — exit 0, (3) doctor — exit 0, (4) total --range 24h — exit 0, (5) graph --metric billable --range 24h — exit 0, (6) --version — exit 0, (7) first-run with empty source — handles gracefully, (8) web server — HTTP 200 response + clean stop. `make test-smoke` target runs against local build. Fixed bash arithmetic bug (post-increment under `set -e`).

---

## Challenge 12: go.mod uses non-standard Go version format
**Status:** ADDRESSED
**Track:** T1 (CI & Build)

The `go.mod` file declares `go 1.25.4`, but this was flagged as potentially non-standard.

**Resolution:** Go 1.25 was released Aug 2025, and 1.25.4 is a valid patch release (Feb 2026 timeframe). Since Go 1.21, patch versions in go.mod are standard (see `go help mod`). The CI workflow uses `go-version-file: go.mod` which correctly reads this version. All tests pass (`go test ./...`, `go vet ./...`). No change needed.

---

## Challenge 13: GoReleaser Homebrew tap automation not configured
**Status:** ADDRESSED
**Track:** T2 (Distribution)

GoReleaser can automatically update Homebrew formulas via the `brews` section, but it's missing.

**Resolution:** `.goreleaser.yml` lines 37-48 include the `brews` section: pushes formula to `giannimassi/homebrew-jevons` using `HOMEBREW_TAP_TOKEN`, includes test block that runs `jevons doctor`, homepage and description set. Formula is auto-generated on each release.

---

## Challenge 14: No CI test matrix for cross-platform validation
**Status:** ADDRESSED
**Track:** T1 (CI & Build)

`.goreleaser.yml` builds for 4 platforms but no CI matrix validates builds.

**Resolution:** `.github/workflows/ci.yml` runs on matrix: `[ubuntu-latest, macos-latest]`. Each runs `make vet` and `make test`. This validates Go code compiles and tests pass on both macOS (arm64) and Linux (amd64). Note: full cross-platform binary testing (all 4 OS/arch combos) would require additional runners; the current matrix covers the two primary platforms and catches platform-specific bugs in logic/paths.

---

## Challenge 15: Install script needs version pinning
**Status:** ADDRESSED
**Track:** T2 (Distribution)

Install script should accept optional version argument rather than always downloading latest.

**Resolution:** `install.sh` accepts optional version as first argument: `./install.sh v0.1.0`. If no version provided, queries GitHub API for latest release via `/repos/{owner}/{repo}/releases/latest`. See `install.sh` lines 114-121 (`main` function, version resolution logic).

---

## Challenge 16: Shell dependency warnings in doctor are misleading
**Status:** ADDRESSED
**Track:** T4 (Release Docs) / T1 (CI & Build)

`internal/cli/doctor.go` warns if `jq`, `python3`, or `curl` are missing, but the Go binary doesn't need them.

**Resolution:** `doctor.go` now: (1) uses `coreOK` variable instead of `allOK` — only source dir, data dir, and events.tsv affect pass/fail, (2) labels shell dependencies under "Optional (legacy shell script only):" header, (3) reports "All checks passed" even without jq/python3/curl. See `internal/cli/doctor.go` lines 59-67.

---

## Challenge 17: Artifact signing mentioned but undefined
**Status:** ADDRESSED
**Track:** T1 (CI & Build)

RELEASE_EXECUTION_PLAN.md Phase 2 mentions "signed artifacts" but no signing method defined.

**Resolution:** Descoped from v0.1.0. Signing is aspirational, not required for the initial release. v0.1.0 relies on SHA-256 checksums for integrity verification (generated by GoReleaser, validated by install script). Signing can be added in a future release via GoReleaser's `signs` section (supports cosign, GPG). The `checksums.txt` file published with each release provides sufficient integrity verification for a local development tool's first release.

---

## Challenge 18: v0.2 research scope boundaries undefined
**Status:** ADDRESSED
**Track:** T5 (Feature Research)

Risk of scope creep in v0.2 research.

**Resolution:** Research scope explicitly bounded in `track-feature-research.md`: surveys exactly 5 AI tools (Claude Code, Cursor, GitHub Copilot, Windsurf, Aider), cost tracking limited to pricing lookup + budget alerts (no invoicing), community features lowest priority, all features rated with effort estimates (S/M/L/XL). Research output includes feasibility ratings per tool and prioritized roadmap grouped into phases (v0.2-alpha through v0.3+).

---

## Challenge 19: v0.2 architecture deliverable format undefined
**Status:** ADDRESSED
**Track:** T6 (Feature Architecture)

Convergence criterion #12 requires "Provider abstraction interface designed" but no definition of "designed."

**Resolution:** `track-feature-arch.md` delivers all required artifacts: (1) Go `Provider` interface definition with 5 methods (Name, Discover, Parse, ParseLive, ExtractProjectPath) + `SessionFile` struct, (2) concrete Claude implementation stub with `init()` registration, (3) compiled-in registry pattern (`Register/Get/All/Names`), (4) event model changes (new `Provider` field in `TokenEvent`, TSV v2 format with field-count detection for backward compat), (5) dashboard change plan (provider filter, color coding, scope tree), (6) migration path (automatic via full-rebuild sync), (7) alternative design considered and rejected (separate data stores per provider — rejected due to dashboard complexity and consumer burden). Design decisions are explicit with reasoning.

---

## Challenge 20: GitHub token permissions for CI undocumented
**Status:** ADDRESSED
**Track:** T1 (CI & Build)

GH Actions release workflow needs specific token permissions.

**Resolution:** `.github/workflows/release.yml` declares `permissions: contents: write` at the workflow level, which grants the default `GITHUB_TOKEN` sufficient access to create releases and upload artifacts. For the Homebrew tap push, `.goreleaser.yml` references `{{ .Env.HOMEBREW_TAP_TOKEN }}` — this is a separate Personal Access Token (PAT) with `public_repo` scope that must be stored as a repository secret. Prerequisites documented in `track-distribution.md` under "Prerequisites for First Release" section: create PAT with `public_repo` scope, store as `HOMEBREW_TAP_TOKEN` in repo secrets.

---

## Challenge 21: Missing HOMEBREW_TAP_TOKEN in release workflow (Critic Iteration 2)
**Status:** ADDRESSED
**Track:** T1 (CI & Build)

Critic agent found that `.github/workflows/release.yml` only passed `GITHUB_TOKEN` but not `HOMEBREW_TAP_TOKEN`, which GoReleaser needs to push the formula to the tap repo.

**Resolution:** Added `HOMEBREW_TAP_TOKEN: ${{ secrets.HOMEBREW_TAP_TOKEN }}` to the GoReleaser action step's `env` block in `.github/workflows/release.yml`. Committed in `e6c4819`.

---

## Challenge 22: Homebrew formula test could fail in isolated environments (Critic Iteration 2)
**Status:** ADDRESSED
**Track:** T2 (Distribution)

Critic noted that `jevons doctor` checks for source dir and data dir which won't exist in Homebrew's isolated test environment. While `doctor` always returns exit 0, the output shows warnings which could confuse users.

**Resolution:** Changed GoReleaser `brews` test from `system "#{bin}/jevons", "doctor"` to `assert_match "jevons", shell_output("#{bin}/jevons --version")`. This is more reliable in isolated environments. `Formula/jevons.rb` already used `--version` test. Committed in `e6c4819`.

---

## Challenge 23: RELEASING.md missing prerequisites for first release (Critic Iteration 2)
**Status:** ADDRESSED
**Track:** T4 (Release Docs)

Critic found that the release checklist didn't mention verifying that `HOMEBREW_TAP_TOKEN` secret exists or that the `giannimassi/homebrew-jevons` repository is created.

**Resolution:** Added "Prerequisites (First Release Only)" section to RELEASING.md with 3 items: tap repo must exist, HOMEBREW_TAP_TOKEN secret configured, GoReleaser installed locally. Committed in `e6c4819`.

---

## Challenge 24: web-stop command documented but not implemented in Go CLI (Critic Iteration 3)
**Status:** ADDRESSED
**Track:** T4 (Release Docs) / T1 (CI & Build)
**Severity:** MEDIUM

The Go CLI (`jevons`) does NOT implement a `web-stop` command, but it is documented in multiple files as if it exists.

**Resolution:** The Go CLI's `web` command runs a foreground HTTP server that stops on Ctrl+C (SIGINT/SIGTERM via signal handling in `internal/cli/web.go`). This is intentionally different from the shell script's background daemon model. All documentation updated to remove `web-stop` references:
- `CLAUDE.md`: Changed to `web --port 8765  # start dashboard (Ctrl+C to stop)`
- `README.md`: Changed to `web --port 8765 --interval 15  # start dashboard + background sync (Ctrl+C to stop)`
- `CHANGELOG.md` line 18: Removed `web-stop` from Go CLI command list (kept in Shell Era section since that script does have it)
- `track-release-qa.md`: Changed web test description from `web-stop cleanly terminates` to `Process terminated via kill (Ctrl+C in interactive use)`

---

## Challenge 25: GoReleaser uses deprecated `brews` section (Critic Iteration 3)
**Status:** ADDRESSED
**Track:** T1 (CI & Build)
**Severity:** LOW

GoReleaser shows deprecation warning for `brews:` section.

**Resolution:** Known and accepted for v0.1.0. Migration to `homebrew_casks:` was attempted in iteration 2 but the new schema has different field names (`test`/`install` don't exist in `HomebrewCask` type). The `brews` section still works correctly in GoReleaser v2 — the warning is non-blocking and `make release-dry-run` succeeds. Will migrate when GoReleaser publishes the new schema docs. Not a v0.1.0 blocker.

---

## Challenge 26: CHANGELOG item count discrepancy (Critic Iteration 3)
**Status:** ADDRESSED
**Track:** T4 (Release Docs)
**Severity:** LOW

Critic noted CHANGELOG v0.1.0 has 14 items under "Added" and 5 items under "Shell Era" (19 total).

**Resolution:** The CHANGELOG header does not claim a specific count. Challenge 4's resolution text said "14 items covering Go port..." which correctly describes the "Added" section. The "Shell Era" section (5 items) documents the pre-Go legacy reference. Both sections are accurate. The CHANGELOG itself has no count claim to be inconsistent with. No change needed.

---

_Note: See `critic-2-findings.md` for additional lower-priority challenges from the initial review. All critical/high-priority findings have been normalized and addressed above._

---

## Challenge 27: Homebrew tap repository does not exist (Critic Iteration 4)
**Status:** ADDRESSED
**Track:** T2 (Distribution)
**Severity:** MEDIUM (documented prerequisite, not a code/config gap)

Critic verified that `giannimassi/homebrew-jevons` returns HTTP 404. GoReleaser will fail to push the formula if the repo doesn't exist at release time.

**Resolution:** This is explicitly documented in `RELEASING.md` "Prerequisites (First Release Only)" section, item 1: "Repository `giannimassi/homebrew-jevons` exists and is public." The tap repo creation is a manual infrastructure step the user performs before the first release — it's not automatable from this codebase. The code, config, docs, and tests are all correct and ready. The user must create the repo and configure the `HOMEBREW_TAP_TOKEN` secret as documented.

Additionally, RELEASING.md step 10 was clarified from "Update Homebrew tap formula (if applicable)" to "Verify Homebrew formula was updated automatically (check `giannimassi/homebrew-jevons` for new commit from GoReleaser)" — addressing the minor ambiguity noted by the critic.

---

## Critic Iteration 4 — Final Release Readiness Review
**Date:** 2026-02-13
**Verdict:** RELEASE-READY (pending documented infrastructure prerequisites)
**Reviewer focus:** Release-day simulation, first-user experience, failure modes

**Summary:** Walked through RELEASING.md step by step. All code, config, CI/CD, tests, and documentation are correct. The only prerequisite is infrastructure setup (create tap repo + configure secret), which is explicitly documented. All 26 prior challenges verified as genuinely ADDRESSED. Release pipeline validated: `make release-dry-run` produces 4 binaries, 4 archives, checksums, and Homebrew formula. Version injection works. First-time user experience is solid. No CRITICAL or HIGH issues found in code or docs.
