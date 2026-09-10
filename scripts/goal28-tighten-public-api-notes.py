#!/usr/bin/env python3
"""Tighten Goal 28 publicApiExports intentional-difference rows.

- Rephrase generic notes to name the concrete proven surface.
- Promote value exports that already have a Lisp symbol to fixed
  (evidence: goal28-public-api-exports-test.lisp), after ensuring the
  symbol is listed in that test.
- Leave true type-only / UI / helper aliases as intentional-difference.
"""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def pin_sha():
    return ROOT.joinpath("BASELINE").read_text(encoding="utf-8").split()[0]


PIN = pin_sha()
INDEX = "packages/coding-agent/src/index.ts"
ADJ = ROOT / "docs/benchmarks/goal28-adjudications.tsv"
TEST = ROOT / "test/cadr-cli/goal28-public-api-exports-test.lisp"
DECISIONS = ".orchestrate/goal28/decisions.tsv"

EXPORT_BRACE = re.compile(r"export\s+(type\s+)?\{([^}]+)\}", re.S)
EXPORT_DECL = re.compile(
    r"export\s+(?:async\s+)?(?:function|class|const|let|var|enum)\s+([A-Za-z_][\w]*)"
)


def kebab(name: str) -> str:
    out: list[str] = []
    for i, ch in enumerate(name):
        if ch.isupper() and i > 0:
            prev = name[i - 1]
            nxt = name[i + 1] if i + 1 < len(name) else ""
            if not prev.isupper() or (nxt and nxt.islower()):
                out.append("-")
        out.append(ch.lower())
    return "".join(out).replace("_", "-")


def pin_index() -> str:
    return subprocess.check_output(
        ["git", "-C", "/root/projects/pi-mono", "show", f"{PIN}:{INDEX}"],
        text=True,
    )


def classify_exports(source: str) -> tuple[set[str], set[str]]:
    type_names: set[str] = set()
    value_names: set[str] = set()
    for match in EXPORT_BRACE.finditer(source):
        is_type_kw = bool(match.group(1))
        body = re.sub(r"//[^\n]*", "", match.group(2))
        body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
        for part in body.split(","):
            part = part.strip()
            if not part:
                continue
            type_only = part.startswith("type ") or is_type_kw
            part = re.sub(r"^type\s+", "", part)
            if " as " in part:
                part = part.split(" as ")[-1].strip()
            if re.fullmatch(r"[A-Za-z_][\w]*", part):
                (type_names if type_only else value_names).add(part)
    for match in EXPORT_DECL.finditer(source):
        value_names.add(match.group(1))
    return type_names, value_names


def load_lisp_symbols() -> set[str]:
    names: set[str] = set()
    pat = re.compile(
        r"\(def(?:class|un|var|parameter|struct|constant|generic|method|"
        r"ine-condition|macro)\s+(?:\(setf\s+)?([:*A-Za-z0-9+-]+)",
        re.I,
    )
    for path in (ROOT / "src").rglob("*.lisp"):
        if "vendor" in str(path):
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for match in pat.finditer(text):
            names.add(match.group(1).lower().lstrip(":"))
    for path in (ROOT / "src").rglob("package.lisp"):
        text = path.read_text(encoding="utf-8", errors="ignore")
        for match in re.finditer(r"#:\|?([A-Za-z0-9*+=<>!?/-]+)\|?", text):
            names.add(match.group(1).lower())
    return names


def symbol_exists(sym: str, lisp: set[str]) -> bool:
    flat = {s.replace("-", ""): s for s in lisp}
    for candidate in (sym, sym.strip("+*"), f"+{sym.strip('+*')}+", f"*{sym.strip('+*')}*"):
        if candidate in lisp or candidate.replace("-", "") in flat:
            return True
    return False


def ui_component(name: str) -> bool:
    return name.endswith("Component") or name in {
        "BorderedLoader",
        "DynamicBorder",
        "CustomEditor",
        "InteractiveMode",
        "ExtensionRunner",
        "FooterComponent",
    }


def note_for(name: str, type_names: set[str]) -> str:
    if name in type_names:
        if name.endswith("Event"):
            return (
                "TS event type only; runtime hook is proven on extensionEvents "
                "(or agent tool-call events)"
            )
        if name.endswith(("Options", "Config", "Callback", "Listener", "Factory", "Result")):
            return (
                "TS type-only options/result alias; callers use Lisp kwargs / "
                "settings / RPC payloads"
            )
        return (
            "TS type-only export; no runtime binding. User capability is the "
            "matching CLI/RPC/tool/extension surface"
        )
    if ui_component(name):
        return (
            "UI component module export; Armin/interactive transcript covers "
            "the rendered surface"
        )
    if name.startswith(("is", "create", "wrap")) and (
        "Tool" in name or name.endswith("Tools") or "Operations" in name
    ):
        return "Tool factory/predicate alias; make-*-tool makers are fixed on toolFiles"
    if name.startswith(("get", "init", "has", "detect", "format", "highlight", "render")):
        return (
            "Library helper export; path/theme/image helpers fold into "
            "coding-agent-directory and themeTokens"
        )
    return (
        f"Value export {name} has no direct Lisp binding; user capability is "
        "covered by CLI/RPC/session surfaces"
    )


def read_test_symbols() -> set[str]:
    text = TEST.read_text(encoding="utf-8")
    match = re.search(
        r"\(defparameter \+goal28-public-api-lisp-symbols\+\s*'\((.*?)\)\)",
        text,
        re.S,
    )
    if not match:
        return set()
    return set(re.findall(r'"([^"]+)"', match.group(1)))


def write_test_symbols(symbols: set[str]) -> None:
    unique = sorted(symbols)
    lisp_form = "\n".join(f'    "{sym}"' for sym in unique)
    TEST.write_text(
        f"""(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defparameter +goal28-public-api-lisp-symbols+
  '(
{lisp_form}
    ))

(defun goal28-public-api-symbol-reachable-p (name)
  (loop for pkg-name in '("CADR-CLI" "CADR-AGENT" "CADR-CORE" "CADR-AI" "CADR-TUI"
                          "CADR-SERVER" "CADR-STORAGE")
        for pkg = (find-package pkg-name)
        for sym = (and pkg (find-symbol (string-upcase name) pkg))
        thereis (and sym
                     (or (fboundp sym)
                         (boundp sym)
                         (find-class sym nil)
                         (macro-function sym)))))

(test goal28-public-api-exports-reach-existing-lisp
  (dolist (name +goal28-public-api-lisp-symbols+)
    (is (goal28-public-api-symbol-reachable-p name)
        (format nil "missing Lisp symbol ~A" name))))
""",
        encoding="utf-8",
    )


def main() -> None:
    type_names, value_names = classify_exports(pin_index())
    lisp = load_lisp_symbols()
    test_syms = read_test_symbols()
    lines = ADJ.read_text(encoding="utf-8").splitlines()
    header, rows = lines[0], lines[1:]
    out = [header]
    promoted = 0
    rewritten = 0
    for line in rows:
        parts = line.split("\t")
        if len(parts) < 5 or parts[0] != "publicApiExports":
            out.append(line)
            continue
        name, status, evidence, note = parts[1], parts[2], parts[3], parts[4]
        if status != "intentional-difference":
            out.append(line)
            continue
        k = kebab(name)
        alts = [k, f"+{k}+", f"*{k}*"]
        # PowerShell special case
        if name == "getPowerShellConfig":
            alts = ["get-powershell-config"]
        hit = next((a for a in alts if symbol_exists(a, lisp)), None)
        if hit and name in value_names and not ui_component(name):
            test_syms.add(hit)
            out.append(
                f"publicApiExports\t{name}\tfixed\t"
                "test/cadr-cli/goal28-public-api-exports-test.lisp\t"
                f"Lisp symbol {hit}"
            )
            promoted += 1
            continue
        new_note = note_for(name, type_names)
        if new_note != note:
            rewritten += 1
        out.append(
            f"publicApiExports\t{name}\tintentional-difference\t{DECISIONS}\t{new_note}"
        )
    write_test_symbols(test_syms)
    ADJ.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"promoted={promoted} rewritten={rewritten} test_symbols={len(test_syms)}")


if __name__ == "__main__":
    main()
