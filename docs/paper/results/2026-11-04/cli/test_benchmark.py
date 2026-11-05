"""Checks that benchmark failures cannot become accepted performance samples."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BenchmarkTests(unittest.TestCase):
    def harness(self):
        path = ROOT / "scripts/benchmark.py"
        self.assertTrue(path.exists(), "The benchmark harness must exist")
        spec = importlib.util.spec_from_file_location("benchmark", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_summary_excludes_first_warmup_failure_and_timeout(self):
        bench = self.harness()
        samples = [dict(workload="data", rows=10, variant="plain", phase=phase,
                        status=status, wall_s=wall, user_s=0.1, system_s=0.01,
                        peak_rss_bytes=1024)
                   for phase, status, wall in [("first", "ok", 100), ("warmup", "ok", 100),
                                               ("measured", "invalid", 100), ("measured", "timeout", 100),
                                               ("measured", "ok", 1), ("measured", "ok", 3),
                                               ("measured", "ok", 5), ("measured", "ok", 7)]]
        result = bench.summarize(samples)[0]
        self.assertEqual(result["accepted"], 4)
        self.assertEqual(result["invalid"], 1)
        self.assertEqual(result["timeouts"], 1)
        self.assertEqual(result["median_s"], 4)
        self.assertEqual(result["q1_s"], 2.5)
        self.assertEqual(result["q3_s"], 5.5)

    def test_runner_collects_per_child_usage_and_captures_output(self):
        bench = self.harness()
        with tempfile.TemporaryDirectory() as folder:
            result = bench.measure([sys.executable, "-c", "print('CHECK 10 55')"], Path(folder), 5)
        self.assertEqual(result["returncode"], 0)
        self.assertEqual(result["stdout"], "CHECK 10 55\n")
        self.assertFalse(result["timed_out"])
        self.assertGreater(result["wall_s"], 0)
        self.assertGreater(result["peak_rss_bytes"], 0)
        self.assertGreaterEqual(result["user_s"], 0)

    def test_runner_enforces_timeout(self):
        bench = self.harness()
        with tempfile.TemporaryDirectory() as folder:
            result = bench.measure([sys.executable, "-c", "import time; time.sleep(10)"], Path(folder), 0.1)
        self.assertTrue(result["timed_out"])
        self.assertNotEqual(result["returncode"], 0)
        self.assertLess(result["wall_s"], 3)

    def test_existing_experiment_is_never_overwritten(self):
        self.harness()
        import subprocess
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            (path / 'metadata.json').write_text('original evidence')
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/benchmark.py'),
                                     '--output', folder, '--work', str(path / 'work'),
                                     '--sizes', '200', '--warmups', '0', '--repetitions', '1'],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Refusing to overwrite', result.stderr)
            self.assertEqual((path / 'metadata.json').read_text(), 'original evidence')

    def test_validator_rejects_plausible_but_wrong_results_and_diagnostics(self):
        bench = self.harness()
        case = {"name": "data", "rows": 10, "expected": [10, 185]}
        bench.validate(case, "CHECK 10 185\n", "", None)
        for output, errors in [("CHECK 10 184\n", ""), ("", ""),
                               ("CHECK 10 185\n", "ERROR: calculation failed")]:
            with self.subTest(output=output, errors=errors), self.assertRaises(ValueError):
                bench.validate(case, output, errors, None)

    def test_anova_error_row_is_not_a_runtime_diagnostic(self):
        bench = self.harness()
        case = {"name": "reg", "rows": 10000, "expected": [10000, 50005000]}
        output = ("CHECK 10000 50005000\nError\t9997\t10000.0000000000\t1.0\n"
                  "Intercept\t1\t2.0\n" "x\t1\t3.0\n" "z\t1\t-4.0\n")
        bench.validate(case, output, "", None)

    def test_table_validator_rejects_shape_and_frequency_corruption(self):
        bench = self.harness()
        case = {"name": "freq", "rows": 10000, "expected": [10000, 50005000]}
        headers = [{"cells": [{"text": "Group", "span": 1}, {"text": "Frequency", "span": 1}]}]
        rows = [{"kind": "data", "cells": [{"text": str(i), "span": 1}, {"text": "100", "span": 1}]} for i in range(100)]
        table = {"version": 1, "tables": [{"procedure": "FREQ", "headers": headers, "rows": rows}]}
        listing = "CHECK 10000 50005000\n" + '\n'.join(f'{i} 100 1.00 {(i+1)*100} {i+1}.00' for i in range(100))
        bench.validate(case, listing, "", table)
        rows[0]["cells"][1]["text"] = "99"
        with self.assertRaises(ValueError):
            bench.validate(case, listing, "", table)
        rows[0]["cells"][1]["text"] = "100"
        rows[0]["cells"][1]["span"] = 2
        with self.assertRaises(ValueError):
            bench.validate(case, listing, "", table)

    def test_plain_frequency_listing_must_match_all_expected_groups(self):
        bench = self.harness()
        case = {"name": "freq", "rows": 10000, "expected": [10000, 50005000]}
        with self.assertRaises(ValueError):
            bench.validate(case, 'CHECK 10000 50005000\n0 99 1.00 99 1.00\n', '', None)

    def test_prepared_inputs_are_deterministic_and_join_is_bounded(self):
        bench = self.harness()
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            ca = bench.prepare(Path(a), [10000])
            cb = bench.prepare(Path(b), [10000])
            self.assertEqual(ca, cb)
            self.assertEqual(len((Path(a) / '10000/input.csv').read_text().splitlines()), 10001)
            dimension = (Path(a) / '10000/dimension.csv').read_text().splitlines()
            self.assertEqual(len(dimension), 101)
            self.assertEqual(len(set(line.split(',')[0] for line in dimension[1:])), 100)
            self.assertEqual({case['name'] for case in ca},
                             {'data', 'sort', 'group', 'join', 'reg', 'csv', 'freq', 'print', 'example'})


if __name__ == '__main__':
    unittest.main(verbosity=2)
