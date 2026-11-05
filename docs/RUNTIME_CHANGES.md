# Runtime provenance and local changes

Upstream: https://github.com/kirha-ai/opensas

Pinned commit: `927a2fa9f1401e365d975536bd704819ada1f1f4`.

The source is vendored as a snapshot, including upstream tests, documentation, and Apache-2.0 license. No nested Git checkout or submodule is required. The 0.1.0-alpha runtime identifies itself as `localstat-0.1.0-alpha+927a2fa9f140`. Source builds use Zig 0.16.0 and ReleaseSafe.

Local changes:

- `src/io.zig`: CSV import infers whole-column types in a first pass and
  builds owned values in a second pass, resetting temporary decoded fields
  per record and releasing import scratch storage on return. Numeric, date,
  quoting, and missing-value policies are preserved. Dataset snapshots now
  allocate retained cells once while still copying character bytes. Regression
  tests bound destination allocations and verify source-buffer independence.

- Normalize literal em dashes to ASCII hyphens throughout the vendored snapshot,
  including comments, diagnostic messages, documentation, and fixture output.
  Matching expected messages and fixture results use the same punctuation.
- `src/reg.zig`: bounded PROC REG parser, scaled pivoted Householder QR solver, text statistical output and analytical unit tests.
- `src/root.zig`, `src/main.zig`: module/dispatch registration and report-title integration.
- `src/main.zig`: nonzero CLI exit on missing/unreadable input; unsupported ODS destinations produce explicit diagnostic errors.
- `src/table_result.zig`, `src/main.zig`, `src/proc.zig`: optional versioned
  `--tables-json <path>` sidecar for displayed PRINT, FREQ, and TABULATE tables.
  It does not alter stdout, stderr, or procedure calculations.
- `src/sas7bcat.zig`: catalog parsing validates physical page counts, rejects cyclic block chains, bounds reconstructed data, and validates entry counts before allocation.
- ODS destination unit/corpus expectations deliberately differ from upstream. This implements the user's requested error behavior and overrides upstream decision D-022's destination no-op policy. ODS LISTING controls remain inert and now emit a note.

Upstream's broad claims and historical engineering notes describe upstream, not an independent certification of this fork. New regression tests use synthetic data, analytical solutions and a published SAS census example. No private data is included.
