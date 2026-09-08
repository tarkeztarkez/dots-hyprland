import importlib.util
import json
import os
import select
import shutil
import socket
import stat
import struct
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

BRIDGE = Path(__file__).with_name("bridge.py")
PYTHON = shutil.which("python3")
spec = importlib.util.spec_from_file_location("bridge", BRIDGE)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class StateTests(unittest.TestCase):
    def test_stale(self):
        state = bridge.State()
        state.receive({"type": "state", "available": True, "running": True, "elapsed": 20})
        self.assertTrue(state.snapshot()["available"])
        state.updated -= 13
        self.assertFalse(state.snapshot()["available"])

    def test_bad_values_and_expired_command(self):
        state = bridge.State()
        state.receive({"type": "state", "available": "yes", "elapsed": -100})
        self.assertFalse(state.snapshot()["available"])
        self.assertEqual(state.snapshot()["elapsed"], 0)
        state.pending["x"] = time.monotonic() - 1
        state.expire()
        self.assertFalse(state.snapshot()["pending"])
        self.assertIn("not confirm", state.snapshot()["error"])

    def test_projects_survive_timer_samples(self):
        state = bridge.State()
        state.receive({"type": "projects", "projects": [{"id": "42", "name": "Work"}]})
        state.receive({"type": "state", "available": True})
        self.assertEqual(state.snapshot()["projects"][0]["name"], "Work")
        self.assertGreater(state.snapshot()["projectsAt"], 0)


class HostTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.env = os.environ | {"XDG_RUNTIME_DIR": self.temp.name}
        self.path = Path(self.temp.name) / "toggl-bar/bridge.sock"
        self.host = subprocess.Popen([PYTHON, str(BRIDGE), "host"], env=self.env,
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        for _ in range(100):
            if self.path.exists():
                break
            time.sleep(0.01)
        self.assertTrue(self.path.exists())

    def tearDown(self):
        if self.host.poll() is None:
            self.host.stdin.close()
            self.host.wait(timeout=3)
        self.host.stdout.close()
        self.host.stderr.close()
        self.temp.cleanup()

    def request(self, action="status", **extra):
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(2)
            client.connect(str(self.path))
            client.sendall(json.dumps({"action": action, **extra}).encode() + b"\n")
            return json.loads(client.recv(65536))

    def send(self, message, fragmented=False):
        raw = json.dumps(message).encode()
        frame = struct.pack("=I", len(raw)) + raw
        if fragmented:
            for chunk in [frame[:2], frame[2:5], frame[5:]]:
                self.host.stdin.write(chunk)
                self.host.stdin.flush()
                time.sleep(0.02)
        else:
            self.host.stdin.write(frame)
            self.host.stdin.flush()
        time.sleep(0.15)

    def receive(self):
        self.assertTrue(select.select([self.host.stdout], [], [], 2)[0])
        size = struct.unpack("=I", self.host.stdout.read(4))[0]
        return json.loads(self.host.stdout.read(size))

    def test_framed_state_command_ack_and_permissions(self):
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.path.parent.stat().st_mode), 0o700)
        self.assertFalse(self.request()["available"])
        self.send({"type": "state", "available": True, "running": True, "title": "Fixture", "elapsed": 12}, True)
        self.assertEqual(self.request()["title"], "Fixture")
        self.assertTrue(self.request("stop")["pending"])
        command = self.receive()
        self.assertEqual(command["action"], "stop")
        self.assertTrue(command["expectedRunning"])
        self.assertIn("Waiting", self.request("stop")["error"])
        self.send({"type": "result", "id": command["id"], "error": ""})
        self.assertFalse(self.request()["pending"])
        self.assertIn("changed", self.request("start")["error"])
        self.assertIn("Unknown", self.request("delete")["error"])

    def test_disconnect_removes_socket_and_client_is_unavailable(self):
        self.host.stdin.close()
        self.host.wait(timeout=3)
        self.assertFalse(self.path.exists())
        result = subprocess.check_output([PYTHON, str(BRIDGE), "status"], env=self.env)
        self.assertFalse(json.loads(result)["available"])

    def test_commands_rejected_when_unavailable(self):
        self.assertIn("unavailable", self.request("start")["error"])

    def test_second_host_cannot_steal_socket(self):
        second = subprocess.run([PYTHON, str(BRIDGE), "host"], env=self.env,
                                input=b"", capture_output=True, timeout=2)
        self.assertEqual(second.returncode, 0)
        self.assertTrue(self.path.exists())
        self.assertFalse(self.request()["available"])

    def test_start_carries_project_and_optimistic_request_id(self):
        self.send({"type": "state", "available": True, "running": False, "elapsed": 0})
        self.assertIn("project", self.request("start")["error"])
        result = self.request("start", projectId="42", id="optimistic-1")
        self.assertEqual(result["commandId"], "optimistic-1")
        self.assertTrue(result["pending"])
        command = self.receive()
        self.assertEqual(command["projectId"], "42")
        self.assertEqual(command["id"], "optimistic-1")
        self.send({"type": "state", "available": True, "running": True, "title": "Work", "elapsed": 0})
        self.send({"type": "result", "id": "optimistic-1", "error": ""})
        result = self.request()
        self.assertTrue(result["running"])
        self.assertFalse(result["pending"])
        self.assertEqual(result["commandId"], "optimistic-1")


if __name__ == "__main__":
    unittest.main()
