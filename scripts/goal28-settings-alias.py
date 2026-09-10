#!/usr/bin/env python3
"""Classify Goal 28 settingsKeys marked missing as alias or truly-absent.

Status stays open. match is forbidden.
"""
import argparse
import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PRESENCE = ROOT / "docs/benchmarks/goal28-presence-rest.tsv"
HEADER = ("name", "disposition", "cadr_path", "evidence", "status")
ALLOWED_DISPOSITION = ("alias", "truly-absent")

# Frozen table. Each cadr_path is a JSON path or setting id actually
# read or written in settings bootstrap, manager, or SDK settings.
# Similar English words without that path stay truly-absent.
ROWS = (
    (
        "BranchSummary.reserveTokens",
        "truly-absent",
        "",
        "no branchSummary object in settings-value/nested set; generate-branch-summary uses a Lisp default in src/cadr-agent/branch-summarization.lisp",
    ),
    (
        "BranchSummary.skipPrompt",
        "truly-absent",
        "",
        "no skipPrompt key on settings; branch summary has no settings-backed skip flag in bootstrap or manager",
    ),
    (
        "Compaction.keepRecentTokens",
        "truly-absent",
        "",
        "compaction stores only enabled via settings-boolean-value/settings-set-nested in src/cadr-cli/bootstrap/settings.lisp; keepRecentTokens is not read",
    ),
    (
        "Compaction.reserveTokens",
        "truly-absent",
        "",
        "compaction JSON only has enabled in src/cadr-cli/bootstrap/settings.lisp and src/cadr-cli/sdk/settings-service.lisp; reserveTokens is an agent slot default, not a settings path",
    ),
    (
        "Image.autoResize",
        "alias",
        "images.autoResize",
        "settings-value images then json-get autoResize; persist settings-set-nested images autoResize; option id auto-resize-images in src/cadr-cli/bootstrap/settings.lisp",
    ),
    (
        "Image.blockImages",
        "alias",
        "images.blockImages",
        "settings-value images then json-get blockImages; persist settings-set-nested images blockImages; option id block-images; settings-block-images-p in src/cadr-cli/settings/manager.lisp",
    ),
    (
        "Markdown.codeBlockIndent",
        "truly-absent",
        "",
        "markdown nested key in settings is mermaid only (settings-nested-value markdown mermaid) in src/cadr-cli/bootstrap/settings.lisp; no codeBlockIndent",
    ),
    (
        "ProviderRetry.maxRetries",
        "alias",
        "retry.provider.maxRetries",
        "sdk-settings-retry-settings reads retry then json-get provider and field maxRetries (merge of retry and retry.provider) in src/cadr-cli/sdk/settings-service.lisp",
    ),
    (
        "ProviderRetry.maxRetryDelayMs",
        "alias",
        "retry.provider.maxRetryDelayMs",
        "sdk-settings-retry-settings field maxRetryDelayMs on merged retry/retry.provider in src/cadr-cli/sdk/settings-service.lisp",
    ),
    (
        "ProviderRetry.timeoutMs",
        "alias",
        "retry.provider.timeoutMs",
        "sdk-settings-retry-settings field timeoutMs on merged retry/retry.provider in src/cadr-cli/sdk/settings-service.lisp",
    ),
    (
        "Retry.provider",
        "alias",
        "retry.provider",
        "sdk-settings-retry-settings json-get retry provider in src/cadr-cli/sdk/settings-service.lisp",
    ),
    (
        "Terminal.hyperlinks",
        "alias",
        "terminal.hyperlinks",
        "settings-terminal-capability-overrides json-present-p/json-get terminal hyperlinks in src/cadr-cli/bootstrap/settings.lisp",
    ),
    (
        "Terminal.images",
        "alias",
        "terminal.images",
        "settings-terminal-capability-overrides json-get terminal images (kitty/iterm2/none) in src/cadr-cli/bootstrap/settings.lisp, not the top-level images object",
    ),
    (
        "Terminal.trueColor",
        "alias",
        "terminal.trueColor",
        "settings-terminal-capability-overrides json-get terminal trueColor in src/cadr-cli/bootstrap/settings.lisp",
    ),
    (
        "ThinkingBudgets.high",
        "truly-absent",
        "",
        "no thinkingBudgets object in settings; modelThinkingLevels and defaultThinkingLevel are different keys in src/cadr-cli/settings/manager.lisp",
    ),
    (
        "ThinkingBudgets.low",
        "truly-absent",
        "",
        "no thinkingBudgets.low in settings bootstrap or manager",
    ),
    (
        "ThinkingBudgets.medium",
        "truly-absent",
        "",
        "no thinkingBudgets.medium in settings bootstrap or manager",
    ),
    (
        "ThinkingBudgets.minimal",
        "truly-absent",
        "",
        "no thinkingBudgets.minimal in settings bootstrap or manager",
    ),
    (
        "Warning.anthropicExtraUsage",
        "alias",
        "warnings.anthropicExtraUsage",
        "settings-boolean-value warnings anthropicExtraUsage; settings-set-nested warnings anthropicExtraUsage; option id anthropic-extra-usage in src/cadr-cli/bootstrap/settings.lisp",
    ),
    (
        "branchSummary",
        "truly-absent",
        "",
        "no settings-value branchSummary in bootstrap, manager, or settings-service",
    ),
    (
        "extensions",
        "truly-absent",
        "",
        "settings.json has no extensions array reader; resource loader uses CLI paths and packages, not this key (src/cadr-cli/resource-loader.lisp)",
    ),
    (
        "externalEditor",
        "truly-absent",
        "",
        "externalEditor in src/cadr-cli/settings/manager.lisp is a keybinding name migration to app.editor.external, not the externalEditor command string setting",
    ),
    (
        "httpProxy",
        "truly-absent",
        "",
        "apply-http-proxy-setting takes a string in src/cadr-cli/sdk/cache-version.lisp; no settings-value httpProxy",
    ),
    (
        "lastChangelogVersion",
        "truly-absent",
        "",
        "no lastChangelogVersion in settings bootstrap or manager; collapseChangelog is a different key",
    ),
    (
        "npmCommand",
        "truly-absent",
        "",
        "package-npm-install-argv takes an npm-command keyword in src/cadr-cli/packages/source.lisp; no settings-value npmCommand",
    ),
    (
        "prompts",
        "truly-absent",
        "",
        "no settings-value prompts; prompt paths come from CLI and agent-dir, not a settings.json array",
    ),
    (
        "sessionDir",
        "truly-absent",
        "",
        "session directory is CLI --session-dir / CADR_CODING_AGENT_SESSION_DIR in src/cadr-cli/arguments.lisp; no settings-value sessionDir",
    ),
    (
        "shellCommandPrefix",
        "truly-absent",
        "",
        "no shellCommandPrefix in settings bootstrap, manager, or settings-service",
    ),
    (
        "shellPath",
        "truly-absent",
        "",
        "get-shell-config optional path is not loaded from settings; the settings.json mention in src/cadr-cli/support/shell-process.lisp is error text only",
    ),
    (
        "skills",
        "truly-absent",
        "",
        "no settings-value skills; skill paths come from CLI and agent-dir, not a settings.json array",
    ),
    (
        "themes",
        "truly-absent",
        "",
        "settings theme is the string key theme; no settings-value themes array for extra theme paths",
    ),
    (
        "thinkingBudgets",
        "truly-absent",
        "",
        "thinkingBudgets appears as a stream option in src/cadr-agent/proxy.lisp, not as a settings.json key",
    ),
    (
        "websocketConnectTimeoutMs",
        "truly-absent",
        "",
        "merge-stream-settings copies a plist key in src/cadr-cli/support/headers.lisp; no settings-value websocketConnectTimeoutMs",
    ),
)

BY_NAME = {row[0]: row for row in ROWS}


def missing_settings_names(path):
    names = []
    with path.open(encoding="utf-8") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        for row in reader:
            if row.get("class") == "settingsKeys" and row.get("presence") == "missing":
                names.append(row["name"])
    return names


def write_table(path, names):
    lines = ["\t".join(HEADER)]
    for name in names:
        row = BY_NAME[name]
        lines.append("\t".join((row[0], row[1], row[2], row[3], "open")))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def check_table(path, expected_names):
    errors = []
    with path.open(encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    names = [row["name"] for row in rows]
    if names != expected_names:
        errors.append(
            "name list must be the 33 missing settingsKeys in presence-rest order"
        )
    if len(names) != len(set(names)):
        errors.append("duplicate name")
    if len(names) != 33:
        errors.append(f"expected 33 rows, got {len(names)}")
    for row in rows:
        if row.get("status") == "match":
            errors.append(f"{row['name']} status is match")
        if row.get("status") != "open":
            errors.append(f"{row['name']} status is {row.get('status')!r}")
        if row.get("disposition") not in ALLOWED_DISPOSITION:
            errors.append(f"{row['name']} disposition {row.get('disposition')!r}")
        if row.get("disposition") == "alias" and not (row.get("cadr_path") or "").strip():
            errors.append(f"{row['name']} alias missing cadr_path")
    auto = next((row for row in rows if row["name"] == "Image.autoResize"), None)
    if auto is None or auto.get("disposition") != "alias":
        errors.append("Image.autoResize must be alias")
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", type=Path)
    parser.add_argument("--check", type=Path)
    args = parser.parse_args()
    presence = PRESENCE
    if not presence.is_file():
        print(f"missing {presence}", file=sys.stderr)
        return 1
    expected = missing_settings_names(presence)
    missing_class = [name for name in expected if name not in BY_NAME]
    extra_class = [name for name in BY_NAME if name not in expected]
    if missing_class or extra_class:
        print(
            f"classification table mismatch missing={missing_class} extra={extra_class}",
            file=sys.stderr,
        )
        return 1
    if args.write:
        write_table(args.write, expected)
        alias = sum(1 for name in expected if BY_NAME[name][1] == "alias")
        absent = len(expected) - alias
        print(f"wrote {args.write} rows={len(expected)} alias={alias} truly-absent={absent}")
    if args.check:
        errors = check_table(args.check, expected)
        if errors:
            for error in errors:
                print(error, file=sys.stderr)
            return 1
        with args.check.open(encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle, delimiter="\t"))
        alias = sum(1 for row in rows if row["disposition"] == "alias")
        absent = sum(1 for row in rows if row["disposition"] == "truly-absent")
        print(f"check ok rows={len(rows)} alias={alias} truly-absent={absent}")
    if not args.write and not args.check:
        parser.print_help()
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
