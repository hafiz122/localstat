import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
ZIG = ROOT / ".toolchain/zig-aarch64-macos-0.16.0/zig"


class CorpusInventoryTests(unittest.TestCase):
    def test_missing_expected_output_fails_the_corpus(self):
        with tempfile.TemporaryDirectory() as directory:
            (pathlib.Path(directory) / "unreviewed.sas").write_text(
                "data _null_; run;\n", encoding="utf-8"
            )
            result = subprocess.run(
                [str(ZIG), "run", "tests/corpus_runner.zig", "--", "/usr/bin/true", directory],
                cwd=ROOT / "vendor/opensas",
                capture_output=True,
                text=True,
                check=False,
            )
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertIn("no expected", result.stderr)


if __name__ == "__main__":
    unittest.main()
