"""Offline activity-log tests: uv run python -m unittest scripts.test_activity_log."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "setup/config/bin/activity-log"


class ActivityLogTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        hosts = root / "hosts.toml"
        hosts.write_text("machines = []\n")
        self.env = {
            **os.environ,
            "ACTIVITY_LOG_STATE": str(root / "state"),
            "DEV_HOSTS_FILE": str(hosts),
        }

    def call(self, *args, ok=True):
        result = subprocess.run(
            [str(SCRIPT), *args], env=self.env, capture_output=True, text=True, check=False
        )
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def test_incremental_sync_and_deduplication(self):
        self.call("add", "--category", "work", "--source", "prompt", "--summary", "project · goal")
        raw = self.call("export", "--offset", "0").stdout
        self.assertEqual(json.loads(raw)["summary"], "project · goal")
        self.call("sync")
        self.call("sync")
        entries = self.call("staged").stdout.splitlines()
        self.assertEqual(len(entries), 1)
        self.assertEqual(self.call("export", "--offset", str(len(raw.encode()))).stdout, "")
        self.call(
            "add", "--category", "personal", "--source", "manual", "--summary", "Another event"
        )
        self.call("sync")
        self.assertEqual(len(self.call("staged").stdout.splitlines()), 2)
        self.assertEqual(len(self.call("staged", "--after", "1").stdout.splitlines()), 1)

    def test_invalid_summary_and_spool_truncation(self):
        self.assertNotEqual(
            self.call(
                "add", "--category", "work", "--source", "prompt", "--summary", " ", ok=False
            ).returncode,
            0,
        )
        self.call("add", "--category", "work", "--source", "prompt", "--summary", "Valid")
        self.assertNotEqual(self.call("export", "--offset", "999999", ok=False).returncode, 0)
        self.assertEqual(len(self.call("export", "--offset", "0").stdout.splitlines()), 1)


if __name__ == "__main__":
    unittest.main()
