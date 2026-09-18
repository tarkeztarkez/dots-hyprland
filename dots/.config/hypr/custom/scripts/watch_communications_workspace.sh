#!/usr/bin/env bash

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOCK_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr-communications-workspace.lock"

exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

arrange() {
  sleep 0.15
  "${SCRIPT_DIR}/arrange_communications_workspace.sh"
}

arrange

while true; do
  socket_path="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"

  if [ ! -S "$socket_path" ]; then
    sleep 1
    continue
  fi

  while IFS= read -r event; do
    case "$event" in
      openwindow\>\>*|movewindow\>\>*|movewindowv2\>\>*|changefloatingmode\>\>*|closewindow\>\>*|activewindow\>\>*|activewindowv2\>\>*)
        arrange
        ;;
    esac
  done < <(nc -U "$socket_path")

  sleep 1
done
