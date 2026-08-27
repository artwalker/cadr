#!/usr/bin/env python3
"""Audit render-diff disposition ledger against scenarios manifest and analysis."""
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "test/fixtures/render-diff/scenarios.json"
DEFAULT_DISPOSITIONS = ROOT / "test/fixtures/render-diff/dispositions.json"
DEFAULT_ANALYSIS = Path("/tmp/goal21-render-diff-analysis")
DEFAULT_REPORT = Path("/tmp/goal21-disposition-audit.json")


def load_render_diff() -> Any:
    spec = importlib.util.spec_from_file_location("render_diff", ROOT / "scripts/render-diff.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load scripts/render-diff.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def manifest_keys(manifest: dict[str, Any], rd: Any) -> set[str]:
    keys: set[str] = set()
    for scenario in manifest["scenarios"]:
        scenario_id = scenario["id"]
        dimensions = scenario.get("dimensions") or [
            dimension["id"] for dimension in manifest["dimensions"]
        ]
        checkpoints = set(rd.scenario_checkpoint_ids(scenario)) | {"process-exit"}
        for checkpoint in checkpoints:
            for dimension in dimensions:
                if rd.scenario_allows_dimension(scenario, dimension):
                    keys.add(f"{scenario_id}/{dimension}/{checkpoint}")
    return keys


def stale_entries(data: dict[str, Any], manifest: dict[str, Any], rd: Any) -> list[dict[str, Any]]:
    scenarios = {
        scenario["id"]: set(rd.scenario_checkpoint_ids(scenario)) | {"process-exit"}
        for scenario in manifest["scenarios"]
    }
    stale: list[dict[str, Any]] = []
    for entry in data.get("entries", []):
        scenario = entry.get("scenario")
        checkpoint = entry.get("checkpoint")
        if scenario not in scenarios or checkpoint not in scenarios[scenario]:
            stale.append(
                {
                    "scenario": scenario,
                    "checkpoint": checkpoint,
                    "dimensions": entry.get("dimensions", []),
                }
            )
    return stale


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--dispositions", type=Path, default=DEFAULT_DISPOSITIONS)
    parser.add_argument("--analysis", type=Path, default=DEFAULT_ANALYSIS)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--validate-only", action="store_true")
    parser.add_argument("--prune-stale", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    rd = load_render_diff()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    data = json.loads(args.dispositions.read_text(encoding="utf-8"))

    validation_error: str | None = None
    expanded: dict[str, Any] = {}
    try:
        expanded = rd.expand_dispositions(data, manifest)
    except Exception as exc:  # HarnessFailure
        validation_error = str(exc)

    required = manifest_keys(manifest, rd)
    booked = set(expanded.keys())
    manifest_missing = sorted(required - booked)
    manifest_extra = sorted(booked - required)
    process_exit_missing = sorted(
        key for key in manifest_missing if key.endswith("/process-exit")
    )
    actionable_manifest_missing = sorted(
        key for key in manifest_missing if not key.endswith("/process-exit")
    )
    stale = stale_entries(data, manifest, rd)

    analysis_missing: list[str] = []
    analysis_stale: list[str] = []
    pending_path = args.analysis / "pending-dispositions.json"
    if pending_path.is_file():
        pending = json.loads(pending_path.read_text(encoding="utf-8"))
        analysis_missing = list(pending.get("missing", []))
        analysis_stale = list(pending.get("stale", []))

    report: dict[str, Any] = {
        "validationError": validation_error,
        "entryCount": len(data.get("entries", [])),
        "expandedKeyCount": len(expanded),
        "manifestPossibleKeys": len(required),
        "manifestMissingKeys": manifest_missing,
        "manifestMissingProcessExitOnly": process_exit_missing,
        "manifestMissingActionable": actionable_manifest_missing,
        "manifestExtraKeys": manifest_extra,
        "staleEntries": stale,
        "analysisMissingKeys": analysis_missing,
        "analysisStaleKeys": analysis_stale,
        "pruned": False,
    }
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    print(
        "goal21-render-diff-audit: "
        f"entries={report['entryCount']} expanded={report['expandedKeyCount']} "
        f"manifest_missing={len(manifest_missing)} manifest_extra={len(manifest_extra)} "
        f"stale_entries={len(stale)} analysis_missing={len(analysis_missing)} "
        f"report={args.report}"
    )

    if validation_error is not None:
        print(f"goal21-render-diff-audit: validation failed: {validation_error}", file=sys.stderr)
        if not args.prune_stale or not stale:
            return 1

    if args.prune_stale and stale and not args.dry_run:
        stale_targets = {(row["scenario"], row["checkpoint"]) for row in stale}
        kept: list[dict[str, Any]] = []
        for entry in data.get("entries", []):
            target = (entry.get("scenario"), entry.get("checkpoint"))
            if target in stale_targets:
                continue
            kept.append(entry)
        data["entries"] = kept
        args.dispositions.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        report["pruned"] = True
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"goal21-render-diff-audit: pruned {len(stale)} stale entries")

    if args.validate_only:
        return 1 if validation_error is not None else 0

    if validation_error is not None:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
