#!/usr/bin/env python3
"""Deterministic LocalStat workloads and fresh-process measurements on macOS."""
import argparse
import collections
import csv
import datetime
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import signal
import statistics
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def measure(command, cwd, timeout):
    """wait4 supplies per-child counters, including Darwin's RSS in bytes."""
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        start = time.perf_counter_ns()
        child = subprocess.Popen(command, cwd=cwd, stdout=out, stderr=err,
                                 stdin=subprocess.DEVNULL, start_new_session=True)
        expired = threading.Event()

        def stop():
            try:
                os.killpg(child.pid, signal.SIGKILL)
                expired.set()
            except ProcessLookupError:
                pass

        watchdog = threading.Timer(timeout, stop)
        watchdog.start()
        try:
            _, status, usage = os.wait4(child.pid, 0)
            end = time.perf_counter_ns()
            child.returncode = os.waitstatus_to_exitcode(status)
        finally:
            watchdog.cancel()
            watchdog.join()
        out.seek(0)
        err.seek(0)
        return dict(wall_s=(end-start)/1e9, user_s=usage.ru_utime,
                    system_s=usage.ru_stime, peak_rss_bytes=usage.ru_maxrss * (1 if sys.platform == 'darwin' else 1024),
                    returncode=child.returncode, timed_out=expired.is_set(),
                    stdout=out.read().decode('utf-8', errors='replace'),
                    stderr=err.read().decode('utf-8', errors='replace'))


def check_step(dataset, value='id', extras=''):
    return (f"data _null_; set {dataset} end=done; retain n 0 total 0; "
            f"n=n+1; total=total+{value}; {extras} "
            "if done then put 'CHECK ' n best32. total best32.; run;\n")


def prepare(root, sizes):
    cases = []
    example_folder = root / 'example'
    example_folder.mkdir(parents=True, exist_ok=True)
    example = example_folder / 'example.sas'
    example.write_text((ROOT / 'examples/03-multiple-regression.sas').read_text() + '\n' + check_step('experiment', '0'))
    cases.append(dict(name='example', rows=6, directory='example', source=example.name,
                      source_sha256=digest(example), inputs={}, expected=[6, 0], variants=['plain']))
    for n in sorted(set(sizes)):
        if n < 100 or n % 200:
            raise ValueError('Row counts must be positive multiples of 200 (balanced groups and regression design)')
        folder = root / str(n)
        folder.mkdir(parents=True, exist_ok=True)
        with (folder / 'input.csv').open('w') as stream:
            stream.write('id,grp,x,z,y\n')
            for i in range(n):
                x, z, noise = 2*(i % 2)-1, 2*((i//2) % 2)-1, 2*((i//4) % 2)-1
                stream.write(f'{n-i},{i%100},{x},{z},{2+3*x-4*z+noise}\n')
        with (folder / 'dimension.csv').open('w') as stream:
            stream.write('grp,weight\n')
            for i in range(100):
                stream.write(f'{i},{i+1}\n')
        load = "proc import datafile='input.csv' out=base dbms=csv replace; getnames=yes; run;\n"
        total = n*(n+1)//2
        programs = {
            'data': (load + "data result; set base; value=3*id+2; run;\n" + check_step('result', 'value'), [n, 3*total+2*n]),
            'sort': (load + "proc sort data=base out=sorted; by id; run;\n"
                     "data _null_; set sorted end=done; retain n 0 total 0 bad 0; n=n+1; total=total+id; "
                     "if id ne n then bad=bad+1; if done then put 'CHECK ' n best32. total best32. bad best32.; run;\n", [n, total, 0]),
            'group': (load + "proc sql; create table grouped as select grp, count(*) as cnt, sum(id) as subtotal "
                      "from base group by grp; quit;\n"
                      "data _null_; set grouped end=done; retain groups 0 n 0 total 0 bad 0; groups=groups+1; "
                      f"n=n+cnt; total=total+subtotal; expected={n//100}*({n}-grp)-100*{(n//100)*(n//100-1)//2}; "
                      f"if cnt ne {n//100} or subtotal ne expected then bad=bad+1; "
                      "if done then put 'CHECK ' groups best32. n best32. total best32. bad best32.; run;\n", [100, n, total, 0]),
            'join': (load + "proc import datafile='dimension.csv' out=dim dbms=csv replace; getnames=yes; run;\n"
                     "proc sql; create table joined as select a.id, b.weight from base as a inner join dim as b on a.grp=b.grp; quit;\n"
                     "data _null_; set joined end=done; retain n 0 total 0 weights 0 bad 0; n=n+1; total=total+id; weights=weights+weight; "
                     f"if weight ne mod({n}-id,100)+1 then bad=bad+1; "
                     "if done then put 'CHECK ' n best32. total best32. weights best32. bad best32.; run;\n", [n, total, n//100*5050, 0]),
            'reg': (load + check_step('base') + "proc reg data=base; model y=x z; run; quit;\n", [n, total]),
            'csv': (load + "proc export data=base outfile='roundtrip.csv' dbms=csv replace; run;\n"
                    "proc import datafile='roundtrip.csv' out=again dbms=csv replace; getnames=yes; run;\n" + check_step('again'), [n, total]),
            'freq': (load + check_step('base') + "proc freq data=base; tables grp; run;\n", [n, total]),
        }
        if n <= 10000:
            programs['print'] = (load + check_step('base') + 'proc print data=base noobs; run;\n', [n, total])
        input_hashes = {name: digest(folder / name) for name in ['input.csv', 'dimension.csv']}
        for name, (source, expected) in programs.items():
            path = folder / f'{name}.sas'
            path.write_text(source)
            cases.append(dict(name=name, rows=n, directory=str(n), source=path.name,
                              source_sha256=digest(path), inputs=input_hashes, expected=expected,
                              variants=['plain', 'tables'] if name in ['freq', 'print'] else ['plain']))
    return cases


def validate(case, output, errors, sidecar):
    if re.search(r'(?im)^\s*(ERROR|UNSUPPORTED)(?:\([^\n]*\))?\s*:', errors + '\n' + output):
        raise ValueError('Runtime error or unsupported behavior')
    checks = re.findall(r'^CHECK\s+(.+)$', output, re.MULTILINE)
    if len(checks) != 1:
        raise ValueError('Expected exactly one CHECK record')
    values = [float(item) for item in checks[0].split()]
    if values != case['expected']:
        raise ValueError(f'Incorrect CHECK: {values} != {case["expected"]}')
    if case['name'] in ['freq', 'print']:
        listing = []
        for line in output.splitlines():
            cells = line.split()
            if len(cells) == 5:
                try:
                    listing.append([float(cell) for cell in cells])
                except ValueError:
                    pass
        if case['name'] == 'freq':
            expected = [[i, case['rows']//100, 1, (i+1)*(case['rows']//100), i+1] for i in range(100)]
        else:
            expected = [[case['rows']-i, i % 100, 2*(i%2)-1, 2*((i//2)%2)-1,
                         2+3*(2*(i%2)-1)-4*(2*((i//2)%2)-1)+(2*((i//4)%2)-1)] for i in range(case['rows'])]
        if listing != expected:
            raise ValueError('Incorrect procedure listing values')
    if case['name'] in ['reg', 'example']:
        for name, expected in [('Intercept', 2), ('x', 3), ('z', -4)]:
            match = re.search(rf'^{name}\t1\t([^\t\n]+)', output, re.MULTILINE)
            if not match or not math.isclose(float(match[1]), expected, abs_tol=1e-8, rel_tol=1e-8):
                raise ValueError(f'Incorrect regression coefficient {name}')
        error = re.search(r'^Error\t[^\t]+\t([^\t\n]+)', output, re.MULTILINE)
        expected_sse = 12 if case['name'] == 'example' else case['rows']
        if not error or not math.isclose(float(error[1]), expected_sse, rel_tol=1e-8):
            raise ValueError('Incorrect regression residual sum of squares')
    if sidecar is None:
        return
    if sidecar.get('version') != 1 or len(sidecar.get('tables', [])) != 1:
        raise ValueError('Incorrect sidecar version or table count')
    table = sidecar['tables'][0]
    if table['procedure'] != case['name'].upper():
        raise ValueError('Incorrect table procedure')
    width = sum(cell['span'] for cell in table['headers'][-1]['cells'])
    for row in table['headers'] + table['rows']:
        if width <= 0 or any(cell['span'] <= 0 for cell in row['cells']) or sum(cell['span'] for cell in row['cells']) != width:
            raise ValueError('Incorrect table shape')
    rows = [row for row in table['rows'] if row.get('kind', 'data') == 'data']
    if case['name'] == 'freq':
        actual = {}
        for row in rows:
            cells = row['cells']
            actual[int(cells[0]['text'])] = int(cells[1]['text'].replace(',', ''))
        if actual != {i: case['rows']//100 for i in range(100)}:
            raise ValueError('Incorrect frequency counts')
    if case['name'] == 'print':
        if len(rows) != case['rows']:
            raise ValueError('Incorrect printed row count')
        for i, row in enumerate(rows):
            x, z, noise = 2*(i % 2)-1, 2*((i//2) % 2)-1, 2*((i//4) % 2)-1
            expected = [case['rows']-i, i % 100, x, z, 2+3*x-4*z+noise]
            if [float(cell['text']) for cell in row['cells']] != expected:
                raise ValueError('Incorrect printed row values')


def validate_csv(path, n):
    with path.open() as stream:
        reader = csv.reader(stream)
        if [name.lower() for name in next(reader)] != ['id', 'grp', 'x', 'z', 'y']:
            raise ValueError('Incorrect CSV header')
        count = 0
        for i, row in enumerate(reader):
            x, z, noise = 2*(i % 2)-1, 2*((i//2) % 2)-1, 2*((i//4) % 2)-1
            if [float(value) for value in row] != [n-i, i % 100, x, z, 2+3*x-4*z+noise]:
                raise ValueError('Incorrect CSV row')
            count += 1
        if count != n:
            raise ValueError('Incorrect CSV row count')


def summarize(samples):
    groups = collections.defaultdict(list)
    for sample in samples:
        if sample['phase'] == 'measured':
            groups[sample['workload'], sample['rows'], sample['variant']].append(sample)
    results = []
    for (name, rows, variant), values in sorted(groups.items()):
        good = [v for v in values if v['status'] == 'ok']
        result = dict(workload=name, rows=rows, variant=variant, accepted=len(good),
                      invalid=sum(v['status'] == 'invalid' for v in values),
                      timeouts=sum(v['status'] == 'timeout' for v in values))
        if good:
            times = [v['wall_s'] for v in good]
            q = statistics.quantiles(times, n=4, method='inclusive') if len(times) > 1 else [times[0]]*3
            result.update(median_s=statistics.median(times), q1_s=q[0], q3_s=q[2],
                          median_user_s=statistics.median(v['user_s'] for v in good),
                          median_system_s=statistics.median(v['system_s'] for v in good),
                          median_peak_rss_bytes=statistics.median(v['peak_rss_bytes'] for v in good),
                          max_peak_rss_bytes=max(v['peak_rss_bytes'] for v in good))
        results.append(result)
    return results


def capture(command):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else f'unavailable (exit {result.returncode})'


def metadata(binary):
    hardware = json.loads(capture(['system_profiler', 'SPHardwareDataType', '-json']))['SPHardwareDataType'][0]
    files = sorted(set(subprocess.check_output(['git', 'ls-files', '-co', '--exclude-standard'], cwd=ROOT, text=True).splitlines()))
    evidence = {name: digest(ROOT / name) for name in files if (ROOT / name).is_file() and
                (name.startswith(('Sources/', 'vendor/opensas/src/', 'scripts/', 'Tests/', 'examples/')) or
                 name in ['Package.swift', 'vendor/opensas/build.zig', 'vendor/opensas/build.zig.zon'])}
    return dict(started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                source_revision=capture(['git', 'rev-parse', 'HEAD']),
                working_tree=capture(['git', 'status', '--short']), source_sha256=evidence,
                executable_sha256=digest(binary), runtime_version=capture([str(binary), '--version']),
                swift_version=capture(['swift', '--version']),
                zig_version=capture([str(ROOT / '.toolchain/zig-aarch64-macos-0.16.0/zig'), 'version']),
                os=capture(['sw_vers']), architecture=platform.machine(),
                hardware={k: hardware.get(k) for k in ['chip_type', 'machine_model', 'physical_memory', 'number_processors']},
                power_settings=capture(['pmset', '-g', 'custom']), power_source=capture(['pmset', '-g', 'batt']),
                load_average=list(os.getloadavg()),
                timer='time.perf_counter_ns around Popen + wait4; validation excluded',
                resource_counters='os.wait4 per-child rusage; Darwin ru_maxrss is bytes',
                build='scripts/build.sh: Zig ReleaseSafe aarch64-macos; Swift release arm64')


def run(args):
    if sys.platform != 'darwin':
        raise SystemExit('The published experiment protocol targets macOS')
    binary = args.binary.resolve()
    destination = args.output.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    raw = destination / 'runs.jsonl'
    if any(destination.iterdir()):
        raise SystemExit('Refusing to overwrite an existing experiment; choose a new --output')
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    cases = prepare(work, args.sizes)
    if args.only:
        cases = [case for case in cases if case['name'] in args.only]
    meta = metadata(binary)
    meta.update(warmups=args.warmups, repetitions=args.repetitions, timeout_s=args.timeout)
    (destination / 'metadata.json').write_text(json.dumps(meta, indent=2) + '\n')
    (destination / 'workloads.json').write_text(json.dumps(cases, indent=2) + '\n')
    sources = destination / 'programs'
    sources.mkdir(exist_ok=True)
    for case in cases:
        (sources / f'{case["name"]}-{case["rows"]}.sas').write_bytes((work / case['directory'] / case['source']).read_bytes())
    if args.profile:
        outcomes = []
        for case in cases:
            folder = work / case['directory']
            profile_path = destination / f'{case["name"]}-{case["rows"]}.sample.txt'
            with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
                child = subprocess.Popen([str(binary), case['source']], cwd=folder, stdout=out, stderr=err)
                sampler = subprocess.run(['/usr/bin/sample', str(child.pid), '1', '1', '-mayDie', '-file', str(profile_path)], capture_output=True, text=True, timeout=20)
                try:
                    child.wait(timeout=args.timeout)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
                out.seek(0)
                err.seek(0)
                reason = ''
                try:
                    validate(case, out.read().decode(), err.read().decode(), None)
                    if child.returncode != 0:
                        raise ValueError(f'Exit {child.returncode}')
                except ValueError as error:
                    reason = str(error)
                if profile_path.exists():
                    text = profile_path.read_text().replace(str(ROOT), '<workspace>').replace(str(Path.home()), '<home>')
                    profile_path.write_text(text)
                outcomes.append(dict(workload=case['name'], rows=case['rows'], sample_exit=sampler.returncode,
                                     validation_error=reason, sampler_message=sampler.stderr.replace(str(ROOT), '<workspace>'),
                                     profile_exists=profile_path.exists()))
        (destination / 'profiles.json').write_text(json.dumps(outcomes, indent=2) + '\n')
        print(json.dumps(outcomes, indent=2))
        return 0 if all(item['sample_exit'] == 0 and not item['validation_error'] and item['profile_exists'] for item in outcomes) else 1
    samples = []
    phases = ['first'] + ['warmup']*args.warmups + ['measured']*args.repetitions
    with raw.open('x') as stream:
        for case in cases:
            folder = work / case['directory']
            print(f'{case["name"]} n={case["rows"]}', flush=True)
            first_plain = None
            for iteration, phase in enumerate(phases):
                variants = case['variants'] if iteration % 2 == 0 else list(reversed(case['variants']))
                for variant in variants:
                    sidefile = folder / 'tables.json'
                    sidefile.unlink(missing_ok=True)
                    (folder / 'roundtrip.csv').unlink(missing_ok=True)
                    command = [str(binary), case['source']]
                    if variant == 'tables':
                        command += ['--tables-json', 'tables.json']
                    result = measure(command, folder, args.timeout)
                    status, reason = 'ok', ''
                    try:
                        if result['timed_out']:
                            status = 'timeout'
                        elif result['returncode'] != 0:
                            raise ValueError(f'Exit {result["returncode"]}')
                        else:
                            sidecar = json.loads(sidefile.read_text()) if variant == 'tables' else None
                            validate(case, result['stdout'], result['stderr'], sidecar)
                            if case['name'] == 'csv':
                                validate_csv(folder / 'roundtrip.csv', case['rows'])
                            pair = (result['stdout'], result['stderr'])
                            if first_plain is None:
                                first_plain = pair
                            elif pair != first_plain:
                                raise ValueError('Output/diagnostics changed across repetitions or sidecar variants')
                    except (ValueError, KeyError, OSError) as error:
                        status, reason = 'invalid', str(error)
                    output, errors = result.pop('stdout'), result.pop('stderr')
                    sample = dict(workload=case['name'], rows=case['rows'], variant=variant,
                                  phase=phase, iteration=iteration, status=status, reason=reason,
                                  stdout_sha256=hashlib.sha256(output.encode()).hexdigest(), stdout_bytes=len(output.encode()),
                                  stderr_sha256=hashlib.sha256(errors.encode()).hexdigest(),
                                  tables_bytes=sidefile.stat().st_size if sidefile.exists() else 0, **result)
                    samples.append(sample)
                    stream.write(json.dumps(sample) + '\n')
                    stream.flush()
                    if status != 'ok':
                        (destination / f'failure-{case["name"]}-{case["rows"]}-{iteration}-{variant}.txt').write_text(reason+'\n'+errors+'\n'+output)
                        print(f'  {phase} {variant}: {status}: {reason}', flush=True)
            summary = summarize(samples)
            (destination / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    meta['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    meta['end_load_average'] = list(os.getloadavg())
    (destination / 'metadata.json').write_text(json.dumps(meta, indent=2) + '\n')
    summary = summarize(samples)
    fields = ['workload', 'rows', 'variant', 'accepted', 'invalid', 'timeouts', 'median_s', 'q1_s', 'q3_s', 'median_user_s', 'median_system_s', 'median_peak_rss_bytes', 'max_peak_rss_bytes']
    with (destination / 'summary.csv').open('w') as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(summary)
    print(json.dumps(summary, indent=2), flush=True)
    return 1 if any(sample['status'] != 'ok' for sample in samples) else 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, default=ROOT / 'dist/LocalStat.app/Contents/Helpers/opensas')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--work', type=Path, default=ROOT / 'dist/benchmarks/workloads')
    parser.add_argument('--sizes', nargs='+', type=int, default=[10000, 100000, 1000000])
    parser.add_argument('--only', nargs='+', choices=['data', 'sort', 'group', 'join', 'reg', 'csv', 'freq', 'print', 'example'])
    parser.add_argument('--profile', action='store_true', help='Collect separate one-second stack samples instead of timing runs')
    parser.add_argument('--warmups', type=int, default=3)
    parser.add_argument('--repetitions', type=int, default=15)
    parser.add_argument('--timeout', type=float, default=60)
    arguments = parser.parse_args()
    if arguments.warmups < 0 or arguments.repetitions < 1 or arguments.timeout <= 0:
        parser.error('warmups >= 0, repetitions >= 1, timeout > 0 are required')
    arguments.work.mkdir(parents=True, exist_ok=True)
    with (arguments.work / '.benchmark.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit('Another benchmark is using this workload directory')
        raise SystemExit(run(arguments))
