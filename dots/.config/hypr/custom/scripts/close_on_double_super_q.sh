#!/usr/bin/env bash
set -euo pipefail

threshold_ms=600
state_dir="${XDG_RUNTIME_DIR:-/tmp}"
state_file="$state_dir/hypr-super-q-close.state"

now_ms=$(date +%s%3N)
active_addr=$(hyprctl activewindow 2>/dev/null | awk '/^Window / {print $2; exit}')

last_ms=0
last_addr=""
if [[ -r "$state_file" ]]; then
  read -r last_ms last_addr < "$state_file" || true
fi

if [[ "$last_ms" =~ ^[0-9]+$ ]] && (( now_ms - last_ms <= threshold_ms )) && [[ -n "$active_addr" && "$active_addr" == "$last_addr" ]]; then
  rm -f "$state_file"
  # This config uses hyprland-lua, which overrides `hyprctl dispatch` to
  # expect Lua dispatcher expressions instead of raw Hyprland dispatcher names.
  hyprctl dispatch 'hl.dsp.window.close()'
else
  printf '%s %s\n' "$now_ms" "$active_addr" > "$state_file"
fi
