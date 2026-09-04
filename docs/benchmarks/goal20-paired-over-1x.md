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
| `ai_support.threads_absent` | 0.165 | 0.077 | 2.141× | 8.00× | leftover collect restore pair 883; `stop-thread-for-cleanup` nil vs worker_threads absent | invent pause；地板优化另刀 |
| `ai_support.threads_current` | 0.135 | 0.072 | 1.882× | 8.00× | leftover collect restore pair 884; `stop-thread-for-cleanup` current vs isMainThread | invent pause；地板优化另刀 |

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
| `oauth_pkce_device.base64url_value` | 0.739 | 0.293 | 2.520× | 8.00× | leftover collect restore pair 358; `base64url-value` vs RFC 4648 §5 alphabet; sub-µs | invent pause；地板优化另刀 |
| `oauth_pkce_device.base64url_decode` | 2.922 | 0.452 | 6.461× | 8.00× | leftover collect restore pair 359; `base64url-decode` vs `decodeJwt` `atob` | invent pause；地板优化另刀 |
| `oauth_pkce_device.account_id` | 6.065 | 1.174 | 5.167× | 8.00× | leftover collect restore pair 360; `openai-account-id-from-token` vs `getAccountId` | invent pause；地板优化另刀 |
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
| `oauth_pkce_device.error_detail` | 0.810 | 0.371 | 2.184× | 8.00× | leftover collect restore pair 379; `oauth-response-error-detail` vs xai.ts requestFailure detail (sub-µs) | invent pause；地板优化另刀 |
| `oauth_pkce_device.notify_device` | 0.889 | 0.336 | 2.643× | 8.00× | leftover collect restore pair 381; `notify-device-authorization` vs xai.ts interaction.notify device_code (sub-µs) | invent pause；地板优化另刀 |
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
| `oauth_pkce_device.json_copy` | 0.938 | 0.432 | 2.173× | 8.00× | leftover collect restore pair 421; `oauth-response-json-copy` vs JSON.stringify error-body copy | invent pause；地板优化另刀 |
| `oauth_pkce_device.device_start` | 8.602 | 8.064 | 1.067× | 8.00× | leftover collect restore pair 423; stubbed `start-openai-codex-device-authorization` | invent pause；地板优化另刀 |
| `evals_harness.eval_layout` | 3.297 | 1.074 | 3.071× | 8.00× | measure-only pair 418; leftover eval workspace/agent/sessions layout vs path join | invent pause；地板优化另刀 |
| `evals_harness.output_selector` | 0.189 | 0.188 | 1.007× | 8.00× | measure-only pair 420; leftover `:selector` vs `options.output`; sub-µs — variance floor applies | invent pause；地板优化另刀 |
| `oauth_pkce_device.openrouter_exchange` | 7.533 | 6.469 | 1.164× | 8.00× | leftover collect restore pair 438; leftover `openrouter-exchange-code` vs `exchangeAuthorizationCode` (stubbed HTTP) | invent pause；地板优化另刀 |
| `oauth_pkce_device.anth_oauth_name` | 0.373 | 0.099 | 3.755× | 8.00× | leftover collect restore pair 880; anthropicOAuth.name | invent pause；地板优化另刀 |
| `oauth_pkce_device.anth_oauth_sub` | 0.143 | 0.075 | 1.913× | 8.00× | leftover collect restore pair 881; anthropicOAuth.isSubscription | invent pause；地板优化另刀 |
| `oauth_pkce_device.anth_oauth_instructions` | 0.729 | 0.103 | 7.100× | 8.00× | leftover collect restore pair 882; login notify instructions | invent pause；地板优化另刀 |
| `oauth_pkce_device.kimi_host_default` | 0.348 | 0.152 | 2.293× | 8.00× | leftover collect restore pair 877; getOauthHost DEFAULT_OAUTH_HOST | invent pause；地板优化另刀 |
| `oauth_pkce_device.kimi_host_code` | 0.440 | 0.159 | 2.773× | 8.00× | leftover collect restore pair 878; getOauthHost KIMI_CODE_OAUTH_HOST | invent pause；地板优化另刀 |
| `oauth_pkce_device.kimi_host_trim` | 0.614 | 0.204 | 3.014× | 8.00× | leftover collect restore pair 879; getOauthHost trailing-slash trim | invent pause；地板优化另刀 |
| `output_accumulator.needs_file` | 50.564 | 20.524 | 2.464× | 8.00× | measure-only pair 428; leftover `needs-file-p` vs `shouldUseTempFile` | invent pause；地板优化另刀 |
| `evals_harness.artifact_metadata` | 1.025 | 0.868 | 1.182× | 8.00× | measure-only pair 432; leftover `reporter-artifact-metadata` vs `appendHarnessRunReport` metadata filter | invent pause；地板优化另刀 |
| `evals_harness.extension_authoring_input` | 1.148 | 0.246 | 4.662× | 8.00× | measure-only pair 439; `extension-authoring-input` types/length leftover (sub-µs variance) | invent pause；地板优化另刀 |
| `evals_harness.json_string` | 0.902 | 0.180 | 5.012× | 8.00× | measure-only pair 441; `json-string` leftover vs missing/false JSON accessor (sub-µs variance) | invent pause；地板优化另刀 |
| `package_manager.type_label` | 0.135 | 0.134 | 1.002× | 8.00× | measure-only pair 444; `config-resource-type-label` leftover (sub-µs variance) | invent pause；地板优化另刀 |
| `package_manager.update_argv` | 8.431 | 3.270 | 2.579× | 8.00× | leftover collect restore pair 445; `package-update-check-process-argv` (sub-µs path) | invent pause；地板优化另刀 |
| `package_manager.git_object_id` | 3.300 | 1.095 | 3.013× | 8.00× | leftover collect restore pair 447; `package-update-git-object-id` vs getRemoteGitHead extract | invent pause；地板优化另刀 |
| `find_tool.glob_regex` | 0.527 | 0.220 | 2.403× | 8.00× | measure-only pair 448; leftover `glob-regex-source` (sub-µs path) | invent pause；地板优化另刀 |
| `find_tool.gitignore_regex` | 0.693 | 0.607 | 1.142× | 8.00× | measure-only pair 450; leftover `gitignore-regex-source` (sub-µs path) | invent pause；地板优化另刀 |
| `settings_load.provider_symbol` | 0.313 | 0.231 | 1.351× | 8.00× | measure-only pair 454; leftover `provider-symbol` (sub-µs path) | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.legacy_product` | 0.171 | 0.145 | 1.178× | 8.00× | measure-only pair 457; leftover `legacy-product-name` (sub-µs path) | invent pause；地板优化另刀 |
| `cli_support.no_models_help` | 244.9 | 8.92 | 27.45× | 50.00× | measure-only pair 460; leftover CLI wrapper; same ASDF docs-dir as `ai_support.auth_guidance` | invent pause；地板/去 ASDF 另刀 |
| `cli_support.no_model_selected` | 245.4 | 8.87 | 27.67× | 50.00× | measure-only pair 461; leftover CLI wrapper; same ASDF docs-dir as `ai_support.auth_guidance` | invent pause；地板/去 ASDF 另刀 |
| `cli_support.no_api_key` | 480.3 | 17.48 | 27.48× | 50.00× | measure-only pair 462; leftover CLI wrapper; same ASDF docs-dir as `ai_support.auth_guidance` | invent pause；地板/去 ASDF 另刀 |
| `cli_support.provider_login_help` | 477.0 | 10.48 | 45.52× | 50.00× | measure-only pair 907; leftover CLI wrapper; same ASDF docs-dir as 460–462 | invent pause；地板/去 ASDF 另刀 |
| `cli_support.docs_directory` | 227.9 | 6.83 | 33.35× | 50.00× | measure-only pair 908; leftover CLI docs path; same ASDF docs-dir as 460–462 | invent pause；地板/去 ASDF 另刀 |
| `cli_print_rpc.rpc_prompt` | 1.323 | 0.584 | 2.266× | 8.00× | measure-only leftover 464; `rpc-prompt-message` vs RPC prompt message+images (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_print_rpc.bash_result` | 2.165 | 0.743 | 2.913× | 8.00× | measure-only leftover 465; `rpc-bash-result-json` vs RPC bash result payload (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_print_rpc.dialog_request` | 1.570 | 0.648 | 2.423× | 8.00× | leftover collect restore pair 466; `rpc-dialog-request-object` vs createDialogPromise request | invent pause；地板优化另刀 |
| `cli_print_rpc.dialog_result` | 2.387 | 0.350 | 6.823× | 8.00× | leftover collect restore pair 467; `rpc-dialog-result` vs createDialogPromise parseResponse | invent pause；地板优化另刀 |
| `settings_load.sdk_nonempty` | 20.855 | 6.284 | 3.319× | 8.00× | measure-only pair 469; leftover `sdk-nonempty-setting-string` vs `getDefaultProvider` | invent pause；地板优化另刀 |
| `settings_load.sdk_boolean` | 13.423 | 6.283 | 2.136× | 8.00× | measure-only pair 470; leftover `sdk-settings-boolean` vs `getCompactionEnabled` | invent pause；地板优化另刀 |
| `settings_load.sdk_tools` | 12.769 | 6.268 | 2.037× | 8.00× | measure-only pair 471; leftover `sdk-settings-enabled-tools` vs `getDefaultTools` | invent pause；地板优化另刀 |
| `skill_prompt_load.resolve_prompt` | 16.882 | 4.643 | 3.636× | 8.00× | measure-only pair 472; leftover `resolve-system-prompt` vs `resolvePromptInput` | invent pause；地板优化另刀 |
| `skill_prompt_load.node_read_error` | 10.042 | 3.219 | 3.120× | 8.00× | measure-only pair 473; leftover `node-read-error-message` vs Node fs errno text | invent pause；地板优化另刀 |
| `skill_prompt_load.prompt_appends` | 6.306 | 1.930 | 3.268× | 8.00× | measure-only pair 474; leftover `resolve-system-prompt-with-appends` vs append join | invent pause；地板优化另刀 |
| `cli_print_rpc.command_list` | 1.490 | 0.359 | 4.151× | 8.00× | measure-only leftover pair 477; `rpc-command-list` vs `get_commands` walk | invent pause；地板优化另刀 |
| `skill_prompt_load.sdk_prompt_input` | 15.179 | 3.512 | 4.322× | 8.00× | measure-only leftover pair 478; `sdk-resolve-prompt-input` vs `resolvePromptInput` | invent pause；地板优化另刀 |
| `skill_prompt_load.sdk_context_files` | 7.556 | 2.625 | 2.879× | 8.00× | measure-only leftover pair 480; `sdk-context-file-records` vs agentsFiles records | invent pause；地板优化另刀 |
| `skill_prompt_load.sdk_get_skills` | 0.175 | 0.110 | 1.587× | 8.00× | leftover collect restore pair 919; `sdk-resource-loader-skills` vs DefaultResourceLoader.getSkills | invent pause；地板优化另刀 |
| `skill_prompt_load.sdk_get_prompts` | 0.167 | 0.123 | 1.367× | 8.00× | leftover collect restore pair 920; `sdk-resource-loader-prompts` vs getPrompts | invent pause；地板优化另刀 |
| `skill_prompt_load.sdk_get_themes` | 0.298 | 0.117 | 2.560× | 8.00× | leftover collect restore pair 921; `sdk-resource-loader-themes` vs getThemes | invent pause；地板优化另刀 |
| `cli_support.watch_signature` | 23.825 | 6.843 | 3.482× | 8.00× | leftover collect restore pair 483; `watched-path-signature` vs statSync presence | invent pause；地板优化另刀 |
| `cli_support.watch_retry_delay` | 0.157 | 0.118 | 1.335× | 8.00× | leftover collect restore pair 481; `+fs-watch-retry-delay-milliseconds+` vs FS_WATCH_RETRY_DELAY_MS | invent pause；地板优化另刀 |
| `cli_support.close_watcher` | 0.162 | 0.155 | 1.046× | 8.00× | leftover collect restore pair 482; `close-watcher` vs closeWatcher | invent pause；地板优化另刀 |
| `cli_support.write_hello` | 277.332 | 165.319 | 1.678× | 8.00× | leftover collect restore pair 871; `atomic-write-utf8` hello vs activateManagedRelease temp+rename | invent pause；地板优化另刀 |
| `cli_support.write_overwrite` | 438.860 | 338.824 | 1.295× | 8.00× | leftover collect restore pair 872; `atomic-write-utf8` overwrite vs activateManagedRelease | invent pause；地板优化另刀 |
| `cli_support.write_empty` | 129.194 | 46.306 | 2.790× | 15.00× | leftover collect restore pair 873; `atomic-write-utf8` empty vs activateManagedRelease | invent pause；地板优化另刀 |
| `cli_support.threads_absent` | 0.192 | 0.118 | 1.631× | 8.00× | leftover collect restore pair 886; `stop-thread-for-cleanup` nil vs worker_threads absent | invent pause；地板优化另刀 |
| `cli_support.threads_current` | 0.139 | 0.120 | 1.165× | 8.00× | leftover collect restore pair 887; `stop-thread-for-cleanup` current vs isMainThread | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.model_scope_line` | 37.431 | 23.274 | 1.608× | 8.00× | measure-only leftover pair 485; `model-scope-startup-line` vs interactive-mode init line | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.response_text` | 0.939 | 0.714 | 1.314× | 8.00× | measure-only pair 491; `response-text` vs `textParts.join` (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.data_directory` | 8.765 | 0.883 | 9.926× | 40.00× | leftover collect restore pair 838; `data-directory` vs join(home, CONFIG_DIR_NAME) | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.legacy_data_directory` | 8.924 | 1.122 | 7.950× | 40.00× | leftover collect restore pair 839; `legacy-data-directory` vs join(home, .legacy) | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.manual_migration_command` | 4.577 | 1.679 | 2.726× | 8.00× | leftover collect restore pair 840; `manual-migration-command` vs mv -- quoted paths | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.managed_binary_names` | 0.430 | 0.315 | 1.362× | 8.00× | leftover collect restore pair 841; `+managed-binary-names+` vs fd/rg names | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.migration_guide_url` | 0.656 | 0.212 | 3.089× | 8.00× | leftover collect restore pair 842; `+migration-guide-url+` vs MIGRATION_GUIDE_URL | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.extensions_doc_url` | 0.549 | 0.204 | 2.691× | 8.00× | leftover collect restore pair 843; `+extensions-doc-url+` vs EXTENSIONS_DOC_URL | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.rt_ok` | 1.475 | 0.590 | 2.499× | 8.00× | leftover collect restore pair 1013; `response-text` vs textParts.join replica (does not remount response_text) | invent pause；地板优化另刀 |
| `cli_interactive_controller.make_entry` | 1.424 | 0.238 | 5.982× | 8.00× | measure-only pair 493; `make-tui-user-bash-entry` vs BashExecutionComponent constructor (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_interactive_controller.append_output` | 0.776 | 0.290 | 2.670× | 8.00× | measure-only pair 494; `append-tui-user-bash-output` vs appendOutput concatenate (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_interactive_controller.complete_entry` | 0.974 | 0.404 | 2.411× | 8.00× | measure-only pair 495; `complete-tui-user-bash-entry` vs setComplete (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_print_rpc.handle_bad_json` | 5.390 | 4.937 | 1.092× | 8.00× | measure-only pair 496; `rpc-handle-line` JSON.parse catch (sub-µs variance) | invent pause；地板优化另刀 |
| `cli_print_rpc.handle_not_object` | 5.213 | 4.889 | 1.066× | 8.00× | measure-only pair 497; `rpc-handle-line` require-object | invent pause；地板优化另刀 |
| `cli_print_rpc.handle_ui_miss` | 6.190 | 1.521 | 4.070× | 8.00× | measure-only pair 498; `rpc-handle-line` unknown extension_ui_response | invent pause；地板优化另刀 |
| `cli_extensions_install.unsafe_git` | 0.776 | 0.610 | 1.272× | 8.00× | leftover collect restore pair 499; `unsafe-git-source-p` vs hasUnsafeGitInstallPart (sub-µs) | invent pause；地板优化另刀 |
| `cli_extensions_install.git_path` | 1.075 | 0.579 | 1.855× | 8.00× | leftover collect restore pair 500; `git-source-path` vs git URL path slice | invent pause；地板优化另刀 |
| `cli_extensions_install.quant_label` | 1.070 | 0.868 | 1.232× | 8.00× | leftover collect restore pair 507; `llama-quantization-option-label` vs downloadModel option text | invent pause；地板优化另刀 |
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
| `cli_extensions_install.llama_context_label` | 1.425 | 1.134 | 1.257× | 8.00× | leftover collect restore pair 544; `llama-context-label` vs `contextLabel` | invent pause；地板优化另刀 |
| `cli_extensions_install.llama_model_description` | 1.569 | 1.357 | 1.156× | 8.00× | leftover collect restore pair 545; `llama-model-description` vs `modelDescription` | invent pause；地板优化另刀 |
| `cli_extensions_install.llama_compact_count` | 1.017 | 0.638 | 1.593× | 8.00× | leftover collect restore pair 546; `llama-compact-count` vs `compactCount` | invent pause；地板优化另刀 |
| `cli_selectors.daxnuts_image_line` | 36.319 | 16.357 | 2.220× | 8.00× | measure-only leftover 548; `daxnuts-image-line` vs `buildImage` half-block row | invent pause；地板优化另刀 |
| `cli_interactive_controller.framed_select_title` | 0.775 | 0.551 | 1.406× | 8.00× | measure-only leftover 550; `framed-select-title` vs countdown `${title} (${s}s)` (sub-µs) | invent pause；地板优化另刀 |
| `cli_interactive_controller.extension_overlay_options` | 1.270 | 0.601 | 2.114× | 8.00× | measure-only leftover 551; `extension-overlay-options` vs resolveOptions | invent pause；地板优化另刀 |
| `cli_interactive_controller.extension_custom_ui_visible` | 1.027 | 0.551 | 1.866× | 8.00× | measure-only leftover 552; `extension-custom-ui-visible-p` flags (no size callback) | invent pause；地板优化另刀 |
| `cli_selectors.countdown_seconds` | 0.768 | 0.335 | 2.292× | 8.00× | measure-only leftover 556; `make-countdown-timer` remaining seconds vs `Math.ceil` (sub-µs) | invent pause；地板优化另刀 |
| `cli_selectors.countdown_tick` | 0.700 | 0.233 | 3.006× | 8.00× | measure-only leftover 557; `countdown-timer-tick` vs interval body (sub-µs) | invent pause；地板优化另刀 |
| `cli_selectors.countdown_render` | 0.892 | 0.463 | 1.928× | 8.00× | measure-only leftover 558; `countdown-request-render` vs `tui?.requestRender` (sub-µs) | invent pause；地板优化另刀 |
| `cli_selectors.countdown_dispose` | 0.318 | 0.179 | 1.773× | 8.00× | measure-only leftover 904-906; remeasure Friend-MachineD | countdown dispose trio |
| `cli_selectors.countdown_unstarted` | 0.249 | 0.150 | 1.653× | 8.00× | measure-only leftover 904-906; remeasure Friend-MachineD | countdown dispose trio |
| `cli_selectors.countdown_start_guard` | 0.292 | 0.200 | 1.458× | 8.00× | measure-only leftover 904-906; remeasure Friend-MachineD | countdown dispose trio |
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
| `cli_selectors.daxnuts_render` | 594.5 | 146.6 | 4.055× | 8.00× | measure-only pair 910; `cadr-tui:component-render` vs leftoverDaxnutsRenderOnce | invent pause；地板优化另刀 |
| `cli_selectors.daxnuts_invalidate` | 21.78 | 3.568 | 6.106× | 8.00× | measure-only pair 911; `cadr-tui:component-invalidate` vs leftoverDaxnutsInvalidateOnce | invent pause；地板优化另刀 |
| `cli_selectors.daxnuts_dispose` | 0.851 | 0.241 | 3.537× | 8.00× | measure-only pair 912; `cadr-tui:component-dispose` vs leftoverDaxnutsDisposeUnstarted | invent pause；地板优化另刀 |
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
| `find_tool.directory_gitignore_rules` | 598.841 | 366.283 | 1.635× | 8.00× | measure-only leftover 901-903; remeasure Friend-MachineD | glob walk trio |
| `find_tool.collect_tree_files` | 754.579 | 573.769 | 1.315× | 8.00× | measure-only leftover 901-903; remeasure Friend-MachineD | glob walk trio |
| `find_tool.glob_files` | 1370.273 | 702.302 | 1.951× | 8.00× | measure-only leftover 901-903; remeasure Friend-MachineD | glob walk trio |
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
| `settings_load.sdk_default_provider` | 34.963 | 14.971 | 2.335× | 8.00× | leftover collect restore pair 763; `sdk-settings-default-provider` vs SettingsManager.getDefaultProvider | invent pause；地板优化另刀 |
| `settings_load.sdk_default_model` | 36.317 | 7.229 | 5.024× | 8.00× | leftover collect restore pair 764; `sdk-settings-default-model` vs getDefaultModel | invent pause；地板优化另刀 |
| `settings_load.sdk_retry_settings` | 19.285 | 10.602 | 1.819× | 8.00× | leftover collect restore pair 765; `sdk-settings-retry-settings` vs getRetrySettings | invent pause；地板优化另刀 |
| `provider_registry_defs.oauth_to_auth` | 0.428 | 0.267 | 1.601× | 8.00× | measure-only leftover 747; `built-in-oauth-to-auth` vs anthropic/kimi toAuth | invent pause；地板优化另刀 |
| `provider_registry_defs.models_runtime` | 412.117 | 258.229 | 1.596× | 8.00× | leftover collect restore pair 753; `make-built-in-models-runtime` vs builtinProviders Map | invent pause；地板优化另刀 |
| `provider_registry_defs.protocol_provider` | 1.756 | 1.358 | 1.293× | 8.00× | leftover collect restore pair 754; `make-protocol-provider` openai-responses vs openAIResponsesApi | invent pause；地板优化另刀 |
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
| `cli_interactive_controller.sess_new` | 0.550 | 0.172 | 3.192× | 8.00× | measure-only leftover 964; `make-tool-render-session` vs leftover ToolExecutionComponent construct (does not remount sess_make) | invent pause；地板优化另刀 |
| `cli_interactive_controller.sess_set` | 0.537 | 0.196 | 2.746× | 8.00× | measure-only leftover 965; `update-tool-render-session` vs leftover result/pending (does not remount sess_upd) | invent pause；地板优化另刀 |
| `cli_selectors.dlg_make` | 0.189 | 0.128 | 1.471× | 8.00× | measure-only leftover 946; `make-login-dialog-state` vs leftover LoginDialogComponent construct | invent pause；地板优化另刀 |
| `cli_selectors.dlg_auth` | 2.003 | 1.186 | 1.689× | 8.00× | measure-only leftover 947; `login-dialog-show-auth` vs leftover showAuth | invent pause；地板优化另刀 |
| `cli_selectors.dlg_dev` | 4.085 | 1.179 | 3.465× | 8.00× | measure-only leftover 948; `login-dialog-show-device-code` vs leftover showDeviceCode | invent pause；地板优化另刀 |
| `cli_interactive_controller.pad_str` | 0.215 | 0.206 | 1.041× | 8.00× | measure-only leftover 950; `output-padding-string` vs leftover output padding spaces | invent pause；地板优化另刀 |
| `cli_interactive_controller.cache_p` | 1.264 | 0.627 | 2.014× | 8.00× | measure-only leftover 951; `tui-entry-render-cacheable-p` vs leftover TUI entry render cacheable | invent pause；地板优化另刀 |
| `evals_harness.art_meta` | 1.038 | 0.879 | 1.181× | 8.00× | measure-only leftover 954; `reporter-artifact-metadata` vs leftover artifact metadata filter | invent pause；地板优化另刀 |
| `cli_interactive_controller.bash_run` | 0.807 | 0.363 | 2.219× | 8.00× | measure-only leftover 955; `append-tui-user-bash-running` vs leftover BashExecutionComponent addChild running | invent pause；地板优化另刀 |
| `cli_interactive_controller.bash_fin` | 0.785 | 0.300 | 2.620× | 8.00× | measure-only leftover 956; `complete-tui-user-bash-string` vs leftover setComplete exit 0 string | invent pause；地板优化另刀 |
| `cli_interactive_controller.bash_halt` | 0.635 | 0.221 | 2.872× | 8.00× | measure-only leftover 957; `stop-tui-user-bash-entry` vs leftover loader.stop without setComplete | invent pause；地板优化另刀 |
| `cli_selectors.latxxx_ok` | 2.534 | 1.220 | 2.078× | 8.00× | measure-only leftover 1354; `login-auth-type-route` vs leftover showLoginAuthTypeSelector routing | invent pause；地板优化另刀 |
| `cli_selectors.lpoxxx_ok` | 8.355 | 5.726 | 1.459× | 8.00× | measure-only leftover 1355; `login-provider-options` vs leftover getLoginProviderOptions | invent pause；地板优化另刀 |
| `cli_selectors.lgoxxx_ok` | 7.260 | 3.422 | 2.122× | 8.00× | measure-only leftover 1356; `logout-provider-options` vs leftover getLogoutProviderOptions | invent pause；地板优化另刀 |
| `cli_selectors.lstxxx_ok` | 1.172 | 0.743 | 1.577× | 8.00× | measure-only leftover 1365; `thinking-level-search-text` vs leftover thinking selector label + description search text | invent pause；地板优化另刀 |
| `cli_selectors.ldwxxx_ok` | 5.581 | 2.175 | 2.566× | 8.00× | measure-only leftover 1381; `login-dialog-show-waiting` vs leftover showWaiting | invent pause；地板优化另刀 |
| `cli_selectors.ldpxxx_ok` | 3.206 | 1.811 | 1.770× | 8.00× | measure-only leftover 1382; `login-dialog-show-progress` vs leftover showProgress | invent pause；地板优化另刀 |
| `cli_selectors.ldmixxx_ok` | 5.271 | 2.515 | 2.096× | 8.00× | measure-only leftover 1383; `login-dialog-show-manual-input` vs leftover showManualInput | invent pause；地板优化另刀 |
| `cli_selectors.ldprxxx_ok` | 7.001 | 3.234 | 2.164× | 8.00× | measure-only leftover 1384; `login-dialog-show-prompt` vs leftover showPrompt | invent pause；地板优化另刀 |
| `cli_selectors.ldixxx_ok` | 9.135 | 3.977 | 2.297× | 8.00× | measure-only leftover 1385; `login-dialog-show-info` vs leftover showInfo | invent pause；地板优化另刀 |
| `cli_selectors.ldcixxx_ok` | 5.854 | 1.813 | 3.230× | 8.00× | measure-only leftover 1387; `login-dialog-complete-input` vs leftover replaceInputWithSubmittedText | invent pause；地板优化另刀 |
| `cli_selectors.ldhexxx_ok` | 7.396 | 2.562 | 2.887× | 8.00× | measure-only leftover 1388; `login-dialog-handle-event` vs leftover handleInput | invent pause；地板优化另刀 |
| `cli_selectors.ldrdxxx_ok` | 106.883 | 3.590 | 29.776× | 50.00× | measure-only leftover 1389; `render-login-dialog-state` vs leftover LoginDialogComponent layout | invent pause；地板优化另刀 |
| `cli_selectors.umrwxxx_ok` | 85.685 | 4.862 | 17.622× | 30.00× | measure-only leftover 1391; `user-message-selector-handle-raw-input` vs leftover handleInput raw | invent pause；地板优化另刀 |
| `cli_selectors.umrsxxx_ok` | 242.804 | 3.433 | 70.735× | 100.00× | measure-only leftover 1392; `render-user-message-selector` vs leftover UserMessageSelectorComponent layout | invent pause；地板优化另刀 |
| `cli_selectors.mkbxxx_ok` | 32.739 | 21.614 | 1.515× | 8.00× | measure-only leftover 1393; `make-models-selector-keybindings` vs leftover KeybindingsManager app.models.* | invent pause；地板优化另刀 |
| `cli_selectors.msmsxxx_ok` | 105.397 | 4.314 | 24.432× | 40.00× | measure-only leftover 1394; `make-scoped-models-selector-state` vs leftover ScopedModelsSelectorComponent constructor | invent pause；地板优化另刀 |
| `cli_selectors.mrmsxxx_ok` | 196.853 | 7.167 | 27.467× | 50.00× | measure-only leftover 1395; `render-model-selector` vs leftover ModelSelectorComponent layout | invent pause；地板优化另刀 |
| `cli_selectors.thafxxx_ok` | 13.551 | 10.831 | 1.251× | 8.00× | measure-only leftover 1396; `thinking-selector-apply-filter` vs leftover applyFilter | invent pause；地板优化另刀 |
| `cli_selectors.thmvxxx_ok` | 0.633 | 0.378 | 1.675× | 8.00× | measure-only leftover 1399; `thinking-selector-move` vs leftover wrap selected | invent pause；地板优化另刀 |
| `cli_selectors.thhrxxx_ok` | 143.544 | 5.996 | 23.939× | 30.00× | measure-only leftover 1400; `thinking-selector-handle-raw-input` vs leftover handleInput | invent pause；地板优化另刀 |
| `cli_selectors.trsvxxx_ok` | 76.972 | 15.197 | 5.065× | 8.00× | measure-only leftover 1402; `trust-option-saved-p` vs leftover isSavedOption | invent pause；地板优化另刀 |
| `cli_selectors.trmkxxx_ok` | 131.369 | 51.480 | 2.552× | 8.00× | measure-only leftover 1403; `make-trust-selector-state` vs leftover TrustSelectorComponent constructor | invent pause；地板优化另刀 |
| `cli_selectors.trrsxxx_ok` | 1023.386 | 111.757 | 9.157× | 15.00× | measure-only leftover 1404; `render-trust-selector` vs leftover TrustSelectorComponent layout | invent pause；地板优化另刀 |
| `cli_selectors.lmsxxxx_ok` | 2.681 | 2.105 | 1.274× | 8.00× | measure-only leftover 1405; `make-login-method-selector-state` vs leftover ExtensionSelector login-method constructor | invent pause；地板优化另刀 |
| `cli_selectors.akixxxx_ok` | 2.164 | 1.061 | 2.039× | 8.00× | measure-only leftover 1406; `make-api-key-input-state` vs leftover showPrompt api key Input constructor | invent pause；地板优化另刀 |
| `cli_selectors.ossxxxx_ok` | 7.239 | 5.400 | 1.340× | 8.00× | measure-only leftover 1407; `make-oauth-selector-state` vs leftover OauthSelectorComponent constructor | invent pause；地板优化另刀 |
| `settings_load.read_cli_config` | 260.6 | 219.3 | 1.19× | 8.00× | measure-only leftover 760; `read-cli-config` vs JSON.parse settings object | invent pause；地板优化另刀 |
| `settings_load.provider_config_secrets` | 61.3 | 1.9 | 33.09× | 50.00× | measure-only leftover 761; `provider-config-secrets` vs apiKey/oauth/env collect; first-freeze headroom 50.0 | invent pause；地板优化另刀 |
| `settings_load.resolve_provider_config` | 208.7 | 202.5 | 1.03× | 8.00× | measure-only leftover 762; `resolve-provider-config` vs openaiProvider construct | invent pause；地板优化另刀 |
| `package_manager.records_project_first` | 0.6 | 0.5 | 1.06× | 8.00× | measure-only leftover 757; `package-update-records-project-first` vs project-then-user collect | invent pause；地板优化另刀 |
| `package_manager.candidate_record` | 7.8 | 2.5 | 3.05× | 20.00× | measure-only leftover 758; `package-update-candidate-record-p` vs git/unpinned/exists; first-freeze headroom 20.0 | invent pause；地板优化另刀 |
| `package_manager.update_offline` | 0.4 | 0.3 | 1.57× | 8.00× | measure-only leftover 759; `check-for-available-package-updates` offline vs isOfflineModeEnabled | invent pause；地板优化另刀 |
| `settings_load.sdk_http_idle_timeout` | 11.3 | 8.0 | 1.41× | 8.00× | measure-only leftover 766; `sdk-settings-http-idle-timeout-ms` vs getHttpIdleTimeoutMs | invent pause；地板优化另刀 |
| `settings_load.sdk_apply_overrides` | 47.3 | 6.2 | 7.58× | 8.00× | measure-only leftover 767; `sdk-settings-apply-overrides` vs applyOverrides | invent pause；地板优化另刀 |
| `settings_load.sdk_model_thinking_level` | 16.8 | 3.1 | 5.35× | 8.00× | measure-only leftover 768; `sdk-settings-model-thinking-level` vs getModelThinkingLevel | invent pause；地板优化另刀 |
| `settings_load.sdk_settings_value` | 33.5 | 0.3 | 114.68× | 150.00× | measure-only leftover 769; `sdk-settings-value` vs Settings json-get | invent pause；地板优化另刀 |
| `settings_load.sdk_default_thinking_level` | 10.3 | 4.1 | 2.54× | 8.00× | measure-only leftover 770; `sdk-settings-default-thinking-level` vs getDefaultThinkingLevel | invent pause；地板优化另刀 |
| `settings_load.sdk_effective_object` | 15.8 | 0.2 | 86.67× | 100.00× | measure-only leftover 772; `sdk-settings-effective-object` vs merge replica; first-freeze headroom 100.0 | invent pause；地板优化另刀 |
| `settings_load.sdk_settings_set` | 17.9 | 8.1 | 2.21× | 8.00× | measure-only leftover 773; `sdk-settings-set` vs setDefaultProvider/setDefaultModel/setTheme | invent pause；地板优化另刀 |
| `settings_load.sdk_settings_remove` | 32.7 | 0.9 | 35.83× | 40.00× | measure-only leftover 774; `sdk-settings-remove` vs delete-key replica; first-freeze headroom 40.0 | invent pause；地板优化另刀 |
| `settings_load.sdk_settings_reload` | 24.3 | 5.9 | 4.14× | 8.00× | measure-only leftover 775; `sdk-settings-reload` vs SettingsManager.reload | invent pause；地板优化另刀 |
| `settings_load.sdk_settings_flush` | 26.4 | 4.5 | 5.94× | 8.00× | measure-only leftover 776; `sdk-settings-flush` vs SettingsManager.flush | invent pause；地板优化另刀 |
| `settings_load.sdk_compaction_enabled` | 17.2 | 4.7 | 3.64× | 8.00× | measure-only leftover 777; `sdk-settings-compaction-enabled-p` vs getCompactionEnabled | invent pause；地板优化另刀 |
| `evals_harness.matching_hello_call` | 5.6 | 2.1 | 2.60× | 8.00× | measure-only leftover 778; `matching-hello-tool-call-p` vs ExtensionAuthoringJudge hello-call | invent pause；地板优化另刀 |
| `evals_harness.authoring_judge` | 16.7 | 7.2 | 2.33× | 8.00× | measure-only leftover 779; `judge-extension-authoring-result` vs ExtensionAuthoringJudge | invent pause；地板优化另刀 |
| `package_manager.resource_item_key` | 15.782 | 0.672 | 23.49× | 50.00× | measure-only leftover 781; `config-resource-item-key` vs leftover getResourceItemKey; first-freeze headroom 50.0 | invent pause；地板优化另刀 |
| `package_manager.project_override_state` | 44.722 | 2.605 | 17.17× | 20.00× | measure-only leftover 782; `config-selector-project-state` vs leftover override hash; first-freeze headroom 20.0 | invent pause；地板优化另刀 |
| `package_manager.next_project_state` | 40.473 | 4.330 | 9.35× | 15.00× | measure-only leftover 783; `config-selector-next-project-state` vs leftover nextProjectOverrideState; first-freeze headroom 15.0 | invent pause；地板优化另刀 |
| `package_manager.inherited_enabled` | 28.743 | 3.682 | 7.81× | 20.00× | measure-only leftover 784; `config-selector-inherited-enabled-p` vs leftover inheritedEnabled map; first-freeze headroom 20.0 | invent pause；地板优化另刀 |
| `package_manager.resource_group_key` | 12.761 | 0.775 | 16.47× | 50.00× | measure-only leftover 785; `config-resource-group-key` vs leftover group key; first-freeze headroom 50.0 | invent pause；地板优化另刀 |
| `package_manager.package_entry_index` | 14.402 | 1.934 | 7.45× | 20.00× | measure-only leftover 786; `config-selector-package-entry-index` vs leftover npm identity index; first-freeze headroom 20.0 | invent pause；地板优化另刀 |
| `package_manager.project_package_entry` | 18.051 | 2.691 | 6.71× | 15.00× | measure-only leftover 787; `config-selector-project-package-entry` vs leftover project identity find; first-freeze headroom 15.0 | invent pause；地板优化另刀 |
| `package_manager.project_package_state` | 25.317 | 3.203 | 7.90× | 15.00× | measure-only leftover 788; `config-selector-project-package-state` vs leftover filter walk; first-freeze headroom 15.0 | invent pause；地板优化另刀 |
| `package_manager.package_setting_record` | 10.399 | 0.873 | 11.91× | 40.00× | measure-only leftover 789; `config-package-setting-record` vs leftover npm record; first-freeze headroom 40.0 | invent pause；地板优化另刀 |
| `package_manager.package_setting_records` | 22.779 | 4.036 | 5.64× | 15.00× | measure-only leftover 790; `config-package-setting-records` vs leftover npm merge; first-freeze headroom 15.0 | invent pause；地板优化另刀 |
| `package_manager.selector_rebuild` | 26.127 | 4.435 | 5.89× | 15.00× | measure-only leftover 791; `config-selector-rebuild` vs leftover flat rebuild; first-freeze headroom 15.0 | invent pause；地板优化另刀 |
| `package_manager.switch_scope` | 36.289 | 6.020 | 6.03× | 12.00× | measure-only leftover 792; `config-selector-switch-scope` vs leftover scope flip; first-freeze headroom 12.0 | invent pause；地板优化另刀 |
| `evals_harness.visible_extension_bundles` | 12.635 | 0.585 | 21.59× | 25.00× | measure-only leftover 794; `visible-extension-bundles` vs leftover hidden-p filter; first-freeze headroom 25.0 | invent pause；地板优化另刀 |
| `evals_harness.authoring_harness_table` | 0.880 | 0.205 | 4.301× | 8.00× | measure-only leftover 795; `extension-authoring-harness-table` vs leftover two-row table | invent pause；地板优化另刀 |
| `package_manager.git_output` | 3.208 | 0.221 | 14.54× | 120.00× | measure-only leftover 796; `package-update-git-output` vs leftover git argv runner; first-freeze headroom 120.0 | invent pause；地板优化另刀 |
| `package_manager.remote_ref` | 4.714 | 1.155 | 4.082× | 25.00× | measure-only leftover 797; `package-update-remote-ref` vs leftover origin/ upstream ref; first-freeze headroom 25.0 | invent pause；地板优化另刀 |
| `package_manager.update_record_result` | 11.610 | 6.399 | 1.814× | 8.00× | measure-only leftover 798; `package-update-record-result` vs leftover host/path result | invent pause；地板优化另刀 |
| `package_manager.selector_hint` | 10.635 | 0.687 | 15.49× | 20.00× | measure-only leftover 799; `config-selector-hint` vs leftover keyHint wrap; first-freeze headroom 20.0 | invent pause；地板优化另刀 |
| `package_manager.override_suffix` | 35.220 | 3.881 | 9.075× | 25.00× | measure-only leftover 800; `config-selector-override-suffix` vs leftover getItemSuffix; first-freeze headroom 25.0 | invent pause；地板优化另刀 |
| `package_manager.checkbox` | 36.479 | 3.484 | 10.47× | 25.00× | measure-only leftover 801; `config-selector-checkbox` vs leftover renderCheckbox; first-freeze headroom 25.0 | invent pause；地板优化另刀 |
| `cli_extensions_install.string_prefix` | 0.236 | 0.213 | 1.109× | 8.00× | measure-only leftover 802; `string-prefix-p` vs leftover startsWith; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_extensions_install.split_path_segments` | 0.885 | 0.323 | 2.742× | 8.00× | measure-only leftover 803; `split-path-segments` vs leftover split("/"); first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_extensions_install.strip_git_query` | 0.697 | 0.248 | 2.811× | 8.00× | measure-only leftover 804; `strip-git-query-and-ref` vs leftover strip query/hash; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `provider_registry_defs.models_runtime` | 309.041 | 203.473 | 1.519× | 8.00× | measure-only leftover 753; `make-built-in-models-runtime` vs builtinProviders Map | invent pause；地板优化另刀 |
| `package_manager.candidate_record` | 30.746 | 1.795 | 17.132× | 20.00× | measure-only leftover 758; `package-update-candidate-record-p` vs git/unpinned/exists | invent pause；地板优化另刀 |
| `package_manager.update_offline` | 0.333 | 0.253 | 1.316× | 8.00× | measure-only leftover 759; `check-for-available-package-updates` offline vs isOfflineModeEnabled | invent pause；地板优化另刀 |
| `settings_load.read_cli_config` | 200.606 | 95.628 | 2.098× | 8.00× | measure-only leftover 760; `read-cli-config` vs JSON.parse settings object | invent pause；地板优化另刀 |
| `settings_load.provider_config_secrets` | 59.914 | 1.371 | 43.688× | 50.00× | measure-only leftover 761; `provider-config-secrets` vs apiKey/oauth/env collect; first-freeze headroom 50.0 | invent pause；地板优化另刀 |
| `settings_load.resolve_provider_config` | 225.982 | 42.635 | 5.300× | 8.00× | measure-only leftover 762; `resolve-provider-config` vs openaiProvider construct | invent pause；地板优化另刀 |
| `settings_load.sdk_default_provider` | 31.153 | 6.243 | 4.990× | 8.00× | measure-only leftover 763; `sdk-settings-default-provider` vs getDefaultProvider | invent pause；地板优化另刀 |
| `settings_load.sdk_default_model` | 31.246 | 5.925 | 5.274× | 8.00× | measure-only leftover 764; `sdk-settings-default-model` vs getDefaultModel | invent pause；地板优化另刀 |
| `settings_load.sdk_retry_settings` | 15.933 | 6.038 | 2.639× | 8.00× | measure-only leftover 765; `sdk-settings-retry-settings` vs getRetrySettings | invent pause；地板优化另刀 |
| `settings_load.sdk_http_idle_timeout` | 10.990 | 8.800 | 1.249× | 8.00× | measure-only leftover 766; `sdk-settings-http-idle-timeout-ms` vs getHttpIdleTimeoutMs | invent pause；地板优化另刀 |
| `settings_load.sdk_apply_overrides` | 45.476 | 6.534 | 6.960× | 8.00× | measure-only leftover 767; `sdk-settings-apply-overrides` vs applyOverrides | invent pause；地板优化另刀 |
| `settings_load.sdk_model_thinking_level` | 16.293 | 3.769 | 4.323× | 8.00× | measure-only leftover 768; `sdk-settings-model-thinking-level` vs getModelThinkingLevel | invent pause；地板优化另刀 |
| `settings_load.sdk_settings_value` | 30.545 | 0.352 | 86.814× | 100.00× | measure-only leftover 769; `sdk-settings-value` vs json-get replica; first-freeze headroom 100.0 | invent pause；地板优化另刀 |
| `settings_load.sdk_default_thinking_level` | 9.418 | 4.677 | 2.014× | 8.00× | measure-only leftover 770; `sdk-settings-default-thinking-level` vs getDefaultThinkingLevel | invent pause；地板优化另刀 |
| `settings_load.sdk_effective_object` | 13.971 | 0.225 | 62.130× | 80.00× | measure-only leftover 772; `sdk-settings-effective-object` vs merge replica; first-freeze headroom 80.0 | invent pause；地板优化另刀 |
| `settings_load.sdk_settings_set` | 16.186 | 8.855 | 1.828× | 8.00× | measure-only leftover 773; `sdk-settings-set` vs setDefaultProvider/setDefaultModel/setTheme | invent pause；地板优化另刀 |
| `settings_load.sdk_settings_remove` | 30.936 | 0.991 | 31.220× | 40.00× | measure-only leftover 774; `sdk-settings-remove` vs delete-key replica; first-freeze headroom 40.0 | invent pause；地板优化另刀 |
| `settings_load.sdk_settings_reload` | 22.742 | 6.416 | 3.545× | 8.00× | measure-only leftover 775; `sdk-settings-reload` vs SettingsManager.reload | invent pause；地板优化另刀 |
| `settings_load.sdk_settings_flush` | 22.538 | 5.139 | 4.385× | 8.00× | measure-only leftover 776; `sdk-settings-flush` vs SettingsManager.flush | invent pause；地板优化另刀 |
| `settings_load.sdk_compaction_enabled` | 15.262 | 5.436 | 2.808× | 8.00× | measure-only leftover 777; `sdk-settings-compaction-enabled-p` vs getCompactionEnabled | invent pause；地板优化另刀 |
| `evals_harness.matching_hello_call` | 3.448 | 1.294 | 2.665× | 8.00× | measure-only leftover 778; `matching-hello-tool-call-p` vs ExtensionAuthoringJudge hello-call | invent pause；地板优化另刀 |
| `evals_harness.authoring_judge` | 13.153 | 3.689 | 3.565× | 8.00× | measure-only leftover 779; `judge-extension-authoring-result` vs ExtensionAuthoringJudge | invent pause；地板优化另刀 |
| `package_manager.resource_item_key` | 34.919 | 0.914 | 38.223× | 50.00× | measure-only leftover 781; `config-resource-item-key` vs leftover getResourceItemKey; first-freeze headroom 50.0 | invent pause；地板优化另刀 |
| `package_manager.project_override_state` | 52.878 | 2.954 | 17.903× | 20.00× | measure-only leftover 782; `config-selector-project-state` vs leftover override hash; first-freeze headroom 20.0 | invent pause；地板优化另刀 |
| `package_manager.next_project_state` | 52.464 | 4.986 | 10.522× | 15.00× | measure-only leftover 783; `config-selector-next-project-state` vs leftover nextProjectOverrideState; first-freeze headroom 15.0 | invent pause；地板优化另刀 |
| `package_manager.inherited_enabled` | 44.007 | 2.829 | 15.558× | 20.00× | measure-only leftover 784; `config-selector-inherited-enabled-p` vs leftover inheritedEnabled map; first-freeze headroom 20.0 | invent pause；地板优化另刀 |
| `package_manager.resource_group_key` | 33.767 | 0.902 | 37.443× | 50.00× | measure-only leftover 785; `config-resource-group-key` vs leftover group key; first-freeze headroom 50.0 | invent pause；地板优化另刀 |
| `package_manager.package_entry_index` | 37.334 | 2.313 | 16.140× | 20.00× | measure-only leftover 786; `config-selector-package-entry-index` vs leftover npm identity index; first-freeze headroom 20.0 | invent pause；地板优化另刀 |
| `package_manager.project_package_entry` | 41.428 | 3.242 | 12.778× | 15.00× | measure-only leftover 787; `config-selector-project-package-entry` vs leftover project identity find; first-freeze headroom 15.0 | invent pause；地板优化另刀 |
| `package_manager.project_package_state` | 46.466 | 3.385 | 13.727× | 15.00× | measure-only leftover 788; `config-selector-project-package-state` vs leftover filter walk; first-freeze headroom 15.0 | invent pause；地板优化另刀 |
| `package_manager.package_setting_record` | 32.598 | 1.048 | 31.093× | 40.00× | measure-only leftover 789; `config-package-setting-record` vs leftover npm record; first-freeze headroom 40.0 | invent pause；地板优化另刀 |
| `package_manager.package_setting_records` | 39.372 | 3.556 | 11.073× | 15.00× | measure-only leftover 790; `config-package-setting-records` vs leftover npm merge; first-freeze headroom 15.0 | invent pause；地板优化另刀 |
| `package_manager.selector_rebuild` | 44.571 | 4.452 | 10.012× | 15.00× | measure-only leftover 791; `config-selector-rebuild` vs leftover flat rebuild; first-freeze headroom 15.0 | invent pause；地板优化另刀 |
| `package_manager.switch_scope` | 52.658 | 5.942 | 8.862× | 12.00× | measure-only leftover 792; `config-selector-switch-scope` vs leftover scope flip; first-freeze headroom 12.0 | invent pause；地板优化另刀 |
| `evals_harness.visible_extension_bundles` | 6.515 | 0.734 | 8.873× | 12.00× | measure-only leftover 794; `visible-extension-bundles` vs leftover hidden-p filter; first-freeze headroom 12.0 | invent pause；地板优化另刀 |
| `evals_harness.authoring_harness_table` | 0.568 | 0.218 | 2.598× | 8.00× | measure-only leftover 795; `extension-authoring-harness-table` vs leftover two-row table | invent pause；地板优化另刀 |
| `package_manager.git_output` | 24.678 | 0.260 | 95.093× | 120.00× | measure-only leftover 796; `package-update-git-output` vs leftover git argv runner; first-freeze headroom 120.0 | invent pause；地板优化另刀 |
| `package_manager.remote_ref` | 26.081 | 1.304 | 20.001× | 25.00× | measure-only leftover 797; `package-update-remote-ref` vs leftover origin/ upstream ref; first-freeze headroom 25.0 | invent pause；地板优化另刀 |
| `package_manager.update_record_result` | 32.630 | 7.033 | 4.640× | 8.00× | measure-only leftover 798; `package-update-record-result` vs leftover host/path result | invent pause；地板优化另刀 |
| `package_manager.selector_hint` | 11.293 | 0.675 | 16.742× | 20.00× | measure-only leftover 799; `config-selector-hint` vs leftover keyHint wrap; first-freeze headroom 20.0 | invent pause；地板优化另刀 |
| `package_manager.override_suffix` | 49.261 | 2.679 | 18.389× | 25.00× | measure-only leftover 800; `config-selector-override-suffix` vs leftover getItemSuffix; first-freeze headroom 25.0 | invent pause；地板优化另刀 |
| `package_manager.checkbox` | 51.092 | 2.611 | 19.566× | 25.00× | measure-only leftover 801; `config-selector-checkbox` vs leftover renderCheckbox; first-freeze headroom 25.0 | invent pause；地板优化另刀 |
| `cli_extensions_install.split_path_segments` | 0.635 | 0.295 | 2.152× | 8.00× | measure-only leftover 803; `split-path-segments` vs leftover split("/"); first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_extensions_install.llama_format_context` | 0.868 | 0.200 | 4.332× | 8.00× | measure-only leftover 805; `llama-format-context-size` vs leftover Math.round k; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_extensions_install.llama_js_to_fixed` | 1.301 | 0.423 | 3.076× | 8.00× | measure-only leftover 806; `llama-js-to-fixed` vs leftover Number.toFixed; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_extensions_install.llama_search_exact` | 0.945 | 0.231 | 4.086× | 8.00× | measure-only leftover 807; `llama-search-exact-query-p` vs leftover org/name regex; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_extensions_install.llama_search_status` | 0.880 | 0.181 | 4.854× | 8.00× | measure-only leftover 826; `llama-search-status-text` vs leftover HuggingFaceSearch status; remeasure Friend-MachineD | invent pause；地板优化另刀 |
| `cli_extensions_install.llama_view_width` | 27.891 | 0.244 | 114.091× | 180.00× | measure-only leftover 828; `llama-view-width` vs leftover lastWidth (CLOS view vs property); remeasure Friend-MachineD | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.assistant_tool_call_only` | 1.423 | 0.671 | 2.121× | 8.00× | measure-only leftover 808; `assistant-tool-call-only-p` vs leftover hasTextContent invert; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.session_entry_user_text` | 1.431 | 0.651 | 2.198× | 8.00× | measure-only leftover 809; `session-entry-user-text` vs leftover contentText user entry; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.session_compaction_status` | 2.150 | 0.609 | 3.530× | 8.00× | measure-only leftover 810; `session-compaction-status` vs leftover compaction count string; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.last_assistant_text` | 4.006 | 1.182 | 3.389× | 8.00× | measure-only leftover 811; `last-assistant-text` vs leftover getLastAssistantText; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.session_export_basename` | 12.308 | 2.292 | 5.369× | 8.00× | measure-only leftover 812; `session-export-basename` vs leftover APP_NAME-session ISO_id.html; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.session_user_messages_for_forking` | 2.542 | 0.944 | 2.692× | 8.00× | measure-only leftover 813; `session-user-messages-for-forking` vs leftover getUserMessagesForForking; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.session_command_stats` | 2.578 | 1.092 | 2.362× | 8.00× | measure-only leftover 814; `session-command-stats` vs leftover getSessionStats; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.session_usage_breakdown` | 7.127 | 1.932 | 3.689× | 8.00× | measure-only leftover 815; `session-usage-breakdown` vs leftover getUsageCostBreakdown; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.session_tree_label_timestamps` | 4.218 | 1.468 | 2.873× | 8.00× | measure-only leftover 816; `session-tree-label-timestamps` vs leftover label timestamps; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.session_tree_tool_calls` | 2.883 | 1.047 | 2.754× | 8.00× | measure-only leftover 817; `session-tree-tool-calls` vs leftover tool-call id→name map; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.session_compaction_display_state` | 3.306 | 1.006 | 3.286× | 8.00× | measure-only leftover 818; `session-compaction-display-state` vs leftover display messages + nil summary; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.write_hotkeys_command` | 8.281 | 2.421 | 3.421× | 8.00× | measure-only leftover 819; `write-hotkeys-command` vs leftover Keyboard Shortcuts list; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.find_session_by_id_or_prefix` | 1.627 | 0.862 | 1.888× | 8.00× | measure-only leftover 820; `find-session-by-id-or-prefix` vs leftover find by id or prefix; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.session_display_messages` | 3.262 | 0.940 | 3.471× | 8.00× | measure-only leftover 821; `session-display-messages` vs leftover display message projection; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.session_tree_selector_data` | 4.557 | 1.275 | 3.574× | 8.00× | measure-only leftover 822; `session-tree-selector-data` vs leftover tree row map; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.validate_cli_session_flags` | 2.825 | 0.526 | 5.366× | 8.00× | measure-only leftover 823; `validate-cli-session-flags` vs leftover fork/session-id flag conflicts; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.session_entry_tree_selector_data` | 4.460 | 0.970 | 4.596× | 8.00× | measure-only leftover 824; `session-entry-tree-selector-data` vs leftover one tree row; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.session_restored_model` | 4.808 | 3.084 | 1.559× | 8.00× | measure-only leftover 825; `session-restored-model` vs leftover restored model lookup; first-freeze headroom 8.0 | invent pause；地板优化另刀 |
| `cli_print_rpc.close_pending` | 2.293 | 0.714 | 3.213× | 8.00× | measure-only leftover 831; `rpc-close-pending-dialogs` vs leftover pending map clear; remeasure Friend-MachineD | invent pause；地板优化另刀 |
| `oauth_pkce_device.write_http_response` | 6.758 | 0.620 | 10.896× | 12.00× | measure-only leftover 833; remeasure Friend-MachineD | invent pause；地板优化另刀 |
| `oauth_pkce_device.present_auth_url` | 2.080 | 0.354 | 5.875× | 8.00× | measure-only leftover 834; remeasure Friend-MachineD | invent pause；地板优化另刀 |
| `cli_selectors.armin_make_grid` | 27.119 | 16.108 | 1.684× | 8.00× | measure-only leftover 835; remeasure Friend-MachineD | invent pause；地板优化另刀 |
| `cli_selectors.armin_copy_grid` | 24.841 | 3.842 | 6.466× | 8.00× | measure-only leftover 836; remeasure Friend-MachineD | invent pause；地板优化另刀 |
| `cli_selectors.armin_row_string` | 23.584 | 5.494 | 4.293× | 8.00× | measure-only leftover 837; remeasure Friend-MachineD | invent pause；地板优化另刀 |
| `cli_extensions_install.http_timeout_p` | 1.356 | 0.303 | 4.480× | 8.00× | measure-only leftover 844; remeasure Friend-MachineD | invent pause；地板优化另刀 |
| `cli_extensions_install.same_source` | 0.759 | 0.158 | 4.802× | 8.00× | measure-only leftover 845; remeasure Friend-MachineD | invent pause；地板优化另刀 |
| `cli_extensions_install.quiet_manager` | 1.176 | 0.171 | 6.863× | 8.00× | measure-only leftover 846; remeasure Friend-MachineD | invent pause；地板优化另刀 |
| `cli_extensions_install.manager_notify` | 3.618 | 1.235 | 2.930× | 8.00× | measure-only leftover 847; remeasure Friend-MachineD | invent pause；地板优化另刀 |
| `cli_extensions_install.startup_issues` | 3.989 | 0.828 | 4.819× | 8.00× | measure-only leftover 848; remeasure Friend-MachineD | invent pause；地板优化另刀 |
| `cli_extensions_install.output_boundary` | 1.196 | 0.230 | 5.208× | 8.00× | measure-only leftover 849; remeasure Friend-MachineD | invent pause；地板优化另刀 |
| `cli_extensions_install.llama_format_context` | 0.586 | 0.299 | 1.959× | 8.00× | measure-only leftover 805; `llama-format-context-size` vs leftover Math.round k | invent pause；地板优化另刀 |
| `cli_extensions_install.llama_js_to_fixed` | 0.807 | 0.511 | 1.577× | 8.00× | measure-only leftover 806; `llama-js-to-fixed` vs leftover Number.toFixed | invent pause；地板优化另刀 |
| `cli_extensions_install.llama_search_exact` | 0.678 | 0.284 | 2.389× | 8.00× | measure-only leftover 807; `llama-search-exact-query-p` vs leftover org/name regex | invent pause；地板优化另刀 |
| `cli_extensions_install.llama_search_status` | 0.456 | 0.157 | 2.908× | 8.00× | measure-only leftover 826; `llama-search-status-text` vs leftover HuggingFaceSearch status | invent pause；地板优化另刀 |
| `cli_extensions_install.llama_view_width` | 27.079 | 0.181 | 149.278× | 180.00× | measure-only leftover 828; `llama-view-width` vs leftover lastWidth (CLOS view vs property) | invent pause；地板优化另刀 |
| `cli_extensions_install.http_timeout_p` | 0.832 | 0.298 | 2.787× | 8.00× | measure-only leftover 844; `extension-http-timeout-condition-p` vs leftover timeout names | invent pause；地板优化另刀 |
| `cli_extensions_install.same_source` | 0.421 | 0.160 | 2.631× | 8.00× | measure-only leftover 845; `same-extension-source-p` vs leftover path equality | invent pause；地板优化另刀 |
| `cli_extensions_install.quiet_manager` | 0.680 | 0.248 | 2.740× | 8.00× | measure-only leftover 846; `call-with-quiet-extension-manager` vs leftover silenced notify | invent pause；地板优化另刀 |
| `cli_extensions_install.manager_notify` | 3.324 | 1.328 | 2.503× | 8.00× | measure-only leftover 847; `extension-manager-notify` vs leftover notify format | invent pause；地板优化另刀 |
| `cli_extensions_install.startup_issues` | 2.919 | 1.137 | 2.567× | 8.00× | measure-only leftover 848; `report-startup-extension-issues` vs leftover reportDiagnostics | invent pause；地板优化另刀 |
| `cli_extensions_install.output_boundary` | 0.740 | 0.268 | 2.759× | 8.00× | measure-only leftover 849; `call-with-extension-output-boundary` vs leftover stdout/stderr bind | invent pause；地板优化另刀 |
| `cli_extensions_install.loaded_model` | 0.427 | 0.130 | 3.296× | 8.00× | measure-only leftover 850; remeasure Friend-MachineD | invent pause；地板优化另刀 |
| `cli_extensions_install.catalog_notify` | 9.316 | 0.654 | 14.250× | 60.00× | measure-only leftover 851; remeasure Friend-MachineD | invent pause；地板优化另刀 |
| `cli_extensions_install.progress_notify` | 11.417 | 0.577 | 19.792× | 60.00× | measure-only leftover 852; remeasure Friend-MachineD | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.session_info_style` | 2.643 | 0.367 | 7.201× | 8.00× | measure-only leftover 854; `session-info-style` vs leftover heading/label/other style; remeasure Friend-MachineD | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.default_changelog_path` | 218.058 | 0.184 | 1182.272× | 1200.00× | measure-only leftover 855; `default-changelog-path` vs leftover CHANGELOG env/leaf; remeasure Friend-MachineD | invent pause；地板优化另刀 |
| `cli_selectors.armin_copy_cell` | 25.759 | 4.869 | 5.290× | 8.00× | measure-only leftover 862-864; remeasure Friend-MachineD | typewriter/scanline/rotate grid helpers |
| `cli_selectors.armin_copy_row` | 23.953 | 5.08 | 4.716× | 8.00× | measure-only leftover 862-864; remeasure Friend-MachineD | typewriter/scanline/rotate grid helpers |
| `cli_selectors.armin_rotate_row` | 21.362 | 6.23 | 3.429× | 8.00× | measure-only leftover 862-864; remeasure Friend-MachineD | typewriter/scanline/rotate grid helpers |
| `cli_interactive_controller.extension_host_turn` | 0.323 | 0.216 | 1.495× | 8.00× | measure-only leftover 865-867; remeasure Friend-MachineD | extension-ui tui-thread/wrap |
| `cli_interactive_controller.wrap_extension_host_turn` | 1.297 | 0.561 | 2.313× | 8.00× | measure-only leftover 865-867; remeasure Friend-MachineD | extension-ui tui-thread/wrap |
| `oauth_pkce_device.openai_exchange` | 29.574 | 5.257 | 5.625× | 8.00× | measure-only leftover 889-891; remeasure Friend-MachineD | openai-anthropic token/exchange trio |
| `oauth_pkce_device.anthropic_exchange` | 12.807 | 7.545 | 1.697× | 8.00× | measure-only leftover 889-891; remeasure Friend-MachineD | openai-anthropic token/exchange trio |
| `oauth_pkce_device.device_poll_complete` | 2.586 | 0.164 | 15.756× | 15.00× | measure-only leftover 892-894; remeasure Friend-MachineD | openai-device poll trio |
| `oauth_pkce_device.device_poll_fail` | 2.962 | 1.737 | 1.705× | 8.00× | measure-only leftover 892-894; remeasure Friend-MachineD | openai-device poll trio |
| `oauth_pkce_device.device_poll_slow` | 3.588 | 1.967 | 1.824× | 8.00× | measure-only leftover 892-894; remeasure Friend-MachineD | openai-device poll trio |
| `oauth_pkce_device.xai_login` | 15.536 | 1.185 | 13.116× | 20.00× | measure-only leftover 895-897; remeasure Friend-MachineD | xai login/refresh trio |
| `oauth_pkce_device.xai_login_fail` | 8.266 | 2.136 | 3.870× | 8.00× | measure-only leftover 895-897; remeasure Friend-MachineD | xai login/refresh trio |
| `oauth_pkce_device.xai_refresh` | 5.365 | 0.237 | 22.614× | 20.00× | measure-only leftover 895-897; remeasure Friend-MachineD | xai login/refresh trio |
| `oauth_pkce_device.openrouter_login` | 168.272 | 4.804 | 35.027× | 50.00× | measure-only leftover 898-900; remeasure Friend-MachineD | openrouter login trio |
| `oauth_pkce_device.openrouter_login_fail` | 202.181 | 3.766 | 53.681× | 80.00× | measure-only leftover 898-900; remeasure Friend-MachineD | openrouter login trio |
| `oauth_pkce_device.github_oauth_url` | 1.387 | 0.417 | 3.329× | 8.00× | measure-only leftover 914; `github-oauth-url` vs leftoverGithubOAuthUrl / getUrls | invent pause；地板优化另刀 |
| `cli_support.watch_start_close` | 178.516 | 7.568 | 23.588× | 40.00× | measure-only leftover 917; `watch-with-error-handler` + `close-watcher` vs watchWithErrorHandler + closeWatcher | invent pause；地板优化另刀 |
| `bash_tool.output_path` | 117.640 | 11.032 | 10.664× | 24.00× | measure-only leftover 922; `bash-output-path` vs ensureTempFile temp log path | invent pause；地板优化另刀 |
| `bash_tool.make_tool` | 3.108 | 1.519 | 2.046× | 8.00× | measure-only leftover 923; `make-bash-tool` vs createBashTool | invent pause；地板优化另刀 |
| `bash_tool.record_nil` | 0.384 | 0.112 | 3.436× | 8.00× | measure-only leftover 924; `record-user-bash-result` nil agent vs leftover no-op | invent pause；地板优化另刀 |
| `oauth_pkce_device.openrouter_login_miss` | 183.818 | 1.862 | 98.722× | 100.00× | measure-only leftover 898-900; remeasure Friend-MachineD | openrouter login trio |
| `cli_print_rpc.line_bad` | 7.254 | 6.107 | 1.188× | 8.00× | measure-only leftover 970; `rpc-handle-line` vs leftover JSON.parse catch | invent pause；地板优化另刀 |
| `cli_print_rpc.line_arr` | 6.497 | 4.830 | 1.345× | 8.00× | measure-only leftover 971; `rpc-handle-line` vs leftover require JSON object | invent pause；地板优化另刀 |
| `cli_print_rpc.line_ui` | 7.486 | 1.780 | 4.206× | 8.00× | measure-only leftover 972; `rpc-handle-line` vs leftover unknown extension_ui_response | invent pause；地板优化另刀 |
| `cli_print_rpc.asst_hit` | 0.520 | 0.275 | 1.889× | 8.00× | measure-only leftover 974; `rpc-last-assistant-text` vs leftover last assistant | invent pause；地板优化另刀 |
| `cli_print_rpc.cmd_n` | 2.232 | 0.254 | 8.772× | 12.00× | measure-only leftover 975; `rpc-command-list` vs leftover command list; first-freeze ceiling 12.0 | invent pause；地板优化另刀 |
| `cli_print_rpc.prompt_ok` | 1.991 | 0.498 | 3.997× | 8.00× | measure-only leftover 977; `rpc-prompt-message` vs leftover prompt message+images | invent pause；地板优化另刀 |
| `cli_print_rpc.bash_js` | 3.070 | 0.677 | 4.536× | 8.00× | measure-only leftover 978; `rpc-bash-result-json` vs leftover bash result payload | invent pause；地板优化另刀 |
| `evals_harness.val_ext` | 3.633 | 0.199 | 18.295× | 20.00× | measure-only leftover 979; `validate-extension-result` leftover; first-freeze ceiling 20.0 | invent pause；地板优化另刀 |
| `evals_harness.suite_id` | 0.244 | 0.105 | 2.323× | 8.00× | measure-only leftover 980; suite cond leftover replica | invent pause；地板优化另刀 |
| `evals_harness.type_ok` | 1.005 | 0.248 | 4.059× | 8.00× | measure-only leftover 981; eval-result typep leftover | invent pause；地板优化另刀 |
| `evals_harness.msg_txt` | 1.599 | 0.607 | 2.635× | 8.00× | measure-only leftover 982; `message-content-text` leftover | invent pause；地板优化另刀 |
| `evals_harness.tools_n` | 2.373 | 0.235 | 10.111× | 12.00× | measure-only leftover 983; `eval-agent-tools` leftover; first-freeze ceiling 12.0 | invent pause；地板优化另刀 |
| `evals_harness.paths_n` | 4.853 | 0.350 | 13.850× | 16.00× | measure-only leftover 984; `eval-extension-paths` leftover; first-freeze ceiling 16.0 | invent pause；地板优化另刀 |
| `evals_harness.rep_ok` | 0.570 | 0.316 | 1.805× | 8.00× | measure-only leftover 985; make-eval-harness-reporter leftover | invent pause；地板优化另刀 |
| `evals_harness.fin_ok` | 0.267 | 0.142 | 1.873× | 8.00× | measure-only leftover 986; reporter-finite-number leftover | invent pause；地板优化另刀 |
| `evals_harness.meta_ok` | 1.651 | 0.809 | 2.042× | 8.00× | measure-only leftover 987; reporter-artifact-metadata leftover | invent pause；地板优化另刀 |
| `cli_interactive_controller.bash_go` | 1.218 | 0.293 | 4.156× | 8.00× | measure-only leftover 988; append-tui-user-bash-running leftover | invent pause；地板优化另刀 |
| `cli_interactive_controller.bash_end` | 1.460 | 0.223 | 6.552× | 8.00× | measure-only leftover 989; complete-tui-user-bash-string leftover | invent pause；地板优化另刀 |
| `cli_interactive_controller.bash_off` | 1.346 | 0.168 | 8.012× | 12.00× | measure-only leftover 990; stop-tui-user-bash-entry leftover; first-freeze ceiling 12.0 | invent pause；地板优化另刀 |
| `cli_selectors.dlg_new` | 0.514 | 0.102 | 5.046× | 8.00× | measure-only leftover 991; make-login-dialog-state leftover | invent pause；地板优化另刀 |
| `cli_selectors.dlg_key` | 2.945 | 0.526 | 5.599× | 8.00× | measure-only leftover 992; login-dialog-show-auth leftover | invent pause；地板优化另刀 |
| `cli_selectors.dlg_code` | 5.677 | 0.949 | 5.985× | 8.00× | measure-only leftover 993; login-dialog-show-device-code leftover | invent pause；地板优化另刀 |
| `cli_selectors.th_sel` | 0.809 | 0.454 | 1.783× | 8.00× | measure-only leftover 994; thinking-selector-selected-level leftover | invent pause；地板优化另刀 |
| `cli_selectors.th_desc` | 0.729 | 0.133 | 5.486× | 8.00× | measure-only leftover 995; thinking-level-description-line leftover | invent pause；地板优化另刀 |
| `cli_selectors.th_draw` | 278.008 | 4.681 | 59.389× | 60.00× | measure-only leftover 996; render-thinking-selector leftover; first-freeze ceiling 60.0 | invent pause；地板优化另刀 |
| `cli_selectors.sl_ok` | 0.982 | 0.223 | 4.398× | 8.00× | measure-only leftover 1132; sl_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.dsc_ok` | 0.505 | 0.135 | 3.757× | 8.00× | measure-only leftover 1133; dsc_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.rth_ok` | 294.766 | 7.086 | 41.601× | 8.00× | measure-only leftover 1134; rth_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.slx_ok` | 0.851 | 0.203 | 4.190× | 8.00× | measure-only leftover 1213; slx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.dscx_ok` | 0.499 | 0.119 | 4.188× | 8.00× | measure-only leftover 1214; dscx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.rthx_ok` | 258.321 | 4.314 | 59.875× | 8.00× | measure-only leftover 1215; rthx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.slxx_ok` | 0.785 | 0.351 | 2.236× | 8.00× | measure-only leftover 1279; slxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.dscxx_ok` | 0.519 | 0.139 | 3.744× | 8.00× | measure-only leftover 1280; dscxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.rthxx_ok` | 280.415 | 3.068 | 91.402× | 8.00× | measure-only leftover 1281; rthxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.um_evt` | 2.504 | 1.649 | 1.518× | 8.00× | measure-only leftover 997; user-message-selector-handle-event leftover | invent pause；地板优化另刀 |
| `cli_selectors.um_raw` | 100.493 | 7.058 | 14.238× | 30.00× | measure-only leftover 998; user-message-selector-handle-raw-input leftover | invent pause；地板优化另刀 |
| `cli_selectors.um_draw` | 312.691 | 2.973 | 105.189× | 120.00× | measure-only leftover 999; render-user-message-selector leftover; first-freeze ceiling 120.0 | invent pause；地板优化另刀 |
| `cli_selectors.tosp_ok` | 51.075 | 26.680 | 1.914× | 8.00× | measure-only leftover 1000; trust-option-saved-p leftover | invent pause；地板优化另刀 |
| `cli_selectors.mtss_ok` | 164.943 | 85.159 | 1.937× | 8.00× | measure-only leftover 1001; make-trust-selector-state leftover | invent pause；地板优化另刀 |
| `cli_selectors.rtrs_ok` | 1370.312 | 194.933 | 7.030× | 15.00× | measure-only leftover 1002; render-trust-selector leftover | invent pause；地板优化另刀 |
| `cli_selectors.sv_ok` | 56.278 | 36.077 | 1.560× | 8.00× | measure-only leftover 1123; sv_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.mk_ok` | 145.127 | 108.325 | 1.340× | 8.00× | measure-only leftover 1124; mk_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.trn_ok` | 1162.348 | 215.910 | 5.383× | 8.00× | measure-only leftover 1125; trn_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.trsv_ok` | 52.581 | 24.296 | 2.164× | 8.00× | measure-only leftover 1204; trsv_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.trmk_ok` | 136.316 | 82.531 | 1.652× | 8.00× | measure-only leftover 1205; trmk_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.trrs_ok` | 1114.238 | 177.291 | 6.285× | 8.00× | measure-only leftover 1206; trrs_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.trsvx_ok` | 54.839 | 28.920 | 1.896× | 8.00× | measure-only leftover 1270; trsvx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.trmkx_ok` | 154.616 | 87.346 | 1.770× | 8.00× | measure-only leftover 1271; trmkx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.trrsx_ok` | 1224.489 | 196.750 | 6.224× | 8.00× | measure-only leftover 1272; trrsx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.mlms_ok` | 3.649 | 1.921 | 1.900× | 8.00× | measure-only leftover 1003; make-login-method-selector-state leftover | invent pause；地板优化另刀 |
| `cli_selectors.makis_ok` | 3.372 | 0.881 | 3.828× | 8.00× | measure-only leftover 1004; make-api-key-input-state leftover | invent pause；地板优化另刀 |
| `cli_selectors.moss_ok` | 9.651 | 5.922 | 1.630× | 8.00× | measure-only leftover 1005; make-oauth-selector-state leftover | invent pause；地板优化另刀 |
| `cli_selectors.lms_ok` | 3.885 | 2.662 | 1.460× | 8.00× | measure-only leftover 1126; lms_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.aki_ok` | 2.957 | 0.473 | 6.256× | 8.00× | measure-only leftover 1127; aki_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.akhe_ok` | 7.823 | 4.838 | 1.617× | 8.00× | measure-only leftover 1147; akhe_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lmsu_ok` | 457.136 | 95.817 | 4.771× | 8.00× | measure-only leftover 1165; lmsu_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.aui_ok` | 196.168 | 93.225 | 2.104× | 8.00× | measure-only leftover 1166; aui_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lmhx_ok` | 3.231 | 0.585 | 5.528× | 8.00× | measure-only leftover 1225; lmhx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.luix_ok` | 388.529 | 83.137 | 4.673× | 8.00× | measure-only leftover 1226; luix_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.akux_ok` | 191.040 | 80.139 | 2.384× | 8.00× | measure-only leftover 1227; akux_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lmhxx_ok` | 3.617 | 0.646 | 5.597× | 8.00× | measure-only leftover 1291; lmhxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.luixx_ok` | 435.820 | 102.824 | 4.239× | 8.00× | measure-only leftover 1292; luixx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.akuxx_ok` | 203.048 | 99.350 | 2.044× | 8.00× | measure-only leftover 1293; akuxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ahe_ok` | 6.326 | 4.929 | 1.283× | 8.00× | measure-only leftover 1167; ahe_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.mls_ok` | 3.899 | 3.639 | 1.071× | 8.00× | measure-only leftover 1148; mls_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ais_ok` | 3.860 | 0.720 | 5.362× | 8.00× | measure-only leftover 1149; ais_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oss_ok` | 8.838 | 5.596 | 1.579× | 8.00× | measure-only leftover 1128; oss_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ohe_ok` | 182.806 | 15.748 | 11.608× | 8.00× | measure-only leftover 1153; ohe_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.mos_ok` | 13.535 | 11.644 | 1.162× | 8.00× | measure-only leftover 1154; mos_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lmsx_ok` | 4.009 | 1.308 | 3.066× | 8.00× | measure-only leftover 1207; lmsx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.akix_ok` | 3.520 | 0.328 | 10.725× | 8.00× | measure-only leftover 1208; akix_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.akhex_ok` | 6.046 | 2.914 | 2.075× | 8.00× | measure-only leftover 1228; akhex_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.mlsx_ok` | 3.176 | 0.876 | 3.626× | 8.00× | measure-only leftover 1229; mlsx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.aisx_ok` | 2.480 | 0.317 | 7.834× | 8.00× | measure-only leftover 1230; aisx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ossx_ok` | 8.436 | 4.203 | 2.007× | 8.00× | measure-only leftover 1209; ossx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lmsxx_ok` | 3.606 | 1.489 | 2.421× | 8.00× | measure-only leftover 1273; lmsxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.akixx_ok` | 2.669 | 0.355 | 7.512× | 8.00× | measure-only leftover 1274; akixx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.akhexx_ok` | 6.396 | 3.770 | 1.697× | 8.00× | measure-only leftover 1294; akhexx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.mlsxx_ok` | 3.415 | 0.956 | 3.572× | 8.00× | measure-only leftover 1295; mlsxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.aisxx_ok` | 2.799 | 0.330 | 8.480× | 8.00× | measure-only leftover 1296; aisxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ossxx_ok` | 8.001 | 4.668 | 1.714× | 8.00× | measure-only leftover 1275; ossxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.sst_ok` | 2.557 | 0.399 | 6.411× | 8.00× | measure-only leftover 1155; sst_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oasx_ok` | 76.164 | 3.819 | 19.944× | 8.00× | measure-only leftover 1219; oasx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.fltx_ok` | 78.904 | 8.841 | 8.925× | 8.00× | measure-only leftover 1220; fltx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.qryx_ok` | 1.447 | 0.255 | 5.681× | 8.00× | measure-only leftover 1221; qryx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oasxx_ok` | 77.864 | 4.382 | 17.768× | 8.00× | measure-only leftover 1285; oasxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.fltxx_ok` | 89.250 | 8.810 | 10.131× | 8.00× | measure-only leftover 1286; fltxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.qryxx_ok` | 1.512 | 0.291 | 5.191× | 8.00× | measure-only leftover 1287; qryxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_extensions_install.hp_ok` | 0.604 | 0.597 | 1.012× | 8.00× | measure-only leftover 1007; handle-extension-command plain leftover | invent pause；地板优化另刀 |
| `cli_interactive_controller.br_ok` | 1.316 | 0.337 | 3.907× | 8.00× | measure-only leftover 1009; append-tui-user-bash-running leftover | invent pause；地板优化另刀 |
| `cli_interactive_controller.bf_ok` | 1.405 | 0.267 | 5.260× | 8.00× | measure-only leftover 1010; complete-tui-user-bash-string leftover | invent pause；地板优化另刀 |
| `cli_interactive_controller.bh_ok` | 1.345 | 0.187 | 7.203× | 8.00× | measure-only leftover 1011; stop-tui-user-bash-entry leftover | invent pause；地板优化另刀 |
| `powershell_tool.up_ok` | 0.739 | 0.137 | 5.415× | 8.00× | measure-only leftover 1015; +powershell-utf8-output-prefix+ leftover | invent pause；地板优化另刀 |
| `powershell_tool.pc_ok` | 0.873 | 0.273 | 3.197× | 8.00× | measure-only leftover 1016; UTF-8 prefix + command concatenate leftover | invent pause；地板优化另刀 |
| `powershell_tool.mt_ok` | 2.723 | 1.349 | 2.019× | 8.00× | measure-only leftover 1017; make-powershell-tool leftover | invent pause；地板优化另刀 |
| `powershell_tool.ps_up` | 0.846 | 0.125 | 6.778× | 8.00× | measure-only leftover 1090; ps_up leftover remount | invent pause；地板优化另刀 |
| `powershell_tool.ps_pc` | 1.246 | 0.306 | 4.067× | 8.00× | measure-only leftover 1091; ps_pc leftover remount | invent pause；地板优化另刀 |
| `powershell_tool.ps_mt` | 4.116 | 2.133 | 1.930× | 8.00× | measure-only leftover 1092; ps_mt leftover remount | invent pause；地板优化另刀 |
| `powershell_tool.utf_ok` | 0.705 | 0.125 | 5.636× | 8.00× | measure-only leftover 1171; utf_ok leftover remount | invent pause；地板优化另刀 |
| `powershell_tool.pfx_ok` | 1.656 | 0.259 | 6.387× | 8.00× | measure-only leftover 1172; pfx_ok leftover remount | invent pause；地板优化另刀 |
| `powershell_tool.mtb_ok` | 3.052 | 1.876 | 1.627× | 8.00× | measure-only leftover 1173; mtb_ok leftover remount | invent pause；地板优化另刀 |
| `powershell_tool.utfx_ok` | 0.630 | 0.109 | 5.782× | 8.00× | measure-only leftover 1237; utfx_ok leftover remount | invent pause；地板优化另刀 |
| `powershell_tool.pfxx_ok` | 0.733 | 0.204 | 3.593× | 8.00× | measure-only leftover 1238; pfxx_ok leftover remount | invent pause；地板优化另刀 |
| `powershell_tool.mtbx_ok` | 2.382 | 1.329 | 1.793× | 8.00× | measure-only leftover 1239; mtbx_ok leftover remount | invent pause；地板优化另刀 |
| `powershell_tool.utfxx_ok` | 0.702 | 0.113 | 6.209× | 8.00× | measure-only leftover 1303; utfxx_ok leftover remount | invent pause；地板优化另刀 |
| `powershell_tool.pfxxx_ok` | 1.042 | 0.227 | 4.585× | 8.00× | measure-only leftover 1304; pfxxx_ok leftover remount | invent pause；地板优化另刀 |
| `powershell_tool.mtbxx_ok` | 3.145 | 1.476 | 2.131× | 8.00× | measure-only leftover 1305; mtbxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.cd_sec` | 1.152 | 0.204 | 5.648× | 8.00× | measure-only leftover 1018; countdown-seconds leftover | invent pause；地板优化另刀 |
| `cli_selectors.cd_tick` | 1.066 | 0.165 | 6.479× | 8.00× | measure-only leftover 1019; countdown-tick leftover | invent pause；地板优化另刀 |
| `cli_selectors.cd_rnd` | 1.539 | 0.335 | 4.599× | 8.00× | measure-only leftover 1020; countdown-render leftover | invent pause；地板优化另刀 |
| `cli_selectors.cds_ok` | 1.080 | 0.129 | 8.372× | 8.00× | measure-only leftover 1168; cds_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.cdt_ok` | 1.021 | 0.196 | 5.213× | 8.00× | measure-only leftover 1169; cdt_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.cdr_ok` | 1.337 | 0.231 | 5.790× | 8.00× | measure-only leftover 1170; cdr_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.cdsx_ok` | 1.110 | 0.115 | 9.650× | 8.00× | measure-only leftover 1234; cdsx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.cdtx_ok` | 1.045 | 0.146 | 7.172× | 8.00× | measure-only leftover 1235; cdtx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.cdrx_ok` | 1.357 | 0.271 | 5.010× | 8.00× | measure-only leftover 1236; cdrx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.cdsxx_ok` | 1.212 | 0.131 | 9.253× | 8.00× | measure-only leftover 1300; cdsxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.cdtxx_ok` | 1.052 | 0.164 | 6.431× | 8.00× | measure-only leftover 1301; cdtxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.cdrxx_ok` | 1.204 | 0.163 | 7.367× | 8.00× | measure-only leftover 1302; cdrxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.dax_rgb` | 1.131 | 0.359 | 3.149× | 8.00× | measure-only leftover 1021; daxnuts-rgb-at leftover | invent pause；地板优化另刀 |
| `cli_selectors.dax_make` | 0.999 | 0.153 | 6.531× | 8.00× | measure-only leftover 1022; make-daxnuts-component leftover | invent pause；地板优化另刀 |
| `cli_selectors.dax_tick` | 5.142 | 0.581 | 8.845× | 12.00× | measure-only leftover 1023; daxnuts-component-tick leftover; first-freeze ceiling 12.0 | invent pause；地板优化另刀 |
| `cli_selectors.dn_rgb` | 1.580 | 0.404 | 3.909× | 8.00× | measure-only leftover 1093; dn_rgb leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.dn_make` | 1.395 | 0.301 | 4.636× | 8.00× | measure-only leftover 1094; dn_make leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.dn_tick` | 5.390 | 0.344 | 15.673× | 8.00× | measure-only leftover 1095; dn_tick leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.dra_ok` | 1.484 | 0.242 | 6.138× | 8.00× | measure-only leftover 1174; dra_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.dmc_ok` | 1.227 | 0.125 | 9.850× | 8.00× | measure-only leftover 1175; dmc_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.dct_ok` | 4.958 | 0.244 | 20.277× | 8.00× | measure-only leftover 1176; dct_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.drax_ok` | 1.229 | 0.197 | 6.244× | 8.00× | measure-only leftover 1240; drax_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.dmcx_ok` | 1.232 | 0.112 | 11.028× | 8.00× | measure-only leftover 1241; dmcx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.dctx_ok` | 4.363 | 0.216 | 20.209× | 8.00× | measure-only leftover 1242; dctx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.draxx_ok` | 1.297 | 0.239 | 5.419× | 8.00× | measure-only leftover 1306; draxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.dmcxx_ok` | 1.025 | 0.136 | 7.513× | 8.00× | measure-only leftover 1307; dmcxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.dctxx_ok` | 4.434 | 0.285 | 15.546× | 8.00× | measure-only leftover 1308; dctxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.th_lbl` | 0.386 | 0.197 | 1.960× | 8.00× | measure-only leftover 1024; thinking-level-label leftover | invent pause；地板优化另刀 |
| `cli_selectors.th_kb` | 4.463 | 1.064 | 4.194× | 8.00× | measure-only leftover 1026; thinking-selector-keybindings leftover | invent pause；地板优化另刀 |
| `cli_selectors.tlbl_ok` | 0.484 | 0.142 | 3.419× | 8.00× | measure-only leftover 1099; tlbl_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tqry_ok` | 12.620 | 8.834 | 1.429× | 8.00× | measure-only leftover 1100; tqry_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tkb_ok` | 3.415 | 0.289 | 11.805× | 8.00× | measure-only leftover 1101; tkb_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tll_ok` | 0.523 | 0.127 | 4.123× | 8.00× | measure-only leftover 1180; tll_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tsq_ok` | 14.395 | 7.939 | 1.813× | 8.00× | measure-only leftover 1181; tsq_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tskb_ok` | 3.062 | 0.323 | 9.466× | 8.00× | measure-only leftover 1182; tskb_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tllx_ok` | 0.455 | 0.129 | 3.512× | 8.00× | measure-only leftover 1246; tllx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tsqx_ok` | 11.623 | 7.323 | 1.587× | 8.00× | measure-only leftover 1247; tsqx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tskbx_ok` | 2.861 | 0.176 | 16.298× | 8.00× | measure-only leftover 1248; tskbx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tllxx_ok` | 0.582 | 0.143 | 4.063× | 8.00× | measure-only leftover 1312; tllxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tsqxx_ok` | 14.416 | 7.953 | 1.813× | 8.00× | measure-only leftover 1313; tsqxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tskbxx_ok` | 3.278 | 0.212 | 15.428× | 8.00× | measure-only leftover 1314; tskbxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ld_wait` | 6.342 | 1.871 | 3.389× | 8.00× | measure-only leftover 1027; login-dialog-show-waiting leftover | invent pause；地板优化另刀 |
| `cli_selectors.ld_prog` | 3.541 | 1.369 | 2.586× | 8.00× | measure-only leftover 1028; login-dialog-show-progress leftover | invent pause；地板优化另刀 |
| `cli_selectors.ld_man` | 6.210 | 2.343 | 2.650× | 8.00× | measure-only leftover 1029; login-dialog-show-manual-input leftover | invent pause；地板优化另刀 |
| `cli_selectors.wait_ok` | 7.978 | 1.487 | 5.365× | 8.00× | measure-only leftover 1102; wait_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.prog_ok` | 4.603 | 1.062 | 4.332× | 8.00× | measure-only leftover 1103; prog_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.man_ok` | 8.147 | 1.623 | 5.021× | 8.00× | measure-only leftover 1104; man_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldw_ok` | 8.371 | 2.040 | 4.104× | 8.00× | measure-only leftover 1183; ldw_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldp_ok` | 4.138 | 1.384 | 2.991× | 8.00× | measure-only leftover 1184; ldp_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldmi_ok` | 7.537 | 1.664 | 4.531× | 8.00× | measure-only leftover 1185; ldmi_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldwx_ok` | 6.326 | 4.145 | 1.526× | 8.00× | measure-only leftover 1249; ldwx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldpx_ok` | 3.738 | 0.939 | 3.981× | 8.00× | measure-only leftover 1250; ldpx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldmix_ok` | 5.863 | 1.112 | 5.275× | 8.00× | measure-only leftover 1251; ldmix_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldwxx_ok` | 7.936 | 1.447 | 5.483× | 8.00× | measure-only leftover 1315; ldwxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldpxx_ok` | 6.653 | 1.011 | 6.580× | 8.00× | measure-only leftover 1316; ldpxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldmixx_ok` | 7.435 | 1.197 | 6.211× | 8.00× | measure-only leftover 1317; ldmixx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ld_prmt` | 10.038 | 3.250 | 3.088× | 8.00× | measure-only leftover 1030; login-dialog-show-prompt leftover | invent pause；地板优化另刀 |
| `cli_selectors.ld_cmp` | 6.716 | 2.977 | 2.256× | 8.00× | measure-only leftover 1033; login-dialog-complete-input leftover | invent pause；地板优化另刀 |
| `cli_selectors.ld_evt` | 7.339 | 2.254 | 3.257× | 8.00× | measure-only leftover 1034; login-dialog-handle-event leftover | invent pause；地板优化另刀 |
| `cli_selectors.ld_rnd` | 98.051 | 1.661 | 59.042× | 70.00× | measure-only leftover 1035; render-login-dialog leftover | invent pause；地板优化另刀 |
| `cli_selectors.cmp_ok` | 7.304 | 1.288 | 5.672× | 8.00× | measure-only leftover 1108; cmp_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.evt_ok` | 8.149 | 2.060 | 3.956× | 8.00× | measure-only leftover 1109; evt_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.rnd2_ok` | 104.030 | 2.132 | 48.784× | 8.00× | measure-only leftover 1110; rnd2_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldci_ok` | 7.260 | 1.354 | 5.361× | 8.00× | measure-only leftover 1189; ldci_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldhe_ok` | 7.976 | 1.364 | 5.848× | 8.00× | measure-only leftover 1190; ldhe_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldrd_ok` | 129.532 | 1.357 | 95.438× | 8.00× | measure-only leftover 1191; ldrd_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldcix_ok` | 7.691 | 1.330 | 5.781× | 8.00× | measure-only leftover 1255; ldcix_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldhex_ok` | 9.049 | 1.325 | 6.829× | 8.00× | measure-only leftover 1256; ldhex_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldrdx_ok` | 111.106 | 1.440 | 77.143× | 8.00× | measure-only leftover 1257; ldrdx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldcixx_ok` | 7.961 | 1.427 | 5.578× | 8.00× | measure-only leftover 1321; ldcixx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldhexx_ok` | 9.364 | 1.311 | 7.142× | 8.00× | measure-only leftover 1322; ldhexx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldrdxx_ok` | 133.993 | 1.470 | 91.160× | 8.00× | measure-only leftover 1323; ldrdxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.um_he` | 1.736 | 0.582 | 2.984× | 8.00× | measure-only leftover 1036; user-message-handle-event leftover | invent pause；地板优化另刀 |
| `cli_selectors.um_hr` | 95.867 | 7.576 | 12.654× | 16.00× | measure-only leftover 1037; user-message-handle-raw leftover | invent pause；地板优化另刀 |
| `cli_selectors.um_rd` | 276.946 | 1.227 | 225.713× | 250.00× | measure-only leftover 1038; render-user-message-selector leftover | invent pause；地板优化另刀 |
| `cli_selectors.he_ok` | 1.652 | 0.989 | 1.670× | 8.00× | measure-only leftover 1111; he_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.raw_ok` | 91.365 | 5.688 | 16.062× | 8.00× | measure-only leftover 1112; raw_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.sel_ok` | 254.663 | 2.210 | 115.242× | 8.00× | measure-only leftover 1113; sel_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.umev_ok` | 2.048 | 0.590 | 3.469× | 8.00× | measure-only leftover 1192; umev_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.umrw_ok` | 103.853 | 3.280 | 31.664× | 8.00× | measure-only leftover 1193; umrw_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.umrs_ok` | 290.148 | 1.102 | 263.196× | 8.00× | measure-only leftover 1194; umrs_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.umevx_ok` | 1.791 | 0.607 | 2.950× | 8.00× | measure-only leftover 1258; umevx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.umrwx_ok` | 108.530 | 3.330 | 32.591× | 8.00× | measure-only leftover 1259; umrwx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.umrsx_ok` | 263.484 | 1.222 | 215.567× | 8.00× | measure-only leftover 1260; umrsx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.umevxx_ok` | 2.178 | 0.636 | 3.424× | 8.00× | measure-only leftover 1324; umevxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.umrwxx_ok` | 98.992 | 3.561 | 27.799× | 8.00× | measure-only leftover 1325; umrwxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.umrsxx_ok` | 267.422 | 1.308 | 204.526× | 8.00× | measure-only leftover 1326; umrsxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.sm_st` | 107.261 | 4.351 | 24.651× | 40.00× | measure-only leftover 1040; make-scoped-models-selector-state leftover | invent pause；地板优化另刀 |
| `cli_selectors.rm_sel` | 184.907 | 6.566 | 28.160× | 50.00× | measure-only leftover 1041; render-model-selector leftover | invent pause；地板优化另刀 |
| `cli_selectors.kb_ok` | 30.920 | 30.541 | 1.012× | 8.00× | measure-only leftover 1114; kb_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.sms_ok` | 109.309 | 3.827 | 28.561× | 8.00× | measure-only leftover 1115; sms_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.rms_ok` | 187.216 | 6.550 | 28.581× | 8.00× | measure-only leftover 1116; rms_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.msms_ok` | 134.701 | 3.452 | 39.017× | 8.00× | measure-only leftover 1196; msms_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.mrms_ok` | 243.569 | 8.604 | 28.308× | 8.00× | measure-only leftover 1197; mrms_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.msmsx_ok` | 109.615 | 4.066 | 26.957× | 8.00× | measure-only leftover 1262; msmsx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.mrmsx_ok` | 188.436 | 6.760 | 27.875× | 8.00× | measure-only leftover 1263; mrmsx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lat_ok` | 3.668 | 1.731 | 2.118× | 8.00× | measure-only leftover 1141; lat_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lpo_ok` | 12.585 | 3.685 | 3.415× | 8.00× | measure-only leftover 1142; lpo_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lgo_ok` | 10.328 | 3.658 | 2.824× | 8.00× | measure-only leftover 1143; lgo_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.th_cl` | 1.557 | 0.506 | 3.075× | 8.00× | measure-only leftover 1043; th_cl leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.th_sc` | 1.870 | 0.975 | 1.919× | 8.00× | measure-only leftover 1044; th_sc leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.th_mv` | 1.128 | 0.502 | 2.244× | 8.00× | measure-only leftover 1045; th_mv leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.th_lv` | 0.877 | 0.712 | 1.231× | 8.00× | measure-only leftover 1046; th_lv leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.th_ds` | 0.596 | 0.181 | 3.296× | 8.00× | measure-only leftover 1047; th_ds leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tr_pto` | 72.698 | 43.738 | 1.662× | 8.00× | measure-only leftover 1048; tr_pto leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tr_tss` | 251.711 | 43.252 | 5.820× | 8.00× | measure-only leftover 1049; tr_tss leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tr_tdd` | 176.212 | 56.817 | 3.101× | 8.00× | measure-only leftover 1050; tr_tdd leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldpr_ok` | 10.961 | 2.365 | 4.634× | 8.00× | measure-only leftover 1186; ldpr_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldi_ok` | 11.704 | 3.396 | 3.446× | 8.00× | measure-only leftover 1187; ldi_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lddt_ok` | 4.310 | 2.792 | 1.544× | 8.00× | measure-only leftover 1188; lddt_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldprx_ok` | 8.460 | 1.678 | 5.043× | 8.00× | measure-only leftover 1252; ldprx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldix_ok` | 11.876 | 2.146 | 5.533× | 8.00× | measure-only leftover 1253; ldix_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lddtx_ok` | 3.003 | 1.583 | 1.897× | 8.00× | measure-only leftover 1254; lddtx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldprxx_ok` | 12.485 | 3.010 | 4.148× | 8.00× | measure-only leftover 1318; ldprxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ldixx_ok` | 12.861 | 4.216 | 3.051× | 8.00× | measure-only leftover 1319; ldixx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lddtxx_ok` | 3.876 | 2.531 | 1.532× | 8.00× | measure-only leftover 1320; lddtxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.rtk_ok` | 1.777 | 0.723 | 2.458× | 8.00× | measure-only leftover 1178; rtk_ok leftover remount | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.dpk_ok` | 0.898 | 0.758 | 1.185× | 8.00× | measure-only leftover 1179; dpk_ok leftover remount | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.pbkx_ok` | 0.711 | 0.555 | 1.282× | 8.00× | measure-only leftover 1243; pbkx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.rtkx_ok` | 1.283 | 0.522 | 2.458× | 8.00× | measure-only leftover 1244; rtkx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.dpkx_ok` | 0.683 | 0.622 | 1.098× | 8.00× | measure-only leftover 1245; dpkx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.pbkxx_ok` | 0.965 | 0.299 | 3.227× | 8.00× | measure-only leftover 1309; pbkxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.rtkxx_ok` | 1.442 | 0.549 | 2.628× | 8.00× | measure-only leftover 1310; rtkxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.dpkxx_ok` | 0.847 | 0.471 | 1.799× | 8.00× | measure-only leftover 1311; dpkxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.mv_ok` | 1.300 | 0.133 | 9.747× | 8.00× | measure-only leftover 1120; mv_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.hri_ok` | 161.015 | 10.052 | 16.019× | 8.00× | measure-only leftover 1121; hri_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.hev_ok` | 4.005 | 2.304 | 1.738× | 8.00× | measure-only leftover 1122; hev_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.hen_ok` | 6.210 | 2.471 | 2.514× | 8.00× | measure-only leftover 1150; hen_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.thmv_ok` | 0.992 | 0.123 | 8.055× | 8.00× | measure-only leftover 1201; thmv_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.thhr_ok` | 166.081 | 4.840 | 34.311× | 8.00× | measure-only leftover 1202; thhr_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.thhe_ok` | 4.275 | 2.383 | 1.793× | 8.00× | measure-only leftover 1203; thhe_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.mts_ok` | 2.186 | 0.454 | 4.818× | 8.00× | measure-only leftover 1151; mts_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lst_ok` | 1.614 | 0.227 | 7.115× | 8.00× | measure-only leftover 1152; lst_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.henx_ok` | 3.946 | 2.292 | 1.721× | 8.00× | measure-only leftover 1231; henx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.thmvx_ok` | 0.947 | 0.135 | 7.009× | 8.00× | measure-only leftover 1267; thmvx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.thhrx_ok` | 166.608 | 5.405 | 30.826× | 8.00× | measure-only leftover 1268; thhrx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.thhex_ok` | 4.024 | 2.522 | 1.596× | 8.00× | measure-only leftover 1269; thhex_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.mtsx_ok` | 2.082 | 0.396 | 5.261× | 8.00× | measure-only leftover 1232; mtsx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lstx_ok` | 1.257 | 0.202 | 6.236× | 8.00× | measure-only leftover 1233; lstx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.henxx_ok` | 4.835 | 2.555 | 1.892× | 8.00× | measure-only leftover 1297; henxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.mtsxx_ok` | 2.041 | 0.423 | 4.827× | 8.00× | measure-only leftover 1298; mtsxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lstxx_ok` | 1.473 | 0.220 | 6.705× | 8.00× | measure-only leftover 1299; lstxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.af_ok` | 17.747 | 10.269 | 1.728× | 8.00× | measure-only leftover 1117; af_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.cl_ok` | 0.906 | 0.189 | 4.795× | 8.00× | measure-only leftover 1118; cl_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.sc_ok` | 1.283 | 0.335 | 3.825× | 8.00× | measure-only leftover 1119; sc_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.thaf_ok` | 13.343 | 9.437 | 1.414× | 8.00× | measure-only leftover 1198; thaf_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.thcl_ok` | 0.987 | 0.182 | 5.437× | 8.00× | measure-only leftover 1199; thcl_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.thsc_ok` | 1.341 | 0.369 | 3.634× | 8.00× | measure-only leftover 1200; thsc_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.thafx_ok` | 14.773 | 10.024 | 1.474× | 8.00× | measure-only leftover 1264; thafx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.thclx_ok` | 0.986 | 0.193 | 5.108× | 8.00× | measure-only leftover 1265; thclx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.thscx_ok` | 1.321 | 0.385 | 3.435× | 8.00× | measure-only leftover 1266; thscx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.prmt_ok` | 8.683 | 1.811 | 4.795× | 8.00× | measure-only leftover 1105; prmt_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.info_ok` | 13.436 | 5.714 | 2.351× | 8.00× | measure-only leftover 1106; info_ok leftover remount | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.psb_ok` | 1.042 | 0.851 | 1.225× | 8.00× | measure-only leftover 1096; psb_ok leftover remount | invent pause；地板优化另刀 |
| `cli_bootstrap_sessions.rst_ok` | 1.737 | 0.700 | 2.482× | 8.00× | measure-only leftover 1097; rst_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tr_mv` | 286.724 | 113.395 | 2.529× | 8.00× | measure-only leftover 1051; tr_mv leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tr_he` | 301.199 | 125.263 | 2.405× | 8.00× | measure-only leftover 1052; tr_he leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tr_ui` | 335.271 | 160.186 | 2.093× | 8.00× | measure-only leftover 1053; tr_ui leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tsm_ok` | 337.926 | 134.774 | 2.507× | 8.00× | measure-only leftover 1129; tsm_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tse_ok` | 370.246 | 157.217 | 2.355× | 8.00× | measure-only leftover 1130; tse_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tui_ok` | 405.519 | 192.023 | 2.112× | 8.00× | measure-only leftover 1131; tui_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tsmx_ok` | 286.270 | 104.310 | 2.744× | 8.00× | measure-only leftover 1210; tsmx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tsex_ok` | 285.730 | 114.245 | 2.501× | 8.00× | measure-only leftover 1211; tsex_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tuix_ok` | 336.435 | 128.478 | 2.619× | 8.00× | measure-only leftover 1212; tuix_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tsmxx_ok` | 294.776 | 113.763 | 2.591× | 8.00× | measure-only leftover 1276; tsmxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tsexx_ok` | 312.875 | 141.421 | 2.212× | 8.00× | measure-only leftover 1277; tsexx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tuixx_ok` | 365.451 | 157.831 | 2.315× | 8.00× | measure-only leftover 1278; tuixx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_lbl` | 1.961 | 1.359 | 1.443× | 8.00× | measure-only leftover 1054; oa_lbl leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_typ` | 0.575 | 0.458 | 1.254× | 8.00× | measure-only leftover 1055; oa_typ leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_env` | 1.061 | 0.686 | 1.548× | 8.00× | measure-only leftover 1056; oa_env leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lbl_ok` | 2.108 | 0.829 | 2.544× | 8.00× | measure-only leftover 1135; lbl_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.typ_ok` | 0.847 | 0.155 | 5.457× | 8.00× | measure-only leftover 1136; typ_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.osr_ok` | 10.561 | 1.799 | 5.869× | 8.00× | measure-only leftover 1156; osr_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.osl_ok` | 2.036 | 0.548 | 3.717× | 8.00× | measure-only leftover 1157; osl_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.cet_ok` | 0.609 | 0.162 | 3.753× | 8.00× | measure-only leftover 1158; cet_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.env_ok` | 1.199 | 0.221 | 5.427× | 8.00× | measure-only leftover 1137; env_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_sel` | 75.871 | 5.562 | 13.640× | 20.00× | measure-only leftover 1057; oa_sel leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_rt` | 3.335 | 0.893 | 3.735× | 8.00× | measure-only leftover 1060; oa_rt leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_lin` | 10.793 | 3.027 | 3.566× | 8.00× | measure-only leftover 1061; oa_lin leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_out` | 8.807 | 2.228 | 3.953× | 8.00× | measure-only leftover 1062; oa_out leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.rwi_ok` | 1039.776 | 181.734 | 5.721× | 8.00× | measure-only leftover 1159; rwi_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.esp_ok` | 1.847 | 0.214 | 8.619× | 8.00× | measure-only leftover 1160; esp_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lblx_ok` | 1.841 | 0.487 | 3.777× | 8.00× | measure-only leftover 1216; lblx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.typx_ok` | 0.571 | 0.143 | 3.992× | 8.00× | measure-only leftover 1217; typx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.envx_ok` | 1.084 | 0.202 | 5.375× | 8.00× | measure-only leftover 1218; envx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lblxx_ok` | 2.121 | 0.530 | 4.001× | 8.00× | measure-only leftover 1282; lblxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.typxx_ok` | 0.589 | 0.156 | 3.779× | 8.00× | measure-only leftover 1283; typxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.envxx_ok` | 1.050 | 0.209 | 5.032× | 8.00× | measure-only leftover 1284; envxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lgt_ok` | 10.011 | 2.255 | 4.440× | 8.00× | measure-only leftover 1161; lgt_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_lmh` | 3.612 | 2.043 | 1.768× | 8.00× | measure-only leftover 1063; oa_lmh leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_lui` | 515.508 | 80.430 | 6.409× | 8.00× | measure-only leftover 1064; oa_lui leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_aki` | 233.752 | 78.178 | 2.990× | 8.00× | measure-only leftover 1065; oa_aki leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lmh_ok` | 3.307 | 0.577 | 5.735× | 8.00× | measure-only leftover 1144; lmh_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.rte_ok` | 3.667 | 0.415 | 8.829× | 8.00× | measure-only leftover 1162; rte_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lpr_ok` | 16.974 | 3.064 | 5.540× | 8.00× | measure-only leftover 1163; lpr_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.latx_ok` | 3.123 | 0.366 | 8.535× | 8.00× | measure-only leftover 1222; latx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lpox_ok` | 9.745 | 2.608 | 3.737× | 8.00× | measure-only leftover 1223; lpox_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lgox_ok` | 8.527 | 1.993 | 4.279× | 8.00× | measure-only leftover 1224; lgox_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.latxx_ok` | 3.705 | 0.408 | 9.081× | 8.00× | measure-only leftover 1288; latxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lpoxx_ok` | 10.552 | 2.800 | 3.768× | 8.00× | measure-only leftover 1289; lpoxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lgoxx_ok` | 9.229 | 3.723 | 2.479× | 8.00× | measure-only leftover 1290; lgoxx_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lhe_ok` | 3.803 | 0.607 | 6.260× | 8.00× | measure-only leftover 1164; lhe_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.lui_ok` | 430.541 | 93.029 | 4.628× | 8.00× | measure-only leftover 1145; lui_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.aku_ok` | 200.852 | 74.457 | 2.698× | 8.00× | measure-only leftover 1146; aku_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_mls` | 4.539 | 1.831 | 2.478× | 8.00× | measure-only leftover 1067; oa_mls leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_ais` | 3.248 | 0.907 | 3.580× | 8.00× | measure-only leftover 1068; oa_ais leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.th_he` | 4.958 | 4.343 | 1.142× | 8.00× | measure-only leftover 1069; th_he leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.th_mts` | 2.324 | 0.900 | 2.582× | 8.00× | measure-only leftover 1070; th_mts leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.th_lst` | 1.536 | 0.226 | 6.810× | 8.00× | measure-only leftover 1071; th_lst leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_ohe` | 134.720 | 11.085 | 12.153× | 20.00× | measure-only leftover 1072; oa_ohe leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_osr` | 10.627 | 1.425 | 7.459× | 8.00× | measure-only leftover 1075; oa_osr leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_osl` | 2.286 | 0.772 | 2.963× | 8.00× | measure-only leftover 1076; oa_osl leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_cet` | 0.682 | 0.248 | 2.746× | 8.00× | measure-only leftover 1077; oa_cet leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_hri` | 620.744 | 159.344 | 3.896× | 8.00× | measure-only leftover 1078; oa_hri leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_esp` | 1.200 | 0.372 | 3.229× | 8.00× | measure-only leftover 1079; oa_esp leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_lgo` | 11.156 | 5.324 | 2.095× | 8.00× | measure-only leftover 1080; oa_lgo leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_lat` | 3.632 | 1.033 | 3.516× | 8.00× | measure-only leftover 1081; oa_lat leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_lpo` | 14.676 | 7.636 | 1.922× | 8.00× | measure-only leftover 1082; oa_lpo leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_lhe` | 4.008 | 2.254 | 1.778× | 8.00× | measure-only leftover 1083; oa_lhe leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_lms` | 498.558 | 103.684 | 4.808× | 8.00× | measure-only leftover 1084; oa_lms leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_aku` | 230.325 | 107.085 | 2.151× | 8.00× | measure-only leftover 1085; oa_aku leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_ahe` | 7.956 | 4.847 | 1.642× | 8.00× | measure-only leftover 1086; oa_ahe leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.sec_ok` | 1.199 | 0.336 | 3.567× | 8.00× | measure-only leftover 1087; sec_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.tick_ok` | 1.269 | 0.318 | 3.994× | 8.00× | measure-only leftover 1088; tick_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.rnd_ok` | 1.467 | 0.421 | 3.484× | 8.00× | measure-only leftover 1089; rnd_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_mos` | 11.495 | 9.950 | 1.155× | 8.00× | measure-only leftover 1073; oa_mos leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_sst` | 1.769 | 0.606 | 2.920× | 8.00× | measure-only leftover 1074; oa_sst leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oas_ok` | 106.295 | 4.585 | 23.182× | 8.00× | measure-only leftover 1138; oas_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.flt_ok` | 85.440 | 11.545 | 7.400× | 8.00× | measure-only leftover 1139; flt_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.qry_ok` | 1.642 | 0.429 | 3.823× | 8.00× | measure-only leftover 1140; qry_ok leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_flt` | 78.512 | 9.198 | 8.536× | 12.00× | measure-only leftover 1058; oa_flt leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.oa_qry` | 1.461 | 0.320 | 4.565× | 8.00× | measure-only leftover 1059; oa_qry leftover remount | invent pause；地板优化另刀 |
| `cli_selectors.ld_info` | 10.904 | 3.575 | 3.050× | 8.00× | measure-only leftover 1031; login-dialog-show-info leftover | invent pause；地板优化另刀 |
Ceilings not lowered. Do not redo withdrawn phenomenon knives.
| settings_load.sdk_make_manager | 1.411 | 3.670 | 2.600 | 8.0 | Friend-MachineD | leftover 856 loop-tick-47 |
| settings_load.sdk_make_memory | 5.581 | 26.876 | 4.816 | 8.0 | Friend-MachineD | leftover 857 loop-tick-47 |
| settings_load.sdk_effective_thinking_level | 3.700 | 14.454 | 3.907 | 8.0 | Friend-MachineD | leftover 858 loop-tick-47 |
| cli_interactive_controller.terminal_title_sequence | 1.519 | 2.713 | 1.785 | 8.0 | Friend-MachineD | leftover 859 loop-tick-48 |
| cli_interactive_controller.make_notification_stream | 8.280 | 1.429 | 0.173 | 8.0 | Friend-MachineD | leftover 860 loop-tick-48 |
| cli_interactive_controller.notification_stream_flush | 4.675 | 1.154 | 0.247 | 8.0 | Friend-MachineD | leftover 861 loop-tick-48 |
