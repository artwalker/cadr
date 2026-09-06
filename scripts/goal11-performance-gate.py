#!/usr/bin/env python3
import argparse
import hashlib
import json
import math
import re
import sys
from pathlib import Path
from statistics import median


import importlib.util as _baseline_import
_spec = _baseline_import.spec_from_file_location(
    "baseline_anchor", Path(__file__).resolve().parent / "baseline-anchor.py"
)
_baseline_anchor = _baseline_import.module_from_spec(_spec)
_spec.loader.exec_module(_baseline_anchor)
FIXED_BASELINE_REVISION = _baseline_anchor.read_baseline()["commit"]
FIXED_CONTINUOUS_TRACE_SHA256 = (
    "2dfea100e8e8825a96ea55795c39e6cea2f265c6aa1a4b98f4edba8b4e5edb61"
)
COMMON_TRACE_SHA256 = {
    "mouse_drag": "13483601f4696d53de318057f9f355bed854c69d548601e45ba0011fb93ad3cc",
    "wheel": "fd18193bb055059e342815a6768f6dca4e6ce0fc59ab6e41d8aa7b42591653c1",
    "editor_key": "24c4d742dbd461a4f7e8fdead4e9d0215eb6575eeba6e2352cc662e975ca60ec",
}
COMMON_TRACE_COUNTS = {
    "mouse_drag": {"drag": 1024},
    "wheel": {"wheel_up": 512, "wheel_down": 512},
    "editor_key": {"insert": 512, "backspace": 512},
}
COMMON_ABSOLUTE_P99_US = 16_000
FIXED_BASELINE_DIST_SHA256 = {
    "tui": "897358300f9abff3028d7ea07ca5df6e5b343fcf7579130ce098abc933b37479",
    "ai": "6ea7a794b02bb1ebf6f20d48be246ceaee480e94b5f9e8b2162c4ca9fb2f7975",
    "agent": "b141f890e211eafe49ffda498cc41edd08f60cf0ab4aaca9d2b18aad0d17b5a7",
    "coding_agent": "44c64982bb381813c263b967162121da60e55a8a154295eeb60790ea97c60864",
}
FIXED_BASELINE_OBJECT_IDS = {
    "package_lock_object_id": "1f77aa69a44915990ba2e4f41573cb2b7005b0ca",
    "tui_object_id": "5172a9a142c582f8d8ad9c8c85772f1b093cc5a7",
    "interactive_mode_object_id": "6d5e6b884fc7729b517c17ab18acea9f9a672776",
    "alt_screen_object_id": "783a92ab8f064ee6d5b1407d2d9f8d81c42ab892",
}
FIXED_BASELINE_DEPENDENCY_TREE_SHA256 = (
    "b9847a32b8c1d8a83b1cd76f3b07c29cc7406c414dfb6728862dca12b24796ee"
)
FIXED_BASELINE_ARTIFACT_SHA256 = (
    "967e2ce8070340108729f30572721ab9368778b6958a86f39bf3eff14857f671"
)


def load_json(path: str) -> dict:
    with Path(path).open(encoding="utf-8") as stream:
        return json.load(stream)


def file_sha256(path: str | Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def point_at(metric: dict, count: int) -> dict:
    for point in metric["points"]:
        if point["n"] == count:
            return point
    raise ValueError(f"metric has no N={count} point")


def log_slope(points: list[tuple[float, float]]) -> float:
    usable = [(math.log(x), math.log(y)) for x, y in points if x > 0 and y > 0]
    if len(usable) < 2:
        return 0.0
    x_mean = sum(x for x, _ in usable) / len(usable)
    y_mean = sum(y for _, y in usable) / len(usable)
    denominator = sum((x - x_mean) ** 2 for x, _ in usable)
    if denominator == 0:
        return 0.0
    return sum((x - x_mean) * (y - y_mean) for x, y in usable) / denominator


def check(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def baseline_limit_us(value: float, run_mad: float) -> float:
    return max(2 * value, value + max(5_000, 6 * run_mad))


def same_machine(candidate: dict, baseline: dict) -> bool:
    """Host match between a cadr report and a pi report.

    cadr reports the host as machine.machine_instance ((machine-instance)),
    pi as machine.hostname (os.hostname()).  Absolute microseconds only
    compare on the host that produced both halves, so every pi-paired gate
    calls this one rule: scripts/goal20-paired-paths.py imports it rather
    than growing a second host-match mechanism.
    """
    return (
        candidate["machine"]["machine_instance"]
        == baseline["machine"]["hostname"]
    )


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, math.ceil(fraction * len(ordered)) - 1))
    return ordered[index]


def check_point_samples(
    point: dict,
    label: str,
    allocation_field: str,
    allocation_summary_field: str,
    failures: list[str],
) -> None:
    time_samples = point["samples_us"]
    allocation_samples = point[allocation_field]
    check(
        len(time_samples) == 5 and len(allocation_samples) == 5,
        f"{label} does not contain exactly five samples",
        failures,
    )
    if len(time_samples) == 5:
        center = median(time_samples)
        check(
            math.isclose(point["median_us"], center)
            and math.isclose(
                point["mad_us"], median(abs(value - center) for value in time_samples)
            ),
            f"{label} latency summary was not recomputed from samples",
            failures,
        )
    if len(allocation_samples) == 5:
        check(
            math.isclose(
                point[allocation_summary_field], median(allocation_samples)
            ),
            f"{label} allocation summary was not recomputed from samples",
            failures,
        )


def check_paired_contract(
    data: dict, baseline: dict, failures: list[str]
) -> None:
    parameters = data["parameters"]
    baseline_parameters = baseline["parameters"]
    paired = data["paired_continuous_alt_input"]
    baseline_paired = baseline["continuous_alt_input"]
    check(
        data["kind"] == "cadr-goal11-performance"
        and data["schema_version"] == 1
        and baseline["kind"] == "pi-goal11-structural-baseline"
        and baseline["schema_version"] == 2,
        "paired benchmark report kind or schema differs",
        failures,
    )
    check(
        isinstance(data["provenance"].get("renderer_object_id"), str)
        and re.fullmatch(
            r"[0-9a-f]{40}", data["provenance"]["renderer_object_id"]
        )
        is not None,
        "candidate renderer object id is missing or invalid",
        failures,
    )
    expected_entry_counts = [0, 50, 200, 1000, 5000]
    check(
        data["entry_counts"] == expected_entry_counts
        and baseline_parameters["entry_counts"] == expected_entry_counts
        and parameters["samples"] == baseline_parameters["samples"] == 5
        and parameters["warmups"] == baseline_parameters["warmups"] == 1,
        "paired benchmark is not a full five-run report",
        failures,
    )
    check(
        baseline["provenance"]["source_revision"]
        == FIXED_BASELINE_REVISION,
        f"fixed baseline revision is not {FIXED_BASELINE_REVISION[:9]}",
        failures,
    )
    check(
        baseline["provenance"]["tracked_worktree_clean"] is True
        and baseline["provenance"]["loaded_dist_tree_sha256"]
        == FIXED_BASELINE_DIST_SHA256
        and baseline["provenance"]["installed_dependency_tree_sha256"]
        == FIXED_BASELINE_DEPENDENCY_TREE_SHA256
        and all(
            baseline["provenance"][field] == value
            for field, value in FIXED_BASELINE_OBJECT_IDS.items()
        ),
        "fixed baseline build provenance differs",
        failures,
    )
    for field in ("width", "height", "continuous_events"):
        check(
            parameters[field] == baseline_parameters[field],
            f"paired benchmark {field.replace('_', ' ')} differs",
            failures,
        )
    check(
        parameters["width"] == 100
        and parameters["height"] == 40
        and parameters["continuous_events"] == 1024,
        "paired benchmark dimensions differ from 100x40/1024",
        failures,
    )
    check(
        parameters["paired_fresh_fixture_per_run"] is True
        and baseline_parameters["paired_fresh_fixture_per_run"] is True,
        "paired benchmark does not use a fresh fixture per run",
        failures,
    )
    check(
        paired["event_trace_sha256"]
        == baseline_paired["event_trace_sha256"]
        == FIXED_CONTINUOUS_TRACE_SHA256,
        "paired benchmark event trace differs",
        failures,
    )
    expected_counts = {"drag": 342, "wheel_up": 341, "wheel_down": 341}
    check(
        paired["event_trace_counts"] == expected_counts
        and baseline_paired["event_trace_counts"] == expected_counts,
        "paired benchmark event counts differ from 342/341/341",
        failures,
    )
    for field, expected, message in (
        ("terminal_sink", "count-only", "paired benchmark terminal sink differs"),
        ("gc_mode", "runtime-default", "paired benchmark GC mode differs"),
        (
            "renderer_mode",
            "synchronous-requested-frame",
            "paired benchmark renderer mode differs",
        ),
        (
            "scheduler_mode",
            "production-request-immediate-flush",
            "paired benchmark scheduler mode differs",
        ),
    ):
        check(
            paired[field] == expected and baseline_paired[field] == expected,
            message,
            failures,
        )
    check(
        paired["event_count"] == 1024
        and baseline_paired["event_count"] == 1024,
        "paired benchmark did not record exactly 1024 events",
        failures,
    )
    check(
        paired["rendered_frame_count"] == 1024
        and baseline_paired["rendered_frame_count"] == 1024,
        "paired benchmark skipped requested frames",
        failures,
    )
    check(
        paired["final_selection_active"] is True
        and baseline_paired["final_selection_active"] is True,
        "paired benchmark did not preserve the final drag selection",
        failures,
    )
    check(
        len(paired["runs"]) == 5 and len(baseline_paired["runs"]) == 5,
        "paired benchmark does not contain exactly five runs",
        failures,
    )
    for label, runs, allocation_field in (
        ("candidate", paired["runs"], "samples_bytes"),
        (
            "baseline",
            baseline_paired["runs"],
            "samples_retained_heap_delta_bytes",
        ),
    ):
        for index, run in enumerate(runs):
            prefix = f"paired benchmark {label} run {index + 1}"
            check(
                run["event_count"] == 1024
                and run["rendered_frame_count"] == 1024
                and len(run["samples_us"]) == 1024
                and len(run[allocation_field]) == 1024,
                f"{prefix} does not contain 1024 measured frames",
                failures,
            )
            check(
                run["event_trace_sha256"] == FIXED_CONTINUOUS_TRACE_SHA256
                and run["event_trace_counts"] == expected_counts,
                f"{prefix} event trace differs",
                failures,
            )
            check(
                run["terminal_sink"] == "count-only"
                and run["gc_mode"] == "runtime-default"
                and run["renderer_mode"] == "synchronous-requested-frame"
                and run["scheduler_mode"]
                == "production-request-immediate-flush",
                f"{prefix} execution mode differs",
                failures,
            )
            check(
                run["initial_viewport_top"] == run["final_viewport_top"],
                "paired benchmark wheel trace did not return to its initial viewport",
                failures,
            )
            check(
                run["final_selection_active"] is True,
                f"{prefix} did not preserve the final drag selection",
                failures,
            )
            if len(run["samples_us"]) == 1024:
                check(
                    math.isclose(run["median_us"], median(run["samples_us"]))
                    and math.isclose(
                        run["p95_us"], percentile(run["samples_us"], 0.95)
                    )
                    and math.isclose(
                        run["p99_us"], percentile(run["samples_us"], 0.99)
                    )
                    and math.isclose(run["max_us"], max(run["samples_us"])),
                    f"{prefix} latency summary was not recomputed from samples",
                    failures,
                )
            if len(run[allocation_field]) == 1024:
                allocation_summary = (
                    "median_retained_heap_delta_bytes"
                    if label == "baseline"
                    else "median_bytes"
                )
                check(
                    math.isclose(
                        run[allocation_summary], median(run[allocation_field])
                    ),
                    f"{prefix} allocation summary was not recomputed from samples",
                    failures,
                )
    if len(paired["runs"]) == 5 and len(baseline_paired["runs"]) == 5:
        for field in ("median_us", "p95_us", "p99_us"):
            check(
                math.isclose(
                    paired[field], median(run[field] for run in paired["runs"])
                )
                and math.isclose(
                    baseline_paired[field],
                    median(run[field] for run in baseline_paired["runs"]),
                ),
                f"paired benchmark aggregate {field} was not recomputed from runs",
                failures,
            )
            for label, report in (
                ("candidate", paired),
                ("fixed baseline", baseline_paired),
            ):
                run_values = [run[field] for run in report["runs"]]
                center = median(run_values)
                check(
                    math.isclose(
                        report[field.replace("_us", "_run_mad_us")],
                        median(abs(value - center) for value in run_values),
                    ),
                    f"{label} aggregate {field} MAD was not recomputed from runs",
                    failures,
                )
        check(
            math.isclose(
                paired["max_us"], max(run["max_us"] for run in paired["runs"])
            )
            and math.isclose(
                baseline_paired["max_us"],
                max(run["max_us"] for run in baseline_paired["runs"]),
            ),
            "paired benchmark aggregate max_us was not recomputed from runs",
            failures,
        )
        check(
            math.isclose(
                paired["median_bytes"],
                median(run["median_bytes"] for run in paired["runs"]),
            )
            and math.isclose(
                baseline_paired["median_retained_heap_delta_bytes"],
                median(
                    run["median_retained_heap_delta_bytes"]
                    for run in baseline_paired["runs"]
                ),
            ),
            "paired benchmark aggregate allocation was not recomputed from runs",
            failures,
        )
        check(
            math.isclose(
                baseline_paired["retained_heap_delta_bytes_per_event"],
                median(
                    run["retained_heap_delta_bytes_per_event"]
                    for run in baseline_paired["runs"]
                ),
            )
            and math.isclose(
                baseline_paired[
                    "retained_heap_high_water_delta_bytes_per_event"
                ],
                median(
                    run["retained_heap_high_water_delta_bytes_per_event"]
                    for run in baseline_paired["runs"]
                ),
            ),
            "fixed baseline retained-heap summary was not recomputed from runs",
            failures,
        )
    check(
        paired["median_bytes"] > 0
        and baseline_paired["sampled_allocated_bytes_per_event"] > 0,
        "paired benchmark did not record allocation evidence",
        failures,
    )
    for metric_name in ("mouse_drag_to_frame", "wheel_to_frame"):
        baseline_point = point_at(baseline["metrics"][metric_name], 5000)
        check(
            baseline_point["sampled_allocated_bytes_per_event"] > 0
            and baseline_point["allocation_sample_event_count"] == 32,
            f"fixed baseline {metric_name} allocation sample is incomplete",
            failures,
        )
    check(
        baseline_paired["allocation_sample_event_count"] == 96,
        "fixed baseline continuous allocation sample is incomplete",
        failures,
    )


def check_common_continuous_contract(data: dict, failures: list[str]) -> list[str]:
    profile = data["session_scale_profile"]
    privacy = profile["privacy"]
    percentiles = profile["entry_percentiles"]
    tiers = profile["tiers"]
    profile_contract = (
        profile["schema_version"] == 1
        and profile["kind"] == "cadr-anonymous-session-scale"
        and profile["valid_session_count"] > 0
        and profile["source_file_count"]
        == profile["valid_session_count"] + profile["invalid_session_count"]
        and all(value is False for value in privacy.values())
        and set(privacy)
        == {
            "contains_message_content",
            "contains_session_identifiers",
            "contains_paths",
            "contains_timestamps",
            "contains_provider_or_model",
        }
        and 0
        <= percentiles["min"]
        <= percentiles["p50"]
        <= percentiles["p90"]
        <= percentiles["p95"]
        <= percentiles["p99"]
        <= percentiles["max"]
        and tiers["typical"] == percentiles["p50"]
        and tiers["common"] == max(50, percentiles["p95"])
        and tiers["heavy"] == percentiles["p99"]
        and tiers["stress"] == 5000
    )
    check(
        profile_contract,
        "anonymous session scale profile contract differs",
        failures,
    )

    common = data["common_continuous_input"]
    check(
        common["entry_count"] == tiers["common"]
        and common["event_count_per_kind"] == 1024,
        "common tier does not match the anonymous p95 session scale",
        failures,
    )
    summary: list[str] = []
    for kind in ("mouse_drag", "wheel", "editor_key"):
        run = common[kind]
        samples = run["samples_us"]
        allocations = run["samples_bytes"]
        gc_samples = run["gc_affected_samples_us"]
        final_state_ok = (
            (kind == "mouse_drag" and run["final_selection_active"] is True)
            or (
                kind == "wheel"
                and run["initial_viewport_top"] == run["final_viewport_top"]
            )
            or (kind == "editor_key" and run["final_editor_text_length"] == 0)
        )
        execution_contract = (
            run["input_kind"] == kind
            and run["event_count"] == 1024
            and run["rendered_frame_count"] == 1024
            and len(samples) == 1024
            and len(allocations) == 1024
            and run["event_trace_sha256"] == COMMON_TRACE_SHA256[kind]
            and run["event_trace_counts"] == COMMON_TRACE_COUNTS[kind]
            and run["terminal_sink"] == "count-only"
            and run["gc_mode"] == "forced-8mib-nursery"
            and run["renderer_mode"] == "synchronous-requested-frame"
            and run["scheduler_mode"] == "production-request-immediate-flush"
            and run["nursery_bytes"] == 8 * 1024 * 1024
            and final_state_ok
        )
        check(
            execution_contract,
            f"common {kind} trace execution contract differs",
            failures,
        )
        if len(samples) == 1024 and len(allocations) == 1024:
            check(
                math.isclose(run["median_us"], median(samples))
                and math.isclose(run["p95_us"], percentile(samples, 0.95))
                and math.isclose(run["p99_us"], percentile(samples, 0.99))
                and math.isclose(run["max_us"], max(samples))
                and math.isclose(run["median_bytes"], median(allocations))
                and math.isclose(run["total_bytes"], sum(allocations)),
                f"common {kind} latency summary was not recomputed from samples",
                failures,
            )
        check(
            run["gc_affected_event_count"] == len(gc_samples)
            and math.isclose(
                run["gc_affected_max_us"], max(gc_samples, default=0)
            ),
            f"common {kind} GC summary was not recomputed from samples",
            failures,
        )
        check(
            run["gc_affected_event_count"] > 0
            or run["total_bytes"] < run["nursery_bytes"],
            f"common {kind} allocated a nursery without observing GC",
            failures,
        )
        check(
            run["p99_us"] <= COMMON_ABSOLUTE_P99_US,
            f"absolute interaction target: common {kind} p99 exceeds 16ms",
            failures,
        )
        summary.append(f"common_{kind}_p99={run['p99_us'] / 1000:.2f}ms")
    return summary


def check_sustained_mixed_contract(
    data: dict, failures: list[str]
) -> list[str]:
    run = data.get("sustained_mixed_interaction")
    if not isinstance(run, dict):
        failures.append("sustained mixed interaction report is missing")
        return []

    duration = run.get("duration_seconds")
    target_hz = run.get("target_event_hz")
    event_count = run.get("event_count")
    samples = run.get("samples_us")
    counts = run.get("event_trace_counts")
    execution_contract = (
        isinstance(duration, int)
        and duration >= 180
        and target_hz == 60
        and event_count == duration * target_hz
        and run.get("rendered_frame_count") == event_count
        and isinstance(samples, list)
        and len(samples) == event_count
        and counts
        == {
            "drag": event_count // 4,
            "wheel_up": event_count // 4,
            "wheel_down": event_count // 4,
            "editor_key": event_count // 4,
        }
        and run.get("terminal_sink") == "count-only"
        and run.get("renderer_mode") == "synchronous-requested-frame"
        and run.get("scheduler_mode") == "paced-60hz-mixed-input"
        and run.get("gc_mode") == "runtime-default"
    )
    check(
        execution_contract,
        "sustained mixed interaction execution contract differs",
        failures,
    )
    if isinstance(samples, list) and samples:
        check(
            math.isclose(run.get("p999_us", -1), percentile(samples, 0.999))
            and math.isclose(run.get("max_us", -1), max(samples)),
            "sustained mixed interaction tail summary was not recomputed from samples",
            failures,
        )
    check(
        isinstance(run.get("actual_elapsed_seconds"), (int, float))
        and isinstance(duration, int)
        and run["actual_elapsed_seconds"] >= duration,
        "sustained mixed interaction was not paced for the declared duration",
        failures,
    )
    check(
        isinstance(run.get("p999_us"), (int, float))
        and run["p999_us"] <= 100_000,
        "sustained mixed interaction p99.9 exceeds 100ms",
        failures,
    )
    check(
        isinstance(run.get("max_us"), (int, float))
        and run["max_us"] <= 500_000,
        "sustained mixed interaction maximum pause exceeds 500ms",
        failures,
    )

    affected_samples = run.get("gc_affected_samples_us")
    pause_samples = run.get("gc_pause_samples_us")
    if not isinstance(affected_samples, list):
        affected_samples = []
    if not isinstance(pause_samples, list):
        pause_samples = []
    gc_contract = (
        run.get("gc_affected_event_count") == len(affected_samples)
        and math.isclose(
            run.get("gc_affected_max_us", -1),
            max(affected_samples, default=0),
        )
        and math.isclose(
            run.get("gc_pause_p999_us", -1),
            percentile(pause_samples, 0.999) if pause_samples else 0,
        )
        and math.isclose(
            run.get("gc_pause_max_us", -1), max(pause_samples, default=0)
        )
        and isinstance(duration, int)
        and math.isclose(
            run.get("gc_frequency_per_minute", -1),
            len(pause_samples) * 60 / duration,
        )
        and run.get("gc_cpu_us", -1) >= 0
        and run.get("gc_pause_measurement")
        == "sb-ext:*gc-run-time* delta; event wall latency is gc_affected_samples_us"
    )
    check(
        gc_contract,
        "sustained mixed interaction GC summary was not recomputed from samples",
        failures,
    )

    memory_samples = run.get("memory_samples")
    memory_contract = False
    if (
        isinstance(memory_samples, list)
        and len(memory_samples) >= 19
        and isinstance(duration, int)
    ):
        elapsed = [sample.get("elapsed_seconds") for sample in memory_samples]
        if (
            all(isinstance(value, (int, float)) for value in elapsed)
            and elapsed == sorted(elapsed)
            and elapsed[0] == 0
            and elapsed[-1] == duration
            and all(
                isinstance(sample.get("heap_bytes"), int)
                and isinstance(sample.get("rss_bytes"), int)
                for sample in memory_samples
            )
        ):
            window_start = duration - 30
            window_sample = next(
                sample
                for sample in memory_samples
                if sample["elapsed_seconds"] >= window_start
            )
            final_sample = memory_samples[-1]
            growth = max(
                0,
                final_sample["heap_bytes"] - window_sample["heap_bytes"],
                final_sample["rss_bytes"] - window_sample["rss_bytes"],
            )
            heap_growth = max(
                0,
                final_sample["heap_bytes"] - window_sample["heap_bytes"],
            )
            rss_growth = max(
                0,
                final_sample["rss_bytes"] - window_sample["rss_bytes"],
            )
            retained_before = run.get("memory_retained_heap_before_bytes")
            retained_after = run.get("memory_retained_heap_after_bytes")
            retained_growth = (
                max(0, retained_after - retained_before)
                if isinstance(retained_before, int)
                and isinstance(retained_after, int)
                else None
            )
            post_gc_rss = run.get("memory_post_gc_rss_bytes")
            post_gc_rss_growth = (
                max(0, post_gc_rss - memory_samples[0]["rss_bytes"])
                if isinstance(post_gc_rss, int)
                else None
            )
            converged = (
                isinstance(retained_growth, int)
                and retained_growth <= 8 * 1024 * 1024
                and isinstance(post_gc_rss_growth, int)
                and post_gc_rss_growth <= 8 * 1024 * 1024
            )
            memory_contract = (
                run.get("memory_final_window_growth_bytes") == growth
                and run.get("memory_final_window_heap_growth_bytes")
                == heap_growth
                and run.get("memory_final_window_rss_growth_bytes")
                == rss_growth
                and run.get("memory_retained_heap_growth_bytes")
                == retained_growth
                and run.get("memory_post_gc_rss_growth_bytes")
                == post_gc_rss_growth
                and run.get("memory_converged") is converged
            )
    check(
        memory_contract and run.get("memory_converged") is True,
        "sustained mixed interaction memory did not converge in the final 30s",
        failures,
    )
    return [
        f"sustained_p999={run.get('p999_us', 0) / 1000:.2f}ms",
        f"sustained_max={run.get('max_us', 0) / 1000:.2f}ms",
        f"sustained_gc_max={run.get('gc_pause_max_us', 0) / 1000:.2f}ms",
        "sustained_memory=converged"
        if run.get("memory_converged") is True
        else "sustained_memory=not-converged",
    ]


def check_bench(
    data: dict, failures: list[str], baseline: dict
) -> list[str]:
    check_paired_contract(data, baseline, failures)
    common_summary = check_common_continuous_contract(data, failures)
    sustained_summary = check_sustained_mixed_contract(data, failures)
    metrics = data["metrics"]
    frame = point_at(metrics["frame_render"], 5000)
    key = point_at(metrics["key_to_frame"], 5000)
    stream = point_at(metrics["stream_delta_to_frame"], 5000)
    mouse = point_at(metrics["mouse_drag_to_frame"], 5000)
    wheel = point_at(metrics["wheel_to_frame"], 5000)
    continuous = data["continuous_alt_input"]
    paired_continuous = data["paired_continuous_alt_input"]
    baseline_mouse = point_at(
        baseline["metrics"]["mouse_drag_to_frame"], 5000
    )
    baseline_wheel = point_at(
        baseline["metrics"]["wheel_to_frame"], 5000
    )
    baseline_continuous = baseline["continuous_alt_input"]
    for label, point, allocation_field, allocation_summary in (
        ("candidate mouse", mouse, "samples_bytes", "median_bytes"),
        ("candidate wheel", wheel, "samples_bytes", "median_bytes"),
        (
            "fixed baseline mouse",
            baseline_mouse,
            "samples_retained_heap_delta_bytes",
            "median_retained_heap_delta_bytes",
        ),
        (
            "fixed baseline wheel",
            baseline_wheel,
            "samples_retained_heap_delta_bytes",
            "median_retained_heap_delta_bytes",
        ),
    ):
        check_point_samples(
            point, label, allocation_field, allocation_summary, failures
        )
    baseline_same_machine = same_machine(data, baseline)
    baseline_mouse_ratio = mouse["median_us"] / max(
        1, baseline_mouse["median_us"]
    )
    baseline_wheel_ratio = wheel["median_us"] / max(
        1, baseline_wheel["median_us"]
    )
    baseline_continuous_p99_ratio = paired_continuous["p99_us"] / max(
        1, baseline_continuous["p99_us"]
    )
    append_exponent = metrics["append_entry"]["scaling"]["log_log_exponent"]
    cold_start = data["cold_start"]["median_us"]

    check(frame["median_us"] <= 50_000, "N=5000 frame exceeds 50ms", failures)
    check(key["median_us"] <= 50_000, "N=5000 key-to-frame exceeds 50ms", failures)
    check(stream["median_us"] <= 50_000, "N=5000 stream frame exceeds 50ms", failures)
    check(mouse["median_us"] <= 50_000,
          "N=5000 mouse drag-to-frame exceeds 50ms", failures)
    check(wheel["median_us"] <= 50_000,
          "N=5000 wheel-to-frame exceeds 50ms", failures)
    check(frame["median_bytes"] <= 16 * 1024 * 1024,
          "N=5000 frame allocates more than 16MiB", failures)
    check(mouse["median_bytes"] <= 16 * 1024 * 1024,
          "N=5000 mouse drag allocates more than 16MiB", failures)
    check(wheel["median_bytes"] <= 16 * 1024 * 1024,
          "N=5000 wheel event allocates more than 16MiB", failures)
    check(stream["delta_per_second"] >= 20,
          "N=5000 stream throughput is below 20 delta/s", failures)
    check(append_exponent < 0.35,
          f"TUI append is not constant-time ({append_exponent:.3f})", failures)
    check(cold_start <= 750_000, "cold start exceeds 750ms", failures)
    check(continuous["event_count"] == 1024,
          "continuous alt-input benchmark did not record exactly 1024 events",
          failures)
    check(
        continuous["rendered_frame_count"] == 1024
        and len(continuous["samples_us"]) == 1024
        and len(continuous["samples_bytes"]) == 1024,
        "continuous alt-input stress report does not contain 1024 measured frames",
        failures,
    )
    check(
        continuous["event_trace_sha256"] == FIXED_CONTINUOUS_TRACE_SHA256
        and continuous["event_trace_counts"]
        == {"drag": 342, "wheel_up": 341, "wheel_down": 341}
        and continuous["terminal_sink"] == "count-only"
        and continuous["gc_mode"] == "forced-8mib-nursery"
        and continuous["renderer_mode"] == "synchronous-requested-frame"
        and continuous["scheduler_mode"]
        == "production-request-immediate-flush"
        and continuous["nursery_bytes"] == 8 * 1024 * 1024,
        "continuous alt-input stress execution contract differs",
        failures,
    )
    if (
        len(continuous["samples_us"]) == 1024
        and len(continuous["samples_bytes"]) == 1024
    ):
        check(
            math.isclose(
                continuous["median_us"], median(continuous["samples_us"])
            )
            and math.isclose(
                continuous["p99_us"],
                percentile(continuous["samples_us"], 0.99),
            )
            and math.isclose(continuous["max_us"], max(continuous["samples_us"]))
            and math.isclose(
                continuous["median_bytes"], median(continuous["samples_bytes"])
            )
            and math.isclose(
                continuous["total_bytes"], sum(continuous["samples_bytes"])
            ),
            "continuous alt-input stress summary was not recomputed from samples",
            failures,
        )
    gc_samples = continuous["gc_affected_samples_us"]
    check(
        continuous["gc_affected_event_count"] == len(gc_samples)
        and math.isclose(
            continuous["gc_affected_max_us"], max(gc_samples, default=0)
        ),
        "continuous alt-input GC summary was not recomputed from samples",
        failures,
    )
    # The fixed 8MiB nursery deliberately forces GC during roughly half of
    # the events.  Keep ordinary N=5000 event medians at 50ms, while giving
    # the stress-run tail enough host variance to distinguish a pause from
    # the former near-second full redraw path.
    check(continuous["p99_us"] <= 150_000,
          "continuous alt-input p99 exceeds 150ms", failures)
    check(continuous["gc_affected_max_us"] <= 500_000,
          "continuous alt-input GC-affected event exceeds 500ms", failures)
    check(continuous["gc_affected_event_count"] > 0
          or continuous["total_bytes"] < continuous["nursery_bytes"],
          "continuous alt-input allocated a nursery without observing GC",
          failures)
    # Fixed absolute microseconds are only comparable on the machine that
    # produced the archived baseline. Other hosts retain the pre-existing broad
    # absolute budgets above and report ratios without treating them as gates.
    if baseline_same_machine:
        check(
            mouse["median_us"]
            <= baseline_limit_us(
                baseline_mouse["median_us"], baseline_mouse["mad_us"]
            ),
            "fixed baseline regression: mouse drag exceeds derived limit",
            failures,
        )
        check(
            wheel["median_us"]
            <= baseline_limit_us(
                baseline_wheel["median_us"], baseline_wheel["mad_us"]
            ),
            "fixed baseline regression: wheel event exceeds derived limit",
            failures,
        )
        for field in ("median", "p95", "p99"):
            check(
                paired_continuous[f"{field}_us"]
                <= baseline_limit_us(
                    baseline_continuous[f"{field}_us"],
                    baseline_continuous[f"{field}_run_mad_us"],
                ),
                f"fixed baseline regression: continuous alt-input {field} exceeds derived limit",
                failures,
            )

    memory_point = next(
        point for point in data["memory"]["points"] if point["n"] == 5000
    )
    check(memory_point["heap_delta_bytes"] <= 32 * 1024 * 1024,
          "N=5000 retained heap exceeds 32MiB", failures)
    return common_summary + sustained_summary + [
        "absolute_interaction_gate=enforced",
        f"frame={frame['median_us'] / 1000:.2f}ms",
        f"key={key['median_us'] / 1000:.2f}ms",
        f"stream={stream['median_us'] / 1000:.2f}ms",
        f"mouse={mouse['median_us'] / 1000:.2f}ms",
        f"wheel={wheel['median_us'] / 1000:.2f}ms",
        f"continuous_p99={continuous['p99_us'] / 1000:.2f}ms",
        f"continuous_gc_max={continuous['gc_affected_max_us'] / 1000:.2f}ms",
        f"baseline_same_machine={'yes' if baseline_same_machine else 'no'}",
        "baseline_relative_gate="
        + (
            "enforced"
            if baseline_same_machine
            else "informational-host-mismatch"
        ),
        f"baseline_mouse_ratio={baseline_mouse_ratio:.2f}x",
        f"baseline_wheel_ratio={baseline_wheel_ratio:.2f}x",
        f"baseline_continuous_p99_ratio={baseline_continuous_p99_ratio:.2f}x",
        f"append_exp={append_exponent:.3f}",
        f"cold={cold_start / 1000:.2f}ms",
    ]


def self_history_summary(
    bench: dict, history_path: str, bands_path: str, failures: list[str]
) -> list[str]:
    """Fail-close cadr-vs-previous-same-machine drift per the adjudicated bands.

    Goal 20 Part A, adjudicated 2026-08-14 (goal20-state.md ruling 2): the
    band is max(floor, 6 * MAD) read from
    docs/benchmarks/goal20-part-a-noise-bands.json, which only
    scripts/goal20-part-a-noise-bands.py writes.  Enforced when the bands
    file says fail-closed: cold_start.median_us (floor 10ms) and
    frame_render.5000.median_bytes (floor 4096 bytes).
    frame_render.5000.median_us stays informational: the reading is
    quantized at the 4000us timer step and cannot express a band until the
    measurement gains resolution.  A missing history file or a machine
    mismatch stays informational (same_machine rule); a missing or
    unreadable bands file fails now that enforcement is adjudicated.
    """
    try:
        bands = json.loads(Path(bands_path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        check(
            False,
            f"adjudicated noise-bands file is missing or unreadable: {bands_path}",
            failures,
        )
        return ["self_history_gate=failed-no-noise-bands"]
    path = Path(history_path)
    if not path.is_file():
        return ["self_history_gate=informational-no-file"]
    try:
        history = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        check(
            False,
            f"self-history file is unreadable: {history_path}",
            failures,
        )
        return ["self_history_gate=failed-unreadable-history"]
    machine = (bench.get("machine") or {}).get("machine_instance")
    previous = None
    for entry in reversed(list(history.get("entries") or [])):
        if machine and entry.get("machine") == machine:
            previous = entry
            break
    if previous is None:
        return [
            "self_history_gate=informational-no-same-machine-row",
            "self_history_enforced=no",
        ]
    cold = (bench.get("cold_start") or {}).get("median_us")
    frame = None
    alloc = None
    for point in ((bench.get("metrics") or {}).get("frame_render") or {}).get(
        "points"
    ) or []:
        if point.get("n") == 5000:
            frame = point.get("median_us")
            alloc = point.get("median_bytes")
            break

    def ratio(current, prior):
        if not current or not prior:
            return None
        return current / prior

    cold_r = ratio(cold, previous.get("coldStartMedianUs"))
    frame_r = ratio(frame, previous.get("frame5000MedianUs"))
    alloc_r = ratio(alloc, previous.get("frame5000MedianBytes"))
    summary = [
        f"self_history_cold_ratio="
        + ("n/a" if cold_r is None else f"{cold_r:.2f}x"),
        f"self_history_frame5000_ratio="
        + ("n/a" if frame_r is None else f"{frame_r:.2f}x"),
        f"self_history_frame5000_alloc_ratio="
        + ("n/a" if alloc_r is None else f"{alloc_r:.2f}x"),
    ]
    if bands.get("machine") != machine:
        return [
            "self_history_gate=informational-band-machine-mismatch",
            "self_history_enforced=no",
            *summary,
        ]

    metrics = bands.get("metrics") or {}
    enforced = []

    cold_band = metrics.get("cold_start.median_us") or {}
    prior_cold = previous.get("coldStartMedianUs")
    if cold_band.get("enforcement") == "fail-closed" and cold and prior_cold:
        limit = prior_cold + cold_band["band_us"]
        check(
            cold <= limit,
            "cold start drifted beyond the adjudicated band: "
            f"{cold:.0f}us > {prior_cold:.0f}us + {cold_band['band_us']:.0f}us",
            failures,
        )
        enforced.append("cold")

    alloc_band = metrics.get("frame_render.5000.median_bytes") or {}
    prior_alloc = previous.get("frame5000MedianBytes")
    if alloc_band.get("enforcement") == "fail-closed" and alloc and prior_alloc:
        limit = prior_alloc + alloc_band["band_bytes"]
        check(
            alloc <= limit,
            "frame allocation drifted beyond the adjudicated band: "
            f"{alloc:.0f}B > {prior_alloc:.0f}B + {alloc_band['band_bytes']:.0f}B",
            failures,
        )
        enforced.append("alloc")

    return [
        "self_history_gate=adjudicated-bands",
        "self_history_enforced=" + (",".join(enforced) if enforced else "no"),
        "self_history_frame5000_time=informational-quantized-4000us",
        *summary,
    ]


def check_stability(data: dict, failures: list[str]) -> list[str]:
    baseline = data["baseline"]
    long_run = data["long_run"]
    checkpoints = long_run["checkpoints"]
    cleanup = long_run["post_cleanup"]
    large = data["large_session"]
    append = data["append_scaling"]

    check(long_run["turns"] >= 1200, "long run has fewer than 1200 turns", failures)
    check(long_run["simulated_hours"] >= 10,
          "long run represents fewer than 10 hours", failures)
    check(large["file_bytes"] >= 10 * 1024 * 1024,
          "large JSONL session is smaller than 10MiB", failures)
    check(len(checkpoints) >= 5, "long run has fewer than five checkpoints", failures)

    for key, label in (
        ("fd_count", "file descriptor"),
        ("lisp_thread_count", "Lisp thread"),
        ("os_thread_count", "OS thread"),
    ):
        expected = baseline[key]
        observed = [point[key] for point in checkpoints] + [cleanup[key]]
        check(all(value == expected for value in observed),
              f"{label} count changed: expected {expected}, got {observed}", failures)

    first = checkpoints[0]
    last = checkpoints[-1]
    heap_growth = last["heap_bytes"] - first["heap_bytes"]
    heap_slope = log_slope([
        (point["turn"], point["heap_bytes"] - first["heap_bytes"])
        for point in checkpoints[1:]
    ])
    check(heap_growth <= 128 * 1024 * 1024,
          "1200-turn retained heap growth exceeds 128MiB", failures)
    check(heap_slope <= 1.30,
          f"retained heap growth is superlinear ({heap_slope:.3f})", failures)
    check(max(point["gc_full_pause_us"] for point in checkpoints) <= 500_000,
          "full GC pause exceeds 500ms", failures)
    check(cleanup["heap_bytes"] - baseline["heap_bytes"] <= 16 * 1024 * 1024,
          "post-cleanup retained heap exceeds baseline by 16MiB", failures)
    check(cleanup["rss_bytes"] - baseline["rss_bytes"] <= 64 * 1024 * 1024,
          "post-cleanup RSS exceeds baseline by 64MiB", failures)

    for operation in large["operations"]:
        name = operation["name"]
        check(operation["duration_us"] <= 5_000_000,
              f"{name} of 10MiB session exceeds 5s", failures)
        check(operation["rss_peak_sampled_bytes"] - operation["rss_base_bytes"]
              <= 512 * 1024 * 1024,
              f"{name} sampled RSS peak exceeds baseline by 512MiB", failures)
        check(operation["heap_peak_sampled_bytes"] - operation["heap_base_bytes"]
              <= 512 * 1024 * 1024,
              f"{name} sampled heap peak exceeds baseline by 512MiB", failures)
        check(operation["sample_count"] > 0,
              f"{name} peak sampler captured no samples", failures)

    for name in ("agent", "session"):
        exponent = append[name]["log_log_exponent"]
        check(exponent < 0.35,
              f"{name} append is not constant-time ({exponent:.3f})", failures)

    operation_summary = ",".join(
        f"{operation['name']}={operation['duration_us'] / 1000:.1f}ms"
        for operation in large["operations"]
    )
    return [
        f"turns={long_run['turns']}",
        f"heap_growth={heap_growth / 1024 / 1024:.1f}MiB",
        f"heap_exp={heap_slope:.3f}",
        f"gc_max={max(point['gc_full_pause_us'] for point in checkpoints) / 1000:.1f}ms",
        operation_summary,
    ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bench", required=True)
    parser.add_argument("--stability", required=True)
    parser.add_argument(
        "--baseline",
        default=str(
            Path(__file__).resolve().parents[1]
            / "docs"
            / "benchmarks"
            / "goal-v11-pi-baseline.json"
        ),
    )
    parser.add_argument(
        "--history",
        default=str(
            Path(__file__).resolve().parents[1]
            / "docs"
            / "benchmarks"
            / "performance-history.json"
        ),
        help="cadr self-history JSON compared against the adjudicated drift bands.",
    )
    parser.add_argument(
        "--noise-bands",
        default=str(
            Path(__file__).resolve().parents[1]
            / "docs"
            / "benchmarks"
            / "goal20-part-a-noise-bands.json"
        ),
        help="adjudicated drift bands written by scripts/goal20-part-a-noise-bands.py.",
    )
    args = parser.parse_args()

    failures: list[str] = []
    try:
        check(
            file_sha256(args.baseline) == FIXED_BASELINE_ARTIFACT_SHA256,
            "fixed baseline artifact SHA-256 differs",
            failures,
        )
        bench = load_json(args.bench)
        bench_summary = check_bench(bench, failures, load_json(args.baseline))
        bench_summary.extend(
            self_history_summary(bench, args.history, args.noise_bands, failures)
        )
        stability_summary = check_stability(load_json(args.stability), failures)
    except (KeyError, OSError, TypeError, ValueError, json.JSONDecodeError) as error:
        print(f"goal11 gate: invalid report: {error}", file=sys.stderr)
        return 2

    if failures:
        for failure in failures:
            print(f"goal11 gate: FAIL: {failure}", file=sys.stderr)
        return 1

    print("goal11 gate: PASS")
    print("  bench: " + ", ".join(bench_summary))
    print("  stability: " + ", ".join(stability_summary))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
