proc import datafile='input.csv' out=base dbms=csv replace; getnames=yes; run;
data result; set base; value=3*id+2; run;
data _null_; set result end=done; retain n 0 total 0; n=n+1; total=total+value;  if done then put 'CHECK ' n best32. total best32.; run;
