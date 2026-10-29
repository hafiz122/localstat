"""End-to-end checks against the exact bundled binary, using synthetic/public data."""
import math
import pathlib
import subprocess
import tempfile
import unittest

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
