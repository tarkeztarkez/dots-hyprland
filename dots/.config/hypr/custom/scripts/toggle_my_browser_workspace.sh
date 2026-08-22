#!/usr/bin/env bash
set -euo pipefail

# A unique initial title lets my-browser bind once without confusing this tab
# with a New tab in another Helium window. my-browser remembers the tab after it
# navigates away from this page.
bootstrap="http://my-browser.localhost/"
exec ~/.agents/skills/my-browser/scripts/toggle-my-browser-window "$@" "$bootstrap"
