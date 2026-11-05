"""Checks that benchmark failures cannot become accepted performance samples."""
import importlib.util
import io
import json
from copy import deepcopy
from contextlib import redirect_stdout
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))


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

    def frequency_fixture(self, count=10000):
        case = {"name": "freq", "rows": count, "expected": [count, count*(count+1)//2]}
        headers = [{"kind": "data", "cells": [{"text": text, "span": 1} for text in
                   ["grp", "Frequency", "Percent", "Cumulative Frequency", "Cumulative Percent"]]}]
        rows = [{"kind": "data", "cells": [{"text": str(value), "span": 1} for value in
                 [i, count//100, '1.00', (i+1)*(count//100), f'{i+1}.00']]} for i in range(100)]
        table = {"version": 1, "tables": [{"procedure": "FREQ", "title": "Frequency of grp",
                 "section": "", "headers": headers, "rows": rows, "notes": []}]}
        listing = f'CHECK {count} {count*(count+1)//2}\n' + '\n'.join(f'{i} {count//100} 1.00 {(i+1)*(count//100)} {i+1}.00' for i in range(100))
        return case, listing, table

    def test_table_validator_rejects_shape_and_frequency_corruption(self):
        bench = self.harness()
        case, listing, table = self.frequency_fixture()
        rows = table['tables'][0]['rows']
        bench.validate(case, listing, "", table)
        rows[0]["cells"][1]["text"] = "99"
        with self.assertRaises(ValueError):
            bench.validate(case, listing, "", table)
        rows[0]["cells"][1]["text"] = "100"
        rows[0]["cells"][1]["span"] = 2
        with self.assertRaises(ValueError):
            bench.validate(case, listing, "", table)

    def test_frequency_validator_rejects_duplicate_categories(self):
        bench = self.harness()
        case, listing, table = self.frequency_fixture()
        table['tables'][0]['rows'].append(table['tables'][0]['rows'][0])
        with self.assertRaises(ValueError):
            bench.validate(case, listing, '', table)

    def malformed_sidecars(self):
        _, _, fixture = self.frequency_fixture(200)
        yield 'null tables', dict(version=1, tables=None)
        yield 'object tables', dict(version=1, tables={'0': fixture['tables'][0]})
        yield 'null table', dict(version=1, tables=[None])
        mutations = [
            ('headers', None), ('headers', []), ('headers', {}),
            ('rows', None), ('rows', {}),
        ]
        for key, value in mutations:
            sidecar = deepcopy(fixture)
            sidecar['tables'][0][key] = value
            yield f'{key}={value}', sidecar
        for collection in ['headers', 'rows']:
            for value in [None, [], {'kind': 'data', 'cells': None},
                          {'kind': 'data', 'cells': {}}, {'kind': 1, 'cells': []}]:
                sidecar = deepcopy(fixture)
                sidecar['tables'][0][collection][0] = value
                yield f'{collection} row={value}', sidecar
            for value in [None, [], {'span': 1, 'text': None}, {'span': '1', 'text': '0'},
                          {'span': True, 'text': '0'}, {'span': 1.5, 'text': '0'}]:
                sidecar = deepcopy(fixture)
                sidecar['tables'][0][collection][0]['cells'][0] = value
                yield f'{collection} cell={value}', sidecar

    def test_validator_rejects_malformed_nested_sidecars(self):
        bench = self.harness()
        case, listing, _ = self.frequency_fixture(200)
        for label, sidecar in self.malformed_sidecars():
            with self.subTest(label=label), self.assertRaises(ValueError):
                bench.validate(case, listing, '', sidecar, require_tables=True)

    def test_frequency_validator_checks_percent_and_cumulative_values(self):
        bench = self.harness()
        for column in [2, 3, 4]:
            for value in ['WRONG', '999', 'nan', 'inf']:
                case, listing, sidecar = self.frequency_fixture()
                sidecar['tables'][0]['rows'][0]['cells'][column]['text'] = value
                with self.subTest(column=column, value=value), self.assertRaises(ValueError):
                    bench.validate(case, listing, '', sidecar)

    def test_frequency_validator_requires_all_five_unspanned_columns(self):
        bench = self.harness()
        for keep in [2, 3, 4]:
            case, listing, sidecar = self.frequency_fixture()
            table = sidecar['tables'][0]
            for row in table['headers'] + table['rows']:
                row['cells'] = row['cells'][:keep]
                row['cells'][-1]['span'] = 6-keep
            with self.subTest(keep=keep), self.assertRaises(ValueError):
                bench.validate(case, listing, '', sidecar)

    def assert_runner_rejects(self, workload, listing, sidecar=None):
        for script in ['benchmark', 'benchmark_compare']:
            with self.subTest(script=script), tempfile.TemporaryDirectory() as temporary:
                folder = Path(temporary)
                spec = importlib.util.spec_from_file_location(script, ROOT/'scripts'/f'{script}.py')
                bench = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(bench)
                work = folder/'work'
                work.mkdir()
                cases = [case for case in bench.prepare(work, [200]) if case['name'] == workload]
                binary = folder/'interpreter'
                binary.write_text(f'#!{sys.executable}\nfrom pathlib import Path\n'
                                  f'Path("tables.json").write_text({json.dumps(sidecar)!r})\n'
                                  'Path("roundtrip.csv").write_text("")\n'
                                  f'print({listing!r})\n')
                binary.chmod(0o755)
                args = SimpleNamespace(binary=binary, before=binary, after=binary,
                                       output=folder/'results', work=work, sizes=[200],
                                       only=[workload], profile=False, warmups=0, repetitions=1,
                                       timeout=5, native_before=None, native_after=None)
                with mock.patch.object(bench, 'metadata', return_value={}), \
                        mock.patch.object(bench, 'prepare', return_value=cases), \
                        redirect_stdout(io.StringIO()):
                    if script == 'benchmark':
                        self.assertNotEqual(bench.run(args), 0)
                    else:
                        with self.assertRaises(ValueError):
                            bench.run(args)
                rows = [json.loads(line) for line in (args.output/'runs.jsonl').read_text().splitlines()]
                expected_count = 2 * len(cases[0]['variants']) * (2 if script == 'benchmark_compare' else 1)
                self.assertEqual(len(rows), expected_count)
                for row in rows:
                    expected_status = 'invalid' if workload == 'csv' or row['variant'] == 'tables' else 'ok'
                    self.assertEqual(row['status'], expected_status)
                    if expected_status == 'invalid':
                        self.assertTrue(row['reason'])

    def test_benchmark_runners_reject_null_table_sidecars(self):
        _, listing, _ = self.frequency_fixture(200)
        self.assert_runner_rejects('freq', listing)

    def test_benchmark_runners_record_malformed_sidecars_as_invalid(self):
        _, listing, _ = self.frequency_fixture(200)
        for label, sidecar in self.malformed_sidecars():
            with self.subTest(label=label):
                self.assert_runner_rejects('freq', listing, sidecar)

    def test_csv_validator_rejects_empty_export(self):
        bench = self.harness()
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)/'roundtrip.csv'
            path.write_text('')
            with self.assertRaises(ValueError):
                bench.validate_csv(path, 200)

    def test_benchmark_runners_record_empty_csv_as_invalid(self):
        self.assert_runner_rejects('csv', 'CHECK 200 20100\n')

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
