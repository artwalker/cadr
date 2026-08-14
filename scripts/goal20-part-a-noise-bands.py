#!/usr/bin/env python3
"""Goal 20 Part A: measure the adjudicated self-history drift bands.

Adjudicated shape (goal20-state.md, 2026-08-14): band = max(floor, 6 * MAD),
the same form scripts/goal20-paired-paths.py already uses.  Per metric:

- frame_render.5000.median_bytes: floor 4096 bytes (one page).  Allocation
  is deterministic (historical variance 0), so a sub-page change has no
  explainable source and a change above one page is a real change.
- cold_start.median_us: floor 10ms.  MAD is measured here at n >= 20 real
  PTY cold starts; if 6 * MAD exceeds 20% of the median the metric is
  recorded informational instead of widening the floor.
- frame_render.5000.median_us: always informational.  The reading is
  quantized at the 4000us timer step (observed sample set
  {0.0, 4000.0, 4001.0}); a band cannot express anything until the
  measurement itself gains resolution.

The output file is the machine-written source of truth the gate reads
(scripts/goal11-performance-gate.py).  Never hand-edit it; rerun this
script on the gate machine instead.

usage:
  python3 scripts/goal20-part-a-noise-bands.py \
      --bench /tmp/goal20-part-a-bench.json \
      [--cold-samples 20] [--cold-warmups 1] \
      [--output docs/benchmarks/goal20-part-a-noise-bands.json]
"""

from __future__ import annotations

import argparse
import json
import shutil
import statistics
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

PROJECT_DIRECTORY = Path(__file__).resolve().parents[1]

COLD_FLOOR_US = 10_000.0
ALLOCATION_FLOOR_BYTES = 4_096.0
MAD_MULTIPLIER = 6
COLD_INFORMATIONAL_FRACTION = 0.20

FRAME_TIME_REASON = (
    "reading is quantized at the 4000us timer step (observed sample set "
    "{0.0, 4000.0, 4001.0}); no band can be expressed until the "
    "measurement gains resolution"
)


def mad(values: list[float], center: float) -> float:
    return statistics.median(abs(value - center) for value in values)


def measure_cold_start(samples: int, warmups: int) -> list[float]:
    """Measure in an isolated /tmp tree, matching the verify.sh series.

    The gate compares verify-isolated history rows, which start the binary
    with the isolated project copy under /tmp as its cwd.  Measuring with
    the real repository as cwd is not the same experiment: an ancestor
    directory outside HOME carrying .agents/skills/ (for example
    /root/.agents/skills over /root/projects/cadr) makes startup stop at
    the project-trust prompt before the first frame.
    """
    binary = PROJECT_DIRECTORY / "cadr"
    helper = PROJECT_DIRECTORY / "scripts" / "goal11-cold-start.py"
    if not binary.is_file():
        raise SystemExit("build ./cadr first; the band must measure the release image")
    subprocess.run(
        [str(PROJECT_DIRECTORY / "scripts" / "check-root-binary.sh")], check=True
    )

    with tempfile.TemporaryDirectory(prefix="cadr-noise-band-") as scratch:
        workspace = Path(scratch) / "project"
        workspace.mkdir()
        for name in ("AGENTS.md",):
            source = PROJECT_DIRECTORY / name
            if source.is_file():
                shutil.copyfile(source, workspace / name)
        isolated_binary = workspace / "cadr"
        shutil.copyfile(binary, isolated_binary)
        isolated_binary.chmod(0o755)

        def one() -> float:
            output = subprocess.run(
                ["python3", str(helper), str(isolated_binary)],
                check=True,
                stdout=subprocess.PIPE,
                text=True,
            ).stdout.strip()
            return float(output)

        for _ in range(warmups):
            one()
        return [one() for _ in range(samples)]


def frame_point(bench: dict) -> dict:
    for point in bench["metrics"]["frame_render"]["points"]:
        if point.get("n") == 5000:
            return point
    raise SystemExit("bench report has no frame_render point at n=5000")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bench", type=Path, required=True)
    parser.add_argument("--cold-samples", type=int, default=20)
    parser.add_argument("--cold-warmups", type=int, default=1)
    parser.add_argument(
        "--output",
        type=Path,
        default=PROJECT_DIRECTORY / "docs/benchmarks/goal20-part-a-noise-bands.json",
    )
    args = parser.parse_args()
    if args.cold_samples < 20:
        raise SystemExit("the adjudication requires n >= 20 cold-start samples")

    bench = json.loads(args.bench.read_text(encoding="utf-8"))
    machine = bench["machine"]["machine_instance"]
    git_head = subprocess.run(
        ["git", "-C", str(PROJECT_DIRECTORY), "rev-parse", "HEAD"],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    ).stdout.strip()

    cold_samples = measure_cold_start(args.cold_samples, args.cold_warmups)
    cold_median = statistics.median(cold_samples)
    cold_mad = mad(cold_samples, cold_median)
    cold_band = max(COLD_FLOOR_US, MAD_MULTIPLIER * cold_mad)
    cold_informational = (
        MAD_MULTIPLIER * cold_mad > COLD_INFORMATIONAL_FRACTION * cold_median
    )

    point = frame_point(bench)
    alloc_median = float(point["median_bytes"])
    alloc_mad = float(point["mad_bytes"])
    alloc_band = max(ALLOCATION_FLOOR_BYTES, MAD_MULTIPLIER * alloc_mad)

    document = {
        "schemaVersion": 1,
        "generator": "scripts/goal20-part-a-noise-bands.py",
        "adjudication": (
            "2026-08-14 advisor ruling (goal20-state.md): shape "
            "max(floor, 6*MAD); floors 4096 bytes / 10ms; frame time "
            "informational until the measurement has resolution"
        ),
        "measuredAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "machine": machine,
        "gitHead": git_head,
        "benchLabel": bench.get("label")
        or (bench.get("provenance") or {}).get("label"),
        "metrics": {
            "cold_start.median_us": {
                "enforcement": "informational" if cold_informational else "fail-closed",
                "floor_us": COLD_FLOOR_US,
                "k": MAD_MULTIPLIER,
                "n": len(cold_samples),
                "median_us": cold_median,
                "mad_us": cold_mad,
                "band_us": cold_band,
                "samples_us": cold_samples,
                **(
                    {
                        "reason": (
                            f"6*MAD ({MAD_MULTIPLIER * cold_mad:.0f}us) exceeds "
                            f"{COLD_INFORMATIONAL_FRACTION:.0%} of the median "
                            f"({cold_median:.0f}us); the adjudication forbids "
                            "widening the floor to keep it fail-closed"
                        )
                    }
                    if cold_informational
                    else {}
                ),
            },
            "frame_render.5000.median_bytes": {
                "enforcement": "fail-closed",
                "floor_bytes": ALLOCATION_FLOOR_BYTES,
                "k": MAD_MULTIPLIER,
                "n": len(point["samples_bytes"]),
                "median_bytes": alloc_median,
                "mad_bytes": alloc_mad,
                "band_bytes": alloc_band,
                "samples_bytes": point["samples_bytes"],
            },
            "frame_render.5000.median_us": {
                "enforcement": "informational",
                "reason": FRAME_TIME_REASON,
                "n": len(point["samples_us"]),
                "median_us": point["median_us"],
                "mad_us": point["mad_us"],
                "samples_us": point["samples_us"],
            },
        },
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(document, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    for name, metric in document["metrics"].items():
        band = metric.get("band_us") or metric.get("band_bytes")
        print(
            f"noise-band: {name} enforcement={metric['enforcement']} "
            f"n={metric.get('n')} median={metric.get('median_us') or metric.get('median_bytes')} "
            f"mad={metric.get('mad_us') if 'mad_us' in metric else metric.get('mad_bytes')} "
            f"band={band}"
        )
    print(f"noise-band: output={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
