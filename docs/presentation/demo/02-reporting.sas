/* Synthetic sales data matching the presentation preview. */
data sales;
  do store = 1 to 4;
    do week = 1 to 2;
      revenue = 100 + store*15 + week*5;
      output;
    end;
  end;
run;
title 'Sales by store';
proc print data=sales noobs;
run;
proc freq data=sales;
  tables store;
run;
