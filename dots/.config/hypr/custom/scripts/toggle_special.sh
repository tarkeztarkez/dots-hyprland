#!/usr/bin/env bash

# Usage: toggle_special.sh <command> <class> <workspace_number>

CMD="$1"
CLASS="$2"
TARGET_WS="$3"
LOCK_TTL_SECONDS=8
POLL_INTERVAL_SECONDS=0.2
LOG_FILE="/tmp/hypr-toggle.log"

if [ -z "$CMD" ] || [ -z "$CLASS" ] || [ -z "$TARGET_WS" ]; then
  echo "Usage: $0 <command> <class> <workspace_number>"
  exit 1
fi

LOCK_KEY="$(printf '%s' "${CLASS}-${TARGET_WS}" | tr -cs '[:alnum:]_.-' '_')"
LOCK_FILE="/tmp/hypr-toggle-${LOCK_KEY}.lock"

is_app_running() {
  if command -v jq >/dev/null 2>&1; then
    hyprctl clients -j | jq -e --arg class "$CLASS" '.[] | select(.class == $class)' >/dev/null 2>&1
  else
    hyprctl clients | awk '/class: / {print substr($0, 8)}' | grep -Fxq "$CLASS"
  fi
}

is_lock_fresh() {
  [ -f "$LOCK_FILE" ] || return 1
  lock_mtime="$(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)"
  now_epoch="$(date +%s)"
  [ $((now_epoch - lock_mtime)) -lt "$LOCK_TTL_SECONDS" ]
}

# App already running: switch to its workspace.
if is_app_running; then
  hyprctl dispatch "hl.dsp.focus({ workspace = ${TARGET_WS} })"
  exit 0
fi

# Launch already requested recently: don't spawn a second instance.
if is_lock_fresh; then
  hyprctl dispatch "hl.dsp.focus({ workspace = ${TARGET_WS} })"
  exit 0
fi

# Stale lock from a failed/aborted previous launch.
rm -f "$LOCK_FILE"
printf '%s\n' "$$" > "$LOCK_FILE"

# Not running and no fresh lock: launch silently on target workspace, then switch.
hyprctl dispatch "hl.dsp.exec_cmd(\"[workspace ${TARGET_WS} silent] ${CMD}\")"
hyprctl dispatch "hl.dsp.focus({ workspace = ${TARGET_WS} })"

# Wait briefly for window mapping. If launch fails, unlock after timeout.
attempts=$((LOCK_TTL_SECONDS * 10 / 2))
for _ in $(seq 1 "$attempts"); do
  if is_app_running; then
    rm -f "$LOCK_FILE"
    exit 0
  fi
  sleep "$POLL_INTERVAL_SECONDS"
done

printf '%s toggle_special: launch timeout for class=%s ws=%s cmd=%s\n' \
  "$(date -Iseconds)" "$CLASS" "$TARGET_WS" "$CMD" >> "$LOG_FILE"
rm -f "$LOCK_FILE"
