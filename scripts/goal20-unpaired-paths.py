#!/usr/bin/env python3
"""Goal 20 Part H: book which src Lisp files are paired, unpairable, or uncovered.

A file with no same-path baseline counterpart may use the single reference
"no worse than cadr before the change". That finding has to be booked here;
declaring it at the rewrite site does not discharge the evidence burden.

Files the timed thunks actually own are `paired`. Everything else that still
has a baseline counterpart is `pairable-uncovered` (Part K blocked by Part A
hard condition 2 until a pair exists). `unpairable` is the booked exception.

usage:
  python3 scripts/goal20-unpaired-paths.py --check
  python3 scripts/goal20-unpaired-paths.py --write
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

PROJECT_DIRECTORY = Path(__file__).resolve().parents[1]
INVENTORY_PATH = PROJECT_DIRECTORY / "docs/benchmarks/goal20-unpaired-paths.json"
LEDGER_PATH = PROJECT_DIRECTORY / "docs/acceptance/goal-v20-part-h.md"
START = "<!-- GOAL20_UNPAIRED_PATHS_START -->"
END = "<!-- GOAL20_UNPAIRED_PATHS_END -->"
VALID_CLASSES = frozenset(("paired", "unpairable", "pairable-uncovered"))


class GateError(Exception):
    pass


def load_inventory(path: Path) -> dict:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise GateError(f"cannot read unpaired-path inventory {path}: {error}") from error
    if not isinstance(document, dict) or document.get("schemaVersion") != 1:
        raise GateError("unpaired-path inventory schemaVersion must be 1")
    denominator = document.get("denominator")
    rules = document.get("fileRules")
    paths = document.get("unpairablePaths")
    metrics = document.get("pairedMetrics")
    if not isinstance(denominator, dict):
        raise GateError("denominator must be an object")
    files = denominator.get("files")
    lines = denominator.get("lines")
    if not isinstance(files, int) or isinstance(files, bool) or files < 0:
        raise GateError("denominator.files must be a non-negative integer")
    if not isinstance(lines, int) or isinstance(lines, bool) or lines < 0:
        raise GateError("denominator.lines must be a non-negative integer")
    if not isinstance(rules, list) or not isinstance(paths, list):
        raise GateError("fileRules and unpairablePaths must be arrays")
    if not isinstance(metrics, list) or not metrics:
        raise GateError("pairedMetrics must be a non-empty array")
    seen_ids: set[str] = set()
    for entry in paths:
        if not isinstance(entry, dict) or not isinstance(entry.get("id"), str):
            raise GateError("each unpairable path needs a string id")
        if entry["id"] in seen_ids:
            raise GateError(f"duplicate unpairable path id: {entry['id']}")
        seen_ids.add(entry["id"])
        if not isinstance(entry.get("path"), str) or not isinstance(
            entry.get("reason"), str
        ):
            raise GateError(f"unpairable path {entry['id']} needs path and reason")
    for index, rule in enumerate(rules):
        if not isinstance(rule, dict):
            raise GateError(f"fileRules[{index}] must be an object")
        prefix = rule.get("prefix")
        klass = rule.get("class")
        if not isinstance(prefix, str) or not prefix.startswith("src/"):
            raise GateError(f"fileRules[{index}].prefix must start with src/")
        if klass not in ("paired", "unpairable"):
            raise GateError(
                f"fileRules[{index}].class must be paired or unpairable "
                "(unmatched files default to pairable-uncovered)"
            )
        if klass == "unpairable":
            path_id = rule.get("pathId")
            if path_id not in seen_ids:
                raise GateError(
                    f"fileRules[{index}].pathId {path_id!r} is not in unpairablePaths"
                )
        if klass == "paired":
            listed = rule.get("metrics")
            if not isinstance(listed, list) or not listed:
                raise GateError(f"fileRules[{index}] paired rule needs metrics")
            unknown = [item for item in listed if item not in metrics]
            if unknown:
                raise GateError(
                    f"fileRules[{index}] unknown metrics: {unknown}"
                )
    return document


def lisp_files(root: Path) -> list[Path]:
    src = root / "src"
    if not src.is_dir():
        raise GateError(f"src directory is missing: {src}")
    return sorted(path for path in src.rglob("*.lisp") if path.is_file())


def newline_count(path: Path) -> int:
    return path.read_bytes().count(b"\n")


def relative_posix(root: Path, path: Path) -> str:
    return path.relative_to(root).as_posix()


def classify(relative: str, rules: list[dict]) -> dict:
    best = None
    best_len = -1
    for rule in rules:
        prefix = rule["prefix"]
        if relative == prefix or relative.startswith(prefix):
            if len(prefix) > best_len:
                best = rule
                best_len = len(prefix)
    if best is None:
        return {"class": "pairable-uncovered", "prefix": "", "metrics": [], "pathId": None}
    return {
        "class": best["class"],
        "prefix": best["prefix"],
        "metrics": list(best.get("metrics") or []),
        "pathId": best.get("pathId"),
    }


def module_key(relative: str) -> str:
    parts = relative.split("/")
    if len(parts) >= 3:
        return "/".join(parts[:3])
    return "/".join(parts[:2])


def classify_tree(root: Path, inventory: dict) -> dict:
    rules = inventory["fileRules"]
    files = lisp_files(root)
    rows = []
    totals = {klass: {"files": 0, "lines": 0} for klass in VALID_CLASSES}
    matched_prefixes: set[str] = set()
    for path in files:
        relative = relative_posix(root, path)
        lines = newline_count(path)
        decision = classify(relative, rules)
        klass = decision["class"]
        if klass not in VALID_CLASSES:
            raise GateError(f"invalid class for {relative}: {klass}")
        if decision["prefix"]:
            matched_prefixes.add(decision["prefix"])
        rows.append(
            {
                "path": relative,
                "lines": lines,
                "class": klass,
                "metrics": decision["metrics"],
                "pathId": decision["pathId"],
            }
        )
        totals[klass]["files"] += 1
        totals[klass]["lines"] += lines
    expected_prefixes = {rule["prefix"] for rule in rules}
    missing = sorted(expected_prefixes - matched_prefixes)
    if missing:
        raise GateError(
            "fileRules prefixes matched no Lisp file: " + ", ".join(missing)
        )
    total_files = len(rows)
    total_lines = sum(row["lines"] for row in rows)
    booked = inventory["denominator"]
    if total_files != booked["files"] or total_lines != booked["lines"]:
        raise GateError(
            "denominator drifted: disk "
            f"files={total_files} lines={total_lines}, inventory "
            f"files={booked['files']} lines={booked['lines']}. "
            "Book the new file in docs/benchmarks/goal20-unpaired-paths.json "
            "(new Lisp defaults to pairable-uncovered)."
        )
    return {
        "rows": rows,
        "totals": totals,
        "files": total_files,
        "lines": total_lines,
    }


def percent(part: int, whole: int) -> str:
    if whole == 0:
        return "—"
    return f"{(100.0 * part / whole):.1f}%"


def render_section(inventory: dict, classified: dict) -> str:
    totals = classified["totals"]
    lines = classified["lines"]
    paired = totals["paired"]
    unpairable = totals["unpairable"]
    uncovered = totals["pairable-uncovered"]
    advanceable = paired["lines"] + unpairable["lines"]
    rows = [
        START,
        "",
        "Produced by `scripts/goal20-unpaired-paths.py` from",
        "`docs/benchmarks/goal20-unpaired-paths.json`. Do not edit the",
        "tables by hand. `--check` fails when a new `src/**/*.lisp` file",
        "is not reflected in the booked denominator, or when a prefix",
        "matches nothing.",
        "",
        f"Denominator: **{classified['files']} files / {classified['lines']:,} lines**",
        "(same Part I lock: `src/**/*.lisp`, `wc -l`).",
        "",
        "| class | files | lines | share of lines | Part K |",
        "|---|---:|---:|---:|---|",
        f"| `paired` | {paired['files']} | {paired['lines']:,} | {percent(paired['lines'], lines)} | `no worse than baseline` is falsifiable |",
        f"| `unpairable` | {unpairable['files']} | {unpairable['lines']:,} | {percent(unpairable['lines'], lines)} | single reference vs previous cadr |",
        f"| `pairable-uncovered` | {uncovered['files']} | {uncovered['lines']:,} | {percent(uncovered['lines'], lines)} | blocked by Part A hard condition 2 |",
        "",
        f"- **Falsifiable vs baseline:** {percent(paired['lines'], lines)} of lines "
        f"({paired['files']} files). This is the share whose `no worse than baseline` claim is a measured pair.",
        f"- **K-advanceable** (paired ∪ unpairable): {percent(advanceable, lines)} of lines.",
        f"- **K-blocked** until a new pair or a booked unpairable finding: "
        f"{percent(uncovered['lines'], lines)} of lines.",
        "",
        "H does not require the paired ratios to be ≤ 1.0×; that is Part O.",
        "",
        "### 6.1 Unpairable paths",
        "",
        "These have no same-path baseline counterpart, so no same-input pair",
        "exists. Absence is a recorded decision, not an oversight. A path may",
        "be unpairable without owning every line of a file (restarts live",
        "inside otherwise-pairable tool execution).",
        "",
        "| path | why unpairable | booked files |",
        "|---|---|---|",
    ]
    files_by_path_id: dict[str, list[str]] = defaultdict(list)
    for row in classified["rows"]:
        if row["class"] == "unpairable" and row["pathId"]:
            files_by_path_id[row["pathId"]].append(row["path"])
    for entry in inventory["unpairablePaths"]:
        booked = files_by_path_id.get(entry["id"], [])
        if booked:
            files_cell = "<br>".join(f"`{name}`" for name in booked)
        else:
            files_cell = "— (path, not an exclusive file)"
        rows.append(
            f"| {entry['path']} | {entry['reason']} | {files_cell} |"
        )
    rows.extend(
        [
            "",
            "`src/cadr-agent/sqlite-storage.lisp` and `src/cadr-storage/` are",
            "**not** unpairable: the baseline ships `packages/session-backends/sqlite-node`,",
            "so SQLite is pairable and simply not covered yet.",
            "",
            "### 6.2 Currently paired owners",
            "",
            "A file is `paired` when a live Part H or Goal 11 thunk names it as",
            "production work, not merely as a transitive callee. Callees that",
            "are not named stay `pairable-uncovered`.",
            "",
            "| file | lines | metrics |",
            "|---|---:|---|",
        ]
    )
    paired_rows = [row for row in classified["rows"] if row["class"] == "paired"]
    paired_rows.sort(key=lambda row: row["path"])
    for row in paired_rows:
        metrics = ", ".join(f"`{item}`" for item in row["metrics"])
        rows.append(f"| `{row['path']}` | {row['lines']:,} | {metrics} |")
    rows.extend(
        [
            "",
            "### 6.3 Pairable, not yet paired",
            "",
            "Grouped by directory. Every line here still has a baseline",
            "counterpart; large-scale Lisp-ification is blocked until a pair",
            "is added or the path is booked unpairable above.",
            "",
            "| module | files | lines |",
            "|---|---:|---:|",
        ]
    )
    grouped: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    for row in classified["rows"]:
        if row["class"] != "pairable-uncovered":
            continue
        key = module_key(row["path"])
        grouped[key][0] += 1
        grouped[key][1] += row["lines"]
    for key, counts in sorted(grouped.items(), key=lambda item: (-item[1][1], item[0])):
        rows.append(f"| `{key}` | {counts[0]} | {counts[1]:,} |")
    rows.extend(["", END, ""])
    return "\n".join(rows)


def replace_marked_section(markdown: str, section: str) -> str:
    if START in markdown and END in markdown:
        before, rest = markdown.split(START, 1)
        _, after = rest.split(END, 1)
        return before.rstrip() + "\n\n" + section + after.lstrip("\n")
    raise GateError(
        f"{LEDGER_PATH} is missing {START} / {END}; refuse to append blindly"
    )


def write_ledger(root: Path, inventory: dict, classified: dict) -> None:
    path = root / LEDGER_PATH.relative_to(PROJECT_DIRECTORY)
    markdown = path.read_text(encoding="utf-8")
    path.write_text(
        replace_marked_section(markdown, render_section(inventory, classified)),
        encoding="utf-8",
    )


def check_ledger(root: Path, inventory: dict, classified: dict) -> None:
    path = root / LEDGER_PATH.relative_to(PROJECT_DIRECTORY)
    markdown = path.read_text(encoding="utf-8")
    expected = render_section(inventory, classified)
    if START not in markdown or END not in markdown:
        raise GateError(f"{path} is missing the unpaired-path markers")
    current = START + markdown.split(START, 1)[1].split(END, 1)[0] + END + "\n"
    if current != expected:
        raise GateError(
            f"{path} unpaired-path section is stale; run "
            "python3 scripts/goal20-unpaired-paths.py --write"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=PROJECT_DIRECTORY)
    parser.add_argument(
        "--inventory",
        type=Path,
        default=INVENTORY_PATH,
    )
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    inventory = load_inventory(args.inventory)
    try:
        classified = classify_tree(root, inventory)
        if args.write:
            write_ledger(root, inventory, classified)
        if args.check or not args.write:
            check_ledger(root, inventory, classified)
    except GateError as error:
        print(f"goal20 unpaired paths: {error}", file=sys.stderr)
        return 1
    totals = classified["totals"]
    print(
        "goal20 unpaired paths: "
        f"files={classified['files']} lines={classified['lines']} "
        f"paired={totals['paired']['lines']} "
        f"unpairable={totals['unpairable']['lines']} "
        f"uncovered={totals['pairable-uncovered']['lines']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
