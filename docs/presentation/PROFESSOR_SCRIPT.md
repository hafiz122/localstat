# LocalStat: professor presentation script and explained code

**Suggested length:** about 5 minutes, including three short demonstrations.

Read only the quotes in **Five-minute presentation script** aloud. The timings
include pauses to run the prepared programs. The line-by-line explanations and
questions below are study notes, outside the five-minute script.

## Before presenting

1. Open LocalStat `0.1.2-alpha` or a current source build. The original
   `0.1.0-alpha` predates the formatted output data view used here.
2. Open this presentation's `demo` folder as the project folder.
3. Open `01-regression.sas`, `02-reporting.sas`, and `03-limitation.sas`.
   Increase the font size so the code and results are easy to read.
4. Keep the slides available as a fallback if the live demonstration fails.

## Five-minute presentation script

### 0:00–0:35 | Introduction and goal (slides 1–2)

> Good morning, Professor. This is LocalStat, a Mac application for running
> supported SAS-language programs locally. The goal is simple: students can
> write code, run it, see the results, and save a report in one application.
> It works on Apple Silicon Macs and runs offline after it is built.

### 0:35–1:05 | How it works (slides 3–4)

> The interface uses Swift and AppKit. The calculations run through a bundled
> OpenSAS interpreter written in Zig. When I press Run, the app sends the
> current code to a new local process and displays its results. Each run starts
> fresh, so the program must create the data it needs.

**Action:** Point to the editor, Run button, and results area.

### 1:05–2:00 | Regression demo (slide 5)

> The first example uses five artificial data points. The DATA step creates
> the dataset, and PROC REG fits a straight line predicting y from x.
>
> After running it, the fitted equation is predicted y equals 2.2 plus 0.6
> times x. R-square is 0.6. This means the line explains 60 percent of the
> variation in these y values. This is a small teaching example.

**Action:** Run `01-regression.sas` with Command-R. In **Output**, point to
Intercept = 2.2, x = 0.6, and R-Square = 0.6.

### 2:00–2:40 | Table demo (slide 6)

> The second example creates artificial sales data for four stores over two
> weeks. The loops produce eight rows. PROC PRINT shows the rows, and PROC
> FREQ counts them by store. Each store has two rows, or 25 percent of the
> total. These results appear as formatted tables.

**Action:** Run `02-reporting.sas` and show both results in **Tables**.

### 2:40–3:00 | Report export (slide 7)

> The latest run can be saved as a searchable PDF containing the code, results,
> and execution details. A professor can then review the program and its output
> together.

**Action:** Point to **File > Export Report as PDF**. Skip the save dialog to
stay within five minutes.

### 3:00–3:40 | Testing and performance (slides 8–10)

> The recorded tests check the interpreter, editor, reports, and numerical
> results. In a before-and-after study on one Mac, median peak interpreter
> memory fell by about 54 to 76 percent across seven million-row numeric
> workloads. Building a ten-thousand-row PRINT table became about four times
> faster. These results apply to the tested workloads; they do not prove every
> program will improve.

### 3:40–4:30 | Show a limitation (slide 11)

> LocalStat supports only part of the SAS language. Here I use the same data
> but request PROC GLM, which is unsupported. The app reports an error instead
> of producing a model result. This demonstrates a compatibility limit.
>
> WORK data also resets between runs. Direct comparison against an installed
> SAS engine remains future work.

**Action:** Run `03-limitation.sas`. Show the diagnostic:
`ERROR: PROC glm is not supported`. This failure is intentional.

### 4:30–5:00 | Contribution and closing (slide 12)

> OpenSAS provides the interpreter foundation. My work includes the native Mac
> application, runtime extensions, formatted tables, PDF reports, and performance
> improvements. Next, I would compare course exercises against SAS and ask
> students to try the application. I would appreciate your advice on which
> exercises to prioritize. Thank you.

## Demo 1: regression, with every line explained

Copy the following complete program into LocalStat, or open
`demo/01-regression.sas`. The code is identical to that file. Line numbers in
the explanation table count from the first comment; they are not part of the
code.

```sas
/* Synthetic teaching data matching the presentation preview. */
data measurements;
  input x y;
  datalines;
1 2
2 4
3 5
4 4
5 5
;
run;
title 'Simple linear regression';
proc reg data=measurements;
  model y = x;
run;
quit;
```

| Line | Code | Explanation |
| --- | --- | --- |
| 1 | `/* Synthetic teaching data matching the presentation preview. */` | A comment identifying the values as artificial teaching data. It does not execute. |
| 2 | `data measurements;` | Begins a DATA step that creates a dataset named `measurements`. |
| 3 | `input x y;` | Defines two numeric variables, `x` and `y`, and reads them in that order from each data row. |
| 4 | `datalines;` | Begins the data written directly inside the program. |
| 5 | `1 2` | Adds observation 1: `x = 1`, `y = 2`. Data rows do not need individual semicolons. |
| 6 | `2 4` | Adds observation 2: `x = 2`, `y = 4`. |
| 7 | `3 5` | Adds observation 3: `x = 3`, `y = 5`. |
| 8 | `4 4` | Adds observation 4: `x = 4`, `y = 4`. |
| 9 | `5 5` | Adds observation 5: `x = 5`, `y = 5`. |
| 10 | `;` | Ends the inline data section. This semicolon must be on its own line. |
| 11 | `run;` | Ends and executes the DATA step, making the dataset available to the next procedure. |
| 12 | `title 'Simple linear regression';` | Sets the heading for subsequent output. |
| 13 | `proc reg data=measurements;` | Begins the regression procedure using the `measurements` dataset. |
| 14 | `model y = x;` | Requests ordinary least-squares regression with `y` as the response and `x` as the predictor. An intercept is included by default. |
| 15 | `run;` | Executes the regression and produces the statistical output. |
| 16 | `quit;` | Ends the REG procedure. |

### Expected result and interpretation

| Output | Expected value | Meaning |
| --- | --- | --- |
| Observations used | 5 | All five input rows are used. |
| Intercept estimate | 2.2 | The fitted value of `y` at `x = 0`. Zero is outside this sample's x range, so this is an extrapolation. |
| Estimate for `x` | 0.6 | A one-unit increase in `x` corresponds to a 0.6-unit increase in fitted `y`. |
| R-Square | 0.6 | The model accounts for 60% of the observed variation in `y` around its mean. |

The fitted equation is **predicted y = 2.2 + 0.6x**. At `x = 3`, the prediction
is `2.2 + 0.6 × 3 = 4.0`; the observed value is 5, so its residual is 1.0.

**If asked to calculate the coefficients by hand:** mean x is 3 and mean y is
4. The sum of `(x - 3)(y - 4)` is 6, and the sum of `(x - 3)²` is 10. Therefore,
the slope is `6 / 10 = 0.6` and the intercept is `4 - 0.6 × 3 = 2.2`.
The residual sum of squares is 2.4 and total sum of squares is 6, giving
`R² = 1 - 2.4 / 6 = 0.6`.

## Demo 2: reporting, with every line explained

This complete program is identical to `demo/02-reporting.sas`. Run it as a
separate submission; it creates all the data it needs.

```sas
/* Synthetic sales data matching the presentation preview. */
data sales;
  do store = 1 to 4;
    do week = 1 to 2;
      revenue = 100 + store*15 + week*5;
      output;
    end;
  end;
run;
title 'Sales by store';
proc print data=sales noobs;
run;
proc freq data=sales;
  tables store;
run;
```

| Line | Code | Explanation |
| --- | --- | --- |
| 1 | `/* Synthetic sales data matching the presentation preview. */` | A comment identifying this as artificial sales data. It does not execute. |
| 2 | `data sales;` | Begins a DATA step that creates a dataset named `sales`. |
| 3 | `do store = 1 to 4;` | Starts an outer loop for store numbers 1, 2, 3, and 4. |
| 4 | `do week = 1 to 2;` | Starts an inner loop for weeks 1 and 2 for each store. |
| 5 | `revenue = 100 + store*15 + week*5;` | Calculates an artificial revenue value. Multiplication happens before addition; for store 1, week 1, the result is `100 + 15 + 5 = 120`. |
| 6 | `output;` | Writes the current store, week, and revenue values as one dataset row. Explicit OUTPUT saves each loop combination instead of only the final values. |
| 7 | `end;` | Closes the inner loop over weeks. |
| 8 | `end;` | Closes the outer loop over stores. |
| 9 | `run;` | Ends and executes the DATA step, producing `4 × 2 = 8` rows. |
| 10 | `title 'Sales by store';` | Sets the heading for the output that follows. |
| 11 | `proc print data=sales noobs;` | Starts PRINT to display `sales`. The `noobs` option hides the extra observation-number column. |
| 12 | `run;` | Executes PRINT. |
| 13 | `proc freq data=sales;` | Starts FREQ using the same `sales` dataset. |
| 14 | `tables store;` | Requests a one-way frequency table for `store`. This counts rows, not revenue totals. |
| 15 | `run;` | Executes FREQ and produces the frequency table. |

### Expected PRINT result

| store | week | revenue |
| --- | --- | --- |
| 1 | 1 | 120 |
| 1 | 2 | 125 |
| 2 | 1 | 135 |
| 2 | 2 | 140 |
| 3 | 1 | 150 |
| 3 | 2 | 155 |
| 4 | 1 | 165 |
| 4 | 2 | 170 |

### Expected FREQ result

| store | Frequency | Percent |
| --- | --- | --- |
| 1 | 2 | 25.00 |
| 2 | 2 | 25.00 |
| 3 | 2 | 25.00 |
| 4 | 2 | 25.00 |

The runtime also prints cumulative frequency and percentage columns. The
frequency for each store is 2 because there are two weeks per store.
Its percentage is `2 / 8 × 100 = 25%`.

## Demo 3: reaching a limitation, with every line explained

Open `demo/03-limitation.sas` and run it separately. It includes its own data
because datasets from Demo 1 do not persist into another submission. It uses
the same five observations but requests **PROC GLM**, which LocalStat does not
support. The failure is intentional; no implementation change is needed.

```sas
/* Intentional limitation demo: PROC GLM is unsupported in LocalStat. */
data measurements;
  input x y;
  datalines;
1 2
2 4
3 5
4 4
5 5
;
run;
proc glm data=measurements;
  model y = x;
run;
quit;
```

| Line | Code | Explanation |
| --- | --- | --- |
| 1 | `/* Intentional limitation demo: PROC GLM is unsupported in LocalStat. */` | A comment explaining why this program is expected to fail. |
| 2 | `data measurements;` | Begins a DATA step to create `measurements` within this submission. |
| 3 | `input x y;` | Reads two numeric values per row into `x` and `y`. |
| 4 | `datalines;` | Begins the inline data section. |
| 5 | `1 2` | Supplies observation 1: `x = 1`, `y = 2`. |
| 6 | `2 4` | Supplies observation 2: `x = 2`, `y = 4`. |
| 7 | `3 5` | Supplies observation 3: `x = 3`, `y = 5`. |
| 8 | `4 4` | Supplies observation 4: `x = 4`, `y = 4`. |
| 9 | `5 5` | Supplies observation 5: `x = 5`, `y = 5`. |
| 10 | `;` | Ends the inline data section. |
| 11 | `run;` | Marks the end of the DATA step. The complete submission still fails because GLM is unsupported. |
| 12 | `proc glm data=measurements;` | Requests the general linear models procedure. This is the unsupported feature that triggers the diagnostic. |
| 13 | `model y = x;` | Specifies the intended model with response `y` and predictor `x`. LocalStat does not fit it through GLM. |
| 14 | `run;` | Would execute the GLM model in an implementation supporting it. It cannot make the unsupported procedure run here. |
| 15 | `quit;` | Would end the GLM procedure. It does not remove the compatibility limit. |

### Expected failure

```text
ERROR: PROC glm is not supported
```

The bundled interpreter returns exit status **2**. In the app, inspect
**Diagnostics**. Do not expect coefficients from this run. For the simple
numeric straight-line model shown here, use `PROC REG` as in Demo 1. This is a
workaround for this example, not a replacement for all GLM features.

## Short answers to likely questions (outside the five minutes)

**Did you write the whole interpreter?**

> No. LocalStat builds on the open-source OpenSAS interpreter. My work adds
> the native Mac application, runtime extensions, result presentation, reports,
> and optimizations. The repository documents the upstream version and changes.

**How do you know the regression answer is correct?**

> This example can be checked by hand using the calculations above. The
> project also has numerical regression tests. A direct comparison against an
> installed SAS engine remains future work.

**Does R-square of 0.6 mean 60 percent accuracy?**

> No. It means 60 percent of the variation in these observed y values is
> accounted for by the fitted model. It is not a measure of prediction accuracy
> on new data and does not establish causation.

**Can it run every SAS program?**

> No. It runs a documented subset using an independent interpreter. I would
> check the compatibility guide before choosing a new course exercise.

**What is the main contribution?**

> Integrating a local interpreter into a native Mac workflow, extending useful
> functionality, and measuring specific memory and table-layout improvements.

## Evidence and demo verification

- Presentation: [localstat-beamer.tex](localstat-beamer.tex).
- Demo sources: [regression](demo/01-regression.sas),
  [reporting](demo/02-reporting.sas), and
  [intentional limitation](demo/03-limitation.sas).
- Scope: [compatibility guide](../COMPATIBILITY.md).
- Recorded checks: [verification record](../VERIFICATION.md).
- Performance evidence: [4 November experiment](../paper/results/2026-11-04-optimization/README.md).

The first two programs were checked with the bundled interpreter on
5 November 2026 and matched the results above. The third was checked on the
same date and returned the expected unsupported-GLM diagnostic and exit status
2. These checks cover interpreter output; the full test suite and live app
interaction were not rerun for this document. Performance numbers come from
the preserved 4 November experiment.
