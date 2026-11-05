proc import datafile='input.csv' out=base dbms=csv replace; getnames=yes; run;
proc export data=base outfile='roundtrip.csv' dbms=csv replace; run;
proc import datafile='roundtrip.csv' out=again dbms=csv replace; getnames=yes; run;
data _null_; set again end=done; retain n 0 total 0; n=n+1; total=total+id;  if done then put 'CHECK ' n best32. total best32.; run;
