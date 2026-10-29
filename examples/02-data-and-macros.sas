%let limit=5;
data squares;
  do x=1 to &limit;
    square=x*x;
    output;
  end;
run;
proc print data=squares noobs; run;
proc means data=squares; var square; run;
