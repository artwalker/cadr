#!/usr/bin/env python3
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_script(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(
        name, ROOT / "scripts" / filename
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ANCHOR = load_script("write_test_check_anchor", "write-test-check-anchor.py")
RECORD = load_script("record_paired_paths", "record-paired-paths.py")
LEDGER = load_script("write_performance_ledger", "write-performance-ledger.py")
HISTORY = load_script(
    "record_performance_history", "record-performance-history.py"
)


def run_main(module, argv: list[str]) -> int:
    import sys

    old = sys.argv
    try:
        sys.argv = argv
        return module.main()
    finally:
        sys.argv = old

SUMMARY = (
    "cadr test summary: systems=9 checks=17036 pass=17036 skip=0 fail=0"
)


def fake_cadr(*, quick: bool = True) -> dict:
    metrics: dict = {}
    for index, key in enumerate(RECORD.METRIC_KEYS):
        group, name = key.split(".", 1)
        metrics.setdefault(group, {})[name] = {
            "median_us": 1000.0 * (index + 1),
            "mad_us": 0.0,
        }
    return {
        "machine": {"machine_instance": "test-host"},
        "parameters": {"quick": quick, "samples": 1},
        "provenance": {
            "source_revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        },
        "metrics": metrics,
    }


def fake_summary(cadr: dict) -> dict:
    ratios = {}
    ceilings = {}
    for index, key in enumerate(RECORD.METRIC_KEYS):
        ratios[key] = 2.0 + index * 0.1
        ceilings[key] = 12.0
    return {
        "ceilings": ceilings,
        "failures": [],
        "notes": ["fixture-note"],
        "ratio_gate": "informational-quick-run",
        "ratios": ratios,
        "same_machine": True,
    }


class TestCheckAnchor(unittest.TestCase):
    def test_parse_summary_and_roundtrip_comment(self) -> None:
        fields = ANCHOR.parse_summary(SUMMARY)
        self.assertEqual(fields["systems"], 9)
        self.assertEqual(fields["checks"], 17036)
        self.assertEqual(fields["passed"], 17036)
        markdown = "# Title\n\nbody\n"
        updated = ANCHOR.apply_comment(markdown, fields)
        self.assertIn(ANCHOR.render_comment(fields), updated)
        self.assertEqual(ANCHOR.parse_comment(updated), fields)

    def test_strict_exits_one_on_drift_then_zero_when_stable(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            ledger = Path(temporary) / "test-matrix.md"
            ledger.write_text("# Title\n\nbody\n", encoding="utf-8")
            argv = [
                "write-test-check-anchor.py",
                "--summary",
                SUMMARY,
                "--ledger",
                str(ledger),
                "--strict",
            ]
            self.assertEqual(run_main(ANCHOR, argv), 1)
            self.assertEqual(run_main(ANCHOR, argv), 0)
            self.assertEqual(
                run_main(
                    ANCHOR,
                    [
                        "write-test-check-anchor.py",
                        "--verify",
                        "--summary",
                        SUMMARY,
                        "--ledger",
                        str(ledger),
                    ],
                ),
                0,
            )

    def test_refuses_implausible_check_drop(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            ledger = Path(temporary) / "test-matrix.md"
            ledger.write_text(
                "# Title\n\n"
                "<!-- GOAL20_TEST_CHECKS systems=9 checks=17036 pass=17036 skip=0 fail=0 -->\n",
                encoding="utf-8",
            )
            self.assertEqual(
                run_main(
                    ANCHOR,
                    [
                        "write-test-check-anchor.py",
                        "--summary",
                        "cadr test summary: systems=9 checks=27 pass=27 skip=0 fail=0",
                        "--ledger",
                        str(ledger),
                        "--strict",
                    ],
                ),
                2,
            )
            self.assertIn("17036", ledger.read_text(encoding="utf-8"))

    def test_verify_rejects_missing_comment(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            ledger = Path(temporary) / "test-matrix.md"
            ledger.write_text("# Title\n", encoding="utf-8")
            self.assertEqual(
                run_main(
                    ANCHOR,
                    [
                        "write-test-check-anchor.py",
                        "--verify",
                        "--ledger",
                        str(ledger),
                    ],
                ),
                2,
            )


class TestPairedPathRecord(unittest.TestCase):
    def test_sqlite_session_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("sqlite_session.open_walk", RECORD.METRIC_KEYS)
        self.assertIn("open_walk", paired.METRICS["sqlite_session"])
        self.assertIn("sqlite_session.open_walk", paired.RATIO_CEILINGS)
        self.assertIn("entry_count", paired.OBSERVED_EXACT["sqlite_session"])
        self.assertIn("leaf_id", paired.OBSERVED_EXACT["sqlite_session"])

    def test_tool_read_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("tool_read.text_file", RECORD.METRIC_KEYS)
        self.assertIn("text_file", paired.METRICS["tool_read"])
        self.assertIn("tool_read.text_file", paired.RATIO_CEILINGS)
        self.assertIn("line_count", paired.OBSERVED_EXACT["tool_read"])
        self.assertIn("output_chars", paired.OBSERVED_EXACT["tool_read"])
        self.assertIn("truncated", paired.OBSERVED_EXACT["tool_read"])

    def test_agent_tool_loop_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("agent_tool_loop.roundtrip", RECORD.METRIC_KEYS)
        self.assertIn("roundtrip", paired.METRICS["agent_tool_loop"])
        self.assertIn("agent_tool_loop.roundtrip", paired.RATIO_CEILINGS)
        self.assertIn("final_text", paired.OBSERVED_EXACT["agent_tool_loop"])
        self.assertIn("message_count", paired.OBSERVED_EXACT["agent_tool_loop"])
        self.assertIn("tool_error", paired.OBSERVED_EXACT["agent_tool_loop"])
        self.assertIn("tool_value", paired.OBSERVED_EXACT["agent_tool_loop"])

    def test_provider_anthropic_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("provider_anthropic.stream_roundtrip", RECORD.METRIC_KEYS)
        self.assertIn("stream_roundtrip", paired.METRICS["provider_anthropic"])
        self.assertIn("provider_anthropic.stream_roundtrip", paired.RATIO_CEILINGS)
        self.assertIn("stop_reason", paired.OBSERVED_EXACT["provider_anthropic"])
        self.assertIn("tool_call_count", paired.OBSERVED_EXACT["provider_anthropic"])
        self.assertIn("usage_input", paired.OBSERVED_EXACT["provider_anthropic"])

    def test_provider_google_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("provider_google.stream_roundtrip", RECORD.METRIC_KEYS)
        self.assertIn("stream_roundtrip", paired.METRICS["provider_google"])
        self.assertIn("provider_google.stream_roundtrip", paired.RATIO_CEILINGS)
        self.assertIn("stop_reason", paired.OBSERVED_EXACT["provider_google"])
        self.assertIn("tool_call_count", paired.OBSERVED_EXACT["provider_google"])
        self.assertIn("usage_input", paired.OBSERVED_EXACT["provider_google"])
        self.assertIn("payload_tool_count", paired.OBSERVED_EXACT["provider_google"])

    def test_provider_bedrock_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("provider_bedrock.stream_roundtrip", RECORD.METRIC_KEYS)
        self.assertIn("stream_roundtrip", paired.METRICS["provider_bedrock"])
        self.assertIn("provider_bedrock.stream_roundtrip", paired.RATIO_CEILINGS)
        self.assertIn("stop_reason", paired.OBSERVED_EXACT["provider_bedrock"])
        self.assertIn("tool_call_count", paired.OBSERVED_EXACT["provider_bedrock"])
        self.assertIn("usage_input", paired.OBSERVED_EXACT["provider_bedrock"])
        self.assertIn("payload_tool_count", paired.OBSERVED_EXACT["provider_bedrock"])

    def test_provider_mistral_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("provider_mistral.stream_roundtrip", RECORD.METRIC_KEYS)
        self.assertIn("stream_roundtrip", paired.METRICS["provider_mistral"])
        self.assertIn("provider_mistral.stream_roundtrip", paired.RATIO_CEILINGS)
        self.assertIn("stop_reason", paired.OBSERVED_EXACT["provider_mistral"])
        self.assertIn("tool_call_count", paired.OBSERVED_EXACT["provider_mistral"])
        self.assertIn("usage_input", paired.OBSERVED_EXACT["provider_mistral"])
        self.assertIn("payload_stream", paired.OBSERVED_EXACT["provider_mistral"])

    def test_provider_openai_responses_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn(
            "provider_openai_responses.stream_roundtrip", RECORD.METRIC_KEYS
        )
        self.assertIn(
            "stream_roundtrip", paired.METRICS["provider_openai_responses"]
        )
        self.assertIn(
            "provider_openai_responses.stream_roundtrip", paired.RATIO_CEILINGS
        )
        self.assertIn(
            "stop_reason", paired.OBSERVED_EXACT["provider_openai_responses"]
        )
        self.assertIn(
            "tool_call_count", paired.OBSERVED_EXACT["provider_openai_responses"]
        )
        self.assertIn(
            "payload_stream", paired.OBSERVED_EXACT["provider_openai_responses"]
        )

    def test_provider_azure_openai_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("provider_azure_openai.stream_roundtrip", RECORD.METRIC_KEYS)
        self.assertIn("stream_roundtrip", paired.METRICS["provider_azure_openai"])
        self.assertIn("provider_azure_openai.stream_roundtrip", paired.RATIO_CEILINGS)
        self.assertIn("stop_reason", paired.OBSERVED_EXACT["provider_azure_openai"])
        self.assertIn("tool_call_count", paired.OBSERVED_EXACT["provider_azure_openai"])
        self.assertIn("payload_stream", paired.OBSERVED_EXACT["provider_azure_openai"])

    def test_provider_vertex_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("provider_vertex.stream_roundtrip", RECORD.METRIC_KEYS)
        self.assertIn("stream_roundtrip", paired.METRICS["provider_vertex"])
        self.assertIn("provider_vertex.stream_roundtrip", paired.RATIO_CEILINGS)
        self.assertIn("stop_reason", paired.OBSERVED_EXACT["provider_vertex"])
        self.assertIn("tool_call_count", paired.OBSERVED_EXACT["provider_vertex"])
        self.assertIn("adc_type", paired.OBSERVED_EXACT["provider_vertex"])

    def test_provider_codex_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("provider_codex.stream_roundtrip", RECORD.METRIC_KEYS)
        self.assertIn("stream_roundtrip", paired.METRICS["provider_codex"])
        self.assertIn("provider_codex.stream_roundtrip", paired.RATIO_CEILINGS)
        self.assertIn("stop_reason", paired.OBSERVED_EXACT["provider_codex"])
        self.assertIn("tool_call_count", paired.OBSERVED_EXACT["provider_codex"])
        self.assertIn("payload_stream", paired.OBSERVED_EXACT["provider_codex"])

    def test_provider_pi_messages_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("provider_pi_messages.stream_roundtrip", RECORD.METRIC_KEYS)
        self.assertIn("stream_roundtrip", paired.METRICS["provider_pi_messages"])
        self.assertIn("provider_pi_messages.stream_roundtrip", paired.RATIO_CEILINGS)
        self.assertIn("stop_reason", paired.OBSERVED_EXACT["provider_pi_messages"])
        self.assertIn("tool_call_count", paired.OBSERVED_EXACT["provider_pi_messages"])
        self.assertIn("payload_tool_count", paired.OBSERVED_EXACT["provider_pi_messages"])

    def test_cli_settings_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("cli_settings.create", RECORD.METRIC_KEYS)
        self.assertIn("create", paired.METRICS["cli_settings"])
        self.assertIn("cli_settings.create", paired.RATIO_CEILINGS)
        self.assertIn("theme", paired.OBSERVED_EXACT["cli_settings"])
        self.assertIn("compaction_reserve_tokens", paired.OBSERVED_EXACT["cli_settings"])
        self.assertIn("project_trusted", paired.OBSERVED_EXACT["cli_settings"])

    def test_resource_loader_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("resource_loader.reload", RECORD.METRIC_KEYS)
        self.assertIn("reload", paired.METRICS["resource_loader"])
        self.assertIn("resource_loader.reload", paired.RATIO_CEILINGS)
        self.assertIn("skill_count", paired.OBSERVED_EXACT["resource_loader"])
        self.assertIn("prompt_count", paired.OBSERVED_EXACT["resource_loader"])
        self.assertIn("system_prompt", paired.OBSERVED_EXACT["resource_loader"])

    def test_package_manager_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("package_manager.resolve", RECORD.METRIC_KEYS)
        self.assertIn("resolve", paired.METRICS["package_manager"])
        self.assertIn("package_manager.resolve", paired.RATIO_CEILINGS)
        self.assertIn("package_count", paired.OBSERVED_EXACT["package_manager"])
        self.assertIn("skill_count", paired.OBSERVED_EXACT["package_manager"])
        self.assertIn("extension_count", paired.OBSERVED_EXACT["package_manager"])

    def test_session_discovery_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("session_discovery.header_probe", RECORD.METRIC_KEYS)
        self.assertIn("header_probe", paired.METRICS["session_discovery"])
        self.assertIn("session_discovery.header_probe", paired.RATIO_CEILINGS)
        self.assertIn("file_count", paired.OBSERVED_EXACT["session_discovery"])
        self.assertIn("session_id", paired.OBSERVED_EXACT["session_discovery"])
        self.assertIn("most_recent_name", paired.OBSERVED_EXACT["session_discovery"])

    def test_session_export_html_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("session_export_html.to_html", RECORD.METRIC_KEYS)
        self.assertIn("to_html", paired.METRICS["session_export_html"])
        self.assertIn("session_export_html.to_html", paired.RATIO_CEILINGS)
        self.assertIn("has_accent", paired.OBSERVED_EXACT["session_export_html"])
        self.assertIn("theme", paired.OBSERVED_EXACT["session_export_html"])

    def test_protocol_cbor_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("protocol_cbor.roundtrip", RECORD.METRIC_KEYS)
        self.assertIn("roundtrip", paired.METRICS["protocol_cbor"])
        self.assertIn("protocol_cbor.roundtrip", paired.RATIO_CEILINGS)
        self.assertIn("vector_count", paired.OBSERVED_EXACT["protocol_cbor"])
        self.assertIn("roundtrip_hex", paired.OBSERVED_EXACT["protocol_cbor"])
        self.assertIn("match", paired.OBSERVED_EXACT["protocol_cbor"])

    def test_agent_schema_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("agent_schema.validate_ok_fail", RECORD.METRIC_KEYS)
        self.assertIn("validate_ok_fail", paired.METRICS["agent_schema"])
        self.assertIn("agent_schema.validate_ok_fail", paired.RATIO_CEILINGS)
        self.assertIn("ok", paired.OBSERVED_EXACT["agent_schema"])
        self.assertIn("fail", paired.OBSERVED_EXACT["agent_schema"])
        self.assertIn("tool", paired.OBSERVED_EXACT["agent_schema"])

    def test_harness_storage_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("harness_storage.open_walk", RECORD.METRIC_KEYS)
        self.assertIn("open_walk", paired.METRICS["harness_storage"])
        self.assertIn("harness_storage.open_walk", paired.RATIO_CEILINGS)
        self.assertIn("entry_count", paired.OBSERVED_EXACT["harness_storage"])
        self.assertIn("leaf_id", paired.OBSERVED_EXACT["harness_storage"])
        self.assertIn("session_id", paired.OBSERVED_EXACT["harness_storage"])

    def test_protocol_codec_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("protocol_codec.roundtrip", RECORD.METRIC_KEYS)
        self.assertIn("roundtrip", paired.METRICS["protocol_codec"])
        self.assertIn("protocol_codec.roundtrip", paired.RATIO_CEILINGS)
        self.assertIn("frame_bytes", paired.OBSERVED_EXACT["protocol_codec"])
        self.assertIn("type", paired.OBSERVED_EXACT["protocol_codec"])
        self.assertIn("command", paired.OBSERVED_EXACT["protocol_codec"])

    def test_agent_proxy_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("agent_proxy.stream_roundtrip", RECORD.METRIC_KEYS)
        self.assertIn("stream_roundtrip", paired.METRICS["agent_proxy"])
        self.assertIn("agent_proxy.stream_roundtrip", paired.RATIO_CEILINGS)
        self.assertIn("event_count", paired.OBSERVED_EXACT["agent_proxy"])
        self.assertIn("text", paired.OBSERVED_EXACT["agent_proxy"])
        self.assertIn("usage_total", paired.OBSERVED_EXACT["agent_proxy"])

    def test_oauth_pkce_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("oauth_pkce.challenge_urls", RECORD.METRIC_KEYS)
        self.assertIn("challenge_urls", paired.METRICS["oauth_pkce"])
        self.assertIn("oauth_pkce.challenge_urls", paired.RATIO_CEILINGS)
        self.assertIn("challenge", paired.OBSERVED_EXACT["oauth_pkce"])
        self.assertIn("openai_prefix", paired.OBSERVED_EXACT["oauth_pkce"])
        self.assertIn("anthropic_prefix", paired.OBSERVED_EXACT["oauth_pkce"])

    def test_evals_harness_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("evals_harness.summarize", RECORD.METRIC_KEYS)
        self.assertIn("summarize", paired.METRICS["evals_harness"])
        self.assertIn("evals_harness.summarize", paired.RATIO_CEILINGS)
        self.assertIn("eval_sets", paired.OBSERVED_EXACT["evals_harness"])
        self.assertIn("candidate_wins", paired.OBSERVED_EXACT["evals_harness"])
        self.assertIn("ties", paired.OBSERVED_EXACT["evals_harness"])

    def test_ai_crypto_model_data_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("ai_crypto_model_data.manifest", RECORD.METRIC_KEYS)
        self.assertIn("manifest", paired.METRICS["ai_crypto_model_data"])
        self.assertIn("ai_crypto_model_data.manifest", paired.RATIO_CEILINGS)
        self.assertIn("structure_hash", paired.OBSERVED_EXACT["ai_crypto_model_data"])
        self.assertIn("openai_json_hash", paired.OBSERVED_EXACT["ai_crypto_model_data"])
        self.assertIn("anthropic_json_hash", paired.OBSERVED_EXACT["ai_crypto_model_data"])

    def test_cli_models_rest_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("cli_models_rest.pattern_match", RECORD.METRIC_KEYS)
        self.assertIn("pattern_match", paired.METRICS["cli_models_rest"])
        self.assertIn("cli_models_rest.pattern_match", paired.RATIO_CEILINGS)
        self.assertIn("exact_id", paired.OBSERVED_EXACT["cli_models_rest"])
        self.assertIn("scoped_thinking", paired.OBSERVED_EXACT["cli_models_rest"])
        self.assertIn("miss", paired.OBSERVED_EXACT["cli_models_rest"])

    def test_image_runtime_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("image_runtime.dimensions", RECORD.METRIC_KEYS)
        self.assertIn("dimensions", paired.METRICS["image_runtime"])
        self.assertIn("image_runtime.dimensions", paired.RATIO_CEILINGS)
        self.assertIn("png_width", paired.OBSERVED_EXACT["image_runtime"])
        self.assertIn("gif_height", paired.OBSERVED_EXACT["image_runtime"])
        self.assertIn("miss", paired.OBSERVED_EXACT["image_runtime"])

    def test_cli_print_rpc_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("cli_print_rpc.jsonl_line", RECORD.METRIC_KEYS)
        self.assertIn("jsonl_line", paired.METRICS["cli_print_rpc"])
        self.assertIn("cli_print_rpc.jsonl_line", paired.RATIO_CEILINGS)
        self.assertIn("line_chars", paired.OBSERVED_EXACT["cli_print_rpc"])
        self.assertIn("newline", paired.OBSERVED_EXACT["cli_print_rpc"])
        self.assertIn("payload", paired.OBSERVED_EXACT["cli_print_rpc"])

    def test_tui_latex_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("tui_latex.render", RECORD.METRIC_KEYS)
        self.assertIn("render", paired.METRICS["tui_latex"])
        self.assertIn("tui_latex.render", paired.RATIO_CEILINGS)
        self.assertIn("e_mc2", paired.OBSERVED_EXACT["tui_latex"])
        self.assertIn("frac_inline", paired.OBSERVED_EXACT["tui_latex"])
        self.assertIn("unknown_miss", paired.OBSERVED_EXACT["tui_latex"])

    def test_tui_editor_helpers_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("tui_editor_helpers.fuzzy_match", RECORD.METRIC_KEYS)
        self.assertIn("fuzzy_match", paired.METRICS["tui_editor_helpers"])
        self.assertIn("tui_editor_helpers.fuzzy_match", paired.RATIO_CEILINGS)
        self.assertIn("gpt", paired.OBSERVED_EXACT["tui_editor_helpers"])
        self.assertIn("miss", paired.OBSERVED_EXACT["tui_editor_helpers"])
        self.assertIn("empty", paired.OBSERVED_EXACT["tui_editor_helpers"])

    def test_tui_theme_overlay_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("tui_theme_overlay.osc11_bg", RECORD.METRIC_KEYS)
        self.assertIn("osc11_bg", paired.METRICS["tui_theme_overlay"])
        self.assertIn("tui_theme_overlay.osc11_bg", paired.RATIO_CEILINGS)
        self.assertIn("rgb_r", paired.OBSERVED_EXACT["tui_theme_overlay"])
        self.assertIn("hex6_b", paired.OBSERVED_EXACT["tui_theme_overlay"])
        self.assertIn("scheme_dark", paired.OBSERVED_EXACT["tui_theme_overlay"])

    def test_ai_support_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("ai_support.estimate_text", RECORD.METRIC_KEYS)
        self.assertIn("estimate_text", paired.METRICS["ai_support"])
        self.assertIn("ai_support.estimate_text", paired.RATIO_CEILINGS)
        self.assertIn("empty", paired.OBSERVED_EXACT["ai_support"])
        self.assertIn("hello", paired.OBSERVED_EXACT["ai_support"])
        self.assertIn("block", paired.OBSERVED_EXACT["ai_support"])

    def test_tui_select_settings_loaders_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("tui_select_settings_loaders.filter", RECORD.METRIC_KEYS)
        self.assertIn("filter", paired.METRICS["tui_select_settings_loaders"])
        self.assertIn("tui_select_settings_loaders.filter", paired.RATIO_CEILINGS)
        self.assertIn("he_count", paired.OBSERVED_EXACT["tui_select_settings_loaders"])
        self.assertIn("he_first", paired.OBSERVED_EXACT["tui_select_settings_loaders"])
        self.assertIn("zz_count", paired.OBSERVED_EXACT["tui_select_settings_loaders"])

    def test_tui_word_navigation_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("tui_word_navigation.step", RECORD.METRIC_KEYS)
        self.assertIn("step", paired.METRICS["tui_word_navigation"])
        self.assertIn("tui_word_navigation.step", paired.RATIO_CEILINGS)
        self.assertIn("back_from_space", paired.OBSERVED_EXACT["tui_word_navigation"])
        self.assertIn("fwd_from_o", paired.OBSERVED_EXACT["tui_word_navigation"])
        self.assertIn("fwd_end", paired.OBSERVED_EXACT["tui_word_navigation"])

    def test_tui_overlay_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("tui_overlay.composite_line", RECORD.METRIC_KEYS)
        self.assertIn("composite_line", paired.METRICS["tui_overlay"])
        self.assertIn("tui_overlay.composite_line", paired.RATIO_CEILINGS)
        self.assertIn("line_chars", paired.OBSERVED_EXACT["tui_overlay"])
        self.assertIn("visible_width", paired.OBSERVED_EXACT["tui_overlay"])
        self.assertIn("has_reset", paired.OBSERVED_EXACT["tui_overlay"])

    def test_tui_kill_ring_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("tui_kill_ring.push_peek", RECORD.METRIC_KEYS)
        self.assertIn("push_peek", paired.METRICS["tui_kill_ring"])
        self.assertIn("tui_kill_ring.push_peek", paired.RATIO_CEILINGS)
        self.assertIn("empty_len", paired.OBSERVED_EXACT["tui_kill_ring"])
        self.assertIn("peek_two", paired.OBSERVED_EXACT["tui_kill_ring"])
        self.assertIn("acc_prepend", paired.OBSERVED_EXACT["tui_kill_ring"])

    def test_tui_undo_stack_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("tui_undo_stack.push_pop", RECORD.METRIC_KEYS)
        self.assertIn("push_pop", paired.METRICS["tui_undo_stack"])
        self.assertIn("tui_undo_stack.push_pop", paired.RATIO_CEILINGS)
        self.assertIn("empty_len", paired.OBSERVED_EXACT["tui_undo_stack"])
        self.assertIn("clone_n", paired.OBSERVED_EXACT["tui_undo_stack"])
        self.assertIn("after_clear", paired.OBSERVED_EXACT["tui_undo_stack"])

    def test_tui_autocomplete_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("tui_autocomplete.suggest_apply", RECORD.METRIC_KEYS)
        self.assertIn("suggest_apply", paired.METRICS["tui_autocomplete"])
        self.assertIn("tui_autocomplete.suggest_apply", paired.RATIO_CEILINGS)
        self.assertIn("slash_count", paired.OBSERVED_EXACT["tui_autocomplete"])
        self.assertIn("quote_first_len", paired.OBSERVED_EXACT["tui_autocomplete"])
        self.assertIn("apply_col", paired.OBSERVED_EXACT["tui_autocomplete"])

    def test_tui_keybindings_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("tui_keybindings.resolve_match", RECORD.METRIC_KEYS)
        self.assertIn("resolve_match", paired.METRICS["tui_keybindings"])
        self.assertIn("tui_keybindings.resolve_match", paired.RATIO_CEILINGS)
        self.assertIn("left_count", paired.OBSERVED_EXACT["tui_keybindings"])
        self.assertIn("enter_submit", paired.OBSERVED_EXACT["tui_keybindings"])
        self.assertIn("conflict_count", paired.OBSERVED_EXACT["tui_keybindings"])

    def test_tui_stdin_buffer_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("tui_stdin_buffer.process", RECORD.METRIC_KEYS)
        self.assertIn("process", paired.METRICS["tui_stdin_buffer"])
        self.assertIn("tui_stdin_buffer.process", paired.RATIO_CEILINGS)
        self.assertIn("hello_count", paired.OBSERVED_EXACT["tui_stdin_buffer"])
        self.assertIn("leftover", paired.OBSERVED_EXACT["tui_stdin_buffer"])
        self.assertIn("paste_len", paired.OBSERVED_EXACT["tui_stdin_buffer"])

    def test_tui_input_component_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("tui_input_component.edit", RECORD.METRIC_KEYS)
        self.assertIn("edit", paired.METRICS["tui_input_component"])
        self.assertIn("tui_input_component.edit", paired.RATIO_CEILINGS)
        self.assertIn("after_insert", paired.OBSERVED_EXACT["tui_input_component"])
        self.assertIn("after_yank", paired.OBSERVED_EXACT["tui_input_component"])
        self.assertIn("last_code", paired.OBSERVED_EXACT["tui_input_component"])

    def test_tui_native_modifiers_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("tui_native_modifiers.pressed", RECORD.METRIC_KEYS)
        self.assertIn("pressed", paired.METRICS["tui_native_modifiers"])
        self.assertIn("tui_native_modifiers.pressed", paired.RATIO_CEILINGS)
        self.assertIn("shift", paired.OBSERVED_EXACT["tui_native_modifiers"])
        self.assertIn("control", paired.OBSERVED_EXACT["tui_native_modifiers"])
        self.assertIn("command", paired.OBSERVED_EXACT["tui_native_modifiers"])

    def test_tui_settings_list_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("tui_settings_list.apply_filter", RECORD.METRIC_KEYS)
        self.assertIn("apply_filter", paired.METRICS["tui_settings_list"])
        self.assertIn("tui_settings_list.apply_filter", paired.RATIO_CEILINGS)
        self.assertIn("he_count", paired.OBSERVED_EXACT["tui_settings_list"])
        self.assertIn("he_hello", paired.OBSERVED_EXACT["tui_settings_list"])
        self.assertIn("he_help", paired.OBSERVED_EXACT["tui_settings_list"])
        self.assertIn("he_selected", paired.OBSERVED_EXACT["tui_settings_list"])

    def test_ai_capabilities_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("ai_capabilities.short_hash", RECORD.METRIC_KEYS)
        self.assertIn("short_hash", paired.METRICS["ai_capabilities"])
        self.assertIn("ai_capabilities.short_hash", paired.RATIO_CEILINGS)
        self.assertIn("empty", paired.OBSERVED_EXACT["ai_capabilities"])
        self.assertIn("abc", paired.OBSERVED_EXACT["ai_capabilities"])
        self.assertIn("cjk", paired.OBSERVED_EXACT["ai_capabilities"])

    def test_cli_support_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("cli_support.strip_ansi", RECORD.METRIC_KEYS)
        self.assertIn("cli_support.normalize_path", RECORD.METRIC_KEYS)
        self.assertIn("strip_ansi", paired.METRICS["cli_support"])
        self.assertIn("normalize_path", paired.METRICS["cli_support"])
        self.assertIn("cli_support.strip_ansi", paired.RATIO_CEILINGS)
        self.assertIn("cli_support.normalize_path", paired.RATIO_CEILINGS)
        self.assertIn("csi_osc", paired.OBSERVED_EXACT["cli_support"])
        self.assertIn("ris", paired.OBSERVED_EXACT["cli_support"])
        self.assertIn("plain", paired.OBSERVED_EXACT["cli_support"])
        self.assertIn("trim", paired.OBSERVED_EXACT["cli_support"])
        self.assertIn("tilde", paired.OBSERVED_EXACT["cli_support"])
        self.assertIn("file", paired.OBSERVED_EXACT["cli_support"])

    def test_cli_interactive_controller_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("cli_interactive_controller.decode_entity", RECORD.METRIC_KEYS)
        self.assertIn("decode_entity", paired.METRICS["cli_interactive_controller"])
        self.assertIn("cli_interactive_controller.decode_entity", paired.RATIO_CEILINGS)
        self.assertIn("amp", paired.OBSERVED_EXACT["cli_interactive_controller"])
        self.assertIn("hash65", paired.OBSERVED_EXACT["cli_interactive_controller"])
        self.assertIn("miss", paired.OBSERVED_EXACT["cli_interactive_controller"])

    def test_cli_sdk_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("cli_sdk.version_newer", RECORD.METRIC_KEYS)
        self.assertIn("version_newer", paired.METRICS["cli_sdk"])
        self.assertIn("cli_sdk.version_newer", paired.RATIO_CEILINGS)
        self.assertIn("beta", paired.OBSERVED_EXACT["cli_sdk"])
        self.assertIn("newer_flag", paired.OBSERVED_EXACT["cli_sdk"])
        self.assertIn("equal_flag", paired.OBSERVED_EXACT["cli_sdk"])

    def test_provider_registry_defs_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("provider_registry_defs.lookup", RECORD.METRIC_KEYS)
        self.assertIn("lookup", paired.METRICS["provider_registry_defs"])
        self.assertIn("provider_registry_defs.lookup", paired.RATIO_CEILINGS)
        self.assertIn("openai", paired.OBSERVED_EXACT["provider_registry_defs"])
        self.assertIn("google", paired.OBSERVED_EXACT["provider_registry_defs"])
        self.assertIn("unknown", paired.OBSERVED_EXACT["provider_registry_defs"])

    def test_skill_prompt_load_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("skill_prompt_load.build_prompt", RECORD.METRIC_KEYS)
        self.assertIn("build_prompt", paired.METRICS["skill_prompt_load"])
        self.assertIn("skill_prompt_load.build_prompt", paired.RATIO_CEILINGS)
        self.assertIn("custom_len", paired.OBSERVED_EXACT["skill_prompt_load"])
        self.assertIn("has_cwd", paired.OBSERVED_EXACT["skill_prompt_load"])
        self.assertIn("has_agents", paired.OBSERVED_EXACT["skill_prompt_load"])

    def test_cli_bootstrap_sessions_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("cli_bootstrap_sessions.coding_tools", RECORD.METRIC_KEYS)
        self.assertIn("coding_tools", paired.METRICS["cli_bootstrap_sessions"])
        self.assertIn("cli_bootstrap_sessions.coding_tools", paired.RATIO_CEILINGS)
        self.assertIn("count", paired.OBSERVED_EXACT["cli_bootstrap_sessions"])
        self.assertIn("baseline", paired.OBSERVED_EXACT["cli_bootstrap_sessions"])
        self.assertIn("read_first", paired.OBSERVED_EXACT["cli_bootstrap_sessions"])

    def test_ai_runtime_faux_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("ai_runtime_faux.blocks", RECORD.METRIC_KEYS)
        self.assertIn("blocks", paired.METRICS["ai_runtime_faux"])
        self.assertIn("ai_runtime_faux.blocks", paired.RATIO_CEILINGS)
        self.assertIn("text_len", paired.OBSERVED_EXACT["ai_runtime_faux"])
        self.assertIn("text", paired.OBSERVED_EXACT["ai_runtime_faux"])
        self.assertIn("think", paired.OBSERVED_EXACT["ai_runtime_faux"])

    def test_http_transport_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("http_transport.parse_url", RECORD.METRIC_KEYS)
        self.assertIn("parse_url", paired.METRICS["http_transport"])
        self.assertIn("http_transport.parse_url", paired.RATIO_CEILINGS)
        self.assertIn("https_host", paired.OBSERVED_EXACT["http_transport"])
        self.assertIn("http_port", paired.OBSERVED_EXACT["http_transport"])
        self.assertIn("http_path", paired.OBSERVED_EXACT["http_transport"])

    def test_session_compact_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("session_compact.compact", RECORD.METRIC_KEYS)
        self.assertIn("compact", paired.METRICS["session_compact"])
        self.assertIn("session_compact.compact", paired.RATIO_CEILINGS)
        self.assertIn("compacted", paired.OBSERVED_EXACT["session_compact"])
        self.assertIn("first_kept", paired.OBSERVED_EXACT["session_compact"])
        self.assertIn("summary_chars", paired.OBSERVED_EXACT["session_compact"])

    def test_tool_grep_is_a_recorded_metric(self) -> None:
        paired = load_script("goal20_paired_paths", "goal20-paired-paths.py")
        self.assertIn("tool_grep.context_file", RECORD.METRIC_KEYS)
        self.assertIn("context_file", paired.METRICS["tool_grep"])
        self.assertIn("tool_grep.context_file", paired.RATIO_CEILINGS)
        self.assertIn("match_limit", paired.OBSERVED_EXACT["tool_grep"])
        self.assertIn("output_chars", paired.OBSERVED_EXACT["tool_grep"])
        self.assertIn("truncated", paired.OBSERVED_EXACT["tool_grep"])

    def test_build_entry_derives_baseline_from_ratio(self) -> None:
        cadr = fake_cadr()
        summary = fake_summary(cadr)
        entry = RECORD.build_entry(
            summary, cadr, recorded_at="2026-08-14T00:00:00Z"
        )
        self.assertEqual(entry["label"], "paired-paths-quick")
        self.assertTrue(entry["quick"])
        self.assertEqual(len(entry["metrics"]), len(RECORD.METRIC_KEYS))
        first = entry["metrics"][RECORD.METRIC_KEYS[0]]
        self.assertAlmostEqual(first["cadrMedianUs"], 1000.0)
        self.assertAlmostEqual(first["ratio"], 2.0)
        self.assertAlmostEqual(first["baselineMedianUs"], 500.0)

    def test_append_then_render_current_and_previous(self) -> None:
        cadr = fake_cadr()
        summary = fake_summary(cadr)
        with tempfile.TemporaryDirectory() as temporary:
            history_path = Path(temporary) / "paired.json"
            first = RECORD.build_entry(
                summary, cadr, recorded_at="2026-08-14T00:00:00Z"
            )
            RECORD.append_entry(history_path, first)
            second_summary = json.loads(json.dumps(summary))
            second_summary["ratios"]["storage_journal.journal_append"] = 1.5
            second = RECORD.build_entry(
                second_summary,
                fake_cadr(quick=False),
                recorded_at="2026-08-14T01:00:00Z",
            )
            history = RECORD.append_entry(history_path, second)
            section = LEDGER.render_paired_section(history)
            self.assertIn("GOAL20_PAIRED_PATHS_START", section)
            self.assertIn("`storage_journal.journal_append`", section)
            self.assertIn("`sqlite_session.open_walk`", section)
            self.assertIn("`tool_read.text_file`", section)
            self.assertIn("`tool_grep.context_file`", section)
            self.assertIn("`agent_tool_loop.roundtrip`", section)
            self.assertIn("`session_compact.compact`", section)
            self.assertIn("`provider_anthropic.stream_roundtrip`", section)
            self.assertIn("`provider_google.stream_roundtrip`", section)
            self.assertIn("`provider_bedrock.stream_roundtrip`", section)
            self.assertIn("`cli_settings.create`", section)
            self.assertIn("`resource_loader.reload`", section)
            self.assertIn("`ai_crypto_model_data.manifest`", section)
            self.assertIn("`cli_models_rest.pattern_match`", section)
            self.assertIn("`image_runtime.dimensions`", section)
            self.assertIn("`cli_print_rpc.jsonl_line`", section)
            self.assertIn("`tui_latex.render`", section)
            self.assertIn("`tui_editor_helpers.fuzzy_match`", section)
            self.assertIn("`tui_theme_overlay.osc11_bg`", section)
            self.assertIn("`ai_support.estimate_text`", section)
            self.assertIn("`tui_select_settings_loaders.filter`", section)
            self.assertIn("`tui_word_navigation.step`", section)
            self.assertIn("`tui_overlay.composite_line`", section)
            self.assertIn("`tui_kill_ring.push_peek`", section)
            self.assertIn("`tui_undo_stack.push_pop`", section)
            self.assertIn("`tui_autocomplete.suggest_apply`", section)
            self.assertIn("`tui_keybindings.resolve_match`", section)
            self.assertIn("`tui_stdin_buffer.process`", section)
            self.assertIn("`tui_input_component.edit`", section)
            self.assertIn("`tui_native_modifiers.pressed`", section)
            self.assertIn("`tui_settings_list.apply_filter`", section)
            self.assertIn("`ai_capabilities.short_hash`", section)
            self.assertIn("`cli_support.strip_ansi`", section)
            self.assertIn("`cli_support.normalize_path`", section)
            self.assertIn("`cli_interactive_controller.decode_entity`", section)
            self.assertIn("`cli_sdk.version_newer`", section)
            self.assertIn("`provider_registry_defs.lookup`", section)
            self.assertIn("`skill_prompt_load.build_prompt`", section)
            self.assertIn("`cli_bootstrap_sessions.coding_tools`", section)
            self.assertIn("`ai_runtime_faux.blocks`", section)
            self.assertIn("`http_transport.parse_url`", section)
            self.assertIn("1.50×", section)
            self.assertIn("Previous:", section)
            self.assertIn("paired-paths-quick", section)
            markdown = "# Performance\n\nintro\n"
            markdown = LEDGER.replace_marked_section(
                markdown,
                LEDGER.PAIRED_START,
                LEDGER.PAIRED_END,
                section,
            )
            markdown = LEDGER.replace_marked_section(
                markdown,
                LEDGER.PAIRED_START,
                LEDGER.PAIRED_END,
                LEDGER.render_paired_section(history),
            )
            self.assertEqual(markdown.count("GOAL20_PAIRED_PATHS_START"), 1)


class TestNativeImageHistory(unittest.TestCase):
    def test_extract_omits_bytes_when_absent(self) -> None:
        row = HISTORY.extract(
            {
                "cold_start": {"median_us": 100.0},
                "metrics": {
                    "frame_render": {
                        "points": [{"n": 5000, "median_us": 1.0, "median_bytes": 2.0}]
                    }
                },
            }
        )
        self.assertNotIn("nativeImageBytes", row)
        self.assertNotEqual(row.get("nativeImageBytes"), 20_884_056)

    def test_extract_copies_stat_size_only(self) -> None:
        row = HISTORY.extract(
            {
                "cold_start": {"median_us": 100.0},
                "metrics": {
                    "frame_render": {
                        "points": [{"n": 5000, "median_us": 1.0, "median_bytes": 2.0}]
                    }
                },
            },
            native_image_bytes=20457848,
        )
        self.assertEqual(row["nativeImageBytes"], 20457848)

    def test_native_image_flag_stats_a_real_file(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            image = Path(temporary) / "cadr"
            image.write_bytes(b"x" * 4096)
            bench = Path(temporary) / "bench.json"
            history = Path(temporary) / "history.json"
            bench.write_text(
                json.dumps(
                    {
                        "label": "probe",
                        "cold_start": {"median_us": 100.0},
                        "metrics": {
                            "frame_render": {
                                "points": [
                                    {
                                        "n": 5000,
                                        "median_us": 1.0,
                                        "median_bytes": 2.0,
                                    }
                                ]
                            }
                        },
                    }
                ),
                encoding="utf-8",
            )
            self.assertEqual(
                run_main(
                    HISTORY,
                    [
                        "record-performance-history.py",
                        "--bench",
                        str(bench),
                        "--history",
                        str(history),
                        "--native-image",
                        str(image),
                    ],
                ),
                0,
            )
            stored = json.loads(history.read_text(encoding="utf-8"))
            self.assertEqual(stored["entries"][0]["nativeImageBytes"], 4096)

    def test_ledger_prints_emdash_when_bytes_missing(self) -> None:
        history = {
            "entries": [
                {
                    "recordedAt": "2026-08-14T00:00:00Z",
                    "label": "verify-isolated",
                    "gitHead": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                    "machine": "test-host",
                    "coldStartMedianUs": 100.0,
                    "frame5000MedianUs": 1.0,
                    "frame5000MedianBytes": 2.0,
                },
                {
                    "recordedAt": "2026-08-14T01:00:00Z",
                    "label": "verify-isolated",
                    "gitHead": "cccccccccccccccccccccccccccccccccccccccc",
                    "machine": "test-host",
                    "coldStartMedianUs": 110.0,
                    "nativeImageBytes": 20457848,
                    "frame5000MedianUs": 1.0,
                    "frame5000MedianBytes": 2.0,
                },
            ]
        }
        section = LEDGER.render_section(history, None)
        self.assertIn("native image B", section)
        self.assertIn("| 100.0 | — | 1.0 |", section)
        self.assertIn("| 110.0 | 20,457,848 | 1.0 |", section)
        self.assertNotIn("20,884,056", section)


class TestSelfHistoryStillRenders(unittest.TestCase):
    def test_replace_keeps_surrounding_prose(self) -> None:
        history = {
            "entries": [
                {
                    "recordedAt": "2026-08-14T00:00:00Z",
                    "label": "verify-isolated",
                    "gitHead": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                    "machine": "test-host",
                    "coldStartMedianUs": 100.0,
                    "frame5000MedianUs": 1.0,
                    "frame5000MedianBytes": 2.0,
                }
            ]
        }
        markdown = "before\n\n" + LEDGER.render_section(history, None) + "after\n"
        rewritten = LEDGER.replace_section(
            markdown, LEDGER.render_section(history, None)
        )
        self.assertTrue(rewritten.startswith("before"))
        self.assertIn("after", rewritten)
        self.assertEqual(rewritten.count("GOAL20_PERF_HISTORY_START"), 1)


if __name__ == "__main__":
    unittest.main()
