#!/usr/bin/env python3
"""Presence table for remaining Goal 28 classes except publicApiExports.

Presence is a registry, parser, or declared-constant hit in cadr.
Status stays open. match is forbidden.
"""
import argparse
import csv
import io
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INVENTORY = ROOT / "docs/benchmarks/goal28-capabilities.tsv"
PRESENCE_CLASSES = (
    "exitCodes",
    "settingsKeys",
    "sessionFormatVersions",
    "providers",
    "errorClasses",
    "extensionEvents",
    "extensionTypeFields",
    "exportedComponents",
    "keybindingActions",
    "themeTokens",
    "environmentVariables",
)
FORBIDDEN_CLASSES = ("publicApiExports",)
ALLOWED_PRESENCE = ("name-present", "missing", "extractor-noise")
HEADER = "class\tname\tpresence\tstatus\tnote"

EXIT_FILE = "src/cadr-cli/bootstrap/commands.lisp"
EXIT_MAIN = "src/cadr-cli/bootstrap/main.lisp"
EXIT_SESSIONS = "src/cadr-cli/bootstrap/sessions.lisp"
SETTINGS_BOOTSTRAP = "src/cadr-cli/bootstrap/settings.lisp"
SETTINGS_MANAGER = "src/cadr-cli/settings/manager.lisp"
SETTINGS_SDK = "src/cadr-cli/sdk/settings-service.lisp"
SESSION_CODEC = "src/cadr-agent/session/codec.lisp"
SESSION_JOURNAL = "src/cadr-agent/session/journal.lisp"
SESSION_MIGRATION = "src/cadr-agent/session/migration.lisp"
PROVIDER_DEFS = "src/cadr-ai/providers/definitions.lisp"
FAUX_PROVIDER = "src/cadr-ai/runtime/faux-provider.lisp"
ERROR_CLI = "src/cadr-cli/models/credential-print.lisp"
ERROR_AGENT = "src/cadr-agent/conditions.lisp"
HOOK_EVENTS = "src/cadr-agent/extensions/registration.lisp"
EXT_API = "src/cadr-agent/extensions/api.lisp"
EXT_CONTEXT = "src/cadr-agent/extensions/context.lisp"
EXT_BUNDLE = "src/cadr-agent/extensions/registration.lisp"
ARMIN = "src/cadr-cli/interactive/components/armin.lisp"
ARMIN_PKG = "src/cadr-cli/package.lisp"
KEY_TUI = "src/cadr-tui/keybindings.lisp"
KEY_SESSIONS = "src/cadr-cli/interactive/selectors/sessions.lisp"
KEY_MODELS = "src/cadr-cli/interactive/selectors/models.lisp"
KEY_THINKING = "src/cadr-cli/interactive/selectors/thinking.lisp"
KEY_TREE = "src/cadr-cli/interactive/selectors/tree.lisp"
THEME_JSON = "src/cadr-cli/interactive/themes.lisp"

PROVIDER_HELPER_STEMS = {
    "all",
    "register-builtins",
    "data-json.d",
    "cloudflare-auth",
    "cloudflare-stream",
    "radius-config",
}

SETTINGS_SCAN_FILES = (
    SETTINGS_BOOTSTRAP,
    SETTINGS_MANAGER,
    SETTINGS_SDK,
    "src/cadr-cli/sdk/cache-version.lisp",
    "src/cadr-cli/sdk/agent-session.lisp",
    "src/cadr-cli/packages/settings.lisp",
    "src/cadr-cli/bootstrap/commands.lisp",
    "src/cadr-cli/modes/rpc/commands.lisp",
    "src/cadr-agent/proxy.lisp",
)


def read_text(path):
    return Path(path).read_text(encoding="utf-8")


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
            if cls in FORBIDDEN_CLASSES:
                continue
            if cls in PRESENCE_CLASSES:
                rows.append((cls, name, status))
    return rows


def kebab_to_camel(name):
    text = name
    boolean_p = text.endswith("-p")
    if boolean_p:
        text = text[:-2]
    parts = text.split("-")
    camel = parts[0] + "".join(part[:1].upper() + part[1:] for part in parts[1:])
    if boolean_p and camel == "hasUi":
        return "hasUI"
    return camel


def lisp_type_name(condition):
    parts = condition.split("-")
    return "".join(part[:1].upper() + part[1:] for part in parts)


def cadr_exit_codes():
    found = {}
    commands = read_text(ROOT / EXIT_FILE)
    for match in re.finditer(r"exit-on-signal\s+(\d+)", commands):
        found[match.group(1)] = EXIT_FILE
    main = read_text(ROOT / EXIT_MAIN)
    if re.search(r"return-from main 1", main) or re.search(
        r"\(cadr-ai:cadr-error[\s\S]*?\n\s+1\)", main
    ):
        found["1"] = EXIT_MAIN
    if "cli-session-abort-status" in main:
        found.setdefault("1", EXIT_MAIN)
    sessions = read_text(ROOT / EXIT_SESSIONS)
    if re.search(r":initform 0", sessions) or re.search(r":status 0", sessions):
        found["0"] = EXIT_SESSIONS
    if "1)" in main and "cadr-ai:cadr-error" in main:
        found["1"] = EXIT_MAIN
    return found


def cadr_settings_keys():
    top = {}
    nested = {}

    def add_top(key, file):
        if key:
            top[key] = file

    def add_nested(parent, child, file):
        if parent and child:
            nested[parent + "." + child] = file
            add_top(parent, file)

    for rel in SETTINGS_SCAN_FILES:
        path = ROOT / rel
        if not path.is_file():
            continue
        source = read_text(path)
        for key in re.findall(
            r'\(settings-value\s+\S+\s+"([^"]+)"', source
        ):
            add_top(key, rel)
        for key in re.findall(
            r'\(sdk-settings-value\s+\S+\s+"([^"]+)"', source
        ):
            add_top(key, rel)
        for key in re.findall(
            r'\(settings-set\s+\S+\s+"([^"]+)"', source
        ):
            add_top(key, rel)
        for key in re.findall(
            r'\(settings-choice-value\s+\S+\s+"([^"]+)"', source
        ):
            add_top(key, rel)
        for parent, child in re.findall(
            r'\(settings-nested-value\s+\S+\s+"([^"]+)"\s+"([^"]+)"',
            source,
        ):
            add_nested(parent, child, rel)
        for parent, child in re.findall(
            r'\(settings-set-nested\s+\S+\s+"([^"]+)"\s+"([^"]+)"',
            source,
        ):
            add_nested(parent, child, rel)
        for parent, child in re.findall(
            r'\(settings-boolean-value\s+\S+\s+"([^"]+)"\s+\S+\s+"([^"]+)"',
            source,
        ):
            add_nested(parent, child, rel)
        for parent, child in re.findall(
            r'\(sdk-settings-boolean\s+\S+\s+"([^"]+)"\s+\S+\s+"([^"]+)"',
            source,
        ):
            add_nested(parent, child, rel)
        for key in re.findall(r'\(settings-boolean-value\s+\S+\s+"([^"]+)"', source):
            add_top(key, rel)
        for key in re.findall(
            r'\(cadr-ai::json-get\s+\S+\s+"([^"]+)"', source
        ):
            if re.match(r"^[a-z][A-Za-z0-9]+$", key):
                add_top(key, rel)
        if rel == SETTINGS_SDK:
            for key in re.findall(r'\(field "([^"]+)"', source):
                add_nested("retry", key, rel)

    fallback = read_text(ROOT / SETTINGS_BOOTSTRAP)
    start = fallback.find("(defparameter +settings-fallback-keys+")
    end = fallback.find("(defun ", start)
    for lisp_key, json_key in re.findall(
        r'\("([^"]+)"\s+\.\s+"([^"]+)"\)', fallback[start:end]
    ):
        add_top(json_key, SETTINGS_BOOTSTRAP)
        add_top(lisp_key, SETTINGS_BOOTSTRAP)
    return top, nested


def cadr_session_versions():
    found = {}
    codec = read_text(ROOT / SESSION_CODEC)
    if re.search(r"\(version 3\)", codec):
        found["3"] = SESSION_CODEC
    if re.search(r"\(version 1\)", codec):
        found["1"] = SESSION_CODEC
    journal = read_text(ROOT / SESSION_JOURNAL)
    if ":version 3" in journal:
        found["3"] = SESSION_JOURNAL
    migration = read_text(ROOT / SESSION_MIGRATION)
    if "migrate-v2-session-objects" in migration:
        found["2"] = SESSION_MIGRATION
    if ":version 3" in migration:
        found["3"] = SESSION_MIGRATION
    return found


def cadr_provider_ids():
    source = read_text(ROOT / PROVIDER_DEFS)
    start = source.find("(defparameter *built-in-provider-definition-rows*")
    if start < 0:
        raise SystemExit("providers: *built-in-provider-definition-rows* missing")
    ids = set(re.findall(r":id :([a-z0-9-]+)", source[start:]))
    if not ids:
        raise SystemExit("providers: empty id table")
    return ids


def cadr_error_classes():
    names = {}
    for rel in (ERROR_CLI, ERROR_AGENT, "src/cadr-ai/conditions.lisp"):
        source = read_text(ROOT / rel)
        for cond in re.findall(r"\(define-condition\s+([a-z0-9-]+)", source):
            names[lisp_type_name(cond)] = rel
            names[cond] = rel
    return names


def cadr_extension_events():
    source = read_text(ROOT / HOOK_EVENTS)
    start = source.find("(defparameter +extension-hook-events+")
    if start < 0:
        raise SystemExit("extension events: +extension-hook-events+ missing")
    end = source.find("(defun ", start)
    keywords = re.findall(r":([a-z0-9-]+)", source[start:end])
    if not keywords:
        raise SystemExit("extension events: empty")
    return {kw.replace("-", "_"): HOOK_EVENTS for kw in keywords}


def cadr_extension_type_fields():
    fields = {}

    def add(type_name, field, file):
        fields[type_name + "." + field] = file

    bundle = read_text(ROOT / EXT_BUNDLE)
    match = re.search(
        r"\(defstruct extension-bundle\n(.*?)\)\n\n\(defstruct",
        bundle,
        re.DOTALL,
    )
    if not match:
        raise SystemExit("extension bundle defstruct missing")
    slots = re.findall(r"\(([a-z0-9-]+)\b", match.group(1))
    slots += re.findall(r"^\s+([a-z0-9-]+)\n", match.group(1), re.MULTILINE)
    for slot in slots:
        add("Extension", kebab_to_camel(slot), EXT_BUNDLE)
    add("Extension", "hidden", EXT_BUNDLE)
    add("Extension", "messageRenderers", EXT_BUNDLE)
    add("Extension", "entryRenderers", EXT_BUNDLE)
    add("Extension", "markdownTransformer", EXT_BUNDLE)

    for struct, type_name in (
        ("extension-flag-definition", "ExtensionFlag"),
        ("extension-shortcut-definition", "ExtensionShortcut"),
        ("extension-command-definition", "RegisteredCommand"),
    ):
        block = re.search(
            rf"\(defstruct {struct}\n(.*?)\)\n\n\(defstruct",
            bundle,
            re.DOTALL,
        )
        if not block:
            continue
        for slot in re.findall(r"^\s+([a-z0-9-]+)\n", block.group(1), re.MULTILINE):
            add(type_name, kebab_to_camel(slot), EXT_BUNDLE)

    api = read_text(ROOT / EXT_API)
    for fn in re.findall(r"\(defun extension-api-([a-z0-9-]+)", api):
        camel = kebab_to_camel(fn)
        add("ExtensionAPI", camel, EXT_API)
        add("ExtensionActions", camel, EXT_API)
        if fn.startswith("events-"):
            add("ExtensionAPI", "events", EXT_API)
        if fn == "set-session-name":
            add("ExtensionActions", "setSessionName", EXT_API)

    ctx = read_text(ROOT / EXT_CONTEXT)
    for fn in re.findall(r"\(defun extension-command-context-([a-z0-9-]+)", ctx):
        camel = kebab_to_camel(fn)
        add("ExtensionCommandContextActions", camel, EXT_CONTEXT)
        if fn == "system-prompt-options":
            add("ExtensionContextActions", "getSystemPromptOptions", EXT_CONTEXT)
            add("ExtensionCommandContextActions", "getSystemPromptOptions", EXT_CONTEXT)
        if fn == "new-session":
            add("ExtensionCommandContextActions", "newSession", EXT_CONTEXT)
        if fn == "wait-for-idle":
            add("ExtensionCommandContextActions", "waitForIdle", EXT_CONTEXT)
    for fn in re.findall(r"\(defun extension-context-([a-z0-9-]+)", ctx):
        camel = kebab_to_camel(fn)
        add("ExtensionContext", camel, EXT_CONTEXT)
        add("ExtensionContextActions", camel, EXT_CONTEXT)
        if fn == "has-ui-p":
            add("ExtensionContext", "hasUI", EXT_CONTEXT)
        if fn == "idle-p":
            add("ExtensionContextActions", "isIdle", EXT_CONTEXT)
        if fn == "context-usage":
            add("ExtensionContextActions", "getContextUsage", EXT_CONTEXT)
        if fn == "system-prompt":
            add("ExtensionContextActions", "getSystemPrompt", EXT_CONTEXT)
        if fn.startswith("get-"):
            add("ExtensionContextActions", camel, EXT_CONTEXT)
        if fn == "model":
            add("ExtensionContextActions", "getModel", EXT_CONTEXT)
        if fn == "scoped-models":
            add("ExtensionContextActions", "getScopedModels", EXT_CONTEXT)
        if fn == "signal":
            add("ExtensionContextActions", "getSignal", EXT_CONTEXT)
        if fn == "has-pending-messages-p":
            add("ExtensionContextActions", "hasPendingMessages", EXT_CONTEXT)
        if fn == "model-registry-find":
            add("ExtensionContext", "modelRegistry", EXT_CONTEXT)
        if fn == "reload":
            add("ExtensionCommandContextActions", "reload", EXT_CONTEXT)
        if fn == "set-session-name":
            add("ExtensionActions", "setSessionName", EXT_CONTEXT)
    if ":placement" in ctx:
        add("ExtensionWidgetOptions", "placement", EXT_CONTEXT)
    if "&key signal timeout-ms" in ctx or ":signal signal" in ctx:
        add("ExtensionUIDialogOptions", "signal", EXT_CONTEXT)
    if "timeout-ms" in ctx:
        add("ExtensionUIDialogOptions", "timeout", EXT_CONTEXT)

    host = re.search(
        r"\(defstruct \(extension-host\n(.*?)\)\n\n;;;",
        ctx,
        re.DOTALL,
    )
    if host:
        for slot in re.findall(r"^\s+([a-z0-9-]+)\n", host.group(1), re.MULTILINE):
            camel = kebab_to_camel(slot)
            add("ExtensionRuntimeState", camel, EXT_CONTEXT)
            add("ExtensionHost", camel, EXT_CONTEXT)
        add("ExtensionRuntimeState", "flagValues", EXT_CONTEXT)
        add("ExtensionRuntimeState", "assertActive", EXT_CONTEXT)

    return fields


def cadr_keybinding_actions():
    actions = {}
    for rel in (KEY_TUI, KEY_SESSIONS, KEY_MODELS, KEY_THINKING, KEY_TREE):
        source = read_text(ROOT / rel)
        for name in re.findall(r'"((?:app|tui)\.[^"]+)"', source):
            actions[name] = rel
    return actions


def cadr_theme_tokens():
    source = read_text(ROOT / THEME_JSON)
    tokens = {}
    for name in re.findall(r'\("([A-Za-z]+)"\s+\.\s+:', source):
        tokens[name] = THEME_JSON
    return tokens


ENV_CALL = re.compile(
    r"(?:uiop:getenv|getenv|environment-value|environment-function|"
    r"truthy-environment-p|proxy-environment-value|"
    r"clipboard-environment-value|positive-environment-integer)"
    r"[\s\n]+\"([A-Z][A-Z0-9_]{2,})\"",
    re.MULTILINE,
)


def cadr_env_vars():
    names = {}
    for path in (ROOT / "src").rglob("*.lisp"):
        rel = str(path.relative_to(ROOT))
        source = read_text(path)
        if not (
            "getenv" in source
            or "environment-value" in source
            or "environment-function" in source
            or "truthy-environment-p" in source
        ):
            continue
        for name in ENV_CALL.findall(source):
            names[name] = rel
        for name in re.findall(
            r'funcall environment-function\s+"([A-Z][A-Z0-9_]{2,})"',
            source,
        ):
            names[name] = rel
        for name in re.findall(r'"([A-Z][A-Z0-9_]{2,})"', source):
            if name in (
                "HTTP_PROXY",
                "HTTPS_PROXY",
                "COLUMNS",
                "LINES",
                "DISPLAY",
                "WAYLAND_DISPLAY",
                "KITTY_WINDOW_ID",
                "GHOSTTY_RESOURCES_DIR",
                "WEZTERM_PANE",
                "WARP_SESSION_ID",
                "WARP_TERMINAL_SESSION_UUID",
                "ITERM_SESSION_ID",
                "WT_SESSION",
                "TMUX",
                "TERM_PROGRAM",
                "COLORTERM",
                "TERMINAL_EMULATOR",
            ):
                names[name] = rel
    return names


def inventory_settings_path(name):
    if "." not in name:
        return name
    iface, field = name.split(".", 1)
    return iface[:1].lower() + iface[1:] + "." + field


def classify(cls, name, regs):
    if cls == "exitCodes":
        file = regs["exit"].get(name)
        if file:
            return ("name-present", f"CLI exit status {name} in {file}")
        return ("missing", f"not a declared CLI exit status in {EXIT_FILE}/{EXIT_MAIN}/{EXIT_SESSIONS}")
    if cls == "settingsKeys":
        top, nested = regs["settings"]
        path = inventory_settings_path(name)
        if name in top:
            return ("name-present", f"settings JSON key in {top[name]}")
        if path in nested:
            return ("name-present", f"settings nested JSON path in {nested[path]}")
        if path in top:
            return ("name-present", f"settings JSON key in {top[path]}")
        parent = path.split(".", 1)[0] if "." in path else path
        file = top.get(parent) or nested.get(path)
        return (
            "missing",
            f"not in settings-value/nested keys ({SETTINGS_BOOTSTRAP}, {SETTINGS_MANAGER}, {SETTINGS_SDK})",
        )
    if cls == "sessionFormatVersions":
        file = regs["session"].get(name)
        if file:
            return ("name-present", f"session format version {name} in {file}")
        return ("missing", f"not in {SESSION_CODEC}/{SESSION_JOURNAL}/{SESSION_MIGRATION}")
    if cls == "providers":
        stem = name[:-3] if name.endswith(".ts") else name
        if stem in regs["providers"]:
            return (
                "name-present",
                f"*built-in-provider-definition-rows* :{stem} in {PROVIDER_DEFS}",
            )
        if stem == "faux" and (ROOT / FAUX_PROVIDER).is_file():
            return ("name-present", f"faux provider in {FAUX_PROVIDER}")
        if stem in PROVIDER_HELPER_STEMS or stem == "openrouter-images":
            return (
                "extractor-noise",
                f"helper module, not a *built-in-provider-definition-rows* id ({PROVIDER_DEFS})",
            )
        return ("missing", f"not in *built-in-provider-definition-rows* ({PROVIDER_DEFS})")
    if cls == "errorClasses":
        file = regs["errors"].get(name)
        if file:
            return ("name-present", f"define-condition in {file}")
        return ("missing", f"no define-condition matching {name} ({ERROR_CLI}, {ERROR_AGENT})")
    if cls == "extensionEvents":
        file = regs["events"].get(name)
        if file:
            return ("name-present", f"+extension-hook-events+ in {file}")
        return ("missing", f"not in +extension-hook-events+ ({HOOK_EVENTS})")
    if cls == "extensionTypeFields":
        file = regs["fields"].get(name)
        if file:
            return ("name-present", f"extension struct/function in {file}")
        return (
            "missing",
            f"not in extension defstruct/API ({EXT_BUNDLE}, {EXT_API}, {EXT_CONTEXT})",
        )
    if cls == "exportedComponents":
        pkg = read_text(ROOT / ARMIN_PKG)
        src = read_text(ROOT / ARMIN)
        if name == "ArminComponent" and "armin-component" in pkg and "defclass armin-component" in src:
            return ("name-present", f"armin-component class export in {ARMIN} / {ARMIN_PKG}")
        return ("missing", f"no exported component named {name}")
    if cls == "keybindingActions":
        file = regs["keys"].get(name)
        if file:
            return ("name-present", f"keybinding definition in {file}")
        return (
            "missing",
            f"not in +tui-keybinding-definitions+ or selector tables ({KEY_TUI})",
        )
    if cls == "themeTokens":
        file = regs["theme"].get(name)
        if file:
            return ("name-present", f"+tui-theme-json-color-map+ / export map in {file}")
        return ("missing", f"not in +tui-theme-json-color-map+ ({THEME_JSON})")
    if cls == "environmentVariables":
        file = regs["env"].get(name)
        if file:
            return ("name-present", f"uiop:getenv {name!r} in {file}")
        return ("missing", "no uiop:getenv literal for this name under src/")
    raise SystemExit(f"unknown class {cls}")


def load_registries():
    return {
        "exit": cadr_exit_codes(),
        "settings": cadr_settings_keys(),
        "session": cadr_session_versions(),
        "providers": cadr_provider_ids(),
        "errors": cadr_error_classes(),
        "events": cadr_extension_events(),
        "fields": cadr_extension_type_fields(),
        "keys": cadr_keybinding_actions(),
        "theme": cadr_theme_tokens(),
        "env": cadr_env_vars(),
    }


def render_tsv(inventory_path):
    regs = load_registries()
    if not regs["exit"]:
        raise SystemExit("blocked: exitCodes registry empty")
    lines = [HEADER]
    for cls, name, _status in inventory_rows(inventory_path):
        presence, note = classify(cls, name, regs)
        lines.append(f"{cls}\t{name}\t{presence}\topen\t{note}")
    return "\n".join(lines) + "\n"


def check_tsv(path, generated):
    expected = list(csv.reader(io.StringIO(generated), delimiter="\t"))
    found = list(csv.reader(io.StringIO(Path(path).read_text(encoding="utf-8")), delimiter="\t"))
    if found != expected:
        raise SystemExit("check: file bytes differ from regeneration")
    inventory = inventory_rows(INVENTORY)
    wanted = [(cls, name) for cls, name, _status in inventory]
    got = []
    for i, row in enumerate(found):
        if i == 0:
            continue
        cls, name, presence, status, _note = row
        if cls in FORBIDDEN_CLASSES:
            raise SystemExit(f"check: publicApiExports must be absent ({name})")
        if cls not in PRESENCE_CLASSES:
            raise SystemExit(f"check: unexpected class {cls}")
        if status == "match":
            raise SystemExit(f"check: match status on {cls}\t{name}")
        if status != "open":
            raise SystemExit(f"check: status must stay open on {cls}\t{name}")
        if presence not in ALLOWED_PRESENCE:
            raise SystemExit(f"check: bad presence {presence}")
        got.append((cls, name))
    if got != wanted:
        raise SystemExit("check: inventory rows for covered classes are not 1:1")


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
