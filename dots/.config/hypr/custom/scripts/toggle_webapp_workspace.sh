#!/usr/bin/env bash
set -euo pipefail

TARGET_WS="${1:-}"
MATCH_RE="${2:-}"
shift 2 || true

if [[ -z "$TARGET_WS" || -z "$MATCH_RE" || "$#" -eq 0 ]]; then
  echo "Usage: $0 <workspace_number> <match_regex> <command...>" >&2
  exit 1
fi

CMD=("$@")
LOCK_TTL_SECONDS=8
POLL_INTERVAL_SECONDS=0.1
LOG_FILE="/tmp/hypr-toggle-webapp.log"
DEBOUNCE_MS=700

LOCK_KEY="$(printf '%s' "${MATCH_RE}-${TARGET_WS}" | tr -cs '[:alnum:]_.-' '_')"
LOCK_FILE="/tmp/hypr-toggle-webapp-${LOCK_KEY}.lock"
DEBOUNCE_FILE="/tmp/hypr-toggle-webapp-${LOCK_KEY}.last"

now_ms() {
  date +%s%3N
}

is_debounced() {
  [[ -f "$DEBOUNCE_FILE" ]] || return 1
  local last now
  last="$(cat "$DEBOUNCE_FILE" 2>/dev/null || echo 0)"
  now="$(now_ms)"
  [[ $((now - last)) -lt "$DEBOUNCE_MS" ]]
}

mark_invocation() {
  now_ms > "$DEBOUNCE_FILE"
}

is_lock_fresh() {
  [[ -f "$LOCK_FILE" ]] || return 1
  local lock_mtime now_epoch
  lock_mtime="$(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)"
  now_epoch="$(date +%s)"
  [[ $((now_epoch - lock_mtime)) -lt "$LOCK_TTL_SECONDS" ]]
}

ensure_helium_debug_port() {
  local executable="${CMD[0]##*/}"

  [[ "$executable" == "helium" || "$executable" == "helium-browser" ]] || return 0

  for arg in "${CMD[@]}"; do
    [[ "$arg" == --remote-debugging-port=* ]] && return 0
  done

  CMD+=("--remote-debugging-port=9222")
}

ensure_helium_debug_port

log_event() {
  printf '%s toggle_webapp: %s regex=%q ws=%s cmd=%q\n' \
    "$(date -Iseconds)" "$1" "$MATCH_RE" "$TARGET_WS" "${CMD[*]}" >> "$LOG_FILE"
}

clients_json() {
  hyprctl clients -j
}

matching_addr() {
  clients_json | jq -r --arg re "$MATCH_RE" '
    [.[] | select(([.class, .initialClass, .title, .initialTitle] | map(. // "") | any(test($re; "i"))))]
    | sort_by(.focusHistoryID)
    | .[0].address // empty
  '
}

webapp_exists_via_debug_port() {
  command -v curl >/dev/null 2>&1 || return 1

  # Helium/Chromium app-window titles are sometimes generic for a moment.  In
  # that short period Hyprland matching can miss the already-open app and a
  # second `--app=...` command is spawned.  The browser debug target still knows
  # the real URL/title, so use it as a no-launch guard.
  curl -fsS --max-time 0.25 http://127.0.0.1:9222/json/list 2>/dev/null \
    | jq -e --arg re "$MATCH_RE" '
        .[]? | select(([.url, .title] | map(. // "") | any(test($re; "i"))))
      ' >/dev/null 2>&1
}

all_addresses() {
  clients_json | jq -r '.[].address' | sort
}

window_workspace() {
  local addr="$1"
  clients_json | jq -r --arg addr "$addr" '.[] | select(.address == $addr) | .workspace.id // empty'
}

move_window_to_target() {
  local addr="$1"
  local current_ws
  current_ws="$(window_workspace "$addr")"
  if [[ "$current_ws" == "$TARGET_WS" ]]; then
    return 0
  fi

  # Helium --app windows sometimes restore as floating with their previous
  # app-window size. Force them back into the tiling layout before/after moving.
  hyprctl dispatch "hl.dsp.window.float({ action = \"unset\", window = \"address:${addr}\" })" >/dev/null || true
  hyprctl dispatch "hl.dsp.window.move({ workspace = ${TARGET_WS}, window = \"address:${addr}\", follow = false })"
  hyprctl dispatch "hl.dsp.window.float({ action = \"unset\", window = \"address:${addr}\" })" >/dev/null || true
}

focus_target() {
  hyprctl dispatch "hl.dsp.focus({ workspace = ${TARGET_WS} })"
}

if is_debounced; then
  log_event "debounced"
  focus_target
  exit 0
fi
mark_invocation

# Existing web app: ensure it is on the configured workspace and go there.
addr="$(matching_addr)"
if [[ -n "$addr" ]]; then
  log_event "matched-hypr addr=$addr"
  move_window_to_target "$addr"
  focus_target
  exit 0
fi

# Existing web app seen by Chromium, but Hyprland title/class matching is in a
# transient state.  Do not launch another instance; just go to its workspace.
if webapp_exists_via_debug_port; then
  log_event "matched-debug-port"
  focus_target
  exit 0
fi

# A launch was already requested recently, likely by key repeat or a previous
# press while the app window was still mapping.  Avoid spawning another process.
if is_lock_fresh; then
  log_event "fresh-lock"
  focus_target
  exit 0
fi

rm -f "$LOCK_FILE"
printf '%s\n' "$$" > "$LOCK_FILE"

before="$(all_addresses)"
"${CMD[@]}" >/dev/null 2>&1 &
log_event "launch pid=$!"

# App windows are created by the already-running Helium process, so Hyprland's
# exec workspace rule can miss them. Detect the new client by address instead.
for _ in {1..60}; do
  after="$(all_addresses)"
  new_addr="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | sed '/^$/d' | head -n1)"
  if [[ -n "$new_addr" ]]; then
    log_event "new-addr addr=$new_addr"
    move_window_to_target "$new_addr"
    focus_target
    rm -f "$LOCK_FILE"
    exit 0
  fi

  addr="$(matching_addr)"
  if [[ -n "$addr" ]]; then
    log_event "matched-after-launch addr=$addr"
    move_window_to_target "$addr"
    focus_target
    rm -f "$LOCK_FILE"
    exit 0
  fi

  sleep "$POLL_INTERVAL_SECONDS"
done

# Last-resort fallback if address diff raced but title/url appeared later.
addr="$(matching_addr)"
if [[ -n "$addr" ]]; then
  log_event "fallback-match addr=$addr"
  move_window_to_target "$addr"
fi
focus_target
rm -f "$LOCK_FILE"
