"""Checks for the controlled before/after benchmark protocol."""
import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))


class ComparisonTests(unittest.TestCase):
    def harness(self):
        path = ROOT / 'scripts/benchmark_compare.py'
        self.assertTrue(path.exists(), 'The controlled comparison harness must exist')
        spec = importlib.util.spec_from_file_location('benchmark_compare', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_builds_are_adjacent_and_alternate_order(self):
        bench = self.harness()
        case = dict(name='freq', rows=1000, variants=['plain', 'tables'])
        rows = list(bench.schedule([case], 3, 15))
        self.assertEqual(len(rows), 76)
        self.assertEqual(sum(row[1] == 'measured' for row in rows), 60)
        for left, right in zip(rows[::2], rows[1::2]):
            self.assertEqual(left[:4], right[:4])
            self.assertEqual([left[4], right[4]], ['before', 'after'] if left[2] % 2 == 0 else ['after', 'before'])

    def test_auditor_rejects_missing_build_or_output_change(self):
        bench = self.harness()
        case = dict(name='data', rows=1000, variants=['plain'])
        rows = [dict(workload=c['name'], rows=c['rows'], phase=phase, iteration=i,
                     variant=variant, build=build, status='ok', stdout_sha256='same',
                     stderr_sha256='same', sidecar_sha256=None)
                for c, phase, i, variant, build in bench.schedule([case], 0, 2)]
        bench.audit(rows, [case], 0, 2)
        with self.assertRaises(ValueError):
            bench.audit(rows[:-1], [case], 0, 2)
        rows[-1]['stdout_sha256'] = 'different'
        with self.assertRaises(ValueError):
            bench.audit(rows, [case], 0, 2)

    def test_before_after_metrics_use_the_same_units(self):
        bench = self.harness()
        rows = [dict(workload='data', rows=1000, variant='plain', phase='measured',
                     build=build, status='ok', wall_s=wall, user_s=wall,
                     system_s=0, peak_rss_bytes=memory)
                for build, wall, memory in [('before', 4, 2048), ('after', 1, 512)] for _ in range(3)]
        result = bench.comparisons(rows)[0]
        self.assertEqual(result['speedup'], 4)
        self.assertEqual(result['memory_reduction_pct'], 75)

    def test_auditor_requires_scheduled_iteration_ids_for_each_build(self):
        bench = self.harness()
        case = dict(name='data', rows=1000, variants=['plain'])
        for warmups in [0, 2]:
            rows = [dict(workload=c['name'], rows=c['rows'], phase=phase, iteration=i,
                         variant=variant, build=build, status='ok', stdout_sha256='same',
                         stderr_sha256='same', sidecar_sha256=None)
                    for c, phase, i, variant, build in bench.schedule([case], warmups, 3)]
            bench.audit(rows, [case], warmups, 3)
            for build in ['before', 'after']:
                with self.subTest(warmups=warmups, build=build):
                    shifted = [dict(row, iteration=row['iteration']+1) if row['build'] == build else dict(row)
                               for row in rows]
                    with self.assertRaisesRegex(ValueError, 'phase/iteration'):
                        bench.audit(shifted, [case], warmups, 3)

    def test_auditor_rejects_swapped_phase_iteration_pairs(self):
        bench = self.harness()
        case = dict(name='freq', rows=1000, variants=['plain', 'tables'])
        rows = [dict(workload=c['name'], rows=c['rows'], phase=phase, iteration=i,
                     variant=variant, build=build, status='ok', stdout_sha256='same',
                     stderr_sha256='same', sidecar_sha256=None)
                for c, phase, i, variant, build in bench.schedule([case], 2, 3)]
        for build in ['before', 'after']:
            for phase in ['first', 'warmup']:
                with self.subTest(build=build, phase=phase):
                    swapped = [dict(row) for row in rows]
                    selected = [row for row in swapped if row['build'] == build and row['variant'] == 'tables']
                    left = next(row for row in selected if row['phase'] == phase)
                    right = next(row for row in selected if row['phase'] == 'measured')
                    left['phase'], right['phase'] = right['phase'], left['phase']
                    with self.assertRaisesRegex(ValueError, 'phase/iteration'):
                        bench.audit(swapped, [case], 2, 3)

    def test_native_blocks_counterbalance_order_and_keep_fifteen_repetitions(self):
        bench = self.harness()
        self.assertTrue(hasattr(bench, 'native_blocks'))
        blocks = bench.native_blocks(15)
        self.assertEqual([build for build, _, _ in blocks], ['before', 'after', 'after', 'before'])
        for build in ['before', 'after']:
            self.assertEqual(sum(count for name, count, _ in blocks if name == build), 15)


if __name__ == '__main__':
    unittest.main(verbosity=2)
