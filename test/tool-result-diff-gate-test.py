#!/usr/bin/env python3
"""Unit contract for the fixed-baseline tool-result differential gate."""

from __future__ import annotations

import base64
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts/tool-result-diff.py"
SPEC = importlib.util.spec_from_file_location("cadr_tool_result_diff", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
TOOL_DIFF = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TOOL_DIFF)


class ToolResultDiffGateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.manifest_path = (
            ROOT / "test/fixtures/tool-result-diff/scenarios.json"
        )

    def test_manifest_pins_baseline_and_covers_every_builtin_outcome(self) -> None:
        manifest = TOOL_DIFF.load_manifest(self.manifest_path)
        self.assertEqual(
            manifest["baselineCommit"],
            "74caa2649f10ed71b4378ce69f5d9fbfd2466ca5",
        )
        self.assertEqual(
            manifest["builtinTools"],
            ["read", "bash", "edit", "write", "grep", "find", "ls"],
        )
        coverage = {
            (case["tool"], case["outcome"])
            for case in manifest["scenarios"]
        }
        for tool in manifest["builtinTools"]:
            self.assertIn((tool, "success"), coverage)
            self.assertIn((tool, "failure"), coverage)
        broken_pipe = [
            case
            for case in manifest["scenarios"]
            if case.get("contract") == "broken-pipe"
        ]
        self.assertEqual(len(broken_pipe), 1)
        self.assertEqual(broken_pipe[0]["tool"], "bash")

    def test_drivers_use_real_production_agent_wrappers(self) -> None:
        pi_driver = (
            ROOT / "test/fixtures/tool-result-diff/pi-driver.ts"
        ).read_text(encoding="utf-8")
        cadr_driver = (
            ROOT / "test/fixtures/tool-result-diff/cadr-driver.lisp"
        ).read_text(encoding="utf-8")
        self.assertIn("agentLoop(", pi_driver)
        self.assertIn("createAllTools(cwd)", pi_driver)
        self.assertNotIn(".execute(", pi_driver)
        self.assertIn("cadr-agent::execute-tool-batch", cadr_driver)
        self.assertIn("cadr-cli::make-all-coding-tools", cadr_driver)
        self.assertNotIn("cadr-ai:tool-executor", cadr_driver)

    def test_typed_full_output_path_is_the_only_normalization(self) -> None:
        path = "/tmp/fixed/full-output.txt"
        raw = {
            "isError": False,
            "content": [
                TOOL_DIFF.text_block(
                    f"prefix /tmp/untyped.txt\nFull output: {path}\nsuffix"
                )
            ],
            "typedFullOutputPath": path,
            "typedFullOutputSha256": "a" * 64,
        }
        normalized = TOOL_DIFF.normalize_result(raw)
        text = base64.urlsafe_b64decode(
            normalized["content"][0]["utf8Base64"] + "=="
        ).decode("utf-8")
        self.assertIn("/tmp/untyped.txt", text)
        self.assertIn("<FULL_OUTPUT_PATH>", text)
        self.assertNotIn(path, text)
        self.assertEqual(normalized["typedFullOutputSha256"], "a" * 64)

    def test_typed_path_normalization_fails_closed(self) -> None:
        path = "/tmp/fixed/full-output.txt"
        absent = {
            "isError": False,
            "content": [TOOL_DIFF.text_block("no path here")],
            "typedFullOutputPath": path,
            "typedFullOutputSha256": "b" * 64,
        }
        duplicate = {
            **absent,
            "content": [TOOL_DIFF.text_block(f"{path}\n{path}")],
        }
        with self.assertRaisesRegex(TOOL_DIFF.GateFailure, "exactly once"):
            TOOL_DIFF.normalize_result(absent)
        with self.assertRaisesRegex(TOOL_DIFF.GateFailure, "exactly once"):
            TOOL_DIFF.normalize_result(duplicate)

    def test_byte_level_comparison_detects_a_single_utf8_difference(self) -> None:
        expected = {
            "isError": False,
            "content": [TOOL_DIFF.text_block("中 🙂\n")],
        }
        actual = {
            "isError": False,
            "content": [TOOL_DIFF.text_block("中🙂\n")],
        }
        differences = TOOL_DIFF.compare_result("unicode", expected, actual)
        self.assertTrue(differences)
        self.assertIn("content", "\n".join(differences))

    def test_broken_pipe_contract_rejects_wrapper_noise_even_if_both_sides_match(self) -> None:
        result = {
            "isError": False,
            "content": [TOOL_DIFF.text_block("1\n2\nBroken pipe\n")],
        }
        with self.assertRaisesRegex(TOOL_DIFF.GateFailure, "broken-pipe noise"):
            TOOL_DIFF.validate_scenario_contract(
                {"id": "bash-broken-pipe", "contract": "broken-pipe"},
                result,
                result,
            )

    def test_declared_success_and_failure_are_checked_on_both_sides(self) -> None:
        success = {"isError": False, "content": [TOOL_DIFF.text_block("ok")]}
        failure = {"isError": True, "content": [TOOL_DIFF.text_block("bad")]}
        TOOL_DIFF.validate_scenario_contract(
            {"id": "ok", "outcome": "success"}, success, success
        )
        TOOL_DIFF.validate_scenario_contract(
            {"id": "bad", "outcome": "failure"}, failure, failure
        )
        with self.assertRaisesRegex(TOOL_DIFF.GateFailure, "expected isError=True"):
            TOOL_DIFF.validate_scenario_contract(
                {"id": "bad", "outcome": "failure"}, success, failure
            )

    def test_result_file_rejects_missing_and_duplicate_scenarios(self) -> None:
        expected = [
            {"id": "one"},
            {"id": "two"},
        ]
        with tempfile.TemporaryDirectory(prefix="cadr-tool-diff-test-") as temp:
            path = Path(temp) / "results.json"
            path.write_text(
                json.dumps({"results": [{"scenarioId": "one"}]}),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(TOOL_DIFF.GateFailure, "result matrix"):
                TOOL_DIFF.load_result_file(path, expected, "pi")
            path.write_text(
                json.dumps(
                    {
                        "results": [
                            {"scenarioId": "one"},
                            {"scenarioId": "one"},
                            {"scenarioId": "two"},
                        ]
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(TOOL_DIFF.GateFailure, "duplicate"):
                TOOL_DIFF.load_result_file(path, expected, "pi")


if __name__ == "__main__":
    unittest.main()
