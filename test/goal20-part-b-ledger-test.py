#!/usr/bin/env python3
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_script(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(
        name, ROOT / "scripts" / filename
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ANCHOR = load_script("write_test_check_anchor", "write-test-check-anchor.py")
RECORD = load_script("record_paired_paths", "record-paired-paths.py")
LEDGER = load_script("write_performance_ledger", "write-performance-ledger.py")
HISTORY = load_script(
    "record_performance_history", "record-performance-history.py"
)


def run_main(module, argv: list[str]) -> int:
    import sys

    old = sys.argv
    try:
        sys.argv = argv
        return module.main()
    finally:
        sys.argv = old

SUMMARY = (
    "cadr test summary: systems=9 checks=17036 pass=17036 skip=0 fail=0"
)


def fake_cadr(*, quick: bool = True) -> dict:
    metrics: dict = {}
    for index, key in enumerate(RECORD.METRIC_KEYS):
        group, name = key.split(".", 1)
        metrics.setdefault(group, {})[name] = {
            "median_us": 1000.0 * (index + 1),
            "mad_us": 0.0,
        }
    return {
        "machine": {"machine_instance": "test-host"},
        "parameters": {"quick": quick, "samples": 1},
        "provenance": {
            "source_revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        },
        "metrics": metrics,
    }


def fake_summary(cadr: dict) -> dict:
    ratios = {}
    ceilings = {}
    for index, key in enumerate(RECORD.METRIC_KEYS):
        ratios[key] = 2.0 + index * 0.1
        ceilings[key] = 12.0
    return {
        "ceilings": ceilings,
        "failures": [],
        "notes": ["fixture-note"],
        "ratio_gate": "informational-quick-run",
        "ratios": ratios,
        "same_machine": True,
    }


class TestCheckAnchor(unittest.TestCase):
    def test_parse_summary_and_roundtrip_comment(self) -> None:
        fields = ANCHOR.parse_summary(SUMMARY)
        self.assertEqual(fields["systems"], 9)
        self.assertEqual(fields["checks"], 17036)
        self.assertEqual(fields["passed"], 17036)
        markdown = "# Title\n\nbody\n"
        updated = ANCHOR.apply_comment(markdown, fields)
        self.assertIn(ANCHOR.render_comment(fields), updated)
        self.assertEqual(ANCHOR.parse_comment(updated), fields)

    def test_strict_exits_one_on_drift_then_zero_when_stable(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            ledger = Path(temporary) / "test-matrix.md"
            ledger.write_text("# Title\n\nbody\n", encoding="utf-8")
            argv = [
                "write-test-check-anchor.py",
                "--summary",
                SUMMARY,
                "--ledger",
                str(ledger),
                "--strict",
            ]
            self.assertEqual(run_main(ANCHOR, argv), 1)
            self.assertEqual(run_main(ANCHOR, argv), 0)
            self.assertEqual(
                run_main(
                    ANCHOR,
                    [
                        "write-test-check-anchor.py",
                        "--verify",
                        "--summary",
                        SUMMARY,
                        "--ledger",
                        str(ledger),
                    ],
                ),
                0,
            )

    def test_refuses_implausible_check_drop(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            ledger = Path(temporary) / "test-matrix.md"
            ledger.write_text(
                "# Title\n\n"
                "<!-- GOAL20_TEST_CHECKS systems=9 checks=17036 pass=17036 skip=0 fail=0 -->\n",
                encoding="utf-8",
            )
            self.assertEqual(
                run_main(
                    ANCHOR,
                    [
                        "write-test-check-anchor.py",
                        "--summary",
                        "cadr test summary: systems=9 checks=27 pass=27 skip=0 fail=0",
                        "--ledger",
                        str(ledger),
                        "--strict",
                    ],
                ),
                2,
            )
            self.assertIn("17036", ledger.read_text(encoding="utf-8"))

    def test_verify_rejects_missing_comment(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            ledger = Path(temporary) / "test-matrix.md"
            ledger.write_text("# Title\n", encoding="utf-8")
            self.assertEqual(
                run_main(
                    ANCHOR,
                    [
                        "write-test-check-anchor.py",
                        "--verify",
                        "--ledger",
                        str(ledger),
                    ],
                ),
                2,
            )


class TestPairedPathRecord(unittest.TestCase):
    def test_sqlite_session_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("sqlite_session.open_walk", RECORD.METRIC_KEYS)
        self.assertIn("open_walk", paired.METRICS["sqlite_session"])
        self.assertIn("sqlite_session.open_walk", paired.RATIO_CEILINGS)
        self.assertIn("entry_count", paired.OBSERVED_EXACT["sqlite_session"])
        self.assertIn("leaf_id", paired.OBSERVED_EXACT["sqlite_session"])

    def test_build_entry_derives_baseline_from_ratio(self) -> None:
        cadr = fake_cadr()
        summary = fake_summary(cadr)
        entry = RECORD.build_entry(
            summary, cadr, recorded_at="2026-08-14T00:00:00Z"
        )
        self.assertEqual(entry["label"], "paired-paths-quick")
        self.assertTrue(entry["quick"])
        self.assertEqual(len(entry["metrics"]), 10)
        first = entry["metrics"][RECORD.METRIC_KEYS[0]]
        self.assertAlmostEqual(first["cadrMedianUs"], 1000.0)
        self.assertAlmostEqual(first["ratio"], 2.0)
        self.assertAlmostEqual(first["baselineMedianUs"], 500.0)

    def test_append_then_render_current_and_previous(self) -> None:
        cadr = fake_cadr()
        summary = fake_summary(cadr)
        with tempfile.TemporaryDirectory() as temporary:
            history_path = Path(temporary) / "paired.json"
            first = RECORD.build_entry(
                summary, cadr, recorded_at="2026-08-14T00:00:00Z"
            )
            RECORD.append_entry(history_path, first)
            second_summary = json.loads(json.dumps(summary))
            second_summary["ratios"]["storage_journal.journal_append"] = 1.5
            second = RECORD.build_entry(
                second_summary,
                fake_cadr(quick=False),
                recorded_at="2026-08-14T01:00:00Z",
            )
            history = RECORD.append_entry(history_path, second)
            section = LEDGER.render_paired_section(history)
            self.assertIn("GOAL20_PAIRED_PATHS_START", section)
            self.assertIn("`storage_journal.journal_append`", section)
            self.assertIn("`sqlite_session.open_walk`", section)
            self.assertIn("1.50×", section)
            self.assertIn("Previous:", section)
            self.assertIn("paired-paths-quick", section)
            markdown = "# Performance\n\nintro\n"
            markdown = LEDGER.replace_marked_section(
                markdown,
                LEDGER.PAIRED_START,
                LEDGER.PAIRED_END,
                section,
            )
            markdown = LEDGER.replace_marked_section(
                markdown,
                LEDGER.PAIRED_START,
                LEDGER.PAIRED_END,
                LEDGER.render_paired_section(history),
            )
            self.assertEqual(markdown.count("GOAL20_PAIRED_PATHS_START"), 1)


class TestNativeImageHistory(unittest.TestCase):
    def test_extract_omits_bytes_when_absent(self) -> None:
        row = HISTORY.extract(
            {
                "cold_start": {"median_us": 100.0},
                "metrics": {
                    "frame_render": {
                        "points": [{"n": 5000, "median_us": 1.0, "median_bytes": 2.0}]
                    }
                },
            }
        )
        self.assertNotIn("nativeImageBytes", row)
        self.assertNotEqual(row.get("nativeImageBytes"), 20_884_056)

    def test_extract_copies_stat_size_only(self) -> None:
        row = HISTORY.extract(
            {
                "cold_start": {"median_us": 100.0},
                "metrics": {
                    "frame_render": {
                        "points": [{"n": 5000, "median_us": 1.0, "median_bytes": 2.0}]
                    }
                },
            },
            native_image_bytes=20457848,
        )
        self.assertEqual(row["nativeImageBytes"], 20457848)

    def test_native_image_flag_stats_a_real_file(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            image = Path(temporary) / "cadr"
            image.write_bytes(b"x" * 4096)
            bench = Path(temporary) / "bench.json"
            history = Path(temporary) / "history.json"
            bench.write_text(
                json.dumps(
                    {
                        "label": "probe",
                        "cold_start": {"median_us": 100.0},
                        "metrics": {
                            "frame_render": {
                                "points": [
                                    {
                                        "n": 5000,
                                        "median_us": 1.0,
                                        "median_bytes": 2.0,
                                    }
                                ]
                            }
                        },
                    }
                ),
                encoding="utf-8",
            )
            self.assertEqual(
                run_main(
                    HISTORY,
                    [
                        "record-performance-history.py",
                        "--bench",
                        str(bench),
                        "--history",
                        str(history),
                        "--native-image",
                        str(image),
                    ],
                ),
                0,
            )
            stored = json.loads(history.read_text(encoding="utf-8"))
            self.assertEqual(stored["entries"][0]["nativeImageBytes"], 4096)

    def test_ledger_prints_emdash_when_bytes_missing(self) -> None:
        history = {
            "entries": [
                {
                    "recordedAt": "2026-08-14T00:00:00Z",
                    "label": "verify-isolated",
                    "gitHead": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                    "machine": "test-host",
                    "coldStartMedianUs": 100.0,
                    "frame5000MedianUs": 1.0,
                    "frame5000MedianBytes": 2.0,
                },
                {
                    "recordedAt": "2026-08-14T01:00:00Z",
                    "label": "verify-isolated",
                    "gitHead": "cccccccccccccccccccccccccccccccccccccccc",
                    "machine": "test-host",
                    "coldStartMedianUs": 110.0,
                    "nativeImageBytes": 20457848,
                    "frame5000MedianUs": 1.0,
                    "frame5000MedianBytes": 2.0,
                },
            ]
        }
        section = LEDGER.render_section(history, None)
        self.assertIn("native image B", section)
        self.assertIn("| 100.0 | — | 1.0 |", section)
        self.assertIn("| 110.0 | 20,457,848 | 1.0 |", section)
        self.assertNotIn("20,884,056", section)


class TestSelfHistoryStillRenders(unittest.TestCase):
    def test_replace_keeps_surrounding_prose(self) -> None:
        history = {
            "entries": [
                {
                    "recordedAt": "2026-08-14T00:00:00Z",
                    "label": "verify-isolated",
                    "gitHead": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                    "machine": "test-host",
                    "coldStartMedianUs": 100.0,
                    "frame5000MedianUs": 1.0,
                    "frame5000MedianBytes": 2.0,
                }
            ]
        }
        markdown = "before\n\n" + LEDGER.render_section(history, None) + "after\n"
        rewritten = LEDGER.replace_section(
            markdown, LEDGER.render_section(history, None)
        )
        self.assertTrue(rewritten.startswith("before"))
        self.assertIn("after", rewritten)
        self.assertEqual(rewritten.count("GOAL20_PERF_HISTORY_START"), 1)


if __name__ == "__main__":
    unittest.main()
