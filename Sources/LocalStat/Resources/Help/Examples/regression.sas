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
proc reg data=measurements;
  model y=x;
run;
quit;
