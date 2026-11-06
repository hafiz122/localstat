"""End-to-end checks against the exact bundled binary, using synthetic/public data."""
import math
import json
import pathlib
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "dist/LocalStat.app/Contents/Helpers/opensas"
DATA = "data d; input x y; datalines;\n1 2\n2 4\n3 5\n4 4\n5 5\n;\nrun;\n"


def run(source, cwd=None):
    with tempfile.TemporaryDirectory(prefix="sas test source ") as folder:
        file = pathlib.Path(folder) / "program with spaces.sas"
        file.write_text(source)
        return subprocess.run([str(RUNTIME), str(file)], cwd=cwd or folder,
                              text=True, capture_output=True, timeout=15)


def table(output, name):
    return next(line.split("\t") for line in output.splitlines() if line.startswith(name + "\t"))


class RuntimeTests(unittest.TestCase):
    def test_sgplot_writes_graphics_to_result_bundle(self):
        source = ("data d; input category $ x y; datalines;\n"
                  "A 1 2\nA 2 4\nB 3 3\nB 4 5\n;\nrun;\n"
                  "proc print data=d; run;\n"
                  "proc sgplot data=d; scatter x=x y=y; run;\n"
                  "proc sgplot data=d; series x=x y=y; run;\n"
                  "proc sgplot data=d; vbar category / response=y stat=sum; run;\n"
                  "proc sgplot data=d; hbar category; run;\n")
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder)
            program = path / "program.sas"
            bundle = path / "results"
            program.write_text(source)
            result = subprocess.run([str(RUNTIME), str(program), "--results-dir", str(bundle)],
                                    cwd=folder, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = json.loads((bundle / "manifest.json").read_text())
            self.assertEqual(manifest["schema_version"], 1)
            self.assertTrue(manifest["complete"])
            tables = [item for item in manifest["objects"] if item["kind"] == "table"]
            self.assertEqual(len(tables), 1)
            self.assertEqual(tables[0]["procedure"], "PRINT")
            self.assertEqual(tables[0]["path"], "tables.json")
            self.assertEqual(len(json.loads((bundle / "tables.json").read_text())["tables"]), 1)
            graphics = [item for item in manifest["objects"] if item["kind"] == "graphic"]
            self.assertEqual(len(graphics), 4)
            for index, graphic in enumerate(graphics):
                self.assertEqual(graphic["procedure"], "SGPLOT")
                self.assertEqual(graphic["index"], index)
                self.assertTrue(graphic["path"].startswith("graphics/"))
                svg = ET.parse(bundle / graphic["path"]).getroot()
                self.assertEqual(svg.tag, "{http://www.w3.org/2000/svg}svg")
                self.assertGreater(float(svg.attrib["width"]), 0)
                self.assertGreater(float(svg.attrib["height"]), 0)
                tag = "circle" if index == 0 else "polyline" if index == 1 else "rect"
                role = "plot-point" if index == 0 else "plot-series" if index == 1 else "plot-bar"
                marks = [mark for mark in svg.findall(f".//{{http://www.w3.org/2000/svg}}{tag}")
                         if mark.attrib.get("class") == role]
                self.assertGreaterEqual(len(marks), 4 if index == 0 else 1 if index == 1 else 2)
                if index == 0:
                    self.assertEqual(len(marks), 4)
                if index == 1:
                    self.assertEqual(len(marks), 1)
                    self.assertEqual(len(marks[0].attrib["points"].split()), 4)
                if index == 2:
                    self.assertEqual(len(marks), 2)
                    self.assertAlmostEqual(float(marks[0].attrib["height"]) /
                                           float(marks[1].attrib["height"]), 6 / 8, places=2)

    def test_sgplot_sas_like_categories_width_and_series_order(self):
        source = ("data d; input category $ x y; datalines;\n"
                  "B 3 30\nA 1 10\nC 2 20\nA 4 .\nB 5 5\n;\nrun;\n"
                  "proc sgplot data=d; scatter x=x y=y; run;\n"
                  "proc sgplot data=d; series x=x y=y; run;\n"
                  "proc sgplot data=d; vbar category / response=y stat=sum; run;\n"
                  "proc sgplot data=d; hbar category; run;\n")
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder)
            program = path / "program.sas"
            bundle = path / "results"
            program.write_text(source)
            result = subprocess.run([str(RUNTIME), str(program), "--results-dir", str(bundle)],
                                    cwd=folder, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = json.loads((bundle / "manifest.json").read_text())
            graphics = [obj for obj in manifest["objects"] if obj["kind"] == "graphic"]
            self.assertEqual(len(graphics), 4)
            svgs = [ET.parse(bundle / obj["path"]).getroot() for obj in graphics]
            namespace = "{http://www.w3.org/2000/svg}"
            scatter = [mark for mark in svgs[0].iter(namespace + "circle")
                       if mark.attrib.get("class") == "plot-point"]
            self.assertEqual(len(scatter), 4, "missing numeric pairs should not create markers")
            lines = [mark for mark in svgs[1].iter(namespace + "polyline")
                     if mark.attrib.get("class") == "plot-series"]
            self.assertEqual(len(lines), 1)
            x_coordinates = [float(point.split(",")[0]) for point in lines[0].attrib["points"].split()]
            self.assertEqual(len(x_coordinates), 4)
            self.assertGreater(x_coordinates[0], x_coordinates[1])
            self.assertGreater(x_coordinates[2], x_coordinates[1])
            self.assertGreater(x_coordinates[3], x_coordinates[0])
            for index, svg in enumerate(svgs[2:]):
                labels = [node for node in svg.iter(namespace + "text")
                          if node.attrib.get("class") == "category-label"]
                axis = "x" if index == 0 else "y"
                ordered = sorted(labels, key=lambda node: float(node.attrib[axis]), reverse=index == 1)
                self.assertEqual(["".join(node.itertext()) for node in ordered], ["A", "B", "C"])
                ticks = ["".join(node.itertext()) for node in svg.iter(namespace + "text")
                         if node.attrib.get("class") == "value-tick"]
                self.assertIn(0.0, [float(tick) for tick in ticks])
            vbars = [mark for mark in svgs[2].iter(namespace + "rect")
                     if mark.attrib.get("class") == "plot-bar"]
            self.assertEqual(len(vbars), 3)
            vbars.sort(key=lambda bar: float(bar.attrib["x"]))
            self.assertEqual([float(bar.attrib["data-value"]) for bar in vbars], [10, 35, 20])
            centers = [float(bar.attrib["x"]) + float(bar.attrib["width"]) / 2 for bar in vbars]
            slot = centers[1] - centers[0]
            self.assertGreater(slot, 0)
            self.assertAlmostEqual(float(vbars[0].attrib["width"]) / slot, 0.8, delta=0.05)
            hbars = [mark for mark in svgs[3].iter(namespace + "rect")
                     if mark.attrib.get("class") == "plot-bar"]
            self.assertEqual(len(hbars), 3)
            hbars.sort(key=lambda bar: float(bar.attrib["y"]), reverse=True)
            self.assertEqual([float(bar.attrib["data-value"]) for bar in hbars], [2, 2, 1])

    def test_corr_and_ttest_subsets_run_in_bundled_helper(self):
        source = ("data d; input x y; datalines;\n1 3\n2 6\n3 9\n;\nrun;\n"
                  "proc corr data=d; var x y; run;\n"
                  "proc ttest data=d; var x; run;\n")
        with tempfile.TemporaryDirectory() as folder:
            program = pathlib.Path(folder) / "program.sas"
            sidecar = pathlib.Path(folder) / "tables.json"
            program.write_text(source)
            result = subprocess.run([str(RUNTIME), str(program), "--tables-json", str(sidecar)],
                                    cwd=folder, text=True, capture_output=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Pearson Correlation Coefficients", result.stdout)
            self.assertIn("The TTEST Procedure", result.stdout)
            tables = json.loads(sidecar.read_text())["tables"]
            self.assertIn("CORR", [item["procedure"] for item in tables])

    def test_formatted_table_sidecar_preserves_stdout_and_order(self):
        source = ("data d; input group $ response $ value; datalines;\n"
                  "A yes 10\nA no 20\nB yes 30\n;\nrun;\n"
                  "proc print data=d noobs label; label value='Value \"USD\"'; sum value; run;\n"
                  "proc freq data=d; tables group response group*response; run;\n"
                  "proc tabulate data=d; class group response; var value; "
                  "table group all, response*value*sum all*value*sum; run;\n")
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder)
            program = path / "program.sas"
            sidecar = path / "tables.json"
            program.write_text(source)
            baseline = subprocess.run([str(RUNTIME), str(program)], cwd=folder,
                                      capture_output=True, text=True, timeout=15)
            formatted = subprocess.run([str(RUNTIME), str(program), "--tables-json", str(sidecar)],
                                       cwd=folder, capture_output=True, text=True, timeout=15)
            self.assertEqual((formatted.returncode, formatted.stdout, formatted.stderr),
                             (baseline.returncode, baseline.stdout, baseline.stderr))
            document = json.loads(sidecar.read_text())
            self.assertEqual(document["version"], 1)
            tables = document["tables"]
            self.assertEqual([t["procedure"] for t in tables],
                             ["PRINT", "FREQ", "FREQ", "FREQ", "TABULATE"])
            for item in tables:
                columns = sum(cell["span"] for cell in item["headers"][-1]["cells"])
                self.assertGreater(columns, 0)
                for row in item["headers"] + item["rows"]:
                    self.assertEqual(sum(cell["span"] for cell in row["cells"]), columns)
            self.assertIn('Value "USD"', str(tables[0]["headers"]))
            self.assertTrue(any(r["kind"] == "total" for r in tables[0]["rows"]))
            self.assertTrue(any("Frequency:" in cell["text"] for row in tables[3]["rows"]
                                for cell in row["cells"]))
            self.assertGreater(len(tables[-1]["headers"]), 2)

    def test_table_sidecar_suppression_empty_and_partial_error(self):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder)
            program = path / "program.sas"
            sidecar = path / "tables.json"
            program.write_text("data d; x=1; run; proc freq data=d noprint; tables x; run; "
                               "proc print data=d; run; proc print data=missing; run;")
            result = subprocess.run([str(RUNTIME), str(program), "--tables-json", str(sidecar)],
                                    cwd=folder, capture_output=True, text=True, timeout=15)
            self.assertNotEqual(result.returncode, 0)
            tables = json.loads(sidecar.read_text())["tables"]
            self.assertEqual([t["procedure"] for t in tables], ["PRINT"])
            self.assertIn("1", str(tables[0]["rows"]))

    def test_freq_nlevels_and_tabulate_by_sections(self):
        source = ("data d; input g $ x; datalines;\nA 1\nA 2\nB 3\n;\nrun;\n"
                  "proc freq data=d nlevels; tables g; run;\n"
                  "proc tabulate data=d; class g; var x; by g; table g, x*sum; run;\n")
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder)
            program = path / "program.sas"
            sidecar = path / "tables.json"
            program.write_text(source)
            result = subprocess.run([str(RUNTIME), str(program), "--tables-json", str(sidecar)],
                                    cwd=folder, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            tables = json.loads(sidecar.read_text())["tables"]
            self.assertEqual([t["procedure"] for t in tables], ["FREQ", "FREQ", "TABULATE", "TABULATE"])
            self.assertEqual([t["section"] for t in tables[-2:]], ["g=A", "g=B"])

    def test_analytic_regression(self):
        result = run(DATA + "proc reg data=d; model y=x; run; quit;")
        self.assertEqual(result.returncode, 0, result.stderr)
        intercept = list(map(float, table(result.stdout, "Intercept")[2:]))
        slope = list(map(float, table(result.stdout, "x")[2:]))
        self.assertAlmostEqual(intercept[0], 2.2, places=9)
        self.assertAlmostEqual(slope[0], .6, places=9)
        self.assertAlmostEqual(intercept[1], math.sqrt(.88), places=9)
        self.assertAlmostEqual(slope[1], math.sqrt(.08), places=9)
        self.assertAlmostEqual(float(table(result.stdout, "Error")[2]), 2.4, places=9)
        self.assertAlmostEqual(float(table(result.stdout, "R-Square")[1]), .6, places=9)
        # Closed-form two-sided t survival for 3 residual degrees of freedom.
        u = (.6 / math.sqrt(.08)) / math.sqrt(3)
        probability = 1 - 2 / math.pi * (math.atan(u) + u / (1 + u*u))
        self.assertAlmostEqual(slope[3], probability, places=9)
        self.assertAlmostEqual(float(table(result.stdout, "Model")[5]), probability, places=9)

    def test_multiple_regression(self):
        result = run((ROOT / "examples/03-multiple-regression.sas").read_text())
        self.assertEqual(result.returncode, 0, result.stderr)
        for name, expected in [("Intercept", 2), ("x", 3), ("z", -4)]:
            self.assertAlmostEqual(float(table(result.stdout, name)[2]), expected, places=9)
        self.assertAlmostEqual(float(table(result.stdout, "Error")[2]), 12, places=9)
        fstat = float(table(result.stdout, "Model")[4])
        expected_p = (3 / (3 + 2*fstat)) ** 1.5
        self.assertAlmostEqual(float(table(result.stdout, "Model")[5]), expected_p, places=9)

    def test_published_sas_population_example(self):
        # SAS/STAT 13.2, REG, Polynomial Regression, Figure 85.5:
        # https://support.sas.com/documentation/cdl/en/statug/67523/HTML/default/statug_reg_gettingstarted02.htm
        # Public US census observations; omit unsupported plots and interval options.
        populations = [3929,5308,7239,9638,12866,17069,23191,31443,39818,50155,
                       62947,75994,91972,105710,122775,131669,151325,179323,203211,
                       226542,248710,281422]
        source = "data census; input Year Population; datalines;\n"
        source += "\n".join(f"{1790 + 10*i} {p/1000}" for i,p in enumerate(populations))
        source += "\n;\nrun; proc reg data=census; model Population=Year; run; quit;"
        result = run(source)
        self.assertEqual(result.returncode, 0, result.stderr)
        # Published table is rounded to five decimal places.
        for name, coefficient, se in [("Intercept", -2345.85498, 161.39279), ("Year", 1.28786, .08512)]:
            values = table(result.stdout, name)
            self.assertAlmostEqual(float(values[2]), coefficient, delta=0.0000051)
            self.assertAlmostEqual(float(values[3]), se, delta=0.0000051)
        self.assertAlmostEqual(float(table(result.stdout, "Error")[3]), 641.58160, delta=.0000051)

    def test_complete_cases(self):
        source = DATA.replace("5 5\n", "5 5\n. 100\n6 .\n.A 99\n")
        result = run(source + "proc reg data=d; model y=x; run;")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Observations Read: 8", result.stdout)
        self.assertIn("Observations Used: 5", result.stdout)
        self.assertAlmostEqual(float(table(result.stdout, "x")[2]), .6, places=9)

    def test_singular_and_insufficient(self):
        for rows, expected in [("1 2\n1 3\n1 4", "Rank-deficient"), ("1 2\n2 3", "Insufficient")]:
            with self.subTest(rows=rows):
                result = run("data d; input x y; datalines;\n"+rows+"\n;\nrun; proc reg data=d; model y=x; run;")
                self.assertEqual(result.returncode, 1)
                self.assertIn(expected, result.stderr)
                self.assertNotIn("Parameter Estimates", result.stdout)

    def test_constant_and_perfect(self):
        for rows in ["1 4\n2 4\n3 4\n4 4", "1 3\n2 5\n3 7\n4 9", "1 0\n2 0\n3 0\n4 0"]:
            result = run("data d; input x y; datalines;\n"+rows+"\n;\nrun; proc reg data=d; model y=x; run;")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Perfect fit", result.stdout)
            self.assertNotRegex(result.stdout.lower(), r"\b(?:nan|inf|infinity)\b")
            self.assertEqual(float(table(result.stdout, "Error")[2]), 0)
            self.assertEqual(table(result.stdout, "x")[4:], [".", "."])

    def test_nonnumeric_and_unknown(self):
        for source in ["data d; input x $ y; datalines;\na 1\nb 2\nc 3\n;\nrun;",
                       "data d; input x y $; datalines;\n1 a\n2 b\n3 c\n;\nrun;"]:
            result = run(source + "proc reg data=d; model y=x; run;")
            self.assertEqual(result.returncode, 1)
            self.assertIn("numeric", result.stderr)
        result = run(DATA + "proc reg data=d; model y=missingvar; run;")
        self.assertEqual(result.returncode, 1)
        self.assertIn("not found", result.stderr)

    def test_unsupported_syntax(self):
        for header, body in [
            ("data=d", "model y=x / selection=stepwise;"),
            ("data=d", "model y=x; weight x;"),
            ("data=d", "model y=x; freq x;"),
            ("data=d", "model y=x; by x;"),
            ("data=d", "model y=x; output out=fitted p=p;"),
            ("data=d", "model y=x; model x=y;"),
            ("data=d plots=all", "model y=x;"),
            ("data=d", "model y=x / noint;"),
            ("data=d(obs=3)", "model y=x;"),
            ("data=d", "model y=x*x;"),
        ]:
            with self.subTest(header=header, body=body):
                result = run(DATA + f"proc reg {header}; {body} run;")
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("does not support", result.stderr)
                self.assertNotIn("Parameter Estimates", result.stdout)

    def test_malformed_and_duplicate(self):
        for body in ["model y x;", "model y=;", "model y=x x;", "", "model =x;"]:
            result = run(DATA + f"proc reg data=d; {body} run;")
            self.assertEqual(result.returncode, 1, result.stderr)

    def test_case_macros_and_global_statements(self):
        result = run(DATA + "%let response=y; PROC REG DATA=WORK.D; title 'Regression'; MODEL &response=X; RUN; QUIT;")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Regression", result.stdout)
        self.assertAlmostEqual(float(table(result.stdout, "X")[2]), .6, places=9)

    def test_ods_destinations(self):
        for destination in ["pdf", "html", "rtf", "excel", "graphics on", "_all_ close"]:
            result = run(f"ods {destination}; " + DATA + "proc print data=d; run;")
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn("only text listing", result.stderr)

    def test_cli_missing_input(self):
        for arguments in [[], ["/no/such/input.sas"], ["--sasautos"], ["--unknown"], ["one.sas", "two.sas"]]:
            result = subprocess.run([str(RUNTIME)] + arguments, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 1)

    def test_explicit_files_persist_and_work_does_not(self):
        with tempfile.TemporaryDirectory(prefix="sas library ") as directory:
            result = run("libname out '.'; data out.saved; x=42; run;", cwd=directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            files = list(pathlib.Path(directory).glob("saved.*"))
            self.assertTrue(files)
            result = run("libname out '.'; proc print data=out.saved; run;", cwd=directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("42", result.stdout)
            result = run("proc print data=work.saved; run;", cwd=directory)
            self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
