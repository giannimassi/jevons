# Conversation + Build Summary (2026-02-11)

## User Goal

Build a practical Claude token-usage monitor that:

1. Runs continuously with minimal permission interruptions.
2. Shows meaningful real-time and short-window usage.
3. Supports project/directory scoping.
4. Offers a dashboard first (web UX over TUI).
5. Gives account context and cache/non-cache visibility.
6. Is reliable enough to package and share.

## What Was Built

### Core data pipeline

- Sync pipeline from `~/.claude/projects` JSONL logs.
- Event table generation (`events.tsv`) and live prompt-linked table (`live-events.tsv`).
- Account metadata extraction from `~/.claude.json` into `account.json`.
- Sync status + heartbeat files for daemon health.

### Dashboard UX

- Web dashboard with time range, bucket, metric, graph mode, and visualization selectors.
- Graph modes:
  - single metric
  - input vs output
  - cached vs non-cached
  - cache read vs create
- Live prompt-consumption table with prompt preview + token columns.
- Hover tooltips with precise datapoint values.
- Account popover for logged-in user/account metadata.

### Scope selection

- Directory tree scoping with search.
- `Current` scope shortcut (launch directory context).
- Persistent scope selection across refresh/reload.

### UX polish

- Subtle modern background motion and grid texture.
- Improved panel/card hierarchy and typography.
- Better empty-range behavior via actionable hint bar.

## Confirmed Issues and Fixes

### 1) Tree path bug (critical UX)

Issue: hyphenated names (e.g., `skill-guard`) could appear as fake synthetic split paths (e.g., `skill`/`guard`) when log entries lacked `cwd`.

Fix:

- Stop inferring separators from slug fallback.
- Treat fallback path as non-authoritative (`/unknown/<slug>`).
- When multiple entries share a slug, prefer a real `cwd` path.

### 2) Empty dashboard confusion

Issue: with narrow window + inactive scope, dashboard looked broken.

Fix:

- Added explicit empty-range hint with quick actions:
  - set range 7d
  - set range all time
  - show all projects

### 3) Scope persistence regressions

Fix:

- Preserve tree open state and selected scope across refresh and reload.

## Validation Performed

- Shell syntax checks.
- Sync scenario matrix (empty, dedupe, adversarial tool_result).
- Browser automation checks for scope and interaction behavior.
- Visual regression snapshots.

## Current Limitations

- Still a shell codebase (harder to package as a polished binary product).
- Browser automation in restricted sandboxes may fail due host-level browser-launch constraints.
- Live freshness depends on source log write cadence from Claude.

## Product Direction Agreed During Conversation

1. Move code into dedicated repo near product identity.
2. Package for broader external use.
3. Port core runtime to Go for a single-binary UX.
4. Handle optional external integrations via adapters and graceful degradation.
