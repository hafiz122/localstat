"""Reject incomplete or mismatched measurements before generating paper tables."""
import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))


class ReportTests(unittest.TestCase):
    def report(self):
        path = ROOT / 'scripts/benchmark_report.py'
        self.assertTrue(path.exists(), 'The evidence auditor must exist')
        spec = importlib.util.spec_from_file_location('benchmark_report', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def samples(self):
        cli = [dict(workload='data', rows=10000, variant='plain', phase='measured',
                    iteration=i, status='ok', stdout_sha256='expected') for i in range(3)]
        ui = [dict(workload='data', rows=10000, variant=variant, phase='measured',
                   iteration=i, status='ok', stdout_sha256='expected', wall_s=i+1)
              for variant in ['runner', 'app'] for i in range(3)]
        return cli, ui

    def test_rejects_incomplete_repetitions_and_duplicate_iterations(self):
        report = self.report()
        cli, ui = self.samples()
        report.audit(cli, ui, 3)
        with self.assertRaises(ValueError):
            report.audit(cli[:-1], ui, 3)
        cli[-1]['iteration'] = 0
        with self.assertRaises(ValueError):
            report.audit(cli, ui, 3)

    def test_rejects_invalid_results_and_mismatched_app_output(self):
        report = self.report()
        cli, ui = self.samples()
        ui[0]['stdout_sha256'] = 'different'
        with self.assertRaises(ValueError):
            report.audit(cli, ui, 3)
        ui[0]['stdout_sha256'] = 'expected'
        cli[0]['status'] = 'invalid'
        with self.assertRaises(ValueError):
            report.audit(cli, ui, 3)

    def test_paired_differences_match_iterations_rather_than_file_order(self):
        report = self.report()
        rows = [dict(variant=variant, iteration=i, wall_s=value, phase='measured')
                for variant, i, value in [('plain', 4, 1), ('tables', 5, 12),
                                           ('tables', 4, 3), ('plain', 5, 10)]]
        self.assertEqual(report.paired(rows, 'plain', 'tables'), [2, 2])

    def test_rounding_does_not_display_negative_zero_latency(self):
        report = self.report()
        self.assertEqual(report.milliseconds(dict(median_s=-0.00001, q1_s=-0.0001, q3_s=0.0001)), '0.0 (0.2)')


if __name__ == '__main__':
    unittest.main(verbosity=2)
