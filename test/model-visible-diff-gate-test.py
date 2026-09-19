#!/usr/bin/env python3
"""Unit tests for scripts/model-visible-diff.py."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_module():
    path = ROOT / "scripts/model-visible-diff.py"
    spec = importlib.util.spec_from_file_location("model_visible_diff", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ModelVisibleDiffGateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = load_module()

    def test_harness_variant_differs_from_coding_agent_formatter(self) -> None:
        skill = {
            "name": "demo",
            "description": "Demo skill",
            "filePath": "/skills/demo/SKILL.md",
        }
        good = self.mod.format_skills_coding_agent(skill)
        broken = self.mod.format_skills_harness_variant(skill)
        self.assertNotEqual(good, broken)
        self.assertIn("Use the read tool", good)
        self.assertIn("Read the full skill file", broken)

    def test_custom_prompt_branch_keeps_the_trailing_cwd_newline(self) -> None:
        scenario = {
            "customPrompt": "Custom",
            "cwd": "/tmp/project",
            "selectedTools": ["read"],
            "skills": [],
            "contextFiles": [],
        }
        good = self.mod.format_custom_system_prompt(scenario)
        broken = self.mod.format_custom_system_prompt_broken(scenario)
        self.assertTrue(good.endswith("Current working directory: /tmp/project\n"))
        self.assertTrue(broken.endswith("Current working directory: /tmp/project"))
        self.assertNotEqual(good, broken)

    def test_compaction_prompt_validity_mutates_each_template(self) -> None:
        baseline = {
            "system": (
                self.mod.FIXTURES / "baseline-compaction-system-prompt.txt"
            ).read_text(encoding="utf-8"),
            "prompt": (
                self.mod.FIXTURES
                / "baseline-compaction-summarization-prompt.txt"
            ).read_text(encoding="utf-8"),
            "update": (
                self.mod.FIXTURES / "baseline-compaction-update-prompt.txt"
            ).read_text(encoding="utf-8"),
        }
        self.assertIn("ONLY output the structured summary.", baseline["system"])
        self.assertIn("Keep each section concise.", baseline["prompt"])
        self.assertIn("Keep each section concise.", baseline["update"])

    def test_tool_result_truncation_matches_baseline_marker(self) -> None:
        text = "a" * 2500
        got = self.mod.format_serialized_tool_result(text)
        self.assertTrue(got.startswith("[Tool result]: "))
        self.assertIn("\n\n[... 500 more characters truncated]", got)
        self.assertNotEqual(
            got,
            got.replace(
                "more characters truncated]",
                "more characters truncated!]",
                1,
            ),
        )

    def test_gate_passes_against_cadr_formatter(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cadr-mvd-") as temporary:
            code = self.mod.run_gate(Path(temporary))
            self.assertEqual(0, code)
            report = (Path(temporary) / "report.json").read_text(encoding="utf-8")
            self.assertIn('"ok": true', report)


if __name__ == "__main__":
    unittest.main()
