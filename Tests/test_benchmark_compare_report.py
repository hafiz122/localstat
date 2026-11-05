"""Before/after reporting must preserve pagination and complete repetitions."""
import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))


class ComparisonReportTests(unittest.TestCase):
    def report(self):
        path = ROOT/'scripts/benchmark_compare_report.py'
        self.assertTrue(path.exists(), 'The before/after report generator must exist')
        spec = importlib.util.spec_from_file_location('benchmark_compare_report', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def samples(self):
        configurations = [('data', 10000, ['runner', 'app']),
                          ('freq', 100000, ['runner', 'app', 'layout']),
                          ('print', 1000, ['runner', 'app', 'layout']),
                          ('print', 10000, ['runner', 'app', 'layout'])]
        return [dict(workload=name, rows=size, variant=variant, build=build,
                     block=1, iteration=i, phase='measured', status='ok',
                     stdout_sha256='same', page_count=400, wall_s=wall)
                for name, size, variants in configurations for variant in variants
                for build, wall in [('before', 0.3), ('after', 0.1)] for i in range(3)]

    def test_rejects_missing_native_configurations(self):
        report = self.report()
        rows = self.samples()
        self.assertEqual(len(report.native_comparisons(rows, 3)), 11)
        configurations = {(r['workload'], r['rows'], r['variant']) for r in rows}
        for missing in sorted(configurations):
            remaining = [r for r in rows if (r['workload'], r['rows'], r['variant']) != missing]
            with self.subTest(missing=missing), self.assertRaisesRegex(ValueError, 'native configurations'):
                report.native_comparisons(remaining, 3)
        remaining = [r for r in rows if (r['workload'], r['rows']) != ('print', 10000)]
        with self.assertRaisesRegex(ValueError, 'native configurations'):
            report.native_comparisons(remaining, 3)

    def test_rejects_empty_native_evidence(self):
        with self.assertRaisesRegex(ValueError, 'native configurations'):
            self.report().native_comparisons([], 3)

    def test_rejects_changed_pagination_or_missing_repetitions(self):
        report = self.report()
        rows = self.samples()
        report.native_comparisons(rows, 3)
        with self.assertRaises(ValueError):
            report.native_comparisons(rows[:-1], 3)
        rows[-1]['page_count'] = 401
        with self.assertRaises(ValueError):
            report.native_comparisons(rows, 3)

    def test_speedup_uses_median_latency_not_first_run(self):
        report = self.report()
        rows = self.samples()
        rows.append(dict(rows[0], phase='first', wall_s=50))
        result = report.native_comparisons(rows, 3)[0]
        self.assertAlmostEqual(result['speedup'], 3)
        self.assertEqual(result['before']['median_s'], 0.3)

    def test_rejects_before_after_output_mismatch(self):
        report = self.report()
        rows = self.samples()
        rows[-1]['stdout_sha256'] = 'changed'
        with self.assertRaises(ValueError):
            report.native_comparisons(rows, 3)


if __name__ == '__main__':
    unittest.main(verbosity=2)
