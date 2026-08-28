#!/usr/bin/env python3
"""Sharded Goal 20 paired-path history: ledger + per-lane shards.

The 16MB monolith is a stub. Pair records live in
docs/benchmarks/paired/<lane>.json. Readers union shards; writers append
one lane's shard only. CI must not regenerate a combined file.

Schema on cadr-migration (this tip): each history file is
{"schemaVersion": 1, "entries": [...]} with entry fields recordedAt, label,
gitHead, machine, quick, sameMachine, ratioGate, samples, metrics, notes.
The lock file docs/benchmarks/goal20-ledger.json is only schemaVersion and
nextPairNum.
"""

from __future__ import annotations

import json
import re
from functools import lru_cache
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INDEX_PATH = ROOT / "docs/benchmarks/goal20-paired-paths.json"
LEDGER_PATH = ROOT / "docs/benchmarks/goal20-ledger.json"
SHARD_DIR = ROOT / "docs/benchmarks/paired"
LISP_PROVENANCE = ROOT / "scripts/goal20-paired-paths.lisp"
LANES = ("agent", "ai", "cli", "tools", "core", "evals", "tui", "other")
SCHEMA_VERSION = 1
APPEND_SUFFIX = "\n  ]\n}\n"

SHARD_ASSIGNMENT = (
    "src/cadr-agent/ → agent; src/cadr-ai/ → ai; "
    "src/cadr-cli/tools/ → tools; src/cadr-cli/ → cli; "
    "src/cadr-core/ → core; src/cadr-evals/ → evals; "
    "src/cadr-tui/ → tui; else other. "
    "Full-book rows (ratio_gate enforced or informational-quick-run) stay "
    "in other. Leftover enforced-only rows go to the unique lane of those "
    "metrics' cadr sources."
)


def shard_relpath(lane: str) -> str:
    if lane not in LANES:
        raise ValueError(f"unknown paired-path lane {lane!r}")
    return f"docs/benchmarks/paired/{lane}.json"


def shard_path(lane: str) -> Path:
    return ROOT / shard_relpath(lane)


def index_document() -> dict:
    return {
        "schemaVersion": SCHEMA_VERSION,
        "sharded": True,
        "ledger": "docs/benchmarks/goal20-ledger.json",
        "shards": [shard_relpath(lane) for lane in LANES],
        "assignment": SHARD_ASSIGNMENT,
        "note": (
            "Readers union shards + ledger. Do not regenerate a combined "
            "16MB file in CI."
        ),
    }


def load_ledger(path: Path | None = None) -> dict:
    ledger_path = path or LEDGER_PATH
    document = json.loads(ledger_path.read_text(encoding="utf-8"))
    if document.get("schemaVersion") != SCHEMA_VERSION:
        raise ValueError(f"{ledger_path} schemaVersion must be {SCHEMA_VERSION}")
    next_pair = document.get("nextPairNum")
    if not isinstance(next_pair, int) or isinstance(next_pair, bool) or next_pair < 0:
        raise ValueError(f"{ledger_path} nextPairNum must be a non-negative integer")
    return document


def is_sharded_index(document: dict) -> bool:
    shards = document.get("shards")
    return bool(document.get("sharded")) and isinstance(shards, list) and shards


def resolve_repo_path(value: str | Path) -> Path:
    path = Path(value)
    if path.is_absolute():
        return path
    return ROOT / path


@lru_cache(maxsize=1)
def metric_cadr_sources() -> dict[str, str]:
    text = LISP_PROVENANCE.read_text(encoding="utf-8")
    start = text.find("(defun provenance-json")
    end = text.find("(defun run-benchmarks")
    if start < 0 or end < 0 or end <= start:
        raise ValueError("cannot locate provenance-json in goal20-paired-paths.lisp")
    pairs = re.findall(
        r'"([a-z0-9_]+\.[a-z0-9_]+)"\s*\n\s*"(src/[^"]+)"',
        text[start:end],
    )
    sources: dict[str, str] = {}
    for key, source in pairs:
        sources[key] = source.split()[0]
    return sources


def lane_for_cadr_source(source: str) -> str:
    if source.startswith("src/cadr-agent/"):
        return "agent"
    if source.startswith("src/cadr-ai/"):
        return "ai"
    if source.startswith("src/cadr-cli/tools/"):
        return "tools"
    if source.startswith("src/cadr-cli/"):
        return "cli"
    if source.startswith("src/cadr-core/"):
        return "core"
    if source.startswith("src/cadr-evals/"):
        return "evals"
    if source.startswith("src/cadr-tui/"):
        return "tui"
    return "other"


def lane_for_unknown_metric(key: str) -> str | None:
    group = key.split(".", 1)[0]
    lanes = {
        lane_for_cadr_source(source)
        for metric, source in metric_cadr_sources().items()
        if metric.startswith(group + ".")
    }
    if len(lanes) == 1:
        return next(iter(lanes))
    return None


def lane_for_metrics(keys: list[str]) -> str:
    known: set[str] = set()
    unknown: list[str] = []
    sources = metric_cadr_sources()
    for key in keys:
        source = sources.get(key)
        if source:
            known.add(lane_for_cadr_source(source))
        else:
            unknown.append(key)
    if known:
        if len(known) == 1:
            return next(iter(known))
        return "other"
    inferred: set[str] = set()
    for key in unknown:
        lane = lane_for_unknown_metric(key)
        inferred.add(lane or "other")
    if len(inferred) == 1:
        return next(iter(inferred))
    return "other"


def enforced_only_metrics(ratio_gate: str | None) -> list[str] | None:
    if not isinstance(ratio_gate, str) or not ratio_gate.startswith("enforced-only:"):
        return None
    keys = [part.strip() for part in ratio_gate.split(":", 1)[1].split(",")]
    return [key for key in keys if key]


def lane_for_entry(entry: dict) -> str:
    keys = enforced_only_metrics(entry.get("ratioGate"))
    if not keys:
        return "other"
    return lane_for_metrics(keys)


def load_shard_entries(path: Path) -> list[dict]:
    document = json.loads(path.read_text(encoding="utf-8"))
    if document.get("schemaVersion") != SCHEMA_VERSION:
        raise ValueError(f"{path} schemaVersion must be {SCHEMA_VERSION}")
    entries = document.get("entries")
    if not isinstance(entries, list):
        raise ValueError(f"{path} entries must be an array")
    return entries


def load_paired_history(path: Path | None = None) -> dict:
    """Load a concrete history file or union sharded index + ledger."""
    history_path = path or INDEX_PATH
    document = json.loads(history_path.read_text(encoding="utf-8"))
    if not is_sharded_index(document):
        document.setdefault("schemaVersion", SCHEMA_VERSION)
        document.setdefault("entries", [])
        return document
    entries: list[dict] = []
    for shard in document["shards"]:
        entries.extend(load_shard_entries(resolve_repo_path(shard)))
    entries.sort(
        key=lambda entry: (
            str(entry.get("recordedAt") or ""),
            str(entry.get("gitHead") or ""),
            str(entry.get("ratioGate") or ""),
        )
    )
    history = {"schemaVersion": SCHEMA_VERSION, "entries": entries}
    ledger_value = document.get("ledger")
    if ledger_value:
        ledger = load_ledger(resolve_repo_path(ledger_value))
        history["nextPairNum"] = ledger["nextPairNum"]
    return history


def write_json(path: Path, document: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(document, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def append_entry_to_file(history_path: Path, entry: dict) -> dict:
    """Append one entry. Existing pair objects are not re-dumped when the
    file already has entries and is append-splicable.
    """
    if history_path.is_file():
        raw = history_path.read_text(encoding="utf-8")
        history = json.loads(raw)
    else:
        raw = None
        history = {"schemaVersion": SCHEMA_VERSION, "entries": []}
    history.setdefault("schemaVersion", SCHEMA_VERSION)
    existing = list(history.get("entries") or [])
    history["entries"] = existing + [entry]
    history_path.parent.mkdir(parents=True, exist_ok=True)
    if raw is None or not existing:
        write_json(history_path, history)
        return history
    if not raw.endswith(APPEND_SUFFIX):
        raise ValueError(
            f"paired-path history {history_path} is not append-splicable"
        )
    dumped = json.dumps(entry, indent=2, ensure_ascii=False)
    indented = "\n".join(
        ("  " + line if line else line) for line in dumped.split("\n")
    )
    history_path.write_text(
        raw[: -len(APPEND_SUFFIX)] + ",\n" + indented + APPEND_SUFFIX,
        encoding="utf-8",
    )
    return history


def shard_file_for_lane(document: dict, lane: str) -> Path:
    expected = f"{lane}.json"
    for shard in document.get("shards") or []:
        path = resolve_repo_path(shard)
        if path.name == expected:
            return path
    return shard_path(lane)


def append_entry(history_path: Path, entry: dict, lane: str | None = None) -> dict:
    if history_path.is_file():
        header = json.loads(history_path.read_text(encoding="utf-8"))
    else:
        header = {}
    if is_sharded_index(header) or history_path.resolve() == INDEX_PATH.resolve():
        target_lane = lane or lane_for_entry(entry)
        target = (
            shard_file_for_lane(header, target_lane)
            if is_sharded_index(header)
            else shard_path(target_lane)
        )
        append_entry_to_file(target, entry)
        return load_paired_history(
            history_path if history_path.is_file() else INDEX_PATH
        )
    return append_entry_to_file(history_path, entry)


def split_monolith(monolith_path: Path | None = None) -> dict[str, int]:
    """Move existing entries into lane shards once. Does not re-measure."""
    source = monolith_path or INDEX_PATH
    document = json.loads(source.read_text(encoding="utf-8"))
    if is_sharded_index(document):
        raise ValueError(f"{source} is already a sharded index")
    entries = list(document.get("entries") or [])
    pre_count = len(entries)
    buckets: dict[str, list[dict]] = {lane: [] for lane in LANES}
    for entry in entries:
        buckets[lane_for_entry(entry)].append(entry)
    SHARD_DIR.mkdir(parents=True, exist_ok=True)
    counts = {lane: len(buckets[lane]) for lane in LANES}
    if sum(counts.values()) != pre_count:
        raise ValueError(
            f"shard assignment lost entries: {sum(counts.values())} != {pre_count}"
        )
    for lane in LANES:
        write_json(
            shard_path(lane),
            {"schemaVersion": SCHEMA_VERSION, "entries": buckets[lane]},
        )
    write_json(LEDGER_PATH, {"schemaVersion": SCHEMA_VERSION, "nextPairNum": 328})
    write_json(INDEX_PATH, index_document())
    counts["pre"] = pre_count
    counts["post"] = sum(len(load_shard_entries(shard_path(lane))) for lane in LANES)
    return counts
