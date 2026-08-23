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

Ceilings not lowered. Do not redo withdrawn phenomenon knives.
