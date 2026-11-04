data scores;
  input name $ score;
  passed=(score>=50);
  datalines;
Ana 72
Bo 45
Cy 91
;
run;
proc print data=scores; run;
