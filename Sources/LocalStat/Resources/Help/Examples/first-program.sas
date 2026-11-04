data measurements;
  input value;
  datalines;
10
20
30
;
run;
proc means data=measurements n mean;
  var value;
run;
