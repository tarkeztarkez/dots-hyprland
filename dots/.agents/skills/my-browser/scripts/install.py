#!/usr/bin/env python3
"""Register the owned extension's native host without changing browser preferences."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# Load this exact absolute path so the unpacked ID does not depend on symlinks.
EXTENSION = ROOT / "extension"
digest = hashlib.sha256(str(EXTENSION).encode()).hexdigest()[:32]
extension_id = "".join(chr(ord("a") + int(character, 16)) for character in digest)
host = ROOT / "scripts/native-host.py"
host.chmod(0o755)
directory = Path.home() / ".config/net.imput.helium/NativeMessagingHosts"
directory.mkdir(parents=True, exist_ok=True)
manifest = {"name": "local.my_browser", "description": "Pair the tagged Super+E window", "path": str(host), "type": "stdio", "allowed_origins": [f"chrome-extension://{extension_id}/"]}
(directory / "local.my_browser.json").write_text(json.dumps(manifest, indent=2) + "\n")
# Helium's packaged launcher reads this file. Preserve all unrelated flags.
flags = Path.home() / ".config/helium-browser-flags.conf"
lines = flags.read_text().splitlines() if flags.exists() else []
load = next((line for line in lines if line.startswith("--load-extension=")), None)
if load:
    paths = load.split("=", 1)[1].split(",")
    if str(EXTENSION) not in paths:
        lines[lines.index(load)] = load + "," + str(EXTENSION)
else:
    lines.append("--load-extension=" + str(EXTENSION))
flags.write_text("\n".join(lines) + "\n")
print(json.dumps({"path": str(EXTENSION), "extensionId": extension_id}))
