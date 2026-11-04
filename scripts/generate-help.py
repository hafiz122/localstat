#!/usr/bin/env python3
"""Regenerate bundled compatibility and reference pages from pinned sources."""
import argparse
import html
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
HELP = ROOT / "Sources/LocalStat/Resources/Help"


def page(title, body):
    return ('<!doctype html><html lang="en"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width"><title>' + html.escape(title)
            + '</title><link rel="stylesheet" href="style.css"></head><body>\n' + body + '\n</body></html>\n')


def inline(text):
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", html.escape(text.replace("\u2014", ":")))


def compatibility():
    lines = (ROOT / "docs/COMPATIBILITY.md").read_text().splitlines()
    parts, paragraph, code, table = [], [], None, False
    def flush():
        if paragraph:
            parts.append("<p>" + inline(" ".join(paragraph)) + "</p>")
            paragraph.clear()
    for line in lines:
        if line.startswith("```"):
            flush()
            if code is None:
                code = []
            else:
                parts.append("<pre><code>" + html.escape("\n".join(code)) + "</code></pre>")
                code = None
        elif code is not None:
            code.append(line)
        elif line.startswith("|"):
            flush()
            if not table:
                parts.append("<table>"); table = True
            if re.fullmatch(r"[| :\-]+", line):
                continue
            tag = "th" if "Capability" in line and "Status" in line else "td"
            parts.append("<tr>" + "".join(f"<{tag}>{inline(cell.strip())}</{tag}>" for cell in line.strip("|").split("|")) + "</tr>")
        else:
            if table:
                parts.append("</table>"); table = False
            if not line:
                flush()
            elif line.startswith("#"):
                flush(); level = len(line) - len(line.lstrip("#"))
                parts.append(f"<h{level}>" + inline(line[level:].strip()) + f"</h{level}>")
            else:
                paragraph.append(line)
    flush()
    if table: parts.append("</table>")
    return page("Compatibility and limitations", "\n".join(parts))


def reference():
    tracker = (ROOT / "vendor/opensas/docs/sas-functions.md").read_text()
    entries = {}
    partial = {
        "CALL EXECUTE": "Partial: expands its argument at call time and queues generated statements. Some deferred macro-quoting forms are unsupported.",
        "CALL IS8601_CONVERT": "Partial: only two datetimes to duration seconds (dt/dt to du). Other conversions are unsupported.",
        "CEXIST": "Partial: catalog storage is unsupported; returns 0.",
    }
    for mark, name, note in re.findall(r"^- \[([x~ ])\] ([A-Z][A-Z0-9_]*(?: [A-Z][A-Z0-9_]*)?)(.*)$", tracker, re.M):
        if name in partial:
            status = partial[name]
        elif mark == "x":
            status = "Implemented subset."
        else:
            reason = re.search(r"N/A: (.*)", note)
            reason = reason.group(1).rstrip(")") if reason else "not implemented"
            if name.startswith(("VARRAY", "VINARRAY")): reason = "array-name lookup is unsupported"
            reason = reason.replace("\u2014", ":").split(";", 1)[0]
            status = "Unavailable: " + reason + "."
        entries[name] = status
    for filename in ["functions.zig", "eval.zig", "charfns.zig", "numfns.zig", "datefns.zig", "finfns.zig", "statfns.zig"]:
        source = (ROOT / "vendor/opensas/src" / filename).read_text()
        registry_source = source.split('\ntest "', 1)[0]
        names = re.findall(r'eqi\(name, "([a-z][a-z0-9_]*)"\)', source) + re.findall(r'\.name = "([a-z][a-z0-9_]*)"', registry_source)
        for name in names:
            entries.setdefault(name.upper(), "Runtime name or alias; supported arguments only.")
    executor = (ROOT / "vendor/opensas/src/exec.zig").read_text()
    call_body = executor[executor.index('if (eqi(c.name, "symput")'):executor.index('if (eqi(c.name, "is8601_convert"))')]
    for name in re.findall(r'eqi\(c.name, "([a-z][a-z0-9_]*)"\)', call_body):
        entries.setdefault("CALL " + name.upper(), "Runtime CALL routine or alias; supported argument forms only.")
    main = (ROOT / "vendor/opensas/src/main.zig").read_text()
    dispatch = main[main.index('if (eqi(proc, "sort"))'):main.index('failLoud("PROC {s} is not supported"')]
    procs = sorted(set(re.findall(r'eqi\(proc, "([a-z]+)"\)', dispatch)))
    body = ['<h1>Procedure and function index</h1>',
            '<p>This index covers the pinned local runtime. An implemented name is a supported subset, not a claim of complete SAS equivalence. Unavailable names are included so searches explain the boundary. The guide provides worked examples; this index does not reproduce the full SAS function dictionary.</p>',
            '<p>SUMMARY shares the MEANS family. Additional runtime names and aliases are included below. The DATA-step SYSGET function is unavailable; the separate macro directive %SYSGET can read inherited environment variables. See <a href="localstat-help:compatibility">Compatibility and limitations</a>.</p>',
            '<h2>Procedures</h2><table><tr><th>Name</th><th>Support</th></tr>']
    for name in procs:
        note = "Implemented subset; procedure options vary."
        if name == "reg": note = "Bounded numeric ordinary-least-squares subset; see the regression guide."
        elif name == "printto": note = "Accepted but inert: does not redirect output."
        elif name == "summary": note = "MEANS-family procedure with its own output defaults."
        body.append(f"<tr><td>PROC {name.upper()}</td><td>{note}</td></tr>")
    body += ['</table><h2>Functions and CALL routines</h2>', '<table><tr><th>Name</th><th>Support</th></tr>']
    for name, status in sorted(entries.items()):
        body.append(f'<tr id="{name.lower().replace(" ", "-")}"><td><code>{html.escape(name)}</code></td><td>{html.escape(status)}</td></tr>')
    body.append("</table>")
    return page("Procedure and function index", "\n".join(body)), {"procedures": procs, "functions": sorted(entries)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    ref, inventory = reference()
    files = {"compatibility.html": compatibility(), "reference.html": ref,
             "reference-inventory.json": json.dumps(inventory, indent=2) + "\n"}
    for name, content in files.items():
        destination = HELP / name
        if args.check:
            if not destination.exists() or destination.read_text() != content:
                raise SystemExit(f"Stale Help resource: {name}. Run python3 scripts/generate-help.py")
        else:
            destination.write_text(content)


if __name__ == "__main__":
    main()
