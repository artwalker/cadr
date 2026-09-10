#!/usr/bin/env python3
"""Dump named pi capabilities at the Goal 28 pin into a TSV of open rows.

Extractors come from enumerate-baseline-diff.py. git -C points at
/root/projects/pi-mono. Status is always open; this unit does not adjudicate.
"""
import argparse
import importlib.util
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PI_MONO = Path("/root/projects/pi-mono")
CA = "packages/coding-agent"

REQUIRED_CLASSES = (
    "cliFlags",
    "slashCommands",
    "exitCodes",
    "settingsKeys",
    "sessionFormatVersions",
    "rpcMethods",
    "providers",
    "errorClasses",
    "publicApiExports",
    "extensionEvents",
    "extensionTypeFields",
    "exportedComponents",
    "keybindingActions",
    "themeTokens",
    "environmentVariables",
    "toolFiles",
)

_EXPORT_BRACE = re.compile(r"export(?:\s+type)?\s*\{([^}]+)\}", re.DOTALL)
_EXPORT_DECL = re.compile(
    r"^export\s+(?:async\s+)?(?:declare\s+)?(?:type|interface|class|function|const|enum|let|var)\s+(\w+)",
    re.MULTILINE,
)


def _load_extractors():
    spec = importlib.util.spec_from_file_location(
        "enumerate_baseline_diff",
        Path(__file__).resolve().parent / "enumerate-baseline-diff.py",
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ebd = _load_extractors()


def blob(ref, path):
    result = subprocess.run(
        ["git", "-C", str(PI_MONO), "show", ref + ":" + path],
        capture_output=True,
        text=True,
    )
    return result.stdout if result.returncode == 0 else None


def ls(ref, prefix):
    return subprocess.run(
        ["git", "-C", str(PI_MONO), "ls-tree", "-r", "--name-only", ref, "--", prefix],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    ).stdout.splitlines()


ebd.blob = blob
ebd.ls = ls


def pin_sha():
    return ROOT.joinpath("BASELINE").read_text(encoding="utf-8").split()[0]


def public_api_exports(source):
    names = set()
    if not source:
        return names
    for match in _EXPORT_BRACE.finditer(source):
        body = re.sub(r"//[^\n]*", "", match.group(1))
        body = re.sub(r"/\*.*?\*/", "", body, flags=re.DOTALL)
        for part in body.split(","):
            part = part.strip()
            if not part:
                continue
            part = re.sub(r"^type\s+", "", part)
            if " as " in part:
                part = part.split(" as ")[-1].strip()
            if re.fullmatch(r"[A-Za-z_][\w]*", part):
                names.add(part)
    names.update(_EXPORT_DECL.findall(source))
    return names


def tool_files(ref):
    return {
        Path(p).name
        for p in ls(ref, CA + "/src/core/tools")
        if p.endswith(".ts") and p != CA + "/src/core/tools/index.ts"
    }


def collect(pin):
    index_path = CA + "/src/index.ts"
    args_path = CA + "/src/cli/args.ts"
    slash_path = CA + "/src/core/slash-commands.ts"
    settings_path = CA + "/src/core/settings-manager.ts"
    ext_path = CA + "/src/core/extensions/types.ts"
    rpc_path = CA + "/src/modes/rpc/rpc-mode.ts"
    key_ca = CA + "/src/core/keybindings.ts"
    key_tui = "packages/tui/src/keybindings.ts"
    theme_path = CA + "/src/modes/interactive/theme/theme.ts"
    tools_prefix = CA + "/src/core/tools"
    providers_prefix = "packages/ai/src/providers"
    packages_prefix = "packages"

    return [
        ("cliFlags", ebd.cli_flags(blob(pin, args_path)), args_path),
        ("slashCommands", ebd.slash_commands(blob(pin, slash_path)), slash_path),
        ("exitCodes", ebd.exit_codes(pin), CA + "/src"),
        ("settingsKeys", ebd.settings_keys(blob(pin, settings_path)), settings_path),
        ("sessionFormatVersions", ebd.session_format_versions(pin), CA + "/src/core/session-manager.ts"),
        ("rpcMethods", ebd.rpc_methods(blob(pin, rpc_path)), rpc_path),
        ("providers", ebd.provider_files(pin), providers_prefix),
        ("errorClasses", ebd.error_classes(pin), CA + "/src"),
        ("publicApiExports", public_api_exports(blob(pin, index_path)), index_path),
        ("extensionEvents", ebd.extension_events(blob(pin, ext_path)), ext_path),
        ("extensionTypeFields", ebd.extension_type_fields(pin), ext_path),
        ("exportedComponents", ebd.exported_components(blob(pin, index_path)), index_path),
        (
            "keybindingActions",
            ebd.keybinding_actions(blob(pin, key_ca), blob(pin, key_tui)),
            key_ca + "," + key_tui,
        ),
        ("themeTokens", ebd.theme_tokens(pin), theme_path),
        ("environmentVariables", ebd.env_vars(pin), packages_prefix),
        ("toolFiles", tool_files(pin), tools_prefix),
    ]


OVERLAY = ROOT / "docs/benchmarks/goal28-adjudications.tsv"
ALLOWED = {"open", "match", "intentional-difference", "fixed"}
TERMINAL = {"match", "intentional-difference", "fixed"}
BANNED = ("source-parity.md", "presentation-parity.md")


def load_overlay():
    if not OVERLAY.is_file():
        return {}
    rows = {}
    for i, line in enumerate(OVERLAY.read_text(encoding="utf-8").splitlines(), 1):
        if i == 1 or not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) != 5:
            raise SystemExit(f"overlay: bad row {i}")
        cls, name, status, evidence, _note = parts
        if status not in TERMINAL:
            raise SystemExit(f"overlay: bad status {status} on {cls} {name}")
        if any(token in evidence for token in BANNED):
            raise SystemExit(f"overlay: parity file is not evidence for {cls} {name}")
        proof = ROOT / evidence
        if status in {"match", "fixed"} and not proof.is_file():
            raise SystemExit(f"overlay: missing test {evidence}")
        if status == "intentional-difference" and not proof.is_file():
            raise SystemExit(f"overlay: missing adjudication {evidence}")
        rows[(cls, name)] = (status, evidence)
    return rows


def render_tsv(pin, overlay=None):
    overlay = load_overlay() if overlay is None else overlay
    lines = ["class\tname\tstatus\tevidence"]
    for cls, names, evidence in collect(pin):
        if not names:
            lines.append(f"{cls}\t__empty__\topen\tpin-empty")
            continue
        for name in sorted(names, key=str):
            status, proof = overlay.get((cls, name), ("open", evidence))
            lines.append(f"{cls}\t{name}\t{status}\t{proof}")
    return "\n".join(lines) + "\n"


def check_tsv(path, generated, pin):
    text = Path(path).read_text(encoding="utf-8")
    if text != generated:
        raise SystemExit("check: file bytes differ from regeneration")
    overlay = load_overlay()
    pin_names = set()
    for cls, names, _evidence in collect(pin):
        if not names:
            pin_names.add((cls, "__empty__"))
        else:
            pin_names.update((cls, name) for name in names)
    unknown = [key for key in overlay if key not in pin_names]
    if unknown:
        raise SystemExit("check: overlay names not on pin: " + ",".join(sorted(f"{c}:{n}" for c, n in unknown)))
    seen = set()
    open_count = 0
    for i, line in enumerate(text.splitlines()):
        if i == 0:
            if line != "class\tname\tstatus\tevidence":
                raise SystemExit("check: bad header")
            continue
        parts = line.split("\t")
        if len(parts) != 4:
            raise SystemExit(f"check: bad row {i + 1}")
        cls, name, status, evidence = parts
        if status not in ALLOWED:
            raise SystemExit(f"check: bad status {status}")
        if status in TERMINAL and (cls, name) not in overlay:
            raise SystemExit(f"check: {status} without overlay on {cls} {name}")
        if any(token in evidence for token in BANNED):
            raise SystemExit(f"check: parity file is not evidence for {cls} {name}")
        if status == "open":
            open_count += 1
        seen.add(cls)
    missing = [c for c in REQUIRED_CLASSES if c not in seen]
    if missing:
        raise SystemExit("check: missing classes: " + ",".join(missing))
    extra = seen - set(REQUIRED_CLASSES)
    if extra:
        raise SystemExit("check: unexpected classes: " + ",".join(sorted(extra)))
    return open_count


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", metavar="PATH")
    parser.add_argument("--check", metavar="PATH")
    parser.add_argument("--pin", default=None)
    args = parser.parse_args()
    pin = args.pin or pin_sha()
    tsv = render_tsv(pin)
    if not args.check:
        sys.stdout.write(tsv)
    if args.write:
        Path(args.write).write_text(tsv, encoding="utf-8")
    if args.check:
        open_count = check_tsv(args.check, tsv, pin)
        print(f"open-capability={open_count}")


if __name__ == "__main__":
    main()
