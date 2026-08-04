#!/usr/bin/env python3
"""Deterministic orchestration tests for the fixed-baseline render gate."""

from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts/render-diff.py"
SPEC = importlib.util.spec_from_file_location("cadr_render_diff", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
RENDER_DIFF = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RENDER_DIFF)


class RenderDiffGateTest(unittest.TestCase):
    def arguments(self, output: Path) -> argparse.Namespace:
        return argparse.Namespace(
            manifest=ROOT / "test/fixtures/render-diff/scenarios.json",
            dispositions=ROOT / "test/fixtures/render-diff/dispositions.json",
            pi_repo=ROOT,
            output=output,
            analysis_output=output / "analysis",
            baseline_cache=Path("/tmp/unused-render-diff-baseline"),
            timeout=20.0,
        )

    def test_gate_captures_every_manifest_pair_before_real_analysis(self) -> None:
        manifest = RENDER_DIFF.load_manifest(
            ROOT / "test/fixtures/render-diff/scenarios.json"
        )
        expected = [
            (scenario["id"], dimension["id"], "both")
            for dimension in manifest["dimensions"]
            for scenario in manifest["scenarios"]
        ]
        calls: list[tuple[str, str, str]] = []
        caches: list[Path] = []

        def record_capture(arguments: argparse.Namespace) -> int:
            calls.append((arguments.scenario, arguments.dimension, arguments.side))
            caches.append(arguments.cadr_cache)
            return 0

        with tempfile.TemporaryDirectory(prefix="cadr-render-gate-test-") as temporary:
            arguments = self.arguments(Path(temporary) / "captures")
            with mock.patch.object(RENDER_DIFF, "capture", side_effect=record_capture), mock.patch.object(
                RENDER_DIFF, "analyze", return_value=0
            ) as analyze:
                self.assertEqual(RENDER_DIFF.gate(arguments), 0)

        self.assertEqual(calls, expected)
        self.assertEqual(len(calls), 24)
        self.assertEqual(len(set(caches)), 1)
        self.assertEqual(caches[0], arguments.output.resolve() / ".cadr-cache")
        analyze.assert_called_once_with(arguments)

    def test_gate_never_analyzes_an_incomplete_capture_matrix(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cadr-render-gate-test-") as temporary:
            arguments = self.arguments(Path(temporary) / "captures")
            with mock.patch.object(
                RENDER_DIFF,
                "capture",
                side_effect=RENDER_DIFF.HarnessFailure("capture stopped"),
            ), mock.patch.object(RENDER_DIFF, "analyze") as analyze:
                with self.assertRaisesRegex(RENDER_DIFF.HarnessFailure, "capture stopped"):
                    RENDER_DIFF.gate(arguments)
        analyze.assert_not_called()


if __name__ == "__main__":
    unittest.main()
