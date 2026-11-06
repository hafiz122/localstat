#!/usr/bin/env python3
"""Capture SAS 9.4M9 reference runs and compare LocalStat procedure fixtures.

The reference command is an argv array, never a shell command. No SAS binary or
licensed output is bundled with this repository.
"""

import argparse
import csv
import hashlib
import io
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_COVERAGE = ROOT / "docs/procedures/coverage.json"
DEFAULT_RUNTIME = ROOT / "dist/LocalStat.app/Contents/Helpers/opensas"
DEFAULT_REGISTRY = ROOT / "vendor/opensas/src/proc_registry.zig"
DEFAULT_CASES = ROOT / "Tests/ProcedureParity"
DEFAULT_SOURCES = ROOT / "docs/procedures/sources.json"
STATUSES = {"unsupported", "subset", "parity_verified"}
KINDS = {"text", "csv", "json", "binary"}
NAME = re.compile(r"^[A-Z][A-Z0-9_]*$")
VERSION = re.compile(r"9\.04\.[^\s]*M9", re.IGNORECASE)
MARKER = re.compile(r"LOCALSTAT_(SYSVLONG4|SYSSCP|SYSPROD_\w+)=([^\r\n]+)")


class ParityError(ValueError):
    pass


def read_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ParityError(f"Cannot read {path}: {exc}") from exc


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def validate_coverage(document, require_complete=False):
    if document.get("target_release") != "SAS 9.4M9":
        raise ParityError("coverage target_release must be SAS 9.4M9")
    procedures = document.get("procedures")
    if not isinstance(procedures, list) or not procedures:
        raise ParityError("coverage requires a nonempty procedures list")
    names = set()
    for entry in procedures:
        if not isinstance(entry, dict):
            raise ParityError("each procedure entry must be an object")
        name = entry.get("name")
        if not isinstance(name, str) or not NAME.fullmatch(name) or name in names:
            raise ParityError(f"invalid or duplicate procedure name: {name!r}")
        names.add(name)
        if entry.get("status") not in STATUSES:
            raise ParityError(f"{name}: invalid status")
        if entry.get("status") == "parity_verified" and not entry.get("features"):
            raise ParityError(f"{name}: parity_verified requires documented features")
        if document.get("catalog_complete"):
            if not entry.get("product") or not entry.get("documentation_url") or not entry.get("features"):
                raise ParityError(f"{name}: complete catalog requires product, documentation and features")
    if require_complete and not document.get("catalog_complete"):
        raise ParityError("SAS 9.4M9 procedure catalog is not complete")
    if require_complete and any(p["status"] != "parity_verified" for p in procedures):
        raise ParityError("not every catalog procedure is parity verified")
    return names


def validate_sources(document):
    if document.get("target_release") != "SAS 9.4M9" or document.get("schema_version") != 1:
        raise ParityError("source inventory must target SAS 9.4M9 with schema_version 1")
    sources = document.get("sources")
    if not isinstance(sources, list) or not sources:
        raise ParityError("source inventory requires sources")
    by_id = {}
    for source in sources:
        if not isinstance(source, dict) or not isinstance(source.get("id"), str) or source["id"] in by_id:
            raise ParityError("source inventory has an invalid or duplicate ID")
        if (source.get("target_release") != "SAS 9.4M9" or
                not isinstance(source.get("product"), str) or not source["product"] or
                not isinstance(source.get("product_version"), str) or not source["product_version"] or
                not isinstance(source.get("url"), str) or not source["url"].startswith("https://documentation.sas.com/") or
                not isinstance(source.get("sha256"), str) or not re.fullmatch(r"[0-9a-f]{64}", source["sha256"])):
            raise ParityError(f"{source['id']}: missing verified product/version documentation source")
        if source["product"] != "Base SAS" and (
                not isinstance(source.get("reference_product_token"), str) or
                not re.fullmatch(r"[A-Z][A-Z0-9_]*", source["reference_product_token"]) or
                not isinstance(source.get("reference_status_pattern"), str) or
                not source["reference_status_pattern"]):
            raise ParityError(f"{source['id']}: missing reference product/version probe rules")
        procedures = source.get("procedures")
        if not isinstance(procedures, list) or not procedures or any(not isinstance(n, str) or not NAME.fullmatch(n) for n in procedures):
            raise ParityError(f"{source['id']}: invalid procedure names")
        if len(procedures) != len(set(procedures)):
            raise ParityError(f"{source['id']}: duplicate procedure name")
        by_id[source["id"]] = source
    return by_id


def validate_source_coverage(coverage, source_document, require_complete=False):
    sources = validate_sources(source_document)
    entries = {entry["name"]: entry for entry in coverage["procedures"]}
    sourced = set()
    for source_id, source in sources.items():
        for name in source["procedures"]:
            sourced.add(name)
            entry = entries.get(name)
            if entry is None or source_id not in entry.get("source_ids", []):
                raise ParityError(f"{source_id}: {name} missing source link in coverage")
    for name, entry in entries.items():
        linked = entry.get("source_ids", [])
        if len(linked) != len(set(linked)):
            raise ParityError(f"{name}: duplicate source link")
        for source_id in linked:
            source = sources.get(source_id)
            if source is None or name not in source["procedures"]:
                raise ParityError(f"{name}: invalid source link {source_id}")
        if linked and not any(entry.get("product") == sources[source_id]["product"] and
                              entry.get("source_url") == sources[source_id]["url"] for source_id in linked):
            raise ParityError(f"{name}: product and source URL do not match a linked source")
    unsourced = sorted(set(entries) - sourced)
    if require_complete and unsourced:
        raise ParityError(f"procedures lack a verified product/version source: {', '.join(unsourced)}")
    return sources, sourced, unsourced


def validate_reference_environment(environment, sources):
    if environment.get("target_release") != "SAS 9.4M9" or not VERSION.search(environment.get("sysvlong4", "")):
        raise ParityError("reference environment does not confirm SAS 9.4M9")
    log = environment.get("product_status_log", "")
    if not isinstance(log, str) or not log:
        raise ParityError("reference environment lacks PROC PRODUCT_STATUS output")
    tokens = environment.get("product_tokens", {})
    if not isinstance(tokens, dict):
        raise ParityError("reference product tokens are invalid")
    for source in sources.values():
        if source["product"] == "Base SAS":
            continue
        token = source["reference_product_token"]
        if tokens.get(token) != "1":
            raise ParityError(f"{source['product']} is not confirmed licensed by %SYSPROD({token})")
        if not re.search(source["reference_status_pattern"], log, re.IGNORECASE | re.DOTALL):
            raise ParityError(f"{source['product']} {source['product_version']} is not confirmed by PROC PRODUCT_STATUS")


def validate_registry_coverage(registry_path, names):
    try:
        source = Path(registry_path).read_text(encoding="utf-8")
    except OSError as exc:
        raise ParityError(f"cannot read procedure registry: {exc}") from exc
    registered = {name.upper() for name in re.findall(r'\.name\s*=\s*"([a-z0-9_]+)"', source)}
    if not registered:
        raise ParityError("procedure registry has no names")
    missing = sorted(registered - names)
    if missing:
        raise ParityError(f"dispatched procedures missing from coverage: {', '.join(missing)}")
    return registered


def validate_case(case_dir):
    case = read_json(case_dir / "case.json")
    name = case.get("procedure")
    if not isinstance(name, str) or not NAME.fullmatch(name):
        raise ParityError("case procedure must be an uppercase PROC name")
    program = case_dir / "program.sas"
    if not program.is_file():
        raise ParityError(f"missing {program}")
    comparisons = case.get("comparisons")
    if not isinstance(comparisons, list) or not comparisons:
        raise ParityError("case needs at least one explicit artifact comparison")
    for item in comparisons:
        if not isinstance(item, dict) or item.get("kind") not in KINDS:
            raise ParityError("comparison kind must be text, csv, json, or binary")
        for side in ("reference", "localstat"):
            safe_relative(item.get(side))
        for key in ("absolute_tolerance", "relative_tolerance"):
            if key in item and (not isinstance(item[key], (int, float)) or item[key] < 0 or not math.isfinite(item[key])):
                raise ParityError(f"{key} must be a finite nonnegative number")
    return case


def safe_relative(value):
    if not isinstance(value, str) or not value:
        raise ParityError("artifact path must be a nonempty relative path")
    path = Path(value)
    if path.is_absolute() or any(part in ("..", "") for part in path.parts):
        raise ParityError(f"unsafe artifact path: {value}")
    return path


def validate_adapter(adapter):
    argv = adapter.get("argv")
    if not isinstance(argv, list) or not argv or any(not isinstance(a, str) for a in argv):
        raise ParityError("adapter argv must be a nonempty array of strings")
    if not any("{program}" in a for a in argv):
        raise ParityError("adapter argv must use {program}")
    timeout = adapter.get("timeout_seconds", 120)
    if not isinstance(timeout, (int, float)) or timeout <= 0:
        raise ParityError("timeout_seconds must be positive")
    tokens = adapter.get("product_tokens", [])
    if not isinstance(tokens, list) or any(not isinstance(t, str) or not re.fullmatch(r"[A-Z][A-Z0-9_]*", t) for t in tokens):
        raise ParityError("product_tokens must be uppercase SAS product tokens")
    return argv, timeout, tokens


def stage_program(destination, source, inputs=None):
    work = destination / "work"
    work.mkdir(parents=True)
    (work / "program.sas").write_bytes(source)
    if inputs and inputs.is_dir():
        shutil.copytree(inputs, work / "inputs")
    (work / "output").mkdir()
    return work


def run_adapter(destination, adapter, source, inputs=None):
    argv, timeout, _ = validate_adapter(adapter)
    work = stage_program(destination, source, inputs)
    paths = {
        "program": work / "program.sas",
        "workdir": work,
        "log": destination / "log.txt",
        "listing": destination / "listing.txt",
        "tables": destination / "tables.json",
        "results_dir": destination / "results",
    }
    paths["results_dir"].mkdir()
    try:
        command = [part.format_map({key: str(value) for key, value in paths.items()}) for part in argv]
    except (KeyError, ValueError) as exc:
        raise ParityError(f"invalid adapter placeholder: {exc}") from exc
    try:
        result = subprocess.run(command, cwd=work, capture_output=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ParityError(f"reference/runtime command failed: {exc}") from exc
    (destination / "stdout.txt").write_bytes(result.stdout)
    (destination / "stderr.txt").write_bytes(result.stderr)
    return result.returncode


def probe(adapter_path, out):
    adapter = read_json(adapter_path)
    _, _, tokens = validate_adapter(adapter)
    lines = ["%put LOCALSTAT_SYSVLONG4=&sysvlong4;", "%put LOCALSTAT_SYSSCP=&sysscp;"]
    lines += [f"%put LOCALSTAT_SYSPROD_{token}=%sysprod({token});" for token in tokens]
    lines += ["proc product_status; run;", ""]
    with tempfile.TemporaryDirectory(prefix="localstat-sas-probe-") as temporary:
        path = Path(temporary)
        rc = run_adapter(path, adapter, "\n".join(lines).encode())
        raw = b"".join((path / item).read_bytes() for item in ("stdout.txt", "stderr.txt", "log.txt") if (path / item).exists())
        markers = {key: value.strip() for key, value in MARKER.findall(raw.decode("utf-8", errors="replace"))}
        version = markers.get("SYSVLONG4", "")
        if rc != 0 or not VERSION.search(version):
            raise ParityError(f"reference probe did not confirm SAS 9.4M9 (exit {rc}, version {version!r})")
        products = {token: markers.get(f"SYSPROD_{token}") for token in tokens}
        document = {
            "target_release": "SAS 9.4M9",
            "sysvlong4": version,
            "sysscp": markers.get("SYSSCP", ""),
            "product_tokens": products,
            "product_status_log": raw.decode("utf-8", errors="replace"),
            "adapter_sha256": digest(Path(adapter_path).read_bytes()),
        }
        out.parent.mkdir(parents=True, exist_ok=True)
        write_json(out, document)
    return document


def capture(case_dir, adapter_path, environment_path, out, replace=False):
    case = validate_case(case_dir)
    adapter = read_json(adapter_path)
    validate_adapter(adapter)
    environment = read_json(environment_path)
    if environment.get("target_release") != "SAS 9.4M9" or not VERSION.search(environment.get("sysvlong4", "")):
        raise ParityError("environment probe does not confirm SAS 9.4M9")
    if out.exists() and not replace:
        raise ParityError(f"reference already exists: {out}; pass --replace to refresh")
    with tempfile.TemporaryDirectory(prefix="localstat-sas-reference-") as temporary:
        run_dir = Path(temporary)
        source = (case_dir / "program.sas").read_bytes()
        rc = run_adapter(run_dir, adapter, source, case_dir / "inputs")
        for item in case["comparisons"]:
            rel = safe_relative(item["reference"])
            if not (run_dir / rel).is_file():
                raise ParityError(f"reference did not produce declared artifact: {rel}")
        manifest = {
            "schema_version": 1,
            "target_release": "SAS 9.4M9",
            "procedure": case["procedure"],
            "program_sha256": digest(source),
            "case_sha256": digest((case_dir / "case.json").read_bytes()),
            "environment_sha256": digest(Path(environment_path).read_bytes()),
            "exit_code": rc,
        }
        write_json(run_dir / "reference.json", manifest)
        if out.exists():
            shutil.rmtree(out)
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(run_dir, out)
    return manifest


def compare_value(expected, actual, abs_tol, rel_tol, where):
    if isinstance(expected, bool) or isinstance(actual, bool):
        if expected != actual:
            raise ParityError(f"{where}: expected {expected!r}, got {actual!r}")
    elif isinstance(expected, (int, float)) and isinstance(actual, (int, float)):
        if not math.isclose(expected, actual, abs_tol=abs_tol, rel_tol=rel_tol):
            raise ParityError(f"{where}: expected {expected!r}, got {actual!r}")
    elif isinstance(expected, list) and isinstance(actual, list):
        if len(expected) != len(actual):
            raise ParityError(f"{where}: list length differs")
        for index, (left, right) in enumerate(zip(expected, actual)):
            compare_value(left, right, abs_tol, rel_tol, f"{where}[{index}]")
    elif isinstance(expected, dict) and isinstance(actual, dict):
        if expected.keys() != actual.keys():
            raise ParityError(f"{where}: object keys differ")
        for key in expected:
            compare_value(expected[key], actual[key], abs_tol, rel_tol, f"{where}.{key}")
    elif expected != actual:
        raise ParityError(f"{where}: expected {expected!r}, got {actual!r}")


def compare_artifact(reference, localstat, comparison):
    kind = comparison["kind"]
    left, right = reference.read_bytes(), localstat.read_bytes()
    if kind == "binary":
        if left != right:
            raise ParityError(f"{reference.name}: binary content differs")
        return
    if kind == "text":
        a = left.decode("utf-8").replace("\r\n", "\n")
        b = right.decode("utf-8").replace("\r\n", "\n")
        compare_value(a, b, 0, 0, reference.name)
        return
    if kind == "json":
        a, b = json.loads(left), json.loads(right)
    else:
        a = list(csv.reader(io.StringIO(left.decode("utf-8")), strict=True))
        b = list(csv.reader(io.StringIO(right.decode("utf-8")), strict=True))
        if len(a) != len(b) or any(len(x) != len(y) for x, y in zip(a, b)):
            raise ParityError(f"{reference.name}: CSV shape differs")
        for row_index, (row_a, row_b) in enumerate(zip(a, b)):
            for col_index, (value_a, value_b) in enumerate(zip(row_a, row_b)):
                if row_index and ("absolute_tolerance" in comparison or "relative_tolerance" in comparison):
                    try:
                        value_a, value_b = float(value_a), float(value_b)
                    except ValueError:
                        pass
                compare_value(value_a, value_b, comparison.get("absolute_tolerance", 0),
                              comparison.get("relative_tolerance", 0), f"{reference.name}[{row_index},{col_index}]")
        return
    compare_value(a, b, comparison.get("absolute_tolerance", 0),
                  comparison.get("relative_tolerance", 0), reference.name)


def verify(case_dir, reference, runtime):
    case = validate_case(case_dir)
    manifest = read_json(reference / "reference.json")
    if manifest.get("schema_version") != 1 or manifest.get("procedure") != case["procedure"]:
        raise ParityError("reference manifest does not match case")
    if manifest.get("program_sha256") != digest((case_dir / "program.sas").read_bytes()):
        raise ParityError("reference program is stale")
    if manifest.get("case_sha256") != digest((case_dir / "case.json").read_bytes()):
        raise ParityError("reference comparison rules are stale")
    adapter = {"argv": [str(runtime), "{program}", "--tables-json", "{tables}"], "timeout_seconds": case.get("timeout_seconds", 120)}
    with tempfile.TemporaryDirectory(prefix="localstat-parity-") as temporary:
        actual = Path(temporary)
        rc = run_adapter(actual, adapter, (case_dir / "program.sas").read_bytes(), case_dir / "inputs")
        if rc != manifest.get("exit_code"):
            raise ParityError(f"exit code differs: SAS {manifest.get('exit_code')}, LocalStat {rc}")
        for item in case["comparisons"]:
            expected = reference / safe_relative(item["reference"])
            got = actual / safe_relative(item["localstat"])
            if not expected.is_file() or not got.is_file():
                raise ParityError(f"missing declared artifact: {expected if not expected.is_file() else got}")
            compare_artifact(expected, got, item)
    return len(case["comparisons"])


def verify_all(cases_root, runtime, coverage_path=DEFAULT_COVERAGE):
    coverage = read_json(coverage_path)
    catalog_names = validate_coverage(coverage)
    if not cases_root.exists():
        cases = []
    else:
        candidates = set(cases_root.rglob("case.json")) | set(cases_root.rglob("program.sas"))
        cases = sorted({path.parent for path in candidates
                        if "reference" not in path.relative_to(cases_root).parts})
    if not cases and coverage.get("catalog_complete"):
        raise ParityError("complete catalog has no committed parity cases")
    artifacts = 0
    for case in cases:
        case_data = validate_case(case)
        if case_data["procedure"] not in catalog_names:
            raise ParityError(f"{case.name}: procedure {case_data['procedure']} is absent from coverage")
        reference = case / "reference"
        if not (reference / "reference.json").is_file():
            raise ParityError(f"{case.name}: missing committed reference manifest")
        artifacts += verify(case, reference, runtime)
    return len(cases), artifacts


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    inventory = commands.add_parser("check-inventory")
    inventory.add_argument("--coverage", type=Path, default=DEFAULT_COVERAGE)
    inventory.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY)
    inventory.add_argument("--sources", type=Path, default=DEFAULT_SOURCES)
    inventory.add_argument("--environment", type=Path)
    inventory.add_argument("--require-complete", action="store_true")
    source_report = commands.add_parser("source-inventory")
    source_report.add_argument("--coverage", type=Path, default=DEFAULT_COVERAGE)
    source_report.add_argument("--sources", type=Path, default=DEFAULT_SOURCES)
    ref_probe = commands.add_parser("probe")
    ref_probe.add_argument("--adapter", type=Path, required=True)
    ref_probe.add_argument("--out", type=Path, required=True)
    ref_capture = commands.add_parser("capture")
    ref_capture.add_argument("--case", type=Path, required=True)
    ref_capture.add_argument("--adapter", type=Path, required=True)
    ref_capture.add_argument("--environment", type=Path, required=True)
    ref_capture.add_argument("--out", type=Path, required=True)
    ref_capture.add_argument("--replace", action="store_true")
    local_verify = commands.add_parser("verify")
    local_verify.add_argument("--case", type=Path, required=True)
    local_verify.add_argument("--reference", type=Path, required=True)
    local_verify.add_argument("--runtime", type=Path, default=DEFAULT_RUNTIME)
    all_verify = commands.add_parser("verify-all")
    all_verify.add_argument("--cases-root", type=Path, default=DEFAULT_CASES)
    all_verify.add_argument("--coverage", type=Path, default=DEFAULT_COVERAGE)
    all_verify.add_argument("--runtime", type=Path, default=DEFAULT_RUNTIME)
    args = parser.parse_args(argv)
    try:
        if args.command == "check-inventory":
            document = read_json(args.coverage)
            names = validate_coverage(document, args.require_complete)
            registered = validate_registry_coverage(args.registry, names)
            sources, sourced, unsourced = validate_source_coverage(document, read_json(args.sources), args.require_complete)
            if args.require_complete and registered != names:
                raise ParityError("complete catalog contains procedures without runtime dispatch")
            if args.require_complete:
                if args.environment is None:
                    raise ParityError("--require-complete needs a SAS 9.4M9 --environment probe")
                validate_reference_environment(read_json(args.environment), sources)
            print(f"{len(names)} entries validated; {len(sourced)} sourced; {len(registered)} dispatched; complete={document.get('catalog_complete')}")
        elif args.command == "source-inventory":
            document = read_json(args.coverage)
            validate_coverage(document)
            sources, sourced, unsourced = validate_source_coverage(document, read_json(args.sources))
            for source in sources.values():
                print(f"{source['id']}: {source['product']} {source['product_version']}, {len(source['procedures'])} names, sha256 {source['sha256'][:12]}")
            print(f"{len(sourced)} unique sourced names; {len(unsourced)} unsourced provisional names")
            if unsourced:
                print("Unsourced: " + ", ".join(unsourced))
        elif args.command == "probe":
            result = probe(args.adapter, args.out)
            print(f"Confirmed {result['sysvlong4']} ({result['sysscp']})")
        elif args.command == "capture":
            result = capture(args.case, args.adapter, args.environment, args.out, args.replace)
            print(f"Captured {result['procedure']} reference (exit {result['exit_code']})")
        elif args.command == "verify":
            count = verify(args.case, args.reference, args.runtime)
            print(f"Verified {count} declared artifact(s)")
        else:
            cases, artifacts = verify_all(args.cases_root, args.runtime, args.coverage)
            print(f"Verified {cases} parity case(s), {artifacts} declared artifact(s)")
    except (ParityError, UnicodeError, json.JSONDecodeError, csv.Error) as exc:
        parser.exit(1, f"procedure parity: {exc}\n")


if __name__ == "__main__":
    main()
