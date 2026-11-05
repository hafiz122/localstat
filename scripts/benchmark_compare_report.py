#!/usr/bin/env python3
"""Audit controlled optimization runs and generate before/after paper tables."""
import argparse
import collections
import json
from pathlib import Path
import statistics

from benchmark_compare import NATIVE_VARIANTS, audit, comparisons
from benchmark_report import milliseconds, table


def distribution(values):
    q = statistics.quantiles(values, n=4, method='inclusive') if len(values) > 1 else [values[0]]*3
    return dict(median_s=statistics.median(values), q1_s=q[0], q3_s=q[2])


def native_comparisons(samples, repetitions):
    groups = collections.defaultdict(list)
    hashes = collections.defaultdict(set)
    pages = collections.defaultdict(set)
    for row in samples:
        if row['status'] != 'ok':
            raise ValueError('Failed native observation')
        key = row['workload'], row['rows'], row['variant']
        hashes[key[:2]].add(row['stdout_sha256'])
        if row['variant'] == 'layout':
            pages[key[:2]].add(row['page_count'])
        if row['phase'] == 'measured':
            groups[key].append(row)
    expected = {(name, size, variant) for (name, size), variants in NATIVE_VARIANTS.items()
                for variant in variants}
    observed = set(groups)
    if observed != expected:
        raise ValueError(f'Missing or unexpected native configurations: '
                         f'missing={sorted(expected-observed)}, unexpected={sorted(observed-expected)}')
    if any(len(values) != 1 for values in hashes.values()) or any(len(values) != 1 or min(values) <= 0 for values in pages.values()):
        raise ValueError('Native output or pagination changed')
    results = []
    for key, rows in sorted(groups.items()):
        stats = {}
        for build in ['before', 'after']:
            values = [r for r in rows if r['build'] == build]
            if len(values) != repetitions or len({(r['block'], r['iteration']) for r in values}) != repetitions:
                raise ValueError('Incomplete or duplicated native measured repetitions')
            stats[build] = distribution([r['wall_s'] for r in values])
        results.append(dict(workload=key[0], rows=key[1], variant=key[2], **stats,
                            speedup=stats['before']['median_s']/stats['after']['median_s']))
    return results


def generate(directory):
    raw = directory/'measurements'
    samples = [json.loads(line) for line in (raw/'runs.jsonl').read_text().splitlines()]
    cases = json.loads((raw/'workloads.json').read_text())
    meta = json.loads((raw/'metadata.json').read_text())
    audit(samples, cases, meta['warmups'], meta['repetitions'])
    summary = comparisons(samples)
    if summary != json.loads((raw/'summary.json').read_text()):
        raise ValueError('Comparison summary differs from raw observations')
    native = json.loads((raw/'native-runs.json').read_text())
    cli_hashes = {(r['workload'], r['rows'], r['stdout_sha256']) for r in samples}
    if any((r['workload'], r['rows'], r['stdout_sha256']) not in cli_hashes for r in native):
        raise ValueError('Native output does not match validated CLI output')
    ui = native_comparisons(native, meta['repetitions'])
    labels = dict(data='DATA transform', sort='SORT', group='SQL grouping', join='SQL join',
                  reg='REG', csv='CSV round trip', freq='FREQ', print='PRINT')
    lookup = {(r['workload'], r['rows'], r['variant']): r for r in summary}
    latency, memory = [], []
    for name in ['data', 'sort', 'group', 'join', 'reg', 'csv', 'freq']:
        row = lookup[name, 1000000, 'plain']
        latency.append([labels[name], milliseconds(row['before']), milliseconds(row['after']), f'{row["speedup"]:.2f}'])
        memory.append([labels[name], f'{row["before"]["median_peak_rss_bytes"]/2**20:.1f}',
                       f'{row["after"]["median_peak_rss_bytes"]/2**20:.1f}', f'{row["memory_reduction_pct"]:.1f}'])
    (directory/'latency-comparison.tex').write_text(table(['Workload', 'Before', 'After', r'Speedup ($\times$)'], latency))
    (directory/'memory-comparison.tex').write_text(table(['Workload', 'Before (MiB)', 'After (MiB)', r'Reduction (\%)'], memory))
    ui_rows = []
    for row in ui:
        ui_rows.append([f'{labels[row["workload"]]} ({row["rows"]:,})', row['variant'],
                        milliseconds(row['before']), milliseconds(row['after']), f'{row["speedup"]:.2f}'])
    (directory/'native-comparison.tex').write_text(table(['Workload', 'Path', 'Before', 'After', r'Speedup ($\times$)'], ui_rows))
    (directory/'comparison-summary.json').write_text(json.dumps(dict(cli=summary, native=ui), indent=2)+'\n')
    print(f'Audited {len(samples)} CLI and {len(native)} native observations; generated three before/after tables.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    generate(parser.parse_args().directory)
