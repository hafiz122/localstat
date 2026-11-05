# LocalStat baseline experiment: 4 November 2026

The study completed 703 CLI samples (37 configurations, 555 measured samples)
and 152 native samples (8 configurations, 120 measured samples). All passed
output checks; there were no timing-study failures or timeouts. Every configuration
has one separately recorded first run, three warmups, and fifteen measured runs.
Seven additional million-row executions produced separate stack profiles.

The host was an Apple M5 MacBook Pro with 10 cores and 16 GB of memory, macOS
26.4.1, Swift 6.3.3, and Zig 0.16.0. It used AC power with low-power mode disabled.
No claim of cold-cache measurement, host isolation, optimized-build speedup,
language superiority, or installed-SAS equivalence is made.

## Evidence files

- `cli/runs.jsonl`: each first, warmup, and measured observation, including
  status, elapsed time, child CPU time/RSS, output hashes, and output sizes.
- `cli/metadata.json`: host/toolchain information, power state, load averages,
  executable hash, base revision, dirty-tree state, and source fingerprints.
- `cli/workloads.json` and `cli/programs`: exact workload specifications,
  analytical expectations, SAS source, and generated CSV input hashes.
- `cli/summary.json` and `cli/summary.csv`: measured CLI medians, quartiles,
  per-child memory, and failure counts, recomputed from raw records by the auditor.
- `cli/harness.py` and `cli/test_benchmark.py`: the measurement implementation
  and its checks as preserved for this run. Current maintained versions are in
  `scripts` and `Tests` at the repository root.
- `ui-runs.json`, `ui-summary.json`, and `ui-manifest.json`: raw native timing
  observations, summaries, workload selection, artifact hashes, and test context.
- `native-source.tar.gz` and `native-source-sha256.json`: exact frozen native
  sources compiled for the release-mode XCTest experiment, including the test.
- `native-log.txt`: build and native experiment output. The native benchmark
  test passed; unrelated pre-existing Swift test fixtures emitted Sendable warnings.
- `native-overwrite-check.txt`: a disposable negative fixture confirmed that
  the maintained native benchmark rejects existing output before measurement.
- `verification.txt`: fresh project-suite output. It records 969 runtime unit
  tests, 1,924 corpus programs, 11 program fixtures, 48 Swift tests with one opt-in
  benchmark skip and no failures, 16 packaged-runtime checks, 9 harness checks,
  3 Help checks, and the repository text check. The opt-in benchmark subsequently
  ran successfully. `harness-verification.txt` records the final harness/auditor checks.
- `profiles`: seven separate validated stack samples, profile status, metadata,
  and workload definitions. Profile overhead is excluded from timing summaries.
- `paired-sidecar.json`: iteration-matched sidecar-minus-plain differences.
- `reporter.py` and `test_reporter.py`: the audited table generator and its
  four checks as preserved for this paper; maintained versions live under
  `scripts` and `Tests` at the repository root.
- `cli-timings.tex`, `table-costs.tex`, and `ui-timings.tex`: generated paper
  tables. Regenerate them with `python3 scripts/benchmark_report.py` and this directory.
- `artifact-manifest.json`: SHA-256 hashes of the archived experiment evidence.

## Interpretation

The recorded base revision is `7f6dec6537cc9e9ca9f9c37961b8b6811c5b7aff`.
Uncommitted app edits were present, so source archives and hashes identify the
evaluation more precisely than the revision alone. The native source hashes
match the corresponding source fingerprints captured in the CLI study.

CLI timings use a monotonic clock around `Popen` and `wait4`, with per-child
kernel resource counters. They include process launch, CSV load, procedure
execution, validation scans, and output writing. Input generation and output
checking are outside timing. Child RSS is recorded in bytes; paper tables
convert to MiB. Python orchestration is not an interpreter backend.

The native experiment ran sequentially after the CLI study. It used the same
frozen interpreter, a release-mode XCTest host, light appearance, default
preferences, a 1100-by-780 window, and alternating runner/app order. App timing
ends at a synchronous display pass, with one-millisecond completion polling.
Native output hashes match validated CLI output. This measures the actual app
workflow in a test host; it is not physical screen latency or a pure rendering
measurement. Native-process memory and individual UI stages were not measured.

FREQ/PRINT table comparisons alternate variant order. Paired deltas match
iterations; they are not differences of marginal medians. A difference IQR
crossing zero is treated as inconclusive, without asserting a significance test.
Profiles are short, partial samples. No additional stage instrumentation or
optimization experiment was performed.

See `../../BENCHMARKS.md` for commands to repeat the studies in a new output
directory. Generated CSV files and build artifacts remain under ignored `dist`.
