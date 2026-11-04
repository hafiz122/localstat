data sales;
  input group $ amount;
  datalines;
A 10
A 20
B 7
;
run;
proc sql;
  select group, sum(amount) as total from sales group by group order by group;
quit;
