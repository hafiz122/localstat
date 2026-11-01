# Third-party notices and fixture provenance

LocalStat vendors OpenSAS at commit
`927a2fa9f1401e365d975536bd704819ada1f1f4` under Apache-2.0. Its license and
modification record are retained in `vendor/opensas/LICENSE` and
`docs/RUNTIME_CHANGES.md`.

The SAS7BDAT and SAS7BCAT readers identify portions ported from Evan Miller's
ReadStat under MIT. The full notice is in `licenses/ReadStat-MIT.txt` and is
bundled with the app. Source: https://github.com/WizardMac/ReadStat/blob/master/LICENSE.

## External binary fixtures

On 1 November 2026 the following Git blob hashes matched upstream exactly.
These fixtures are used by source tests and are not copied into app Resources.

| Local file under vendor/opensas/src/testdata | Upstream file | Git blob SHA-1 |
| --- | --- | --- |
| formats.sas7bcat | haven tests/testthat/sas/formats.sas7bcat | 9c0076e06307e17ffffe7a27fdbbaf42d53e36d3 |
| hadley.sas7bdat | haven tests/testthat/sas/hadley.sas7bdat | e0df5e59eaaf04136b53c7f5a0e0867835770da6 |
| tagged_na.sas7bdat | haven tests/testthat/sas/tagged-na.sas7bdat | adb30e1f663a25f6e86422a520206e0c4a889e6e |
| test7.sas7bdat | pandas pandas/tests/io/sas/data/test7.sas7bdat | 785b12cf175e39d9a7aa73475f6ebc8ffec3a8c3 |

haven reference: https://github.com/tidyverse/haven/tree/66a332ab467edc0f55ee01071b51eeeec5a7106f/tests/testthat/sas.
Its MIT notice is retained in `licenses/haven-MIT.txt`.

pandas reference: https://github.com/pandas-dev/pandas/blob/c42cc0a6fc9f748ba01fa1e59ff67eaf44012bd0/pandas/tests/io/sas/data/test7.sas7bdat.
Its BSD license and accompanying notices are retained in `licenses/pandas-LICENSE.txt`.

Other `.sas7bdat` and `.xpt` corpus fixtures are inherited with the pinned
OpenSAS snapshot. The TE fixture's upstream NOTES describe its synthetic data
and OpenSAS generation. No claim of separate SAS Institute endorsement or
validation follows from these fixtures.

The photographic logo and derived icon are covered separately in
`ASSET_LICENSES.md`; they are excluded from Apache-2.0.
