#!/usr/bin/env python3
"""Install the bridge and register its native host for Helium."""
import hashlib
import json
import os
import shutil
from pathlib import Path

SOURCE = Path(__file__).resolve().parent
HOME = Path.home()
DEST = HOME / ".local/share/toggl-bar"
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "net.imput.helium"


def extension_id():
    # Chromium derives an unpacked extension ID from its absolute directory path.
    digest = hashlib.sha256(str(DEST / "extension").encode()).hexdigest()[:32]
    return "".join(chr(ord("a") + int(char, 16)) for char in digest)


def main():
    if SOURCE != DEST:
        shutil.copytree(SOURCE, DEST, dirs_exist_ok=True, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    (DEST / "bridge.py").chmod(0o755)
    directory = CONFIG / "NativeMessagingHosts"
    directory.mkdir(parents=True, exist_ok=True)
    manifest = {
        "name": "local.toggl_bar",
        "description": "Local Toggl timer bridge for Quickshell",
        "path": str(DEST / "bridge.py"),
        "type": "stdio",
        "allowed_origins": [f"chrome-extension://{extension_id()}/"],
    }
    (directory / "local.toggl_bar.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Load unpacked extension: {DEST / 'extension'}")
    print(f"Expected extension ID: {extension_id()}")


if __name__ == "__main__":
    main()
