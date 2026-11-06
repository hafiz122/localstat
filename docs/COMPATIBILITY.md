# LocalStat source-build compatibility

The downloadable `0.1.0-alpha` predates the formatted Tables view described below.

This is an independent SAS-language implementation based on OpenSAS, not SAS Institute's runtime. It is not a drop-in SAS replacement and is not validated for clinical or regulated work.

| Capability | Status |
| --- | --- |
| Local execution | Native macOS ARM64, offline, fresh subprocess per whole program |
| DATA steps, macros, SQL and existing procedures | Inherited OpenSAS subset; upstream conformance suites run locally. Not universal SAS compatibility. |
| PROC REG | One numeric response; explicit numeric predictors; intercept; one MODEL; complete-case ordinary least squares |
| PROC CORR | Numeric Pearson correlations with VAR and WITH, BY groups, WHERE filtering, and pairwise counts; other methods and output options are unsupported |
| PROC TTEST | Numeric one-sample tests with optional H0=, one paired variable pair, and two-sample CLASS tests with pooled and Satterthwaite results; other options are unsupported |
| PROC SGPLOT | SCATTER and SERIES with X=/Y=; VBAR and HBAR with optional RESPONSE= and STAT=FREQ, SUM, or MEAN; DATA= and WHERE filtering. Other statements and options are unsupported. |
| REG output | Text ANOVA, estimates, standard errors, t and F tests, Root MSE, R-square and adjusted R-square |
| REG verification | Analytic and published-example checks; no new direct SAS-engine validation claimed |
| Singular models | Explicit error; SAS's generalized-inverse/aliased-coefficient behavior is not implemented |
| Perfect fits | Zero residual variance; inference values that require division by zero display `.` with an explanatory note |
| Constant response | R-square and adjusted R-square display `.` |
| REG options, WEIGHT, FREQ, BY, OUTPUT, selection, plots | Unsupported; explicit error |
| Other modeling procedures | GLM, LOGISTIC, MIXED, GLIMMIX, PHREG, LIFETEST and others remain unsupported |
| ODS | Text listing only. Other destinations and controls error; LISTING open/close are inert with a note |
| Formatted tables | PROC PRINT, PROC FREQ TABLES/NLEVELS, PROC TABULATE, and PROC CORR results in the native Tables tab; SAS-style presentation, not exact ODS rendering |
| Graphics | Supported PROC SGPLOT statements produce SVG files in the result bundle and display in the Graphics tab after the run finishes. The light style follows public SAS 9.4 ODS HTML/HTMLBlue examples; it has not been compared with licensed SAS output. |
| Printing | Print all formatted tables from the latest run through the macOS print dialog |
| IDE report export | Searchable, paginated PDF containing run metadata, executed source, formatted tables, raw text output and diagnostics; this is an IDE report, not an ODS destination |
| Datasets | OpenSAS readers/writers for CSV, SAS7BDAT and XPT; limitations remain upstream |
| Runtime session | WORK and macro state reset each run; explicit filesystem outputs persist |
| Security boundary | Programs are executable content: filesystem access and `%SYSGET` use the app process's permissions and environment; the alpha is not sandboxed |
| Diagnostics | Original source positions navigate only when the editor still matches the executed snapshot; expanded macro positions never navigate |
| Output timing | Runtime buffers output until execution finishes. Stop can discard buffered output. |

## Supported REG syntax

```sas
proc reg data=measurements;
  model response = predictor1 predictor2;
run;
quit;
```

Input variables must be numeric. Rows missing any model variable are excluded. At least one predictor and positive residual degrees of freedom are required. Duplicate predictors, unknown variables, and numerically rank-deficient designs fail visibly. Named two-level libraries are supported. Predictor lists, transformations inside MODEL, multiple responses/models and dataset options on DATA= are outside this subset. Global OBS/FIRSTOBS settings use the existing OpenSAS input machinery.

The implementation uses column scaling and Householder QR with column pivoting. It rejects scaled pivots below `16 * machine epsilon * max(observations, parameters)`. Extremely ill-conditioned full-rank problems can therefore be rejected. Tests compare well-conditioned numerical results using absolute and relative tolerances, not byte-identical report formatting. Very small p-values can underflow or round to zero in text output.

## Supported SGPLOT syntax

```sas
data measurements;
  input group $ x y;
  datalines;
A 1 2
A 2 4
B 3 3
B 4 5
;
run;

proc sgplot data=measurements;
  scatter x=x y=y;
run;

proc sgplot data=measurements;
  vbar group / response=y stat=sum;
run;
```

Each PROC SGPLOT step accepts one plot statement and creates one SVG graphic. SCATTER and SERIES use numeric X and Y variables. SERIES connects observations in data order. VBAR and HBAR count categories by default; RESPONSE= selects a numeric variable for SUM or MEAN. Categories appear in ascending unformatted order, bars start at zero and occupy 80% of a category slot, and the default SVG is 640 × 480. These defaults follow the [public SAS 9.4 visual target](procedures/sgplot-visual-target.md), not a licensed output comparison. DATA= selects the input dataset, and a WHERE statement can filter rows. The current chart limits are 20,000 input rows and 100 categories. Negative bar values fail with an error. The SVG is saved in the run's result bundle; direct command line runs must pass `--results-dir`. Overlays, grouping, axis and style options, ODS GRAPHICS controls, other SGPLOT statements such as VBOX, and graphics from statistical procedures are outside this subset.

## Known inherited differences

OpenSAS implements subsets of SAS statements and procedure options. The upstream test corpus is evidence for those fixtures only. Some inherited statements are deliberately inert: for example X does not execute shell commands and PROC PRINTTO does not redirect output. Text PUT output and procedure listings share stdout. This app preserves raw stdout/stderr and the process exit code; diagnostics are not the full SAS log format. ABORT can explicitly return an exit code, including 1 or 2, so the text log remains authoritative when interpreting those statuses.

No persistent interactive session, selection execution, dataset grid, HTML/RTF results, or ODS PDF destination is included in the current source build. Other procedures remain in the text Output tab. A successful exit is not proof of numerical equivalence to SAS.
