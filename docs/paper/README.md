# LocalStat system paper

`localstat.tex` is the system paper, authored by Muhammad Hafiz bin Ismail.
It includes two studies completed on 4 November 2026: the initial 855-sample
baseline and a 1,912-sample controlled optimization comparison. The latter
interleaves 1,406 CLI observations and counterbalances 506 native runner, app,
and table-construction observations. All pass their stated output checks;
sidecar JSON and pagination are preserved. Five listings embed evaluated code
excerpts directly in the compiled paper. No alternative language or installed
SAS engine was compared.

## Build

Requires a LaTeX installation with `latexmk`, pdfLaTeX, Latin Modern, and the
packages declared in the source. Run these commands from the repository root:

```sh
mkdir -p tmp/pdfs/localstat output/pdf
latexmk -pdf -interaction=nonstopmode -halt-on-error -outdir=tmp/pdfs/localstat docs/paper/localstat.tex
cp tmp/pdfs/localstat/localstat.pdf output/pdf/localstat.pdf
```

The final PDF is `output/pdf/localstat.pdf`. Intermediate files stay under
`tmp/pdfs/localstat`. Both output directories are ignored by Git.

## Evidence and completion

The paper pins repository references to the recorded base revision
`7f6dec6537cc9e9ca9f9c37961b8b6811c5b7aff`. The evaluated working tree included
uncommitted app changes, so the evidence also includes exact native source,
source hashes, and executable hashes. The OpenSAS reference uses its independently
pinned upstream commit. The experiment does not claim a clean evaluated release.

The frozen logs, profiles, and configurations retain machine-local paths from
the evaluated host. The reproduction instructions generate fresh paths for
your checkout. Historical files and their recorded hashes remain unchanged;
the maintained harness and auditors include later validation fixes.

[The experiment record](results/2026-11-04/README.md) explains the evidence files,
measurement boundaries, and limitations. [Benchmark instructions](BENCHMARKS.md)
describe how to repeat the studies with new output directories. Expand related
work before journal or conference submission.

[The optimization record](results/2026-11-04-optimization/README.md) preserves
fresh before/after controls, frozen sources, the implementation patch, code
excerpt provenance, individual measurements, and generated comparison tables.
Its baseline starts from application revision `a651c8d`, with the same measurement
driver in both builds. The native application sources differ only in the table
view; runtime changes are confined to `io.zig`.

Regenerate the three result tables from audited raw evidence before rebuilding:

```sh
python3 scripts/benchmark_report.py docs/paper/results/2026-11-04
python3 scripts/benchmark_compare_report.py docs/paper/results/2026-11-04-optimization
```
