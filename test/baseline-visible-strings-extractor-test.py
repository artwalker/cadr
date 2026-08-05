#!/usr/bin/env python3
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]
EXTRACTOR = ROOT / "test/fixtures/render-diff/baseline-visible-strings.ts"
BASELINE_NODE_MODULES = Path("/tmp/cadr-render-diff-pi-74caa2649/node_modules")


class BaselineVisibleStringsExtractorTest(unittest.TestCase):
    def setUp(self) -> None:
        if not BASELINE_NODE_MODULES.is_dir():
            self.skipTest("fixed render-diff baseline node_modules is unavailable")
        self.temporary = tempfile.TemporaryDirectory(prefix="cadr-visible-sites-")
        self.root = Path(self.temporary.name)
        (self.root / "node_modules").symlink_to(BASELINE_NODE_MODULES, target_is_directory=True)
        self.extractor = self.root / "extractor.ts"
        shutil.copy2(EXTRACTOR, self.extractor)
        source = self.root / "packages/coding-agent/src/modes/interactive/sample.ts"
        source.parent.mkdir(parents=True)
        (self.root / "packages/tui/src").mkdir(parents=True)
        source.write_text(
            textwrap.dedent(
                """
                const captured: string[] = [];
                const theme = {
                  fg: (role: string, value: string) => `<${role}>${value}</${role}>`,
                  bold: (value: string) => `<b>${value}</b>`,
                };
                const keyHint = (key: string, description: string) => `[${key}] ${description}`;
                const name = process.env.SAMPLE_NAME ?? "Ada";
                const total = 2;
                class Text {
                  constructor(value: string) { captured.push(value); }
                }
                const showStatus = (value: string) => captured.push(value);
                const showError = (value: string) => captured.push(value);
                const showWarning = (value: string) => captured.push(value);
                const setTextInternal = (value: string, _cursor: "start" | "end") => captured.push(value);
                function getModelSearchText(): string { return "fuzzy-only haystack"; }

                new Text(theme.bold(theme.fg(
                  "accent",
                  `Hello ${name} ${name === "Ada" ? "friend" : "stranger"} ${keyHint("confirm", "continue")}`,
                )));
                showStatus("Done " + total + " items");
                showError("same");
                showWarning("same");
                setTextInternal("editor text", "start");
                void getModelSearchText();

                export { captured };
                """
            ).lstrip(),
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_extractor(self, *extra: str) -> dict[str, object]:
        result = subprocess.run(
            [
                str(self.root / "node_modules/.bin/tsx"),
                str(self.extractor),
                str(self.root),
                "deadbeef",
                *extra,
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        return json.loads(result.stdout)

    def test_sink_expressions_are_site_keyed_composites(self) -> None:
        inventory = self.run_extractor()
        self.assertEqual(3, inventory["schemaVersion"])
        self.assertIn(
            "explicit sink contracts",
            inventory["extractionRules"]["soundnessBoundary"],
        )
        entries = inventory["entries"]
        self.assertEqual(5, len(entries))
        self.assertEqual(5, len({entry["id"] for entry in entries}))

        kinds = [entry["site"]["kind"] for entry in entries]
        self.assertEqual(
            ["new:Text", "call:showStatus", "call:showError", "call:showWarning", "call:setTextInternal"],
            kinds,
        )
        positions = {
            (entry["site"]["path"], entry["site"]["start"], entry["site"]["end"])
            for entry in entries
        }
        self.assertEqual(5, len(positions))
        for entry in entries:
            self.assertRegex(entry["id"], r"^VS-[0-9a-f]{16}$")
            self.assertRegex(entry["site"]["nodeSha256"], r"^[0-9a-f]{64}$")
            self.assertEqual("printable-visible", entry["sink"]["channel"])

        text_entry = entries[0]
        self.assertEqual(4, len(text_entry["branches"]))
        choices = [branch["runtimeChoices"] for branch in text_entry["branches"]]
        self.assertTrue(all(len(choice) == 1 for choice in choices))
        self.assertRegex(choices[0][0], r"^C-[0-9a-f]{12}:true$")
        self.assertRegex(choices[1][0], r"^C-[0-9a-f]{12}:false$")
        self.assertEqual(choices[0][0].split(":")[0], choices[1][0].split(":")[0])
        branch_literals = [
            "".join(segment.get("text", "") for segment in branch["segments"])
            for branch in text_entry["branches"]
        ]
        self.assertEqual(
            {
                "Hello  friend  continue",
                "Hello  stranger  continue",
                "Hello Ada friend  continue",
                "Hello Ada stranger  continue",
            },
            set(branch_literals),
        )
        for branch in text_entry["branches"]:
            self.assertIn(
                sum(segment["kind"] == "slot" for segment in branch["segments"]),
                {1, 2},
            )
            self.assertTrue(all("stylePath" in segment for segment in branch["segments"]))

        same_entries = [
            entry
            for entry in entries
            if any(
                segment.get("text") == "same"
                for branch in entry["branches"]
                for segment in branch["segments"]
            )
        ]
        self.assertEqual(2, len(same_entries), "identical text at distinct sinks must not deduplicate")
        self.assertNotEqual(same_entries[0]["id"], same_entries[1]["id"])
        inventory_text = json.dumps(inventory)
        self.assertNotIn("fuzzy-only haystack", inventory_text)
        self.assertNotIn(
            "start",
            [
                segment.get("text")
                for entry in entries
                for branch in entry["branches"]
                for segment in branch["segments"]
            ],
        )
        self.assertEqual(inventory, self.run_extractor(), "site IDs and ordering must be deterministic")

    def test_known_terminal_protocol_identifiers_are_not_printable_sites(self) -> None:
        terminal = self.root / "packages/tui/src/terminal.ts"
        terminal.write_text(
            textwrap.dedent(
                r'''
                const KITTY_KEYBOARD_PROTOCOL_QUERY = "\x1b[?u";
                function queryAndEnableKittyProtocol(): void {
                  process.stdout.write(KITTY_KEYBOARD_PROTOCOL_QUERY);
                }
                queryAndEnableKittyProtocol();
                '''
            ).lstrip(),
            encoding="utf-8",
        )
        main_screen = self.root / "packages/tui/src/TuiMainScreen.ts"
        main_screen.write_text(
            textwrap.dedent(
                r'''
                const terminal = { write: (_value: string) => undefined };
                class TuiMainScreen {
                  positionHardwareCursor(): void {
                    let buffer = "";
                    buffer += "\x1b[1A";
                    terminal.write(buffer);
                  }
                }
                new TuiMainScreen().positionHardwareCursor();
                '''
            ).lstrip(),
            encoding="utf-8",
        )

        inventory = self.run_extractor()
        protocol_paths = {
            entry["site"]["path"]
            for entry in inventory["entries"]
            if entry["sink"]["channel"] == "terminal-protocol"
        }
        self.assertIn("packages/tui/src/terminal.ts", protocol_paths)
        self.assertIn("packages/tui/src/TuiMainScreen.ts", protocol_paths)

    def test_instrumentation_is_local_zero_width_and_opt_in(self) -> None:
        destination = self.root / "instrumented"
        inventory = self.run_extractor("--instrument", str(destination))
        instrumented = destination / "packages/coding-agent/src/modes/interactive/sample.ts"
        source = instrumented.read_text(encoding="utf-8")
        self.assertEqual(1, source.count("function __cadrRenderDiffVisibleSite_"))
        self.assertEqual(1, source.count("function __cadrRenderDiffVisibleChoice_"))
        self.assertEqual(2, source.count("cadr-visible-branch;phase="))
        self.assertNotIn("cadr-visible-choice=", source)
        self.assertIn("__cadrRenderDiffVisibleChoices ??= []).push", source)
        self.assertIn('process.env.RENDER_DIFF_VISIBLE_SITES !== "1"', source)
        for entry in inventory["entries"]:
            self.assertEqual(1, source.count(json.dumps(entry["id"])))

        runner = destination / "runner.ts"
        runner.write_text(
            'import { captured } from "./packages/coding-agent/src/modes/interactive/sample.ts";\n'
            'if (process.env.RENDER_DIFF_VISIBLE_SITES === "1") {\n'
            '  for (const value of captured) process.stdout.write(`${value}\\n`);\n'
            '} else process.stdout.write(JSON.stringify(captured));\n',
            encoding="utf-8",
        )
        command = [str(self.root / "node_modules/.bin/tsx"), str(runner)]
        disabled_result = subprocess.run(
            command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        disabled = disabled_result.stdout
        self.assertNotIn(b"\x1b]777", disabled)
        self.assertNotIn(b"\x1b]777", disabled_result.stderr)
        self.assertEqual(
            [
                "<b><accent>Hello Ada friend [confirm] continue</accent></b>",
                "Done 2 items",
                "same",
                "same",
                "editor text",
            ],
            json.loads(disabled),
        )

        environment = os.environ.copy()
        environment["RENDER_DIFF_VISIBLE_SITES"] = "1"
        enabled_result = subprocess.run(
            command,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        )
        enabled_stream = enabled_result.stdout.decode("ascii")
        self.assertEqual(b"", enabled_result.stderr)
        for entry in inventory["entries"]:
            selected_branch = next(
                branch
                for branch in entry["branches"]
                if not branch["runtimeChoices"]
                or branch["runtimeChoices"][0].endswith(":true")
            )
            marker = (
                f"\x1b]777;cadr-visible-branch;phase=begin;site={entry['id']};"
                f"branch={selected_branch['id']}\x07"
            )
            self.assertIn(marker, enabled_stream)
            self.assertIn(marker.replace("phase=begin", "phase=end"), enabled_stream)
            for branch in entry["branches"]:
                if branch is selected_branch:
                    continue
                self.assertNotIn(f"branch={branch['id']}", enabled_stream)

        clean_enabled = re.sub(
            r"\x1b\]777;cadr-visible-branch;phase=(?:begin|end);site=VS-[0-9a-f]{16};branch=B-[0-9a-f]{12}\x07",
            "",
            enabled_stream,
        ).splitlines()
        self.assertEqual(json.loads(disabled), clean_enabled)

        alternate_environment = environment.copy()
        alternate_environment["SAMPLE_NAME"] = "Grace"
        alternate_result = subprocess.run(
            command,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=alternate_environment,
        )
        alternate_stream = alternate_result.stdout.decode("ascii")
        self.assertEqual(b"", alternate_result.stderr)
        text_entry = inventory["entries"][0]
        false_branch = next(
            branch
            for branch in text_entry["branches"]
            if branch["runtimeChoices"][0].endswith(":false")
        )
        self.assertIn(f"branch={false_branch['id']}", alternate_stream)
        clean_alternate = re.sub(
            r"\x1b\]777;cadr-visible-branch;phase=(?:begin|end);site=VS-[0-9a-f]{16};branch=B-[0-9a-f]{12}\x07",
            "",
            alternate_stream,
        ).splitlines()
        self.assertEqual("<b><accent>Hello Grace stranger [confirm] continue</accent></b>", clean_alternate[0])

    def test_marker_is_provenance_that_must_reach_the_emission_stream(self) -> None:
        destination = self.root / "instrumented-hidden"
        inventory = self.run_extractor("--instrument", str(destination))
        runner = destination / "hidden-runner.ts"
        runner.write_text(
            'import { captured } from "./packages/coding-agent/src/modes/interactive/sample.ts";\n'
            'process.stdout.write(captured[0] ?? "");\n',
            encoding="utf-8",
        )
        environment = os.environ.copy()
        environment["RENDER_DIFF_VISIBLE_SITES"] = "1"
        result = subprocess.run(
            [str(self.root / "node_modules/.bin/tsx"), str(runner)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        )
        self.assertEqual(0, result.returncode, result.stderr.decode())
        stream = result.stdout.decode("ascii")
        self.assertEqual(b"", result.stderr)
        self.assertIn(f"site={inventory['entries'][0]['id']}", stream)
        for entry in inventory["entries"][1:]:
            self.assertNotIn(f"site={entry['id']}", stream)

    def test_tui_string_array_provenance_reaches_terminal_emission(self) -> None:
        source = self.root / "packages/tui/src/components/rows.ts"
        # The component subtree is the typed TUI presentation boundary.
        source.parent.mkdir(parents=True, exist_ok=True)
        source.write_text(
            'export function renderRows(): string[] { return ["first row", "second row"]; }\n',
            encoding="utf-8",
        )
        destination = self.root / "instrumented-rows"
        inventory = self.run_extractor("--instrument", str(destination))
        row_entry = next(
            entry for entry in inventory["entries"]
            if entry["site"]["path"] == "packages/tui/src/components/rows.ts"
        )
        runner = destination / "rows-runner.ts"
        runner.write_text(
            'import { renderRows } from "./packages/tui/src/components/rows.ts";\n'
            'renderRows();\n'
            'const rendered = renderRows().join("\\n");\n'
            'process.stdout.write(rendered);\n',
            encoding="utf-8",
        )
        environment = os.environ.copy()
        environment["RENDER_DIFF_VISIBLE_SITES"] = "1"
        result = subprocess.run(
            [str(self.root / "node_modules/.bin/tsx"), str(runner)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        )
        self.assertEqual(b"", result.stderr)
        self.assertIn(f"site={row_entry['id']}".encode(), result.stdout)
        self.assertEqual(
            1,
            result.stdout.count(
                f"phase=begin;site={row_entry['id']}".encode()
            ),
            "repeated renders before one output chunk must not duplicate a pending site",
        )
        clean = re.sub(
            rb"\x1b\]777;cadr-visible-branch;phase=(?:begin|end);site=VS-[0-9a-f]{16};branch=B-[0-9a-f]{12}\x07",
            b"",
            result.stdout,
        )
        self.assertEqual(b"first row\nsecond row", clean)

    def test_tui_components_markdown_extension_seams_and_all_direct_outputs_are_sinks(self) -> None:
        tui = self.root / "packages/tui/src/components/sample.ts"
        tui.parent.mkdir(parents=True, exist_ok=True)
        tui.write_text(
            textwrap.dedent(
                """
                const theme = { fg: (_role: string, value: string) => value };
                export class Selector {
                  private dirty: boolean;
                  constructor(dirty: boolean) { this.dirty = dirty; }
                  render(): string[] {
                    const parts = ["enter toggle", "1/2 enabled"];
                    return [this.dirty
                      ? theme.fg("dim", `  ${parts.join(" · ")} `) + theme.fg("warning", "(unsaved)")
                      : theme.fg("dim", `  ${parts.join(" · ")}`)];
                  }
                  renderSpacing(): string[] { return [this.dirty ? " " : "\\n"]; }
                }
                """
            ).lstrip(),
            encoding="utf-8",
        )
        interactive = self.root / "packages/coding-agent/src/modes/interactive/extra.ts"
        interactive.write_text(
            textwrap.dedent(
                """
                class Markdown { constructor(_value: string) {} }
                class ExpandableText { constructor(_value: string) {} }
                const hotkeys = `**Navigation**\n| Key | Action |`;
                const showExtensionSelector = (_title: string, _options: string[]) => undefined;
                const showInfo = (_message: string) => undefined;
                new Markdown(hotkeys.trim());
                new ExpandableText("Expandable header");
                showExtensionSelector("Summarize branch?", ["Default", "Custom"]);
                showInfo("Configured outside pi.");
                """
            ).lstrip(),
            encoding="utf-8",
        )
        cli = self.root / "packages/coding-agent/src/cli/sample.ts"
        cli.parent.mkdir(parents=True, exist_ok=True)
        cli.write_text(
            'process.stdout.write("CLI stdout visible");\n'
            'process.stderr.write("CLI stderr visible");\n'
            'console.log("CLI log visible");\n'
            'console.error("CLI error visible");\n'
            'console.warn("CLI warning visible");\n',
            encoding="utf-8",
        )

        for source in (tui, interactive, cli):
            subprocess.run(
                [str(self.root / "node_modules/.bin/tsx"), str(source)],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

        inventory = self.run_extractor()
        entries = inventory["entries"]
        inventory_text = json.dumps(inventory)
        for visible in [
            "**Navigation**", "Expandable header", "Summarize branch?",
            "Default", "Custom", "Configured outside pi.", "CLI stdout visible",
            "CLI stderr visible", "CLI log visible", "CLI error visible",
            "CLI warning visible", "(unsaved)",
        ]:
            self.assertIn(visible, inventory_text)
        tui_entries = [entry for entry in entries if entry["site"]["path"].startswith("packages/tui/src/")]
        self.assertGreaterEqual(len(tui_entries), 2)
        conditional_entries = [entry for entry in tui_entries if len(entry["branches"]) == 2]
        self.assertGreaterEqual(len(conditional_entries), 2)
        self.assertTrue(
            any(
                "enter toggle" in "".join(
                    segment.get("text", "") for segment in branch["segments"]
                )
                for entry in conditional_entries
                for branch in entry["branches"]
            ),
            "array join must preserve its fixed runtime text",
        )
        self.assertTrue(
            any(
                all(
                    segment["kind"] != "literal" or not segment["text"].strip()
                    for segment in branch["segments"]
                )
                for entry in conditional_entries
                for branch in entry["branches"]
            ),
            "whitespace-only presentation branch must remain an obligation",
        )

    def test_explicit_sink_contracts_cover_real_metadata_render_and_protocol_paths(self) -> None:
        slash = self.root / "packages/coding-agent/src/core/slash-commands.ts"
        slash.parent.mkdir(parents=True, exist_ok=True)
        slash.write_text(
            textwrap.dedent(
                """
                interface BuiltinSlashCommand { name: string; description: string; argumentHint?: string }
                export const BUILTIN_SLASH_COMMANDS: ReadonlyArray<BuiltinSlashCommand> = [
                  { name: "model", description: "Select model", argumentHint: "<provider/model>" },
                ];
                """
            ).lstrip(),
            encoding="utf-8",
        )
        print_mode = self.root / "packages/coding-agent/src/modes/print/print-mode.ts"
        print_mode.parent.mkdir(parents=True, exist_ok=True)
        print_mode.write_text(
            'const writeRawStdout = (_text: string) => undefined;\n'
            'writeRawStdout("print payload");\n',
            encoding="utf-8",
        )
        markdown = self.root / "packages/tui/src/components/markdown.ts"
        markdown.parent.mkdir(parents=True, exist_ok=True)
        markdown.write_text(
            textwrap.dedent(
                """
                const theme = { codeBlockBorder: (value: string) => value };
                export function renderMarkdown(): string[] {
                  const lines: string[] = [];
                  lines.push(theme.codeBlockBorder("```text"));
                  lines.push(theme.codeBlockBorder("```"));
                  return lines;
                }
                """
            ).lstrip(),
            encoding="utf-8",
        )
        settings = self.root / "packages/tui/src/components/settings-list.ts"
        settings.write_text(
            textwrap.dedent(
                """
                const theme = { hint: (value: string) => value };
                export function renderSettings(): string[] {
                  const lines: string[] = [];
                  lines.push(theme.hint("  No settings available"));
                  return lines;
                }
                """
            ).lstrip(),
            encoding="utf-8",
        )
        select_list = self.root / "packages/tui/src/components/select-list.ts"
        select_list.write_text(
            textwrap.dedent(
                """
                export interface SelectItem { value: string; label: string; description?: string }
                const theme = { noMatch: (value: string) => value };
                export class SelectList {
                  private readonly item: SelectItem;
                  constructor(item: SelectItem) { this.item = item; }
                  render(_width: number): string[] {
                    const lines: string[] = [];
                    lines.push(theme.noMatch("  No matching commands"));
                    lines.push(this.renderItem(this.item));
                    return lines;
                  }
                  private renderItem(item: SelectItem): string { return `${item.label} ${item.description ?? ""}`; }
                }
                """
            ).lstrip(),
            encoding="utf-8",
        )
        terminal = self.root / "packages/tui/src/terminal.ts"
        terminal.write_text(
            'const terminal = { write: (_value: string) => undefined };\n'
            'terminal.write("\\x1b[?2004h");\n',
            encoding="utf-8",
        )
        false_positive = self.root / "packages/coding-agent/src/modes/interactive/not-visible.ts"
        false_positive.write_text(
            'class DefaultResourceLoader { constructor(_value: object) {} }\n'
            'const addHintLine = (_lines: string[], _width: number) => undefined;\n'
            'new DefaultResourceLoader({});\n'
            'addHintLine([], 80);\n',
            encoding="utf-8",
        )

        inventory = self.run_extractor()
        entries = inventory["entries"]
        text = json.dumps(inventory)
        for expected in [
            "model", "Select model", "<provider/model>", "print payload",
            "```text", "```", "  No settings available", "  No matching commands",
        ]:
            self.assertIn(expected, text)
        self.assertNotIn("DefaultResourceLoader", [entry["site"]["kind"] for entry in entries])
        self.assertFalse(
            any(entry["site"]["path"].endswith("not-visible.ts") for entry in entries),
            "non-presentation names and non-string arguments are not sink contracts",
        )
        terminal_entry = next(
            entry
            for entry in entries
            if entry["site"]["path"] == "packages/tui/src/terminal.ts"
        )
        self.assertEqual("terminal-protocol", terminal_entry["sink"]["channel"])
        self.assertEqual(
            "printable-visible",
            next(
                entry
                for entry in entries
                if entry["site"]["path"].endswith("print-mode.ts")
            )["sink"]["channel"],
        )

        destination = self.root / "instrumented-explicit-contracts"
        instrumented_inventory = self.run_extractor("--instrument", str(destination))
        instrumented_slash = (
            destination / "packages/coding-agent/src/core/slash-commands.ts"
        ).read_text(encoding="utf-8")
        self.assertIn('{ name: "model", description: "Select model", argumentHint: "<provider/model>" }', instrumented_slash)
        self.assertNotRegex(instrumented_slash, r'name:\s*__cadrRenderDiff')
        self.assertNotRegex(instrumented_slash, r'description:\s*__cadrRenderDiff')
        self.assertNotRegex(instrumented_slash, r'argumentHint:\s*__cadrRenderDiff')
        runner = destination / "slash-runner.ts"
        runner.write_text(
            'import { BUILTIN_SLASH_COMMANDS } from "./packages/coding-agent/src/core/slash-commands.ts";\n'
            'import { SelectList } from "./packages/tui/src/components/select-list.ts";\n'
            'const command = BUILTIN_SLASH_COMMANDS.find((item) => item.name === "model");\n'
            'if (!command) throw new Error("command lookup changed");\n'
            'const description = `${command.argumentHint} — ${command.description}`;\n'
            'const rendered = new SelectList({ value: command.name, label: command.name, description }).render(80)[1];\n'
            'process.stdout.write(JSON.stringify({ matched: command.name, rendered }));\n',
            encoding="utf-8",
        )
        environment = os.environ.copy()
        environment["RENDER_DIFF_VISIBLE_SITES"] = "1"
        result = subprocess.run(
            [str(self.root / "node_modules/.bin/tsx"), str(runner)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        )
        self.assertEqual(0, result.returncode, result.stderr.decode())
        clean_stdout = re.sub(
            rb"\x1b\]777;cadr-visible-branch;phase=(?:begin|end);site=VS-[0-9a-f]{16};branch=B-[0-9a-f]{12}\x07",
            b"",
            result.stdout,
        )
        payload = json.loads(clean_stdout)
        self.assertEqual("model", payload["matched"], "metadata markers must not alter matching or dispatch values")
        metadata_entries = [
            entry
            for entry in instrumented_inventory["entries"]
            if entry["site"]["path"].endswith("slash-commands.ts")
        ]
        self.assertEqual(3, len(metadata_entries))
        for entry in metadata_entries:
            self.assertIn(f"site={entry['id']}", payload["rendered"])

    def test_local_assignment_append_trim_and_array_items_preserve_runtime_bytes(self) -> None:
        source = self.root / "packages/coding-agent/src/modes/interactive/dataflow.ts"
        source.write_text(
            textwrap.dedent(
                """
                const captured: string[] = [];
                class Markdown { constructor(value: string) { captured.push(value); } }
                let hotkeys = "\\n**Navigation**\\n";
                if (process.env.WITH_EXTENSIONS === "1") {
                  hotkeys += "\\n**Extensions**\\n";
                }
                let blank = "\\n";
                if (process.env.WITH_EXTENSIONS === "1") blank += "\\n";
                const blankValue = blank.trim();
                new Markdown(hotkeys.trim());
                new Markdown(blankValue);
                export { captured, blankValue };
                """
            ).lstrip(),
            encoding="utf-8",
        )
        rows = self.root / "packages/tui/src/components/assignment-rows.ts"
        rows.parent.mkdir(parents=True, exist_ok=True)
        rows.write_text(
            textwrap.dedent(
                """
                export function renderRows(): string[] {
                  const lines: string[] = [];
                  lines.push("first row", "second row");
                  return lines;
                }
                """
            ).lstrip(),
            encoding="utf-8",
        )
        destination = self.root / "instrumented-dataflow"
        inventory = self.run_extractor("--instrument", str(destination))
        dataflow_entry = next(
            entry
            for entry in inventory["entries"]
            if entry["site"]["path"].endswith("dataflow.ts")
        )
        self.assertEqual(2, len(dataflow_entry["branches"]))
        branch_text = [
            "".join(segment.get("text", "") for segment in branch["segments"])
            for branch in dataflow_entry["branches"]
        ]
        self.assertIn("**Navigation**", branch_text)
        self.assertIn("**Navigation**\n\n**Extensions**", branch_text)
        self.assertTrue(all(not value.startswith("\n") and not value.endswith("\n") for value in branch_text))

        row_entries = [
            entry
            for entry in inventory["entries"]
            if entry["site"]["path"].endswith("assignment-rows.ts")
        ]
        self.assertEqual(2, len(row_entries), "every pushed string is its own viewport-visible obligation")

        runner = destination / "dataflow-runner.ts"
        runner.write_text(
            'import { captured, blankValue } from "./packages/coding-agent/src/modes/interactive/dataflow.ts";\n'
            'if (blankValue !== "") throw new Error("choice instrumentation changed trim truthiness");\n'
            'process.stdout.write(captured[0] ?? "");\n',
            encoding="utf-8",
        )
        command = [str(self.root / "node_modules/.bin/tsx"), str(runner)]
        for enabled, expected in [
            (False, "**Navigation**"),
            (True, "**Navigation**\n\n**Extensions**"),
        ]:
            environment = os.environ.copy()
            environment["RENDER_DIFF_VISIBLE_SITES"] = "1"
            if enabled:
                environment["WITH_EXTENSIONS"] = "1"
            result = subprocess.run(
                command,
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=environment,
            )
            clean = re.sub(
                rb"\x1b\]777;cadr-visible-(?:choice=[^\x07]+|branch;phase=(?:begin|end);site=VS-[0-9a-f]{16};branch=B-[0-9a-f]{12})\x07",
                b"",
                result.stdout,
            ).decode()
            self.assertEqual(expected, clean)
            self.assertIn(f"site={dataflow_entry['id']}".encode(), result.stdout)

    def test_array_join_and_spread_are_closed_without_invalid_instrumentation(self) -> None:
        dataflow = self.root / "packages/coding-agent/src/modes/interactive/array-join.ts"
        dataflow.write_text(
            textwrap.dedent(
                """
                const captured: string[] = [];
                class Text { constructor(value: string) { captured.push(value); } }
                const theme = { fg: (_role: string, value: string) => value };
                const statusParts: string[] = [];
                if (process.env.TRUNCATED === "1") {
                  statusParts.push(theme.fg("warning", `Output truncated. Full output: ${process.env.OUTPUT_PATH}`));
                }
                new Text(statusParts.join("\n"));
                export { captured };
                """
            ).lstrip(),
            encoding="utf-8",
        )
        rows = self.root / "packages/tui/src/components/spread-rows.ts"
        rows.parent.mkdir(parents=True, exist_ok=True)
        rows.write_text(
            textwrap.dedent(
                """
                export function renderRows(): string[] {
                  const state: { lines: string[] } = { lines: ["spread row"] };
                  const lines: string[] = [];
                  lines.push(...state.lines);
                  return lines;
                }
                """
            ).lstrip(),
            encoding="utf-8",
        )
        destination = self.root / "instrumented-array-join"
        inventory = self.run_extractor("--instrument", str(destination))
        obligations = [
            (entry["id"], branch["id"])
            for entry in inventory["entries"]
            for branch in entry["branches"]
            if any(
                segment.get("kind") == "literal"
                and "Output truncated. Full output:" in segment.get("text", "")
                for segment in branch["segments"]
            )
        ]
        self.assertTrue(obligations, "array push -> conditional -> join must retain the warning text")
        runner = destination / "spread-runner.ts"
        runner.write_text(
            'import { renderRows } from "./packages/tui/src/components/spread-rows.ts";\n'
            'const rendered = renderRows().join("\\n");\n'
            'process.stdout.write(rendered);\n',
            encoding="utf-8",
        )
        environment = os.environ.copy()
        environment["RENDER_DIFF_VISIBLE_SITES"] = "1"
        result = subprocess.run(
            [str(self.root / "node_modules/.bin/tsx"), str(runner)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        )
        self.assertEqual(0, result.returncode, result.stderr.decode())
        clean = re.sub(
            rb"\x1b\]777;cadr-visible-branch;phase=(?:begin|end);site=VS-[0-9a-f]{16};branch=B-[0-9a-f]{12}\x07",
            b"",
            result.stdout,
        )
        self.assertEqual(b"spread row", clean)

    def test_instrumented_state_setter_preserves_empty_editor_exit_semantics(self) -> None:
        source = self.root / "packages/coding-agent/src/modes/interactive/editor-state.ts"
        source.write_text(
            textwrap.dedent(
                """
                export const editor = { value: "seed" };
                const setText = (value: string) => { editor.value = value; };
                function initialize(value: string): void { setText(value); }
                initialize("");
                export function canExit(): boolean {
                  return editor.value.length === 0 && !editor.value.trim();
                }
                """
            ).lstrip(),
            encoding="utf-8",
        )
        destination = self.root / "instrumented-editor-state"
        inventory = self.run_extractor("--instrument", str(destination))
        state_entry = next(
            entry
            for entry in inventory["entries"]
            if entry["site"]["path"].endswith("editor-state.ts")
        )
        runner = destination / "editor-state-runner.ts"
        runner.write_text(
            'import { canExit, editor } from "./packages/coding-agent/src/modes/interactive/editor-state.ts";\n'
            'if (!canExit()) throw new Error(`instrumented empty editor is not empty: ${JSON.stringify(editor.value)}`);\n'
            'process.stdout.write(`EMPTY:${editor.value.length}:${Boolean(editor.value.trim())}`);\n',
            encoding="utf-8",
        )
        environment = os.environ.copy()
        environment["RENDER_DIFF_VISIBLE_SITES"] = "1"
        result = subprocess.run(
            [str(self.root / "node_modules/.bin/tsx"), str(runner)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        )
        self.assertEqual(0, result.returncode, result.stderr.decode())
        self.assertEqual(b"EMPTY:0:false", result.stdout)
        self.assertNotIn(f"site={state_entry['id']}".encode(), result.stdout)

    def test_source_asset_inventory_is_fail_closed_and_locks_theme_roles(self) -> None:
        theme = self.root / "packages/coding-agent/src/modes/interactive/theme/dark.json"
        theme.parent.mkdir(parents=True, exist_ok=True)
        theme.write_text(
            json.dumps({"name": "dark", "vars": {"ink": "#ffffff"}, "colors": {"text": "ink"}, "export": {"pageBg": "#000000"}}),
            encoding="utf-8",
        )
        vendor = self.root / "packages/coding-agent/src/core/export-html/vendor/marked.min.js"
        vendor.parent.mkdir(parents=True, exist_ok=True)
        vendor.write_text("/*! marked fixture */", encoding="utf-8")
        inventory = self.run_extractor()
        assets = {item["path"]: item for item in inventory["sourceInventory"]}
        theme_item = assets["packages/coding-agent/src/modes/interactive/theme/dark.json"]
        self.assertEqual("terminal-theme", theme_item["kind"])
        self.assertEqual({"vars": ["ink"], "colors": ["text"], "export": ["pageBg"]}, theme_item["roles"])
        vendor_item = assets["packages/coding-agent/src/core/export-html/vendor/marked.min.js"]
        self.assertEqual("excluded-third-party-html-export-asset", vendor_item["kind"])
        self.assertIn("browser", vendor_item["reason"])

        unknown = self.root / "packages/tui/src/unclassified.svg"
        unknown.write_text("<svg/>", encoding="utf-8")
        result = subprocess.run(
            [str(self.root / "node_modules/.bin/tsx"), str(self.extractor), str(self.root), "deadbeef"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.assertNotEqual(0, result.returncode)
        self.assertIn("unclassified presentation source asset", result.stderr)


if __name__ == "__main__":
    unittest.main()
