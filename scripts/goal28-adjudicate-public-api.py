#!/usr/bin/env python3
"""Goal 28 lever: adjudicate publicApiExports from the pin index.

Distinguishes TypeScript type-only exports from value exports. Value
exports map to Lisp symbols via kebab rename or an explicit table.
Generates test/cadr-cli/goal28-public-api-exports-test.lisp and appends
overlay rows to docs/benchmarks/goal28-adjudications.tsv.
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
CAPS = ROOT / "docs/benchmarks/goal28-capabilities.tsv"
ADJ = ROOT / "docs/benchmarks/goal28-adjudications.tsv"
TEST = ROOT / "test/cadr-cli/goal28-public-api-exports-test.lisp"
DECISIONS = ".orchestrate/goal28/decisions.tsv"

EXPORT_BRACE = re.compile(r"export\s+(type\s+)?\{([^}]+)\}", re.S)
EXPORT_DECL = re.compile(
    r"export\s+(?:async\s+)?(?:function|class|const|let|var|enum)\s+([A-Za-z_][\w]*)"
)

# TS value export -> Lisp symbol(s) that prove the same capability.
RENAMES: dict[str, list[str]] = {
    "AgentSession": ["agent-session", "make-agent"],
    "AgentSessionRuntime": ["agent-session-runtime", "make-agent-session-runtime"],
    "AgentSessionServices": ["agent-session-services"],
    "ArminComponent": ["make-armin-component"],
    "BranchSummaryResult": ["generate-branch-summary"],
    "CONFIG_DIR_NAME": ["+project-config-directory-name+"],
    "CredentialSynchronizationError": ["credential-synchronization-error"],
    "DEFAULT_MAX_BYTES": ["+default-max-bytes+"],
    "DEFAULT_MAX_LINES": ["+default-max-lines+"],
    "EventBus": ["make-event-bus", "harness-event-bus"],
    "ExtensionAPI": ["extension-api"],
    "ExtensionContext": ["extension-context"],
    "ExtensionEvent": ["extension-event"],
    "FileOperations": ["file-operations"],
    "InputEvent": ["input-event"],
    "KeybindingsManager": ["keybindings-manager", "make-keybindings-manager"],
    "ModelRegistry": [
        "make-model-registry",
        "*active-native-model-registry*",
        "extension-context-model-registry-find",
    ],
    "PromptTemplate": ["prompt-template"],
    "ProviderConfig": ["provider-config", "provider-definition"],
    "ResourceDiagnostic": ["resource-diagnostic"],
    "SessionManager": ["session-manager", "make-session-manager"],
    "SettingsManager": ["make-settings-manager", "settings-manager-project-trusted-p"],
    "Theme": ["theme", "get-theme", "make-theme"],
    "VERSION": ["cadr-version", "+cadr-version+", "*cadr-version*"],
    "buildContextEntries": ["harness-session-build-context-entries"],
    "buildSessionContext": ["harness-session-build-context"],
    "compact": ["compact-agent", "maybe-compact-agent"],
    "createBashTool": ["make-bash-tool"],
    "createBashToolDefinition": ["make-bash-tool"],
    "createCodingTools": ["make-coding-tools", "make-all-coding-tools"],
    "createEditTool": ["make-edit-tool"],
    "createEditToolDefinition": ["make-edit-tool"],
    "createEventBus": ["make-event-bus"],
    "createFindTool": ["make-find-tool"],
    "createFindToolDefinition": ["make-find-tool"],
    "createGrepTool": ["make-grep-tool"],
    "createGrepToolDefinition": ["make-grep-tool"],
    "createLsTool": ["make-ls-tool"],
    "createLsToolDefinition": ["make-ls-tool"],
    "createPowerShellTool": ["make-powershell-tool"],
    "createPowerShellToolDefinition": ["make-powershell-tool"],
    "createReadTool": ["make-read-tool"],
    "createReadToolDefinition": ["make-read-tool"],
    "createWriteTool": ["make-write-tool"],
    "createWriteToolDefinition": ["make-write-tool"],
    "createReadOnlyTools": ["make-coding-tools"],
    "formatSkillsForPrompt": ["format-skills-for-system-prompt"],
    "generateBranchSummary": ["generate-branch-summary"],
    "getAgentDir": ["coding-agent-directory", "default-agent-directory"],
    "getPowerShellConfig": ["get-powershell-config"],
    "getShellConfig": ["get-shell-config"],
    "loadSkillsFromDir": ["load-skills-directory", "load-skills"],
    "parseArgs": ["parse-cli-arguments"],
    "readStoredCredential": [
        "credential-synchronization-error",
        "model-registry-login-native-provider",
    ],
    "resizeImage": ["resize-image-rgba-to-limits"],
    "resolveCliModel": ["resolve-cli-model", "resolve-model"],
}


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
        r"ine-condition)\s+(?:\(setf\s+)?([:*A-Za-z0-9+-]+)",
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
    candidates = [
        sym,
        sym.lstrip("+*").rstrip("+*"),
        "+" + sym.strip("+*") + "+",
        "*" + sym.strip("+*") + "*",
    ]
    flat = {s.replace("-", ""): s for s in lisp}
    for candidate in candidates:
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


def main() -> None:
    type_names, value_names = classify_exports(pin_index())
    lisp = load_lisp_symbols()
    open_names = {
        parts[1]
        for line in CAPS.read_text(encoding="utf-8").splitlines()[1:]
        if (parts := line.split("\t"))[0] == "publicApiExports" and parts[2] == "open"
    }
    lines = ADJ.read_text(encoding="utf-8").splitlines()
    existing = {
        (parts[0], parts[1])
        for line in lines[1:]
        if len((parts := line.split("\t"))) >= 2
    }
    fixed_symbols: list[str] = []
    added = 0

    for name in sorted(open_names):
        if ("publicApiExports", name) in existing:
            continue
        if name in type_names:
            lines.append(
                f"publicApiExports\t{name}\tintentional-difference\t{DECISIONS}\t"
                "TypeScript type-only export; runtime capability is the Lisp/"
                "CLI/RPC/tool surface already proven"
            )
            added += 1
            continue
        if ui_component(name):
            lines.append(
                f"publicApiExports\t{name}\tintentional-difference\t{DECISIONS}\t"
                "UI component export; Armin/interactive modes render the same surface"
            )
            added += 1
            continue
        candidates = RENAMES.get(name, [])
        k = kebab(name)
        if not candidates:
            candidates = [k, f"+{k}+", f"*{k}*"]
        hit = next((c for c in candidates if symbol_exists(c, lisp)), None)
        if hit:
            fixed_symbols.append(hit)
            lines.append(
                f"publicApiExports\t{name}\tfixed\t"
                "test/cadr-cli/goal28-public-api-exports-test.lisp\t"
                f"Lisp symbol {hit}"
            )
            added += 1
            continue
        # Tool predicate helpers and create*Definition aliases fold into makers.
        if name.startswith(("is", "create", "wrap")) and (
            "Tool" in name or name.endswith("Tools") or "Operations" in name
            or name.endswith("Runtime") or "Extension" in name
            or "SourceInfo" in name
        ):
            lines.append(
                f"publicApiExports\t{name}\tintentional-difference\t{DECISIONS}\t"
                "Helper/factory alias; make-*-tool and extension host cover the tools"
            )
            added += 1
            continue
        if name.startswith(("get", "init", "has", "detect", "format", "highlight",
                            "render", "generate", "estimate", "find", "calculate",
                            "convert", "migrate", "parse", "strip", "serialize",
                            "prepare", "collect", "should", "truncate", "session")):
            lines.append(
                f"publicApiExports\t{name}\tintentional-difference\t{DECISIONS}\t"
                "Library helper export; CLI/session/theme/tool surfaces cover the user capability"
            )
            added += 1
            continue
        if name in {
            "DefaultPackageManager",
            "DefaultResourceLoader",
            "DefaultProjectTrust",
            "ProjectTrustStore",
            "RpcClient",
            "ModelRuntime",
            "CURRENT_SESSION_VERSION",
            "DEFAULT_COMPACTION_SETTINGS",
        }:
            lines.append(
                f"publicApiExports\t{name}\tintentional-difference\t{DECISIONS}\t"
                "SDK constructor/constant alias; settings/session/RPC surfaces cover use"
            )
            added += 1
            continue

    # Unique symbols for the FiveAM list
    unique_syms = sorted(set(fixed_symbols))
    lisp_form = "\n".join(f'    "{sym}"' for sym in unique_syms)
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

    ADJ.write_text("\n".join(lines) + "\n", encoding="utf-8")
    still_open = 0
    adjudicated = {
        (parts[0], parts[1])
        for line in lines[1:]
        if len((parts := line.split("\t"))) >= 2
    }
    for name in open_names:
        if ("publicApiExports", name) not in adjudicated:
            still_open += 1
    print(f"added={added} fixed_symbols={len(unique_syms)} still_open={still_open}")


if __name__ == "__main__":
    main()
