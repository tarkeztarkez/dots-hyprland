import importlib.util
import io
import json
import struct
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("native", Path(__file__).resolve().parents[1] / "scripts/native-host.py")
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


class NativeTests(unittest.TestCase):
    def test_pair_is_retained_when_titles_change(self):
        window = {"address": "e", "pid": 1, "stableId": "x", "title": "1. Bootstrap - Helium"}
        paired = native.pair(window, [{"id": 6, "title": "Bootstrap"}], "browser", None)
        self.assertEqual(native.pair({**window, "title": "Same"}, [{"id": 6, "title": "Same"}, {"id": 8, "title": "Same"}], "browser", paired)["windowId"], 6)

    def test_ambiguous_bootstrap_and_restarted_browser_fail_closed(self):
        window = {"address": "e", "pid": 1, "stableId": "x", "title": "Same"}
        candidates = [{"id": 6, "title": "Same"}, {"id": 8, "title": "Same"}]
        with self.assertRaises(ValueError):
            native.pair(window, candidates, "browser", None)
        old = {**window, "instance": "old", "windowId": 8}
        with self.assertRaises(ValueError):
            native.pair(window, candidates, "new", old)

    def test_native_message_bounds(self):
        data = json.dumps({"op": "resolve"}).encode()
        self.assertEqual(native.read_message(io.BytesIO(struct.pack("=I", len(data)) + data)), {"op": "resolve"})
        for data in (b"", struct.pack("=I", 999999), struct.pack("=I", 20) + b"{}"):
            with self.assertRaises(ValueError):
                native.read_message(io.BytesIO(data))

    def test_launcher_does_not_pass_its_lock_to_browser(self):
        source = (Path(__file__).resolve().parents[1] / "scripts/toggle-my-browser-window").read_text()
        self.assertIn('"${browser_args[@]}" 9>&-', source)
        self.assertIn('"$@" 9>&-', source)
