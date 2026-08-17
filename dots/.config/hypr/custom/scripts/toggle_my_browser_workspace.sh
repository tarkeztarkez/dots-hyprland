#!/usr/bin/env bash
set -euo pipefail

# Super+E owns workspace 6. It has no pinned anchor tab or agent-browser state.
exec ~/.agents/skills/my-browser/scripts/toggle-my-browser-window "$@"
