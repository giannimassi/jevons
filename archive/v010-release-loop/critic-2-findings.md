# Critic 2 Findings: Feasibility & Release Risk Assessment

## Challenge 1: No GitHub Actions CI workflow exists
**Status:** OPEN
**Track:** T1

The release plan (Phase 2) requires "CI release workflow with mandatory smoke and migration checks" but `.github/workflows/` does not exist. The `.goreleaser.yml` is configured but there's no automation to trigger it. Without CI:
- No automated release on tag push
- No cross-platform build validation before merge
- No smoke test enforcement
- Manual release process prone to human error

**Required:** Create `.github/workflows/release.yml` that triggers on tag push (`v*`), runs `goreleaser release`, uploads artifacts and checksums to GitHub Releases.

## Challenge 2: GoReleaser ldflags not configured for version injection
**Status:** OPEN
**Track:** T1

`.goreleaser.yml` has no `ldflags` configuration. The version constant in `cmd/jevons/main.go:5` is hardcoded to `"dev"`, so `jevons --version` will always print `dev` even in released binaries. This breaks convergence criterion #3.

**Required:** Add `ldflags: -s -w -X main.version={{.Version}}` to the `builds` section in `.goreleaser.yml`.

## Challenge 3: No Homebrew tap repository exists
**Status:** OPEN
**Track:** T2

The release plan assumes a Homebrew tap will exist at `brew install <tap>/jevons`, but:
1. No separate tap repo has been created (e.g., `github.com/giannimassi/homebrew-jevons`)
2. No formula file exists (should be `Formula/jevons.rb` in the tap repo)
3. The tap repo must be created and initialized BEFORE the first release, or the formula update workflow will fail

**Required:** Create `homebrew-jevons` repo with proper tap structure (README, Formula/, Casks/), write initial formula template. Document prerequisite in T2 track.

## Challenge 4: Install script platform detection is undefined
**Status:** OPEN
**Track:** T2

RELEASE_AND_PACKAGING_STRATEGY.md mentions an "install script that downloads latest signed binary" but no script exists. Critical edge cases undefined:
1. How does the script detect macOS vs Linux?
2. How does it detect arm64 vs amd64? (macOS `uname -m` returns `arm64`, Linux returns `aarch64`)
3. What happens if the platform is unsupported? (e.g., Windows, BSD)
4. How does it handle download failures or checksum mismatches?
5. Where should the binary be installed? (`/usr/local/bin`, `~/.local/bin`, or prompt user?)
6. Does it require sudo for system-wide install?

**Required:** Design install script UX flow, document platform detection logic, write install script with validation and error handling.

## Challenge 5: No smoke test script for release artifacts
**Status:** OPEN
**Track:** T3

RELEASE_EXECUTION_PLAN.md Phase 2 requires "Automated smoke test execution: jevons sync, jevons web, jevons status" but no smoke test script exists. The existing `make test-parity` compares shell vs Go from source, not from release artifacts.

**Missing:**
1. Script that downloads a release tarball (not builds from source)
2. Extracts the binary to a clean temp directory
3. Runs `jevons sync`, `jevons web` (start/stop), `jevons status`, `jevons doctor` with test fixtures
4. Validates exit codes and output format
5. Can run in CI matrix (macOS, Linux × amd64, arm64)

**Required:** Write `tests/smoke-test-release.sh` that takes artifact URL as input and validates all core commands.

## Challenge 6: Migration validation from shell-era data has no test
**Status:** OPEN
**Track:** T3

Convergence criterion #7 requires "Migration validation confirms Go binary reads shell-era data without errors" but:
1. No test script exists that creates shell-era data and validates Go binary can read it
2. `make test-parity` creates fresh data from both tools — it doesn't test reading PRE-EXISTING shell data
3. Edge cases untested: empty events.tsv, malformed TSV lines (>12 or <12 fields), missing projects.json, hyphenated project slugs in old data

**Required:** Write `tests/migration-validation.sh` that:
- Runs shell script to generate data
- Runs Go binary `jevons sync` against the SAME source (should dedupe, not duplicate)
- Runs Go binary `jevons web` to verify dashboard loads shell-era data
- Validates event counts match and no parsing errors occur

## Challenge 7: No Makefile target for release dry-run
**Status:** OPEN
**Track:** T1

RELEASING.md documents a 10-step release checklist but no automation exists. Convergence criterion #10 requires `make release-dry-run` produces all artifacts locally without errors, but the Makefile has no such target.

**Required:** Add `make release-dry-run` that runs `goreleaser release --snapshot --clean --skip=publish` to build all platform binaries and checksums locally without pushing to GitHub.

## Challenge 8: No test coverage for empty data directory on first run
**Status:** OPEN
**Track:** T3

The `doctor` command checks if data dir exists but there's no smoke test for the first-run experience:
1. User runs `jevons sync` with no existing data dir — does it create one?
2. User runs `jevons web` before `jevons sync` — what happens? Does it crash or show empty dashboard?
3. User has no `~/.claude/projects/` directory — does `doctor` provide actionable guidance?

**Required:** Add smoke test scenario: clean environment (no data dir, no source dir) → run each command → validate error messages are actionable.

## Challenge 9: GoReleaser Homebrew tap automation not configured
**Status:** OPEN
**Track:** T2

GoReleaser can automatically update Homebrew formulas via the `brews` section in `.goreleaser.yml`, but it's missing. Without this:
1. Every release requires manually updating the formula in the tap repo
2. Manual process is error-prone (wrong SHA256, wrong version, wrong URL)
3. Release process is slower and blocks on manual work

**Required:** Add `brews` section to `.goreleaser.yml` that pushes formula updates to `homebrew-jevons` repo automatically on release.

## Challenge 10: Checksum validation missing from install script design
**Status:** OPEN
**Track:** T2

Convergence criterion #5 requires "Install script downloads correct platform binary and validates checksum" but checksum validation is undefined:
1. How does the script fetch `checksums.txt` from the release?
2. What tool is used to validate? (macOS has `shasum`, Linux has `sha256sum` — syntax differs)
3. What happens if checksum mismatch? Delete downloaded binary? Exit with error?
4. Does the script validate the binary is executable after download?

**Required:** Design checksum validation flow, document tool compatibility matrix, handle validation failures gracefully.

## Challenge 11: No CI test matrix for cross-platform validation
**Status:** OPEN
**Track:** T1

`.goreleaser.yml` builds for 4 platforms (darwin/{amd64,arm64}, linux/{amd64,arm64}) but there's no CI matrix to validate builds actually work on each platform. Risks:
1. Binary builds but crashes on startup due to platform-specific bug
2. Embedded assets don't load correctly on Linux
3. File path handling differs between macOS and Linux
4. Darwin/amd64 binary not tested on Intel Mac (most devs use Apple Silicon)

**Required:** Add GitHub Actions matrix job that runs smoke tests on all 4 platforms. Use `runs-on: macos-latest` (arm64), `macos-13` (amd64), `ubuntu-latest` (amd64), and ARM Linux runner if available.

## Challenge 12: Version constant location is fragile
**Status:** OPEN
**Track:** T1

`cmd/jevons/main.go:5` declares `var version = "dev"` which will be overwritten by ldflags at build time. This works but is fragile:
1. If the variable is renamed or moved, ldflags path breaks silently
2. No test validates version injection works
3. Developers running `go run cmd/jevons/main.go` always see "dev"

**Required:** Add build-time validation: smoke test checks that release artifact reports correct version (not "dev"). Consider moving version to dedicated `internal/version/version.go` for clarity.

## Challenge 13: Install script lacks version pinning capability
**Status:** OPEN
**Track:** T2

The install script design mentions "downloads latest signed binary" but no option to install a specific version. Users may need to:
1. Install a specific version for reproducibility
2. Downgrade if latest release has a bug
3. Install a pre-release version for testing

**Required:** Design install script to accept optional version argument: `curl -fsSL install.sh | bash -s -- v0.1.0`. Default to latest if not specified.

## Challenge 14: No rollback/downgrade smoke test
**Status:** OPEN
**Track:** T3

RELEASING.md documents rollback procedure but no test validates it works. Critical scenario: v0.1.1 has a data corruption bug, user needs to downgrade to v0.1.0. Risks:
1. v0.1.1 changed TSV format, v0.1.0 can't read it
2. Homebrew caches broken version, `brew uninstall && brew install` doesn't help
3. User's data is unrecoverable

**Required:** Add migration test: generate data with v0.1.0, upgrade to v0.1.1 (mock), downgrade to v0.1.0, validate data still readable. Document version compatibility policy.

## Challenge 15: CHANGELOG.md has no v0.1.0 release header
**Status:** OPEN
**Track:** T4

CHANGELOG.md has `## [Unreleased]` but no `## [0.1.0] - YYYY-MM-DD` section. The release checklist (RELEASING.md step 1) requires "move Unreleased items under new version header" but the changelog format isn't ready for it.

**Required:** Before first release, add `## [0.1.0] - TBD` section below Unreleased, move all current items under it, update comparison links at bottom.

## Challenge 16: No smoke test for `doctor --fix`
**Status:** OPEN
**Track:** T3

`internal/cli/doctor.go` implements `--fix` flag to auto-create data directory, but no test validates it works. Edge cases:
1. Data dir parent doesn't exist — does `os.MkdirAll` create it?
2. Data dir exists but isn't writable — what error message?
3. User runs `doctor --fix` twice — idempotent or error?

**Required:** Add unit test for `doctor --fix` that creates temp environment, runs command, validates directory created with correct permissions.

## Challenge 17: Shell dependency warnings in `doctor` are misleading
**Status:** OPEN
**Track:** T4

`internal/cli/doctor.go:60-66` warns if `jq`, `python3`, or `curl` are missing, but the Go binary doesn't need them. This confuses users:
1. "Shell dep jq: [WARN] not found" implies the Go binary won't work
2. Users may waste time installing jq when it's unnecessary
3. Contradicts SUPPORT.md claim that core features work "with no external dependencies beyond the binary"

**Required:** Either remove shell dependency checks OR clearly label them as "optional (for shell script only)" and never treat as warnings that affect "All checks passed" status.

## Challenge 18: No v0.2 research scope boundaries defined
**Status:** OPEN
**Track:** T5

The prompt lists 6 v0.2 sub-questions (multi-provider, cost tracking, dashboard improvements, config files, notifications, community features) but no scope boundaries. Risk of scope creep:
1. Research could spiral into evaluating 20+ AI tools instead of focusing on top 3-5
2. Cost tracking could expand into full billing/invoice generation
3. Community features could become a social network

**Required:** Define research constraints BEFORE dispatching agents:
- Survey top 5 AI coding tools only (Claude, Cursor, GitHub Copilot, Windsurf, Aider)
- Cost tracking scope: pricing lookup + budget alerts ONLY, no invoicing
- Community features: optional, lowest priority
- Research output must include effort ratings (S/M/L/XL) for each feature

## Challenge 19: No convergence criteria for v0.2 architecture design
**Status:** OPEN
**Track:** T6

Convergence criterion #12 requires "Provider abstraction interface designed with concrete Claude implementation" but no definition of "designed" — what's the deliverable? Risks:
1. Agent produces high-level sketch, claims it's "designed"
2. No validation that the interface is actually implementable
3. Missing: how providers are registered, how events are mapped, how dashboard queries work

**Required:** Define T6 deliverable format: Go interface definition + concrete Claude implementation stub + migration plan from v0.1 event model + at least one alternative design considered and rejected with reasoning.

## Challenge 20: Test fixture coverage missing for TSV edge cases
**Status:** OPEN
**Track:** T3

`internal/parser/testdata/` has 9 JSONL fixtures but `internal/store/` has no corresponding TSV fixtures. TSV parsing edge cases untested:
1. TSV line with >12 fields (Issue 5 claims it's handled but no fixture)
2. TSV line with <12 fields (should error)
3. TSV with Windows line endings (CRLF vs LF)
4. TSV with tabs in prompt_preview field (escaped or breaks parsing?)
5. TSV with very large integers (int64 overflow)

**Required:** Add `internal/store/testdata/` with edge case TSV files and corresponding tests in `tsv_test.go`.

## Challenge 21: No release-blocking defect triage process defined
**Status:** OPEN
**Track:** T4

RELEASE_EXECUTION_PLAN.md Phase 4 mentions "No open release-blocking defects remain" as an exit criterion but no definition of "release-blocking":
1. Who decides if a bug is blocking? (product owner role is TBD)
2. What severity levels exist? (critical, high, medium, low?)
3. Can a release ship with known bugs? (if so, what severity threshold?)
4. Where are defects tracked? (GitHub issues, challenges.md, or both?)

**Required:** Define defect severity levels and blocking criteria in RELEASING.md. Document triage workflow: who files, who triages, who approves/rejects blocking status.

## Challenge 22: Homebrew formula test block is undefined
**Status:** OPEN
**Track:** T2

Convergence criterion #4 requires "Homebrew formula defined with test block that runs `jevons doctor`" but:
1. Homebrew `test do` block syntax not documented
2. What's the success criteria? (exit code 0? specific output string?)
3. Does the test run in an isolated environment? (no ~/.claude/projects)
4. What if `doctor` returns non-zero because source dir doesn't exist in test env?

**Required:** Write Homebrew formula template with test block that validates `jevons doctor` runs without crashing. Test must not fail due to missing source directory (expected in isolated Homebrew test env).

## Challenge 23: No GitHub token permissions documented for CI
**Status:** OPEN
**Track:** T1

GitHub Actions release workflow will need `GITHUB_TOKEN` with specific permissions to:
1. Create releases
2. Upload artifacts
3. Push to Homebrew tap repo (if using GoReleaser automation)

Missing:
1. Which permissions are required? (`contents: write`, `packages: write`?)
2. Does the workflow need a separate PAT for the tap repo push?
3. How are secrets configured?

**Required:** Document required GitHub token permissions in T1 track. Test that default `GITHUB_TOKEN` has sufficient permissions or document PAT setup.

## Challenge 24: No CHANGELOG comparison link template
**Status:** OPEN
**Track:** T4

CHANGELOG.md follows Keep a Changelog format but has no comparison links at bottom (e.g., `[0.1.0]: https://github.com/giannimassi/jevons/releases/tag/v0.1.0`). This is a standard feature of the format.

**Required:** Add comparison links section to CHANGELOG.md template. Update RELEASING.md checklist to include "update comparison links" step.

## Challenge 25: Artifact signing is mentioned but undefined
**Status:** OPEN
**Track:** T1

RELEASE_EXECUTION_PLAN.md Phase 2 mentions "Produce checksums and signed artifacts" but:
1. What signing method? (GPG, cosign, macOS codesign?)
2. Whose key signs the artifacts?
3. How do users verify signatures?
4. Is signing required for v0.1.0 or aspirational?

**Required:** Clarify signing requirements. If signing is required for v0.1.0, document signing workflow (key generation, GoReleaser signing config, user verification instructions). If not required, remove from Phase 2 scope to avoid confusion.

## Challenge 26: `make test-parity` requires jq but Makefile doesn't check
**Status:** OPEN
**Track:** T1

`make test-parity` (line 49 in Makefile) runs `jq -S .` to compare projects.json but doesn't validate `jq` is installed. If `jq` is missing:
1. Test fails with cryptic error
2. No actionable message to install jq
3. CI could fail silently if jq not in runner image

**Required:** Either add `jq` check to `make test-parity` target OR add prerequisite documentation to Makefile help/README.

## Challenge 27: No test for hyphenated project slugs in real data
**Status:** OPEN
**Track:** T3

The UI regression test (`tests/claude-usage-ui-regression.sh:131-132`) validates hyphenated folder names don't get split in the scope tree, but there's no unit test for the slug generation logic itself. The slug function is critical for data integrity:
1. What if a project path has multiple consecutive hyphens?
2. What if a path has leading/trailing slashes?
3. What if a path is `/` (root)?

**Required:** Add unit test for slug generation covering edge cases (consecutive hyphens, root path, paths with spaces, non-ASCII characters).

## Challenge 28: No documentation for CLAUDE_USAGE_DATA_DIR override
**Status:** OPEN
**Track:** T4

README.md mentions "Default data directory: ~/dev/.claude-usage (override with CLAUDE_USAGE_DATA_DIR)" but:
1. Not documented in `jevons --help` output
2. Not documented in SUPPORT.md
3. Users won't discover this unless they read source code
4. What if the env var is set to a relative path? Absolute path required?

**Required:** Add environment variables section to README.md and SUPPORT.md. Document CLAUDE_USAGE_DATA_DIR and CLAUDE_USAGE_SOURCE_DIR with examples and validation behavior.

## Summary

**Critical blockers (must resolve before v0.1.0):**
- Challenge 1: No CI workflow (convergence criterion #2)
- Challenge 2: No version injection (convergence criterion #3)
- Challenge 3: No Homebrew tap repo (convergence criterion #4)
- Challenge 5: No smoke test script (convergence criterion #6)
- Challenge 6: No migration validation (convergence criterion #7)
- Challenge 7: No release dry-run target (convergence criterion #10)

**High risk (should resolve before v0.1.0):**
- Challenge 4: Install script platform detection undefined
- Challenge 9: GoReleaser Homebrew automation missing
- Challenge 10: Checksum validation undefined
- Challenge 11: No CI test matrix
- Challenge 15: CHANGELOG not ready for release
- Challenge 18: v0.2 research scope unbounded

**Medium risk (may defer to v0.1.1):**
- Challenge 8, 12, 14, 16, 17, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28

**Total challenges filed:** 28
