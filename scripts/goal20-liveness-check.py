#!/usr/bin/env python3
"""Goal 20, 12E-1 step 5: statistical liveness stage.

n captures (default 3). Fail if any run's worst inter-output gap exceeds
the booked N_i. Failure prints the full gap list, not just red.

Outside render-diff gate --tier core. Default check is the silence-
injection scenario (the P0-4 lock). --all walks the booked table.

Usage:
  python3 scripts/goal20-liveness-check.py
  python3 scripts/goal20-liveness-check.py --all
  python3 scripts/goal20-liveness-check.py --from-artifacts DIR
"""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RENDER_DIFF = ROOT / "scripts/render-diff.py"
THRESHOLDS = ROOT / "docs/benchmarks/goal20-liveness-thresholds.json"
CORE_MANIFEST = ROOT / "test/fixtures/render-diff/scenarios.json"
LIVENESS_MANIFEST = ROOT / "test/fixtures/render-diff/liveness-scenarios.json"
DEFAULT_SCENARIO = "liveness-ttt-agent-turn"


def load_thresholds(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schemaVersion") != 1:
        raise SystemExit(f"liveness thresholds schema is not 1: {path}")
    rows = data.get("thresholds")
    if not isinstance(rows, list) or not rows:
        raise SystemExit(f"liveness thresholds missing rows: {path}")
    return data


def gaps_ms(timing_path: Path) -> list[float]:
    entries = json.loads(timing_path.read_text(encoding="ascii"))
    if len(entries) < 2:
        return []
    return [
        round((entries[i][0] - entries[i - 1][0]) * 1000, 1)
        for i in range(1, len(entries))
    ]


def summarize(gaps: list[float]) -> dict[str, float | int]:
    if not gaps:
        return {"reads": 1, "median_ms": 0.0, "p95_ms": 0.0, "worst_ms": 0.0}
    ordered = sorted(gaps)
    p95_index = min(len(ordered) - 1, int(len(ordered) * 0.95))
    return {
        "reads": len(gaps) + 1,
        "median_ms": round(statistics.median(ordered), 1),
        "p95_ms": round(ordered[p95_index], 1),
        "worst_ms": round(ordered[-1], 1),
    }


def select_rows(thresholds: dict, scenario: str | None, all_rows: bool) -> list[dict]:
    rows = thresholds["thresholds"]
    if all_rows:
        return list(rows)
    wanted = scenario or DEFAULT_SCENARIO
    matched = [row for row in rows if row["scenario"] == wanted]
    if not matched:
        raise SystemExit(f"no booked N_i for scenario {wanted}")
    return matched


def capture_timing(
    manifest: Path,
    scenario: str,
    dimension: str,
    output: Path,
    timeout: float,
) -> Path:
    command = [
        sys.executable,
        "-u",
        str(RENDER_DIFF),
        "capture",
        "--manifest",
        str(manifest),
        "--scenario",
        scenario,
        "--dimension",
        dimension,
        "--side",
        "cadr",
        "--output",
        str(output),
        "--timeout",
        str(timeout),
    ]
    if manifest == LIVENESS_MANIFEST:
        command.append("--allow-partial-coverage")
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        tail = (result.stdout or "")[-400:] + (result.stderr or "")[-400:]
        raise RuntimeError(
            f"capture failed {scenario}/{dimension}: {tail}"
        )
    timing = output / f"{scenario}.{dimension}.cadr.timing.json"
    if not timing.is_file():
        raise RuntimeError(f"capture wrote no timing sidecar: {timing}")
    return timing


def evaluate_run(gaps: list[float], threshold_ms: int) -> dict:
    stats = summarize(gaps)
    return {
        **stats,
        "threshold_ms": threshold_ms,
        "gaps_ms": gaps,
        "pass": stats["worst_ms"] <= threshold_ms,
    }


def print_failure(row: dict, runs: list[dict]) -> None:
    print(
        f"liveness FAIL {row['scenario']}/{row['dimension']}: "
        f"N_i={row['thresholdMs']}ms "
        f"(10× baseline worst {row['baselineWorstMs']}ms, floor 500ms)",
        file=sys.stderr,
    )
    for index, run in enumerate(runs, start=1):
        print(
            f"  run {index}: worst={run['worst_ms']}ms "
            f"median={run['median_ms']}ms p95={run['p95_ms']}ms "
            f"reads={run['reads']}",
            file=sys.stderr,
        )
        print(f"  run {index} gaps_ms={run['gaps_ms']}", file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--thresholds", type=Path, default=THRESHOLDS)
    parser.add_argument("--captures", type=int, default=None)
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--scenario", type=str, default=None)
    parser.add_argument("--from-artifacts", type=Path, default=None)
    parser.add_argument("--output", type=Path, default=None)
    args = parser.parse_args()

    booked = load_thresholds(args.thresholds)
    captures = args.captures
    if captures is None:
        captures = int(booked.get("capturesPerCheck") or 3)
    if captures < 1:
        raise SystemExit("--captures must be >= 1")
    rows = select_rows(booked, args.scenario, args.all)
    output = args.output
    if output is None and args.from_artifacts is None:
        output = Path(tempfile.mkdtemp(prefix="cadr-liveness-check-"))

    failed = 0
    checked = 0
    for row in rows:
        scenario = row["scenario"]
        dimension = row["dimension"]
        threshold_ms = int(row["thresholdMs"])
        runs: list[dict] = []
        try:
            if args.from_artifacts is not None:
                timing = (
                    args.from_artifacts
                    / f"{scenario}.{dimension}.cadr.timing.json"
                )
                if not timing.is_file():
                    raise RuntimeError(f"missing timing artifact {timing}")
                runs.append(evaluate_run(gaps_ms(timing), threshold_ms))
            else:
                manifest = (
                    LIVENESS_MANIFEST
                    if scenario.startswith("liveness-")
                    else CORE_MANIFEST
                )
                for index in range(captures):
                    run_dir = output / f"{scenario}.{dimension}.{index + 1}"
                    run_dir.mkdir(parents=True, exist_ok=True)
                    timing = capture_timing(
                        manifest,
                        scenario,
                        dimension,
                        run_dir,
                        args.timeout,
                    )
                    runs.append(evaluate_run(gaps_ms(timing), threshold_ms))
        except Exception as error:
            print(
                f"liveness FAIL {scenario}/{dimension}: {error}",
                file=sys.stderr,
            )
            failed += 1
            checked += 1
            continue
        checked += 1
        if all(run["pass"] for run in runs):
            worst = max(run["worst_ms"] for run in runs)
            print(
                f"liveness PASS {scenario}/{dimension}: "
                f"{len(runs)} run(s) worst={worst}ms <= N_i={threshold_ms}ms"
            )
        else:
            print_failure(row, runs)
            failed += 1

    print(f"liveness summary: checked={checked} fail={failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
