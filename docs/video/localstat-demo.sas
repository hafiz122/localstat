/* Fictional data. */
data students;
input group score;
datalines;
1 55
1 75
2 65
2 85
;
run;
/* Show the rows. */
proc print data=students noobs;
run;
/* Count each group. */
proc freq data=students;
tables group;
run;
