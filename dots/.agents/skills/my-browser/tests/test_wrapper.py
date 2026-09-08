import importlib.machinery
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/my-browser"
loader = importlib.machinery.SourceFileLoader("my_browser", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
browser = importlib.util.module_from_spec(spec)
loader.exec_module(browser)


class WrapperTests(unittest.TestCase):
    def test_requires_explicit_session_without_connecting(self):
        with patch.object(browser, "manage") as manage:
            with self.assertRaisesRegex(ValueError, "task session"):
                browser.main(["snapshot", "-i"])
            manage.assert_not_called()

    def test_rejects_session_paths_and_overrides(self):
        for name in ("../other", "A", "", "x" * 65):
            with self.assertRaises(ValueError):
                browser.validate_session(name)
        for command in (["connect", "9222"], ["tab", "t1"], ["close"], ["open", "--cdp=9222"], ["snapshot", "--namespace", "shared"]):
            with self.assertRaises(ValueError):
                browser.validate_command(command)
        browser.validate_command(["fill", "@e1", "normal text"])

    def test_same_session_lock_fails_but_other_session_can_work(self):
        with tempfile.TemporaryDirectory(prefix="my-browser-tests-") as directory, patch.object(browser, "STATE_DIR", Path(directory)):
            with browser.session_lock("a"):
                with self.assertRaisesRegex(RuntimeError, "busy"):
                    with browser.session_lock("a"):
                        pass
                with browser.session_lock("b"):
                    pass
            with browser.session_lock("a"):
                pass

    def test_state_files_are_separate_private_and_atomic(self):
        with tempfile.TemporaryDirectory(prefix="my-browser-tests-") as directory, patch.object(browser, "STATE_DIR", Path(directory)):
            browser.save({"session": "a", "selected": "first"})
            browser.save({"session": "b", "selected": "second"})
            self.assertEqual(json.loads(browser.state_path("a").read_text())["selected"], "first")
            self.assertEqual(browser.state_path("a").stat().st_mode & 0o777, 0o600)
            self.assertFalse(list(Path(directory).glob("*.pending")))

    def test_missing_state_does_not_adopt_an_existing_tab(self):
        with tempfile.TemporaryDirectory(prefix="my-browser-tests-") as directory, patch.object(browser, "STATE_DIR", Path(directory)), patch.object(browser, "manage") as manage:
            with self.assertRaisesRegex(RuntimeError, "Unknown session"):
                browser.main(["--session", "missing", "snapshot"])
            manage.assert_not_called()

    def test_daemon_names_are_short_private_and_ignore_shared_environment(self):
        with patch.dict(browser.os.environ, {"AGENT_BROWSER_SESSION": "shared", "AGENT_BROWSER_NAMESPACE": "shared", "AGENT_BROWSER_CDP": "9222"}):
            a = browser.daemon_env({"session": "a" * 64, "selected": "target-a"})
            b = browser.daemon_env({"session": "a" * 64, "selected": "target-b"})
            self.assertNotEqual(a["AGENT_BROWSER_SESSION"], b["AGENT_BROWSER_SESSION"])
            self.assertLess(len(a["AGENT_BROWSER_SESSION"]), 25)
            self.assertEqual(a["AGENT_BROWSER_NAMESPACE"], "mb")
            self.assertNotIn("AGENT_BROWSER_CDP", a)

    def test_lost_or_ambiguous_window_fails_closed(self):
        for clients in ([], [{"class": "helium", "workspace": {"id": 8}, "tags": []}], [{"class": "helium", "workspace": {"id": 6}, "tags": ["helium-test"]}] * 2):
            with patch.object(browser, "run") as run:
                run.return_value.stdout = json.dumps(clients)
                with self.assertRaisesRegex(RuntimeError, "exactly one"):
                    browser.tagged_window()


if __name__ == "__main__":
    unittest.main()
