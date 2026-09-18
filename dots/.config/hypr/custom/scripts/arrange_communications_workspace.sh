#!/usr/bin/env bash

TARGET_CLASS="${1:-}"
TARGET_WS=20

clients_json="$(hyprctl -j clients)"

main_window() {
  local class="$1"
  local preferred_initial_title="$2"

  jq -r \
    --arg class "$class" \
    --arg preferred "$preferred_initial_title" '
      [
        .[]
        | select(.class == $class)
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

window_value() {
  local address="$1"
  local filter="$2"

  jq -r --arg address "$address" ".[] | select(.address == \$address) | ${filter}" <<<"$clients_json"
}

move_to_communications_workspace() {
  local address="$1"

  [ -n "$address" ] || return 0
  if [ "$(window_value "$address" '.workspace.id')" != "$TARGET_WS" ]; then
    hyprctl dispatch \
      "hl.dsp.window.move({ workspace = ${TARGET_WS}, window = \"address:${address}\", follow = false })" \
      >/dev/null
  fi
  if [ "$(window_value "$address" '.floating')" = "true" ]; then
    hyprctl dispatch \
      "hl.dsp.window.float({ action = \"unset\", window = \"address:${address}\" })" \
      >/dev/null
  fi
}

slack_address="$(main_window "Slack" "Slack")"
thunderbird_address="$(main_window "org.mozilla.Thunderbird" "Mozilla Thunderbird")"

move_to_communications_workspace "$slack_address"
move_to_communications_workspace "$thunderbird_address"

clients_json="$(hyprctl -j clients)"

if [ -n "$slack_address" ] && [ -n "$thunderbird_address" ]; then
  slack_x="$(window_value "$slack_address" '.at[0]')"
  thunderbird_x="$(window_value "$thunderbird_address" '.at[0]')"

  if [ -n "$slack_x" ] && [ -n "$thunderbird_x" ] && [ "$slack_x" -gt "$thunderbird_x" ]; then
    hyprctl dispatch \
      "hl.dsp.window.move({ direction = \"l\", window = \"address:${slack_address}\" })" \
      >/dev/null
  fi
fi

case "$TARGET_CLASS" in
  Slack)
    target_address="$slack_address"
    ;;
  org.mozilla.Thunderbird)
    target_address="$thunderbird_address"
    ;;
  *)
    target_address=""
    ;;
esac

if [ -n "$target_address" ]; then
  hyprctl dispatch "hl.dsp.focus({ window = \"address:${target_address}\" })" >/dev/null
fi
