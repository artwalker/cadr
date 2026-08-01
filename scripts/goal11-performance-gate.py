#!/usr/bin/env python3
import argparse
import json
import math
import sys
from pathlib import Path


def load_json(path: str) -> dict:
    with Path(path).open(encoding="utf-8") as stream:
        return json.load(stream)


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


def check_bench(data: dict, failures: list[str]) -> list[str]:
    metrics = data["metrics"]
    frame = point_at(metrics["frame_render"], 5000)
    key = point_at(metrics["key_to_frame"], 5000)
    stream = point_at(metrics["stream_delta_to_frame"], 5000)
    append_exponent = metrics["append_entry"]["scaling"]["log_log_exponent"]
    cold_start = data["cold_start"]["median_us"]

    check(frame["median_us"] <= 50_000, "N=5000 frame exceeds 50ms", failures)
    check(key["median_us"] <= 50_000, "N=5000 key-to-frame exceeds 50ms", failures)
    check(stream["median_us"] <= 50_000, "N=5000 stream frame exceeds 50ms", failures)
    check(frame["median_bytes"] <= 16 * 1024 * 1024,
          "N=5000 frame allocates more than 16MiB", failures)
    check(stream["delta_per_second"] >= 20,
          "N=5000 stream throughput is below 20 delta/s", failures)
    check(append_exponent < 0.35,
          f"TUI append is not constant-time ({append_exponent:.3f})", failures)
    check(cold_start <= 750_000, "cold start exceeds 750ms", failures)

    memory_point = next(
        point for point in data["memory"]["points"] if point["n"] == 5000
    )
    check(memory_point["heap_delta_bytes"] <= 32 * 1024 * 1024,
          "N=5000 retained heap exceeds 32MiB", failures)
    return [
        f"frame={frame['median_us'] / 1000:.2f}ms",
        f"key={key['median_us'] / 1000:.2f}ms",
        f"stream={stream['median_us'] / 1000:.2f}ms",
        f"append_exp={append_exponent:.3f}",
        f"cold={cold_start / 1000:.2f}ms",
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
    args = parser.parse_args()

    failures: list[str] = []
    try:
        bench_summary = check_bench(load_json(args.bench), failures)
        stability_summary = check_stability(load_json(args.stability), failures)
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
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
