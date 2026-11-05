Assalamualaikum and hello. I'm Muhammad Hafiz bin Ismail, and this is LocalStat.

LocalStat lets you write and run a supported subset of SAS programs on your Mac. The idea is simple: give learners one place to try some code and see what happens.

I'll create a small dataset with two fields: group and score. These are fictional values, entered directly into the program.

There are four records. The semicolon ends the data, and RUN finishes this step.

PRINT displays the records. I'll run this now. We can see all four scores.

Next, FREQ counts the records in each group. Running it again shows two in each.

Now I'll add a condition inside PRINT: show scores of seventy or above.

We now see seventy-five and eighty-five. The group counts stay the same because the filter changes this display, not the dataset.

A student can predict the result, change the code, and check their answer. That's the learning activity I'd build around LocalStat.

The application also includes offline Help and PDF report export. Supported analyses run locally, without a hosted service.

LocalStat builds on the open-source OpenSAS interpreter. My contributions include the native Mac application, runtime extensions, and structured tables.

I also measured performance. Across seven tested million-row numeric workloads, optimizations reduced median peak interpreter memory by fifty-four to seventy-six percent.

For a ten-thousand-row PRINT table, median construction time fell from about two hundred and eleven milliseconds to fifty-two, roughly four times faster.

Those results come from one Apple M5 Mac. LocalStat is still an alpha application with a documented SAS subset.

My next step would be a classroom pilot to find out where learners struggle and improve the application around that feedback.

Thank you.
