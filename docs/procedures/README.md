# Procedure parity workbench

`coverage.json` is a provisional list from official Base SAS, SAS/STAT, SAS/ETS, SAS/OR, SAS/QC, SAS/IML, SAS/GRAPH, mapping, and ODS Graphics guides. Its `catalog_complete` value is `false`; none of its entries claims SAS parity. `sources.json` records each guide's URL, product version, SHA-256, extraction rule, and extracted names. The analytical products' 15.4 guides correspond to [SAS 9.4M9](https://documentation.sas.com/api/collections/pgmsascdc/9.4_3.5/docsets/whatsnew/content/whatsnew.pdf?locale=en).

This is not the complete 9.4M9 product catalog. Other product guides, procedure-specific documentation, statement/option inventories, and reference runs still need review. The current `source_url` points to a guide; `documentation_url` stays null until the individual procedure documentation is linked. Add features only from documented syntax. Only set `catalog_complete` after every installed product guide has been reviewed and no documented procedure is absent. The mapping guide records that SGMAP and several map-preparation procedures are in Base SAS by 9.4M9; GMAP remains in SAS/GRAPH. SGPLOT is sourced from the Base SAS ODS Graphics guide.

`SGPLOT` is tracked as a LocalStat subset covering SCATTER, SERIES, VBAR, and HBAR, which are documented in the [SAS 9.4 ODS Graphics Procedures Guide](https://documentation.sas.com/api/collections/pgmsascdc/9.4_3.5/docsets/grstatproc/content/grstatproc.pdf?locale=en). Its SVG output and app display require local tests, and no licensed SAS reference fixture has been captured. The `subset` status does not imply SAS visual or numerical parity.

## Reference batch adapter

Copy `sas-adapter.example.json` outside the repository and replace its executable path and arguments for the licensed local SAS 9.4M9 installation. The `argv` array is executed without a shell. Supported placeholders are `{program}`, `{workdir}`, `{log}`, `{listing}`, `{tables}`, and `{results_dir}`. The last two are primarily for LocalStat and future structured output; SAS may ignore them. Product tokens are passed to `%SYSPROD` during the probe. Add every product from the frozen catalog.

```sh
python3 scripts/procedure_parity.py probe --adapter /private/sas-adapter.json --out /private/sas-environment.json
python3 scripts/procedure_parity.py check-inventory
python3 scripts/procedure_parity.py source-inventory
```

The probe requires a `SYSVLONG4` marker containing `9.04...M9`, records `SYSSCP`, `%SYSPROD` results, and preserves the `PROC PRODUCT_STATUS` log for product review. The user must supply the licensed local batch command before any parity claim. Keep the environment record private if it contains license or site details. The SAS binary is used only to prepare and check fixtures, never when a user runs LocalStat.

## Cases

Put each case in `Tests/ProcedureParity/<case-id>/` with `program.sas`, `case.json`, and optional `inputs/`. A case declares every result it compares; there is no implicit pass for a missing output. For example:

```json
{
  "procedure": "MEANS",
  "comparisons": [
    {"kind": "csv", "reference": "work/output/stats.csv", "localstat": "work/output/stats.csv", "absolute_tolerance": 1e-10},
    {"kind": "text", "reference": "listing.txt", "localstat": "stdout.txt"}
  ]
}
```

`text` compares UTF-8 after newline normalization, `csv` compares the full grid and optionally tolerates numeric differences, `json` compares all keys and values, and `binary` requires exact bytes. These are initial comparators, not a claim that every SAS output type is covered. Add a comparator with documented tolerances for graphics and richer ODS objects before using them for a parity claim.

```sh
python3 scripts/procedure_parity.py capture --case Tests/ProcedureParity/<case-id> --adapter /private/sas-adapter.json --environment /private/sas-environment.json --out Tests/ProcedureParity/<case-id>/reference
python3 scripts/procedure_parity.py verify --case Tests/ProcedureParity/<case-id> --reference Tests/ProcedureParity/<case-id>/reference
python3 scripts/procedure_parity.py verify-all
```

Capture runs in a fresh temporary work directory, checks every declared reference artifact, and records source, case, and environment hashes. It refuses to replace an existing reference without `--replace`. Verify runs LocalStat in another fresh directory and fails if the case changed, an artifact is absent, an exit code differs, or a declared comparison differs. Reference fixtures need human review before they are committed. No licensed SAS output was available in this workspace to commit an initial fixture.

`verify-all` discovers every case directory with a `program.sas` or `case.json` and requires a committed `reference/reference.json` for each. It can run in ordinary CI without licensed SAS. While this provisional catalog has no reviewed reference fixtures, it reports zero verified cases and makes no parity claim.

`check-inventory --require-complete --environment /private/sas-environment.json` is the final catalog gate: it fails while the catalog is incomplete, any procedure lacks a verified product/version source and procedure-specific documentation, any entry is not `parity_verified`, a catalog procedure has no runtime dispatch, or the SAS probe cannot confirm the required licensed products and versions. It does not replace the differential result tests.
