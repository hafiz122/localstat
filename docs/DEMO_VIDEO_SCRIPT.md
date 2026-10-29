# LocalStat demo video script

**Estimated duration:** 4 to 5 minutes

**Topic:** Solving SAS-language compatibility problems on macOS

## 0:00 to 0:35 | The compatibility problem

**On screen:** Show the LocalStat icon, then open the application.

**Narration:**

> Many students, researchers, and analysts receive SAS programs but cannot run a traditional SAS runtime directly on their Apple Silicon Mac.
>
> LocalStat addresses this compatibility problem with a native macOS editor and a bundled local SAS-language runtime. It does not require a server, virtual machine, or separate SAS installation.

## 0:35 to 1:00 | Set expectations

**On screen:** Show the editor, project sidebar, Output pane, and Diagnostics pane.

**Narration:**

> LocalStat is an independent SAS-language implementation based on OpenSAS. It supports a tested subset of the SAS language, but it is not a complete replacement for SAS Institute software.
>
> The application documents its compatibility boundaries and reports unsupported behavior through diagnostics instead of claiming that every SAS program will work.

## 1:00 to 1:25 | Introduce the probability problem

**On screen:** Create a new SAS program.

**Narration:**

> For this demonstration, I will solve a simple probability problem.
>
> Two fair six-sided dice are rolled. What is the probability that their sum is seven?
>
> The program will generate the complete sample space and calculate the probability from all possible outcomes.

## 1:25 to 2:10 | Enter the SAS program

**On screen:** Paste this program into LocalStat.

```sas
/*
  Probability demonstration:

  Two fair six-sided dice are rolled.
  What is the probability that their sum is 7?
*/

/* Create a dataset containing the complete sample space. */
data dice_rolls;
  /* Cycle through the six possible values of the first die. */
  do die1 = 1 to 6;
    /* Pair each first-die value with every value of the second die. */
    do die2 = 1 to 6;
      /* Add the two dice to get the outcome's total. */
      total = die1 + die2;
      /* Store 1 for a total of 7 and 0 for every other total. */
      sum_is_7 = (total = 7);
      /* Write the current dice combination to the dataset. */
      output;
    /* Finish the loop for the second die. */
    end;
  /* Finish the loop for the first die. */
  end;
/* Execute the DATA step after generating all 36 combinations. */
run;

/* Label the statistical output shown in the results pane. */
title 'Probability That Two Dice Sum to 7';

/* Calculate the count, number of successes, and probability estimate. */
proc means data=dice_rolls n sum mean;
  /* Analyze the binary indicator created for each dice combination. */
  var sum_is_7;
/* Execute PROC MEANS and print its results. */
run;
```

**Narration:**

> The nested loops generate every possible pair of dice values.
>
> The variable `sum_is_7` equals one when the total is seven and zero for every other outcome.
>
> Because this is a binary indicator, its mean is the probability of the event.

## 2:10 to 2:40 | Run the program

**On screen:** Click **Run Program**.

**Narration:**

> LocalStat executes the entire editor buffer in a fresh local process. The program is not uploaded to a remote service.
>
> The results appear in the Output pane. Parser and runtime messages appear separately in Diagnostics.

## 2:40 to 3:15 | Explain the result

**On screen:** Point to the `N`, `SUM`, and `MEAN` values.

**Narration:**

> The result contains 36 observations because two dice have 36 equally likely combinations.
>
> The sum of the indicator variable is six, meaning six combinations produce a total of seven.
>
> Its mean is approximately 0.1667. Therefore, the probability is six divided by 36, or approximately 16.67 percent.

## 3:15 to 3:50 | Explain compatibility handling

**On screen:** Open **Help > Compatibility and Limitations**.

**Narration:**

> LocalStat treats compatibility as a documented engineering problem.
>
> The compatibility matrix lists the language features and procedures that have been tested, those with partial support, and those that remain unsupported.
>
> Unsupported features should produce an explicit diagnostic instead of silently returning a misleading result.
>
> Each run starts with clean WORK data and macro state, which makes execution predictable and reproducible.

## 3:50 to 4:20 | Export the report

**On screen:** Select **File > Export Report as PDF...** and show the native save panel.

**Narration:**

> The completed run can be exported as a searchable PDF report.
>
> The report includes the executed source snapshot, program name, working directory, runtime version, termination status, output, and diagnostics.
>
> This report export belongs to the LocalStat IDE. It is not an implementation of the SAS ODS PDF destination.

## 4:20 to 4:40 | Closing

**On screen:** Show the editor and completed output together.

**Narration:**

> LocalStat provides a practical way to run supported SAS-language programs locally on Apple Silicon Macs.
>
> The project does not hide compatibility gaps. It tests and documents current behavior while providing a useful native workflow for the supported subset.

## Expected result

The `PROC MEANS` output should report:

- `N = 36`
- `SUM = 6`
- `MEAN` approximately `0.1667`

The probability that two fair dice sum to seven is therefore approximately **16.67 percent**.

