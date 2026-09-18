#!/usr/bin/env bash

# Opens Slack or Thunderbird, then asks the shared layout script to restore
# their workspace and left/right positions.

CMD="$1"
TARGET_CLASS="$2"
TARGET_WS="$3"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$CMD" ] || [ -z "$TARGET_CLASS" ] || [ -z "$TARGET_WS" ]; then
  echo "Usage: $0 <command> <class> <workspace_number>" >&2
  exit 1
fi

"${SCRIPT_DIR}/toggle_special.sh" "$CMD" "$TARGET_CLASS" "$TARGET_WS"
"${SCRIPT_DIR}/arrange_communications_workspace.sh" "$TARGET_CLASS"
