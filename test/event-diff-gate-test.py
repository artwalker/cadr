#!/usr/bin/env python3

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "event-diff.py"


def load_module():
    spec = importlib.util.spec_from_file_location("event_diff", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class EventDiffGateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.event_diff = load_module()

    def test_exact_pointer_normalization_does_not_rewrite_payload_text(self):
        records = [
            {
                "type": "session",
                "sessionId": "session-actual",
                "timestamp": "2026-08-05T00:00:00.000Z",
                "product": "pi",
                "message": "pi session-actual 2026-08-05T00:00:00.000Z",
            }
        ]
        rules = [
            {"pointer": "/0/sessionId", "replacement": "<SESSION_ID>"},
            {"pointer": "/0/timestamp", "replacement": "<TIMESTAMP>"},
            {"pointer": "/0/product", "replacement": "<PRODUCT>"},
        ]

        normalized, trace = self.event_diff.normalize_records(records, rules)

        self.assertEqual(normalized[0]["sessionId"], "<SESSION_ID>")
        self.assertEqual(normalized[0]["timestamp"], "<TIMESTAMP>")
        self.assertEqual(normalized[0]["product"], "<PRODUCT>")
        self.assertEqual(
            normalized[0]["message"],
            "pi session-actual 2026-08-05T00:00:00.000Z",
        )
        self.assertEqual(
            [entry["pointer"] for entry in trace],
            ["/0/sessionId", "/0/timestamp", "/0/product"],
        )

    def test_jsonl_comparison_is_recursive_and_reports_exact_pointer(self):
        expected = [{"type": "message_update", "assistantMessageEvent": {"delta": " 12"}}]
        actual = [{"type": "message_update", "assistantMessageEvent": {"delta": "12"}}]

        differences = self.event_diff.compare_records(expected, actual)

        self.assertEqual(len(differences), 1)
        self.assertEqual(differences[0]["pointer"], "/0/assistantMessageEvent/delta")
        self.assertEqual(differences[0]["kind"], "value-mismatch")

    def test_raw_artifact_preserves_bytes_and_records_sha256(self):
        payload = b'{"type":"agent_start"}\n{"type":"agent_end"}\n'
        with tempfile.TemporaryDirectory() as temp_dir:
            metadata = self.event_diff.write_raw_artifact(
                Path(temp_dir), "normal", "json", "pi", payload
            )
            raw_path = Path(temp_dir) / metadata["path"]

            self.assertEqual(raw_path.read_bytes(), payload)
            self.assertEqual(metadata["sha256"], hashlib.sha256(payload).hexdigest())
            self.assertEqual(metadata["bytes"], len(payload))

    def test_dispositions_are_exact_and_fail_closed(self):
        difference = {
            "scenario": "normal",
            "mode": "json",
            "ordinal": 3,
            "pointer": "/3/product",
            "kind": "value-mismatch",
            "expected_sha256": hashlib.sha256(b'"pi"').hexdigest(),
            "actual_sha256": hashlib.sha256(b'"cadr"').hexdigest(),
        }
        valid = {
            "baselineCommit": "4e58f324fae8ebfa98a3d45181fb248072a2afac",
            "entries": [
                {
                    **difference,
                    "disposition": "approved-difference",
                    "reason": "Product identity is intentionally cadr.",
                }
            ],
        }

        result = self.event_diff.apply_dispositions(
            [difference], valid, "4e58f324fae8ebfa98a3d45181fb248072a2afac"
        )
        self.assertEqual(result["unresolved"], [])
        self.assertEqual(len(result["resolved"]), 1)
        self.assertEqual(result["blocking"], [])

        wildcard = json.loads(json.dumps(valid))
        wildcard["entries"][0]["pointer"] = "*"
        with self.assertRaisesRegex(ValueError, "wildcard"):
            self.event_diff.apply_dispositions(
                [difference], wildcard, "4e58f324fae8ebfa98a3d45181fb248072a2afac"
            )

        stale = json.loads(json.dumps(valid))
        stale["entries"][0]["actual_sha256"] = "0" * 64
        stale_result = self.event_diff.apply_dispositions(
            [difference], stale, "4e58f324fae8ebfa98a3d45181fb248072a2afac"
        )
        self.assertEqual(stale_result["resolved"], [])
        self.assertEqual(stale_result["unresolved"], [difference])

        known_bug = json.loads(json.dumps(valid))
        known_bug["entries"][0]["disposition"] = "cadr-bug"
        bug_result = self.event_diff.apply_dispositions(
            [difference], known_bug, "4e58f324fae8ebfa98a3d45181fb248072a2afac"
        )
        self.assertEqual(len(bug_result["blocking"]), 1)

    def test_scenario_matrix_covers_every_required_path_in_both_modes(self):
        scenarios = json.loads(
            (ROOT / "test" / "fixtures" / "event-diff" / "scenarios.json").read_text()
        )

        self.event_diff.validate_scenario_matrix(scenarios)
        names = {scenario["name"] for scenario in scenarios["scenarios"]}
        self.assertEqual(
            names,
            {
                "normal",
                "transient-retry",
                "deterministic-error",
                "abort",
                "manual-compaction",
                "summarization-transient-retry",
                "threshold-compaction",
                "overflow-compaction",
                "tool-failure",
                "tool-call-error-sidecar",
            },
        )
        for scenario in scenarios["scenarios"]:
            self.assertEqual(set(scenario["modes"]), {"json", "rpc"})

    def test_drivers_bind_real_serializers_and_modes(self):
        fixture_dir = ROOT / "test" / "fixtures" / "event-diff"
        pi_driver = (fixture_dir / "pi-driver.ts").read_text()
        cadr_driver = (fixture_dir / "cadr-driver.lisp").read_text()

        self.assertIn("runPrintMode", pi_driver)
        self.assertIn("runRpcMode", pi_driver)
        self.assertIn("JSON.stringify(event)", pi_driver)
        self.assertIn("cadr-cli::run-print-mode", cadr_driver)
        self.assertIn("cadr-cli::run-rpc-mode", cadr_driver)
        self.assertIn("cadr-cli::make-json-event-renderer", cadr_driver)
        self.assertRegex(cadr_driver, r"\(apply\s+#'cadr-ai:faux-stream")
        self.assertNotIn("(defun aligned-faux-stream", cadr_driver)

    def test_normalization_rules_reject_unknown_matrix_coordinates_globally(self):
        fixture_dir = ROOT / "test" / "fixtures" / "event-diff"
        manifest = json.loads((fixture_dir / "scenarios.json").read_text())
        valid = {
            "rules": [
                {
                    "scenario": "normal",
                    "mode": "json",
                    "side": "pi",
                    "pointer": "/0/timestamp",
                    "replacement": "<TIMESTAMP>",
                    "reason": "fixed test rule",
                }
            ]
        }
        self.event_diff.validate_normalization_rules(valid, manifest)

        for field, value in (
            ("scenario", "does-not-exist"),
            ("mode", "screen"),
            ("side", "other"),
        ):
            invalid = json.loads(json.dumps(valid))
            invalid["rules"][0][field] = value
            with self.subTest(field=field):
                with self.assertRaisesRegex(ValueError, field):
                    self.event_diff.validate_normalization_rules(invalid, manifest)

    def test_checked_in_normalizers_are_exact_volatile_fields_only(self):
        fixture_dir = ROOT / "test" / "fixtures" / "event-diff"
        rules = json.loads((fixture_dir / "normalization-rules.json").read_text())["rules"]
        dispositions = json.loads((fixture_dir / "dispositions.json").read_text())

        self.assertEqual(len(rules), 40)
        self.assertEqual(dispositions["entries"], [])
        for rule in rules:
            self.assertIn(
                rule["pointer"],
                {
                    "/0/timestamp",
                    "/1/result/firstKeptEntryId",
                    "/2/result/firstKeptEntryId",
                    "/2/data/firstKeptEntryId",
                    "/4/result/firstKeptEntryId",
                    "/5/result/firstKeptEntryId",
                    "/5/data/firstKeptEntryId",
                    "/10/result/firstKeptEntryId",
                    "/13/result/firstKeptEntryId",
                },
            )
            self.assertNotIn("*", rule["pointer"])
            self.assertNotIn("?", rule["pointer"])
            self.assertIn(rule["side"], {"pi", "cadr"})

    def test_message_update_wire_projection_strips_snapshot(self):
        """Baseline modes/json-event.ts toJsonEvent emits only
        assistantMessageEvent on message_update; a cumulative `message`
        snapshot on every delta diverges from the wire contract."""
        print_source = (ROOT / "src" / "cadr-cli" / "modes" / "print.lisp").read_text()
        message_update_branch = print_source.split("(:message-update")[1].split("(:turn-end")[0]

        self.assertIn("assistantMessageEvent", message_update_branch)
        self.assertNotIn('"message"', message_update_branch)
        self.assertIn("remhash", message_update_branch)


if __name__ == "__main__":
    unittest.main()
