#!/usr/bin/env bash

# Opens Slack and Thunderbird on one workspace, then keeps their main windows
# in a stable left/right split.

CMD="$1"
TARGET_CLASS="$2"
TARGET_WS="$3"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$CMD" ] || [ -z "$TARGET_CLASS" ] || [ -z "$TARGET_WS" ]; then
  echo "Usage: $0 <command> <class> <workspace_number>" >&2
  exit 1
fi

"${SCRIPT_DIR}/toggle_special.sh" "$CMD" "$TARGET_CLASS" "$TARGET_WS"

clients_json="$(hyprctl -j clients)"

main_window() {
  local class="$1"
  local preferred_initial_title="$2"

  jq -r \
    --arg class "$class" \
    --arg preferred "$preferred_initial_title" \
    --argjson workspace "$TARGET_WS" '
      [
        .[]
        | select(.class == $class and .workspace.id == $workspace)
        | . + {
            preferred: (if .initialTitle == $preferred then 1 else 0 end),
            area: (.size[0] * .size[1])
          }
      ]
      | sort_by([.preferred, (if .floating then 0 else 1 end), .area])
      | last
      | .address // empty
    ' <<<"$clients_json"
}

slack_address="$(main_window "Slack" "Slack")"
thunderbird_address="$(main_window "org.mozilla.Thunderbird" "Mozilla Thunderbird")"

move_window() {
  local address="$1"
  local direction="$2"

  hyprctl dispatch \
    "hl.dsp.window.move({ direction = \"${direction}\", window = \"address:${address}\" })" \
    >/dev/null
}

if [ -n "$slack_address" ] && [ -n "$thunderbird_address" ]; then
  move_window "$slack_address" "l"
  move_window "$thunderbird_address" "r"
fi

target_address="$(main_window "$TARGET_CLASS" "${TARGET_CLASS#org.mozilla.}")"
if [ -n "$target_address" ]; then
  hyprctl dispatch "hl.dsp.focus({ window = \"address:${target_address}\" })" >/dev/null
fi
