#!/usr/bin/env python3
"""Goal 20 Part H: pair the cadr and pi non-TUI benchmark reports.

Goal 11 paired cadr against pi on three TUI-input ratios (mouse drag, wheel,
continuous alt input).  Nothing outside the renderer was paired, so "no worse
than pi" was unfalsifiable for the CLI, provider, agent-session, and storage
layers.  scripts/goal20-paired-paths.lisp and scripts/goal20-paired-paths.mjs
measure four such paths over byte-identical fixtures; this script proves the
two halves really did the same work and compares them.

Host match is not re-implemented here: same_machine is imported from
scripts/goal11-performance-gate.py, which is the only host-match rule in the
tree.

usage:
  python3 scripts/goal20-paired-paths.py \
      --cadr /tmp/goal20-cadr.json --pi /tmp/goal20-pi.json \
      [--cadr-journal /tmp/cadr.jsonl --pi-journal /tmp/pi.jsonl] \
      [--summary-json PATH]

Exit codes: 0 pass, 1 gate failure, 2 unusable report.
"""

import argparse
import hashlib
import importlib.util
import json
import re
import sys
from pathlib import Path

PROJECT_DIRECTORY = Path(__file__).resolve().parents[1]
FIXTURE_DIRECTORY = PROJECT_DIRECTORY / "test/fixtures/goal20-paired-paths"

# The pi revision is owned by the BASELINE anchor (goal 18 L2.1); deriving it
# here keeps scripts/baseline-anchor.py check green.
_baseline_spec = importlib.util.spec_from_file_location(
    "baseline_anchor", PROJECT_DIRECTORY / "scripts" / "baseline-anchor.py"
)
if _baseline_spec is None or _baseline_spec.loader is None:
    raise SystemExit("cannot import scripts/baseline-anchor.py")
_baseline_anchor = importlib.util.module_from_spec(_baseline_spec)
_baseline_spec.loader.exec_module(_baseline_anchor)
EXPECTED_PI_REVISION = _baseline_anchor.read_baseline(PROJECT_DIRECTORY)["commit"]

CADR_KIND = "cadr-goal20-part-h-paired-paths"
PI_KIND = "pi-goal20-part-h-paired-paths"

FIXTURE_NAMES = (
    "auth.json",
    "cli-argv.json",
    "manifest.json",
    "models.json",
    "anthropic-messages.sse",
    "google-generative-ai.sse",
    "bedrock-converse-stream.bin",
    "mistral-conversations.sse",
    "openai-responses.sse",
    "azure-openai-responses.sse",
    "google-vertex.sse",
    "vertex-adc.json",
    "openai-codex-responses.sse",
    "pi-messages.sse",
    "settings-global.json",
    "settings-project.json",
    "resource-skill-global.md",
    "resource-skill-project.md",
    "resource-prompt-global.md",
    "resource-prompt-project.md",
    "resource-agents.md",
    "package-manifest.json",
    "package-skill.md",
    "package-prompt.md",
    "package-theme.json",
    "package-extension.js",
    "package-settings-global.json",
    "package-settings-project.json",
    "resource-system.md",
    "openai-completions.sse",
    "provider-context.json",
    "session.jsonl",
)

METRICS = {
    "cli_dispatch": (
        "argv_parse",
        "help_render",
        "list_models_registry",
        "list_models_render",
    ),
    "provider_stream": ("stream_roundtrip",),
    "provider_anthropic": ("stream_roundtrip",),
    "provider_google": ("stream_roundtrip",),
    "provider_bedrock": ("stream_roundtrip",),
    "provider_mistral": ("stream_roundtrip",),
    "provider_openai_responses": ("stream_roundtrip",),
    "provider_azure_openai": ("stream_roundtrip",),
    "provider_vertex": ("stream_roundtrip",),
    "provider_codex": ("stream_roundtrip",),
    "provider_pi_messages": ("stream_roundtrip",),
    "cli_settings": ("create", "reload", "enabled_models", "block_images"),
    "agent_conditions": ("error_probe",),
    "execution_env": ("exists_remove_temps",),
    "file_mutation_queue": ("with_queue", "queue_key", "lock", "register", "wait_turn", "release_turn", "ensure_state", "call_with", "make_state", "state_key", "pending_count", "next_ticket", "serving_ticket"),
    "harness_events": ("emit", "on", "watch", "make_start", "make_end", "event_type", "make_bus"),
    "bash_tool": ("strip_exit_footer", "append_status", "truncation_notice", "live_output", "strip_status", "strip_truncation"),
    "output_accumulator": ("append", "snapshot", "finish"),
    "find_tool": ("pattern_match", "find_files", "make_tool"),
    "write_tool": ("ensure_parent", "write_utf8", "make_tool"),
    "ls_tool": ("directory_entry_name", "list_directory", "make_tool"),
    "tool_manager": ("get_tool_path", "ensure_tool", "cleanup_quarantine"),
    "powershell_tool": ("utf8_prefix", "prefix_command", "make_tool"),
    "settings_load": ("project_trust", "config_value", "http_idle", "stored_auth_secrets", "config_paths"),
    "resource_loader": ("reload", "dedupe_by_name"),
    "package_manager": ("resolve", "manifest_parse", "package_source"),
    "session_discovery": ("header_probe", "session_list_probe"),
    "session_export_html": ("to_html",),
    "protocol_cbor": ("roundtrip",),
    "agent_schema": ("validate_ok_fail",),
    "harness_storage": ("open_walk",),
    "protocol_codec": ("roundtrip",),
    "agent_proxy": ("stream_roundtrip",),
    "oauth_pkce": ("challenge_urls",),
    "oauth_pkce_device": (
        "poll",
        "auth_json",
        "copilot_url",
        "cloudflare_url",
        "radius_gateway",
        "copilot_auth",
        "percent_decode",
        "parse_query",
        "parse_authorization_input",
    ),
    "cli_extensions_install": ("llama_url", "hf_token", "llama_catalog", "extension_discovery"),
    "evals_harness": ("summarize", "group_key", "artifact_persist", "format", "normalize_steps", "resolve_selection", "transcript", "last_assistant", "step_value", "usage", "result_json", "eval_environment", "prompt_step", "reload_step"),
    "ai_crypto_model_data": ("manifest",),
    "ai_crypto": ("hmac",),
    "cli_models_rest": ("pattern_match", "auth_command", "login_selection"),
    "image_runtime": ("dimensions", "mime_type", "lookup", "dimension_note", "api_provider", "output_modalities", "openrouter_content", "parse_data_image"),
    "cli_print_rpc": ("jsonl_line", "jsonl_read", "clamp_thinking", "session_stats"),
    "tui_latex": ("render", "normalize_output"),
    "tui_mermaid": ("render", "source_box", "transform"),
    "tui_editor_helpers": ("fuzzy_match",),
    "tui_theme_overlay": ("osc11_bg",),
    "ai_support": ("estimate_text", "context_overflow", "grammar_delta", "uuid_v7", "auth_guidance"),
    "tui_select_settings_loaders": ("filter",),
    "tui_word_navigation": ("step",),
    "tui_overlay": ("composite_line",),
    "tui_kill_ring": ("push_peek",),
    "tui_undo_stack": ("push_pop",),
    "tui_autocomplete": ("suggest_apply",),
    "tui_keybindings": ("resolve_match",),
    "tui_stdin_buffer": ("process",),
    "tui_input_component": ("edit",),
    "tui_native_modifiers": ("pressed",),
    "tui_settings_list": ("apply_filter",),
    "ai_capabilities": ("short_hash", "deferred_tools", "event_stream", "http_proxy", "session_resources"),
    "cli_support": ("strip_ansi", "normalize_path", "timings", "event_bus", "attribution_headers", "shell_config", "sanitize_output", "git_source", "user_agent", "parse_changelog", "experimental"),
    "cli_interactive_controller": ("decode_entity", "wayland", "cwd_footer", "auth_type", "parse_auto_theme", "resolve_theme"),
    "cli_selectors": ("session_search", "session_format_age", "session_record_label", "session_shorten_path", "session_quoted_search", "session_thread_records", "session_binding_label", "session_same_path", "session_quoted_p", "session_named_p", "settings_thinking_description", "settings_display_value", "settings_automatic_theme_setting", "settings_active_automatic_theme", "settings_cycle", "settings_apply_filter", "tree_entry_filtered", "tree_query_matches", "tree_entry_search_text", "tree_settings_entry_p", "tree_normalize_display_text", "tree_status_labels", "tree_shorten_path", "tree_foldable_p", "tree_tool_argument", "tree_cycle_filter", "tree_format_label_timestamp", "tree_format_tool_call", "tree_entry_display_text", "tree_prefix", "tree_visual_nodes", "tree_horizontal_viewport", "tree_help_keys", "tree_help_key", "tree_app_key_p", "tree_help_lines", "tree_active_path", "tree_nearest_visible_id", "tree_prioritize_active", "tree_entry_map", "tree_order_entries", "tree_iso_timestamp", "tree_rebuild_visible_maps", "tree_apply_filter", "tree_render_lines", "tree_move", "tree_fold_or_up", "tree_unfold_or_down", "tree_branch_segment_id", "tree_set_query", "tree_set_filter", "tree_copy_selected", "tree_toggle_label_timestamps", "tree_start_label_edit", "tree_confirm_label", "tree_cancel_label", "tree_handle_raw_input", "tree_handle_event", "tree_handle_label_event", "tree_selected_entry", "tree_selected_id", "tree_select_id", "tree_visible_ids", "project_trust_options", "trust_selector_selection", "trust_decision_description", "trust_selector_move", "trust_selector_handle_event", "trust_selector_handle_raw_input", "trust_selector_ui_state", "oauth_option_status_label", "oauth_option_status_rendered", "credential_entry_auth_type", "oauth_environment_source_p", "oauth_selector_selection", "oauth_selector_apply_filter", "oauth_selector_handle_event", "oauth_selector_handle_raw_input", "oauth_selector_search_text", "login_auth_type_route", "login_provider_options", "logout_provider_options", "login_method_selector_handle_event", "oauth_selector_move", "api_key_input_state_handle_event", "login_method_selector_ui_state", "api_key_input_ui_state", "oauth_selector_ui_state", "model_selector_search_text", "qualified_model_id", "model_selector_apply_filter", "model_selector_move", "model_selector_handle_event", "model_selector_handle_raw_input", "model_selector_set_query", "model_selector_selected_model", "model_selector_toggle_scope", "model_selector_ui_state", "scoped_models_selector_set_query", "scoped_models_selector_move", "scoped_models_selector_handle_event", "scoped_models_selector_handle_raw_input", "scoped_models_selector_ui_state", "scoped_models_selector_sorted_ids", "scoped_models_selector_counts", "scoped_models_selector_toggle_selected", "scoped_models_selector_target_ids", "scoped_models_selector_enable_all", "scoped_models_selector_toggle_provider", "scoped_models_selector_clear_all", "scoped_models_selector_reorder", "scoped_models_selector_persist", "scoped_models_selector_provider_count", "key_text", "fuzzy_filter", "delete_query", "visible_slice", "move_index", "align_left_right", "fit_line", "border_line", "selected_line", "muted_line", "dim_line", "modified_cursor_key", "title_line", "overlay_title_line", "input_line", "keybinding_text", "keybinding_hint"),
    "websocket_stream": ("stream_roundtrip",),
    "cli_sdk": ("version_newer", "cache_miss", "cache_waste", "thinking_level", "session_list", "agent_session", "session_services", "model_runtime"),
    "provider_registry_defs": (
        "lookup",
        "definition_ids",
        "merge_environment",
        "runtime_models",
        "structured_api_key_login",
    ),
    "skill_prompt_load": ("build_prompt",),
    "cli_bootstrap_sessions": ("coding_tools", "bootstrap_auth"),
    "ai_runtime_faux": ("blocks",),
    "http_transport": ("parse_url",),
    "core_rest": ("cancellation_abort", "redacted_secrets", "threads_cleanup"),
    "session_pipeline": ("session_load", "context_walk", "session_leaf_id"),
    "storage_journal": ("journal_read", "journal_append", "journal_entry_count"),
    "sqlite_session": ("open_walk",),
    "tool_read": ("text_file",),
    "tool_grep": ("context_file",),
    "agent_tool_loop": ("roundtrip", "tool_path", "line_ending", "tool_result_digest", "runtime"),
    "session_compact": ("compact", "branch_summarize", "prepare_branch_entries"),
    "text_truncation": ("truncate_head", "truncate_tail", "truncate_middle"),
    "render_slicing": ("slice_ansi_clip", "slice_plain_clip"),
}

# Recorded cadr/pi median ratios plus headroom.  Observed spread over repeated
# --samples 5 --warmups 1 runs on Friend-MachineD (SBCL 2.6.7, node v22.22.0):
#
#   argv_parse           1.68-2.06    help_render          3.94-8.51
#   list_models_registry 0.53-0.70    list_models_render   2.67-2.94
#   stream_roundtrip     1.30-1.68    session_load         5.46-7.16
#   context_walk         0.88-1.13    journal_read         4.75-6.07
#   journal_append       7.36-8.52
#
# argv_parse, help_render, and context_walk are sub-10us operations whose ratio
# swings on pi's own jitter; the MICROSECOND_FLOOR_US term below, not the ratio,
# is what actually bounds them.
#
# Seven of the nine start above parity.  These ceilings freeze that measured
# state so further drift fails; they are NOT a claim that cadr matches pi on
# those paths.  docs/acceptance/goal-v20-part-h.md records the gaps.  Ratchet
# them down as cadr improves; never up without adjudication.
RATIO_CEILINGS = {
    "cli_dispatch.argv_parse": 3.0,
    "cli_dispatch.help_render": 6.0,
    "cli_dispatch.list_models_registry": 1.5,
    "cli_dispatch.list_models_render": 4.0,
    "provider_stream.stream_roundtrip": 2.5,
    # Frozen from the first Friend-MachineD non-quick provider_anthropic
    # pair (samples=5): observed 0.97x (2508 / 2585 µs). cadr ties/leads.
    # 1.5 follows the list_models_registry / render_slicing precedent
    # (headroom above 1.0). Ratchet down only.
    "provider_anthropic.stream_roundtrip": 1.5,
    # Frozen from the first Friend-MachineD non-quick provider_google
    # pair (samples=5): observed 0.58x (4378 / 7498 µs). cadr leads.
    # 1.5 follows the list_models_registry / render_slicing precedent
    # (headroom above 1.0). Ratchet down only.
    "provider_google.stream_roundtrip": 1.5,
    # Frozen from the first Friend-MachineD non-quick provider_bedrock
    # pair (samples=5): observed 0.67x (4316 / 6406 µs). cadr leads.
    # 1.5 follows the list_models_registry / render_slicing precedent
    # (headroom above 1.0). Ratchet down only.
    "provider_bedrock.stream_roundtrip": 1.5,
    # Frozen from the first Friend-MachineD non-quick provider_mistral
    # pair (samples=5): observed 1.89x (3401 / 1801 µs). 3.0 follows
    # the argv_parse / tool_grep headroom precedent. Ratchet down only.
    "provider_mistral.stream_roundtrip": 3.0,
    # Frozen from the first Friend-MachineD non-quick
    # provider_openai_responses pair (samples=5): observed 0.37x
    # (1460 / 3901 µs). cadr leads. 1.5 follows the
    # list_models_registry / render_slicing precedent (headroom
    # above 1.0). Ratchet down only.
    "provider_openai_responses.stream_roundtrip": 1.5,
    # Frozen from the first Friend-MachineD non-quick
    # provider_azure_openai pair (samples=5): observed 0.33x
    # (1369 / 4152 µs). cadr leads. 1.5 follows the
    # list_models_registry / render_slicing precedent. Ratchet
    # down only.
    "provider_azure_openai.stream_roundtrip": 1.5,
    # Frozen from the first Friend-MachineD non-quick provider_vertex
    # pair (samples=5): observed 0.49x (2641 / 5443 us). cadr leads.
    # 1.5 follows the list_models_registry / render_slicing precedent.
    # Ratchet down only.
    "provider_vertex.stream_roundtrip": 1.5,
    # Frozen from the first Friend-MachineD non-quick provider_codex
    # pair (samples=5): observed 1.26x (1582 / 1258 us). 1.5 follows
    # the list_models_registry / render_slicing precedent. Ratchet
    # down only.
    "provider_codex.stream_roundtrip": 1.5,
    # Frozen from the first Friend-MachineD non-quick provider_pi_messages
    # pair (samples=5): observed 1.25x (1103 / 885 us). 1.5 follows
    # the list_models_registry / render_slicing precedent. Ratchet
    # down only.
    "provider_pi_messages.stream_roundtrip": 1.5,
    # Frozen from the first Friend-MachineD non-quick cli_settings
    # pair (samples=5): observed 0.13x (105 / 813 µs). cadr leads.
    # 1.5 follows the list_models_registry / render_slicing precedent
    # (headroom above 1.0). Ratchet down only.
    "cli_settings.create": 1.5,
    # cli_settings leftover trio (samples=5): first-freeze headroom.
    # Ratchet down only.
    "cli_settings.reload": 8.0,
    "cli_settings.enabled_models": 8.0,
    "cli_settings.block_images": 8.0,
    # agent_conditions.error_probe pair (samples=5): first-freeze headroom.
    # Ratchet down only.
    "agent_conditions.error_probe": 8.0,
    # execution_env.exists_remove_temps pair (samples=5): first-freeze headroom.
    # Ratchet down only.
    "execution_env.exists_remove_temps": 8.0,
    "file_mutation_queue.with_queue": 8.0,
    # file_mutation_queue.queue_key pair (samples=5): first-freeze headroom.
    # Ratchet down only.
    "file_mutation_queue.queue_key": 8.0,
    # file_mutation_queue.lock pair (samples=5): first-freeze headroom.
    # Ratchet down only.
    "file_mutation_queue.lock": 8.0,
    # file_mutation_queue.register pair (samples=5): first-freeze headroom.
    # Ratchet down only.
    "file_mutation_queue.register": 8.0,
    # file_mutation_queue.wait_turn pair (samples=5): first-freeze headroom.
    # Ratchet down only.
    "file_mutation_queue.wait_turn": 8.0,
    # file_mutation_queue.release_turn pair (samples=5): first-freeze headroom.
    # Ratchet down only.
    "file_mutation_queue.release_turn": 8.0,
    # file_mutation_queue.ensure_state pair (samples=5): first-freeze headroom.
    # Ratchet down only.
    "file_mutation_queue.ensure_state": 8.0,
    # file_mutation_queue.call_with pair (samples=5): first-freeze headroom.
    # Ratchet down only.
    "file_mutation_queue.call_with": 8.0,
    # file_mutation_queue.make_state pair (samples=5): first-freeze headroom.
    # Ratchet down only.
    "file_mutation_queue.make_state": 8.0,
    # file_mutation_queue.state_key pair (samples=5): first-freeze headroom.
    # Ratchet down only.
    "file_mutation_queue.state_key": 8.0,
    # file_mutation_queue.pending_count pair (samples=5): first-freeze headroom.
    # Ratchet down only.
    "file_mutation_queue.pending_count": 8.0,
    # file_mutation_queue.next_ticket pair (samples=5): first-freeze headroom.
    # Ratchet down only.
    "file_mutation_queue.next_ticket": 8.0,
    # file_mutation_queue.serving_ticket pair (samples=5): first-freeze headroom.
    # Ratchet down only.
    "file_mutation_queue.serving_ticket": 8.0,
    # harness_events.emit pair (samples=5): first-freeze headroom.
    # Ratchet down only.
    "harness_events.emit": 8.0,
    # bash_tool leftover trio (samples=5): first-freeze headroom.
    # Ratchet down only.
    "bash_tool.strip_exit_footer": 8.0,
    "bash_tool.append_status": 8.0,
    "bash_tool.truncation_notice": 8.0,
    # bash_tool leftover trio on tools/bash.lisp (508-510).
    # First leftover freeze pending; 8.0 is first-freeze headroom.
    "bash_tool.live_output": 8.0,
    "bash_tool.strip_status": 8.0,
    "bash_tool.strip_truncation": 8.0,
    "output_accumulator.append": 8.0,
    "output_accumulator.snapshot": 8.0,
    "output_accumulator.finish": 8.0,
    # harness_events.on pair (samples=5): first-freeze headroom.
    # Ratchet down only.
    "harness_events.on": 8.0,
    # harness_events.watch pair (samples=5): first-freeze headroom.
    # Ratchet down only.
    "harness_events.watch": 8.0,
    # harness_events.make_start pair (samples=5): first-freeze headroom.
    # Ratchet down only.
    "harness_events.make_start": 8.0,
    # harness_events leftover trio (samples=5): first-freeze headroom.
    # Ratchet down only.
    "harness_events.make_end": 8.0,
    "harness_events.event_type": 8.0,
    "harness_events.make_bus": 8.0,
    # find_tool leftover trio (samples=5): first-freeze headroom.
    # Ratchet down only.
    "find_tool.pattern_match": 8.0,
    "find_tool.find_files": 8.0,
    "find_tool.make_tool": 8.0,
    # write_tool leftover trio (samples=5): first-freeze headroom.
    # Ratchet down only.
    "write_tool.ensure_parent": 8.0,
    "write_tool.write_utf8": 8.0,
    "write_tool.make_tool": 8.0,
    # ls_tool leftover trio (samples=5): first-freeze headroom.
    # Ratchet down only.
    "ls_tool.directory_entry_name": 8.0,
    "ls_tool.list_directory": 8.0,
    "ls_tool.make_tool": 8.0,
    # tool_manager.get_tool_path/ensure_tool/cleanup_quarantine pair
    # (samples=5): first-freeze headroom. Ratchet down only.
    "tool_manager.get_tool_path": 8.0,
    "tool_manager.ensure_tool": 8.0,
    "tool_manager.cleanup_quarantine": 8.0,
    # powershell_tool leftover trio (samples=5): first-freeze headroom.
    # Ratchet down only.
    "powershell_tool.utf8_prefix": 8.0,
    "powershell_tool.prefix_command": 8.0,
    "powershell_tool.make_tool": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # settings_load.project_trust pair (samples=5): observed
    # 0.24x (330.6 / 1402.9 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "settings_load.project_trust": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # settings_load.config_value pair (samples=5): observed
    # 0.43x (2.70 / 6.21 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "settings_load.config_value": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # settings_load.http_idle pair (samples=5): observed
    # 0.47x (0.25 / 0.53 us). cadr leads. 8.0 is
    # first-freeze headroom (microsecond-floor). Ratchet down only.
    "settings_load.http_idle": 8.0,
    # settings_load.stored_auth_secrets pair (samples=5): observed 4.19x
    # (426.6 / 101.8 us). 8.0 is first-freeze headroom. Ratchet down only.
    "settings_load.stored_auth_secrets": 8.0,
    # settings_load.config_paths pair (samples=5): first-freeze headroom.
    # Ratchet down only.
    "settings_load.config_paths": 8.0,
    # Frozen from the first Friend-MachineD non-quick resource_loader
    # pair (samples=5): observed 0.29x (568 / 1978 µs). cadr leads.
    # 1.5 follows the list_models_registry / render_slicing precedent
    # (headroom above 1.0). Ratchet down only.
    "resource_loader.reload": 1.5,
    # resource_loader.dedupe_by_name pair (samples=5): first-freeze headroom.
    # Ratchet down only.
    "resource_loader.dedupe_by_name": 8.0,
    # Frozen from the first Friend-MachineD non-quick package_manager
    # pair (samples=5): observed 0.36x (200 / 551 us). cadr leads.
    # 1.5 follows the list_models_registry / render_slicing precedent.
    # Ratchet down only.
    "package_manager.resolve": 1.5,
    # package_manager.manifest_parse pair (samples=5): first-freeze headroom.
    # Ratchet down only.
    "package_manager.manifest_parse": 8.0,
    # package_manager.package_source pair (samples=5): first-freeze headroom.
    # Ratchet down only.
    "package_manager.package_source": 8.0,
    # Frozen from the first Friend-MachineD non-quick session_discovery
    # pair (samples=5): observed 2.05x (1450 / 709 us). 8.0 follows
    # the journal_read / tool_read headroom precedent. Ratchet down only.
    "session_discovery.header_probe": 8.0,
    "session_discovery.session_list_probe": 8.0,
    # Frozen from the first Friend-MachineD non-quick session_export_html
    # pair (samples=5): observed 3.55x (29218 / 8240 us). 20.0 follows
    # the session_compact headroom precedent. Ratchet down only.
    "session_export_html.to_html": 20.0,
    # Frozen from the first Friend-MachineD non-quick protocol_cbor
    # pair (samples=5): observed 0.25x (17.7 / 70.1 us). cadr leads.
    # 1.5 follows the list_models_registry / render_slicing precedent.
    # Ratchet down only.
    "protocol_cbor.roundtrip": 1.5,
    # Frozen from the first Friend-MachineD non-quick agent_schema
    # pair (samples=5): observed 0.38x (34.2 / 89.4 us). cadr leads.
    # 1.5 follows the list_models_registry / render_slicing precedent.
    # Ratchet down only.
    "agent_schema.validate_ok_fail": 1.5,
    # Frozen from the first Friend-MachineD non-quick harness_storage
    # pair (samples=5): observed 1.80x (11644 / 6485 us). 8.0 follows
    # the journal_read / tool_read headroom precedent. Ratchet down only.
    "harness_storage.open_walk": 8.0,
    # Frozen from the first Friend-MachineD non-quick protocol_codec
    # pair (samples=5): observed 0.10x (9.6 / 94.2 us). cadr leads.
    # 1.5 follows the list_models_registry / render_slicing precedent.
    # Ratchet down only.
    "protocol_codec.roundtrip": 1.5,
    # Frozen from the first Friend-MachineD non-quick agent_proxy
    # pair (samples=5): observed 1.59x (25.4 / 16.0 us). 1.5 follows
    # the list_models_registry / microsecond-floor precedent (variance
    # bound, not ratio). Ratchet down only.
    "agent_proxy.stream_roundtrip": 1.5,
    # Frozen from the first Friend-MachineD non-quick oauth_pkce
    # pair (samples=5): observed 0.37x (50.6 / 135.3 us). cadr leads.
    # 1.5 follows the list_models_registry / render_slicing precedent.
    # Ratchet down only.
    "oauth_pkce.challenge_urls": 1.5,
    # Frozen from the first Friend-MachineD non-quick
    # oauth_pkce_device.poll pair (samples=5): observed
    # 0.09x (1.01 / 11.51 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "oauth_pkce_device.poll": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # oauth_pkce_device.auth_json pair (samples=5): observed
    # 1.21x (257.5 / 212.9 us). 8.0 is first-freeze
    # headroom. Ratchet down only.
    "oauth_pkce_device.auth_json": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # oauth_pkce_device.copilot_url pair (samples=5): observed
    # 1.15x (2.12 / 1.85 us). 8.0 is first-freeze
    # headroom. Ratchet down only.
    "oauth_pkce_device.copilot_url": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # oauth_pkce_device.cloudflare_url pair (samples=5): observed
    # 6.66x (9.27 / 1.39 us). 8.0 is first-freeze
    # headroom (microsecond-floor / variance). Ratchet down only.
    "oauth_pkce_device.cloudflare_url": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # oauth_pkce_device.radius_gateway pair (samples=5): observed
    # 1.05x (0.57 / 0.54 us). 8.0 is first-freeze
    # headroom (microsecond-floor / variance). Ratchet down only.
    "oauth_pkce_device.radius_gateway": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # oauth_pkce_device.copilot_auth pair (samples=5): observed
    # 1.35x (3.21 / 2.38 us). 8.0 is first-freeze
    # headroom. Ratchet down only.
    "oauth_pkce_device.copilot_auth": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # oauth_pkce_device leftover trio (samples=5): first-freeze
    # headroom. Ratchet down only.
    "oauth_pkce_device.percent_decode": 8.0,
    "oauth_pkce_device.parse_query": 8.0,
    "oauth_pkce_device.parse_authorization_input": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_extensions_install.llama_url pair (samples=5): observed
    # 0.45x (4.79 / 10.52 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "cli_extensions_install.llama_url": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_extensions_install.hf_token pair (samples=5): observed
    # 0.28x (277.4 / 1002.4 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "cli_extensions_install.hf_token": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_extensions_install.llama_catalog pair (samples=5): observed
    # 0.36x (4.78 / 13.41 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "cli_extensions_install.llama_catalog": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_extensions_install.extension_discovery pair (samples=5): observed
    # 1.98x (1954.5 / 987.2 us). pi leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "cli_extensions_install.extension_discovery": 8.0,
    # Frozen from the first Friend-MachineD non-quick evals_harness
    # pair (samples=5): observed 0.88x (8.0 / 9.0 us). cadr leads.
    # 1.5 follows the list_models_registry / render_slicing precedent.
    # Ratchet down only.
    "evals_harness.summarize": 1.5,
    # Frozen from the first Friend-MachineD non-quick
    # evals_harness.group_key pair (samples=5): observed
    # 4.06x (5.01 / 1.23 us). 8.0 is first-freeze
    # headroom (microsecond-floor / variance). Ratchet down only.
    "evals_harness.group_key": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # evals_harness.artifact_persist pair (samples=5):
    # observed 0.53x (595 / 1130 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "evals_harness.artifact_persist": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # evals_harness.format pair (samples=5): observed
    # 1.14x (20.62 / 18.10 us). 8.0 is first-freeze
    # headroom. Ratchet down only.
    "evals_harness.format": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # evals_harness.normalize_steps pair (samples=5): observed
    # 0.11x (1.30 / 12.15 us). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "evals_harness.normalize_steps": 8.0,
    # evals_harness leftover trio on harness.lisp (samples=5): first-freeze
    # headroom. Ratchet down only.
    "evals_harness.resolve_selection": 8.0,
    "evals_harness.transcript": 8.0,
    "evals_harness.last_assistant": 8.0,
    "evals_harness.step_value": 8.0,
    "evals_harness.usage": 8.0,
    "evals_harness.result_json": 8.0,
    # evals_harness leftover trio on harness.lisp (samples=5): first-freeze
    # headroom. Ratchet down only.
    "evals_harness.eval_environment": 8.0,
    "evals_harness.prompt_step": 8.0,
    "evals_harness.reload_step": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # ai_crypto_model_data pair (samples=5): observed 8.97x
    # (77.3 / 8.6 us). 20.0 follows the session_compact /
    # truncate_head headroom precedent. Ratchet down only.
    "ai_crypto_model_data.manifest": 20.0,
    # Frozen from the first Friend-MachineD non-quick
    # ai_crypto.hmac pair (samples=5): observed 18.81x
    # (133.9 / 7.1 us). A first attempt at 8.0 failed.
    # 30.0 is first-freeze headroom. Ratchet down only.
    "ai_crypto.hmac": 30.0,
    # Frozen from the first Friend-MachineD non-quick cli_models_rest
    # pair (samples=5): observed 1.65x (31.9 / 19.4 us). 3.0 follows
    # the argv_parse / tool_grep headroom precedent. Ratchet down only.
    "cli_models_rest.pattern_match": 3.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_models_rest.auth_command pair (samples=5): observed
    # 0.47x (3.56 / 7.54 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "cli_models_rest.auth_command": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_models_rest.login_selection pair (samples=5): observed
    # 1.78x (7.53 / 4.22 us). 8.0 is first-freeze headroom.
    # Ratchet down only.
    "cli_models_rest.login_selection": 8.0,
    # Frozen from the first Friend-MachineD non-quick image_runtime
    # pair (samples=5): observed 5.44x (7.8 / 1.4 us). 8.0 follows
    # the tool_read / journal_read headroom precedent. Ratchet down only.
    "image_runtime.dimensions": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # image_runtime.mime_type pair (samples=5): observed
    # 1.62x (6.63 / 4.09 us). 8.0 is first-freeze
    # headroom. Ratchet down only.
    "image_runtime.mime_type": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # image_runtime.lookup pair (samples=5): observed
    # 7.38x (1.51 / 0.20 us). 8.0 is first-freeze
    # headroom (variance). Ratchet down only.
    "image_runtime.lookup": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # image_runtime.dimension_note pair (samples=5): observed
    # 1.73x (3.67 / 2.12 us). 8.0 is first-freeze
    # headroom. Ratchet down only.
    "image_runtime.dimension_note": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # image_runtime.api_provider pair (samples=5): observed
    # 1.09x (0.23 / 0.21 us). 8.0 is first-freeze
    # headroom (variance). Ratchet down only.
    "image_runtime.api_provider": 8.0,
    # Frozen from the first n=5 image_runtime.output_modalities
    # leftover pair: observed 0.657x (0.196 / 0.299 us). cadr leads.
    # 8.0 is first-freeze headroom. Ratchet down only.
    "image_runtime.output_modalities": 8.0,
    # Frozen from the first n=5 image_runtime.openrouter_content
    # leftover pair: observed 3.34x (1.367 / 0.409 us). 8.0 is
    # first-freeze headroom. Ratchet down only.
    "image_runtime.openrouter_content": 8.0,
    # Frozen from the first n=5 image_runtime.parse_data_image
    # leftover pair: observed 1.43x (0.555 / 0.387 us). 8.0 is
    # first-freeze headroom. Ratchet down only.
    "image_runtime.parse_data_image": 8.0,
    # Frozen from the first Friend-MachineD non-quick cli_print_rpc
    # pair (samples=5): observed 13.21x (3.3 / 0.25 us). 8.0 follows
    # the microsecond-floor / agent_proxy variance precedent (not
    # the ratio). Ratchet down only.
    "cli_print_rpc.jsonl_line": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_print_rpc.jsonl_read pair (samples=5): observed
    # 0.03x (0.63 / 23.84 us). cadr leads (sync read-line vs
    # async Readable). 8.0 is first-freeze headroom.
    # Ratchet down only.
    "cli_print_rpc.jsonl_read": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_print_rpc.clamp_thinking pair (samples=5): observed
    # 0.59x (1.37 / 2.33 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "cli_print_rpc.clamp_thinking": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_print_rpc.session_stats pair (samples=5): observed
    # 0.19x (13.16 / 70.76 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "cli_print_rpc.session_stats": 8.0,
    # Frozen from the first Friend-MachineD non-quick tui_latex pair
    # (samples=5): observed 2.49x (64.4 / 25.8 us). 3.0 follows the
    # argv_parse / tool_grep headroom precedent. Ratchet down only.
    "tui_latex.render": 3.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_latex.normalize_output pair (samples=5): observed
    # 1.46x (12.66 / 8.68 us). 20.0 is first-freeze headroom.
    # Ratchet down only.
    "tui_latex.normalize_output": 20.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_mermaid.render pair (samples=5): observed
    # 0.30x (75.31 / 255.24 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "tui_mermaid.render": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_mermaid.source_box pair (samples=5): observed
    # 0.38x (58.73 / 155.58 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "tui_mermaid.source_box": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_mermaid.transform pair (samples=5): observed
    # 0.65x (69.67 / 107.87 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "tui_mermaid.transform": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_editor_helpers pair (samples=5): observed 0.45x
    # (1.8 / 4.0 us). cadr leads. 8.0 is the first-freeze
    # headroom (microsecond path). Ratchet down only.
    "tui_editor_helpers.fuzzy_match": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_theme_overlay pair (samples=5): observed 1.16x
    # (3.8 / 3.3 us). 8.0 follows the microsecond-floor
    # first-freeze headroom. Ratchet down only.
    "tui_theme_overlay.osc11_bg": 8.0,
    # Frozen from the first Friend-MachineD non-quick ai_support
    # pair (samples=5): observed 3.10x (0.54 / 0.17 us). 8.0 follows
    # the microsecond-floor / agent_proxy variance precedent.
    # Ratchet down only.
    "ai_support.estimate_text": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # ai_support.context_overflow pair (samples=5): observed
    # 1.67x (1.85 / 1.11 us). 8.0 is first-freeze
    # headroom (variance). Ratchet down only.
    "ai_support.context_overflow": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # ai_support.grammar_delta pair (samples=5): observed
    # 2.87x (1.52 / 0.53 us). 8.0 is first-freeze
    # headroom (variance). Ratchet down only.
    "ai_support.grammar_delta": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # ai_support.uuid_v7 pair (samples=5): observed
    # 0.32x (3.08 / 9.49 us). cadr leads (entropy pool).
    # 8.0 is first-freeze headroom. Ratchet down only.
    "ai_support.uuid_v7": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # ai_support.auth_guidance pair (samples=5): observed
    # 27.66x (1922 / 69.5 us). cadr-docs-directory hits
    # ASDF. 50.0 is first-freeze headroom. Ratchet down only.
    "ai_support.auth_guidance": 50.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_select_settings_loaders pair (samples=5): observed
    # 1.27x (1.2 / 1.0 us). 8.0 follows the microsecond-floor
    # first-freeze headroom. Ratchet down only.
    "tui_select_settings_loaders.filter": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_word_navigation pair (samples=5): observed 0.17x
    # (0.94 / 5.4 us). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "tui_word_navigation.step": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_overlay pair (samples=5): observed 0.87x
    # (19.1 / 22.0 us). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "tui_overlay.composite_line": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_kill_ring pair (samples=5): observed 0.85x
    # (0.58 / 0.68 us). cadr leads. 8.0 follows the
    # microsecond-floor first-freeze headroom.
    # Ratchet down only.
    "tui_kill_ring.push_peek": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_undo_stack pair (samples=5): observed 0.21x
    # (0.51 / 2.42 us). cadr leads. 8.0 follows the
    # microsecond-floor first-freeze headroom.
    # Ratchet down only.
    "tui_undo_stack.push_pop": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_autocomplete pair (samples=5): observed 5.17x
    # (136.4 / 26.4 us). 8.0 follows the tool_read /
    # journal_read first-freeze headroom. Ratchet down only.
    "tui_autocomplete.suggest_apply": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_keybindings pair (samples=5): observed 1.88x
    # (27.7 / 14.8 us). 8.0 is first-freeze headroom.
    # Ratchet down only.
    "tui_keybindings.resolve_match": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_stdin_buffer pair (samples=5): observed 0.33x
    # (2.3 / 6.9 us). cadr leads. 8.0 follows the
    # microsecond-floor first-freeze headroom.
    # Ratchet down only.
    "tui_stdin_buffer.process": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_input_component pair (samples=5): observed 0.06x
    # (5.5 / 97.8 us). cadr leads. 8.0 follows the
    # microsecond-floor first-freeze headroom.
    # Ratchet down only.
    "tui_input_component.edit": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_native_modifiers pair (samples=5): observed 7.50x
    # (1.22 / 0.16 us). 8.0 follows the microsecond-floor
    # first-freeze headroom. Ratchet down only.
    "tui_native_modifiers.pressed": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_settings_list pair (samples=5): observed 0.47x
    # (5.3 / 11.4 us). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "tui_settings_list.apply_filter": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # ai_capabilities pair (samples=5): observed 1.70x
    # (1.5 / 0.9 us). 8.0 follows the microsecond-floor
    # first-freeze headroom. Ratchet down only.
    "ai_capabilities.short_hash": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # ai_capabilities.deferred_tools pair (samples=5): observed
    # 2.04x (5.51 / 2.70 us). 8.0 is first-freeze
    # headroom. Ratchet down only.
    "ai_capabilities.deferred_tools": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # ai_capabilities.event_stream pair (samples=5): observed
    # 1.44x (1.73 / 1.20 us). 8.0 is first-freeze
    # headroom (variance). Ratchet down only.
    "ai_capabilities.event_stream": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # ai_capabilities.http_proxy pair (samples=5): observed
    # 0.45x (5.71 / 12.59 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "ai_capabilities.http_proxy": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # ai_capabilities.session_resources pair (samples=5):
    # observed 0.16x (1.41 / 9.04 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "ai_capabilities.session_resources": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_support pair (samples=5): observed 2.73x
    # (1.3 / 0.5 us). 8.0 follows the microsecond-floor
    # first-freeze headroom. Ratchet down only.
    "cli_support.strip_ansi": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_support.normalize_path pair (samples=5): observed
    # 2.82x (4.58 / 1.63 us). 8.0 is first-freeze
    # headroom. Ratchet down only.
    "cli_support.normalize_path": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_support.timings pair (samples=5): observed 1.71x
    # (4.55 / 2.66 us). 8.0 is first-freeze headroom.
    # Ratchet down only.
    "cli_support.timings": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_support.event_bus pair (samples=5): observed
    # 0.33x (2.68 / 8.21 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "cli_support.event_bus": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_support.attribution_headers pair (samples=5):
    # observed 0.29x (2.70 / 9.31 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "cli_support.attribution_headers": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_support.shell_config pair (samples=5): observed
    # 2.47x (21.07 / 8.54 us). 8.0 is first-freeze
    # headroom. Ratchet down only.
    "cli_support.shell_config": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_support.sanitize_output pair (samples=5): observed
    # 0.91x (1.26 / 1.39 us). cadr leads. 8.0 follows the
    # microsecond-floor first-freeze headroom. Ratchet down
    # only.
    "cli_support.sanitize_output": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_support.git_source pair (samples=5): observed
    # 0.48x (26.85 / 55.99 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "cli_support.git_source": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_support.user_agent pair (samples=5): observed
    # 3.14x (1.41 / 0.45 us). 8.0 follows the
    # microsecond-floor first-freeze headroom. Ratchet down
    # only.
    "cli_support.user_agent": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_support.parse_changelog pair (samples=5): observed
    # 2.96x (36.04 / 12.20 us). 8.0 is first-freeze
    # headroom. Ratchet down only.
    "cli_support.parse_changelog": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_support.experimental pair (samples=5): observed
    # 0.05x (0.23 / 4.77 us). cadr leads. 8.0 is
    # first-freeze headroom (microsecond-floor). Ratchet down only.
    "cli_support.experimental": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_interactive_controller pair (samples=5): observed
    # 1.49x (0.63 / 0.42 us). 8.0 follows the
    # microsecond-floor first-freeze headroom.
    # Ratchet down only.
    "cli_interactive_controller.decode_entity": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_interactive_controller.wayland pair (samples=5): observed
    # 1.17x (0.36 / 0.30 us). 8.0 is first-freeze
    # headroom (microsecond-floor / variance). Ratchet down only.
    "cli_interactive_controller.wayland": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_interactive_controller.cwd_footer pair (samples=5): observed
    # 0.34x (0.78 / 2.31 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "cli_interactive_controller.cwd_footer": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_interactive_controller.auth_type pair (samples=5):
    # observed 1.44x (0.21 / 0.15 us). 8.0 is first-freeze
    # headroom (microsecond-floor / variance). Ratchet down only.
    "cli_interactive_controller.auth_type": 8.0,
    # First-freeze headroom for cli_interactive_controller.parse_auto_theme.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.parse_auto_theme": 8.0,
    # First-freeze headroom for cli_interactive_controller.resolve_theme.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.resolve_theme": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_selectors.session_search pair (samples=5): observed
    # 2.48x (42.40 / 17.10 us). 8.0 is first-freeze
    # headroom. Ratchet down only.
    "cli_selectors.session_search": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_selectors.key_text pair (samples=5): observed
    # 2.86x (5.76 / 2.01 us). 8.0 is first-freeze
    # headroom. Ratchet down only.
    "cli_selectors.key_text": 8.0,
    # First-freeze headroom for cli_selectors.fuzzy_filter.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.fuzzy_filter": 8.0,
    # First-freeze headroom for cli_selectors.delete_query.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.delete_query": 8.0,
    # First-freeze headroom for cli_selectors.visible_slice.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.visible_slice": 8.0,
    # First-freeze headroom for cli_selectors.move_index.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.move_index": 8.0,
    # First-freeze headroom for cli_selectors.align_left_right.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.align_left_right": 8.0,
    # First-freeze headroom for cli_selectors.fit_line.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.fit_line": 8.0,
    # First-freeze headroom for cli_selectors.border_line.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.border_line": 8.0,
    # First-freeze headroom for cli_selectors.selected_line.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.selected_line": 8.0,
    # First-freeze headroom for cli_selectors.muted_line.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.muted_line": 8.0,
    # First-freeze headroom for cli_selectors.dim_line.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.dim_line": 8.0,
    # First-freeze headroom for cli_selectors.modified_cursor_key.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.modified_cursor_key": 20.0,
    # First-freeze headroom for cli_selectors.title_line.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.title_line": 8.0,
    # First-freeze headroom for cli_selectors.overlay_title_line.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.overlay_title_line": 8.0,
    # First-freeze headroom for cli_selectors.input_line.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.input_line": 8.0,
    # First-freeze headroom for cli_selectors.keybinding_text.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.keybinding_text": 8.0,
    # First-freeze headroom for cli_selectors.keybinding_hint.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.keybinding_hint": 8.0,
    # First-freeze headroom for cli_selectors.session_format_age.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.session_format_age": 8.0,
    # First-freeze headroom for cli_selectors.session_record_label.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.session_record_label": 8.0,
    # First-freeze headroom for cli_selectors.session_shorten_path.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.session_shorten_path": 8.0,
    # First-freeze headroom for cli_selectors.session_quoted_search.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.session_quoted_search": 8.0,
    # First-freeze headroom for cli_selectors.session_thread_records.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.session_thread_records": 30.0,
    # First-freeze headroom for cli_selectors.session_binding_label.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.session_binding_label": 8.0,
    # First-freeze headroom for cli_selectors.session_same_path.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.session_same_path": 8.0,
    # First-freeze headroom for cli_selectors.session_quoted_p.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.session_quoted_p": 8.0,
    # First-freeze headroom for cli_selectors.session_named_p.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.session_named_p": 8.0,
    # First-freeze headroom for cli_selectors.settings_thinking_description.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.settings_thinking_description": 8.0,
    # First-freeze headroom for cli_selectors.settings_display_value.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.settings_display_value": 8.0,
    # First-freeze headroom for cli_selectors.settings_automatic_theme_setting.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.settings_automatic_theme_setting": 8.0,
    # First-freeze headroom for cli_selectors.settings_active_automatic_theme.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.settings_active_automatic_theme": 8.0,
    # First-freeze headroom for cli_selectors.settings_cycle.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.settings_cycle": 8.0,
    # First-freeze headroom for cli_selectors.settings_apply_filter.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.settings_apply_filter": 8.0,
    # First-freeze headroom for cli_selectors.tree_entry_filtered.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.tree_entry_filtered": 8.0,
    # First-freeze headroom for cli_selectors.tree_query_matches.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.tree_query_matches": 8.0,
  # First-freeze headroom for cli_selectors.tree_entry_search_text.
  # Ratchet down only after a non-quick Friend-MachineD freeze.
  "cli_selectors.tree_entry_search_text": 8.0,
  # First-freeze headroom for cli_selectors.tree_settings_entry_p.
  # Ratchet down only after a non-quick Friend-MachineD freeze.
  "cli_selectors.tree_settings_entry_p": 8.0,
  # First-freeze headroom for cli_selectors.tree_normalize_display_text.
  # Ratchet down only after a non-quick Friend-MachineD freeze.
  "cli_selectors.tree_normalize_display_text": 8.0,
  # First-freeze headroom for cli_selectors.tree_status_labels.
  # Ratchet down only after a non-quick Friend-MachineD freeze.
  "cli_selectors.tree_status_labels": 8.0,
  # First-freeze headroom for cli_selectors.tree_shorten_path.
  # Ratchet down only after a non-quick Friend-MachineD freeze.
  "cli_selectors.tree_shorten_path": 8.0,
  # First-freeze headroom for cli_selectors.tree_foldable_p.
  # Ratchet down only after a non-quick Friend-MachineD freeze.
  "cli_selectors.tree_foldable_p": 8.0,
  # First-freeze headroom for cli_selectors.tree_tool_argument.
  # Ratchet down only after a non-quick Friend-MachineD freeze.
  "cli_selectors.tree_tool_argument": 8.0,
  # First-freeze headroom for cli_selectors.tree_cycle_filter.
  # Ratchet down only after a non-quick Friend-MachineD freeze.
  "cli_selectors.tree_cycle_filter": 8.0,
  # First-freeze headroom for cli_selectors.tree_format_label_timestamp.
  # Ratchet down only after a non-quick Friend-MachineD freeze.
  "cli_selectors.tree_format_label_timestamp": 8.0,
  # First-freeze headroom for cli_selectors.tree_format_tool_call.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_format_tool_call": 8.0,
  # First-freeze headroom for cli_selectors.tree_entry_display_text.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_entry_display_text": 8.0,
  # First-freeze headroom for cli_selectors.tree_prefix.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_prefix": 8.0,
  # First-freeze headroom for cli_selectors.tree_visual_nodes.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_visual_nodes": 8.0,
  # First-freeze headroom for cli_selectors.tree_horizontal_viewport.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_horizontal_viewport": 8.0,
  # First-freeze headroom for cli_selectors.tree_help_keys.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_help_keys": 8.0,
  # First-freeze headroom for cli_selectors.tree_help_key.
  # Measure-only pair (Pair 189); ceiling not lowered.
  "cli_selectors.tree_help_key": 8.0,
  # First-freeze headroom for cli_selectors.tree_app_key_p.
  # Measure-only pair (Pair 190); ceiling not lowered.
  "cli_selectors.tree_app_key_p": 8.0,
  # First-freeze headroom for cli_selectors.tree_help_lines.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_help_lines": 8.0,
  # First-freeze headroom for cli_selectors.tree_active_path.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_active_path": 8.0,
  # First-freeze headroom for cli_selectors.tree_nearest_visible_id.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_nearest_visible_id": 8.0,
  # First-freeze headroom for cli_selectors.tree_prioritize_active.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_prioritize_active": 8.0,
  # First-freeze headroom for cli_selectors.tree_entry_map.
  # Measure-only pair (Pair 186); ceiling not lowered.
  "cli_selectors.tree_entry_map": 8.0,
  # First-freeze headroom for cli_selectors.tree_order_entries.
  # Measure-only pair (Pair 187); ceiling not lowered.
  "cli_selectors.tree_order_entries": 8.0,
  # First-freeze headroom for cli_selectors.tree_iso_timestamp.
  # Measure-only pair (Pair 188); ceiling not lowered.
  "cli_selectors.tree_iso_timestamp": 8.0,
  # First-freeze headroom for cli_selectors.tree_rebuild_visible_maps.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_rebuild_visible_maps": 8.0,
  # First-freeze headroom for cli_selectors.tree_apply_filter.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_apply_filter": 8.0,
  # First-freeze headroom for cli_selectors.tree_render_lines.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_render_lines": 8.0,
  # First-freeze headroom for cli_selectors.tree_move.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_move": 8.0,
  # First-freeze headroom for cli_selectors.tree_fold_or_up.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_fold_or_up": 8.0,
  # First-freeze headroom for cli_selectors.tree_unfold_or_down.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_unfold_or_down": 8.0,
  # First-freeze headroom for cli_selectors.tree_branch_segment_id.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_branch_segment_id": 8.0,
  # First-freeze headroom for cli_selectors.tree_set_query.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_set_query": 8.0,
  # First-freeze headroom for cli_selectors.tree_set_filter.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_set_filter": 8.0,
  # First-freeze headroom for cli_selectors.tree_copy_selected.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_copy_selected": 8.0,
  # First-freeze headroom for cli_selectors.tree_toggle_label_timestamps.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_toggle_label_timestamps": 8.0,
  # First-freeze headroom for cli_selectors.tree_start_label_edit.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_start_label_edit": 8.0,
  # First-freeze headroom for cli_selectors.tree_confirm_label.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_confirm_label": 8.0,
  # First-freeze headroom for cli_selectors.tree_cancel_label.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_cancel_label": 8.0,
  # First-freeze headroom for cli_selectors.tree_handle_raw_input.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_handle_raw_input": 8.0,
  # First-freeze headroom for cli_selectors.tree_handle_event.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_handle_event": 8.0,
  # First-freeze headroom for cli_selectors.tree_handle_label_event.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_handle_label_event": 8.0,
  # First-freeze headroom for cli_selectors.tree_selected_entry.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_selected_entry": 8.0,
  # First-freeze headroom for cli_selectors.tree_selected_id.
  # Measure-only pair (Pair 185); selected id accessor.
  "cli_selectors.tree_selected_id": 8.0,
  # First-freeze headroom for cli_selectors.tree_select_id.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_select_id": 8.0,
  # First-freeze headroom for cli_selectors.tree_visible_ids.
  # Measure-only pair; ceiling not lowered.
  "cli_selectors.tree_visible_ids": 8.0,
  # First-freeze headroom for cli_selectors.project_trust_options.
  # Measure-only pair (Pair 191); ceiling not lowered.
  "cli_selectors.project_trust_options": 8.0,
  # First-freeze headroom for cli_selectors.trust_selector_selection.
  # Measure-only pair (Pair 192); ceiling not lowered.
  "cli_selectors.trust_selector_selection": 8.0,
  # First-freeze headroom for cli_selectors.trust_decision_description.
  # Measure-only pair (Pair 193); ceiling not lowered.
  "cli_selectors.trust_decision_description": 8.0,
  # First-freeze headroom for cli_selectors.trust_selector_move.
  # Measure-only pair (Pair 194); ceiling not lowered.
  "cli_selectors.trust_selector_move": 8.0,
  # First-freeze headroom for cli_selectors.trust_selector_handle_event.
  # Measure-only pair (Pair 195); ceiling not lowered.
  "cli_selectors.trust_selector_handle_event": 8.0,
  # First-freeze headroom for cli_selectors.trust_selector_handle_raw_input.
  # Measure-only pair (Pair 196); ceiling not lowered.
  "cli_selectors.trust_selector_handle_raw_input": 8.0,
  # First-freeze headroom for cli_selectors.trust_selector_ui_state.
  # Measure-only pair (Pair 197); ceiling not lowered.
  "cli_selectors.trust_selector_ui_state": 8.0,
  # First-freeze headroom for cli_selectors.oauth_option_status_label.
  # Measure-only pair (Pair 198); ceiling not lowered.
  "cli_selectors.oauth_option_status_label": 8.0,
  # First-freeze headroom for cli_selectors.oauth_option_status_rendered.
  # Measure-only pair (Pair 211); first freeze 10.63× (15.2 / 1.4 µs).
  "cli_selectors.oauth_option_status_rendered": 15.0,
  # First-freeze headroom for cli_selectors.credential_entry_auth_type.
  # Measure-only pair (Pair 199); ceiling not lowered.
  "cli_selectors.credential_entry_auth_type": 8.0,
  # First-freeze headroom for cli_selectors.oauth_environment_source_p.
  # Measure-only pair (Pair 200); ceiling not lowered.
  "cli_selectors.oauth_environment_source_p": 8.0,
  # First-freeze headroom for cli_selectors.oauth_selector_selection.
  # Measure-only pair (Pair 201); ceiling not lowered.
  "cli_selectors.oauth_selector_selection": 8.0,
  # First-freeze headroom for cli_selectors.oauth_selector_apply_filter.
  # Measure-only pair (Pair 202); ceiling not lowered.
  "cli_selectors.oauth_selector_apply_filter": 8.0,
  # First-freeze headroom for cli_selectors.oauth_selector_handle_event.
  # Measure-only pair (Pair 203); ceiling not lowered.
  "cli_selectors.oauth_selector_handle_event": 8.0,
  # First-freeze headroom for cli_selectors.oauth_selector_handle_raw_input.
  # Measure-only pair (Pair 204); ceiling not lowered.
  "cli_selectors.oauth_selector_handle_raw_input": 8.0,
  # First-freeze headroom for cli_selectors.oauth_selector_search_text.
  # Measure-only pair (Pair 205); ceiling not lowered.
  "cli_selectors.oauth_selector_search_text": 8.0,
  # First-freeze headroom for cli_selectors.login_auth_type_route.
  # Measure-only pair (Pair 206); ceiling not lowered.
  "cli_selectors.login_auth_type_route": 8.0,
  # First-freeze headroom for cli_selectors.login_provider_options.
  # Measure-only pair (Pair 207); ceiling not lowered.
  "cli_selectors.login_provider_options": 8.0,
  # First-freeze headroom for cli_selectors.logout_provider_options.
  # Measure-only pair (Pair 208); ceiling not lowered.
  "cli_selectors.logout_provider_options": 8.0,
  # First-freeze headroom for cli_selectors.login_method_selector_handle_event.
  # Measure-only pair (Pair 209); ceiling not lowered.
  "cli_selectors.login_method_selector_handle_event": 8.0,
  # First-freeze headroom for cli_selectors.oauth_selector_move.
  # Measure-only pair (Pair 210); ceiling not lowered.
  "cli_selectors.oauth_selector_move": 50.0,
  # First-freeze headroom for cli_selectors.api_key_input_state_handle_event.
  # Measure-only pair (Pair 212); first freeze 1.66× (7.0 / 4.2 µs).
  "cli_selectors.api_key_input_state_handle_event": 8.0,
  # First-freeze headroom for cli_selectors.login_method_selector_ui_state.
  # Measure-only pair (Pair 213); first freeze 10.07× (622.6 / 61.8 µs).
  "cli_selectors.login_method_selector_ui_state": 12.0,
  # First-freeze headroom for cli_selectors.api_key_input_ui_state.
  # Measure-only pair (Pair 214); first freeze 4.86× (263.5 / 54.2 µs).
  "cli_selectors.api_key_input_ui_state": 8.0,
  # First-freeze headroom for cli_selectors.oauth_selector_ui_state.
  # Measure-only pair (Pair 215); first freeze 24.66× (372.1 / 15.1 µs).
  "cli_selectors.oauth_selector_ui_state": 35.0,
  # First-freeze headroom for cli_selectors.model_selector_search_text.
  # Measure-only pair (Pair 216); ceiling not lowered.
  "cli_selectors.model_selector_search_text": 8.0,
  # First-freeze headroom for cli_selectors.qualified_model_id.
  "cli_selectors.qualified_model_id": 8.0,
  "cli_selectors.model_selector_apply_filter": 8.0,
  # First-freeze headroom for cli_selectors.model_selector_move.
  # Measure-only pair (Pair 219); first freeze 17.63×.
  "cli_selectors.model_selector_move": 20.0,
  "cli_selectors.model_selector_handle_event": 8.0,
  "cli_selectors.model_selector_handle_raw_input": 8.0,
  "cli_selectors.model_selector_set_query": 8.0,
  # First-freeze headroom for cli_selectors.model_selector_selected_model.
  # Measure-only pair (Pair 223); first freeze 9.75×.
  "cli_selectors.model_selector_selected_model": 12.0,
  "cli_selectors.model_selector_toggle_scope": 8.0,
  "cli_selectors.model_selector_ui_state": 35.0,
  "cli_selectors.scoped_models_selector_set_query": 8.0,
  # First-freeze headroom for cli_selectors.scoped_models_selector_move.
  # Measure-only pair (Pair 227); first freeze 14.16×.
  "cli_selectors.scoped_models_selector_move": 20.0,
  # First-freeze headroom for cli_selectors.scoped_models_selector_handle_event.
  # Measure-only pair (Pair 228); first freeze 10.40×.
  "cli_selectors.scoped_models_selector_handle_event": 12.0,
  "cli_selectors.scoped_models_selector_handle_raw_input": 8.0,
  "cli_selectors.scoped_models_selector_ui_state": 35.0,
  # First-freeze headroom for cli_selectors.scoped_models_selector_sorted_ids.
  # Measure-only pair (Pair 233); first freeze 37.36×.
  "cli_selectors.scoped_models_selector_sorted_ids": 50.0,
  # Measure-only pair (Pair 232); first freeze 43.32x.
  "cli_selectors.scoped_models_selector_counts": 55.0,
  "cli_selectors.scoped_models_selector_toggle_selected": 8.0,
  "cli_selectors.scoped_models_selector_toggle_provider": 8.0,
  "cli_selectors.scoped_models_selector_clear_all": 25.0,
  "cli_selectors.scoped_models_selector_reorder": 8.0,
  # Measure-only pair (Pair 239); first freeze 20.35×.
  "cli_selectors.scoped_models_selector_persist": 25.0,
  # Measure-only pair (Pair 240); first freeze 46.24×.
  "cli_selectors.scoped_models_selector_provider_count": 50.0,
  "cli_selectors.scoped_models_selector_target_ids": 8.0,
  # Measure-only pair (Pair 235); first freeze 20.77×.
  "cli_selectors.scoped_models_selector_enable_all": 25.0,
  # Frozen from the first Friend-MachineD non-quick
    # websocket_stream.stream_roundtrip pair (samples=5):
    # observed 507.72x (44298 / 87.25 us). TCP loopback
    # vs MockWebSocket. 800.0 is first-freeze headroom.
    # Ratchet down only.
    "websocket_stream.stream_roundtrip": 800.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_sdk pair (samples=5): observed 0.40x
    # (4.1 / 10.3 us). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "cli_sdk.version_newer": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_sdk.cache_miss pair (samples=5): observed
    # 0.55x (2.29 / 4.13 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "cli_sdk.cache_miss": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_sdk.cache_waste pair (samples=5): observed
    # 0.60x (3.96 / 6.56 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "cli_sdk.cache_waste": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_sdk.thinking_level pair (samples=5): observed
    # 3.21x (0.72 / 0.22 us). 8.0 follows the
    # microsecond-floor first-freeze headroom. Ratchet down
    # only.
    "cli_sdk.thinking_level": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_sdk.session_list pair (samples=5): observed
    # 1.93x (15402 / 7989 us). cadr full-loads; pi
    # SessionInfo. 8.0 is first-freeze headroom.
    # Ratchet down only.
    "cli_sdk.session_list": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_sdk.agent_session pair (samples=5): observed
    # 0.36x (3151 / 8769 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "cli_sdk.agent_session": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_sdk.session_services pair (samples=5): observed
    # 0.24x (2306 / 9493 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "cli_sdk.session_services": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_sdk.model_runtime pair (samples=5): observed
    # 0.58x (2243 / 3858 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "cli_sdk.model_runtime": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # provider_registry_defs pair (samples=5): observed 4.44x
    # (1.03 / 0.23 us). 8.0 follows the microsecond-floor
    # first-freeze headroom. Ratchet down only.
    "provider_registry_defs.lookup": 8.0,
    # provider_registry_defs.definition_ids pair (samples=5): observed 99.97x
    # (728.7 / 7.3 us). 125.0 is first-freeze headroom. Ratchet down only.
    "provider_registry_defs.definition_ids": 125.0,
    # provider_registry_defs.merge_environment pair (samples=5): observed 0.114x
    # (0.320 / 2.803 us). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "provider_registry_defs.merge_environment": 8.0,
    # provider_registry_defs.runtime_models pair (samples=5): observed 3.733x
    # (17.89 / 4.794 us). 8.0 is first-freeze headroom. Ratchet down only.
    "provider_registry_defs.runtime_models": 8.0,
    # provider_registry_defs.structured_api_key_login pair (samples=5): observed 0.000831x
    # (0.176 / 211.2 us). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "provider_registry_defs.structured_api_key_login": 8.0,
    # core_rest.cancellation_abort pair (samples=5): observed 0.0712x
    # (0.579 / 8.130 us). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "core_rest.cancellation_abort": 8.0,
    # core_rest.redacted_secrets pair (samples=5): observed 2.488x
    # (2.750 / 1.105 us). 8.0 is first-freeze headroom. Ratchet down only.
    "core_rest.redacted_secrets": 8.0,
    # core_rest.threads_cleanup pair (samples=5): observed 0.00799x
    # (181.6 / 22730 us). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "core_rest.threads_cleanup": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # skill_prompt_load pair (samples=5): observed 1170.57x
    # (2196 / 1.88 us). Keyword initforms still hit ASDF
    # on the custom-prompt path. 3000.0 is first-freeze
    # headroom. Ratchet down only.
    "skill_prompt_load.build_prompt": 3000.0,
    # Frozen from the first Friend-MachineD non-quick
    # cli_bootstrap_sessions pair (samples=5): observed 2.40x
    # (11.1 / 4.6 us). 8.0 is first-freeze headroom.
    # Ratchet down only.
    "cli_bootstrap_sessions.coding_tools": 8.0,
    # cli_bootstrap_sessions.bootstrap_auth pair (samples=5): observed 0.64x
    # (3928.6 / 6134.0 us). 8.0 is first-freeze headroom. Ratchet down only.
    "cli_bootstrap_sessions.bootstrap_auth": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # ai_runtime_faux pair (samples=5): observed 1.76x
    # (0.27 / 0.15 us). 8.0 is first-freeze headroom
    # (variance; sub-10 us floor). Ratchet down only.
    "ai_runtime_faux.blocks": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # http_transport pair (samples=5): observed 0.99x
    # (1.16 / 1.17 us). 8.0 is first-freeze headroom
    # (variance). Ratchet down only.
    "http_transport.parse_url": 8.0,
    "session_pipeline.session_load": 9.0,
    "session_pipeline.context_walk": 2.0,
    # Frozen from the first Friend-MachineD non-quick
    # session_pipeline.session_leaf_id pair (samples=5): observed
    # 0.74x (0.04 / 0.05 us). 8.0 is first-freeze headroom
    # (microsecond-floor / variance). Ratchet down only.
    "session_pipeline.session_leaf_id": 8.0,
    "storage_journal.journal_read": 8.0,
    "storage_journal.journal_append": 12.0,
    # storage_journal.journal_entry_count pair (samples=5): observed 0.06x
    # (0.22 / 3.7 us). 8.0 is first-freeze headroom. Ratchet down only.
    "storage_journal.journal_entry_count": 8.0,
    # Frozen from the first Friend-MachineD non-quick sqlite_session
    # pair (samples=5): observed 0.15x. cadr leads. 1.5 follows the
    # list_models_registry / render_slicing precedent (headroom above
    # 1.0). Ratchet down only.
    "sqlite_session.open_walk": 1.5,
    # Frozen from the first Friend-MachineD non-quick tool_read pair
    # (samples=5): observed 5.32x (21747 / 4087 µs). 8.0 follows the
    # journal_read headroom precedent. Ratchet down only.
    "tool_read.text_file": 8.0,
    # Frozen from the first Friend-MachineD non-quick tool_grep pair
    # (samples=5): observed 1.77x (28357 / 16053 µs). 3.0 follows the
    # argv_parse headroom precedent. Ratchet down only.
    "tool_grep.context_file": 3.0,
    # Frozen from the first Friend-MachineD non-quick agent_tool_loop
    # pair (samples=5): observed 0.77x (329 / 428 µs). cadr leads. 1.5
    # follows the list_models_registry / render_slicing precedent
    # (headroom above 1.0). Ratchet down only.
    "agent_tool_loop.roundtrip": 1.5,
    # Frozen from the first Friend-MachineD non-quick
    # agent_tool_loop.tool_path pair (samples=5): observed
    # 2.44x (12.74 / 5.23 us). 8.0 is first-freeze
    # headroom. Ratchet down only.
    "agent_tool_loop.tool_path": 8.0,
    # First-freeze headroom for agent_tool_loop.line_ending. Observed
    # numbers filled after Friend-MachineD n=5. Ratchet down only.
    "agent_tool_loop.line_ending": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # agent_tool_loop.tool_result_digest pair (samples=5): observed
    # 107.57x (289.4 / 2.7 us). 125.0 follows the
    # provider_registry_defs.definition_ids headroom precedent.
    # Ratchet down only.
    "agent_tool_loop.tool_result_digest": 125.0,
    "agent_tool_loop.runtime": 8.0,
    # Frozen from the first Friend-MachineD non-quick session_compact
    # pair (samples=5): observed 11.33x (965 / 85 µs). 20.0 follows
    # the truncate_head headroom precedent. Ratchet down only.
    "session_compact.compact": 20.0,
    # First-freeze headroom for session_compact.branch_summarize. Observed
    # numbers filled after Friend-MachineD n=5. Ratchet down only.
    "session_compact.branch_summarize": 20.0,
    "session_compact.prepare_branch_entries": 20.0,
    # Initial values frozen from the first full measurement (2026-08-15,
    # Friend-MachineD, samples=5): head 16.71x, tail 15.27x.  These record
    # that cadr currently LOSES to pi on truncation (whole-content encode +
    # per-line passes vs Buffer.byteLength); Part O owns pulling them down.
    # Ratchet down only.
    "text_truncation.truncate_head": 20.0,
    "text_truncation.truncate_tail": 18.0,
    # text_truncation.truncate_middle pair (samples=5): observed 0.12x
    # (1777.8 / 14420.3 us). cadr leads. 8.0 follows the normalize_steps
    # headroom precedent. Ratchet down only.
    "text_truncation.truncate_middle": 8.0,
    # cadr currently WINS here (2026-08-15 quick run: 0.26x / 0.21x) after
    # the 12F-2 span-iteration rewrite; pi still pays the quadratic
    # pendingAnsi concat.  1.5 follows the list_models_registry precedent:
    # headroom above 1.0 so jitter cannot false-red a metric cadr leads.
    "render_slicing.slice_ansi_clip": 1.5,
    "render_slicing.slice_plain_clip": 1.5,
}

# Absolute allowance for the microsecond-scale metrics.  goal11's own limit
# carries a 5000us floor because a ratio between two frame times is noise at
# small absolute values; the same is true here at a much smaller scale, where
# pi's help render lands under a microsecond and its run-to-run swing alone
# moves the ratio between 3.9x and 5.6x.  A 10us allowance cannot be perceived
# in a CLI dispatch and is 500x tighter than the goal11 floor.
MICROSECOND_FLOOR_US = 10.0

# Observed values that must be identical: same fixture in, same work done.
OBSERVED_EXACT = {
    "render_slicing": (
        "dense_clip_text",
        "dense_clip_width",
        "dense_head_text",
        "dense_head_width",
        "plain_clip_text",
        "plain_clip_width",
    ),
    "text_truncation": (
        "content_bytes",
        "head_output_lines",
        "head_output_bytes",
        "head_truncated_by",
        "head_first_line_exceeds",
        "tail_output_lines",
        "tail_output_bytes",
        "tail_truncated_by",
        "tail_last_line_partial",
        "middle_output_lines",
        "middle_output_bytes",
        "middle_truncated_by",
        "middle_omitted_lines",
        "middle_first_line_exceeds",
    ),
    "cli_dispatch": (
        "parsed_provider",
        "parsed_model",
        "parsed_thinking",
        "parsed_tools",
        "parsed_exclude_tools",
        "parsed_messages",
        "parsed_file_args",
        "parsed_list_models",
        "parsed_unknown_flag_count",
        "parsed_diagnostic_count",
        "available_model_count",
        "available_providers",
        "list_models_characters",
        "list_models_lines",
    ),
    "provider_stream": (
        "payload_keys",
        "payload_message_count",
        "payload_tool_count",
        "payload_stream",
        "content_block_types",
        "text_characters",
        "tool_call_count",
        "stop_reason",
        "usage_input",
        "usage_output",
    ),
    "provider_anthropic": (
        "content_block_types",
        "stop_reason",
        "text_characters",
        "tool_call_count",
        "usage_input",
        "usage_output",
        "payload_stream",
        "payload_tool_count",
    ),
    "provider_google": (
        "content_block_types",
        "stop_reason",
        "text_characters",
        "tool_call_count",
        "usage_input",
        "usage_output",
        "payload_tool_count",
    ),
    "provider_bedrock": (
        "content_block_types",
        "stop_reason",
        "text_characters",
        "tool_call_count",
        "usage_input",
        "usage_output",
        "payload_tool_count",
    ),
    "provider_mistral": (
        "content_block_types",
        "stop_reason",
        "text_characters",
        "tool_call_count",
        "usage_input",
        "usage_output",
        "payload_stream",
        "payload_tool_count",
    ),
    "provider_openai_responses": (
        "content_block_types",
        "stop_reason",
        "text_characters",
        "tool_call_count",
        "usage_input",
        "usage_output",
        "payload_stream",
        "payload_tool_count",
    ),
    "provider_azure_openai": (
        "content_block_types",
        "stop_reason",
        "text_characters",
        "tool_call_count",
        "usage_input",
        "usage_output",
        "payload_stream",
        "payload_tool_count",
    ),
    "provider_vertex": (
        "content_block_types",
        "stop_reason",
        "text_characters",
        "tool_call_count",
        "usage_input",
        "usage_output",
        "payload_tool_count",
        "adc_type",
    ),
    "provider_codex": (
        "content_block_types",
        "stop_reason",
        "text_characters",
        "tool_call_count",
        "usage_input",
        "usage_output",
        "payload_stream",
        "payload_tool_count",
    ),
    "provider_pi_messages": (
        "content_block_types",
        "stop_reason",
        "text_characters",
        "tool_call_count",
        "usage_input",
        "usage_output",
        "payload_tool_count",
    ),
    "cli_settings": (
        "theme",
        "default_model",
        "default_provider",
        "compaction_reserve_tokens",
        "default_project_trust",
        "http_idle_timeout_ms",
        "project_trusted",
        "rl_theme_light",
        "rl_model",
        "rl_idle",
        "rl_n",
        "em_all",
        "em_one",
        "em_n",
        "bi_default",
        "bi_blocked",
        "bi_n",
    ),
    "agent_conditions": (
        "ac_schema_tool",
        "ac_schema_ptr",
        "ac_schema_reason",
        "ac_tool_name",
        "ac_tool_id",
        "ac_sess_path",
        "ac_sess_line",
        "ac_sub_schema",
        "ac_sub_tool",
        "ac_sub_ext_reg",
        "ac_sub_ext_exec",
        "ac_sub_stale",
        "ac_sub_session",
        "ac_catch_busy",
        "ac_catch_shutdown",
        "ac_catch_turn",
        "ac_catch_ext_reg",
        "ac_catch_ext_exec",
        "ac_catch_stale",
    ),
    "execution_env": (
        "ex_missing",
        "ex_present",
        "ex_after_rm",
        "tmp_dir",
        "tmp_file",
        "tmp_suffix",
        "rm_force",
        "rm_recursive",
    ),
    "file_mutation_queue": (
        "fmq_alias_key",
        "fmq_missing_key",
        "fmq_other_key",
        "fmq_fifo_sum",
        "fmq_other_run",
        "fmq_clean",
        "fmqk_alias",
        "fmqk_missing",
        "fmqk_other",
        "fmqk_n",
        "fmql_alias",
        "fmql_other",
        "fmql_missing",
        "fmql_repeat",
        "fmql_n",
        "fmqr_alias",
        "fmqr_other",
        "fmqr_pending",
        "fmqr_ticket",
        "fmqr_n",
        "fmqw_serving",
        "fmqw_pending",
        "fmqw_other",
        "fmqw_missing",
        "fmqw_n",
        "fmqe_serving",
        "fmqe_pending",
        "fmqe_other",
        "fmqe_missing",
        "fmqe_n",
        "fmqs_alias",
        "fmqs_other",
        "fmqs_missing",
        "fmqs_repeat",
        "fmqs_n",
        "fmqf_alias",
        "fmqf_other",
        "fmqf_fifo",
        "fmqf_run",
        "fmqf_n",
        "fmqm_pending",
        "fmqm_ticket",
        "fmqm_serving",
        "fmqm_other",
        "fmqm_n",
        "fmqt_alias",
        "fmqt_other",
        "fmqt_missing",
        "fmqt_repeat",
        "fmqt_n",
        "fmqp_shared",
        "fmqp_other",
        "fmqp_missing",
        "fmqp_alias",
        "fmqp_n",
        "fmqi_shared",
        "fmqi_other",
        "fmqi_missing",
        "fmqi_alias",
        "fmqi_n",
        "fmqv_zero",
        "fmqv_other",
        "fmqv_missing",
        "fmqv_alias",
        "fmqv_n",
    ),
    "harness_events": (
        "he_direct",
        "he_watch",
        "he_start",
        "he_end",
        "he_second",
        "heon_off",
        "heon_keep",
        "heon_type",
        "hew_snap",
        "hew_count",
        "hew_start",
        "hew_end",
        "hes_type",
        "hes_lane",
        "hes_run",
        "hee_type",
        "hee_lane",
        "hee_run",
        "hee_outcome",
        "hee_abort",
        "het_start",
        "het_end",
        "het_fail",
        "heb_distinct",
        "heb_a",
        "heb_b",
    ),
    "bash_tool": (
        "sef_exact",
        "sef_nl",
        "sef_no_nl",
        "sef_plain",
        "sef_empty",
        "sef_n",
        "abs_empty",
        "abs_abort",
        "abs_exit",
        "abs_timeout",
        "abs_n",
        "btn_none",
        "btn_partial",
        "btn_lines",
        "btn_bytes",
        "btn_n",
        "lo_repl",
        "lo_tui",
        "lo_print",
        "lo_rpc",
        "ss_exact",
        "ss_nl",
        "ss_plain",
        "ss_trim",
        "st_none",
        "st_footer",
        "st_no_full",
        "st_plain",
    ),
    "output_accumulator": (
        "oa_append_bytes",
        "oa_append_trunc",
        "oa_append_lines",
        "oa_append_last",
        "oa_append_n",
        "oa_snap_bytes",
        "oa_snap_trunc",
        "oa_snap_lines",
        "oa_snap_total",
        "oa_snap_n",
        "oa_fin_bytes",
        "oa_fin_fffd",
        "oa_fin_last",
        "oa_fin_trunc",
        "oa_fin_n",
    ),
    "find_tool": (
        "fpm_star_a",
        "fpm_star_src",
        "fpm_star_txt",
        "fpm_path_src",
        "fpm_path_root",
        "fpm_src_star",
        "fpm_n",
        "ff_empty",
        "ff_lisp",
        "ff_path",
        "ff_src_star",
        "ff_n",
        "fmt_name",
        "fmt_desc",
        "fmt_req",
        "fmt_n",
    ),
    "write_tool": (
        "ep_nested",
        "ep_exists",
        "ep_eexist",
        "ep_n",
        "wu_ok",
        "wu_ascii",
        "wu_cjk",
        "wu_n",
        "wmt_name",
        "wmt_desc",
        "wmt_req",
        "wmt_n",
    ),
    "ls_tool": (
        "lden_file",
        "lden_dir",
        "lden_nested",
        "lden_n",
        "ld_empty",
        "ld_mixed",
        "ld_first",
        "ld_limit",
        "ld_n",
        "lst_name",
        "lst_desc",
        "lst_req",
        "lst_n",
    ),
    "tool_manager": (
        "gtp_local_fd",
        "gtp_local_rg",
        "gtp_miss_fd",
        "gtp_miss_rg",
        "gtp_n",
        "et_local_fd",
        "et_offline_miss",
        "et_n",
        "cq_removed",
        "cq_noop",
        "cq_n",
    ),
    "powershell_tool": (
        "psu_len",
        "psu_nl",
        "psu_try",
        "psu_utf8",
        "psu_n",
        "psc_empty",
        "psc_date",
        "psc_write",
        "psc_n",
        "pmt_name",
        "pmt_desc",
        "pmt_req",
        "pmt_n",
    ),
    "settings_load": (
        "tr_empty",
        "tr_proj",
        "rs_empty",
        "rs_ask",
        "rs_always",
        "rs_never",
        "rs_ov_yes",
        "rs_ov_no",
        "cv_lit",
        "cv_dol",
        "cv_brace",
        "cv_esc",
        "cv_bang",
        "cv_miss",
        "cv_mix",
        "cv_cmd",
        "ht_30",
        "ht_1m",
        "ht_2m",
        "ht_5m",
        "ht_off",
        "sas_missing",
        "sas_fixture",
        "sas_oauth",
        "sas_bad",
        "sas_fixture_key",
        "sas_oauth_access",
        "sas_oauth_refresh",
        "cp_auth_eq",
        "cp_cfg_eq",
        "cp_same_p",
        "cp_auth_leaf",
        "cp_cfg_leaf",
    ),
    "package_manager": (
        "package_count",
        "skill_count",
        "prompt_count",
        "theme_count",
        "extension_count",
        "manifest_p",
        "manifest_extensions",
        "manifest_skills",
        "manifest_prompts",
        "manifest_themes",
        "ps_npm_pin",
        "ps_npm_rng",
        "ps_git",
        "ps_git_pin",
        "ps_local",
        "ps_ref_ok",
        "ps_git_id",
        "ps_ded_n",
        "ps_ded_proj",
    ),
    "session_discovery": (
        "file_count",
        "header_count",
        "found",
        "session_id",
        "most_recent_name",
        "list_count",
        "list_id",
        "list_most_recent_name",
        "empty_count",
    ),
    "session_export_html": (
        "has_accent",
        "theme",
    ),
    "protocol_cbor": (
        "vector_count",
        "roundtrip_hex",
        "match",
    ),
    "agent_schema": (
        "ok",
        "fail",
        "tool",
    ),
    "harness_storage": (
        "entry_count",
        "leaf_id",
        "ingested_entry_count",
        "session_id",
        "source_leaf_id",
    ),
    "protocol_codec": (
        "frame_bytes",
        "message_count",
        "type",
        "id",
        "command",
    ),
    "agent_proxy": (
        "event_count",
        "text",
        "usage_total",
    ),
    "oauth_pkce": (
        "challenge",
        "openai_has_challenge",
        "anthropic_has_challenge",
        "openai_prefix",
        "anthropic_prefix",
    ),
    "oauth_pkce_device": (
        "dc_ok",
        "dc_fail",
        "dc_cancel",
        "ak_ok",
        "ak_len",
        "oa_ok",
        "oa_len",
        "auth_miss",
        "auth_bad",
        "gc_def",
        "gc_ind",
        "gc_ent",
        "gc_dom",
        "cf_plain",
        "cf_ok",
        "cf_gw",
        "rg_slash",
        "rg_plain",
        "rg_http",
        "ga_def",
        "ga_ind",
        "ga_ent",
        "ga_dom",
        "ga_key",
        "pd_plain",
        "pd_plus",
        "pd_slash",
        "pd_space",
        "pd_utf8",
        "pd_n",
        "pq_code",
        "pq_state",
        "pq_plus",
        "pq_empty",
        "pq_n",
        "pai_url",
        "pai_hash",
        "pai_qs",
        "pai_plain",
        "pai_n",
    ),
    "cli_extensions_install": (
        "nu_local",
        "nu_https",
        "nu_file",
        "inf_ok",
        "fb_b",
        "fb_k",
        "hf_env",
        "hf_path",
        "hf_home",
        "hf_miss",
        "hf_blank",
        "lc_n",
        "lc_img",
        "lc_ctx",
        "lc_url",
        "lc_sleep",
        "lc_fb",
        "ed_n",
        "ed_err",
        "ed_coll",
        "ed_cli",
        "ed_proj",
        "ed_glob",
        "ed_probe",
        "ed_miss",
    ),
    "evals_harness": (
        "eval_sets",
        "comparisons",
        "candidate_wins",
        "ties",
        "gk_id",
        "gk_trim",
        "art_ok",
        "art_bad",
        "ap_n",
        "ap_sess",
        "ap_src",
        "ap_sess_prefix",
        "ap_src_prefix",
        "ap_sess_file",
        "ap_src_file",
        "fmt_empty",
        "fmt_empty_hdr",
        "fmt_hdr",
        "fmt_base",
        "fmt_pass",
        "ns_empty",
        "ns_str_n",
        "ns_str_pr",
        "ns_seq_n",
        "ns_seq_rel",
        "ns_kw_n",
        "ns_kw_rel",
        "ns_vec_n",
        "ns_bad",
        "rs_explicit",
        "rs_env",
        "rs_miss",
        "rs_prov",
        "rs_blank",
        "rs_n",
        "tr_n",
        "tr_user",
        "tr_role",
        "tr_text",
        "tr_call",
        "tr_name",
        "tr_result",
        "tr_err",
        "tr_keys",
        "la_new",
        "la_none",
        "la_full",
        "la_n",
        "sv_hash",
        "sv_plist",
        "sv_intern",
        "sv_miss",
        "sv_n",
        "us_in",
        "us_out",
        "us_total",
        "us_tools",
        "us_prov",
        "us_model",
        "us_cost",
        "us_n",
        "rj_out",
        "rj_ev",
        "rj_err",
        "rj_art",
        "rj_time",
        "rj_n",
        "ee_trim",
        "ee_model",
        "ee_ws",
        "ee_miss",
        "ee_n",
        "ps_type",
        "ps_content",
        "ps_n",
        "rs_type",
        "rs_no_content",
        "rs_n",
    ),
    "ai_crypto_model_data": (
        "schema_version",
        "structure_hash",
        "generated_at",
        "file_count",
        "openai_json_hash",
        "anthropic_json_hash",
    ),
    "ai_crypto": (
        "fox",
        "empty",
        "long",
    ),
    "cli_models_rest": (
        "exact_id",
        "exact_provider",
        "bare_id",
        "partial_id",
        "scoped_id",
        "scoped_thinking",
        "miss",
        "ac_skip",
        "ac_api",
        "ac_api_prov",
        "ac_bearer",
        "ac_exp",
        "ac_check",
        "ac_json",
        "ac_cred",
        "ac_noref",
        "ac_chk_prov",
        "ac_min_api",
        "ac_unknown",
        "ac_help",
        "ac_help2",
        "ls_xai",
        "ls_nodef",
        "ls_defun",
        "ls_ok",
        "ls_fail",
        "ls_nomodels_sub",
        "ls_nodef_sub",
    ),
    "image_runtime": (
        "png_width",
        "png_height",
        "gif_width",
        "gif_height",
        "miss",
        "png_mime",
        "jpeg_mime",
        "gif_mime",
        "webp_mime",
        "miss_mime",
        "gemini",
        "flux",
        "unknown",
        "note_resized",
        "note_half",
        "note_plain",
        "api_fixture",
        "api_unknown",
        "om_gemini_n",
        "om_gemini_text",
        "om_flux_n",
        "om_flux_text",
        "oc_text_type",
        "oc_text",
        "oc_img_type",
        "oc_img_url",
        "oc_ok",
        "pd_ok_mime",
        "pd_ok_data",
        "pd_ok",
        "pd_miss",
        "pd_plain",
    ),
    "cli_print_rpc": (
        "line_chars",
        "newline",
        "payload",
        "line_count",
        "first",
        "second",
        "last_line",
        "tl_off",
        "tl_high",
        "tl_xh",
        "tl_max",
        "tl_xh_down",
        "tl_unk",
        "tl_full_n",
        "tl_short_n",
        "ss_user",
        "ss_asst",
        "ss_tool",
        "ss_calls",
        "ss_total",
        "ss_id",
    ),
    "tui_latex": (
        "e_mc2",
        "frac_inline",
        "greek",
        "frac_display_newlines",
        "unknown_miss",
        "empty",
        "alpha",
        "frac",
        "script",
        "operator",
        "marker_edge",
    ),
    "tui_mermaid": (
        "mm_lr_w",
        "mm_lr_first",
        "mm_lr_rows",
        "mm_empty",
        "mm_unk",
        "mm_cjk_w",
        "sb_wide_w",
        "sb_wide_first",
        "sb_narrow_rows",
        "sb_empty_w",
        "tf_ok",
        "tf_art",
        "tf_off",
        "tf_think",
        "tf_wide",
        "tf_len",
    ),
    "tui_editor_helpers": (
        "gpt",
        "id_suffix",
        "swapped",
        "miss",
        "empty",
    ),
    "tui_theme_overlay": (
        "rgb_r",
        "rgb_g",
        "rgb_b",
        "hex6_r",
        "hex6_g",
        "hex6_b",
        "hex12_r",
        "miss",
        "scheme_dark",
    ),
    "ai_support": (
        "empty",
        "hello",
        "block",
        "prompt",
        "rate",
        "silent",
        "length",
        "d1",
        "d2",
        "d3",
        "started",
        "closed",
        "uuid_len",
        "uuid_hyphens",
        "uuid_version",
        "uuid_variant",
        "uuid_neq",
        "no_models",
        "no_selected",
        "no_key",
        "no_unknown",
        "has_login",
        "has_providers",
        "has_models",
    ),
    "tui_select_settings_loaders": (
        "he_count",
        "he_first",
        "wo_count",
        "zz_count",
    ),
    "tui_word_navigation": (
        "back_from_space",
        "fwd_from_o",
        "back_start",
        "fwd_end",
    ),
    "tui_overlay": (
        "line_chars",
        "visible_width",
        "has_reset",
    ),
    "tui_kill_ring": (
        "empty_len",
        "ring_len",
        "peek_two",
        "peek_rot",
        "acc_append",
        "acc_prepend",
    ),
    "tui_undo_stack": (
        "empty_len",
        "after_two",
        "pop_n",
        "after_pop",
        "clone_n",
        "after_clear",
    ),
    "tui_autocomplete": (
        "slash_count",
        "slash_help",
        "slash_hello",
        "slash_prefix",
        "quote_count",
        "quote_first_len",
        "force_count",
        "force_hello",
        "force_help",
        "at_count",
        "apply_col",
        "apply_len",
    ),
    "tui_keybindings": (
        "left_count",
        "left_ctrl_b",
        "hist_count",
        "enter_submit",
        "tab_tab",
        "enter_undo",
        "conflict_count",
        "conflict_key_len",
    ),
    "tui_stdin_buffer": (
        "hello_count",
        "leftover",
        "up_len",
        "paste_len",
        "tail_count",
    ),
    "tui_input_component": (
        "after_insert",
        "after_bs",
        "after_kill",
        "after_yank",
        "last_code",
    ),
    "tui_native_modifiers": (
        "shift",
        "control",
        "option",
        "command",
    ),
    "tui_settings_list": (
        "he_count",
        "he_hello",
        "he_help",
        "wo_count",
        "zz_count",
        "he_selected",
    ),
    "ai_capabilities": (
        "empty",
        "abc",
        "cjk",
        "off_imm",
        "off_def",
        "off_first",
        "off_second",
        "off_read",
        "on_imm",
        "on_def",
        "on_first",
        "on_second",
        "on_read",
        "ev_first",
        "ev_second",
        "ev_third",
        "ev_result",
        "px_hit",
        "px_star",
        "px_skip",
        "px_keep",
        "px_socks",
        "sr_first",
        "sr_n1",
        "sr_n2",
        "sr_err",
    ),
    "cli_support": (
        "csi_osc",
        "ris",
        "single",
        "plain",
        "trim",
        "at",
        "nbsp",
        "tilde",
        "file",
        "time_title",
        "time_boot",
        "time_load",
        "time_total",
        "eb_first",
        "eb_n1",
        "eb_n2",
        "eb_n3",
        "eb_throw",
        "at_or_ref",
        "at_or_title",
        "at_or_cat",
        "at_or_off",
        "at_nv",
        "at_cf",
        "at_oc_sess",
        "at_oc_client",
        "at_ov",
        "sh_def",
        "sh_arg",
        "sh_stdin",
        "sh_custom",
        "sh_carg",
        "sh_cstdin",
        "sh_miss",
        "sz_plain",
        "sz_ctl",
        "sz_tnr",
        "sz_fmt",
        "sz_esc",
        "gs_https_host",
        "gs_https_path",
        "gs_https_ref",
        "gs_https_pin",
        "gs_ssh_host",
        "gs_ssh_path",
        "gs_ssh_pin",
        "gs_short_host",
        "gs_short_path",
        "gs_bare",
        "gs_dotdot",
        "gs_abs",
        "ua_ver",
        "ua_paren",
        "ua_semi",
        "cl_n",
        "cl_first",
        "cl_hdr",
        "cl_second",
        "cl_miss",
        "ex_on",
        "ex_empty",
        "ex_zero",
        "ex_true",
        "ex_nil",
    ),
    "cli_interactive_controller": (
        "amp",
        "lt",
        "gt",
        "quot",
        "apos",
        "hash65",
        "miss",
        "wl_disp",
        "wl_type",
        "wl_x11",
        "wl_none",
        "cf_home",
        "cf_proj",
        "cf_out",
        "cf_slash",
        "al_oauth",
        "al_key",
        "pat_valid",
        "pat_empty_left",
        "pat_empty_right",
        "pat_nil",
        "pat_double",
        "pat_fixed",
        "rts_auto_light",
        "rts_auto_dark",
        "rts_fixed",
        "rts_bad",
        "rts_nil",
    ),
    "cli_selectors": (
        "ss_empty",
        "ss_hit",
        "ss_miss",
        "ss_re",
        "ss_badre",
        "ss_named",
        "kt_ctrl",
        "kt_slash",
        "kt_shift",
        "kt_cap",
        "kt_empty",
        "ff_empty",
        "ff_an",
        "ff_app",
        "ff_cl",
        "ff_slash",
        "dq_empty",
        "dq_a",
        "dq_abc",
        "dq_cafe",
        "dq_emoji",
        "dq_combining",
        "vs0",
        "vs0_end",
        "vs0_vis",
        "vs5",
        "vs5_vis",
        "vs20_mid",
        "vs20_mid_vis",
        "vs20_top",
        "vs20_bot",
        "vs20_bot_vis",
        "vs3_vis",
        "mi_empty",
        "mi_wrap_up",
        "mi_wrap_dn",
        "mi_fwd",
        "mi_back",
        "mi_big",
        "alr_wide",
        "alr_trunc_left",
        "alr_trunc_right",
        "alr_narrow",
        "alr_empty_left",
        "alr_empty_right",
        "fl_short",
        "fl_trunc",
        "fl_pad",
        "fl_ellipsis",
        "fl_wide",
        "fl_empty",
        "bl_w40",
        "bl_w40_acc",
        "bl_w1",
        "bl_w80",
        "bl_w10_acc",
        "bl_w20",
        "sl_short",
        "sl_trunc",
        "sl_wide",
        "sl_empty",
        "sl_pad20",
        "sl_narrow",
        "ml_short",
        "ml_trunc",
        "ml_wide",
        "ml_empty",
        "ml_item20",
        "ml_narrow",
        "dl_short",
        "dl_trunc",
        "dl_wide",
        "dl_empty",
        "dl_item20",
        "dl_narrow",
        "mck_up",
        "mck_shift_dn",
        "mck_ctrl_rt",
        "mck_alt_lt",
        "mck_ctrl_shift_up",
        "mck_super_dn",
        "tl_short",
        "tl_trunc",
        "tl_empty",
        "tl_wide",
        "tl_narrow",
        "tl_normal",
        "otl_short",
        "otl_trunc",
        "otl_empty",
        "otl_wide",
        "otl_narrow",
        "otl_normal",
        "il_empty",
        "il_short",
        "il_ab12",
        "il_grapheme",
        "il_narrow",
        "il_scroll",
        "kbt_confirm",
        "kbt_cancel",
        "kbt_left",
        "kbt_empty",
        "kbt_custom_confirm",
        "kbt_custom_cancel",
        "kbh_confirm",
        "kbh_cancel",
        "kbh_left",
        "kbh_empty",
        "kbh_custom_save",
        "kbh_custom_cancel",
        "sfa_now",
        "sfa_sec",
        "sfa_min",
        "sfa_hour",
        "sfa_day",
        "sfa_week",
        "srl_named",
        "srl_first",
        "srl_empty",
        "srl_ctrl",
        "srl_name_ctrl",
        "ssp_home",
        "ssp_prefix",
        "ssp_abs",
        "ssp_proj",
        "ssp_empty",
        "sqs_cadr",
        "sqs_phrase",
        "sqs_miss",
        "sqs_other_miss",
        "sqs_name",
        "sqs_other_hit",
        "str_count",
        "str_depths",
        "str_ids",
        "sbl_confirm",
        "sbl_delete",
        "sbl_noninvasive",
        "sbl_fallback",
        "sbl_custom",
        "ssp_same",
        "ssp_diff",
        "ssp_nil_left",
        "ssp_nil_right",
        "ssp_nil_both",
        "sqp_phrase",
        "sqp_words",
        "sqp_plain",
        "sqp_empty",
        "sqp_one",
        "sqp_open",
        "snp_named",
        "snp_whitespace",
        "snp_empty",
        "snp_nil",
        "std_off",
        "std_minimal",
        "std_low",
        "std_medium",
        "std_high",
        "std_xhigh",
        "std_max",
        "std_unknown",
        "sdv_true",
        "sdv_false",
        "sdv_symbol",
        "sdv_int",
        "sdv_string",
        "sats_solarized",
        "sats_same",
        "sats_light_dark",
        "saat_light_term",
        "saat_dark_term",
        "saat_light_pair",
        "ssc_true",
        "ssc_transport",
        "ssc_wrap",
        "ssc_missing",
        "sap_empty",
        "sap_trans",
        "sap_none",
        "sap_app",
        "tef_user_def",
        "tef_label_def",
        "tef_user_uo",
        "tef_tool_nt",
        "tef_labeled_lo",
        "tef_all_label",
        "tqm_hit",
        "tqm_miss",
        "tqm_multi",
        "tqm_partial",
        "tqm_empty",
        "tese_sparse",
        "tese_label",
        "tese_empty",
        "tese_full",
        "tese_text",
        "tsep_label",
        "tsep_user",
        "tsep_custom",
        "tsep_model",
        "tsep_think",
        "tsep_session",
        "tnd_hello",
        "tnd_spaced",
        "tnd_newline",
        "tnd_empty",
        "tnd_ws",
        "tsl_empty",
        "tsl_notools",
        "tsl_user",
        "tsl_labeled",
        "tsl_all",
        "tsl_time",
        "tsl_both",
        "tsp_home",
        "tsp_prefix",
        "tsp_abs",
        "tsp_proj",
        "tsp_empty",
        "tfp_root",
        "tfp_leaf",
        "tfp_only_child",
        "tfp_branch",
        "tta_path",
        "tta_file",
        "tta_prio",
        "tta_miss",
        "tta_nil",
        "tcf_def_fwd",
        "tcf_nt_back",
        "tcf_all_fwd",
        "tcf_user_fwd",
        "09:07",
        "3/28 14:32",
        "25/12/31 23:59",
        "07:30",
        "tvn_single",
        "tvn_branch",
        "tvn_multi",
        "tvn_chain",
        "tvn_deep",
        "thv_short",
        "thv_scroll",
        "thv_narrow",
        "thv_noselect",
        "thv_ansi",
        "thk_move",
        "thk_page",
        "thk_branch",
        "thk_copy",
        "thk_filters",
        "thk_cycle",
        "thk_custom",
        "thl_w80",
        "thl_w50",
        "thl_w30",
        "thl_w20",
        "thl_w12",
        "tap_leaf",
        "tap_mid",
        "tap_root",
        "tap_nil",
        "tap_missing",
        "tnvi_hit",
        "tnvi_ancestor",
        "tnvi_branch",
        "tnvi_fallback",
        "tnvi_missing",
        "tnvi_nil",
        "tpa_leaf_a",
        "tpa_leaf_b",
        "tpa_root",
        "tpa_nil",
        "pto_child",
        "pto_single",
        "tss_child_trust",
        "tss_child_parent",
        "tss_child_distrust",
        "tss_single_trust",
        "tss_single_distrust",
        "tdd_none",
        "tdd_child_local",
        "tdd_child_inherited",
        "tdd_single_untrusted",
        "tsm_child_down",
        "tsm_child_up",
        "tsm_child_wrap_up",
        "tsm_child_wrap_down",
        "tsm_child_page",
        "tsm_single_down",
        "tsm_single_wrap",
        "tshe_child_down",
        "tshe_child_up",
        "tshe_child_enter",
        "tshe_child_k",
        "tshe_child_bad",
        "tshe_child_esc",
        "tshe_child_nop",
        "tshri_child_down",
        "tshri_child_k",
        "tshri_child_enter",
        "tshri_child_esc",
        "tshri_child_bad",
        "tshri_child_j",
        "tshri_child_confirm",
        "rts_child_default",
        "rts_child_saved",
        "rts_child_inherited",
        "rts_child_distrust",
        "rts_single",
        "oosl_none",
        "oosl_api_mismatch",
        "oosl_oauth_mismatch",
        "oosl_oauth_configured",
        "oosl_stored",
        "oosl_env",
        "oosl_custom",
        "oosr_none",
        "oosr_api_mismatch",
        "oosr_oauth_mismatch",
        "oosr_oauth_configured",
        "oosr_stored",
        "oosr_env",
        "oosr_custom",
        "ceat_oauth",
        "ceat_api_key",
        "ceat_api_key_hyphen",
        "ceat_oauth_sym",
        "ceat_api_key_sym",
        "ceat_oauth_mixed",
        "ceat_api_key_upper",
        "oesp_nil",
        "oesp_oauth",
        "oesp_single_env",
        "oesp_multi_env",
        "oesp_runtime",
        "oesp_stored",
        "oesp_lower",
        "oss_first",
        "oss_second",
        "oss_third",
        "oss_filter_hit",
        "oss_filter_miss",
        "osaf_all",
        "osaf_open",
        "osaf_miss",
        "osaf_anth",
        "osaf_google",
        "oshe_down",
        "oshe_up",
        "oshe_enter",
        "oshe_esc",
        "oshe_text",
        "oshe_backspace",
        "oshri_down",
        "oshri_j",
        "oshri_enter",
        "oshri_esc",
        "oshri_bad",
        "oshri_o",
        "oshri_confirm",
        "osst_oauth",
        "osst_api",
        "osst_no_method",
        "osst_api_plain",
        "latr_none",
        "latr_oauth",
        "latr_api",
        "latr_both",
        "latr_generic",
        "lpo_all",
        "lpo_oauth",
        "lpo_api",
        "lpo_labeled",
        "lpo_status",
        "lgo_empty",
        "lgo_mixed",
        "lgo_unknown",
        "lgo_sorted",
        "lmhe_down",
        "lmhe_up",
        "lmhe_enter_oauth",
        "lmhe_enter_api",
        "lmhe_esc",
        "lmhe_clear",
        "lmhe_interrupt",
        "osmv_0_1",
        "osmv_2_m1",
        "osmv_1_1",
        "osmv_1_m1",
        "osmv_filter",
        "akhe_esc",
        "akhe_clear",
        "akhe_text",
        "akhe_bs",
        "akhe_enter_empty",
        "akhe_enter_key",
        "akhe_interrupt",
        "lmsui_default",
        "lmsui_sel1",
        "lmsui_title",
        "lmsui_narrow",
        "lmsui_mid",
        "akiui_empty",
        "akiui_key",
        "akiui_openai",
        "akiui_narrow",
        "akiui_long",
        "osui_default",
        "osui_sel2",
        "osui_filter",
        "osui_miss",
        "osui_logout_empty",
        "msst_openai",
        "msst_anthropic",
        "msst_codex",
        "msst_openrouter",
        "msst_google",
        "qmid_openai",
        "qmid_anthropic",
        "qmid_codex",
        "qmid_openrouter",
        "qmid_google",
        "msaf_all",
        "msaf_gpt",
        "msaf_miss",
        "msaf_anth",
        "msaf_google",
        "msmv_0_1",
        "msmv_2_m1",
        "msmv_1_1",
        "msmv_1_m1",
        "msmv_filter",
        "mshe_down",
        "mshe_up",
        "mshe_enter",
        "mshe_esc",
        "mshe_text",
        "mshe_bs",
        "mshri_down",
        "mshri_j",
        "mshri_esc",
        "mshri_bad",
        "mshri_o",
        "mshri_confirm",
        "mshri_up",
        "mssq_clear",
        "mssq_gpt",
        "mssq_same",
        "mssq_reset",
        "mssq_miss",
        "mssm_0",
        "mssm_1",
        "mssm_3",
        "mssm_gpt0",
        "mssm_gpt2",
        "mssm_miss",
        "mssm_oob",
        "msts_all",
        "msts_scoped",
        "msts_gpt",
        "msts_none",
        "msts_anth",
        "msui_default",
        "msui_sel2",
        "msui_scoped",
        "msui_filter",
        "msui_miss",
        "msui_error",
        "msui_refresh",
        "smssq_clear",
        "smssq_gpt",
        "smssq_same",
        "smssq_reset",
        "smssq_miss",
        "smsmv_0_1",
        "smsmv_2_m1",
        "smsmv_1_1",
        "smsmv_1_m1",
        "smsmv_filter",
        "smshe_down",
        "smshe_up",
        "smshe_enter",
        "smshe_esc",
        "smshe_text",
        "smshe_bs",
        "smsri_down",
        "smsri_j",
        "smsri_esc",
        "smsri_bad",
        "smsri_o",
        "smsri_confirm",
        "smsri_up",
        "smsui_default",
        "smsui_sel2",
        "smsui_partial",
        "smsui_filter",
        "smsui_miss",
        "smsui_refresh",
        "smsui_dirty",
        "smssi_all",
        "smssi_partial",
        "smssi_single",
        "smssi_empty",
        "smssi_reorder",
        "smstg_all_0",
        "smstg_partial_off",
        "smstg_partial_on",
        "smstg_retoggle",
        "smstg_filter",
        "smstg_miss",
        "smsti_all",
        "smsti_gpt",
        "smsti_nope",
        "smsti_claude",
        "smsti_partial",
        "smsea_all",
        "smsea_partial",
        "smsea_empty",
        "smsea_two",
        "smsea_filter",
        "smsea_miss",
        "smstgp_all_0",
        "smstgp_partial_off",
        "smstgp_partial_on",
        "smstgp_retoggle",
        "smstgp_filter",
        "smstgp_miss",
        "smsca_all",
        "smsca_partial",
        "smsca_empty",
        "smsca_two",
        "smsca_filter",
        "smsca_miss",
        "smsror_down",
        "smsror_up",
        "smsror_noop",
        "smsror_empty",
        "smsror_filter",
        "smsror_miss",
        "smsper_all",
        "smsper_partial",
        "smsper_no_cb",
        "smsper_empty",
        "smsper_two",
        "smsper_single",
        "smsprv_all",
        "smsprv_partial",
        "smsprv_unavail",
        "smsprv_empty",
        "smsprv_single",
    ),
    "websocket_stream": (
        "ws_text",
        "stop_reason",
        "text_characters",
        "usage_input",
        "usage_output",
    ),
    "cli_sdk": (
        "beta",
        "eq",
        "older",
        "newer_flag",
        "equal_flag",
        "cm_tok",
        "cm_idle",
        "cm_chg",
        "cm_hit",
        "sw_tok",
        "sw_idle",
        "sw_chg",
        "sw_hit",
        "healthy_hit",
        "empty_hit",
        "cw_tok",
        "cw_n",
        "cw_healthy",
        "cw_reset",
        "cw_sw_tok",
        "cw_sw_n",
        "cw_nocache",
        "tl_off",
        "tl_min",
        "tl_low",
        "tl_med",
        "tl_high",
        "tl_xhigh",
        "tl_max",
        "tl_miss",
        "sl_n",
        "sl_id",
        "sl_empty",
        "as_ok",
        "as_model",
        "as_fb",
        "ss_ok",
        "ss_cwd",
        "ss_snap",
        "mr_oa",
        "mr_an",
        "mr_missp",
        "mr_gpt",
        "mr_missm",
    ),
    "provider_registry_defs": (
        "openai",
        "anthropic",
        "google",
        "unknown",
        "count",
        "sorted_digest",
        "me_oa",
        "me_gemini",
        "me_azure",
        "me_miss",
        "rm_openai",
        "rm_anthropic",
        "rm_google",
        "rm_unknown",
        "sl_openai",
        "sl_anthropic",
        "sl_google",
        "sl_bedrock",
        "sl_vertex",
    ),
    "skill_prompt_load": (
        "custom_len",
        "append_len",
        "ctx_len",
        "has_cwd",
        "has_extra",
        "has_agents",
    ),
    "cli_bootstrap_sessions": (
        "count",
        "baseline",
        "snippet_count",
        "read_first",
        "option_count",
        "auth_pairs_digest",
        "vertex_structured",
        "bedrock_structured",
    ),
    "ai_runtime_faux": (
        "text_len",
        "text",
        "think_len",
        "think",
    ),
    "http_transport": (
        "https_scheme",
        "https_host",
        "https_path",
        "http_scheme",
        "http_host",
        "http_port",
        "http_path",
    ),
    "core_rest": (
        "ca_live",
        "ca_abort",
        "ca_clear",
        "ca_pred",
        "rd_keep",
        "rd_secret",
        "rd_token",
        "rd_mark",
        "th_absent",
        "th_current",
        "th_joined",
    ),
    "resource_loader": (
        "skill_count",
        "prompt_count",
        "skill_names",
        "prompt_names",
        "skill_from_project",
        "prompt_from_project",
        "context_file_count",
        "system_prompt",
        "dbn_skill_count",
        "dbn_skill_collisions",
        "dbn_skill_project",
        "dbn_prompt_count",
        "dbn_prompt_collisions",
        "dbn_prompt_project",
    ),
    "session_pipeline": (
        "entry_count",
        "leaf_id",
        "session_id",
        "session_name",
        "context_entry_count",
        "context_message_count",
        "context_thinking_level",
        "context_model",
    ),
    "storage_journal": (
        "read_file_entry_count",
        "append_entry_count",
        "session_entry_count",
        "written_file_entry_count",
    ),
    "sqlite_session": (
        "entry_count",
        "leaf_id",
        "ingested_entry_count",
        "session_id",
        "source_leaf_id",
    ),
    "tool_read": (
        "line_count",
        "output_chars",
        "truncated",
    ),
    "tool_grep": (
        "match_limit",
        "output_chars",
        "truncated",
    ),
    "agent_tool_loop": (
        "final_text",
        "message_count",
        "tool_error",
        "tool_value",
        "tp_rel",
        "tp_abs",
        "tp_at",
        "tp_nbsp",
        "tp_parent",
        "le_lf",
        "le_crlf",
        "le_none",
        "le_empty",
        "trd_short",
        "trd_exact",
        "trd_over",
        "trd_over_one",
        "trd_utf16",
        "trd_empty",
        "rt_steer_len", "rt_follow_len", "rt_drain_steer_a", "rt_drain_steer1_n",
        "rt_steer_remain1", "rt_drain_steer_b", "rt_steer_empty", "rt_drain_steer_all_n",
        "rt_drain_follow_c", "rt_follow_remain1", "rt_drain_follow_d", "rt_follow_empty",
        "rt_clear_steer_n", "rt_clear_follow_n", "rt_snap_steer_empty", "rt_snap_follow_empty",
    ),
    "session_compact": (
        "compacted",
        "first_kept",
        "summary_chars",
        "summarized",
        "entry_count",
        "branch_summary_chars",
        "prepared",
        "message_count",
        "total_tokens",
        "read_file_count",
        "modified_file_count",
    ),
}

# Divergences the pairing found that are real cadr-vs-pi gaps rather than
# measurement artefacts.  Recording the exact pair of values keeps them
# visible and fails the gate when either side moves, instead of dropping the
# comparison.  docs/acceptance/goal-v20-part-h.md explains each one.
KNOWN_EVENT_KIND_DIVERGENCES = {
    # pi emits a toolcall_delta for the opening tool-call chunk even though it
    # carries an empty argument fragment; cadr suppresses the empty delta.
    "toolcall_delta": {"pi": 6, "cadr": 5},
}

# pi tags the messages it synthesises from compaction and custom entries with
# their own roles; cadr materialises both as user messages
# (session-messages in src/cadr-agent/session/journal.lisp).  Folding pi's
# spellings compares the message stream rather than the tagging.
PI_ROLE_FOLD = {"compactionSummary": "user", "custom": "user"}

# cadr's help text is the pi text with the product-identity renames applied,
# so character counts cannot be equal; they can still be bounded.
HELP_CHARACTER_TOLERANCE = 0.02

# cadr's session codec writes a few fields differently from pi's (see the
# acceptance doc), which makes its journal slightly larger for the same
# entries.  Bound the excess instead of blessing an exact byte count.
JOURNAL_BYTE_TOLERANCE = 1.05

JOURNAL_VOLATILE_KEYS = ("id", "parentId", "timestamp")

# Structural journal differences the write pair found, as JSON paths within a
# message entry.  Same policy as the event-kind record above.
KNOWN_JOURNAL_KEY_DIVERGENCES = {
    "message.content[].redacted",
    "message.details",
    "message.stopReason",
    "message.usage.cost.cacheRead",
    "message.usage.cost.cacheWrite",
    "message.usage.cost.input",
    "message.usage.cost.output",
    "message.usage.cost.total",
    "message.usage.total",
    "message.usage.totalTokens",
}


def load_goal11_gate():
    """Import the goal11 gate for its same_machine rule."""
    path = PROJECT_DIRECTORY / "scripts/goal11-performance-gate.py"
    spec = importlib.util.spec_from_file_location("goal11_performance_gate", path)
    if spec is None or spec.loader is None:
        raise ValueError(f"cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_json(path: str) -> dict:
    with Path(path).open(encoding="utf-8") as stream:
        return json.load(stream)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def check(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def paired_limit_us(pi_median: float, pi_mad: float, cadr_mad: float, ceiling: float) -> float:
    """Allowed cadr median for one metric.

    Same shape as goal11-performance-gate.py's baseline_limit_us -- a ratio
    term plus a run-MAD term plus an absolute floor -- with the floor scaled
    from that gate's 5000us down to MICROSECOND_FLOOR_US, because these pairs
    include operations three orders of magnitude smaller than a frame.
    """
    return max(
        ceiling * pi_median,
        pi_median + max(MICROSECOND_FLOOR_US, 6 * max(pi_mad, cadr_mad)),
    )


def check_provenance(cadr: dict, pi: dict, failures: list[str]) -> None:
    check(cadr["schema_version"] == 1, "cadr report schema_version is not 1", failures)
    check(pi["schema_version"] == 1, "pi report schema_version is not 1", failures)
    check(cadr["kind"] == CADR_KIND, f"cadr report kind is {cadr['kind']!r}", failures)
    check(pi["kind"] == PI_KIND, f"pi report kind is {pi['kind']!r}", failures)
    check(
        pi["provenance"]["source_revision"] == EXPECTED_PI_REVISION,
        "pi report was not produced from the pinned baseline revision",
        failures,
    )

    # Same fixture bytes is the whole premise of a pair, so it is checked
    # against the files on disk rather than taken from either report.
    disk = {name: file_sha256(FIXTURE_DIRECTORY / name) for name in FIXTURE_NAMES}
    for label, report in (("cadr", cadr), ("pi", pi)):
        digests = report["provenance"]["fixture_sha256"]
        check(
            digests == disk,
            f"{label} report fixture digests differ from the checked-in fixtures",
            failures,
        )
    check(
        cadr["provenance"]["staged_agent_dir_sha256"]
        == pi["provenance"]["staged_agent_dir_sha256"],
        "the two sides staged different models.json/auth.json bytes",
        failures,
    )


def check_parameters(cadr: dict, pi: dict, failures: list[str]) -> None:
    for field in ("repetitions", "samples", "warmups", "quick", "journal_append_entry_count"):
        check(
            cadr["parameters"][field] == pi["parameters"][field],
            f"parameter {field} differs between the two reports",
            failures,
        )
    for label, report in (("cadr", cadr), ("pi", pi)):
        samples = report["parameters"]["samples"]
        for group, names in METRICS.items():
            for name in names:
                metric = report["metrics"][group][name]
                check(
                    len(metric["samples_us"]) == samples,
                    f"{label} {group}.{name} does not carry {samples} samples",
                    failures,
                )
                check(
                    metric["repetitions"] == report["parameters"]["repetitions"][f"{group}.{name}"],
                    f"{label} {group}.{name} repetition count disagrees with the declared table",
                    failures,
                )


def fold_pi_roles(roles: dict) -> dict:
    folded: dict[str, int] = {}
    for role, count in roles.items():
        key = PI_ROLE_FOLD.get(role, role)
        folded[key] = folded.get(key, 0) + count
    return dict(sorted(folded.items()))


def check_observed(cadr: dict, pi: dict, failures: list[str]) -> list[str]:
    notes: list[str] = []
    for group, keys in OBSERVED_EXACT.items():
        cadr_observed = cadr["metrics"][group]["observed"]
        pi_observed = pi["metrics"][group]["observed"]
        for key in keys:
            check(
                cadr_observed[key] == pi_observed[key],
                f"{group}.{key} differs: pi={pi_observed[key]!r} cadr={cadr_observed[key]!r}",
                failures,
            )

    cadr_kinds = cadr["metrics"]["provider_stream"]["observed"]["event_kind_counts"]
    pi_kinds = pi["metrics"]["provider_stream"]["observed"]["event_kind_counts"]
    check(
        sorted(cadr_kinds) == sorted(pi_kinds),
        "provider_stream event kinds differ between the two sides",
        failures,
    )
    for kind in sorted(set(cadr_kinds) | set(pi_kinds)):
        recorded = KNOWN_EVENT_KIND_DIVERGENCES.get(kind)
        pi_count = pi_kinds.get(kind)
        cadr_count = cadr_kinds.get(kind)
        if recorded is None:
            check(
                pi_count == cadr_count,
                f"provider_stream event kind {kind} differs: pi={pi_count} cadr={cadr_count}",
                failures,
            )
            continue
        check(
            (pi_count, cadr_count) == (recorded["pi"], recorded["cadr"]),
            f"recorded {kind} divergence moved: expected pi={recorded['pi']} "
            f"cadr={recorded['cadr']}, got pi={pi_count} cadr={cadr_count}",
            failures,
        )
        notes.append(f"known_divergence:event_kind:{kind}=pi{pi_count}/cadr{cadr_count}")

    cadr_roles = cadr["metrics"]["session_pipeline"]["observed"]["context_message_roles"]
    pi_roles = fold_pi_roles(pi["metrics"]["session_pipeline"]["observed"]["context_message_roles"])
    check(
        cadr_roles == pi_roles,
        f"context message roles differ after folding pi's synthetic roles: "
        f"pi={pi_roles!r} cadr={cadr_roles!r}",
        failures,
    )

    cadr_help = cadr["metrics"]["cli_dispatch"]["observed"]["help_characters"]
    pi_help = pi["metrics"]["cli_dispatch"]["observed"]["help_characters"]
    check(
        abs(cadr_help - pi_help) <= HELP_CHARACTER_TOLERANCE * pi_help,
        f"help text size gap exceeds {HELP_CHARACTER_TOLERANCE:.0%}: "
        f"pi={pi_help} cadr={cadr_help}",
        failures,
    )
    notes.append(f"help_characters=pi{pi_help}/cadr{cadr_help}")

    cadr_journal = cadr["metrics"]["storage_journal"]["observed"]
    pi_journal = pi["metrics"]["storage_journal"]["observed"]
    check(
        cadr_journal["journal_cwd"].rstrip("/") == pi_journal["journal_cwd"].rstrip("/"),
        "the two sides wrote journals for different working directories",
        failures,
    )
    for field in ("written_bytes", "written_body_bytes"):
        check(
            cadr_journal[field] <= JOURNAL_BYTE_TOLERANCE * pi_journal[field],
            f"cadr {field} exceeds {JOURNAL_BYTE_TOLERANCE:.2f}x pi: "
            f"pi={pi_journal[field]} cadr={cadr_journal[field]}",
            failures,
        )
    notes.append(
        "journal_body_bytes=pi{}/cadr{} ({:+.1%})".format(
            pi_journal["written_body_bytes"],
            cadr_journal["written_body_bytes"],
            cadr_journal["written_body_bytes"] / pi_journal["written_body_bytes"] - 1,
        )
    )
    return notes


def flatten_journal_entry(entry, prefix: str = "", leaves: dict | None = None) -> dict:
    """Map an entry to {json path: sorted scalar values}.

    Only leaves are recorded, so a single differing field does not also
    implicate every object above it.  List position is dropped: the two
    writers agree on content-block order, and comparing multisets keeps the
    report readable when they would not.
    """
    if leaves is None:
        leaves = {}
    if isinstance(entry, dict):
        for key, value in entry.items():
            flatten_journal_entry(value, f"{prefix}.{key}" if prefix else key, leaves)
    elif isinstance(entry, list):
        for value in entry:
            flatten_journal_entry(value, f"{prefix}[]", leaves)
    else:
        leaves.setdefault(prefix, []).append(json.dumps(entry, ensure_ascii=False))
    return leaves


def differing_journal_keys(pi_entries: list[dict], cadr_entries: list[dict]) -> set[str]:
    """JSON paths that differ between two written journals.

    Entry ids and wall-clock timestamps are dropped first: both sides mint
    those per run, so they carry no parity signal.
    """
    differing: set[str] = set()
    for pi_entry, cadr_entry in zip(pi_entries, cadr_entries):
        stripped = []
        for entry in (pi_entry, cadr_entry):
            copy = dict(entry)
            for key in JOURNAL_VOLATILE_KEYS:
                copy.pop(key, None)
            stripped.append(flatten_journal_entry(copy))
        pi_leaves, cadr_leaves = stripped
        for path in set(pi_leaves) | set(cadr_leaves):
            if sorted(pi_leaves.get(path, [])) != sorted(cadr_leaves.get(path, [])):
                differing.add(path)
    return differing


def check_journals(pi_path: str, cadr_path: str, failures: list[str]) -> list[str]:
    pi_entries = [json.loads(line) for line in Path(pi_path).read_text(encoding="utf-8").splitlines()]
    cadr_entries = [
        json.loads(line) for line in Path(cadr_path).read_text(encoding="utf-8").splitlines()
    ]
    check(
        len(pi_entries) == len(cadr_entries),
        f"written journals have different entry counts: "
        f"pi={len(pi_entries)} cadr={len(cadr_entries)}",
        failures,
    )
    # The header line carries the cwd spelling and the creation timestamp,
    # which the observed checks already cover.
    differing = differing_journal_keys(pi_entries[1:], cadr_entries[1:])
    unexpected = sorted(differing - KNOWN_JOURNAL_KEY_DIVERGENCES)
    resolved = sorted(KNOWN_JOURNAL_KEY_DIVERGENCES - differing)
    check(
        not unexpected,
        f"written journals diverge on unrecorded keys: {unexpected}",
        failures,
    )
    check(
        not resolved,
        f"recorded journal divergences no longer reproduce (update the record): {resolved}",
        failures,
    )
    return [f"journal_key_divergences={len(differing)}"]


def parse_only_enforce(values: list[str]) -> frozenset[str] | None:
    if not values:
        return None
    keys: set[str] = set()
    for value in values:
        for key in value.split(","):
            key = key.strip()
            if key:
                keys.add(key)
    unknown = sorted(keys - set(RATIO_CEILINGS))
    if unknown:
        raise ValueError(f"--only-enforce unknown metrics: {unknown}")
    return frozenset(keys)


def check_ratios(
    cadr: dict,
    pi: dict,
    enforced: bool,
    failures: list[str],
    only_enforce: frozenset[str] | None = None,
) -> list[str]:
    summary: list[str] = []
    for group, names in METRICS.items():
        for name in names:
            key = f"{group}.{name}"
            cadr_metric = cadr["metrics"][group][name]
            pi_metric = pi["metrics"][group][name]
            ratio = cadr_metric["median_us"] / max(1e-9, pi_metric["median_us"])
            ceiling = RATIO_CEILINGS[key]
            limit = paired_limit_us(
                pi_metric["median_us"], pi_metric["mad_us"], cadr_metric["mad_us"], ceiling
            )
            if enforced and (only_enforce is None or key in only_enforce):
                check(
                    cadr_metric["median_us"] <= limit,
                    f"{key} exceeds its recorded ceiling: cadr={cadr_metric['median_us']:.2f}us, "
                    f"limit={limit:.2f}us ({ratio:.2f}x pi, ceiling {ceiling:.2f}x)",
                    failures,
                )
            # Say which term actually bound the metric, so a ratio printed
            # above its ceiling on a tiny operation does not read as a
            # violation the gate let through.
            bound = "ratio" if ceiling * pi_metric["median_us"] >= limit else "variance"
            summary.append(f"{key}={ratio:.2f}x/{ceiling:.2f}x[{bound}]")
    return summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cadr", required=True, help="scripts/goal20-paired-paths.lisp report")
    parser.add_argument("--pi", required=True, help="scripts/goal20-paired-paths.mjs report")
    parser.add_argument("--cadr-journal", help="journal written by --keep-journal (cadr side)")
    parser.add_argument("--pi-journal", help="journal written by --keep-journal (pi side)")
    parser.add_argument("--summary-json", help="write the machine-readable summary here")
    parser.add_argument(
        "--only-enforce",
        action="append",
        default=[],
        metavar="GROUP.NAME",
        help="enforce ratio ceilings only for these metrics (repeatable; comma-separated ok)",
    )
    arguments = parser.parse_args()

    failures: list[str] = []
    notes: list[str] = []
    try:
        only_enforce = parse_only_enforce(arguments.only_enforce)
        goal11 = load_goal11_gate()
        cadr = load_json(arguments.cadr)
        pi = load_json(arguments.pi)
        check_provenance(cadr, pi, failures)
        check_parameters(cadr, pi, failures)
        notes += check_observed(cadr, pi, failures)

        host_match = goal11.same_machine(cadr, pi)
        quick = bool(cadr["parameters"]["quick"] or pi["parameters"]["quick"])
        enforced = host_match and not quick
        ratios = check_ratios(cadr, pi, enforced, failures, only_enforce)

        if bool(arguments.cadr_journal) != bool(arguments.pi_journal):
            raise ValueError("--cadr-journal and --pi-journal must be given together")
        if arguments.cadr_journal:
            notes += check_journals(arguments.pi_journal, arguments.cadr_journal, failures)
    except (KeyError, OSError, TypeError, ValueError, json.JSONDecodeError) as error:
        print(f"goal20 pair gate: invalid report: {error}", file=sys.stderr)
        return 2

    status = (
        f"enforced-only:{','.join(sorted(only_enforce))}"
        if enforced and only_enforce
        else (
            "enforced"
            if enforced
            else ("informational-quick-run" if quick else "informational-host-mismatch")
        )
    )
    summary = [
        f"same_machine={'yes' if host_match else 'no'}",
        f"ratio_gate={status}",
        f"cadr_host={cadr['machine']['machine_instance']}",
        f"pi_host={pi['machine']['hostname']}",
        f"samples={cadr['parameters']['samples']}",
    ]

    if arguments.summary_json:
        Path(arguments.summary_json).write_text(
            json.dumps(
                {
                    "same_machine": host_match,
                    "ratio_gate": status,
                    "only_enforce": sorted(only_enforce) if only_enforce else None,
                    "failures": failures,
                    "ratios": {
                        f"{group}.{name}": (
                            cadr["metrics"][group][name]["median_us"]
                            / max(1e-9, pi["metrics"][group][name]["median_us"])
                        )
                        for group, names in METRICS.items()
                        for name in names
                    },
                    "ceilings": RATIO_CEILINGS,
                    "notes": notes,
                },
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )

    if failures:
        for failure in failures:
            print(f"goal20 pair gate: FAIL: {failure}", file=sys.stderr)
        return 1

    print("goal20 pair gate: PASS")
    print("  run: " + ", ".join(summary))
    print("  ratios: " + ", ".join(ratios))
    if notes:
        print("  notes: " + ", ".join(notes))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
