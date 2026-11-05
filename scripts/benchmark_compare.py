#!/usr/bin/env python3
"""Interleave before/after interpreter builds on identical validated workloads."""
import argparse
import collections
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

from benchmark import ROOT, digest, measure, metadata, prepare, summarize, validate, validate_csv


NATIVE_VARIANTS = {('data', 10000): ('runner', 'app'),
                   ('freq', 100000): ('runner', 'app', 'layout'),
                   ('print', 1000): ('runner', 'app', 'layout'),
                   ('print', 10000): ('runner', 'app', 'layout')}


def schedule(cases, warmups, repetitions):
    phases = ['first'] + ['warmup']*warmups + ['measured']*repetitions
    for case in cases:
        for iteration, phase in enumerate(phases):
            variants = case['variants'] if iteration % 2 == 0 else list(reversed(case['variants']))
            builds = ['before', 'after'] if iteration % 2 == 0 else ['after', 'before']
            for variant in variants:
                for build in builds:
                    yield case, phase, iteration, variant, build


def audit(samples, cases, warmups, repetitions):
    expected = {(c['name'], c['rows'], variant, build): [] for c in cases
                for variant in c['variants'] for build in ['before', 'after']}
    hashes = collections.defaultdict(set)
    for row in samples:
        key = row['workload'], row['rows'], row['variant'], row['build']
        if key not in expected or row['status'] != 'ok':
            raise ValueError('Unexpected, failed, or timed-out comparison observation')
        expected[key].append(row)
        hashes[key[:3]].add((row['stdout_sha256'], row['stderr_sha256'], row['sidecar_sha256']))
    phases = ['first'] + ['warmup']*warmups + ['measured']*repetitions
    expected_pairs = collections.Counter((phase, iteration) for iteration, phase in enumerate(phases))
    for rows in expected.values():
        if collections.Counter((row['phase'], row['iteration']) for row in rows) != expected_pairs:
            raise ValueError('Incomplete, duplicated, or unexpected comparison phase/iteration pairs')
    if any(len(values) != 1 for values in hashes.values()):
        raise ValueError('Output or sidecar changed between builds or iterations')


def comparisons(samples):
    summaries = {build: {(r['workload'], r['rows'], r['variant']): r
                         for r in summarize([s for s in samples if s['build'] == build])}
                 for build in ['before', 'after']}
    if summaries['before'].keys() != summaries['after'].keys():
        raise ValueError('Before/after configurations differ')
    result = []
    for key in sorted(summaries['before']):
        before, after = summaries['before'][key], summaries['after'][key]
        item = dict(workload=key[0], rows=key[1], variant=key[2], before=before, after=after)
        if before.get('median_s') and after.get('median_s'):
            item.update(speedup=before['median_s']/after['median_s'],
                        memory_reduction_pct=100*(1-after['median_peak_rss_bytes']/before['median_peak_rss_bytes']))
        result.append(item)
    return result


def native_blocks(repetitions):
    first, second = (repetitions+1)//2, repetitions//2
    return [(build, count, block) for build, count, block in
            [('before', first, 1), ('after', first, 1), ('after', second, 2), ('before', second, 2)] if count]


def run_native(args, cases, work, output, binaries, cli_samples):
    wanted = set(NATIVE_VARIANTS)
    selected = [c for c in cases if (c['name'], c['rows']) in wanted]
    if len(selected) != 4:
        raise ValueError('Native comparison requires sizes 1000, 10000, and 100000')
    packages = dict(before=args.native_before.resolve(), after=args.native_after.resolve())
    hashes = {(r['workload'], r['rows'], r['stdout_sha256']) for r in cli_samples}
    samples = []
    for build, count, block in native_blocks(args.repetitions):
        result_path = output/f'native-{build}-{block}.json'
        config_path = output/f'native-{build}-{block}-config.json'
        config = dict(binary=str(binaries[build]), work=str(work), output=str(result_path),
                      cases=selected, warmups=args.warmups, repetitions=count, measure_layout=True)
        config_path.write_text(json.dumps(config, indent=2)+'\n')
        print(f'Native {build} block {block}: {count} measured repetitions', flush=True)
        command = ['swift', 'test', '--skip-build', '--package-path', str(packages[build]),
                   '-c', 'release', '--filter', 'BenchmarkIntegrationTests/testMeasuredRuns']
        result = subprocess.run(command, env=dict(os.environ, LOCALSTAT_BENCHMARK_CONFIG=str(config_path)),
                                capture_output=True, text=True, timeout=300)
        (output/f'native-{build}-{block}.log').write_text(result.stdout+result.stderr)
        if result.returncode != 0:
            raise ValueError(f'Native benchmark failed: {build} block {block}')
        for row in json.loads(result_path.read_text()):
            if row['status'] != 'ok' or (row['workload'], row['rows'], row['stdout_sha256']) not in hashes:
                raise ValueError('Native output differs from validated CLI result')
            samples.append(dict(build=build, block=block, **row))
    for (name, size), variants in NATIVE_VARIANTS.items():
        for build in ['before', 'after']:
            for variant in variants:
                rows = [r for r in samples if (r['workload'], r['rows'], r['build'], r['variant'], r['phase']) ==
                        (name, size, build, variant, 'measured')]
                if len(rows) != args.repetitions or len({(r['block'], r['iteration']) for r in rows}) != args.repetitions:
                    raise ValueError('Incomplete native comparison')
    for name, size in wanted - {('data', 10000)}:
        pages = {r['page_count'] for r in samples if r['workload'] == name and r['rows'] == size and r['variant'] == 'layout'}
        if len(pages) != 1 or min(pages) <= 0:
            raise ValueError('Before/after table pagination changed')
    (output/'native-runs.json').write_text(json.dumps(samples, indent=2)+'\n')


def run(args):
    output, work = args.output.resolve(), args.work.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise SystemExit('Refusing to overwrite an existing comparison')
    binaries = dict(before=args.before.resolve(), after=args.after.resolve())
    cases = prepare(work, args.sizes)
    meta = metadata(binaries['after'])
    meta.update(before_executable_sha256=digest(binaries['before']),
                after_executable_sha256=digest(binaries['after']),
                warmups=args.warmups, repetitions=args.repetitions, timeout_s=args.timeout,
                protocol='Within each case/variant/iteration, adjacent builds alternate before-after and after-before')
    (output/'metadata.json').write_text(json.dumps(meta, indent=2)+'\n')
    (output/'workloads.json').write_text(json.dumps(cases, indent=2)+'\n')
    programs = output/'programs'
    programs.mkdir()
    for case in cases:
        (programs/f'{case["name"]}-{case["rows"]}.sas').write_bytes((work/case['directory']/case['source']).read_bytes())
    samples = []
    previous = None
    with (output/'runs.jsonl').open('x') as stream:
        for case, phase, iteration, variant, build in schedule(cases, args.warmups, args.repetitions):
            label = (case['name'], case['rows'])
            if label != previous:
                print(f'{case["name"]} n={case["rows"]}', flush=True)
                previous = label
            folder = work/case['directory']
            sidefile = folder/'tables.json'
            sidefile.unlink(missing_ok=True)
            (folder/'roundtrip.csv').unlink(missing_ok=True)
            command = [str(binaries[build]), case['source']]
            if variant == 'tables':
                command += ['--tables-json', 'tables.json']
            result = measure(command, folder, args.timeout)
            status, reason, sidehash = 'ok', '', None
            try:
                if result['timed_out']:
                    status = 'timeout'
                elif result['returncode'] != 0:
                    raise ValueError(f'Exit {result["returncode"]}')
                else:
                    sidecar = json.loads(sidefile.read_text()) if variant == 'tables' else None
                    validate(case, result['stdout'], result['stderr'], sidecar,
                             require_tables=variant == 'tables')
                    if sidecar is not None:
                        sidehash = hashlib.sha256(json.dumps(sidecar, sort_keys=True).encode()).hexdigest()
                    if case['name'] == 'csv':
                        validate_csv(folder/'roundtrip.csv', case['rows'])
            except (ValueError, KeyError, OSError) as error:
                status, reason = 'invalid', str(error)
            stdout, stderr = result.pop('stdout'), result.pop('stderr')
            row = dict(workload=case['name'], rows=case['rows'], build=build,
                       phase=phase, iteration=iteration, variant=variant, status=status, reason=reason,
                       stdout_sha256=hashlib.sha256(stdout.encode()).hexdigest(),
                       stderr_sha256=hashlib.sha256(stderr.encode()).hexdigest(), sidecar_sha256=sidehash,
                       stdout_bytes=len(stdout.encode()), tables_bytes=sidefile.stat().st_size if sidefile.exists() else 0,
                       **result)
            samples.append(row)
            stream.write(json.dumps(row)+'\n')
            stream.flush()
            if status != 'ok':
                (output/f'failure-{case["name"]}-{case["rows"]}-{build}-{iteration}-{variant}.txt').write_text(reason+'\n'+stderr+'\n'+stdout)
                print(f'  {build} {phase}: {status} {reason}', flush=True)
    summary = comparisons(samples)
    (output/'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
    audit(samples, cases, args.warmups, args.repetitions)
    meta['cli_finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    if args.native_before:
        run_native(args, cases, work, output, binaries, samples)
    meta['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    (output/'metadata.json').write_text(json.dumps(meta, indent=2)+'\n')
    print(f'Validated {len(samples)} interleaved samples across {len(summary)} configurations per build.', flush=True)
    return 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--after', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--native-before', type=Path, help='Precompiled baseline Swift package with release tests')
    parser.add_argument('--native-after', type=Path, help='Precompiled optimized Swift package with release tests')
    parser.add_argument('--work', type=Path, default=ROOT/'dist/benchmarks/optimization-workloads')
    parser.add_argument('--sizes', type=int, nargs='+', default=[1000, 10000, 100000, 1000000])
    parser.add_argument('--warmups', type=int, default=3)
    parser.add_argument('--repetitions', type=int, default=15)
    parser.add_argument('--timeout', type=float, default=60)
    args = parser.parse_args()
    if sys.platform != 'darwin' or args.warmups < 0 or args.repetitions < 1 or args.timeout <= 0:
        parser.error('macOS, warmups >= 0, repetitions >= 1, timeout > 0 required')
    if bool(args.native_before) != bool(args.native_after):
        parser.error('Supply both native package paths or neither')
    args.work.mkdir(parents=True, exist_ok=True)
    with (args.work/'.benchmark.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit('Another benchmark is using this workload directory')
        raise SystemExit(run(args))
