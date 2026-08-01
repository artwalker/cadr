#!/usr/bin/env python3
import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "goal11_performance_gate",
    ROOT / "scripts" / "goal11-performance-gate.py",
)
assert SPEC is not None and SPEC.loader is not None
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)


def point(*, latency=4_000, allocation=1_000_000, throughput=None):
    value = {
        "n": 5000,
        "median_us": latency,
        "median_bytes": allocation,
    }
    if throughput is not None:
        value["delta_per_second"] = throughput
    return value


def valid_report():
    return {
        "metrics": {
            "frame_render": {"points": [point()]},
            "key_to_frame": {"points": [point()]},
            "stream_delta_to_frame": {
                "points": [point(throughput=100)]
            },
            "mouse_drag_to_frame": {"points": [point()]},
            "wheel_to_frame": {"points": [point()]},
            "append_entry": {
                "scaling": {"log_log_exponent": 0.0},
            },
        },
        "continuous_alt_input": {
            "event_count": 1024,
            "p99_us": 50_000,
            "gc_affected_max_us": 80_000,
            "gc_affected_event_count": 1,
            "total_bytes": 16 * 1024 * 1024,
            "nursery_bytes": 8 * 1024 * 1024,
        },
        "cold_start": {"median_us": 150_000},
        "memory": {
            "points": [{"n": 5000, "heap_delta_bytes": 1_000_000}]
        },
    }


class ContinuousInputGateTest(unittest.TestCase):
    def failures(self, mutate=None):
        report = valid_report()
        if mutate is not None:
            mutate(report)
        failures = []
        GATE.check_bench(report, failures)
        return failures

    def test_valid_report_passes(self):
        self.assertEqual([], self.failures())

    def test_every_continuous_input_budget_is_enforced(self):
        cases = [
            (
                "mouse drag-to-frame exceeds 50ms",
                lambda report: report["metrics"]["mouse_drag_to_frame"][
                    "points"
                ][0].update(median_us=50_001),
            ),
            (
                "wheel-to-frame exceeds 50ms",
                lambda report: report["metrics"]["wheel_to_frame"]["points"][
                    0
                ].update(median_us=50_001),
            ),
            (
                "mouse drag allocates more than 16MiB",
                lambda report: report["metrics"]["mouse_drag_to_frame"][
                    "points"
                ][0].update(median_bytes=16 * 1024 * 1024 + 1),
            ),
            (
                "wheel event allocates more than 16MiB",
                lambda report: report["metrics"]["wheel_to_frame"]["points"][
                    0
                ].update(median_bytes=16 * 1024 * 1024 + 1),
            ),
            (
                "did not record exactly 1024 events",
                lambda report: report["continuous_alt_input"].update(
                    event_count=1023
                ),
            ),
            (
                "p99 exceeds 150ms",
                lambda report: report["continuous_alt_input"].update(
                    p99_us=150_001
                ),
            ),
            (
                "GC-affected event exceeds 500ms",
                lambda report: report["continuous_alt_input"].update(
                    gc_affected_max_us=500_001
                ),
            ),
            (
                "allocated a nursery without observing GC",
                lambda report: report["continuous_alt_input"].update(
                    gc_affected_event_count=0
                ),
            ),
        ]
        for expected, mutate in cases:
            with self.subTest(expected=expected):
                failures = self.failures(mutate)
                self.assertTrue(
                    any(expected in failure for failure in failures), failures
                )


if __name__ == "__main__":
    unittest.main()
