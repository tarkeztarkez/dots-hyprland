#!/usr/bin/env python3
"""Native messaging host and local Quickshell client. No HTTP or Toggl API."""
import argparse
import fcntl
import json
import os
import queue
import select
import socket
import socketserver
import struct
import sys
import threading
import time
import uuid
from pathlib import Path

ROOT = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "toggl-bar"
SOCKET = ROOT / "bridge.sock"
TTL = 12
MAX_MESSAGE = 65536


class State:
    def __init__(self):
        self.lock = threading.Lock()
        self.data = {"available": False, "reason": "Waiting for Toggl"}
        self.updated = 0
        self.pending = {}
        self.error = ""
        self.command_id = ""
        self.projects = []
        self.projects_at = 0
        self.tabs = []

    def snapshot(self):
        with self.lock:
            data = dict(self.data)
            if time.monotonic() - self.updated > TTL:
                data.update(available=False, reason="Toggl connection lost")
            data["error"] = self.error
            data["pending"] = bool(self.pending)
            data["commandId"] = self.command_id
            data["projects"] = self.projects
            data["projectsAt"] = self.projects_at
            data["tabs"] = self.tabs
            return data

    def receive(self, message):
        with self.lock:
            if message.get("type") == "state":
                elapsed = message.get("elapsed", 0)
                if not isinstance(elapsed, (int, float)) or not 0 <= elapsed <= 315360000:
                    elapsed = 0
                self.data = {
                    "available": message.get("available") is True,
                    "running": message.get("running") is True,
                    "title": str(message.get("title", ""))[:240],
                    "elapsed": int(elapsed),
                    "sampledAt": time.time(),
                    "reason": str(message.get("reason", ""))[:240],
                }
                self.updated = time.monotonic()
            elif message.get("type") == "tabs":
                self.tabs = [
                    {"id": tab.get("id"), "pinned": tab.get("pinned") is True, "managed": tab.get("managed") is True}
                    for tab in message.get("tabs", [])[:100] if isinstance(tab, dict)
                ]
            elif message.get("type") == "projects":
                self.projects = [
                    {key: str(project.get(key, ""))[:240] for key in ("id", "name", "client", "color")}
                    for project in message.get("projects", [])[:2000]
                    if isinstance(project, dict) and str(project.get("id", "")).isdigit()
                ]
                self.projects_at = time.time()
            elif message.get("type") == "result" and message.get("id") in self.pending:
                self.pending.pop(message["id"])
                self.error = str(message.get("error", ""))[:240]

    def expire(self):
        with self.lock:
            expired = [key for key, deadline in self.pending.items() if deadline < time.monotonic()]
            for key in expired:
                self.pending.pop(key)
                self.error = "Toggl did not confirm the command. Check the page."


def serve():
    ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    ROOT.chmod(0o700)
    lockfile = (ROOT / "host.lock").open("w")
    try:
        fcntl.flock(lockfile, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return
    SOCKET.unlink(missing_ok=True)
    state = State()
    outgoing = queue.Queue()

    class Handler(socketserver.StreamRequestHandler):
        def handle(self):
            self.request.settimeout(1)
            request = {}
            try:
                raw = self.rfile.readline(4097)
                if len(raw) > 4096:
                    return
                request = json.loads(raw)
                if not isinstance(request, dict):
                    request = {}
                    raise ValueError("Expected a JSON object")
                action = request.get("action", "status")
                current = state.snapshot()
                if action != "status":
                    if action not in ("open", "start", "stop", "projects"):
                        raise ValueError("Unknown action")
                    if action != "open" and not current.get("available"):
                        raise ValueError("Toggl is unavailable")
                    with state.lock:
                        if state.pending:
                            raise ValueError("Waiting for Toggl")
                        if action in ("start", "stop") and current.get("running") != (action == "stop"):
                            raise ValueError("Timer changed. Try again.")
                        project_id = str(request.get("projectId", ""))
                        if action == "start" and not project_id.isdigit():
                            raise ValueError("Choose a project first")
                        command = {"id": str(request.get("id") or uuid.uuid4().hex)[:100], "action": action,
                                   "expectedRunning": action == "stop", "projectId": project_id}
                        state.command_id = command["id"]
                        state.pending[command["id"]] = time.monotonic() + 20
                        state.error = ""
                        outgoing.put(command)
                    current = state.snapshot()
                self.wfile.write(json.dumps(current).encode() + b"\n")
            except (ValueError, OSError) as error:
                try:
                    result = state.snapshot()
                    result.update(error=str(error), commandId=request.get("id", ""), pending=False)
                    self.wfile.write(json.dumps(result).encode() + b"\n")
                except OSError:
                    pass

    class Server(socketserver.ThreadingUnixStreamServer):
        daemon_threads = True

    server = Server(str(SOCKET), Handler)
    SOCKET.chmod(0o600)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    buffer = bytearray()
    try:
        while True:
            if select.select([sys.stdin.buffer], [], [], 0.1)[0]:
                chunk = os.read(sys.stdin.fileno(), 65536)
                if not chunk:
                    break
                buffer.extend(chunk)
                while len(buffer) >= 4:
                    size = struct.unpack("=I", buffer[:4])[0]
                    if size > MAX_MESSAGE:
                        raise ValueError("Native message too large")
                    if len(buffer) < size + 4:
                        break
                    message = json.loads(buffer[4:4 + size])
                    del buffer[:4 + size]
                    if isinstance(message, dict):
                        state.receive(message)
            state.expire()
            while not outgoing.empty():
                payload = json.dumps(outgoing.get_nowait()).encode()
                sys.stdout.buffer.write(struct.pack("=I", len(payload)) + payload)
                sys.stdout.buffer.flush()
    finally:
        server.shutdown()
        server.server_close()
        SOCKET.unlink(missing_ok=True)


def client(action, project_id="", request_id=""):
    try:
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(1)
            connection.connect(str(SOCKET))
            connection.sendall(json.dumps({"action": action, "projectId": project_id, "id": request_id}).encode() + b"\n")
            result = b""
            while b"\n" not in result and len(result) <= MAX_MESSAGE:
                chunk = connection.recv(4096)
                if not chunk:
                    break
                result += chunk
            return json.loads(result)
    except (OSError, ValueError):
        return {"available": False, "reason": "Helium or the Toggl extension is unavailable"}


def main():
    # Chromium passes the extension origin when launching a native host.
    if len(sys.argv) > 1 and sys.argv[1].startswith("chrome-extension://"):
        serve()
        return
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["status", "open", "start", "stop", "projects", "host"], nargs="?", default="status")
    parser.add_argument("--project", default="")
    parser.add_argument("--id", default="")
    args = parser.parse_args()
    if args.action == "host":
        serve()
    else:
        print(json.dumps(client(args.action, args.project, args.id)))


if __name__ == "__main__":
    main()
