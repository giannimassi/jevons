#!/usr/bin/env bash
set -euo pipefail

# Migration validation script
# Tests that Go binary correctly reads data produced by shell script
#
# Usage: tests/migration-test.sh [binary-path]
# Default binary: ./bin/jevons
#
# Requirements: shell script at ./claude-usage-tracker.sh, jq command available

BINARY="${1:-./bin/jevons}"
SHELL_SCRIPT="./claude-usage-tracker.sh"
TMPDIR=$(mktemp -d)
FAILED=0
PASSED=0

# Cleanup on exit
cleanup() {
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

# Check prerequisites
if [ ! -f "$SHELL_SCRIPT" ]; then
    echo "SKIP: Shell script not found at $SHELL_SCRIPT"
    exit 0
fi

if ! command -v jq &>/dev/null; then
    echo "SKIP: jq required for migration test"
    exit 0
fi

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

echo "Binary: $BINARY"
echo "Shell script: $SHELL_SCRIPT"
echo "Temp dir: $TMPDIR"
echo ""
echo "=== Migration Validation ==="
echo ""

# Step 1: Generate data with shell script
echo "Step 1: Running shell script sync..."
export CLAUDE_USAGE_DATA_DIR="$TMPDIR/shell-data"
if "$SHELL_SCRIPT" sync > /dev/null 2>&1; then
    echo "PASS: shell script sync completed"
    ((PASSED++))
else
    echo "FAIL: shell script sync failed"
    ((FAILED++))
    exit 1
fi

if [ ! -f "$CLAUDE_USAGE_DATA_DIR/events.tsv" ]; then
    echo "FAIL: shell script did not produce events.tsv"
    ((FAILED++))
    exit 1
fi

SHELL_EVENT_COUNT=$(wc -l < "$CLAUDE_USAGE_DATA_DIR/events.tsv")
echo "  Shell events: $SHELL_EVENT_COUNT lines"

# Step 2: Run Go binary status against shell-era data (read test)
echo ""
echo "Step 2: Testing Go binary reads shell-era data..."
export CLAUDE_USAGE_DATA_DIR="$TMPDIR/shell-data"
if "$BINARY" status > /dev/null 2>&1; then
    echo "PASS: Go binary reads shell-era data"
    ((PASSED++))
else
    echo "FAIL: Go binary cannot read shell-era data"
    ((FAILED++))
fi

# Step 3: Run Go sync against same source (should produce compatible data)
echo ""
echo "Step 3: Running Go sync against same source..."
export CLAUDE_USAGE_DATA_DIR="$TMPDIR/go-data"
if "$BINARY" sync > /dev/null 2>&1; then
    echo "PASS: Go sync completed"
    ((PASSED++))
else
    echo "FAIL: Go sync failed"
    ((FAILED++))
    exit 1
fi

if [ ! -f "$CLAUDE_USAGE_DATA_DIR/events.tsv" ]; then
    echo "FAIL: Go sync did not produce events.tsv"
    ((FAILED++))
    exit 1
fi

GO_EVENT_COUNT=$(wc -l < "$CLAUDE_USAGE_DATA_DIR/events.tsv")
echo "  Go events: $GO_EVENT_COUNT lines"

# Step 4: Compare TSV headers
echo ""
echo "Step 4: Comparing TSV headers..."
SHELL_HEADER=$(head -1 "$TMPDIR/shell-data/events.tsv")
GO_HEADER=$(head -1 "$TMPDIR/go-data/events.tsv")
if [ "$SHELL_HEADER" = "$GO_HEADER" ]; then
    echo "PASS: events.tsv headers match"
    ((PASSED++))
else
    echo "FAIL: events.tsv headers differ"
    echo "  Shell: $SHELL_HEADER"
    echo "  Go:    $GO_HEADER"
    ((FAILED++))
fi

# Step 5: Compare projects.json
echo ""
echo "Step 5: Comparing projects.json..."
if diff <(jq -S . "$TMPDIR/shell-data/projects.json" 2>/dev/null) \
        <(jq -S . "$TMPDIR/go-data/projects.json" 2>/dev/null) > /dev/null 2>&1; then
    echo "PASS: projects.json matches"
    ((PASSED++))
else
    echo "FAIL: projects.json differs"
    echo "  Shell: $(cat $TMPDIR/shell-data/projects.json)"
    echo "  Go:    $(cat $TMPDIR/go-data/projects.json)"
    ((FAILED++))
fi

# Step 6: Compare live-events.tsv if they exist
echo ""
echo "Step 6: Comparing live-events.tsv headers..."
if [ -f "$TMPDIR/shell-data/live-events.tsv" ] && [ -f "$TMPDIR/go-data/live-events.tsv" ]; then
    SHELL_LIVE_HEADER=$(head -1 "$TMPDIR/shell-data/live-events.tsv")
    GO_LIVE_HEADER=$(head -1 "$TMPDIR/go-data/live-events.tsv")
    if [ "$SHELL_LIVE_HEADER" = "$GO_LIVE_HEADER" ]; then
        echo "PASS: live-events.tsv headers match"
        ((PASSED++))
    else
        echo "FAIL: live-events.tsv headers differ"
        echo "  Shell: $SHELL_LIVE_HEADER"
        echo "  Go:    $GO_LIVE_HEADER"
        ((FAILED++))
    fi
else
    echo "SKIP: live-events.tsv not available for comparison"
fi

# Summary
echo ""
echo "========================================="
echo "Migration Validation Summary"
echo "========================================="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "Migration validation passed!"
    exit 0
else
    echo "Migration validation failed."
    exit 1
fi
