#!/usr/bin/env python3
"""Deterministic regressions for the permanent code-organization gate."""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]
CHECKER = REPOSITORY / "scripts" / "check-code-organization.py"


class CodeOrganizationGateTest(unittest.TestCase):
    def run_gate(self, root: Path, manifest: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                "python3",
                str(CHECKER),
                "--root",
                str(root),
                "--manifest",
                str(manifest),
            ],
            check=False,
            capture_output=True,
            text=True,
        )

    def write_fixture(
        self,
        directory: Path,
        *,
        source_lines: int,
        exemptions: list[dict[str, str]],
    ) -> tuple[Path, Path]:
        root = directory / "project"
        source = root / "src" / "example.lisp"
        source.parent.mkdir(parents=True)
        source.write_text("x\n" * source_lines, encoding="utf-8")
        manifest = root / "docs" / "code-organization-exemptions.json"
        manifest.parent.mkdir(parents=True)
        manifest.write_text(
            json.dumps(
                {
                    "schema": 1,
                    "threshold": {
                        "lines": 1000,
                        "comparison": "at-or-above",
                        "basis": (
                            "Part A isolated the audited 1000-plus-line band "
                            "as the manual-review boundary."
                        ),
                    },
                    "exemptions": exemptions,
                }
            ),
            encoding="utf-8",
        )
        return root, manifest

    def test_real_repository_and_manifest_pass_together(self) -> None:
        result = self.run_gate(
            REPOSITORY,
            REPOSITORY / "docs" / "code-organization-exemptions.json",
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("threshold >= 1000 lines", result.stdout)
        self.assertIn("20 reviewed exemptions", result.stdout)
        self.assertIn("symptom detector only", result.stdout)

    def test_exact_threshold_without_exemption_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root, manifest = self.write_fixture(
                Path(temporary), source_lines=1000, exemptions=[]
            )
            result = self.run_gate(root, manifest)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unreviewed oversized file", result.stderr)
            self.assertIn("src/example.lisp", result.stderr)

    def test_file_below_threshold_needs_no_exemption(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root, manifest = self.write_fixture(
                Path(temporary), source_lines=999, exemptions=[]
            )
            result = self.run_gate(root, manifest)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_exemption_requires_a_reason(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root, manifest = self.write_fixture(
                Path(temporary),
                source_lines=1000,
                exemptions=[{"path": "src/example.lisp", "reason": ""}],
            )
            result = self.run_gate(root, manifest)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("non-empty reason", result.stderr)

    def test_stale_exemption_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root, manifest = self.write_fixture(
                Path(temporary),
                source_lines=999,
                exemptions=[
                    {
                        "path": "src/example.lisp",
                        "reason": "Fixture was reviewed as one cohesive owner.",
                    }
                ],
            )
            result = self.run_gate(root, manifest)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("stale exemption", result.stderr)

    def test_duplicate_exemption_path_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root, manifest = self.write_fixture(
                Path(temporary),
                source_lines=1000,
                exemptions=[
                    {
                        "path": "src/example.lisp",
                        "reason": "First claimed owner reason.",
                    },
                    {
                        "path": "src/example.lisp",
                        "reason": "Conflicting second owner reason.",
                    },
                ],
            )
            result = self.run_gate(root, manifest)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("duplicate exemption path", result.stderr)


if __name__ == "__main__":
    unittest.main()
