# Jevons

Local AI usage monitor and dashboard. Reads session logs from AI coding tools (Claude, Codex, and others), aggregates token consumption into event stores, and serves an interactive HTML dashboard.

Named after [Jevons paradox](https://en.wikipedia.org/wiki/Jevons_paradox) — as AI tools get more efficient, we use them more.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Current Implementation

The tool currently ships as a shell implementation (`claude-usage-tracker.sh`) with a Go port in progress.

### Shell (stable)

```bash
# start dashboard + sync loop
./claude-usage-tracker.sh web --interval 15 --port 8765

# one-shot sync
./claude-usage-tracker.sh sync

# status
./claude-usage-tracker.sh status
```

### Go (in development)

```bash
# build
make build

# run
./bin/jevons web --port 8765 --interval 15
./bin/jevons sync
./bin/jevons status
./bin/jevons doctor
```

Dashboard URL: `http://127.0.0.1:8765/dashboard/index.html`

## Install

### From source

```bash
git clone https://github.com/OWNER/jevons.git
cd jevons
make build
```

### Shell script (no Go required)

```bash
./claude-usage-tracker.sh web
```

## Docs

- [Go Port Plan](docs/GO_PORT_PLAN.md)
- [Release & Packaging Strategy](docs/RELEASE_AND_PACKAGING_STRATEGY.md)
- [Release Execution Plan](docs/RELEASE_EXECUTION_PLAN.md)

## License

[MIT](LICENSE)
