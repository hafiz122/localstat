# Repeating the LocalStat study

The harness uses Python 3.11 or later for orchestration. The timer surrounds
the native interpreter subprocess, so input generation, Python startup, output
validation, and report generation are outside its measurement interval. It uses
only the standard library. Native app measurements require macOS and Xcode.

## Validate and freeze a runtime

Run from the repository root:

```sh
./scripts/test.sh
mkdir -p dist/benchmarks/replay
cp dist/LocalStat.app/Contents/Helpers/opensas dist/benchmarks/replay/opensas
```

The project suite includes the harness and report-auditor tests. The native
measurement test skips unless `LOCALSTAT_BENCHMARK_CONFIG` is set. Ensure the
normal suite runs with that variable unset.

## Command-line measurements

```sh
python3 scripts/benchmark.py \
  --binary dist/benchmarks/replay/opensas \
  --output dist/benchmarks/replay/cli \
  --sizes 1000 10000 100000 1000000
```

Defaults are three warmups, fifteen measured repetitions, and a sixty-second
timeout. One first execution is recorded separately. Frequencies and printed
tables alternate plain/sidecar order each iteration. Size must be a positive
multiple of 200 for balanced groups and regression design. The six-row example
is always prepared; `--only` can select families for shorter studies.

Each accepted run must satisfy analytical checks. The harness captures stdout
and stderr into temporary files, obtains per-child CPU time and RSS through
`wait4`, and records high-resolution elapsed time. Failed and timed-out runs
remain in the raw evidence and make the command exit unsuccessfully. Output
directories must be new or empty; existing experiments are never overwritten.
A lock prevents concurrent harness invocations sharing the workload directory.
Do not run another benchmark, compiler, or profiler concurrently.

Generated inputs stay under `dist/benchmarks/workloads`. The manifest preserves
source and input hashes, and the output directory contains the generated SAS
programs. CSV input loading and validation scans are included in execution time;
checking their output occurs afterward. These are pipeline benchmarks.

## Native runner and application measurements

For the published app-source snapshot, extract the preserved source archive:

```sh
mkdir -p dist/benchmarks/native-source-replay
tar -xzf docs/paper/results/2026-11-04/native-source.tar.gz \
  -C dist/benchmarks/native-source-replay
```

Alternatively omit `--package-path` below to measure the current working tree.
Generate a configuration with paths for this checkout:

```sh
python3 - <<'PY'
import json
from pathlib import Path
root = Path.cwd()
output = root / 'dist/benchmarks/replay'
cases = json.loads((output / 'cli/workloads.json').read_text())
wanted = {('data', 10000), ('freq', 100000), ('print', 1000), ('print', 10000)}
selected = [c for c in cases if (c['name'], c['rows']) in wanted]
assert len(selected) == 4
config = dict(binary=str(output / 'opensas'),
              work=str(root / 'dist/benchmarks/workloads'),
              output=str(output / 'ui-runs.json'), cases=selected,
              warmups=3, repetitions=15)
(output / 'ui-config.json').write_text(json.dumps(config, indent=2))
PY
LOCALSTAT_BENCHMARK_CONFIG="$PWD/dist/benchmarks/replay/ui-config.json" \
  swift test --package-path dist/benchmarks/native-source-replay -c release \
  --filter BenchmarkIntegrationTests/testMeasuredRuns
```

The release-mode test exercises actual `LocalRuntimeRunner` and
`AppDelegate.runProgram` code in an XCTest host, using fresh interpreter
processes, a light 1100-by-780 window, and isolated default preferences. It
alternates runner/app order. App timing ends after result application, layout,
and a synchronous display pass. One-millisecond completion polling adds
observation overhead; this does not measure physical screen presentation.
The paired difference is not a decomposition of one execution.

## Separate stack profiles

After all timing experiments have finished:

```sh
python3 scripts/benchmark.py \
  --binary dist/benchmarks/replay/opensas \
  --output dist/benchmarks/replay/profiles \
  --sizes 1000000 --only data sort group join reg csv freq --profile
```

This uses macOS `sample` with a nominal one-second duration and one-millisecond
interval. Attaching to processes may require normal local process-inspection
permissions. Profiles are separate from the timing dataset and can miss startup
or early-finishing stages. They identify stack locations, not exact stage costs.

## Audit and report

```sh
python3 scripts/benchmark_report.py dist/benchmarks/replay
```

The report tool verifies complete, unique measured iterations, successful status,
native/CLI output-hash agreement, and agreement between raw CLI samples and the
saved summary. It generates LaTeX timing tables and paired-difference summaries.
The paper includes the dated published tables; new experiments must be reviewed
before changing that reference. Timings use median and inclusive-quartile IQR
width. RSS uses MiB, and native app memory is not measured by this harness.

## Controlled optimization comparison

The follow-up artifact at `docs/paper/results/2026-11-04-optimization` preserves
buildable before/after runtime and native packages. Extract them into new ignored
directories so the current working tree is not changed:

```sh
mkdir -p dist/benchmarks/compare-replay/before-runtime dist/benchmarks/compare-replay/after-runtime
mkdir -p dist/benchmarks/compare-replay/before-native dist/benchmarks/compare-replay/after-native
tar -xzf docs/paper/results/2026-11-04-optimization/before-runtime-source.tar.gz -C dist/benchmarks/compare-replay/before-runtime
tar -xzf docs/paper/results/2026-11-04-optimization/after-runtime-source.tar.gz -C dist/benchmarks/compare-replay/after-runtime
tar -xzf docs/paper/results/2026-11-04-optimization/before-native-source.tar.gz -C dist/benchmarks/compare-replay/before-native
tar -xzf docs/paper/results/2026-11-04-optimization/after-native-source.tar.gz -C dist/benchmarks/compare-replay/after-native
```

Build both runtimes with the pinned toolchain and the same ReleaseSafe options.
Run these two subshell commands from the repository root:

```sh
(cd dist/benchmarks/compare-replay/before-runtime && ../../../../.toolchain/zig-aarch64-macos-0.16.0/zig build -Doptimize=ReleaseSafe -Dtarget=aarch64-macos -Dversion=localstat-0.1.0-alpha+927a2fa9f140)
(cd dist/benchmarks/compare-replay/after-runtime && ../../../../.toolchain/zig-aarch64-macos-0.16.0/zig build -Doptimize=ReleaseSafe -Dtarget=aarch64-macos -Dversion=localstat-0.1.0-alpha+927a2fa9f140)
```

Compile the native test hosts in release test mode with the measurement variable
unset; the selected benchmark will skip during this preparation:

```sh
swift test --package-path dist/benchmarks/compare-replay/before-native -c release --filter BenchmarkIntegrationTests/testMeasuredRuns
swift test --package-path dist/benchmarks/compare-replay/after-native -c release --filter BenchmarkIntegrationTests/testMeasuredRuns
```

Then collect the interleaved CLI and counterbalanced native studies. This command
uses a new output directory and runs the studies sequentially:

```sh
python3 scripts/benchmark_compare.py \
  --before dist/benchmarks/compare-replay/before-runtime/zig-out/bin/opensas \
  --after dist/benchmarks/compare-replay/after-runtime/zig-out/bin/opensas \
  --native-before dist/benchmarks/compare-replay/before-native \
  --native-after dist/benchmarks/compare-replay/after-native \
  --work dist/benchmarks/compare-replay/workloads \
  --output dist/benchmarks/compare-replay/results/measurements
python3 scripts/benchmark_compare_report.py dist/benchmarks/compare-replay/results
```

The default four row counts, three warmups, and fifteen measured repetitions
match the paper. The CLI alternates build order within each workload iteration.
Native blocks use before-after-after-before order, with eight then seven measured
repetitions per build. Each native block has its own first execution and warmups.
The additional layout path constructs a view from preloaded results; it never
substitutes for the complete application measurement. Rebuilt executable hashes
may differ with source paths or SDKs and must be recorded for the new study.
