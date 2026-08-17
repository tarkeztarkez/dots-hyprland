#!/usr/bin/env bash
set -euo pipefail

# The lingering user manager starts before Hyprland, so import the compositor
# environment before starting the persistent Herdr server and its pane shells.
for _ in {1..50}; do
  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -n "${WAYLAND_DISPLAY:-}" ]]; then
    break
  fi
  sleep 0.1
done

if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" || -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo "Hyprland environment did not become available" >&2
  exit 1
fi

variables=(HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY XDG_CURRENT_DESKTOP)
if [[ -n "${DISPLAY:-}" ]]; then
  variables+=(DISPLAY)
fi

dbus-update-activation-environment --systemd "${variables[@]}"
systemctl --user restart herdr.service
