#!/usr/bin/env bash
set -euo pipefail

TARGET_WS="${1:-}"
shift || true

if [[ -z "$TARGET_WS" || "$#" -eq 0 ]]; then
  echo "Usage: $0 <workspace_number> <helium command...>" >&2
  exit 1
fi

CLASS_RE="^(helium|Helium)$"
CMD=("$@")
TEST_TAG="helium-test"

ensure_helium_debug_port() {
  local executable="${CMD[0]##*/}"

  [[ "$executable" == "helium" || "$executable" == "helium-browser" ]] || return 0

  for arg in "${CMD[@]}"; do
    [[ "$arg" == --remote-debugging-port=* ]] && return 0
  done

  CMD+=("--remote-debugging-port=9222")
}

ensure_helium_debug_port

clients_json() {
  hyprctl clients -j
}

helium_on_target() {
  clients_json | jq -e --arg class_re "$CLASS_RE" --argjson ws "$TARGET_WS" \
    '.[] | select(.class | test($class_re)) | select(.workspace.id == $ws) | .address' >/dev/null
}

helium_addresses() {
  clients_json | jq -r --arg class_re "$CLASS_RE" '.[] | select(.class | test($class_re)) | .address' | sort
}

move_window_to_target() {
  local addr="$1"
  hyprctl dispatch "hl.dsp.window.move({ workspace = ${TARGET_WS}, window = \"address:${addr}\", follow = false })"

  if [[ "$TARGET_WS" == "6" ]]; then
    hyprctl dispatch "hl.dsp.window.tag({ tag = \"+${TEST_TAG}\", window = \"address:${addr}\" })"
  fi
}

focus_target() {
  [[ "${HELIUM_NO_FOCUS:-0}" == "1" ]] && return 0
  hyprctl dispatch "hl.dsp.focus({ workspace = ${TARGET_WS} })"
}

# If this browser workspace already has a Helium window, just go there.
if helium_on_target; then
  focus_target
  exit 0
fi

before="$(helium_addresses)"
"${CMD[@]}" >/dev/null 2>&1 &

# Browser windows are often created by an already-running browser process, so
# Hyprland's exec workspace rule cannot reliably target them. Detect the new
# client by address and move that exact window instead.
for _ in {1..50}; do
  after="$(helium_addresses)"
  new_addr="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | sed '/^$/d' | head -n1)"
  if [[ -n "$new_addr" ]]; then
    move_window_to_target "$new_addr"
    focus_target
    exit 0
  fi
  sleep 0.1
done

# Fallback: move the most recently focused Helium window if address diffing raced.
fallback_addr="$(clients_json | jq -r --arg class_re "$CLASS_RE" '
  [.[] | select(.class | test($class_re))]
  | sort_by(.focusHistoryID)
  | .[0].address // empty
')"

if [[ -n "$fallback_addr" ]]; then
  move_window_to_target "$fallback_addr"
fi

focus_target
