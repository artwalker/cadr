#!/usr/bin/env python3
"""Goal 21 task 2: lock v0.84.2→v0.84.3 enumeration and source-parity dispositions."""
from __future__ import annotations

import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FROM = "914cf1472e715297caa30db4b9535d534a9eb718"
TO = "4e58f324fae8ebfa98a3d45181fb248072a2afac"
PI_REPO = Path("/root/projects/pi-mono")
FIXTURE_DIR = ROOT / "test/fixtures/source-parity"
DISPOSITIONS = FIXTURE_DIR / "g21-0843-dispositions.tsv"
ENUMERATION = FIXTURE_DIR / "g21-0843-enumeration.json"
UPGRADE_DOC = ROOT / "docs/source-parity-upgrade.md"
LEDGER = ROOT / "docs/source-parity.md"
MANIFEST_SHA = "ef4f653f95a0e5e7a86d9dc79efffa7a1f576529e9976dc2f70845bda44ea355"


def run(cmd: list[str], *, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=cwd or ROOT,
        check=True,
        text=True,
        capture_output=True,
    )


class Goal21SourceParityTest(unittest.TestCase):
    def test_enumerate_baseline_diff_matches_fixture(self) -> None:
        expected = json.loads(ENUMERATION.read_text(encoding="utf-8"))
        proc = run(
            ["python3", "scripts/enumerate-baseline-diff.py", FROM, TO],
        )
        report = json.loads(proc.stdout)
        for label in (
            "slashCommands",
            "settingsKeys",
            "extensionEvents",
            "environmentVariables",
            "toolFiles",
        ):
            with self.subTest(label=label):
                self.assertEqual(report[label], expected[label])
        self.assertEqual(
            report["publicApiExportCount"],
            expected["publicApiExportCount"],
        )

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
        self.assertIn("Source parity dispositions complete: 10", proc.stdout)

    def test_upgrade_doc_records_v0843_enumeration(self) -> None:
        text = UPGRADE_DOC.read_text(encoding="utf-8")
        self.assertIn("### v0.84.3 enumeration result", text)
        self.assertIn("914cf1472", text)
        self.assertIn("v0.84.3", text)
        self.assertIn("slash commands", text)
        self.assertIn("`thinking`", text)
        self.assertIn("modelThinkingLevels", text)
        self.assertIn("session_compact_failed", text)
        self.assertIn("powershell.ts", text)
        self.assertIn("g21-0843-dispositions.tsv", text)

    def test_source_ledger_records_v0843_upgrade_lock(self) -> None:
        text = UPGRADE_DOC.read_text(encoding="utf-8")
        self.assertIn("### v0.84.3 enumeration result", text)
        self.assertIn("g21-0843-dispositions.tsv", text)
        ledger = LEDGER.read_text(encoding="utf-8")
        self.assertIn("| `packages/coding-agent/src/core/tools/powershell.ts` |", ledger)


if __name__ == "__main__":
    unittest.main()
