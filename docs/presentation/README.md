# LocalStat Beamer presentation

An English presentation for a professor: 12 main slides and two appendix slides,
prepared for approximately 10 to 12 minutes before questions or a live demo.

The deck uses LaTeX Beamer in 16:9 format. It includes two source-rendered AppKit previews and a rendered PDF output
excerpt from the repository.
The preview provenance is visible on the corresponding slides. Features refer
to the current source, while performance measurements refer to the preserved
4 November 2026 experiment. Verification counts follow the dated 5 November
integration record. This presentation does not claim a new benchmark or test run.

## Build

Install a TeX distribution with Beamer, Latin Modern, listings, booktabs,
pgfpages, pdfLaTeX and latexmk, then run:

```sh
sh build.sh
```

The script creates `localstat-professor-presentation.pdf`. It works from any
current directory and keeps compiler files in `build/`.

## Edit or use Overleaf

Edit `localstat-beamer.tex`. The source package is self-contained: keep the
`assets/` directory beside the TeX file. For Overleaf, upload the package
contents and select `localstat-beamer.tex` as the main document with pdfLaTeX.

The title uses the author name credited in the repository's system paper,
Muhammad Hafiz bin Ismail. Change the name and presentation date if needed.
The navy/teal typography keeps attention on the screenshots, code, and
evidence tables.

## Presenter notes

Every frame contains a hidden `\note{...}` with talking points and caveats.
The presentation PDF hides these notes. To compile a separate two-screen
version with notes on the right:

```sh
mkdir -p build
pdflatex -interaction=nonstopmode -halt-on-error -output-directory=build \
  -jobname=localstat-presenter \
  '\def\presenternotes{1}\input{localstat-beamer.tex}'
pdflatex -interaction=nonstopmode -halt-on-error -output-directory=build \
  -jobname=localstat-presenter \
  '\def\presenternotes{1}\input{localstat-beamer.tex}'
```

## Demonstration

Open `demo/` as the LocalStat project folder. Run `01-regression.sas`, inspect
the model estimates, then run `02-reporting.sas` and inspect its two tables.
Export a report and open the compatibility document. Use `0.1.2-alpha` or a
current source build for formatted output data.

Expected regression: intercept 2.2, slope 0.6, R-square 0.6. Expected PRINT:
eight rows. Expected FREQ: four store levels, each frequency 2 and percent 25.

## Evidence

Slide footnotes identify repository sources. Full evidence remains in the
repository, especially `docs/VERIFICATION.md`, `docs/COMPATIBILITY.md`, and
`docs/paper/results/2026-11-04-optimization/`. Asset provenance follows the
project README. The app previews come from source commit `83b46a8` and contain
synthetic data. The screenshots are supplied unchanged.

The source archive also includes the original project license and asset-license
record. LocalStat uses an extended OpenSAS interpreter and is independent of
SAS Institute's engine. The deck distinguishes that provenance and the known
compatibility boundaries.
