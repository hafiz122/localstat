proc import datafile='input.csv' out=base dbms=csv replace; getnames=yes; run;
proc import datafile='dimension.csv' out=dim dbms=csv replace; getnames=yes; run;
proc sql; create table joined as select a.id, b.weight from base as a inner join dim as b on a.grp=b.grp; quit;
data _null_; set joined end=done; retain n 0 total 0 weights 0 bad 0; n=n+1; total=total+id; weights=weights+weight; if weight ne mod(10000-id,100)+1 then bad=bad+1; if done then put 'CHECK ' n best32. total best32. weights best32. bad best32.; run;
