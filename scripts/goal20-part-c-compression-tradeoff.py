#!/usr/bin/env python3
"""Goal 20 Part C: price the core-compression trade.

Builds an uncompressed control image with the production save arguments
minus compression (cadr-cli:native-image-save-arguments called with a
feature list lacking :sb-core-compression, so every other flag stays
identical), then measures cold start for both images with the same real
PTY harness (scripts/goal11-cold-start.py: new process to first real TUI
frame, fresh temporary HOME, no credentials; --version/--help paths are
rejected by definition, docs/performance.md:51-55).

Samples are interleaved (compressed, uncompressed, compressed, ...) so a
slow machine drift cannot bias one column.  Both binaries are measured
from an isolated /tmp workspace for the same reason the Part A band
script does: with the repository as cwd, an ancestor .agents/skills/
directory outside the temporary HOME stops startup at the project-trust
prompt before the first frame.

The verdict on keeping compression is a product decision and is not made
here; this script only writes the size/latency evidence to
docs/benchmarks/goal20-part-c-compression.json.

usage:
  python3 scripts/goal20-part-c-compression-tradeoff.py \
      [--samples 20] [--warmups 1] \
      [--output docs/benchmarks/goal20-part-c-compression.json]
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import statistics
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

PROJECT_DIRECTORY = Path(__file__).resolve().parents[1]

UNCOMPRESSED_BUILD_TEMPLATE = """(require "asdf")

(defparameter *cadr-build-root* #p"{root}/")

(defun build-path (name)
  (merge-pathnames name *cadr-build-root*))

(let ((quicklisp-setup (uiop:getenv "QUICKLISP_SETUP")))
  (unless (and quicklisp-setup (probe-file quicklisp-setup))
    (error "QUICKLISP_SETUP does not name a readable file"))
  (load quicklisp-setup))

(dolist (system '("cadr-core" "cadr-ai" "cadr-agent" "cadr-tui" "cadr-cli"))
  (asdf:load-asd (truename (build-path (format nil "~A.asd" system)))))

(let ((*debug-io* (make-broadcast-stream)))
  (asdf:load-system "slynk/mrepl"))
(asdf:load-system "cadr-cli")

;; Production arguments minus compression: pass a feature list without
;; :sb-core-compression through the one production owner of these flags.
(apply
 #'sb-ext:save-lisp-and-die
 "{output}"
 (cadr-cli:native-image-save-arguments
  (remove :sb-core-compression *features*)))
"""


def mad(values: list[float], center: float) -> float:
    return statistics.median(abs(value - center) for value in values)


def build_uncompressed(target: Path) -> None:
    build_file = target.parent / "build-uncompressed.lisp"
    build_file.write_text(
        UNCOMPRESSED_BUILD_TEMPLATE.format(
            root=str(PROJECT_DIRECTORY).rstrip("/"), output=target
        ),
        encoding="utf-8",
    )
    environment = dict(os.environ)
    environment.setdefault(
        "QUICKLISP_SETUP", str(Path.home() / "quicklisp/setup.lisp")
    )
    result = subprocess.run(
        [
            environment.get("SBCL", "sbcl"),
            "--noinform",
            "--disable-debugger",
            "--script",
            str(build_file),
        ],
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    if result.returncode != 0:
        raise SystemExit(
            f"uncompressed build failed ({result.returncode}):\n{result.stdout[-4000:]}"
        )
    if not target.is_file():
        raise SystemExit("uncompressed build produced no image")
    target.chmod(0o755)


def isolated_workspace(binary: Path, scratch: Path, name: str) -> Path:
    workspace = scratch / name
    workspace.mkdir()
    agents = PROJECT_DIRECTORY / "AGENTS.md"
    if agents.is_file():
        shutil.copyfile(agents, workspace / "AGENTS.md")
    isolated = workspace / "cadr"
    shutil.copyfile(binary, isolated)
    isolated.chmod(0o755)
    return isolated


def cold_start(binary: Path) -> float:
    helper = PROJECT_DIRECTORY / "scripts" / "goal11-cold-start.py"
    output = subprocess.run(
        ["python3", str(helper), str(binary)],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    ).stdout.strip()
    return float(output)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=20)
    parser.add_argument("--warmups", type=int, default=1)
    parser.add_argument(
        "--output",
        type=Path,
        default=PROJECT_DIRECTORY / "docs/benchmarks/goal20-part-c-compression.json",
    )
    args = parser.parse_args()
    if args.samples < 20:
        raise SystemExit("use n >= 20, matching the Part A cold-start discipline")

    compressed = PROJECT_DIRECTORY / "cadr"
    if not compressed.is_file():
        raise SystemExit("build ./cadr first; the trade must price the release image")
    subprocess.run(
        [str(PROJECT_DIRECTORY / "scripts" / "check-root-binary.sh")], check=True
    )
    git_head = subprocess.run(
        ["git", "-C", str(PROJECT_DIRECTORY), "rev-parse", "HEAD"],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    ).stdout.strip()

    with tempfile.TemporaryDirectory(prefix="cadr-part-c-") as scratch_text:
        scratch = Path(scratch_text)
        uncompressed = scratch / "cadr-uncompressed"
        print("part-c: building the uncompressed control image ...")
        build_uncompressed(uncompressed)

        sizes = {
            "compressed": compressed.stat().st_size,
            "uncompressed": uncompressed.stat().st_size,
        }
        print(
            f"part-c: sizes compressed={sizes['compressed']:,}B "
            f"uncompressed={sizes['uncompressed']:,}B"
        )

        binaries = {
            "compressed": isolated_workspace(compressed, scratch, "compressed-ws"),
            "uncompressed": isolated_workspace(
                uncompressed, scratch, "uncompressed-ws"
            ),
        }
        for _ in range(args.warmups):
            for variant in ("compressed", "uncompressed"):
                cold_start(binaries[variant])
        samples: dict[str, list[float]] = {"compressed": [], "uncompressed": []}
        for index in range(args.samples):
            for variant in ("compressed", "uncompressed"):
                samples[variant].append(cold_start(binaries[variant]))
            print(
                f"part-c: sample {index + 1}/{args.samples} "
                f"compressed={samples['compressed'][-1]:,.0f}us "
                f"uncompressed={samples['uncompressed'][-1]:,.0f}us"
            )

    variants = {}
    for variant in ("compressed", "uncompressed"):
        median = statistics.median(samples[variant])
        variants[variant] = {
            "binary_bytes": sizes[variant],
            "n": len(samples[variant]),
            "cold_start_median_us": median,
            "cold_start_mad_us": mad(samples[variant], median),
            "cold_start_samples_us": samples[variant],
        }

    document = {
        "schemaVersion": 1,
        "generator": "scripts/goal20-part-c-compression-tradeoff.py",
        "measuredAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "machine": platform.node(),
        "gitHead": git_head,
        "harness": (
            "scripts/goal11-cold-start.py, new process to first real TUI frame, "
            "fresh temporary HOME, no credentials, isolated /tmp workspace, "
            "interleaved sampling"
        ),
        "save_arguments": (
            "cadr-cli:native-image-save-arguments; control drops "
            ":sb-core-compression from the feature list, all other flags equal"
        ),
        "variants": variants,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(document, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    for variant, data in variants.items():
        print(
            f"part-c: {variant} {data['binary_bytes']:,}B "
            f"median={data['cold_start_median_us']:,.0f}us "
            f"mad={data['cold_start_mad_us']:,.0f}us n={data['n']}"
        )
    print(f"part-c: output={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
