#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TRACKER_SCRIPT="$SCRIPT_ROOT/claude-usage-tracker.sh"
SESSION_NAME="cui$$"
PORT="${1:-8876}"
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/Users/gianni/dev/fun/research/skill-guard/.playwright-browsers}"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
}

require_cmd jq
require_cmd curl
require_cmd agent-browser

TMP_DIR="$(mktemp -d)"
DATA_ROOT="$TMP_DIR/data"
SOURCE_ROOT="$TMP_DIR/source"
WORKSPACE_ROOT="$TMP_DIR/workspace"
AGENT_BROWSER_HOME="$TMP_DIR/agent-browser-home"
AGENT_BROWSER_SOCKET_DIR="$TMP_DIR/sock"
PROJECT_CURRENT="$WORKSPACE_ROOT/dev/fun/research/skill-guard"
PROJECT_OTHER="$WORKSPACE_ROOT/dev/fun/other-heavy-repo"
PROJECT_THIRD="$WORKSPACE_ROOT/dev/labs/sandbox"

mkdir -p "$PROJECT_CURRENT" "$PROJECT_OTHER" "$PROJECT_THIRD"
mkdir -p "$AGENT_BROWSER_HOME"
mkdir -p "$AGENT_BROWSER_SOCKET_DIR"
export AGENT_BROWSER_HOME
export AGENT_BROWSER_SOCKET_DIR
export PLAYWRIGHT_BROWSERS_PATH

slug_from_path() {
  local path="$1"
  printf -- '-%s\n' "${path#/}" | tr '/' '-'
}

write_session() {
  local project_path="$1"
  local session_id="$2"
  local ts_user="$3"
  local ts_assistant="$4"
  local prompt="$5"
  local input_tokens="$6"
  local output_tokens="$7"
  local cache_read_tokens="$8"
  local cache_create_tokens="$9"
  local slug

  slug="$(slug_from_path "$project_path")"
  mkdir -p "$SOURCE_ROOT/$slug"
  cat > "$SOURCE_ROOT/$slug/$session_id.jsonl" <<JSONL
{"type":"user","timestamp":"$ts_user","cwd":"$project_path","message":{"content":"$prompt"}}
{"type":"assistant","timestamp":"$ts_assistant","message":{"usage":{"input_tokens":$input_tokens,"output_tokens":$output_tokens,"cache_read_input_tokens":$cache_read_tokens,"cache_creation_input_tokens":$cache_create_tokens},"content":[{"type":"text","text":"ok"}]}}
JSONL
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "ASSERTION FAILED: $message" >&2
    echo "Expected to find: $needle" >&2
    echo "Got: $haystack" >&2
    exit 1
  fi
}
assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "ASSERTION FAILED: $message" >&2
    echo "Did not expect to find: $needle" >&2
    echo "Got: $haystack" >&2
    exit 1
  fi
}

cleanup() {
  CLAUDE_USAGE_DATA_DIR="$DATA_ROOT" CLAUDE_USAGE_SOURCE_DIR="$SOURCE_ROOT" "$TRACKER_SCRIPT" web-stop --with-sync >/dev/null 2>&1 || true
  agent-browser --session "$SESSION_NAME" close >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

now_epoch="$(date +%s)"
iso_at() {
  date -u -r "$1" +"%Y-%m-%dT%H:%M:%S.000Z"
}

write_session "$PROJECT_CURRENT" "session-current" "$(iso_at $((now_epoch - 2400)))" "$(iso_at $((now_epoch - 2390)))" "Design a safer tree UI" 220 510 1300 210
write_session "$PROJECT_CURRENT" "session-current-2" "$(iso_at $((now_epoch - 1200)))" "$(iso_at $((now_epoch - 1180)))" "Add regression tests for scope navigation" 140 420 900 120
write_session "$PROJECT_OTHER" "session-other" "$(iso_at $((now_epoch - 1800)))" "$(iso_at $((now_epoch - 1788)))" "Generate benchmark report" 95 205 300 40
write_session "$PROJECT_THIRD" "session-third" "$(iso_at $((now_epoch - 900)))" "$(iso_at $((now_epoch - 880)))" "quick sandbox prompt" 30 55 0 0

slug_current="$(slug_from_path "$PROJECT_CURRENT")"
cat > "$SOURCE_ROOT/$slug_current/session-current-nocwd.jsonl" <<JSONL
{"type":"user","timestamp":"$(iso_at $((now_epoch - 700)))","message":{"content":"missing cwd test"}}
{"type":"assistant","timestamp":"$(iso_at $((now_epoch - 690)))","message":{"usage":{"input_tokens":60,"output_tokens":90,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"content":[{"type":"text","text":"ok"}]}}
JSONL

(
  cd "$PROJECT_CURRENT"
  CLAUDE_USAGE_DATA_DIR="$DATA_ROOT" CLAUDE_USAGE_SOURCE_DIR="$SOURCE_ROOT" "$TRACKER_SCRIPT" web --no-open --port "$PORT" --interval 2 >/dev/null
)

for _ in {1..50}; do
  if curl -fsS "http://127.0.0.1:$PORT/dashboard/index.html" >/dev/null; then
    break
  fi
  sleep 0.2
done

url="http://127.0.0.1:$PORT/dashboard/index.html"
agent-browser --session "$SESSION_NAME" open "$url"
agent-browser --session "$SESSION_NAME" wait --load networkidle

agent-browser --session "$SESSION_NAME" click '#currentScopeBtn'
agent-browser --session "$SESSION_NAME" wait 500
subtitle_now="$(agent-browser --session "$SESSION_NAME" get text '#subtitle')"
assert_contains "$subtitle_now" "$PROJECT_CURRENT" "Current button should scope to launch directory"
tree_labels="$(agent-browser --session "$SESSION_NAME" eval '[...document.querySelectorAll("#scopeTree .scope-btn")].map((b)=>b.textContent.trim()).join("|")')"
assert_contains "$tree_labels" "skill-guard" "Tree should include hyphenated repo folder name"
assert_not_contains "$tree_labels" "|guard|" "Tree should not invent a synthetic guard subfolder from slug fallback"

agent-browser --session "$SESSION_NAME" find role button click --name "skill-guard"
agent-browser --session "$SESSION_NAME" wait 6100
agent-browser --session "$SESSION_NAME" find role button click --name "skill-guard"
subtitle_after_refresh="$(agent-browser --session "$SESSION_NAME" get text '#subtitle')"
assert_contains "$subtitle_after_refresh" "$PROJECT_CURRENT" "Scope should persist after auto-refresh"

agent-browser --session "$SESSION_NAME" click '#allScopeBtn'
agent-browser --session "$SESSION_NAME" wait 300
subtitle_all="$(agent-browser --session "$SESSION_NAME" get text '#subtitle')"
assert_contains "$subtitle_all" "all projects" "All button should return to global scope"

agent-browser --session "$SESSION_NAME" click '#currentScopeBtn'
agent-browser --session "$SESSION_NAME" click '#refreshBtn'
agent-browser --session "$SESSION_NAME" wait 800
subtitle_after_manual_refresh="$(agent-browser --session "$SESSION_NAME" get text '#subtitle')"
assert_contains "$subtitle_after_manual_refresh" "$PROJECT_CURRENT" "Manual refresh should not lose current scope"

agent-browser --session "$SESSION_NAME" screenshot "$TMP_DIR/ui-regression.png" >/dev/null

printf 'ui_regression=pass\n'
printf 'artifact=%s\n' "$TMP_DIR/ui-regression.png"
printf 'dashboard=%s\n' "$url"
