#!/usr/bin/env python3
import importlib.util
import json
import subprocess
import tempfile
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

PROFILE_SPEC = importlib.util.spec_from_file_location(
    "goal13_session_scale_profile",
    ROOT / "scripts" / "goal13-session-scale-profile.py",
)
assert PROFILE_SPEC is not None and PROFILE_SPEC.loader is not None
PROFILE = importlib.util.module_from_spec(PROFILE_SPEC)
PROFILE_SPEC.loader.exec_module(PROFILE)


def point(*, latency=4_000, allocation=1_000_000, throughput=None):
    value = {
        "n": 5000,
        "median_us": latency,
        "mad_us": 0,
        "samples_us": [latency] * 5,
        "median_bytes": allocation,
        "mad_bytes": 0,
        "samples_bytes": [allocation] * 5,
    }
    if throughput is not None:
        value["delta_per_second"] = throughput
    return value


def paired_run(*, baseline=False, median_us=4_000, p95_us=5_000, p99_us=6_000):
    samples = [median_us] * 972 + [p95_us] * 41 + [p99_us] * 11
    run = {
        "event_count": 1024,
        "median_us": median_us,
        "p95_us": p95_us,
        "p99_us": p99_us,
        "max_us": p99_us,
        "event_trace_sha256": GATE.FIXED_CONTINUOUS_TRACE_SHA256,
        "event_trace_counts": {
            "drag": 342,
            "wheel_up": 341,
            "wheel_down": 341,
        },
        "terminal_sink": "count-only",
        "gc_mode": "runtime-default",
        "renderer_mode": "synchronous-requested-frame",
        "scheduler_mode": "production-request-immediate-flush",
        "rendered_frame_count": 1024,
        "final_selection_active": True,
        "initial_viewport_top": 100,
        "final_viewport_top": 100,
        "samples_us": samples,
    }
    run[
        "samples_retained_heap_delta_bytes" if baseline else "samples_bytes"
    ] = [1_000] * 1024
    run[
        "median_retained_heap_delta_bytes" if baseline else "median_bytes"
    ] = 1_000
    if baseline:
        run["retained_heap_delta_bytes_per_event"] = 250_000
        run["retained_heap_high_water_delta_bytes_per_event"] = 300_000
    return run


def common_run(kind, *, p99_us=6_000):
    samples = [4_000] * 972 + [5_000] * 41 + [p99_us] * 11
    counts = {
        "mouse_drag": {"drag": 1024},
        "wheel": {"wheel_up": 512, "wheel_down": 512},
        "editor_key": {"insert": 512, "backspace": 512},
    }[kind]
    run = {
        "input_kind": kind,
        "event_count": 1024,
        "median_us": 4_000,
        "p95_us": 5_000,
        "p99_us": p99_us,
        "max_us": p99_us,
        "median_bytes": 1_000,
        "total_bytes": 1_024_000,
        "gc_affected_event_count": 0,
        "gc_affected_max_us": 0,
        "gc_affected_samples_us": [],
        "nursery_bytes": 8 * 1024 * 1024,
        "rendered_frame_count": 1024,
        "event_trace_sha256": GATE.COMMON_TRACE_SHA256[kind],
        "event_trace_counts": counts,
        "terminal_sink": "count-only",
        "gc_mode": "forced-8mib-nursery",
        "renderer_mode": "synchronous-requested-frame",
        "scheduler_mode": "production-request-immediate-flush",
        "samples_us": samples,
        "samples_bytes": [1_000] * 1024,
    }
    if kind == "mouse_drag":
        run["final_selection_active"] = True
    elif kind == "wheel":
        run["initial_viewport_top"] = 100
        run["final_viewport_top"] = 100
    else:
        run["final_editor_text_length"] = 0
    return run


def sustained_run(*, p999_us=8_000, maximum_us=12_000):
    event_count = 10_800
    samples = [4_000] * (event_count - 12) + [p999_us] * 11 + [maximum_us]
    memory_samples = [
        {
            "elapsed_seconds": index * 10,
            "heap_bytes": 20_000_000 + min(index, 6) * 100_000,
            "rss_bytes": 70_000_000 + min(index, 6) * 100_000,
        }
        for index in range(19)
    ]
    return {
        "duration_seconds": 180,
        "target_event_hz": 60,
        "event_count": event_count,
        "rendered_frame_count": event_count,
        "event_trace_counts": {
            "drag": 2_700,
            "wheel_up": 2_700,
            "wheel_down": 2_700,
            "editor_key": 2_700,
        },
        "samples_us": samples,
        "p999_us": p999_us,
        "max_us": maximum_us,
        "gc_affected_event_count": 2,
        "gc_affected_samples_us": [7_000, 8_000],
        "gc_affected_max_us": 8_000,
        "gc_cpu_us": 2_000,
        "gc_frequency_per_minute": 2 * 60 / 180,
        "gc_pause_samples_us": [1_000, 2_000],
        "gc_pause_p999_us": 2_000,
        "gc_pause_max_us": 2_000,
        "gc_pause_measurement": (
            "sb-ext:*gc-run-time* delta; event wall latency is "
            "gc_affected_samples_us"
        ),
        "memory_samples": memory_samples,
        "memory_final_window_growth_bytes": 0,
        "memory_final_window_heap_growth_bytes": 0,
        "memory_final_window_rss_growth_bytes": 0,
        "memory_retained_heap_before_bytes": 20_000_000,
        "memory_retained_heap_after_bytes": 20_500_000,
        "memory_retained_heap_growth_bytes": 500_000,
        "memory_post_gc_rss_bytes": 70_600_000,
        "memory_post_gc_rss_growth_bytes": 600_000,
        "memory_converged": True,
        "terminal_sink": "count-only",
        "renderer_mode": "synchronous-requested-frame",
        "scheduler_mode": "paced-60hz-mixed-input",
        "gc_mode": "runtime-default",
        "actual_elapsed_seconds": 180.1,
    }


def session_scale_profile():
    return {
        "schema_version": 1,
        "kind": "cadr-anonymous-session-scale",
        "source_file_count": 10,
        "valid_session_count": 9,
        "invalid_session_count": 1,
        "entry_percentiles": {
            "min": 1,
            "p50": 42,
            "p90": 100,
            "p95": 120,
            "p99": 300,
            "max": 420,
        },
        "tiers": {
            "typical": 42,
            "common": 120,
            "heavy": 300,
            "stress": 5000,
        },
        "privacy": {
            "contains_message_content": False,
            "contains_session_identifiers": False,
            "contains_paths": False,
            "contains_timestamps": False,
            "contains_provider_or_model": False,
        },
    }


def valid_report():
    return {
        "schema_version": 1,
        "kind": "cadr-goal11-performance",
        "entry_counts": [0, 50, 200, 1000, 5000],
        "provenance": {
            "source_revision": "candidate",
            "renderer_object_id": "1" * 40,
        },
        "machine": {"machine_instance": "same-machine"},
        "parameters": {
            "width": 100,
            "height": 40,
            "continuous_events": 1024,
            "paired_fresh_fixture_per_run": True,
            "samples": 5,
            "warmups": 1,
        },
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
            "median_us": 50_000,
            "p99_us": 50_000,
            "max_us": 50_000,
            "median_bytes": 16_384,
            "gc_affected_max_us": 80_000,
            "gc_affected_event_count": 1,
            "gc_affected_samples_us": [80_000],
            "total_bytes": 16 * 1024 * 1024,
            "nursery_bytes": 8 * 1024 * 1024,
            "rendered_frame_count": 1024,
            "event_trace_sha256": GATE.FIXED_CONTINUOUS_TRACE_SHA256,
            "event_trace_counts": {
                "drag": 342,
                "wheel_up": 341,
                "wheel_down": 341,
            },
            "terminal_sink": "count-only",
            "gc_mode": "forced-8mib-nursery",
            "renderer_mode": "synchronous-requested-frame",
            "scheduler_mode": "production-request-immediate-flush",
            "samples_us": [50_000] * 1024,
            "samples_bytes": [16_384] * 1024,
        },
        "paired_continuous_alt_input": {
            "event_count": 1024,
            "median_us": 4_000,
            "median_run_mad_us": 0,
            "p95_us": 5_000,
            "p95_run_mad_us": 0,
            "p99_us": 6_000,
            "p99_run_mad_us": 0,
            "event_trace_sha256": GATE.FIXED_CONTINUOUS_TRACE_SHA256,
            "event_trace_counts": {
                "drag": 342,
                "wheel_up": 341,
                "wheel_down": 341,
            },
            "terminal_sink": "count-only",
            "gc_mode": "runtime-default",
            "renderer_mode": "synchronous-requested-frame",
            "scheduler_mode": "production-request-immediate-flush",
            "rendered_frame_count": 1024,
            "final_selection_active": True,
            "median_bytes": 1_000,
            "max_us": 6_000,
            "runs": [paired_run() for _ in range(5)],
        },
        "session_scale_profile": session_scale_profile(),
        "common_continuous_input": {
            "entry_count": 120,
            "event_count_per_kind": 1024,
            "mouse_drag": common_run("mouse_drag"),
            "wheel": common_run("wheel"),
            "editor_key": common_run("editor_key"),
        },
        "sustained_mixed_interaction": sustained_run(),
        "cold_start": {"median_us": 150_000},
        "memory": {
            "points": [{"n": 5000, "heap_delta_bytes": 1_000_000}]
        },
    }


def valid_baseline_report():
    return {
        "schema_version": 2,
        "kind": "pi-goal11-structural-baseline",
        "provenance": {
            "source_revision": (
                "ecac0a9c4edad3dac5d9f8b40e0c7db7a56471fc"
            ),
            "tracked_worktree_clean": True,
            "loaded_dist_tree_sha256": dict(GATE.FIXED_BASELINE_DIST_SHA256),
            "installed_dependency_tree_sha256": (
                GATE.FIXED_BASELINE_DEPENDENCY_TREE_SHA256
            ),
            **GATE.FIXED_BASELINE_OBJECT_IDS,
        },
        "machine": {"hostname": "same-machine"},
        "parameters": {
            "width": 100,
            "height": 40,
            "continuous_events": 1024,
            "paired_fresh_fixture_per_run": True,
            "entry_counts": [0, 50, 200, 1000, 5000],
            "samples": 5,
            "warmups": 1,
        },
        "metrics": {
            "mouse_drag_to_frame": {
                "points": [{
                    **point(latency=12_000),
                    "median_retained_heap_delta_bytes": 1_000_000,
                    "samples_retained_heap_delta_bytes": [1_000_000] * 5,
                    "sampled_allocated_bytes_per_event": 100_000,
                    "allocation_sample_event_count": 32,
                }]
            },
            "wheel_to_frame": {
                "points": [{
                    **point(latency=10_000),
                    "median_retained_heap_delta_bytes": 1_000_000,
                    "samples_retained_heap_delta_bytes": [1_000_000] * 5,
                    "sampled_allocated_bytes_per_event": 100_000,
                    "allocation_sample_event_count": 32,
                }]
            },
        },
        "continuous_alt_input": {
            "event_count": 1024,
            "median_us": 10_000,
            "median_run_mad_us": 0,
            "p95_us": 12_000,
            "p95_run_mad_us": 0,
            "p99_us": 15_000,
            "p99_run_mad_us": 0,
            "retained_heap_delta_bytes_per_event": 250_000,
            "retained_heap_high_water_delta_bytes_per_event": 300_000,
            "event_trace_sha256": GATE.FIXED_CONTINUOUS_TRACE_SHA256,
            "event_trace_counts": {
                "drag": 342,
                "wheel_up": 341,
                "wheel_down": 341,
            },
            "terminal_sink": "count-only",
            "gc_mode": "runtime-default",
            "renderer_mode": "synchronous-requested-frame",
            "scheduler_mode": "production-request-immediate-flush",
            "rendered_frame_count": 1024,
            "final_selection_active": True,
            "sampled_allocated_bytes_per_event": 1_000_000,
            "allocation_sample_event_count": 96,
            "median_retained_heap_delta_bytes": 1_000,
            "max_us": 15_000,
            "runs": [
                paired_run(
                    baseline=True,
                    median_us=10_000,
                    p95_us=12_000,
                    p99_us=15_000,
                )
                for _ in range(5)
            ],
        },
    }


class ContinuousInputGateTest(unittest.TestCase):
    def failures(self, mutate=None):
        report = valid_report()
        if mutate is not None:
            mutate(report)
        failures = []
        GATE.check_bench(report, failures, valid_baseline_report())
        return failures

    def test_valid_report_passes(self):
        self.assertEqual([], self.failures())

    def test_sustained_mixed_interaction_is_required_and_gated(self):
        self.assertTrue(
            any(
                "sustained mixed interaction" in failure
                for failure in self.failures(
                    lambda report: report.pop(
                        "sustained_mixed_interaction"
                    )
                )
            )
        )
        self.assertTrue(
            any(
                "sustained mixed interaction p99.9" in failure
                for failure in self.failures(
                    lambda report: report[
                        "sustained_mixed_interaction"
                    ].update(p999_us=100_001)
                )
            )
        )
        self.assertTrue(
            any(
                "sustained mixed interaction memory" in failure
                for failure in self.failures(
                    lambda report: report[
                        "sustained_mixed_interaction"
                    ].update(
                        memory_converged=False,
                        memory_final_window_growth_bytes=32 * 1024 * 1024,
                    )
                )
            )
        )

    def test_pacing_rechecks_clock_after_early_sleep_return(self):
        helper = ROOT / "scripts" / "goal11-pacing.lisp"
        expression = """
            (let ((now 0) (sleeps 0))
              (cadr-goal11-pacing:paced-wait-until
               100
               :clock-function (lambda () now)
               :sleep-function
               (lambda (seconds)
                 (declare (ignore seconds))
                 (incf sleeps)
                 (incf now (if (= sleeps 1) 30 70)))
               :time-units-per-second 100)
              (unless (and (= now 100) (= sleeps 2))
                (error "pacing stopped early: now=~D sleeps=~D"
                       now sleeps)))
        """
        result = subprocess.run(
            [
                "sbcl",
                "--noinform",
                "--disable-debugger",
                "--eval",
                f"(load {json.dumps(str(helper))})",
                "--eval",
                expression,
                "--quit",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertTrue(
            any(
                "sustained mixed interaction memory" in failure
                for failure in self.failures(
                    lambda report: report[
                        "sustained_mixed_interaction"
                    ].update(
                        memory_retained_heap_after_bytes=64_000_000,
                        memory_retained_heap_growth_bytes=44_000_000,
                        memory_converged=True,
                    )
                )
            )
        )

    def test_committed_fixed_baseline_artifact_passes_full_contract(self):
        path = ROOT / "docs" / "benchmarks" / "goal-v11-pi-baseline.json"
        self.assertEqual(
            GATE.FIXED_BASELINE_ARTIFACT_SHA256,
            GATE.file_sha256(path),
        )
        failures = []
        GATE.check_bench(valid_report(), failures, GATE.load_json(path))
        self.assertEqual([], failures)

    def test_goal13_checked_artifacts_are_complete_and_final_is_replayable(self):
        before_path = (
            ROOT / "docs" / "benchmarks" / "goal-v13-c3-before.json"
        )
        final_path = (
            ROOT / "docs" / "benchmarks" / "goal-v13-c3-final.json"
        )
        stability_path = (
            ROOT / "docs" / "benchmarks" / "goal-v11-stability.json"
        )
        for path in (before_path, final_path):
            with self.subTest(path=path.name):
                cold_start = GATE.load_json(path).get("cold_start")
                self.assertIsInstance(cold_start, dict)
                self.assertEqual(5, len(cold_start.get("samples_us", [])))
                self.assertGreater(cold_start.get("median_us", 0), 0)
        with tempfile.TemporaryDirectory() as temporary:
            # The artifact predates today's history rows; replayability is
            # judged against the fixed contract and ceilings, not against a
            # drift series it was never part of. An empty history keeps the
            # adjudicated drift gate in its no-prior-row informational state.
            empty_history = Path(temporary) / "history.json"
            empty_history.write_text(
                json.dumps({"schemaVersion": 1, "entries": []}), encoding="utf-8"
            )
            result = subprocess.run(
                [
                    "python3",
                    str(ROOT / "scripts" / "goal11-performance-gate.py"),
                    "--bench",
                    str(final_path),
                    "--stability",
                    str(stability_path),
                    "--history",
                    str(empty_history),
                ],
                capture_output=True,
                text=True,
                check=False,
            )
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("goal11 gate: PASS", result.stdout)

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

    def test_common_tier_absolute_contract_is_separate_and_exact(self):
        for kind in ("mouse_drag", "wheel", "editor_key"):
            with self.subTest(kind=kind):
                failures = self.failures(
                    lambda report, current=kind: report[
                        "common_continuous_input"
                    ][current].update(p99_us=16_001)
                )
                expected = (
                    "absolute interaction target: common "
                    f"{kind} p99 exceeds 16ms"
                )
                self.assertTrue(
                    any(expected in failure for failure in failures), failures
                )
                self.assertFalse(
                    any("fixed baseline regression" in failure
                        for failure in failures),
                    failures,
                )

        contract_cases = [
            (
                "anonymous session scale profile contract differs",
                lambda report: report["session_scale_profile"]["privacy"].update(
                    contains_paths=True
                ),
            ),
            (
                "common tier does not match the anonymous p95 session scale",
                lambda report: report["common_continuous_input"].update(
                    entry_count=119
                ),
            ),
            (
                "common editor_key trace execution contract differs",
                lambda report: report["common_continuous_input"][
                    "editor_key"
                ].update(event_trace_sha256="wrong"),
            ),
            (
                "common wheel latency summary was not recomputed from samples",
                lambda report: report["common_continuous_input"][
                    "wheel"
                ]["samples_us"].__setitem__(0, 999_999),
            ),
        ]
        for expected, mutate in contract_cases:
            with self.subTest(expected=expected):
                failures = self.failures(mutate)
                self.assertTrue(
                    any(expected in failure for failure in failures), failures
                )

    def test_baseline_relative_budgets_reject_order_of_magnitude_drift(self):
        cases = [
            (
                "fixed baseline regression: mouse drag exceeds derived limit",
                lambda report: report["metrics"]["mouse_drag_to_frame"][
                    "points"
                ][0].update(median_us=24_001),
            ),
            (
                "fixed baseline regression: wheel event exceeds derived limit",
                lambda report: report["metrics"]["wheel_to_frame"][
                    "points"
                ][0].update(median_us=20_001),
            ),
            (
                "fixed baseline regression: continuous alt-input median exceeds derived limit",
                lambda report: report["paired_continuous_alt_input"].update(
                    median_us=20_001
                ),
            ),
            (
                "fixed baseline regression: continuous alt-input p95 exceeds derived limit",
                lambda report: report["paired_continuous_alt_input"].update(
                    p95_us=24_001
                ),
            ),
            (
                "fixed baseline regression: continuous alt-input p99 exceeds derived limit",
                lambda report: report["paired_continuous_alt_input"].update(
                    p99_us=30_001
                ),
            ),
        ]
        for expected, mutate in cases:
            with self.subTest(expected=expected):
                failures = self.failures(mutate)
                self.assertTrue(
                    any(expected in failure for failure in failures), failures
                )

    def test_baseline_limit_boundary_and_paired_contract_are_exact(self):
        self.assertEqual(24_000, GATE.baseline_limit_us(12_000, 500))
        self.assertEqual(28_000, GATE.baseline_limit_us(10_000, 3_000))
        report = valid_report()
        baseline = valid_baseline_report()
        report["metrics"]["mouse_drag_to_frame"]["points"][0][
            "median_us"
        ] = 24_000
        failures = []
        GATE.check_bench(report, failures, baseline)
        self.assertFalse(
            any("fixed baseline regression: mouse drag" in item for item in failures),
            failures,
        )
        cross_machine = valid_report()
        cross_machine["machine"]["machine_instance"] = "other-machine"
        cross_machine["paired_continuous_alt_input"]["p99_us"] = 300_000
        failures = []
        GATE.check_bench(cross_machine, failures, baseline)
        self.assertFalse(
            any("fixed baseline regression" in item for item in failures),
            failures,
        )
        cases = [
            (
                "paired benchmark report kind or schema differs",
                lambda candidate, _base: candidate.update(schema_version=0),
            ),
            (
                "candidate renderer object id is missing or invalid",
                lambda candidate, _base: candidate["provenance"].update(
                    renderer_object_id="old-object"
                ),
            ),
            (
                "paired benchmark is not a full five-run report",
                lambda candidate, _base: candidate["parameters"].update(samples=4),
            ),
            (
                "fixed baseline revision is not ecac0a9c4",
                lambda _report, base: base["provenance"].update(
                    source_revision="wrong"
                ),
            ),
            (
                "fixed baseline build provenance differs",
                lambda _report, base: base["provenance"][
                    "loaded_dist_tree_sha256"
                ].update(tui="wrong"),
            ),
            (
                "candidate mouse does not contain exactly five samples",
                lambda candidate, _base: candidate["metrics"][
                    "mouse_drag_to_frame"
                ]["points"][0].update(samples_us=[4_000] * 4),
            ),
            (
                "fixed baseline wheel latency summary was not recomputed from samples",
                lambda _candidate, base: base["metrics"][
                    "wheel_to_frame"
                ]["points"][0].update(median_us=10_001),
            ),
            (
                "continuous alt-input stress report does not contain 1024 measured frames",
                lambda candidate, _base: candidate[
                    "continuous_alt_input"
                ].update(rendered_frame_count=1023),
            ),
            (
                "continuous alt-input stress execution contract differs",
                lambda candidate, _base: candidate[
                    "continuous_alt_input"
                ].update(event_trace_sha256="wrong"),
            ),
            (
                "continuous alt-input stress summary was not recomputed from samples",
                lambda candidate, _base: candidate[
                    "continuous_alt_input"
                ]["samples_us"].__setitem__(0, 999_999),
            ),
            (
                "continuous alt-input GC summary was not recomputed from samples",
                lambda candidate, _base: candidate[
                    "continuous_alt_input"
                ].update(gc_affected_max_us=80_001),
            ),
            (
                "paired benchmark width differs",
                lambda candidate, _base: candidate["parameters"].update(
                    width=99
                ),
            ),
            (
                "paired benchmark dimensions differ from 100x40/1024",
                lambda candidate, base: (
                    candidate["parameters"].update(width=99),
                    base["parameters"].update(width=99),
                ),
            ),
            (
                "paired benchmark event trace differs",
                lambda candidate, _base: candidate[
                    "paired_continuous_alt_input"
                ].update(event_trace_sha256="wrong"),
            ),
            (
                "paired benchmark event counts differ from 342/341/341",
                lambda candidate, _base: candidate[
                    "paired_continuous_alt_input"
                ]["event_trace_counts"].update(drag=341),
            ),
            (
                "paired benchmark terminal sink differs",
                lambda candidate, _base: candidate[
                    "paired_continuous_alt_input"
                ].update(terminal_sink="virtual-terminal"),
            ),
            (
                "paired benchmark GC mode differs",
                lambda candidate, _base: candidate[
                    "paired_continuous_alt_input"
                ].update(gc_mode="forced"),
            ),
            (
                "paired benchmark renderer mode differs",
                lambda candidate, _base: candidate[
                    "paired_continuous_alt_input"
                ].update(renderer_mode="coalesced"),
            ),
            (
                "paired benchmark wheel trace did not return to its initial viewport",
                lambda candidate, _base: candidate[
                    "paired_continuous_alt_input"
                ]["runs"][0].update(final_viewport_top=99),
            ),
            (
                "paired benchmark candidate run 1 latency summary was not recomputed from samples",
                lambda candidate, _base: candidate[
                    "paired_continuous_alt_input"
                ]["runs"][0]["samples_us"].__setitem__(0, 999_999),
            ),
            (
                "paired benchmark candidate run 1 allocation summary was not recomputed from samples",
                lambda candidate, _base: candidate[
                    "paired_continuous_alt_input"
                ]["runs"][0].update(median_bytes=2_000),
            ),
            (
                "fixed baseline aggregate median_us MAD was not recomputed from runs",
                lambda _candidate, base: base[
                    "continuous_alt_input"
                ].update(median_run_mad_us=1),
            ),
            (
                "candidate aggregate median_us MAD was not recomputed from runs",
                lambda candidate, _base: candidate[
                    "paired_continuous_alt_input"
                ].update(median_run_mad_us=1),
            ),
            (
                "paired benchmark aggregate p95_us was not recomputed from runs",
                lambda candidate, _base: candidate[
                    "paired_continuous_alt_input"
                ].update(p95_us=5_001),
            ),
            (
                "paired benchmark did not record allocation evidence",
                lambda candidate, _base: candidate[
                    "paired_continuous_alt_input"
                ].update(median_bytes=0),
            ),
            (
                "fixed baseline mouse_drag_to_frame allocation sample is incomplete",
                lambda _candidate, base: base["metrics"][
                    "mouse_drag_to_frame"
                ]["points"][0].update(allocation_sample_event_count=31),
            ),
            (
                "fixed baseline wheel_to_frame allocation sample is incomplete",
                lambda _candidate, base: base["metrics"][
                    "wheel_to_frame"
                ]["points"][0].update(sampled_allocated_bytes_per_event=0),
            ),
            (
                "fixed baseline continuous allocation sample is incomplete",
                lambda _candidate, base: base[
                    "continuous_alt_input"
                ].update(allocation_sample_event_count=95),
            ),
            (
                "paired benchmark skipped requested frames",
                lambda candidate, _base: candidate[
                    "paired_continuous_alt_input"
                ].update(rendered_frame_count=1),
            ),
        ]
        for expected, mutate in cases:
            with self.subTest(expected=expected):
                candidate = valid_report()
                base = valid_baseline_report()
                mutate(candidate, base)
                failures = []
                GATE.check_bench(candidate, failures, base)
                self.assertTrue(
                    any(expected in failure for failure in failures), failures
                )

    def test_session_scale_profile_is_aggregate_only_and_follows_active_path(self):
        secret = "DO-NOT-LEAK-THIS-MESSAGE"
        with tempfile.TemporaryDirectory() as temporary:
            sessions = Path(temporary)
            records = [
                {
                    "type": "session",
                    "version": 3,
                    "id": "private-session",
                    "cwd": "/secret",
                },
                {
                    "type": "message",
                    "id": "a",
                    "parentId": False,
                    "message": {"role": "user", "content": secret},
                },
                {
                    "type": "message",
                    "id": "b",
                    "parentId": "a",
                    "message": {
                        "role": "assistant",
                        "provider": "secret-provider",
                        "model": "secret-model",
                        "content": [
                            {
                                "type": "toolCall",
                                "id": "private-tool-call",
                                "name": "read",
                                "arguments": {"path": "/secret/file"},
                            }
                        ],
                    },
                },
                {
                    "type": "leaf",
                    "id": "c",
                    "parentId": "b",
                    "targetId": "b",
                },
            ]
            (sessions / "private.jsonl").write_text(
                "".join(json.dumps(record) + "\n" for record in records),
                encoding="utf-8",
            )
            (sessions / "invalid.jsonl").write_text("not-json\n", encoding="utf-8")
            profile = PROFILE.build_profile(sessions)
            serialized = json.dumps(profile, sort_keys=True)
            self.assertEqual(2, profile["source_file_count"])
            self.assertEqual(1, profile["valid_session_count"])
            self.assertEqual(1, profile["invalid_session_count"])
            self.assertEqual(3, profile["entry_percentiles"]["p95"])
            self.assertEqual(50, profile["tiers"]["common"])
            for forbidden in (
                secret,
                "private-session",
                "/secret",
                "secret-provider",
                "secret-model",
                "private-tool-call",
                "private.jsonl",
            ):
                self.assertNotIn(forbidden, serialized)


class SelfHistoryInformationalTest(unittest.TestCase):
    def test_self_history_drift_enforces_adjudicated_bands(self):
        def bench(cold_us, alloc_bytes, frame_us=4_000, machine="Friend-MachineD"):
            return {
                "machine": {"machine_instance": machine},
                "cold_start": {"median_us": cold_us},
                "metrics": {
                    "frame_render": {
                        "points": [
                            {
                                "n": 5000,
                                "median_us": frame_us,
                                "median_bytes": alloc_bytes,
                            }
                        ]
                    }
                },
            }

        bands = {
            "schemaVersion": 1,
            "machine": "Friend-MachineD",
            "metrics": {
                "cold_start.median_us": {
                    "enforcement": "fail-closed",
                    "band_us": 12_000.0,
                },
                "frame_render.5000.median_bytes": {
                    "enforcement": "fail-closed",
                    "band_bytes": 4_096.0,
                },
                "frame_render.5000.median_us": {
                    "enforcement": "informational",
                    "reason": "quantized at the 4000us step",
                },
            },
        }
        history = {
            "schemaVersion": 1,
            "entries": [
                {
                    "machine": "Friend-MachineD",
                    "coldStartMedianUs": 250_000,
                    "frame5000MedianUs": 3_500,
                    "frame5000MedianBytes": 300_000,
                }
            ],
        }
        with tempfile.TemporaryDirectory() as temporary:
            history_path = Path(temporary) / "history.json"
            history_path.write_text(json.dumps(history), encoding="utf-8")
            bands_path = Path(temporary) / "bands.json"
            bands_path.write_text(json.dumps(bands), encoding="utf-8")

            # Within band: passes and reports enforcement.
            failures: list[str] = []
            summary = GATE.self_history_summary(
                bench(258_000, 302_000), str(history_path), str(bands_path), failures
            )
            self.assertEqual([], failures)
            self.assertIn("self_history_gate=adjudicated-bands", summary)
            self.assertIn("self_history_enforced=cold,alloc", summary)
            self.assertIn(
                "self_history_frame5000_time=informational-quantized-4000us", summary
            )

            # Cold start beyond previous + band fails closed.
            failures = []
            GATE.self_history_summary(
                bench(263_000, 300_000), str(history_path), str(bands_path), failures
            )
            self.assertTrue(any("cold start drifted" in item for item in failures))

            # Allocation beyond previous + band fails closed.
            failures = []
            GATE.self_history_summary(
                bench(250_000, 304_097), str(history_path), str(bands_path), failures
            )
            self.assertTrue(
                any("frame allocation drifted" in item for item in failures)
            )

            # Frame time is informational: a huge regression adds no failure.
            failures = []
            GATE.self_history_summary(
                bench(250_000, 300_000, frame_us=40_000),
                str(history_path),
                str(bands_path),
                failures,
            )
            self.assertEqual([], failures)

            # A bands file demotion (informational) disables cold enforcement.
            demoted = json.loads(json.dumps(bands))
            demoted["metrics"]["cold_start.median_us"]["enforcement"] = (
                "informational"
            )
            demoted_path = Path(temporary) / "demoted.json"
            demoted_path.write_text(json.dumps(demoted), encoding="utf-8")
            failures = []
            summary = GATE.self_history_summary(
                bench(400_000, 300_000), str(history_path), str(demoted_path), failures
            )
            self.assertEqual([], failures)
            self.assertIn("self_history_enforced=alloc", summary)

            # Machine mismatch stays informational (same_machine rule).
            failures = []
            summary = GATE.self_history_summary(
                bench(999_000, 999_000, machine="Other-Machine"),
                str(history_path),
                str(bands_path),
                failures,
            )
            self.assertEqual([], failures)
            self.assertIn(
                "self_history_gate=informational-no-same-machine-row", summary
            )

            # Missing bands file fails closed post-adjudication.
            failures = []
            summary = GATE.self_history_summary(
                bench(250_000, 300_000),
                str(history_path),
                str(Path(temporary) / "absent.json"),
                failures,
            )
            self.assertTrue(any("noise-bands" in item for item in failures))
            self.assertIn("self_history_gate=failed-no-noise-bands", summary)


if __name__ == "__main__":
    unittest.main()
