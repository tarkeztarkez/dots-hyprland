#!/usr/bin/env sh
set -eu

CONFIG="$HOME/.config/hypr/custom/hyprlock.conf"

if pidof hyprlock >/dev/null 2>&1; then
    exit 0
fi

exec hyprlock --config "$CONFIG"
