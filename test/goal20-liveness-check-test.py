#!/usr/bin/env python3
"""Deterministic tests for the 12E-1 statistical liveness checker."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHECK = ROOT / "scripts/goal20-liveness-check.py"
THRESHOLDS = ROOT / "docs/benchmarks/goal20-liveness-thresholds.json"
MEASUREMENT = ROOT / "docs/benchmarks/goal20-liveness-measurement-2026-08-15.json"


class LivenessCheckTest(unittest.TestCase):
    def test_booked_thresholds_match_the_adjudicated_rule(self) -> None:
        booked = json.loads(THRESHOLDS.read_text(encoding="utf-8"))
        measured = json.loads(MEASUREMENT.read_text(encoding="utf-8"))
        self.assertEqual(booked["schemaVersion"], 1)
        self.assertEqual(booked["capturesPerCheck"], 3)
        self.assertEqual(booked["rule"], "max(10 * baseline_worst_ms, 500)")
        expected = {}
        for row in measured["rows"]:
            if row["side"] == "cadr":
                continue
            key = (row["scenario"], row["dimension"])
            expected[key] = max(int(round(10 * float(row["worst_ms"]))), 500)
        actual = {
            (row["scenario"], row["dimension"]): row["thresholdMs"]
            for row in booked["thresholds"]
        }
        self.assertEqual(actual, expected)
        ttt = actual[("liveness-ttt-agent-turn", "wide")]
        self.assertEqual(ttt, 2037)

    def test_synthetic_silence_fails_and_prints_the_gap_list(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            timing = root / "liveness-ttt-agent-turn.wide.cadr.timing.json"
            # 26s interior silence — the pre-fix P0-4 shape from add4d0ac3.
            timing.write_text(
                json.dumps([[0.0, 8], [0.08, 12], [26.089, 4096], [26.2, 20]])
                + "\n",
                encoding="ascii",
            )
            result = subprocess.run(
                [
                    sys.executable,
                    str(CHECK),
                    "--from-artifacts",
                    str(root),
                    "--scenario",
                    "liveness-ttt-agent-turn",
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
            )
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("liveness FAIL", result.stderr)
        self.assertIn("26009.0", result.stderr)
        self.assertIn("gaps_ms=", result.stderr)

    def test_healthy_rhythm_passes_the_booked_threshold(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            timing = root / "liveness-ttt-agent-turn.wide.cadr.timing.json"
            entries = [[i * 0.08, 16] for i in range(12)]
            timing.write_text(json.dumps(entries) + "\n", encoding="ascii")
            result = subprocess.run(
                [
                    sys.executable,
                    str(CHECK),
                    "--from-artifacts",
                    str(root),
                    "--scenario",
                    "liveness-ttt-agent-turn",
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("liveness PASS", result.stdout)

    def test_wrap_free_text_without_booked_scenario_is_rejected(self) -> None:
        result = subprocess.run(
            [sys.executable, str(CHECK), "--scenario", "not-a-scenario"],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("no booked N_i", result.stderr)


if __name__ == "__main__":
    unittest.main()
