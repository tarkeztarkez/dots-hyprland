#!/usr/bin/env bash
set -euo pipefail

# This local bootstrap identifies the Super+E native window on first launch.
# my-browser start creates a separate task-owned group and tab in that window.
# Agents never reuse the bootstrap or the user's active tab for their task.
bootstrap="http://my-browser.localhost/"
exec ~/.agents/skills/my-browser/scripts/toggle-my-browser-window "$@" "$bootstrap"
