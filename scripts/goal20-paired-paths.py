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
    "cli_dispatch": ("argv_parse", "help_render", "list_models_registry", "list_models_render", "parsed_provider", "parsed_model", "parsed_thinking", "parsed_tools", "parsed_exclude_tools", "parsed_messages", "parsed_file_args", "parsed_list_models", "parsed_unknown_flag_count", "parsed_diagnostic_count", "available_model_count", "available_providers", "list_models_characters", "list_models_lines"),
    "provider_stream": ("stream_roundtrip", "payload_keys", "payload_message_count", "payload_tool_count", "payload_stream", "content_block_types", "text_characters", "tool_call_count", "stop_reason", "usage_input", "usage_output"),
    "provider_anthropic": ("stream_roundtrip", "content_block_types", "stop_reason", "text_characters", "tool_call_count", "usage_input", "usage_output", "payload_stream", "payload_tool_count"),
    "provider_google": ("stream_roundtrip", "content_block_types", "stop_reason", "text_characters", "tool_call_count", "usage_input", "usage_output", "payload_tool_count"),
    "provider_bedrock": ("stream_roundtrip", "content_block_types", "stop_reason", "text_characters", "tool_call_count", "usage_input", "usage_output", "payload_tool_count"),
    "provider_mistral": ("stream_roundtrip", "content_block_types", "stop_reason", "text_characters", "tool_call_count", "usage_input", "usage_output", "payload_stream", "payload_tool_count"),
    "provider_openai_responses": ("stream_roundtrip", "content_block_types", "stop_reason", "text_characters", "tool_call_count", "usage_input", "usage_output", "payload_stream", "payload_tool_count"),
    "provider_azure_openai": ("stream_roundtrip", "content_block_types", "stop_reason", "text_characters", "tool_call_count", "usage_input", "usage_output", "payload_stream", "payload_tool_count"),
    "provider_vertex": ("stream_roundtrip", "content_block_types", "stop_reason", "text_characters", "tool_call_count", "usage_input", "usage_output", "payload_tool_count", "adc_type"),
    "provider_codex": ("stream_roundtrip", "content_block_types", "stop_reason", "text_characters", "tool_call_count", "usage_input", "usage_output", "payload_stream", "payload_tool_count"),
    "provider_pi_messages": ("stream_roundtrip", "content_block_types", "stop_reason", "text_characters", "tool_call_count", "usage_input", "usage_output", "payload_tool_count"),
    "cli_settings": ("create", "reload", "enabled_models", "block_images", "default_model", "default_provider", "output_padding", "theme", "compaction_reserve_tokens", "default_project_trust", "http_idle_timeout_ms", "project_trusted", "rl_theme_light", "rl_model", "rl_idle", "rl_n", "em_all", "em_one", "em_n", "bi_default", "bi_blocked", "bi_n"),
    "agent_conditions": ("error_probe", "ac_schema_tool", "ac_schema_ptr", "ac_schema_reason", "ac_tool_name", "ac_tool_id", "ac_sess_path", "ac_sess_line", "ac_sub_schema", "ac_sub_tool", "ac_sub_ext_reg", "ac_sub_ext_exec", "ac_sub_stale", "ac_sub_session", "ac_catch_busy", "ac_catch_shutdown", "ac_catch_turn", "ac_catch_ext_reg", "ac_catch_ext_exec", "ac_catch_stale"),
    "execution_env": ("exists_remove_temps", "ex_missing", "ex_present", "ex_after_rm", "tmp_dir", "tmp_file", "tmp_suffix", "rm_force", "rm_recursive", "absolute_path", "join_path", "file_info"),
    "file_mutation_queue": ("with_queue", "queue_key", "lock", "register", "wait_turn", "release_turn", "ensure_state", "call_with", "make_state", "state_key", "pending_count", "next_ticket", "serving_ticket", "fmq_alias_key", "fmq_missing_key", "fmq_other_key", "fmq_fifo_sum", "fmq_other_run", "fmq_clean", "fmqk_alias", "fmqk_missing", "fmqk_other", "fmqk_n", "fmql_alias", "fmql_other", "fmql_missing", "fmql_repeat", "fmql_n", "fmqr_alias", "fmqr_other", "fmqr_pending", "fmqr_ticket", "fmqr_n", "fmqw_serving", "fmqw_pending", "fmqw_other", "fmqw_missing", "fmqw_n", "fmqe_serving", "fmqe_pending", "fmqe_other", "fmqe_missing", "fmqe_n", "fmqs_alias", "fmqs_other", "fmqs_missing", "fmqs_repeat", "fmqs_n", "fmqf_alias", "fmqf_other", "fmqf_fifo", "fmqf_run", "fmqf_n", "fmqm_pending", "fmqm_ticket", "fmqm_serving", "fmqm_other", "fmqm_n", "fmqt_alias", "fmqt_other", "fmqt_missing", "fmqt_repeat", "fmqt_n", "fmqp_shared", "fmqp_other", "fmqp_missing", "fmqp_alias", "fmqp_n", "fmqi_shared", "fmqi_other", "fmqi_missing", "fmqi_alias", "fmqi_n", "fmqv_zero", "fmqv_other", "fmqv_missing", "fmqv_alias", "fmqv_n", "waitqueue", "registry", "state_p"),
    "harness_events": ("emit", "on", "watch", "make_start", "make_end", "event_type", "make_bus", "he_direct", "he_watch", "he_start", "he_end", "he_second", "heon_off", "heon_keep", "heon_type", "hew_snap", "hew_count", "hew_start", "hew_end", "hes_type", "hes_lane", "hes_run", "hee_type", "hee_lane", "hee_run", "hee_outcome", "hee_abort", "het_start", "het_end", "het_fail", "heb_distinct", "heb_a", "heb_b"),
    "bash_tool": ("strip_exit_footer", "append_status", "truncation_notice", "sef_exact", "sef_nl", "sef_no_nl", "sef_plain", "sef_empty", "sef_n", "abs_empty", "abs_abort", "abs_exit", "abs_timeout", "abs_n", "btn_none", "btn_partial", "btn_lines", "btn_bytes", "btn_n", "live_output", "strip_status", "strip_truncation", "process_deadline", "user_bash_result", "normalized_extension", "pd_nil", "pd_int", "pd_ord", "pd_zero", "ubr_cmd", "ubr_out", "ubr_exit", "ubr_can", "ubr_ex", "ubr_n", "neb_text", "neb_nl", "neb_code", "neb_can", "neb_path", "neb_n"),
    "output_accumulator": ("append", "snapshot", "finish", "oa_append_bytes", "oa_append_trunc", "oa_append_lines", "oa_append_last", "oa_append_n", "oa_snap_bytes", "oa_snap_trunc", "oa_snap_lines", "oa_snap_total", "oa_snap_n", "oa_fin_bytes", "oa_fin_fffd", "oa_fin_last", "oa_fin_trunc", "oa_fin_n", "last_line_bytes", "needs_file", "close_temp_file"),
    "find_tool": ("pattern_match", "find_files", "make_tool", "fpm_star_a", "fpm_star_src", "fpm_star_txt", "fpm_path_src", "fpm_path_root", "fpm_src_star", "fpm_n", "ff_empty", "ff_lisp", "ff_path", "ff_src_star", "ff_n", "fmt_name", "fmt_desc", "fmt_req", "fmt_n", "glob_regex", "glob_special", "gitignore_regex", "glob_scanner", "glob_regex_body", "parse_gitignore_line", "gsc_star", "gsc_miss", "gsc_glob", "gsc_q", "gsc_dot", "grb_star", "grb_glob", "grb_q", "grb_dot", "pgl_empty", "pgl_hash", "pgl_foo", "pgl_bang", "pgl_scan", "ignored_directory", "gitignored", "make_glob_tool", "igd_git", "igd_nm", "igd_src", "igd_hub", "igd_slash", "gig_empty", "gig_hit", "gig_miss", "gig_bang", "gig_out", "mgt_name", "mgt_desc", "mgt_req", "mgt_par", "mgt_n"),
    "grep_tool": ("match_event", "line_text", "make_tool", "read_utf8", "file_lines", "context_block"),
    "write_tool": ("ensure_parent", "write_utf8", "make_tool"),
    "ls_tool": ("directory_entry_name", "list_directory", "make_tool", "lden_file", "lden_dir", "lden_nested", "lden_n", "ld_empty", "ld_mixed", "ld_first", "ld_limit", "ld_n", "lst_name", "lst_desc", "lst_req", "lst_n"),
    "tool_manager": ("get_tool_path", "ensure_tool", "cleanup_quarantine", "gtp_local_fd", "gtp_local_rg", "gtp_miss_fd", "gtp_miss_rg", "gtp_n", "et_local_fd", "et_offline_miss", "et_n", "cq_removed", "cq_noop", "cq_n", "release_asset", "find_binary", "quarantine_native"),
    "powershell_tool": ("utf8_prefix", "prefix_command", "make_tool", "psu_len", "psu_nl", "psu_try", "psu_utf8", "psu_n", "psc_empty", "psc_date", "psc_write", "psc_n", "pmt_name", "pmt_desc", "pmt_req", "pmt_n"),
    "settings_load": ("project_trust", "config_value", "http_idle", "stored_auth_secrets", "config_paths", "tr_empty", "tr_proj", "rs_empty", "rs_ask", "rs_always", "rs_never", "rs_ov_yes", "rs_ov_no", "cv_lit", "cv_dol", "cv_brace", "cv_esc", "cv_bang", "cv_miss", "cv_mix", "cv_cmd", "ht_30", "ht_1m", "ht_2m", "ht_5m", "ht_off", "sas_missing", "sas_fixture", "sas_oauth", "sas_bad", "sas_fixture_key", "sas_oauth_access", "sas_oauth_refresh", "cp_auth_eq", "cp_cfg_eq", "cp_same_p", "cp_auth_leaf", "cp_cfg_leaf", "provider_symbol", "parse_auth_provider", "split_command_line", "environment_value", "configured_provider_name", "provider_settings", "provider_default_model", "oauth_refresh_function", "oauth_login_function", "sdk_nonempty", "sdk_boolean", "sdk_tools"),
    "resource_loader": ("reload", "dedupe_by_name", "skill_count", "prompt_count", "skill_names", "prompt_names", "skill_from_project", "prompt_from_project", "context_file_count", "system_prompt", "dbn_skill_count", "dbn_skill_collisions", "dbn_skill_project", "dbn_prompt_count", "dbn_prompt_collisions", "dbn_prompt_project", "context_from_dir", "project_context", "nearest_config"),
    "package_manager": ("resolve", "manifest_parse", "package_source", "package_count", "skill_count", "prompt_count", "theme_count", "extension_count", "manifest_p", "manifest_extensions", "manifest_skills", "manifest_prompts", "manifest_themes", "ps_npm_pin", "ps_npm_rng", "ps_git", "ps_git_pin", "ps_local", "ps_ref_ok", "ps_git_id", "ps_ded_n", "ps_ded_proj", "normalize_pattern", "resource_kinds", "type_label", "resource_file_p", "resource_display_name", "settings_array", "resource_specification", "config_glob_regex", "entry_target", "autoload_disabled", "package_entry_filter", "item_matches", "resource_key", "relative_pattern", "config_fit_line", "group_less_p", "package_entry_has_filters", "find_item_index", "selected_entry", "selector_move", "visible_range", "item_ordinal", "replace_pattern", "scope_base", "selector_items", "item_source_base", "package_resource_pattern", "package_override_source", "resource_group_label", "settings_values", "pattern_candidates", "pattern_matches", "enabled_by_patterns", "delta_resource_state", "project_top_level_state", "derived_project_state", "rfp_lisp", "rfp_case", "rfp_miss", "rfp_skill", "rfp_n", "rdn_skill", "rdn_lisp", "rdn_md", "rdn_json", "rdn_n", "csa_vec", "csa_list", "csa_miss", "csa_bad", "csa_n", "rsp_ext", "rsp_sk", "rsp_rel", "rsp_miss", "rsp_n", "cgr_star", "cgr_q", "cgr_plain", "cgr_dot", "cgr_n", "cet_bang", "cet_plus", "cet_minus", "cet_plain", "cet_empty", "cet_n", "ad_nil", "ad_true", "ad_miss", "ad_notht", "ad_n", "pef_vec", "pef_list", "pef_miss", "pef_bad", "pef_n", "im_empty", "im_name", "im_path", "im_type", "im_miss", "im_n", "crk_ext", "crk_sk", "crk_pr", "crk_th", "crk_n", "rel_file", "rel_nested", "rel_ext", "rel_plain", "rel_n", "cfl_short", "cfl_long", "cfl_dots", "cfl_zero", "cfl_n", "gl_pkg", "gl_user", "gl_src", "gl_rev", "gl_n", "hf_ext", "hf_miss", "hf_sk", "hf_other", "hf_n", "fi_fwd", "fi_skip", "fi_back", "fi_end", "fi_n", "se_item", "se_group", "se_sub", "se_last", "se_n", "sm_fwd", "sm_skip", "sm_back", "sm_end", "sm_n", "vr_small", "vr_mid", "vr_top", "vr_bot", "vr_n", "io_group", "io_first", "io_second", "io_sub", "io_n", "rp_drop", "rp_load", "rp_unload", "rp_keep", "rp_n", "sb_global", "sb_proj", "sb_nested", "sb_slash", "sb_n", "si_global", "si_proj", "si_empty", "si_copy", "si_n", "isb_global", "isb_proj", "isb_user", "isb_diff", "isb_n", "prp_file", "prp_nested", "prp_ext", "prp_plain", "prp_n", "pos_npm", "pos_rel", "pos_same", "pos_pin", "pos_n", "rgl_pkg", "rgl_user", "rgl_proj", "rgl_cadr", "rgl_n", "csv_ok", "csv_proj", "csv_nums", "csv_bad", "csv_n", "cpc_plain", "cpc_abs", "cpc_skill", "cpc_hello", "cpc_n", "cpm_lisp", "cpm_miss", "cpm_exact", "cpm_q", "cpm_n", "ebp_def", "ebp_inc", "ebp_exc", "ebp_load", "ebp_n", "update_argv", "update_env", "git_object_id"),
    "session_discovery": ("header_probe", "session_list_probe", "file_count", "header_count", "found", "session_id", "most_recent_name", "list_count", "list_id", "list_most_recent_name", "empty_count"),
    "session_export_html": ("to_html", "has_accent", "theme"),
    "protocol_cbor": ("roundtrip", "vector_count", "roundtrip_hex", "match"),
    "agent_schema": ("validate_ok_fail", "ok", "fail", "tool"),
    "harness_storage": ("open_walk", "entry_count", "leaf_id", "ingested_entry_count", "session_id", "source_leaf_id"),
    "protocol_codec": ("roundtrip", "frame_bytes", "message_count", "type", "id", "command"),
    "agent_proxy": ("stream_roundtrip", "event_count", "text", "usage_total"),
    "oauth_pkce": ("challenge_urls", "challenge", "openai_has_challenge", "anthropic_has_challenge", "openai_prefix", "anthropic_prefix"),
    "oauth_pkce_device": ("poll", "auth_json", "copilot_url", "cloudflare_url", "radius_gateway", "copilot_auth", "percent_decode", "parse_query", "parse_authorization_input", "provider_key", "http_status_text", "parse_callback_request", "base64url_value", "base64url_decode", "account_id", "dc_ok", "dc_fail", "dc_cancel", "ak_ok", "ak_len", "oa_ok", "oa_len", "auth_miss", "auth_bad", "gc_def", "gc_ind", "gc_ent", "gc_dom", "cf_plain", "cf_ok", "cf_gw", "rg_slash", "rg_plain", "rg_http", "ga_def", "ga_ind", "ga_ent", "ga_dom", "ga_key", "pd_plain", "pd_plus", "pd_slash", "pd_space", "pd_utf8", "pd_n", "pq_code", "pq_state", "pq_plus", "pq_empty", "pq_n", "pai_url", "pai_hash", "pai_qs", "pai_plain", "pai_n", "bv_A", "bv_a", "bv_0", "bv_dash", "bv_us", "bv_n", "bd_obj", "bd_foo", "bd_acct", "bd_n", "aid_ok", "aid_miss", "aid_bad", "aid_n", "error_detail", "ensure_success", "notify_device", "json_copy", "interval_seconds", "device_start", "openrouter_input", "openrouter_refresh", "openrouter_exchange", "anth_oauth_name", "anth_oauth_sub", "anth_oauth_instructions", "kimi_host_default", "kimi_host_code", "kimi_host_trim"),
    "cli_extensions_install": ("llama_url", "hf_token", "llama_catalog", "extension_discovery", "nu_local", "nu_https", "nu_file", "inf_ok", "fb_b", "fb_k", "hf_env", "hf_path", "hf_home", "hf_miss", "hf_blank", "lc_n", "lc_img", "lc_ctx", "lc_url", "lc_sleep", "lc_fb", "ed_n", "ed_err", "ed_coll", "ed_cli", "ed_proj", "ed_glob", "ed_probe", "ed_miss", "split_command", "handle_plain", "handle_unknown", "unsafe_git", "git_path", "normalize_git", "package_fragment", "local_system_name", "inline_factory", "gated_approval", "split_args", "quant_label", "llama_context_label", "llama_model_description", "llama_compact_count"),
    "evals_harness": ("summarize", "group_key", "artifact_persist", "format", "normalize_steps", "resolve_selection", "transcript", "last_assistant", "step_value", "usage", "result_json", "eval_environment", "prompt_step", "reload_step", "make_eval_root", "normalize_step_type", "selected_eval_tools", "prompt_eval_agent", "reload_shutdown", "run_coding_agent_eval", "eval_sets", "comparisons", "candidate_wins", "ties", "gk_id", "gk_trim", "art_ok", "art_bad", "ap_n", "ap_sess", "ap_src", "ap_sess_prefix", "ap_src_prefix", "ap_sess_file", "ap_src_file", "fmt_empty", "fmt_empty_hdr", "fmt_hdr", "fmt_base", "fmt_pass", "ns_empty", "ns_str_n", "ns_str_pr", "ns_seq_n", "ns_seq_rel", "ns_kw_n", "ns_kw_rel", "ns_vec_n", "ns_bad", "rs_explicit", "rs_env", "rs_miss", "rs_prov", "rs_blank", "rs_n", "tr_n", "tr_user", "tr_role", "tr_text", "tr_call", "tr_name", "tr_result", "tr_err", "tr_keys", "la_new", "la_none", "la_full", "la_n", "ct_plain", "ct_join", "ct_empty", "ct_blank", "ct_n", "te_type", "te_role", "te_content", "te_asst_role", "te_asst", "te_n", "el_now", "el_past", "el_order", "el_n", "release_extensions", "agent_tools", "extension_paths", "argument_prefix", "parse_arguments", "validate_smoke", "eval_result", "root_observer", "model_resolver", "status_name", "case_observation", "finish", "eval_layout", "system_prompt", "output_selector", "make_reporter", "finite_number", "artifact_metadata", "extension_authoring_input", "json_array_items", "json_string", "canonical_api", "legacy_api", "extension_error_json", "required_prompt_boundary", "exclude_guidelines", "prepare_default_prompt", "reporter_run_id", "artifact_reference_json", "reporter_artifacts", "validate_extension", "suite_dispatch", "eval_result_p", "sca_def", "sca_pkg", "sca_case", "sca_miss", "sca_leg", "sla_mz", "sla_tb", "sla_pi", "sla_case", "sla_miss", "see_path", "see_err", "see_empty", "see_blank", "see_n", "rpb_mid", "rpb_end", "rpb_zero", "rpb_miss", "rpb_n", "egd_cut", "egd_len", "egd_no_g", "egd_head", "egd_n", "pdp_cut", "pdp_dbl", "pdp_no_cwd", "pdp_keep", "pdp_n", "rid_hit", "rid_empty", "rid_custom", "rid_gen", "rid_n", "arj_name", "arj_path", "arj_empty", "arj_keys", "arj_n", "ra_empty", "ra_sess", "ra_rec", "ra_case", "ra_n", "ve_ok", "ve_greet", "ve_paths", "ve_empty", "ve_n", "sd_smoke", "sd_ext", "sd_auth", "sd_unk", "sd_n", "er_yes", "er_hash", "er_str", "er_nil", "er_n", "msg_content", "eval_tools", "eval_paths", "at_empty", "at_n", "at_read", "at_bash", "at_keys", "ep_none", "ep_n", "ep_path", "ep_skip", "ep_keys", "ai_crypto_model_data", "manifest", "schema_version", "structure_hash", "generated_at", "file_count", "openai_json_hash", "anthropic_json_hash", "rep_make", "fin_num", "art_meta", "mr_explicit", "mr_env", "mr_miss", "mr_n", "fn_int", "fn_float", "fn_nil", "fn_inf", "fn_str", "fn_n", "am_keep", "am_runid", "am_snap", "am_n"),
    "ai_crypto_model_data": ("manifest", "schema_version", "structure_hash", "generated_at", "file_count", "openai_json_hash", "anthropic_json_hash"),
    "ai_crypto": ("hmac", "fox", "empty", "long"),
    "cli_models_rest": ("pattern_match", "auth_command", "login_selection", "exact_id", "exact_provider", "bare_id", "partial_id", "scoped_id", "scoped_thinking", "miss", "ac_skip", "ac_api", "ac_api_prov", "ac_bearer", "ac_exp", "ac_check", "ac_json", "ac_cred", "ac_noref", "ac_chk_prov", "ac_min_api", "ac_unknown", "ac_help", "ac_help2", "ls_xai", "ls_nodef", "ls_defun", "ls_ok", "ls_fail", "ls_nomodels_sub", "ls_nodef_sub"),
    "image_runtime": ("dimensions", "mime_type", "lookup", "dimension_note", "api_provider", "output_modalities", "openrouter_content", "parse_data_image", "png_width", "png_height", "gif_width", "gif_height", "miss", "png_mime", "jpeg_mime", "gif_mime", "webp_mime", "miss_mime", "gemini", "flux", "unknown", "note_resized", "note_half", "note_plain", "api_fixture", "api_unknown", "om_gemini_n", "om_gemini_text", "om_flux_n", "om_flux_text", "oc_text_type", "oc_text", "oc_img_type", "oc_img_url", "oc_ok", "pd_ok_mime", "pd_ok_data", "pd_ok", "pd_miss", "pd_plain", "us_in", "us_out", "us_cr", "us_cw", "us_in2", "us_out2", "us_cr2", "us_cw2", "poi_id", "poi_text", "poi_n", "poi_mime", "poi_data", "poi_in", "poi_out", "er_auth", "er_hit", "er_abort", "er_flag", "er_prov", "openrouter_usage", "parse_openrouter_images", "error_result"),
    "cli_print_rpc": ("jsonl_line", "jsonl_read", "clamp_thinking", "session_stats", "line_chars", "newline", "payload", "line_count", "first", "second", "last_line", "tl_off", "tl_high", "tl_xh", "tl_max", "tl_xh_down", "tl_unk", "tl_full_n", "tl_short_n", "ss_user", "ss_asst", "ss_tool", "ss_calls", "ss_total", "ss_id", "rpc_images", "rpc_prompt", "bash_result", "queue_parse", "asst_text", "cmd_list", "dialog_request", "dialog_result", "dialog_expired", "queue_mode", "last_assistant", "command_list", "handle_bad_json", "handle_not_object", "handle_ui_miss", "bad_line", "array_line", "ui_absent"),
    "tui_latex": ("render", "normalize_output", "e_mc2", "frac_inline", "greek", "frac_display_newlines", "unknown_miss", "empty", "alpha", "frac", "script", "operator", "marker_edge"),
    "tui_mermaid": ("render", "source_box", "transform", "mm_lr_w", "mm_lr_first", "mm_lr_rows", "mm_empty", "mm_unk", "mm_cjk_w", "sb_wide_w", "sb_wide_first", "sb_narrow_rows", "sb_empty_w", "tf_ok", "tf_art", "tf_off", "tf_think", "tf_wide", "tf_len"),
    "tui_editor_helpers": ("fuzzy_match", "gpt", "id_suffix", "swapped", "miss", "empty"),
    "tui_theme_overlay": ("osc11_bg", "rgb_to_ansi_256", "parse_hex_color", "theme_foreground_ansi", "rgb_r", "rgb_g", "rgb_b", "hex6_r", "hex6_g", "hex6_b", "hex12_r", "miss", "scheme_dark"),
    "ai_support": ("estimate_text", "context_overflow", "grammar_delta", "uuid_v7", "auth_guidance", "threads_absent", "threads_current", "threads_joined", "empty", "hello", "block", "tha_eq", "tha_n", "thc_eq", "thc_n", "thj_eq", "thj_n", "prompt", "rate", "silent", "length", "d1", "d2", "d3", "started", "closed", "uuid_len", "uuid_hyphens", "uuid_version", "uuid_variant", "uuid_neq", "no_models", "no_selected", "no_key", "no_unknown", "has_login", "has_providers", "has_models"),
    "tui_select_settings_loaders": ("filter", "he_count", "he_first", "wo_count", "zz_count", "loader_frames", "loader_interval", "loader_step", "make_loader_component", "set_message", "set_indicator", "update_display", "make_cancellable_loader", "cancellation_token_aborted"),
    "tui_word_navigation": ("step", "back_from_space", "fwd_from_o", "back_start", "fwd_end"),
    "tui_overlay": ("composite_line", "line_chars", "visible_width", "has_reset"),
    "tui_kill_ring": ("push_peek", "empty_len", "ring_len", "peek_two", "peek_rot", "acc_append", "acc_prepend"),
    "tui_undo_stack": ("push_pop", "empty_len", "after_two", "pop_n", "after_pop", "clone_n", "after_clear"),
    "tui_autocomplete": ("suggest_apply", "slash_count", "slash_help", "slash_hello", "slash_prefix", "quote_count", "quote_first_len", "force_count", "force_hello", "force_help", "at_count", "apply_col", "apply_len"),
    "tui_keybindings": ("resolve_match", "left_count", "left_ctrl_b", "hist_count", "enter_submit", "tab_tab", "enter_undo", "conflict_count", "conflict_key_len"),
    "tui_stdin_buffer": ("process", "hello_count", "leftover", "up_len", "paste_len", "tail_count", "flush", "clear", "contents"),
    "tui_input_component": ("edit", "after_insert", "after_bs", "after_kill", "after_yank", "last_code"),
    "tui_native_modifiers": ("pressed", "shift", "control", "option", "command"),
    "tui_settings_list": ("apply_filter", "he_count", "he_hello", "he_help", "wo_count", "zz_count", "he_selected"),
    "ai_capabilities": ("short_hash", "deferred_tools", "event_stream", "http_proxy", "session_resources", "empty", "abc", "cjk", "off_imm", "off_def", "off_first", "off_second", "off_read", "on_imm", "on_def", "on_first", "on_second", "on_read", "ev_first", "ev_second", "ev_third", "ev_result", "px_hit", "px_star", "px_skip", "px_keep", "px_socks", "sr_first", "sr_n1", "sr_n2", "sr_err"),
    "cli_support": ("strip_ansi", "normalize_path", "timings", "event_bus", "attribution_headers", "shell_config", "sanitize_output", "git_source", "user_agent", "parse_changelog", "experimental", "csi_osc", "ris", "single", "plain", "trim", "at", "nbsp", "tilde", "file", "time_title", "time_boot", "time_load", "time_total", "eb_first", "eb_n1", "eb_n2", "eb_n3", "eb_throw", "at_or_ref", "at_or_title", "at_or_cat", "at_or_off", "at_nv", "at_cf", "at_oc_sess", "at_oc_client", "at_ov", "sh_def", "sh_arg", "sh_stdin", "sh_custom", "sh_carg", "sh_cstdin", "sh_miss", "sz_plain", "sz_ctl", "sz_tnr", "sz_fmt", "sz_esc", "gs_https_host", "gs_https_path", "gs_https_ref", "gs_https_pin", "gs_ssh_host", "gs_ssh_path", "gs_ssh_pin", "gs_short_host", "gs_short_path", "gs_bare", "gs_dotdot", "gs_abs", "ua_ver", "ua_paren", "ua_semi", "cl_n", "cl_first", "cl_hdr", "cl_second", "cl_miss", "ex_on", "ex_empty", "ex_zero", "ex_true", "ex_nil", "no_models_help", "no_model_selected", "no_api_key", "watch_retry_delay", "close_watcher", "watch_signature", "write_hello", "write_overwrite", "write_empty", "editor_success", "editor_fail", "editor_empty", "threads_absent", "threads_current", "threads_joined", "awh_hello", "awh_len", "awh_file", "awh_n", "awo_second", "awo_no_first", "awo_len", "awo_n", "awe_ok", "awe_len", "awe_file", "awe_n", "eed_hello", "eed_len", "eed_round", "eed_nonl", "eed_n", "eef_orig", "eef_empty", "eef_twice", "eef_n", "eee_ok", "eee_len", "eee_x", "eee_xlen", "eee_n", "cta_eq", "cta_n", "ctc_eq", "ctc_n", "ctj_eq", "ctj_n"),
    "cli_interactive_controller": ("decode_entity", "wayland", "cwd_footer", "auth_type", "parse_auto_theme", "resolve_theme", "amp", "lt", "gt", "quot", "apos", "hash65", "miss", "wl_disp", "wl_type", "wl_x11", "wl_none", "cf_home", "cf_proj", "cf_out", "cf_slash", "al_oauth", "al_key", "pat_valid", "pat_empty_left", "pat_empty_right", "pat_nil", "pat_double", "pat_fixed", "rts_auto_light", "rts_auto_dark", "rts_fixed", "rts_bad", "rts_nil", "make_entry", "append_output", "complete_entry", "sanitize_title", "title_basename", "terminal_title", "wrap_transcript", "output_padding", "render_cacheable", "tool_session_make", "tool_session_update", "tool_session_render", "theme_primitive", "theme_resolve", "theme_validate", "theme_object_overrides", "apply_tui_theme_summary", "load_tui_theme_file", "theme_prim", "theme_val", "theme_res", "bash_append_running", "bash_complete_string", "bash_stop_entry", "assistant_has_tools", "assistant_display_blocks", "transcript_summary_label", "transcript_summary_text", "assistant_stop_error", "update_notification_border", "theme_message_background", "update_notification_text", "syntax_highlight", "assistant_price_known", "accumulate_usage", "append_user_message", "seed_tui_message", "reset_tui_messages", "render_user_lines", "render_assistant_lines", "transform_tui_markdown", "render_transcript_summary", "render_assistant_blocks", "render_version_notification", "render_package_notification", "render_tui_entry_uncached", "render_tui_entry", "render_tui_entries", "should_use_tui", "tui_command_error", "route_tui_submission", "extension_dialog_chrome", "tui_component_protocol", "extension_render_value_lines", "make_framed_select_state", "note_component_render_channel", "tui_extension_theme_runtime", "make_extension_input_dialog", "make_extension_editor_dialog", "make_runtime_auth_input_state", "runtime_auth_input_handle_event", "render_runtime_auth_input", "render_extension_custom_entry", "render_framed_select_state", "framed_select_state_handle_event", "framed_select_state_handle_raw_input", "render_extension_custom_ui", "extension_custom_ui_handle_event", "render_tui_extension_overlay", "announcement_make", "announcement_url", "announcement_title", "eam_ok", "eam_min", "eam_n", "eau_eq", "eau_sold", "eau_n", "eat_eq", "eat_pi", "eat_n", "clipboard_candidates", "osc52_copy", "clipboard_copy", "colorfgbg_index", "rgb_background", "detect_background", "fit_footer_text", "footer_usage", "footer_git_paths", "framed_select_title", "extension_overlay_options", "extension_custom_ui_visible", "sess_make", "sess_upd", "sess_draw", "wrap_osc", "pad_str", "cache_p", "bash_run", "bash_fin", "bash_halt"),
    "cli_selectors": ("session_search", "session_format_age", "session_record_label", "session_shorten_path", "session_quoted_search", "session_thread_records", "session_binding_label", "session_same_path", "session_quoted_p", "session_named_p", "settings_thinking_description", "settings_display_value", "settings_automatic_theme_setting", "settings_active_automatic_theme", "settings_cycle", "settings_apply_filter", "tree_entry_filtered", "tree_query_matches", "tree_entry_search_text", "tree_settings_entry_p", "tree_normalize_display_text", "tree_status_labels", "tree_shorten_path", "tree_foldable_p", "tree_tool_argument", "tree_cycle_filter", "tree_format_label_timestamp", "tree_format_tool_call", "tree_entry_display_text", "tree_prefix", "tree_visual_nodes", "tree_horizontal_viewport", "tree_help_keys", "tree_help_key", "tree_app_key_p", "tree_help_lines", "tree_active_path", "tree_nearest_visible_id", "tree_prioritize_active", "tree_entry_map", "tree_order_entries", "tree_iso_timestamp", "tree_rebuild_visible_maps", "tree_apply_filter", "tree_render_lines", "tree_move", "tree_fold_or_up", "tree_unfold_or_down", "tree_branch_segment_id", "tree_set_query", "tree_set_filter", "tree_copy_selected", "tree_toggle_label_timestamps", "tree_start_label_edit", "tree_confirm_label", "tree_cancel_label", "tree_handle_raw_input", "tree_handle_event", "tree_handle_label_event", "tree_selected_entry", "tree_selected_id", "tree_select_id", "tree_visible_ids", "project_trust_options", "trust_selector_selection", "trust_decision_description", "trust_selector_move", "trust_selector_handle_event", "trust_selector_handle_raw_input", "trust_selector_ui_state", "oauth_option_status_label", "oauth_option_status_rendered", "credential_entry_auth_type", "oauth_environment_source_p", "oauth_selector_selection", "oauth_selector_apply_filter", "oauth_selector_handle_event", "oauth_selector_handle_raw_input", "oauth_selector_search_text", "login_auth_type_route", "latxxx_ok", "login_provider_options", "lpoxxx_ok", "logout_provider_options", "lgoxxx_ok", "login_method_selector_handle_event", "oauth_selector_move", "api_key_input_state_handle_event", "login_method_selector_ui_state", "api_key_input_ui_state", "oauth_selector_ui_state", "model_selector_search_text", "qualified_model_id", "model_selector_apply_filter", "model_selector_move", "model_selector_handle_event", "model_selector_handle_raw_input", "model_selector_set_query", "model_selector_selected_model", "model_selector_toggle_scope", "model_selector_ui_state", "scoped_models_selector_set_query", "scoped_models_selector_move", "scoped_models_selector_handle_event", "scoped_models_selector_handle_raw_input", "scoped_models_selector_ui_state", "scoped_models_selector_sorted_ids", "scoped_models_selector_counts", "scoped_models_selector_toggle_selected", "scoped_models_selector_target_ids", "scoped_models_selector_enable_all", "scoped_models_selector_toggle_provider", "scoped_models_selector_clear_all", "scoped_models_selector_reorder", "scoped_models_selector_persist", "scoped_models_selector_provider_count", "key_text", "fuzzy_filter", "delete_query", "visible_slice", "move_index", "align_left_right", "fit_line", "border_line", "selected_line", "muted_line", "dim_line", "modified_cursor_key", "title_line", "overlay_title_line", "input_line", "keybinding_text", "keybinding_hint", "ss_empty", "ss_hit", "ss_miss", "ss_re", "ss_badre", "ss_named", "kt_ctrl", "kt_slash", "kt_shift", "kt_cap", "kt_empty", "ff_empty", "ff_an", "ff_app", "ff_cl", "ff_slash", "dq_empty", "dq_a", "dq_abc", "dq_cafe", "dq_emoji", "dq_combining", "vs0", "vs0_end", "vs0_vis", "vs5", "vs5_vis", "vs20_mid", "vs20_mid_vis", "vs20_top", "vs20_bot", "vs20_bot_vis", "vs3_vis", "mi_empty", "mi_wrap_up", "mi_wrap_dn", "mi_fwd", "mi_back", "mi_big", "alr_wide", "alr_trunc_left", "alr_trunc_right", "alr_narrow", "alr_empty_left", "alr_empty_right", "fl_short", "fl_trunc", "fl_pad", "fl_ellipsis", "fl_wide", "fl_empty", "bl_w40", "bl_w40_acc", "bl_w1", "bl_w80", "bl_w10_acc", "bl_w20", "sl_short", "sl_trunc", "sl_wide", "sl_empty", "sl_pad20", "sl_narrow", "ml_short", "ml_trunc", "ml_wide", "ml_empty", "ml_item20", "ml_narrow", "dl_short", "dl_trunc", "dl_wide", "dl_empty", "dl_item20", "dl_narrow", "mck_up", "mck_shift_dn", "mck_ctrl_rt", "mck_alt_lt", "mck_ctrl_shift_up", "mck_super_dn", "tl_short", "tl_trunc", "tl_empty", "tl_wide", "tl_narrow", "tl_normal", "otl_short", "otl_trunc", "otl_empty", "otl_wide", "otl_narrow", "otl_normal", "il_empty", "il_short", "il_ab12", "il_grapheme", "il_narrow", "il_scroll", "kbt_confirm", "kbt_cancel", "kbt_left", "kbt_empty", "kbt_custom_confirm", "kbt_custom_cancel", "kbh_confirm", "kbh_cancel", "kbh_left", "kbh_empty", "kbh_custom_save", "kbh_custom_cancel", "sfa_now", "sfa_sec", "sfa_min", "sfa_hour", "sfa_day", "sfa_week", "srl_named", "srl_first", "srl_empty", "srl_ctrl", "srl_name_ctrl", "ssp_home", "ssp_prefix", "ssp_abs", "ssp_proj", "ssp_empty", "sqs_cadr", "sqs_phrase", "sqs_miss", "sqs_other_miss", "sqs_name", "sqs_other_hit", "str_count", "str_depths", "str_ids", "sbl_confirm", "sbl_delete", "sbl_noninvasive", "sbl_fallback", "sbl_custom", "ssp_same", "ssp_diff", "ssp_nil_left", "ssp_nil_right", "ssp_nil_both", "sqp_phrase", "sqp_words", "sqp_plain", "sqp_empty", "sqp_one", "sqp_open", "snp_named", "snp_whitespace", "snp_empty", "snp_nil", "std_off", "std_minimal", "std_low", "std_medium", "std_high", "std_xhigh", "std_max", "std_unknown", "sdv_true", "sdv_false", "sdv_symbol", "sdv_int", "sdv_string", "sats_solarized", "sats_same", "sats_light_dark", "saat_light_term", "saat_dark_term", "saat_light_pair", "ssc_true", "ssc_transport", "ssc_wrap", "ssc_missing", "sap_empty", "sap_trans", "sap_none", "sap_app", "tef_user_def", "tef_label_def", "tef_user_uo", "tef_tool_nt", "tef_labeled_lo", "tef_all_label", "tqm_hit", "tqm_miss", "tqm_multi", "tqm_partial", "tqm_empty", "tese_sparse", "tese_label", "tese_empty", "tese_full", "tese_text", "tsep_label", "tsep_user", "tsep_custom", "tsep_model", "tsep_think", "tsep_session", "tnd_hello", "tnd_spaced", "tnd_newline", "tnd_empty", "tnd_ws", "tsl_empty", "tsl_notools", "tsl_user", "tsl_labeled", "tsl_all", "tsl_time", "tsl_both", "tsp_home", "tsp_prefix", "tsp_abs", "tsp_proj", "tsp_empty", "tfp_root", "tfp_leaf", "tfp_only_child", "tfp_branch", "tta_path", "tta_file", "tta_prio", "tta_miss", "tta_nil", "tcf_def_fwd", "tcf_nt_back", "tcf_all_fwd", "tcf_user_fwd", "09:07", "3/28 14:32", "25/12/31 23:59", "07:30", "tvn_single", "tvn_branch", "tvn_multi", "tvn_chain", "tvn_deep", "thv_short", "thv_scroll", "thv_narrow", "thv_noselect", "thv_ansi", "thk_move", "thk_page", "thk_branch", "thk_copy", "thk_filters", "thk_cycle", "thk_custom", "thl_w80", "thl_w50", "thl_w30", "thl_w20", "thl_w12", "tap_leaf", "tap_mid", "tap_root", "tap_nil", "tap_missing", "tnvi_hit", "tnvi_ancestor", "tnvi_branch", "tnvi_fallback", "tnvi_missing", "tnvi_nil", "tpa_leaf_a", "tpa_leaf_b", "tpa_root", "tpa_nil", "pto_child", "pto_single", "tss_child_trust", "tss_child_parent", "tss_child_distrust", "tss_single_trust", "tss_single_distrust", "tdd_none", "tdd_child_local", "tdd_child_inherited", "tdd_single_untrusted", "tsm_child_down", "tsm_child_up", "tsm_child_wrap_up", "tsm_child_wrap_down", "tsm_child_page", "tsm_single_down", "tsm_single_wrap", "tshe_child_down", "tshe_child_up", "tshe_child_enter", "tshe_child_k", "tshe_child_bad", "tshe_child_esc", "tshe_child_nop", "tshri_child_down", "tshri_child_k", "tshri_child_enter", "tshri_child_esc", "tshri_child_bad", "tshri_child_j", "tshri_child_confirm", "rts_child_default", "rts_child_saved", "rts_child_inherited", "rts_child_distrust", "rts_single", "oosl_none", "oosl_api_mismatch", "oosl_oauth_mismatch", "oosl_oauth_configured", "oosl_stored", "oosl_env", "oosl_custom", "oosr_none", "oosr_api_mismatch", "oosr_oauth_mismatch", "oosr_oauth_configured", "oosr_stored", "oosr_env", "oosr_custom", "ceat_oauth", "ceat_api_key", "ceat_api_key_hyphen", "ceat_oauth_sym", "ceat_api_key_sym", "ceat_oauth_mixed", "ceat_api_key_upper", "oesp_nil", "oesp_oauth", "oesp_single_env", "oesp_multi_env", "oesp_runtime", "oesp_stored", "oesp_lower", "oss_first", "oss_second", "oss_third", "oss_filter_hit", "oss_filter_miss", "osaf_all", "osaf_open", "osaf_miss", "osaf_anth", "osaf_google", "oshe_down", "oshe_up", "oshe_enter", "oshe_esc", "oshe_text", "oshe_backspace", "oshri_down", "oshri_j", "oshri_enter", "oshri_esc", "oshri_bad", "oshri_o", "oshri_confirm", "osst_oauth", "osst_api", "osst_no_method", "osst_api_plain", "latr_none", "latr_oauth", "latr_api", "latr_both", "latr_generic", "lpo_all", "lpo_oauth", "lpo_api", "lpo_labeled", "lpo_status", "lgo_empty", "lgo_mixed", "lgo_unknown", "lgo_sorted", "lmhe_down", "lmhe_up", "lmhe_enter_oauth", "lmhe_enter_api", "lmhe_esc", "lmhe_clear", "lmhe_interrupt", "osmv_0_1", "osmv_2_m1", "osmv_1_1", "osmv_1_m1", "osmv_filter", "akhe_esc", "akhe_clear", "akhe_text", "akhe_bs", "akhe_enter_empty", "akhe_enter_key", "akhe_interrupt", "lmsui_default", "lmsui_sel1", "lmsui_title", "lmsui_narrow", "lmsui_mid", "akiui_empty", "akiui_key", "akiui_openai", "akiui_narrow", "akiui_long", "osui_default", "osui_sel2", "osui_filter", "osui_miss", "osui_logout_empty", "msst_openai", "msst_anthropic", "msst_codex", "msst_openrouter", "msst_google", "qmid_openai", "qmid_anthropic", "qmid_codex", "qmid_openrouter", "qmid_google", "msaf_all", "msaf_gpt", "msaf_miss", "msaf_anth", "msaf_google", "msmv_0_1", "msmv_2_m1", "msmv_1_1", "msmv_1_m1", "msmv_filter", "mshe_down", "mshe_up", "mshe_enter", "mshe_esc", "mshe_text", "mshe_bs", "mshri_down", "mshri_j", "mshri_esc", "mshri_bad", "mshri_o", "mshri_confirm", "mshri_up", "mssq_clear", "mssq_gpt", "mssq_same", "mssq_reset", "mssq_miss", "mssm_0", "mssm_1", "mssm_3", "mssm_gpt0", "mssm_gpt2", "mssm_miss", "mssm_oob", "msts_all", "msts_scoped", "msts_gpt", "msts_none", "msts_anth", "msui_default", "msui_sel2", "msui_scoped", "msui_filter", "msui_miss", "msui_error", "msui_refresh", "smssq_clear", "smssq_gpt", "smssq_same", "smssq_reset", "smssq_miss", "smsmv_0_1", "smsmv_2_m1", "smsmv_1_1", "smsmv_1_m1", "smsmv_filter", "smshe_down", "smshe_up", "smshe_enter", "smshe_esc", "smshe_text", "smshe_bs", "smsri_down", "smsri_j", "smsri_esc", "smsri_bad", "smsri_o", "smsri_confirm", "smsri_up", "smsui_default", "smsui_sel2", "smsui_partial", "smsui_filter", "smsui_miss", "smsui_refresh", "smsui_dirty", "smssi_all", "smssi_partial", "smssi_single", "smssi_empty", "smssi_reorder", "smstg_all_0", "smstg_partial_off", "smstg_partial_on", "smstg_retoggle", "smstg_filter", "smstg_miss", "smsti_all", "smsti_gpt", "smsti_nope", "smsti_claude", "smsti_partial", "smsea_all", "smsea_partial", "smsea_empty", "smsea_two", "smsea_filter", "smsea_miss", "smstgp_all_0", "smstgp_partial_off", "smstgp_partial_on", "smstgp_retoggle", "smstgp_filter", "smstgp_miss", "smsca_all", "smsca_partial", "smsca_empty", "smsca_two", "smsca_filter", "smsca_miss", "smsror_down", "smsror_up", "smsror_noop", "smsror_empty", "smsror_filter", "smsror_miss", "smsper_all", "smsper_partial", "smsper_no_cb", "smsper_empty", "smsper_two", "smsper_single", "smsprv_all", "smsprv_partial", "smsprv_unavail", "smsprv_empty", "smsprv_single", "armin_pixel", "armin_cell", "armin_grid_height", "user_message_make", "user_message_move", "user_message_selection", "login_dialog_make", "login_dialog_auth", "login_dialog_device", "thinking_level_label", "thinking_level_search_text", "lstxxx_ok", "thinking_selector_set_query", "daxnuts_parse_image", "daxnuts_image_line", "daxnuts_center_line", "countdown_seconds", "countdown_tick", "countdown_render", "model_selector_provider_badge", "scoped_models_copy_enabled", "move_list_item", "session_scoped_models", "scoped_model_id_enabled_p", "scoped_models_toggle_id", "all_known_model_ids_enabled_p", "scoped_models_enable_ids", "scoped_models_clear_ids", "scoped_models_enabled_set", "model_equal_p", "scoped_model_selector_search_text", "model_selector_active_models", "model_selector_clamp_selected", "model_selector_select_current", "sort_model_selector_models", "model_selector_visible_models", "model_selector_visible_slice", "model_selector_rebuild_search_text_table", "model_selector_filter_search_text", "model_selector_finish_refresh", "scoped_models_selector_rebuild_models_by_id", "scoped_models_model_by_id", "scoped_model_item_search_text", "scoped_models_selector_items", "scoped_models_selector_cancel", "scoped_models_selector_selected_item", "scoped_models_selector_select_id", "scoped_models_selector_notify_change", "scoped_models_selector_rebuild_items", "scoped_models_selector_apply_filter", "scoped_models_selector_visible_items", "scoped_models_selector_refresh_items", "scoped_models_selector_clamp_selected", "scoped_models_selector_mark_changed", "scoped_models_selector_finish_refresh", "scoped_models_selector_key_p", "scoped_models_binding_label", "model_selector_key_p", "model_selector_keybindings", "make_model_selector_state", "thinking_selector_key_p", "thinking_selector_keybindings", "make_thinking_selector_state", "mtsxxx_ok", "thinking_selector_apply_filter", "thinking_selector_clamp_selected", "thinking_selector_select_current", "thafxxx_ok", "thclxxx_ok", "thscxxx_ok", "thinking_selector_move", "thinking_selector_handle_raw_input", "thinking_selector_handle_event", "henxxx_ok", "thmvxxx_ok", "thhrxxx_ok", "thhexxx_ok", "thinking_selector_selected_level", "thinking_level_description_line", "render_thinking_selector", "trust_option_saved_p", "make_trust_selector_state", "render_trust_selector", "trsvxxx_ok", "trmkxxx_ok", "trrsxxx_ok", "make_login_method_selector_state", "make_api_key_input_state", "make_oauth_selector_state", "lmsxxxx_ok", "akixxxx_ok", "ossxxxx_ok", "login_dialog_show_waiting", "login_dialog_show_progress", "login_dialog_show_manual_input", "ldwxxx_ok", "ldpxxx_ok", "ldmixxx_ok", "login_dialog_show_prompt", "login_dialog_show_info", "login_dialog_show_details", "ldprxxx_ok", "ldixxx_ok", "lddtxxx_ok", "login_dialog_complete_input", "login_dialog_handle_event", "render_login_dialog", "ldcixxx_ok", "ldhexxx_ok", "ldrdxxx_ok", "user_message_handle_event", "user_message_handle_raw", "render_user_message_selector", "umevxxx_ok", "umrwxxx_ok", "umrsxxx_ok", "make_models_selector_keybindings", "make_scoped_models_selector_state", "render_model_selector", "mkbxxx_ok", "msmsxxx_ok", "mrmsxxx_ok", "daxnuts_rgb_at", "make_daxnuts_component", "daxnuts_component_tick", "dlg_make", "dlg_auth", "dlg_dev"),
    "websocket_stream": ("stream_roundtrip", "ws_text", "stop_reason", "text_characters", "usage_input", "usage_output"),
    "cli_sdk": ("version_newer", "cache_miss", "cache_waste", "thinking_level", "session_list", "agent_session", "session_services", "model_runtime", "beta", "eq", "older", "newer_flag", "equal_flag", "cm_tok", "cm_idle", "cm_chg", "cm_hit", "sw_tok", "sw_idle", "sw_chg", "sw_hit", "healthy_hit", "empty_hit", "cw_tok", "cw_n", "cw_healthy", "cw_reset", "cw_sw_tok", "cw_sw_n", "cw_nocache", "tl_off", "tl_min", "tl_low", "tl_med", "tl_high", "tl_xhigh", "tl_max", "tl_miss", "sl_n", "sl_id", "sl_empty", "as_ok", "as_model", "as_fb", "ss_ok", "ss_cwd", "ss_snap", "mr_oa", "mr_an", "mr_missp", "mr_gpt", "mr_missm"),
    "provider_registry_defs": ("lookup", "definition_ids", "merge_environment", "runtime_models", "structured_api_key_login", "openai", "anthropic", "google", "unknown", "count", "sorted_digest", "me_oa", "me_gemini", "me_azure", "me_miss", "rm_openai", "rm_anthropic", "rm_google", "rm_unknown", "sl_openai", "sl_anthropic", "sl_google", "sl_bedrock", "sl_vertex", "api_key_strategy", "provider_options", "strip_runtime_options", "oauth_login_function", "oauth_refresh_function", "oauth_to_auth", "api_key_login_function", "api_key_auth", "model_filter_function", "runtime_provider", "runtime_provider_copilot", "models_runtime", "protocol_provider", "protocol_provider_anthropic", "instantiate_provider"),
    "skill_prompt_load": ("build_prompt", "custom_len", "append_len", "ctx_len", "has_cwd", "has_extra", "has_agents", "resolve_prompt", "node_read_error", "prompt_appends", "sdk_prompt_input", "sdk_list_override", "sdk_context_files"),
    "cli_bootstrap_sessions": ("coding_tools", "bootstrap_auth", "count", "baseline", "snippet_count", "read_first", "option_count", "auth_pairs_digest", "vertex_structured", "bedrock_structured", "session_path", "split_command", "path_argument", "legacy_product", "shell_quote", "affirmative", "model_cycle", "model_scope_line", "process_files", "parse_bash", "response_text", "dispatch_plain", "session_argument_path", "path_command_argument", "cycle_wrap", "scope_hint", "file_tags", "data_directory", "legacy_data_directory", "manual_migration_command", "managed_binary_names", "migration_guide_url", "extensions_doc_url"),
    "ai_runtime_faux": ("blocks", "text_len", "text", "think_len", "think"),
    "http_transport": ("parse_url", "https_scheme", "https_host", "https_path", "http_scheme", "http_host", "http_port", "http_path"),
    "core_rest": ("cancellation_abort", "redacted_secrets", "threads_cleanup", "cancellation_wait", "redacted_types", "threads_join", "ca_live", "ca_abort", "ca_clear", "ca_pred", "rd_keep", "rd_secret", "rd_token", "rd_mark", "th_absent", "th_current", "th_joined", "cancellation_make", "cancellation_aborted", "cancellation_set", "cancellation_predicate", "redacted_register", "redacted_replace"),
    "session_pipeline": ("session_load", "context_walk", "session_leaf_id", "entry_count", "leaf_id", "session_id", "session_name", "context_entry_count", "context_message_count", "context_thinking_level", "context_model"),
    "storage_journal": ("journal_read", "journal_append", "journal_entry_count", "read_file_entry_count", "append_entry_count", "session_entry_count", "written_file_entry_count"),
    "sqlite_session": ("open_walk", "entry_count", "leaf_id", "ingested_entry_count", "session_id", "source_leaf_id"),
    "tool_read": ("text_file", "line_count", "output_chars", "truncated"),
    "tool_grep": ("context_file", "match_limit", "output_chars", "truncated"),
    "agent_tool_loop": ("roundtrip", "tool_path", "line_ending", "tool_result_digest", "runtime", "final_text", "message_count", "tool_error", "tool_value", "tp_rel", "tp_abs", "tp_at", "tp_nbsp", "tp_parent", "le_lf", "le_crlf", "le_none", "le_empty", "trd_short", "trd_exact", "trd_over", "trd_over_one", "trd_utf16", "trd_empty", "rt_steer_len", "rt_follow_len", "rt_drain_steer_a", "rt_drain_steer1_n", "rt_steer_remain1", "rt_drain_steer_b", "rt_steer_empty", "rt_drain_steer_all_n", "rt_drain_follow_c", "rt_follow_remain1", "rt_drain_follow_d", "rt_follow_empty", "rt_clear_steer_n", "rt_clear_follow_n", "rt_snap_steer_empty", "rt_snap_follow_empty"),
    "session_compact": ("compact", "branch_summarize", "prepare_branch_entries", "compacted", "first_kept", "summary_chars", "summarized", "entry_count", "branch_summary_chars", "prepared", "message_count", "total_tokens", "read_file_count", "modified_file_count"),
    "text_truncation": ("truncate_head", "truncate_tail", "truncate_middle", "content_bytes", "head_output_lines", "head_output_bytes", "head_truncated_by", "head_first_line_exceeds", "tail_output_lines", "tail_output_bytes", "tail_truncated_by", "tail_last_line_partial", "middle_output_lines", "middle_output_bytes", "middle_truncated_by", "middle_omitted_lines", "middle_first_line_exceeds"),
    "render_slicing": ("slice_ansi_clip", "slice_plain_clip", "dense_clip_text", "dense_clip_width", "dense_head_text", "dense_head_width", "plain_clip_text", "plain_clip_width"),
    "edit_tool": ("normalize_line_endings", "restore_line_endings", "make_tool"),
}

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
    # cli_settings leftover trio 352-354 (samples=5): first-freeze headroom.
    # Ratchet down only.
    "cli_settings.default_model": 8.0,
    "cli_settings.default_provider": 8.0,
    "cli_settings.output_padding": 8.0,
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
    "oauth_pkce_device.provider_key": 8.0,
    "oauth_pkce_device.http_status_text": 8.0,
    "oauth_pkce_device.parse_callback_request": 8.0,
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
    # evals_harness leftover trio on harness.lisp (pairs 349-351):
    # first-freeze headroom. Ratchet down only.
    "evals_harness.make_eval_root": 8.0,
    "evals_harness.normalize_step_type": 8.0,
    "evals_harness.selected_eval_tools": 8.0,
    # evals_harness leftover trio on harness.lisp (pairs 355-357).
    # prompt_eval_agent first freeze observed 10.47x (19.3 / 1.84 us);
    # 20.0 follows the session_compact / model_data headroom precedent.
    # reload_shutdown 1.87x and run_coding_agent_eval 7.98x keep 8.0.
    # Ratchet down only.
    "evals_harness.prompt_eval_agent": 20.0,
    "evals_harness.reload_shutdown": 8.0,
    "evals_harness.run_coding_agent_eval": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # ai_crypto_model_data pair (samples=5): observed 8.97x
    # (77.3 / 8.6 us). 20.0 follows the session_compact /
    # truncate_head headroom precedent. Ratchet down only.
        # Frozen from the first non-quick oauth_pkce_device leftover
    # trio on openai-anthropic.lisp (samples=5): first-freeze
    # headroom. Ratchet down only.
    "oauth_pkce_device.base64url_value": 8.0,
    "oauth_pkce_device.base64url_decode": 8.0,
    "oauth_pkce_device.account_id": 8.0,
    # evals_harness leftover trio 364-366 on harness.lisp (samples=5):
    # first-freeze headroom. Ratchet down only.
    "evals_harness.content_text": 8.0,
    "evals_harness.transcript_event": 8.0,
    "evals_harness.elapsed": 8.0,
    # Frozen from the first n=5 image_runtime.openrouter_usage leftover
    # pair: observed 4.218x (2.167 / 0.514 us). 8.0 is first-freeze
    # headroom. Ratchet down only.
    "image_runtime.openrouter_usage": 8.0,
    # Frozen from the first n=5 image_runtime.parse_openrouter_images leftover
    # pair: observed 2.986x (3.188 / 1.068 us). 8.0 is first-freeze
    # headroom. Ratchet down only.
    "image_runtime.parse_openrouter_images": 8.0,
    # Frozen from the first n=5 image_runtime.error_result leftover
    # pair: observed 3.028x (1.047 / 0.346 us). 8.0 is first-freeze
    # headroom. Ratchet down only.
    "image_runtime.error_result": 8.0,
    # core_rest leftover trio (samples=5): cancellation_make observed
    # 0.972x (0.2446 / 0.2518 us). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "core_rest.cancellation_make": 8.0,
    # core_rest.cancellation_aborted leftover pair (samples=5): observed
    # 0.0965x (0.6703 / 6.943 us). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "core_rest.cancellation_aborted": 8.0,
    # core_rest.cancellation_set leftover pair (samples=5): observed
    # 0.148x (0.5152 / 3.478 us). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "core_rest.cancellation_set": 8.0,
    "evals_harness.release_extensions": 8.0,
    "evals_harness.agent_tools": 8.0,
    "evals_harness.extension_paths": 8.0,
    # grep_tool leftover trio (samples=5): first-freeze headroom.
    # Ratchet down only.
    "grep_tool.match_event": 8.0,
    "grep_tool.line_text": 8.0,
    "grep_tool.make_tool": 8.0,
        # edit_tool leftover trio (samples=5): first-freeze headroom.
    # Ratchet down only.
    "edit_tool.normalize_line_endings": 8.0,
    "edit_tool.restore_line_endings": 8.0,
    "edit_tool.make_tool": 8.0,
    # evals_harness leftover trio on main.lisp (samples=5): first-freeze
    # headroom. Ratchet down only.
    "evals_harness.argument_prefix": 8.0,
    "evals_harness.parse_arguments": 8.0,
    "evals_harness.validate_smoke": 8.0,
    # resource_loader leftover trio (samples=5): first-freeze headroom.
    # Ratchet down only.
    "resource_loader.context_from_dir": 8.0,
    "resource_loader.project_context": 8.0,
    "resource_loader.nearest_config": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_select_settings_loaders leftover trio (samples=5):
    # first-freeze headroom 8.0. Ratchet down only.
    "tui_select_settings_loaders.loader_frames": 8.0,
    "tui_select_settings_loaders.loader_interval": 8.0,
    "tui_select_settings_loaders.loader_step": 8.0,
    "oauth_pkce_device.error_detail": 8.0,
    "oauth_pkce_device.ensure_success": 8.0,
    "oauth_pkce_device.notify_device": 8.0,
    # core_rest leftover trio (samples=5): cancellation_predicate observed
    # 0.106x (0.296 / 2.788 us). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "core_rest.cancellation_predicate": 8.0,
    # core_rest.redacted_register leftover pair (samples=5): observed
    # 0.698x (0.216 / 0.309 us). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "core_rest.redacted_register": 8.0,
    # core_rest.redacted_replace leftover pair (samples=5): observed
    # 3.383x (1.464 / 0.433 us). 8.0 is first-freeze headroom.
    # Ratchet down only.
    "core_rest.redacted_replace": 8.0,
    # evals_harness leftover seams on harness.lisp (samples=5): first-freeze
    # headroom. eval_result / root_observer / model_resolver (stub; not
    # default-eval-model-resolver). Ratchet down only.
    "evals_harness.eval_result": 8.0,
    "evals_harness.root_observer": 8.0,
    "evals_harness.model_resolver": 8.0,
    "execution_env.absolute_path": 8.0,
    "execution_env.join_path": 8.0,
    "execution_env.file_info": 8.0,
    # provider_registry_defs.api_key_strategy pair (samples=5): observed 0.417x
    # (0.114 / 0.274 µs). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "provider_registry_defs.api_key_strategy": 8.0,
    # provider_registry_defs.provider_options pair (samples=5): observed 1.697x
    # (0.560 / 0.330 µs). 8.0 is first-freeze headroom. Ratchet down only.
    "provider_registry_defs.provider_options": 8.0,
    # provider_registry_defs.strip_runtime_options pair (samples=5): observed 0.0627x
    # (0.134 / 2.131 µs). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "provider_registry_defs.strip_runtime_options": 8.0,
    # leftover 745–747 runtime-projection oauth (samples=5):
    # first-freeze headroom. Ratchet down only. Measure-only leftover 745–747.
    # leftover 745; first freeze 0.008× (0.121 / 15.704 µs).
    "provider_registry_defs.oauth_login_function": 8.0,
    # leftover 746; first freeze 0.008× (0.122 / 15.368 µs).
    "provider_registry_defs.oauth_refresh_function": 8.0,
    # leftover 747; first freeze 1.601× (0.428 / 0.267 µs).
    "provider_registry_defs.oauth_to_auth": 8.0,
    # leftover 748–750 runtime-projection api-key/filter (samples=5):
    # first-freeze headroom. Ratchet down only. Measure-only leftover 748–750.
    # leftover 748; first freeze 0.001× (0.174 / 212.888 µs). cadr leads.
    "provider_registry_defs.api_key_login_function": 8.0,
    # leftover 749; first freeze 0.003× (0.709 / 209.735 µs). cadr leads.
    "provider_registry_defs.api_key_auth": 8.0,
    # leftover 750; first freeze 0.003× (0.646 / 215.457 µs). cadr leads.
    "provider_registry_defs.model_filter_function": 8.0,
    # leftover 751–753 runtime-projection construct (samples=5):
    # first-freeze headroom. Ratchet down only. Measure-only leftover 751–753.
    "provider_registry_defs.runtime_provider": 8.0,
    "provider_registry_defs.runtime_provider_copilot": 8.0,
    "provider_registry_defs.models_runtime": 8.0,
    # leftover 754–756 registry protocol/instantiate (samples=5):
    # first-freeze headroom. Ratchet down only. Measure-only leftover 754–756.
    "provider_registry_defs.protocol_provider": 8.0,
    "provider_registry_defs.protocol_provider_anthropic": 8.0,
    "provider_registry_defs.instantiate_provider": 8.0,
    "tool_manager.release_asset": 8.0,
    "tool_manager.find_binary": 8.0,
    "tool_manager.quarantine_native": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_select_settings_loaders leftover trio 415-417 (samples=5):
    # first-freeze headroom 8.0. Ratchet down only.
    "tui_select_settings_loaders.make_loader_component": 8.0,
    "tui_select_settings_loaders.set_message": 8.0,
    "tui_select_settings_loaders.set_indicator": 8.0,
    "evals_harness.status_name": 8.0,
    "evals_harness.case_observation": 8.0,
    "evals_harness.finish": 8.0,
    "oauth_pkce_device.json_copy": 8.0,
    "oauth_pkce_device.interval_seconds": 8.0,
    "oauth_pkce_device.device_start": 8.0,
    # grep_tool leftover trio (samples=5): first-freeze headroom.
    # Ratchet down only. Not match_event / line_text / make_tool (PR #48).
    "grep_tool.read_utf8": 8.0,
    "grep_tool.file_lines": 8.0,
    "grep_tool.context_block": 8.0,
    # file_mutation_queue leftover trio (samples=5): first-freeze headroom.
    # Ratchet down only.
    "file_mutation_queue.waitqueue": 8.0,
    "file_mutation_queue.registry": 8.0,
    "file_mutation_queue.state_p": 8.0,
    "evals_harness.eval_layout": 8.0,
    "evals_harness.system_prompt": 8.0,
    "evals_harness.output_selector": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_select_settings_loaders leftover trio 433-435 (samples=5):
    # first-freeze headroom 8.0. Ratchet down only.
    "tui_select_settings_loaders.update_display": 8.0,
    "tui_select_settings_loaders.make_cancellable_loader": 8.0,
    "tui_select_settings_loaders.cancellation_token_aborted": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # oauth_pkce_device openrouter leftover trio (samples=5): first-freeze
    # headroom. Ratchet down only.
    "oauth_pkce_device.openrouter_input": 8.0,
    "oauth_pkce_device.openrouter_refresh": 8.0,
    "oauth_pkce_device.openrouter_exchange": 8.0,
    "oauth_pkce_device.anth_oauth_name": 8.0,
    "oauth_pkce_device.anth_oauth_sub": 8.0,
    "oauth_pkce_device.anth_oauth_instructions": 8.0,
    "oauth_pkce_device.kimi_host_default": 8.0,
    "oauth_pkce_device.kimi_host_code": 8.0,
    "oauth_pkce_device.kimi_host_trim": 8.0,
    # output_accumulator leftover trio (samples=5): first-freeze headroom.
    # Ratchet down only.
    "output_accumulator.last_line_bytes": 8.0,
    "output_accumulator.needs_file": 8.0,
    "output_accumulator.close_temp_file": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_stdin_buffer.flush leftover pair (samples=5): observed
    # 0.14x (0.392 / 2.818 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "tui_stdin_buffer.flush": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_stdin_buffer.clear leftover pair (samples=5): observed
    # 0.17x (0.710 / 4.129 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "tui_stdin_buffer.clear": 8.0,
    # Frozen from the first Friend-MachineD non-quick
    # tui_stdin_buffer.contents leftover pair (samples=5): observed
    # 0.15x (0.715 / 4.615 us). cadr leads. 8.0 is
    # first-freeze headroom. Ratchet down only.
    "tui_stdin_buffer.contents": 8.0,
    # evals_harness leftover trio on reporter.lisp (samples=5): first-freeze
    # default ceiling 8.0. Do not raise.
    "evals_harness.make_reporter": 8.0,
    "evals_harness.finite_number": 8.0,
    "evals_harness.artifact_metadata": 8.0,
    # evals_harness leftover trio on suites.lisp (samples=5): first-freeze
    # headroom. Ratchet down only.
    "evals_harness.extension_authoring_input": 8.0,
    "evals_harness.json_array_items": 8.0,
    "evals_harness.json_string": 8.0,
    # evals_harness leftover trio on suites.lisp (samples=5): first-freeze
    # headroom. Ratchet down only. Measure-only leftover 697–699.
    # leftover 697; first freeze 1.842× (0.944 / 0.512 µs).
    "evals_harness.canonical_api": 8.0,
    # leftover 698; first freeze 3.666× (1.903 / 0.519 µs).
    "evals_harness.legacy_api": 8.0,
    # leftover 699; first freeze 4.784× (0.860 / 0.180 µs).
    "evals_harness.extension_error_json": 8.0,
    # evals_harness leftover trio on suites.lisp (samples=5): first-freeze
    # headroom. Ratchet down only. Measure-only leftover 700–702.
    # leftover 700; first freeze 0.397× (0.852 / 2.148 µs). cadr leads.
    "evals_harness.required_prompt_boundary": 8.0,
    # leftover 701; first freeze 3.757× (0.742 / 0.197 µs).
    "evals_harness.exclude_guidelines": 8.0,
    # leftover 702; first freeze 6.700× (2.797 / 0.417 µs).
    "evals_harness.prepare_default_prompt": 8.0,
    # evals_harness leftover trio on reporter.lisp (samples=5): first-freeze
    # headroom. Ratchet down only. Measure-only leftover 703–705.
    # leftover 703; first freeze 2.941× (2.621 / 0.891 µs).
    "evals_harness.reporter_run_id": 8.0,
    # leftover 704; first freeze 5.883× (0.913 / 0.155 µs).
    "evals_harness.artifact_reference_json": 8.0,
    # leftover 705; first freeze 0.927× (1.620 / 1.747 µs). cadr leads.
    "evals_harness.reporter_artifacts": 8.0,
    # evals_harness leftover trio on main.lisp (samples=5): first-freeze
    # headroom. Ratchet down only. Measure-only leftover 925–927.
    # leftover 925; first freeze 7.979× (2.604 / 0.326 µs).
    "evals_harness.validate_extension": 8.0,
    # leftover 926; first freeze 0.874× (0.171 / 0.196 µs). cadr leads.
    "evals_harness.suite_dispatch": 8.0,
    # leftover 927; first freeze 1.836× (0.608 / 0.331 µs).
    "evals_harness.eval_result_p": 8.0,
    # evals_harness leftover trio on harness.lisp (samples=5): first-freeze
    # headroom. Ratchet down only. Measure-only leftover 928–930.
    # Does not remount content_text / agent_tools / extension_paths.
    # leftover 928; first freeze 1.352× (1.008 / 0.745 µs).
    "evals_harness.msg_content": 8.0,
    # leftover 929; first freeze 5.428× (1.547 / 0.285 µs).
    "evals_harness.eval_tools": 8.0,
    # leftover 930; first freeze 7.223× (3.230 / 0.447 µs).
    "evals_harness.eval_paths": 8.0,
    # Measure-only leftover 952; first freeze 0.898× (0.367 / 0.409 µs).
    # Does not remount make_reporter / finite_number / artifact_metadata.
    "evals_harness.rep_make": 8.0,
    # Measure-only leftover 953; first freeze 0.563× (0.126 / 0.224 µs).
    "evals_harness.fin_num": 8.0,
    # Measure-only leftover 954; first freeze 1.181× (1.038 / 0.879 µs).
    "evals_harness.art_meta": 8.0,
    # package_manager leftover trio on config-selector.lisp (samples=5):
    # first-freeze headroom. Ratchet down only.
    "package_manager.normalize_pattern": 8.0,
    "package_manager.resource_kinds": 8.0,
    "package_manager.type_label": 8.0,
    # package_manager leftover trio on config-selector.lisp (samples=5):
    # first-freeze headroom. Ratchet down only. Measure-only leftover 706–708.
    # leftover 706; first freeze 6.124× (10.973 / 1.792 µs).
    "package_manager.resource_file_p": 8.0,
    # leftover 707; first freeze 33.631× (15.082 / 0.448 µs).
    # First-freeze headroom; ratchet down only after a non-quick Friend-MachineD freeze.
    "package_manager.resource_display_name": 60.0,
    # leftover 708; first freeze 2.393× (1.161 / 0.485 µs).
    "package_manager.settings_array": 8.0,
    # package_manager leftover trio on config-selector.lisp (samples=5):
    # first-freeze headroom. Ratchet down only. Measure-only leftover 709–711.
    # leftover 709; first freeze 0.190× (0.428 / 2.249 µs). cadr leads.
    "package_manager.resource_specification": 8.0,
    # leftover 710; first freeze 0.546× (0.900 / 1.648 µs). cadr leads.
    "package_manager.config_glob_regex": 8.0,
    # leftover 711; first freeze 0.893× (0.277 / 0.310 µs). cadr leads.
    "package_manager.entry_target": 8.0,
    # package_manager leftover trio on config-selector.lisp (samples=5):
    # first-freeze headroom. Ratchet down only. Measure-only leftover 712–714.
    # leftover 712; first freeze 2.181× (0.758 / 0.347 µs).
    "package_manager.autoload_disabled": 8.0,
    # leftover 713; first freeze 1.788× (1.074 / 0.600 µs).
    "package_manager.package_entry_filter": 8.0,
    # leftover 714; first freeze 11.092× (10.553 / 0.951 µs).
    # First-freeze headroom; ratchet down only after a non-quick Friend-MachineD freeze.
    "package_manager.item_matches": 20.0,
    # package_manager leftover trio on config-selector.lisp (samples=5):
    # first-freeze headroom. Ratchet down only. Measure-only leftover 715–717.
    # leftover 715; first freeze 11.643× (2.758 / 0.237 µs).
    # First-freeze headroom; ratchet down only after a non-quick Friend-MachineD freeze.
    "package_manager.resource_key": 20.0,
    # leftover 716; first freeze 17.574× (15.709 / 0.894 µs).
    # First-freeze headroom; ratchet down only after a non-quick Friend-MachineD freeze.
    "package_manager.relative_pattern": 30.0,
    # leftover 717; first freeze 2.793× (5.200 / 1.862 µs).
    "package_manager.config_fit_line": 8.0,
    # package_manager leftover trio on config-selector.lisp (samples=5):
    # first-freeze headroom. Ratchet down only. Measure-only leftover 718–720.
    # leftover 718; first freeze 7.128× (3.937 / 0.552 µs).
    "package_manager.group_less_p": 8.0,
    # leftover 719; first freeze 1.804× (1.379 / 0.765 µs).
    "package_manager.package_entry_has_filters": 8.0,
    # leftover 720; first freeze 0.569× (0.242 / 0.426 µs). cadr leads.
    "package_manager.find_item_index": 8.0,
    # package_manager leftover trio on config-selector.lisp (samples=5):
    # first-freeze headroom. Ratchet down only. Measure-only leftover 721–723.
    # leftover 721; first freeze 1.195× (0.968 / 0.810 µs).
    "package_manager.selected_entry": 8.0,
    # leftover 722; first freeze 0.896× (1.069 / 1.193 µs). cadr leads.
    "package_manager.selector_move": 8.0,
    # leftover 723; first freeze 0.542× (1.898 / 3.504 µs). cadr leads.
    "package_manager.visible_range": 8.0,
    # package_manager leftover trio on config-selector.lisp (samples=5):
    # first-freeze headroom. Ratchet down only. Measure-only leftover 724–726.
    # leftover 724; first freeze 0.835× (1.077 / 1.289 µs). cadr leads.
    "package_manager.item_ordinal": 8.0,
    # leftover 725; first freeze 0.716× (0.629 / 0.879 µs). cadr leads.
    "package_manager.replace_pattern": 8.0,
    # leftover 726; first freeze 30.489× (16.512 / 0.542 µs).
    "package_manager.scope_base": 50.0,
    # package_manager leftover trio on config-selector.lisp (samples=5):
    # first-freeze headroom. Ratchet down only. Measure-only leftover 727–729.
    # leftover 727; first freeze 22.378× (10.768 / 0.481 µs).
    "package_manager.selector_items": 40.0,
    # leftover 728; first freeze 28.506× (16.439 / 0.577 µs).
    "package_manager.item_source_base": 50.0,
    # leftover 729; first freeze 13.804× (15.247 / 1.105 µs).
    "package_manager.package_resource_pattern": 20.0,
    # package_manager leftover trio on config-selector.lisp (samples=5):
    # first-freeze headroom. Ratchet down only. Measure-only leftover 730–732.
    # leftover 730; first freeze 12.402× (18.871 / 1.522 µs).
    "package_manager.package_override_source": 20.0,
    # leftover 731; first freeze 31.609× (17.081 / 0.540 µs).
    "package_manager.resource_group_label": 50.0,
    # leftover 732; first freeze 6.444× (5.209 / 0.808 µs).
    "package_manager.settings_values": 8.0,
    # package_manager leftover trio on config-selector.lisp (samples=5):
    # first-freeze headroom. Ratchet down only. Measure-only leftover 733–735.
    # leftover 733; first freeze 5.911× (15.875 / 2.686 µs).
    "package_manager.pattern_candidates": 8.0,
    # leftover 734; first freeze 7.155× (32.598 / 4.556 µs).
    "package_manager.pattern_matches": 8.0,
    # leftover 735; first freeze 4.820× (31.989 / 6.637 µs).
    "package_manager.enabled_by_patterns": 8.0,
    # package_manager leftover trio on config-selector.lisp (samples=5):
    # first-freeze headroom. Ratchet down only. Measure-only leftover 736–738.
    # leftover 736; first freeze 3.946× (17.140 / 4.344 µs).
    "package_manager.delta_resource_state": 8.0,
    # leftover 737; first freeze 5.971× (31.215 / 5.227 µs).
    "package_manager.project_top_level_state": 8.0,
    # leftover 738; first freeze 6.210× (31.710 / 5.107 µs).
    "package_manager.derived_project_state": 8.0,
    # package_manager leftover trio on update-checks.lisp (samples=5):
    # first-freeze headroom. Ratchet down only.
    "package_manager.update_argv": 8.0,
    "package_manager.update_env": 8.0,
    "package_manager.git_object_id": 8.0,
    # find_tool leftover trio on glob.lisp (samples=5): first-freeze
    # headroom. Ratchet down only.
    "find_tool.glob_regex": 8.0,
    "find_tool.glob_special": 8.0,
    "find_tool.gitignore_regex": 8.0,
    # find_tool leftover trio on glob.lisp (samples=5): first-freeze
    # headroom. Ratchet down only. Measure-only leftover 688–690.
    # leftover 688; first freeze 11.176× (10.624 / 0.951 µs).
    # First-freeze headroom; ratchet down only after a non-quick Friend-MachineD freeze.
    "find_tool.glob_scanner": 20.0,
    # leftover 689; first freeze 1.393× (0.580 / 0.417 µs).
    "find_tool.glob_regex_body": 8.0,
    # leftover 690; first freeze 5.556× (7.267 / 1.308 µs).
    "find_tool.parse_gitignore_line": 8.0,
    # find_tool leftover trio on glob.lisp (samples=5): first-freeze
    # headroom. Ratchet down only. Measure-only leftover 691–693.
    # leftover 691; first freeze 8.621× (16.582 / 1.923 µs).
    "find_tool.ignored_directory": 16.0,
    # leftover 692; first freeze 10.286× (37.755 / 3.671 µs).
    "find_tool.gitignored": 20.0,
    # leftover 693; first freeze 701.525× (193.915 / 0.276 µs).
    # First-freeze headroom; ratchet down only after a non-quick Friend-MachineD freeze.
    "find_tool.make_glob_tool": 1200.0,
    # cli_bootstrap_sessions leftover trio on sessions.lisp (samples=5):
    # first-freeze headroom. Ratchet down only.
    "cli_bootstrap_sessions.session_path": 8.0,
    "cli_bootstrap_sessions.split_command": 8.0,
    "cli_bootstrap_sessions.path_argument": 8.0,
    "settings_load.provider_symbol": 8.0,
    "settings_load.parse_auth_provider": 8.0,
    "settings_load.split_command_line": 8.0,
    # settings_load leftover trio on config.lisp (samples=5):
    # first-freeze headroom. Ratchet down only. Measure-only leftover 739–741.
    # leftover 739; first freeze 1.090× (0.299 / 0.274 µs).
    "settings_load.environment_value": 8.0,
    # leftover 740; first freeze 0.760× (0.376 / 0.495 µs).
    "settings_load.configured_provider_name": 8.0,
    # leftover 741; first freeze 2.018× (1.333 / 0.661 µs).
    "settings_load.provider_settings": 8.0,
    # settings_load leftover trio on config.lisp (samples=5):
    # first-freeze headroom. Ratchet down only. Measure-only leftover 742–744.
    # leftover 742; first freeze 0.410× (0.970 / 2.367 µs).
    "settings_load.provider_default_model": 8.0,
    # leftover 743; first freeze 0.139× (0.346 / 2.498 µs).
    "settings_load.oauth_refresh_function": 8.0,
    # leftover 744; first freeze 1.057× (2.562 / 2.423 µs).
    "settings_load.oauth_login_function": 8.0,
    "cli_bootstrap_sessions.legacy_product": 8.0,
    "cli_bootstrap_sessions.shell_quote": 8.0,
    "cli_bootstrap_sessions.affirmative": 8.0,
    # leftover CLI wrappers over the same docs-dir strings as
    # ai_support.auth_guidance. First freeze observed 27.45x / 27.67x /
    # 27.48x. 50.0 matches that sibling. Ratchet down only.
    "cli_support.no_models_help": 50.0,
    "cli_support.no_model_selected": 50.0,
    "cli_support.no_api_key": 50.0,
    "cli_print_rpc.rpc_images": 8.0,
    "cli_print_rpc.rpc_prompt": 8.0,
    "cli_print_rpc.bash_result": 8.0,
    "cli_print_rpc.dialog_request": 8.0,
    "cli_print_rpc.dialog_result": 8.0,
    "cli_print_rpc.dialog_expired": 8.0,
    # settings_load SDK leftover trio (samples=5): observed
    # sdk_nonempty 3.32x (20.85 / 6.28 us), sdk_boolean 2.14x
    # (13.42 / 6.28 us), sdk_tools 2.04x (12.77 / 6.27 us).
    # 8.0 is first-freeze headroom. Ratchet down only.
    "settings_load.sdk_nonempty": 8.0,
    "settings_load.sdk_boolean": 8.0,
    "settings_load.sdk_tools": 8.0,
    # skill_prompt_load leftover trio (samples=5): observed
    # resolve_prompt 3.64x (16.88 / 4.64 us), node_read_error 3.12x
    # (10.04 / 3.22 us), prompt_appends 3.27x (6.31 / 1.93 us).
    # 8.0 is first-freeze headroom. Ratchet down only.
    "skill_prompt_load.resolve_prompt": 8.0,
    "skill_prompt_load.node_read_error": 8.0,
    "skill_prompt_load.prompt_appends": 8.0,
    # cli_print_rpc leftover trio (samples=5): observed
    # queue_mode 0.12x (0.32 / 2.72 us), last_assistant 0.71x
    # (0.28 / 0.40 us), command_list 4.15x (1.49 / 0.36 us).
    # 8.0 is first-freeze headroom. Ratchet down only.
    "cli_print_rpc.queue_mode": 8.0,
    "cli_print_rpc.last_assistant": 8.0,
    "cli_print_rpc.command_list": 8.0,
    # Measure-only leftover 934; first freeze 0.132× (0.337 / 2.547 µs).
    "cli_print_rpc.queue_parse": 8.0,
    # Measure-only leftover 935; first freeze 0.791× (0.293 / 0.370 µs).
    "cli_print_rpc.asst_text": 8.0,
    # Measure-only leftover 936; first freeze 4.603× (1.533 / 0.333 µs).
    "cli_print_rpc.cmd_list": 8.0,
    # skill_prompt_load leftover trio (samples=5): observed
    # sdk_prompt_input 4.32x (15.18 / 3.51 us), sdk_list_override
    # 0.36x (0.19 / 0.52 us), sdk_context_files 2.88x (7.56 / 2.62 us).
    # 8.0 is first-freeze headroom. Ratchet down only.
    "skill_prompt_load.sdk_prompt_input": 8.0,
    "skill_prompt_load.sdk_list_override": 8.0,
    "skill_prompt_load.sdk_context_files": 8.0,
    # Measure-only leftover 919-921; freeze pending.
    "skill_prompt_load.sdk_get_skills": 8.0,
    "skill_prompt_load.sdk_get_prompts": 8.0,
    "skill_prompt_load.sdk_get_themes": 8.0,
    # cli_support leftover trio (samples=5): observed
    # watch_retry_delay 0.67x (0.07 / 0.10 us), close_watcher 0.65x
    # (0.07 / 0.11 us), watch_signature 5.38x (12.17 / 2.26 us).
    # 8.0 is first-freeze headroom. Ratchet down only.
    "cli_support.watch_retry_delay": 8.0,
    "cli_support.close_watcher": 8.0,
    "cli_support.watch_signature": 8.0,
    "cli_support.write_hello": 8.0,
    "cli_support.write_overwrite": 8.0,
    "cli_support.write_empty": 15.0,
    "cli_support.editor_success": 8.0,
    "cli_support.editor_fail": 8.0,
    "cli_support.editor_empty": 8.0,
    "cli_support.threads_absent": 8.0,
    "cli_support.threads_current": 8.0,
    "cli_support.threads_joined": 8.0,
    # Leftover trio on src/cadr-cli/bootstrap/commands.lisp (pairs 484-486):
    # model_cycle 0.622x (0.632 / 1.017 us), model_scope_line 1.608x
    # (37.431 / 23.274 us), process_files 0.419x (61.164 / 146.148 us).
    # 8.0 is first-freeze headroom. Ratchet down only.
    "cli_bootstrap_sessions.model_cycle": 8.0,
    "cli_bootstrap_sessions.model_scope_line": 8.0,
    "cli_bootstrap_sessions.process_files": 8.0,
    # Measure-only leftover 940; first freeze 0.745× (0.655 / 0.879 µs).
    "cli_bootstrap_sessions.cycle_wrap": 8.0,
    # Measure-only leftover 941; first freeze 0.838× (35.665 / 42.573 µs).
    "cli_bootstrap_sessions.scope_hint": 8.0,
    # Measure-only leftover 942; first freeze 0.556× (80.505 / 144.830 µs).
    "cli_bootstrap_sessions.file_tags": 8.0,
    # Leftover trio on src/cadr-cli/extensions/commands.lisp (pairs 487-489):
    # split_command 0.282x (0.465 / 1.652 us), handle_plain 0.449x
    # (0.344 / 0.766 us), handle_unknown 0.561x (0.474 / 0.845 us).
    # 8.0 is first-freeze headroom. Ratchet down only.
    "cli_extensions_install.split_command": 8.0,
    "cli_extensions_install.handle_plain": 8.0,
    "cli_extensions_install.handle_unknown": 8.0,
    # cli_bootstrap_sessions.parse_bash leftover (samples=5): observed 0.421x
    # (0.528 / 1.252 us). 8.0 is first-freeze headroom. Ratchet down only.
    "cli_bootstrap_sessions.parse_bash": 8.0,
    # cli_bootstrap_sessions.response_text leftover (samples=5): observed 1.314x
    # (0.939 / 0.714 us). 8.0 is first-freeze headroom. Ratchet down only.
    "cli_bootstrap_sessions.response_text": 8.0,
    # cli_bootstrap_sessions.dispatch_plain leftover (samples=5): observed 0.446x
    # (0.543 / 1.216 us). 8.0 is first-freeze headroom. Ratchet down only.
    "cli_bootstrap_sessions.dispatch_plain": 8.0,
    # cli_interactive_controller.make_entry leftover (samples=5): observed 5.982x
    # (1.424 / 0.238 us). 8.0 is first-freeze headroom. Ratchet down only.
    "cli_interactive_controller.make_entry": 8.0,
    # cli_interactive_controller.append_output leftover (samples=5): observed 2.670x
    # (0.776 / 0.290 us). 8.0 is first-freeze headroom. Ratchet down only.
    "cli_interactive_controller.append_output": 8.0,
    # cli_interactive_controller.complete_entry leftover (samples=5): observed 2.411x
    # (0.974 / 0.404 us). 8.0 is first-freeze headroom. Ratchet down only.
    "cli_interactive_controller.complete_entry": 8.0,
    # Frozen from the first Friend-MachineD leftover
    # cli_print_rpc.handle_bad_json pair (samples=5): observed
    # 1.092x (5.390 / 4.937 us). 8.0 is first-freeze headroom.
    # Ratchet down only.
    "cli_print_rpc.handle_bad_json": 8.0,
    # Frozen from the first Friend-MachineD leftover
    # cli_print_rpc.handle_not_object pair (samples=5): observed
    # 1.066x (5.213 / 4.889 us). 8.0 is first-freeze headroom.
    # Ratchet down only.
    "cli_print_rpc.handle_not_object": 8.0,
    # Frozen from the first Friend-MachineD leftover
    # cli_print_rpc.handle_ui_miss pair (samples=5): observed
    # 4.070x (6.190 / 1.521 us). 8.0 is first-freeze headroom.
    # Ratchet down only.
    "cli_print_rpc.handle_ui_miss": 8.0,
    # Measure-only leftover 937; first freeze 1.262× (5.686 / 4.505 µs).
    "cli_print_rpc.bad_line": 8.0,
    # Measure-only leftover 938; first freeze 1.474× (5.528 / 3.750 µs).
    "cli_print_rpc.array_line": 8.0,
    # Measure-only leftover 939; first freeze 4.202× (6.543 / 1.557 µs).
    "cli_print_rpc.ui_absent": 8.0,
    # Frozen from the first Friend-MachineD leftover
    # cli_extensions_install.unsafe_git pair (samples=5): observed
    # 1.159x (0.762 / 0.658 us). 8.0 is first-freeze headroom.
    # Ratchet down only.
    "cli_extensions_install.unsafe_git": 8.0,
    # Frozen from the first Friend-MachineD leftover
    # cli_extensions_install.git_path pair (samples=5): observed
    # 1.852x (1.055 / 0.569 us). 8.0 is first-freeze headroom.
    # Ratchet down only.
    "cli_extensions_install.git_path": 8.0,
    # Frozen from the first Friend-MachineD leftover
    # cli_extensions_install.normalize_git pair (samples=5): observed
    # 0.369x (4.884 / 13.233 us). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "cli_extensions_install.normalize_git": 8.0,
    # Frozen from the first Friend-MachineD leftover
    # cli_extensions_install.package_fragment pair (samples=5): observed
    # 0.351x (0.468 / 1.334 us). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "cli_extensions_install.package_fragment": 8.0,
    # Frozen from the first Friend-MachineD leftover
    # cli_extensions_install.local_system_name pair (samples=5): observed
    # 0.273x (0.192 / 0.704 us). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "cli_extensions_install.local_system_name": 8.0,
    # Frozen from the first Friend-MachineD leftover
    # cli_extensions_install.inline_factory pair (samples=5): observed
    # 0.260x (0.188 / 0.725 us). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "cli_extensions_install.inline_factory": 8.0,
    # Frozen from the first Friend-MachineD leftover
    # cli_extensions_install.gated_approval pair (samples=5): observed
    # 0.579x (0.120 / 0.208 us). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "cli_extensions_install.gated_approval": 8.0,
    # Frozen from the first Friend-MachineD leftover
    # cli_extensions_install.split_args pair (samples=5): observed
    # 0.408x (0.827 / 2.025 us). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "cli_extensions_install.split_args": 8.0,
    # Frozen from the first Friend-MachineD leftover
    # cli_extensions_install.quant_label pair (samples=5): observed
    # 1.249x (1.033 / 0.827 us). pi leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "cli_extensions_install.quant_label": 8.0,
    # Frozen from the first Friend-MachineD leftover
    # bash_tool.live_output pair (samples=5): observed
    # 0.479x (0.105 / 0.218 us). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "bash_tool.live_output": 8.0,
    # Frozen from the first Friend-MachineD leftover
    # bash_tool.strip_status pair (samples=5): observed
    # 0.773x (0.417 / 0.540 us). cadr leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "bash_tool.strip_status": 8.0,
    # Frozen from the first Friend-MachineD leftover
    # bash_tool.strip_truncation pair (samples=5): observed
    # 5.885x (2.331 / 0.396 us). pi leads. 8.0 is first-freeze
    # headroom. Ratchet down only.
    "bash_tool.strip_truncation": 8.0,
    # bash_tool leftover trio on bash.lisp (samples=5): first-freeze
    # headroom. Ratchet down only. Measure-only leftover 694–696.
    "bash_tool.process_deadline": 8.0,
    # leftover 694; first freeze 0.272× (0.124 / 0.457 µs). cadr leads.
    "bash_tool.user_bash_result": 8.0,
    # leftover 695; first freeze 2.070× (2.616 / 1.264 µs).
    "bash_tool.normalized_extension": 8.0,
    # First-freeze headroom for leftover
    # cli_interactive_controller.sanitize_title.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.sanitize_title": 8.0,
    # First-freeze headroom for leftover
    # cli_interactive_controller.title_basename.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.title_basename": 8.0,
    # First-freeze headroom for leftover
    # cli_interactive_controller.terminal_title.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.terminal_title": 8.0,
    # First-freeze headroom for leftover cli_selectors.armin_pixel.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.armin_pixel": 8.0,
    # First-freeze headroom for leftover cli_selectors.armin_cell.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.armin_cell": 8.0,
    # First-freeze headroom for leftover cli_selectors.armin_grid_height.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.armin_grid_height": 8.0,
    # First-freeze headroom for leftover cli_interactive_controller.wrap_transcript.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.wrap_transcript": 8.0,
    # First-freeze headroom for leftover cli_interactive_controller.output_padding.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.output_padding": 8.0,
    # First-freeze headroom for leftover cli_interactive_controller.render_cacheable.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.render_cacheable": 8.0,
    # First-freeze headroom for leftover cli_interactive_controller.tool_session_make.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.tool_session_make": 8.0,
    # First-freeze headroom for leftover cli_interactive_controller.tool_session_update.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.tool_session_update": 8.0,
    # First-freeze headroom for leftover cli_interactive_controller.tool_session_render.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.tool_session_render": 8.0,
    # First-freeze headroom for leftover cli_interactive_controller.theme_primitive.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.theme_primitive": 8.0,
    # First-freeze headroom for leftover cli_interactive_controller.theme_resolve.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.theme_resolve": 8.0,
    # First-freeze headroom for leftover cli_interactive_controller.theme_validate.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.theme_validate": 8.0,
    # Measure-only leftover 637; first freeze 0.651× (22.839 / 35.090 µs).
    "cli_interactive_controller.theme_object_overrides": 8.0,
    # Measure-only leftover 638; first freeze 3.211× (52.489 / 16.348 µs).
    "cli_interactive_controller.apply_tui_theme_summary": 8.0,
    # Measure-only leftover 639; first freeze 2.383× (233.265 / 97.883 µs).
    "cli_interactive_controller.load_tui_theme_file": 8.0,
    # Measure-only leftover 931; first freeze 0.741× (0.110 / 0.149 µs).
    "cli_interactive_controller.theme_prim": 8.0,
    # Measure-only leftover 932; first freeze 0.756× (19.713 / 26.066 µs).
    "cli_interactive_controller.theme_val": 8.0,
    # Measure-only leftover 933; first freeze 0.144× (1.192 / 8.261 µs).
    "cli_interactive_controller.theme_res": 8.0,
    # Measure-only leftover 943; first freeze 1.130× (0.244 / 0.216 µs).
    # Does not remount tool_session_make / tool_session_update / tool_session_render.
    "cli_interactive_controller.sess_make": 8.0,
    # Measure-only leftover 944; first freeze 1.132× (0.257 / 0.227 µs).
    "cli_interactive_controller.sess_upd": 8.0,
    # Measure-only leftover 945; first freeze 0.842× (1.503 / 1.785 µs).
    "cli_interactive_controller.sess_draw": 8.0,
    # Measure-only leftover 949; first freeze 0.981× (0.583 / 0.594 µs).
    # Does not remount wrap_transcript / output_padding / render_cacheable.
    "cli_interactive_controller.wrap_osc": 8.0,
    # Measure-only leftover 950; first freeze 1.041× (0.215 / 0.206 µs).
    "cli_interactive_controller.pad_str": 8.0,
    # Measure-only leftover 951; first freeze 2.014× (1.264 / 0.627 µs).
    "cli_interactive_controller.cache_p": 8.0,
    # Measure-only leftover 955; first freeze 2.219× (0.807 / 0.363 µs).
    # Does not remount bash_append_running / bash_complete_string / bash_stop_entry.
    "cli_interactive_controller.bash_run": 8.0,
    # Measure-only leftover 956; first freeze 2.620× (0.785 / 0.300 µs).
    "cli_interactive_controller.bash_fin": 8.0,
    # Measure-only leftover 957; first freeze 2.872× (0.635 / 0.221 µs).
    "cli_interactive_controller.bash_halt": 8.0,
    # Measure-only leftover 640; first freeze 2.059× (0.735 / 0.357 µs).
    "cli_interactive_controller.bash_append_running": 8.0,
    # Measure-only leftover 641; first freeze 2.719× (0.745 / 0.274 µs).
    "cli_interactive_controller.bash_complete_string": 8.0,
    # Measure-only leftover 642; first freeze 2.843× (0.621 / 0.219 µs).
    "cli_interactive_controller.bash_stop_entry": 8.0,
    # Measure-only leftover 643; first freeze 1.160× (1.082 / 0.933 µs).
    "cli_interactive_controller.assistant_has_tools": 8.0,
    # Measure-only leftover 644; first freeze 0.686× (0.948 / 1.383 µs).
    "cli_interactive_controller.assistant_display_blocks": 8.0,
    # Measure-only leftover 645; first freeze 6.352× (12.217 / 1.923 µs).
    "cli_interactive_controller.transcript_summary_label": 8.0,
    # Measure-only leftover 646; first freeze 5.434× (8.866 / 1.632 µs).
    "cli_interactive_controller.transcript_summary_text": 8.0,
    # Measure-only leftover 647; first freeze 10.444× (24.257 / 2.323 µs).
    # First-freeze headroom; ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.assistant_stop_error": 20.0,
    # Measure-only leftover 648; first freeze 4.259× (6.319 / 1.484 µs).
    "cli_interactive_controller.update_notification_border": 8.0,
    # Measure-only leftover 649; first freeze 5.465× (8.586 / 1.571 µs).
    "cli_interactive_controller.theme_message_background": 8.0,
    # Measure-only leftover 650; first freeze 29.104× (59.152 / 2.032 µs).
    # First-freeze headroom; ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.update_notification_text": 50.0,
    # Measure-only leftover 651; first freeze 12.184× (13.174 / 1.081 µs).
    # First-freeze headroom; ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.syntax_highlight": 20.0,
    # Measure-only leftover 652; first freeze 0.240× (4.477 / 18.674 µs).
    "cli_interactive_controller.assistant_price_known": 8.0,
    # Measure-only leftover 653; first freeze 1.188× (0.775 / 0.652 µs).
    "cli_interactive_controller.accumulate_usage": 8.0,
    # Measure-only leftover 654; first freeze 4.205× (5.050 / 1.201 µs).
    "cli_interactive_controller.append_user_message": 8.0,
    # Measure-only leftover 655; first freeze 0.469× (4.095 / 8.722 µs).
    "cli_interactive_controller.seed_tui_message": 8.0,
    # Measure-only leftover 656; first freeze 1.296× (2.035 / 1.570 µs).
    "cli_interactive_controller.reset_tui_messages": 8.0,
    # Measure-only leftover 657; first freeze 2.567× (3.956 / 1.541 µs).
    "cli_interactive_controller.render_user_lines": 8.0,
    # Measure-only leftover 658; first freeze 2.730× (12.279 / 4.498 µs).
    "cli_interactive_controller.render_assistant_lines": 8.0,
    # Measure-only leftover 659; first freeze 1.485× (2.923 / 1.968 µs).
    "cli_interactive_controller.transform_tui_markdown": 8.0,
    # Measure-only leftover 660; first freeze 255.111× (786.501 / 3.083 µs).
    # First-freeze headroom; ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.render_transcript_summary": 400.0,
    # Measure-only leftover 661; first freeze 5.377× (54.605 / 10.156 µs).
    "cli_interactive_controller.render_assistant_blocks": 8.0,
    # Measure-only leftover 662; first freeze 69.400× (304.547 / 4.388 µs).
    # First-freeze headroom; ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.render_version_notification": 120.0,
    # Measure-only leftover 663; first freeze 52.727× (217.221 / 4.120 µs).
    # First-freeze headroom; ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.render_package_notification": 100.0,
    # Measure-only leftover 664; first freeze 27.525× (200.288 / 7.276 µs).
    # First-freeze headroom; ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.render_tui_entry_uncached": 50.0,
    # Measure-only leftover 665; first freeze 17.083× (102.484 / 5.999 µs).
    # First-freeze headroom; ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.render_tui_entry": 30.0,
    # Measure-only leftover 666; first freeze 5.530× (42.711 / 7.723 µs).
    "cli_interactive_controller.render_tui_entries": 8.0,
    # Measure-only leftover 667; first freeze 0.199× (0.115 / 0.576 µs). cadr leads.
    "cli_interactive_controller.should_use_tui": 8.0,
    # Measure-only leftover 668; first freeze 0.069× (1.472 / 21.323 µs). cadr leads.
    "cli_interactive_controller.tui_command_error": 8.0,
    # Measure-only leftover 669; first freeze 0.360× (0.190 / 0.527 µs). cadr leads.
    "cli_interactive_controller.route_tui_submission": 8.0,
    # Measure-only leftover 670; first freeze 14.268× (21.804 / 1.528 µs).
    # First-freeze headroom; ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.extension_dialog_chrome": 30.0,
    # Measure-only leftover 671; first freeze 1.527× (0.587 / 0.384 µs).
    "cli_interactive_controller.tui_component_protocol": 8.0,
    # Measure-only leftover 672; first freeze 2.452× (2.505 / 1.022 µs).
    "cli_interactive_controller.extension_render_value_lines": 8.0,
    # Measure-only leftover 673; first freeze 1.037× (0.903 / 0.870 µs).
    "cli_interactive_controller.make_framed_select_state": 8.0,
    # Measure-only leftover 674; first freeze 1.278× (0.357 / 0.279 µs).
    "cli_interactive_controller.note_component_render_channel": 8.0,
    # Measure-only leftover 675; first freeze 3.379× (1.449 / 0.429 µs).
    "cli_interactive_controller.tui_extension_theme_runtime": 8.0,
    # Measure-only leftover 676; first freeze 1.099× (0.496 / 0.451 µs).
    "cli_interactive_controller.make_extension_input_dialog": 8.0,
    # Measure-only leftover 677; first freeze 4.545× (1.648 / 0.363 µs).
    "cli_interactive_controller.make_extension_editor_dialog": 8.0,
    # Measure-only leftover 678; first freeze 1.042× (0.459 / 0.441 µs).
    "cli_interactive_controller.make_runtime_auth_input_state": 8.0,
    # Measure-only leftover 679; first freeze 1.135× (1.040 / 0.916 µs).
    "cli_interactive_controller.runtime_auth_input_handle_event": 8.0,
    # Measure-only leftover 680; first freeze 56.286× (143.679 / 2.553 µs).
    # First-freeze headroom; ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.render_runtime_auth_input": 100.0,
    # Measure-only leftover 681; first freeze 2.800× (0.434 / 0.155 µs).
    "cli_interactive_controller.render_extension_custom_entry": 8.0,
    # Measure-only leftover 682; first freeze 101.599× (230.310 / 2.267 µs).
    # First-freeze headroom; ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.render_framed_select_state": 180.0,
    # Measure-only leftover 683; first freeze 1.252× (1.259 / 1.006 µs).
    "cli_interactive_controller.framed_select_state_handle_event": 8.0,
    # Measure-only leftover 684; first freeze 91.669× (87.360 / 0.953 µs).
    # First-freeze headroom; ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.framed_select_state_handle_raw_input": 160.0,
    # Measure-only leftover 685; first freeze 22.775× (32.260 / 1.416 µs).
    # First-freeze headroom; ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.render_extension_custom_ui": 40.0,
    # Measure-only leftover 686; first freeze 0.421× (0.344 / 0.818 µs). cadr leads.
    "cli_interactive_controller.extension_custom_ui_handle_event": 8.0,
    # Measure-only leftover 687; first freeze 88.995× (144.970 / 1.629 µs).
    # First-freeze headroom; ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.render_tui_extension_overlay": 160.0,
    "cli_interactive_controller.announcement_make": 8.0,
    "cli_interactive_controller.announcement_url": 8.0,
    "cli_interactive_controller.announcement_title": 8.0,
    # First-freeze headroom for leftover cli_selectors.user_message_make.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.user_message_make": 8.0,
    # First-freeze headroom for leftover cli_selectors.user_message_move.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.user_message_move": 8.0,
    # First-freeze headroom for leftover cli_selectors.user_message_selection.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.user_message_selection": 8.0,
    # First-freeze headroom for leftover cli_selectors.login_dialog_make.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.login_dialog_make": 8.0,
    # First-freeze headroom for leftover cli_selectors.login_dialog_auth.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.login_dialog_auth": 8.0,
    # First-freeze headroom for leftover cli_selectors.login_dialog_device.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.login_dialog_device": 8.0,
    # First-freeze headroom for leftover cli_selectors.thinking_level_label.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.thinking_level_label": 8.0,
    # First-freeze headroom for leftover cli_selectors.thinking_level_search_text.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.thinking_level_search_text": 8.0,
  # Measure-only leftover 1365; first freeze 1.577× (1.172 / 0.743 µs).
  "cli_selectors.lstxxx_ok": 8.0,
    # First-freeze headroom for leftover cli_selectors.thinking_selector_set_query.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_selectors.thinking_selector_set_query": 8.0,
    # First-freeze headroom for leftover cli_interactive_controller.clipboard_candidates.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.clipboard_candidates": 8.0,
    # First-freeze headroom for leftover cli_interactive_controller.osc52_copy.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.osc52_copy": 8.0,
    # First-freeze headroom for leftover cli_interactive_controller.clipboard_copy.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.clipboard_copy": 8.0,
    # First-freeze headroom for leftover cli_interactive_controller.colorfgbg_index.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.colorfgbg_index": 8.0,
    # First-freeze headroom for leftover cli_interactive_controller.rgb_background.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.rgb_background": 8.0,
    # First-freeze headroom for leftover cli_interactive_controller.detect_background.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.detect_background": 8.0,
    # First-freeze headroom for leftover cli_interactive_controller.fit_footer_text.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.fit_footer_text": 8.0,
    # First-freeze headroom for leftover cli_interactive_controller.footer_usage.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.footer_usage": 8.0,
    # First-freeze headroom for leftover cli_interactive_controller.footer_git_paths.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_interactive_controller.footer_git_paths": 8.0,
    # First-freeze headroom for leftover llama/ui.lisp helpers.
    # Ratchet down only after a non-quick Friend-MachineD freeze.
    "cli_extensions_install.llama_context_label": 8.0,
    "cli_extensions_install.llama_model_description": 8.0,
    "cli_extensions_install.llama_compact_count": 8.0,
  # First-freeze headroom for leftover daxnuts.lisp slugs (Pairs 547-549).
  "cli_selectors.daxnuts_parse_image": 8.0,
  "cli_selectors.daxnuts_image_line": 8.0,
  "cli_selectors.daxnuts_center_line": 8.0,
    # First-freeze headroom for leftover extension-ui.lisp slugs (Pairs 550-552).
    "cli_interactive_controller.framed_select_title": 8.0,
    "cli_interactive_controller.extension_overlay_options": 8.0,
    "cli_interactive_controller.extension_custom_ui_visible": 8.0,
    # cli_bootstrap_sessions.session_argument_path leftover 553 (samples=5):
    # observed 0.852x (0.371 / 0.436 us). 8.0 is first-freeze
    # headroom. Ratchet down only.
    "cli_bootstrap_sessions.session_argument_path": 8.0,
    # cli_bootstrap_sessions.path_command_argument leftover 555 (samples=5):
    # observed 0.802x (0.713 / 0.889 us). 8.0 is first-freeze
    # headroom. Ratchet down only.
    "cli_bootstrap_sessions.path_command_argument": 8.0,
  # cli_selectors.countdown_seconds leftover 556 (samples=5):
  # observed 2.292x (0.768 / 0.335 us). 8.0 is first-freeze
  # headroom. Ratchet down only.
  "cli_selectors.countdown_seconds": 8.0,
  # cli_selectors.countdown_tick leftover 557 (samples=5):
  # observed 3.006x (0.700 / 0.233 us). 8.0 is first-freeze
  # headroom. Ratchet down only.
  "cli_selectors.countdown_tick": 8.0,
  # cli_selectors.countdown_render leftover 558 (samples=5):
  # observed 1.928x (0.892 / 0.463 us). 8.0 is first-freeze
  # headroom. Ratchet down only.
  "cli_selectors.countdown_render": 8.0,
  # cli_selectors.model_selector_provider_badge leftover 559 (samples=5):
  # observed 0.307x (0.126 / 0.411 us). 8.0 is first-freeze
  # headroom. Ratchet down only.
  "cli_selectors.model_selector_provider_badge": 8.0,
  # cli_selectors.scoped_models_copy_enabled leftover 560 (samples=5):
  # observed 1.960x (1.074 / 0.548 us). 8.0 is first-freeze
  # headroom. Ratchet down only.
  "cli_selectors.scoped_models_copy_enabled": 8.0,
  # cli_selectors.move_list_item leftover 561 (samples=5):
  # observed 1.357x (1.317 / 0.971 us). 8.0 is first-freeze
  # headroom. Ratchet down only.
  "cli_selectors.move_list_item": 8.0,
  # cli_selectors.session_scoped_models leftover 562 (samples=5):
  # observed 2.563x (11.473 / 4.477 us). 8.0 is first-freeze
  # headroom. Ratchet down only.
  "cli_selectors.session_scoped_models": 8.0,
  # cli_selectors.scoped_model_id_enabled_p leftover 563 (samples=5):
  # observed 0.775x (0.167 / 0.215 us). 8.0 is first-freeze
  # headroom. Ratchet down only.
  "cli_selectors.scoped_model_id_enabled_p": 8.0,
  # cli_selectors.scoped_models_toggle_id leftover 564 (samples=5):
  # observed 1.191x (1.098 / 0.922 us). 8.0 is first-freeze
  # headroom. Ratchet down only.
  "cli_selectors.scoped_models_toggle_id": 8.0,
  # leftover 565 first freeze 2.035× (1.679 / 0.825 µs). 8.0 first-freeze
  # headroom. Ratchet down only.
  "cli_selectors.all_known_model_ids_enabled_p": 8.0,
  # leftover 566 first freeze 1.519× (2.605 / 1.715 µs). 8.0 first-freeze
  # headroom. Ratchet down only.
  "cli_selectors.scoped_models_enable_ids": 8.0,
  # leftover 567 first freeze 2.015× (2.931 / 1.455 µs). 8.0 first-freeze
  # headroom. Ratchet down only.
  "cli_selectors.scoped_models_clear_ids": 8.0,
  # leftover 568 first freeze 2.540× (2.709 / 1.067 µs). 8.0 first-freeze
  # headroom. Ratchet down only.
  "cli_selectors.scoped_models_enabled_set": 8.0,
  # leftover 569 first freeze 1.840× (0.458 / 0.249 µs). 8.0 first-freeze
  # headroom. Ratchet down only.
  "cli_selectors.model_equal_p": 8.0,
  # leftover 570 first freeze 8.503× (4.242 / 0.499 µs). 12.0 first-freeze
  # headroom. Ratchet down only.
  "cli_selectors.scoped_model_selector_search_text": 12.0,
  # leftover 571 first freeze 11.315× (20.408 / 1.804 µs). 15.0 first-freeze
  # headroom. Ratchet down only.
  "cli_selectors.model_selector_active_models": 15.0,
  # leftover 572 first freeze 4.015× (21.011 / 5.234 µs). 8.0 first-freeze
  # headroom. Ratchet down only.
  "cli_selectors.model_selector_clamp_selected": 8.0,
  # leftover 573 first freeze 43.943× (19.744 / 0.449 µs). 55.0 first-freeze
  # headroom. Ratchet down only.
  "cli_selectors.model_selector_select_current": 55.0,
  # Measure-only leftover 574; first freeze 2.928× (8.603 / 2.939 µs).
  "cli_selectors.sort_model_selector_models": 8.0,
  # Measure-only leftover 575; first freeze 1.879× (37.867 / 20.148 µs).
  "cli_selectors.model_selector_visible_models": 8.0,
  # Measure-only leftover 576; first freeze 2.710× (31.486 / 11.617 µs).
  "cli_selectors.model_selector_visible_slice": 8.0,
  # Measure-only leftover 577; first freeze 3.240× (16.001 / 4.939 µs).
  "cli_selectors.model_selector_rebuild_search_text_table": 8.0,
  # Measure-only leftover 578; first freeze 4.389× (13.376 / 3.048 µs).
  "cli_selectors.model_selector_filter_search_text": 8.0,
  # Measure-only leftover 579; first freeze 4.278× (46.658 / 10.907 µs).
  "cli_selectors.model_selector_finish_refresh": 8.0,
  # Measure-only leftover 580; first freeze 2.096× (10.000 / 4.771 µs).
  "cli_selectors.scoped_models_selector_rebuild_models_by_id": 8.0,
  # Measure-only leftover 581; first freeze 3.185× (9.193 / 2.886 µs).
  "cli_selectors.scoped_models_model_by_id": 8.0,
  # Measure-only leftover 582; first freeze 3.735× (2.879 / 0.771 µs).
  "cli_selectors.scoped_model_item_search_text": 8.0,
  # Measure-only leftover 584; first freeze 4.189× (26.959 / 6.435 µs).
  "cli_selectors.scoped_models_selector_items": 8.0,
  # Measure-only leftover 585; first freeze 1.746× (0.667 / 0.382 µs).
  "cli_selectors.scoped_models_selector_cancel": 8.0,
  # Measure-only leftover 586; first freeze 3.417× (26.636 / 7.796 µs).
  "cli_selectors.scoped_models_selector_selected_item": 8.0,
  # Measure-only leftover 587; first freeze 3.323× (26.954 / 8.112 µs).
  "cli_selectors.scoped_models_selector_select_id": 8.0,
  # Measure-only leftover 588; first freeze 1.745× (1.398 / 0.801 µs).
  "cli_selectors.scoped_models_selector_notify_change": 8.0,
  # Measure-only leftover 589; first freeze 4.448× (27.154 / 6.105 µs).
  "cli_selectors.scoped_models_selector_rebuild_items": 8.0,
  # Measure-only leftover 590; first freeze 1.464× (34.896 / 23.842 µs).
  "cli_selectors.scoped_models_selector_apply_filter": 8.0,
  # Measure-only leftover 591; first freeze 2.422× (32.039 / 13.230 µs).
  "cli_selectors.scoped_models_selector_visible_items": 8.0,
  # Measure-only leftover 592; first freeze 2.471× (33.511 / 13.561 µs).
  "cli_selectors.scoped_models_selector_refresh_items": 8.0,
  # Measure-only leftover 593; first freeze 2.365× (30.415 / 12.863 µs).
  "cli_selectors.scoped_models_selector_clamp_selected": 8.0,
  # Measure-only leftover 594; first freeze 1.359× (35.327 / 25.989 µs).
  "cli_selectors.scoped_models_selector_mark_changed": 8.0,
  # Measure-only leftover 595; first freeze 3.243× (68.310 / 21.063 µs).
  "cli_selectors.scoped_models_selector_finish_refresh": 8.0,
  # Measure-only leftover 596; first freeze 18.835× (22.914 / 1.217 µs).
  # 30.0 is first-freeze headroom. Ratchet down only.
  "cli_selectors.scoped_models_selector_key_p": 30.0,
  # Measure-only leftover 597; first freeze 16.362× (5.542 / 0.339 µs).
  # 25.0 is first-freeze headroom. Ratchet down only.
  "cli_selectors.scoped_models_binding_label": 25.0,
  # Measure-only leftover 598; first freeze 18.605× (16.140 / 0.868 µs).
  # 30.0 is first-freeze headroom. Ratchet down only.
  "cli_selectors.model_selector_key_p": 30.0,
  # Measure-only leftover 599; first freeze 8.076× (4.144 / 0.513 µs).
  # 12.0 is first-freeze headroom. Ratchet down only.
  "cli_selectors.model_selector_keybindings": 12.0,
  # Measure-only leftover 600; first freeze 3.037× (21.230 / 6.989 µs).
  "cli_selectors.make_model_selector_state": 8.0,
  # Measure-only leftover 601; first freeze 19.196× (15.469 / 0.806 µs).
  # 30.0 is first-freeze headroom. Ratchet down only.
  "cli_selectors.thinking_selector_key_p": 30.0,
  # Measure-only leftover 602; first freeze 5.685× (3.014 / 0.530 µs).
  "cli_selectors.thinking_selector_keybindings": 8.0,
  # Measure-only leftover 603; first freeze 0.638× (1.623 / 2.545 µs). cadr leads.
  "cli_selectors.make_thinking_selector_state": 8.0,
  # Measure-only leftover 1364; first freeze 0.775× (1.706 / 2.200 µs). cadr leads.
  "cli_selectors.mtsxxx_ok": 8.0,
  # Measure-only leftover 604; first freeze 1.149× (13.399 / 11.664 µs).
  "cli_selectors.thinking_selector_apply_filter": 8.0,
  # Measure-only leftover 605; first freeze 0.753× (0.637 / 0.847 µs). cadr leads.
  "cli_selectors.thinking_selector_clamp_selected": 8.0,
  # Measure-only leftover 606; first freeze 0.854× (0.981 / 1.149 µs). cadr leads.
  "cli_selectors.thinking_selector_select_current": 8.0,
  # Measure-only leftover 1396; first freeze 1.251× (13.551 / 10.831 µs).
  "cli_selectors.thafxxx_ok": 8.0,
  # Measure-only leftover 1397; first freeze 0.854× (0.650 / 0.761 µs). cadr leads.
  "cli_selectors.thclxxx_ok": 8.0,
  # Measure-only leftover 1398; first freeze 0.837× (0.984 / 1.176 µs). cadr leads.
  "cli_selectors.thscxxx_ok": 8.0,
  # Measure-only leftover 607; first freeze 1.353× (0.637 / 0.471 µs).
  "cli_selectors.thinking_selector_move": 8.0,
  # Measure-only leftover 608; first freeze 20.910× (144.448 / 6.908 µs).
  # 30.0 is first-freeze headroom. Ratchet down only.
  "cli_selectors.thinking_selector_handle_raw_input": 30.0,
  # Measure-only leftover 609; first freeze 0.834× (3.312 / 3.974 µs). cadr leads.
  "cli_selectors.thinking_selector_handle_event": 8.0,
  # Measure-only leftover 1363; first freeze 0.839× (3.337 / 3.979 µs). cadr leads.
  "cli_selectors.henxxx_ok": 8.0,
  # Measure-only leftover 1399; first freeze 1.675× (0.633 / 0.378 µs).
  "cli_selectors.thmvxxx_ok": 8.0,
  # Measure-only leftover 1400; first freeze 23.939× (143.544 / 5.996 µs).
  "cli_selectors.thhrxxx_ok": 30.0,
  # Measure-only leftover 1401; first freeze 0.914× (3.238 / 3.542 µs). cadr leads.
  "cli_selectors.thhexxx_ok": 8.0,
  # Measure-only leftover 610; first freeze 0.608× (0.467 / 0.768 µs). cadr leads.
  "cli_selectors.thinking_selector_selected_level": 8.0,
  # Measure-only leftover 611; first freeze 1.155× (0.268 / 0.232 µs).
  "cli_selectors.thinking_level_description_line": 8.0,
  # Measure-only leftover 612; first freeze 44.726× (316.671 / 7.080 µs).
  # 60.0 is first-freeze headroom. Ratchet down only.
  "cli_selectors.render_thinking_selector": 60.0,
  # Measure-only leftover 613; first freeze 2.292× (35.594 / 15.530 µs).
  "cli_selectors.trust_option_saved_p": 8.0,
  # Measure-only leftover 614; first freeze 1.715× (91.097 / 53.106 µs).
  "cli_selectors.make_trust_selector_state": 8.0,
  # Measure-only leftover 615; first freeze 8.798× (1074.462 / 122.128 µs).
  # 15.0 is first-freeze headroom. Ratchet down only.
  "cli_selectors.render_trust_selector": 15.0,
  # Measure-only leftover 1402; first freeze 5.065× (76.972 / 15.197 µs).
  "cli_selectors.trsvxxx_ok": 8.0,
  # Measure-only leftover 1403; first freeze 2.552× (131.369 / 51.480 µs).
  "cli_selectors.trmkxxx_ok": 8.0,
  # Measure-only leftover 1404; first freeze 9.157× (1023.386 / 111.757 µs).
  "cli_selectors.trrsxxx_ok": 15.0,
  # Measure-only leftover 616; first freeze 1.143× (2.654 / 2.323 µs).
  "cli_selectors.make_login_method_selector_state": 8.0,
  # Measure-only leftover 617; first freeze 1.803× (2.203 / 1.222 µs).
  "cli_selectors.make_api_key_input_state": 8.0,
  # Measure-only leftover 618; first freeze 1.204× (7.245 / 6.020 µs).
  "cli_selectors.make_oauth_selector_state": 8.0,
  # Measure-only leftover 1405; first freeze 1.274× (2.681 / 2.105 µs).
  "cli_selectors.lmsxxxx_ok": 8.0,
  # Measure-only leftover 1406; first freeze 2.039× (2.164 / 1.061 µs).
  "cli_selectors.akixxxx_ok": 8.0,
  # Measure-only leftover 1407; first freeze 1.340× (7.239 / 5.400 µs).
  "cli_selectors.ossxxxx_ok": 8.0,
  # Measure-only leftover 619; first freeze 1.338× (5.469 / 4.088 µs).
  "cli_selectors.login_dialog_show_waiting": 8.0,
  # Measure-only leftover 620; first freeze 1.281× (3.159 / 2.466 µs).
  "cli_selectors.login_dialog_show_progress": 8.0,
  # Measure-only leftover 621; first freeze 1.683× (5.131 / 3.050 µs).
  "cli_selectors.login_dialog_show_manual_input": 8.0,
  # Measure-only leftover 1381; first freeze 2.566× (5.581 / 2.175 µs).
  "cli_selectors.ldwxxx_ok": 8.0,
  # Measure-only leftover 1382; first freeze 1.770× (3.206 / 1.811 µs).
  "cli_selectors.ldpxxx_ok": 8.0,
  # Measure-only leftover 1383; first freeze 2.096× (5.271 / 2.515 µs).
  "cli_selectors.ldmixxx_ok": 8.0,
  # Measure-only leftover 622; first freeze 1.771× (6.781 / 3.830 µs).
  "cli_selectors.login_dialog_show_prompt": 8.0,
  # Measure-only leftover 623; first freeze 1.567× (8.766 / 5.594 µs).
  "cli_selectors.login_dialog_show_info": 8.0,
  # Measure-only leftover 624; first freeze 0.756× (2.598 / 3.435 µs).
  "cli_selectors.login_dialog_show_details": 8.0,
  # Measure-only leftover 1384; first freeze 2.164× (7.001 / 3.234 µs).
  "cli_selectors.ldprxxx_ok": 8.0,
  # Measure-only leftover 1385; first freeze 2.297× (9.135 / 3.977 µs).
  "cli_selectors.ldixxx_ok": 8.0,
  # Measure-only leftover 1386; first freeze 0.794× (2.646 / 3.330 µs). cadr leads.
  "cli_selectors.lddtxxx_ok": 8.0,
  # Measure-only leftover 625; first freeze 1.643× (5.722 / 3.482 µs).
  "cli_selectors.login_dialog_complete_input": 8.0,
  # Measure-only leftover 626; first freeze 1.923× (6.392 / 3.325 µs).
  "cli_selectors.login_dialog_handle_event": 8.0,
  # Measure-only leftover 627; first freeze 32.688× (135.552 / 4.147 µs).
  # 50.0 is first-freeze headroom. Ratchet down only.
  "cli_selectors.render_login_dialog": 50.0,
  # Measure-only leftover 1387; first freeze 3.230× (5.854 / 1.813 µs).
  "cli_selectors.ldcixxx_ok": 8.0,
  # Measure-only leftover 1388; first freeze 2.887× (7.396 / 2.562 µs).
  "cli_selectors.ldhexxx_ok": 8.0,
  # Measure-only leftover 1389; first freeze 29.776× (106.883 / 3.590 µs).
  # 50.0 is first-freeze headroom matching leftover 1323. Ratchet down only.
  "cli_selectors.ldrdxxx_ok": 50.0,
  # Measure-only leftover 628; first freeze 0.766× (1.754 / 2.288 µs).
  "cli_selectors.user_message_handle_event": 8.0,
  # Measure-only leftover 629; first freeze 15.827× (85.983 / 5.433 µs).
  # 30.0 is first-freeze headroom. Ratchet down only.
  "cli_selectors.user_message_handle_raw": 30.0,
  # Measure-only leftover 630; first freeze 65.009× (265.302 / 4.081 µs).
  # 100.0 is first-freeze headroom. Ratchet down only.
  "cli_selectors.render_user_message_selector": 100.0,
  # Measure-only leftover 1390; first freeze 0.707× (1.371 / 1.940 µs). cadr leads.
  "cli_selectors.umevxxx_ok": 8.0,
  # Measure-only leftover 1391; first freeze 17.622× (85.685 / 4.862 µs).
  # 30.0 is first-freeze headroom. Ratchet down only.
  "cli_selectors.umrwxxx_ok": 30.0,
  # Measure-only leftover 1392; first freeze 70.735× (242.804 / 3.433 µs).
  # 100.0 is first-freeze headroom. Ratchet down only.
  "cli_selectors.umrsxxx_ok": 100.0,
  # Measure-only leftover 631; first freeze 1.496× (32.105 / 21.468 µs).
  "cli_selectors.make_models_selector_keybindings": 8.0,
  # Measure-only leftover 632; first freeze 20.997× (97.005 / 4.620 µs).
  # 40.0 is first-freeze headroom. Ratchet down only.
  "cli_selectors.make_scoped_models_selector_state": 40.0,
  # Measure-only leftover 633; first freeze 26.593× (247.317 / 9.300 µs).
  # 50.0 is first-freeze headroom. Ratchet down only.
  "cli_selectors.render_model_selector": 50.0,
  # Measure-only leftover 1393; first freeze 1.515× (32.739 / 21.614 µs).
  "cli_selectors.mkbxxx_ok": 8.0,
  # Measure-only leftover 1394; first freeze 24.432× (105.397 / 4.314 µs).
  # 40.0 is first-freeze headroom. Ratchet down only.
  "cli_selectors.msmsxxx_ok": 40.0,
  # Measure-only leftover 1395; first freeze 27.467× (196.853 / 7.167 µs).
  # 50.0 is first-freeze headroom. Ratchet down only.
  "cli_selectors.mrmsxxx_ok": 50.0,
  # Measure-only leftover 634; first freeze 1.831× (0.910 / 0.497 µs).
  "cli_selectors.daxnuts_rgb_at": 8.0,
  # Measure-only leftover 635; first freeze 3.472× (0.688 / 0.198 µs).
  "cli_selectors.make_daxnuts_component": 8.0,
  # Measure-only leftover 636; first freeze 1.119× (3.787 / 3.384 µs).
  "cli_selectors.daxnuts_component_tick": 8.0,
    # Measure-only leftover 946; first freeze 1.471× (0.189 / 0.128 µs).
    # Does not remount login_dialog_make / login_dialog_auth / login_dialog_device.
    "cli_selectors.dlg_make": 8.0,
    # Measure-only leftover 947; first freeze 1.689× (2.003 / 1.186 µs).
    "cli_selectors.dlg_auth": 8.0,
    # Measure-only leftover 948; first freeze 3.465× (4.085 / 1.179 µs).
    "cli_selectors.dlg_dev": 8.0,
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
    # tui_theme leftover trio (samples=5): first-freeze headroom.
    # Ratchet down only.
    "tui_theme_overlay.rgb_to_ansi_256": 8.0,
    "tui_theme_overlay.parse_hex_color": 8.0,
    "tui_theme_overlay.theme_foreground_ansi": 8.0,
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
    "ai_support.threads_absent": 8.0,
    "ai_support.threads_current": 8.0,
    "ai_support.threads_joined": 8.0,
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
  # Measure-only leftover 1354; first freeze 2.078× (2.534 / 1.220 µs).
  "cli_selectors.latxxx_ok": 8.0,
  # First-freeze headroom for cli_selectors.login_provider_options.
  # Measure-only pair (Pair 207); ceiling not lowered.
  "cli_selectors.login_provider_options": 8.0,
  # Measure-only leftover 1355; first freeze 1.459× (8.355 / 5.726 µs).
  "cli_selectors.lpoxxx_ok": 8.0,
  # First-freeze headroom for cli_selectors.logout_provider_options.
  # Measure-only pair (Pair 208); ceiling not lowered.
  "cli_selectors.logout_provider_options": 8.0,
  # Measure-only leftover 1356; first freeze 2.122× (7.260 / 3.422 µs).
  "cli_selectors.lgoxxx_ok": 8.0,
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
    "cli_bootstrap_sessions.data_directory": 40.0,
    "cli_bootstrap_sessions.legacy_data_directory": 40.0,
    "cli_bootstrap_sessions.manual_migration_command": 8.0,
    "cli_bootstrap_sessions.managed_binary_names": 8.0,
    "cli_bootstrap_sessions.migration_guide_url": 8.0,
    "cli_bootstrap_sessions.extensions_doc_url": 8.0,
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
    # core_rest leftover trio (samples=5): cancellation_wait observed 6.041x
    # (53.40 / 8.840 us). 8.0 is first-freeze headroom. Ratchet down only.
    "core_rest.cancellation_wait": 8.0,
    # core_rest.redacted_types leftover pair (samples=5): observed 4.494x
    # (2.375 / 0.528 us). 8.0 is first-freeze headroom. Ratchet down only.
    "core_rest.redacted_types": 8.0,
    # core_rest.threads_join leftover pair (samples=5): observed 0.00575x
    # (128.7 / 22383 us). cadr leads. 8.0 is first-freeze headroom.
    # Ratchet down only.
    "core_rest.threads_join": 8.0,
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
        "dm_fixture",
        "dm_missing",
        "dm_n",
        "dp_fixture",
        "dp_missing",
        "dp_n",
        "op_default",
        "op_zero",
        "op_n",
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
        "ap_rel",
        "ap_abs",
        "ap_home",
        "ap_file",
        "ap_n",
        "jp_rel",
        "jp_abs",
        "jp_n",
        "fi_name",
        "fi_kind",
        "fi_size",
        "fi_n",
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
        "fmqb_present",
        "fmqb_shared",
        "fmqb_other",
        "fmqb_repeat",
        "fmqb_n",
        "fmqg_hit",
        "fmqg_alias",
        "fmqg_miss",
        "fmqg_repeat",
        "fmqg_n",
        "fmqc_target",
        "fmqc_other",
        "fmqc_list",
        "fmqc_null",
        "fmqc_n",
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
        "pd_nil",
        "pd_int",
        "pd_ord",
        "pd_zero",
        "ubr_cmd",
        "ubr_out",
        "ubr_exit",
        "ubr_can",
        "ubr_ex",
        "ubr_n",
        "neb_text",
        "neb_nl",
        "neb_code",
        "neb_can",
        "neb_path",
        "neb_n",
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
        "oa_ll_open",
        "oa_ll_nl",
        "oa_ll_utf8",
        "oa_ll_n",
        "oa_nf_empty",
        "oa_nf_under",
        "oa_nf_bytes",
        "oa_nf_lines",
        "oa_nf_n",
        "oa_close_path",
        "oa_close_stream",
        "oa_close_n",
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
        "gr_star",
        "gr_glob",
        "gr_q",
        "gr_dot",
        "gs_dot",
        "gs_star",
        "gs_pipe",
        "gs_bs",
        "gi_plain",
        "gi_anch",
        "gi_dir",
        "gsc_star",
        "gsc_miss",
        "gsc_glob",
        "gsc_q",
        "gsc_dot",
        "grb_star",
        "grb_glob",
        "grb_q",
        "grb_dot",
        "pgl_empty",
        "pgl_hash",
        "pgl_foo",
        "pgl_bang",
        "pgl_scan",
        "igd_git",
        "igd_nm",
        "igd_src",
        "igd_hub",
        "igd_slash",
        "gig_empty",
        "gig_hit",
        "gig_miss",
        "gig_bang",
        "gig_out",
        "mgt_name",
        "mgt_desc",
        "mgt_req",
        "mgt_par",
        "mgt_n",
    ),
    "grep_tool": (
        "rme_match",
        "rme_begin",
        "rme_bad",
        "rme_n",
        "rlt_crlf",
        "rlt_nl",
        "rlt_plain",
        "rlt_cr",
        "rlt_n",
        "gmt_name",
        "gmt_desc",
        "gmt_req",
        "gmt_n",
        "gru_ascii",
        "gru_empty",
        "gru_n",
        "gfl_n",
        "gfl_first",
        "gfl_cache",
        "gfl_count",
        "gcb_lines",
        "gcb_match",
        "gcb_missing",
        "gcb_n",
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
    "edit_tool": (
        "nlf_lf",
        "nlf_crlf",
        "nlf_cr",
        "nlf_empty",
        "nlf_n",
        "rle_lf",
        "rle_crlf",
        "rle_none",
        "rle_empty",
        "rle_n",
        "emt_name",
        "emt_desc",
        "emt_req",
        "emt_n",
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
        "ra_fd_darwin_arm",
        "ra_fd_linux_x64",
        "ra_fd_win_x64",
        "ra_rg_linux_x64",
        "ra_rg_linux_arm",
        "ra_rg_darwin_arm",
        "ra_n",
        "fb_nested",
        "fb_root",
        "fb_miss",
        "fb_n",
        "qn_restored",
        "qn_stashed",
        "qn_noop",
        "qn_n",
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
        "ps_openai",
        "ps_mixed",
        "ps_hyphen",
        "pap_openai",
        "pap_anth",
        "pap_codex",
        "pap_bad",
        "scl_two",
        "scl_trim",
        "scl_empty",
        "ev_hit",
        "ev_miss",
        "ev_blank",
        "ev_cadr",
        "ev_n",
        "cpn_exp",
        "cpn_cadr",
        "cpn_anth",
        "cpn_openai",
        "cpn_n",
        "pset_hit",
        "pset_miss",
        "pset_none",
        "pset_ht",
        "pset_n",
        "pdm_openai",
        "pdm_anth",
        "pdm_google",
        "pdm_miss",
        "pdm_n",
        "orf_codex",
        "orf_anth",
        "orf_miss",
        "orf_diff",
        "orf_n",
        "olf_codex",
        "olf_anth",
        "olf_miss",
        "olf_diff",
        "olf_n",
        "sn_prov",
        "sn_empty",
        "sn_miss",
        "sb_on",
        "sb_def",
        "sb_miss",
        "st_n",
        "st_read",
        "st_none",
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
        "np_dot",
        "np_plain",
        "np_win",
        "rk_n",
        "rk_ext",
        "rk_sk",
        "rk_pr",
        "rk_th",
        "tl_ext",
        "tl_sk",
        "tl_pr",
        "tl_th",
        "rfp_lisp",
        "rfp_case",
        "rfp_miss",
        "rfp_skill",
        "rfp_n",
        "rdn_skill",
        "rdn_lisp",
        "rdn_md",
        "rdn_json",
        "rdn_n",
        "csa_vec",
        "csa_list",
        "csa_miss",
        "csa_bad",
        "csa_n",
        "rsp_ext",
        "rsp_sk",
        "rsp_rel",
        "rsp_miss",
        "rsp_n",
        "cgr_star",
        "cgr_q",
        "cgr_plain",
        "cgr_dot",
        "cgr_n",
        "cet_bang",
        "cet_plus",
        "cet_minus",
        "cet_plain",
        "cet_empty",
        "cet_n",
        "ad_nil",
        "ad_true",
        "ad_miss",
        "ad_notht",
        "ad_n",
        "pef_vec",
        "pef_list",
        "pef_miss",
        "pef_bad",
        "pef_n",
        "im_empty",
        "im_name",
        "im_path",
        "im_type",
        "im_miss",
        "im_n",
        "crk_ext",
        "crk_sk",
        "crk_pr",
        "crk_th",
        "crk_n",
        "rel_file",
        "rel_nested",
        "rel_ext",
        "rel_plain",
        "rel_n",
        "cfl_short",
        "cfl_long",
        "cfl_dots",
        "cfl_zero",
        "cfl_n",
        "gl_pkg",
        "gl_user",
        "gl_src",
        "gl_rev",
        "gl_n",
        "hf_ext",
        "hf_miss",
        "hf_sk",
        "hf_other",
        "hf_n",
        "fi_fwd",
        "fi_skip",
        "fi_back",
        "fi_end",
        "fi_n",
        "se_item",
        "se_group",
        "se_sub",
        "se_last",
        "se_n",
        "sm_fwd",
        "sm_skip",
        "sm_back",
        "sm_end",
        "sm_n",
        "vr_small",
        "vr_mid",
        "vr_top",
        "vr_bot",
        "vr_n",
        "io_group",
        "io_first",
        "io_second",
        "io_sub",
        "io_n",
        "rp_drop",
        "rp_load",
        "rp_unload",
        "rp_keep",
        "rp_n",
        "sb_global",
        "sb_proj",
        "sb_nested",
        "sb_slash",
        "sb_n",
        "si_global",
        "si_proj",
        "si_empty",
        "si_copy",
        "si_n",
        "isb_global",
        "isb_proj",
        "isb_user",
        "isb_diff",
        "isb_n",
        "prp_file",
        "prp_nested",
        "prp_ext",
        "prp_plain",
        "prp_n",
        "pos_npm",
        "pos_rel",
        "pos_same",
        "pos_pin",
        "pos_n",
        "rgl_pkg",
        "rgl_user",
        "rgl_proj",
        "rgl_cadr",
        "rgl_n",
        "csv_ok",
        "csv_proj",
        "csv_nums",
        "csv_bad",
        "csv_n",
        "cpc_plain",
        "cpc_abs",
        "cpc_skill",
        "cpc_hello",
        "cpc_n",
        "cpm_lisp",
        "cpm_miss",
        "cpm_exact",
        "cpm_q",
        "cpm_n",
        "ebp_def",
        "ebp_inc",
        "ebp_exc",
        "ebp_load",
        "ebp_n",
        "drs_plus",
        "drs_minus",
        "drs_bang",
        "drs_miss",
        "drs_n",
        "pts_load",
        "pts_unload",
        "pts_bang",
        "pts_miss",
        "pts_n",
        "dps_load",
        "dps_unload",
        "dps_pkg",
        "dps_miss",
        "dps_n",
        "ua_setsid",
        "ua_fork",
        "ua_tail",
        "ua_rest",
        "ue_first",
        "ue_one",
        "go_plain",
        "go_nl",
        "go_ls",
        "go_upper",
        "go_bad",
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
    "oauth_pkce_device": ("dc_ok", "dc_fail", "dc_cancel", "ak_ok", "ak_len", "oa_ok", "oa_len", "auth_miss", "auth_bad", "gc_def", "gc_ind", "gc_ent", "gc_dom", "cf_plain", "cf_ok", "cf_gw", "rg_slash", "rg_plain", "rg_http", "ga_def", "ga_ind", "ga_ent", "ga_dom", "ga_key", "pd_plain", "pd_plus", "pd_slash", "pd_space", "pd_utf8", "pd_n", "pq_code", "pq_state", "pq_plus", "pq_empty", "pq_n", "pai_url", "pai_hash", "pai_qs", "pai_plain", "pai_n", "pk_anth", "pk_rad", "pk_other", "pk_n", "st_ok", "st_bad", "st_miss", "st_err", "st_n", "pcr_ok", "pcr_state", "pcr_path", "pcr_code", "pcr_n", "bv_A", "bv_a", "bv_0", "bv_dash", "bv_us", "bv_n", "bd_obj", "bd_foo", "bd_acct", "bd_n", "aid_ok", "aid_miss", "aid_bad", "aid_n", "ed_desc", "ed_error", "ed_n", "es_ok", "es_created", "es_fail", "es_n", "nd_complete", "nd_plain", "nd_code", "nd_n", "jc_empty", "jc_ok", "jc_nil", "jc_n", "iv_num", "iv_str", "iv_zero", "iv_neg", "iv_bad", "iv_n", "ds_ok", "ds_404", "ds_fail", "ds_bad", "ds_n", "ori_url", "ori_qs", "ori_plain", "ori_n", "orr_same", "orr_access", "orr_empty", "orr_n", "ox_ok", "ox_fail", "ox_bad", "ox_n", "anm_eq", "anm_claude", "anm_n", "ans_sub", "ans_t", "ans_n", "ani_eq", "ani_paste", "ani_n", "khd_eq", "khd_https", "khd_n", "khc_eq", "khc_win", "khc_n", "kht_eq", "kht_noslash", "kht_n"),
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
        "sc_reload",
        "sc_reload_args",
        "sc_foo",
        "sc_foo_args",
        "sc_plain",
        "sc_plain_args",
        "sc_blank",
        "sc_blank_args",
        "hp_hello",
        "hp_ws",
        "hp_blank",
        "hu_nope",
        "hu_miss",
        "hu_n",
        "ug_empty",
        "ug_dash",
        "ug_null",
        "ug_bs",
        "ug_dot",
        "ug_ok",
        "ug_n",
        "gp_https",
        "gp_scp",
        "gp_slash",
        "gp_miss",
        "gp_n",
        "ng_https",
        "ng_git",
        "ng_file",
        "ng_empty",
        "ng_bare",
        "pf_plain",
        "pf_hyphen",
        "pf_keep",
        "pf_empty",
        "pf_n",
        "ls_ok",
        "ls_empty",
        "ls_dot",
        "ls_dotdot",
        "ls_slash",
        "ls_n",
        "if_fn",
        "if_plist",
        "if_empty_name",
        "if_no_factory",
        "if_odd",
        "ga_manual",
        "ga_auto",
        "ga_str",
        "ga_nil",
        "sa_login",
        "sa_view",
        "sa_bare",
        "sa_tab",
        "sa_n",
        "ql_name",
        "ql_rec",
        "ql_bytes",
        "ql_both",
        "cl_meta",
        "cl_train",
        "cl_args",
        "cl_small",
        "cl_none",
        "cl_dashc",
        "md_loaded",
        "md_sleep",
        "md_unload",
        "md_load",
        "md_down",
        "md_nocontext",
        "cc_small",
        "cc_k",
        "cc_k0",
        "cc_m",
        "cc_m0",
        "cc_999",
    ),
    "evals_harness": ("eval_sets", "comparisons", "candidate_wins", "ties", "gk_id", "gk_trim", "art_ok", "art_bad", "ap_n", "ap_sess", "ap_src", "ap_sess_prefix", "ap_src_prefix", "ap_sess_file", "ap_src_file", "fmt_empty", "fmt_empty_hdr", "fmt_hdr", "fmt_base", "fmt_pass", "ns_empty", "ns_str_n", "ns_str_pr", "ns_seq_n", "ns_seq_rel", "ns_kw_n", "ns_kw_rel", "ns_vec_n", "ns_bad", "rs_explicit", "rs_env", "rs_miss", "rs_prov", "rs_blank", "rs_n", "tr_n", "tr_user", "tr_role", "tr_text", "tr_call", "tr_name", "tr_result", "tr_err", "tr_keys", "la_new", "la_none", "la_full", "la_n", "sv_hash", "sv_plist", "sv_intern", "sv_miss", "sv_n", "us_in", "us_out", "us_total", "us_tools", "us_prov", "us_model", "us_cost", "us_n", "rj_out", "rj_ev", "rj_err", "rj_art", "rj_time", "rj_n", "ee_trim", "ee_model", "ee_ws", "ee_miss", "ee_n", "ps_type", "ps_content", "ps_n", "rs_type", "rs_no_content", "mer_exists", "mer_prefix", "mer_no_ws", "mer_n", "nst_kw", "nst_sym", "nst_str", "nst_bad", "nst_n", "set_n", "set_names", "set_all", "set_filt_n", "set_no_bash", "set_cases", "pea_out", "pea_msgs", "pea_stop", "pea_n", "rld_err", "rld_active", "rld_reports", "rld_n", "rca_out", "rca_events", "rca_err", "rca_ms", "rca_n", "ct_plain", "ct_join", "ct_empty", "ct_blank", "ct_n", "te_type", "te_role", "te_content", "te_asst_role", "te_asst", "te_n", "el_now", "el_past", "el_order", "el_n", "apr_val", "apr_empty", "apr_miss", "apr_model", "apr_n", "pa_space", "pa_eq", "pa_mix", "pa_miss", "pa_empty", "pa_unknown", "pa_n", "vs_ok", "vs_trim", "vs_city", "vs_tok", "vs_n", "sca_def", "sca_pkg", "sca_case", "sca_miss", "sca_leg", "sla_mz", "sla_tb", "sla_pi", "sla_case", "sla_miss", "see_path", "see_err", "see_empty", "see_blank", "see_n", "rpb_mid", "rpb_end", "rpb_zero", "rpb_miss", "rpb_n", "egd_cut", "egd_len", "egd_no_g", "egd_head", "egd_n", "pdp_cut", "pdp_dbl", "pdp_no_cwd", "pdp_keep", "pdp_n", "rid_hit", "rid_empty", "rid_custom", "rid_gen", "rid_n", "arj_name", "arj_path", "arj_empty", "arj_keys", "arj_n", "ra_empty", "ra_sess", "ra_rec", "ra_case", "ra_n", "ve_ok", "ve_greet", "ve_paths", "ve_empty", "ve_n", "sd_smoke", "sd_ext", "sd_auth", "sd_unk", "sd_n", "er_yes", "er_hash", "er_str", "er_nil", "er_n", "at_empty", "at_n", "at_read", "at_bash", "at_keys", "ep_none", "ep_n", "ep_path", "ep_skip", "ep_keys", "ai_crypto_model_data", "mr_explicit", "mr_env", "mr_miss", "mr_n", "fn_int", "fn_float", "fn_nil", "fn_inf", "fn_str", "fn_n", "am_keep", "am_runid", "am_snap", "am_n"),
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
    "image_runtime": ("png_width", "png_height", "gif_width", "gif_height", "miss", "png_mime", "jpeg_mime", "gif_mime", "webp_mime", "miss_mime", "gemini", "flux", "unknown", "note_resized", "note_half", "note_plain", "api_fixture", "api_unknown", "om_gemini_n", "om_gemini_text", "om_flux_n", "om_flux_text", "oc_text_type", "oc_text", "oc_img_type", "oc_img_url", "oc_ok", "pd_ok_mime", "pd_ok_data", "pd_ok", "pd_miss", "pd_plain", "us_in", "us_out", "us_cr", "us_cw", "us_in2", "us_out2", "us_cr2", "us_cw2", "poi_id", "poi_text", "poi_n", "poi_mime", "poi_data", "poi_in", "poi_out", "er_auth", "er_hit", "er_abort", "er_flag", "er_prov"),
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
        "img_nil",
        "img_n",
        "img_mime",
        "img_bad",
        "rp_str",
        "rp_len",
        "rp_parts",
        "rp_mime",
        "br_out",
        "br_code",
        "br_can",
        "br_tr",
        "br_path",
        "br_null",
        "dr_type",
        "dr_method",
        "dr_msg",
        "dr_opt_n",
        "dr_ph",
        "dr_to",
        "rs_nil",
        "rs_can",
        "rs_ok",
        "rs_val",
        "rs_num",
        "ex_nil",
        "ex_zero",
        "ex_future",
        "qm_all",
        "qm_one",
        "qm_bad",
        "la_hit",
        "la_len",
        "la_miss",
        "cl_n",
        "cl_ext",
        "cl_prompt",
        "bj_cmd",
        "bj_ok",
        "bj_id",
        "bj_nl",
        "no_cmd",
        "no_ok",
        "no_id",
        "no_nl",
        "um_cmd",
        "um_ok",
        "um_id",
        "um_nl",
        "um_unk",
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
        "r256_red",
        "r256_black",
        "r256_gray",
        "r256_white",
        "r256_accent",
        "ph_112233_r",
        "ph_112233_g",
        "ph_112233_b",
        "ph_accent_r",
        "ph_white_b",
        "tfa_accent_esc",
        "tfa_text_esc",
        "tfa_n",
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
        "tha_eq",
        "tha_n",
        "thc_eq",
        "thc_n",
        "thj_eq",
        "thj_n",
    ),
    "tui_select_settings_loaders": (
        "he_count",
        "he_first",
        "wo_count",
        "zz_count",
        "lf_default_n",
        "lf_default_first",
        "lf_custom_n",
        "lf_one_n",
        "li_default",
        "li_pos",
        "li_zero",
        "li_n",
        "ls_initial",
        "ls_next",
        "ls_wrap",
        "ls_n",
        "ml_has_a",
        "ml_frames",
        "ml_n",
        "sm_working",
        "sm_kept_a",
        "sm_n",
        "si_has_x",
        "si_frames",
        "si_n",
        "ud_has_a",
        "ud_frames",
        "ud_n",
        "cl_has_a",
        "cl_aborted",
        "cl_n",
        "ct_before",
        "ct_after",
        "ct_n",
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
        "fl_empty",
        "fl_before",
        "fl_n",
        "fl_seq",
        "fl_after",
        "cl_before",
        "cl_after",
        "cl_hello",
        "cl_final",
        "ct_empty",
        "ct_csi",
        "ct_done",
        "ct_again",
        "ct_n",
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
        "nm_pref",
        "nm_login",
        "nm_prov",
        "ns_pref",
        "ns_then",
        "ns_nl",
        "nk_oai",
        "nk_unk",
        "nk_sel",
        "rd_eq",
        "rd_ms",
        "rd_pos",
        "cl_nil",
        "cl_twice",
        "cl_ok",
        "sg_miss",
        "sg_hit",
        "sg_n",
        "awh_hello",
        "awh_len",
        "awh_file",
        "awh_n",
        "awo_second",
        "awo_no_first",
        "awo_len",
        "awo_n",
        "awe_ok",
        "awe_len",
        "awe_file",
        "awe_n",
        "eed_hello",
        "eed_len",
        "eed_round",
        "eed_nonl",
        "eed_n",
        "eef_orig",
        "eef_empty",
        "eef_twice",
        "eef_n",
        "eee_ok",
        "eee_len",
        "eee_x",
        "eee_xlen",
        "eee_n",
        "cta_eq",
        "cta_n",
        "ctc_eq",
        "ctc_n",
        "ctj_eq",
        "ctj_n",
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
        "me_type",
        "me_label",
        "me_run",
        "me_ex",
        "me_idle",
        "me_stream",
        "me_exp",
        "me_n",
        "ao_text",
        "ao_n",
        "ao_skip",
        "ao_cache",
        "ce_text",
        "ce_exit",
        "ce_cancel",
        "ce_trunc",
        "ce_path",
        "ce_ex",
        "ce_stream",
        "ce_run",
        "ce_err",
        "ce_err_cancel",
        "st_plain",
        "st_esc",
        "st_bel",
        "st_nil",
        "st_empty",
        "bn_unix",
        "bn_win",
        "bn_plain",
        "bn_empty",
        "bn_nil",
        "tt_none",
        "tt_session",
        "tt_esc",
        "tt_empty",
        "wt_nil",
        "wt_one_n",
        "wt_one_order",
        "wt_two_n",
        "wt_two_first",
        "wt_two_last",
        "op_0",
        "op_1",
        "op_other",
        "op_space",
        "rc_assist",
        "rc_stream",
        "rc_tool_nil",
        "rc_tool_done",
        "rc_tool_run",
        "rc_custom",
        "tsm_name",
        "tsm_pending",
        "tsm_nil",
        "tsu_result",
        "tsu_pending",
        "tsu_cleared",
        "trr_pending_n",
        "trr_pending_call",
        "trr_done_n",
        "trr_done_result",
        "trr_custom",
        "trr_empty",
        "tp_str",
        "tp_int",
        "tp_255",
        "tp_256",
        "tp_neg",
        "tp_nil",
        "tr_int",
        "tr_empty",
        "tr_hex",
        "tr_var",
        "tr_cycle",
        "tr_miss",
        "tv_ok",
        "tv_slash",
        "tv_unknown",
        "too_n",
        "too_accent",
        "too_tmax",
        "too_scroll",
        "too_nil",
        "tas_dark",
        "tas_light",
        "tas_obj",
        "tas_bad",
        "tas_name",
        "ltf_name",
        "ltf_ok",
        "ltf_miss",
        "ltf_bad",
        "ltf_empty",
        "bar_n",
        "bar_label",
        "bar_run",
        "bar_stream",
        "bar_ex",
        "bar_run2",
        "cs_text",
        "cs_run",
        "cs_stream",
        "cs_exit",
        "cs_cache",
        "cs_empty",
        "st_run",
        "st_stream",
        "st_text",
        "st_cache",
        "st_exit",
        "aht_empty",
        "aht_text",
        "aht_tool",
        "aht_both",
        "aht_think",
        "adb_n",
        "adb_first",
        "adb_think",
        "adb_tail",
        "adb_blank",
        "tsl_skill",
        "tsl_branch",
        "tsl_empty",
        "tsl_n",
        "tsl_comp",
        "tst_hi",
        "tst_empty",
        "tst_cjk",
        "tst_n",
        "tst_space",
        "ase_len",
        "ase_abort",
        "ase_custom",
        "ase_tool",
        "ase_err",
        "unb_w",
        "unb_ch",
        "unb_0",
        "unb_1",
        "unb_n",
        "tmb_hi",
        "tmb_empty",
        "tmb_n",
        "tmb_keep",
        "tmb_tok",
        "unt_hi",
        "unt_empty",
        "unt_cjk",
        "unt_n",
        "unt_pad",
        "syn_plain",
        "syn_empty",
        "syn_keep",
        "syn_n",
        "syn_json",
        "apk_hit",
        "apk_miss",
        "apk_google",
        "apk_empty",
        "apk_nil",
        "amu_in",
        "amu_out",
        "amu_cache",
        "amu_known",
        "amu_hit",
        "aum_user",
        "aum_n",
        "aum_skill",
        "aum_both",
        "aum_text",
        "stm_user",
        "stm_n",
        "stm_asst",
        "stm_bash",
        "stm_mix",
        "rtm_n",
        "rtm_drop",
        "rtm_keep",
        "rtm_zero",
        "rtm_unk",
        "rum_hi",
        "rum_n",
        "rum_osc",
        "rum_pad",
        "rum_empty",
        "ram_hi",
        "ram_n",
        "ram_osc",
        "ram_think",
        "ram_trunc",
        "ttm_eq",
        "ttm_n",
        "ttm_off",
        "ttm_think",
        "ttm_hit",
        "rts_skill",
        "rts_foo",
        "rts_branch",
        "rts_comp",
        "rts_n",
        "rab_hi",
        "rab_n",
        "rab_empty",
        "rab_err",
        "rab_think",
        "rvn_avail",
        "rvn_ver",
        "rvn_change",
        "rvn_n",
        "rvn_dash",
        "rpn_avail",
        "rpn_pkg",
        "rpn_run",
        "rpn_n",
        "rpn_dash",
        "rteu_user",
        "rteu_asst",
        "rteu_err",
        "rteu_ver",
        "rteu_empty",
        "rte_user",
        "rte_n",
        "rte_hit",
        "rte_err",
        "rte_ver",
        "rtes_user",
        "rtes_asst",
        "rtes_gap",
        "rtes_n",
        "rtes_empty",
        "sut_tty",
        "sut_off",
        "sut_in",
        "sut_out",
        "sut_none",
        "tce_ok",
        "tce_auth",
        "tce_err",
        "tce_n",
        "tce_skip",
        "rsub_start",
        "rsub_queue",
        "rsub_busy",
        "rsub_line",
        "rsub_qline",
        "edc_hi",
        "edc_body",
        "edc_sub",
        "edc_n",
        "edc_dash",
        "tcp_nil",
        "tcp_in",
        "tcp_str",
        "tcp_dlg",
        "tcp_ed",
        "erv_nil",
        "erv_hi",
        "erv_list",
        "erv_num",
        "erv_n",
        "mfs_title",
        "mfs_n",
        "mfs_a",
        "mfs_dead",
        "mfs_open",
        "ncr_nil",
        "ncr_eq",
        "ncr_set",
        "ncr_plain",
        "ncr_ret",
        "tet_fg",
        "tet_bg",
        "tet_bold",
        "tet_italic",
        "tet_hi",
        "eid_t",
        "eid_proto",
        "eid_in",
        "eid_pr",
        "eid_empty",
        "eed_t",
        "eed_hi",
        "eed_empty",
        "eed_proto",
        "eed_ed",
        "rai_type",
        "rai_copy",
        "rai_in",
        "rai_pr",
        "rai_nil",
        "rah_esc",
        "rah_int",
        "rah_fn",
        "rah_sel",
        "rah_nop",
        "rra_hi",
        "rra_dash",
        "rra_n",
        "rra_msg",
        "rra_star",
        "rec_nil",
        "rec_w",
        "rec_again",
        "rec_type",
        "rec_msg",
        "rfs_pick",
        "rfs_dash",
        "rfs_n",
        "rfs_a",
        "rfs_nav",
        "fsh_esc",
        "fsh_sel",
        "fsh_down",
        "fsh_fn",
        "fsh_nop",
        "fsr_j",
        "fsr_k",
        "fsr_x",
        "fsr_z",
        "fsr_again",
        "rcu_hi",
        "rcu_nil",
        "rcu_aa",
        "rcu_n",
        "rcu_dlg",
        "ecu_esc",
        "ecu_sel",
        "ecu_val",
        "ecu_nop",
        "ecu_txt",
        "rto_hid",
        "rto_hi",
        "rto_n",
        "rto_vn",
        "rto_row",
        "eam_ok",
        "eam_min",
        "eam_n",
        "eau_eq",
        "eau_sold",
        "eau_n",
        "eat_eq",
        "eat_pi",
        "eat_n",
        "ccand_darwin",
        "ccand_win",
        "ccand_none",
        "ccand_termux",
        "ccand_wl",
        "ccand_x11",
        "osc_hello",
        "osc_empty",
        "osc_cjk",
        "osc_over",
        "osc_emoji",
        "osc_bound",
        "cc_darwin",
        "cc_linux_shell",
        "cc_remote",
        "cc_osc",
        "cc_win",
        "cc_termux",
        "cfg_plain",
        "cfg_last",
        "cfg_skip",
        "cfg_miss",
        "cfg_pad",
        "cfg_empty",
        "rgb_black",
        "rgb_white",
        "rgb_mid",
        "rgb_187",
        "rgb_188",
        "rgb_red",
        "dbg_white",
        "dbg_black",
        "dbg_none",
        "dbg_empty",
        "dbg_bad",
        "dbg_pair",
        "fft_short",
        "fft_long",
        "fft_cjk",
        "fft_empty",
        "fft_zero",
        "fft_emoji",
        "fu_kimi",
        "fu_plain",
        "fu_zero",
        "fu_nocache",
        "fu_case",
        "fu_cost0",
        "fgp_repo",
        "fgp_nested",
        "fgp_worktree",
        "fgp_common",
        "fgp_nohead",
        "fgp_none",
        "fst_plain",
        "fst_ceil",
        "fst_exact",
        "fst_zero",
        "fst_neg",
        "fst_empty",
        "eoo_nil",
        "eoo_static",
        "eoo_fn",
        "eoo_pct",
        "eoo_zero",
        "eoo_width",
        "ecu_default",
        "ecu_width",
        "ecu_vis_nil",
        "ecu_visp_nil",
        "ecu_vis_t",
        "ecu_fn_nil",
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
        "ap_blank",
        "ap_ink",
        "ap_out",
        "ac_space",
        "ac_lower",
        "ac_upper",
        "ac_full",
        "ag_h",
        "umm_empty",
        "umm_one",
        "umm_two",
        "umm_hit",
        "umm_miss",
        "umm_copy",
        "umv_empty",
        "umv_wrap_fwd",
        "umv_back",
        "umv_full",
        "umv_three_back",
        "umv_three_fwd",
        "ums_empty",
        "ums_last",
        "ums_hit",
        "ums_wrap",
        "ums_miss",
        "ums_one",
        "ldm_empty_n",
        "ldm_named",
        "ldm_named_sec",
        "ldm_long",
        "ldm_input",
        "ldm_long_n",
        "lda_plain",
        "lda_instr",
        "lda_empty_instr",
        "lda_replace",
        "lda_provider",
        "lda_n",
        "ldd_code",
        "ldd_empty",
        "ldd_replace",
        "ldd_provider",
        "ldd_n",
        "ldd_hint",
        "tll_off",
        "tll_minimal",
        "tll_xhigh",
        "tll_max",
        "tll_low",
        "tll_bogus",
        "tlst_off",
        "tlst_minimal",
        "tlst_high",
        "tlst_xhigh",
        "tlst_max",
        "tlst_bogus",
        "tsq_empty",
        "tsq_off",
        "tsq_high",
        "tsq_miss",
        "tsq_nil",
        "tsq_clear",
        "dpi_00",
        "dpi_0x",
        "dpi_mid",
        "dpi_last",
        "dpi_h",
        "dpi_w",
        "dil_0",
        "dil_7",
        "dil_15",
        "dil_0_len",
        "dil_15_len",
        "dil_reset",
        "dcl_plain",
        "dcl_odd",
        "dcl_narrow",
        "dcl_empty",
        "dcl_ansi",
        "dcl_wide",
        "cds_0",
        "cds_1",
        "cds_1000",
        "cds_1001",
        "cds_1500",
        "cds_999",
        "cdt_make",
        "cdt_remain",
        "cdt_expired",
        "cdt_ticks",
        "cdt_expires",
        "cdt_renders",
        "cdr_fn1",
        "cdr_fn2",
        "cdr_nil",
        "cdr_sym",
        "cdr_zero",
        "cdr_fn3",
        "mspb_openai",
        "mspb_anthropic",
        "mspb_codex",
        "mspb_google",
        "mspb_openrouter",
        "mspb_hit",
        "smce_all",
        "smce_two",
        "smce_empty",
        "smce_one",
        "smce_three",
        "smce_unavail",
        "mli_swap",
        "mli_ends",
        "mli_neg",
        "mli_over",
        "mli_same",
        "mli_empty",
        "ssm_all",
        "ssm_partial",
        "ssm_unavail",
        "ssm_empty",
        "ssm_full",
        "ssm_single",
        "smie_all",
        "smie_hit",
        "smie_miss",
        "smie_empty",
        "smie_stale",
        "smie_all_stale",
        "smti_from_all",
        "smti_remove",
        "smti_add",
        "smti_empty",
        "smti_again",
        "smti_unavail",
        "ake_all",
        "ake_full",
        "ake_partial",
        "ake_empty",
        "ake_vacuous",
        "ake_wrong",
        "smei_all",
        "smei_one",
        "smei_rest",
        "smei_add",
        "smei_fill",
        "smei_none",
        "smci_all_one",
        "smci_list",
        "smci_all_all",
        "smci_empty",
        "smci_keep",
        "smci_all_none",
        "smes_empty",
        "smes_one",
        "smes_two",
        "smes_dup",
        "smes_sort",
        "smes_three",
        "meq_same",
        "meq_diff_id",
        "meq_diff_prov",
        "meq_nil_left",
        "meq_nil_right",
        "meq_both_nil",
        "smsst_openai",
        "smsst_anthropic",
        "smsst_codex",
        "smsst_openrouter",
        "smsst_google",
        "smsst_noname",
        "msa_all",
        "msa_scoped",
        "msa_empty",
        "msa_one",
        "msa_force_all",
        "msa_force_scoped",
        "msc_ok",
        "msc_high",
        "msc_zero",
        "msc_one",
        "msc_keep",
        "msc_filter",
        "msel_hit",
        "msel_first",
        "msel_last",
        "msel_miss",
        "msel_nil",
        "msel_empty",
        "smsort_first",
        "smsort_last",
        "smsort_mid",
        "smsort_rev",
        "smsort_single",
        "msvm_all",
        "msvm_gpt",
        "msvm_nope",
        "msvm_anth",
        "msvm_oogle",
        "msvs_all",
        "msvs_mid",
        "msvs_filter",
        "msvs_empty",
        "msvs_max1",
        "msrst_all",
        "msrst_overlap",
        "msrst_extra",
        "msrst_empty",
        "msrst_scoped_only",
        "msfst_hit",
        "msfst_last",
        "msfst_extra",
        "msfst_miss",
        "msfst_empty",
        "msfr_ok",
        "msfr_err",
        "msfr_kind",
        "msfr_rev",
        "msfr_query",
        "smrm_all",
        "smrm_partial",
        "smrm_empty",
        "smrm_single",
        "smrm_extra",
        "smbid_hit",
        "smbid_google",
        "smbid_miss",
        "smbid_empty",
        "smbid_openrouter",
        "smist_gpt",
        "smist_claude",
        "smist_codex",
        "smist_cached",
        "smist_noid",
        "smce_copy",
        "smsi_all",
        "smsi_partial",
        "smsi_none",
        "smsi_empty",
        "smsi_single",
        "smsc_once",
        "smsc_twice",
        "smsc_none",
        "smsc_none2",
        "smsc_zero",
        "smsel_first",
        "smsel_mid",
        "smsel_oob",
        "smsel_empty",
        "smsel_gpt",
        "smsid_first",
        "smsid_last",
        "smsid_miss",
        "smsid_empty",
        "smsid_gpt",
        "smnc_all",
        "smnc_partial",
        "smnc_none",
        "smnc_twice",
        "smnc_empty",
        "smri_all",
        "smri_partial",
        "smri_none",
        "smri_empty",
        "smri_single",
        "smaf_all",
        "smaf_gpt",
        "smaf_miss",
        "smaf_partial",
        "smaf_empty",
        "smvi_all",
        "smvi_gpt",
        "smvi_miss",
        "smvi_empty",
        "smvi_partial",
        "smref_all",
        "smref_gpt",
        "smref_miss",
        "smref_empty",
        "smref_partial",
        "smcl_high",
        "smcl_zero",
        "smcl_miss",
        "smcl_gpt",
        "smcl_empty",
        "smmc_all",
        "smmc_partial",
        "smmc_empty",
        "smmc_nocb",
        "smmc_filter",
        "smfrf_ok",
        "smfrf_success",
        "smfrf_rev",
        "smfrf_enabled",
        "smfrf_filter",
        "smskp_save_hit",
        "smskp_save_miss",
        "smskp_up_hit",
        "smskp_csi_up",
        "smskp_garbage",
        "smbl_save",
        "smbl_enable",
        "smbl_confirm",
        "smbl_fallback",
        "smbl_custom",
        "mskp_tab_hit",
        "mskp_tab_miss",
        "mskp_up_hit",
        "mskp_csi_up",
        "mskp_save_hit",
        "mskb_nil",
        "mskb_default",
        "mskb_custom",
        "mskb_enable",
        "mskb_confirm",
        "msmk_all",
        "msmk_last",
        "msmk_scoped",
        "msmk_extra",
        "msmk_one",
        "tskp_tab_hit",
        "tskp_tab_miss",
        "tskp_up_hit",
        "tskp_csi_up",
        "tskp_save_hit",
        "tskb_nil",
        "tskb_default",
        "tskb_custom",
        "tskb_cancel",
        "tskb_confirm",
        "tms_high",
        "tms_off",
        "tms_miss",
        "tms_empty",
        "tms_default",
        "tsaf_high",
        "tsaf_off",
        "tsaf_miss",
        "tsaf_empty",
        "tsaf_low",
        "tscl_high",
        "tscl_zero",
        "tscl_ok",
        "tscl_last",
        "tscl_one",
        "tssc_high",
        "tssc_off",
        "tssc_miss",
        "tssc_empty",
        "tssc_only",
        "tsmv_down",
        "tsmv_up_wrap",
        "tsmv_down_wrap",
        "tsmv_page",
        "tsmv_empty",
        "tshri_down",
        "tshri_up",
        "tshri_enter",
        "tshri_save",
        "tshri_nop",
        "tshe_down",
        "tshe_enter",
        "tshe_esc",
        "tshe_text",
        "tshe_tab",
        "tssl_first",
        "tssl_mid",
        "tssl_last",
        "tssl_empty",
        "tssl_oob",
        "tsdl_off_def",
        "tsdl_high",
        "tsdl_high_def",
        "tsdl_bogus",
        "tsdl_min",
        "tsrd_default",
        "tsrd_sel",
        "tsrd_query",
        "tsrd_empty",
        "tsrd_wide",
        "tosp_nil",
        "tosp_trust",
        "tosp_parent",
        "tosp_mismatch",
        "tosp_distrust",
        "mtss_child",
        "mtss_saved",
        "mtss_inherited",
        "mtss_distrust",
        "mtss_single",
        "rtrs_default",
        "rtrs_saved",
        "rtrs_inherited",
        "rtrs_distrust",
        "rtrs_single",
        "mlms_default",
        "mlms_title",
        "mlms_custom",
        "mlms_one",
        "mlms_three",
        "makis_anth",
        "makis_openai",
        "makis_google",
        "makis_oauth_opt",
        "makis_named",
        "moss_default",
        "moss_filter",
        "moss_miss",
        "moss_logout_empty",
        "moss_logout",
        "ldw_empty",
        "ldw_auth",
        "ldw_twice",
        "ldw_blank",
        "ldw_device",
        "ldp_empty",
        "ldp_auth",
        "ldp_two",
        "ldp_blank",
        "ldp_wait",
        "ldmi_empty",
        "ldmi_auth",
        "ldmi_blank",
        "ldmi_nocancel",
        "ldmi_wait",
        "ldpr_empty",
        "ldpr_auth",
        "ldpr_noplace",
        "ldpr_nocancel",
        "ldpr_wait",
        "ldi_labeled",
        "ldi_auth",
        "ldi_bare",
        "ldi_nolink",
        "ldi_wait",
        "lddt_two",
        "lddt_auth",
        "lddt_empty",
        "lddt_styles",
        "lddt_wait",
        "ldci_manual",
        "ldci_prompt",
        "ldci_none",
        "ldci_blank",
        "ldci_auth",
        "ldhe_esc",
        "ldhe_cancel",
        "ldhe_enter",
        "ldhe_type",
        "ldhe_down",
        "ldrd_wait",
        "ldrd_auth",
        "ldrd_manual",
        "ldrd_prompt",
        "ldrd_details",
        "umhe_down",
        "umhe_enter",
        "umhe_esc",
        "umhe_text",
        "umhe_empty",
        "umhr_down",
        "umhr_up",
        "umhr_enter",
        "umhr_esc",
        "umhr_nop",
        "umrd_three",
        "umrd_one",
        "umrd_empty",
        "umrd_narrow",
        "umrd_hit",
        "mmskb_save",
        "mmskb_enable",
        "mmskb_confirm",
        "mmskb_custom",
        "mmskb_reorder",
        "msmksc_all",
        "msmksc_partial",
        "msmksc_empty",
        "msmksc_status",
        "msmksc_copy",
        "rms_default",
        "rms_sel2",
        "rms_scoped",
        "rms_narrow",
        "rms_miss",
        "dra_00",
        "dra_0x",
        "dra_mid",
        "dra_last",
        "dra_10",
        "dmc_tick",
        "dmc_stop",
        "dmc_thread",
        "dmc_cache",
        "dmc_second",
        "dct_one",
        "dct_max",
        "dct_stop",
        "dct_after",
        "dct_renders",
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
        "as_bedrock",
        "as_vertex",
        "as_env",
        "as_miss",
        "as_hit",
        "po_azure",
        "po_project",
        "po_location",
        "po_cf",
        "po_res",
        "sro_keep",
        "sro_drop",
        "sro_n",
        "sro_empty",
        "sro_temp",
        "ologin_copilot",
        "ologin_anth",
        "ologin_miss",
        "ologin_diff",
        "ologin_n",
        "orefresh_copilot",
        "orefresh_anth",
        "orefresh_miss",
        "orefresh_diff",
        "orefresh_n",
        "ota_anth",
        "ota_kimi",
        "ota_miss",
        "ota_diff",
        "ota_n",
        "alk_bedrock",
        "alk_vertex",
        "alk_openai",
        "alk_diff",
        "alk_n",
        "aka_explicit",
        "aka_stored",
        "aka_env",
        "aka_miss",
        "aka_n",
        "mff_copilot",
        "mff_openai",
        "mff_keep",
        "mff_empty",
        "mff_n",
        "rp_id",
        "rp_key",
        "rp_no_oauth",
        "rp_models",
        "rp_n",
        "rpc_oauth",
        "rpc_login",
        "rpc_filter",
        "rpc_models",
        "rpc_n",
        "mr_oa",
        "mr_anth",
        "mr_miss",
        "mr_env",
        "mr_n",
        "pp_stream",
        "pp_simple",
        "pp_miss",
        "pp_diff",
        "pp_n",
        "ppa_id",
        "ppa_oauth",
        "ppa_type",
        "ppa_diff",
        "ppa_n",
        "ip_id",
        "ip_api",
        "ip_model",
        "ip_type",
        "ip_n",
    ),
    "skill_prompt_load": (
        "custom_len",
        "append_len",
        "ctx_len",
        "has_cwd",
        "has_extra",
        "has_agents",
        "rp_lit",
        "rp_file",
        "rp_miss",
        "nr_eisdir",
        "nr_eacces",
        "nr_other",
        "pa_len",
        "pa_join",
        "pa_base",
        "si_nil",
        "si_lit",
        "si_file",
        "ov_none",
        "ov_replace",
        "ov_keep",
        "cf_n",
        "cf_path",
        "cf_text",
        "sk_n",
        "sk_list",
        "sk_ok",
        "pr_n",
        "pr_list",
        "pr_ok",
        "th_n",
        "th_list",
        "th_ok",
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
        "sp_id",
        "sp_slash",
        "sp_win",
        "sp_jsonl",
        "sp_plain",
        "sc_cmd",
        "sc_arg",
        "sc_only",
        "sc_noarg",
        "sc_cmd3",
        "sc_rest",
        "pa_plain",
        "pa_quote",
        "pa_empty",
        "pa_miss",
        "lp_len",
        "lp_p",
        "lp_i",
        "sq_plain",
        "sq_space",
        "sq_quote",
        "sq_empty",
        "af_y",
        "af_yes",
        "af_trim",
        "af_no",
        "mc_fwd",
        "mc_bwd",
        "mc_wrap",
        "mc_miss",
        "mc_one",
        "mc_empty",
        "ms_quiet",
        "ms_empty",
        "ms_text",
        "ms_n",
        "ms_disabled",
        "pf_hello",
        "pf_n",
        "pf_img",
        "pb_ls",
        "pb_ls_ex",
        "pb_ls_ok",
        "pb_excl",
        "pb_excl_ex",
        "pb_excl_ok",
        "pb_bang",
        "pb_bang_ok",
        "pb_ws",
        "pb_ws_ok",
        "pb_plain_ok",
        "pb_n",
        "rt_one",
        "rt_two",
        "rt_empty",
        "rt_n",
        "dp_empty",
        "dp_ws",
        "dp_plain",
        "dp_plain_n",
        "dp_slash",
        "dp_bash",
        "dp_bash_n",
        "dp_bang",
        "dp_n",
        "sap_slash",
        "sap_backslash",
        "sap_jsonl",
        "sap_id",
        "sap_empty",
        "sap_json",
        "sc_name",
        "sc_name_arg",
        "sc_pad",
        "sc_import",
        "sc_empty",
        "sc_tab",
        "pca_none",
        "pca_plain",
        "pca_dq",
        "pca_sq",
        "pca_unclosed",
        "pca_extra",
        "dd_under",
        "dd_neq",
        "dd_dot",
        "ldd_under",
        "ldd_neq",
        "ldd_leaf",
        "mmc_mv",
        "mmc_old",
        "mmc_new",
        "mmc_space",
        "mmc_quote",
        "mbn_n",
        "mbn_fd",
        "mbn_rg",
        "mbn_fdexe",
        "mbn_rgexe",
        "mgu_eq",
        "mgu_https",
        "mgu_gh",
        "mgu_n",
        "edu_eq",
        "edu_https",
        "edu_gh",
        "edu_n"
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
        "cw_timeout",
        "cw_pred",
        "cw_abort",
        "rt_list",
        "rt_syms",
        "rt_sorted",
        "tj_value",
        "tj_done",
        "tj_reason",
        "cp_nil",
        "cp_true",
        "cp_false",
        "cp_err",
        "rr_new",
        "rr_dup",
        "rr_sort",
        "ra_hit",
        "ra_mark",
        "ra_miss",
        "ra_empty",
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
        "cfd_agents",
        "cfd_empty",
        "cfd_claude",
        "cfd_override",
        "cfd_n",
        "pc_n",
        "pc_cwd",
        "pc_cases",
        "nc_sys",
        "nc_append",
        "nc_miss",
        "nc_n",
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
