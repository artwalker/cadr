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

    def test_source_ledger_matches_v0843_manifest(self) -> None:
        text = LEDGER.read_text(encoding="utf-8")
        self.assertIn(
            "GOAL12_LEDGER baseline=4e58f324fae8ebfa98a3d45181fb248072a2afac "
            "source=685/513/169/3",
            text,
        )
        self.assertIn("sorted 685-path manifest", text)
        self.assertIn(MANIFEST_SHA, text)
        self.assertIn("| **Total** | **685** | **513** | **169** | **3** |", text)
        for path in json.loads(ENUMERATION.read_text(encoding="utf-8"))[
            "files"
        ]["addedNonTest"]:
            with self.subTest(path=path):
                self.assertIn(f"| `{path}` |", text)
        removed = json.loads(ENUMERATION.read_text(encoding="utf-8"))["files"][
            "removedNonTest"
        ]
        for path in removed:
            with self.subTest(removed=path):
                self.assertNotIn(f"| `{path}` |", text)

    def test_ledger_only_gate_passes(self) -> None:
        proc = run(
            [
                str(ROOT / "scripts/check-source-parity-drift.sh"),
                "--ledger-only",
                "--dispositions",
                str(LEDGER),
            ],
        )
        self.assertIn("Source parity ledger entries: 685", proc.stdout)
        self.assertIn(f"Source parity ledger path SHA-256: {MANIFEST_SHA}", proc.stdout)
        self.assertIn("Source parity ledger validation complete.", proc.stdout)


if __name__ == "__main__":
    unittest.main()
