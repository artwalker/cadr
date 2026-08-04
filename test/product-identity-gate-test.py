#!/usr/bin/env python3
"""Deterministic regressions for the permanent product-identity gate."""

from __future__ import annotations

import hashlib
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]
CHECKER = REPOSITORY / "scripts" / "check-product-identity.py"
MANIFEST = REPOSITORY / "docs" / "product-identity-allowlist.json"
VERIFY = REPOSITORY / "scripts" / "verify.sh"


class ProductIdentityGateTest(unittest.TestCase):
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
        source: str,
        allow: list[dict[str, object]],
        expected_findings: int,
        opaque_files: list[dict[str, object]] | None = None,
    ) -> tuple[Path, Path]:
        root = directory / "project"
        for relative in ("src", "examples", "scripts", ".github"):
            (root / relative).mkdir(parents=True)
        (root / "src" / "example.lisp").write_text(source, encoding="utf-8")
        (root / "README.md").write_text("# Cadr\n", encoding="utf-8")
        (root / "CHANGELOG.md").write_text("# Changelog\n", encoding="utf-8")
        manifest = root / "docs" / "product-identity-allowlist.json"
        manifest.parent.mkdir(parents=True)
        manifest.write_text(
            json.dumps(
                {
                    "schema": 1,
                    "expected_findings": expected_findings,
                    "allow": allow,
                    "opaque_files": opaque_files or [],
                }
            ),
            encoding="utf-8",
        )
        return root, manifest

    def allowed_line(
        self,
        *,
        kind: str,
        token: str,
        line: str,
        occurrences: int = 1,
    ) -> dict[str, object]:
        return {
            "path": "src/example.lisp",
            "kind": kind,
            "token": token,
            "line": line,
            "occurrences": occurrences,
            "reason": "Exact fixture contract retained for baseline provenance.",
        }

    def test_real_repository_and_allowlist_pass_together(self) -> None:
        result = self.run_gate(REPOSITORY, MANIFEST)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRegex(
            result.stdout,
            r"Product identity gate: \d+ findings, \d+ exact dispositions",
        )
        self.assertIn("real tree and allowlist agree", result.stdout)

    def test_verify_runs_synthetic_and_real_identity_gates_before_tests(self) -> None:
        source = VERIFY.read_text(encoding="utf-8")
        self.assertIn('run_deterministic "product identity gate"', source)
        self.assertIn('test/product-identity-gate-test.py', source)
        self.assertIn('scripts/check-product-identity.py', source)
        self.assertIn('docs/product-identity-allowlist.json', source)
        self.assertLess(
            source.index('run_deterministic "product identity gate"'),
            source.index('run_deterministic "deterministic FiveAM"'),
        )

    def test_unregistered_pi_identity_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root, manifest = self.write_fixture(
                Path(temporary),
                source='(defparameter +user-agent+ "pi")\n',
                allow=[],
                expected_findings=0,
            )
            result = self.run_gate(root, manifest)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unapproved identity", result.stderr)
            self.assertIn("src/example.lisp", result.stderr)

    def test_exact_line_disposition_passes(self) -> None:
        line = '(defparameter +protocol+ "pi-messages")'
        with tempfile.TemporaryDirectory() as temporary:
            root, manifest = self.write_fixture(
                Path(temporary),
                source=f"{line}\n",
                allow=[self.allowed_line(kind="pi-token", token="pi", line=line)],
                expected_findings=1,
            )
            result = self.run_gate(root, manifest)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_same_token_on_a_different_line_fails_closed(self) -> None:
        approved = '(defparameter +protocol+ "pi-messages")'
        changed = '(defparameter +product-name+ "pi")'
        with tempfile.TemporaryDirectory() as temporary:
            root, manifest = self.write_fixture(
                Path(temporary),
                source=f"{changed}\n",
                allow=[
                    self.allowed_line(kind="pi-token", token="pi", line=approved)
                ],
                expected_findings=1,
            )
            result = self.run_gate(root, manifest)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unapproved identity", result.stderr)
            self.assertIn("stale disposition", result.stderr)

    def test_legacy_environment_name_is_a_distinct_finding(self) -> None:
        line = '(uiop:getenv "PI_OFFLINE")'
        with tempfile.TemporaryDirectory() as temporary:
            root, manifest = self.write_fixture(
                Path(temporary),
                source=f"{line}\n",
                allow=[
                    self.allowed_line(
                        kind="legacy-env", token="PI_OFFLINE", line=line
                    )
                ],
                expected_findings=1,
            )
            result = self.run_gate(root, manifest)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_upstream_organization_without_pi_repo_is_detected(self) -> None:
        line = '"https://github.com/badlogic/reference"'
        with tempfile.TemporaryDirectory() as temporary:
            root, manifest = self.write_fixture(
                Path(temporary),
                source=f"{line}\n",
                allow=[],
                expected_findings=0,
            )
            result = self.run_gate(root, manifest)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("upstream-org", result.stderr)
            self.assertIn("badlogic", result.stderr)

    def test_duplicate_wildcard_and_empty_reason_dispositions_are_rejected(self) -> None:
        line = '"pi"'
        base = self.allowed_line(kind="pi-token", token="pi", line=line)
        cases = (
            ([base, dict(base)], "duplicate disposition"),
            ([{**base, "path": "src/*"}], "exact repository-relative file"),
            ([{**base, "reason": ""}], "non-empty reason"),
        )
        for allow, expected in cases:
            with self.subTest(expected=expected), tempfile.TemporaryDirectory() as temporary:
                root, manifest = self.write_fixture(
                    Path(temporary),
                    source=f"{line}\n",
                    allow=allow,
                    expected_findings=1,
                )
                result = self.run_gate(root, manifest)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(expected, result.stderr)

    def test_opaque_file_requires_an_exact_digest(self) -> None:
        source = 'builtins = "pi"\n'
        digest = hashlib.sha256(source.encode()).hexdigest()
        opaque = [
            {
                "path": "src/example.lisp",
                "sha256": digest,
                "reason": "Exact vendored fixture bytes contain a language builtin.",
            }
        ]
        with tempfile.TemporaryDirectory() as temporary:
            root, manifest = self.write_fixture(
                Path(temporary),
                source=source,
                allow=[],
                expected_findings=0,
                opaque_files=opaque,
            )
            result = self.run_gate(root, manifest)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            (root / "src" / "example.lisp").write_text(
                'builtins = "pi tau"\n', encoding="utf-8"
            )
            result = self.run_gate(root, manifest)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("opaque file digest mismatch", result.stderr)


if __name__ == "__main__":
    unittest.main()
