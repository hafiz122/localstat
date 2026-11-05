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

data _null_; set experiment end=done; retain n 0 total 0; n=n+1; total=total+0;  if done then put 'CHECK ' n best32. total best32.; run;
