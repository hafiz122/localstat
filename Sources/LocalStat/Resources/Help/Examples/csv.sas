/* Creates localstat-help-demo.csv in the current project folder. */
data _null_;
  file 'localstat-help-demo.csv';
  put 'name,value';
  put 'Ana,10';
  put 'Bo,20';
run;
proc import datafile='localstat-help-demo.csv' out=work.imported dbms=csv replace;
  getnames=yes;
run;
proc print data=work.imported; run;
