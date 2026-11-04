"""Repository text conventions, including vendored source and fixtures."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent


class TextTests(unittest.TestCase):
    def test_tracked_text_contains_no_em_dashes(self):
        paths = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).split(b"\0")
        violations = []
        for raw in paths:
            if not raw:
                continue
            path = ROOT / raw.decode()
            data = path.read_bytes()
            if b"\0" in data:
                continue
            try:
                text = data.decode("utf-8")
            except UnicodeDecodeError:
                continue
            if "\u2014" in text:
                violations.append(str(path.relative_to(ROOT)))
        self.assertEqual(violations, [], "Replace em dashes in these tracked text files")


if __name__ == "__main__":
    unittest.main(verbosity=2)
