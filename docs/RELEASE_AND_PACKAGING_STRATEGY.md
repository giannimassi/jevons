# Release and Packaging Strategy

## Objective

Ship `claude-usage` as a tool other developers can install quickly and run without setup friction.

## Packaging Principles

1. Prefer one command and one binary UX.
2. Keep optional integrations optional.
3. Auto-detect and auto-fix environment issues where safe.
4. Fail with actionable diagnostics, never silent breakage.

## Distribution Channels

### Primary

- Homebrew tap (macOS): `brew install <tap>/claude-usage`

### Secondary

- GitHub Releases tarballs (`darwin`, `linux`, `amd64`, `arm64`)
- Install script that downloads latest signed binary

## Install UX

### Command

- `claude-usage doctor`
- `claude-usage doctor --fix`

### Doctor responsibilities

- Verify access to `~/.claude/projects`
- Verify writable data dir (`~/.claude-usage`)
- Verify browser-launch capability for dashboard auto-open
- Verify optional adapters (MCP/scanners) and mark as optional

## External Tool Strategy (MCP / scanner)

1. Classify as optional providers/adapters.
2. Detect on startup and show availability in UI/CLI.
3. Provide opt-in installer hooks where legally/operationally safe.
4. Never block core usage-monitor features on optional tools.

## Versioning and Releases

- SemVer tags (`v0.x` while iterating quickly).
- Release checklist includes:
  - cross-platform build
  - checksums
  - smoke test (`sync`, `web`, `status`)
  - migration test from prior data files

## Support Policy

- Core features supported without external tool installs.
- Optional providers documented separately with support matrix.
