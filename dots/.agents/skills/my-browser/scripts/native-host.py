#!/usr/bin/env python3
"""Read-only Hyprland/browser window pairing, invoked by the owned extension."""
import fcntl
import html
import json
import os
import re
import struct
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "my-browser"
LIMIT = 65536


def normalize(title):
    return re.sub(r"^\d+\. ", "", html.unescape(title.removesuffix(" - Helium")))


def pair(window, candidates, instance, cached):
    identity = {"instance": instance, "address": window["address"], "stableId": window.get("stableId"), "pid": window["pid"]}
    if cached and all(cached.get(key) == value for key, value in identity.items()):
        if any(candidate["id"] == cached["windowId"] for candidate in candidates):
            return cached
    matches = [candidate for candidate in candidates if normalize(candidate["title"]) == normalize(window["title"])]
    if len(matches) != 1:
        raise ValueError("Cannot prove which browser window is Super+E. No tab was opened or changed")
    return {**identity, "windowId": matches[0]["id"]}


def read_message(stream):
    header = stream.read(4)
    if len(header) != 4:
        raise ValueError("Missing native message header")
    size = struct.unpack("=I", header)[0]
    if size > LIMIT:
        raise ValueError("Native message too large")
    body = stream.read(size)
    if len(body) != size:
        raise ValueError("Truncated native message")
    return json.loads(body)


def resolve(message):
    if message.get("op") != "resolve" or not isinstance(message.get("windows"), list) or len(message["windows"]) > 100:
        raise ValueError("Invalid native operation")
    for candidate in message["windows"]:
        if type(candidate.get("id")) is not int or not isinstance(candidate.get("title"), str):
            raise ValueError("Invalid window candidate")
    clients = json.loads(subprocess.run(["hyprctl", "clients", "-j"], check=True, capture_output=True, text=True).stdout)
    windows = [c for c in clients if c.get("class", "").lower() == "helium" and c.get("workspace", {}).get("id") == 6 and "helium-test" in c.get("tags", [])]
    if len(windows) != 1:
        raise ValueError("Expected exactly one tagged Super+E window")
    with urllib.request.urlopen("http://127.0.0.1:9222/json/version", timeout=3) as response:
        instance = json.load(response)["webSocketDebuggerUrl"]
    ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (ROOT / "window.lock").open("a") as lock:
        os.chmod(lock.name, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = ROOT / "window.json"
        try:
            cached = json.loads(path.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            cached = None
        result = pair(windows[0], message["windows"], instance, cached)
        pending = path.with_suffix(".pending")
        fd = os.open(pending, os.O_CREAT | os.O_TRUNC | os.O_WRONLY, 0o600)
        with os.fdopen(fd, "w") as out:
            json.dump(result, out)
        os.replace(pending, path)
        return result


def main():
    try:
        result = {"ok": True, "window": resolve(read_message(sys.stdin.buffer))}
    except Exception as error:
        result = {"ok": False, "error": str(error)[:400]}
    body = json.dumps(result).encode()
    sys.stdout.buffer.write(struct.pack("=I", len(body)) + body)
    sys.stdout.buffer.flush()


if __name__ == "__main__":
    main()
