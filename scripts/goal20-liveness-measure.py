#!/usr/bin/env python3
"""Goal 20, 12E-1 step 3: re-measure pi-side PTY output timing per scenario.

Captures every agent-turn scenario (non-empty faux `responses`) in both
dimensions, pi side, then the liveness manifest scenarios on both sides,
and aggregates each capture's `.timing.json` sidecar into per-scenario
gap statistics. The table feeds the N_i adjudication (proposal §3).

Usage:
  python3 scripts/goal20-liveness-measure.py [--output DIR] [--timeout S]

Writes <output>/liveness-measurement.json and liveness-measurement.md.
"""
import argparse
import importlib.util
import json
import statistics
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RENDER_DIFF = ROOT / "scripts/render-diff.py"
LIVENESS_MANIFEST = ROOT / "test/fixtures/render-diff/liveness-scenarios.json"


def load_render_diff():
    spec = importlib.util.spec_from_file_location("render_diff", RENDER_DIFF)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def gaps_from(timing_path: Path) -> list[float]:
    entries = json.loads(timing_path.read_text(encoding="ascii"))
    return [
        round(entries[i][0] - entries[i - 1][0], 6) for i in range(1, len(entries))
    ]


def stats_for(gaps: list[float]) -> dict[str, float | int]:
    if not gaps:
        return {"reads": 0, "median_ms": 0.0, "p95_ms": 0.0, "worst_ms": 0.0}
    ordered = sorted(gaps)
    p95_index = min(len(ordered) - 1, int(len(ordered) * 0.95))
    return {
        "reads": len(gaps) + 1,
        "median_ms": round(statistics.median(ordered) * 1000, 1),
        "p95_ms": round(ordered[p95_index] * 1000, 1),
        "worst_ms": round(ordered[-1] * 1000, 1),
    }


def run_capture(manifest: Path, scenario: str, dimension: str, side: str,
                output: Path, timeout: float, partial: bool) -> bool:
    command = [
        sys.executable, "-u", str(RENDER_DIFF), "capture",
        "--manifest", str(manifest),
        "--scenario", scenario,
        "--dimension", dimension,
        "--side", side,
        "--output", str(output),
        "--timeout", str(timeout),
    ]
    if partial:
        command.append("--allow-partial-coverage")
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"FAILED {scenario}/{dimension}/{side}: {result.stdout[-300:]}", flush=True)
        return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
                        default=ROOT / ".tmp/liveness-measurement")
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument("--quick", action="store_true",
                        help="only the liveness manifest scenarios")
    args = parser.parse_args()

    rd = load_render_diff()
    manifest = rd.load_manifest((ROOT / "test/fixtures/render-diff/scenarios.json"))
    agent_scenarios = [
        s for s in manifest["scenarios"] if s.get("responses")
    ]
    dimensions = [d["id"] for d in manifest["dimensions"]]

    rows = []
    failures = []
    started = time.monotonic()
    if not args.quick:
        for scenario in agent_scenarios:
            for dimension in dimensions:
                if not rd.scenario_allows_dimension(scenario, dimension):
                    continue
                side = "pi"
                ok = run_capture(manifest_path := ROOT / "test/fixtures/render-diff/scenarios.json",
                                 scenario["id"], dimension, side, args.output,
                                 args.timeout, partial=False)
                if not ok:
                    failures.append(f"{scenario['id']}/{dimension}/{side}")
                    continue
                timing = args.output / f"{scenario['id']}.{dimension}.{side}.timing.json"
                gaps = gaps_from(timing)
                rows.append({"scenario": scenario["id"], "dimension": dimension,
                             "side": side, **stats_for(gaps)})
                print(f"{scenario['id']} {dimension} {side}: {rows[-1]}", flush=True)

    liveness = json.loads(LIVENESS_MANIFEST.read_text(encoding="utf-8"))
    for scenario in liveness["scenarios"]:
        for dimension in dimensions:
            if not rd.scenario_allows_dimension(scenario, dimension):
                continue
            for side in ("pi", "cadr"):
                ok = run_capture(LIVENESS_MANIFEST, scenario["id"], dimension, side,
                                 args.output, args.timeout, partial=True)
                if not ok:
                    failures.append(f"{scenario['id']}/{dimension}/{side}")
                    continue
                timing = args.output / f"{scenario['id']}.{dimension}.{side}.timing.json"
                gaps = gaps_from(timing)
                rows.append({"scenario": scenario["id"], "dimension": dimension,
                             "side": side, **stats_for(gaps)})
                print(f"{scenario['id']} {dimension} {side}: {rows[-1]}", flush=True)

    elapsed = time.monotonic() - started
    payload = {
        "measuredAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "elapsedSeconds": round(elapsed, 1),
        "rows": rows,
        "failures": failures,
    }
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "liveness-measurement.json").write_text(
        json.dumps(payload, indent=1) + "\n", encoding="utf-8")

    lines = ["| scenario | dimension | side | reads | median ms | p95 ms | worst ms |",
             "|---|---|---|---:|---:|---:|---:|"]
    for row in rows:
        lines.append(
            f"| {row['scenario']} | {row['dimension']} | {row['side']} "
            f"| {row['reads']} | {row['median_ms']} | {row['p95_ms']} | {row['worst_ms']} |"
        )
    (args.output / "liveness-measurement.md").write_text(
        "\n".join(lines) + "\n", encoding="utf-8")
    print(f"done: {len(rows)} captures, {len(failures)} failures, {elapsed:.0f}s", flush=True)
    if failures:
        print("failures: " + ", ".join(failures), flush=True)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
