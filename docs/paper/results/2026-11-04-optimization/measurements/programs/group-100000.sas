proc import datafile='input.csv' out=base dbms=csv replace; getnames=yes; run;
proc sql; create table grouped as select grp, count(*) as cnt, sum(id) as subtotal from base group by grp; quit;
data _null_; set grouped end=done; retain groups 0 n 0 total 0 bad 0; groups=groups+1; n=n+cnt; total=total+subtotal; expected=1000*(100000-grp)-100*499500; if cnt ne 1000 or subtotal ne expected then bad=bad+1; if done then put 'CHECK ' groups best32. n best32. total best32. bad best32.; run;
