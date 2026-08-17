#!/usr/bin/env bash
set -euo pipefail

curr_workspace="$(hyprctl activeworkspace -j | jq -r '.id')"
[[ "${curr_workspace}" =~ ^-?[0-9]+$ ]] || exit 0

# Only act on normal numeric workspaces.
if (( curr_workspace < 1 )); then
  exit 0
fi

# Move by decades: 1-10 <-> 11-20 (and also 21-30 <-> 31-40, etc).
group=$(((curr_workspace - 1) / 10))
if (( group % 2 == 0 )); then
  target_workspace=$((curr_workspace + 10))
else
  target_workspace=$((curr_workspace - 10))
fi

hyprctl dispatch "hl.dsp.window.move({ workspace = ${target_workspace}, follow = false })"
