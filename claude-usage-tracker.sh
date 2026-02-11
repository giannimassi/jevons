#!/usr/bin/env bash
set -euo pipefail

DATA_ROOT="${CLAUDE_USAGE_DATA_DIR:-$HOME/dev/.claude-usage}"
SOURCE_ROOT="${CLAUDE_USAGE_SOURCE_DIR:-$HOME/.claude/projects}"
DEFAULT_PORT="8765"
DEFAULT_SYNC_INTERVAL="15"

usage() {
  cat <<'USAGE'
claude-usage-tracker: accurate Claude usage dashboard + auto-sync

Usage:
  claude-usage [command] [options]
  claude-usage --web [options]

If no command is provided, web mode is used by default.

Commands:
  web            Start auto-sync + dashboard server (opens browser unless --no-open)
  web-stop       Stop dashboard server
  web-status     Show dashboard server status
  sync           One-shot sync from ~/.claude/projects into events store
  sync-start     Start background sync loop
  sync-stop      Stop background sync loop
  sync-status    Show sync loop status
  status         Show combined sync + web + latest usage status
  total          Print totals from synced events (JSON)
  graph          Render ASCII graph from synced events

Compatibility aliases:
  snapshot       Alias for sync
  start          Alias for sync-start
  stop           Alias for sync-stop
  live           Tail synced events as they are appended

Common options:
  --project-path <path>     Filter to one project path
  --project-slug <slug>     Filter to one project slug
  --range <window>          1h|3h|6h|12h|24h|30h|48h|7d|14d|30d|all (default: 30h)

Web options:
  --interval <seconds>      Sync interval for background loop (default: 15)
  --port <port>             Dashboard server port (default: 8765)
  --no-open                 Do not open browser automatically

Graph options:
  --metric <name>           billable|input|output|cache_read|cache_create|total_with_cache
  --points <n>              Number of buckets to render (default: 80)
  --bucket <seconds>        Bucket width in seconds (default: 900)
USAGE
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
}

ensure_data_dirs() {
  mkdir -p \
    "$DATA_ROOT" \
    "$DATA_ROOT/pids" \
    "$DATA_ROOT/logs" \
    "$DATA_ROOT/heartbeat" \
    "$DATA_ROOT/web" \
    "$DATA_ROOT/dashboard"
}

project_slug_from_path() {
  local path="$1"
  path="$(cd "$path" && pwd -P)"
  printf -- "-%s" "${path#/}" | tr '/' '-'
}

project_path_guess_from_slug() {
  local slug="$1"
  printf '/unknown/%s\n' "$slug"
}

sync_events_path() {
  printf '%s/events.tsv\n' "$DATA_ROOT"
}

sync_live_events_path() {
  printf '%s/live-events.tsv\n' "$DATA_ROOT"
}

projects_manifest_path() {
  printf '%s/projects.json\n' "$DATA_ROOT"
}

account_info_path() {
  printf '%s/account.json\n' "$DATA_ROOT"
}

ui_context_path() {
  printf '%s/ui-context.json\n' "$DATA_ROOT"
}

sync_status_path() {
  printf '%s/sync-status.json\n' "$DATA_ROOT"
}

sync_pid_file_path() {
  printf '%s/pids/sync.pid\n' "$DATA_ROOT"
}

sync_log_file_path() {
  printf '%s/logs/sync.log\n' "$DATA_ROOT"
}

sync_heartbeat_file_path() {
  printf '%s/heartbeat/sync.txt\n' "$DATA_ROOT"
}

web_pid_file_path() {
  printf '%s/web/server.pid\n' "$DATA_ROOT"
}

web_port_file_path() {
  printf '%s/web/server.port\n' "$DATA_ROOT"
}

web_log_file_path() {
  printf '%s/web/server.log\n' "$DATA_ROOT"
}

is_pid_running() {
  local pid="$1"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" >/dev/null 2>&1
}

sync_heartbeat_state() {
  local heartbeat_file now hb hb_epoch hb_interval hb_pid hb_status age
  local healthy_limit
  heartbeat_file="$(sync_heartbeat_file_path)"
  [[ -f "$heartbeat_file" ]] || return 1

  hb="$(cat "$heartbeat_file" 2>/dev/null || true)"
  IFS=',' read -r hb_epoch hb_interval hb_pid hb_status <<< "$hb"
  [[ "${hb_epoch:-}" =~ ^[0-9]+$ ]] || return 1
  [[ "${hb_interval:-}" =~ ^[0-9]+$ ]] || hb_interval=0
  now="$(date +%s)"
  age=$(( now - hb_epoch ))
  healthy_limit=$(( hb_interval * 12 ))
  if [[ "$healthy_limit" -lt 300 ]]; then
    healthy_limit=300
  fi

  if [[ "$hb_interval" -gt 0 ]] && [[ "$age" -le "$healthy_limit" ]]; then
    printf 'running\t%s\t%s\t%s\t%s\n' "${hb_pid:-unknown}" "$hb_interval" "$age" "${hb_status:-unknown}"
  else
    printf 'stale\t%s\t%s\t%s\t%s\n' "${hb_pid:-unknown}" "$hb_interval" "$age" "${hb_status:-unknown}"
  fi
}

is_dashboard_responding() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  command -v curl >/dev/null 2>&1 || return 1
  curl -fsS --max-time 1 "http://127.0.0.1:${port}/dashboard/index.html" \
    | head -c 8192 \
    | grep -q "Claude Usage Monitor"
}

is_sync_running() {
  local pid_file pid
  pid_file="$(sync_pid_file_path)"
  if [[ -f "$pid_file" ]]; then
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if is_pid_running "$pid"; then
      return 0
    fi
  fi

  local hb_state
  hb_state="$(sync_heartbeat_state 2>/dev/null || true)"
  [[ "${hb_state%%$'\t'*}" == "running" ]]
}

is_web_server_running() {
  local pid_file port_file pid port
  pid_file="$(web_pid_file_path)"
  port_file="$(web_port_file_path)"

  if [[ -f "$pid_file" ]]; then
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if is_pid_running "$pid"; then
      return 0
    fi
  fi

  if [[ -f "$port_file" ]]; then
    port="$(cat "$port_file" 2>/dev/null || true)"
    if is_dashboard_responding "$port"; then
      return 0
    fi
  fi

  return 1
}

open_url() {
  local url="$1"
  if command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1 || true
    return
  fi
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 || true
  fi
}

write_ui_context() {
  local ui_file tmp_file cwd now_iso
  ui_file="$(ui_context_path)"
  tmp_file="$(mktemp)"
  cwd="$(pwd -P)"
  now_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  jq -n \
    --arg cwd "$cwd" \
    --arg source_root "$SOURCE_ROOT" \
    --arg generated_at "$now_iso" \
    '{
      cwd: $cwd,
      source_root: $source_root,
      generated_at: $generated_at
    }' > "$tmp_file"

  mv "$tmp_file" "$ui_file"
}

range_to_seconds() {
  local range="$1"
  case "$range" in
    1h) echo 3600 ;;
    3h) echo 10800 ;;
    6h) echo 21600 ;;
    12h) echo 43200 ;;
    24h) echo 86400 ;;
    30h) echo 108000 ;;
    48h) echo 172800 ;;
    7d) echo 604800 ;;
    14d) echo 1209600 ;;
    30d) echo 2592000 ;;
    all) echo 0 ;;
    *)
      echo "Unknown range: $range" >&2
      exit 1
      ;;
  esac
}

project_path_from_session_file() {
  local session_file="$1"
  local cwd

  # Prefer path metadata recorded by Claude; it is authoritative.
  cwd="$(jq -r 'select(.cwd != null and (.cwd|type)=="string") | .cwd' "$session_file" 2>/dev/null | sed -n '1p' || true)"
  if [[ -n "$cwd" ]]; then
    printf '%s\n' "$cwd"
    return
  fi

  printf '\n'
}

extract_events_from_session_file() {
  local session_file="$1"
  local project_slug="$2"
  local session_id="$3"

  jq -R -n -r \
    --arg project_slug "$project_slug" \
    --arg session_id "$session_id" '
    def usage_sig($m):
      "\($m.usage.input_tokens // 0)|\($m.usage.output_tokens // 0)|\($m.usage.cache_read_input_tokens // 0)|\($m.usage.cache_creation_input_tokens // 0)";

    def parse_epoch($ts):
      if ($ts | type) == "string" then
        ((
          $ts
          | sub("\\.[0-9]+Z$"; "Z")
          | sub("\\.[0-9]+(?<tz>[+-][0-9]{2}:[0-9]{2})$"; "\(.tz)")
          | fromdateiso8601?
        ) // 0)
      else
        0
      end;

    def content_type($row):
      if ($row.message.content | type) == "array" then
        if (($row.message.content | length) > 0) and (($row.message.content[0] | type) == "object") then
          ($row.message.content[0].type // "-")
        else
          "-"
        end
      elif ($row.message.content | type) == "string" then
        "text"
      else
        "-"
      end;

    def is_human_prompt($row):
      if ($row.message.content | type) == "string" then
        true
      elif ($row.message.content | type) == "array" then
        ([ $row.message.content[]? | .type ] as $types
          | if ($types | length) == 0 then
              true
            else
              ($types | all(. == "tool_result") | not)
            end
        )
      else
        true
      end;

    foreach (inputs | fromjson? | select(type == "object")) as $row (
      {pending_human:false, last_sig:null, emit:null};
      .emit = null
      | if ($row.type == "user" and ($row.message? != null)) then
          .pending_human = (.pending_human or is_human_prompt($row))
        elif (
          $row.type == "assistant"
          and ($row.message? != null)
          and ($row.message.usage? != null)
          and ((($row.isApiErrorMessage // false) | not))
        ) then
          ($row.message.usage.input_tokens // 0) as $in
          | ($row.message.usage.output_tokens // 0) as $out
          | ($row.message.usage.cache_read_input_tokens // 0) as $cr
          | ($row.message.usage.cache_creation_input_tokens // 0) as $cc
          | (usage_sig($row.message)) as $sig
          | if (.last_sig == $sig and (.pending_human | not)) then
              .last_sig = $sig
              | .pending_human = false
            else
              .emit = ([
                parse_epoch($row.timestamp // ""),
                ($row.timestamp // ""),
                $project_slug,
                $session_id,
                $in,
                $out,
                $cr,
                $cc,
                ($in + $out),
                ($in + $out + $cr + $cc),
                content_type($row),
                $sig
              ] | @tsv)
              | .last_sig = $sig
              | .pending_human = false
            end
        else
          .
        end;
      .emit
    ) | select(. != null)
  ' "$session_file"
}

extract_live_events_from_session_file() {
  local session_file="$1"
  local project_slug="$2"
  local session_id="$3"

  jq -R -n -r \
    --arg project_slug "$project_slug" \
    --arg session_id "$session_id" '
    def usage_sig($m):
      "\($m.usage.input_tokens // 0)|\($m.usage.output_tokens // 0)|\($m.usage.cache_read_input_tokens // 0)|\($m.usage.cache_creation_input_tokens // 0)";

    def parse_epoch($ts):
      if ($ts | type) == "string" then
        ((
          $ts
          | sub("\\.[0-9]+Z$"; "Z")
          | sub("\\.[0-9]+(?<tz>[+-][0-9]{2}:[0-9]{2})$"; "\(.tz)")
          | fromdateiso8601?
        ) // 0)
      else
        0
      end;

    def content_type($row):
      if ($row.message.content | type) == "array" then
        if (($row.message.content | length) > 0) and (($row.message.content[0] | type) == "object") then
          ($row.message.content[0].type // "-")
        else
          "-"
        end
      elif ($row.message.content | type) == "string" then
        "text"
      else
        "-"
      end;

    def is_human_prompt($row):
      if ($row.message.content | type) == "string" then
        true
      elif ($row.message.content | type) == "array" then
        ([ $row.message.content[]? | .type ] as $types
          | if ($types | length) == 0 then
              true
            else
              ($types | all(. == "tool_result") | not)
            end
        )
      else
        true
      end;

    def prompt_text($row):
      if ($row.message.content | type) == "string" then
        ($row.message.content // "")
      elif ($row.message.content | type) == "array" then
        ([ $row.message.content[]?
          | if (.type // "") == "text" then (.text // "")
            elif (.type // "") == "tool_result" then ""
            else ""
            end
        ] | join(" "))
      else
        ""
      end;

    def clean_text($s):
      ($s
        | tostring
        | gsub("[\t\r\n]+"; " ")
        | gsub(" +"; " ")
        | sub("^ "; "")
        | sub(" $"; "")
      );

    def prompt_preview($row):
      (clean_text(prompt_text($row))) as $p
      | if ($p | length) == 0 then
          "-"
        elif ($p | length) > 180 then
          ($p[0:177] + "...")
        else
          $p
        end;

    foreach (inputs | fromjson? | select(type == "object")) as $row (
      {pending_human:false, last_sig:null, last_prompt:"-", emit:null};
      .emit = null
      | if ($row.type == "user" and ($row.message? != null)) then
          if is_human_prompt($row) then
            .pending_human = true
            | .last_prompt = prompt_preview($row)
          else
            .
          end
        elif (
          $row.type == "assistant"
          and ($row.message? != null)
          and ($row.message.usage? != null)
          and ((($row.isApiErrorMessage // false) | not))
        ) then
          ($row.message.usage.input_tokens // 0) as $in
          | ($row.message.usage.output_tokens // 0) as $out
          | ($row.message.usage.cache_read_input_tokens // 0) as $cr
          | ($row.message.usage.cache_creation_input_tokens // 0) as $cc
          | (usage_sig($row.message)) as $sig
          | if (.last_sig == $sig and (.pending_human | not)) then
              .last_sig = $sig
            else
              .emit = ([
                parse_epoch($row.timestamp // ""),
                ($row.timestamp // ""),
                $project_slug,
                $session_id,
                (.last_prompt // "-"),
                $in,
                $out,
                $cr,
                $cc,
                ($in + $out),
                ($in + $out + $cr + $cc),
                content_type($row),
                $sig
              ] | @tsv)
              | .last_sig = $sig
              | .pending_human = false
            end
        else
          .
        end;
      .emit
    ) | select(. != null)
  ' "$session_file"
}

cmd_sync() {
  require_cmd jq
  ensure_data_dirs

  local source_root="$SOURCE_ROOT"
  local events_file live_events_file projects_file status_file account_file
  local tmp_events tmp_events_sorted tmp_live_events tmp_live_events_sorted tmp_projects_txt tmp_projects_json tmp_account_json
  local session_files_count=0 events_count=0 live_events_count=0
  local now_epoch now_iso

  events_file="$(sync_events_path)"
  live_events_file="$(sync_live_events_path)"
  projects_file="$(projects_manifest_path)"
  status_file="$(sync_status_path)"
  account_file="$(account_info_path)"

  tmp_events="$(mktemp)"
  tmp_events_sorted="$(mktemp)"
  tmp_live_events="$(mktemp)"
  tmp_live_events_sorted="$(mktemp)"
  tmp_projects_txt="$(mktemp)"
  tmp_projects_json="$(mktemp)"
  tmp_account_json="$(mktemp)"

  printf 'ts_epoch\tts_iso\tproject_slug\tsession_id\tinput\toutput\tcache_read\tcache_create\tbillable\ttotal_with_cache\tcontent_type\tsignature\n' > "$tmp_events"
  printf 'ts_epoch\tts_iso\tproject_slug\tsession_id\tprompt_preview\tinput\toutput\tcache_read\tcache_create\tbillable\ttotal_with_cache\tcontent_type\tsignature\n' > "$tmp_live_events"

  if [[ -d "$source_root" ]]; then
    while IFS= read -r session_file; do
      [[ -n "$session_file" ]] || continue
      local project_slug session_id project_path
      project_slug="$(basename "$(dirname "$session_file")")"
      session_id="$(basename "$session_file" .jsonl)"
      project_path="$(project_path_from_session_file "$session_file" "$project_slug")"
      if [[ -z "$project_path" ]]; then
        project_path="$(project_path_guess_from_slug "$project_slug")"
      fi

      printf '%s\t%s\n' "$project_slug" "$project_path" >> "$tmp_projects_txt"
      extract_events_from_session_file "$session_file" "$project_slug" "$session_id" >> "$tmp_events" || true
      extract_live_events_from_session_file "$session_file" "$project_slug" "$session_id" >> "$tmp_live_events" || true
      session_files_count=$((session_files_count + 1))
    done < <(find "$source_root" -mindepth 2 -maxdepth 2 -type f -name '*.jsonl' | LC_ALL=C sort)
  fi

  {
    head -n 1 "$tmp_events"
    tail -n +2 "$tmp_events" | LC_ALL=C sort -t $'\t' -k1,1n -k2,2 -k3,3 -k4,4 -k12,12 | awk '!seen[$0]++'
  } > "$tmp_events_sorted"

  mv "$tmp_events_sorted" "$events_file"

  {
    head -n 1 "$tmp_live_events"
    tail -n +2 "$tmp_live_events" | LC_ALL=C sort -t $'\t' -k1,1n -k2,2 -k3,3 -k4,4 -k13,13 | awk '!seen[$0]++'
  } > "$tmp_live_events_sorted"
  mv "$tmp_live_events_sorted" "$live_events_file"

  if [[ -s "$tmp_projects_txt" ]]; then
    LC_ALL=C sort -u "$tmp_projects_txt" \
      | jq -R -s '
          split("\n")
          | map(select(length > 0))
          | map(split("\t"))
          | map({slug: .[0], path: .[1]})
          | group_by(.slug)
          | map({
              slug: .[0].slug,
              path: (
                (map(.path) | map(select(startswith("/unknown/") | not)) | first)
                // .[0].path
              )
            })
          | sort_by(.path)
        ' > "$tmp_projects_json"
  else
    printf '[]\n' > "$tmp_projects_json"
  fi
  mv "$tmp_projects_json" "$projects_file"

  events_count=$(( $(wc -l < "$events_file" | tr -d ' ') - 1 ))
  if (( events_count < 0 )); then
    events_count=0
  fi
  live_events_count=$(( $(wc -l < "$live_events_file" | tr -d ' ') - 1 ))
  if (( live_events_count < 0 )); then
    live_events_count=0
  fi

  if [[ -f "$HOME/.claude.json" ]]; then
    jq '{
      display_name: (.oauthAccount.displayName // null),
      email: (.oauthAccount.emailAddress // null),
      billing_type: (.oauthAccount.billingType // null),
      account_uuid: (.oauthAccount.accountUuid // null),
      organization_uuid: (.oauthAccount.organizationUuid // null),
      has_extra_usage_enabled: (.oauthAccount.hasExtraUsageEnabled // null),
      account_created_at: (.oauthAccount.accountCreatedAt // null),
      subscription_created_at: (.oauthAccount.subscriptionCreatedAt // null),
      has_available_subscription: (.hasAvailableSubscription // null),
      has_opus_plan_default: (.hasOpusPlanDefault // null),
      user_id: (.userID // null),
      generated_at: (now | todateiso8601)
    }' "$HOME/.claude.json" > "$tmp_account_json" 2>/dev/null || printf '{}\n' > "$tmp_account_json"
  else
    printf '{}\n' > "$tmp_account_json"
  fi
  mv "$tmp_account_json" "$account_file"

  now_epoch="$(date +%s)"
  now_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  jq -n \
    --argjson last_sync_epoch "$now_epoch" \
    --arg last_sync_iso "$now_iso" \
    --arg source_root "$source_root" \
    --argjson session_files "$session_files_count" \
    --argjson event_rows "$events_count" \
    --argjson live_event_rows "$live_events_count" \
    '{
      last_sync_epoch: $last_sync_epoch,
      last_sync_iso: $last_sync_iso,
      source_root: $source_root,
      session_files: $session_files,
      event_rows: $event_rows,
      live_event_rows: $live_event_rows
    }' > "$status_file"

  rm -f "$tmp_events" "$tmp_live_events" "$tmp_projects_txt" 2>/dev/null || true

  echo "sync_ok session_files=$session_files_count event_rows=$events_count live_rows=$live_events_count source_root=$source_root"
}

write_sync_heartbeat() {
  local interval="$1"
  local pid="$2"
  local status="$3"
  local heartbeat
  heartbeat="$(sync_heartbeat_file_path)"
  printf '%s,%s,%s,%s\n' "$(date +%s)" "$interval" "$pid" "$status" > "$heartbeat"
}

cmd_sync_loop() {
  local interval="$DEFAULT_SYNC_INTERVAL"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --interval) interval="$2"; shift 2 ;;
      *) echo "Unknown option for sync-loop: $1" >&2; exit 1 ;;
    esac
  done

  if ! [[ "$interval" =~ ^[0-9]+$ ]] || [[ "$interval" -lt 1 ]]; then
    echo "--interval must be a positive integer" >&2
    exit 1
  fi

  ensure_data_dirs

  while true; do
    write_sync_heartbeat "$interval" "$$" "working"
    if cmd_sync >/dev/null 2>&1; then
      write_sync_heartbeat "$interval" "$$" "ok"
    else
      write_sync_heartbeat "$interval" "$$" "error"
    fi
    sleep "$interval"
  done
}

cmd_sync_start() {
  local interval="$DEFAULT_SYNC_INTERVAL"
  local pid_file log_file script_path script_invoked_path pid hb_state hb_mode hb_pid

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --interval) interval="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option for sync-start: $1" >&2; exit 1 ;;
    esac
  done

  if ! [[ "$interval" =~ ^[0-9]+$ ]] || [[ "$interval" -lt 1 ]]; then
    echo "--interval must be a positive integer" >&2
    exit 1
  fi

  ensure_data_dirs

  pid_file="$(sync_pid_file_path)"
  log_file="$(sync_log_file_path)"
  script_invoked_path="${BASH_SOURCE[0]:-$0}"
  if [[ "$script_invoked_path" != */* ]]; then
    script_invoked_path="$(command -v "$script_invoked_path" 2>/dev/null || printf '%s' "$script_invoked_path")"
  fi
  script_path="$(cd "$(dirname "$script_invoked_path")" && pwd -P)/$(basename "$script_invoked_path")"

  if [[ -f "$pid_file" ]]; then
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if is_pid_running "$pid"; then
      echo "Sync loop already running (pid=$pid)"
      write_sync_heartbeat "$interval" "$pid" "ok"
      return 0
    fi
  fi

  hb_state="$(sync_heartbeat_state 2>/dev/null || true)"
  hb_mode="${hb_state%%$'\t'*}"
  hb_pid="$(printf '%s' "$hb_state" | awk -F'\t' '{print $2}')"
  if [[ "$hb_mode" == "running" ]]; then
    echo "Sync loop already running (pid=${hb_pid:-unknown}, via heartbeat)"
    return 0
  fi

  rm -f "$pid_file"

  nohup "$script_path" sync-loop --interval "$interval" >> "$log_file" 2>&1 &
  pid=$!
  echo "$pid" > "$pid_file"
  write_sync_heartbeat "$interval" "$pid" "ok"
  echo "Started sync loop (pid=$pid, interval=${interval}s)"
}

cmd_sync_stop() {
  local pid_file heartbeat_file pid
  pid_file="$(sync_pid_file_path)"
  heartbeat_file="$(sync_heartbeat_file_path)"

  if [[ ! -f "$pid_file" ]]; then
    echo "Sync loop not running"
    rm -f "$heartbeat_file"
    return 0
  fi

  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if is_pid_running "$pid"; then
    kill "$pid" >/dev/null 2>&1 || true
    echo "Stopped sync loop (pid=$pid)"
  else
    echo "Sync pid file was stale"
  fi

  rm -f "$pid_file" "$heartbeat_file"
}

cmd_sync_status() {
  local pid_file heartbeat_file status_file pid hb status_json hb_state hb_mode hb_pid hb_interval hb_age hb_status
  pid_file="$(sync_pid_file_path)"
  heartbeat_file="$(sync_heartbeat_file_path)"
  status_file="$(sync_status_path)"

  hb_state="$(sync_heartbeat_state 2>/dev/null || true)"
  hb_mode="${hb_state%%$'\t'*}"
  if [[ -n "$hb_state" ]]; then
    hb_pid="$(printf '%s' "$hb_state" | awk -F'\t' '{print $2}')"
    hb_interval="$(printf '%s' "$hb_state" | awk -F'\t' '{print $3}')"
    hb_age="$(printf '%s' "$hb_state" | awk -F'\t' '{print $4}')"
    hb_status="$(printf '%s' "$hb_state" | awk -F'\t' '{print $5}')"
  fi

  if [[ "$hb_mode" == "running" ]]; then
    echo "sync_status=running pid=${hb_pid:-unknown} source=heartbeat age=${hb_age:-0}s interval=${hb_interval:-0}s status=${hb_status:-unknown}"
  elif [[ -f "$pid_file" ]]; then
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if is_pid_running "$pid"; then
      echo "sync_status=running pid=$pid"
    else
      echo "sync_status=stale-pid pid=${pid:-unknown}"
    fi
  else
    echo "sync_status=stopped"
  fi

  if [[ -f "$heartbeat_file" ]]; then
    hb="$(cat "$heartbeat_file")"
    echo "sync_heartbeat=$hb"
  else
    echo "sync_heartbeat=none"
  fi

  if [[ -f "$status_file" ]]; then
    status_json="$(cat "$status_file")"
    echo "sync_last_status_json=$status_json"
  else
    echo "sync_last_status_json=none"
  fi

  echo "events_file=$(sync_events_path)"
}

ensure_dashboard_html() {
  local file="$DATA_ROOT/dashboard/index.html"
  cat > "$file" <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Claude Usage Monitor</title>
  <style>
    :root {
      --bg: #f4f2ea;
      --bg2: #e8f1f7;
      --bg3: #ecf8ff;
      --ink: #1a2233;
      --muted: #56647d;
      --card: #ffffff;
      --border: #d7e0ec;
      --accent: #0f766e;
      --accent2: #c2410c;
      --accent3: #1d4ed8;
      --ok: #0f766e;
      --bad: #b91c1c;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background:
        radial-gradient(circle at 10% 4%, #fff4cf 0%, transparent 38%),
        radial-gradient(circle at 92% 8%, #d8efff 0%, transparent 44%),
        linear-gradient(165deg, var(--bg) 0%, var(--bg2) 62%, var(--bg3) 100%);
      color: var(--ink);
      font-family: "Space Grotesk", "IBM Plex Sans", "Avenir Next", "Segoe UI", sans-serif;
      min-height: 100vh;
      position: relative;
      overflow-x: hidden;
      animation: bgDrift 18s ease-in-out infinite alternate;
    }
    body::before {
      content: "";
      position: fixed;
      inset: 0;
      pointer-events: none;
      opacity: 0.16;
      background-image:
        linear-gradient(rgba(25, 44, 74, 0.08) 1px, transparent 1px),
        linear-gradient(90deg, rgba(25, 44, 74, 0.08) 1px, transparent 1px);
      background-size: 32px 32px;
      animation: gridFloat 26s linear infinite;
      z-index: 0;
    }
    @keyframes bgDrift {
      from { background-position: 0 0, 0 0, 0 0; }
      to { background-position: 22px -12px, -24px 10px, 0 0; }
    }
    @keyframes gridFloat {
      from { transform: translate3d(0, 0, 0); }
      to { transform: translate3d(-32px, -18px, 0); }
    }
    @keyframes fadeUp {
      from { opacity: 0; transform: translateY(4px); }
      to { opacity: 1; transform: translateY(0); }
    }
    .wrap { max-width: 1460px; margin: 0 auto; padding: 16px; position: relative; z-index: 1; }
    .topbar {
      display: flex;
      align-items: start;
      justify-content: space-between;
      gap: 12px;
    }
    h1 {
      margin: 0;
      font-size: 34px;
      letter-spacing: -0.03em;
      background: linear-gradient(130deg, #111827 0%, #123254 46%, #0f766e 100%);
      -webkit-background-clip: text;
      background-clip: text;
      color: transparent;
      text-shadow: 0 1px 0 rgba(255, 255, 255, 0.45);
    }
    .subtitle { margin-top: 4px; color: var(--muted); font-size: 14px; }
    .acct-wrap { position: relative; }
    .acct-btn {
      border: 1px solid #bfd6ee;
      background: #ffffff;
      color: #16324b;
      border-radius: 999px;
      padding: 8px 12px;
      cursor: pointer;
      font-weight: 600;
      transition: transform .14s ease, box-shadow .14s ease, background .14s ease;
    }
    .acct-btn:hover { transform: translateY(-1px); box-shadow: 0 8px 18px rgba(19, 39, 67, 0.16); }
    .acct-box {
      position: absolute;
      right: 0;
      top: 42px;
      width: 320px;
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 10px;
      box-shadow: 0 14px 30px rgba(25, 38, 61, 0.22);
      opacity: 0;
      pointer-events: none;
      transform: translateY(-6px);
      transition: opacity .16s ease, transform .16s ease;
      z-index: 40;
      font-size: 13px;
    }
    .acct-wrap.open .acct-box {
      opacity: 1;
      pointer-events: auto;
      transform: translateY(0);
    }
    .acct-title { font-weight: 700; margin-bottom: 6px; }
    .acct-kv { display: grid; grid-template-columns: 110px 1fr; gap: 6px 8px; }
    .acct-k { color: var(--muted); }
    .toolbar {
      margin-top: 12px;
      background: color-mix(in srgb, var(--card) 92%, #f2f8ff 8%);
      border: 1px solid var(--border);
      border-radius: 14px;
      padding: 10px;
      display: grid;
      grid-template-columns: repeat(8, minmax(110px, 1fr));
      gap: 8px;
      align-items: end;
      box-shadow: 0 8px 22px rgba(18, 42, 76, 0.08);
    }
    .toolbar label { font-size: 12px; color: var(--muted); display: block; font-weight: 600; }
    select, input, button {
      width: 100%;
      margin-top: 5px;
      padding: 8px 10px;
      font-size: 14px;
      border-radius: 9px;
      border: 1px solid #c8d4e5;
      background: #fff;
      color: var(--ink);
    }
    button {
      border: 0;
      background: linear-gradient(135deg, #0f2035, #0f766e);
      color: #fff;
      cursor: pointer;
      font-weight: 600;
      transition: transform .14s ease, box-shadow .14s ease, filter .14s ease;
    }
    button:hover { transform: translateY(-1px); box-shadow: 0 9px 18px rgba(15, 32, 53, 0.24); filter: brightness(1.03); }
    .status {
      margin-top: 10px;
      display: flex;
      gap: 12px;
      flex-wrap: wrap;
      font-size: 13px;
      color: var(--muted);
    }
    .scope-hint {
      margin-top: 8px;
      display: none;
      align-items: center;
      gap: 8px;
      flex-wrap: wrap;
      background: color-mix(in srgb, #fff 90%, #f4faff 10%);
      border: 1px solid #cddcf0;
      border-radius: 10px;
      padding: 8px 10px;
      font-size: 13px;
      color: #314560;
    }
    .scope-hint.show { display: flex; }
    .scope-hint .label { font-weight: 600; }
    .scope-hint button {
      width: auto;
      margin-top: 0;
      padding: 5px 9px;
      font-size: 12px;
      border-radius: 8px;
      background: linear-gradient(140deg, #12324f, #0f766e);
    }
    .pill {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 999px;
      padding: 6px 10px;
    }
    .pill.ok { color: var(--ok); border-color: #9bd7c8; }
    .pill.bad { color: var(--bad); border-color: #efb8b8; }
    .layout {
      margin-top: 12px;
      display: grid;
      grid-template-columns: 300px 1fr;
      gap: 12px;
      min-height: 70vh;
    }
    .scope-panel {
      background: color-mix(in srgb, var(--card) 90%, #f2f8ff 10%);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 10px;
      display: flex;
      flex-direction: column;
      min-height: 400px;
      animation: fadeUp .28s ease both;
      box-shadow: 0 10px 26px rgba(18, 42, 76, 0.10);
    }
    .scope-head {
      display: grid;
      grid-template-columns: 1fr auto;
      gap: 8px;
      align-items: center;
      margin-bottom: 8px;
    }
    .scope-title {
      margin: 0;
      font-size: 13px;
      text-transform: uppercase;
      letter-spacing: .05em;
      color: var(--muted);
    }
    .scope-tree {
      overflow: auto;
      max-height: calc(100vh - 270px);
      border: 1px solid #e5ebf4;
      border-radius: 10px;
      padding: 6px;
      background: #fcfdff;
    }
    .scope-head button {
      width: auto;
      margin-top: 0;
      border: 1px solid #c6d8ec;
      background: linear-gradient(145deg, #12324f, #0f766e);
      padding: 6px 10px;
      font-size: 13px;
      border-radius: 9px;
    }
    .scope-head button:disabled {
      cursor: not-allowed;
      opacity: 0.55;
      transform: none;
      box-shadow: none;
      filter: grayscale(0.25);
    }
    .tree-node details { margin-left: 4px; }
    .tree-node summary { list-style: none; cursor: default; }
    .tree-node summary::-webkit-details-marker { display: none; }
    .tree-node summary::before {
      content: "▸";
      display: inline-block;
      width: 10px;
      margin-right: 6px;
      color: #5f728f;
      font-size: 11px;
      transform-origin: 45% 50%;
      transition: transform .12s ease;
      vertical-align: middle;
    }
    .tree-node details[open] > summary::before {
      transform: rotate(90deg);
    }
    .tree-line {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      margin: 2px 0;
    }
    .scope-btn {
      border: 0;
      background: transparent;
      color: #1f2a3f;
      text-align: left;
      padding: 4px 6px;
      border-radius: 6px;
      font-size: 13px;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      cursor: pointer;
    }
    .scope-btn:hover { background: #eef4fb; }
    .scope-btn.active { background: #dff1ee; color: #0c5d57; font-weight: 700; }
    .scope-total { color: #445770; font-size: 12px; white-space: nowrap; }
    .main {
      min-width: 0;
    }
    .cards {
      margin-top: 0;
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 10px;
    }
    .card {
      background: color-mix(in srgb, var(--card) 94%, #f1f7ff 6%);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 10px 12px;
      transition: transform .14s ease, box-shadow .14s ease;
      animation: fadeUp .26s ease both;
    }
    .card:hover { transform: translateY(-1px); box-shadow: 0 10px 18px rgba(25, 38, 61, 0.12); }
    .k { color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .05em; }
    .v {
      margin-top: 3px;
      font-size: 24px;
      font-weight: 700;
      letter-spacing: -0.01em;
      font-family: "JetBrains Mono", "IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, Monaco, monospace;
    }
    .grid {
      margin-top: 12px;
      display: grid;
      grid-template-columns: 1.7fr 1fr;
      gap: 12px;
    }
    .panel {
      background: color-mix(in srgb, var(--card) 94%, #f4f9ff 6%);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 10px;
      animation: fadeUp .32s ease both;
      box-shadow: 0 10px 24px rgba(17, 37, 64, 0.08);
    }
    .panel h2 {
      margin: 0 0 8px;
      font-size: 14px;
      text-transform: uppercase;
      letter-spacing: .05em;
      color: var(--muted);
    }
    .chart-wrap { position: relative; }
    canvas { width: 100%; height: 290px; display: block; cursor: crosshair; }
    .tip {
      position: absolute;
      left: 0;
      top: 0;
      opacity: 0;
      pointer-events: none;
      transform: translate(10px, -100%);
      background: #111827;
      color: #f9fafb;
      border-radius: 8px;
      padding: 6px 8px;
      font-size: 12px;
      line-height: 1.35;
      white-space: nowrap;
      box-shadow: 0 10px 26px rgba(0,0,0,.25);
      z-index: 10;
      transition: opacity .08s linear;
    }
    .live-wrap {
      margin-top: 10px;
      max-height: 420px;
      overflow: auto;
      border-radius: 10px;
      border: 1px solid var(--border);
    }
    table { width: 100%; border-collapse: collapse; font-size: 12px; }
    th, td { padding: 7px 8px; border-bottom: 1px solid #edf1f7; text-align: left; }
    th { position: sticky; top: 0; background: #f9fbff; z-index: 2; color: #4c5a73; }
    tr:nth-child(2n) { background: #fbfdff; }
    td.prompt {
      max-width: 520px;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .meta { margin-top: 8px; color: var(--muted); font-size: 12px; }

    @media (max-width: 1040px) {
      .toolbar { grid-template-columns: repeat(4, minmax(120px, 1fr)); }
      .layout { grid-template-columns: 1fr; }
      .scope-tree { max-height: 300px; }
      .grid { grid-template-columns: 1fr; }
    }
    @media (max-width: 680px) {
      .wrap { padding: 10px; }
      h1 { font-size: 24px; }
      .toolbar { grid-template-columns: repeat(2, minmax(120px, 1fr)); }
      canvas { height: 230px; }
      .acct-box { width: 280px; }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="topbar">
      <div>
        <h1>Claude Usage Monitor</h1>
        <div class="subtitle" id="subtitle">Live token consumption and prompt flow from Claude session logs</div>
      </div>
      <div class="acct-wrap" id="acctWrap">
        <button class="acct-btn" id="acctBtn">Account</button>
        <div class="acct-box" id="acctBox"></div>
      </div>
    </div>

    <div class="toolbar">
      <label>Range
        <select id="range">
          <option value="1h">Last 1h</option>
          <option value="30h" selected>Last 30h</option>
          <option value="3h">Last 3h</option>
          <option value="6h">Last 6h</option>
          <option value="12h">Last 12h</option>
          <option value="24h">Last 24h</option>
          <option value="48h">Last 48h</option>
          <option value="7d">Last 7d</option>
          <option value="14d">Last 14d</option>
          <option value="30d">Last 30d</option>
          <option value="all">All Time</option>
        </select>
      </label>

      <label>Bucket
        <select id="bucket">
          <option value="auto" selected>Auto</option>
          <option value="60">1m</option>
          <option value="300">5m</option>
          <option value="900">15m</option>
          <option value="3600">1h</option>
          <option value="21600">6h</option>
          <option value="86400">1d</option>
        </select>
      </label>

      <label>Graph Mode
        <select id="graphMode">
          <option value="single" selected>Single Metric</option>
          <option value="in_out">Stacked In vs Out</option>
          <option value="cached_non_cached">Stacked Cached vs Non-Cached</option>
          <option value="cache_parts">Stacked Cache Read vs Create</option>
        </select>
      </label>

      <label>Metric (Single)
        <select id="metric">
          <option value="billable" selected>billable</option>
          <option value="input">input</option>
          <option value="output">output</option>
          <option value="cache_read">cache_read</option>
          <option value="cache_create">cache_create</option>
          <option value="total_with_cache">total_with_cache</option>
        </select>
      </label>

      <label>Visualization
        <select id="viz">
          <option value="bar" selected>bar</option>
          <option value="line">line</option>
          <option value="area">area</option>
        </select>
      </label>

      <label>Live Window
        <select id="liveWindow">
          <option value="30m" selected>Last 30m</option>
          <option value="1h">Last 1h</option>
          <option value="3h">Last 3h</option>
          <option value="6h">Last 6h</option>
        </select>
      </label>

      <label>Jump To Timestamp
        <input id="focusTs" type="datetime-local" />
      </label>

      <div>
        <button id="refreshBtn">Refresh</button>
      </div>
    </div>

    <div class="status" id="statusRow"></div>
    <div class="scope-hint" id="scopeHint"></div>

    <div class="layout">
      <aside class="scope-panel">
        <div class="scope-head">
          <h2 class="scope-title">Directory Scope</h2>
          <div style="display:flex; gap:6px;">
            <button id="currentScopeBtn" type="button">Current</button>
            <button id="allScopeBtn" type="button">All</button>
          </div>
        </div>
        <label style="font-size:12px; color:var(--muted);">
          Search
          <input id="scopeSearch" type="text" placeholder="Filter directories or repos" />
        </label>
        <div class="scope-tree tree-node" id="scopeTree"></div>
      </aside>

      <main class="main">
        <div class="cards" id="cards"></div>

        <div class="grid">
          <div class="panel">
            <h2 id="mainTitle">Token Flow</h2>
            <div class="chart-wrap">
              <canvas id="mainChart" width="1100" height="320"></canvas>
              <div class="tip" id="mainTip"></div>
            </div>
            <div class="meta" id="mainMeta"></div>
          </div>

          <div class="panel">
            <h2>Daily Billable (Last 30 Days)</h2>
            <div class="chart-wrap">
              <canvas id="dailyChart" width="480" height="320"></canvas>
              <div class="tip" id="dailyTip"></div>
            </div>
            <div class="meta" id="dailyMeta"></div>
          </div>
        </div>

        <div class="panel" style="margin-top:12px;">
          <h2 id="liveTitle">Live Prompt Consumption</h2>
          <div class="live-wrap">
            <table>
              <thead>
                <tr>
                  <th>Time</th>
                  <th>Project</th>
                  <th>Prompt Preview</th>
                  <th>Input</th>
                  <th>Output</th>
                  <th>Billable</th>
                  <th>Cached</th>
                </tr>
              </thead>
              <tbody id="liveBody"></tbody>
            </table>
          </div>
          <div class="meta" id="liveMeta"></div>
        </div>
      </main>
    </div>
  </div>

<script>
(() => {
  const state = {
    projects: [],
    events: [],
    liveEvents: [],
    syncStatus: null,
    account: null,
    uiContext: null,
    scopeHydrated: false,
    scope: { kind: 'all', value: '__all__' },
    treeOpenPaths: new Set(),
    projectBySlug: new Map(),
    focusEpoch: null,
    chartStore: new Map(),
  };

  const rangeEl = document.getElementById('range');
  const bucketEl = document.getElementById('bucket');
  const metricEl = document.getElementById('metric');
  const graphModeEl = document.getElementById('graphMode');
  const vizEl = document.getElementById('viz');
  const liveWindowEl = document.getElementById('liveWindow');
  const focusEl = document.getElementById('focusTs');
  const statusRowEl = document.getElementById('statusRow');
  const scopeHintEl = document.getElementById('scopeHint');
  const subtitleEl = document.getElementById('subtitle');
  const scopeTreeEl = document.getElementById('scopeTree');
  const scopeSearchEl = document.getElementById('scopeSearch');
  const currentScopeBtnEl = document.getElementById('currentScopeBtn');
  const allScopeBtnEl = document.getElementById('allScopeBtn');
  const liveBodyEl = document.getElementById('liveBody');
  const liveMetaEl = document.getElementById('liveMeta');
  const liveTitleEl = document.getElementById('liveTitle');
  const cardsEl = document.getElementById('cards');
  const mainMetaEl = document.getElementById('mainMeta');
  const dailyMetaEl = document.getElementById('dailyMeta');
  const mainTitleEl = document.getElementById('mainTitle');
  const acctWrapEl = document.getElementById('acctWrap');
  const acctBoxEl = document.getElementById('acctBox');
  const acctBtnEl = document.getElementById('acctBtn');

  const rangeToSec = {
    '1h': 3600,
    '3h': 10800,
    '6h': 21600,
    '12h': 43200,
    '24h': 86400,
    '30h': 108000,
    '48h': 172800,
    '7d': 604800,
    '14d': 1209600,
    '30d': 2592000,
    'all': 0,
  };
  const liveWindowToSec = {
    '30m': 1800,
    '1h': 3600,
    '3h': 10800,
    '6h': 21600,
  };
  const SCOPE_STORAGE_KEY = 'claude-usage.scope.v1';

  function fmt(n) {
    return Number(n || 0).toLocaleString();
  }

  function fmtShort(n) {
    const v = Number(n || 0);
    if (Math.abs(v) >= 1_000_000) return `${(v / 1_000_000).toFixed(2)}M`;
    if (Math.abs(v) >= 1_000) return `${(v / 1_000).toFixed(1)}k`;
    return v.toLocaleString();
  }
  function esc(s) {
    return String(s || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }
  function localTime(iso) {
    if (!iso) return '-';
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return iso;
    return d.toLocaleString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
  }
  function normalizePath(path) {
    if (!path) return '/';
    if (path === '/') return '/';
    return path.replace(/\/+$/, '') || '/';
  }
  function uiContextPath() {
    if (!state.uiContext || !state.uiContext.cwd) return null;
    return normalizePath(String(state.uiContext.cwd));
  }
  function scopePathExists(path) {
    const normalized = normalizePath(path);
    return state.projects.some((p) => {
      const projectPath = normalizePath(p.path || '');
      return projectPath === normalized || projectPath.startsWith(normalized + '/');
    });
  }
  function nearestScopePath(path) {
    const candidate = normalizePath(path);
    if (candidate === '/') return '/';
    let cur = candidate;
    while (cur && cur !== '/') {
      if (scopePathExists(cur)) {
        return cur;
      }
      const idx = cur.lastIndexOf('/');
      if (idx <= 0) break;
      cur = cur.slice(0, idx);
    }
    return '/';
  }
  function pathAncestors(path) {
    const list = [];
    let cur = normalizePath(path);
    while (cur && cur !== '/') {
      list.push(cur);
      const idx = cur.lastIndexOf('/');
      if (idx <= 0) break;
      cur = cur.slice(0, idx);
    }
    return list.reverse();
  }
  function ensurePathExpanded(path) {
    pathAncestors(path).forEach((ancestorPath) => state.treeOpenPaths.add(ancestorPath));
  }
  function persistScope() {
    try {
      localStorage.setItem(SCOPE_STORAGE_KEY, JSON.stringify(state.scope));
    } catch (_) {
      // ignore storage failures
    }
  }
  function loadPersistedScope() {
    try {
      const raw = localStorage.getItem(SCOPE_STORAGE_KEY);
      if (!raw) return null;
      const parsed = JSON.parse(raw);
      if (!parsed || typeof parsed !== 'object') return null;
      if (!parsed.kind || typeof parsed.value !== 'string') return null;
      return parsed;
    } catch (_) {
      return null;
    }
  }
  function setScope(nextScope, opts = {}) {
    if (!nextScope || typeof nextScope !== 'object') return;
    const persist = opts.persist !== false;
    const rerender = opts.rerender !== false;
    const kind = nextScope.kind || 'all';
    const value = (kind === 'path') ? normalizePath(nextScope.value || '/') : (nextScope.value || '__all__');
    state.scope = { kind, value };
    if (kind === 'path') {
      ensurePathExpanded(value);
    }
    if (persist) persistScope();
    if (rerender) render(null);
  }
  function hydrateScopeSelection() {
    if (state.scopeHydrated) return;
    state.scopeHydrated = true;

    const saved = loadPersistedScope();
    if (saved) {
      setScope(saved, { persist: false, rerender: false });
    }

    if (state.scope.kind === 'path' && !scopePathExists(state.scope.value)) {
      state.scope = { kind: 'all', value: '__all__' };
    }

    if (state.scope.kind === 'all') {
      const contextPath = uiContextPath();
      if (contextPath) {
        const nearest = nearestScopePath(contextPath);
        if (nearest !== '/') {
          setScope({ kind: 'path', value: nearest }, { persist: false, rerender: false });
        }
      }
    }
  }
  function setScopeToCurrent() {
    const contextPath = uiContextPath();
    if (!contextPath) return;
    setScope({ kind: 'path', value: nearestScopePath(contextPath) });
  }

  function projectRepo(project) {
    const path = project.path || project.slug;
    const parts = path.split('/').filter(Boolean);
    return parts[parts.length - 1] || project.slug;
  }

  function parseEventsTSV(text) {
    const lines = text.trim().split(/\r?\n/);
    if (lines.length <= 1) return [];
    return lines.slice(1).map((line) => {
      const p = line.split('\t');
      if (p.length < 12) return null;
      return {
        ts_epoch: Number(p[0] || 0),
        ts_iso: p[1] || '',
        project_slug: p[2] || '',
        session_id: p[3] || '',
        input: Number(p[4] || 0),
        output: Number(p[5] || 0),
        cache_read: Number(p[6] || 0),
        cache_create: Number(p[7] || 0),
        billable: Number(p[8] || 0),
        total_with_cache: Number(p[9] || 0),
        content_type: p[10] || '-',
        signature: p[11] || '',
      };
    }).filter(Boolean);
  }
  function parseLiveTSV(text) {
    const lines = text.trim().split(/\r?\n/);
    if (lines.length <= 1) return [];
    return lines.slice(1).map((line) => {
      const p = line.split('\t');
      if (p.length < 13) return null;
      return {
        ts_epoch: Number(p[0] || 0),
        ts_iso: p[1] || '',
        project_slug: p[2] || '',
        session_id: p[3] || '',
        prompt_preview: p[4] || '-',
        input: Number(p[5] || 0),
        output: Number(p[6] || 0),
        cache_read: Number(p[7] || 0),
        cache_create: Number(p[8] || 0),
        billable: Number(p[9] || 0),
        total_with_cache: Number(p[10] || 0),
        content_type: p[11] || '-',
        signature: p[12] || '',
      };
    }).filter(Boolean);
  }

  async function fetchJson(path) {
    try {
      const r = await fetch(`${path}?_=${Date.now()}`, { cache: 'no-store' });
      if (!r.ok) return null;
      return await r.json();
    } catch (_) {
      return null;
    }
  }
  async function loadText(path) {
    try {
      const r = await fetch(`${path}?_=${Date.now()}`, { cache: 'no-store' });
      if (!r.ok) return '';
      return await r.text();
    } catch (_) {
      return '';
    }
  }

  async function loadHeartbeat() {
    try {
      const r = await fetch(`/heartbeat/sync.txt?_=${Date.now()}`, { cache: 'no-store' });
      if (!r.ok) return null;
      const txt = (await r.text()).trim();
      const [epochS, intervalS, pidS, statusS] = txt.split(',');
      return {
        epoch: Number(epochS || 0),
        interval: Number(intervalS || 0),
        pid: pidS || '-',
        status: statusS || '-',
      };
    } catch (_) {
      return null;
    }
  }

  function scopeIncludesSlug(slug) {
    if (state.scope.kind === 'all') return true;
    if (state.scope.kind === 'slug') return slug === state.scope.value;
    if (state.scope.kind === 'path') {
      const p = state.projectBySlug.get(slug);
      if (!p || !p.path) return false;
      const projectPath = normalizePath(p.path);
      const basePath = normalizePath(state.scope.value);
      return projectPath === basePath || projectPath.startsWith(basePath + '/');
    }
    return true;
  }
  function scopedEvents(arr) {
    return (arr || []).filter((x) => scopeIncludesSlug(x.project_slug));
  }
  function filterByRange(events) {
    const sec = rangeToSec[rangeEl.value] ?? 108000;
    if (!sec || sec <= 0) return events;
    const cutoff = Math.floor(Date.now() / 1000) - sec;
    return events.filter((e) => e.ts_epoch >= cutoff);
  }
  function filterByLiveWindow(rows) {
    const sec = liveWindowToSec[liveWindowEl.value] ?? 1800;
    const cutoff = Math.floor(Date.now() / 1000) - sec;
    return rows.filter((e) => e.ts_epoch >= cutoff);
  }

  function buildTree(projects) {
    const root = { name: '/', path: '/', children: new Map(), slugs: [] };
    projects.forEach((p) => {
      const parts = (p.path || '').split('/').filter(Boolean);
      let node = root;
      let cur = '';
      parts.forEach((part) => {
        cur += `/${part}`;
        if (!node.children.has(part)) {
          node.children.set(part, { name: part, path: cur, children: new Map(), slugs: [] });
        }
        node = node.children.get(part);
        node.slugs.push(p.slug);
      });
    });
    return root;
  }
  function nodeTotal(node, slugTotals) {
    return (node.slugs || []).reduce((acc, slug) => acc + Number(slugTotals.get(slug) || 0), 0);
  }
  function renderTree(root, slugTotals) {
    // Preserve open folders across refreshes/re-renders.
    scopeTreeEl.querySelectorAll('details[data-path][open]').forEach((el) => {
      if (el.dataset.path) state.treeOpenPaths.add(el.dataset.path);
    });
    if (state.scope.kind === 'path') {
      ensurePathExpanded(state.scope.value);
    }

    const q = (scopeSearchEl.value || '').trim().toLowerCase();
    function walk(node, depth) {
      const path = normalizePath(node.path);
      const kids = [...node.children.values()].sort((a, b) => a.name.localeCompare(b.name));
      const childHtml = kids.map((k) => walk(k, depth + 1)).join('');
      const total = nodeTotal(node, slugTotals);
      const selfMatch = !q || path.toLowerCase().includes(q) || node.name.toLowerCase().includes(q);
      if (!selfMatch && !childHtml) return '';
      const active = (state.scope.kind === 'path' && state.scope.value === path) ? 'active' : '';
      const hasChildren = kids.length > 0;
      if (!hasChildren) {
        return `
          <div class="tree-line">
            <button type="button" class="scope-btn ${active}" data-scope-kind="path" data-scope-value="${esc(path)}" title="${esc(path)}">${esc(node.name)}</button>
            <span class="scope-total">${fmtShort(total)}</span>
          </div>
        `;
      }

      const isAncestorOfSelected = state.scope.kind === 'path' && state.scope.value.startsWith(path + '/');
      const shouldOpen = state.treeOpenPaths.has(path) || depth < 1 || isAncestorOfSelected || (q && (selfMatch || childHtml));
      return `
        <details data-path="${esc(path)}" ${shouldOpen ? 'open' : ''}>
          <summary>
            <div class="tree-line">
              <button type="button" class="scope-btn ${active}" data-scope-kind="path" data-scope-value="${esc(path)}" title="${esc(path)}">${esc(node.name)}</button>
              <span class="scope-total">${fmtShort(total)}</span>
            </div>
          </summary>
          ${childHtml}
        </details>
      `;
    }
    const html = [...root.children.values()].sort((a, b) => a.name.localeCompare(b.name)).map((n) => walk(n, 0)).join('');
    scopeTreeEl.innerHTML = html || '<div class="meta">No matching directories.</div>';
    scopeTreeEl.querySelectorAll('details[data-path]').forEach((detailsEl) => {
      detailsEl.addEventListener('toggle', () => {
        const path = detailsEl.dataset.path || '';
        if (!path) return;
        if (detailsEl.open) state.treeOpenPaths.add(path);
        else state.treeOpenPaths.delete(path);
      });
    });
  }
  function renderAccountBox() {
    const a = state.account || {};
    const has = Object.keys(a).length > 0;
    if (!has) {
      acctBoxEl.innerHTML = '<div class="acct-title">Account</div><div class="meta">No local account metadata found.</div>';
      return;
    }
    const rows = [
      ['name', a.display_name || '-'],
      ['email', a.email || '-'],
      ['billing', a.billing_type || '-'],
      ['org', a.organization_uuid || '-'],
      ['extra usage', String(a.has_extra_usage_enabled ?? '-')],
      ['subscribed', String(a.has_available_subscription ?? '-')],
    ];
    acctBoxEl.innerHTML = `
      <div class="acct-title">Claude Account</div>
      <div class="acct-kv">
        ${rows.map(([k, v]) => `<div class="acct-k">${esc(k)}</div><div>${esc(v)}</div>`).join('')}
      </div>
    `;
  }

  function autoBucketSec(rangeSec) {
    if (!rangeSec || rangeSec <= 0) return 3600;
    if (rangeSec <= 3 * 3600) return 60;
    if (rangeSec <= 12 * 3600) return 300;
    if (rangeSec <= 48 * 3600) return 900;
    if (rangeSec <= 7 * 86400) return 3600;
    if (rangeSec <= 30 * 86400) return 21600;
    return 86400;
  }

  function selectedBucketSec() {
    if (bucketEl.value !== 'auto') return Number(bucketEl.value || 900);
    const sec = rangeToSec[rangeEl.value] ?? 108000;
    return autoBucketSec(sec);
  }
  function bucketize(events, bucketSec) {
    const map = new Map();
    events.forEach((e) => {
      const b = Math.floor(e.ts_epoch / bucketSec) * bucketSec;
      let row = map.get(b);
      if (!row) {
        row = {
          epoch: b,
          count: 0,
          input: 0,
          output: 0,
          cache_read: 0,
          cache_create: 0,
          billable: 0,
          total_with_cache: 0,
          value: 0,
        };
        map.set(b, row);
      }
      row.count += 1;
      row.input += Number(e.input || 0);
      row.output += Number(e.output || 0);
      row.cache_read += Number(e.cache_read || 0);
      row.cache_create += Number(e.cache_create || 0);
      row.billable += Number(e.billable || 0);
      row.total_with_cache += Number(e.total_with_cache || 0);
    });
    return [...map.values()]
      .sort((a, b) => a.epoch - b.epoch)
      .map((row) => ({ ...row }));
  }

  function formatBucketLabel(epoch, bucketSec) {
    const d = new Date(epoch * 1000);
    if (bucketSec >= 86400) {
      return d.toLocaleDateString([], { month: 'short', day: 'numeric' });
    }
    if (bucketSec >= 3600) {
      return d.toLocaleString([], { month: 'short', day: 'numeric', hour: '2-digit' });
    }
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }
  function chartSeries(mode, metric) {
    if (mode === 'in_out') {
      return { stacked: true, label: 'Input vs Output', series: [
        { key: 'input', label: 'input', color: '#0f766e', value: (p) => p.input },
        { key: 'output', label: 'output', color: '#c2410c', value: (p) => p.output },
      ]};
    }
    if (mode === 'cached_non_cached') {
      return { stacked: true, label: 'Cached vs Non-Cached', series: [
        { key: 'non_cached', label: 'non_cached(billable)', color: '#0f766e', value: (p) => p.billable },
        { key: 'cached', label: 'cached(read+create)', color: '#1d4ed8', value: (p) => (p.cache_read + p.cache_create) },
      ]};
    }
    if (mode === 'cache_parts') {
      return { stacked: true, label: 'Cache Read vs Create', series: [
        { key: 'cache_read', label: 'cache_read', color: '#1d4ed8', value: (p) => p.cache_read },
        { key: 'cache_create', label: 'cache_create', color: '#7c3aed', value: (p) => p.cache_create },
      ]};
    }
    return { stacked: false, label: metric, series: [
      { key: metric, label: metric, color: '#c2410c', value: (p) => Number(p[metric] || 0) },
    ]};
  }
  function drawChart(chartId, tipId, points, opts) {
    const canvas = document.getElementById(chartId);
    const tip = document.getElementById(tipId);
    const ctx = canvas.getContext('2d');
    const w = canvas.width;
    const h = canvas.height;
    const padL = 56;
    const padR = 14;
    const padT = 12;
    const padB = 34;

    ctx.clearRect(0, 0, w, h);

    const effectiveViz = (opts.viz === 'area' && opts.series.length > 1) ? 'line' : opts.viz;
    const values = points.map((p) => {
      const vals = opts.series.map((s) => Number(s.value(p) || 0));
      p.__vals = vals;
      p.__sum = vals.reduce((a, v) => a + v, 0);
      return opts.stacked ? p.__sum : Math.max(...vals, 0);
    });
    const min = 0;
    const maxRaw = Math.max(...values, 1);
    const max = maxRaw <= min ? min + 1 : maxRaw;

    const plotW = Math.max(1, w - padL - padR);
    const plotH = Math.max(1, h - padT - padB);

    const x = (i) => padL + (i * plotW / Math.max(1, points.length - 1));
    const y = (v) => h - padB - ((v - min) * plotH / (max - min));

    ctx.strokeStyle = '#e5e7eb';
    ctx.lineWidth = 1;
    for (let i = 0; i <= 4; i++) {
      const yy = padT + ((plotH * i) / 4);
      ctx.beginPath();
      ctx.moveTo(padL, yy);
      ctx.lineTo(w - padR, yy);
      ctx.stroke();
    }

    if (effectiveViz === 'bar') {
      const bw = Math.max(2, plotW / Math.max(1, points.length) * 0.78);
      points.forEach((p, i) => {
        const xx = x(i) - (bw / 2);
        if (opts.stacked) {
          let acc = 0;
          opts.series.forEach((s, j) => {
            const v = p.__vals[j];
            const yTop = y(acc + v);
            const yBottom = y(acc);
            ctx.fillStyle = s.color;
            ctx.fillRect(xx, yTop, bw, Math.max(1, yBottom - yTop));
            acc += v;
          });
        } else {
          const groupW = bw / Math.max(1, opts.series.length);
          opts.series.forEach((s, j) => {
            const v = p.__vals[j];
            const yy = y(v);
            ctx.fillStyle = s.color;
            ctx.fillRect(xx + (j * groupW), yy, Math.max(1, groupW - 1), Math.max(1, h - padB - yy));
          });
        }
      });
    } else {
      opts.series.forEach((s, j) => {
        if (effectiveViz === 'area' && opts.series.length === 1) {
          ctx.fillStyle = 'rgba(194, 65, 12, 0.20)';
          ctx.beginPath();
          points.forEach((p, i) => {
            const xx = x(i);
            const yy = y(p.__vals[j]);
            if (i === 0) ctx.moveTo(xx, yy);
            else ctx.lineTo(xx, yy);
          });
          ctx.lineTo(x(points.length - 1), h - padB);
          ctx.lineTo(x(0), h - padB);
          ctx.closePath();
          ctx.fill();
        }
        ctx.strokeStyle = s.color;
        ctx.lineWidth = 2;
        ctx.beginPath();
        points.forEach((p, i) => {
          const xx = x(i);
          const yy = y(opts.stacked ? p.__sum : p.__vals[j]);
          if (i === 0) ctx.moveTo(xx, yy);
          else ctx.lineTo(xx, yy);
        });
        ctx.stroke();
      });
    }

    if (opts.focusEpoch) {
      let nearest = null;
      let dist = Infinity;
      points.forEach((p, i) => {
        const d = Math.abs(p.epoch - opts.focusEpoch);
        if (d < dist) {
          dist = d;
          nearest = { i, p };
        }
      });
      if (nearest) {
        const xx = x(nearest.i);
        ctx.strokeStyle = '#1d4ed8';
        ctx.lineWidth = 1;
        ctx.setLineDash([4, 4]);
        ctx.beginPath();
        ctx.moveTo(xx, padT);
        ctx.lineTo(xx, h - padB);
        ctx.stroke();
        ctx.setLineDash([]);
      }
    }

    ctx.fillStyle = '#4b5563';
    ctx.font = '11px sans-serif';
    ctx.fillText(`max ${fmtShort(max)}`, 6, padT + 8);
    const latestVal = opts.stacked ? (points[points.length - 1]?.__sum || 0) : Math.max(...(points[points.length - 1]?.__vals || [0]));
    ctx.fillText(`latest ${fmtShort(latestVal)}`, w - 165, padT + 8);
    if (points.length > 1) {
      ctx.fillText(formatBucketLabel(points[0].epoch, opts.bucketSec), padL, h - 8);
      ctx.fillText(formatBucketLabel(points[Math.floor(points.length / 2)].epoch, opts.bucketSec), Math.max(padL + 120, Math.floor(w / 2) - 50), h - 8);
      ctx.fillText(formatBucketLabel(points[points.length - 1].epoch, opts.bucketSec), w - 130, h - 8);
    }

    state.chartStore.set(chartId, { canvas, tip, points, opts, x, y, padL, padR, padT, padB });
  }

  function bindChartHover(chartId) {
    const canvas = document.getElementById(chartId);
    if (canvas.dataset.bound === '1') return;
    canvas.dataset.bound = '1';

    canvas.addEventListener('mousemove', (event) => {
      const st = state.chartStore.get(chartId);
      if (!st || !st.points.length) return;
      const rect = canvas.getBoundingClientRect();
      const px = event.clientX - rect.left;
      const py = event.clientY - rect.top;
      const mx = px * (canvas.width / rect.width);
      const range = Math.max(1, canvas.width - st.padL - st.padR);
      const idxRaw = ((mx - st.padL) * Math.max(1, st.points.length - 1)) / range;
      const idx = Math.max(0, Math.min(st.points.length - 1, Math.round(idxRaw)));
      const pt = st.points[idx];

      const lines = st.opts.series.map((s, i) => `${esc(s.label)}: ${fmt(pt.__vals[i] || 0)}`).join('<br>');
      const totalLine = st.opts.stacked ? `<br>total: ${fmt(pt.__sum || 0)}` : '';
      st.tip.innerHTML = `${esc(st.opts.tipLabel)}<br>${esc(formatBucketLabel(pt.epoch, st.opts.bucketSec))}<br>${lines}${totalLine}<br>prompts: ${fmt(pt.count)}`;
      st.tip.style.left = `${Math.max(8, Math.min(rect.width - 8, px))}px`;
      st.tip.style.top = `${Math.max(18, py)}px`;
      st.tip.style.opacity = '1';
    });

    canvas.addEventListener('mouseleave', () => {
      const st = state.chartStore.get(chartId);
      if (!st) return;
      st.tip.style.opacity = '0';
    });
  }

  function renderStatus(syncHeartbeat) {
    const pills = [];
    const now = Math.floor(Date.now() / 1000);

    if (syncHeartbeat && syncHeartbeat.epoch) {
      const age = now - syncHeartbeat.epoch;
      const healthy = syncHeartbeat.interval > 0 ? age <= Math.max(300, syncHeartbeat.interval * 12) : false;
      const raw = (syncHeartbeat.status || '').toLowerCase();
      const stateLabel = (raw === 'ok') ? 'running' : (raw === 'working' ? 'syncing' : (healthy ? 'running' : 'stale'));
      pills.push(`<span class="pill ${healthy ? 'ok' : 'bad'}">Sync: ${stateLabel} (pid ${syncHeartbeat.pid}, age ${age}s)</span>`);
    } else {
      pills.push('<span class="pill bad">Sync: no heartbeat</span>');
    }

    if (state.syncStatus) {
      pills.push(`<span class="pill">Last sync: ${state.syncStatus.last_sync_iso || '-'}</span>`);
      pills.push(`<span class="pill">Projects: ${fmt(state.projects.length)}</span>`);
      pills.push(`<span class="pill">Rows: ${fmt(state.syncStatus.live_event_rows || state.syncStatus.event_rows || 0)}</span>`);
    }

    statusRowEl.innerHTML = pills.join('');
  }
  function latestEpoch(events) {
    if (!events || !events.length) return null;
    let max = 0;
    events.forEach((e) => {
      const ts = Number(e.ts_epoch || 0);
      if (ts > max) max = ts;
    });
    return max || null;
  }
  function scopeHintHtml(message, actions) {
    const btns = (actions || []).map((a) => `<button type="button" data-action="${esc(a.action)}">${esc(a.label)}</button>`).join('');
    return `<span class="label">${esc(message)}</span>${btns}`;
  }
  function renderScopeHint(scoped, ranged) {
    scopeHintEl.classList.remove('show');
    scopeHintEl.innerHTML = '';

    if (state.scope.kind === 'all') return;

    const hasAnyScoped = (scoped || []).length > 0;
    const latestScopedEpoch = latestEpoch(scoped);
    if (!hasAnyScoped) {
      scopeHintEl.innerHTML = scopeHintHtml(
        'No usage found for this directory scope yet.',
        [
          { action: 'scope-all', label: 'Show All Projects' },
          { action: 'scope-current', label: 'Jump To Current' },
        ]
      );
      scopeHintEl.classList.add('show');
      return;
    }

    if ((ranged || []).length === 0 && rangeEl.value !== 'all') {
      const latestIso = latestScopedEpoch ? new Date(latestScopedEpoch * 1000).toLocaleString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }) : '-';
      scopeHintEl.innerHTML = scopeHintHtml(
        `No usage in ${rangeEl.options[rangeEl.selectedIndex]?.text || rangeEl.value} for this scope (latest ${latestIso}).`,
        [
          { action: 'range-7d', label: 'Set Range 7d' },
          { action: 'range-all', label: 'Set Range All Time' },
          { action: 'scope-all', label: 'Show All Projects' },
        ]
      );
      scopeHintEl.classList.add('show');
    }
  }

  function renderCards(scoped, ranged, liveRows) {
    const sum = (arr, key) => arr.reduce((acc, x) => acc + Number(x[key] || 0), 0);
    const now = Math.floor(Date.now() / 1000);
    const inWindow = (arr, sec) => arr.filter((x) => x.ts_epoch >= (now - sec));

    const totalBillable = sum(ranged, 'billable');
    const billable30m = sum(inWindow(scoped, 1800), 'billable');
    const billable1h = sum(inWindow(scoped, 3600), 'billable');
    const prompts1h = inWindow(liveRows, 3600).length;
    const latestEpoch = ranged.length ? ranged[ranged.length - 1].ts_epoch : null;
    const latestAgeSec = latestEpoch ? Math.max(0, now - latestEpoch) : null;
    const latestAgeLabel = latestAgeSec == null ? '-' : (latestAgeSec < 120 ? `${latestAgeSec}s` : `${Math.round(latestAgeSec / 60)}m`);
    const io1hIn = sum(inWindow(scoped, 3600), 'input');
    const io1hOut = sum(inWindow(scoped, 3600), 'output');
    const cacheAmplification = totalBillable > 0 ? ((sum(ranged, 'cache_read') + sum(ranged, 'cache_create')) / totalBillable) : 0;
    const cacheAmplificationLabel = Number.isFinite(cacheAmplification) ? `${cacheAmplification.toFixed(1)}x` : '-';
    const burnRate30m = billable30m * 2;

    const rows = [
      ['billable (range)', totalBillable],
      ['billable (last 30m)', billable30m],
      ['billable (last 1h)', billable1h],
      ['burn rate / hr', burnRate30m],
      ['in/out (last 1h)', `${fmt(io1hIn)} / ${fmt(io1hOut)}`],
      ['prompts (last 1h)', prompts1h],
      ['cache / non-cache', cacheAmplificationLabel],
      ['latest event age', latestAgeLabel],
    ];

    const cardValue = (v) => (typeof v === 'number' ? fmt(v) : String(v));
    cardsEl.innerHTML = rows.map(([k, v]) => `
      <div class="card">
        <div class="k">${k}</div>
        <div class="v">${cardValue(v)}</div>
      </div>
    `).join('');
  }

  function renderMainChart(ranged, metric, bucketSec, viz, mode) {
    const points = bucketize(ranged, bucketSec);
    const config = chartSeries(mode, metric);
    mainTitleEl.textContent = `Token Flow (${config.label}, ${viz}, ${bucketSec}s)`;

    if (!points.length) {
      drawChart('mainChart', 'mainTip', [{ epoch: Math.floor(Date.now() / 1000), value: 0 }], {
        viz,
        series: [{ key: 'none', label: 'none', color: '#0f766e', value: () => 0 }],
        stacked: false,
        tipLabel: 'No data',
        bucketSec,
        focusEpoch: state.focusEpoch,
      });
      mainMetaEl.textContent = 'No usage in selected scope/range.';
      return;
    }

    const totals = config.series.map((s) => points.reduce((acc, p) => acc + Number(s.value(p) || 0), 0));
    drawChart('mainChart', 'mainTip', points, {
      viz,
      series: config.series,
      stacked: config.stacked,
      tipLabel: 'Bucket',
      bucketSec,
      focusEpoch: state.focusEpoch,
    });
    const totalLabel = config.series.map((s, i) => `${s.label}=${fmt(totals[i])}`).join(' | ');
    mainMetaEl.textContent = `buckets=${points.length} ${totalLabel} latest=${formatBucketLabel(points[points.length - 1].epoch, bucketSec)}`;
  }

  function renderDailyChart(scoped) {
    const now = Math.floor(Date.now() / 1000);
    const cutoff = now - (30 * 86400);
    const recent = scoped.filter((e) => e.ts_epoch >= cutoff);
    const points = bucketize(recent, 86400);
    const cfg = chartSeries('single', 'billable');

    if (!points.length) {
      drawChart('dailyChart', 'dailyTip', [{ epoch: now, value: 0 }], {
        viz: 'bar',
        series: [{ key: 'none', label: 'none', color: '#1d4ed8', value: () => 0 }],
        stacked: false,
        tipLabel: 'Day',
        bucketSec: 86400,
        focusEpoch: state.focusEpoch,
      });
      dailyMetaEl.textContent = 'No billable events in last 30 days.';
      return;
    }

    drawChart('dailyChart', 'dailyTip', points, {
      viz: 'bar',
      series: [{ ...cfg.series[0], color: '#1d4ed8' }],
      stacked: false,
      tipLabel: 'Day',
      bucketSec: 86400,
      focusEpoch: state.focusEpoch,
    });

    const total = points.reduce((a, p) => a + p.billable, 0);
    dailyMetaEl.textContent = `days=${points.length} total_billable=${fmt(total)}`;
  }

  function renderLiveTable(rows) {
    const sorted = [...rows].sort((a, b) => b.ts_epoch - a.ts_epoch).slice(0, 80);
    const bySlug = new Map(state.projects.map((p) => [p.slug, p]));
    liveBodyEl.innerHTML = sorted.map((e) => {
      const p = bySlug.get(e.project_slug);
      const label = p ? projectRepo(p) : e.project_slug;
      const prompt = e.prompt_preview || '-';
      const cached = Number(e.cache_read || 0) + Number(e.cache_create || 0);
      return `
        <tr>
          <td>${esc(localTime(e.ts_iso || ''))}</td>
          <td>${label}</td>
          <td class="prompt" title="${esc(prompt)}">${esc(prompt)}</td>
          <td>${fmt(e.input)}</td>
          <td>${fmt(e.output)}</td>
          <td>${fmt(e.billable)}</td>
          <td>${fmt(cached)}</td>
        </tr>
      `;
    }).join('');
    liveTitleEl.textContent = `Live Prompt Consumption (${liveWindowEl.value})`;
    liveMetaEl.textContent = `rows_shown=${sorted.length} | scope=${state.scope.kind === 'all' ? 'all projects' : state.scope.value}`;
  }

  function parseFocusInput() {
    const v = focusEl.value;
    if (!v) {
      state.focusEpoch = null;
      return;
    }
    const t = new Date(v).getTime();
    state.focusEpoch = Number.isFinite(t) ? Math.floor(t / 1000) : null;
  }
  function renderCurrentScopeButton() {
    const contextPath = uiContextPath();
    if (!contextPath) {
      currentScopeBtnEl.disabled = true;
      currentScopeBtnEl.textContent = 'Current';
      currentScopeBtnEl.title = 'No launch directory detected.';
      return;
    }
    const label = contextPath.split('/').filter(Boolean).pop() || contextPath;
    currentScopeBtnEl.disabled = false;
    currentScopeBtnEl.textContent = `Current: ${label}`;
    currentScopeBtnEl.title = `Jump to ${contextPath}`;
  }

  function render(syncHeartbeat) {
    hydrateScopeSelection();
    if (state.scope.kind === 'path' && !scopePathExists(state.scope.value)) {
      state.scope = { kind: 'all', value: '__all__' };
    }
    const scoped = scopedEvents(state.events);
    const scopedLive = scopedEvents(state.liveEvents);
    const ranged = filterByRange(scoped).sort((a, b) => a.ts_epoch - b.ts_epoch);
    const liveRows = filterByLiveWindow(scopedLive).sort((a, b) => a.ts_epoch - b.ts_epoch);
    const rangeScopedAll = filterByRange(state.events);
    const slugTotals = new Map();
    rangeScopedAll.forEach((e) => {
      slugTotals.set(e.project_slug, (slugTotals.get(e.project_slug) || 0) + Number(e.billable || 0));
    });
    const metric = metricEl.value;
    const viz = vizEl.value;
    const mode = graphModeEl.value;
    const bucketSec = selectedBucketSec();
    const contextPath = uiContextPath();

    subtitleEl.textContent = state.scope.kind === 'all'
      ? (contextPath ? `Scope: all projects (launch: ${contextPath})` : 'Live token consumption and prompt flow from Claude session logs')
      : `Scope: ${state.scope.value}`;
    renderCurrentScopeButton();
    renderStatus(syncHeartbeat);
    renderScopeHint(scoped, ranged);
    renderCards(scoped, ranged, scopedLive);
    renderMainChart(ranged, metric, bucketSec, viz, mode);
    renderDailyChart(scoped);
    renderLiveTable(liveRows);
    renderTree(buildTree(state.projects), slugTotals);
    renderAccountBox();
  }

  async function refresh() {
    const [projects, eventsTxt, liveTxt, syncStatus, heartbeat, account, uiContext] = await Promise.all([
      fetchJson('/projects.json'),
      loadText('/events.tsv'),
      loadText('/live-events.tsv'),
      fetchJson('/sync-status.json'),
      loadHeartbeat(),
      fetchJson('/account.json'),
      fetchJson('/ui-context.json'),
    ]);

    state.projects = Array.isArray(projects) ? projects.filter((x) => x && x.slug) : [];
    state.projectBySlug = new Map(state.projects.map((p) => [p.slug, p]));
    state.events = eventsTxt.trim() ? parseEventsTSV(eventsTxt) : [];
    state.liveEvents = liveTxt.trim() ? parseLiveTSV(liveTxt) : [];
    state.syncStatus = syncStatus;
    state.account = account || {};
    state.uiContext = uiContext || null;
    render(heartbeat);
  }

  document.getElementById('refreshBtn').addEventListener('click', async () => {
    parseFocusInput();
    await refresh();
  });

  rangeEl.addEventListener('change', () => {
    parseFocusInput();
    render(null);
  });
  bucketEl.addEventListener('change', () => { parseFocusInput(); render(null); });
  metricEl.addEventListener('change', () => { parseFocusInput(); render(null); });
  graphModeEl.addEventListener('change', () => { parseFocusInput(); render(null); });
  vizEl.addEventListener('change', () => { parseFocusInput(); render(null); });
  liveWindowEl.addEventListener('change', () => { parseFocusInput(); render(null); });
  focusEl.addEventListener('change', () => { parseFocusInput(); render(null); });
  scopeSearchEl.addEventListener('input', () => { render(null); });
  scopeTreeEl.addEventListener('click', (ev) => {
    const btn = ev.target.closest('.scope-btn');
    if (!btn) return;
    ev.preventDefault();
    ev.stopPropagation();
    setScope({ kind: btn.dataset.scopeKind || 'path', value: btn.dataset.scopeValue || '/' });
  });
  allScopeBtnEl.addEventListener('click', () => { setScope({ kind: 'all', value: '__all__' }); });
  currentScopeBtnEl.addEventListener('click', () => { setScopeToCurrent(); });
  scopeHintEl.addEventListener('click', (ev) => {
    const btn = ev.target.closest('button[data-action]');
    if (!btn) return;
    const action = btn.dataset.action || '';
    if (action === 'scope-all') {
      setScope({ kind: 'all', value: '__all__' });
      return;
    }
    if (action === 'scope-current') {
      setScopeToCurrent();
      return;
    }
    if (action === 'range-7d') {
      rangeEl.value = '7d';
      render(null);
      return;
    }
    if (action === 'range-all') {
      rangeEl.value = 'all';
      render(null);
    }
  });
  acctBtnEl.addEventListener('click', () => {
    acctWrapEl.classList.toggle('open');
  });
  document.addEventListener('click', (ev) => {
    if (!acctWrapEl.contains(ev.target)) acctWrapEl.classList.remove('open');
  });

  bindChartHover('mainChart');
  bindChartHover('dailyChart');

  refresh();
  setInterval(refresh, 5000);
})();
</script>
</body>
</html>
HTML
}

ensure_web_server() {
  local port="$1"
  local pid_file port_file log_file pid running_port

  require_cmd python3
  ensure_data_dirs

  pid_file="$(web_pid_file_path)"
  port_file="$(web_port_file_path)"
  log_file="$(web_log_file_path)"

  if is_web_server_running; then
    running_port="$(cat "$port_file" 2>/dev/null || echo "$port")"
    if [[ "$running_port" != "$port" ]]; then
      echo "Web server already running on port $running_port (requested $port)"
    fi
    return 0
  fi

  rm -f "$pid_file"

  nohup python3 -m http.server "$port" --bind 127.0.0.1 --directory "$DATA_ROOT" > "$log_file" 2>&1 &
  pid=$!
  echo "$pid" > "$pid_file"
  echo "$port" > "$port_file"

  sleep 0.2
  if ! is_pid_running "$pid"; then
    echo "Failed to start web server. Check $log_file" >&2
    exit 1
  fi
}

cmd_web_status() {
  local pid_file port_file pid port
  pid_file="$(web_pid_file_path)"
  port_file="$(web_port_file_path)"

  if is_web_server_running; then
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if ! is_pid_running "$pid"; then
      pid="unknown"
    fi
    port="$(cat "$port_file" 2>/dev/null || echo "$DEFAULT_PORT")"
    echo "web_status=running pid=$pid port=$port url=http://127.0.0.1:$port/dashboard/index.html"
  else
    echo "web_status=stopped"
  fi
}

cmd_web_stop() {
  local with_sync="0"
  local pid_file port_file pid
  pid_file="$(web_pid_file_path)"
  port_file="$(web_port_file_path)"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --with-sync) with_sync="1"; shift ;;
      *) echo "Unknown option for web-stop: $1" >&2; exit 1 ;;
    esac
  done

  if [[ ! -f "$pid_file" ]]; then
    echo "Web server not running"
    rm -f "$port_file"
  else
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if is_pid_running "$pid"; then
      kill "$pid" >/dev/null 2>&1 || true
      echo "Stopped web server (pid=$pid)"
    else
      echo "Web server pid file was stale"
    fi
    rm -f "$pid_file" "$port_file"
  fi

  if [[ "$with_sync" == "1" ]]; then
    cmd_sync_stop
  fi
}

cmd_status() {
  local events_file latest
  events_file="$(sync_events_path)"

  cmd_sync_status
  cmd_web_status

  if [[ -f "$events_file" ]]; then
    latest="$(tail -n 1 "$events_file")"
    echo "events_latest=$latest"
  else
    echo "events_latest=none"
  fi
}

cmd_web() {
  local interval="$DEFAULT_SYNC_INTERVAL"
  local port="$DEFAULT_PORT"
  local no_open="0"
  local url

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --interval) interval="$2"; shift 2 ;;
      --port) port="$2"; shift 2 ;;
      --no-open) no_open="1"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option for web: $1" >&2; exit 1 ;;
    esac
  done

  if ! [[ "$interval" =~ ^[0-9]+$ ]] || [[ "$interval" -lt 1 ]]; then
    echo "--interval must be a positive integer" >&2
    exit 1
  fi

  if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
    echo "--port must be in range 1-65535" >&2
    exit 1
  fi

  ensure_data_dirs
  ensure_dashboard_html
  write_ui_context

  cmd_sync >/dev/null
  cmd_sync_start --interval "$interval" >/dev/null
  ensure_web_server "$port"

  url="http://127.0.0.1:$port/dashboard/index.html"
  if [[ "$no_open" == "0" ]]; then
    open_url "$url"
  fi

  echo "Dashboard URL: $url"
  echo "Auto-sync interval: ${interval}s"
  echo "Source root: $SOURCE_ROOT"
}

resolve_project_slug_filter() {
  local project_path=""
  local project_slug=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-path) project_path="$2"; shift 2 ;;
      --project-slug) project_slug="$2"; shift 2 ;;
      --) shift; break ;;
      *) break ;;
    esac
  done

  if [[ -n "$project_path" ]]; then
    project_slug="$(project_slug_from_path "$project_path")"
  fi

  printf '%s\n' "$project_slug"
}

cmd_total() {
  local range="30h"
  local project_slug=""
  local events_file cutoff now

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-path) project_slug="$(project_slug_from_path "$2")"; shift 2 ;;
      --project-slug) project_slug="$2"; shift 2 ;;
      --range) range="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option for total: $1" >&2; exit 1 ;;
    esac
  done

  events_file="$(sync_events_path)"
  if [[ ! -f "$events_file" ]]; then
    echo "No synced events found. Run: claude-usage sync" >&2
    exit 1
  fi

  local range_sec
  range_sec="$(range_to_seconds "$range")"
  now="$(date +%s)"
  cutoff=0
  if [[ "$range_sec" -gt 0 ]]; then
    cutoff=$((now - range_sec))
  fi

  local awk_out
  awk_out="$(awk -F'\t' -v slug="$project_slug" -v cutoff="$cutoff" '
    NR==1 {next}
    {
      ts=$1+0
      if (cutoff>0 && ts<cutoff) next
      if (slug != "" && $3 != slug) next
      n+=1
      input_sum+=$5
      output_sum+=$6
      cache_read_sum+=$7
      cache_create_sum+=$8
      billable_sum+=$9
      total_with_cache_sum+=$10
    }
    END {
      printf("%d\t%d\t%d\t%d\t%d\t%d\t%d\n", n, input_sum, output_sum, cache_read_sum, cache_create_sum, billable_sum, total_with_cache_sum)
    }
  ' "$events_file")"

  local n input_sum output_sum cache_read_sum cache_create_sum billable_sum total_with_cache_sum
  IFS=$'\t' read -r n input_sum output_sum cache_read_sum cache_create_sum billable_sum total_with_cache_sum <<< "$awk_out"

  jq -n \
    --arg range "$range" \
    --arg project_slug "$project_slug" \
    --argjson events "$n" \
    --argjson input "$input_sum" \
    --argjson output "$output_sum" \
    --argjson cache_read "$cache_read_sum" \
    --argjson cache_create "$cache_create_sum" \
    --argjson billable "$billable_sum" \
    --argjson total_with_cache "$total_with_cache_sum" \
    '{
      range: $range,
      project_slug: (if $project_slug == "" then null else $project_slug end),
      events: $events,
      input: $input,
      output: $output,
      cache_read: $cache_read,
      cache_create: $cache_create,
      billable: $billable,
      total_with_cache: $total_with_cache
    }'
}

cmd_graph() {
  local range="30h"
  local metric="billable"
  local points="80"
  local bucket="900"
  local project_slug=""
  local events_file range_sec cutoff now

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-path) project_slug="$(project_slug_from_path "$2")"; shift 2 ;;
      --project-slug) project_slug="$2"; shift 2 ;;
      --range) range="$2"; shift 2 ;;
      --metric) metric="$2"; shift 2 ;;
      --points) points="$2"; shift 2 ;;
      --bucket) bucket="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option for graph: $1" >&2; exit 1 ;;
    esac
  done

  if ! [[ "$points" =~ ^[0-9]+$ ]] || [[ "$points" -lt 1 ]]; then
    echo "--points must be a positive integer" >&2
    exit 1
  fi
  if ! [[ "$bucket" =~ ^[0-9]+$ ]] || [[ "$bucket" -lt 1 ]]; then
    echo "--bucket must be a positive integer" >&2
    exit 1
  fi

  events_file="$(sync_events_path)"
  if [[ ! -f "$events_file" ]]; then
    echo "No synced events found. Run: claude-usage sync" >&2
    exit 1
  fi

  local col
  case "$metric" in
    input) col=5 ;;
    output) col=6 ;;
    cache_read) col=7 ;;
    cache_create) col=8 ;;
    billable) col=9 ;;
    total_with_cache) col=10 ;;
    *) echo "Unknown metric: $metric" >&2; exit 1 ;;
  esac

  range_sec="$(range_to_seconds "$range")"
  now="$(date +%s)"
  cutoff=0
  if [[ "$range_sec" -gt 0 ]]; then
    cutoff=$((now - range_sec))
  fi

  awk -F'\t' -v slug="$project_slug" -v cutoff="$cutoff" -v bucket="$bucket" -v points="$points" -v col="$col" -v metric="$metric" '
    NR==1 {next}
    {
      ts=$1+0
      if (cutoff>0 && ts<cutoff) next
      if (slug != "" && $3 != slug) next
      b=int(ts / bucket) * bucket
      v=$col+0
      sum[b]+=v
      if (!(b in seen)) {
        seen[b]=1
        order[++n]=b
      }
    }
    END {
      if (n==0) {
        print "No data in selected range."
        exit 0
      }

      for (i=1;i<=n;i++) {
        for (j=i+1;j<=n;j++) {
          if (order[i] > order[j]) {
            t=order[i]; order[i]=order[j]; order[j]=t
          }
        }
      }

      start=n-points+1
      if (start<1) start=1

      maxv=1
      for (i=start;i<=n;i++) {
        b=order[i]
        if (sum[b] > maxv) maxv=sum[b]
      }

      printf("metric=%s range_buckets=%d bucket_seconds=%d max=%.0f\n", metric, n-start+1, bucket, maxv)
      for (i=start;i<=n;i++) {
        b=order[i]
        v=sum[b]
        len=int((v/maxv)*60)
        bar=""
        for (k=0;k<len;k++) bar=bar "#"
        cmd="date -u -r " b " +%H:%M"
        cmd | getline tlabel
        close(cmd)
        printf("%s | %-60s %.0f\n", tlabel, bar, v)
      }
    }
  ' "$events_file"
}

cmd_live() {
  local events_file
  events_file="$(sync_events_path)"

  if [[ ! -f "$events_file" ]]; then
    echo "No synced events found. Running initial sync..."
    cmd_sync >/dev/null
  fi

  cmd_sync_start >/dev/null
  echo "Watching synced events in: $events_file"
  echo "Press Ctrl-C to stop"
  tail -n 0 -F "$events_file" | awk -F'\t' '
    NR==1 {next}
    {
      printf("ts=%s project=%s session=%s in=%s out=%s cache_read=%s cache_create=%s billable=%s\n", $2, $3, $4, $5, $6, $7, $8, $9)
      fflush()
    }
  '
}

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    --web) cmd_web "$@" ;;
    web) cmd_web "$@" ;;
    web-stop) cmd_web_stop "$@" ;;
    web-status) cmd_web_status "$@" ;;
    sync) cmd_sync "$@" ;;
    sync-start) cmd_sync_start "$@" ;;
    sync-stop) cmd_sync_stop "$@" ;;
    sync-status) cmd_sync_status "$@" ;;
    status) cmd_status "$@" ;;
    total) cmd_total "$@" ;;
    graph) cmd_graph "$@" ;;
    live) cmd_live "$@" ;;

    # compatibility
    snapshot) cmd_sync "$@" ;;
    start) cmd_sync_start "$@" ;;
    stop) cmd_sync_stop "$@" ;;

    sync-loop) cmd_sync_loop "$@" ;;

    -h|--help|help) usage ;;
    "") cmd_web "$@" ;;
    *)
      echo "Unknown command: $cmd" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
