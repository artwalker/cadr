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
    "provider_mistral.stream_roundtrip",
    "provider_openai_responses.stream_roundtrip",
    "provider_azure_openai.stream_roundtrip",
    "provider_vertex.stream_roundtrip",
    "provider_codex.stream_roundtrip",
    "provider_pi_messages.stream_roundtrip",
    "cli_settings.create",
    "settings_load.project_trust",
    "settings_load.config_value",
    "settings_load.http_idle",
    "resource_loader.reload",
    "package_manager.resolve",
    "session_discovery.header_probe",
    "session_export_html.to_html",
    "protocol_cbor.roundtrip",
    "agent_schema.validate_ok_fail",
    "harness_storage.open_walk",
    "protocol_codec.roundtrip",
    "agent_proxy.stream_roundtrip",
    "oauth_pkce.challenge_urls",
    "oauth_pkce_device.poll",
    "oauth_pkce_device.auth_json",
    "oauth_pkce_device.copilot_url",
    "oauth_pkce_device.cloudflare_url",
    "oauth_pkce_device.radius_gateway",
    "oauth_pkce_device.copilot_auth",
    "cli_extensions_install.llama_url",
    "cli_extensions_install.hf_token",
    "cli_extensions_install.llama_catalog",
    "evals_harness.summarize",
    "evals_harness.group_key",
    "evals_harness.artifact_persist",
    "evals_harness.format",
    "ai_crypto_model_data.manifest",
    "ai_crypto.hmac",
    "cli_models_rest.pattern_match",
    "cli_models_rest.auth_command",
    "image_runtime.dimensions",
    "image_runtime.mime_type",
    "image_runtime.lookup",
    "image_runtime.dimension_note",
    "image_runtime.api_provider",
    "cli_print_rpc.jsonl_line",
    "cli_print_rpc.jsonl_read",
    "cli_print_rpc.clamp_thinking",
    "cli_print_rpc.session_stats",
    "tui_latex.render",
    "tui_mermaid.render",
    "tui_mermaid.source_box",
    "tui_mermaid.transform",
    "tui_editor_helpers.fuzzy_match",
    "tui_theme_overlay.osc11_bg",
    "ai_support.estimate_text",
    "ai_support.context_overflow",
    "ai_support.grammar_delta",
    "ai_support.uuid_v7",
    "ai_support.auth_guidance",
    "tui_select_settings_loaders.filter",
    "tui_word_navigation.step",
    "tui_overlay.composite_line",
    "tui_kill_ring.push_peek",
    "tui_undo_stack.push_pop",
    "tui_autocomplete.suggest_apply",
    "tui_keybindings.resolve_match",
    "tui_stdin_buffer.process",
    "tui_input_component.edit",
    "tui_native_modifiers.pressed",
    "tui_settings_list.apply_filter",
    "ai_capabilities.short_hash",
    "ai_capabilities.deferred_tools",
    "ai_capabilities.event_stream",
    "ai_capabilities.http_proxy",
    "ai_capabilities.session_resources",
    "cli_support.strip_ansi",
    "cli_support.normalize_path",
    "cli_support.timings",
    "cli_support.event_bus",
    "cli_support.attribution_headers",
    "cli_support.shell_config",
    "cli_support.sanitize_output",
    "cli_support.git_source",
    "cli_support.user_agent",
    "cli_support.parse_changelog",
    "cli_support.experimental",
    "cli_interactive_controller.decode_entity",
    "cli_interactive_controller.wayland",
    "cli_interactive_controller.cwd_footer",
    "cli_interactive_controller.auth_type",
    "cli_selectors.session_search",
    "cli_selectors.key_text",
    "cli_selectors.fuzzy_filter",
    "cli_selectors.delete_query",
    "cli_selectors.visible_slice",
    "cli_selectors.move_index",
    "cli_selectors.align_left_right",
    "cli_selectors.fit_line",
    "cli_selectors.border_line",
    "cli_selectors.selected_line",
    "cli_selectors.muted_line",
    "websocket_stream.stream_roundtrip",
    "cli_sdk.version_newer",
    "cli_sdk.cache_miss",
    "cli_sdk.cache_waste",
    "cli_sdk.thinking_level",
    "cli_sdk.session_list",
    "cli_sdk.agent_session",
    "cli_sdk.session_services",
    "cli_sdk.model_runtime",
    "provider_registry_defs.lookup",
    "skill_prompt_load.build_prompt",
    "cli_bootstrap_sessions.coding_tools",
    "ai_runtime_faux.blocks",
    "http_transport.parse_url",
    "session_pipeline.session_load",
    "session_pipeline.context_walk",
    "storage_journal.journal_read",
    "storage_journal.journal_append",
    "sqlite_session.open_walk",
    "tool_read.text_file",
    "tool_grep.context_file",
    "agent_tool_loop.roundtrip",
    "agent_tool_loop.tool_path",
    "agent_tool_loop.line_ending",
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
