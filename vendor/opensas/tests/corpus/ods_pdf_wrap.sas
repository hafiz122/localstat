/* Modified by LocalStat: expect-rc 2 for unavailable ODS destinations. */
/* expect-rc: 2; LocalStat rejects unavailable ODS destinations. */
ods pdf file="x.pdf";
data _null_; put "must not execute"; run;
