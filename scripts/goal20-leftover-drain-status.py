#!/usr/bin/env python3
"""Goal 20 leftover drain status and loop tick payloads.

Serial band: open leftover pairing PRs below the unused-slug remount mill (PR #325+).
Exit predicate: drain that band; keep needs-pair=0 and uncovered=0; never mark G.17 met.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = "artwalker/cadr"
SERIAL_MIN_PR = 182
SERIAL_MAX_PR = 324
REMOUNT_RE = re.compile(r"unused[- ]slug|remount mill", re.I)
LEFTOVER_RE = re.compile(r"leftover|goal 20", re.I)
PAIR_NUM_RE = re.compile(r"\b(\d{3,4})\s*[–-]\s*(\d{3,4})\b")


def git_head() -> str:
    return subprocess.check_output(
        ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
    ).strip()


def git_head_short() -> str:
    return subprocess.check_output(
        ["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"], text=True
    ).strip()


def inventory_counts() -> dict[str, int]:
    inv_path = ROOT / "docs/benchmarks/goal20-unpaired-paths.json"
    inv = json.loads(inv_path.read_text(encoding="utf-8"))
    needs = sum(1 for e in inv.get("fileRules", []) if e.get("class") == "needs-pair")
    paired = len(inv.get("pairedMetrics", []))
    return {"needs_pair": needs, "paired_metrics": paired}


def open_leftover_prs() -> list[dict]:
    raw = subprocess.check_output(
        [
            "gh",
            "pr",
            "list",
            "-R",
            REPO,
            "--state",
            "open",
            "--base",
            "cadr-migration",
            "--limit",
            "200",
            "--json",
            "number,title,headRefName,url",
        ],
        text=True,
    )
    rows = json.loads(raw)
    serial: list[dict] = []
    for row in rows:
        number = int(row["number"])
        title = row["title"]
        if number < SERIAL_MIN_PR or number > SERIAL_MAX_PR:
            continue
        if REMOUNT_RE.search(title):
            continue
        if not LEFTOVER_RE.search(title):
            continue
        serial.append(row)
    serial.sort(key=lambda r: int(r["number"]))
    return serial


def pair_span(title: str) -> str | None:
    match = PAIR_NUM_RE.search(title)
    if not match:
        return None
    return f"{match.group(1)}-{match.group(2)}"


def build_prompt(next_pr: dict | None, head: str, inv: dict[str, int]) -> str:
    next_line = "none (band drained or blocked)"
    if next_pr is not None:
        span = pair_span(next_pr["title"]) or "?"
        next_line = f"#{next_pr['number']} ({span}) {next_pr['title']}"

    return (
        "Goal20 leftover drain on /root/projects/cadr branch cadr-migration. "
        f"Tip {head}. Inventory needs-pair={inv['needs_pair']} paired_metrics={inv['paired_metrics']}. "
        "Exit when open serial leftover pairing PRs (#182-324 inclusive, non-remount) are drained "
        "(merge onto tip or close superseded if metrics already on pairedMetrics); "
        "keep needs-pair=0 and uncovered=0; never mark G.17 met; never announce Goal 20 complete; "
        "skip unused-slug remount PRs (#325+). "
        "On wake read the latest AGENT_LOOP_TICK_goal20 JSON from the terminal file and run its prompt. "
        "Each tick land or close one leftover trio (wire cherry-pick, scoped gate, n=5 harness, book, merge, inventory sync, close leftover PR); "
        "log .audit/goal20-needs-pair.tsv; self-chain the next unit in the same session after each landing. "
        f"Next serial unit: {next_line}."
    )


def status_payload() -> dict:
    inv = inventory_counts()
    head = git_head()
    head_short = git_head_short()
    serial = open_leftover_prs()
    next_pr = serial[0] if serial else None
    return {
        "head": head,
        "head_short": head_short,
        "needs_pair": inv["needs_pair"],
        "paired_metrics": inv["paired_metrics"],
        "open_serial_leftovers": len(serial),
        "next_pr": next_pr,
        "prompt": build_prompt(next_pr, head_short, inv),
        "complete": len(serial) == 0 and inv["needs_pair"] == 0,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "mode",
        nargs="?",
        default="json",
        choices=("json", "emit-tick", "prompt"),
    )
    args = parser.parse_args()
    payload = status_payload()
    if args.mode == "prompt":
        print(payload["prompt"])
        return 0
    if args.mode == "emit-tick":
        tick = {
            "event": "leftover_drain_tick",
            "head": payload["head_short"],
            "needs_pair": payload["needs_pair"],
            "open_serial_leftovers": payload["open_serial_leftovers"],
            "next_pr": payload["next_pr"]["number"] if payload["next_pr"] else None,
            "complete": payload["complete"],
            "prompt": payload["prompt"],
        }
        print(json.dumps(tick, separators=(",", ":")))
        return 0
    print(json.dumps(payload, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
