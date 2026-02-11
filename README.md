# Claude Usage Monitor

Local usage monitor and dashboard for Claude session logs.

## Current Implementation

This repository currently contains a production-ready shell implementation:

- `claude-usage-tracker.sh`: sync daemon + dashboard server + CLI
- `tests/claude-usage-ui-regression.sh`: UI regression script (agent-browser)

## Quick Start

```bash
# start dashboard + sync loop
./claude-usage-tracker.sh web --interval 15 --port 8765

# one-shot sync
./claude-usage-tracker.sh sync

# status
./claude-usage-tracker.sh status
```

Dashboard URL:

- `http://127.0.0.1:8765/dashboard/index.html`

## Docs

- `docs/CONVERSATION_AND_BUILD_SUMMARY_2026-02-11.md`
- `docs/RELEASE_AND_PACKAGING_STRATEGY.md`
- `docs/GO_PORT_PLAN.md`

## Notes

The shell implementation is stable enough for daily use, but the long-term direction is a single-binary Go CLI that embeds the dashboard and offers better packaging/distribution.
