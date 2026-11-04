data demo;
  length name $20;
  name=upcase(strip('  Ana  '));
  magnitude=abs(-3);
  date=mdy(1,15,2026);
  format date date9.;
run;
proc print data=demo; run;
