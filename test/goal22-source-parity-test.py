#!/usr/bin/env python3
"""Goal 22: lock v0.84.3→v0.84.4 enumeration and the live source-parity ledger."""
from __future__ import annotations

import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FROM = "4e58f324fae8ebfa98a3d45181fb248072a2afac"
TO = "b79e4cc834970cca69daebffab7df1da7d1e52c4"
PI_REPO = Path("/root/projects/pi-mono")
FIXTURE_DIR = ROOT / "test/fixtures/source-parity"
DISPOSITIONS = FIXTURE_DIR / "g22-0844-dispositions.tsv"
ENUMERATION = FIXTURE_DIR / "g22-0844-enumeration.json"
UPGRADE_DOC = ROOT / "docs/source-parity-upgrade.md"
LEDGER = ROOT / "docs/source-parity.md"
MANIFEST_SHA = "ba7e18fcd8c057605ff826e85dd6394d69d48b3083a9dc6aa5522a9b81d50e11"


def run(cmd: list[str], *, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=cwd or ROOT,
        check=True,
        text=True,
        capture_output=True,
    )


class Goal22SourceParityTest(unittest.TestCase):
    def test_enumerate_baseline_diff_matches_fixture(self) -> None:
        expected = json.loads(ENUMERATION.read_text(encoding="utf-8"))
        proc = run(
            ["python3", "scripts/enumerate-baseline-diff.py", FROM, TO],
        )
        report = json.loads(proc.stdout)
        for label in (
            "settingsKeys",
            "extensionEvents",
            "environmentVariables",
            "rpcMethods",
        ):
            with self.subTest(label=label):
                self.assertEqual(report[label], expected[label])
        self.assertEqual(
            report["publicApiExportCount"],
            expected["publicApiExportCount"],
        )
        added = [
            path
            for path in report["files"]["added"]
            if not path.endswith(".test.ts") and "/test/" not in path
        ]
        self.assertEqual(added, expected["files"]["addedNonTest"])

    def test_source_parity_drift_dispositions_complete(self) -> None:
        if not PI_REPO.is_dir():
            self.skipTest(f"pi-mono checkout missing: {PI_REPO}")
        proc = run(
            [
                str(ROOT / "scripts/check-source-parity-drift.sh"),
                "--repo",
                str(PI_REPO),
                "--from",
                FROM,
                "--to",
                TO,
                "--dispositions",
                str(DISPOSITIONS),
            ],
        )
        self.assertIn("Source parity dispositions complete: 1", proc.stdout)

    def test_upgrade_doc_records_v0844_enumeration(self) -> None:
        text = UPGRADE_DOC.read_text(encoding="utf-8")
        self.assertIn("### v0.84.4 enumeration result", text)
        self.assertIn("4e58f324", text)
        self.assertIn("v0.84.4", text)
        self.assertIn("fullscreenCopyOnSelect", text)
        self.assertIn("ui_prompt_start", text)
        self.assertIn("clear_queue", text)
        self.assertIn("openrouter-reasoning-options.ts", text)
        self.assertIn("g22-0844-dispositions.tsv", text)

    def test_source_ledger_matches_v0844_manifest(self) -> None:
        text = LEDGER.read_text(encoding="utf-8")
        self.assertIn(
            "GOAL12_LEDGER baseline=b79e4cc834970cca69daebffab7df1da7d1e52c4 "
            "source=686/514/169/3",
            text,
        )
        self.assertIn("sorted 686-path manifest", text)
        self.assertIn(MANIFEST_SHA, text)
        self.assertIn("| **Total** | **686** | **514** | **169** | **3** |", text)
        self.assertIn(
            "| `packages/ai/scripts/openrouter-reasoning-options.ts` |",
            text,
        )

    def test_ledger_only_gate_passes(self) -> None:
        proc = run(
            [
                str(ROOT / "scripts/check-source-parity-drift.sh"),
                "--ledger-only",
                "--dispositions",
                str(LEDGER),
            ],
        )
        self.assertIn("Source parity ledger entries: 686", proc.stdout)
        self.assertIn(f"Source parity ledger path SHA-256: {MANIFEST_SHA}", proc.stdout)
        self.assertIn("Source parity ledger validation complete.", proc.stdout)


if __name__ == "__main__":
    unittest.main()
