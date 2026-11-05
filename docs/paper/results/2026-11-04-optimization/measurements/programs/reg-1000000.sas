proc import datafile='input.csv' out=base dbms=csv replace; getnames=yes; run;
data _null_; set base end=done; retain n 0 total 0; n=n+1; total=total+id;  if done then put 'CHECK ' n best32. total best32.; run;
proc reg data=base; model y=x z; run; quit;
