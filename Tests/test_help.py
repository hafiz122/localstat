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
        self.code_blocks = []
        self.in_pre = False
    def handle_starttag(self, tag, attrs):
        if tag == "pre":
            self.in_pre = True
            self.code_blocks.append("")
        for key, value in attrs:
            if key in ("href", "src"):
                self.links.append(value)
    def handle_endtag(self, tag):
        if tag == "pre":
            self.in_pre = False
    def handle_data(self, data):
        if self.in_pre:
            self.code_blocks[-1] += data


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
        registry = (ROOT / "vendor/opensas/src/proc_registry.zig").read_text()
        procs = set(re.findall(r'\.name = "([a-z]+)"', registry))
        self.assertEqual(set(inventory["procedures"]), procs)
        self.assertTrue({"corr", "ttest", "copy", "sgplot"}.issubset(procs))
        page = (HELP / "reference.html").read_text()
        self.assertIn("Scatter, series, vertical bar, and horizontal bar SVG plots", page)
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
        articles = json.loads((HELP / "contents.json").read_text())
        for article in articles:
            if "example" not in article:
                continue
            file = article["example"]
            parser = Links(); parser.feed((HELP / article["file"]).read_text())
            with self.subTest(file=file):
                self.assertTrue(parser.code_blocks, "Show a complete program that readers can copy")
            sources = {"Open Example": (HELP / "Examples" / file).read_text(),
                       "Article code": "\n".join(parser.code_blocks)}
            for action, text in sources.items():
                with self.subTest(file=file, action=action), tempfile.TemporaryDirectory(prefix="localstat-help-") as folder:
                    source = Path(folder) / file
                    source.write_text(text)
                    result = subprocess.run([str(BINARY), str(source)], cwd=folder, capture_output=True, text=True, timeout=15)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn(expected[file], result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
