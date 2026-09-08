import concurrent.futures
import json
import os
import subprocess
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLI = str(ROOT / "scripts/my-browser")
STATE = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "my-browser/sessions"


@unittest.skipUnless(os.environ.get("MY_BROWSER_LIVE_TEST") == "1", "Explicit opt-in required for the user's Helium")
class LiveTests(unittest.TestCase):
    def call(self, session, *command, ok=True):
        result = subprocess.run([CLI, "--session", session, *command], capture_output=True, text=True, timeout=20)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def state(self, session):
        return json.loads((STATE / f"{session}.json").read_text())

    def native(self, action, a, b):
        result = subprocess.run(["bun", str(ROOT / "tests/native-fixture.ts")], input=json.dumps({"action": action, "a": self.state(a), "b": self.state(b)}), capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_parallel_groups_recovery_and_closed_target(self):
        sessions = []
        try:
            def start(name):
                result = subprocess.run([CLI, "start", name], capture_output=True, text=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stderr)
                return json.loads(result.stdout)["session"]
            with concurrent.futures.ThreadPoolExecutor() as pool:
                sessions = list(pool.map(start, ["groups-live-a", "groups-live-b"]))
                a, b = sessions
                groups = self.native("status", a, b)
                self.assertNotEqual(groups[0]["id"], groups[1]["id"])
                self.assertEqual(groups[0]["windowId"], groups[1]["windowId"])
                for index, session in enumerate(sessions):
                    self.call(session, "eval", f'document.title="Groups live {index}"; document.body.innerHTML="<button>Increment {index}</button>"; window.count=0; document.querySelector("button").onclick=()=>++window.count; true')
                    self.assertIn("@e1", self.call(session, "snapshot", "-i").stdout.replace("ref=e1", "@e1"))
                for _ in range(3):
                    list(pool.map(lambda session: self.call(session, "click", "@e1"), sessions))
                for session in sessions:
                    self.assertEqual(json.loads(self.call(session, "eval", "window.count").stdout), 3)
                initial = self.state(a)["selected"]
                self.call(a, "new-tab")
                self.call(a, "select", initial)
                self.native("move", a, b)
                try:
                    self.call(a, "eval", "window.count=99", ok=False)
                    self.assertEqual(json.loads(self.call(b, "eval", "window.count").stdout), 3)
                finally:
                    self.native("restore", a, b)
                self.assertEqual(json.loads(self.call(a, "eval", "window.count").stdout), 3)
                holding = pool.submit(self.call, a, "eval", 'new Promise(resolve=>setTimeout(()=>resolve("done"),2500))')
                time.sleep(0.5)
                self.assertIn("busy", self.call(a, "snapshot", ok=False).stderr)
                holding.result()
                self.call(a, "snapshot")
                self.native("close", a, b)
                self.call(a, "eval", "window.count=99", ok=False)
                self.assertEqual(json.loads(self.call(b, "eval", "window.count").stdout), 3)
        finally:
            for session in sessions:
                self.call(session, "finish")


if __name__ == "__main__":
    unittest.main()
