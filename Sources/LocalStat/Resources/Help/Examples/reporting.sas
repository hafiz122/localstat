data scores;
  input name $ group $ score;
  datalines;
Ana A 72
Bo A 45
Cy B 91
;
run;
proc print data=scores; run;
proc means data=scores n mean; var score; run;
proc freq data=scores; tables group; run;
proc tabulate data=scores; class group; var score; table group, score*mean; run;
