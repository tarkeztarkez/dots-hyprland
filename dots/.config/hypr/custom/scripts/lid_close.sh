#!/usr/bin/env bash

set -euo pipefail

on_ac=false
for power_supply in /sys/class/power_supply/*; do
  [[ -f "$power_supply/type" ]] || continue
  [[ "$(cat "$power_supply/type")" == "Mains" ]] || continue
  [[ -f "$power_supply/online" ]] || continue

  if [[ "$(cat "$power_supply/online")" == "1" ]]; then
    on_ac=true
    break
  fi
done

if [[ "$on_ac" == true ]]; then
  exec qs -c ii ipc call lock activate
fi

exec systemctl suspend || exec loginctl suspend
