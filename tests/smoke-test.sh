#!/usr/bin/env bash
set -euo pipefail

# Smoke test suite for Jevons v0.1.0
# Tests all core commands work against a local build
#
# Usage: tests/smoke-test.sh [binary-path]
# Default binary: ./bin/jevons

BINARY="${1:-./bin/jevons}"
TMPDIR=$(mktemp -d)
FAILED=0
PASSED=0

# Cleanup on exit
cleanup() {
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

export CLAUDE_USAGE_DATA_DIR="$TMPDIR/data"
export CLAUDE_USAGE_SOURCE_DIR="$TMPDIR/source"

# Helper: increment counters (safe under set -e)
pass() { PASSED=$((PASSED + 1)); }
fail() { FAILED=$((FAILED + 1)); }

# Helper: run test and track result
test_cmd() {
    local name="$1"
    local expected_exit="$2"
    shift 2

    echo "=== Test: $name ==="
    if "$@" > /tmp/test_output.txt 2>&1; then
        local exit_code=0
    else
        local exit_code=$?
    fi

    if [ "$exit_code" -eq "$expected_exit" ]; then
        echo "PASS: $name (exit code: $exit_code)"
        pass
    else
        echo "FAIL: $name (expected exit $expected_exit, got $exit_code)"
        cat /tmp/test_output.txt
        fail
    fi
    rm -f /tmp/test_output.txt
}

# Helper: check file exists
file_exists() {
    local path="$1"
    if [ -f "$path" ]; then
        echo "PASS: $path exists"
        pass
        return 0
    else
        echo "FAIL: $path missing"
        fail
        return 1
    fi
}

# Check binary exists
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

echo "Binary: $BINARY"
echo "Data dir: $CLAUDE_USAGE_DATA_DIR"
echo "Source dir: $CLAUDE_USAGE_SOURCE_DIR"
echo ""

# Setup: create minimal JSONL source file
mkdir -p "$CLAUDE_USAGE_SOURCE_DIR/test-project"
cat > "$CLAUDE_USAGE_SOURCE_DIR/test-project/session.jsonl" << 'JSONL'
{"parentUuid":"","type":"summary","summary":{"turnCount":1,"inputTokens":100,"outputTokens":50,"cacheReadTokens":10,"cacheCreationTokens":5},"timestamp":"2026-02-13T10:00:00.000Z","uuid":"test-uuid-1","sessionId":"test-session-1"}
JSONL

# Test 1: sync
echo "=== Test: sync ==="
if "$BINARY" sync > /tmp/sync_output.txt 2>&1; then
    echo "PASS: sync exits 0"
    pass
    file_exists "$CLAUDE_USAGE_DATA_DIR/events.tsv" || true
    file_exists "$CLAUDE_USAGE_DATA_DIR/projects.json" || true
else
    echo "FAIL: sync non-zero"
    cat /tmp/sync_output.txt
    fail
fi
rm -f /tmp/sync_output.txt

# Test 2: status
test_cmd "status" 0 "$BINARY" status

# Test 3: doctor
test_cmd "doctor" 0 "$BINARY" doctor

# Test 4: total
test_cmd "total --range 24h" 0 "$BINARY" total --range 24h

# Test 5: graph
test_cmd "graph --metric billable --range 24h" 0 "$BINARY" graph --metric billable --range 24h

# Test 6: version
test_cmd "version" 0 "$BINARY" --version

# Test 7: first-run with empty source
echo "=== Test: first-run with empty source ==="
TMPDIR2=$(mktemp -d)
export CLAUDE_USAGE_DATA_DIR="$TMPDIR2/data"
export CLAUDE_USAGE_SOURCE_DIR="$TMPDIR2/empty-source"
mkdir -p "$CLAUDE_USAGE_SOURCE_DIR"
test_cmd "sync on empty source" 0 "$BINARY" sync
rm -rf "$TMPDIR2"

# Test 8: web server start and health check
echo "=== Test: web server ==="
export CLAUDE_USAGE_DATA_DIR="$TMPDIR/data"
export CLAUDE_USAGE_SOURCE_DIR="$TMPDIR/source"
PORT=19876

# Start web server in background
if "$BINARY" web --port "$PORT" --interval 0 > /tmp/web_output.txt 2>&1 &
    WEB_PID=$!
then
    sleep 2

    # Check if server responds
    if curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/" 2>/dev/null | grep -q "200"; then
        echo "PASS: web server responds with 200"
        pass
    else
        echo "FAIL: web server not responding"
        fail
    fi

    # Stop server
    if "$BINARY" web-stop 2>/dev/null || kill $WEB_PID 2>/dev/null; then
        echo "PASS: web server stopped"
        pass
    else
        echo "FAIL: web server stop failed"
        fail
    fi
else
    echo "FAIL: web server failed to start"
    cat /tmp/web_output.txt
    fail
fi
rm -f /tmp/web_output.txt

# Summary
echo ""
echo "========================================="
echo "Smoke Test Summary"
echo "========================================="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "All smoke tests passed!"
    exit 0
else
    echo "Some tests failed."
    exit 1
fi
