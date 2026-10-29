# Penn State probability demo for LocalStat

## Source

This question is adapted from [Penn State STAT 500, Lesson 2, Example 2.5](https://online.stat.psu.edu/stat500/Lesson02).

## Question

Two fair six-sided dice are rolled. What is the probability that their sum is greater than or equal to 10?

## LocalStat program

```sas
/*
  Question adapted from Penn State STAT 500:
  What is the probability that two fair dice
  have a sum greater than or equal to 10?
*/

/* Create a dataset containing all possible dice outcomes. */
data dice_outcomes;

  /* Generate each possible value of the first die. */
  do die1 = 1 to 6;

    /* Pair it with each possible value of the second die. */
    do die2 = 1 to 6;

      /* Calculate the sum of the two dice. */
      total = die1 + die2;

      /* Record 1 when the sum is at least 10 and 0 otherwise. */
      sum_at_least_10 = (total >= 10);

      /* Save this combination as one observation. */
      output;

    /* Finish the second-die loop. */
    end;

  /* Finish the first-die loop. */
  end;

/* Execute the DATA step. */
run;

/* Add a heading to the results. */
title 'Probability That Two Dice Sum to At Least 10';

/* Calculate the number of outcomes, successes, and probability. */
proc means data=dice_outcomes n sum mean;

  /* Analyze the binary indicator for the event. */
  var sum_at_least_10;

/* Execute PROC MEANS. */
run;
```

## Expected result

LocalStat should report:

```text
N      = 36
SUM    = 6
MEAN   = 0.1666667
```

The six successful outcomes are:

```text
(4,6), (5,5), (6,4), (5,6), (6,5), (6,6)
```

Therefore:

\[
P(\text{sum} \ge 10) = \frac{6}{36} = \frac{1}{6} \approx 16.67\%
\]

## Suggested LinkedIn opening

> I found this probability exercise in Penn State's online statistics course. Can my native Mac SAS-language app solve it?

