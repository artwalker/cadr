#!/usr/bin/env python3
"""Build an aggregate-only TUI session-size profile from local JSONL sessions."""

import argparse
import json
import math
import os
import sys
from pathlib import Path


PROFILE_KIND = "cadr-anonymous-session-scale"
STRESS_ENTRY_COUNT = 5000
COMMON_ENTRY_FLOOR = 50


def nearest_rank(values: list[int], fraction: float) -> int:
    if not values:
        return 0
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, math.ceil(fraction * len(ordered)) - 1))
    return ordered[index]


def active_path(records: list[dict]) -> list[dict]:
    entries = records[1:]
    if not entries:
        return []
    version = records[0].get("version", 1)
    if version == 1:
        return entries
    if not isinstance(version, int) or version < 1:
        raise ValueError("invalid session version")
    by_id: dict[str, dict] = {}
    for record in entries:
        identifier = record.get("id")
        if not isinstance(identifier, str) or identifier in by_id:
            raise ValueError("invalid or duplicate session entry id")
        by_id[identifier] = record
    current = entries[-1]["id"]
    seen: set[str] = set()
    result: list[dict] = []
    while current is not None:
        if current in seen or current not in by_id:
            raise ValueError("invalid active session path")
        seen.add(current)
        entry = by_id[current]
        result.append(entry)
        parent = entry.get("parentId")
        if parent is False:
            parent = None
        if parent is not None and not isinstance(parent, str):
            raise ValueError("invalid session parent id")
        current = parent
    result.reverse()
    return result


def assistant_tool_call_count(message: dict) -> int:
    content = message.get("content")
    if not isinstance(content, list):
        return 0
    return sum(
        1
        for block in content
        if isinstance(block, dict)
        and block.get("type") in ("toolCall", "tool_call")
    )


def projected_tui_entry_count(records: list[dict]) -> int:
    header = records[0] if records else None
    if not isinstance(header, dict) or header.get("type") != "session":
        raise ValueError("session header is missing")
    count = 0
    latest_compaction_seen = False
    for entry in active_path(records):
        entry_type = entry.get("type")
        if entry_type == "message":
            message = entry.get("message")
            if not isinstance(message, dict):
                raise ValueError("session message is invalid")
            role = message.get("role")
            if role in ("user", "assistant"):
                count += 1
            if role == "assistant":
                count += assistant_tool_call_count(message)
        elif entry_type == "custom_message" and entry.get("display") is True:
            count += 1
        elif entry_type == "compaction":
            latest_compaction_seen = True
    if latest_compaction_seen:
        count += 1
    return count


def read_session_count(path: Path) -> int:
    records: list[dict] = []
    with path.open(encoding="utf-8") as stream:
        for line in stream:
            if not line.strip():
                continue
            record = json.loads(line)
            if not isinstance(record, dict):
                raise ValueError("session row is not an object")
            records.append(record)
    return projected_tui_entry_count(records)


def build_profile(session_directory: Path) -> dict:
    paths = sorted(session_directory.glob("*.jsonl")) if session_directory.is_dir() else []
    counts: list[int] = []
    invalid = 0
    for path in paths:
        try:
            counts.append(read_session_count(path))
        except (OSError, UnicodeError, ValueError, json.JSONDecodeError):
            invalid += 1
    percentiles = {
        "min": min(counts, default=0),
        "p50": nearest_rank(counts, 0.50),
        "p90": nearest_rank(counts, 0.90),
        "p95": nearest_rank(counts, 0.95),
        "p99": nearest_rank(counts, 0.99),
        "max": max(counts, default=0),
    }
    return {
        "schema_version": 1,
        "kind": PROFILE_KIND,
        "source_file_count": len(paths),
        "valid_session_count": len(counts),
        "invalid_session_count": invalid,
        "entry_percentiles": percentiles,
        "tiers": {
            "typical": percentiles["p50"],
            "common": max(COMMON_ENTRY_FLOOR, percentiles["p95"]),
            "heavy": percentiles["p99"],
            "stress": STRESS_ENTRY_COUNT,
        },
        "privacy": {
            "contains_message_content": False,
            "contains_session_identifiers": False,
            "contains_paths": False,
            "contains_timestamps": False,
            "contains_provider_or_model": False,
        },
    }


def write_profile(profile: dict, output: str) -> None:
    serialized = json.dumps(profile, sort_keys=True, separators=(",", ":")) + "\n"
    if output == "-":
        sys.stdout.write(serialized)
        return
    target = Path(output)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(f".{target.name}.tmp-{os.getpid()}")
    try:
        temporary.write_text(serialized, encoding="utf-8")
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sessions", required=True)
    parser.add_argument("--output", default="-")
    args = parser.parse_args()
    write_profile(build_profile(Path(args.sessions)), args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
