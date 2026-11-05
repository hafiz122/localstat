"""Reject incomplete or mismatched measurements before generating paper tables."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
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

    def cases(self):
        return [dict(name=name, rows=rows,
                     variants=['plain', 'tables'] if name in ['freq', 'print'] else ['plain'])
                for name in ['data', 'sort', 'group', 'join', 'reg', 'csv', 'freq', 'print']
                for rows in ([1000, 10000] if name == 'print' else [10000, 100000, 1000000])]

    def samples(self):
        cli = [dict(workload=case['name'], rows=case['rows'], variant=variant, phase='measured',
                    iteration=i, status='ok', stdout_sha256='expected', wall_s=i+1,
                    user_s=0.5, system_s=0.1, peak_rss_bytes=1024)
               for case in self.cases() for variant in case['variants'] for i in range(3)]
        ui = [dict(workload=name, rows=rows, variant=variant, phase='measured',
                   iteration=i, status='ok', stdout_sha256='expected', wall_s=i+1)
              for name, rows in [('data', 10000), ('freq', 100000), ('print', 1000), ('print', 10000)]
              for variant in ['runner', 'app'] for i in range(3)]
        return cli, ui

    def test_rejects_missing_native_configurations(self):
        report = self.report()
        cli, ui = self.samples()
        keys = {(row['workload'], row['rows'], row['variant']) for row in ui}
        for key in sorted(keys):
            with self.subTest(configuration=key):
                incomplete = [row for row in ui if (row['workload'], row['rows'], row['variant']) != key]
                with self.assertRaisesRegex(ValueError, 'native configurations'):
                    report.audit(cli, incomplete, 3, self.cases())

    def test_generate_rejects_missing_cli_manifest_variant_with_matching_summary(self):
        report = self.report()
        cli, ui = self.samples()
        cli = [row for row in cli if (row['workload'], row['rows'], row['variant']) != ('freq', 1000000, 'tables')]
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / 'cli').mkdir()
            (directory / 'cli/runs.jsonl').write_text(''.join(json.dumps(row)+'\n' for row in cli))
            (directory / 'cli/workloads.json').write_text(json.dumps(self.cases()))
            (directory / 'cli/metadata.json').write_text(json.dumps(dict(repetitions=3)))
            (directory / 'cli/summary.json').write_text(json.dumps(report.summarize(cli)))
            (directory / 'ui-runs.json').write_text(json.dumps(ui))
            with self.assertRaisesRegex(ValueError, 'CLI configurations'), contextlib.redirect_stdout(io.StringIO()):
                report.generate(directory)

    def test_rejects_inconsistent_cli_stdout_hashes(self):
        report = self.report()
        cli, ui = self.samples()
        cli[0]['stdout_sha256'] = 'different'
        with self.assertRaisesRegex(ValueError, 'CLI output changed'):
            report.audit(cli, ui, 3, self.cases())

    def test_generate_rejects_unpaired_iterations_before_creating_artifacts(self):
        report = self.report()
        for source, key in [('CLI', ('print', 10000, 'tables')),
                            ('native', ('print', 10000, 'app'))]:
            with self.subTest(source=source), tempfile.TemporaryDirectory() as temporary:
                cli, ui = self.samples()
                for row in cli if source == 'CLI' else ui:
                    if (row['workload'], row['rows'], row['variant']) == key:
                        row['iteration'] += 1
                directory = Path(temporary)
                (directory / 'cli').mkdir()
                (directory / 'cli/runs.jsonl').write_text(''.join(json.dumps(row)+'\n' for row in cli))
                (directory / 'cli/workloads.json').write_text(json.dumps(self.cases()))
                (directory / 'cli/metadata.json').write_text(json.dumps(dict(repetitions=3)))
                (directory / 'cli/summary.json').write_text(json.dumps(report.summarize(cli)))
                (directory / 'ui-runs.json').write_text(json.dumps(ui))
                inputs = set(directory.rglob('*'))
                with self.assertRaisesRegex(ValueError, 'Unpaired'), contextlib.redirect_stdout(io.StringIO()):
                    report.generate(directory)
                self.assertEqual(set(directory.rglob('*')), inputs)

    def test_cli_configurations_follow_the_supplied_manifest(self):
        report = self.report()
        cli, ui = self.samples()
        native_cases = {(row['workload'], row['rows']) for row in ui}
        cases = [dict(name=name, rows=rows, variants=['plain']) for name, rows in sorted(native_cases)]
        cli = [row for row in cli if (row['workload'], row['rows']) in native_cases and row['variant'] == 'plain']
        cases.append(dict(name='custom', rows=200, variants=['plain']))
        cli.extend(dict(cli[0], workload='custom', rows=200, iteration=i) for i in range(3))
        report.audit(cli, ui, 3, cases)

    def test_rejects_incomplete_repetitions_and_duplicate_iterations(self):
        report = self.report()
        cli, ui = self.samples()
        report.audit(cli, ui, 3, self.cases())
        with self.assertRaisesRegex(ValueError, 'Incomplete or duplicated measured iterations'):
            report.audit(cli[:-1], ui, 3, self.cases())
        cli[-1]['iteration'] = 0
        with self.assertRaisesRegex(ValueError, 'Incomplete or duplicated measured iterations'):
            report.audit(cli, ui, 3, self.cases())

    def test_rejects_invalid_results_and_mismatched_app_output(self):
        report = self.report()
        cli, ui = self.samples()
        ui[0]['stdout_sha256'] = 'different'
        with self.assertRaisesRegex(ValueError, 'Native app output does not match'):
            report.audit(cli, ui, 3, self.cases())
        ui[0]['stdout_sha256'] = 'expected'
        cli[0]['status'] = 'invalid'
        with self.assertRaisesRegex(ValueError, 'Failed or timed-out samples'):
            report.audit(cli, ui, 3, self.cases())

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
