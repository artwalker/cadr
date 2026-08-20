#!/usr/bin/env python3
"""Append one paired-path run to the Goal 20 Part B history JSON.

Reads a gate summary plus the cadr half-report (medians, machine, git).
Baseline microseconds are cadr_median / ratio so this script never opens the
peer report. scripts/write-performance-ledger.py then rewrites the marked
section in docs/performance.md. Numbers are never hand-edited.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WRITER = ROOT / "scripts" / "write-performance-ledger.py"

METRIC_KEYS = (
    "cli_dispatch.argv_parse",
    "cli_dispatch.help_render",
    "cli_dispatch.list_models_registry",
    "cli_dispatch.list_models_render",
    "provider_stream.stream_roundtrip",
    "provider_anthropic.stream_roundtrip",
    "provider_google.stream_roundtrip",
    "provider_bedrock.stream_roundtrip",
    "cli_settings.create",
    "session_pipeline.session_load",
    "session_pipeline.context_walk",
    "storage_journal.journal_read",
    "storage_journal.journal_append",
    "sqlite_session.open_walk",
    "tool_read.text_file",
    "tool_grep.context_file",
    "agent_tool_loop.roundtrip",
    "session_compact.compact",
)


def metric_median(report: dict, key: str) -> float:
    group, name = key.split(".", 1)
    return float(report["metrics"][group][name]["median_us"])


def build_entry(
    summary: dict,
    cadr: dict,
    recorded_at: str | None = None,
) -> dict:
    ratios = summary["ratios"]
    ceilings = summary["ceilings"]
    metrics: dict[str, dict] = {}
    for key in METRIC_KEYS:
        if key not in ratios or key not in ceilings:
            raise ValueError(f"summary is missing {key}")
        ratio = float(ratios[key])
        if ratio <= 0:
            raise ValueError(f"{key} ratio must be positive, got {ratio}")
        cadr_us = metric_median(cadr, key)
        metrics[key] = {
            "cadrMedianUs": cadr_us,
            "baselineMedianUs": cadr_us / ratio,
            "ratio": ratio,
            "ceiling": float(ceilings[key]),
        }
    params = cadr.get("parameters") or {}
    provenance = cadr.get("provenance") or {}
    machine = cadr.get("machine") or {}
    quick = bool(params.get("quick"))
    return {
        "recordedAt": recorded_at
        or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "label": "paired-paths-quick" if quick else "paired-paths",
        "gitHead": provenance.get("source_revision"),
        "machine": machine.get("machine_instance"),
        "quick": quick,
        "sameMachine": bool(summary.get("same_machine")),
        "ratioGate": summary.get("ratio_gate"),
        "samples": params.get("samples"),
        "metrics": metrics,
        "notes": list(summary.get("notes") or []),
    }


def append_entry(history_path: Path, entry: dict) -> dict:
    if history_path.is_file():
        history = json.loads(history_path.read_text(encoding="utf-8"))
    else:
        history = {"schemaVersion": 1, "entries": []}
    history.setdefault("schemaVersion", 1)
    history.setdefault("entries", []).append(entry)
    history_path.parent.mkdir(parents=True, exist_ok=True)
    history_path.write_text(
        json.dumps(history, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return history


def rewrite_ledger(history_path: Path, ledger_path: Path) -> None:
    result = subprocess.run(
        [
            sys.executable,
            str(WRITER),
            "--history",
            str(ROOT / "docs/benchmarks/performance-history.json"),
            "--paired",
            str(history_path),
            "--ledger",
            str(ledger_path),
        ],
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"write-performance-ledger.py exited {result.returncode}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--summary", type=Path, required=True)
    parser.add_argument("--cadr-report", type=Path, required=True)
    parser.add_argument(
        "--history",
        type=Path,
        default=ROOT / "docs/benchmarks/goal20-paired-paths.json",
    )
    parser.add_argument(
        "--ledger",
        type=Path,
        default=ROOT / "docs/performance.md",
    )
    parser.add_argument("--recorded-at", help="UTC timestamp override")
    parser.add_argument(
        "--skip-ledger",
        action="store_true",
        help="append JSON only; do not rewrite docs/performance.md",
    )
    args = parser.parse_args()
    try:
        summary = json.loads(args.summary.read_text(encoding="utf-8"))
        cadr = json.loads(args.cadr_report.read_text(encoding="utf-8"))
        entry = build_entry(summary, cadr, args.recorded_at)
        history = append_entry(args.history, entry)
        if not args.skip_ledger:
            rewrite_ledger(args.history, args.ledger)
        append_ratio = entry["metrics"]["storage_journal.journal_append"]["ratio"]
        print(
            "paired-path-history: "
            f"entries={len(history['entries'])} "
            f"ratio_gate={entry.get('ratioGate')} "
            f"quick={str(entry['quick']).lower()} "
            f"journal_append={append_ratio:.2f}x "
            f"output={args.history}"
        )
        return 0
    except (OSError, KeyError, TypeError, ValueError, RuntimeError, json.JSONDecodeError) as error:
        print(f"paired-path-history: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
