# Track T4: Release Documentation

## Completion Summary

All release documentation has been updated for v0.1.0 and is ready for publication.

## Updated Files

### CHANGELOG.md
- Moved all v0.1.0 entries from `[Unreleased]` to `## [0.1.0] - 2026-02-13`
- Kept `## [Unreleased]` at the top (empty, for future changes)
- Added comparison links for version tracking:
  - `[Unreleased]` → HEAD from v0.1.0
  - `[0.1.0]` → release tag

**Format:** Follows keep-a-changelog standard with three subsections:
- Added (31 items covering Go port, architecture, tests, branding, policy docs)
- Shell Era (5 legacy items for historical context)

### RELEASING.md
- **Removed:** Manual version constant update step (version injected via ldflags)
- **Added:** Step 2 — `make release-dry-run` validation before tagging
- **Added:** "Version Injection" section explaining build-time version handling
- **Clarified:** 10-step checklist with rollback procedure and smoke test targets

**Coverage:**
- SemVer policy with v0.x flexibility and breaking change allowances
- Automated CI release flow via GoReleaser
- Rollback procedure (yank + patch)
- Build targets (darwin/linux × amd64/arm64)

### SUPPORT.md
- No changes required — already covers:
  - Core features (fully supported without external deps)
  - Optional features (future AI adapters, MCP)
  - Compatibility (v0.x data format backward-compat, platform matrix, Go version tracking)
  - Issue reporting template

### doctor.go
- **Changed:** Shell dependency checks from "blocking" to "informational"
- **Updated:** Variable from `allOK` → `coreOK` (only source/data dirs and events.tsv block pass/fail)
- **Labeled:** Shell dependencies as "(legacy shell script only)" with separate output section
- **Effect:** Users see "All checks passed" even without jq/python3/curl

## Remaining Work

### Release Notes Template (Not in Scope)
Once the release is cut, populate GitHub Releases with:
- Release title: `v0.1.0`
- Body: Auto-generated from CHANGELOG [0.1.0] section + context about Go port completion
- Assets: Auto-uploaded by GoReleaser (darwin-amd64, darwin-arm64, linux-amd64, linux-arm64, checksums)

Example structure:
```markdown
## Go CLI Parity MVP

Jevons v0.1.0 marks the completion of the Go port, replacing the legacy shell script. This release delivers:

- Full feature parity with shell implementation
- 104 comprehensive tests with 100% compatibility validation
- Production-ready binary for macOS (Intel/Apple Silicon) and Linux (amd64/arm64)

### What's New
[Auto-populated from CHANGELOG]

### Migration Notes
- Shell script (`claude-usage-tracker.sh`) remains in repo as reference
- Recommended: Replace shell calls with `jevons` binary
- All data formats are backward-compatible
```

## Validation Checklist

- [x] CHANGELOG.md has `[Unreleased]` at top (empty)
- [x] CHANGELOG.md has `## [0.1.0] - 2026-02-13` with all v0.1.0 items
- [x] Comparison links added to CHANGELOG
- [x] RELEASING.md removes manual version constant step
- [x] RELEASING.md adds `make release-dry-run` step
- [x] RELEASING.md explains version injection via ldflags
- [x] doctor.go only blocks on core checks (source/data dirs, events.tsv)
- [x] doctor.go labels shell dependencies as optional/legacy
- [x] SUPPORT.md unchanged (already complete)

## Next Steps

1. Commit these changes: `docs: update release documentation for v0.1.0`
2. Create release via CLI or GitHub UI (v0.1.0, 2026-02-13)
3. Verify GoReleaser artifacts are published
4. Populate GitHub Releases body with v0.1.0 context and CHANGELOG entries
