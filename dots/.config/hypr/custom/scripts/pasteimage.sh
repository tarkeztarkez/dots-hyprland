#!/usr/bin/env bash
# Paste clipboard image into Kitty terminal via wtype
# Requires: wl-clipboard, wtype, libnotify
# Hyprland keybind: Ctrl+Alt+V
set -eufo pipefail

destdir=/tmp
mkdir -p "${destdir}"

# Clean up old pasted images
find "${destdir}" -name "pasted-image-*.png" -mtime +1 -delete 2>/dev/null || true

random="${destdir}/$(mktemp -u pasted-image-XXXXXX).png"

if wl-paste --type image/png > "${random}" 2>/dev/null && [ -s "${random}" ]; then
    notify-send pasteimage "Image saved to ${random}"
    # Copy file path to clipboard and type it into the active terminal
    echo -n "${random}" | wl-copy
    wtype -M ctrl -M shift v
else
    rm -f "${random}"
    notify-send pasteimage "No image found in clipboard"
    exit 1
fi
