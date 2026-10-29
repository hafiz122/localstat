/* Orthogonal synthetic predictors: intercept=2, x=3, z=-4. */
data experiment;
  input x z y;
  datalines;
-1 -1 4
-1 1 -4
0 -1 4
0 1 -4
1 -1 10
1 1 2
;
run;
proc reg data=experiment;
  model y = x z;
run;
quit;
