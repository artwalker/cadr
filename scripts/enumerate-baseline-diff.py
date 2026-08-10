#!/usr/bin/env python3
"""Goal 18 Part L: mechanically enumerate every named user-observable or
contract set that differs between two baseline commits.

Hand-written upgrade checklists have repeatedly missed classes (the
--tui-mode flag and the MarkdownSettings.mermaid key were both missed by
hand passes and caught by this enumeration).  Every class below is
derived from the two commits' git objects; the file-level
add/delete/rename diff is the catch-all.

Usage: scripts/enumerate-baseline-diff.py <from-commit> <to-commit>
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def blob(ref, path):
    result = subprocess.run(
        ["git", "-C", str(ROOT), "show", ref + ":" + path],
        capture_output=True,
        text=True,
    )
    return result.stdout if result.returncode == 0 else None


def ls(ref, prefix):
    return subprocess.run(
        ["git", "-C", str(ROOT), "ls-tree", "-r", "--name-only", ref, "--", prefix],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    ).stdout.splitlines()


def cli_flags(source):
    if not source:
        return set()
    return set(re.findall(r'"(--[a-z0-9-]+)"', source))


def slash_commands(source):
    if not source:
        return set()
    match = re.search(r"BUILTIN_SLASH_COMMANDS[^=]*=\s*\[(.*?)\n\];", source, re.DOTALL)
    if not match:
        raise SystemExit("slash-command registry shape changed")
    return set(re.findall(r'\{\s*name:\s*"([^"]+)"', match.group(1)))


def settings_keys(source):
    if not source:
        return set()
    keys = set()
    for match in re.finditer(
        r"export interface (\w*(?:Settings|Config))\s*\{(.*?)\n\}", source, re.DOTALL
    ):
        name, body = match.group(1), match.group(2)
        prefix = "" if name == "Settings" else name.removesuffix("Settings") + "."
        for key in re.findall(r"^\t(\w+)[?:]", body, re.MULTILINE):
            keys.add(prefix + key)
    return keys


def extension_events(source):
    if not source:
        return set()
    aliases = {}
    literals = {}
    extends = {}
    for match in re.finditer(
        r"export type (\w+)\s*=\s*\n((?:\s*\|\s*\w+\s*\n?)+);", source
    ):
        aliases[match.group(1)] = re.findall(r"\|\s*(\w+)", match.group(2))
    for match in re.finditer(
        r"(?:export )?interface (\w+)(?:\s+extends\s+(\w+))?\s*\{([^}]*?)\n\}",
        source,
        re.DOTALL,
    ):
        literal = re.search(r'\ttype:\s*"([a-z_]+)";', match.group(3))
        if literal:
            literals[match.group(1)] = literal.group(1)
        elif match.group(2):
            extends[match.group(1)] = match.group(2)
    leaves = set()
    pending = list(aliases.get("ExtensionEvent", []))
    while pending:
        name = pending.pop()
        if name in aliases:
            pending.extend(aliases[name])
        elif name in literals:
            leaves.add(literals[name])
        elif name in extends and extends[name] in literals:
            leaves.add(literals[extends[name]])
    return leaves


def exported_components(source):
    if not source:
        return set()
    return set(re.findall(r"export \{[^}]*?(\w*Component)[^}]*\}", source))


def keybinding_actions(*sources):
    actions = set()
    for source in sources:
        if not source:
            continue
        actions.update(re.findall(r'^\t+("?[a-z][\w.]+"?):', source, re.MULTILINE))
    return {a.strip('"') for a in actions if "." in a}


def provider_files(ref):
    return {
        Path(p).name
        for p in ls(ref, "packages/ai/src/providers")
        if p.endswith(".ts") and not p.endswith(".models.ts")
    }


def env_vars(ref):
    names = set()
    for path in ls(ref, "packages"):
        if "/src/" not in path or not path.endswith(".ts"):
            continue
        source = blob(ref, path)
        if source:
            names.update(re.findall(r"process\.env\.(?:\[)?([A-Z][A-Z0-9_]{2,})", source))
    return names


def theme_tokens(ref):
    source = blob(ref, "packages/coding-agent/src/modes/interactive/theme/theme.ts")
    if not source:
        return set()
    tokens = set()
    for match in re.finditer(
        r"export type (ThemeColor|ThemeBg)\s*=\s*\n((?:\s*\|\s*\"\w+\"\n?)+);",
        source,
    ):
        tokens.update(re.findall(r'"(\w+)"', match.group(2)))
    return tokens


def extension_type_fields(ref):
    source = blob(ref, "packages/coding-agent/src/core/extensions/types.ts")
    if not source:
        return set()
    fields = set()
    for match in re.finditer(
        r"export interface (Extension\w*|RegisteredCommand)\s*\{(.*?)\n\}",
        source,
        re.DOTALL,
    ):
        fields.update(
            match.group(1) + "." + field
            for field in re.findall(r"^\t(\w+)[?:]", match.group(2), re.MULTILINE)
        )
    return fields


def error_classes(ref):
    names = set()
    for path in ls(ref, "packages/coding-agent/src"):
        if not path.endswith(".ts"):
            continue
        source = blob(ref, path)
        if source:
            names.update(re.findall(r"export class (\w+(?:Error|Exception))", source))
    return names


def rpc_methods(source):
    if not source:
        return set()
    return set(re.findall(r'case "([a-z_]+)":', source))


def exit_codes(ref):
    codes = set()
    for path in ls(ref, "packages/coding-agent/src"):
        if not path.endswith(".ts"):
            continue
        source = blob(ref, path)
        if source:
            codes.update(re.findall(r"process\.exit\((\d+)\)", source))
    return codes


def session_format_versions(ref):
    source = blob(ref, "packages/coding-agent/src/core/session-manager.ts")
    if not source:
        return set()
    return set(re.findall(r"entry\.version = (\d+);", source))


def public_api_count(source):
    if not source:
        return 0
    return len(re.findall(r"^export ", source, re.MULTILINE))


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: enumerate-baseline-diff.py <from> <to>")
    old, new = sys.argv[1], sys.argv[2]
    ca = "packages/coding-agent"
    report = {}

    def diff(label, before, after):
        report[label] = {"added": sorted(after - before), "removed": sorted(before - after)}

    diff("cliFlags", cli_flags(blob(old, ca + "/src/cli/args.ts")),
         cli_flags(blob(new, ca + "/src/cli/args.ts")))
    diff("slashCommands", slash_commands(blob(old, ca + "/src/core/slash-commands.ts")),
         slash_commands(blob(new, ca + "/src/core/slash-commands.ts")))
    diff("settingsKeys", settings_keys(blob(old, ca + "/src/core/settings-manager.ts")),
         settings_keys(blob(new, ca + "/src/core/settings-manager.ts")))
    diff("extensionEvents", extension_events(blob(old, ca + "/src/core/extensions/types.ts")),
         extension_events(blob(new, ca + "/src/core/extensions/types.ts")))
    diff("exportedComponents", exported_components(blob(old, ca + "/src/index.ts")),
         exported_components(blob(new, ca + "/src/index.ts")))
    diff("keybindingActions",
         keybinding_actions(blob(old, ca + "/src/core/keybindings.ts"),
                            blob(old, "packages/tui/src/keybindings.ts")),
         keybinding_actions(blob(new, ca + "/src/core/keybindings.ts"),
                            blob(new, "packages/tui/src/keybindings.ts")))
    diff("providers", provider_files(old), provider_files(new))
    diff("environmentVariables", env_vars(old), env_vars(new))
    diff("themeTokens", theme_tokens(old), theme_tokens(new))
    diff("extensionTypeFields", extension_type_fields(old), extension_type_fields(new))
    diff("errorClasses", error_classes(old), error_classes(new))

    def tool_files(ref):
        return {
            Path(p).name
            for p in ls(ref, ca + "/src/core/tools")
            if p.endswith(".ts") and p != ca + "/src/core/tools/index.ts"
        }

    diff("toolFiles", tool_files(old), tool_files(new))
    diff("rpcMethods",
         rpc_methods(blob(old, ca + "/src/modes/rpc/rpc-mode.ts")),
         rpc_methods(blob(new, ca + "/src/modes/rpc/rpc-mode.ts")))
    diff("exitCodes", exit_codes(old), exit_codes(new))
    diff("sessionFormatVersions", session_format_versions(old), session_format_versions(new))
    report["publicApiExportCount"] = {
        "from": public_api_count(blob(old, ca + "/src/index.ts")),
        "to": public_api_count(blob(new, ca + "/src/index.ts")),
    }
    added = subprocess.run(
        ["git", "-C", str(ROOT), "diff", "--diff-filter=A", "--name-only", old, new, "--", "packages"],
        check=True, stdout=subprocess.PIPE, text=True,
    ).stdout.splitlines()
    removed = subprocess.run(
        ["git", "-C", str(ROOT), "diff", "--diff-filter=D", "--name-only", old, new, "--", "packages"],
        check=True, stdout=subprocess.PIPE, text=True,
    ).stdout.splitlines()
    renamed = subprocess.run(
        ["git", "-C", str(ROOT), "diff", "--diff-filter=R", "--name-status", old, new, "--", "packages"],
        check=True, stdout=subprocess.PIPE, text=True,
    ).stdout.splitlines()
    report["files"] = {
        "added": [p for p in added if p.endswith((".ts", ".tsx"))],
        "removed": [p for p in removed if p.endswith((".ts", ".tsx"))],
        "renamed": renamed,
    }
    print(json.dumps(report, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    main()
