# Controlled memory and PRINT optimization study

Completed on 4 November 2026 on the same Apple M5 / 16 GB Mac as the initial
study. The new experiment contains 1,406 CLI observations and 506 native
runner/app/table-construction observations. All pass their stated checks.
The original study and its manifests remain unchanged under `../2026-11-04`.

## Results

At one million rows, median peak interpreter RSS falls by 54.0 to 75.6 percent
across the seven numeric workload families. Median runtime improves by factors
of 1.12 to 1.26. The CSV round trip falls from 2324.0 to 579.7 MiB; FREQ falls
from 1464.5 to 357.8 MiB.

At 10,000 PRINT rows, median table-view construction falls from 210.5 to
51.8 ms (4.07 times faster), while complete app latency falls from 343.5 to
172.9 ms (1.99 times faster). All 10,000 rows remain available on the same 385
pages. PRINT at 1,000 rows stays at 39 pages; FREQ stays at four pages.

Not every path improves: the DATA app case changes from 74.2 to 74.9 ms,
within its IQRs. FREQ app latency changes little, and its optimized direct
runner has a wide IQR. The complete tables retain these results. Ratios compare
medians; no significance test, confidence interval, or per-change ablation is
asserted. These synthetic numeric workloads do not establish general SAS
equivalence, native-app peak memory, or alternative-language superiority.

## Changes and source identity

- CSV import makes two passes over an in-memory record index. It resets
  record-local decoded fields, frees import scratch at return, and preserves
  whole-column numeric/date inference and character ownership.
- PDV snapshots append one owned row instead of allocating a temporary row
  and copying it into another retained allocation.
- Table construction caches text heights by text, width, font name, and size;
  it retains row/header metrics for drawing and reuses full-column rows.
  Its temporary text cache is discarded after construction.

The native baseline was frozen at application base revision `a651c8d`. Only
`Sources/SASCore/TableDocumentView.swift` differs between the before/after
application sources; both packages use an identical measurement driver.
Runtime production changes are confined to `vendor/opensas/src/io.zig`.
The baseline runtime source matches the original study's source fingerprint.
The binary hashes are:

| Build | Interpreter SHA-256 |
| --- | --- |
| Before | `5eba6715b7bbe80de7be29b69a4a99163c54c93dd144783e2fa0e0fdf6e914f1` |
| After | `4eaa95922251e4cc72e5f1bb5afe5d50f0a9531030b918df73af53c165cc1151` |

## Protocol

CLI builds run adjacently within each workload/sidecar variant/iteration;
before-after and after-before order alternates. Each build has 37 configurations,
one separately recorded first execution, three warmups, and fifteen measured
repetitions. This produces 1,110 measured and 296 first/warmup observations.
Elapsed time and per-child kernel counters use the same measurement helper as
the original study. Both builds have normal local process access in this study.

Native execution uses before-after-after-before blocks. The first block per
build has eight measured repetitions and the second has seven. Each block has
a first execution and three warmups per configuration. There are eleven paths
per build: DATA runner/app, and FREQ plus two PRINT sizes with runner/app/layout.
The resulting 506 observations include 330 measured and 176 first/warmup samples.
Layout measures construction from a preloaded validated table, excluding process
execution, JSON decoding, and drawing. App timing ends after a synchronous display
pass and includes one-millisecond observation polling. It does not measure
physical screen presentation. Native process peak RSS was not measured.

The same source/input hashes, analytical checks, exported CSV checks, and listing
checks apply to both builds. Stdout, stderr, and canonical sidecar hashes must
agree across builds. Native output hashes must match CLI output, repetitions
must be complete and unique, and layout page counts must match.

## Evidence

- `measurements/runs.jsonl`, `summary.json`, `metadata.json`, `workloads.json`,
  and `programs`: raw interleaved CLI measurements, provenance, generated source,
  expected results, input hashes, and summaries.
- `measurements/native-runs.json`: combined native observations, tagged by build
  and counterbalanced block; individual block JSON/config/log files are retained.
- `comparison-summary.json` and the three `*-comparison.tex` files: audited
  before/after medians, quartiles, memory changes, and latency ratios.
- `before-runtime-source.tar.gz`, `after-runtime-source.tar.gz`: buildable runtime
  sources and fixtures, excluding compiler caches and generated executables.
- `runtime-replay-check.txt`: both runtime archives were rebuilt and their
  example, DATA, and CSV outputs validated and compared after extraction.
- `before-native-source.tar.gz`, `after-native-source.tar.gz`, and
  `native-source-sha256.json`: exact native source packages and file hashes.
- `code`: full changed source files, the five code excerpts embedded in the
  paper, and `provenance.json` with their source line ranges and hashes.
- `implementation.patch`: runtime/view/test changes relative to the recorded
  application base. Measurement-driver and harness sources are preserved separately.
- `benchmark*.py`: the exact collection/report scripts used for this study.
- `optimization-memory-red.log` and `optimization-print-red.log`: expected
  pre-implementation regression failures; these are intentional red-test evidence.
- `optimization-verification-final.log`: the passing full suite, including 973
  runtime tests, 1,924 corpus programs, 11 end-to-end programs, and 57 Swift tests
  with one opt-in skip and no failures. The new comparison-report tests ran
  separately after that full-suite run.
- `python-verification.txt`: all twenty final Python harness/report checks.
- `baseline-paper.pdf` and `baseline-paper.tex`: preserved original paper artifacts,
  matching the previous study's recorded hashes.
- `evaluated-binaries.json`: native test-host/app hashes, interpreter hashes,
  source archive hashes, and context.
- `artifact-manifest.json`: SHA-256 hashes of the evidence and updated paper.

Follow `../../BENCHMARKS.md` for the exact reproduction workflow. The two
changesets are evaluated together; this record does not assign individual
speedups to the import and snapshot edits or the separate layout edits.
