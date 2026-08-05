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
        self.assertEqual(2, inventory["schemaVersion"])
        self.assertIn(
            "heuristic closure",
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

        text_entry = entries[0]
        self.assertEqual(2, len(text_entry["branches"]))
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
            ["Hello  friend  continue", "Hello  stranger  continue"],
            branch_literals,
        )
        for branch in text_entry["branches"]:
            self.assertEqual(2, sum(segment["kind"] == "slot" for segment in branch["segments"]))
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

    def test_instrumentation_is_local_zero_width_and_opt_in(self) -> None:
        destination = self.root / "instrumented"
        inventory = self.run_extractor("--instrument", str(destination))
        instrumented = destination / "packages/coding-agent/src/modes/interactive/sample.ts"
        source = instrumented.read_text(encoding="utf-8")
        self.assertEqual(1, source.count("function __cadrRenderDiffVisibleSite_"))
        self.assertEqual(1, source.count("function __cadrRenderDiffVisibleChoice_"))
        self.assertEqual(1, source.count("cadr-visible-branch;site="))
        self.assertEqual(2, source.count("cadr-visible-choice="))
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
                f"\x1b]777;cadr-visible-branch;site={entry['id']};"
                f"branch={selected_branch['id']}\x07"
            )
            self.assertIn(marker, enabled_stream)
            for branch in entry["branches"]:
                if branch is selected_branch:
                    continue
                self.assertNotIn(f"branch={branch['id']}", enabled_stream)

        clean_enabled = re.sub(
            r"\x1b\]777;cadr-visible-branch;site=VS-[0-9a-f]{16};branch=B-[0-9a-f]{12}\x07",
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
            r"\x1b\]777;cadr-visible-branch;site=VS-[0-9a-f]{16};branch=B-[0-9a-f]{12}\x07",
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
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        )
        stream = result.stdout.decode("ascii")
        self.assertEqual(b"", result.stderr)
        self.assertIn(f"site={inventory['entries'][0]['id']}", stream)
        for entry in inventory["entries"][1:]:
            self.assertNotIn(f"site={entry['id']}", stream)

    def test_tui_string_array_provenance_reaches_terminal_emission(self) -> None:
        source = self.root / "packages/tui/src/rows.ts"
        source.write_text(
            'export function renderRows(): string[] { return ["first row", "second row"]; }\n',
            encoding="utf-8",
        )
        destination = self.root / "instrumented-rows"
        inventory = self.run_extractor("--instrument", str(destination))
        row_entry = next(
            entry for entry in inventory["entries"]
            if entry["site"]["path"] == "packages/tui/src/rows.ts"
        )
        runner = destination / "rows-runner.ts"
        runner.write_text(
            'import { renderRows } from "./packages/tui/src/rows.ts";\n'
            'process.stdout.write(renderRows().join("\\n"));\n',
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
        self.assertTrue(result.stdout.endswith(b"first row\nsecond row"))

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
                  render(): string {
                    const parts = ["enter toggle", "1/2 enabled"];
                    return this.dirty
                      ? theme.fg("dim", `  ${parts.join(" · ")} `) + theme.fg("warning", "(unsaved)")
                      : theme.fg("dim", `  ${parts.join(" · ")}`);
                  }
                  renderSpacing(): string { return this.dirty ? " " : "\\n"; }
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
                any(
                    segment["kind"] == "slot" and segment["expression"] == 'parts.join(" · ")'
                    for segment in branch["segments"]
                )
                for entry in conditional_entries
                for branch in entry["branches"]
            ),
            "dynamic-only clean branch must remain an obligation",
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
