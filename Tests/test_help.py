"""Check the offline manual, reference inventory, and its runnable examples."""
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
HELP = ROOT / "Sources/LocalStat/Resources/Help"
BINARY = ROOT / "dist/LocalStat.app/Contents/Helpers/opensas"


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key in ("href", "src"):
                self.links.append(value)


class HelpTests(unittest.TestCase):
    def test_manifest_links_and_offline_assets(self):
        articles = json.loads((HELP / "contents.json").read_text())
        ids = {article["id"] for article in articles}
        self.assertEqual(len(ids), len(articles))
        for article in articles:
            text = (HELP / article["file"]).read_text()
            self.assertNotIn("\u2014", text, article["file"])
            self.assertIn('lang="en"', text)
            self.assertIn("<title>", text)
            self.assertIn("<h1>", text)
            parser = Links(); parser.feed(text)
            for link in parser.links:
                if link.startswith("localstat-help:"):
                    self.assertIn(link.split(":", 1)[1], ids)
                else:
                    self.assertNotIn(":", link, "Help must work without remote assets")
                    self.assertTrue((HELP / link.split("#", 1)[0]).is_file(), link)
            if "example" in article:
                self.assertTrue((HELP / "Examples" / article["example"]).is_file())

    def test_reference_inventory_covers_pinned_sources(self):
        inventory = json.loads((HELP / "reference-inventory.json").read_text())
        tracker = (ROOT / "vendor/opensas/docs/sas-functions.md").read_text()
        names = set(re.findall(r"^- \[[x~ ]\] ([A-Z][A-Z0-9_]*(?: [A-Z][A-Z0-9_]*)?)", tracker, re.M))
        self.assertTrue(names.issubset(set(inventory["functions"])))
        main = (ROOT / "vendor/opensas/src/main.zig").read_text()
        procs = set(re.findall(r'eqi\(proc, "([a-z]+)"\)', main))
        self.assertEqual(set(inventory["procedures"]), procs)
        page = (HELP / "reference.html").read_text()
        self.assertIn("Accepted but inert", page)
        self.assertIn("Partial: catalog storage", page)
        self.assertIn("Partial: only two datetimes", page)
        self.assertIn("Unavailable:", page)
        self.assertEqual(len(inventory["functions"]), len(set(inventory["functions"])))
        self.assertNotIn("TARGET", inventory["functions"])
        self.assertNotIn("A", inventory["functions"])

    def test_examples_run_in_fresh_temporary_projects(self):
        expected = {"first-program.sas": "20", "data-steps.sas": "Ana", "csv.sas": "20",
                    "macros.sas": "9", "sql.sas": "30", "reporting.sas": "91",
                    "regression.sas": "0.6000000000", "functions.sas": "ANA"}
        for file, marker in expected.items():
            with self.subTest(file=file), tempfile.TemporaryDirectory(prefix="localstat-help-") as folder:
                source = HELP / "Examples" / file
                result = subprocess.run([str(BINARY), str(source)], cwd=folder, capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(marker, result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
