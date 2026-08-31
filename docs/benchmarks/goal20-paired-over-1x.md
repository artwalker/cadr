# Goal 20 — already-paired paths still >1.0× (docs only)

Friend-MachineD ledger in `docs/performance.md` (not a remesure).
**No optimize in this file.** Invent remains paused (十B.17–18).
G.17 stays `missing`. Not Goal 20 complete.

| metric | cadr µs | pi µs | ratio | ceiling | leftover | disposition |
|---|---:|---:|---:|---:|---|---|
| `session_pipeline.session_load` | 1762.6 | 1595.0 | 1.11× | 9.00× | `PARSE-SESSION-RECORD-OCTETS` vs V8 `JSON.parse` (compact-prefix + u32 entry + message first-byte kept) | invent pause; 待本质提案（分配/表示） |
| `storage_journal.journal_read` | 1577.6 | 1305.4 | 1.21× | 8.00× | `SCAN-BUFFER` / line consume; inline consume-line withdrawn | invent pause; 待本质提案 |
| `provider_pi_messages.stream_roundtrip` | 1080.8 | 830.4 | 1.30× | 1.50× | character `PARSE-JSON-SOURCE` on SSE; `WRITE-JSON-STRING`; EQUAL hash grow. parse-json-octets / unescaped stringify / pairs / pre-size withdrawn | invent pause; 待本质提案 |
| `provider_mistral.stream_roundtrip` | 2045.6 | 1644.0 | 1.24× | 3.00× | character `PARSE-JSON-SOURCE` on Conversations SSE; `data-octets` withdrawn | invent pause; 待本质提案 |
| `session_compact.compact` | 36.7 | 35.3 | 1.04× | 20.00× | near 1.0; uuid-v7 entropy pool already kept | 待 MAD/本质；不开现象刀 |
| `session_compact.branch_summarize` | 37.3 | 32.5 | 1.15× | 20.00× | measure-only pair 255; collect+generate branch summary | invent pause；地板优化另刀 |
| `session_discovery.header_probe` | 1449.6 | 708.6 | 2.05× | 8.00× | measure-only pair `f0a1ee93d`; not load-session | invent pause；地板优化另刀 |
| `session_export_html.to_html` | 29217.8 | 8239.7 | 3.55× | 20.00× | measure-only pair `7cefd82b9`; html_chars size gap booked | invent pause；地板优化另刀 |
| `harness_storage.open_walk` | 11643.5 | 6484.9 | 1.80× | 8.00× | measure-only pair `7d0d772b1`; branch_entry_count shape gap booked | invent pause；地板优化另刀 |
| `agent_proxy.stream_roundtrip` | 25.4 | 16.0 | 1.59× | 1.50× | measure-only pair `c5fa14820`; **over ceiling** (variance-bound 1.5) | invent pause；地板/抬天花板另刀 |
| `ai_crypto_model_data.manifest` | 77.3 | 8.6 | 8.97× | 20.00× | measure-only pair `287109b9e`; SHA-256 catalog (not dir walk) | invent pause；地板优化另刀 |
| `ai_crypto.hmac` | 133.9 | 7.1 | 18.81× | 30.00× | measure-only pair `e4eb5e647`; pure-Lisp SHA-256 vs OpenSSL | invent pause；地板优化另刀 |
| `cli_models_rest.pattern_match` | 31.9 | 19.4 | 1.65× | 3.00× | measure-only pair `53b522b00` | invent pause；地板优化另刀 |
| `image_runtime.dimensions` | 7.8 | 1.4 | 5.44× | 8.00× | measure-only pair `bc6e6a527`; header parse only | invent pause；地板优化另刀 |
| `image_runtime.mime_type` | 6.63 | 4.09 | 1.62× | 8.00× | measure-only pair `db66f79e6`; sibling of dimensions; JPEG 0xf7/APNG/BMP gaps booked | invent pause；地板优化另刀 |
| `image_runtime.lookup` | 1.51 | 0.20 | 7.38× | 8.00× | measure-only pair `6d48a539f`; catalog presence; count not exact; sub-µs variance | invent pause；地板优化另刀 |
| `image_runtime.dimension_note` | 3.67 | 2.12 | 1.73× | 8.00× | measure-only pair `94d472e68`; format note only (no decode/resize) | invent pause；地板优化另刀 |
| `image_runtime.api_provider` | 0.23 | 0.21 | 1.09× | 8.00× | measure-only pair `7823f9c15`; fixture registry lookup; sub-µs variance | invent pause；地板优化另刀 |
| `image_runtime.openrouter_content` | 1.367 | 0.409 | 3.34× | 8.00× | measure-only pair 299; OpenRouter content parts on `src/cadr-ai/images.lisp` | invent pause；地板优化另刀 |
| `image_runtime.parse_data_image` | 0.555 | 0.387 | 1.43× | 8.00× | measure-only pair 300; data-URL parse on `src/cadr-ai/images.lisp` | invent pause；地板优化另刀 |
| `image_runtime.openrouter_usage` | 2.167 | 0.514 | 4.22× | 8.00× | measure-only pair 367; OpenRouter usage parse on `src/cadr-ai/images.lisp` | invent pause；地板优化另刀 |
| `image_runtime.parse_openrouter_images` | 3.188 | 1.068 | 2.99× | 8.00× | measure-only pair 368; OpenRouter image response parse on `src/cadr-ai/images.lisp` | invent pause；地板优化另刀 |
| `image_runtime.error_result` | 1.047 | 0.346 | 3.03× | 8.00× | measure-only pair 369; image error/abort mapping on `src/cadr-ai/images.lisp` | invent pause；地板优化另刀 |
| `cli_print_rpc.jsonl_line` | 3.3 | 0.25 | 13.21× | 8.00× | measure-only pair `7178273d6`; **ratio > named ceiling**; sub-µs path — gate uses variance/10µs floor | invent pause；地板/抬天花板另刀 |
| `tui_latex.render` | 64.4 | 25.8 | 2.49× | 3.00× | measure-only pair `d73577497` | invent pause；地板优化另刀 |
| `tui_theme_overlay.osc11_bg` | 3.8 | 3.3 | 1.16× | 8.00× | measure-only pair `5f8210ae6` | invent pause；地板优化另刀 |
| `ai_support.estimate_text` | 0.54 | 0.17 | 3.10× | 8.00× | measure-only pair `0aac11a8d`; sub-µs — variance floor applies | invent pause；地板优化另刀 |
| `tui_select_settings_loaders.filter` | 1.2 | 1.0 | 1.27× | 8.00× | measure-only pair `096fcc540`; sub-µs — variance floor applies | invent pause；地板优化另刀 |
| `tui_autocomplete.suggest_apply` | 136.4 | 26.4 | 5.17× | 8.00× | measure-only pair `5fb0f589d` | invent pause；地板优化另刀 |
| `tui_keybindings.resolve_match` | 27.7 | 14.8 | 1.88× | 8.00× | measure-only pair `0d2c6c287` | invent pause；地板优化另刀 |
| `tui_native_modifiers.pressed` | 1.22 | 0.16 | 7.50× | 8.00× | measure-only pair `791ea158e`; Linux no-addon gate (all 0); sub-µs variance | invent pause；地板优化另刀 |
| `ai_capabilities.short_hash` | 1.5 | 0.9 | 1.70× | 8.00× | measure-only pair `f5e3817db`; sub-µs — variance floor applies | invent pause；地板优化另刀 |
| `ai_capabilities.deferred_tools` | 5.51 | 2.70 | 2.04× | 8.00× | measure-only pair `8924f239d`; sibling of short_hash | invent pause；地板优化另刀 |
| `ai_capabilities.event_stream` | 1.73 | 1.20 | 1.44× | 8.00× | measure-only pair `eedd1753d`; sibling of short_hash/deferred | invent pause；地板优化另刀 |
| `cli_support.strip_ansi` | 1.3 | 0.5 | 2.73× | 8.00× | measure-only pair `b0c27cd59`; sub-µs — variance floor applies | invent pause；地板优化另刀 |
| `cli_interactive_controller.decode_entity` | 0.63 | 0.42 | 1.49× | 8.00× | measure-only pair `1cc4b83d5`; sub-µs — variance floor applies | invent pause；地板优化另刀 |
| `provider_registry_defs.lookup` | 1.03 | 0.23 | 4.44× | 8.00× | measure-only pair `cec8aa391`; catalog count gap booked (40/39); sub-µs variance | invent pause；地板优化另刀 |
| `skill_prompt_load.build_prompt` | 2196 | 1.88 | 1170.57× | 3000.00× | measure-only pair `221af13c1`; **keyword initforms still hit ASDF** | invent pause；地板/去 ASDF 另刀 |
| `ai_support.auth_guidance` | 1922 | 69.5 | 27.66× | 50.00× | measure-only pair `b04d7b46e`; **ASDF docs-dir** (prefix-only exact) | invent pause；地板/去 ASDF 另刀 |
| `cli_bootstrap_sessions.coding_tools` | 11.1 | 4.6 | 2.40× | 8.00× | measure-only pair `e8da8ac48` | invent pause；地板优化另刀 |
| `ai_runtime_faux.blocks` | 0.27 | 0.15 | 1.76× | 8.00× | measure-only pair `25826109b`; sub-µs — variance floor applies | invent pause；地板优化另刀 |
| `cli_support.normalize_path` | 4.58 | 1.63 | 2.82× | 8.00× | measure-only pair `03559cdc7`; sibling of strip_ansi | invent pause；地板优化另刀 |
| `cli_support.timings` | 4.55 | 2.66 | 1.71× | 8.00× | measure-only pair `477f6d74f`; sibling of strip_ansi/normalize_path | invent pause；地板优化另刀 |
| `ai_support.context_overflow` | 1.85 | 1.11 | 1.67× | 8.00× | measure-only pair `e03a52133`; sibling of estimate_text | invent pause；地板优化另刀 |
| `ai_support.grammar_delta` | 1.52 | 0.53 | 2.87× | 8.00× | measure-only pair `1cc632962`; sibling of estimate/overflow | invent pause；地板优化另刀 |

| `cli_support.shell_config` | 21.07 | 8.54 | 2.47× | 8.00× | measure-only pair `ae3b0c1c9`; sibling of strip_ansi/timings/event_bus/attribution | invent pause；地板优化另刀 |

| `cli_support.user_agent` | 1.41 | 0.45 | 3.14× | 8.00× | measure-only pair `32e7f115c`; sibling of git_source; sub-µs — variance floor applies | invent pause；地板优化另刀 |

| `cli_support.parse_changelog` | 36.04 | 12.20 | 2.96× | 8.00× | measure-only pair `114022abc`; sibling of strip_ansi in changelog-share | invent pause；地板优化另刀 |

| `cli_sdk.thinking_level` | 0.72 | 0.22 | 3.21× | 8.00× | measure-only pair `eb82f8ee8`; sibling of cache_miss/waste; sub-µs — variance floor applies | invent pause；地板优化另刀 |

| `oauth_pkce_device.auth_json` | 257.5 | 212.9 | 1.21× | 8.00× | measure-only pair `abea28244`; sibling of poll | invent pause；地板优化另刀 |

| `oauth_pkce_device.copilot_url` | 2.12 | 1.85 | 1.15× | 8.00× | measure-only pair `15853bedf`; sibling of auth_json/poll | invent pause；地板优化另刀 |

| `cli_sdk.session_list` | 15402 | 7989 | 1.93× | 8.00× | measure-only pair `40e704d50`; SessionManager.list vs session-manager-list | invent pause；地板优化另刀 |

| `oauth_pkce_device.cloudflare_url` | 9.27 | 1.39 | 6.66× | 8.00× | measure-only pair `7b718d200`; variance floor; near ceiling | invent pause；地板优化另刀 |

| `oauth_pkce_device.radius_gateway` | 0.57 | 0.54 | 1.05× | 8.00× | measure-only pair `08636862d`; sub-µs — variance floor applies | invent pause；地板优化另刀 |

| `cli_interactive_controller.wayland` | 0.36 | 0.30 | 1.17× | 8.00× | measure-only pair `25263186a`; sub-µs — variance floor applies | invent pause；地板优化另刀 |

| `evals_harness.group_key` | 5.01 | 1.23 | 4.06× | 8.00× | measure-only pair `b4a1fe51d`; variance floor | invent pause；地板优化另刀 |

| `oauth_pkce_device.copilot_auth` | 3.21 | 2.38 | 1.35× | 8.00× | measure-only pair `1cd076b8d`; sibling of copilot_url | invent pause；地板优化另刀 |

| `cli_selectors.session_search` | 42.40 | 17.10 | 2.48× | 8.00× | measure-only pair `51b4a868e`; filter/sort only | invent pause；地板优化另刀 |

| `websocket_stream.stream_roundtrip` | 44298 | 87.25 | 507.72× | 800.00× | measure-only pair `11ab40877`; TCP loopback vs MockWebSocket shape gap | invent pause；地板优化另刀 |

| `cli_selectors.key_text` | 5.76 | 2.01 | 2.86× | 8.00× | measure-only pair `23eb31564`; format only | invent pause；地板优化另刀 |

| `evals_harness.format` | 20.62 | 18.10 | 1.14× | 8.00× | measure-only pair `23ba2b271`; sibling of summarize | invent pause；地板优化另刀 |

| `cli_interactive_controller.auth_type` | 0.21 | 0.15 | 1.44× | 8.00× | measure-only pair `39ff7f5c4`; sub-µs — variance floor applies | invent pause；地板优化另刀 |

| `agent_tool_loop.tool_path` | 12.74 | 5.23 | 2.44× | 8.00× | measure-only pair `9b37f5914`; resolve only | invent pause；地板优化另刀 |
| `agent_tool_loop.runtime` | 7.8 | 1.2 | 6.30× | 8.00× | measure-only pair 253; steering/follow-up queue enqueue/drain/clear | invent pause；地板优化另刀 |

| `agent_tool_loop.line_ending` | 0.75 | 0.38 | 1.99× | 8.00× | measure-only pair `7c9e733a6`; sub-µs — variance floor applies | invent pause；地板优化另刀 |

| `cli_selectors.visible_slice` | 2.5 | 1.1 | 2.23× | 8.00× | measure-only pair `549643880`; viewport slice only | invent pause；地板优化另刀 |

| `cli_selectors.move_index` | 4.5 | 3.1 | 1.44× | 8.00× | measure-only pair `1445967bf`; mod-wrap only | invent pause；地板优化另刀 |

| `cli_selectors.align_left_right` | 27.2 | 7.2 | 3.79× | 8.00× | measure-only pair `6c2f97c61`; truncate/pad only | invent pause；地板优化另刀 |

| `cli_selectors.modified_cursor_key` | 47.3 | 4.1 | 11.56× | 20.00× | measure-only pair `f5a3f5bfa`; CSI modified arrows only | invent pause；地板优化另刀 |

| `cli_selectors.keybinding_hint` | 59.9 | 23.2 | 1.32× | 8.00× | measure-only pair `120292c32`; rawKeyHint dim/muted on joined keys | invent pause；地板优化另刀 |

| `cli_selectors.session_record_label` | 2.6 | 1.4 | 1.84× | 8.00× | measure-only pair `c10fe79bb`; row label sanitize only | invent pause；地板优化另刀 |

| `cli_selectors.session_shorten_path` | 5.5 | 1.1 | 5.05× | 8.00× | measure-only pair `69334160e`; home tilde shorten only | invent pause；地板优化另刀 |

| `cli_selectors.session_quoted_search` | 11.0 | 8.6 | 1.29× | 8.00× | measure-only pair `27579bfa1`; quoted phrase position only | invent pause；地板优化另刀 |

| `cli_selectors.session_thread_records` | 165.9 | 12.7 | 13.07× | 30.00× | measure-only pair `9964bdb69`; thread tree flatten only | invent pause；地板优化另刀 |

| `cli_selectors.session_binding_label` | 41.2 | 28.9 | 1.43× | 8.00× | measure-only pair `d080c3d21`; first key or binding id fallback | invent pause；地板优化另刀 |

| `cli_selectors.session_named_p` | 0.6 | 0.3 | 2.11× | 8.00× | measure-only pair `d0a390735`; named-session predicate only | invent pause；地板优化另刀 |

| `cli_selectors.settings_display_value` | 0.6 | 0.2 | 3.39× | 8.00× | measure-only pair `e47e7382c`; settings value label only | invent pause；地板优化另刀 |

| `cli_interactive_controller.parse_auto_theme` | 1.0 | 0.5 | 1.96× | 8.00× | measure-only pair `ea3915685`; auto theme parse only | invent pause；地板优化另刀 |

| `cli_interactive_controller.resolve_theme` | 0.8 | 0.7 | 1.16× | 8.00× | measure-only pair `e4918c77c`; resolve auto/fixed theme only | invent pause；地板优化另刀 |

| `cli_selectors.settings_automatic_theme_setting` | 0.4 | 0.2 | 2.42× | 8.00× | measure-only pair `2bbd1b489`; automatic theme format only | invent pause；地板优化另刀 |

| `cli_selectors.settings_active_automatic_theme` | 0.2 | 0.1 | 1.33× | 8.00× | measure-only pair `f52dd27bf`; terminal branch pick only | invent pause；地板优化另刀 |

| `cli_selectors.settings_cycle` | 2.0 | 0.5 | 4.13× | 8.00× | measure-only pair `0c9cb67b2`; settings value cycle only | invent pause；地板优化另刀 |

| `cli_selectors.settings_apply_filter` | 7.8 | 4.8 | 1.61× | 8.00× | measure-only pair `ef32cddbe`; settings filter + selected reset | invent pause；地板优化另刀 |

| `cli_selectors.tree_query_matches` | 5.2 | 2.3 | 2.20× | 8.00× | measure-only pair `12b48fb83`; tree search token predicate only | invent pause；地板优化另刀 |

| `cli_selectors.tree_entry_search_text` | 1.8 | 1.5 | 1.22× | 8.00× | measure-only pair `4691dc64c`; tree search haystack join only | invent pause；地板优化另刀 |

| `cli_selectors.tree_normalize_display_text` | 4.3 | 1.5 | 2.88× | 8.00× | measure-only pair `549191a19`; display text normalize only | invent pause；地板优化另刀 |

| `cli_selectors.tree_status_labels` | 4.1 | 0.5 | 8.92× | 8.00× | measure-only pair `41f43d1d8`; filter/timestamp status suffix only | invent pause；地板优化另刀 |

| `cli_selectors.tree_shorten_path` | 2.7 | 1.6 | 1.76× | 8.00× | measure-only pair `de5c850ff`; tree formatToolCall shortenPath only | invent pause；地板优化另刀 |

| `cli_selectors.tree_foldable_p` | 4.1 | 1.5 | 2.79× | 8.00× | measure-only pair `abe413c80`; tree isFoldable predicate only | invent pause；地板优化另刀 |

| `cli_selectors.tree_tool_argument` | 24.7 | 7.4 | 3.32× | 8.00× | measure-only pair `841211d61`; tree tool-arg path lookup only | invent pause；地板优化另刀 |

| `cli_selectors.tree_cycle_filter` | 4.8 | 0.3 | 17.08× | 8.00× | measure-only pair `637496621`; tree filter cycle only | invent pause；地板优化另刀 |

| `cli_selectors.tree_format_label_timestamp` | 9.2 | 4.9 | 1.85× | 8.00× | measure-only pair `9b65af57f`; tree label timestamp only | invent pause；地板优化另刀 |

| `cli_selectors.tree_format_tool_call` | 14.1 | 2.4 | 5.86× | 8.00× | measure-only pair `516eaace1`; tree formatToolCall only | invent pause；地板优化另刀 |

| `cli_selectors.tree_entry_display_text` | 19.2 | 3.3 | 5.79× | 8.00× | measure-only pair `476fa75b5`; tree getEntryDisplayText only | invent pause；地板优化另刀 |
| `cli_selectors.tree_help_keys` | 190.2 | 41.7 | 4.56× | 8.00× | measure-only pair (Pair 160); tree formatHelpKeys compaction only | invent pause；地板优化另刀 |
| `cli_selectors.tree_help_lines` | 979.6 | 293.8 | 3.33× | 8.00× | measure-only pair (Pair 161); TreeHelp chunk wrap + muted theme | invent pause；地板优化另刀 |
| `cli_selectors.tree_active_path` | 11.8 | 4.8 | 2.43× | 8.00× | measure-only pair (Pair 162); leaf-to-root ancestor walk | invent pause；地板优化另刀 |
| `cli_selectors.tree_nearest_visible_id` | 14.9 | 6.4 | 2.34× | 8.00× | measure-only pair (Pair 163); visible ancestor walk + fallback | invent pause；地板优化另刀 |
| `cli_selectors.tree_prioritize_active` | 16.3 | 8.9 | 1.83× | 8.00× | measure-only pair (Pair 164); active-path entry reorder | invent pause；地板优化另刀 |
| `cli_selectors.tree_rebuild_visible_maps` | 41.3 | 27.7 | 1.49× | 8.00× | measure-only pair (Pair 165); visible parent/children maps | invent pause；地板优化另刀 |
| `cli_selectors.tree_apply_filter` | 71.6 | 19.9 | 3.60× | 8.00× | measure-only pair (Pair 166); filter/fold/query + selection preserve | invent pause；地板优化另刀 |
| `cli_selectors.tree_move` | 331.4 | 190.3 | 1.74× | 8.00× | measure-only pair (Pair 168); visible-id selection move | invent pause；地板优化另刀 |
| `cli_selectors.tree_fold_or_up` | 316.9 | 179.6 | 1.76× | 8.00× | measure-only pair (Pair 169); fold or branch-segment up | invent pause；地板优化另刀 |
| `cli_selectors.tree_unfold_or_down` | 324.4 | 178.0 | 1.82× | 8.00× | measure-only pair (Pair 170); unfold or move down | invent pause；地板优化另刀 |
| `cli_selectors.tree_branch_segment_id` | 264.9 | 145.6 | 1.82× | 8.00× | measure-only pair (Pair 171); branch-segment start up/down | invent pause；地板优化另刀 |
| `cli_selectors.tree_copy_selected` | 142.5 | 49.6 | 2.87× | 8.00× | measure-only pair (Pair 174); copy selected entry text | invent pause；地板优化另刀 |
| `cli_selectors.tree_start_label_edit` | 150.8 | 62.9 | 2.40× | 8.00× | measure-only pair (Pair 176); enter label-edit mode | invent pause；地板优化另刀 |
| `cli_selectors.tree_confirm_label` | 260.2 | 59.5 | 4.37× | 8.00× | measure-only pair (Pair 177); confirm label edit | invent pause；地板优化另刀 |
| `cli_selectors.tree_cancel_label` | 214.6 | 136.7 | 1.57× | 8.00× | measure-only pair (Pair 178); cancel label edit | invent pause；地板优化另刀 |
| `cli_selectors.tree_handle_raw_input` | 1068.1 | 263.3 | 4.06× | 8.00× | measure-only pair (Pair 179); keybinding dispatch | invent pause；地板优化另刀 |
| `cli_selectors.tree_selected_entry` | 199.5 | 38.8 | 5.14× | 8.00× | measure-only pair (Pair 182); selected entry lookup | invent pause；地板优化另刀 |
| `cli_selectors.tree_select_id` | 217.0 | 46.7 | 4.64× | 8.00× | measure-only pair (Pair 183); visible-id selection | invent pause；地板优化另刀 |
| `cli_selectors.tree_visible_ids` | 82.1 | 14.2 | 5.78× | 8.00× | measure-only pair (Pair 184); visible id list | invent pause；地板优化另刀 |
| `cli_selectors.tree_selected_id` | 213.4 | 85.3 | 2.50× | 8.00× | measure-only pair (Pair 185); selected id accessor | invent pause；地板优化另刀 |
| `cli_selectors.tree_entry_map` | 11.6 | 4.2 | 2.76× | 8.00× | measure-only pair (Pair 186); id→entry map | invent pause；地板优化另刀 |
| `cli_selectors.tree_order_entries` | 38.4 | 31.7 | 1.21× | 8.00× | measure-only pair (Pair 187); DFS entry order | invent pause；地板优化另刀 |
| `cli_selectors.tree_iso_timestamp` | 6.1 | 4.3 | 1.43× | 8.00× | measure-only pair (Pair 188); ISO timestamp formatter | invent pause；地板优化另刀 |
| `cli_selectors.tree_help_key` | 58.4 | 34.4 | 1.70× | 8.00× | measure-only pair (Pair 189); single help key lookup | invent pause；地板优化另刀 |
| `cli_selectors.project_trust_options` | 72.9 | 62.9 | 1.16× | 8.00× | measure-only pair (Pair 191); trust option list | invent pause；地板优化另刀 |
| `cli_selectors.trust_selector_selection` | 242.4 | 64.1 | 3.78× | 8.00× | measure-only pair (Pair 192); trust selection at index | invent pause；地板优化另刀 |
| `cli_selectors.trust_decision_description` | 156.7 | 66.4 | 2.36× | 8.00× | measure-only pair (Pair 193); saved decision label | invent pause；地板优化另刀 |
| `cli_selectors.trust_selector_move` | 328.1 | 133.3 | 2.46× | 8.00× | measure-only pair (Pair 194); trust list navigation | invent pause；地板优化另刀 |
| `cli_selectors.trust_selector_handle_event` | 333.3 | 142.1 | 2.35× | 8.00× | measure-only pair (Pair 195); trust event dispatch | invent pause；地板优化另刀 |
| `cli_selectors.trust_selector_handle_raw_input` | 693.8 | 233.2 | 2.98× | 8.00× | measure-only pair (Pair 196); trust raw input dispatch | invent pause；地板优化另刀 |
| `cli_selectors.trust_selector_ui_state` | 394.9 | 173.7 | 2.27× | 8.00× | measure-only pair (Pair 197); trust selector UI state digest | invent pause；地板优化另刀 |
| `cli_selectors.oauth_option_status_label` | 2.1 | 0.8 | 2.46× | 8.00× | measure-only pair (Pair 198); oauth status label | invent pause；地板优化另刀 |
| `cli_selectors.credential_entry_auth_type` | 0.6 | 0.3 | 1.87× | 8.00× | measure-only pair (Pair 199); credential kind normalization | invent pause；地板优化另刀 |
| `cli_selectors.oauth_environment_source_p` | 1.2 | 0.3 | 3.51× | 8.00× | measure-only pair (Pair 200); env source regex | invent pause；地板优化另刀 |
| `cli_selectors.oauth_selector_selection` | 103.4 | 27.2 | 3.80× | 8.00× | measure-only pair (Pair 201); oauth selector selection | invent pause；地板优化另刀 |
| `cli_selectors.oauth_selector_apply_filter` | 113.2 | 29.5 | 3.84× | 8.00× | measure-only pair (Pair 202); oauth selector filter | invent pause；地板优化另刀 |
| `cli_selectors.oauth_selector_handle_event` | 138.2 | 113.6 | 1.22× | 8.00× | measure-only pair (Pair 203); oauth selector events | invent pause；地板优化另刀 |
| `cli_selectors.oauth_selector_handle_raw_input` | 691.4 | 137.7 | 5.02× | 8.00× | measure-only pair (Pair 204); oauth raw input dispatch | invent pause；地板优化另刀 |
| `cli_selectors.oauth_selector_search_text` | 9.5 | 6.2 | 1.52× | 8.00× | measure-only pair (Pair 205); oauth filter search text | invent pause；地板优化另刀 |
| `cli_selectors.login_auth_type_route` | 3.8 | 1.1 | 3.44× | 8.00× | measure-only pair (Pair 206); login auth-type routing | invent pause；地板优化另刀 |
| `cli_selectors.logout_provider_options` | 10.4 | 3.8 | 2.71× | 8.00× | measure-only pair (Pair 208); logout provider projection | invent pause；地板优化另刀 |
| `cli_selectors.oauth_selector_move` | 83.8 | 3.1 | 27.34× | 50.00× | measure-only pair (Pair 210); oauth selector wrap move | invent pause；地板优化另刀 |
| `cli_selectors.oauth_option_status_rendered` | 13.9 | 1.4 | 10.02× | 15.00× | measure-only pair (Pair 211); themed status indicator | invent pause；地板优化另刀 |
| `cli_selectors.api_key_input_state_handle_event` | 7.0 | 4.2 | 1.66× | 8.00× | measure-only pair (Pair 212); api key overlay dispatch | invent pause；地板优化另刀 |
| `cli_selectors.login_method_selector_ui_state` | 622.6 | 61.8 | 10.07× | 12.00× | measure-only pair (Pair 213); login method selector UI | invent pause；地板优化另刀 |
| `cli_selectors.api_key_input_ui_state` | 263.5 | 54.2 | 4.86× | 8.00× | measure-only pair (Pair 214); api key overlay UI | invent pause；地板优化另刀 |
| `cli_selectors.oauth_selector_ui_state` | 372.1 | 15.1 | 24.66× | 35.00× | measure-only pair (Pair 215); oauth selector UI | invent pause；地板优化另刀 |
| `cli_selectors.model_selector_search_text` | 5.6 | 0.8 | 6.78× | 8.00× | measure-only pair (Pair 216); model selector search text | invent pause；地板优化另刀 |
| `cli_selectors.qualified_model_id` | 2.1 | 0.3 | 7.65× | 8.00× | measure-only pair (Pair 217); provider/id label | invent pause；地板优化另刀 |
| `cli_selectors.model_selector_apply_filter` | 130.9 | 23.7 | 5.53× | 8.00× | measure-only pair (Pair 218); model selector fuzzy filter | invent pause；地板优化另刀 |
| `cli_selectors.model_selector_move` | 102.3 | 5.5 | 18.60× | 20.00× | measure-only pair (Pair 219); model selector wrap move | invent pause；地板优化另刀 |
| `cli_selectors.model_selector_handle_event` | 147.6 | 27.5 | 5.37× | 8.00× | measure-only pair (Pair 220); model selector event dispatch | invent pause；地板优化另刀 |
| `cli_selectors.model_selector_handle_raw_input` | 823.0 | 116.3 | 7.08× | 8.00× | measure-only pair (Pair 221); model selector raw key dispatch | invent pause；地板优化另刀 |
| `cli_selectors.model_selector_set_query` | 148.5 | 38.6 | 3.85× | 8.00× | measure-only pair (Pair 222); model selector query update | invent pause；地板优化另刀 |
| `cli_selectors.model_selector_selected_model` | 160.3 | 20.3 | 7.90× | 12.00× | measure-only pair (Pair 223); model selector selected lookup | invent pause；地板优化另刀 |
| `cli_selectors.model_selector_toggle_scope` | 141.1 | 25.9 | 5.45× | 8.00× | measure-only pair (Pair 224); model selector scope toggle | invent pause；地板优化另刀 |
| `cli_selectors.model_selector_ui_state` | 648.3 | 29.9 | 21.70× | 35.00× | measure-only pair (Pair 225); model selector UI render | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_set_query` | 272.7 | 40.1 | 6.80× | 8.00× | measure-only pair (Pair 226); scoped models query update | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_move` | 170.8 | 11.7 | 14.63× | 20.00× | measure-only pair (Pair 227); scoped models wrap move | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_handle_event` | 246.1 | 36.4 | 6.76× | 12.00× | measure-only pair (Pair 228); scoped models event dispatch | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_handle_raw_input` | 1,638.3 | 181.4 | 9.03× | 8.00× | measure-only pair (Pair 229); scoped models raw key dispatch | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_ui_state` | 1,636.7 | 49.5 | 33.04× | 35.00× | measure-only pair (Pair 230); scoped models UI render | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_counts` | 158.5 | 3.7 | 43.32× | 55.00× | measure-only pair (Pair 232); scoped models footer enabled/unavailable counts | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_sorted_ids` | 145.0 | 3.9 | 37.36× | 50.00× | measure-only pair (Pair 233); scoped models enabled-first sort | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_toggle_selected` | 247.0 | 83.7 | 2.95× | 8.00× | measure-only pair (Pair 231); scoped models confirm toggle | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_target_ids` | 240.6 | 45.7 | 5.27× | 8.00× | measure-only pair (Pair 234); enableAll/clearAll targetIds | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_enable_all` | 384.3 | 18.5 | 20.77× | 25.00× | measure-only pair (Pair 235); scoped models enableAll | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_toggle_provider` | 303.9 | 66.8 | 4.55× | 8.00× | measure-only pair (Pair 236); scoped models toggleProvider | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_clear_all` | 287.2 | 13.6 | 21.18× | 25.00× | measure-only pair (Pair 237); scoped models clearAll | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_persist` | 208.1 | 15.3 | 13.58× | 25.00× | measure-only pair (Pair 239); scoped models onPersist | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_provider_count` | 182.6 | 3.9 | 46.51× | 50.00× | measure-only pair (Pair 240); scoped models provider count | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_rebuild_models_by_id` | 10.000 | 4.771 | 2.096× | 8.00× | measure-only leftover 580; `scoped-models-selector-rebuild-models-by-id` vs `modelsById` rebuild | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_model_by_id` | 9.193 | 2.886 | 3.185× | 8.00× | measure-only leftover 581; `scoped-models-model-by-id` vs `modelsById` lookup | invent pause；地板优化另刀 |
| `cli_selectors.scoped_model_item_search_text` | 2.879 | 0.771 | 3.735× | 8.00× | measure-only leftover 582; `scoped-model-item-search-text` vs `getModelSearchText` | invent pause；地板优化另刀 |
| `tui_latex.normalize_output` | 12.7 | 8.7 | 1.46× | 20.00× | measure-only pair (Pair 243); latex marker cleanup | invent pause；地板优化另刀 |
| `file_mutation_queue.queue_key` | 169.3 | 156.2 | 1.08× | 8.00× | measure-only pair 270; `file-mutation-queue-key` only (not `with_queue`) | invent pause；地板优化另刀 |
| `file_mutation_queue.lock` | 183.3 | 148.0 | 1.24× | 8.00× | measure-only pair 271; `file-mutation-queue-lock` only (not `with_queue` / `queue_key`) | invent pause；地板优化另刀 |
| `bash_tool.strip_exit_footer` | 0.989 | 0.619 | 1.60× | 8.00× | measure-only pair 277; `bash-strip-exit-footer` only (not execute/spawn); sub-µs — variance floor applies | invent pause；地板优化另刀 |
| `bash_tool.append_status` | 1.109 | 0.381 | 2.91× | 8.00× | measure-only pair 278; `append-bash-status` vs `appendStatus`; sub-µs — variance floor applies | invent pause；地板优化另刀 |
| `bash_tool.truncation_notice` | 2.798 | 0.832 | 3.36× | 8.00× | measure-only pair 279; `bash-truncation-notice` vs `formatOutput` notice body | invent pause；地板优化另刀 |
| `harness_events.make_start` | 0.14 | 0.12 | 1.18× | 8.00× | measure-only pair 285; `make-run-start-event` vs `RunStartEvent` object (sub-µs variance) | invent pause；地板优化另刀 |
| `file_mutation_queue.make_state` | 105.7 | 66.2 | 1.597× | 8.00× | measure-only pair 287; `make-file-mutation-queue-state` vs JS object literal | invent pause；地板优化另刀 |
| `file_mutation_queue.state_key` | 134.3 | 133.1 | 1.009× | 8.00× | measure-only pair 288; `file-mutation-queue-state-key` after ensure | invent pause；地板优化另刀 |
| `find_tool.pattern_match` | 30.5 | 4.26 | 7.16× | 8.00× | measure-only pair 289; `find-pattern-match-p` basename vs path glob | invent pause；地板优化另刀 |
| `find_tool.find_files` | 633.4 | 184.1 | 3.44× | 8.00× | measure-only pair 290; `find-files` empty copy + fixture counts | invent pause；地板优化另刀 |
| `find_tool.make_tool` | 131.9 | 93.3 | 1.41× | 8.00× | measure-only pair 291; `make-find-tool` vs `createFindToolDefinition` | invent pause；地板优化另刀 |
| `tool_manager.cleanup_quarantine` | 120.1 | 88.0 | 1.37× | 8.00× | measure-only pair 294; `cleanup-windows-self-update-quarantine` (not download/ensure) | invent pause；地板优化另刀 |
| `evals_harness.transcript` | 3.80 | 2.18 | 1.743× | 8.00× | measure-only pair 326; `messages-to-transcript` vs `toTranscriptEvents` | invent pause；地板优化另刀 |
| `evals_harness.last_assistant` | 0.579 | 0.560 | 1.034× | 8.00× | measure-only pair 327; `last-assistant-since` vs promptAgent slice; sub-µs — variance floor applies | invent pause；地板优化另刀 |
| `evals_harness.content_text` | 0.997 | 0.719 | 1.386× | 8.00× | measure-only pair 364; `message-content-text` vs `contentText`; sub-µs — variance floor applies | invent pause；地板优化另刀 |
| `evals_harness.transcript_event` | 1.016 | 0.178 | 5.702× | 8.00× | measure-only pair 365; `transcript-message-event` vs message object; sub-µs — variance floor applies | invent pause；地板优化另刀 |
| `provider_registry_defs.runtime_models` | 17.89 | 4.794 | 3.73× | 8.00× | measure-only pair 296; leftover `provider-runtime-models` vs `getBuiltinModels` | invent pause；地板优化另刀 |
| `core_rest.redacted_secrets` | 2.750 | 1.105 | 2.49× | 8.00× | measure-only pair 323; leftover `redact-secrets` vs String.split/join | invent pause；地板优化另刀 |
| `powershell_tool.utf8_prefix` | 0.647 | 0.171 | 3.79× | 8.00× | measure-only pair 301; `+powershell-utf8-output-prefix+` vs `UTF8_OUTPUT_PREFIX` (not execute/spawn); sub-µs — variance floor applies | invent pause；地板优化另刀 |
| `powershell_tool.prefix_command` | 0.468 | 0.336 | 1.39× | 8.00× | measure-only pair 302; UTF-8 prefix + command concatenate (not exec/spawn) | invent pause；地板优化另刀 |
| `powershell_tool.make_tool` | 1.936 | 1.448 | 1.34× | 8.00× | measure-only pair 303; `make-powershell-tool` vs `createPowerShellToolDefinition` | invent pause；地板优化另刀 |
| `harness_events.make_end` | 0.216 | 0.137 | 1.574× | 8.00× | measure-only pair 313; `make-run-end-event` vs `RunEndEvent` object (sub-µs variance) | invent pause；地板优化另刀 |
| `harness_events.event_type` | 0.175 | 0.119 | 1.468× | 8.00× | measure-only pair 314; `harness-event-type` vs `event.type` (sub-µs variance) | invent pause；地板优化另刀 |
| `harness_events.make_bus` | 0.344 | 0.255 | 1.351× | 8.00× | measure-only pair 315; `make-harness-event-bus` vs `new HarnessEventBus()` (sub-µs variance) | invent pause；地板优化另刀 |
| `write_tool.write_utf8` | 169.771 | 135.369 | 1.254× | 8.00× | measure-only pair 344; `write-utf8-file` vs `fs.writeFile` utf-8 | invent pause；地板优化另刀 |
| `write_tool.make_tool` | 13.633 | 4.343 | 3.139× | 8.00× | measure-only pair 345; `make-write-tool` vs `createWriteToolDefinition` | invent pause；地板优化另刀 |
| `evals_harness.step_value` | 0.774 | 0.210 | 3.693× | 8.00× | measure-only pair 331; leftover `step-value` vs step property access (sub-µs variance) | invent pause；地板优化另刀 |
| `evals_harness.usage` | 2.240 | 1.042 | 2.148× | 8.00× | measure-only pair 332; leftover `eval-usage` vs usage object assembly | invent pause；地板优化另刀 |
| `evals_harness.result_json` | 1.933 | 0.370 | 5.225× | 8.00× | measure-only pair 333; leftover `eval-result-json` vs SimpleHarnessResult JSON shape | invent pause；地板优化另刀 |
| `evals_harness.eval_environment` | 0.758 | 0.282 | 2.692× | 8.00× | measure-only pair 346; `eval-environment` getenv+trim leftover (sub-µs variance) | invent pause；地板优化另刀 |
| `tui_select_settings_loaders.update_display` | 0.282 | 0.230 | 1.225× | 8.00× | measure-only pair 433; leftover `loader-component-update-display` vs `Loader.updateDisplay` (sub-µs variance) | invent pause；地板优化另刀 |
| `ls_tool.list_directory` | 352.2 | 314.9 | 1.119× | 8.00× | measure-only pair 317; `list-directory` empty/mixed/limit listing | invent pause；地板优化另刀 |
| `ls_tool.make_tool` | 284.4 | 279.6 | 1.017× | 8.00× | measure-only pair 318; `make-ls-tool` vs `createLsToolDefinition` | invent pause；地板优化另刀 |
| `cli_interactive_controller.clipboard_candidates` | 2.349 | 1.672 | 1.405× | 8.00× | measure-only leftover pair 535; `clipboard-command-candidates` vs copy argv lists | invent pause；地板优化另刀 |
| `cli_interactive_controller.osc52_copy` | 1.614 | 1.547 | 1.043× | 8.00× | measure-only leftover pair 536; `osc52-copy-sequence` vs OSC 52 encode | invent pause；地板优化另刀 |
| `cli_interactive_controller.clipboard_copy` | 1.911 | 1.680 | 1.137× | 8.00× | measure-only leftover pair 537; `copy-to-clipboard` vs injected copyToClipboard | invent pause；地板优化另刀 |
| `cli_settings.enabled_models` | 18.7 | 3.26 | 5.735× | 8.00× | measure-only pair 308; `settings-enabled-models` missing→`:all` plus one in-memory pattern | invent pause；地板优化另刀 |
| `cli_settings.block_images` | 19.1 | 3.41 | 5.623× | 8.00× | measure-only pair 309; `settings-block-images-p` default false plus in-memory `images.blockImages` | invent pause；地板优化另刀 |
| `evals_harness.make_eval_root` | 73.6 | 44.0 | 1.672× | 8.00× | measure-only pair 349; `make-eval-root` isolated eval directory leftover | invent pause；地板优化另刀 |
| `evals_harness.normalize_step_type` | 0.256 | 0.255 | 1.003× | 8.00× | measure-only pair 350; `normalize-step-type` leftover (sub-µs variance) | invent pause；地板优化另刀 |
| `evals_harness.selected_eval_tools` | 19.9 | 13.2 | 1.506× | 8.00× | measure-only pair 351; `selected-eval-tools` default/:all/exclude filter | invent pause；地板优化另刀 |

| `file_mutation_queue.pending_count` | 194.6 | 135.5 | 1.435× | 8.00× | measure-only pair 304; `file-mutation-queue-state-pending-count` after enqueue | invent pause；地板优化另刀 |
| `file_mutation_queue.next_ticket` | 157.9 | 137.6 | 1.147× | 8.00× | measure-only pair 305; `file-mutation-queue-state-next-ticket` after enqueue | invent pause；地板优化另刀 |
| `file_mutation_queue.waitqueue` | 120.311 | 107.377 | 1.120× | 8.00× | measure-only pair 328; `file-mutation-queue-state-waitqueue` vs `state.current` | invent pause；地板优化另刀 |
| `file_mutation_queue.state_p` | 100.853 | 70.044 | 1.440× | 8.00× | measure-only pair 330; `file-mutation-queue-state-p` vs queue-state object predicate | invent pause；地板优化另刀 |
| `oauth_pkce_device.percent_decode` | 1.592 | 1.044 | 1.525× | 8.00× | measure-only pair 310; `percent-decode` vs URLSearchParams | invent pause；地板优化另刀 |
| `oauth_pkce_device.parse_query` | 6.672 | 3.431 | 1.944× | 8.00× | measure-only pair 311; `parse-query` vs URLSearchParams | invent pause；地板优化另刀 |
| `tui_theme_overlay.rgb_to_ansi_256` | 2.52 | 1.29 | 1.955× | 8.00× | measure-only pair 319; `rgb-to-ansi-256` vs unexported `rgbTo256`; sub-µs — variance floor applies | invent pause；地板优化另刀 |
| `tui_theme_overlay.parse_hex_color` | 0.944 | 0.837 | 1.127× | 8.00× | measure-only pair 320; `parse-theme-hex-color` vs unexported `hexToRgb`; sub-µs — variance floor applies | invent pause；地板优化另刀 |
| `tui_theme_overlay.theme_foreground_ansi` | 5.58 | 0.379 | 14.724× | 8.00× | measure-only pair 321; `theme-foreground-ansi` vs `Theme.getFgAnsi`; **ratio > named ceiling**; sub-µs path — gate uses variance/10µs floor | invent pause；地板/抬天花板另刀 |
| `cli_settings.default_model` | 15.69 | 2.080 | 7.544× | 8.00× | measure-only pair 352; `settings-default-model` fixture plus missing-key in-memory | invent pause；地板优化另刀 |
| `cli_settings.default_provider` | 15.67 | 2.327 | 6.737× | 8.00× | measure-only pair 353; `settings-default-provider` fixture plus missing-key in-memory | invent pause；地板优化另刀 |
| `cli_settings.output_padding` | 17.54 | 2.788 | 6.289× | 8.00× | measure-only pair 354; `settings-output-padding` default 1 plus in-memory `outputPad=0` | invent pause；地板优化另刀 |
| `evals_harness.prompt_eval_agent` | 19.3 | 1.84 | 10.47× | 20.00× | measure-only pair 355; `prompt-eval-agent` vs `promptAgent` (first-freeze ceiling 20) | invent pause；地板优化另刀 |
| `evals_harness.reload_shutdown` | 222.4 | 118.8 | 1.872× | 8.00× | measure-only pair 356; reload + shutdown leftover | invent pause；地板优化另刀 |
| `evals_harness.run_coding_agent_eval` | 940.1 | 117.8 | 7.979× | 8.00× | measure-only pair 357; `run-coding-agent-eval` vs `runPiCodingAgent` | invent pause；地板优化另刀 |
| `oauth_pkce_device.parse_callback_request` | 12.588 | 3.403 | 3.699× | 8.00× | measure-only pair 336; `parse-oauth-callback-request` vs openai-codex loopback pathname/state/code | invent pause；地板优化另刀 |
| `core_rest.cancellation_wait` | 53.40 | 8.840 | 6.041× | 8.00× | measure-only pair 337; leftover `wait-for-cancellation` vs Atomics.wait timeout + aborted AbortSignal | invent pause；地板优化另刀 |
| `core_rest.redacted_types` | 2.375 | 0.528 | 4.494× | 8.00× | measure-only pair 338; leftover `redacted-object-types` vs sorted type-list copy; not redact-secrets | invent pause；地板优化另刀 |
| `oauth_pkce_device.base64url_value` | 0.736 | 0.273 | 2.692× | 8.00× | measure-only pair 358; `base64url-value` vs RFC 4648 §5 alphabet; sub-µs — variance floor applies | invent pause；地板优化另刀 |
| `oauth_pkce_device.base64url_decode` | 2.969 | 0.454 | 6.544× | 8.00× | measure-only pair 359; `base64url-decode` vs `decodeJwt` `atob` | invent pause；地板优化另刀 |
| `oauth_pkce_device.account_id` | 6.112 | 1.021 | 5.986× | 8.00× | measure-only pair 360; `openai-account-id-from-token` vs `getAccountId` | invent pause；地板优化另刀 |
| `evals_harness.release_extensions` | 6.187 | 0.293 | 21.13× | 8.00× | measure-only pair 370; `release-eval-extensions`; ratio > named ceiling — gate uses variance/µs floor | invent pause；地板优化另刀 |
| `evals_harness.agent_tools` | 1.466 | 0.286 | 5.118× | 8.00× | measure-only pair 371; `eval-agent-tools` vs session tools list | invent pause；地板优化另刀 |
| `evals_harness.extension_paths` | 2.963 | 0.464 | 6.381× | 8.00× | measure-only pair 372; `eval-extension-paths` vs `getExtensionPaths` | invent pause；地板优化另刀 |
| `grep_tool.make_tool` | 4.152 | 0.415 | 10.006× | 8.00× | measure-only pair 375; `make-grep-tool` vs `createGrepToolDefinition`; printed ratio > named ceiling — gate uses 10 µs variance floor | invent pause；地板优化另刀 |
| `edit_tool.normalize_line_endings` | 1.574 | 0.564 | 2.792× | 8.00× | measure-only pair 388; `normalize-line-endings` vs `normalizeToLF` | invent pause；地板优化另刀 |
| `edit_tool.restore_line_endings` | 0.773 | 0.398 | 1.944× | 8.00× | measure-only pair 389; `restore-line-endings` vs `restoreLineEndings` | invent pause；地板优化另刀 |
| `edit_tool.make_tool` | 3.313 | 0.566 | 5.850× | 8.00× | measure-only pair 390; `make-edit-tool` vs `createEditToolDefinition` | invent pause；地板优化另刀 |
| `resource_loader.context_from_dir` | 64.741 | 26.834 | 2.413× | 8.00× | measure-only pair 394; `load-context-file-from-dir` vs `loadContextFileFromDir` | invent pause；地板优化另刀 |
| `resource_loader.project_context` | 56.791 | 29.679 | 1.913× | 8.00× | measure-only pair 395; `load-project-context-files` vs `loadProjectContextFiles` | invent pause；地板优化另刀 |
| `resource_loader.nearest_config` | 30.226 | 5.596 | 5.401× | 8.00× | measure-only pair 396; `nearest-config-file` vs project SYSTEM.md existsSync | invent pause；地板优化另刀 |
| `tui_select_settings_loaders.loader_frames` | 0.200 | 0.190 | 1.051× | 8.00× | measure-only pair 397; `loader-frames` vs Loader DEFAULT_FRAMES copy (sub-µs — variance floor applies) | invent pause；地板优化另刀 |
| `tui_select_settings_loaders.loader_interval` | 0.201 | 0.138 | 1.464× | 8.00× | measure-only pair 398; `loader-interval-seconds` vs Loader intervalMs (sub-µs — variance floor applies) | invent pause；地板优化另刀 |
| `tui_select_settings_loaders.loader_step` | 0.339 | 0.219 | 1.543× | 8.00× | measure-only pair 399; `loader-component-step` vs Loader animation tick (sub-µs — variance floor applies) | invent pause；地板优化另刀 |
| `oauth_pkce_device.error_detail` | 0.838 | 0.364 | 2.301× | 8.00× | measure-only pair 379; `oauth-response-error-detail` vs xai.ts requestFailure detail (sub-µs variance) | invent pause；地板优化另刀 |
| `oauth_pkce_device.notify_device` | 0.960 | 0.371 | 2.586× | 8.00× | measure-only pair 381; `notify-device-authorization` vs xai.ts interaction.notify device_code (sub-µs variance) | invent pause；地板优化另刀 |
| `core_rest.redacted_replace` | 1.464 | 0.433 | 3.383× | 8.00× | measure-only pair 387; `replace-all` vs String.split/join one needle | invent pause；地板优化另刀 |
| `evals_harness.eval_result` | 0.762 | 0.440 | 1.734× | 8.00× | measure-only pair 376; leftover `make-eval-result` vs SimpleHarnessResult construction; sub-µs — variance floor applies | invent pause；地板优化另刀 |
| `evals_harness.root_observer` | 0.362 | 0.162 | 2.239× | 8.00× | measure-only pair 377; leftover `*eval-root-observer*` vs isolated eval root handoff; sub-µs — variance floor applies | invent pause；地板优化另刀 |
| `execution_env.absolute_path` | 11.920 | 3.612 | 3.301× | 8.00× | measure-only pair 391; leftover `execution-env-absolute-path` vs `absolutePath` | invent pause；地板优化另刀 |
| `execution_env.join_path` | 9.267 | 0.918 | 10.091× | 8.00× | measure-only pair 392; leftover `execution-env-join-path` vs `joinPath`; sub-µs pi — variance floor applies | invent pause；地板优化另刀 |
| `provider_registry_defs.provider_options` | 0.560 | 0.330 | 1.697× | 8.00× | measure-only pair 404; leftover `built-in-provider-options` vs Azure/Cloudflare/Google env keys (sub-µs variance) | invent pause；地板优化另刀 |
| `tool_manager.release_asset` | 1.532 | 1.046 | 1.465× | 8.00× | measure-only pair 409; leftover `tool-release-asset` vs `TOOLS.getAssetName` (sub-µs variance) | invent pause；地板优化另刀 |
| `tool_manager.find_binary` | 339.3 | 216.5 | 1.568× | 8.00× | measure-only pair 410; leftover `find-file-recursively` vs `findBinaryRecursively` | invent pause；地板优化另刀 |
| `tui_select_settings_loaders.set_message` | 0.244 | 0.192 | 1.269× | 8.00× | measure-only pair 416; leftover `loader-component-set-message` vs `Loader.setMessage` (sub-µs variance) | invent pause；地板优化另刀 |
| `evals_harness.status_name` | 0.352 | 0.204 | 1.726× | 8.00× | measure-only pair 412; leftover `reporter-status-name` vs status lowercasing (sub-µs variance) | invent pause；地板优化另刀 |
| `evals_harness.case_observation` | 9.383 | 3.057 | 3.069× | 8.00× | measure-only pair 413; leftover `reporter-case-observation` vs collectHarnessObservations | invent pause；地板优化另刀 |
| `oauth_pkce_device.json_copy` | 0.936 | 0.427 | 2.191× | 8.00× | measure-only pair 421; `oauth-response-json-copy` vs JSON.stringify error-body copy | invent pause；地板优化另刀 |
| `oauth_pkce_device.device_start` | 8.710 | 7.805 | 1.116× | 8.00× | measure-only pair 423; stubbed `start-openai-codex-device-authorization` | invent pause；地板优化另刀 |
| `evals_harness.eval_layout` | 3.297 | 1.074 | 3.071× | 8.00× | measure-only pair 418; leftover eval workspace/agent/sessions layout vs path join | invent pause；地板优化另刀 |
| `evals_harness.output_selector` | 0.189 | 0.188 | 1.007× | 8.00× | measure-only pair 420; leftover `:selector` vs `options.output`; sub-µs — variance floor applies | invent pause；地板优化另刀 |
| `oauth_pkce_device.openrouter_exchange` | 10.390 | 6.991 | 1.486× | 8.00× | measure-only pair 438; leftover `openrouter-exchange-code` vs `exchangeAuthorizationCode` (stubbed HTTP) | invent pause；地板优化另刀 |
| `output_accumulator.needs_file` | 50.564 | 20.524 | 2.464× | 8.00× | measure-only pair 428; leftover `needs-file-p` vs `shouldUseTempFile` | invent pause；地板优化另刀 |
| `evals_harness.artifact_metadata` | 1.025 | 0.868 | 1.182× | 8.00× | measure-only pair 432; leftover `reporter-artifact-metadata` vs `appendHarnessRunReport` metadata filter | invent pause；地板优化另刀 |
| `evals_harness.extension_authoring_input` | 1.148 | 0.246 | 4.662× | 8.00× | measure-only pair 439; `extension-authoring-input` types/length leftover (sub-µs variance) | invent pause；地板优化另刀 |
| `evals_harness.json_string` | 0.902 | 0.180 | 5.012× | 8.00× | measure-only pair 441; `json-string` leftover vs missing/false JSON accessor (sub-µs variance) | invent pause；地板优化另刀 |
| `package_manager.type_label` | 0.135 | 0.134 | 1.002× | 8.00× | measure-only pair 444; `config-resource-type-label` leftover (sub-µs variance) | invent pause；地板优化另刀 |
| `package_manager.update_argv` | 5.696 | 1.588 | 3.587× | 8.00× | measure-only pair 445; leftover `package-update-check-process-argv` (sub-µs path) | invent pause；地板优化另刀 |
| `package_manager.git_object_id` | 2.328 | 1.215 | 1.916× | 8.00× | measure-only pair 447; leftover `package-update-git-object-id` (sub-µs path) | invent pause；地板优化另刀 |
| `find_tool.glob_regex` | 0.527 | 0.220 | 2.403× | 8.00× | measure-only pair 448; leftover `glob-regex-source` (sub-µs path) | invent pause；地板优化另刀 |
| `find_tool.gitignore_regex` | 0.693 | 0.607 | 1.142× | 8.00× | measure-only pair 450; leftover `gitignore-regex-source` (sub-µs path) | invent pause；地板优化另刀 |
| `settings_load.provider_symbol` | 0.313 | 0.231 | 1.351× | 8.00× | measure-only pair 454; leftover `provider-symbol` (sub-µs path) | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.legacy_product` | 0.171 | 0.145 | 1.178× | 8.00× | measure-only pair 457; leftover `legacy-product-name` (sub-µs path) | invent pause；地板优化另刀 |
| `cli_support.no_models_help` | 244.9 | 8.92 | 27.45× | 50.00× | measure-only pair 460; leftover CLI wrapper; same ASDF docs-dir as `ai_support.auth_guidance` | invent pause；地板/去 ASDF 另刀 |
| `cli_support.no_model_selected` | 245.4 | 8.87 | 27.67× | 50.00× | measure-only pair 461; leftover CLI wrapper; same ASDF docs-dir as `ai_support.auth_guidance` | invent pause；地板/去 ASDF 另刀 |
| `cli_support.no_api_key` | 480.3 | 17.48 | 27.48× | 50.00× | measure-only pair 462; leftover CLI wrapper; same ASDF docs-dir as `ai_support.auth_guidance` | invent pause；地板/去 ASDF 另刀 |
| `cli_print_rpc.rpc_prompt` | 1.323 | 0.584 | 2.266× | 8.00× | measure-only leftover 464; `rpc-prompt-message` vs RPC prompt message+images (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_print_rpc.bash_result` | 2.165 | 0.743 | 2.913× | 8.00× | measure-only leftover 465; `rpc-bash-result-json` vs RPC bash result payload (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_print_rpc.dialog_request` | 1.129 | 0.325 | 3.471× | 8.00× | measure-only leftover 466; `rpc-dialog-request-object` vs createDialogPromise request (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_print_rpc.dialog_result` | 1.233 | 0.290 | 4.257× | 8.00× | measure-only leftover 467; `rpc-dialog-result` vs createDialogPromise parseResponse (sub-µs variance) | invent pause；地板优化另刀 |
| `settings_load.sdk_nonempty` | 20.855 | 6.284 | 3.319× | 8.00× | measure-only pair 469; leftover `sdk-nonempty-setting-string` vs `getDefaultProvider` | invent pause；地板优化另刀 |
| `settings_load.sdk_boolean` | 13.423 | 6.283 | 2.136× | 8.00× | measure-only pair 470; leftover `sdk-settings-boolean` vs `getCompactionEnabled` | invent pause；地板优化另刀 |
| `settings_load.sdk_tools` | 12.769 | 6.268 | 2.037× | 8.00× | measure-only pair 471; leftover `sdk-settings-enabled-tools` vs `getDefaultTools` | invent pause；地板优化另刀 |
| `skill_prompt_load.resolve_prompt` | 16.882 | 4.643 | 3.636× | 8.00× | measure-only pair 472; leftover `resolve-system-prompt` vs `resolvePromptInput` | invent pause；地板优化另刀 |
| `skill_prompt_load.node_read_error` | 10.042 | 3.219 | 3.120× | 8.00× | measure-only pair 473; leftover `node-read-error-message` vs Node fs errno text | invent pause；地板优化另刀 |
| `skill_prompt_load.prompt_appends` | 6.306 | 1.930 | 3.268× | 8.00× | measure-only pair 474; leftover `resolve-system-prompt-with-appends` vs append join | invent pause；地板优化另刀 |
| `cli_print_rpc.command_list` | 1.490 | 0.359 | 4.151× | 8.00× | measure-only leftover pair 477; `rpc-command-list` vs `get_commands` walk | invent pause；地板优化另刀 |
| `skill_prompt_load.sdk_prompt_input` | 15.179 | 3.512 | 4.322× | 8.00× | measure-only leftover pair 478; `sdk-resolve-prompt-input` vs `resolvePromptInput` | invent pause；地板优化另刀 |
| `skill_prompt_load.sdk_context_files` | 7.556 | 2.625 | 2.879× | 8.00× | measure-only leftover pair 480; `sdk-context-file-records` vs agentsFiles records | invent pause；地板优化另刀 |
| `cli_support.watch_signature` | 12.165 | 2.262 | 5.379× | 8.00× | measure-only leftover pair 483; `watched-path-signature` vs `statSync` presence | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.model_scope_line` | 37.431 | 23.274 | 1.608× | 8.00× | measure-only leftover pair 485; `model-scope-startup-line` vs interactive-mode init line | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.response_text` | 0.939 | 0.714 | 1.314× | 8.00× | measure-only pair 491; `response-text` vs `textParts.join` (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_interactive_controller.make_entry` | 1.424 | 0.238 | 5.982× | 8.00× | measure-only pair 493; `make-tui-user-bash-entry` vs BashExecutionComponent constructor (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_interactive_controller.append_output` | 0.776 | 0.290 | 2.670× | 8.00× | measure-only pair 494; `append-tui-user-bash-output` vs appendOutput concatenate (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_interactive_controller.complete_entry` | 0.974 | 0.404 | 2.411× | 8.00× | measure-only pair 495; `complete-tui-user-bash-entry` vs setComplete (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_print_rpc.handle_bad_json` | 5.390 | 4.937 | 1.092× | 8.00× | measure-only pair 496; `rpc-handle-line` JSON.parse catch (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_print_rpc.handle_not_object` | 5.213 | 4.889 | 1.066× | 8.00× | measure-only pair 497; `rpc-handle-line` require-object | invent pause；地板优化另刀 |
| `cli_print_rpc.handle_ui_miss` | 6.190 | 1.521 | 4.070× | 8.00× | measure-only pair 498; `rpc-handle-line` unknown extension_ui_response | invent pause；地板优化另刀 |
| `cli_extensions_install.unsafe_git` | 0.762 | 0.658 | 1.159× | 8.00× | measure-only pair 499; `unsafe-git-source-p` vs hasUnsafeGitInstallPart (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_extensions_install.git_path` | 1.055 | 0.569 | 1.852× | 8.00× | measure-only pair 500; `git-source-path` vs git URL path slice | invent pause；地板优化另刀 |
| `cli_extensions_install.quant_label` | 1.033 | 0.827 | 1.249× | 8.00× | measure-only leftover pair 507; `llama-quantization-option-label` vs downloadModel option text | invent pause；地板优化另刀 |
| `bash_tool.strip_truncation` | 2.331 | 0.396 | 5.885× | 8.00× | measure-only leftover pair 510; `bash-strip-truncation-footer` vs `[Showing … Full output:]` suffix strip | invent pause；地板优化另刀 |
| `cli_interactive_controller.wrap_transcript` | 0.601 | 0.599 | 1.003× | 8.00× | measure-only leftover pair 517; `wrap-transcript-lines` OSC 133 wrap (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_interactive_controller.render_cacheable` | 1.461 | 0.581 | 2.515× | 8.00× | measure-only leftover pair 519; `tui-entry-render-cacheable-p` vs TUI entry render cache gate | invent pause；地板优化另刀 |
| `cli_interactive_controller.tool_session_make` | 0.257 | 0.210 | 1.224× | 8.00× | measure-only leftover pair 520; `make-tool-render-session` construct (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_interactive_controller.tool_session_update` | 0.266 | 0.231 | 1.151× | 8.00× | measure-only leftover pair 521; `update-tool-render-session` result/pending (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_selectors.login_dialog_auth` | 1.925 | 1.853 | 1.039× | 8.00× | measure-only leftover pair 530; `login-dialog-show-auth` vs showAuth | invent pause；地板优化另刀 |
| `cli_selectors.login_dialog_device` | 3.653 | 1.701 | 2.148× | 8.00× | measure-only leftover pair 531; `login-dialog-show-device-code` vs showDeviceCode | invent pause；地板优化另刀 |
| `cli_selectors.thinking_level_search_text` | 1.090 | 0.520 | 2.096× | 8.00× | measure-only leftover pair 533; `thinking-level-search-text` vs thinking search text | invent pause；地板优化另刀 |
| `cli_selectors.thinking_selector_set_query` | 11.827 | 10.942 | 1.081× | 8.00× | measure-only leftover pair 534; `thinking-selector-set-query` vs filter query update | invent pause；地板优化另刀 |
| `cli_interactive_controller.colorfgbg_index` | 1.430 | 0.891 | 1.605× | 8.00× | measure-only leftover pair 538; `colorfgbg-background-index` vs COLORFGBG parse | invent pause；地板优化另刀 |
| `cli_interactive_controller.fit_footer_text` | 21.385 | 20.600 | 1.038× | 8.00× | measure-only pair 541; `fit-footer-text` vs `truncateToWidth` | invent pause；地板优化另刀 |
| `cli_interactive_controller.footer_usage` | 7.216 | 3.522 | 2.049× | 8.00× | measure-only pair 542; `footer-usage-summary` vs `addUsageToTotals` + cadr format | invent pause；地板优化另刀 |
| `cli_interactive_controller.footer_git_paths` | 214.734 | 130.225 | 1.649× | 8.00× | measure-only pair 543; `find-git-footer-paths` vs `findGitPaths` | invent pause；地板优化另刀 |
| `cli_extensions_install.llama_context_label` | 1.279 | 1.119 | 1.143× | 8.00× | measure-only pair 544; `llama-context-label` vs `contextLabel` | invent pause；地板优化另刀 |
| `cli_extensions_install.llama_model_description` | 1.450 | 1.283 | 1.130× | 8.00× | measure-only pair 545; `llama-model-description` vs `modelDescription` | invent pause；地板优化另刀 |
| `cli_extensions_install.llama_compact_count` | 0.968 | 0.641 | 1.511× | 8.00× | measure-only pair 546; `llama-compact-count` vs `compactCount` | invent pause；地板优化另刀 |
| `cli_selectors.daxnuts_image_line` | 36.319 | 16.357 | 2.220× | 8.00× | measure-only leftover 548; `daxnuts-image-line` vs `buildImage` half-block row | invent pause；地板优化另刀 |
| `cli_interactive_controller.framed_select_title` | 0.775 | 0.551 | 1.406× | 8.00× | measure-only leftover 550; `framed-select-title` vs countdown `${title} (${s}s)` (sub-µs) | invent pause；地板优化另刀 |
| `cli_interactive_controller.extension_overlay_options` | 1.270 | 0.601 | 2.114× | 8.00× | measure-only leftover 551; `extension-overlay-options` vs resolveOptions | invent pause；地板优化另刀 |
| `cli_interactive_controller.extension_custom_ui_visible` | 1.027 | 0.551 | 1.866× | 8.00× | measure-only leftover 552; `extension-custom-ui-visible-p` flags (no size callback) | invent pause；地板优化另刀 |
| `cli_selectors.countdown_seconds` | 0.768 | 0.335 | 2.292× | 8.00× | measure-only leftover 556; `make-countdown-timer` remaining seconds vs `Math.ceil` (sub-µs) | invent pause；地板优化另刀 |
| `cli_selectors.countdown_tick` | 0.700 | 0.233 | 3.006× | 8.00× | measure-only leftover 557; `countdown-timer-tick` vs interval body (sub-µs) | invent pause；地板优化另刀 |
| `cli_selectors.countdown_render` | 0.892 | 0.463 | 1.928× | 8.00× | measure-only leftover 558; `countdown-request-render` vs `tui?.requestRender` (sub-µs) | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_copy_enabled` | 1.074 | 0.548 | 1.960× | 8.00× | measure-only leftover 560; `scoped-models-copy-enabled` vs enabled-id copy (sub-µs/low-µs) | invent pause；地板优化另刀 |
| `cli_selectors.move_list_item` | 1.317 | 0.971 | 1.357× | 8.00× | measure-only leftover 561; `move-list-item` vs `move()` index swap (low-µs) | invent pause；地板优化另刀 |
| `cli_selectors.session_scoped_models` | 11.473 | 4.477 | 2.563× | 8.00× | measure-only leftover 562; `session-scoped-models` vs session-scoped filter | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_toggle_id` | 1.098 | 0.922 | 1.191× | 8.00× | measure-only leftover 564; `scoped-models-toggle-id` vs `toggle` (low-µs) | invent pause；地板优化另刀 |
| `cli_selectors.all_known_model_ids_enabled_p` | 1.679 | 0.825 | 2.035× | 8.00× | leftover 565; `all-known-model-ids-enabled-p` vs enableAll collapse-to-null (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_enable_ids` | 2.605 | 1.715 | 1.519× | 8.00× | leftover 566; `scoped-models-enable-ids` vs enableAll id union | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_clear_ids` | 2.931 | 1.455 | 2.015× | 8.00× | leftover 567; `scoped-models-clear-ids` vs clearAll id subtract | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_enabled_set` | 2.709 | 1.067 | 2.540× | 8.00× | leftover 568; `scoped-models-enabled-set` vs `new Set(enabledIds)` | invent pause；地板优化另刀 |
| `cli_selectors.model_equal_p` | 0.458 | 0.249 | 1.840× | 8.00× | leftover 569; `model-equal-p` vs `modelsAreEqual` (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_selectors.scoped_model_selector_search_text` | 4.242 | 0.499 | 8.503× | 12.00× | leftover 570; `scoped-model-selector-search-text` vs `getModelSearchText` | invent pause；地板优化另刀 |
| `cli_selectors.model_selector_active_models` | 20.408 | 1.804 | 11.315× | 15.00× | leftover 571; `model-selector-active-models` vs `activeModels` scope switch | invent pause；地板优化另刀 |
| `cli_selectors.model_selector_clamp_selected` | 21.011 | 5.234 | 4.015× | 8.00× | leftover 572; `model-selector-clamp-selected` vs `filterModels` selectedIndex clamp | invent pause；地板优化另刀 |
| `cli_selectors.model_selector_select_current` | 19.744 | 0.449 | 43.943× | 55.00× | leftover 573; `model-selector-select-current` vs `setScope` currentIndex | invent pause；地板优化另刀 |
| `cli_selectors.sort_model_selector_models` | 8.603 | 2.939 | 2.928× | 8.00× | measure-only leftover 574; `sort-model-selector-models` vs current-first + provider localeCompare | invent pause；地板优化另刀 |
| `cli_selectors.model_selector_visible_models` | 37.867 | 20.148 | 1.879× | 8.00× | measure-only leftover 575; `model-selector-visible-models` vs filteredModels after filter | invent pause；地板优化另刀 |
| `cli_selectors.model_selector_visible_slice` | 31.486 | 11.617 | 2.710× | 8.00× | measure-only leftover 576; `model-selector-visible-slice` vs filteredModels viewport slice | invent pause；地板优化另刀 |
| `cli_selectors.model_selector_rebuild_search_text_table` | 16.001 | 4.939 | 3.240× | 8.00× | measure-only leftover 577; `model-selector-rebuild-search-text-table` vs search-text Map rebuild | invent pause；地板优化另刀 |
| `cli_selectors.model_selector_filter_search_text` | 13.376 | 3.048 | 4.389× | 8.00× | measure-only leftover 578; `model-selector-filter-search-text` vs table lookup / fallback | invent pause；地板优化另刀 |
| `cli_selectors.model_selector_finish_refresh` | 46.658 | 10.907 | 4.278× | 8.00× | measure-only leftover 579; `model-selector-finish-refresh` vs catalog refresh completion | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_items` | 26.959 | 6.435 | 4.189× | 8.00× | measure-only leftover 584; `scoped-models-selector-items` vs items after rebuild | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_cancel` | 0.667 | 0.382 | 1.746× | 8.00× | measure-only leftover 585; `scoped-models-selector-cancel` vs `onCancel` | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_selected_item` | 26.636 | 7.796 | 3.417× | 8.00× | measure-only leftover 586; `scoped-models-selector-selected-item` vs selected visible item | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_select_id` | 26.954 | 8.112 | 3.323× | 8.00× | measure-only leftover 587; `scoped-models-selector-select-id` vs select by id | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_notify_change` | 1.398 | 0.801 | 1.745× | 8.00× | measure-only leftover 588; `scoped-models-selector-notify-change` vs `onChange` | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_rebuild_items` | 27.154 | 6.105 | 4.448× | 8.00× | measure-only leftover 589; `scoped-models-selector-rebuild-items` vs rebuild items | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_apply_filter` | 34.896 | 23.842 | 1.464× | 8.00× | measure-only leftover 590; `scoped-models-selector-apply-filter` vs apply filter | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_visible_items` | 32.039 | 13.230 | 2.422× | 8.00× | measure-only leftover 591; `scoped-models-selector-visible-items` vs lazy visible items | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_refresh_items` | 33.511 | 13.561 | 2.471× | 8.00× | measure-only leftover 592; `scoped-models-selector-refresh-items` vs refresh items | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_clamp_selected` | 30.415 | 12.863 | 2.365× | 8.00× | measure-only leftover 593; `scoped-models-selector-clamp-selected` vs clamp selected | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_mark_changed` | 35.327 | 25.989 | 1.359× | 8.00× | measure-only leftover 594; `scoped-models-selector-mark-changed` vs mark changed | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_finish_refresh` | 68.310 | 21.063 | 3.243× | 8.00× | measure-only leftover 595; `scoped-models-selector-finish-refresh` vs updateModels+setRefreshStatus | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_selector_key_p` | 22.914 | 1.217 | 18.835× | 30.00× | measure-only leftover 596; `scoped-models-selector-key-p` vs KeybindingsManager.matches; first-freeze headroom 30.0 | invent pause；地板优化另刀 |
| `cli_selectors.scoped_models_binding_label` | 5.542 | 0.339 | 16.362× | 25.00× | measure-only leftover 597; `scoped-models-binding-label` vs getKeys first-or-fallback; first-freeze headroom 25.0 | invent pause；地板优化另刀 |
| `cli_selectors.model_selector_key_p` | 16.140 | 0.868 | 18.605× | 30.00× | measure-only leftover 598; `model-selector-key-p` vs KeybindingsManager.matches; first-freeze headroom 30.0 | invent pause；地板优化另刀 |
| `cli_selectors.model_selector_keybindings` | 4.144 | 0.513 | 8.076× | 12.00× | measure-only leftover 599; `model-selector-keybindings` vs getKeybindings slot-or-default; first-freeze headroom 12.0 | invent pause；地板优化另刀 |
| `cli_selectors.make_model_selector_state` | 21.230 | 6.989 | 3.037× | 8.00× | measure-only leftover 600; `make-model-selector-state` vs constructor sort+filter+select | invent pause；地板优化另刀 |
| `cli_selectors.thinking_selector_key_p` | 15.469 | 0.806 | 19.196× | 30.00× | measure-only leftover 601; `thinking-selector-key-p` vs KeybindingsManager.matches; first-freeze headroom 30.0 | invent pause；地板优化另刀 |
| `cli_selectors.thinking_selector_keybindings` | 3.014 | 0.530 | 5.685× | 8.00× | measure-only leftover 602; `thinking-selector-keybindings` vs getKeybindings slot-or-default | invent pause；地板优化另刀 |
| `cli_selectors.thinking_selector_apply_filter` | 13.399 | 11.664 | 1.149× | 8.00× | measure-only leftover 604; `thinking-selector-apply-filter` vs applyFilter | invent pause；地板优化另刀 |
| `cli_selectors.thinking_selector_move` | 0.637 | 0.471 | 1.353× | 8.00× | measure-only leftover 607; `thinking-selector-move` vs wrap selected index | invent pause；地板优化另刀 |
| `cli_selectors.thinking_selector_handle_raw_input` | 144.448 | 6.908 | 20.910× | 30.00× | measure-only leftover 608; `thinking-selector-handle-raw-input` vs handleInput; first-freeze headroom 30.0 | invent pause；地板优化另刀 |
| `cli_selectors.thinking_level_description_line` | 0.268 | 0.232 | 1.155× | 8.00× | measure-only leftover 611; `thinking-level-description-line` vs LEVEL_DESCRIPTIONS · default | invent pause；地板优化另刀 |
| `cli_selectors.render_thinking_selector` | 316.671 | 7.080 | 44.726× | 60.00× | measure-only leftover 612; `render-thinking-selector` vs ThinkingSelectorComponent layout; first-freeze headroom 60.0 | invent pause；地板优化另刀 |
| `cli_selectors.trust_option_saved_p` | 35.594 | 15.530 | 2.292× | 8.00× | measure-only leftover 613; `trust-option-saved-p` vs isSavedOption | invent pause；地板优化另刀 |
| `cli_selectors.make_trust_selector_state` | 91.097 | 53.106 | 1.715× | 8.00× | measure-only leftover 614; `make-trust-selector-state` vs TrustSelectorComponent constructor | invent pause；地板优化另刀 |
| `cli_selectors.render_trust_selector` | 1074.462 | 122.128 | 8.798× | 15.00× | measure-only leftover 615; `render-trust-selector` vs TrustSelectorComponent layout; first-freeze headroom 15.0 | invent pause；地板优化另刀 |
| `cli_selectors.make_login_method_selector_state` | 2.654 | 2.323 | 1.143× | 8.00× | measure-only leftover 616; `make-login-method-selector-state` vs ExtensionSelectorComponent constructor | invent pause；地板优化另刀 |
| `cli_selectors.make_api_key_input_state` | 2.203 | 1.222 | 1.803× | 8.00× | measure-only leftover 617; `make-api-key-input-state` vs login-dialog api key Input constructor | invent pause；地板优化另刀 |
| `cli_selectors.make_oauth_selector_state` | 7.245 | 6.020 | 1.204× | 8.00× | measure-only leftover 618; `make-oauth-selector-state` vs OauthSelectorComponent constructor | invent pause；地板优化另刀 |
| `cli_selectors.login_dialog_show_waiting` | 5.469 | 4.088 | 1.338× | 8.00× | measure-only leftover 619; `login-dialog-show-waiting` vs LoginDialogComponent.showWaiting | invent pause；地板优化另刀 |
| `cli_selectors.login_dialog_show_progress` | 3.159 | 2.466 | 1.281× | 8.00× | measure-only leftover 620; `login-dialog-show-progress` vs LoginDialogComponent.showProgress | invent pause；地板优化另刀 |
| `cli_selectors.login_dialog_show_manual_input` | 5.131 | 3.050 | 1.683× | 8.00× | measure-only leftover 621; `login-dialog-show-manual-input` vs LoginDialogComponent.showManualInput | invent pause；地板优化另刀 |
| `cli_selectors.login_dialog_show_prompt` | 6.781 | 3.830 | 1.771× | 8.00× | measure-only leftover 622; `login-dialog-show-prompt` vs LoginDialogComponent.showPrompt | invent pause；地板优化另刀 |
| `cli_selectors.login_dialog_show_info` | 8.766 | 5.594 | 1.567× | 8.00× | measure-only leftover 623; `login-dialog-show-info` vs LoginDialogComponent.showInfo | invent pause；地板优化另刀 |
| `cli_selectors.login_dialog_complete_input` | 5.722 | 3.482 | 1.643× | 8.00× | measure-only leftover 625; `login-dialog-complete-input` vs replaceInputWithSubmittedText | invent pause；地板优化另刀 |
| `cli_selectors.login_dialog_handle_event` | 6.392 | 3.325 | 1.923× | 8.00× | measure-only leftover 626; `login-dialog-state-handle-event` vs handleInput | invent pause；地板优化另刀 |
| `cli_selectors.render_login_dialog` | 135.552 | 4.147 | 32.688× | 50.00× | measure-only leftover 627; `render-login-dialog-state` vs LoginDialogComponent layout; first-freeze headroom 50.0 | invent pause；地板优化另刀 |
| `cli_selectors.user_message_handle_raw` | 85.983 | 5.433 | 15.827× | 30.00× | measure-only leftover 629; `user-message-selector-handle-raw-input` vs UserMessageList.handleInput; first-freeze headroom 30.0 | invent pause；地板优化另刀 |
| `cli_selectors.render_user_message_selector` | 265.302 | 4.081 | 65.009× | 100.00× | measure-only leftover 630; `render-user-message-selector` vs UserMessageSelectorComponent layout; first-freeze headroom 100.0 | invent pause；地板优化另刀 |
| `cli_selectors.make_models_selector_keybindings` | 32.105 | 21.468 | 1.496× | 8.00× | measure-only leftover 631; `make-models-selector-keybindings` vs KEYBINDINGS app.models.* constructor | invent pause；地板优化另刀 |
| `cli_selectors.make_scoped_models_selector_state` | 97.005 | 4.620 | 20.997× | 40.00× | measure-only leftover 632; `make-scoped-models-selector-state` vs ScopedModelsSelectorComponent constructor; first-freeze headroom 40.0 | invent pause；地板优化另刀 |
| `cli_selectors.render_model_selector` | 247.317 | 9.300 | 26.593× | 50.00× | measure-only leftover 633; `render-model-selector` vs ModelSelectorComponent layout; first-freeze headroom 50.0 | invent pause；地板优化另刀 |
| `cli_selectors.daxnuts_rgb_at` | 0.910 | 0.497 | 1.831× | 8.00× | measure-only leftover 634; `daxnuts-rgb-at` vs parseImage pixel lookup | invent pause；地板优化另刀 |
| `cli_selectors.make_daxnuts_component` | 0.688 | 0.198 | 3.472× | 8.00× | measure-only leftover 635; `make-daxnuts-component` vs DaxnutsComponent constructor (no startAnimation) | invent pause；地板优化另刀 |
| `cli_selectors.daxnuts_component_tick` | 3.787 | 3.384 | 1.119× | 8.00× | measure-only leftover 636; `daxnuts-component-tick` vs DaxnutsComponent interval body | invent pause；地板优化另刀 |
| `cli_interactive_controller.apply_tui_theme_summary` | 52.489 | 16.348 | 3.211× | 8.00× | measure-only leftover 638; `apply-tui-theme-summary` vs setTheme | invent pause；地板优化另刀 |
| `cli_interactive_controller.load_tui_theme_file` | 233.265 | 97.883 | 2.383× | 8.00× | measure-only leftover 639; `load-tui-theme-file` vs loadThemeFromPath | invent pause；地板优化另刀 |
| `cli_interactive_controller.bash_append_running` | 0.735 | 0.357 | 2.059× | 8.00× | measure-only leftover 640; `append-tui-user-bash-running` vs BashExecutionComponent addChild running | invent pause；地板优化另刀 |
| `cli_interactive_controller.bash_complete_string` | 0.745 | 0.274 | 2.719× | 8.00× | measure-only leftover 641; `complete-tui-user-bash-string` vs setComplete exit 0 string | invent pause；地板优化另刀 |
| `cli_interactive_controller.bash_stop_entry` | 0.621 | 0.219 | 2.843× | 8.00× | measure-only leftover 642; `stop-tui-user-bash-entry` vs loader.stop without setComplete | invent pause；地板优化另刀 |
| `cli_interactive_controller.assistant_has_tools` | 1.082 | 0.933 | 1.160× | 8.00× | measure-only leftover 643; `assistant-message-has-tool-calls-p` vs hasToolCalls | invent pause；地板优化另刀 |
| `cli_interactive_controller.transcript_summary_label` | 12.217 | 1.923 | 6.352× | 8.00× | measure-only leftover 645; `transcript-summary-label` vs skill/branch/compaction [name] label | invent pause；地板优化另刀 |
| `cli_interactive_controller.transcript_summary_text` | 8.866 | 1.632 | 5.434× | 8.00× | measure-only leftover 646; `transcript-summary-text` vs customMessageText | invent pause；地板优化另刀 |
| `cli_interactive_controller.assistant_stop_error` | 24.257 | 2.323 | 10.444× | 20.00× | measure-only leftover 647; `assistant-stop-error-lines` vs AssistantMessageComponent stopReason; first-freeze headroom 20.0 | invent pause；地板优化另刀 |
| `cli_interactive_controller.update_notification_border` | 6.319 | 1.484 | 4.259× | 8.00× | measure-only leftover 648; `update-notification-border-line` vs warning DynamicBorder | invent pause；地板优化另刀 |
| `cli_interactive_controller.theme_message_background` | 8.586 | 1.571 | 5.465× | 8.00× | measure-only leftover 649; `theme-message-background-lines` vs theme.bg | invent pause；地板优化另刀 |
| `cli_interactive_controller.update_notification_text` | 59.152 | 2.032 | 29.104× | 50.00× | measure-only leftover 650; `update-notification-text-lines` vs warning body text; first-freeze headroom 50.0 | invent pause；地板优化另刀 |
| `cli_interactive_controller.syntax_highlight` | 13.174 | 1.081 | 12.184× | 20.00× | measure-only leftover 651; `tui-syntax-highlight` vs syntaxHighlight; first-freeze headroom 20.0 | invent pause；地板优化另刀 |
| `cli_interactive_controller.accumulate_usage` | 0.775 | 0.652 | 1.188× | 8.00× | measure-only leftover 653; `accumulate-message-usage` vs session usage accumulate | invent pause；地板优化另刀 |
| `cli_interactive_controller.append_user_message` | 5.050 | 1.201 | 4.205× | 8.00× | measure-only leftover 654; `append-tui-user-message` vs parseSkillBlock UserMessageComponent | invent pause；地板优化另刀 |
| `cli_interactive_controller.reset_tui_messages` | 2.035 | 1.570 | 1.296× | 8.00× | measure-only leftover 656; `reset-tui-messages` vs chatContainer reset + usage preserve | invent pause；地板优化另刀 |
| `cli_interactive_controller.render_user_lines` | 3.956 | 1.541 | 2.567× | 8.00× | measure-only leftover 657; `render-user-message-lines` vs UserMessageComponent wrap + OSC 133 | invent pause；地板优化另刀 |
| `cli_interactive_controller.render_assistant_lines` | 12.279 | 4.498 | 2.730× | 8.00× | measure-only leftover 658; `render-assistant-message-lines` vs AssistantMessageComponent wrap + OSC 133 | invent pause；地板优化另刀 |
| `cli_interactive_controller.transform_tui_markdown` | 2.923 | 1.968 | 1.485× | 8.00× | measure-only leftover 659; `transform-tui-markdown` vs mermaid transform + markdown cache | invent pause；地板优化另刀 |
| `cli_interactive_controller.render_transcript_summary` | 786.501 | 3.083 | 255.111× | 400.00× | measure-only leftover 660; `render-transcript-summary-entry` vs skill/branch/compaction CustomMessage; first-freeze headroom 400.0 | invent pause；地板优化另刀 |
| `cli_interactive_controller.render_assistant_blocks` | 54.605 | 10.156 | 5.377× | 8.00× | measure-only leftover 661; `render-assistant-blocks` vs assistant markdown blocks + stop error | invent pause；地板优化另刀 |
| `cli_interactive_controller.render_version_notification` | 304.547 | 4.388 | 69.400× | 120.00× | measure-only leftover 662; `render-version-update-notification` vs version warning DynamicBorder; first-freeze headroom 120.0 | invent pause；地板优化另刀 |
| `cli_interactive_controller.render_package_notification` | 217.221 | 4.120 | 52.727× | 100.00× | measure-only leftover 663; `render-package-update-notification` vs package warning DynamicBorder; first-freeze headroom 100.0 | invent pause；地板优化另刀 |
| `cli_interactive_controller.render_tui_entry_uncached` | 200.288 | 7.276 | 27.525× | 50.00× | measure-only leftover 664; `render-tui-entry-uncached` vs chat-log render entry uncached; first-freeze headroom 50.0 | invent pause；地板优化另刀 |
| `cli_interactive_controller.render_tui_entry` | 102.484 | 5.999 | 17.083× | 30.00× | measure-only leftover 665; `render-tui-entry` vs chat-log render entry cache; first-freeze headroom 30.0 | invent pause；地板优化另刀 |
| `cli_interactive_controller.render_tui_entries` | 42.711 | 7.723 | 5.530× | 8.00× | measure-only leftover 666; `render-tui-entries` vs chat-log render entries + user gap | invent pause；地板优化另刀 |
| `cli_interactive_controller.extension_dialog_chrome` | 21.804 | 1.528 | 14.268× | 30.00× | measure-only leftover 670; `extension-dialog-chrome` vs dialog chrome border; first-freeze headroom 30.0 | invent pause；地板优化另刀 |
| `cli_interactive_controller.tui_component_protocol` | 0.587 | 0.384 | 1.527× | 8.00× | measure-only leftover 671; `tui-component-protocol-p` vs Component protocol predicate | invent pause；地板优化另刀 |
| `cli_interactive_controller.extension_render_value_lines` | 2.505 | 1.022 | 2.452× | 8.00× | measure-only leftover 672; `extension-render-value-lines` vs custom value lines | invent pause；地板优化另刀 |
| `cli_interactive_controller.make_framed_select_state` | 0.903 | 0.870 | 1.037× | 8.00× | measure-only leftover 673; `make-framed-select-state` vs framed select-list constructor | invent pause；地板优化另刀 |
| `cli_interactive_controller.note_component_render_channel` | 0.357 | 0.279 | 1.278× | 8.00× | measure-only leftover 674; `note-component-render-channel` vs requestRender inject on render-aware mixin | invent pause；地板优化另刀 |
| `cli_interactive_controller.tui_extension_theme_runtime` | 1.449 | 0.429 | 3.379× | 8.00× | measure-only leftover 675; `tui-extension-theme-runtime` vs theme fg/bg/bold/italic runtime | invent pause；地板优化另刀 |
| `cli_interactive_controller.make_extension_input_dialog` | 0.496 | 0.451 | 1.099× | 8.00× | measure-only leftover 676; `make-extension-input-dialog` vs input dialog constructor | invent pause；地板优化另刀 |
| `cli_interactive_controller.make_extension_editor_dialog` | 1.648 | 0.363 | 4.545× | 8.00× | measure-only leftover 677; `make-extension-editor-dialog` vs editor dialog constructor | invent pause；地板优化另刀 |
| `cli_interactive_controller.make_runtime_auth_input_state` | 0.459 | 0.441 | 1.042× | 8.00× | measure-only leftover 678; `make-runtime-auth-input-state` vs runtime auth input constructor | invent pause；地板优化另刀 |
| `cli_interactive_controller.runtime_auth_input_handle_event` | 1.040 | 0.916 | 1.135× | 8.00× | measure-only leftover 679; `runtime-auth-input-state-handle-event` vs oauth runtime auth handleEvent | invent pause；地板优化另刀 |
| `cli_interactive_controller.render_runtime_auth_input` | 143.679 | 2.553 | 56.286× | 100.00× | measure-only leftover 680; `render-runtime-auth-input-state` vs oauth runtime auth render; first-freeze headroom 100.0 | invent pause；地板优化另刀 |
| `cli_interactive_controller.render_extension_custom_entry` | 0.434 | 0.155 | 2.800× | 8.00× | measure-only leftover 681; `render-extension-custom-entry` vs custom entry render nil host | invent pause；地板优化另刀 |
| `cli_interactive_controller.render_framed_select_state` | 230.310 | 2.267 | 101.599× | 180.00× | measure-only leftover 682; `render-framed-select-state` vs framed select-list render; first-freeze headroom 180.0 | invent pause；地板优化另刀 |
| `cli_interactive_controller.framed_select_state_handle_event` | 1.259 | 1.006 | 1.252× | 8.00× | measure-only leftover 683; `framed-select-state-handle-event` vs framed select-list handleEvent | invent pause；地板优化另刀 |
| `cli_interactive_controller.framed_select_state_handle_raw_input` | 87.360 | 0.953 | 91.669× | 160.00× | measure-only leftover 684; `framed-select-state-handle-raw-input` vs framed select-list handleRawInput; first-freeze headroom 160.0 | invent pause；地板优化另刀 |
| `cli_interactive_controller.render_extension_custom_ui` | 32.260 | 1.416 | 22.775× | 40.00× | measure-only leftover 685; `render-extension-custom-ui` vs custom ui render; first-freeze headroom 40.0 | invent pause；地板优化另刀 |
| `cli_interactive_controller.render_tui_extension_overlay` | 144.970 | 1.629 | 88.995× | 160.00× | measure-only leftover 687; `render-tui-extension-overlay` vs extension overlay composite; first-freeze headroom 160.0 | invent pause；地板优化另刀 |
| `find_tool.glob_scanner` | 10.624 | 0.951 | 11.176× | 20.00× | measure-only leftover 688; `glob-scanner` vs glob scanner compile+test; first-freeze headroom 20.0 | invent pause；地板优化另刀 |
| `find_tool.glob_regex_body` | 0.580 | 0.417 | 1.393× | 8.00× | measure-only leftover 689; `glob-regex-body` vs glob regex body | invent pause；地板优化另刀 |
| `find_tool.parse_gitignore_line` | 7.267 | 1.308 | 5.556× | 8.00× | measure-only leftover 690; `parse-gitignore-line` vs gitignore line parse | invent pause；地板优化另刀 |
| `find_tool.ignored_directory` | 16.582 | 1.923 | 8.621× | 16.00× | measure-only leftover 691; `ignored-directory-p` vs ignored directory names; first-freeze headroom 16.0 | invent pause；地板优化另刀 |
| `find_tool.gitignored` | 37.755 | 3.671 | 10.286× | 20.00× | measure-only leftover 692; `gitignored-p` vs gitignore rule apply; first-freeze headroom 20.0 | invent pause；地板优化另刀 |
| `find_tool.make_glob_tool` | 193.915 | 0.276 | 701.525× | 1200.00× | measure-only leftover 693; `make-glob-tool` vs glob tool constructor; first-freeze headroom 1200.0 | invent pause；地板优化另刀 |
| `bash_tool.user_bash_result` | 2.616 | 1.264 | 2.070× | 8.00× | measure-only leftover 695; `make-user-bash-result-from-execution` vs user bash result from execution | invent pause；地板优化另刀 |
| `bash_tool.normalized_extension` | 0.840 | 0.464 | 1.812× | 8.00× | measure-only leftover 696; `normalized-extension-bash-result` vs extension bash result normalize | invent pause；地板优化另刀 |
| `evals_harness.canonical_api` | 0.944 | 0.512 | 1.842× | 8.00× | measure-only leftover 697; `source-uses-canonical-extension-api-p` vs canonical extension API probe | invent pause；地板优化另刀 |
| `evals_harness.legacy_api` | 1.903 | 0.519 | 3.666× | 8.00× | measure-only leftover 698; `source-uses-legacy-extension-api-p` vs legacy extension API probe | invent pause；地板优化另刀 |
| `evals_harness.extension_error_json` | 0.860 | 0.180 | 4.784× | 8.00× | measure-only leftover 699; `extension-error-json` vs extension error JSON | invent pause；地板优化另刀 |
| `evals_harness.exclude_guidelines` | 0.742 | 0.197 | 3.757× | 8.00× | measure-only leftover 701; `exclude-guidelines-and-documentation` vs exclude Guidelines section | invent pause；地板优化另刀 |
| `evals_harness.prepare_default_prompt` | 2.797 | 0.417 | 6.700× | 8.00× | measure-only leftover 702; `prepare-default-prompt-override` vs prepare default prompt override | invent pause；地板优化另刀 |
| `evals_harness.reporter_run_id` | 2.621 | 0.891 | 2.941× | 8.00× | measure-only leftover 703; `reporter-run-id` vs artifact runId | invent pause；地板优化另刀 |
| `evals_harness.artifact_reference_json` | 0.913 | 0.155 | 5.883× | 8.00× | measure-only leftover 704; `artifact-reference-json` vs persist name/path | invent pause；地板优化另刀 |
| `package_manager.resource_file_p` | 10.973 | 1.792 | 6.124× | 8.00× | measure-only leftover 706; `config-resource-file-p` vs resource file match | invent pause；地板优化另刀 |
| `package_manager.resource_display_name` | 15.082 | 0.448 | 33.631× | 60.00× | measure-only leftover 707; `config-resource-display-name` vs resource display name; first-freeze headroom 60.0 | invent pause；地板优化另刀 |
| `package_manager.settings_array` | 1.161 | 0.485 | 2.393× | 8.00× | measure-only leftover 708; `config-settings-array` vs settings array coerce | invent pause；地板优化另刀 |
| `package_manager.autoload_disabled` | 0.758 | 0.347 | 2.181× | 8.00× | measure-only leftover 712; `config-package-entry-autoload-disabled-p` vs package autoload disabled | invent pause；地板优化另刀 |
| `package_manager.package_entry_filter` | 1.074 | 0.600 | 1.788× | 8.00× | measure-only leftover 713; `config-package-entry-filter` vs package entry filter | invent pause；地板优化另刀 |
| `package_manager.item_matches` | 10.553 | 0.951 | 11.092× | 20.00× | measure-only leftover 714; `config-selector-item-matches-p` vs item query match; first-freeze headroom 20.0 | invent pause；地板优化另刀 |
| `package_manager.resource_key` | 2.758 | 0.237 | 11.643× | 20.00× | measure-only leftover 715; `config-selector-resource-key` vs resource type key; first-freeze headroom 20.0 | invent pause；地板优化另刀 |
| `package_manager.relative_pattern` | 15.709 | 0.894 | 17.574× | 30.00× | measure-only leftover 716; `config-selector-relative-pattern` vs relative pattern; first-freeze headroom 30.0 | invent pause；地板优化另刀 |
| `package_manager.config_fit_line` | 5.200 | 1.862 | 2.793× | 8.00× | measure-only leftover 717; `config-selector-fit-line` vs truncateToWidth | invent pause；地板优化另刀 |
| `package_manager.group_less_p` | 3.937 | 0.552 | 7.128× | 8.00× | measure-only leftover 718; `config-resource-group-less-p` vs group sort | invent pause；地板优化另刀 |
| `package_manager.package_entry_has_filters` | 1.379 | 0.765 | 1.804× | 8.00× | measure-only leftover 719; `config-selector-package-entry-has-filters-p` vs package entry filters | invent pause；地板优化另刀 |
| `package_manager.selected_entry` | 0.968 | 0.810 | 1.195× | 8.00× | measure-only leftover 721; `config-selector-selected-entry` vs selected entry | invent pause；地板优化另刀 |
| `package_manager.scope_base` | 16.512 | 0.542 | 30.489× | 50.00× | measure-only leftover 726; `config-selector-scope-base` vs scope base; first-freeze headroom 50.0 | invent pause；地板优化另刀 |
| `package_manager.selector_items` | 10.768 | 0.481 | 22.378× | 40.00× | measure-only leftover 727; `config-selector-items` vs selector items; first-freeze headroom 40.0 | invent pause；地板优化另刀 |
| `package_manager.item_source_base` | 16.439 | 0.577 | 28.506× | 50.00× | measure-only leftover 728; `config-selector-item-source-base` vs item source base; first-freeze headroom 50.0 | invent pause；地板优化另刀 |
| `package_manager.package_resource_pattern` | 15.247 | 1.105 | 13.804× | 20.00× | measure-only leftover 729; `config-selector-package-resource-pattern` vs package resource pattern; first-freeze headroom 20.0 | invent pause；地板优化另刀 |
| `package_manager.package_override_source` | 18.871 | 1.522 | 12.402× | 20.00× | measure-only leftover 730; `config-selector-package-override-source` vs package override source; first-freeze headroom 20.0 | invent pause；地板优化另刀 |
| `package_manager.resource_group_label` | 17.081 | 0.540 | 31.609× | 50.00× | measure-only leftover 731; `config-resource-group-label` vs resource group label; first-freeze headroom 50.0 | invent pause；地板优化另刀 |
| `package_manager.settings_values` | 5.209 | 0.808 | 6.444× | 8.00× | measure-only leftover 732; `config-selector-settings-values` vs settings values | invent pause；地板优化另刀 |
| `package_manager.pattern_candidates` | 15.875 | 2.686 | 5.911× | 8.00× | measure-only leftover 733; `config-pattern-candidates` vs pattern candidates | invent pause；地板优化另刀 |
| `package_manager.pattern_matches` | 32.598 | 4.556 | 7.155× | 8.00× | measure-only leftover 734; `config-pattern-matches-p` vs pattern matches | invent pause；地板优化另刀 |
| `package_manager.enabled_by_patterns` | 31.989 | 6.637 | 4.820× | 8.00× | measure-only leftover 735; `config-enabled-by-patterns-p` vs enabled by patterns | invent pause；地板优化另刀 |
| `package_manager.delta_resource_state` | 17.140 | 4.344 | 3.946× | 8.00× | measure-only leftover 736; `config-package-delta-resource-state` vs package delta resource state | invent pause；地板优化另刀 |
| `package_manager.project_top_level_state` | 31.215 | 5.227 | 5.971× | 8.00× | measure-only leftover 737; `config-selector-project-top-level-state` vs project top-level state | invent pause；地板优化另刀 |
| `package_manager.derived_project_state` | 31.710 | 5.107 | 6.210× | 8.00× | measure-only leftover 738; `config-selector-derived-project-state` vs derived project state | invent pause；地板优化另刀 |
| `settings_load.environment_value` | 0.299 | 0.274 | 1.090× | 8.00× | measure-only leftover 739; `environment-value` vs env lookup | invent pause；地板优化另刀 |
| `settings_load.provider_settings` | 1.333 | 0.661 | 2.018× | 8.00× | measure-only leftover 741; `provider-settings` vs provider settings object | invent pause；地板优化另刀 |
| `settings_load.oauth_login_function` | 2.562 | 2.423 | 1.057× | 8.00× | measure-only leftover 744; `oauth-login-function` vs oauth login function | invent pause；地板优化另刀 |
| `provider_registry_defs.oauth_to_auth` | 0.428 | 0.267 | 1.601× | 8.00× | measure-only leftover 747; `built-in-oauth-to-auth` vs anthropic/kimi toAuth | invent pause；地板优化另刀 |
| `evals_harness.validate_extension` | 2.604 | 0.326 | 7.979× | 8.00× | measure-only leftover 925; `validate-extension-result` vs leftover greeting+path-count replica | invent pause；地板优化另刀 |
| `evals_harness.eval_result_p` | 0.608 | 0.331 | 1.836× | 8.00× | measure-only leftover 927; `typep` eval-result vs leftover object-shape predicate | invent pause；地板优化另刀 |
| `evals_harness.msg_content` | 1.008 | 0.745 | 1.352× | 8.00× | measure-only leftover 928; `message-content-text` vs leftover content-text join | invent pause；地板优化另刀 |
| `evals_harness.eval_tools` | 1.547 | 0.285 | 5.428× | 8.00× | measure-only leftover 929; `eval-agent-tools` vs leftover agent.tools list | invent pause；地板优化另刀 |
| `evals_harness.eval_paths` | 3.230 | 0.447 | 7.223× | 8.00× | measure-only leftover 930; `eval-extension-paths` vs leftover visible paths | invent pause；地板优化另刀 |
| `cli_print_rpc.cmd_list` | 1.533 | 0.333 | 4.603× | 8.00× | measure-only leftover 936; `rpc-command-list` vs leftover rpc command list | invent pause；地板优化另刀 |
| `cli_print_rpc.bad_line` | 5.686 | 4.505 | 1.262× | 8.00× | measure-only leftover 937; `rpc-handle-line` JSON.parse catch (does not remount handle_bad_json) | invent pause；地板优化另刀 |
| `cli_print_rpc.array_line` | 5.528 | 3.750 | 1.474× | 8.00× | measure-only leftover 938; `rpc-handle-line` require JSON object (does not remount handle_not_object) | invent pause；地板优化另刀 |
| `cli_print_rpc.ui_absent` | 6.543 | 1.557 | 4.202× | 8.00× | measure-only leftover 939; `rpc-handle-line` unknown extension_ui_response (does not remount handle_ui_miss) | invent pause；地板优化另刀 |
| `cli_interactive_controller.sess_make` | 0.244 | 0.216 | 1.130× | 8.00× | measure-only leftover 943; `make-tool-render-session` vs leftover ToolExecutionComponent construct | invent pause；地板优化另刀 |
| `cli_interactive_controller.sess_upd` | 0.257 | 0.227 | 1.132× | 8.00× | measure-only leftover 944; `update-tool-render-session` vs leftover result/pending | invent pause；地板优化另刀 |
| `cli_selectors.dlg_make` | 0.189 | 0.128 | 1.471× | 8.00× | measure-only leftover 946; `make-login-dialog-state` vs leftover LoginDialogComponent construct | invent pause；地板优化另刀 |
| `cli_selectors.dlg_auth` | 2.003 | 1.186 | 1.689× | 8.00× | measure-only leftover 947; `login-dialog-show-auth` vs leftover showAuth | invent pause；地板优化另刀 |
| `cli_selectors.dlg_dev` | 4.085 | 1.179 | 3.465× | 8.00× | measure-only leftover 948; `login-dialog-show-device-code` vs leftover showDeviceCode | invent pause；地板优化另刀 |
| `cli_interactive_controller.pad_str` | 0.215 | 0.206 | 1.041× | 8.00× | measure-only leftover 950; `output-padding-string` vs leftover output padding spaces | invent pause；地板优化另刀 |
| `cli_interactive_controller.cache_p` | 1.264 | 0.627 | 2.014× | 8.00× | measure-only leftover 951; `tui-entry-render-cacheable-p` vs leftover TUI entry render cacheable | invent pause；地板优化另刀 |
| `evals_harness.art_meta` | 1.038 | 0.879 | 1.181× | 8.00× | measure-only leftover 954; `reporter-artifact-metadata` vs leftover artifact metadata filter | invent pause；地板优化另刀 |
| `cli_interactive_controller.bash_run` | 0.807 | 0.363 | 2.219× | 8.00× | measure-only leftover 955; `append-tui-user-bash-running` vs leftover BashExecutionComponent addChild running | invent pause；地板优化另刀 |
| `cli_interactive_controller.bash_fin` | 0.785 | 0.300 | 2.620× | 8.00× | measure-only leftover 956; `complete-tui-user-bash-string` vs leftover setComplete exit 0 string | invent pause；地板优化另刀 |
| `cli_interactive_controller.bash_halt` | 0.635 | 0.221 | 2.872× | 8.00× | measure-only leftover 957; `stop-tui-user-bash-entry` vs leftover loader.stop without setComplete | invent pause；地板优化另刀 |
| `cli_selectors.oasx_ok` | 76.778 | 4.806 | 15.976× | 20.00× | measure-only leftover 1219; `oauth-selector-selection` vs leftover filteredProviders[selectedIndex] | invent pause；地板优化另刀 |
| `cli_selectors.fltx_ok` | 84.562 | 7.937 | 10.654× | 12.00× | measure-only leftover 1220; `oauth-selector-apply-filter` vs leftover filterProviders | invent pause；地板优化另刀 |
| `cli_selectors.qryx_ok` | 1.347 | 0.531 | 2.535× | 8.00× | measure-only leftover 1221; `oauth-selector-search-text` vs leftover filterProviders search text | invent pause；地板优化另刀 |
Ceilings not lowered. Do not redo withdrawn phenomenon knives.
