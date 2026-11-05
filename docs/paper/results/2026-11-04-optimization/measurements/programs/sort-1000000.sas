proc import datafile='input.csv' out=base dbms=csv replace; getnames=yes; run;
proc sort data=base out=sorted; by id; run;
data _null_; set sorted end=done; retain n 0 total 0 bad 0; n=n+1; total=total+id; if id ne n then bad=bad+1; if done then put 'CHECK ' n best32. total best32. bad best32.; run;
