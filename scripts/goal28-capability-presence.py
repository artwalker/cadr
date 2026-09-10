#!/usr/bin/env python3
"""Presence table for Goal 28 slash commands, CLI flags, RPC methods, and tools.

Presence is a registry or parser hit in the cadr tree, not a behavior proof.
Status stays open. match is forbidden.
"""
import argparse
import csv
import io
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PI_MONO = Path("/root/projects/pi-mono")
PIN = "d981de1229ef899957bbe968bc8dcda02a21f477"
INVENTORY = ROOT / "docs/benchmarks/goal28-capabilities.tsv"
PRESENCE_CLASSES = (
    "slashCommands",
    "cliFlags",
    "rpcMethods",
    "toolFiles",
)
ALLOWED_PRESENCE = ("name-present", "missing", "extractor-noise")
HEADER = "class\tname\tpresence\tstatus\tnote"

SLASH_FILE = "src/cadr-cli/interactive/autocomplete.lisp"
CLI_FILE = "src/cadr-cli/arguments.lisp"
RPC_FILE = "src/cadr-cli/modes/rpc/commands.lisp"
TOOL_FILE = "src/cadr-cli/bootstrap/tools.lisp"
PI_TOOL_INDEX = "packages/coding-agent/src/core/tools/index.ts"


def read_text(path):
    return Path(path).read_text(encoding="utf-8")


def pin_blob(path):
    result = subprocess.run(
        ["git", "-C", str(PI_MONO), "show", PIN + ":" + path],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout


def inventory_rows(path):
    rows = []
    with Path(path).open(encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle, delimiter="\t")
        header = next(reader)
        if header[:3] != ["class", "name", "status"]:
            raise SystemExit("inventory: unexpected header")
        for parts in reader:
            if len(parts) < 3:
                raise SystemExit("inventory: short row")
            cls, name, status = parts[0], parts[1], parts[2]
            if cls in PRESENCE_CLASSES:
                rows.append((cls, name, status))
    return rows


def cadr_slash_commands():
    source = read_text(ROOT / SLASH_FILE)
    start = source.find(
        "(defparameter +tui-autocomplete-command-specifications+"
    )
    if start < 0:
        raise SystemExit("slash: registry missing")
    end = source.find("(defun ", start)
    names = set(re.findall(r'\("([a-z][a-z0-9-]*)"', source[start:end]))
    if not names:
        raise SystemExit("slash: registry empty")
    return names


def cadr_cli_flags():
    source = read_text(ROOT / CLI_FILE)
    start = source.find("(defparameter +cli-usage-prefix+")
    end = source.find("(defparameter +cli-usage-suffix+")
    if start < 0 or end < 0 or end <= start:
        raise SystemExit("cli: usage strings missing")
    chunk = source[start:end]
    options = chunk.split("Options:", 1)
    if len(options) != 2:
        raise SystemExit("cli: Options section missing")
    body = options[1].split("Extensions can register", 1)[0]
    return set(re.findall(r"--[a-z0-9-]+", body))


def cadr_rpc_methods():
    source = read_text(ROOT / RPC_FILE)
    start = source.find("(defun rpc-handle-command")
    if start < 0:
        raise SystemExit("rpc: handler missing")
    return set(re.findall(r'\(string=\s+type\s+"([^"]+)"\)', source[start:]))


def cadr_tool_names():
    source = read_text(ROOT / TOOL_FILE)
    match = re.search(
        r"\(defparameter \+builtin-coding-tool-names\+\s+'?\((.*?)\)\)",
        source,
        re.DOTALL,
    )
    if not match:
        raise SystemExit("tools: +builtin-coding-tool-names+ missing")
    names = set(re.findall(r'"([^"]+)"', match.group(1)))
    if not names:
        raise SystemExit("tools: +builtin-coding-tool-names+ empty")
    return names


def pi_tool_names():
    source = pin_blob(PI_TOOL_INDEX)
    match = re.search(
        r"export const allToolNames: Set<ToolName> = new Set\(\[(.*?)\]\)",
        source,
        re.DOTALL,
    )
    if not match:
        raise SystemExit("pin tools: allToolNames missing")
    return set(re.findall(r'"([^"]+)"', match.group(1)))


def tool_stem(filename):
    if not filename.endswith(".ts"):
        return filename
    return filename[: -len(".ts")]


def classify(cls, name, slash, flags, rpc, cadr_tools, pi_tools):
    if cls == "slashCommands":
        if name in slash:
            return (
                "name-present",
                f"registry +tui-autocomplete-command-specifications+ in {SLASH_FILE}",
            )
        return ("missing", f"not in +tui-autocomplete-command-specifications+ ({SLASH_FILE})")
    if cls == "cliFlags":
        if name == "---":
            return (
                "extractor-noise",
                "flag regex in enumerate-baseline-diff.py matched --- skip in arguments.lisp",
            )
        if name in flags:
            return (
                "name-present",
                f"+cli-usage-prefix+ Options in {CLI_FILE}",
            )
        return ("missing", f"not in +cli-usage-prefix+ Options ({CLI_FILE})")
    if cls == "rpcMethods":
        if name in rpc:
            return (
                "name-present",
                f"rpc-handle-command type dispatch in {RPC_FILE}",
            )
        return ("missing", f"not in rpc-handle-command ({RPC_FILE})")
    if cls == "toolFiles":
        stem = tool_stem(name)
        if stem not in pi_tools:
            return (
                "extractor-noise",
                "not user-invocable; pi allToolNames in "
                + PI_TOOL_INDEX
                + f" at {PIN}; cadr +builtin-coding-tool-names+ in {TOOL_FILE}",
            )
        if stem in cadr_tools:
            return (
                "name-present",
                f"+builtin-coding-tool-names+ {stem!r} in {TOOL_FILE}",
            )
        return (
            "missing",
            f"pi allToolNames has {stem!r}; not in +builtin-coding-tool-names+ ({TOOL_FILE})",
        )
    raise SystemExit(f"unknown class {cls}")


def render_tsv(inventory_path):
    slash = cadr_slash_commands()
    flags = cadr_cli_flags()
    rpc = cadr_rpc_methods()
    cadr_tools = cadr_tool_names()
    pi_tools = pi_tool_names()
    lines = [HEADER]
    for cls, name, _status in inventory_rows(inventory_path):
        presence, note = classify(
            cls, name, slash, flags, rpc, cadr_tools, pi_tools
        )
        lines.append(f"{cls}\t{name}\t{presence}\topen\t{note}")
    return "\n".join(lines) + "\n"


def parse_presence(path):
    text = Path(path).read_text(encoding="utf-8")
    rows = []
    for i, line in enumerate(text.splitlines()):
        if i == 0:
            if line != HEADER:
                raise SystemExit("check: bad header")
            continue
        parts = line.split("\t")
        if len(parts) != 5:
            raise SystemExit(f"check: bad row {i + 1}")
        rows.append(tuple(parts))
    return rows


def check_tsv(path, generated):
    expected = list(csv.reader(io.StringIO(generated), delimiter="\t"))
    found = list(csv.reader(io.StringIO(Path(path).read_text(encoding="utf-8")), delimiter="\t"))
    if found != expected:
        raise SystemExit("check: file bytes differ from regeneration")
    inventory = inventory_rows(INVENTORY)
    wanted = [(cls, name) for cls, name, _status in inventory]
    got = []
    dash_ok = False
    for i, row in enumerate(found):
        if i == 0:
            continue
        cls, name, presence, status, _note = row
        if cls not in PRESENCE_CLASSES:
            raise SystemExit(f"check: unexpected class {cls}")
        if status == "match":
            raise SystemExit(f"check: match status on {cls}\t{name}")
        if status != "open":
            raise SystemExit(f"check: status must stay open on {cls}\t{name}")
        if presence not in ALLOWED_PRESENCE:
            raise SystemExit(f"check: bad presence {presence}")
        if name == "---":
            if presence != "extractor-noise":
                raise SystemExit("check: --- must be extractor-noise")
            dash_ok = True
        got.append((cls, name))
    if got != wanted:
        raise SystemExit("check: inventory rows for the four classes are not 1:1")
    if ("cliFlags", "---") in wanted and not dash_ok:
        raise SystemExit("check: --- row missing")


def print_counts(tsv):
    counts = {cls: Counter() for cls in PRESENCE_CLASSES}
    for i, line in enumerate(tsv.splitlines()):
        if i == 0:
            continue
        cls, _name, presence, _status, _note = line.split("\t")
        counts[cls][presence] += 1
    for cls in PRESENCE_CLASSES:
        c = counts[cls]
        sys.stderr.write(
            f"{cls}\tname-present={c['name-present']}\t"
            f"missing={c['missing']}\textractor-noise={c['extractor-noise']}\n"
        )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", metavar="PATH")
    parser.add_argument("--check", metavar="PATH")
    parser.add_argument("--inventory", default=str(INVENTORY))
    args = parser.parse_args()
    tsv = render_tsv(args.inventory)
    sys.stdout.write(tsv)
    if args.write:
        Path(args.write).write_text(tsv, encoding="utf-8")
    if args.check:
        check_tsv(args.check, tsv)
    print_counts(tsv)


if __name__ == "__main__":
    main()
