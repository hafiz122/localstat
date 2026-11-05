#!/usr/bin/env python3
"""Audit experiment evidence and regenerate the LaTeX measurement tables."""
import argparse
import collections
import json
from pathlib import Path
import statistics

from benchmark import summarize


def audit(cli, ui, repetitions, cases):
    if not cli or not ui:
        raise ValueError('Both CLI and native app evidence are required')
    hashes = collections.defaultdict(set)
    for sample in cli:
        hashes[sample['workload'], sample['rows']].add(sample['stdout_sha256'])
    if any(len(values) != 1 for values in hashes.values()):
        raise ValueError('CLI output changed for the same workload and row count')
    expected_cli = {(case['name'], case['rows'], variant)
                    for case in cases for variant in case['variants']}
    expected_ui = {(name, rows, variant)
                   for name, rows in [('data', 10000), ('freq', 100000), ('print', 1000), ('print', 10000)]
                   for variant in ['runner', 'app']}
    for label, samples, expected in [('CLI', cli, expected_cli), ('native', ui, expected_ui)]:
        groups = collections.defaultdict(list)
        for sample in samples:
            if sample['status'] != 'ok':
                raise ValueError('Failed or timed-out samples must be reported, not silently accepted')
            if samples is ui and sample['stdout_sha256'] not in hashes[sample['workload'], sample['rows']]:
                raise ValueError('Native app output does not match validated CLI output')
            if sample['phase'] == 'measured':
                groups[sample['workload'], sample['rows'], sample['variant']].append(sample)
        if not groups:
            raise ValueError('No measured samples')
        observed = set(groups)
        if observed != expected:
            raise ValueError(f'Missing or unexpected {label} configurations: '
                             f'missing={sorted(expected-observed)}, unexpected={sorted(observed-expected)}')
        for group in groups.values():
            if len(group) != repetitions or len({sample['iteration'] for sample in group}) != repetitions:
                raise ValueError('Incomplete or duplicated measured iterations')
        left, right = ('plain', 'tables') if label == 'CLI' else ('runner', 'app')
        for name, rows, variant in expected:
            if variant != right:
                continue
            left_iterations = {sample['iteration'] for sample in groups[name, rows, left]}
            right_iterations = {sample['iteration'] for sample in groups[name, rows, right]}
            if left_iterations != right_iterations:
                raise ValueError('Unpaired variants')


def paired(rows, left, right):
    groups = {variant: {r['iteration']: r['wall_s'] for r in rows
                        if r['phase'] == 'measured' and r['variant'] == variant}
              for variant in [left, right]}
    if groups[left].keys() != groups[right].keys():
        raise ValueError('Unpaired variants')
    return [groups[right][i] - groups[left][i] for i in sorted(groups[left])]


def distribution(values):
    q = statistics.quantiles(values, n=4, method='inclusive')
    return dict(median_s=statistics.median(values), q1_s=q[0], q3_s=q[2])


def milliseconds(value):
    median = round(value['median_s']*1000, 1)
    if median == 0:
        median = 0.0
    return f'{median:.1f} ({(value["q3_s"]-value["q1_s"])*1000:.1f})'


def table(headers, rows):
    return ('\\begin{tabular}{l' + 'r'*(len(headers)-1) + '}\n\\toprule\n' +
            ' & '.join(headers) + ' \\\\\n\\midrule\n' +
            ''.join(' & '.join(map(str, row)) + ' \\\\\n' for row in rows) +
            '\\bottomrule\n\\end{tabular}\n')


def generate(directory):
    cli = [json.loads(line) for line in (directory / 'cli/runs.jsonl').read_text().splitlines()]
    ui = json.loads((directory / 'ui-runs.json').read_text())
    meta = json.loads((directory / 'cli/metadata.json').read_text())
    cases = json.loads((directory / 'cli/workloads.json').read_text())
    audit(cli, ui, meta['repetitions'], cases)
    summary = summarize(cli)
    if summary != json.loads((directory / 'cli/summary.json').read_text()):
        raise ValueError('Saved CLI summary does not match raw measurements')
    lookup = {(r['workload'], r['rows'], r['variant']): r for r in summary}
    labels = dict(data='DATA transform', sort='SORT', group='SQL grouping', join='SQL join',
                  reg='REG (two predictors)', csv='CSV round trip', freq='FREQ', print='PRINT')
    rows = []
    for name in ['data', 'sort', 'group', 'join', 'reg', 'csv', 'freq']:
        rows.append([labels[name]] + [milliseconds(lookup[name, n, 'plain']) for n in [10000, 100000, 1000000]] +
                    [f'{lookup[name, 1000000, "plain"]["median_peak_rss_bytes"] / 2**20:.1f}'])
    (directory / 'cli-timings.tex').write_text(table(['Workload', '10,000', '100,000', '1,000,000', 'MiB'], rows))
    pairs = []
    pair_results = []
    for name, n in sorted({(r['workload'], r['rows']) for r in cli if r['variant'] == 'tables'}):
        selected = [r for r in cli if r['workload'] == name and r['rows'] == n]
        delta = distribution(paired(selected, 'plain', 'tables'))
        pairs.append([f'{labels[name]} ({n:,})', milliseconds(lookup[name, n, 'plain']),
                      milliseconds(lookup[name, n, 'tables']), milliseconds(delta)])
        pair_results.append(dict(workload=name, rows=n, **delta))
    (directory / 'table-costs.tex').write_text(table(['Workload', 'Plain', 'Sidecar', r'Paired $\Delta$'], pairs))
    (directory / 'paired-sidecar.json').write_text(json.dumps(pair_results, indent=2)+'\n')
    ui_rows = []
    ui_summary = []
    for name, n in sorted({(r['workload'], r['rows']) for r in ui}):
        selected = [r for r in ui if r['workload'] == name and r['rows'] == n]
        stats = {variant: distribution([r['wall_s'] for r in selected if r['phase'] == 'measured' and r['variant'] == variant])
                 for variant in ['runner', 'app']}
        delta = distribution(paired(selected, 'runner', 'app'))
        ui_rows.append([f'{labels[name]} ({n:,})', milliseconds(stats['runner']), milliseconds(stats['app']), milliseconds(delta)])
        ui_summary.append(dict(workload=name, rows=n, runner=stats['runner'], app=stats['app'], paired_delta=delta))
    (directory / 'ui-timings.tex').write_text(table(['Workload', 'Native runner', 'Application', r'Paired $\Delta$'], ui_rows))
    (directory / 'ui-summary.json').write_text(json.dumps(ui_summary, indent=2)+'\n')
    print(f'Audited {len(cli)} CLI and {len(ui)} native samples; regenerated three LaTeX tables.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    generate(parser.parse_args().directory)
