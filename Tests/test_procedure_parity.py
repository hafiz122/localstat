"""Failure-path tests for the licensed-SAS procedure comparison harness."""

import importlib.util
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("procedure_parity", ROOT / "scripts/procedure_parity.py")
parity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parity)


class ParityHarnessTests(unittest.TestCase):
    def test_provisional_catalog_cannot_claim_completion(self):
        coverage = parity.read_json(parity.DEFAULT_COVERAGE)
        names = parity.validate_coverage(coverage)
        self.assertIn("PRINTTO", names)
        self.assertGreater(len(parity.validate_registry_coverage(parity.DEFAULT_REGISTRY, names)), 20)
        sources, sourced, unsourced = parity.validate_source_coverage(
            coverage, parity.read_json(parity.DEFAULT_SOURCES))
        self.assertIn("GLM", sourced)
        self.assertIn("SGPLOT", sourced)
        self.assertEqual(unsourced, [])
        self.assertEqual(len(sourced), len(names))
        self.assertEqual(sources["sas-stat-15.4-categories"]["product_version"], "15.4")
        broken = copy.deepcopy(coverage)
        next(entry for entry in broken["procedures"] if entry["name"] == "GLM")["source_ids"] = []
        with self.assertRaisesRegex(parity.ParityError, "missing source link"):
            parity.validate_source_coverage(broken, parity.read_json(parity.DEFAULT_SOURCES))
        with self.assertRaisesRegex(parity.ParityError, "not complete"):
            parity.validate_coverage(coverage, require_complete=True)

    def test_reference_environment_requires_installed_product_evidence(self):
        sources = parity.validate_sources(parity.read_json(parity.DEFAULT_SOURCES))
        environment = {"target_release": "SAS 9.4M9", "sysvlong4": "9.04.01M9P010125",
                       "product_status_log": "\n".join(f"{source['product']} {source['product_version']}" for source in sources.values()),
                       "product_tokens": {source["reference_product_token"]: "1" for source in sources.values()
                                          if source["product"] != "Base SAS"}}
        environment["product_tokens"]["STAT"] = "0"
        with self.assertRaisesRegex(parity.ParityError, "not confirmed licensed"):
            parity.validate_reference_environment(environment, sources)
        environment["product_tokens"]["STAT"] = "1"
        parity.validate_reference_environment(environment, sources)

    def test_duplicate_and_unsupported_artifact_paths_fail(self):
        coverage = {"target_release": "SAS 9.4M9", "procedures": [
            {"name": "REG", "status": "subset"}, {"name": "REG", "status": "subset"}]}
        with self.assertRaisesRegex(parity.ParityError, "duplicate"):
            parity.validate_coverage(coverage)
        for path in ("../outside", "/absolute", ""):
            with self.subTest(path=path), self.assertRaises(parity.ParityError):
                parity.safe_relative(path)

    def test_capture_and_verify_use_fresh_work_and_declared_artifacts(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            case = root / "group" / "case"
            case.mkdir(parents=True)
            (case / "program.sas").write_text("proc means; run;\n")
            (case / "case.json").write_text(json.dumps({
                "procedure": "MEANS",
                "comparisons": [{"kind": "csv", "reference": "work/output/stats.csv",
                                 "localstat": "work/output/stats.csv", "absolute_tolerance": 1e-10}],
            }))
            executable = root / "fake-runner"
            executable.write_text("#!/usr/bin/env python3\nfrom pathlib import Path\n"
                                  "Path('output/stats.csv').write_text('name,value\\nx,1.0\\n')\n"
                                  "print('result')\n")
            executable.chmod(0o755)
            adapter = root / "adapter.json"
            adapter.write_text(json.dumps({"argv": [str(executable), "{program}"]}))
            environment = root / "environment.json"
            environment.write_text(json.dumps({"target_release": "SAS 9.4M9", "sysvlong4": "9.04.01M9P010125"}))
            reference = root / "reference"
            parity.capture(case, adapter, environment, reference)
            self.assertEqual(parity.verify(case, reference, executable), 1)
            committed = case / "reference"
            committed.mkdir()
            for item in reference.rglob("*"):
                if item.is_file():
                    target = committed / item.relative_to(reference)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(item.read_bytes())
            coverage = root / "coverage.json"
            coverage.write_text(json.dumps({"target_release": "SAS 9.4M9", "catalog_complete": False,
                                            "procedures": [{"name": "MEANS", "status": "subset"}]}))
            self.assertEqual(parity.verify_all(root, executable, coverage), (1, 1))
            coverage.write_text(json.dumps({"target_release": "SAS 9.4M9", "catalog_complete": False,
                                            "procedures": [{"name": "PRINT", "status": "subset"}]}))
            with self.assertRaisesRegex(parity.ParityError, "absent from coverage"):
                parity.verify_all(root, executable, coverage)
            coverage.write_text(json.dumps({"target_release": "SAS 9.4M9", "catalog_complete": False,
                                            "procedures": [{"name": "MEANS", "status": "subset"}]}))
            (committed / "reference.json").unlink()
            with self.assertRaisesRegex(parity.ParityError, "missing committed reference"):
                parity.verify_all(root, executable, coverage)
            with self.assertRaisesRegex(parity.ParityError, "already exists"):
                parity.capture(case, adapter, environment, reference)
            (case / "program.sas").write_text("proc means data=d; run;\n")
            with self.assertRaisesRegex(parity.ParityError, "stale"):
                parity.verify(case, reference, executable)

    def test_numeric_tolerance_and_missing_artifact(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            left, right = root / "left.csv", root / "right.csv"
            left.write_text("x,y\na,1.0000000000\n")
            right.write_text("x,y\na,1.0000000001\n")
            with self.assertRaises(parity.ParityError):
                parity.compare_artifact(left, right, {"kind": "csv"})
            parity.compare_artifact(left, right, {"kind": "csv", "absolute_tolerance": 1e-9})


if __name__ == "__main__":
    unittest.main()
