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
| `ls_tool.list_directory` | 352.2 | 314.9 | 1.119× | 8.00× | measure-only pair 317; `list-directory` empty/mixed/limit listing | invent pause；地板优化另刀 |
| `ls_tool.make_tool` | 284.4 | 279.6 | 1.017× | 8.00× | measure-only pair 318; `make-ls-tool` vs `createLsToolDefinition` | invent pause；地板优化另刀 |
| `cli_settings.enabled_models` | 18.7 | 3.26 | 5.735× | 8.00× | measure-only pair 308; `settings-enabled-models` missing→`:all` plus one in-memory pattern | invent pause；地板优化另刀 |
| `cli_settings.block_images` | 19.1 | 3.41 | 5.623× | 8.00× | measure-only pair 309; `settings-block-images-p` default false plus in-memory `images.blockImages` | invent pause；地板优化另刀 |

| `file_mutation_queue.pending_count` | 194.6 | 135.5 | 1.435× | 8.00× | measure-only pair 304; `file-mutation-queue-state-pending-count` after enqueue | invent pause；地板优化另刀 |
| `file_mutation_queue.next_ticket` | 157.9 | 137.6 | 1.147× | 8.00× | measure-only pair 305; `file-mutation-queue-state-next-ticket` after enqueue | invent pause；地板优化另刀 |
| `oauth_pkce_device.percent_decode` | 1.592 | 1.044 | 1.525× | 8.00× | measure-only pair 310; `percent-decode` vs URLSearchParams | invent pause；地板优化另刀 |
| `oauth_pkce_device.parse_query` | 6.672 | 3.431 | 1.944× | 8.00× | measure-only pair 311; `parse-query` vs URLSearchParams | invent pause；地板优化另刀 |
| `cli_interactive_controller.make_entry` | 1.424 | 0.238 | 5.982× | 8.00× | measure-only pair 493; `make-tui-user-bash-entry` vs BashExecutionComponent constructor (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_interactive_controller.append_output` | 0.776 | 0.290 | 2.670× | 8.00× | measure-only pair 494; `append-tui-user-bash-output` vs appendOutput concatenate (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_interactive_controller.complete_entry` | 0.974 | 0.404 | 2.411× | 8.00× | measure-only pair 495; `complete-tui-user-bash-entry` vs setComplete (sub-µs variance) | invent pause；地板优化另刀 |

Ceilings not lowered. Do not redo withdrawn phenomenon knives.
