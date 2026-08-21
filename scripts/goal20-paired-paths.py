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
    "cli_settings": ("create",),
    "resource_loader": ("reload",),
    "package_manager": ("resolve",),
    "session_discovery": ("header_probe",),
    "session_export_html": ("to_html",),
    "protocol_cbor": ("roundtrip",),
    "agent_schema": ("validate_ok_fail",),
    "harness_storage": ("open_walk",),
    "protocol_codec": ("roundtrip",),
    "agent_proxy": ("stream_roundtrip",),
    "oauth_pkce": ("challenge_urls",),
    "evals_harness": ("summarize",),
    "ai_crypto_model_data": ("manifest",),
    "cli_models_rest": ("pattern_match",),
    "image_runtime": ("dimensions",),
    "cli_print_rpc": ("jsonl_line",),
    "tui_latex": ("render",),
    "tui_editor_helpers": ("fuzzy_match",),
    "tui_theme_overlay": ("osc11_bg",),
    "ai_support": ("estimate_text",),
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
    "ai_capabilities": ("short_hash",),
    "session_pipeline": ("session_load", "context_walk"),
    "storage_journal": ("journal_read", "journal_append"),
    "sqlite_session": ("open_walk",),
    "tool_read": ("text_file",),
    "tool_grep": ("context_file",),
    "agent_tool_loop": ("roundtrip",),
    "session_compact": ("compact",),
    "text_truncation": ("truncate_head", "truncate_tail"),
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
    # Frozen from the first Friend-MachineD non-quick resource_loader
    # pair (samples=5): observed 0.29x (568 / 1978 µs). cadr leads.
    # 1.5 follows the list_models_registry / render_slicing precedent
    # (headroom above 1.0). Ratchet down only.
    "resource_loader.reload": 1.5,
    # Frozen from the first Friend-MachineD non-quick package_manager
    # pair (samples=5): observed 0.36x (200 / 551 us). cadr leads.
    # 1.5 follows the list_models_registry / render_slicing precedent.
    # Ratchet down only.
    "package_manager.resolve": 1.5,
    # Frozen from the first Friend-MachineD non-quick session_discovery
    # pair (samples=5): observed 2.05x (1450 / 709 us). 8.0 follows
    # the journal_read / tool_read headroom precedent. Ratchet down only.
    "session_discovery.header_probe": 8.0,
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
    # Frozen from the first Friend-MachineD non-quick evals_harness
    # pair (samples=5): observed 0.88x (8.0 / 9.0 us). cadr leads.
    # 1.5 follows the list_models_registry / render_slicing precedent.
    # Ratchet down only.
    "evals_harness.summarize": 1.5,
    # Frozen from the first Friend-MachineD non-quick
    # ai_crypto_model_data pair (samples=5): observed 8.97x
    # (77.3 / 8.6 us). 20.0 follows the session_compact /
    # truncate_head headroom precedent. Ratchet down only.
    "ai_crypto_model_data.manifest": 20.0,
    # Frozen from the first Friend-MachineD non-quick cli_models_rest
    # pair (samples=5): observed 1.65x (31.9 / 19.4 us). 3.0 follows
    # the argv_parse / tool_grep headroom precedent. Ratchet down only.
    "cli_models_rest.pattern_match": 3.0,
    # Frozen from the first Friend-MachineD non-quick image_runtime
    # pair (samples=5): observed 5.44x (7.8 / 1.4 us). 8.0 follows
    # the tool_read / journal_read headroom precedent. Ratchet down only.
    "image_runtime.dimensions": 8.0,
    # Frozen from the first Friend-MachineD non-quick cli_print_rpc
    # pair (samples=5): observed 13.21x (3.3 / 0.25 us). 8.0 follows
    # the microsecond-floor / agent_proxy variance precedent (not
    # the ratio). Ratchet down only.
    "cli_print_rpc.jsonl_line": 8.0,
    # Frozen from the first Friend-MachineD non-quick tui_latex pair
    # (samples=5): observed 2.49x (64.4 / 25.8 us). 3.0 follows the
    # argv_parse / tool_grep headroom precedent. Ratchet down only.
    "tui_latex.render": 3.0,
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
    "session_pipeline.session_load": 9.0,
    "session_pipeline.context_walk": 2.0,
    "storage_journal.journal_read": 8.0,
    "storage_journal.journal_append": 12.0,
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
    # Frozen from the first Friend-MachineD non-quick session_compact
    # pair (samples=5): observed 11.33x (965 / 85 µs). 20.0 follows
    # the truncate_head headroom precedent. Ratchet down only.
    "session_compact.compact": 20.0,
    # Initial values frozen from the first full measurement (2026-08-15,
    # Friend-MachineD, samples=5): head 16.71x, tail 15.27x.  These record
    # that cadr currently LOSES to pi on truncation (whole-content encode +
    # per-line passes vs Buffer.byteLength); Part O owns pulling them down.
    # Ratchet down only.
    "text_truncation.truncate_head": 20.0,
    "text_truncation.truncate_tail": 18.0,
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
    ),
    "package_manager": (
        "package_count",
        "skill_count",
        "prompt_count",
        "theme_count",
        "extension_count",
    ),
    "session_discovery": (
        "file_count",
        "header_count",
        "found",
        "session_id",
        "most_recent_name",
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
    "evals_harness": (
        "eval_sets",
        "comparisons",
        "candidate_wins",
        "ties",
    ),
    "ai_crypto_model_data": (
        "schema_version",
        "structure_hash",
        "generated_at",
        "file_count",
        "openai_json_hash",
        "anthropic_json_hash",
    ),
    "cli_models_rest": (
        "exact_id",
        "exact_provider",
        "bare_id",
        "partial_id",
        "scoped_id",
        "scoped_thinking",
        "miss",
    ),
    "image_runtime": (
        "png_width",
        "png_height",
        "gif_width",
        "gif_height",
        "miss",
    ),
    "cli_print_rpc": (
        "line_chars",
        "newline",
        "payload",
    ),
    "tui_latex": (
        "e_mc2",
        "frac_inline",
        "greek",
        "frac_display_newlines",
        "unknown_miss",
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
    ),
    "session_compact": (
        "compacted",
        "first_kept",
        "summary_chars",
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


def check_ratios(cadr: dict, pi: dict, enforced: bool, failures: list[str]) -> list[str]:
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
            if enforced:
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
    arguments = parser.parse_args()

    failures: list[str] = []
    notes: list[str] = []
    try:
        goal11 = load_goal11_gate()
        cadr = load_json(arguments.cadr)
        pi = load_json(arguments.pi)
        check_provenance(cadr, pi, failures)
        check_parameters(cadr, pi, failures)
        notes += check_observed(cadr, pi, failures)

        host_match = goal11.same_machine(cadr, pi)
        quick = bool(cadr["parameters"]["quick"] or pi["parameters"]["quick"])
        enforced = host_match and not quick
        ratios = check_ratios(cadr, pi, enforced, failures)

        if bool(arguments.cadr_journal) != bool(arguments.pi_journal):
            raise ValueError("--cadr-journal and --pi-journal must be given together")
        if arguments.cadr_journal:
            notes += check_journals(arguments.pi_journal, arguments.cadr_journal, failures)
    except (KeyError, OSError, TypeError, ValueError, json.JSONDecodeError) as error:
        print(f"goal20 pair gate: invalid report: {error}", file=sys.stderr)
        return 2

    status = (
        "enforced"
        if enforced
        else ("informational-quick-run" if quick else "informational-host-mismatch")
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
