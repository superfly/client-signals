import json
import os
from pathlib import Path
import tempfile
import unittest

import client_signals
from client_signals.core import is_interactive_file_for_test


ROOT = Path(__file__).resolve().parents[1]


def load_fixture(name):
    return json.loads((ROOT / "spec" / name).read_text(encoding="utf-8"))


class ClientSignalsTest(unittest.TestCase):
    def test_known_markers_match_shared_spec(self):
        self.assertEqual(client_signals.KNOWN_MARKERS, load_fixture("markers.json"))

    def test_sanitize_invoked_by_fixtures(self):
        for fixture in load_fixture("sanitize-fixtures.json"):
            with self.subTest(fixture["name"]):
                got, ok = client_signals.sanitize_invoked_by(fixture["input"])
                self.assertEqual(ok, fixture["valid"])
                self.assertEqual(got, fixture["want"])

    def test_classify_parent_name_fixtures(self):
        for fixture in load_fixture("parent-fixtures.json"):
            with self.subTest(fixture["raw"]):
                self.assertEqual(client_signals.classify_parent_name(fixture["raw"]), fixture["want"])

    def test_headers_and_user_agent_suffix_fixtures(self):
        for fixture in load_fixture("header-fixtures.json"):
            with self.subTest(fixture["name"]):
                self.assertEqual(client_signals.headers_for(fixture["signals"], fixture["prefix"]), fixture["headers"])
                self.assertEqual(client_signals.user_agent_suffix(fixture["signals"]), fixture["userAgentSuffix"])

    def test_operator_fixtures(self):
        for fixture in load_fixture("operator-fixtures.json"):
            with self.subTest(fixture["name"]):
                self.assertEqual(client_signals.operator(fixture["signals"]), fixture["want"])

    def test_apply_headers(self):
        signals = load_fixture("header-fixtures.json")[0]["signals"]
        headers = {}
        self.assertIs(client_signals.apply_headers(headers, signals), headers)
        self.assertEqual(headers["Fly-Client-Agent"], "claude-code")

    def test_detect_once_caches_first_value(self):
        with clean_agent_env():
            client_signals.reset_cached_for_test()
            os.environ["FLY_INVOKED_BY"] = "cached-tool"
            first = client_signals.detect_once()
            os.environ["FLY_INVOKED_BY"] = "different-tool"
            second = client_signals.detect_once()
            self.assertEqual(second, first)
            self.assertEqual(second.agent, "cached-tool")
            client_signals.reset_cached_for_test()

    def test_detect_returns_finite_values(self):
        signals = client_signals.detect()
        self.assertIsInstance(signals.interactive, bool)
        self.assertIn(signals.parent, {"node", "python", "shell", "other"})
        self.assertIsInstance(signals.agent, str)
        self.assertIsInstance(signals.agent_source, str)
        self.assertIsInstance(signals.ci, bool)

    def test_regular_files_are_not_interactive(self):
        with tempfile.NamedTemporaryFile() as file:
            self.assertFalse(is_interactive_file_for_test(file.name))


class clean_agent_env:
    def __enter__(self):
        self.saved = {}
        names = ["FLY_INVOKED_BY", "AGENT", *[marker["env"] for marker in client_signals.KNOWN_MARKERS]]
        for name in names:
            self.saved[name] = os.environ.pop(name, None)
        return self

    def __exit__(self, exc_type, exc, traceback):
        for name, value in self.saved.items():
            if value is not None:
                os.environ[name] = value
            else:
                os.environ.pop(name, None)


if __name__ == "__main__":
    unittest.main()
