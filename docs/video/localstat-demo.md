# LocalStat: short write-along video

This version uses four records, two variables, PRINT, FREQ, and one filter edit.
The live demo has no regression block. It keeps the teaching example, upstream
credit, measured results, and proposed next step in the competition pitch.

Use [localstat-teleprompter.md](localstat-teleprompter.md) in the voice-following
teleprompter. That file contains only the spoken words below. This file pairs
those words with exactly what to type and show.

## Time budget

Treat these as rehearsal allowances, not measured recording times. Speaking
and typing are budgeted separately, so you can stop talking briefly to type.

| Part | Allowance |
| --- | --- |
| Spoken narration, at 130 words per minute | 2:11 |
| Typing the code, including short comments | 1:40 |
| Running the program and showing results | 0:25 |
| Total planned time | 4:16 |

The remainder of five minutes is your buffer for corrections and transitions.
If your typing takes longer, trim typing gaps during editing. Rehearse once
with a stopwatch before filming the final take.

## Write-along script

Begin with an empty editor. Type each block once. Run only where instructed.
Enter the four records directly after DATALINES, with no blank records. Read
only the Say text aloud; the comments remain in the code on screen.

### Opening

Show the application. No code to type yet.

Say:

> Assalamualaikum and hello. I'm Muhammad Hafiz bin Ismail, and this is LocalStat.
>
> LocalStat lets you write and run a supported subset of SAS programs on your Mac. The idea is simple: give learners one place to try some code and see what happens.

### 1. Start the dataset

Type:

```sas
/* Fictional data. */
data students;
input group score;
datalines;
```

Say:

> I'll create a small dataset with two fields: group and score. These are fictional values, entered directly into the program.

### 2. Enter four records

Type:

```sas
1 55
1 75
2 65
2 85
;
run;
```

Say:

> There are four records. The semicolon ends the data, and RUN finishes this step.

### 3. Display the records

Type:

```sas
/* Show the rows. */
proc print data=students noobs;
run;
```

Say:

> PRINT displays the records. I'll run this now. We can see all four scores.

On screen: Run the whole editor buffer and show the four PRINT rows.

### 4. Count each group

Type:

```sas
/* Count each group. */
proc freq data=students;
tables group;
run;
```

Say:

> Next, FREQ counts the records in each group. Running it again shows two in each.

On screen: Append below PRINT, run the whole buffer, and show the FREQ table.

### 5. Insert a filter

Go back to the existing PRINT block. This is an insertion, not an append.

Type:

```sas
where score >= 70; /* PRINT only. */
```

Say:

> Now I'll add a condition inside PRINT: show scores of seventy or above.

On screen: Insert this line between PROC PRINT and its existing RUN, then run the whole buffer. Keep FREQ below PRINT.

### Show the filtered result

Show PRINT scores 75 and 85, then the unchanged FREQ counts of two per group.
No additional code to type.

Say:

> We now see seventy-five and eighty-five. The group counts stay the same because the filter changes this display, not the dataset.
>
> A student can predict the result, change the code, and check their answer. That's the learning activity I'd build around LocalStat.

### Explain the contribution and close

Show Help or a PDF briefly, followed by the benchmark figures below. Finish
on camera. There is no additional code to type.

Say:

> The application also includes offline Help and PDF report export. Supported analyses run locally, without a hosted service.
>
> LocalStat builds on the open-source OpenSAS interpreter. My contributions include the native Mac application, runtime extensions, and structured tables.
>
> I also measured performance. Across seven tested million-row numeric workloads, optimizations reduced median peak interpreter memory by fifty-four to seventy-six percent.
>
> For a ten-thousand-row PRINT table, median construction time fell from about two hundred and eleven milliseconds to fifty-two, roughly four times faster.
>
> Those results come from one Apple M5 Mac. LocalStat is still an alpha application with a documented SAS subset.
>
> My next step would be a classroom pilot to find out where learners struggle and improve the application around that feedback.
>
> Thank you.

## Complete starting program

[localstat-demo.sas](localstat-demo.sas) contains the same commented program.
Use this as a reference while rehearsing; the five typing steps above are
all you need during filming.

```sas
/* Fictional data. */
data students;
input group score;
datalines;
1 55
1 75
2 65
2 85
;
run;
/* Show the rows. */
proc print data=students noobs;
run;
/* Count each group. */
proc freq data=students;
tables group;
run;
```

After the filter edit, PRINT should be:

```sas
/* Show the rows. */
proc print data=students noobs;
where score >= 70; /* PRINT only. */
run;
```

FREQ continues to use all four records, so its counts remain two per group.
The fictional scores demonstrate code behavior, not findings about students.

## Benchmark caption

These figures come from the recorded optimization study, not this four-row demo.
Label the machine Apple M5 / 16 GB memory.

| Measurement | Before | After |
| --- | --- | --- |
| Median peak interpreter memory, seven million-row numeric workloads | Baseline | 54.0–75.6% lower |
| Median table construction, 10,000 PRINT rows | 210.5 ms | 51.8 ms |

Keep the OpenSAS credit and the distinction between a working prototype and a
proposed classroom pilot. Malay subtitles are encouraged for an English entry.

## Sources

- [Official competition page](https://sites.google.com/mohe.gov.my/foi2026ai/home), rules checked 5 November 2026: maximum five-minute video; English or Malay; Malay subtitles encouraged for English entries.
- [Recorded optimization study](../paper/results/2026-11-04-optimization/README.md): measurements, methods, and limitations.
- [LaTeX manuscript](../paper/localstat.tex): code excerpts and results.
