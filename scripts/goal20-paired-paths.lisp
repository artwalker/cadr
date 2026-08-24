;;;; Goal 20 Part H: cadr side of the non-TUI paired benchmarks.
;;;;
;;;; Goal 11 paired cadr against pi on three TUI-input ratios only (mouse
;;;; drag, wheel, continuous alt input).  Nothing outside the renderer was
;;;; paired, so "no worse than pi" was unfalsifiable for cadr-cli, cadr-ai,
;;;; cadr-agent, and the storage layer.  This script measures the cadr half
;;;; of four such paths over the same fixture bytes that
;;;; scripts/goal20-paired-paths.mjs feeds to pi;
;;;; scripts/goal20-paired-paths.py pairs the two reports using the
;;;; same_machine hostname compare that goal11-performance-gate.py already
;;;; uses.
;;;;
;;;; Pairs (each one same-input, same-machine, no network):
;;;;   1. cli_dispatch      argv parse, help render, --list-models dispatch
;;;;   2. provider_stream   request assembly + SSE response parse
;;;;   3. session_pipeline  session load + context entry walk
;;;;   4. storage_journal   journal read + journal append
;;;;   5. sqlite_session    SQLite open + read-all + leaf walk
;;;;   6. tool_read         production read-tool-file vs pi execute
;;;;   7. tool_grep         production grep-lines vs pi execute (context=2)
;;;;   8. session_discovery glob *.jsonl + header probe vs findMostRecentSession
;;;;   9. session_export_html export-session-html vs exportSessionToHtml
;;;;  10. protocol_cbor encode-cbor/decode-cbor vs encodeCbor/decodeCbor
;;;;  11. agent_schema validate-tool-arguments vs validateToolArguments
;;;;  12. harness_storage jsonl repo open+walk vs JsonlSessionRepo
;;;;  13. protocol_codec encode-client-message + decoder vs encodeClientMessage
;;;;  14. agent_proxy stream-proxy vs streamProxy (stub SSE, no socket)
;;;;  15. oauth_pkce recorded verifier → challenge + authorize URLs
;;;;  16. evals_harness summarize-harness-comparisons vs summarizeHarnessComparisons
;;;;  17. ai_crypto_model_data create-model-data-manifest vs createModelDataManifest
;;;;  18. cli_models_rest parse-scoped-model-pattern vs parseModelPattern
;;;;  19. image_runtime image-dimensions vs getImageDimensions
;;;;  20. cli_print_rpc write-json-line vs serializeJsonLine
;;;;      leftover: read-rpc-jsonl-lines vs attachJsonlLineReader
;;;;  21. tui_latex render-latex vs renderLatex
;;;;  22. tui_editor_helpers fuzzy-match vs fuzzyMatch
;;;;  23. tui_theme_overlay parse-osc-11-background-color vs parseOsc11BackgroundColor
;;;;  24. ai_support estimate-text-tokens vs estimateTextTokens
;;;;  25. tui_select_settings_loaders select-list filter vs SelectList.setFilter
;;;;  26. tui_word_navigation find-word-backward/forward vs findWordBackward/Forward
;;;;  27. tui_overlay composite-overlay-line vs compositeTuiLine
;;;;  28. tui_kill_ring kill-ring-push/peek/rotate vs KillRing
;;;;  29. tui_undo_stack undo-stack-push/pop/clear vs UndoStack
;;;;  30. tui_autocomplete get-suggestions + apply vs CombinedAutocompleteProvider
;;;;  31. tui_keybindings make-keybindings-manager vs KeybindingsManager / getKeybindings
;;;;  32. tui_stdin_buffer stdin-buffer-process vs StdinBuffer.process
;;;;  33. tui_input_component handle-event vs Input.handleInput
;;;;  34. tui_native_modifiers is-native-modifier-pressed vs isNativeModifierPressed
;;;;  35. tui_settings_list apply-filter vs SettingsList.applyFilter
;;;;  36. ai_capabilities short-hash vs shortHash
;;;;  37. cli_support strip-ansi vs stripAnsi
;;;;  38. cli_interactive_controller decode-highlight-entity vs decodeHtmlEntity
;;;;  39. cli_sdk newer-package-version-p vs isNewerPackageVersion
;;;;  40. provider_registry_defs list/find vs getBuiltinProviders
;;;;  41. skill_prompt_load build-system-prompt vs buildSystemPrompt
;;;;  42. cli_bootstrap_sessions make-coding-tools vs createCodingTools
;;;;  43. ai_runtime_faux faux-text/faux-thinking vs fauxText/fauxThinking
;;;;  44. http_transport parse-http-url vs WHATWG URL
;;;;  45. cli_support normalize-path-input vs normalizePath
;;;;  46. ai_support context-overflow-p vs isContextOverflow
;;;;  47. ai_crypto hmac-sha256 vs node:crypto createHmac
;;;;  48. ai_support append-grammar-json-delta vs appendGrammarToolInputJsonDelta
;;;;  49. image_runtime detect-image-mime-type vs detectSupportedImageMimeType
;;;;  50. image_runtime find-image-model vs getImageModel
;;;;  51. image_runtime format-image-dimension-note vs formatDimensionNote
;;;;  52. image_runtime get-images-api-provider vs getImagesApiProvider
;;;;  53. ai_support uuid-v7 vs uuidv7
;;;;  54. ai_capabilities split-deferred-tools vs splitDeferredTools
;;;;  55. ai_support no-models/no-key vs formatNoModelsAvailableMessage
;;;;  56. ai_capabilities make-event-stream vs EventStream
;;;;  57. cli_support reset-timings + record-timing + print-timings vs resetTimings/time/printTimings
;;;;  58. ai_capabilities resolve-http-proxy-url-for-target vs resolveHttpProxyUrlForTarget
;;;;  59. ai_capabilities register/cleanup session resources vs registerSessionResourceCleanup
;;;;  60. cli_support make-event-bus vs createEventBus
;;;;  61. cli_support provider-attribution-headers vs mergeProviderAttributionHeaders
;;;;  62. cli_support get-shell-config vs getShellConfig
;;;;  63. cli_support sanitize-binary-output vs sanitizeBinaryOutput
;;;;  64. cli_support parse-git-source vs parseGitUrl
;;;;  65. cli_support cadr-user-agent vs getPiUserAgent
;;;;  66. cli_support parse-changelog vs parseChangelog
;;;;  67. cli_models_rest parse-auth-command vs parseAuthCommand
;;;;  68. cli_sdk detect-cache-miss vs detectCacheMiss
;;;;  69. cli_sdk compute-cache-waste vs computeCacheWaste
;;;;  70. cli_sdk valid-thinking-level-p vs isValidThinkingLevel
;;;;  71. settings_load resolve-project-trusted vs resolveProjectTrusted
;;;;  72. oauth_pkce_device poll-device-authorization vs pollOAuthDeviceCodeFlow
;;;;  73. cli_extensions_install normalize-llama-server-url vs normalizeLlamaServerUrl
;;;;  74. cli_extensions_install find-hugging-face-token vs findHuggingFaceToken
;;;;  75. settings_load resolve-config-value vs resolveConfigValue
;;;; 108. settings_load http-idle-timeout-label vs formatHttpIdleTimeoutMs
;;;; 109. agent_tool_loop resolve-tool-path vs resolveToCwd
;;;; 110. agent_tool_loop detect-line-ending vs detectLineEnding
;;;; 111. cli_selectors selector-fuzzy-filter vs fuzzyFilter
;;;; 112. cli_selectors selector-delete-query-character vs Input backspace grapheme delete
;;;; 113. cli_selectors selector-frame-visible-slice vs selector viewport slice
;;;; 114. cli_selectors selector-frame-move-index vs selector wrap index
;;;; 115. cli_selectors selector-align-left-right vs session-selector header align
;;;; 116. cli_selectors selector-fit-line vs truncateToWidth + pad
;;;; 117. cli_selectors selector-border-line vs DynamicBorder render
;;;; 118. cli_selectors selector-selected-line vs theme.bg selectedBg + fit
;;;; 119. cli_selectors selector-muted-line vs theme.fg muted + fit
;;;; 120. cli_selectors selector-dim-line vs theme.fg dim + fit
;;;; 121. cli_selectors selector-modified-cursor-key vs parseKey CSI arrows
;;;; 122. cli_selectors selector-title-line vs theme accent bold Text margins
;;;; 123. cli_selectors selector-overlay-title-line vs oauth auth overlay title
;;;; 124. cli_selectors selector-input-line vs Input.render
;;;; 125. cli_selectors selector-keybinding-text vs KeybindingsManager.getKeys join
;;;; 126. cli_selectors selector-keybinding-hint vs rawKeyHint dim/muted
;;;; 127. cli_selectors session-selector-format-age vs formatSessionDate
;;;; 128. cli_selectors session-selector-record-label vs session-selector render label
;;;; 129. cli_selectors session-selector-shorten-path vs shortenPath
;;;; 130. cli_selectors search-record-position quoted phrase vs phrase token indexOf
;;;; 131. cli_selectors thread-session-records vs buildSessionTree flattenSessionTree
;;;; 132. cli_selectors session-selector-binding-label vs KeybindingsManager.getKeys first
;;;; 133. cli_selectors same-session-path-p vs canonicalizePath equality
;;;; 134. cli_selectors quoted-search-p vs session-selector-search quoted phrase predicate
;;;; 135. cli_selectors named-session-p vs session-selector-search hasSessionName
;;;; 136. cli_selectors settings-thinking-description vs settings-selector THINKING_DESCRIPTIONS
;;;; 137. cli_selectors settings-display-value vs settings-selector boolean/value formatting
;;;; 138. cli_interactive_controller parse-auto-theme-setting vs theme parseAutoThemeSetting
;;;; 139. cli_interactive_controller resolve-theme-setting vs theme resolveThemeSetting
;;;; 140. cli_selectors settings-selector-automatic-theme-setting vs ThemeSubmenu getAutomaticThemeSetting
;;;; 141. cli_selectors settings-selector-active-automatic-theme vs ThemeSubmenu getActiveAutomaticTheme
;;;; 142. cli_selectors settings-selector-cycle vs SettingsList value cycle
;;;; 143. cli_selectors settings-selector-apply-filter vs SettingsList applyFilter
;;;; 144. cli_selectors tree-selector-entry-filtered-p vs tree-selector filter modes
;;;; 145. cli_selectors tree-selector-query-matches-p vs tree-selector search tokens
;;;;  76. cli_print_rpc rpc-clamp-thinking-level vs clampThinkingLevel
;;;;  77. oauth_pkce_device read-auth-credential vs ReadOnlyAuthStorage.read
;;;;  78. oauth_pkce_device github-copilot-base-url vs githubCopilotOAuth.toAuth
;;;;  79. cli_sdk session-manager-list vs SessionManager.list
;;;;  80. oauth_pkce_device materialize-cloudflare-url vs resolveCloudflareModel
;;;;  81. oauth_pkce_device normalize-radius-gateway vs normalizeRadiusGatewayUrl
;;;;  82. cli_interactive_controller clipboard-wayland-p vs isWaylandSession
;;;;  83. evals_harness derive-eval-group-key vs deriveEvalGroupKey
;;;;  94. evals_harness persist-eval-artifact-references vs persistEvalArtifactReferences
;;;; 106. evals_harness format-harness-comparison-report vs formatHarnessComparisonReport
;;;;  84. cli_extensions_install llama-provider-set-catalog vs createLlamaProvider.setCatalog
;;;;  85. cli_interactive_controller format-cwd-for-footer vs formatCwdForFooter
;;;; 107. cli_interactive_controller tui-auth-type-label vs formatAuthSelectorProviderType
;;;;  86. cli_sdk create-agent-session vs createAgentSession
;;;;  87. cli_sdk create-agent-session-services vs createAgentSessionServices
;;;;  88. cli_sdk sdk-model-runtime-providers vs ModelRuntime.getProviders
;;;;  89. cli_print_rpc rpc-session-stats vs AgentSession.getSessionStats
;;;;  90. oauth_pkce_device github-copilot-oauth-to-auth vs githubCopilotOAuth.toAuth
;;;;  91. tui_mermaid gm-render vs grok-mermaid render
;;;;  92. tui_mermaid transform-mermaid-markdown vs createMermaidMarkdownTransformer
;;;;  93. cli_selectors filter-and-sort-sessions vs filterAndSortSessions
;;;;  95. cli_selectors format-key-text vs formatKeyText
;;;;  94. websocket_stream stream-chat websocket vs openai-codex-responses stream
;;;;
;;;; usage (via scripts/goal20-paired-paths.sh, or directly):
;;;;   CADR_BENCH_PROJECT_DIRECTORY=... QUICKLISP_SETUP=... \
;;;;     sbcl --script scripts/goal20-paired-paths.lisp [--quick] [--output PATH]

(require :asdf)

(defparameter cl-user::*cadr-bench-project-directory*
  (uiop:ensure-directory-pathname
   (pathname
    (or (uiop:getenv "CADR_BENCH_PROJECT_DIRECTORY")
        (error "CADR_BENCH_PROJECT_DIRECTORY is not set")))))

(let ((*standard-output* *error-output*)
      (*load-verbose* nil)
      (*compile-verbose* nil))
  (load
   (or (uiop:getenv "QUICKLISP_SETUP")
       (error "QUICKLISP_SETUP is not set")))
  (dolist (name '("cadr-core.asd"
                  "cadr-ai.asd"
                  "cadr-agent.asd"
                  "cadr-tui.asd"
                  "cadr-cli.asd"
                  "cadr-protocol.asd"
                  "cadr-evals.asd"))
    (asdf:load-asd
     (truename
      (merge-pathnames
       name cl-user::*cadr-bench-project-directory*))))
  (asdf:load-system "cadr-cli" :verbose nil)
  (asdf:load-system "cadr-protocol" :verbose nil)
  (asdf:load-system "cadr-evals" :verbose nil))

(defpackage #:cadr-goal20-paired-paths
  (:use #:cl))

(in-package #:cadr-goal20-paired-paths)

(defparameter *samples* 5)
(defparameter *warmups* 1)
(defparameter *quick-p* nil)
(defparameter *output-path* "-")
(defparameter *keep-journal-path* nil)
(defparameter *sink* nil)

;;; Repetition counts are per metric so that every inner loop lasts long
;;; enough to clear timer granularity without making the whole run slow.
;;; scripts/goal20-paired-paths.mjs carries the same table and the pairing
;;; gate rejects a run whose counts disagree, because a ratio between
;;; differently sized batches is not a comparison.
(defparameter *repetitions*
  '(("cli_dispatch.argv_parse" . 2000)
    ("cli_dispatch.help_render" . 500)
    ("cli_dispatch.list_models_registry" . 20)
    ("cli_dispatch.list_models_render" . 100)
    ("provider_stream.stream_roundtrip" . 10)
    ("provider_anthropic.stream_roundtrip" . 10)
    ("provider_google.stream_roundtrip" . 10)
    ("provider_bedrock.stream_roundtrip" . 10)
    ("provider_mistral.stream_roundtrip" . 10)
    ("provider_openai_responses.stream_roundtrip" . 10)
    ("provider_azure_openai.stream_roundtrip" . 10)
    ("provider_vertex.stream_roundtrip" . 10)
    ("provider_codex.stream_roundtrip" . 10)
    ("provider_pi_messages.stream_roundtrip" . 10)
    ("cli_settings.create" . 5)
    ("settings_load.project_trust" . 20)
    ("settings_load.config_value" . 50)
    ("settings_load.http_idle" . 50)
    ("resource_loader.reload" . 3)
    ("package_manager.resolve" . 5)
    ("session_discovery.header_probe" . 20)
    ("session_export_html.to_html" . 3)
    ("protocol_cbor.roundtrip" . 50)
    ("agent_schema.validate_ok_fail" . 50)
    ("harness_storage.open_walk" . 3)
    ("protocol_codec.roundtrip" . 50)
    ("agent_proxy.stream_roundtrip" . 10)
    ("oauth_pkce.challenge_urls" . 50)
    ("oauth_pkce_device.poll" . 50)
    ("oauth_pkce_device.auth_json" . 50)
    ("oauth_pkce_device.copilot_url" . 50)
    ("oauth_pkce_device.cloudflare_url" . 50)
    ("oauth_pkce_device.radius_gateway" . 50)
    ("oauth_pkce_device.copilot_auth" . 50)
    ("cli_extensions_install.llama_url" . 50)
    ("cli_extensions_install.hf_token" . 50)
    ("cli_extensions_install.llama_catalog" . 50)
    ("evals_harness.summarize" . 20)
    ("evals_harness.group_key" . 50)
    ("evals_harness.artifact_persist" . 3)
    ("evals_harness.format" . 20)
    ("ai_crypto_model_data.manifest" . 50)
    ("ai_crypto.hmac" . 50)
    ("cli_models_rest.pattern_match" . 50)
    ("cli_models_rest.auth_command" . 50)
    ("image_runtime.dimensions" . 50)
    ("image_runtime.mime_type" . 50)
    ("image_runtime.lookup" . 50)
    ("image_runtime.dimension_note" . 50)
    ("image_runtime.api_provider" . 50)
    ("cli_print_rpc.jsonl_line" . 50)
    ("cli_print_rpc.jsonl_read" . 50)
    ("cli_print_rpc.clamp_thinking" . 50)
    ("cli_print_rpc.session_stats" . 20)
    ("tui_latex.render" . 20)
    ("tui_mermaid.render" . 20)
    ("tui_mermaid.source_box" . 20)
    ("tui_mermaid.transform" . 20)
    ("tui_editor_helpers.fuzzy_match" . 50)
    ("tui_theme_overlay.osc11_bg" . 50)
    ("ai_support.estimate_text" . 50)
    ("ai_support.context_overflow" . 50)
    ("ai_support.grammar_delta" . 50)
    ("ai_support.uuid_v7" . 50)
    ("ai_support.auth_guidance" . 50)
    ("tui_select_settings_loaders.filter" . 50)
    ("tui_word_navigation.step" . 50)
    ("tui_overlay.composite_line" . 50)
    ("tui_kill_ring.push_peek" . 50)
    ("tui_undo_stack.push_pop" . 50)
    ("tui_autocomplete.suggest_apply" . 50)
    ("tui_keybindings.resolve_match" . 50)
    ("tui_stdin_buffer.process" . 50)
    ("tui_input_component.edit" . 50)
    ("tui_native_modifiers.pressed" . 50)
    ("tui_settings_list.apply_filter" . 50)
    ("ai_capabilities.short_hash" . 50)
    ("ai_capabilities.deferred_tools" . 50)
    ("ai_capabilities.event_stream" . 50)
    ("ai_capabilities.http_proxy" . 50)
    ("ai_capabilities.session_resources" . 50)
    ("cli_support.strip_ansi" . 50)
    ("cli_support.normalize_path" . 50)
    ("cli_support.timings" . 50)
    ("cli_support.event_bus" . 50)
    ("cli_support.attribution_headers" . 50)
    ("cli_support.shell_config" . 50)
    ("cli_support.sanitize_output" . 50)
    ("cli_support.git_source" . 50)
    ("cli_support.user_agent" . 50)
    ("cli_support.parse_changelog" . 50)
    ("cli_support.experimental" . 50)
    ("cli_interactive_controller.decode_entity" . 50)
    ("cli_interactive_controller.wayland" . 50)
    ("cli_interactive_controller.cwd_footer" . 50)
    ("cli_interactive_controller.auth_type" . 50)
    ("cli_interactive_controller.parse_auto_theme" . 50)
    ("cli_interactive_controller.resolve_theme" . 50)
    ("cli_selectors.session_search" . 50)
    ("cli_selectors.key_text" . 50)
    ("cli_selectors.fuzzy_filter" . 50)
    ("cli_selectors.delete_query" . 50)
    ("cli_selectors.visible_slice" . 50)
    ("cli_selectors.move_index" . 50)
    ("cli_selectors.align_left_right" . 50)
    ("cli_selectors.fit_line" . 50)
    ("cli_selectors.border_line" . 50)
    ("cli_selectors.selected_line" . 50)
    ("cli_selectors.muted_line" . 50)
    ("cli_selectors.dim_line" . 50)
    ("cli_selectors.modified_cursor_key" . 50)
    ("cli_selectors.title_line" . 50)
    ("cli_selectors.overlay_title_line" . 50)
    ("cli_selectors.input_line" . 50)
    ("cli_selectors.keybinding_text" . 50)
    ("cli_selectors.keybinding_hint" . 50)
    ("cli_selectors.session_format_age" . 50)
    ("cli_selectors.session_record_label" . 50)
    ("cli_selectors.session_shorten_path" . 50)
    ("cli_selectors.session_quoted_search" . 50)
    ("cli_selectors.session_thread_records" . 50)
    ("cli_selectors.session_binding_label" . 50)
    ("cli_selectors.session_same_path" . 50)
    ("cli_selectors.session_quoted_p" . 50)
    ("cli_selectors.session_named_p" . 50)
    ("cli_selectors.settings_thinking_description" . 50)
    ("cli_selectors.settings_display_value" . 50)
    ("cli_selectors.settings_automatic_theme_setting" . 50)
    ("cli_selectors.settings_active_automatic_theme" . 50)
    ("cli_selectors.settings_cycle" . 50)
    ("cli_selectors.settings_apply_filter" . 50)
    ("cli_selectors.tree_entry_filtered" . 50)
    ("cli_selectors.tree_query_matches" . 50)
    ("cli_selectors.tree_entry_search_text" . 50)
    ("cli_selectors.tree_settings_entry_p" . 50)
    ("cli_selectors.tree_normalize_display_text" . 50)
    ("cli_selectors.tree_status_labels" . 50)
    ("cli_selectors.tree_shorten_path" . 50)
    ("cli_selectors.tree_foldable_p" . 50)
    ("cli_selectors.tree_tool_argument" . 50)
    ("cli_selectors.tree_cycle_filter" . 50)
    ("cli_selectors.tree_format_label_timestamp" . 50)
    ("cli_selectors.tree_iso_timestamp" . 50)
    ("cli_selectors.tree_format_tool_call" . 50)
    ("cli_selectors.tree_entry_display_text" . 50)
    ("cli_selectors.tree_prefix" . 50)
    ("cli_selectors.tree_visual_nodes" . 50)
    ("cli_selectors.tree_horizontal_viewport" . 50)
    ("cli_selectors.tree_help_keys" . 50)
    ("cli_selectors.tree_help_key" . 50)
    ("cli_selectors.tree_app_key_p" . 50)
    ("cli_selectors.tree_help_lines" . 50)
    ("cli_selectors.tree_active_path" . 50)
    ("cli_selectors.tree_nearest_visible_id" . 50)
    ("cli_selectors.tree_prioritize_active" . 50)
    ("cli_selectors.tree_entry_map" . 50)
    ("cli_selectors.tree_order_entries" . 50)
    ("cli_selectors.tree_rebuild_visible_maps" . 50)
    ("cli_selectors.tree_apply_filter" . 50)
    ("cli_selectors.tree_render_lines" . 20)
    ("cli_selectors.tree_move" . 50)
    ("cli_selectors.tree_fold_or_up" . 50)
    ("cli_selectors.tree_unfold_or_down" . 50)
    ("cli_selectors.tree_branch_segment_id" . 50)
    ("cli_selectors.tree_set_query" . 50)
    ("cli_selectors.tree_set_filter" . 50)
    ("cli_selectors.tree_copy_selected" . 50)
    ("cli_selectors.tree_toggle_label_timestamps" . 50)
    ("cli_selectors.tree_start_label_edit" . 50)
    ("cli_selectors.tree_confirm_label" . 50)
    ("cli_selectors.tree_cancel_label" . 50)
    ("cli_selectors.tree_handle_raw_input" . 50)
    ("cli_selectors.tree_handle_event" . 50)
    ("cli_selectors.tree_handle_label_event" . 50)
    ("cli_selectors.tree_selected_entry" . 50)
    ("cli_selectors.tree_selected_id" . 50)
    ("cli_selectors.tree_select_id" . 50)
    ("cli_selectors.tree_visible_ids" . 50)
    ("cli_selectors.project_trust_options" . 50)
    ("cli_selectors.trust_selector_selection" . 50)
    ("cli_selectors.trust_decision_description" . 50)
    ("cli_selectors.trust_selector_move" . 50)
    ("cli_selectors.trust_selector_handle_event" . 50)
    ("cli_selectors.trust_selector_handle_raw_input" . 50)
    ("cli_selectors.trust_selector_ui_state" . 50)
    ("cli_selectors.oauth_option_status_label" . 50)
    ("cli_selectors.oauth_option_status_rendered" . 50)
    ("cli_selectors.credential_entry_auth_type" . 50)
    ("cli_selectors.oauth_environment_source_p" . 50)
    ("cli_selectors.oauth_selector_selection" . 50)
    ("cli_selectors.oauth_selector_apply_filter" . 50)
    ("cli_selectors.oauth_selector_handle_event" . 50)
    ("cli_selectors.oauth_selector_handle_raw_input" . 50)
    ("cli_selectors.oauth_selector_search_text" . 50)
    ("cli_selectors.login_auth_type_route" . 50)
    ("cli_selectors.login_provider_options" . 50)
    ("cli_selectors.logout_provider_options" . 50)
    ("cli_selectors.login_method_selector_handle_event" . 50)
    ("cli_selectors.oauth_selector_move" . 50)
    ("cli_selectors.api_key_input_state_handle_event" . 50)
    ("cli_selectors.login_method_selector_ui_state" . 50)
    ("websocket_stream.stream_roundtrip" . 10)
    ("cli_sdk.version_newer" . 50)
    ("cli_sdk.cache_miss" . 50)
    ("cli_sdk.cache_waste" . 50)
    ("cli_sdk.thinking_level" . 50)
    ("cli_sdk.session_list" . 5)
    ("cli_sdk.agent_session" . 5)
    ("cli_sdk.session_services" . 5)
    ("cli_sdk.model_runtime" . 5)
    ("provider_registry_defs.lookup" . 50)
    ("skill_prompt_load.build_prompt" . 50)
    ("cli_bootstrap_sessions.coding_tools" . 50)
    ("ai_runtime_faux.blocks" . 50)
    ("http_transport.parse_url" . 50)
    ("session_pipeline.session_load" . 3)
    ("session_pipeline.context_walk" . 50)
    ("storage_journal.journal_read" . 5)
    ("storage_journal.journal_append" . 3)
    ("sqlite_session.open_walk" . 3)
    ("tool_read.text_file" . 5)
    ("tool_grep.context_file" . 5)
    ("agent_tool_loop.roundtrip" . 3)
    ("agent_tool_loop.tool_path" . 50)
    ("agent_tool_loop.line_ending" . 50)
    ("session_compact.compact" . 3)
    ("text_truncation.truncate_head" . 50)
    ("text_truncation.truncate_tail" . 50)
    ("render_slicing.slice_ansi_clip" . 200)
    ("render_slicing.slice_plain_clip" . 200)))

(defparameter *quick-divisor* 20)
(defparameter *journal-append-entry-count* 128)

(defun parse-positive-integer (text option)
  (let ((value (parse-integer text :junk-allowed t)))
    (unless (and value (plusp value))
      (error "~A requires a positive integer" option))
    value))

(defun parse-options ()
  (let ((arguments (uiop:command-line-arguments)))
    (loop while arguments
          for argument = (pop arguments)
          do
          (cond
            ((string= argument "--quick")
             (setf *quick-p* t
                   *samples* 1
                   *warmups* 0))
            ((string= argument "--samples")
             (unless arguments
               (error "--samples requires a value"))
             (setf *samples*
                   (parse-positive-integer (pop arguments) argument)))
            ((string= argument "--warmups")
             (unless arguments
               (error "--warmups requires a value"))
             (setf *warmups*
                   (parse-integer (pop arguments))))
            ((string= argument "--output")
             (unless arguments
               (error "--output requires a value"))
             (setf *output-path* (pop arguments)))
            ((string= argument "--keep-journal")
             (unless arguments
               (error "--keep-journal requires a value"))
             (setf *keep-journal-path* (pop arguments)))
            (t
             (error "Unknown option: ~A" argument))))))

(defun repetitions-for (name)
  (let ((base (cdr (assoc name *repetitions* :test #'string=))))
    (unless base
      (error "No repetition count for ~A" name))
    (if *quick-p*
        (max 1 (floor base *quick-divisor*))
        base)))

;;; ---------------------------------------------------------------------
;;; Statistics: same shape as scripts/goal11-bench.lisp
;;; ---------------------------------------------------------------------

(defun json-object (&rest pairs)
  (apply #'cadr-ai::json-object pairs))

(defun json-array (values)
  (coerce values 'vector))

(defun median (values)
  (let* ((sorted (sort (copy-list values) #'<))
         (count (length sorted))
         (middle (floor count 2)))
    (if (oddp count)
        (coerce (nth middle sorted) 'double-float)
        (/ (+ (nth (1- middle) sorted)
              (nth middle sorted))
           2d0))))

(defun median-absolute-deviation (values center)
  (median
   (mapcar (lambda (value) (abs (- value center))) values)))

;;; These pairs include microsecond-scale operations, and
;;; get-internal-real-time is quantised to a scheduler tick on some hosts
;;; (~4ms under WSL2), which would report 0us for an argv parse and turn every
;;; ratio into noise.  CLOCK_MONOTONIC matches what pi's
;;; process.hrtime.bigint() reads, so both halves of a pair time themselves
;;; off the same kind of clock.
(defun monotonic-nanoseconds ()
  (multiple-value-bind (seconds nanoseconds)
      (sb-unix:clock-gettime sb-unix:clock-monotonic)
    (+ (* seconds 1000000000) nanoseconds)))

(defun elapsed-microseconds (start end)
  (/ (- end start) 1000d0))

(defun measure-batch (function repetitions)
  (sb-ext:gc :full t)
  (let ((started-at (monotonic-nanoseconds)))
    (dotimes (index repetitions)
      (declare (ignore index))
      (setf *sink* (funcall function)))
    (/ (elapsed-microseconds started-at (monotonic-nanoseconds))
       repetitions)))

(defun collect (name prepare)
  (let ((repetitions (repetitions-for name)))
    (dotimes (index *warmups*)
      (declare (ignore index))
      (measure-batch (funcall prepare) repetitions))
    (let* ((times
             (loop repeat *samples*
                   collect (measure-batch (funcall prepare) repetitions)))
           (center (median times)))
      (json-object
       "mad_us" (median-absolute-deviation times center)
       "median_us" center
       "repetitions" repetitions
       "samples_us" (json-array times)))))

;;; ---------------------------------------------------------------------
;;; Fixtures
;;; ---------------------------------------------------------------------

(defparameter *fixture-directory*
  (merge-pathnames
   "test/fixtures/goal20-paired-paths/"
   cl-user::*cadr-bench-project-directory*))

(defparameter *fixture-names*
  '("auth.json" "cli-argv.json" "manifest.json" "models.json"
    "anthropic-messages.sse" "google-generative-ai.sse"
    "bedrock-converse-stream.bin" "mistral-conversations.sse"
    "openai-responses.sse" "azure-openai-responses.sse"
    "google-vertex.sse" "vertex-adc.json"
    "openai-codex-responses.sse" "pi-messages.sse"
    "settings-global.json" "settings-project.json"
    "resource-skill-global.md" "resource-skill-project.md"
    "resource-prompt-global.md" "resource-prompt-project.md"
    "resource-agents.md" "resource-system.md"
    "package-manifest.json" "package-skill.md" "package-prompt.md"
    "package-theme.json" "package-extension.js"
    "package-settings-global.json" "package-settings-project.json"
    "openai-completions.sse" "provider-context.json" "session.jsonl"))

(defun read-file-octets (path)
  (with-open-file (stream path
                          :direction :input
                          :element-type '(unsigned-byte 8))
    (let ((octets
            (make-array (file-length stream)
                        :element-type '(unsigned-byte 8))))
      (read-sequence octets stream)
      octets)))

(defun file-sha256 (path)
  (cadr-ai::octets-hex
   (cadr-ai::sha256-bytes (read-file-octets path))))

(defun fixture-path (name)
  (merge-pathnames name *fixture-directory*))

(defun fixture-digests-json ()
  (apply #'json-object
         (loop for name in *fixture-names*
               append (list name (file-sha256 (fixture-path name))))))

(defun read-fixture-json (name)
  (cadr-ai::parse-json
   (uiop:read-file-string (fixture-path name)
                          :external-format :utf-8)))

;;; The write pair's cwd comes from the manifest so both sides read one
;;; declared value.  create-session canonicalises cwd through TRUENAME, so the
;;; directory has to exist and pi has to pass the same resolved path for the
;;; header bytes the two sides write to match.
(defun journal-cwd ()
  (let ((declared
          (cadr-ai::json-get
           (cadr-ai::json-get (read-fixture-json "manifest.json")
                              "parameters")
           "journal_cwd")))
    (ensure-directories-exist
     (uiop:ensure-directory-pathname declared))
    declared))

(defparameter *scratch-directory*
  (uiop:ensure-directory-pathname
   (format nil "/tmp/goal20-cadr-paired-~D" (sb-posix:getpid))))

;;; Provider keys in the operator's environment make extra models "available"
;;; and would silently change the observed model set from host to host, so the
;;; fixture auth.json is the only credential either side can see.
(defparameter *scrubbed-environment-suffixes*
  '("API_KEY" "AUTH_TOKEN" "OAUTH_TOKEN" "ACCESS_TOKEN"))

(defun scrubbed-environment-name-p (name)
  (some (lambda (suffix)
          (and (uiop:string-suffix-p name suffix)
               (or (= (length name) (length suffix))
                   (char= #\_
                          (char name
                                (- (length name)
                                   (length suffix)
                                   1))))))
        *scrubbed-environment-suffixes*))

(defun scrub-provider-environment ()
  (let ((removed nil))
    (dolist (entry (sb-ext:posix-environ))
      (let* ((separator (position #\= entry))
             (name (if separator (subseq entry 0 separator) entry)))
        (when (scrubbed-environment-name-p name)
          (sb-posix:unsetenv name)
          (push name removed))))
    (json-array (sort removed #'string<))))

;;; A staged agent directory keeps the fixture tree read-only and gives the
;;; CLI dispatch pair the same models.json and auth.json bytes pi reads.
;;; The staged digests go into the report so the pairing gate can prove the
;;; two sides read identical bytes rather than take it on faith.
(defparameter *agent-directory*
  (merge-pathnames "agent/" *scratch-directory*))

(defun stage-agent-directory ()
  (ensure-directories-exist *agent-directory*)
  (dolist (name '("models.json" "auth.json"))
    (uiop:copy-file (fixture-path name)
                    (merge-pathnames name *agent-directory*)))
  (sb-posix:setenv "CADR_CODING_AGENT_DIR"
                   (namestring *agent-directory*)
                   1)
  (apply #'json-object
         (loop for name in '("models.json" "auth.json")
               append
               (list name
                     (file-sha256
                      (merge-pathnames name *agent-directory*))))))

;;; ---------------------------------------------------------------------
;;; Pair 1: CLI startup / command dispatch
;;; ---------------------------------------------------------------------

(defun counting-stream ()
  ;; Both sides render into a sink that only counts, so neither pays
  ;; terminal I/O and neither can win by writing less.
  (make-string-output-stream))

(defun argv-fixture (key)
  (let ((value (cadr-ai::json-get (read-fixture-json "cli-argv.json") key)))
    (coerce value 'list)))

(defun cli-argv-json (argv)
  (json-array argv))

;;; Same construction print-cli-models uses, credential store included: a
;;; models.json provider outside the built-in catalog is only "available" when
;;; the registry can read auth.json, which is also what pi's
;;; ModelRuntime.create does with its authPath.
(defun list-models-registry ()
  (cadr-cli::make-model-registry
   :path (cadr-core:agent-models-path)
   :credentials
   (cadr-cli:make-file-auth-storage
    (cadr-cli:default-auth-path))))

(defun measure-cli-dispatch (staged-digests)
  (declare (ignore staged-digests))
  (let* ((parse-argv (argv-fixture "parse"))
         (list-argv (argv-fixture "list_models"))
         (pattern (second list-argv))
         (parsed (cadr-cli::parse-cli-arguments parse-argv))
         (help-characters
           (let ((stream (counting-stream)))
             (cadr-cli::print-cli-usage stream)
             (length (get-output-stream-string stream))))
         (registry (list-models-registry))
         (available
           (cadr-cli::model-registry-available-models registry))
         (render-shape
           (let ((stream (counting-stream)))
             (cadr-cli::print-cli-models pattern stream)
             (let ((text (get-output-stream-string stream)))
               (list (length text)
                     (count #\Newline text))))))
    (json-object
     "argv" (cli-argv-json parse-argv)
     "argv_parse"
     (collect "cli_dispatch.argv_parse"
              (lambda ()
                (lambda ()
                  (cadr-cli::parse-cli-arguments parse-argv))))
     "help_render"
     (collect "cli_dispatch.help_render"
              (lambda ()
                (let ((stream (make-broadcast-stream)))
                  (lambda ()
                    (cadr-cli::print-cli-usage stream)))))
     "list_models_registry"
     (collect "cli_dispatch.list_models_registry"
              (lambda ()
                (lambda ()
                  (list-models-registry))))
     "list_models_render"
     (collect "cli_dispatch.list_models_render"
              (lambda ()
                (let ((stream (make-broadcast-stream)))
                  (lambda ()
                    (cadr-cli::print-cli-models pattern stream)))))
     "observed"
     (json-object
      "available_model_count" (length available)
      "available_providers"
      (json-array
       (sort
        (remove-duplicates
         (mapcar
          (lambda (model)
            (string-downcase
             (symbol-name (cadr-ai:model-provider model))))
          available)
         :test #'string=)
        #'string<))
      "help_characters" help-characters
      "list_models_characters" (first render-shape)
      "list_models_lines" (second render-shape)
      "parsed_diagnostic_count"
      (length (cadr-cli::cli-arguments-diagnostics parsed))
      "parsed_exclude_tools"
      (json-array (cadr-cli::cli-arguments-exclude-tools parsed))
      "parsed_file_args"
      (json-array (cadr-cli::cli-arguments-file-arguments parsed))
      "parsed_list_models"
      (cadr-cli::cli-arguments-list-models parsed)
      "parsed_messages"
      (json-array (cadr-cli::cli-arguments-messages parsed))
      "parsed_model" (cadr-cli::cli-arguments-model parsed)
      "parsed_provider" (cadr-cli::cli-arguments-provider parsed)
      "parsed_thinking"
      (let ((level (cadr-cli::cli-arguments-thinking parsed)))
        (if (symbolp level)
            (and level (string-downcase (symbol-name level)))
            level))
      "parsed_tools"
      (json-array (cadr-cli::cli-arguments-tools parsed))
      "parsed_unknown_flag_count"
      (hash-table-count
       (cadr-cli::cli-arguments-unknown-flags parsed))))))

;;; ---------------------------------------------------------------------
;;; Pair 2: provider request assembly + response parse
;;; ---------------------------------------------------------------------

(defparameter *provider-api-key* "goal20-paired-paths-not-a-real-key")

(defun provider-model ()
  (cadr-ai:make-model
   :id "goal20-paired-1"
   :name "Goal 20 Paired 1"
   :api :openai-completions
   :provider :goal20faux
   :base-url "http://127.0.0.1:1/v1"
   :reasoning-p t
   :supports-images-p t
   :context-window 128000
   :max-tokens 16384))

(defun provider-tool (object)
  (cadr-ai:make-tool
   :name (cadr-ai::json-get object "name")
   :description (cadr-ai::json-get object "description")
   :parameters (cadr-ai::json-get object "parameters")))

(defun provider-context ()
  (let ((fixture (read-fixture-json "provider-context.json")))
    (cadr-ai:make-context
     :system-prompt (cadr-ai::json-get fixture "systemPrompt")
     :messages
     (map 'list
          #'cadr-agent::message-from-json
          (cadr-ai::json-get fixture "messages"))
     :tools
     (map 'list
          #'provider-tool
          (cadr-ai::json-get fixture "tools")))))

;;; cadr's documented transport seam is cadr-ai:*http-request-function*, the
;;; same one the provider test suite binds to replay recorded SSE fixtures
;;; (test/cadr-ai/provider-streams-test.lisp).  pi's is
;;; ProviderRequestOptions.fetch.  Both replace only the socket: request
;;; assembly, status handling, SSE decoding, event reduction, and final
;;; message assembly all stay on the production path, and both re-read the
;;; fixture from the filesystem per call so neither side gets a free ride on
;;; a pre-parsed buffer.
(defun fixture-http-request-function ()
  (lambda (url &rest arguments)
    (declare (ignore url arguments))
    (values
     (open (fixture-path "openai-completions.sse")
           :direction :input
           :element-type '(unsigned-byte 8))
     200
     '(("content-type" . "text/event-stream")))))

(defun run-provider-stream (provider model context collect-events-p)
  (let ((events nil)
        (payload nil))
    (let ((cadr-ai:*http-request-function*
            (fixture-http-request-function)))
      (let ((message
              (cadr-ai::stream-chat
               provider model context
               (if collect-events-p
                   (lambda (event) (push event events))
                   (lambda (event) (declare (ignore event)) nil))
               :on-payload
               (lambda (value model)
                 (declare (ignore model))
                 (setf payload value)
                 nil))))
        (values message (nreverse events) payload)))))

(defun count-names-json (names)
  (let ((counts (make-hash-table :test #'equal)))
    (dolist (name names)
      (incf (gethash name counts 0)))
    (apply #'json-object
           (loop for name in (sort (loop for key being the hash-keys of counts
                                         collect key)
                                   #'string<)
                 append (list name (gethash name counts))))))

(defun content-block-type-name (block)
  (etypecase block
    (cadr-ai:text-content "text")
    (cadr-ai:thinking-content "thinking")
    (cadr-ai:tool-call "toolCall")
    (cadr-ai:image-content "image")))

(defun measure-provider-stream ()
  (let ((provider
          (cadr-ai:make-openai-completions-provider
           :api-key *provider-api-key*
           :provider-id :goal20faux))
        (model (provider-model))
        (context (provider-context)))
    (multiple-value-bind (message events payload)
        (run-provider-stream provider model context t)
      (unless (eq :tool-use (cadr-ai:assistant-message-stop-reason message))
        (error "fixture stream produced stop reason ~S"
               (cadr-ai:assistant-message-stop-reason message)))
      (let* ((blocks (cadr-ai:assistant-message-content message))
             (text
               (apply #'concatenate 'string
                      (mapcar #'cadr-ai:text-content-text
                              (remove-if-not
                               (lambda (block)
                                 (typep block 'cadr-ai:text-content))
                               blocks))))
             ;; print.lisp json-event-type-name is the wire spelling the JSON
             ;; mode already emits, so the paired event kinds are compared in
             ;; pi's vocabulary without inventing a second map.
             (event-names
               (mapcar
                (lambda (event)
                  (cadr-cli::json-event-type-name
                   (cadr-ai:stream-event-type event)))
                events))
             (event-kinds
               (sort (remove-duplicates event-names :test #'string=)
                     #'string<)))
        (json-object
         "observed"
         (json-object
          "content_block_types"
          (json-array (mapcar #'content-block-type-name blocks))
          "event_count" (length events)
          "event_kind_counts" (count-names-json event-names)
          "event_kinds" (json-array event-kinds)
          "payload_keys"
          (json-array
           (sort (mapcar #'car (cadr-ai::json-object-alist payload))
                 #'string<))
          "payload_message_count"
          (length (cadr-ai::json-get payload "messages"))
          "payload_stream"
          (eq t (cadr-ai::json-get payload "stream"))
          "payload_tool_count"
          (length (or (cadr-ai::json-get payload "tools") #()))
          "stop_reason" "toolUse"
          "text_characters" (length text)
          "tool_call_count"
          (count-if (lambda (block) (typep block 'cadr-ai:tool-call))
                    blocks)
          "usage_input"
          (cadr-ai:usage-input
           (cadr-ai:assistant-message-usage message))
          "usage_output"
          (cadr-ai:usage-output
           (cadr-ai:assistant-message-usage message)))
         "stream_roundtrip"
         (collect "provider_stream.stream_roundtrip"
                  (lambda ()
                    (lambda ()
                      (run-provider-stream
                       provider model context nil)))))))))

(defun anthropic-model ()
  (cadr-ai:make-model
   :id "goal20-paired-1"
   :name "Goal 20 Paired 1"
   :api :anthropic-messages
   :provider :anthropic
   :base-url "https://api.anthropic.com"
   :reasoning-p nil
   :supports-images-p t
   :context-window 128000
   :max-tokens 16384))

(defun anthropic-http-request-function ()
  (lambda (url &rest arguments)
    (declare (ignore url arguments))
    (values
     (open (fixture-path "anthropic-messages.sse")
           :direction :input
           :element-type '(unsigned-byte 8))
     200
     '(("content-type" . "text/event-stream")))))

(defun run-provider-anthropic (provider model context collect-events-p)
  (let ((events nil)
        (payload nil))
    (let ((cadr-ai:*http-request-function*
            (anthropic-http-request-function)))
      (let ((message
              (cadr-ai::stream-chat
               provider model context
               (if collect-events-p
                   (lambda (event) (push event events))
                   (lambda (event) (declare (ignore event)) nil))
               :on-payload
               (lambda (value model)
                 (declare (ignore model))
                 (setf payload value)
                 nil))))
        (values message (nreverse events) payload)))))

(defun measure-provider-anthropic ()
  (let ((provider
          (cadr-ai:make-anthropic-provider
           :api-key *provider-api-key*
           :provider-id :anthropic))
        (model (anthropic-model))
        (context (provider-context)))
    (multiple-value-bind (message events payload)
        (run-provider-anthropic provider model context t)
      (unless (eq :tool-use (cadr-ai:assistant-message-stop-reason message))
        (error "anthropic fixture stream produced stop reason ~S"
               (cadr-ai:assistant-message-stop-reason message)))
      (let* ((blocks (cadr-ai:assistant-message-content message))
             (text
               (apply #'concatenate 'string
                      (mapcar #'cadr-ai:text-content-text
                              (remove-if-not
                               (lambda (block)
                                 (typep block 'cadr-ai:text-content))
                               blocks)))))
        (json-object
         "observed"
         (json-object
          "content_block_types"
          (json-array (mapcar #'content-block-type-name blocks))
          "stop_reason" "toolUse"
          "text_characters" (length text)
          "tool_call_count"
          (count-if (lambda (block) (typep block 'cadr-ai:tool-call))
                    blocks)
          "usage_input"
          (cadr-ai:usage-input
           (cadr-ai:assistant-message-usage message))
          "usage_output"
          (cadr-ai:usage-output
           (cadr-ai:assistant-message-usage message))
          "payload_stream"
          (eq t (cadr-ai::json-get payload "stream"))
          "payload_tool_count"
          (length (or (cadr-ai::json-get payload "tools") #())))
         "stream_roundtrip"
         (collect "provider_anthropic.stream_roundtrip"
                  (lambda ()
                    (lambda ()
                      (run-provider-anthropic
                       provider model context nil)))))))))

(defun google-model ()
  (cadr-ai:make-model
   :id "gemini-3.6-flash"
   :name "Goal 20 Google"
   :api :google-generative-ai
   :provider :google
   :base-url "https://generativelanguage.googleapis.com/v1beta"
   :reasoning-p nil
   :supports-images-p t
   :context-window 128000
   :max-tokens 16384))

(defun google-http-request-function ()
  (lambda (url &rest arguments)
    (declare (ignore url arguments))
    (values
     (open (fixture-path "google-generative-ai.sse")
           :direction :input
           :element-type '(unsigned-byte 8))
     200
     '(("content-type" . "text/event-stream")))))

(defun run-provider-google (provider model context collect-events-p)
  (let ((events nil)
        (payload nil))
    (let ((cadr-ai:*http-request-function*
            (google-http-request-function)))
      (let ((message
              (cadr-ai::stream-chat
               provider model context
               (if collect-events-p
                   (lambda (event) (push event events))
                   (lambda (event) (declare (ignore event)) nil))
               :on-payload
               (lambda (value model)
                 (declare (ignore model))
                 (setf payload value)
                 nil))))
        (values message (nreverse events) payload)))))

(defun measure-provider-google ()
  (let ((provider
          (cadr-ai:make-google-provider
           :api-key *provider-api-key*
           :provider-id :google))
        (model (google-model))
        (context (provider-context)))
    (multiple-value-bind (message events payload)
        (run-provider-google provider model context t)
      (declare (ignore events))
      (unless (eq :tool-use (cadr-ai:assistant-message-stop-reason message))
        (error "google fixture stream produced stop reason ~S"
               (cadr-ai:assistant-message-stop-reason message)))
      (let* ((blocks (cadr-ai:assistant-message-content message))
             (text
               (apply #'concatenate 'string
                      (mapcar #'cadr-ai:text-content-text
                              (remove-if-not
                               (lambda (block)
                                 (typep block 'cadr-ai:text-content))
                               blocks))))
             (tools (cadr-ai::json-get payload "tools")))
        (json-object
         "observed"
         (json-object
          "content_block_types"
          (json-array (mapcar #'content-block-type-name blocks))
          "stop_reason" "toolUse"
          "text_characters" (length text)
          "tool_call_count"
          (count-if (lambda (block) (typep block 'cadr-ai:tool-call))
                    blocks)
          "usage_input"
          (cadr-ai:usage-input
           (cadr-ai:assistant-message-usage message))
          "usage_output"
          (cadr-ai:usage-output
           (cadr-ai:assistant-message-usage message))
          "payload_tool_count"
          (if tools (length tools) 0))
         "stream_roundtrip"
         (collect "provider_google.stream_roundtrip"
                  (lambda ()
                    (lambda ()
                      (run-provider-google
                       provider model context nil)))))))))

(defun bedrock-model ()
  (cadr-ai:make-model
   :id "us.anthropic.claude-sonnet-4-5"
   :name "Goal 20 Bedrock"
   :api :bedrock-converse-stream
   :provider :amazon-bedrock
   :base-url "https://bedrock-runtime.us-east-1.amazonaws.com"
   :reasoning-p nil
   :supports-images-p t
   :context-window 128000
   :max-tokens 16384))

(defun bedrock-http-request-function ()
  (lambda (url &rest arguments)
    (declare (ignore url arguments))
    (values
     (open (fixture-path "bedrock-converse-stream.bin")
           :direction :input
           :element-type '(unsigned-byte 8))
     200
     '(("content-type" . "application/vnd.amazon.eventstream")
       ("x-amzn-requestid" . "goal20-bedrock")))))

(defun run-provider-bedrock (provider model context collect-events-p)
  (let ((events nil)
        (payload nil))
    (let ((cadr-ai:*http-request-function*
            (bedrock-http-request-function)))
      (let ((message
              (cadr-ai::stream-chat
               provider model context
               (if collect-events-p
                   (lambda (event) (push event events))
                   (lambda (event) (declare (ignore event)) nil))
               :on-payload
               (lambda (value model)
                 (declare (ignore model))
                 (setf payload value)
                 nil))))
        (values message (nreverse events) payload)))))

(defun measure-provider-bedrock ()
  (let ((provider
          (cadr-ai:make-bedrock-provider
           :api-key *provider-api-key*
           :provider-id :amazon-bedrock))
        (model (bedrock-model))
        (context (provider-context)))
    (multiple-value-bind (message events payload)
        (run-provider-bedrock provider model context t)
      (declare (ignore events))
      (unless (eq :tool-use (cadr-ai:assistant-message-stop-reason message))
        (error "bedrock fixture stream produced stop reason ~S"
               (cadr-ai:assistant-message-stop-reason message)))
      (let* ((blocks (cadr-ai:assistant-message-content message))
             (text
               (apply #'concatenate 'string
                      (mapcar #'cadr-ai:text-content-text
                              (remove-if-not
                               (lambda (block)
                                 (typep block 'cadr-ai:text-content))
                               blocks))))
             (tools
               (cadr-ai::json-get
                (cadr-ai::json-get payload "toolConfig")
                "tools")))
        (json-object
         "observed"
         (json-object
          "content_block_types"
          (json-array (mapcar #'content-block-type-name blocks))
          "stop_reason" "toolUse"
          "text_characters" (length text)
          "tool_call_count"
          (count-if (lambda (block) (typep block 'cadr-ai:tool-call))
                    blocks)
          "usage_input"
          (cadr-ai:usage-input
           (cadr-ai:assistant-message-usage message))
          "usage_output"
          (cadr-ai:usage-output
           (cadr-ai:assistant-message-usage message))
          "payload_tool_count"
          (if tools (length tools) 0))
         "stream_roundtrip"
         (collect "provider_bedrock.stream_roundtrip"
                  (lambda ()
                    (lambda ()
                      (run-provider-bedrock
                       provider model context nil)))))))))

(defun mistral-model ()
  (cadr-ai:make-model
   :id "mistral-small-latest"
   :name "Goal 20 Mistral"
   :api :mistral-conversations
   :provider :mistral
   :base-url "https://api.mistral.ai"
   :reasoning-p nil
   :supports-images-p t
   :context-window 128000
   :max-tokens 16384))

(defun mistral-http-request-function ()
  (lambda (url &rest arguments)
    (declare (ignore url arguments))
    (values
     (open (fixture-path "mistral-conversations.sse")
           :direction :input
           :element-type '(unsigned-byte 8))
     200
     '(("content-type" . "text/event-stream")))))

(defun run-provider-mistral (provider model context collect-events-p)
  (let ((events nil)
        (payload nil))
    (let ((cadr-ai:*http-request-function*
            (mistral-http-request-function)))
      (let ((message
              (cadr-ai::stream-chat
               provider model context
               (if collect-events-p
                   (lambda (event) (push event events))
                   (lambda (event) (declare (ignore event)) nil))
               :on-payload
               (lambda (value model)
                 (declare (ignore model))
                 (setf payload value)
                 nil))))
        (values message (nreverse events) payload)))))

(defun measure-provider-mistral ()
  (let ((provider
          (cadr-ai:make-mistral-provider
           :api-key *provider-api-key*
           :provider-id :mistral))
        (model (mistral-model))
        (context (provider-context)))
    (multiple-value-bind (message events payload)
        (run-provider-mistral provider model context t)
      (declare (ignore events))
      (unless (eq :tool-use (cadr-ai:assistant-message-stop-reason message))
        (error "mistral fixture stream produced stop reason ~S"
               (cadr-ai:assistant-message-stop-reason message)))
      (let* ((blocks (cadr-ai:assistant-message-content message))
             (text
               (apply #'concatenate 'string
                      (mapcar #'cadr-ai:text-content-text
                              (remove-if-not
                               (lambda (block)
                                 (typep block 'cadr-ai:text-content))
                               blocks)))))
        (json-object
         "observed"
         (json-object
          "content_block_types"
          (json-array (mapcar #'content-block-type-name blocks))
          "stop_reason" "toolUse"
          "text_characters" (length text)
          "tool_call_count"
          (count-if (lambda (block) (typep block 'cadr-ai:tool-call))
                    blocks)
          "usage_input"
          (cadr-ai:usage-input
           (cadr-ai:assistant-message-usage message))
          "usage_output"
          (cadr-ai:usage-output
           (cadr-ai:assistant-message-usage message))
          "payload_stream"
          (eq t (cadr-ai::json-get payload "stream"))
          "payload_tool_count"
          (length (or (cadr-ai::json-get payload "tools") #())))
         "stream_roundtrip"
         (collect "provider_mistral.stream_roundtrip"
                  (lambda ()
                    (lambda ()
                      (run-provider-mistral
                       provider model context nil)))))))))

(defun openai-responses-model ()
  (cadr-ai:make-model
   :id "gpt-4.1"
   :name "Goal 20 OpenAI Responses"
   :api :openai-responses
   :provider :openai
   :base-url "https://api.openai.com"
   :reasoning-p nil
   :supports-images-p t
   :context-window 128000
   :max-tokens 16384))

(defun openai-responses-http-request-function ()
  (lambda (url &rest arguments)
    (declare (ignore url arguments))
    (values
     (open (fixture-path "openai-responses.sse")
           :direction :input
           :element-type '(unsigned-byte 8))
     200
     '(("content-type" . "text/event-stream")))))

(defun run-provider-openai-responses
    (provider model context collect-events-p)
  (let ((events nil)
        (payload nil))
    (let ((cadr-ai:*http-request-function*
            (openai-responses-http-request-function)))
      (let ((message
              (cadr-ai::stream-chat
               provider model context
               (if collect-events-p
                   (lambda (event) (push event events))
                   (lambda (event) (declare (ignore event)) nil))
               :on-payload
               (lambda (value model)
                 (declare (ignore model))
                 (setf payload value)
                 nil))))
        (values message (nreverse events) payload)))))

(defun measure-provider-openai-responses ()
  (let ((provider
          (cadr-ai:make-openai-provider
           :api-key *provider-api-key*
           :provider-id :openai))
        (model (openai-responses-model))
        (context (provider-context)))
    (multiple-value-bind (message events payload)
        (run-provider-openai-responses provider model context t)
      (declare (ignore events))
      (unless (eq :tool-use (cadr-ai:assistant-message-stop-reason message))
        (error "openai-responses fixture stream produced stop reason ~S"
               (cadr-ai:assistant-message-stop-reason message)))
      (let* ((blocks (cadr-ai:assistant-message-content message))
             (text
               (apply #'concatenate 'string
                      (mapcar #'cadr-ai:text-content-text
                              (remove-if-not
                               (lambda (block)
                                 (typep block 'cadr-ai:text-content))
                               blocks)))))
        (json-object
         "observed"
         (json-object
          "content_block_types"
          (json-array (mapcar #'content-block-type-name blocks))
          "stop_reason" "toolUse"
          "text_characters" (length text)
          "tool_call_count"
          (count-if (lambda (block) (typep block 'cadr-ai:tool-call))
                    blocks)
          "usage_input"
          (cadr-ai:usage-input
           (cadr-ai:assistant-message-usage message))
          "usage_output"
          (cadr-ai:usage-output
           (cadr-ai:assistant-message-usage message))
          "payload_stream"
          (eq t (cadr-ai::json-get payload "stream"))
          "payload_tool_count"
          (length (or (cadr-ai::json-get payload "tools") #())))
         "stream_roundtrip"
         (collect "provider_openai_responses.stream_roundtrip"
                  (lambda ()
                    (lambda ()
                      (run-provider-openai-responses
                       provider model context nil)))))))))

(defun azure-openai-model ()
  (cadr-ai:make-model
   :id "gpt-4.1"
   :name "Goal 20 Azure OpenAI"
   :api :azure-openai-responses
   :provider :azure-openai-responses
   :base-url "https://goal20.openai.azure.com/openai/v1"
   :reasoning-p nil
   :supports-images-p t
   :context-window 128000
   :max-tokens 16384))

(defun azure-openai-http-request-function ()
  (lambda (url &rest arguments)
    (declare (ignore url arguments))
    (values
     (open (fixture-path "azure-openai-responses.sse")
           :direction :input
           :element-type '(unsigned-byte 8))
     200
     '(("content-type" . "text/event-stream")))))

(defun run-provider-azure-openai
    (provider model context collect-events-p)
  (let ((events nil)
        (payload nil))
    (let ((cadr-ai:*http-request-function*
            (azure-openai-http-request-function)))
      (let ((message
              (cadr-ai::stream-chat
               provider model context
               (if collect-events-p
                   (lambda (event) (push event events))
                   (lambda (event) (declare (ignore event)) nil))
               :on-payload
               (lambda (value model)
                 (declare (ignore model))
                 (setf payload value)
                 nil))))
        (values message (nreverse events) payload)))))

(defun measure-provider-azure-openai ()
  (let ((provider
          (cadr-ai:make-azure-openai-provider
           :api-key *provider-api-key*
           :provider-id :azure-openai-responses))
        (model (azure-openai-model))
        (context (provider-context)))
    (multiple-value-bind (message events payload)
        (run-provider-azure-openai provider model context t)
      (declare (ignore events))
      (unless (eq :tool-use (cadr-ai:assistant-message-stop-reason message))
        (error "azure-openai fixture stream produced stop reason ~S"
               (cadr-ai:assistant-message-stop-reason message)))
      (let* ((blocks (cadr-ai:assistant-message-content message))
             (text
               (apply #'concatenate 'string
                      (mapcar #'cadr-ai:text-content-text
                              (remove-if-not
                               (lambda (block)
                                 (typep block 'cadr-ai:text-content))
                               blocks)))))
        (json-object
         "observed"
         (json-object
          "content_block_types"
          (json-array (mapcar #'content-block-type-name blocks))
          "stop_reason" "toolUse"
          "text_characters" (length text)
          "tool_call_count"
          (count-if (lambda (block) (typep block 'cadr-ai:tool-call))
                    blocks)
          "usage_input"
          (cadr-ai:usage-input
           (cadr-ai:assistant-message-usage message))
          "usage_output"
          (cadr-ai:usage-output
           (cadr-ai:assistant-message-usage message))
          "payload_stream"
          (eq t (cadr-ai::json-get payload "stream"))
          "payload_tool_count"
          (length (or (cadr-ai::json-get payload "tools") #())))
         "stream_roundtrip"
         (collect "provider_azure_openai.stream_roundtrip"
                  (lambda ()
                    (lambda ()
                      (run-provider-azure-openai
                       provider model context nil)))))))))

(defun vertex-model ()
  (cadr-ai:make-model
   :id "gemini-3.6-flash"
   :name "Goal 20 Vertex"
   :api :google-vertex
   :provider :google-vertex
   :base-url "https://aiplatform.googleapis.com/v1"
   :reasoning-p nil
   :supports-images-p t
   :context-window 128000
   :max-tokens 16384))

(defun vertex-http-request-function ()
  (lambda (url &rest arguments)
    (declare (ignore url arguments))
    (values
     (open (fixture-path "google-vertex.sse")
           :direction :input
           :element-type '(unsigned-byte 8))
     200
     '(("content-type" . "text/event-stream")))))

(defun run-provider-vertex (provider model context collect-events-p)
  (let ((events nil)
        (payload nil))
    (let ((cadr-ai:*http-request-function*
            (vertex-http-request-function)))
      (let ((message
              (cadr-ai::stream-chat
               provider model context
               (if collect-events-p
                   (lambda (event) (push event events))
                   (lambda (event) (declare (ignore event)) nil))
               :on-payload
               (lambda (value model)
                 (declare (ignore model))
                 (setf payload value)
                 nil))))
        (values message (nreverse events) payload)))))

(defun measure-provider-vertex ()
  (let ((provider
          (cadr-ai:make-vertex-provider
           :api-key *provider-api-key*
           :provider-id :google-vertex))
        (model (vertex-model))
        (context (provider-context)))
    (multiple-value-bind (message events payload)
        (run-provider-vertex provider model context t)
      (declare (ignore events))
      (unless (eq :tool-use (cadr-ai:assistant-message-stop-reason message))
        (error "vertex fixture stream produced stop reason ~S"
               (cadr-ai:assistant-message-stop-reason message)))
      (let* ((blocks (cadr-ai:assistant-message-content message))
             (text
               (apply #'concatenate 'string
                      (mapcar #'cadr-ai:text-content-text
                              (remove-if-not
                               (lambda (block)
                                 (typep block 'cadr-ai:text-content))
                               blocks))))
             (tools (cadr-ai::json-get payload "tools")))
        (json-object
         "observed"
         (json-object
          "content_block_types"
          (json-array (mapcar #'content-block-type-name blocks))
          "stop_reason" "toolUse"
          "text_characters" (length text)
          "tool_call_count"
          (count-if (lambda (block) (typep block 'cadr-ai:tool-call))
                    blocks)
          "usage_input"
          (cadr-ai:usage-input
           (cadr-ai:assistant-message-usage message))
          "usage_output"
          (cadr-ai:usage-output
           (cadr-ai:assistant-message-usage message))
          "payload_tool_count"
          (if tools (length tools) 0)
          "adc_type"
          (cadr-ai::json-get
           (cadr-ai::read-google-application-credential
            (fixture-path "vertex-adc.json"))
           "type"))
         "stream_roundtrip"
         (collect "provider_vertex.stream_roundtrip"
                  (lambda ()
                    (lambda ()
                      (run-provider-vertex
                       provider model context nil)))))))))

(defparameter *codex-oauth-token*
  "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJodHRwczovL2FwaS5vcGVuYWkuY29tL2F1dGgiOnsiY2hhdGdwdF9hY2NvdW50X2lkIjoiZ29hbDIwLWNvZGV4LWFjY291bnQifX0.sig")

(defun openai-codex-model ()
  (cadr-ai:make-model
   :id "gpt-5.5"
   :name "Goal 20 OpenAI Codex"
   :api :openai-codex-responses
   :provider :openai-codex
   :base-url "https://chatgpt.com/backend-api"
   :reasoning-p nil
   :supports-images-p t
   :context-window 128000
   :max-tokens 16384))

(defun openai-codex-http-request-function ()
  (lambda (url &rest arguments)
    (declare (ignore url arguments))
    (values
     (open (fixture-path "openai-codex-responses.sse")
           :direction :input
           :element-type '(unsigned-byte 8))
     200
     '(("content-type" . "text/event-stream")))))

(defun run-provider-codex (provider model context collect-events-p)
  (let ((events nil)
        (payload nil))
    (let ((cadr-ai:*http-request-function*
            (openai-codex-http-request-function)))
      (let ((message
              (cadr-ai::stream-chat
               provider model context
               (if collect-events-p
                   (lambda (event) (push event events))
                   (lambda (event) (declare (ignore event)) nil))
               :transport :sse
               :on-payload
               (lambda (value model)
                 (declare (ignore model))
                 (setf payload value)
                 nil))))
        (values message (nreverse events) payload)))))

(defun measure-provider-codex ()
  (let ((provider
          (cadr-ai:make-openai-codex-provider
           :oauth-access-token *codex-oauth-token*
           :oauth-account-id "goal20-codex-account"
           :provider-id :openai-codex))
        (model (openai-codex-model))
        (context (provider-context)))
    (multiple-value-bind (message events payload)
        (run-provider-codex provider model context t)
      (declare (ignore events))
      (unless (eq :tool-use (cadr-ai:assistant-message-stop-reason message))
        (error "codex fixture stream produced stop reason ~S"
               (cadr-ai:assistant-message-stop-reason message)))
      (let* ((blocks (cadr-ai:assistant-message-content message))
             (text
               (apply #'concatenate 'string
                      (mapcar #'cadr-ai:text-content-text
                              (remove-if-not
                               (lambda (block)
                                 (typep block 'cadr-ai:text-content))
                               blocks)))))
        (json-object
         "observed"
         (json-object
          "content_block_types"
          (json-array (mapcar #'content-block-type-name blocks))
          "stop_reason" "toolUse"
          "text_characters" (length text)
          "tool_call_count"
          (count-if (lambda (block) (typep block 'cadr-ai:tool-call))
                    blocks)
          "usage_input"
          (cadr-ai:usage-input
           (cadr-ai:assistant-message-usage message))
          "usage_output"
          (cadr-ai:usage-output
           (cadr-ai:assistant-message-usage message))
          "payload_stream"
          (eq t (cadr-ai::json-get payload "stream"))
          "payload_tool_count"
          (length (or (cadr-ai::json-get payload "tools") #())))
         "stream_roundtrip"
         (collect "provider_codex.stream_roundtrip"
                  (lambda ()
                    (lambda ()
                      (run-provider-codex
                       provider model context nil)))))))))

(defun pi-messages-model ()
  (cadr-ai:make-model
   :id "pi-goal20"
   :name "Goal 20 pi-messages"
   :api :pi-messages
   :provider :pi
   :base-url "https://goal20.pi.example/v1"
   :reasoning-p nil
   :supports-images-p t
   :context-window 128000
   :max-tokens 16384))

(defun pi-messages-http-request-function ()
  (lambda (url &rest arguments)
    (declare (ignore url arguments))
    (values
     (open (fixture-path "pi-messages.sse")
           :direction :input
           :element-type '(unsigned-byte 8))
     200
     '(("content-type" . "text/event-stream")))))

(defun run-provider-pi-messages (provider model context collect-events-p)
  (let ((events nil)
        (payload nil))
    (let ((cadr-ai:*http-request-function*
            (pi-messages-http-request-function)))
      (let ((message
              (cadr-ai::stream-chat
               provider model context
               (if collect-events-p
                   (lambda (event) (push event events))
                   (lambda (event) (declare (ignore event)) nil))
               :on-payload
               (lambda (value model)
                 (declare (ignore model))
                 (setf payload value)
                 nil))))
        (values message (nreverse events) payload)))))

(defun measure-provider-pi-messages ()
  (let ((provider
          (cadr-ai:make-pi-messages-provider
           :api-key *provider-api-key*
           :provider-id :pi))
        (model (pi-messages-model))
        (context (provider-context)))
    (multiple-value-bind (message events payload)
        (run-provider-pi-messages provider model context t)
      (declare (ignore events))
      (unless (eq :tool-use (cadr-ai:assistant-message-stop-reason message))
        (error "pi-messages fixture stream produced stop reason ~S"
               (cadr-ai:assistant-message-stop-reason message)))
      (let* ((blocks (cadr-ai:assistant-message-content message))
             (text
               (apply #'concatenate 'string
                      (mapcar #'cadr-ai:text-content-text
                              (remove-if-not
                               (lambda (block)
                                 (typep block 'cadr-ai:text-content))
                               blocks))))
             (tools
               (cadr-ai::json-get
                (cadr-ai::json-get payload "context")
                "tools")))
        (json-object
         "observed"
         (json-object
          "content_block_types"
          (json-array (mapcar #'content-block-type-name blocks))
          "stop_reason" "toolUse"
          "text_characters" (length text)
          "tool_call_count"
          (count-if (lambda (block) (typep block 'cadr-ai:tool-call))
                    blocks)
          "usage_input"
          (cadr-ai:usage-input
           (cadr-ai:assistant-message-usage message))
          "usage_output"
          (cadr-ai:usage-output
           (cadr-ai:assistant-message-usage message))
          "payload_tool_count"
          (if tools (length tools) 0))
         "stream_roundtrip"
         (collect "provider_pi_messages.stream_roundtrip"
                  (lambda ()
                    (lambda ()
                      (run-provider-pi-messages
                       provider model context nil)))))))))

;;; ---------------------------------------------------------------------
;;; Pair 3: agent session load + event pipeline
;;; ---------------------------------------------------------------------

(defun message-role-name (message)
  (etypecase message
    (cadr-ai:user-message "user")
    (cadr-ai:assistant-message "assistant")
    (cadr-ai:tool-result-message "toolResult")
    (cadr-agent::bash-execution-message "bashExecution")))

(defun role-counts-json (messages)
  (count-names-json (mapcar #'message-role-name messages)))

;;; pi returns thinkingLevel and model from buildSessionContext; cadr keeps
;;; them in the entry stream and resolves them at the call site
;;; (harness-session-build-context, sdk-session-restored-thinking,
;;; cadr-cli::session-restored-model).  These two helpers apply that same
;;; last-writer-wins rule over the context path so the paired reports can be
;;; compared, and they stay out of the timed context walk.
(defun session-context-thinking-level (entries)
  (let ((entry
          (find :thinking-level-change entries
                :key #'cadr-agent:session-entry-type
                :from-end t)))
    (if entry
        (cadr-agent:session-entry-thinking-level entry)
        "off")))

(defun session-context-model-json (entries)
  (let ((provider nil)
        (model-id nil))
    (dolist (entry entries)
      (case (cadr-agent:session-entry-type entry)
        (:model-change
         (setf provider (cadr-agent:session-entry-provider entry)
               model-id (cadr-agent:session-entry-model-id entry)))
        (:message
         (let ((message (cadr-agent:session-entry-message entry)))
           (when (typep message 'cadr-ai:assistant-message)
             (setf provider
                   (string-downcase
                    (symbol-name
                     (cadr-ai:assistant-message-provider message)))
                   model-id
                   (cadr-ai:assistant-message-model message)))))))
    (if model-id
        (json-object "modelId" model-id "provider" provider)
        'null)))

(defun measure-session-pipeline ()
  (let* ((path (fixture-path "session.jsonl"))
         (session (cadr-agent:load-session path))
         (messages (cadr-agent:session-messages session))
         (context-entries (cadr-agent::session-context-entries session)))
    (json-object
     "context_walk"
     (collect "session_pipeline.context_walk"
              (lambda ()
                (lambda ()
                  (cadr-agent:session-messages session))))
     "observed"
     (json-object
      "context_entry_count" (length context-entries)
      "context_message_count" (length messages)
      "context_message_roles" (role-counts-json messages)
      "context_model" (session-context-model-json context-entries)
      "context_thinking_level"
      (session-context-thinking-level context-entries)
      "entry_count" (length (cadr-agent:session-entries session))
      "leaf_id" (cadr-agent:session-leaf-id session)
      "session_id" (cadr-agent:session-id session)
      "session_name" (or (cadr-agent:session-name session) 'null))
     "session_load"
     (collect "session_pipeline.session_load"
              (lambda ()
                (lambda ()
                  (cadr-agent:load-session path)))))))

;;; ---------------------------------------------------------------------
;;; Pair 4: storage read/write
;;; ---------------------------------------------------------------------

;;; The append fixture is the first N message entries of the shared session
;;; fixture, replayed into a fresh journal.  Both sides therefore write the
;;; same logical entries in the same order.
(defun journal-append-messages ()
  (let ((messages nil)
        (remaining *journal-append-entry-count*))
    (dolist (object (cadr-agent::read-session-objects
                     (fixture-path "session.jsonl")))
      (when (zerop remaining)
        (return))
      (when
          (if (cadr-agent::session-entry-p object)
              (let ((type
                      (cadr-agent::session-entry-type object)))
                (or (eq type :message)
                    (string= type "message")))
              (string=
               "message"
               (cadr-ai::json-get object "type")))
        (push
         (cadr-agent::message-from-json
          (if (cadr-agent::session-entry-p object)
              (cadr-agent::session-entry-message object)
              (cadr-ai::json-get object "message")))
         messages)
        (decf remaining)))
    (unless (zerop remaining)
      (error "session fixture has too few message entries for the append pair"))
    (nreverse messages)))

(defparameter *journal-write-index* 0)

(defun append-journal-once (messages cwd)
  ;; Each sample mkdirs a fresh journal directory.  That is harness tax,
  ;; not the product open-append.  Same-machine split 2026-08-18 (128
  ;; messages): create-session 0.40ms, 128 session-append-message 3.00ms,
  ;; combined 4.00ms.  Create is ~10% of the combined sample here.
  ;; Friend-MachineD sprof ~40% FS self includes product open/write.
  ;; docs/benchmarks/goal20-part-p-append-tax.md
  (incf *journal-write-index*)
  (let* ((directory
           (merge-pathnames
            (format nil "journal/~D/" *journal-write-index*)
            *scratch-directory*))
         (session
           (cadr-agent:create-session
            :directory directory
            :cwd cwd
            :id (format nil "019f0000-0000-7000-8000-~12,'0D"
                        *journal-write-index*)
            :timestamp 1786665600000)))
    (dolist (message messages)
      (cadr-agent:session-append-message session message))
    session))

(defun measure-storage-journal ()
  (let* ((path (fixture-path "session.jsonl"))
         (cwd (journal-cwd))
         (objects (cadr-agent::read-session-objects path))
         (messages (journal-append-messages))
         (written (append-journal-once messages cwd))
         (written-path (cadr-agent:session-path written))
         (written-octets (read-file-octets written-path))
         (written-objects
           (cadr-agent::read-session-objects written-path))
         ;; The header line carries the cwd and a wall-clock timestamp, so the
         ;; body is what the two sides can compare byte for byte.
         (header-length
           (1+ (position (char-code #\Newline) written-octets))))
    (when *keep-journal-path*
      (uiop:copy-file written-path *keep-journal-path*))
    (json-object
     "journal_append"
     (collect "storage_journal.journal_append"
              (lambda ()
                (lambda ()
                  (append-journal-once messages cwd))))
     "journal_read"
     (collect "storage_journal.journal_read"
              (lambda ()
                (lambda ()
                  (cadr-agent::read-session-objects path))))
     "observed"
     (json-object
      "append_entry_count" *journal-append-entry-count*
      "journal_cwd" (cadr-agent:session-cwd written)
      "read_file_entry_count" (length objects)
      "written_body_bytes" (- (length written-octets) header-length)
      "written_bytes" (length written-octets)
      "written_file_entry_count" (length written-objects)))))

;;; ---------------------------------------------------------------------
;;; Pair 5: SQLite session open + read-all + leaf walk
;;; ---------------------------------------------------------------------
;;;
;;; Ingest the shared session.jsonl into the production SQLite backend
;;; once, outside the timed loop.  The timed thunk is repository open,
;;; read every stored entry, and walk the leaf path.  No network.

(defun sqlite-database-path ()
  (merge-pathnames "sqlite/sessions.sqlite" *scratch-directory*))

(defun ingest-sqlite-from-session-jsonl (database-path)
  (let* ((source (cadr-agent:load-session (fixture-path "session.jsonl")))
         (cwd (journal-cwd))
         (repository
           (cadr-agent:make-sqlite-session-repository
            :database-path database-path))
         (session
           (cadr-agent:session-repository-create
            repository
            :id (cadr-agent:session-id source)
            :cwd cwd)))
    (dolist (entry (cadr-agent:session-entries source))
      (cadr-agent:harness-session-append-entry session entry))
    (let ((metadata (cadr-agent:harness-session-metadata session))
          (entry-count (length (cadr-agent:session-entries source)))
          (leaf-id (cadr-agent:session-leaf-id source))
          (session-id (cadr-agent:session-id source)))
      (cadr-agent:harness-session-cleanup session)
      (values repository metadata entry-count leaf-id session-id))))

(defun sqlite-open-read-walk (repository metadata)
  (let ((session
          (cadr-agent:session-repository-open repository metadata)))
    (unwind-protect
         (let ((entries (cadr-agent:harness-session-entries session))
               (branch (cadr-agent:harness-session-branch session)))
           (list (length entries)
                 (cadr-agent:harness-session-leaf-id session)
                 (length branch)))
      (cadr-agent:harness-session-cleanup session))))

(defun jsonl-sessions-root ()
  (merge-pathnames "jsonl-sessions/" *scratch-directory*))

(defun ingest-jsonl-from-session-jsonl (sessions-root)
  (ensure-directories-exist sessions-root)
  (let* ((source (cadr-agent:load-session (fixture-path "session.jsonl")))
         (cwd (journal-cwd))
         (environment
           (cadr-agent:make-node-execution-env :cwd cwd))
         (repository
           (cadr-agent:make-jsonl-session-repository
            :environment environment
            :sessions-root sessions-root))
         (session
           (cadr-agent:session-repository-create
            repository
            :id (cadr-agent:session-id source)
            :cwd cwd)))
    (dolist (entry (cadr-agent:session-entries source))
      (cadr-agent:harness-session-append-entry session entry))
    (let ((metadata (cadr-agent:harness-session-metadata session))
          (entry-count (length (cadr-agent:session-entries source)))
          (leaf-id (cadr-agent:session-leaf-id source))
          (session-id (cadr-agent:session-id source)))
      (cadr-agent:harness-session-cleanup session)
      (values repository metadata entry-count leaf-id session-id))))

(defun jsonl-open-read-walk (repository metadata)
  (let ((session
          (cadr-agent:session-repository-open repository metadata)))
    (unwind-protect
         (let ((entries (cadr-agent:harness-session-entries session))
               (branch (cadr-agent:harness-session-branch session)))
           (list (length entries)
                 (cadr-agent:harness-session-leaf-id session)
                 (length branch)))
      (cadr-agent:harness-session-cleanup session))))

(defun measure-harness-storage ()
  (multiple-value-bind
        (repository metadata entry-count leaf-id session-id)
      (ingest-jsonl-from-session-jsonl (jsonl-sessions-root))
    (let ((observed (jsonl-open-read-walk repository metadata)))
      (json-object
       "observed"
       (json-object
        "entry_count" (first observed)
        "leaf_id" (second observed)
        "branch_entry_count" (third observed)
        "ingested_entry_count" entry-count
        "session_id" session-id
        "source_leaf_id" leaf-id)
       "open_walk"
       (collect "harness_storage.open_walk"
                (lambda ()
                  (lambda ()
                    (jsonl-open-read-walk repository metadata))))))))

(defun measure-sqlite-session ()
  (multiple-value-bind
        (repository metadata entry-count leaf-id session-id)
      (ingest-sqlite-from-session-jsonl (sqlite-database-path))
    (let ((observed (sqlite-open-read-walk repository metadata)))
      (json-object
       "observed"
       (json-object
        "entry_count" (first observed)
        "leaf_id" (second observed)
        "branch_entry_count" (third observed)
        "ingested_entry_count" entry-count
        "session_id" session-id
        "source_leaf_id" leaf-id)
       "open_walk"
       (collect "sqlite_session.open_walk"
                (lambda ()
                  (lambda ()
                    (sqlite-open-read-walk repository metadata))))))))

;;; ---------------------------------------------------------------------
;;; Pair 6: tool-output truncation (goal 20, 12F-1)
;;; ---------------------------------------------------------------------

(defun truncation-fixture-content ()
  (with-output-to-string (out)
    (loop for i from 1 to 4000
          do (if (oddp i)
                 (write-line (make-string 220 :initial-element #\x) out)
                 (write-line "é🙂中文 mixed tail line" out)))))

(defun measure-text-truncation ()
  (let* ((content (truncation-fixture-content))
         (head (cadr-agent::truncate-harness-head content))
         (tail (cadr-agent::truncate-harness-tail content)))
    (json-object
     "observed"
     (json-object
      "content_bytes" (cadr-agent::harness-utf8-length content)
      "head_output_lines"
      (cadr-agent::harness-truncation-result-output-lines head)
      "head_output_bytes"
      (cadr-agent::harness-truncation-result-output-bytes head)
      "head_truncated_by"
      (let ((reason (cadr-agent::harness-truncation-result-truncated-by head)))
        (if reason (string-downcase (symbol-name reason)) "null"))
      "head_first_line_exceeds"
      (if (cadr-agent::harness-truncation-result-first-line-exceeds-limit-p head)
          1 0)
      "tail_output_lines"
      (cadr-agent::harness-truncation-result-output-lines tail)
      "tail_output_bytes"
      (cadr-agent::harness-truncation-result-output-bytes tail)
      "tail_truncated_by"
      (let ((reason (cadr-agent::harness-truncation-result-truncated-by tail)))
        (if reason (string-downcase (symbol-name reason)) "null"))
      "tail_last_line_partial"
      (if (cadr-agent::harness-truncation-result-last-line-partial-p tail)
          1 0))
     "truncate_head"
     (collect "text_truncation.truncate_head"
              (lambda ()
                (lambda ()
                  (cadr-agent::truncate-harness-head content))))
     "truncate_tail"
     (collect "text_truncation.truncate_tail"
              (lambda ()
                (lambda ()
                  (cadr-agent::truncate-harness-tail content)))))))

;;; ---------------------------------------------------------------------
;;; Pair: coding-agent read tool (split lines + truncateHead)
;;; ---------------------------------------------------------------------

(defun write-read-fixture ()
  (let ((path
          (merge-pathnames
           "read/read-fixture.txt" *scratch-directory*)))
    (ensure-directories-exist path)
    (with-open-file
        (out path
             :direction :output
             :if-exists :supersede
             :if-does-not-exist :create
             :external-format :utf-8)
      (write-string (truncation-fixture-content) out))
    path))

(defun measure-tool-read ()
  (let* ((path (write-read-fixture))
         (cwd
           (namestring
            (uiop:pathname-directory-pathname path)))
         (relative (file-namestring path))
         (arguments
           (cadr-ai::json-object "path" relative)))
    (multiple-value-bind (blocks details)
        (cadr-cli::read-tool-file cwd arguments)
      (let ((text
              (cadr-ai::text-content-text (first blocks))))
        (json-object
         "observed"
         (json-object
          "line_count"
          (length
           (cadr-cli::split-all-lines
            (uiop:read-file-string
             path :external-format :utf-8)))
          "output_chars"
          (cadr-cli::utf16-code-unit-length text)
          "truncated"
          (if (and details (getf details :truncated)) 1 0))
         "text_file"
         (collect "tool_read.text_file"
                  (lambda ()
                    (lambda ()
                      (cadr-cli::read-tool-file
                       cwd arguments)))))))))

(defun write-grep-fixture ()
  (let ((path
          (merge-pathnames
           "grep/grep-fixture.txt" *scratch-directory*)))
    (ensure-directories-exist path)
    (with-open-file
        (out path
             :direction :output
             :if-exists :supersede
             :if-does-not-exist :create
             :external-format :utf-8)
      (write-string (truncation-fixture-content) out))
    path))

(defun measure-tool-grep ()
  ;; context=2 forces production ripgrep-file-lines / text-lines.
  ;; context=0 would skip that list encoding.
  (let* ((path (write-grep-fixture))
         (cwd
           (namestring
            (uiop:pathname-directory-pathname path)))
         (relative (file-namestring path))
         (arguments
           (cadr-ai::json-object
            "pattern" "mixed tail"
            "path" relative
            "literal" t
            "context" 2
            "limit" 100)))
    (multiple-value-bind (blocks details)
        (cadr-cli::grep-lines cwd arguments)
      (let ((text
              (cadr-ai::text-content-text (first blocks)))
            (truncation (getf details :truncation)))
        (json-object
         "observed"
         (json-object
          "match_limit"
          (or (getf details :match-limit-reached) 0)
          "output_chars"
          (cadr-cli::utf16-code-unit-length text)
          "truncated"
          (if (and truncation (getf truncation :truncated)) 1 0))
         "context_file"
         (collect "tool_grep.context_file"
                  (lambda ()
                    (lambda ()
                      (cadr-cli::grep-lines
                       cwd arguments)))))))))

(defun paired-echo-tool (executed)
  (cadr-ai:make-tool
   :name "echo"
   :description "Echo"
   :parameters
   (cadr-ai::json-object
    "type" "object"
    "properties"
    (cadr-ai::json-object
     "value" (cadr-ai::json-object "type" "string"))
    "required" (vector "value")
    "additionalProperties" nil)
   :execution-mode :parallel
   :executor
   (lambda (call-id arguments)
     (declare (ignore call-id))
     (setf (car executed)
           (cadr-ai::json-get arguments "value"))
     (list (cadr-ai:make-text-content :text "echoed")))))

(defun paired-tool-loop-stream (responses)
  (let ((queue (copy-list responses)))
    (lambda (provider model context on-event
             &key max-tokens temperature abort-p
               cache-retention session-id)
      (declare (ignore provider model context max-tokens
                       temperature abort-p cache-retention
                       session-id))
      (let ((message (pop queue)))
        (unless message
          (error "paired tool-loop stream exhausted"))
        (funcall on-event
                 (cadr-ai:make-stream-event
                  :type :start :message message))
        (dolist (block (cadr-ai:assistant-message-content message))
          (when (typep block 'cadr-ai:text-content)
            (funcall
             on-event
             (cadr-ai:make-stream-event
              :type :text-delta
              :delta (cadr-ai:text-content-text block)
              :message message))))
        (funcall
         on-event
         (cadr-ai:make-stream-event
          :type :done
          :message message
          :reason (cadr-ai:assistant-message-stop-reason
                   message)))
        message))))

(defun paired-tool-loop-responses ()
  (list
   (cadr-ai:make-assistant-message
    :content
    (list
     (cadr-ai:make-tool-call
      :id "call_1"
      :name "echo"
      :arguments (cadr-ai::json-object "value" "hello")))
    :api :openai-responses
    :provider :openai
    :model "mock"
    :stop-reason :tool-use)
   (cadr-ai:make-assistant-message
    :content
    (list (cadr-ai:make-text-content :text "done"))
    :api :openai-responses
    :provider :openai
    :model "mock"
    :stop-reason :stop)))

(defun run-paired-tool-loop ()
  ;; FiveAM tool-call-result-and-next-model-turn-complete.
  ;; Production agent-prompt + faux stream. No socket.
  (let* ((executed (list nil))
         (agent
           (cadr-agent:make-agent
            :provider :mock
            :model
            (cadr-ai:make-model
             :id "mock"
             :provider :openai
             :api :openai-responses
             :base-url "https://example.invalid"
             :max-tokens 2048)
            :tools (list (paired-echo-tool executed))
            :stream-function
            (paired-tool-loop-stream
             (paired-tool-loop-responses))
            :auto-compact-p nil)))
    (cadr-agent:agent-prompt agent "echo")
    (values agent (car executed))))

(defun tool-path-flag (cwd path expected)
  (if (string= (namestring (cadr-cli::resolve-tool-path cwd path))
               expected)
      1
      0))

(defun run-agent-tool-loop-tool-path ()
  ;; POSIX only. Do not exact empty (cadr errors) or "~"
  ;; (cadr directory namestring keeps a trailing slash).
  (let ((cwd "/tmp/goal20-tp/cwd")
        (nbsp (format nil "a~Cb.txt" (code-char #xa0))))
    (list
     (tool-path-flag cwd "foo.txt" "/tmp/goal20-tp/cwd/foo.txt")
     (tool-path-flag cwd "/tmp/abs/bar" "/tmp/abs/bar")
     (tool-path-flag cwd "@rel.txt" "/tmp/goal20-tp/cwd/rel.txt")
     (tool-path-flag cwd nbsp "/tmp/goal20-tp/cwd/a b.txt")
     (tool-path-flag cwd "../x" "/tmp/goal20-tp/x"))))

(defun line-ending-flag (text expected)
  (if (eq (cadr-cli::detect-line-ending text) expected)
      1
      0))

(defun run-agent-tool-loop-line-ending ()
  ;; Do not exact mixed first-LF-then-CRLF (cadr searches any CRLF;
  ;; pi compares the first \\n against the first \\r\\n).
  (list
   (line-ending-flag (format nil "a~Cb" #\Newline) :lf)
   (line-ending-flag
    (format nil "a~C~Cb" #\Return #\Newline) :crlf)
   (line-ending-flag "ab" :lf)
   (line-ending-flag "" :lf)))

(defun measure-agent-tool-loop ()
  (multiple-value-bind (agent executed)
      (run-paired-tool-loop)
    (let* ((messages (cadr-agent:agent-messages agent))
           (last (car (last messages)))
           (result (third messages))
           (paths (run-agent-tool-loop-tool-path))
           (endings (run-agent-tool-loop-line-ending)))
      (json-object
       "observed"
       (json-object
        "final_text"
        (cadr-ai:text-content-text
         (first (cadr-ai:assistant-message-content last)))
        "message_count" (length messages)
        "tool_error"
        (if (and (typep result 'cadr-ai:tool-result-message)
                 (cadr-ai:tool-result-message-is-error result))
            1
            0)
        "tool_value" (or executed "")
        "tp_rel" (nth 0 paths)
        "tp_abs" (nth 1 paths)
        "tp_at" (nth 2 paths)
        "tp_nbsp" (nth 3 paths)
        "tp_parent" (nth 4 paths)
        "le_lf" (nth 0 endings)
        "le_crlf" (nth 1 endings)
        "le_none" (nth 2 endings)
        "le_empty" (nth 3 endings))
       "roundtrip"
       (collect "agent_tool_loop.roundtrip"
                (lambda ()
                  (lambda ()
                    (run-paired-tool-loop))))
       "tool_path"
       (collect "agent_tool_loop.tool_path"
                (lambda ()
                  (lambda ()
                    (run-agent-tool-loop-tool-path))))
       "line_ending"
       (collect "agent_tool_loop.line_ending"
                (lambda ()
                  (lambda ()
                    (run-agent-tool-loop-line-ending))))))))

(defun paired-compact-model ()
  (cadr-ai:make-model
   :id "tiny"
   :provider :openai
   :api :openai-responses
   :base-url "https://example.invalid"
   :max-tokens 32
   :context-window 100))

(defun paired-compact-response (text)
  (cadr-ai:make-assistant-message
   :content (list (cadr-ai:make-text-content :text text))
   :api :openai-responses
   :provider :openai
   :model "tiny"
   :usage (cadr-ai:make-usage :input 60 :output 20 :total 80)
   :stop-reason :stop))

(defun paired-compact-entry (id parent-id message)
  (cadr-agent::make-session-entry
   :type :message
   :id id
   :parent-id parent-id
   :timestamp 1786665600000
   :message message))

(defun paired-compact-entries ()
  ;; Same five messages as scripts/goal20-paired-paths.mjs
  ;; pairedCompactEntries. In-memory SessionEntry[], not JSONL.
  (list
   (paired-compact-entry
    "e1" nil
    (cadr-ai:make-user-message
     :content
     (concatenate
      'string "discarded context "
      (make-string 40 :initial-element #\d))))
   (paired-compact-entry
    "e2" "e1"
    (paired-compact-response
     (concatenate
      'string "discarded answer "
      (make-string 40 :initial-element #\e))))
   (paired-compact-entry
    "e3" "e2"
    (cadr-ai:make-user-message
     :content
     (concatenate
      'string "old context "
      (make-string 120 :initial-element #\x))))
   (paired-compact-entry
    "e4" "e3"
    (paired-compact-response
     (concatenate
      'string "old answer "
      (make-string 120 :initial-element #\y))))
   (paired-compact-entry
    "e5" "e4"
    (cadr-ai:make-user-message :content "current request"))))

(defun run-paired-compact ()
  ;; Inventory: time compact() to the compaction result, not
  ;; load-session of an already-compacted file and not journal I/O.
  ;; Lisp encoding of prepareCompaction + compact (in-memory).
  ;; compact-agent still persists after this core (FiveAM).
  (let* ((entries (paired-compact-entries))
         (keep 40)
         (reserve 21)
         (cut (cadr-agent::compaction-cut-point entries keep)))
    (unless cut
      (return-from run-paired-compact nil))
    (let* ((source (subseq entries 0 cut))
           (kept (nth cut entries))
           (messages
             (remove
              nil
              (mapcar #'cadr-agent:session-entry-message entries)))
           (tokens
             (cadr-agent::context-estimated-tokens messages))
           (preparation
             (cadr-agent::make-compaction-preparation
              source kept tokens keep reserve))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (paired-compact-model)
              :compaction-reserve-tokens reserve
              :compaction-keep-recent-tokens keep
              :auto-compact-p nil
              :stream-function
              (paired-tool-loop-stream
               (list (paired-compact-response "SUMMARY"))))))
      (multiple-value-bind (summary usage)
          (cadr-agent::compact-from-preparation agent preparation)
        (declare (ignore usage))
        (list
         :summary summary
         :first-kept-entry-id
         (getf preparation :first-kept-entry-id))))))

(defun measure-session-compact ()
  (let ((result (run-paired-compact)))
    (json-object
     "observed"
     (json-object
      "compacted" (if result 1 0)
      "first_kept"
      (if (and result (getf result :first-kept-entry-id)) 1 0)
      "summary_chars"
      (if result
          (cadr-agent::utf16-code-unit-length
           (or (getf result :summary) ""))
          0))
     "compact"
     (collect "session_compact.compact"
              (lambda ()
                (lambda ()
                  (run-paired-compact)))))))

(defparameter *settings-agent-directory*
  (merge-pathnames "settings-agent/" *scratch-directory*))

(defparameter *settings-cwd-directory*
  (merge-pathnames "settings-cwd/" *scratch-directory*))

(defun stage-settings-layout ()
  (let ((global
          (merge-pathnames
           "settings.json" *settings-agent-directory*))
        (project
          (merge-pathnames
           ".pi/settings.json" *settings-cwd-directory*)))
    (ensure-directories-exist global)
    (ensure-directories-exist project)
    (uiop:copy-file (fixture-path "settings-global.json") global)
    (uiop:copy-file (fixture-path "settings-project.json") project)
    (values global project)))

(defun run-cli-settings (global project)
  (cadr-cli::make-settings-manager
   :global-path global
   :project-path project
   :project-trusted-p t))

(defun measure-cli-settings ()
  (multiple-value-bind (global project)
      (stage-settings-layout)
    (let ((manager (run-cli-settings global project)))
      (json-object
       "observed"
       (json-object
        "theme"
        (or (cadr-cli::settings-value manager "theme") "")
        "default_model"
        (or (cadr-cli::settings-value manager "defaultModel") "")
        "default_provider"
        (or (cadr-cli::settings-value manager "defaultProvider") "")
        "compaction_reserve_tokens"
        (or (cadr-cli::settings-nested-value
             manager "compaction" "reserveTokens")
            0)
        "default_project_trust"
        (or (cadr-cli::settings-value manager "defaultProjectTrust")
            "")
        "http_idle_timeout_ms"
        (cadr-cli::settings-http-idle-timeout-ms manager)
        "project_trusted"
        (and (cadr-cli::settings-manager-project-trusted-p manager) t))
       "create"
       (collect "cli_settings.create"
                (lambda ()
                  (lambda ()
                    (run-cli-settings global project))))))))

(defun stage-settings-load-trust ()
  (let* ((empty
           (merge-pathnames "trust-empty/" *scratch-directory*))
         (project
           (merge-pathnames "trust-project/" *scratch-directory*))
         (cadr-config
           (merge-pathnames ".cadr/settings.json" project))
         (pi-config
           (merge-pathnames ".pi/settings.json" project))
         (agent
           (merge-pathnames "trust-agent/" *scratch-directory*))
         (store-path
           (merge-pathnames "trust.json" agent)))
    (ensure-directories-exist empty)
    (ensure-directories-exist cadr-config)
    (ensure-directories-exist pi-config)
    (ensure-directories-exist agent)
    (with-open-file (out cadr-config
                         :direction :output
                         :if-exists :supersede
                         :if-does-not-exist :create
                         :external-format :utf-8)
      (write-string "{}" out))
    (with-open-file (out pi-config
                         :direction :output
                         :if-exists :supersede
                         :if-does-not-exist :create
                         :external-format :utf-8)
      (write-string "{}" out))
    (list
     (namestring (uiop:ensure-directory-pathname empty))
     (namestring (uiop:ensure-directory-pathname project))
     (namestring store-path))))

(defun trust-bool (value)
  (if value 1 0))

(defun run-settings-load-project-trust (empty project store-path)
  (let ((store (cadr-cli::make-project-trust-store store-path)))
    (list
     (trust-bool
      (cadr-cli::trust-requiring-project-resources-p empty))
     (trust-bool
      (cadr-cli::trust-requiring-project-resources-p project))
     (trust-bool
      (cadr-cli::resolve-project-trusted
       store empty :default :ask :has-ui-p nil))
     (trust-bool
      (cadr-cli::resolve-project-trusted
       store project :default :ask :has-ui-p nil))
     (trust-bool
      (cadr-cli::resolve-project-trusted
       store project :default :always :has-ui-p nil))
     (trust-bool
      (cadr-cli::resolve-project-trusted
       store project :default :never :has-ui-p nil))
     (trust-bool
      (cadr-cli::resolve-project-trusted
       store project :override t :override-supplied-p t))
     (trust-bool
      (cadr-cli::resolve-project-trusted
       store project :override nil :override-supplied-p t)))))

(defun config-value-equals (config environment expected)
  (let ((value
          (cadr-cli::resolve-config-value
           config
           :environment environment)))
    (if (and value (string= value expected))
        1
        0)))

(defun config-value-missing-p (config environment)
  (if (cadr-cli::resolve-config-value
       config
       :environment environment)
      0
      1))

(defun run-settings-load-config-value ()
  (let ((environment '(("GOAL20_CV_FOO" . "bar"))))
    (list
     (config-value-equals "abc" environment "abc")
     (config-value-equals "$GOAL20_CV_FOO" environment "bar")
     (config-value-equals "${GOAL20_CV_FOO}" environment "bar")
     (config-value-equals "$$x" environment "$x")
     (config-value-equals "$!x" environment "!x")
     (config-value-missing-p "$GOAL20_CV_NOPE" environment)
     (config-value-equals
      "pre-$GOAL20_CV_FOO-post" environment "pre-bar-post")
     (if (uiop:string-prefix-p "!" "!echo hi") 1 0))))

(defun http-idle-label-flag (timeout-ms expected)
  (if (string= (cadr-cli::http-idle-timeout-label timeout-ms) expected)
      1
      0))

(defun run-settings-load-http-idle ()
  ;; Named HTTP_IDLE_TIMEOUT_CHOICES only. Do not exact a custom
  ;; timeout (cadr ~,3G vs pi `${ms/1000} sec`).
  (list
   (http-idle-label-flag 30000 "30 sec")
   (http-idle-label-flag 60000 "1 min")
   (http-idle-label-flag 120000 "2 min")
   (http-idle-label-flag 300000 "5 min")
   (http-idle-label-flag 0 "disabled")))

(defun measure-settings-load ()
  (destructuring-bind (empty project store-path)
      (stage-settings-load-trust)
    (let ((observed
            (run-settings-load-project-trust empty project store-path))
          (config (run-settings-load-config-value))
          (idle (run-settings-load-http-idle)))
      (json-object
       "observed"
       (json-object
        "tr_empty" (nth 0 observed)
        "tr_proj" (nth 1 observed)
        "rs_empty" (nth 2 observed)
        "rs_ask" (nth 3 observed)
        "rs_always" (nth 4 observed)
        "rs_never" (nth 5 observed)
        "rs_ov_yes" (nth 6 observed)
        "rs_ov_no" (nth 7 observed)
        "cv_lit" (nth 0 config)
        "cv_dol" (nth 1 config)
        "cv_brace" (nth 2 config)
        "cv_esc" (nth 3 config)
        "cv_bang" (nth 4 config)
        "cv_miss" (nth 5 config)
        "cv_mix" (nth 6 config)
        "cv_cmd" (nth 7 config)
        "ht_30" (nth 0 idle)
        "ht_1m" (nth 1 idle)
        "ht_2m" (nth 2 idle)
        "ht_5m" (nth 3 idle)
        "ht_off" (nth 4 idle))
       "project_trust"
       (collect "settings_load.project_trust"
                (lambda ()
                  (lambda ()
                    (run-settings-load-project-trust
                     empty project store-path))))
       "config_value"
       (collect "settings_load.config_value"
                (lambda ()
                  (lambda ()
                    (run-settings-load-config-value))))
       "http_idle"
       (collect "settings_load.http_idle"
                (lambda ()
                  (lambda ()
                    (run-settings-load-http-idle))))))))

(defun copy-resource-fixture (name destination)
  (ensure-directories-exist destination)
  (uiop:copy-file (fixture-path name) destination)
  destination)

(defun stage-resource-layout ()
  (let* ((agent
           (merge-pathnames "resource-agent/" *scratch-directory*))
         (cwd
           (merge-pathnames "resource-cwd/" *scratch-directory*))
         (agent-skill
           (merge-pathnames "skills/shared/" agent))
         (project-skill-cadr
           (merge-pathnames ".cadr/skills/shared/" cwd))
         (project-skill-pi
           (merge-pathnames ".pi/skills/shared/" cwd))
         (agent-prompt
           (merge-pathnames "prompts/" agent))
         (project-prompt-cadr
           (merge-pathnames ".cadr/prompts/" cwd))
         (project-prompt-pi
           (merge-pathnames ".pi/prompts/" cwd)))
    (copy-resource-fixture
     "resource-skill-global.md"
     (merge-pathnames "SKILL.md" agent-skill))
    (copy-resource-fixture
     "resource-skill-project.md"
     (merge-pathnames "SKILL.md" project-skill-cadr))
    (copy-resource-fixture
     "resource-skill-project.md"
     (merge-pathnames "SKILL.md" project-skill-pi))
    (copy-resource-fixture
     "resource-prompt-global.md"
     (merge-pathnames "review.md" agent-prompt))
    (copy-resource-fixture
     "resource-prompt-project.md"
     (merge-pathnames "review.md" project-prompt-cadr))
    (copy-resource-fixture
     "resource-prompt-project.md"
     (merge-pathnames "review.md" project-prompt-pi))
    (copy-resource-fixture
     "resource-agents.md"
     (merge-pathnames "AGENTS.md" cwd))
    (copy-resource-fixture
     "resource-system.md"
     (merge-pathnames ".cadr/SYSTEM.md" cwd))
    (copy-resource-fixture
     "resource-system.md"
     (merge-pathnames ".pi/SYSTEM.md" cwd))
    (values cwd agent
            project-skill-cadr agent-skill
            project-prompt-cadr agent-prompt)))

(defun run-resource-loader (cwd agent project-skill agent-skill
                            project-prompt agent-prompt)
  (let ((loader
          (cadr-cli::make-default-resource-loader
           :cwd cwd
           :agent-directory agent
           :project-trusted-p t
           :no-skills-p t
           :no-prompts-p t
           :no-themes-p t
           :explicit-skill-paths
           (list (namestring project-skill)
                 (namestring agent-skill))
           :explicit-prompt-paths
           (list (namestring project-prompt)
                 (namestring agent-prompt)))))
    (cadr-cli::reload-resources loader)))

(defun stage-package-layout ()
  (let* ((agent
           (merge-pathnames "package-agent/" *scratch-directory*))
         (cwd
           (merge-pathnames "package-cwd/" *scratch-directory*))
         (pkg (merge-pathnames "pkg/" agent))
         (project-cadr
           (merge-pathnames ".cadr/" cwd))
         (project-pi
           (merge-pathnames ".pi/" cwd)))
    (ensure-directories-exist
     (merge-pathnames "skills/goal20/" pkg))
    (ensure-directories-exist
     (merge-pathnames "prompts/" pkg))
    (ensure-directories-exist
     (merge-pathnames "themes/" pkg))
    (ensure-directories-exist
     (merge-pathnames "settings.json" agent))
    (ensure-directories-exist
     (merge-pathnames "settings.json" project-cadr))
    (ensure-directories-exist
     (merge-pathnames "settings.json" project-pi))
    (uiop:copy-file
     (fixture-path "package-manifest.json")
     (merge-pathnames "package.json" pkg))
    (uiop:copy-file
     (fixture-path "package-skill.md")
     (merge-pathnames "skills/goal20/SKILL.md" pkg))
    (uiop:copy-file
     (fixture-path "package-prompt.md")
     (merge-pathnames "prompts/goal20.md" pkg))
    (uiop:copy-file
     (fixture-path "package-theme.json")
     (merge-pathnames "themes/goal20.json" pkg))
    (uiop:copy-file
     (fixture-path "package-extension.js")
     (merge-pathnames "extension.js" pkg))
    (uiop:copy-file
     (fixture-path "package-settings-global.json")
     (merge-pathnames "settings.json" agent))
    (uiop:copy-file
     (fixture-path "package-settings-project.json")
     (merge-pathnames "settings.json" project-cadr))
    (uiop:copy-file
     (fixture-path "package-settings-project.json")
     (merge-pathnames "settings.json" project-pi))
    (values cwd agent project-cadr)))

(defun run-package-manager (manager agent project-config)
  (cadr-cli::package-resource-paths
   (cadr-cli::materialize-package-records
    (cadr-cli::configured-package-records
     manager
     :global-base agent
     :project-base project-config)
    (merge-pathnames "packages/" agent)
    (merge-pathnames "packages/" project-config))))

(defun measure-package-manager ()
  (multiple-value-bind (cwd agent project-config)
      (stage-package-layout)
    (declare (ignore cwd))
    (let* ((manager
             (cadr-cli::make-settings-manager
              :global-path
              (merge-pathnames "settings.json" agent)
              :project-path
              (merge-pathnames "settings.json" project-config)
              :project-trusted-p t))
           (records
             (cadr-cli::configured-package-records
              manager
              :global-base agent
              :project-base project-config))
           (paths
             (run-package-manager manager agent project-config)))
      (json-object
       "observed"
       (json-object
        "package_count" (length records)
        "skill_count" (length (getf paths :skills))
        "prompt_count" (length (getf paths :prompts))
        "theme_count" (length (getf paths :themes))
        "extension_count" (length (getf paths :extensions)))
       "resolve"
       (collect "package_manager.resolve"
                (lambda ()
                  (lambda ()
                    (run-package-manager
                     manager agent project-config))))))))

(defun measure-resource-loader ()
  (multiple-value-bind
        (cwd agent project-skill agent-skill project-prompt agent-prompt)
      (stage-resource-layout)
    (let* ((snapshot
             (run-resource-loader
              cwd agent project-skill agent-skill
              project-prompt agent-prompt))
           (skills
             (cadr-cli::resource-snapshot-skills snapshot))
           (prompts
             (cadr-cli::resource-snapshot-prompts snapshot)))
      (json-object
       "observed"
       (json-object
        "skill_count" (length skills)
        "prompt_count" (length prompts)
        "skill_names"
        (json-array
         (sort (mapcar #'cadr-agent:skill-name skills) #'string<))
        "prompt_names"
        (json-array
         (sort
          (mapcar #'cadr-agent:prompt-template-name prompts)
          #'string<))
        "skill_from_project"
        (if (some
             (lambda (skill)
               (search
                "project overlay"
                (cadr-agent:skill-description skill)))
             skills)
            1
            0)
        "prompt_from_project"
        (if (some
             (lambda (prompt)
               (search
                "project review"
                (cadr-agent:prompt-template-content prompt)))
             prompts)
            1
            0)
        "context_file_count"
        (length
         (cadr-cli::resource-snapshot-context-files snapshot))
        "system_prompt"
        (if (cadr-cli::resource-snapshot-system-prompt-path snapshot)
            1
            0))
       "reload"
       (collect "resource_loader.reload"
                (lambda ()
                  (lambda ()
                    (run-resource-loader
                     cwd agent project-skill agent-skill
                     project-prompt agent-prompt))))))))

;;; ---------------------------------------------------------------------

(defparameter *session-discovery-file-count* 32)

(defun session-discovery-directory ()
  (merge-pathnames "discovery-sessions/" *scratch-directory*))

(defun stage-session-discovery ()
  (let ((directory
          (uiop:ensure-directory-pathname
           (session-discovery-directory))))
    (ensure-directories-exist directory)
    (loop for index from 0 below *session-discovery-file-count*
          for name = (format nil "sess-~2,'0D.jsonl" index)
          for path = (merge-pathnames name directory)
          for stamp = (+ 1700000000 index)
          do
          (uiop:copy-file (fixture-path "session.jsonl") path)
          (sb-posix:utimes (namestring path) stamp stamp))
    directory))

(defun session-discovery-probe (directory)
  (let ((best-path nil)
        (best-mtime nil)
        (file-count 0)
        (header-count 0)
        (session-id ""))
    (dolist
        (path
         (directory
          (merge-pathnames
           (make-pathname :name :wild :type "jsonl")
           (uiop:ensure-directory-pathname directory))))
      (incf file-count)
      (let ((header
              (cadr-agent::read-session-header-for-discovery path)))
        (when header
          (incf header-count)
          (let ((mtime (sb-posix:stat-mtime (sb-posix:stat path))))
            (when (or (null best-mtime) (>= mtime best-mtime))
              (setf best-mtime mtime
                    best-path path
                    session-id
                    (or (cadr-ai::json-get header "id") "")))))))
    (values best-path file-count header-count session-id)))

(defun measure-session-discovery ()
  (let ((directory (stage-session-discovery)))
    (multiple-value-bind
          (best-path file-count header-count session-id)
        (session-discovery-probe directory)
      (json-object
       "observed"
       (json-object
        "file_count" file-count
        "header_count" header-count
        "found" (if best-path 1 0)
        "session_id" session-id
        "most_recent_name"
        (if best-path (file-namestring best-path) ""))
       "header_probe"
       (collect "session_discovery.header_probe"
                (lambda ()
                  (lambda ()
                    (session-discovery-probe directory))))))))

(defun session-export-html-path ()
  (merge-pathnames "export/session.html" *scratch-directory*))

(defun measure-session-export-html ()
  (let* ((session
           (cadr-agent:load-session (fixture-path "session.jsonl")))
         (dest (session-export-html-path)))
    (ensure-directories-exist dest)
    (cadr-agent:export-session-html session dest :theme-name "dark")
    (let ((html
            (uiop:read-file-string dest :external-format :utf-8)))
      (json-object
       "observed"
       (json-object
        "html_chars" (length html)
        "has_accent" (if (search "--accent:" html) 1 0)
        "theme" "dark")
       "to_html"
       (collect "session_export_html.to_html"
                (lambda ()
                  (lambda ()
                    (cadr-agent:export-session-html
                     session dest :theme-name "dark"))))))))

(defparameter *cbor-roundtrip-hex*
  '("f6" "f4" "f5" "00" "01" "0a" "17" "1818" "1864" "1903e8"
    "20" "29" "626869" "60" "80" "a0"))

(defun cbor-hex-octets (hex)
  (let ((bytes
          (make-array
           (/ (length hex) 2)
           :element-type '(unsigned-byte 8))))
    (loop for index below (length bytes)
          do
          (setf (aref bytes index)
                (parse-integer
                 hex
                 :start (* index 2)
                 :end (+ (* index 2) 2)
                 :radix 16)))
    bytes))

(defun cbor-octets-hex (bytes)
  (string-downcase
   (with-output-to-string (stream)
     (loop for byte across bytes
           do (format stream "~2,'0x" byte)))))

(defun protocol-cbor-roundtrip ()
  (let ((hexes nil))
    (dolist (hex *cbor-roundtrip-hex*)
      (let* ((octets (cbor-hex-octets hex))
             (value (cadr-protocol:decode-cbor octets))
             (encoded (cadr-protocol:encode-cbor value)))
        (push (cbor-octets-hex encoded) hexes)))
    (nreverse hexes)))

(defun measure-protocol-cbor ()
  (let ((hexes (protocol-cbor-roundtrip)))
    (json-object
     "observed"
     (json-object
      "vector_count" (length hexes)
      "roundtrip_hex" (apply #'concatenate 'string hexes)
      "match"
      (if (equal hexes *cbor-roundtrip-hex*) 1 0))
     "roundtrip"
     (collect "protocol_cbor.roundtrip"
              (lambda ()
                (lambda ()
                  (protocol-cbor-roundtrip)))))))

(defun agent-schema-edit-schema ()
  (json-object
   "type" "object"
   "properties"
   (json-object
    "path" (json-object "type" "string" "minLength" 1)
    "edits"
    (json-object
     "type" "array"
     "minItems" 1
     "items"
     (json-object
      "type" "object"
      "properties"
      (json-object
       "oldText" (json-object "type" "string")
       "newText" (json-object "type" "string"))
      "required" (json-array '("oldText" "newText"))
      "additionalProperties" nil)))
   "required" (json-array '("path" "edits"))
   "additionalProperties" nil))

(defun agent-schema-good-arguments ()
  (json-object
   "path" "README.md"
   "edits"
   (json-array
    (list (json-object "oldText" "old" "newText" "new")))))

(defun agent-schema-bad-arguments ()
  (json-object
   "path" "README.md"
   "edits"
   (json-array (list (json-object "oldText" "old")))))

(defun agent-schema-validate-ok-fail (tool good bad)
  (cadr-agent:validate-tool-arguments tool good)
  (handler-case
      (progn
        (cadr-agent:validate-tool-arguments tool bad)
        0)
    (cadr-agent:schema-validation-error () 1)))

(defun measure-agent-schema ()
  (let* ((tool
           (cadr-ai:make-tool
            :name "edit"
            :description "Edit"
            :parameters (agent-schema-edit-schema)
            :executor (lambda (id arguments)
                        (declare (ignore id arguments)))))
         (good (agent-schema-good-arguments))
         (bad (agent-schema-bad-arguments))
         (fail (agent-schema-validate-ok-fail tool good bad)))
    (json-object
     "observed"
     (json-object
      "ok" 1
      "fail" fail
      "tool" "edit")
     "validate_ok_fail"
     (collect "agent_schema.validate_ok_fail"
              (lambda ()
                (lambda ()
                  (agent-schema-validate-ok-fail
                   tool
                   (agent-schema-good-arguments)
                   (agent-schema-bad-arguments))))))))

(defun protocol-codec-list-request ()
  (json-object
   "type" "request"
   "id" "request-1"
   "request" (json-object "command" "list")))

(defun protocol-codec-roundtrip ()
  (let* ((message (protocol-codec-list-request))
         (frame (cadr-protocol:encode-client-message message))
         (decoder (cadr-protocol:make-client-message-decoder))
         (messages
           (cadr-protocol:message-decoder-push decoder frame)))
    (cadr-protocol:message-decoder-end decoder)
    (let* ((decoded (first messages))
           (request
             (and decoded (cadr-ai::json-get decoded "request"))))
      (list
       (length frame)
       (length messages)
       (and decoded (cadr-ai::json-get decoded "type"))
       (and decoded (cadr-ai::json-get decoded "id"))
       (and request (cadr-ai::json-get request "command"))))))

(defun measure-protocol-codec ()
  (let ((observed (protocol-codec-roundtrip)))
    (json-object
     "observed"
     (json-object
      "frame_bytes" (first observed)
      "message_count" (second observed)
      "type" (or (third observed) "")
      "id" (or (fourth observed) "")
      "command" (or (fifth observed) ""))
     "roundtrip"
     (collect "protocol_codec.roundtrip"
              (lambda ()
                (lambda ()
                  (protocol-codec-roundtrip)))))))

(defparameter *agent-proxy-sse-json*
  '("{\"type\":\"start\"}"
    "{\"type\":\"text_start\",\"contentIndex\":0}"
    "{\"type\":\"text_delta\",\"contentIndex\":0,\"delta\":\"ok\"}"
    "{\"type\":\"text_end\",\"contentIndex\":0}"
    "{\"type\":\"done\",\"reason\":\"stop\",\"usage\":{\"input\":1,\"output\":2,\"cacheRead\":0,\"cacheWrite\":0,\"totalTokens\":3,\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"total\":0}}}"))

(defun run-agent-proxy ()
  (let ((event-count 0)
        (model
          (cadr-ai:make-model
           :id "proxy"
           :provider :openai
           :api :openai-responses
           :base-url "https://example.invalid"
           :max-tokens 100)))
    (let ((response
            (cadr-agent:stream-proxy
             model
             (cadr-ai:make-context
              :system-prompt "system"
              :messages
              (list (cadr-ai:make-user-message :content "hi")))
             (lambda (event)
               (declare (ignore event))
               (incf event-count))
             :auth-token "secret"
             :proxy-url "https://proxy.invalid"
             :request-sse-function
             (lambda (request consumer &key abort-p)
               (declare (ignore request abort-p))
               (dolist (json *agent-proxy-sse-json*)
                 (funcall
                  consumer
                  (cadr-ai::make-sse-event :data json)))))))
      (let ((block
              (first (cadr-ai:assistant-message-content response))))
        (list
         event-count
         (if (typep block 'cadr-ai:text-content)
             (cadr-ai:text-content-text block)
             "")
         (or (cadr-ai:usage-total
              (cadr-ai:assistant-message-usage response))
             0))))))

(defun measure-agent-proxy ()
  (let ((observed (run-agent-proxy)))
    (json-object
     "observed"
     (json-object
      "event_count" (first observed)
      "text" (second observed)
      "usage_total" (third observed))
     "stream_roundtrip"
     (collect "agent_proxy.stream_roundtrip"
              (lambda ()
                (lambda ()
                  (run-agent-proxy)))))))

(defparameter *oauth-pkce-verifier*
  "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
(defparameter *oauth-pkce-state* "goal20-oauth-state")

(defun run-oauth-pkce ()
  (let* ((challenge
           (cadr-ai:pkce-challenge *oauth-pkce-verifier*))
         (openai
           (cadr-ai:openai-authorization-url
            challenge *oauth-pkce-state*))
         (anthropic
           (cadr-ai:anthropic-authorization-url
            challenge *oauth-pkce-state*)))
    (list
     challenge
     openai
     anthropic
     (if (search challenge openai) 1 0)
     (if (search challenge anthropic) 1 0))))

(defun measure-oauth-pkce ()
  (let ((observed (run-oauth-pkce)))
    (json-object
     "observed"
     (json-object
      "challenge" (first observed)
      "openai_has_challenge" (fourth observed)
      "anthropic_has_challenge" (fifth observed)
      "openai_prefix"
      (subseq (second observed) 0
              (or (position #\? (second observed)) 0))
      "anthropic_prefix"
      (subseq (third observed) 0
              (or (position #\? (third observed)) 0)))
     "challenge_urls"
     (collect "oauth_pkce.challenge_urls"
              (lambda ()
                (lambda ()
                  (run-oauth-pkce)))))))

(defun noop-device-sleep (seconds)
  (declare (ignore seconds)))

(defun frozen-device-time ()
  0)

(defun run-oauth-pkce-device-poll ()
  (let ((ok
          (cadr-ai:poll-device-authorization
           (lambda () (list :status :complete :value "tok"))
           :interval 5
           :expires-in 900
           :sleep-function #'noop-device-sleep
           :time-function #'frozen-device-time))
        (fail
          (handler-case
              (progn
                (cadr-ai:poll-device-authorization
                 (lambda () (list :status :failed :message "nope"))
                 :interval 5
                 :expires-in 900
                 :sleep-function #'noop-device-sleep
                 :time-function #'frozen-device-time)
                0)
            (error () 1)))
        (cancel
          (handler-case
              (progn
                (cadr-ai:poll-device-authorization
                 (lambda () (list :status :pending))
                 :interval 5
                 :expires-in 900
                 :cancelled-p (constantly t)
                 :sleep-function #'noop-device-sleep
                 :time-function #'frozen-device-time)
                0)
            (error () 1))))
    (list
     (if (string= ok "tok") 1 0)
     fail
     cancel)))

(defparameter *oauth-auth-json-fixture*
  "{\"openai\":{\"type\":\"api_key\",\"key\":\"sk-test\"},\"anthropic\":{\"type\":\"oauth\",\"access\":\"acc\",\"refresh\":\"ref\",\"expires\":9999999999}}")

(defun write-oauth-auth-json-file (path text)
  (ensure-directories-exist path)
  (with-open-file (stream path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create
                          :external-format :utf-8)
    (write-string text stream))
  (namestring (truename path)))

(defun run-oauth-pkce-device-auth-json ()
  (let* ((root
           (merge-pathnames
            "oauth-auth-json/"
            *scratch-directory*))
         (good
           (write-oauth-auth-json-file
            (merge-pathnames "auth.json" root)
            *oauth-auth-json-fixture*))
         (bad
           (write-oauth-auth-json-file
            (merge-pathnames "bad.json" root)
            "["))
         (ak (cadr-ai:read-auth-credential good :openai))
         (oa (cadr-ai:read-auth-credential good :anthropic))
         (miss (cadr-ai:read-auth-credential good :github)))
    (list
     (if (typep ak 'cadr-ai:api-key-credential) 1 0)
     (if (and (typep ak 'cadr-ai:api-key-credential)
              (= (length (cadr-ai:api-key-credential-key ak)) 7))
         1
         0)
     (if (typep oa 'cadr-ai:oauth-credential) 1 0)
     (if (and (typep oa 'cadr-ai:oauth-credential)
              (= (length (cadr-ai:oauth-credential-access oa)) 3))
         1
         0)
     (if miss 0 1)
     (handler-case
         (progn
           (cadr-ai:read-auth-credential bad :openai)
           0)
       (error () 1)))))

(defun copilot-url-flag (token enterprise expected)
  (if (string=
       (cadr-ai:github-copilot-base-url token enterprise)
       expected)
      1
      0))

(defun run-oauth-pkce-device-copilot-url ()
  (list
   (copilot-url-flag
    nil nil
    "https://api.individual.githubcopilot.com")
   (copilot-url-flag
    "tid=test;exp=1;proxy-ep=proxy.individual.githubcopilot.com;"
    nil
    "https://api.individual.githubcopilot.com")
   (copilot-url-flag
    "tid=test;exp=1;proxy-ep=proxy.enterprise.githubcopilot.com;"
    nil
    "https://api.enterprise.githubcopilot.com")
   (copilot-url-flag
    nil "example.com"
    "https://copilot-api.example.com")))

(defun copilot-auth-credential (access &optional enterprise)
  (cadr-ai:make-oauth-credential
   :provider :github-copilot
   :access (or access "")
   :refresh "r"
   :expires 1
   :metadata
   (when enterprise
     (list (cons "enterpriseUrl" enterprise)))))

(defun copilot-auth-flag (access enterprise expected)
  (let ((result
          (cadr-ai::github-copilot-oauth-to-auth
           (copilot-auth-credential access enterprise))))
    (if (and (string=
              (cadr-ai:runtime-auth-result-api-key result)
              (or access ""))
             (string=
              (cadr-ai:runtime-auth-result-base-url result)
              expected))
        1
        0)))

(defun run-oauth-pkce-device-copilot-auth ()
  (list
   (copilot-auth-flag
    "" nil
    "https://api.individual.githubcopilot.com")
   (copilot-auth-flag
    "tid=test;exp=1;proxy-ep=proxy.individual.githubcopilot.com;"
    nil
    "https://api.individual.githubcopilot.com")
   (copilot-auth-flag
    "tid=test;exp=1;proxy-ep=proxy.enterprise.githubcopilot.com;"
    nil
    "https://api.enterprise.githubcopilot.com")
   (copilot-auth-flag
    "" "example.com"
    "https://copilot-api.example.com")
   (let ((result
           (cadr-ai::github-copilot-oauth-to-auth
            (copilot-auth-credential "tok" nil))))
     (if (string= (cadr-ai:runtime-auth-result-api-key result) "tok")
         1
         0))))

(defparameter *cloudflare-gateway-template*
  "https://gateway.ai.cloudflare.com/v1/{CLOUDFLARE_ACCOUNT_ID}/{CLOUDFLARE_GATEWAY_ID}/openai")

(defun cloudflare-url-flag (base account gateway expected)
  (handler-case
      (if (string=
           (cadr-ai:materialize-cloudflare-url base account gateway)
           expected)
          1
          0)
    (error () 0)))

(defun run-oauth-pkce-device-cloudflare-url ()
  (list
   (cloudflare-url-flag
    "https://api.example.com/v1" "acct" "gw"
    "https://api.example.com/v1")
   (cloudflare-url-flag
    *cloudflare-gateway-template* "acct" "gw"
    "https://gateway.ai.cloudflare.com/v1/acct/gw/openai")
   (cloudflare-url-flag
    "https://x/{CLOUDFLARE_GATEWAY_ID}" "acct" "gw"
    "https://x/gw")))

(defun radius-gateway-flag (value expected)
  (if (string= (cadr-ai::normalize-radius-gateway value) expected)
      1
      0))

(defun run-oauth-pkce-device-radius-gateway ()
  (list
   (radius-gateway-flag
    "https://radius.example.com/"
    "https://radius.example.com")
   (radius-gateway-flag
    "https://radius.example.com"
    "https://radius.example.com")
   (radius-gateway-flag
    "http://localhost:8080/"
    "http://localhost:8080")))

(defun measure-oauth-pkce-device ()
  (let ((poll (run-oauth-pkce-device-poll))
        (auth (run-oauth-pkce-device-auth-json))
        (copilot (run-oauth-pkce-device-copilot-url))
        (cloudflare (run-oauth-pkce-device-cloudflare-url))
        (radius (run-oauth-pkce-device-radius-gateway))
        (copilot-auth (run-oauth-pkce-device-copilot-auth)))
    (json-object
     "observed"
     (json-object
      "dc_ok" (first poll)
      "dc_fail" (second poll)
      "dc_cancel" (third poll)
      "ak_ok" (nth 0 auth)
      "ak_len" (nth 1 auth)
      "oa_ok" (nth 2 auth)
      "oa_len" (nth 3 auth)
      "auth_miss" (nth 4 auth)
      "auth_bad" (nth 5 auth)
      "gc_def" (nth 0 copilot)
      "gc_ind" (nth 1 copilot)
      "gc_ent" (nth 2 copilot)
      "gc_dom" (nth 3 copilot)
      "cf_plain" (nth 0 cloudflare)
      "cf_ok" (nth 1 cloudflare)
      "cf_gw" (nth 2 cloudflare)
      "rg_slash" (nth 0 radius)
      "rg_plain" (nth 1 radius)
      "rg_http" (nth 2 radius)
      "ga_def" (nth 0 copilot-auth)
      "ga_ind" (nth 1 copilot-auth)
      "ga_ent" (nth 2 copilot-auth)
      "ga_dom" (nth 3 copilot-auth)
      "ga_key" (nth 4 copilot-auth))
     "poll"
     (collect "oauth_pkce_device.poll"
              (lambda ()
                (lambda ()
                  (run-oauth-pkce-device-poll))))
     "auth_json"
     (collect "oauth_pkce_device.auth_json"
              (lambda ()
                (lambda ()
                  (run-oauth-pkce-device-auth-json))))
     "copilot_url"
     (collect "oauth_pkce_device.copilot_url"
              (lambda ()
                (lambda ()
                  (run-oauth-pkce-device-copilot-url))))
     "cloudflare_url"
     (collect "oauth_pkce_device.cloudflare_url"
              (lambda ()
                (lambda ()
                  (run-oauth-pkce-device-cloudflare-url))))
     "radius_gateway"
     (collect "oauth_pkce_device.radius_gateway"
              (lambda ()
                (lambda ()
                  (run-oauth-pkce-device-radius-gateway))))
     "copilot_auth"
     (collect "oauth_pkce_device.copilot_auth"
              (lambda ()
                (lambda ()
                  (run-oauth-pkce-device-copilot-auth)))))))

(defun llama-url-flag (value expected)
  (handler-case
      (if (string=
           (cadr-cli::normalize-llama-server-url value)
           expected)
          1
          0)
    (error () 0)))

(defun llama-url-error-flag (value)
  (handler-case
      (progn
        (cadr-cli::normalize-llama-server-url value)
        0)
    (error () 1)))

(defun run-cli-extensions-llama-url ()
  (list
   (llama-url-flag
    "http://127.0.0.1:8080/v1/"
    "http://127.0.0.1:8080")
   (llama-url-flag
    "https://example.com/foo/v1?x=1#h"
    "https://example.com/foo")
   (llama-url-error-flag "file:///tmp/llama")
   (handler-case
       (if (string=
            (cadr-cli::llama-inference-url
             "http://127.0.0.1:8080/v1/")
            "http://127.0.0.1:8080/v1")
           1
           0)
     (error () 0))
   (if (string= (cadr-cli::format-llama-bytes 512) "512 B")
       1
       0)
   (if (search "KiB" (cadr-cli::format-llama-bytes 1024))
       1
       0)))

(defparameter *hf-lookup-env-names*
  '("HF_TOKEN" "HF_TOKEN_PATH" "HF_HOME" "XDG_CACHE_HOME" "HOME"))

(defun write-hf-lookup-file (path text)
  (ensure-directories-exist path)
  (with-open-file (stream path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create
                          :external-format :utf-8)
    (write-string text stream))
  (namestring (truename path)))

(defun hf-lookup-fixtures ()
  (let* ((root
           (merge-pathnames
            "hf-lookup/"
            *scratch-directory*))
         (empty-home
           (namestring
            (ensure-directories-exist
             (merge-pathnames "empty-home/" root))))
         (hf-home
           (namestring
            (ensure-directories-exist
             (merge-pathnames "hf-home/" root))))
         (token-path
           (write-hf-lookup-file
            (merge-pathnames "token-path" root)
            "from-path")))
    (write-hf-lookup-file
     (merge-pathnames "token"
                      (uiop:ensure-directory-pathname hf-home))
     "from-home")
    (list empty-home token-path hf-home)))

(defun call-with-hf-lookup-env (bindings thunk)
  (let ((saved
          (mapcar
           (lambda (name)
             (cons name (uiop:getenv name)))
           *hf-lookup-env-names*)))
    (unwind-protect
         (progn
           (dolist (name *hf-lookup-env-names*)
             (sb-posix:unsetenv name))
           (dolist (pair bindings)
             (when (cdr pair)
               (sb-posix:setenv (car pair) (cdr pair) 1)))
           (funcall thunk))
      (dolist (pair saved)
        (if (cdr pair)
            (sb-posix:setenv (car pair) (cdr pair) 1)
            (sb-posix:unsetenv (car pair)))))))

(defun hf-token-equals (expected)
  (let ((token (cadr-cli::find-hugging-face-token)))
    (if (and token (string= token expected))
        1
        0)))

(defun hf-token-missing-p ()
  (if (cadr-cli::find-hugging-face-token) 0 1))

(defun run-cli-extensions-hf-token ()
  (destructuring-bind (empty-home token-path hf-home)
      (hf-lookup-fixtures)
    (list
     (call-with-hf-lookup-env
      (list (cons "HOME" empty-home)
            (cons "HF_TOKEN" "  tok  "))
      (lambda () (hf-token-equals "tok")))
     (call-with-hf-lookup-env
      (list (cons "HOME" empty-home)
            (cons "HF_TOKEN_PATH" token-path))
      (lambda () (hf-token-equals "from-path")))
     (call-with-hf-lookup-env
      (list (cons "HOME" empty-home)
            (cons "HF_HOME" hf-home))
      (lambda () (hf-token-equals "from-home")))
     (call-with-hf-lookup-env
      (list (cons "HOME" empty-home))
      (lambda () (hf-token-missing-p)))
     (call-with-hf-lookup-env
      (list (cons "HOME" empty-home)
            (cons "HF_TOKEN" "   "))
      (lambda () (hf-token-missing-p))))))

(defun llama-catalog-info (id status &key modalities ctx)
  (cadr-cli::make-llama-model-info
   :id id
   :status status
   :input-modalities modalities
   :context-window ctx))

(defun run-cli-extensions-llama-catalog ()
  ;; Loaded only. Sleeping/unloaded stay out. Do not exact
  ;; n_ctx_train-only fallback vs cadr training-context-window
  ;; when both are set differently.
  (let* ((controller (cadr-cli::make-llama-provider-controller))
         (models
           (progn
             (cadr-cli::llama-provider-set-catalog
              controller
              (list
               (llama-catalog-info "loaded-text" :loaded :ctx 4096)
               (llama-catalog-info
                "loaded-img" :loaded
                :modalities '("image") :ctx 8192)
               (llama-catalog-info "fb" :loaded)
               (llama-catalog-info "sleeping" :sleeping :ctx 4096)
               (llama-catalog-info "unloaded" :unloaded))
              "http://127.0.0.1:8080/")
             (cadr-ai:runtime-provider-models
              (cadr-cli::llama-provider-controller-provider
               controller))))
         (text
           (find "loaded-text" models
                 :key #'cadr-ai:model-id :test #'string=))
         (img
           (find "loaded-img" models
                 :key #'cadr-ai:model-id :test #'string=))
         (fb
           (find "fb" models
                 :key #'cadr-ai:model-id :test #'string=)))
    (list
     (length models)
     (if (and img (cadr-ai:model-supports-images-p img)) 1 0)
     (if (and text (= (cadr-ai:model-context-window text) 4096)) 1 0)
     (if (and img
              (string=
               (cadr-ai:model-base-url img)
               "http://127.0.0.1:8080/v1"))
         1
         0)
     (if (find "sleeping" models
               :key #'cadr-ai:model-id :test #'string=)
         1
         0)
     (if (and fb (= (cadr-ai:model-context-window fb) 128000))
         1
         0))))

(defun measure-cli-extensions-install ()
  (let ((url (run-cli-extensions-llama-url))
        (token (run-cli-extensions-hf-token))
        (catalog (run-cli-extensions-llama-catalog)))
    (json-object
     "observed"
     (json-object
      "nu_local" (nth 0 url)
      "nu_https" (nth 1 url)
      "nu_file" (nth 2 url)
      "inf_ok" (nth 3 url)
      "fb_b" (nth 4 url)
      "fb_k" (nth 5 url)
      "hf_env" (nth 0 token)
      "hf_path" (nth 1 token)
      "hf_home" (nth 2 token)
      "hf_miss" (nth 3 token)
      "hf_blank" (nth 4 token)
      "lc_n" (nth 0 catalog)
      "lc_img" (nth 1 catalog)
      "lc_ctx" (nth 2 catalog)
      "lc_url" (nth 3 catalog)
      "lc_sleep" (nth 4 catalog)
      "lc_fb" (nth 5 catalog))
     "llama_url"
     (collect "cli_extensions_install.llama_url"
              (lambda ()
                (lambda ()
                  (run-cli-extensions-llama-url))))
     "hf_token"
     (collect "cli_extensions_install.hf_token"
              (lambda ()
                (lambda ()
                  (run-cli-extensions-hf-token))))
     "llama_catalog"
     (collect "cli_extensions_install.llama_catalog"
              (lambda ()
                (lambda ()
                  (run-cli-extensions-llama-catalog)))))))

(defun evals-harness-observation
    (harness test-name score
     &key total-tokens total-ms estimated-cost-usd)
  (apply
   #'cadr-evals:make-harness-observation
   :eval-set "tool access"
   :group-key (format nil "[\"~A\",1]" test-name)
   :test-name test-name
   :file "src/tool-access.eval.ts"
   :harness harness
   :baseline "without-tools"
   :candidates '("with-tools")
   :repetition 1
   :outcome :scored
   :score score
   (append
    (when total-tokens (list :total-tokens total-tokens))
    (when total-ms (list :total-ms total-ms))
    (when estimated-cost-usd
      (list :estimated-cost-usd estimated-cost-usd)))))

(defun evals-harness-observations ()
  (list
   (evals-harness-observation
    "without-tools" "create" 0
    :total-tokens 100 :total-ms 1000 :estimated-cost-usd 0.01d0)
   (evals-harness-observation
    "with-tools" "create" 1
    :total-tokens 120 :total-ms 800 :estimated-cost-usd 0.02d0)
   (evals-harness-observation
    "without-tools" "inspect" 1 :total-tokens 200)
   (evals-harness-observation
    "with-tools" "inspect" 1 :total-tokens 180)))

(defun run-evals-harness-summarize ()
  (let* ((report
           (cadr-evals:summarize-harness-comparisons
            (evals-harness-observations)))
         (sets
           (cadr-evals:harness-comparison-report-eval-sets
            report))
         (comparison
           (first
            (cadr-evals:harness-eval-set-report-comparisons
             (first sets))))
         (correctness
           (cadr-evals:harness-pair-comparison-correctness
            comparison)))
    (list
     (length sets)
     (length
      (cadr-evals:harness-eval-set-report-comparisons
       (first sets)))
     (cadr-evals:correctness-lift-summary-candidate-wins
      correctness)
     (cadr-evals:correctness-lift-summary-ties
      correctness))))

(defun eval-group-key-flag (input repetition expected-id expected-rep)
  (handler-case
      (let* ((text
               (cadr-evals:derive-eval-group-key input repetition))
             (parsed (cadr-ai::parse-json text)))
        (if (and (vectorp parsed)
                 (= 2 (length parsed))
                 (string= (aref parsed 0) expected-id)
                 (= (aref parsed 1) expected-rep))
            1
            0))
    (error () 0)))

(defun eval-artifact-ok-flag (value)
  (if (cadr-evals:parse-eval-harness-iteration-artifact value)
      1
      0))

(defun run-evals-harness-group-key ()
  ;; id-bearing inputs only. Do not exact a no-id SHA path
  ;; (cadr stringify-json vs pi canonicalizeJson key order).
  ;; Do not exact repetition 0 (cadr errors, pi JSON.stringifies).
  (list
   (eval-group-key-flag
    (cadr-ai::json-object "id" "case-1") 1 "case-1" 1)
   (eval-group-key-flag
    (cadr-ai::json-object "id" "  case-2  ") 2 "case-2" 2)
   (eval-artifact-ok-flag
    (cadr-ai::json-object
     "schemaVersion" 1
     "evalSet" "set-a"
     "groupKey" "[\"case-1\",1]"
     "harness" "cadr"
     "baseline" "base"
     "candidates" (vector "cand")
     "repetition" 1))
   (eval-artifact-ok-flag
    (cadr-ai::json-object
     "schemaVersion" 2
     "evalSet" "set-a"
     "groupKey" "k"
     "harness" "cadr"
     "baseline" "base"
     "candidates" (vector "cand")
     "repetition" 1))))

(defun evals-artifact-directory ()
  (let ((directory
          (merge-pathnames
           "eval-artifacts/"
           *scratch-directory*)))
    (ensure-directories-exist directory)
    directory))

(defun evals-persist-artifacts ()
  (cadr-evals:persist-eval-artifact-references
   (list
    (cadr-evals:make-eval-artifact
     :type :session
     :run-id "run-1"
     :attachments
     (list
      (cadr-evals:make-eval-attachment
       :name "session.jsonl"
       :content-type "application/jsonl"
       :body "session-body")))
    (cadr-evals:make-eval-artifact
     :type :source
     :run-id "run-1"
     :attachments
     (list
      (cadr-evals:make-eval-attachment
       :name "source.txt"
       :content-type "text/plain"
       :body "source-body"))))
   "run-1"
   (namestring (evals-artifact-directory))))

(defun run-evals-harness-artifact-persist ()
  (let* ((refs (evals-persist-artifacts))
         (root (evals-artifact-directory))
         (session
           (find "session.jsonl" refs
                 :key #'cadr-evals:eval-artifact-reference-name
                 :test #'string=))
         (source
           (find "source.txt" refs
                 :key #'cadr-evals:eval-artifact-reference-name
                 :test #'string=))
         (session-path
           (and session
                (cadr-evals:eval-artifact-reference-path session)))
         (source-path
           (and source
                (cadr-evals:eval-artifact-reference-path source))))
    (list
     (length refs)
     (if session 1 0)
     (if source 1 0)
     (if (and session-path
              (uiop:string-prefix-p "sessions/" session-path))
         1
         0)
     (if (and source-path
              (uiop:string-prefix-p "sources/" source-path))
         1
         0)
     (if (and session-path
              (probe-file (merge-pathnames session-path root)))
         1
         0)
     (if (and source-path
              (probe-file (merge-pathnames source-path root)))
         1
         0))))

(defun evals-format-flags (text)
  (let ((stripped (cadr-cli::strip-ansi text)))
    (list
     (if (string= stripped "") 1 0)
     (if (search "Eval Comparisons" stripped) 1 0)
     (if (search "Baseline" stripped) 1 0)
     (if (search "Pass rate" stripped) 1 0))))

(defun run-evals-harness-format (empty-report report)
  (append
   (evals-format-flags
    (cadr-evals:format-harness-comparison-report empty-report))
   (evals-format-flags
    (cadr-evals:format-harness-comparison-report report))))

(defun measure-evals-harness ()
  (let* ((observed (run-evals-harness-summarize))
         (group (run-evals-harness-group-key))
         (persist (run-evals-harness-artifact-persist))
         (empty-report
           (cadr-evals:summarize-harness-comparisons nil))
         (report
           (cadr-evals:summarize-harness-comparisons
            (evals-harness-observations)))
         (fmt (run-evals-harness-format empty-report report)))
    (json-object
     "observed"
     (json-object
      "eval_sets" (first observed)
      "comparisons" (second observed)
      "candidate_wins" (third observed)
      "ties" (fourth observed)
      "gk_id" (first group)
      "gk_trim" (second group)
      "art_ok" (third group)
      "art_bad" (fourth group)
      "ap_n" (nth 0 persist)
      "ap_sess" (nth 1 persist)
      "ap_src" (nth 2 persist)
      "ap_sess_prefix" (nth 3 persist)
      "ap_src_prefix" (nth 4 persist)
      "ap_sess_file" (nth 5 persist)
      "ap_src_file" (nth 6 persist)
      "fmt_empty" (nth 0 fmt)
      "fmt_empty_hdr" (nth 1 fmt)
      "fmt_hdr" (nth 5 fmt)
      "fmt_base" (nth 6 fmt)
      "fmt_pass" (nth 7 fmt))
     "summarize"
     (collect "evals_harness.summarize"
              (lambda ()
                (lambda ()
                  (run-evals-harness-summarize))))
     "group_key"
     (collect "evals_harness.group_key"
              (lambda ()
                (lambda ()
                  (run-evals-harness-group-key))))
     "artifact_persist"
     (collect "evals_harness.artifact_persist"
              (lambda ()
                (lambda ()
                  (run-evals-harness-artifact-persist))))
     "format"
     (collect "evals_harness.format"
              (lambda ()
                (lambda ()
                  (cadr-evals:format-harness-comparison-report
                   report)))))))

(defparameter *model-data-generated-at* "2026-01-01T00:00:00.000Z")

(defun model-data-structure ()
  (cadr-ai::json-object
   "anthropic"
   (cadr-ai::json-object "claude-3-opus" "anthropic-messages")
   "openai"
   (cadr-ai::json-object
    "gpt-4o" "openai-completions"
    "gpt-4o-mini" "openai-completions")))

(defun model-data-file-contents ()
  (cadr-ai::json-object
   "anthropic.json"
   "{\"anthropic-messages\":{\"claude-3-opus\":{\"id\":\"claude-3-opus\"}}}"
   "openai.json"
   "{\"openai-completions\":{\"gpt-4o\":{\"id\":\"gpt-4o\"},\"gpt-4o-mini\":{\"id\":\"gpt-4o-mini\"}}}"))

(defun run-ai-crypto-model-data ()
  (let* ((manifest
           (cadr-ai:create-model-data-manifest
            (model-data-structure)
            (model-data-file-contents)
            *model-data-generated-at*))
         (files (cadr-ai::json-get manifest "files")))
    (list
     (cadr-ai::json-get manifest "schemaVersion")
     (cadr-ai::json-get manifest "structureHash")
     (cadr-ai::json-get manifest "generatedAt")
     (hash-table-count files)
     (gethash "openai.json" files)
     (gethash "anthropic.json" files))))

(defun measure-ai-crypto-model-data ()
  (let ((observed (run-ai-crypto-model-data)))
    (json-object
     "observed"
     (json-object
      "schema_version" (first observed)
      "structure_hash" (second observed)
      "generated_at" (third observed)
      "file_count" (fourth observed)
      "openai_json_hash" (fifth observed)
      "anthropic_json_hash" (sixth observed))
     "manifest"
     (collect "ai_crypto_model_data.manifest"
              (lambda ()
                (lambda ()
                  (run-ai-crypto-model-data)))))))

(defun run-ai-crypto-hmac ()
  (list
   (cadr-ai::octets-hex
    (cadr-ai::hmac-sha256
     "key" "The quick brown fox jumps over the lazy dog"))
   (cadr-ai::octets-hex (cadr-ai::hmac-sha256 "key" ""))
   (cadr-ai::octets-hex
    (cadr-ai::hmac-sha256
     (make-string 70 :initial-element #\a) "msg"))))

(defun measure-ai-crypto-hmac ()
  (let ((observed (run-ai-crypto-hmac)))
    (json-object
     "observed"
     (json-object
      "fox" (first observed)
      "empty" (second observed)
      "long" (third observed))
     "hmac"
     (collect "ai_crypto.hmac"
              (lambda ()
                (lambda ()
                  (run-ai-crypto-hmac)))))))

(defparameter *model-match-patterns*
  '("goal20faux/goal20-paired-0"
    "goal20-paired-1"
    "paired-2"
    "goal20-paired-3:high"
    "does-not-exist-xyzzy"))

(defun model-match-fields (model thinking)
  (list
   (if model (cadr-ai:model-id model) "")
   (if model
       (cadr-cli::provider-key (cadr-ai:model-provider model))
       "")
   (if thinking
       (string-downcase (symbol-name thinking))
       "")))

(defun run-cli-models-rest (models)
  (loop for pattern in *model-match-patterns*
        collect
        (multiple-value-bind (model thinking warning)
            (cadr-cli::parse-scoped-model-pattern pattern models)
          (declare (ignore warning))
          (cons pattern (model-match-fields model thinking)))))

(defun auth-command-error-p (arguments)
  (handler-case
      (progn
        (cadr-cli::parse-auth-command arguments)
        0)
    (error () 1)))

(defun run-cli-models-rest-auth-command ()
  (let ((skip (cadr-cli::parse-auth-command '("models")))
        (api
          (cadr-cli::parse-auth-command
           '("auth" "print-api-key" "--provider" "openai")))
        (bearer
          (cadr-cli::parse-auth-command
           '("auth" "print-bearer-token" "--min-expiry" "30m")))
        (check
          (cadr-cli::parse-auth-command
           '("auth" "check" "--json" "--credentials" "--no-refresh"
             "--provider" "openai"))))
    (list
     (if skip 1 0)
     (if (eq (getf api :kind) :api-key) 1 0)
     (if (equal (getf api :arguments) '("--provider" "openai")) 1 0)
     (if (eq (getf bearer :kind) :bearer-token) 1 0)
     (or (getf bearer :minimum-expiry-ms) 0)
     (if (eq (getf check :kind) :check) 1 0)
     (if (getf check :json-p) 1 0)
     (if (getf check :credentials-p) 1 0)
     (if (getf check :no-refresh-p) 1 0)
     (if (equal (getf check :arguments) '("--provider" "openai")) 1 0)
     (auth-command-error-p
      '("auth" "print-api-key" "--min-expiry" "30m"))
     (auth-command-error-p '("auth" "unknown"))
     (if (cadr-cli::auth-command-help-request-p '("auth" "--help"))
         1
         0)
     (if (cadr-cli::auth-command-help-request-p
          '("auth" "print-api-key" "--help"))
         1
         0))))

(defun measure-cli-models-rest ()
  (let* ((models
           (cadr-cli::model-registry-available-models
            (list-models-registry)))
         (rows (run-cli-models-rest models))
         (exact (first rows))
         (bare (second rows))
         (partial (third rows))
         (scoped (fourth rows))
         (missing (fifth rows))
         (auth (run-cli-models-rest-auth-command)))
    (json-object
     "observed"
     (json-object
      "exact_id" (second exact)
      "exact_provider" (third exact)
      "bare_id" (second bare)
      "partial_id" (second partial)
      "scoped_id" (second scoped)
      "scoped_thinking" (fourth scoped)
      "miss" (if (string= (second missing) "") 1 0)
      "ac_skip" (nth 0 auth)
      "ac_api" (nth 1 auth)
      "ac_api_prov" (nth 2 auth)
      "ac_bearer" (nth 3 auth)
      "ac_exp" (nth 4 auth)
      "ac_check" (nth 5 auth)
      "ac_json" (nth 6 auth)
      "ac_cred" (nth 7 auth)
      "ac_noref" (nth 8 auth)
      "ac_chk_prov" (nth 9 auth)
      "ac_min_api" (nth 10 auth)
      "ac_unknown" (nth 11 auth)
      "ac_help" (nth 12 auth)
      "ac_help2" (nth 13 auth))
     "pattern_match"
     (collect "cli_models_rest.pattern_match"
              (lambda ()
                (lambda ()
                  (run-cli-models-rest models))))
     "auth_command"
     (collect "cli_models_rest.auth_command"
              (lambda ()
                (lambda ()
                  (run-cli-models-rest-auth-command)))))))

(defparameter *png-1x1-b64*
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC")
(defparameter *gif-2x3-b64* "R0lGODlhAgADAAAAADs=")

(defun image-dim-pair (base64 mime)
  (multiple-value-bind (width height)
      (cadr-tui:image-dimensions base64 mime)
    (list (or width 0) (or height 0))))

(defun run-image-runtime ()
  (let ((png (image-dim-pair *png-1x1-b64* "image/png"))
        (gif (image-dim-pair *gif-2x3-b64* "image/gif"))
        (miss (image-dim-pair "not-an-image" "image/png")))
    (list (first png) (second png)
          (first gif) (second gif)
          (if (and (zerop (first miss)) (zerop (second miss)))
              1
              0))))

(defun mime-or-empty (bytes)
  (or (cadr-cli::detect-image-mime-type bytes) ""))

(defun ascii-octet-vector (text)
  (cadr-cli::simple-octet-vector
   (map 'vector #'char-code text)))

(defun run-image-runtime-mime ()
  (list
   (mime-or-empty
    (cadr-cli::decode-base64-bytes *png-1x1-b64*))
   (mime-or-empty
    (cadr-cli::simple-octet-vector #(255 216 255 224)))
   (mime-or-empty (ascii-octet-vector "GIF89a"))
   (mime-or-empty (ascii-octet-vector "RIFF....WEBP"))
   (mime-or-empty (ascii-octet-vector "hello"))))

(defun image-lookup-flag (id)
  (handler-case
      (progn
        (cadr-ai:find-image-model :openrouter id)
        1)
    (error () 0)))

(defun run-image-runtime-lookup ()
  (list
   (image-lookup-flag "google/gemini-2.5-flash-image")
   (image-lookup-flag "black-forest-labs/flux.2-pro")
   (image-lookup-flag "nope")))

(defun dim-note-or-empty (result)
  (or (cadr-cli:format-image-dimension-note result) ""))

(defun dim-note-result (original-width original-height width height resized-p)
  (cadr-cli::make-image-process-result
   :bytes #()
   :mime-type "image/png"
   :original-width original-width
   :original-height original-height
   :width width
   :height height
   :resized-p resized-p))

(defun run-image-runtime-dimension-note ()
  (list
   (dim-note-or-empty
    (dim-note-result 2000 1000 1000 500 t))
   (dim-note-or-empty
    (dim-note-result 1000 800 400 320 t))
   (dim-note-or-empty
    (dim-note-result 64 64 64 64 nil))))

(defun ensure-fixture-images-api-provider ()
  (unless (cadr-ai:get-images-api-provider :fixture-images)
    (cadr-ai:register-images-api-provider
     :fixture-images
     (lambda (model context options)
       (declare (ignore model context options))
       nil)
     :source-id "goal20-pair")))

(defun image-api-provider-flag (api)
  (if (cadr-ai:get-images-api-provider api) 1 0))

(defun run-image-runtime-api-provider ()
  (ensure-fixture-images-api-provider)
  (list
   (image-api-provider-flag :fixture-images)
   (image-api-provider-flag :nope)))

(defun measure-image-runtime ()
  (let ((dims (run-image-runtime))
        (mime (run-image-runtime-mime))
        (lookup (run-image-runtime-lookup))
        (notes (run-image-runtime-dimension-note))
        (api (run-image-runtime-api-provider)))
    (json-object
     "observed"
     (json-object
      "png_width" (first dims)
      "png_height" (second dims)
      "gif_width" (third dims)
      "gif_height" (fourth dims)
      "miss" (fifth dims)
      "png_mime" (first mime)
      "jpeg_mime" (second mime)
      "gif_mime" (third mime)
      "webp_mime" (fourth mime)
      "miss_mime" (fifth mime)
      "gemini" (first lookup)
      "flux" (second lookup)
      "unknown" (third lookup)
      "note_resized" (first notes)
      "note_half" (second notes)
      "note_plain" (third notes)
      "api_fixture" (first api)
      "api_unknown" (second api))
     "dimensions"
     (collect "image_runtime.dimensions"
              (lambda ()
                (lambda ()
                  (run-image-runtime))))
     "mime_type"
     (collect "image_runtime.mime_type"
              (lambda ()
                (lambda ()
                  (run-image-runtime-mime))))
     "lookup"
     (collect "image_runtime.lookup"
              (lambda ()
                (lambda ()
                  (run-image-runtime-lookup))))
     "dimension_note"
     (collect "image_runtime.dimension_note"
              (lambda ()
                (lambda ()
                  (run-image-runtime-dimension-note))))
     "api_provider"
     (collect "image_runtime.api_provider"
              (lambda ()
                (lambda ()
                  (run-image-runtime-api-provider)))))))

(defun rpc-jsonl-object ()
  (cadr-ai::json-object
   "command" "get_state"
   "id" "rpc-1"
   "success" t
   "type" "response"))

(defun run-cli-print-rpc ()
  (let ((stream (make-string-output-stream)))
    (cadr-cli::write-json-line (rpc-jsonl-object) stream)
    (get-output-stream-string stream)))

(defparameter *rpc-jsonl-read-fixture*
  (concatenate
   'string
   "{\"id\":\"1\"}"
   (string #\Newline)
   "{\"id\":\"2\"}"
   (string #\Return)
   (string #\Newline)
   "last"
   (string #\Newline)))

(defun run-cli-print-rpc-read ()
  (let ((lines nil))
    (with-input-from-string (stream *rpc-jsonl-read-fixture*)
      (cadr-cli::read-rpc-jsonl-lines
       stream
       (lambda (line)
         (push line lines))))
    (nreverse lines)))

(defun clamp-thinking-fixture-model (map)
  (cadr-ai:make-model
   :id "goal20-clamp"
   :name "goal20-clamp"
   :provider :openai
   :api :openai-completions
   :base-url "http://localhost"
   :reasoning-p t
   :thinking-level-map map
   :context-window 128000
   :max-tokens 4096))

(defun clamp-thinking-name (level available)
  (string-downcase
   (symbol-name
    (cadr-cli::rpc-clamp-thinking-level level available))))

(defparameter *rpc-stats-session-id*
  "019f0000-0000-7000-8000-00000000cadr")

(defun run-cli-print-rpc-session-stats (session)
  (cadr-cli::rpc-session-stats session))

(defun cli-print-rpc-session-stats-observed (stats)
  (list
   (cadr-ai::json-get stats "userMessages")
   (cadr-ai::json-get stats "assistantMessages")
   (cadr-ai::json-get stats "toolResults")
   (cadr-ai::json-get stats "toolCalls")
   (cadr-ai::json-get stats "totalMessages")
   (if (string= (cadr-ai::json-get stats "sessionId")
                *rpc-stats-session-id*)
       1
       0)))

(defun run-cli-print-rpc-clamp-thinking ()
  (let* ((full
           (clamp-thinking-fixture-model
            '((:xhigh . "x") (:max . "m"))))
         (short (clamp-thinking-fixture-model nil))
         (full-av (cadr-ai::supported-thinking-levels full))
         (short-av (cadr-ai::supported-thinking-levels short)))
    (list
     (clamp-thinking-name :off full-av)
     (clamp-thinking-name :high full-av)
     (clamp-thinking-name :xhigh full-av)
     (clamp-thinking-name :max full-av)
     (clamp-thinking-name :xhigh short-av)
     (clamp-thinking-name :nope full-av)
     (length full-av)
     (length short-av))))

(defun measure-cli-print-rpc ()
  (let* ((line (run-cli-print-rpc))
         (newline-p
           (and (plusp (length line))
                (char= #\Newline (char line (1- (length line))))))
         (payload
           (if newline-p
               (subseq line 0 (1- (length line)))
               line))
         (read-lines (run-cli-print-rpc-read))
         (clamp (run-cli-print-rpc-clamp-thinking))
         (session
           (cadr-agent:load-session (fixture-path "session.jsonl")))
         (stats-obs
           (cli-print-rpc-session-stats-observed
            (run-cli-print-rpc-session-stats session))))
    (json-object
     "observed"
     (json-object
      "line_chars" (length line)
      "newline" (if newline-p 1 0)
      "payload" payload
      "line_count" (length read-lines)
      "first" (or (first read-lines) "")
      "second" (or (second read-lines) "")
      "last_line" (or (third read-lines) "")
      "tl_off" (nth 0 clamp)
      "tl_high" (nth 1 clamp)
      "tl_xh" (nth 2 clamp)
      "tl_max" (nth 3 clamp)
      "tl_xh_down" (nth 4 clamp)
      "tl_unk" (nth 5 clamp)
      "tl_full_n" (nth 6 clamp)
      "tl_short_n" (nth 7 clamp)
      "ss_user" (nth 0 stats-obs)
      "ss_asst" (nth 1 stats-obs)
      "ss_tool" (nth 2 stats-obs)
      "ss_calls" (nth 3 stats-obs)
      "ss_total" (nth 4 stats-obs)
      "ss_id" (nth 5 stats-obs))
     "jsonl_line"
     (collect "cli_print_rpc.jsonl_line"
              (lambda ()
                (lambda ()
                  (run-cli-print-rpc))))
     "jsonl_read"
     (collect "cli_print_rpc.jsonl_read"
              (lambda ()
                (lambda ()
                  (run-cli-print-rpc-read))))
     "clamp_thinking"
     (collect "cli_print_rpc.clamp_thinking"
              (lambda ()
                (lambda ()
                  (run-cli-print-rpc-clamp-thinking))))
     "session_stats"
     (collect "cli_print_rpc.session_stats"
              (lambda ()
                (lambda ()
                  (run-cli-print-rpc-session-stats session)))))))

(defparameter *mermaid-lr*
  (format nil "flowchart LR~%  A-->B"))

(defparameter *mermaid-cjk*
  (format nil "flowchart LR~%  A[你好世界]-->B[测试]"))

(defun mermaid-art (src)
  (cadr-tui::gm-render src))

(defun run-tui-mermaid ()
  (let ((lr (mermaid-art *mermaid-lr*))
        (empty (mermaid-art ""))
        (unk (mermaid-art "notadiagram"))
        (cjk (mermaid-art *mermaid-cjk*)))
    (list
     (if lr (getf lr :width) 0)
     (if lr (or (first (getf lr :plain)) "") "")
     (if lr (length (getf lr :plain)) 0)
     (if (null empty) 1 0)
     (if (null unk) 1 0)
     (if cjk (getf cjk :width) 0))))

(defun mermaid-box (src max-width)
  (cadr-tui::gm-source-box src max-width))

(defun run-tui-mermaid-source-box ()
  (let ((wide (mermaid-box *mermaid-lr* 80))
        (narrow (mermaid-box *mermaid-lr* 12))
        (empty (mermaid-box "" 80)))
    (list
     (if wide (getf wide :width) 0)
     (if wide (or (first (getf wide :plain)) "") "")
     (if narrow (length (getf narrow :plain)) 0)
     (if empty (getf empty :width) 0))))

(defparameter *mermaid-md*
  (format nil "```mermaid~%flowchart LR~%  A-->B~%```~%"))

(defun mermaid-transform
    (src &key (mode "streaming") message-type streaming-p (width 80))
  (cadr-tui:transform-mermaid-markdown
   src
   :mode mode
   :message-type message-type
   :streaming-p streaming-p
   :available-width width
   :theme-p nil))

(defun run-tui-mermaid-transform ()
  (let* ((ok (mermaid-transform *mermaid-md*))
         (off (mermaid-transform *mermaid-md* :mode "off"))
         (think
           (mermaid-transform
            *mermaid-md*
            :message-type "assistant-thinking"))
         (wide (mermaid-transform *mermaid-md* :width 5)))
    (list
     (if (and (plusp (length ok))
              (char= (char ok 0) #\`)
              (not (search "```mermaid" ok)))
         1
         0)
     (if (search "──" ok) 1 0)
     (if (string= off *mermaid-md*) 1 0)
     (if (string= think *mermaid-md*) 1 0)
     (if (string= wide *mermaid-md*) 1 0)
     (length ok))))

(defun measure-tui-mermaid ()
  (let ((observed (run-tui-mermaid))
        (box (run-tui-mermaid-source-box))
        (transform (run-tui-mermaid-transform)))
    (json-object
     "observed"
     (json-object
      "mm_lr_w" (nth 0 observed)
      "mm_lr_first" (nth 1 observed)
      "mm_lr_rows" (nth 2 observed)
      "mm_empty" (nth 3 observed)
      "mm_unk" (nth 4 observed)
      "mm_cjk_w" (nth 5 observed)
      "sb_wide_w" (nth 0 box)
      "sb_wide_first" (nth 1 box)
      "sb_narrow_rows" (nth 2 box)
      "sb_empty_w" (nth 3 box)
      "tf_ok" (nth 0 transform)
      "tf_art" (nth 1 transform)
      "tf_off" (nth 2 transform)
      "tf_think" (nth 3 transform)
      "tf_wide" (nth 4 transform)
      "tf_len" (nth 5 transform))
     "render"
     (collect "tui_mermaid.render"
              (lambda ()
                (lambda ()
                  (run-tui-mermaid))))
     "source_box"
     (collect "tui_mermaid.source_box"
              (lambda ()
                (lambda ()
                  (run-tui-mermaid-source-box))))
     "transform"
     (collect "tui_mermaid.transform"
              (lambda ()
                (lambda ()
                  (run-tui-mermaid-transform)))))))

(defun latex-text (source display-p)
  (or (cadr-tui:render-latex source :display-p display-p) ""))

(defun run-tui-latex ()
  (list
   (latex-text "E = mc^2" nil)
   (latex-text "\\frac{1}{2}" nil)
   (latex-text "\\alpha + \\beta \\times \\gamma" nil)
   (count #\Newline (latex-text "\\frac{1}{2}" t))
   (if (string= (latex-text "\\unknowncmd{x}" nil) "") 1 0)))

(defun measure-tui-latex ()
  (let ((observed (run-tui-latex)))
    (json-object
     "observed"
     (json-object
      "e_mc2" (first observed)
      "frac_inline" (second observed)
      "greek" (third observed)
      "frac_display_newlines" (fourth observed)
      "unknown_miss" (fifth observed))
     "render"
     (collect "tui_latex.render"
              (lambda ()
                (lambda ()
                  (run-tui-latex)))))))

(defun fuzzy-hit (query text)
  (multiple-value-bind (matched-p score)
      (cadr-tui:fuzzy-match query text)
    (declare (ignore score))
    (if matched-p 1 0)))

(defun run-tui-fuzzy ()
  (list
   (fuzzy-hit "gpt" "gpt-4o")
   (fuzzy-hit "4o" "gpt-4o")
   (fuzzy-hit "g4" "gpt-4o")
   (fuzzy-hit "xyzzy" "gpt-4o")
   (fuzzy-hit "" "anything")))

(defun measure-tui-fuzzy ()
  (let ((observed (run-tui-fuzzy)))
    (json-object
     "observed"
     (json-object
      "gpt" (first observed)
      "id_suffix" (second observed)
      "swapped" (third observed)
      "miss" (fourth observed)
      "empty" (fifth observed))
     "fuzzy_match"
     (collect "tui_editor_helpers.fuzzy_match"
              (lambda ()
                (lambda ()
                  (run-tui-fuzzy)))))))

(defun osc11-report (body terminator)
  (concatenate 'string (string #\Escape) "]11;" body terminator))

(defun rgb-triple (color)
  (if color
      (list (cadr-tui:rgb-color-red color)
            (cadr-tui:rgb-color-green color)
            (cadr-tui:rgb-color-blue color))
      (list -1 -1 -1)))

(defun run-tui-theme-overlay ()
  (let* ((bell (string (code-char 7)))
         (st (concatenate 'string (string #\Escape) "\\"))
         (rgb
           (rgb-triple
            (cadr-tui:parse-osc-11-background-color
             (osc11-report "rgb:ffff/8000/0000" bell))))
         (hex6
           (rgb-triple
            (cadr-tui:parse-osc-11-background-color
             (osc11-report "#112233" st))))
         (hex12
           (rgb-triple
            (cadr-tui:parse-osc-11-background-color
             (osc11-report "#ffff80000000" bell))))
         (miss
           (cadr-tui:parse-osc-11-background-color
            (concatenate 'string "prefix"
                         (osc11-report "#112233" bell))))
         (scheme
           (cadr-tui:parse-terminal-color-scheme-report
            (format nil "~C[?997;1n" #\Escape))))
    (list (first rgb) (second rgb) (third rgb)
          (first hex6) (second hex6) (third hex6)
          (first hex12)
          (if miss 0 1)
          (if (eq scheme :dark) 1 0))))

(defun measure-tui-theme-overlay ()
  (let ((observed (run-tui-theme-overlay)))
    (json-object
     "observed"
     (json-object
      "rgb_r" (first observed)
      "rgb_g" (second observed)
      "rgb_b" (third observed)
      "hex6_r" (fourth observed)
      "hex6_g" (fifth observed)
      "hex6_b" (sixth observed)
      "hex12_r" (seventh observed)
      "miss" (eighth observed)
      "scheme_dark" (ninth observed))
     "osc11_bg"
     (collect "tui_theme_overlay.osc11_bg"
              (lambda ()
                (lambda ()
                  (run-tui-theme-overlay)))))))

(defparameter *estimate-empty* "")
(defparameter *estimate-hello* "hello world")
(defparameter *estimate-block* (make-string 100 :initial-element #\a))

(defun run-ai-support-estimate ()
  (list
   (cadr-ai:estimate-text-tokens *estimate-empty*)
   (cadr-ai:estimate-text-tokens *estimate-hello*)
   (cadr-ai:estimate-text-tokens *estimate-block*)))

(defun overflow-error-message (text)
  (cadr-ai::make-assistant-message
   :api :openai-completions
   :provider :ollama
   :model "qwen"
   :stop-reason :error
   :error-message text
   :usage (cadr-ai:make-usage)))

(defun overflow-usage-message (stop-reason input output)
  (cadr-ai::make-assistant-message
   :api :openai-completions
   :provider :ollama
   :model "qwen"
   :stop-reason stop-reason
   :usage (cadr-ai:make-usage :input input :output output)))

(defun overflow-flag (message &optional window)
  (if (cadr-ai::context-overflow-p message window) 1 0))

(defun run-ai-support-context-overflow ()
  (list
   (overflow-flag (overflow-error-message "prompt is too long"))
   (overflow-flag (overflow-error-message "rate limit"))
   (overflow-flag (overflow-usage-message :stop 100 0) 50)
   (overflow-flag (overflow-usage-message :length 100 0) 100)))

(defun run-ai-support-grammar-delta ()
  (let ((buffer (cadr-ai::make-grammar-json-buffer)))
    (list
     (or (cadr-ai::append-grammar-json-delta buffer "input" "hel" nil) "")
     (or (cadr-ai::append-grammar-json-delta buffer "input" "hello" nil) "")
     (or (cadr-ai::append-grammar-json-delta buffer "input" "hello" t) "")
     (if (cadr-ai::grammar-json-buffer-started-p buffer) 1 0)
     (if (cadr-ai::grammar-json-buffer-closed-p buffer) 1 0))))

(defun uuid-v7-shape (id)
  (list
   (length id)
   (count #\- id)
   (if (and (> (length id) 14)
            (char= (char id 14) #\7))
       7
       0)
   (if (and (> (length id) 19)
            (find (char id 19) "89ab"))
       1
       0)))

(defun run-ai-support-uuid-v7 ()
  (let* ((first (cadr-ai:uuid-v7))
         (second (cadr-ai:uuid-v7))
         (shape (uuid-v7-shape first)))
    (list
     (first shape)
     (second shape)
     (third shape)
     (fourth shape)
     (if (string= first second) 0 1))))

(defun auth-prefix (text count)
  (if (>= (length text) count)
      (subseq text 0 count)
      text))

(defun auth-flag (text needle)
  (if (search needle text) 1 0))

(defun run-ai-support-auth-guidance ()
  (let ((models (cadr-ai::no-models-available-message))
        (selected (cadr-ai::no-model-selected-message))
        (key (cadr-ai::no-api-key-found-message "openai"))
        (unknown (cadr-ai::no-api-key-found-message "unknown")))
    (list
     (auth-prefix models 21)
     (auth-prefix selected 18)
     (auth-prefix key 28)
     (auth-prefix unknown 40)
     (auth-flag models "Use /login")
     (auth-flag models "providers.md")
     (auth-flag models "models.md"))))

(defun measure-ai-support-estimate ()
  (let ((estimate (run-ai-support-estimate))
        (overflow (run-ai-support-context-overflow))
        (grammar (run-ai-support-grammar-delta))
        (uuid (run-ai-support-uuid-v7))
        (auth (run-ai-support-auth-guidance)))
    (json-object
     "observed"
     (json-object
      "empty" (first estimate)
      "hello" (second estimate)
      "block" (third estimate)
      "prompt" (first overflow)
      "rate" (second overflow)
      "silent" (third overflow)
      "length" (fourth overflow)
      "d1" (first grammar)
      "d2" (second grammar)
      "d3" (third grammar)
      "started" (fourth grammar)
      "closed" (fifth grammar)
      "uuid_len" (first uuid)
      "uuid_hyphens" (second uuid)
      "uuid_version" (third uuid)
      "uuid_variant" (fourth uuid)
      "uuid_neq" (fifth uuid)
      "no_models" (first auth)
      "no_selected" (second auth)
      "no_key" (third auth)
      "no_unknown" (fourth auth)
      "has_login" (fifth auth)
      "has_providers" (sixth auth)
      "has_models" (seventh auth))
     "estimate_text"
     (collect "ai_support.estimate_text"
              (lambda ()
                (lambda ()
                  (run-ai-support-estimate))))
     "context_overflow"
     (collect "ai_support.context_overflow"
              (lambda ()
                (lambda ()
                  (run-ai-support-context-overflow))))
     "grammar_delta"
     (collect "ai_support.grammar_delta"
              (lambda ()
                (lambda ()
                  (run-ai-support-grammar-delta))))
     "uuid_v7"
     (collect "ai_support.uuid_v7"
              (lambda ()
                (lambda ()
                  (run-ai-support-uuid-v7))))
     "auth_guidance"
     (collect "ai_support.auth_guidance"
              (lambda ()
                (lambda ()
                  (run-ai-support-auth-guidance)))))))

(defun select-list-fixture ()
  (cadr-tui:make-select-list
   :show-filter-p nil
   :items
   (list
    (cadr-tui:make-select-item :label "Hello" :value "hello")
    (cadr-tui:make-select-item :label "Help" :value "help")
    (cadr-tui:make-select-item :label "World" :value "world"))))

(defun select-list-filter-count (list query)
  (setf (cadr-tui:select-list-query list) query)
  (length (cadr-tui:select-list-filtered-items list)))

(defun run-tui-select-list ()
  (let ((list (select-list-fixture)))
    (list
     (select-list-filter-count list "he")
     (let ((first
             (first (cadr-tui:select-list-filtered-items list))))
       (if first (cadr-tui:select-item-value first) ""))
     (select-list-filter-count list "wo")
     (select-list-filter-count list "zz"))))

(defun measure-tui-select-list ()
  (let ((observed (run-tui-select-list)))
    (json-object
     "observed"
     (json-object
      "he_count" (first observed)
      "he_first" (second observed)
      "wo_count" (third observed)
      "zz_count" (fourth observed))
     "filter"
     (collect "tui_select_settings_loaders.filter"
              (lambda ()
                (lambda ()
                  (run-tui-select-list)))))))

(defparameter *word-nav-text* "hello world")

(defun run-tui-word-navigation ()
  (list
   (cadr-tui:find-word-backward *word-nav-text* 11)
   (cadr-tui:find-word-forward *word-nav-text* 5)
   (cadr-tui:find-word-backward *word-nav-text* 0)
   (cadr-tui:find-word-forward *word-nav-text* (length *word-nav-text*))))

(defun measure-tui-word-navigation ()
  (let ((observed (run-tui-word-navigation)))
    (json-object
     "observed"
     (json-object
      "back_from_space" (first observed)
      "fwd_from_o" (second observed)
      "back_start" (third observed)
      "fwd_end" (fourth observed))
     "step"
     (collect "tui_word_navigation.step"
              (lambda ()
                (lambda ()
                  (run-tui-word-navigation)))))))

(defparameter *overlay-base* "hello world this is a long line")
(defparameter *overlay-text* "OVER")

(defun run-tui-overlay ()
  (let ((line
          (cadr-tui:composite-overlay-line
           *overlay-base* *overlay-text* 6 4 40)))
    (list
     (length line)
     (cadr-tui:visible-width line)
     (if (search (format nil "~C[0m" #\Escape) line) 1 0))))

(defun measure-tui-overlay ()
  (let ((observed (run-tui-overlay)))
    (json-object
     "observed"
     (json-object
      "line_chars" (first observed)
      "visible_width" (second observed)
      "has_reset" (third observed))
     "composite_line"
     (collect "tui_overlay.composite_line"
              (lambda ()
                (lambda ()
                  (run-tui-overlay)))))))

(defun run-tui-kill-ring ()
  (let ((empty (cadr-tui:make-kill-ring))
        (ring (cadr-tui:make-kill-ring))
        (acc (cadr-tui:make-kill-ring))
        (pre (cadr-tui:make-kill-ring)))
    (cadr-tui:kill-ring-push ring "aa")
    (cadr-tui:kill-ring-push ring "bbb")
    (let ((peek-two (length (or (cadr-tui:kill-ring-peek ring) ""))))
      (cadr-tui:kill-ring-rotate ring)
      (cadr-tui:kill-ring-push acc "ab")
      (cadr-tui:kill-ring-push acc "c" :accumulate-p t)
      (cadr-tui:kill-ring-push pre "yz")
      (cadr-tui:kill-ring-push pre "x" :prepend-p t :accumulate-p t)
      (list
       (cadr-tui:kill-ring-length empty)
       (cadr-tui:kill-ring-length ring)
       peek-two
       (length (or (cadr-tui:kill-ring-peek ring) ""))
       (length (or (cadr-tui:kill-ring-peek acc) ""))
       (length (or (cadr-tui:kill-ring-peek pre) ""))))))

(defun measure-tui-kill-ring ()
  (let ((observed (run-tui-kill-ring)))
    (json-object
     "observed"
     (json-object
      "empty_len" (first observed)
      "ring_len" (second observed)
      "peek_two" (third observed)
      "peek_rot" (fourth observed)
      "acc_append" (fifth observed)
      "acc_prepend" (sixth observed))
     "push_peek"
     (collect "tui_kill_ring.push_peek"
              (lambda ()
                (lambda ()
                  (run-tui-kill-ring)))))))

(defun run-tui-undo-stack ()
  (let ((empty (cadr-tui:make-undo-stack))
        (stack (cadr-tui:make-undo-stack))
        (state (list :text "hello" :n 1)))
    (cadr-tui:undo-stack-push stack state)
    (setf (getf state :n) 99)
    (cadr-tui:undo-stack-push stack (list :text "world" :n 2))
    (let* ((after-two (cadr-tui:undo-stack-length stack))
           (popped (cadr-tui:undo-stack-pop stack))
           (pop-n (getf popped :n))
           (after-pop (cadr-tui:undo-stack-length stack))
           (first (cadr-tui:undo-stack-pop stack))
           (clone-n (getf first :n)))
      (cadr-tui:undo-stack-clear stack)
      (list
       (cadr-tui:undo-stack-length empty)
       after-two
       pop-n
       after-pop
       clone-n
       (cadr-tui:undo-stack-length stack)))))

(defun measure-tui-undo-stack ()
  (let ((observed (run-tui-undo-stack)))
    (json-object
     "observed"
     (json-object
      "empty_len" (first observed)
      "after_two" (second observed)
      "pop_n" (third observed)
      "after_pop" (fourth observed)
      "clone_n" (fifth observed)
      "after_clear" (sixth observed))
     "push_pop"
     (collect "tui_undo_stack.push_pop"
              (lambda ()
                (lambda ()
                  (run-tui-undo-stack)))))))

(defun write-autocomplete-fixture ()
  (let* ((root
           (merge-pathnames "autocomplete/" *scratch-directory*))
         (src (merge-pathnames "src/" root)))
    (ensure-directories-exist src)
    (dolist (name '("hello.txt" "help.md"))
      (with-open-file
          (out (merge-pathnames name root)
               :direction :output
               :if-exists :supersede
               :if-does-not-exist :create
               :external-format :utf-8)
        (write-string "x" out)))
    (with-open-file
        (out (merge-pathnames "a.ts" src)
             :direction :output
             :if-exists :supersede
             :if-does-not-exist :create
             :external-format :utf-8)
      (write-string "x" out))
    (namestring (uiop:ensure-directory-pathname root))))

(defun make-paired-autocomplete-provider (root)
  (cadr-tui:make-autocomplete-provider
   :commands
   (list
    (cadr-tui:make-autocomplete-command
     :name "help" :description "Show help")
    (cadr-tui:make-autocomplete-command
     :name "hello" :description "Hi"))
   :base-path root))

(defun autocomplete-result-count (result)
  (if result
      (length (cadr-tui:autocomplete-suggestions-items result))
      0))

(defun autocomplete-values (result)
  (if result
      (mapcar #'cadr-tui:autocomplete-item-value
              (cadr-tui:autocomplete-suggestions-items result))
      nil))

(defun autocomplete-labels (result)
  (if result
      (mapcar #'cadr-tui:autocomplete-item-label
              (cadr-tui:autocomplete-suggestions-items result))
      nil))

(defun run-tui-autocomplete (provider)
  (let* ((slash
           (cadr-tui:autocomplete-get-suggestions
            provider '("/he") 0 3))
         (slash-values (autocomplete-values slash))
         (quoted
           (cadr-tui:autocomplete-get-suggestions
            provider (list (format nil "~Chel" #\")) 0 4))
         (force
           (cadr-tui:autocomplete-get-suggestions
            provider '("he") 0 2 :force-p t))
         (force-labels (autocomplete-labels force))
         (at
           (cadr-tui:autocomplete-get-suggestions
            provider '("@he") 0 3))
         (item
           (cadr-tui:make-autocomplete-item
            :value "help" :label "help")))
    (multiple-value-bind (lines cursor-line cursor-col)
        (cadr-tui:autocomplete-apply
         '("/he") 0 3 item "/he")
      (declare (ignore cursor-line))
      (list
       (autocomplete-result-count slash)
       (if (find "help" slash-values :test #'string=) 1 0)
       (if (find "hello" slash-values :test #'string=) 1 0)
       (if slash
           (length (cadr-tui:autocomplete-suggestions-prefix slash))
           0)
       (autocomplete-result-count quoted)
       (length (or (first (autocomplete-values quoted)) ""))
       (autocomplete-result-count force)
       (if (find "hello.txt" force-labels :test #'string=) 1 0)
       (if (find "help.md" force-labels :test #'string=) 1 0)
       (autocomplete-result-count at)
       cursor-col
       (length (first lines))))))

(defun measure-tui-autocomplete ()
  (let* ((root (write-autocomplete-fixture))
         (provider (make-paired-autocomplete-provider root))
         (observed (run-tui-autocomplete provider)))
    (json-object
     "observed"
     (json-object
      "slash_count" (first observed)
      "slash_help" (second observed)
      "slash_hello" (third observed)
      "slash_prefix" (fourth observed)
      "quote_count" (fifth observed)
      "quote_first_len" (sixth observed)
      "force_count" (seventh observed)
      "force_hello" (eighth observed)
      "force_help" (ninth observed)
      "at_count" (nth 9 observed)
      "apply_col" (nth 10 observed)
      "apply_len" (nth 11 observed))
     "suggest_apply"
     (collect "tui_autocomplete.suggest_apply"
              (lambda ()
                (lambda ()
                  (run-tui-autocomplete provider)))))))

(defun run-tui-keybindings ()
  (let* ((manager
           (cadr-tui:make-keybindings-manager
            :user-bindings
            '(("tui.editor.yank" . "ctrl+k")
              ("tui.editor.deleteToLineEnd" . "ctrl+k"))))
         (left
           (cadr-tui:keybinding-keys
            manager "tui.editor.cursorLeft"))
         (hist
           (cadr-tui:keybinding-keys
            manager "tui.editor.historyPrevious"))
         (conflicts (cadr-tui:keybinding-conflicts manager))
         (enter (string #\Return))
         (tab (string #\Tab)))
    (list
     (length left)
     (if (find "ctrl+b" left :test #'string=) 1 0)
     (length hist)
     (if (cadr-tui:keybinding-matches-p
          manager enter "tui.input.submit")
         1 0)
     (if (cadr-tui:keybinding-matches-p
          manager tab "tui.input.tab")
         1 0)
     (if (cadr-tui:keybinding-matches-p
          manager enter "tui.editor.undo")
         1 0)
     (length conflicts)
     (length (or (car (first conflicts)) "")))))

(defun measure-tui-keybindings ()
  (let ((observed (run-tui-keybindings)))
    (json-object
     "observed"
     (json-object
      "left_count" (first observed)
      "left_ctrl_b" (second observed)
      "hist_count" (third observed)
      "enter_submit" (fourth observed)
      "tab_tab" (fifth observed)
      "enter_undo" (sixth observed)
      "conflict_count" (seventh observed)
      "conflict_key_len" (eighth observed))
     "resolve_match"
     (collect "tui_keybindings.resolve_match"
              (lambda ()
                (lambda ()
                  (run-tui-keybindings)))))))

(defun run-tui-stdin-buffer ()
  (let ((buffer (cadr-tui:make-stdin-buffer)))
    (multiple-value-bind (hello-seq)
        (cadr-tui:stdin-buffer-process buffer "hello")
      (cadr-tui:stdin-buffer-process
       buffer (format nil "~C[" #\Escape))
      (let ((leftover
              (length (cadr-tui:stdin-buffer-contents buffer))))
        (multiple-value-bind (up-seq)
            (cadr-tui:stdin-buffer-process buffer "A")
          (multiple-value-bind (tail-seq paste-seq)
              (cadr-tui:stdin-buffer-process
               buffer
               (format nil "~C[200~~hi~C[201~~x"
                       #\Escape #\Escape))
            (cadr-tui:stdin-buffer-destroy buffer)
            (list
             (length hello-seq)
             leftover
             (length (or (first up-seq) ""))
             (length (or (first paste-seq) ""))
             (length tail-seq))))))))

(defun measure-tui-stdin-buffer ()
  (let ((observed (run-tui-stdin-buffer)))
    (json-object
     "observed"
     (json-object
      "hello_count" (first observed)
      "leftover" (second observed)
      "up_len" (third observed)
      "paste_len" (fourth observed)
      "tail_count" (fifth observed))
     "process"
     (collect "tui_stdin_buffer.process"
              (lambda ()
                (lambda ()
                  (run-tui-stdin-buffer)))))))

(defun feed-single-line-text (input text)
  (loop for ch across text
        do (cadr-tui:single-line-input-handle-event
            input
            (cadr-tui:make-input-event :kind :text :text (string ch)))))

(defun run-tui-input-component ()
  (let ((input (cadr-tui:make-single-line-input)))
    (feed-single-line-text input "hello world")
    (let ((after-insert
            (length (cadr-tui:single-line-input-value input))))
      (cadr-tui:single-line-input-handle-event
       input (cadr-tui:make-input-event :kind :backspace))
      (let ((after-bs
              (length (cadr-tui:single-line-input-value input))))
        (cadr-tui:single-line-input-handle-event
         input
         (cadr-tui:make-input-event :kind :delete-line-start))
        (let ((after-kill
                (length (cadr-tui:single-line-input-value input))))
          (cadr-tui:single-line-input-handle-event
           input (cadr-tui:make-input-event :kind :yank))
          (let ((value (cadr-tui:single-line-input-value input)))
            (list
             after-insert
             after-bs
             after-kill
             (length value)
             (if (plusp (length value))
                 (char-code (char value (1- (length value))))
                 0))))))))

(defun measure-tui-input-component ()
  (let ((observed (run-tui-input-component)))
    (json-object
     "observed"
     (json-object
      "after_insert" (first observed)
      "after_bs" (second observed)
      "after_kill" (third observed)
      "after_yank" (fourth observed)
      "last_code" (fifth observed))
     "edit"
     (collect "tui_input_component.edit"
              (lambda ()
                (lambda ()
                  (run-tui-input-component)))))))

(defun run-tui-native-modifiers ()
  (list
   (if (cadr-tui:is-native-modifier-pressed "shift") 1 0)
   (if (cadr-tui:is-native-modifier-pressed "control") 1 0)
   (if (cadr-tui:is-native-modifier-pressed "option") 1 0)
   (if (cadr-tui:is-native-modifier-pressed "command") 1 0)))

(defun measure-tui-native-modifiers ()
  (let ((observed (run-tui-native-modifiers)))
    (json-object
     "observed"
     (json-object
      "shift" (first observed)
      "control" (second observed)
      "option" (third observed)
      "command" (fourth observed))
     "pressed"
     (collect "tui_native_modifiers.pressed"
              (lambda ()
                (lambda ()
                  (run-tui-native-modifiers)))))))

(defun settings-list-identity (text &optional selected-p)
  (declare (ignore selected-p))
  text)

(defun settings-list-fixture ()
  (cadr-tui:make-settings-list-component
   (list
    (cadr-tui:make-setting-item
     :id "hello" :label "Hello" :current-value "on")
    (cadr-tui:make-setting-item
     :id "help" :label "Help" :current-value "on")
    (cadr-tui:make-setting-item
     :id "world" :label "World" :current-value "off"))
   5
   :search-enabled-p t
   :label-function #'settings-list-identity
   :value-function #'settings-list-identity
   :description-function #'settings-list-identity
   :cursor "→ "
   :hint-function #'settings-list-identity))

(defun settings-list-apply-query (component query)
  (cadr-tui:single-line-input-set-value
   (cadr-tui::settings-list-component-search-input component)
   query)
  (cadr-tui::settings-list-apply-filter component)
  (cadr-tui::settings-list-component-filtered-items component))

(defun settings-list-has-label (items label)
  (if (find label items
            :key #'cadr-tui:setting-item-label
            :test #'string=)
      1
      0))

(defun run-tui-settings-list ()
  (let* ((component (settings-list-fixture))
         (he (settings-list-apply-query component "he"))
         (he-count (length he))
         (he-hello (settings-list-has-label he "Hello"))
         (he-help (settings-list-has-label he "Help"))
         (he-selected
           (cadr-tui:settings-list-component-selected-index
            component))
         (wo-count
           (length (settings-list-apply-query component "wo")))
         (zz-count
           (length (settings-list-apply-query component "zz"))))
    (list he-count he-hello he-help wo-count zz-count he-selected)))

(defun measure-tui-settings-list ()
  (let ((observed (run-tui-settings-list)))
    (json-object
     "observed"
     (json-object
      "he_count" (first observed)
      "he_hello" (second observed)
      "he_help" (third observed)
      "wo_count" (fourth observed)
      "zz_count" (fifth observed)
      "he_selected" (sixth observed))
     "apply_filter"
     (collect "tui_settings_list.apply_filter"
              (lambda ()
                (lambda ()
                  (run-tui-settings-list)))))))

(defun run-ai-capabilities-short-hash ()
  (list
   (cadr-ai:short-hash "")
   (cadr-ai:short-hash "abc")
   (cadr-ai:short-hash "中文😀")))

(defun deferred-tools-fixture ()
  (cadr-ai:make-context
   :tools
   (list
    (cadr-ai:make-tool :name "grep")
    (cadr-ai:make-tool :name "bash")
    (cadr-ai:make-tool :name "read"))
   :messages
   (list
    (cadr-ai:make-assistant-message
     :content
     (list (cadr-ai:make-tool-call :id "1" :name "bash")))
    (cadr-ai:make-tool-result-message
     :tool-call-id "1"
     :tool-name "bash"
     :added-tool-names '("read")))))

(defun deferred-tools-shape (enabled-p)
  (multiple-value-bind (immediate deferred)
      (cadr-ai:split-deferred-tools (deferred-tools-fixture) enabled-p)
    (list
     (length immediate)
     (hash-table-count deferred)
     (if immediate (cadr-ai:tool-name (first immediate)) "")
     (if (rest immediate)
         (cadr-ai:tool-name (second immediate))
         "")
     (if (gethash "read" deferred) 1 0))))

(defun run-ai-capabilities-deferred-tools ()
  (append
   (deferred-tools-shape nil)
   (deferred-tools-shape t)))

(defun run-ai-capabilities-event-stream ()
  (let ((stream
          (cadr-ai:make-event-stream
           :complete-p (lambda (event) (equal event "end"))
           :result-function #'identity)))
    (cadr-ai:event-stream-push stream "a")
    (cadr-ai:event-stream-push stream "b")
    (cadr-ai:event-stream-push stream "end")
    (list
     (cadr-ai:event-stream-next stream)
     (cadr-ai:event-stream-next stream)
     (cadr-ai:event-stream-next stream)
     (cadr-ai:event-stream-result stream))))

(defun resolve-proxy-or-empty (target environment)
  (handler-case
      (or (cadr-ai:resolve-http-proxy-url-for-target target environment) "")
    (error ()
      "ERR")))

(defun run-ai-capabilities-http-proxy ()
  (let ((hit
          '(("HTTPS_PROXY" . "http://proxy.local:8080/")
            ("NO_PROXY" . "none.invalid")))
        (star
          '(("HTTPS_PROXY" . "http://proxy.local:8080/")
            ("NO_PROXY" . "*")))
        (skip
          '(("HTTPS_PROXY" . "http://proxy.local:8080/")
            ("NO_PROXY" . "example.com")))
        (keep
          '(("HTTPS_PROXY" . "http://proxy.local:8080/")
            ("NO_PROXY" . "other.com")))
        (socks
          '(("HTTPS_PROXY" . "socks://127.0.0.1:1080/")
            ("NO_PROXY" . "none.invalid"))))
    (list
     (resolve-proxy-or-empty "https://keep.example.com/x" hit)
     (resolve-proxy-or-empty "https://keep.example.com/x" star)
     (resolve-proxy-or-empty "https://example.com/x" skip)
     (resolve-proxy-or-empty "https://keep.example.com/x" keep)
     (if (string= (resolve-proxy-or-empty "https://keep.example.com/x" socks)
                  "ERR")
         1
         0))))

(defun run-ai-capabilities-session-resources ()
  (let ((recorded nil)
        (n1 0)
        (n2 0)
        (err 0))
    (let ((unreg
            (cadr-ai:register-session-resource-cleanup
             (lambda (session-id)
               (push (or session-id "") recorded)))))
      (cadr-ai:cleanup-session-resources "sess-1")
      (setf n1 (length recorded))
      (funcall unreg)
      (cadr-ai:cleanup-session-resources "sess-2")
      (setf n2 (length recorded)))
    (let ((unreg-err
            (cadr-ai:register-session-resource-cleanup
             (lambda (session-id)
               (declare (ignore session-id))
               (error "boom")))))
      (unwind-protect
           (setf err
                 (handler-case
                     (progn
                       (cadr-ai:cleanup-session-resources "sess-err")
                       0)
                   (error () 1)))
        (funcall unreg-err)))
    (list (or (car (last recorded)) "") n1 n2 err)))

(defun measure-ai-capabilities-short-hash ()
  (let ((hash (run-ai-capabilities-short-hash))
        (deferred (run-ai-capabilities-deferred-tools))
        (events (run-ai-capabilities-event-stream))
        (proxy (run-ai-capabilities-http-proxy))
        (resources (run-ai-capabilities-session-resources)))
    (json-object
     "observed"
     (json-object
      "empty" (first hash)
      "abc" (second hash)
      "cjk" (third hash)
      "off_imm" (first deferred)
      "off_def" (second deferred)
      "off_first" (third deferred)
      "off_second" (fourth deferred)
      "off_read" (fifth deferred)
      "on_imm" (sixth deferred)
      "on_def" (seventh deferred)
      "on_first" (eighth deferred)
      "on_second" (ninth deferred)
      "on_read" (tenth deferred)
      "ev_first" (first events)
      "ev_second" (second events)
      "ev_third" (third events)
      "ev_result" (fourth events)
      "px_hit" (first proxy)
      "px_star" (second proxy)
      "px_skip" (third proxy)
      "px_keep" (fourth proxy)
      "px_socks" (fifth proxy)
      "sr_first" (first resources)
      "sr_n1" (second resources)
      "sr_n2" (third resources)
      "sr_err" (fourth resources))
     "short_hash"
     (collect "ai_capabilities.short_hash"
              (lambda ()
                (lambda ()
                  (run-ai-capabilities-short-hash))))
     "deferred_tools"
     (collect "ai_capabilities.deferred_tools"
              (lambda ()
                (lambda ()
                  (run-ai-capabilities-deferred-tools))))
     "event_stream"
     (collect "ai_capabilities.event_stream"
              (lambda ()
                (lambda ()
                  (run-ai-capabilities-event-stream))))
     "http_proxy"
     (collect "ai_capabilities.http_proxy"
              (lambda ()
                (lambda ()
                  (run-ai-capabilities-http-proxy))))
     "session_resources"
     (collect "ai_capabilities.session_resources"
              (lambda ()
                (lambda ()
                  (run-ai-capabilities-session-resources)))))))

(defun strip-ansi-csi-osc ()
  (format nil
          "a~C[31mred~C[0m~C]8;;https://example.com~Clink~C]8;;~Cz"
          #\Escape #\Escape #\Escape
          (code-char 7) #\Escape (code-char 7)))

(defun run-cli-support-strip-ansi ()
  (list
   (cadr-cli::strip-ansi (strip-ansi-csi-osc))
   (cadr-cli::strip-ansi (format nil "~Ccdone" #\Escape))
   (cadr-cli::strip-ansi (format nil "~Cmok" #\Escape))
   (cadr-cli::strip-ansi "hello")))

(defun run-cli-support-normalize-path ()
  (let ((nbsp (code-char #x00a0)))
    (list
     (cadr-cli::normalize-path-input
      "  /tmp/foo  " :trim-p t :expand-tilde-p nil)
     (cadr-cli::normalize-path-input
      "@rel" :strip-at-prefix-p t :expand-tilde-p nil)
     (cadr-cli::normalize-path-input
      (format nil "a~Ab" nbsp)
      :normalize-unicode-spaces-p t :expand-tilde-p nil)
     (cadr-cli::normalize-path-input
      "~/x" :home-directory "/tmp/home")
     (cadr-cli::normalize-path-input
      "file:///tmp/z" :expand-tilde-p nil))))

(defun timing-field-ms (text label)
  (let* ((needle (format nil "  ~A: " label))
         (start (search needle text)))
    (when start
      (let* ((num-start (+ start (length needle)))
             (ms (search "ms" text :start2 num-start)))
        (when ms
          (parse-integer text :start num-start :end ms))))))

(defun run-cli-support-timings ()
  (let ((now 0))
    (let ((cadr-cli::*timing-enabled-p* t)
          (cadr-cli::*timing-clock*
            (lambda ()
              (incf now 10))))
      (cadr-cli::reset-timings)
      (cadr-cli::record-timing "boot")
      (cadr-cli::record-timing "load")
      (let ((text
              (with-output-to-string (stream)
                (cadr-cli::print-timings stream))))
        (list
         (if (search "Startup Timings: main" text) 1 0)
         (or (timing-field-ms text "boot") -1)
         (or (timing-field-ms text "load") -1)
         (or (timing-field-ms text "TOTAL") -1))))))

(defun run-cli-support-event-bus ()
  (let ((recorded nil)
        (n1 0)
        (n2 0)
        (n3 0)
        (throw-ok 0))
    (let ((bus
            (cadr-cli::make-event-bus
             :error-output (make-broadcast-stream))))
      (let ((unsub
              (cadr-cli::event-bus-on
               bus "ch"
               (lambda (data)
                 (push data recorded)))))
        (cadr-cli::event-bus-emit bus "ch" "a")
        (cadr-cli::event-bus-emit bus "other" "b")
        (setf n1 (length recorded))
        (funcall unsub)
        (cadr-cli::event-bus-emit bus "ch" "c")
        (setf n2 (length recorded)))
      (cadr-cli::event-bus-on
       bus "boom"
       (lambda (data)
         (declare (ignore data))
         (error "boom")))
      (setf throw-ok
            (handler-case
                (progn
                  (cadr-cli::event-bus-emit bus "boom" "x")
                  1)
              (error () 0)))
      (cadr-cli::event-bus-clear bus)
      (cadr-cli::event-bus-emit bus "ch" "d")
      (setf n3 (length recorded)))
    (list (or (car (last recorded)) "") n1 n2 n3 throw-ok)))

(defun attribution-flag (headers name)
  (if (assoc name headers :test #'string-equal) 1 0))

(defun attribution-val (headers name)
  (or (cdr (assoc name headers :test #'string-equal)) ""))

(defun run-cli-support-attribution-headers ()
  (let ((or-on
          (cadr-cli::provider-attribution-headers
           :provider :openrouter
           :base-url "https://openrouter.ai/api/v1"
           :telemetry-p t))
        (or-off
          (cadr-cli::provider-attribution-headers
           :provider :openrouter
           :base-url "https://openrouter.ai/api/v1"
           :telemetry-p nil))
        (nv
          (cadr-cli::provider-attribution-headers
           :provider :nvidia
           :base-url "https://integrate.api.nvidia.com/v1"
           :telemetry-p t))
        (cf
          (cadr-cli::provider-attribution-headers
           :provider :cloudflare-workers-ai
           :base-url "https://api.cloudflare.com/client/v4"
           :telemetry-p t))
        (oc
          (cadr-cli::provider-attribution-headers
           :provider :opencode
           :base-url "https://opencode.ai/api"
           :telemetry-p nil
           :session-id "sess-1"))
        (ov
          (cadr-cli::provider-attribution-headers
           :provider :openrouter
           :base-url "https://openrouter.ai/api/v1"
           :telemetry-p t
           :request-headers
           '(("X-OpenRouter-Title" . "custom")))))
    (list
     (attribution-flag or-on "HTTP-Referer")
     (attribution-flag or-on "X-OpenRouter-Title")
     (attribution-val or-on "X-OpenRouter-Categories")
     (attribution-flag or-off "HTTP-Referer")
     (attribution-flag nv "X-BILLING-INVOKE-ORIGIN")
     (attribution-flag cf "User-Agent")
     (attribution-val oc "x-opencode-session")
     (attribution-flag oc "x-opencode-client")
     (attribution-val ov "X-OpenRouter-Title"))))

(defun shell-config-shape (config)
  (list
   (cadr-cli::shell-config-shell config)
   (or (first (cadr-cli::shell-config-arguments config)) "")
   (if (eq (cadr-cli::shell-config-command-transport config) :stdin) 1 0)))

(defun run-cli-support-shell-config ()
  (let ((default (shell-config-shape (cadr-cli::get-shell-config)))
        (custom (shell-config-shape (cadr-cli::get-shell-config "/bin/bash")))
        (miss
          (handler-case
              (progn
                (cadr-cli::get-shell-config "/tmp/cadr-no-such-shell")
                0)
            (error () 1))))
    (append default custom (list miss))))

(defun run-cli-support-sanitize-output ()
  (list
   (cadr-cli::sanitize-binary-output "hello")
   (cadr-cli::sanitize-binary-output
    (format nil "a~Cb~Cc" (code-char 0) (code-char 7)))
   (cadr-cli::sanitize-binary-output
    (format nil "a~Cb~Cc~Cd" #\Tab #\Newline #\Return))
   (cadr-cli::sanitize-binary-output
    (format nil "x~Ay" (code-char #xfff9)))
   (cadr-cli::sanitize-binary-output
    (format nil "p~Cq" (code-char #x1b)))))

(defun git-source-shape (source)
  (let ((parsed (cadr-cli::parse-git-source source)))
    (if parsed
        (list
         (or (getf parsed :host) "")
         (or (getf parsed :path) "")
         (or (getf parsed :ref) "")
         (if (getf parsed :pinned-p) 1 0))
        (list "" "" "" 0))))

(defun run-cli-support-git-source ()
  (append
   (git-source-shape "https://github.com/user/repo@v1.0.0")
   (git-source-shape "git:git@github.com:user/repo")
   (git-source-shape "git:github.com/user/repo")
   (list
    (if (cadr-cli::parse-git-source "git@github.com:user/repo") 1 0)
    (if (cadr-cli::parse-git-source
         "git:git@evil.example:../../victim/repo")
        1
        0)
    (if (cadr-cli::parse-git-source
         "git:git@evil.example:/absolute/repo")
        1
        0))))

(defun user-agent-shape (ua)
  (list
   (if (search "1.2.3" ua) 1 0)
   (if (and (find #\( ua) (find #\) ua)) 1 0)
   (count #\; ua)))

(defun run-cli-support-user-agent ()
  (user-agent-shape (cadr-cli::cadr-user-agent "1.2.3")))

(defparameter *paired-changelog-text*
  (format nil
          "# Changelog~%~%## [0.2.0] - 2026-01-02~%~%New.~%~%## malformed~%ignored~%~%## 0.1.0~%~%Old.~%"))

(defun paired-changelog-path ()
  (merge-pathnames "changelog.md" *scratch-directory*))

(defun write-paired-changelog ()
  (ensure-directories-exist *scratch-directory*)
  (with-open-file (out (paired-changelog-path)
                       :direction :output
                       :if-exists :supersede
                       :if-does-not-exist :create
                       :external-format :utf-8)
    (write-string *paired-changelog-text* out))
  (namestring (paired-changelog-path)))

(defun changelog-entry-version (entry)
  (or (getf entry :version) ""))

(defun changelog-entry-content (entry)
  (or (getf entry :content) ""))

(defun run-cli-support-parse-changelog ()
  (let* ((entries
           (or (cadr-cli::parse-changelog (paired-changelog-path))
               nil))
         (first (first entries))
         (second (second entries))
         (missing
           (cadr-cli::parse-changelog
            (merge-pathnames
             "no-such-changelog.md" *scratch-directory*))))
    (list
     (length entries)
     (changelog-entry-version first)
     (if (search "## [0.2.0]" (changelog-entry-content first)) 1 0)
     (changelog-entry-version second)
     (if missing (length missing) 0))))

(defun experimental-flag (value)
  (if (cadr-cli::experimental-features-enabled-p value) 1 0))

(defun run-cli-support-experimental ()
  ;; Production predicate string= "1". Pass the value; do not exact
  ;; CADR_EXPERIMENTAL vs PI_EXPERIMENTAL.
  (list
   (experimental-flag "1")
   (experimental-flag "")
   (experimental-flag "0")
   (experimental-flag "true")
   (experimental-flag nil)))

(defun measure-cli-support-strip-ansi ()
  (write-paired-changelog)
  (let ((ansi (run-cli-support-strip-ansi))
        (paths (run-cli-support-normalize-path))
        (timings (run-cli-support-timings))
        (bus (run-cli-support-event-bus))
        (headers (run-cli-support-attribution-headers))
        (shell (run-cli-support-shell-config))
        (sanitize (run-cli-support-sanitize-output))
        (git (run-cli-support-git-source))
        (ua (run-cli-support-user-agent))
        (changelog (run-cli-support-parse-changelog))
        (experimental (run-cli-support-experimental)))
    (json-object
     "observed"
     (json-object
      "csi_osc" (first ansi)
      "ris" (second ansi)
      "single" (third ansi)
      "plain" (fourth ansi)
      "trim" (first paths)
      "at" (second paths)
      "nbsp" (third paths)
      "tilde" (fourth paths)
      "file" (fifth paths)
      "time_title" (first timings)
      "time_boot" (second timings)
      "time_load" (third timings)
      "time_total" (fourth timings)
      "eb_first" (first bus)
      "eb_n1" (second bus)
      "eb_n2" (third bus)
      "eb_n3" (fourth bus)
      "eb_throw" (fifth bus)
      "at_or_ref" (first headers)
      "at_or_title" (second headers)
      "at_or_cat" (third headers)
      "at_or_off" (fourth headers)
      "at_nv" (fifth headers)
      "at_cf" (sixth headers)
      "at_oc_sess" (seventh headers)
      "at_oc_client" (eighth headers)
      "at_ov" (ninth headers)
      "sh_def" (first shell)
      "sh_arg" (second shell)
      "sh_stdin" (third shell)
      "sh_custom" (fourth shell)
      "sh_carg" (fifth shell)
      "sh_cstdin" (sixth shell)
      "sh_miss" (seventh shell)
      "sz_plain" (first sanitize)
      "sz_ctl" (second sanitize)
      "sz_tnr" (third sanitize)
      "sz_fmt" (fourth sanitize)
      "sz_esc" (fifth sanitize)
      "gs_https_host" (nth 0 git)
      "gs_https_path" (nth 1 git)
      "gs_https_ref" (nth 2 git)
      "gs_https_pin" (nth 3 git)
      "gs_ssh_host" (nth 4 git)
      "gs_ssh_path" (nth 5 git)
      "gs_ssh_pin" (nth 7 git)
      "gs_short_host" (nth 8 git)
      "gs_short_path" (nth 9 git)
      "gs_bare" (nth 12 git)
      "gs_dotdot" (nth 13 git)
      "gs_abs" (nth 14 git)
      "ua_ver" (first ua)
      "ua_paren" (second ua)
      "ua_semi" (third ua)
      "cl_n" (first changelog)
      "cl_first" (second changelog)
      "cl_hdr" (third changelog)
      "cl_second" (fourth changelog)
      "cl_miss" (fifth changelog)
      "ex_on" (nth 0 experimental)
      "ex_empty" (nth 1 experimental)
      "ex_zero" (nth 2 experimental)
      "ex_true" (nth 3 experimental)
      "ex_nil" (nth 4 experimental))
     "strip_ansi"
     (collect "cli_support.strip_ansi"
              (lambda ()
                (lambda ()
                  (run-cli-support-strip-ansi))))
     "normalize_path"
     (collect "cli_support.normalize_path"
              (lambda ()
                (lambda ()
                  (run-cli-support-normalize-path))))
     "timings"
     (collect "cli_support.timings"
              (lambda ()
                (lambda ()
                  (run-cli-support-timings))))
     "event_bus"
     (collect "cli_support.event_bus"
              (lambda ()
                (lambda ()
                  (run-cli-support-event-bus))))
     "attribution_headers"
     (collect "cli_support.attribution_headers"
              (lambda ()
                (lambda ()
                  (run-cli-support-attribution-headers))))
     "shell_config"
     (collect "cli_support.shell_config"
              (lambda ()
                (lambda ()
                  (run-cli-support-shell-config))))
     "sanitize_output"
     (collect "cli_support.sanitize_output"
              (lambda ()
                (lambda ()
                  (run-cli-support-sanitize-output))))
     "git_source"
     (collect "cli_support.git_source"
              (lambda ()
                (lambda ()
                  (run-cli-support-git-source))))
     "user_agent"
     (collect "cli_support.user_agent"
              (lambda ()
                (lambda ()
                  (run-cli-support-user-agent))))
     "parse_changelog"
     (collect "cli_support.parse_changelog"
              (lambda ()
                (lambda ()
                  (run-cli-support-parse-changelog))))
     "experimental"
     (collect "cli_support.experimental"
              (lambda ()
                (lambda ()
                  (run-cli-support-experimental)))))))

(defun decode-highlight-or-empty (entity)
  (or (cadr-cli::decode-highlight-entity entity) ""))

(defun run-cli-interactive-decode-entity ()
  (list
   (decode-highlight-or-empty "amp")
   (decode-highlight-or-empty "lt")
   (decode-highlight-or-empty "gt")
   (decode-highlight-or-empty "quot")
   (decode-highlight-or-empty "apos")
   (decode-highlight-or-empty "#65")
   (if (cadr-cli::decode-highlight-entity "nope") 1 0)))

(defun wayland-session-flag (environment)
  (if (cadr-cli::clipboard-wayland-p environment)
      1
      0))

(defun run-cli-interactive-wayland ()
  ;; Empty env must be a non-NIL dummy alist: NIL falls through to
  ;; live getenv. Do not exact empty WAYLAND_DISPLAY (Lisp non-empty
  ;; vs JS Boolean("")) or mixed-case XDG_SESSION_TYPE (string-equal
  ;; vs === "wayland").
  (list
   (wayland-session-flag '(("WAYLAND_DISPLAY" . "wayland-0")))
   (wayland-session-flag '(("XDG_SESSION_TYPE" . "wayland")))
   (wayland-session-flag '(("XDG_SESSION_TYPE" . "x11")))
   (wayland-session-flag '(("FOO" . "1")))))

(defun cwd-footer-flag (cwd home expected)
  (if (string= (cadr-cli::format-cwd-for-footer cwd home) expected)
      1
      0))

(defun run-cli-interactive-cwd-footer ()
  ;; POSIX only. Do not exact a missing home (cadr still trims;
  ;; pi returns cwd as-is) or Windows separators.
  (list
   (cwd-footer-flag "/home/u" "/home/u" "~")
   (cwd-footer-flag "/home/u/proj" "/home/u" "~/proj")
   (cwd-footer-flag "/tmp" "/home/u" "/tmp")
   (cwd-footer-flag "/home/u/proj/" "/home/u/" "~/proj")))

(defun auth-type-label-flag (auth-type expected)
  (if (string= (cadr-cli::tui-auth-type-label auth-type) expected)
      1
      0))

(defun run-cli-interactive-auth-type ()
  ;; oauth / api-key only. Do not exact other types (cadr's else
  ;; branch is "API key"; pi's union is those two strings).
  (list
   (auth-type-label-flag :oauth "subscription")
   (auth-type-label-flag :api-key "API key")))

(defun parse-auto-theme-encoded (setting)
  (let ((parsed (cadr-cli:parse-auto-theme-setting setting)))
    (if parsed
        (format nil "~A|~A"
                (getf parsed :light-theme)
                (getf parsed :dark-theme))
        "")))

(defun run-cli-interactive-parse-auto-theme ()
  (list
   (parse-auto-theme-encoded "  light / dark  ")
   (parse-auto-theme-encoded " /dark")
   (parse-auto-theme-encoded "light/  ")
   (parse-auto-theme-encoded nil)
   (parse-auto-theme-encoded "light/dark/extra")
   (parse-auto-theme-encoded "dark")))

(defun resolve-theme-str (setting background)
  (or (cadr-cli:resolve-theme-setting setting background) ""))

(defun run-cli-interactive-resolve-theme ()
  (list
   (resolve-theme-str "  light / dark  " :light)
   (resolve-theme-str "  light / dark  " :dark)
   (resolve-theme-str "solarized" :light)
   (resolve-theme-str "light/dark/extra" :dark)
   (resolve-theme-str nil :light)))

(defun measure-cli-interactive-decode-entity ()
  (let ((observed (run-cli-interactive-decode-entity))
        (wayland (run-cli-interactive-wayland))
        (cwd (run-cli-interactive-cwd-footer))
        (auth (run-cli-interactive-auth-type))
        (parse-auto-theme (run-cli-interactive-parse-auto-theme))
        (resolve-theme (run-cli-interactive-resolve-theme)))
    (json-object
     "observed"
     (json-object
      "amp" (first observed)
      "lt" (second observed)
      "gt" (third observed)
      "quot" (fourth observed)
      "apos" (fifth observed)
      "hash65" (sixth observed)
      "miss" (seventh observed)
      "wl_disp" (first wayland)
      "wl_type" (second wayland)
      "wl_x11" (third wayland)
      "wl_none" (fourth wayland)
      "cf_home" (first cwd)
      "cf_proj" (second cwd)
      "cf_out" (third cwd)
      "cf_slash" (fourth cwd)
      "al_oauth" (first auth)
      "al_key" (second auth)
      "pat_valid" (first parse-auto-theme)
      "pat_empty_left" (second parse-auto-theme)
      "pat_empty_right" (third parse-auto-theme)
      "pat_nil" (fourth parse-auto-theme)
      "pat_double" (fifth parse-auto-theme)
      "pat_fixed" (sixth parse-auto-theme)
      "rts_auto_light" (first resolve-theme)
      "rts_auto_dark" (second resolve-theme)
      "rts_fixed" (third resolve-theme)
      "rts_bad" (fourth resolve-theme)
      "rts_nil" (fifth resolve-theme))
     "decode_entity"
     (collect "cli_interactive_controller.decode_entity"
              (lambda ()
                (lambda ()
                  (run-cli-interactive-decode-entity))))
     "wayland"
     (collect "cli_interactive_controller.wayland"
              (lambda ()
                (lambda ()
                  (run-cli-interactive-wayland))))
     "cwd_footer"
     (collect "cli_interactive_controller.cwd_footer"
              (lambda ()
                (lambda ()
                  (run-cli-interactive-cwd-footer))))
     "auth_type"
     (collect "cli_interactive_controller.auth_type"
              (lambda ()
                (lambda ()
                  (run-cli-interactive-auth-type))))
     "parse_auto_theme"
     (collect "cli_interactive_controller.parse_auto_theme"
              (lambda ()
                (lambda ()
                  (run-cli-interactive-parse-auto-theme))))
     "resolve_theme"
     (collect "cli_interactive_controller.resolve_theme"
              (lambda ()
                (lambda ()
                  (run-cli-interactive-resolve-theme)))))))

(defun session-search-fixture-records ()
  (list
   (cadr-cli:make-session-search-record
    :id "019f0000-0000-7000-8000-00000000cadr"
    :name "alpha"
    :cwd "/tmp/a"
    :all-messages-text "hello cadr world"
    :modified 3)
   (cadr-cli:make-session-search-record
    :id "other-id"
    :name nil
    :cwd "/tmp/b"
    :all-messages-text "nope"
    :modified 2)
   (cadr-cli:make-session-search-record
    :id "named-sess"
    :name "  named  "
    :cwd "/proj"
    :all-messages-text "foo"
    :modified 1)))

(defun session-search-count (query &key (name-filter :all))
  (length
   (cadr-cli:filter-and-sort-sessions
    (session-search-fixture-records)
    query
    :sort-mode :recent
    :name-filter name-filter)))

(defun run-cli-selectors-session-search ()
  (list
   (session-search-count "")
   (session-search-count "cadr")
   (session-search-count "no-such-session-zz")
   (session-search-count "re:cadr")
   (session-search-count "re:[")
   (session-search-count "" :name-filter :named)))

(defun run-cli-selectors-key-text ()
  ;; Linux: do not exact darwin alt→option.
  (list
   (cadr-cli:format-key-text "ctrl+c")
   (cadr-cli:format-key-text "ctrl+c/escape")
   (cadr-cli:format-key-text "shift+tab")
   (cadr-cli:format-key-text "ctrl+c" :capitalize-p t)
   (cadr-cli:format-key-text "")))

(defun fuzzy-filter-join (items query text-function)
  (format nil "~{~A~^,~}"
          (cadr-cli::selector-fuzzy-filter items query text-function)))

(defun run-cli-selectors-fuzzy-filter ()
  (let ((items '("apple" "banana" "cherry"))
        (apps '("a_p_p" "app" "application"))
        (cls '("clone" "cl"))
        (model '((:id "gpt-5.5" :provider "openai-codex"))))
    (list
     (length (cadr-cli::selector-fuzzy-filter items "" #'identity))
     (fuzzy-filter-join items "an" #'identity)
     (fuzzy-filter-join apps "app" #'identity)
     (fuzzy-filter-join cls "cl" #'identity)
     (length
      (cadr-cli::selector-fuzzy-filter
       model "openai-codex/gpt-5.5"
       (lambda (entry)
         (format nil "~A ~A"
                 (getf entry :id)
                 (getf entry :provider))))))))

(defun run-cli-selectors-delete-query ()
  (list
   (cadr-cli::selector-delete-query-character "")
   (cadr-cli::selector-delete-query-character "a")
   (cadr-cli::selector-delete-query-character "abc")
   (cadr-cli::selector-delete-query-character "café")
   (cadr-cli::selector-delete-query-character "a🙂b")
   (cadr-cli::selector-delete-query-character
    (concatenate 'string "e" (string (code-char #x301))))))

(defun visible-slice-summary (count selected maximum)
  (let ((items (loop for i below count collect i)))
    (multiple-value-bind (visible start end total)
        (cadr-cli::selector-frame-visible-slice
         items selected maximum)
      (declare (ignore visible))
      (list start end (- end start) total))))

(defun run-cli-selectors-visible-slice ()
  (mapcar
   (lambda (fixture)
     (apply #'visible-slice-summary fixture))
   '((0 0 8) (5 2 8) (20 10 8) (20 0 8) (20 19 8) (3 1 8))))

(defun run-cli-selectors-move-index ()
  (mapcar
   (lambda (fixture)
     (apply #'cadr-cli::selector-frame-move-index fixture))
   '((0 0 1) (0 5 -1) (4 5 1) (2 5 3) (2 5 -2) (1 5 10))))

(defun run-cli-selectors-align-left-right ()
  (mapcar
   (lambda (fixture)
     (destructuring-bind (left right width) fixture
       (cadr-cli::selector-align-left-right left right width)))
   '(("Title" "Sort: Recent" 40)
     ("Very Long Left Title Here" "Right" 20)
     ("Left" "Very Long Right Side Text" 20)
     ("ABCDEFGHIJ" "KLMNOPQRST" 10)
     ("" "Right Only" 15)
     ("Left Only" "" 15))))

(defun run-cli-selectors-fit-line ()
  (list
   (cadr-cli::selector-fit-line "hello" 10)
   (cadr-cli::selector-fit-line "hello world" 5)
   (cadr-cli::selector-fit-line "hello" 10 :pad-p t)
   (cadr-cli::selector-fit-line "hello world" 8 :ellipsis "...")
   (cadr-cli::selector-fit-line "café🙂" 4)
   (cadr-cli::selector-fit-line "" 5 :pad-p t)))

(defun run-cli-selectors-border-line ()
  (list
   (cadr-cli::selector-border-line 40)
   (cadr-cli::selector-border-line 40 :accent)
   (cadr-cli::selector-border-line 1)
   (cadr-cli::selector-border-line 80)
   (cadr-cli::selector-border-line 10 :accent)
   (cadr-cli::selector-border-line 20)))

(defun run-cli-selectors-selected-line ()
  (list
   (cadr-cli::selector-selected-line "hello" 10)
   (cadr-cli::selector-selected-line "hello world" 8)
   (cadr-cli::selector-selected-line "café🙂" 6)
   (cadr-cli::selector-selected-line "" 5)
   (cadr-cli::selector-selected-line "item" 20)
   (cadr-cli::selector-selected-line "ABCDEFGHIJ" 5)))

(defun run-cli-selectors-muted-line ()
  (list
   (cadr-cli::selector-muted-line "hello" 10)
   (cadr-cli::selector-muted-line "hello world" 8)
   (cadr-cli::selector-muted-line "café🙂" 6)
   (cadr-cli::selector-muted-line "" 5)
   (cadr-cli::selector-muted-line "item" 20)
   (cadr-cli::selector-muted-line "ABCDEFGHIJ" 5)))

(defun run-cli-selectors-dim-line ()
  (list
   (cadr-cli::selector-dim-line "hello" 10)
   (cadr-cli::selector-dim-line "hello world" 8)
   (cadr-cli::selector-dim-line "café🙂" 6)
   (cadr-cli::selector-dim-line "" 5)
   (cadr-cli::selector-dim-line "item" 20)
   (cadr-cli::selector-dim-line "ABCDEFGHIJ" 5)))

(defun csi-modified-arrow (modifier direction)
  (format nil "~c[1;~a~a" #\Escape modifier direction))

(defun run-cli-selectors-modified-cursor-key ()
  (list
   (cadr-cli::selector-modified-cursor-key
    (csi-modified-arrow 1 #\A))
   (cadr-cli::selector-modified-cursor-key
    (csi-modified-arrow 2 #\B))
   (cadr-cli::selector-modified-cursor-key
    (csi-modified-arrow 5 #\C))
   (cadr-cli::selector-modified-cursor-key
    (csi-modified-arrow 3 #\D))
   (cadr-cli::selector-modified-cursor-key
    (csi-modified-arrow 6 #\A))
   (cadr-cli::selector-modified-cursor-key
    (csi-modified-arrow 9 #\B))))

(defun run-cli-selectors-title-line ()
  (list
   (cadr-cli::selector-title-line "Resume Session" 40)
   (cadr-cli::selector-title-line "Very Long Title Here That Truncates" 20)
   (cadr-cli::selector-title-line "" 10)
   (cadr-cli::selector-title-line "café" 15)
   (cadr-cli::selector-title-line "A" 5)
   (cadr-cli::selector-title-line "Models" 30)))

(defun run-cli-selectors-overlay-title-line ()
  (list
   (cadr-cli::selector-overlay-title-line "Select provider to configure:" 40)
   (cadr-cli::selector-overlay-title-line
    "Very Long Auth Overlay Title That Truncates" 20)
   (cadr-cli::selector-overlay-title-line "" 10)
   (cadr-cli::selector-overlay-title-line "café" 15)
   (cadr-cli::selector-overlay-title-line "A" 5)
   (cadr-cli::selector-overlay-title-line "Project trust" 30)))

(defun run-cli-selectors-input-line ()
  (list
   (cadr-cli::selector-input-line "" 20)
   (cadr-cli::selector-input-line "hello" 20)
   (cadr-cli::selector-input-line "ab" 12)
   (cadr-cli::selector-input-line "你🙂a" 10)
   (cadr-cli::selector-input-line "你🙂a" 3)
   (cadr-cli::selector-input-line "가나다라마바사아자차카타파하" 20)))

(defun run-cli-selectors-keybinding-text ()
  (let ((default (cadr-tui:make-keybindings-manager))
        (custom
          (cadr-tui:make-keybindings-manager
           :user-bindings
           '(("tui.select.confirm" . "ctrl+x")
             ("tui.select.cancel" . ("alt+x" "ctrl+c"))))))
    (list
     (cadr-cli::selector-keybinding-text default "tui.select.confirm")
     (cadr-cli::selector-keybinding-text default "tui.select.cancel")
     (cadr-cli::selector-keybinding-text default "tui.editor.cursorLeft")
     (cadr-cli::selector-keybinding-text default "tui.editor.historyPrevious")
     (cadr-cli::selector-keybinding-text custom "tui.select.confirm")
     (cadr-cli::selector-keybinding-text custom "tui.select.cancel"))))

(defun run-cli-selectors-keybinding-hint ()
  (let ((default (cadr-tui:make-keybindings-manager))
        (custom
          (cadr-tui:make-keybindings-manager
           :user-bindings
           '(("tui.select.confirm" . "ctrl+x")
             ("tui.select.cancel" . ("alt+x" "ctrl+c"))))))
    (list
     (cadr-cli::selector-keybinding-hint default "tui.select.confirm" "confirm")
     (cadr-cli::selector-keybinding-hint default "tui.select.cancel" "cancel")
     (cadr-cli::selector-keybinding-hint default "tui.editor.cursorLeft" "left")
     (cadr-cli::selector-keybinding-hint default "tui.editor.historyPrevious" "prev")
     (cadr-cli::selector-keybinding-hint custom "tui.select.confirm" "save")
     (cadr-cli::selector-keybinding-hint custom "tui.select.cancel" "cancel"))))

(defparameter *session-format-age-now* 1700000000000)

(defun run-cli-selectors-session-format-age ()
  (let ((now *session-format-age-now*))
    (list
     (cadr-cli::session-selector-format-age now now)
     (cadr-cli::session-selector-format-age (- now 45000) now)
     (cadr-cli::session-selector-format-age (- now 120000) now)
     (cadr-cli::session-selector-format-age (- now 3600000) now)
     (cadr-cli::session-selector-format-age (- now 86400000) now)
     (cadr-cli::session-selector-format-age (- now (* 10 86400000)) now))))

(defun session-record-label-fixture-records ()
  (list
   (cadr-cli:make-session-search-record
    :id "named" :name "My Session" :first-message "ignored")
   (cadr-cli:make-session-search-record
    :id "first" :name nil :first-message "hello world")
   (cadr-cli:make-session-search-record
    :id "empty" :name nil :first-message "")
   (cadr-cli:make-session-search-record
    :id "ctrl"
    :name nil
    :first-message
    (format nil "first~%second~Ctab~A[2Jclear~Cend"
            #\Tab (string (code-char 27)) (code-char 127)))
   (cadr-cli:make-session-search-record
    :id "name-ctrl"
    :name (format nil "bad~Cname" (code-char 127))
    :first-message "ignored")))

(defun run-cli-selectors-session-record-label ()
  (mapcar #'cadr-cli::session-selector-record-label
          (session-record-label-fixture-records)))

(defun run-cli-selectors-session-shorten-path ()
  (let ((home
          (string-right-trim
           "/" (namestring (user-homedir-pathname)))))
    (list
     (cadr-cli::session-selector-shorten-path home)
     (cadr-cli::session-selector-shorten-path
      (concatenate 'string home "land/session.jsonl"))
     (cadr-cli::session-selector-shorten-path
      "/tmp/session.jsonl")
     (cadr-cli::session-selector-shorten-path
      (concatenate 'string home "projects/pi-mono/README.md"))
     (cadr-cli::session-selector-shorten-path ""))))

(defun session-quoted-search-position (record query)
  (or (cadr-cli::search-record-position record query) -1))

(defun run-cli-selectors-session-quoted-search ()
  (let ((hit (first (session-search-fixture-records)))
        (miss (second (session-search-fixture-records))))
    (list
     (session-quoted-search-position hit "\"cadr\"")
     (session-quoted-search-position hit "\"hello cadr\"")
     (session-quoted-search-position hit "\"not-found\"")
     (session-quoted-search-position miss "\"cadr\"")
     (session-quoted-search-position hit "\"alpha\"")
     (session-quoted-search-position hit "\"nope\""))))

(defun session-thread-fixture-records ()
  (list
   (cadr-cli:make-session-search-record
    :id "parent" :path "/tmp/goal20/parent.jsonl" :modified 10)
   (cadr-cli:make-session-search-record
    :id "child1" :path "/tmp/goal20/child1.jsonl"
    :parent-path "/tmp/goal20/parent.jsonl" :modified 8)
   (cadr-cli:make-session-search-record
    :id "grand" :path "/tmp/goal20/grand.jsonl"
    :parent-path "/tmp/goal20/child1.jsonl" :modified 7)
   (cadr-cli:make-session-search-record
    :id "child2" :path "/tmp/goal20/child2.jsonl"
    :parent-path "/tmp/goal20/parent.jsonl" :modified 6)
   (cadr-cli:make-session-search-record
    :id "root2" :path "/tmp/goal20/root2.jsonl" :modified 5)))

(defun run-cli-selectors-session-thread-records ()
  (let ((threaded
          (cadr-cli:thread-session-records
           (session-thread-fixture-records))))
    (list
     (length threaded)
     (format nil "~{~A~^,~}" (mapcar #'car threaded))
     (format nil "~{~A~^,~}"
              (mapcar
               (lambda (node)
                 (cadr-cli:session-search-record-id (cdr node)))
               threaded)))))

(defun run-cli-selectors-session-binding-label ()
  (let ((default (cadr-cli::make-session-selector-state))
        (custom
          (cadr-cli::make-session-selector-state
           :keybindings
           (cadr-cli::make-session-selector-keybindings
            '(("app.session.toggleSort" . "ctrl+k"))))))
    (list
     (cadr-cli::session-selector-binding-label
      default "tui.select.confirm")
     (cadr-cli::session-selector-binding-label
      default "app.session.delete")
     (cadr-cli::session-selector-binding-label
      default "app.session.deleteNoninvasive")
     (cadr-cli::session-selector-binding-label
      default "app.session.not-a-binding")
     (cadr-cli::session-selector-binding-label
      custom "app.session.toggleSort"))))

(defun session-same-path-int (left right)
  (if (cadr-cli::same-session-path-p left right) 1 0))

(defun run-cli-selectors-session-same-path ()
  (list
   (session-same-path-int
    "/tmp/goal20/session-a.jsonl"
    "/tmp/goal20/session-a.jsonl")
   (session-same-path-int
    "/tmp/goal20/session-a.jsonl"
    "/tmp/goal20/session-b.jsonl")
   (session-same-path-int nil "/tmp/goal20/session-a.jsonl")
   (session-same-path-int "/tmp/goal20/session-a.jsonl" nil)
   (session-same-path-int nil nil)))

(defun session-quoted-p-int (query)
  (if (cadr-cli::quoted-search-p query) 1 0))

(defun run-cli-selectors-session-quoted-p ()
  (list
   (session-quoted-p-int "\"cadr\"")
   (session-quoted-p-int "\"hello world\"")
   (session-quoted-p-int "cadr")
   (session-quoted-p-int "")
   (session-quoted-p-int "\"")
   (session-quoted-p-int "\"open")))

(defun session-named-p-int (name)
  (if (cadr-cli::named-session-p
       (cadr-cli::make-session-search-record :name name))
      1
      0))

(defun run-cli-selectors-session-named-p ()
  (list
   (session-named-p-int "alpha")
   (session-named-p-int "   ")
   (session-named-p-int "")
   (session-named-p-int nil)))

(defun settings-thinking-desc-str (value)
  (or (cadr-cli::settings-thinking-description value) ""))

(defun run-cli-selectors-settings-thinking-description ()
  (list
   (settings-thinking-desc-str :off)
   (settings-thinking-desc-str :minimal)
   (settings-thinking-desc-str :low)
   (settings-thinking-desc-str :medium)
   (settings-thinking-desc-str :high)
   (settings-thinking-desc-str :xhigh)
   (settings-thinking-desc-str :max)
   (settings-thinking-desc-str :bogus)))

(defun run-cli-selectors-settings-display-value ()
  (list
   (cadr-cli::settings-display-value t)
   (cadr-cli::settings-display-value nil)
   (cadr-cli::settings-display-value :medium)
   (cadr-cli::settings-display-value 42)
   (cadr-cli::settings-display-value "hello")))

(defun make-settings-auto-theme-fixture (light dark)
  (cadr-cli::make-settings-selector-state
   :current-theme (format nil "~A/~A" light dark)
   :theme-names (list light dark "solarized")))

(defparameter +settings-auto-theme-fixtures+
  (list
   (make-settings-auto-theme-fixture "solarized" "dark")
   (make-settings-auto-theme-fixture "dark" "dark")
   (make-settings-auto-theme-fixture "light" "dark")))

(defun run-cli-selectors-settings-automatic-theme-setting ()
  (mapcar #'cadr-cli::settings-selector-automatic-theme-setting
          +settings-auto-theme-fixtures+))

(defun make-settings-active-auto-theme-fixture (light dark terminal-theme)
  (cadr-cli::make-settings-selector-state
   :current-theme (format nil "~A/~A" light dark)
   :theme-names (list light dark "solarized")
   :terminal-theme terminal-theme))

(defparameter +settings-active-auto-theme-fixtures+
  (list
   (make-settings-active-auto-theme-fixture "solarized" "dark" :light)
   (make-settings-active-auto-theme-fixture "solarized" "dark" :dark)
   (make-settings-active-auto-theme-fixture "light" "dark" :light)))

(defun run-cli-selectors-settings-active-automatic-theme ()
  (mapcar #'cadr-cli::settings-selector-active-automatic-theme
          +settings-active-auto-theme-fixtures+))

(defun settings-cycle-encoded (id values value)
  (let* ((option
           (cadr-cli::make-settings-option
            :id id :label id :description id
            :value value :values values))
         (state
           (cadr-cli::%make-settings-selector-state
            :options (list option)
            :filtered-options (list option)
            :selected 0)))
    (cadr-cli::settings-selector-cycle state)
    (format nil "~A|~A" id (cadr-cli::settings-option-value option))))

(defun run-cli-selectors-settings-cycle ()
  (list
   (settings-cycle-encoded "auto-compact" '("true" "false") "true")
   (settings-cycle-encoded "transport" '("sse" "websocket" "auto") "sse")
   (settings-cycle-encoded "mode" '("a" "b") "b")
   (settings-cycle-encoded "flag" '("true" "false") "bogus")))

(defun settings-apply-filter-encoded (labels query)
  (let* ((options
           (loop for label in labels
                 collect
                 (cadr-cli::make-settings-option
                  :id label :label label :description label
                  :value label)))
         (state
           (cadr-cli::%make-settings-selector-state
            :options options
            :filtered-options (copy-list options)
            :selected 2
            :query query)))
    (cadr-cli::settings-selector-apply-filter state)
    (format nil "~D|~D"
            (length
             (cadr-cli::settings-selector-visible-options state))
            (cadr-cli::settings-selector-state-selected state))))

(defun run-cli-selectors-settings-apply-filter ()
  (list
   (settings-apply-filter-encoded
    '("auto-compact" "transport" "theme") "")
   (settings-apply-filter-encoded
    '("auto-compact" "transport" "theme") "trans")
   (settings-apply-filter-encoded
    '("auto-compact" "transport" "theme") "zzz")
   (settings-apply-filter-encoded
    '("apple" "application" "banana") "app")))

(defun tree-entry-filtered-encoded (entry filter current-leaf-id)
  (if (cadr-cli::tree-selector-entry-filtered-p
       entry filter current-leaf-id)
      "t"
      ""))

(defun run-cli-selectors-tree-entry-filtered ()
  (list
   (tree-entry-filtered-encoded
    '(:id "u1" :type :message :role :user :text "hello")
    :default "leaf")
   (tree-entry-filtered-encoded
    '(:id "l1" :type :label :label "bookmark")
    :default "leaf")
   (tree-entry-filtered-encoded
    '(:id "u1" :type :message :role :user :text "hello")
    :user-only "leaf")
   (tree-entry-filtered-encoded
    '(:id "t1" :type :message :role :tool-result :text "ok")
    :no-tools "leaf")
   (tree-entry-filtered-encoded
    '(:id "m1" :type :message :role :user :text "hi" :label "pin")
    :labeled-only "leaf")
   (tree-entry-filtered-encoded
    '(:id "l1" :type :label :label "bookmark")
    :all "leaf")))

(defun tree-query-matches-encoded (entry query)
  (if (cadr-cli::tree-selector-query-matches-p entry query)
      "t"
      ""))

(defun run-cli-selectors-tree-query-matches ()
  (let ((entry
          '(:label "alpha" :role :user :text "hello world")))
    (list
     (tree-query-matches-encoded entry "hello")
     (tree-query-matches-encoded entry "nope")
     (tree-query-matches-encoded entry "hello world")
     (tree-query-matches-encoded entry "hello beta")
     (tree-query-matches-encoded entry ""))))

(defun run-cli-selectors-tree-entry-search-text ()
  (list
   (cadr-cli::tree-selector-entry-search-text
    '(:label "alpha" :text "beta"))
   (cadr-cli::tree-selector-entry-search-text
    '(:label "solo"))
   (cadr-cli::tree-selector-entry-search-text nil)
   (cadr-cli::tree-selector-entry-search-text
    '(:label "L" :text "T" :summary "S" :name "N"
      :model-id "M" :thinking-level "H" :custom-type "C"))
   (cadr-cli::tree-selector-entry-search-text
    '(:text "only"))))

(defun tree-settings-entry-p-encoded (entry)
  (if (cadr-cli::tree-selector-settings-entry-p entry)
      "t"
      ""))

(defun run-cli-selectors-tree-settings-entry-p ()
  (list
   (tree-settings-entry-p-encoded '(:type :label :label "pin"))
   (tree-settings-entry-p-encoded
    '(:type :message :role :user :text "hello"))
   (tree-settings-entry-p-encoded '(:type :custom :custom-type "x"))
   (tree-settings-entry-p-encoded '(:type :model-change :model-id "m"))
   (tree-settings-entry-p-encoded
    '(:type :thinking-level-change :thinking-level "high"))
   (tree-settings-entry-p-encoded '(:type :session-info))))

(defun run-cli-selectors-tree-normalize-display-text ()
  (list
   (cadr-cli::tree-selector-normalize-display-text "hello")
   (cadr-cli::tree-selector-normalize-display-text "  spaced  ")
   (cadr-cli::tree-selector-normalize-display-text
    (format nil "~Cfoo~Cbar~C" #\Newline #\Tab #\Newline))
   (cadr-cli::tree-selector-normalize-display-text nil)
   (cadr-cli::tree-selector-normalize-display-text
    (format nil "   ~C~C  " #\Tab #\Newline))))

(defun run-cli-selectors-tree-status-labels ()
  (flet ((status-labels (filter show-label-timestamps-p)
           (cadr-cli::tree-selector-status-labels
            (cadr-cli::%make-tree-selector-state
             :filter filter
             :show-label-timestamps-p
             show-label-timestamps-p))))
    (list
     (status-labels :default nil)
     (status-labels :no-tools nil)
     (status-labels :user-only nil)
     (status-labels :labeled-only nil)
     (status-labels :all nil)
     (status-labels :default t)
     (status-labels :no-tools t))))

(defun run-cli-selectors-tree-shorten-path ()
  (let ((home
          (string-right-trim
           "/" (or (uiop:getenv "HOME") ""))))
    (list
     (cadr-cli::tree-selector-shorten-path home)
     (cadr-cli::tree-selector-shorten-path
      (concatenate 'string home "/land/session.jsonl"))
     (cadr-cli::tree-selector-shorten-path
      "/tmp/session.jsonl")
     (cadr-cli::tree-selector-shorten-path
      (concatenate 'string home "/projects/pi-mono/README.md"))
     (cadr-cli::tree-selector-shorten-path ""))))

(defun tree-foldable-state-with-maps (children-alist parent-alist)
  (let ((state (cadr-cli::%make-tree-selector-state)))
    (dolist (pair children-alist)
      (setf (gethash (car pair)
                     (cadr-cli::tree-selector-state-visible-children state))
            (cdr pair)))
    (dolist (pair parent-alist)
      (setf (gethash (car pair)
                     (cadr-cli::tree-selector-state-visible-parent state))
            (cdr pair)))
    state))

(defun tree-foldable-p-encoded (state id)
  (if (cadr-cli::tree-selector-foldable-p state id)
      "t"
      ""))

(defun run-cli-selectors-tree-foldable-p ()
  (list
   (tree-foldable-p-encoded
    (tree-foldable-state-with-maps
     '(("r" . ("a")))
     '(("a" . "r")))
    "r")
   (tree-foldable-p-encoded
    (tree-foldable-state-with-maps nil nil)
    "x")
   (tree-foldable-p-encoded
    (tree-foldable-state-with-maps
     '(("r" . ("p")) ("p" . ("c")))
     '(("p" . "r") ("c" . "p")))
    "p")
   (tree-foldable-p-encoded
    (tree-foldable-state-with-maps
     '(("p" . ("a" "b")) ("a" . ("x")))
     '(("a" . "p") ("b" . "p") ("x" . "a")))
    "a")))

(defun run-cli-selectors-tree-tool-argument ()
  (list
   (cadr-cli::tree-selector-tool-argument
    (json-object "path" "/tmp/foo") "path" "file_path")
   (cadr-cli::tree-selector-tool-argument
    (json-object "file_path" "/tmp/bar") "path" "file_path")
   (cadr-cli::tree-selector-tool-argument
    (json-object "path" "/prio" "file_path" "/alt")
    "path" "file_path")
   (cadr-cli::tree-selector-tool-argument
    (json-object "offset" 5) "path" "file_path")
   (cadr-cli::tree-selector-tool-argument
    nil "path" "file_path")))

(defun tree-filter-keyword (name)
  (cond
    ((string= name "default") :default)
    ((string= name "no-tools") :no-tools)
    ((string= name "user-only") :user-only)
    ((string= name "labeled-only") :labeled-only)
    ((string= name "all") :all)
    (t :default)))

(defun tree-filter-name (filter)
  (ecase filter
    (:default "default")
    (:no-tools "no-tools")
    (:user-only "user-only")
    (:labeled-only "labeled-only")
    (:all "all")))

(defun tree-cycle-filter-encoded (start direction)
  (let ((state
          (cadr-cli::%make-tree-selector-state
           :entries '() :ordered-entries '()
           :filter (tree-filter-keyword start))))
    (cadr-cli::tree-selector-cycle-filter state direction)
    (tree-filter-name
     (cadr-cli::tree-selector-state-filter state))))

(defun run-cli-selectors-tree-cycle-filter ()
  (list
   (tree-cycle-filter-encoded "default" 1)
   (tree-cycle-filter-encoded "no-tools" -1)
   (tree-cycle-filter-encoded "all" 1)
   (tree-cycle-filter-encoded "user-only" 1)))

(defparameter *tree-format-label-timestamp-now*
  (encode-universal-time 0 0 15 2 8 2026 0))

(defparameter *tree-format-label-timestamp-display-tz* 0)

(defparameter *tree-format-label-timestamp-inputs*
  '("2026-08-02T09:07:11.000Z"
    "2026-03-28T14:32:00.000Z"
    "2025-12-31T23:59:00.000Z"
    "2026-08-02T10:00:00+02:30"
    "not-a-date"))

(defun run-cli-selectors-tree-format-label-timestamp ()
  (let* ((tz (uiop:getenv "TZ"))
         (now *tree-format-label-timestamp-now*))
    (setf (uiop:getenv "TZ") "UTC")
    (unwind-protect
         (mapcar
          (lambda (input)
            (cadr-cli::tree-selector-format-label-timestamp
             input now *tree-format-label-timestamp-display-tz*))
          *tree-format-label-timestamp-inputs*)
      (if tz
          (setf (uiop:getenv "TZ") tz)
          (sb-posix:unsetenv "TZ")))))

(defparameter *tree-iso-timestamp-fixtures*
  (list
   (cons :tis_afternoon
         (encode-universal-time 0 0 15 2 8 2026 0))
   (cons :tis_epoch
         (encode-universal-time 0 0 0 1 1 1970 0))
   (cons :tis_eoy
         (encode-universal-time 59 59 23 31 12 2025 0))
   (cons :tis_midnight
         (encode-universal-time 0 0 0 1 6 2024 0))
   (cons :tis_noon
         (encode-universal-time 0 0 12 15 3 2023 0))))

(defun run-cli-selectors-tree-iso-timestamp ()
  (let ((tz (uiop:getenv "TZ")))
    (setf (uiop:getenv "TZ") "UTC")
    (unwind-protect
         (mapcar
          (lambda (fixture)
            (cadr-cli::tree-selector-iso-timestamp
             (cdr fixture)))
          *tree-iso-timestamp-fixtures*)
      (if tz
          (setf (uiop:getenv "TZ") tz)
          (sb-posix:unsetenv "TZ")))))

(defun run-cli-selectors-tree-format-tool-call ()
  (let ((long-bash
          (make-string 55 :initial-element #\a)))
    (list
     (cadr-cli::tree-selector-format-tool-call
      "read" (json-object "path" "/tmp/foo"))
     (cadr-cli::tree-selector-format-tool-call
      "read"
      (json-object "path" "/tmp/foo" "offset" 10 "limit" 5))
     (cadr-cli::tree-selector-format-tool-call
      "read" (json-object "path" "/tmp/foo" "offset" 3))
     (cadr-cli::tree-selector-format-tool-call
      "write" (json-object "path" "/tmp/out"))
     (cadr-cli::tree-selector-format-tool-call
      "edit" (json-object "file_path" "/tmp/edit"))
     (cadr-cli::tree-selector-format-tool-call
      "bash" (json-object "command" "echo hi"))
     (cadr-cli::tree-selector-format-tool-call
      "bash" (json-object "command" long-bash))
     (cadr-cli::tree-selector-format-tool-call
      "grep"
      (json-object "pattern" "needle" "path" "/tmp"))
     (cadr-cli::tree-selector-format-tool-call
      "find"
      (json-object "pattern" "*.ts" "path" "/src"))
     (cadr-cli::tree-selector-format-tool-call
      "ls" (json-object "path" "/var"))
     (cadr-cli::tree-selector-format-tool-call
      "mytool" (json-object "alpha" 1 "beta" "two")))))

(defun run-cli-selectors-tree-entry-display-text ()
  (list
   (cadr-cli::tree-selector-entry-display-text
    '(:type :message :role :user :text "hello") nil)
   (cadr-cli::tree-selector-entry-display-text
    '(:type :message :role :assistant :text "reply text") nil)
   (cadr-cli::tree-selector-entry-display-text
    '(:type :message :role :assistant :text "") nil)
   (cadr-cli::tree-selector-entry-display-text
    '(:type :message :role :assistant :stop-reason :aborted :text "") nil)
   (cadr-cli::tree-selector-entry-display-text
    '(:type :message :role :bash-execution :text "echo hi") nil)
   (cadr-cli::tree-selector-entry-display-text
    '(:type :compaction :tokens-before 42000) nil)
   (cadr-cli::tree-selector-entry-display-text
    '(:type :branch-summary :text "summary text") nil)
   (cadr-cli::tree-selector-entry-display-text
    '(:type :label :entry-label "bookmark") nil)
   (cadr-cli::tree-selector-entry-display-text
    '(:type :message :role :tool-result
      :tool-call-name "read"
      :tool-call-arguments (json-object "path" "/tmp/foo")) nil)
   (cadr-cli::tree-selector-entry-display-text
    '(:type :custom-message :custom-type "note" :text "body") nil)
   (cadr-cli::tree-selector-entry-display-text
    '(:type :message :role :user :text "selected") t)))

(defparameter *tree-prefix-branch-state*
  (tree-foldable-state-with-maps
   '(("p" . ("a" "b")))
   '(("a" . "p") ("b" . "p"))))

(defparameter *tree-prefix-leaf-state*
  (tree-foldable-state-with-maps
   '(("r" . ("a")))
   '(("a" . "r"))))

(defun tree-prefix-visual (&key (indent 1) (show-connector-p t) (last-p nil)
                                 (gutters nil) (virtual-root-child-p nil))
  (list :indent indent
        :show-connector-p show-connector-p
        :last-p last-p
        :gutters gutters
        :virtual-root-child-p virtual-root-child-p))

(defun tree-prefix-encoded (state id visual &optional (multiple-roots-p nil))
  (cadr-cli::tree-selector-prefix state id visual multiple-roots-p))

(defun run-cli-selectors-tree-prefix ()
  (let ((branch *tree-prefix-branch-state*)
        (leaf *tree-prefix-leaf-state*)
        (folded (let ((state (cadr-cli::%make-tree-selector-state)))
                  (setf (gethash "p"
                                 (cadr-cli::tree-selector-state-visible-children
                                  state))
                        '("a" "b"))
                  (setf (gethash "a"
                                 (cadr-cli::tree-selector-state-visible-parent
                                  state))
                        "p")
                  (setf (gethash "b"
                                 (cadr-cli::tree-selector-state-visible-parent
                                  state))
                        "p")
                  (setf (gethash "p"
                                 (cadr-cli::tree-selector-state-folded state))
                        t)
                  state)))
    (list
     (tree-prefix-encoded
      leaf "a"
      (tree-prefix-visual :indent 1 :last-p nil))
     (tree-prefix-encoded
      leaf "a"
      (tree-prefix-visual :indent 1 :last-p t))
     (tree-prefix-encoded
      branch "p"
      (tree-prefix-visual :indent 1 :last-p nil))
     (tree-prefix-encoded
      folded "p"
      (tree-prefix-visual :indent 1 :last-p nil))
     (tree-prefix-encoded
      branch "p"
      (tree-prefix-visual
       :indent 2 :last-p t
       :gutters '((0 . t))))
     (tree-prefix-encoded
      leaf "a"
      (tree-prefix-visual
       :indent 2 :last-p nil
       :gutters '((0 . nil))))
     (tree-prefix-encoded
      leaf "a"
      (tree-prefix-visual
       :indent 1 :show-connector-p nil
       :virtual-root-child-p t)
      t))))

(defun tree-gutters-encoded (gutters)
  (if (null gutters)
      ""
    (format nil "~{~a:~a~^,~}"
            (loop for g in (sort (copy-list gutters) #'< :key #'car)
                  append (list (car g) (if (cdr g) "1" "0"))))))

(defun tree-visual-node-encoded (visual)
  (format nil "~a,~a,~a,~a,~a"
          (getf visual :indent)
          (if (getf visual :show-connector-p) "1" "0")
          (if (getf visual :last-p) "1" "0")
          (tree-gutters-encoded (getf visual :gutters))
          (if (getf visual :virtual-root-child-p) "1" "0")))

(defun tree-visual-nodes-encoded (state)
  (multiple-value-bind (visuals multiple-roots-p)
      (cadr-cli::tree-selector-visual-nodes state)
    (let ((ids (sort (loop for k being the hash-keys of visuals collect k)
                     #'string<))
          (parts nil))
      (dolist (id ids)
        (push (format nil "~a=~a" id
                      (tree-visual-node-encoded (gethash id visuals)))
              parts))
      (concatenate 'string
                   (if multiple-roots-p "1" "0")
                   "|"
                   (format nil "~{~a~^;~}" (reverse parts))))))

(defun tree-visual-state-with-children (children-alist)
  (let ((state (cadr-cli::%make-tree-selector-state)))
    (dolist (pair children-alist)
      (setf (gethash (car pair)
                     (cadr-cli::tree-selector-state-visible-children
                      state))
            (cdr pair)))
    state))

(defun run-cli-selectors-tree-visual-nodes ()
  (list
   (tree-visual-nodes-encoded
    (tree-visual-state-with-children
     '((nil . ("r")) ("r" . ("a")))))
   (tree-visual-nodes-encoded
    (tree-visual-state-with-children
     '((nil . ("p")) ("p" . ("a" "b")))))
   (tree-visual-nodes-encoded
    (tree-visual-state-with-children
     '((nil . ("a" "b")))))
   (tree-visual-nodes-encoded
    (tree-visual-state-with-children
     '((nil . ("a")) ("a" . ("b")) ("b" . ("c")))))
   (tree-visual-nodes-encoded
    (tree-visual-state-with-children
     '((nil . ("r")) ("r" . ("p")) ("p" . ("a" "b")))))))

(defun tree-horizontal-viewport-row
    (&key gutter body anchor-column body-width selected-p)
  (list :gutter gutter :body body :anchor-column anchor-column
        :body-width body-width :selected-p selected-p))

(defun tree-horizontal-viewport-encoded (rows width)
  (format nil "~{~a~^|~}"
          (cadr-cli::tree-selector-horizontal-viewport rows width)))

(defun run-cli-selectors-tree-horizontal-viewport ()
  (let ((long-body (make-string 50 :initial-element #\x))
        (ansi-body
          (concatenate 'string #.(format nil "~C[31m" #\Escape)
                       "red text padding"
                       #.(format nil "~C[0m" #\Escape)
                       (make-string 30 :initial-element #\y))))
    (list
     (tree-horizontal-viewport-encoded
      (list (tree-horizontal-viewport-row
             :gutter "> " :body "hello" :anchor-column 2
             :body-width 5 :selected-p nil)
            (tree-horizontal-viewport-row
             :gutter "  " :body "world" :anchor-column 2
             :body-width 5 :selected-p t))
      40)
     (tree-horizontal-viewport-encoded
      (list (tree-horizontal-viewport-row
             :gutter "> " :body long-body :anchor-column 25
             :body-width 50 :selected-p t))
      30)
     (tree-horizontal-viewport-encoded
      (list (tree-horizontal-viewport-row
             :gutter "> " :body "hello world text"
             :anchor-column 2 :body-width 16 :selected-p t))
      12)
     (tree-horizontal-viewport-encoded
      (list (tree-horizontal-viewport-row
             :gutter "> " :body long-body :anchor-column 2
             :body-width 50 :selected-p nil))
      30)
     (tree-horizontal-viewport-encoded
      (list (tree-horizontal-viewport-row
             :gutter "> " :body ansi-body :anchor-column 25
             :body-width 50 :selected-p t))
      30))))

(defun tree-help-state (&optional user-bindings)
  (cadr-cli::%make-tree-selector-state
   :keybindings
   (cadr-cli::make-tree-selector-keybindings user-bindings)))

(defun run-cli-selectors-tree-help-keys ()
  (let ((default (tree-help-state))
        (custom
          (tree-help-state
           '(("tui.select.up" . "ctrl+k")))))
    (list
     (cadr-cli::tree-selector-help-keys
      default '("tui.select.up" "tui.select.down"))
     (cadr-cli::tree-selector-help-keys
      default '("tui.editor.cursorLeft" "tui.editor.cursorRight"))
     (cadr-cli::tree-selector-help-keys
      default '("app.tree.foldOrUp" "app.tree.unfoldOrDown"))
     (cadr-cli::tree-selector-help-keys
      default '("app.message.copy"))
     (cadr-cli::tree-selector-help-keys
      default '("app.tree.filter.default"
                "app.tree.filter.noTools"
                "app.tree.filter.userOnly"
                "app.tree.filter.labeledOnly"
                "app.tree.filter.all"))
     (cadr-cli::tree-selector-help-keys
      default '("app.tree.filter.cycleForward"
                "app.tree.filter.cycleBackward"))
     (cadr-cli::tree-selector-help-keys
      custom '("tui.select.up" "tui.select.down")))))

(defun tree-help-key-encoded (state name)
  (or (cadr-cli::tree-selector-help-key state name) "null"))

(defun run-cli-selectors-tree-help-key ()
  (let ((default (tree-help-state))
        (custom
          (tree-help-state
           '(("tui.select.up" . "ctrl+k")))))
    (list
     (tree-help-key-encoded default "tui.select.up")
     (tree-help-key-encoded default "app.tree.foldOrUp")
     (tree-help-key-encoded default "app.tree.filter.all")
     (tree-help-key-encoded default "tui.editor.cursorLeft")
     (tree-help-key-encoded custom "tui.select.up")
     (tree-help-key-encoded default "unknown.binding"))))

(defun tree-app-key-p-encoded (state data name)
  (if (cadr-cli::tree-selector-app-key-p state data name)
      "true"
    "false"))

(defun run-cli-selectors-tree-app-key-p ()
  (let ((state (tree-help-state)))
    (list
     (tree-app-key-p-encoded
      state (tree-raw-input-key-data state "app.message.copy")
      "app.message.copy")
     (tree-app-key-p-encoded
      state (tree-raw-input-key-data state "app.message.copy")
      "app.tree.foldOrUp")
     (tree-app-key-p-encoded
      state (tree-raw-input-key-data state "tui.select.up")
      "tui.select.up")
     (tree-app-key-p-encoded
      state (tree-raw-input-key-data state "app.tree.filter.all")
      "app.tree.filter.all")
     (tree-app-key-p-encoded
      state (csi-modified-arrow 1 #\A) "tui.select.up")
     (tree-app-key-p-encoded state "x" "app.message.copy"))))

(defun tree-help-lines-encoded (state width)
  (format nil "~{~a~^|~}"
          (cadr-cli::tree-selector-help-lines state width)))

(defun run-cli-selectors-tree-help-lines ()
  (let ((state (tree-help-state)))
    (list
     (tree-help-lines-encoded state 80)
     (tree-help-lines-encoded state 50)
     (tree-help-lines-encoded state 30)
     (tree-help-lines-encoded state 20)
     (tree-help-lines-encoded state 12))))

(defparameter *tree-active-path-branching-entries*
  '((:id "user-1" :parent-id nil
     :type :message :role :user
     :text "first message")
    (:id "asst-1" :parent-id "user-1"
     :type :message :role :assistant
     :text "response 1")
    (:id "user-2" :parent-id "asst-1"
     :type :message :role :user
     :text "second message")
    (:id "asst-2" :parent-id "user-2"
     :type :message :role :assistant
     :text "response 2")
    (:id "user-3a" :parent-id "asst-2"
     :type :message :role :user
     :text "branch A start")
    (:id "asst-3a" :parent-id "user-3a"
     :type :message :role :assistant
     :text "branch A response")
    (:id "user-4a" :parent-id "asst-3a"
     :type :message :role :user
     :text "branch A deep")
    (:id "asst-4a" :parent-id "user-4a"
     :type :message :role :assistant
     :text "branch A leaf")
    (:id "user-3b" :parent-id "asst-2"
     :type :message :role :user
     :text "branch B start")
    (:id "asst-3b" :parent-id "user-3b"
     :type :message :role :assistant
     :text "branch B response")
    (:id "user-4b" :parent-id "asst-3b"
     :type :message :role :user
     :text "branch B deep")))

(defun tree-entry-map-encoded (entries)
  (let ((entry-map (cadr-cli::tree-selector-entry-map entries)))
    (format nil "~{~a~^;~}"
            (sort
             (mapcar
              (lambda (id)
                (let ((entry (gethash id entry-map)))
                  (format nil "~a|~a|~a"
                          id
                          (string-downcase
                           (symbol-name (getf entry :type)))
                          (or (getf entry :parent-id) "null"))))
              (loop for id being the hash-keys of entry-map
                    collect id))
             #'string<))))

(defun run-cli-selectors-tree-entry-map ()
  (list
   (tree-entry-map-encoded
    *tree-active-path-branching-entries*)
   (tree-entry-map-encoded
    *tree-apply-filter-entries*)
   (tree-entry-map-encoded '())
   (tree-entry-map-encoded
    '((:id "solo" :parent-id nil
       :type :message :role :user
       :text "only")))
   (tree-entry-map-encoded
    (list (first *tree-apply-filter-entries*)))))

(defun tree-active-path-encoded (entries leaf-id)
  (format nil "~{~a~^,~}"
          (sort
           (loop for id being the hash-keys
                 of (cadr-cli::tree-selector-active-path
                     entries leaf-id)
                 collect id)
           #'string<)))

(defun run-cli-selectors-tree-active-path ()
  (let ((entries *tree-active-path-branching-entries*))
    (list
     (tree-active-path-encoded entries "asst-4a")
     (tree-active-path-encoded entries "user-2")
     (tree-active-path-encoded entries "user-1")
     (tree-active-path-encoded entries nil)
     (tree-active-path-encoded entries "missing"))))

(defun tree-nearest-visible-state (visible-ids)
  (let ((state
          (cadr-cli::%make-tree-selector-state
           :entries *tree-active-path-branching-entries*)))
    (setf (cadr-cli::tree-selector-state-visible-ids state)
          visible-ids)
    state))

(defun tree-visible-set (visible-ids)
  (let ((result (make-hash-table :test #'equal)))
    (dolist (id visible-ids)
      (setf (gethash id result) t))
    result))

(defun tree-nearest-visible-id-encoded (visible-ids target)
  (let ((state (tree-nearest-visible-state visible-ids)))
    (cadr-cli::tree-selector-nearest-visible-id
     state target
     (tree-visible-set visible-ids))))

(defun run-cli-selectors-tree-nearest-visible-id ()
  (list
   (tree-nearest-visible-id-encoded '("asst-4a") "asst-4a")
   (tree-nearest-visible-id-encoded '("user-1" "user-4a") "asst-4a")
   (tree-nearest-visible-id-encoded '("user-1" "asst-1") "asst-4a")
   (tree-nearest-visible-id-encoded '("user-3b") "asst-4a")
   (tree-nearest-visible-id-encoded '("user-3b") "missing")
   (tree-nearest-visible-id-encoded '("user-3b") nil)))

(defun tree-prioritize-active-encoded (entries leaf-id)
  (format nil "~{~a~^,~}"
          (mapcar
           (lambda (entry)
             (getf entry :id))
           (cadr-cli::tree-selector-prioritize-active
            entries
            (cadr-cli::tree-selector-active-path
             entries leaf-id)))))

(defun run-cli-selectors-tree-prioritize-active ()
  (let ((entries *tree-active-path-branching-entries*))
    (list
     (tree-prioritize-active-encoded entries "asst-4a")
     (tree-prioritize-active-encoded entries "user-4b")
     (tree-prioritize-active-encoded entries "user-1")
     (tree-prioritize-active-encoded entries nil))))

(defun tree-order-entries-encoded (entries leaf-id)
  (format nil "~{~a~^,~}"
          (mapcar
           (lambda (entry)
             (getf entry :id))
           (cadr-cli::tree-selector-order-entries
            entries leaf-id))))

(defun run-cli-selectors-tree-order-entries ()
  (list
   (tree-order-entries-encoded
    *tree-active-path-branching-entries* "asst-4a")
   (tree-order-entries-encoded
    *tree-active-path-branching-entries* "user-4b")
   (tree-order-entries-encoded
    *tree-active-path-branching-entries* "user-1")
   (tree-order-entries-encoded
    *tree-active-path-branching-entries* nil)
   (tree-order-entries-encoded
    *tree-apply-filter-entries* "user-3")))

(defun tree-visible-entries-by-ids (ids)
  (remove-if-not
   (lambda (entry)
     (member (getf entry :id) ids :test #'string=))
   *tree-active-path-branching-entries*))

(defun tree-parent-map-encoded (parent-map entry-ids)
  (format nil "~{~a~^;~}"
          (sort
           (mapcar
            (lambda (id)
              (format nil "~a=~a" id
                      (or (gethash id parent-map) "null")))
            entry-ids)
           #'string<)))

(defun tree-children-key (parent-id)
  (or parent-id "null"))

(defun tree-children-map-encoded (children-map parent-keys entry-ids)
  (declare (ignore entry-ids))
  (format nil "~{~a~^;~}"
          (sort
           (mapcar
            (lambda (parent-id)
              (format nil "~a=~{~a~^,~}"
                      (tree-children-key parent-id)
                      (gethash parent-id children-map)))
            parent-keys)
           #'string<)))

(defun tree-rebuild-visible-maps-encoded (visible-ids)
  (let* ((visible-entries
           (tree-visible-entries-by-ids visible-ids))
         (state
           (cadr-cli::%make-tree-selector-state
            :entries *tree-active-path-branching-entries*)))
    (cadr-cli::tree-selector-rebuild-visible-maps
     state visible-entries)
    (let* ((parent-map
             (cadr-cli::tree-selector-state-visible-parent
              state))
           (children-map
             (cadr-cli::tree-selector-state-visible-children
              state))
           (parent-keys nil))
      (maphash
       (lambda (parent children)
         (declare (ignore children))
         (push parent parent-keys))
       children-map)
      (format nil "~a|~a"
              (tree-parent-map-encoded parent-map visible-ids)
              (tree-children-map-encoded
               children-map parent-keys visible-ids)))))

(defun run-cli-selectors-tree-rebuild-visible-maps ()
  (list
   (tree-rebuild-visible-maps-encoded
    '("user-1" "asst-1" "user-2" "asst-2" "user-3a"
      "asst-3a" "user-4a" "asst-4a" "user-3b" "asst-3b"
      "user-4b"))
   (tree-rebuild-visible-maps-encoded
    '("user-1" "user-3a" "asst-4a"))
   (tree-rebuild-visible-maps-encoded
    '("user-1" "user-2" "user-3b" "asst-3b" "user-4b"))
   (tree-rebuild-visible-maps-encoded '("user-1"))
   (tree-rebuild-visible-maps-encoded
    '("user-1" "user-3a" "user-3b"))))

(defparameter *tree-apply-filter-entries*
  '((:id "user-1" :parent-id nil
     :type :message :role :user
     :text "root message")
    (:id "label-1" :parent-id "user-1"
     :type :label :label "bookmark")
    (:id "asst-1" :parent-id "user-1"
     :type :message :role :assistant
     :text "response")
    (:id "user-2" :parent-id "asst-1"
     :type :message :role :user
     :text "branch query")
    (:id "tool-1" :parent-id "user-2"
     :type :message :role :tool-result
     :text "tool output")
    (:id "user-3" :parent-id "tool-1"
     :type :message :role :user
     :text "leaf text" :label "pinned")
    (:id "asst-empty" :parent-id "user-3"
     :type :message :role :assistant
     :text "")))

(defun tree-apply-filter-encoded
    (&key filter query folded-ids selected-id preserved-id)
  (let* ((entries *tree-apply-filter-entries*)
         (current-leaf-id "user-3")
         (state
           (cadr-cli::%make-tree-selector-state
            :entries entries
            :ordered-entries
            (cadr-cli::tree-selector-order-entries
             entries current-leaf-id)
            :current-leaf-id current-leaf-id
            :filter (tree-filter-keyword filter)
            :selected-id
            (or selected-id current-leaf-id))))
    (setf (cadr-cli::tree-selector-state-query state)
          (or query ""))
    (when preserved-id
      (setf (cadr-cli::tree-selector-state-selected-id state)
            nil
            (cadr-cli::tree-selector-state-preserved-id state)
            preserved-id))
    (when (and selected-id (not preserved-id))
      (setf (cadr-cli::tree-selector-state-selected-id state)
            selected-id
            (cadr-cli::tree-selector-state-preserved-id state)
            nil))
    (dolist (id folded-ids)
      (setf (gethash id
                     (cadr-cli::tree-selector-state-folded
                      state))
            t))
    (cadr-cli::tree-selector-apply-filter state)
    (format nil "~a|~a|~a"
            (format nil "~{~a~^,~}"
                    (cadr-cli::tree-selector-state-visible-ids
                     state))
            (or (cadr-cli::tree-selector-state-selected-id state)
                "null")
            (or (cadr-cli::tree-selector-state-preserved-id state)
                "null"))))

(defun run-cli-selectors-tree-apply-filter ()
  (list
   (tree-apply-filter-encoded :filter "default")
   (tree-apply-filter-encoded :filter "user-only")
   (tree-apply-filter-encoded :filter "no-tools")
   (tree-apply-filter-encoded :filter "default" :query "branch")
   (tree-apply-filter-encoded
    :filter "default" :folded-ids '("user-2"))
   (tree-apply-filter-encoded
    :filter "user-only" :selected-id "tool-1")))

(defun tree-render-state
    (&key entries current-leaf-id selected-id
          max-visible-lines filter folded-ids)
  (let* ((leaf (or current-leaf-id "asst-4a"))
         (state
           (cadr-cli::make-tree-selector-state
            :entries
            (or entries *tree-active-path-branching-entries*)
            :current-leaf-id leaf
            :initial-selected-id
            (or selected-id leaf)
            :filter (tree-filter-keyword (or filter "default"))
            :max-visible-lines (or max-visible-lines 8))))
    (when folded-ids
      (dolist (id folded-ids)
        (setf (gethash id
                       (cadr-cli::tree-selector-state-folded
                        state))
              t))
      (cadr-cli::tree-selector-apply-filter state))
    (when (and selected-id
               (not (equal selected-id
                           (or current-leaf-id "asst-4a"))))
      (cadr-cli::tree-selector-select-id state selected-id))
    state))

(defun tree-render-lines-encoded (state width)
  (format nil "~{~a~^|~}"
          (cadr-cli::tree-selector-render-lines state width)))

(defun run-cli-selectors-tree-render-lines ()
  (list
   (tree-render-lines-encoded
    (tree-render-state) 80)
   (tree-render-lines-encoded
    (tree-render-state :selected-id "user-2") 60)
   (tree-render-lines-encoded
    (tree-render-state) 28)
   (tree-render-lines-encoded
    (tree-render-state :folded-ids '("asst-2")) 70)
   (tree-render-lines-encoded
    (tree-render-state
     :entries '()
     :current-leaf-id nil
     :selected-id nil
     :max-visible-lines 5)
    40)
   (tree-render-lines-encoded
    (tree-render-state :max-visible-lines 5) 50)))

(defun tree-move-encoded (selected-id delta &key empty-p)
  (let ((state
          (if empty-p
              (cadr-cli::make-tree-selector-state
               :entries '()
               :current-leaf-id nil
               :max-visible-lines 5)
              (tree-render-state :selected-id selected-id))))
    (cadr-cli::tree-selector-move state delta)
    (or (cadr-cli::tree-selector-selected-id state)
        "null")))

(defun run-cli-selectors-tree-move ()
  (list
   (tree-move-encoded "user-1" 1)
   (tree-move-encoded "user-2" -1)
   (tree-move-encoded "user-1" -1)
   (tree-move-encoded "asst-4a" 1)
   (tree-move-encoded "user-2" 10)
   (tree-move-encoded "user-2" -10)
   (tree-move-encoded nil 1 :empty-p t)))

(defun tree-fold-or-up-encoded (selected-id &key pre-folded-ids)
  (let ((state (tree-render-state :selected-id selected-id)))
    (when pre-folded-ids
      (dolist (id pre-folded-ids)
        (setf (gethash id
                       (cadr-cli::tree-selector-state-folded
                        state))
              t))
      (cadr-cli::tree-selector-apply-filter state)
      (cadr-cli::tree-selector-select-id state selected-id))
    (cadr-cli::tree-selector-fold-or-up state)
    (format nil "~a|~{~a~^,~}"
            (or (cadr-cli::tree-selector-selected-id state)
                "null")
            (cadr-cli::tree-selector-state-visible-ids
             state))))

(defun run-cli-selectors-tree-fold-or-up ()
  (list
   (tree-fold-or-up-encoded "asst-2")
   (tree-fold-or-up-encoded "asst-4a")
   (tree-fold-or-up-encoded "user-4a")
   (tree-fold-or-up-encoded "user-3a" :pre-folded-ids '("asst-2"))
   (tree-fold-or-up-encoded "user-1")
   (tree-fold-or-up-encoded "user-4b")))

(defun tree-unfold-or-down-encoded (selected-id &key pre-folded-ids)
  (let ((state (tree-render-state :selected-id selected-id)))
    (when pre-folded-ids
      (dolist (id pre-folded-ids)
        (setf (gethash id
                       (cadr-cli::tree-selector-state-folded
                        state))
              t))
      (cadr-cli::tree-selector-apply-filter state)
      (cadr-cli::tree-selector-select-id state selected-id))
    (cadr-cli::tree-selector-unfold-or-down state)
    (format nil "~a|~{~a~^,~}"
            (or (cadr-cli::tree-selector-selected-id state)
                "null")
            (cadr-cli::tree-selector-state-visible-ids
             state))))

(defun run-cli-selectors-tree-unfold-or-down ()
  (list
   (tree-unfold-or-down-encoded "asst-2" :pre-folded-ids '("asst-2"))
   (tree-unfold-or-down-encoded "asst-4a")
   (tree-unfold-or-down-encoded "user-4a")
   (tree-unfold-or-down-encoded "user-3a" :pre-folded-ids '("asst-2"))
   (tree-unfold-or-down-encoded "user-1")
   (tree-unfold-or-down-encoded "user-4b")))

(defun tree-branch-segment-encoded (selected-id direction)
  (let ((state (tree-render-state :selected-id selected-id)))
    (cadr-cli::tree-selector-select-id state selected-id)
    (or (cadr-cli::tree-selector-branch-segment-id state direction)
        "null")))

(defun run-cli-selectors-tree-branch-segment-id ()
  (list
   (tree-branch-segment-encoded "asst-2" :down)
   (tree-branch-segment-encoded "asst-4a" :down)
   (tree-branch-segment-encoded "user-4a" :down)
   (tree-branch-segment-encoded "user-4a" :up)
   (tree-branch-segment-encoded "user-1" :up)
   (tree-branch-segment-encoded "user-4b" :up)))

(defun tree-set-query-encoded (&key query folded-ids selected-id)
  (let* ((entries *tree-apply-filter-entries*)
         (current-leaf-id "user-3")
         (state
           (cadr-cli::%make-tree-selector-state
            :entries entries
            :ordered-entries
            (cadr-cli::tree-selector-order-entries
             entries current-leaf-id)
            :current-leaf-id current-leaf-id
            :filter :default
            :selected-id
            (or selected-id current-leaf-id))))
    (dolist (id folded-ids)
      (setf (gethash id
                     (cadr-cli::tree-selector-state-folded
                      state))
            t))
    (when folded-ids
      (cadr-cli::tree-selector-apply-filter state))
    (when selected-id
      (cadr-cli::tree-selector-select-id state selected-id))
    (cadr-cli::tree-selector-set-query state (or query ""))
    (format nil "~a|~a|~a"
            (format nil "~{~a~^,~}"
                    (cadr-cli::tree-selector-state-visible-ids
                     state))
            (or (cadr-cli::tree-selector-state-selected-id state)
                "null")
            (or (cadr-cli::tree-selector-state-preserved-id state)
                "null"))))

(defun run-cli-selectors-tree-set-query ()
  (list
   (tree-set-query-encoded :query "")
   (tree-set-query-encoded :query "branch")
   (tree-set-query-encoded
    :query "branch" :folded-ids '("user-2"))
   (tree-set-query-encoded :query "zzzzz")
   (tree-set-query-encoded :query "pinned")
   (tree-set-query-encoded :query "branch query")))

(defun tree-set-filter-encoded (&key filter folded-ids selected-id)
  (let* ((entries *tree-apply-filter-entries*)
         (current-leaf-id "user-3")
         (state
           (cadr-cli::%make-tree-selector-state
            :entries entries
            :ordered-entries
            (cadr-cli::tree-selector-order-entries
             entries current-leaf-id)
            :current-leaf-id current-leaf-id
            :filter :default
            :selected-id
            (or selected-id current-leaf-id))))
    (dolist (id folded-ids)
      (setf (gethash id
                     (cadr-cli::tree-selector-state-folded
                      state))
            t))
    (when folded-ids
      (cadr-cli::tree-selector-apply-filter state))
    (when selected-id
      (cadr-cli::tree-selector-select-id state selected-id))
    (cadr-cli::tree-selector-set-filter
     state (tree-filter-keyword filter))
    (format nil "~a|~a|~a"
            (format nil "~{~a~^,~}"
                    (cadr-cli::tree-selector-state-visible-ids
                     state))
            (or (cadr-cli::tree-selector-state-selected-id state)
                "null")
            (or (cadr-cli::tree-selector-state-preserved-id state)
                "null"))))

(defun run-cli-selectors-tree-set-filter ()
  (list
   (tree-set-filter-encoded :filter "default")
   (tree-set-filter-encoded :filter "user-only")
   (tree-set-filter-encoded :filter "no-tools")
   (tree-set-filter-encoded
    :filter "user-only" :folded-ids '("user-2"))
   (tree-set-filter-encoded :filter "labeled-only")
   (tree-set-filter-encoded
    :filter "user-only" :selected-id "tool-1")))

(defun tree-copy-selected-encoded (selected-id &key empty-p)
  (let ((copied nil)
        (entries (if empty-p '() *tree-apply-filter-entries*))
        (current-leaf-id (if empty-p nil "user-3")))
    (let ((state
            (if empty-p
                (cadr-cli::%make-tree-selector-state
                 :entries '() :ordered-entries '()
                 :copy-callback
                 (lambda (text)
                   (setf copied text)))
                (cadr-cli::make-tree-selector-state
                 :entries entries
                 :current-leaf-id current-leaf-id
                 :initial-selected-id
                 (or selected-id current-leaf-id)
                 :copy-callback
                 (lambda (text)
                   (setf copied text))))))
      (when (and selected-id (not empty-p))
        (cadr-cli::tree-selector-select-id state selected-id))
      (when empty-p
        (setf (cadr-cli::tree-selector-state-selected-id state)
              nil))
      (cadr-cli::tree-selector-copy-selected state)
      (if copied copied "null"))))

(defun run-cli-selectors-tree-copy-selected ()
  (list
   (tree-copy-selected-encoded "user-1")
   (tree-copy-selected-encoded "asst-1")
   (tree-copy-selected-encoded "tool-1")
   (tree-copy-selected-encoded "asst-empty")
   (tree-copy-selected-encoded "label-1")
   (tree-copy-selected-encoded nil :empty-p t)))

(defun tree-toggle-label-timestamps-encoded (&key toggles filter)
  (let ((state
          (cadr-cli::%make-tree-selector-state
           :filter (tree-filter-keyword (or filter "default")))))
    (dotimes (i toggles)
      (cadr-cli::tree-selector-toggle-label-timestamps state))
    (format nil "~a|~a"
            (if (cadr-cli::tree-selector-state-show-label-timestamps-p
                 state)
                "true"
                "false")
            (cadr-cli::tree-selector-status-labels state))))

(defun run-cli-selectors-tree-toggle-label-timestamps ()
  (list
   (tree-toggle-label-timestamps-encoded :toggles 0)
   (tree-toggle-label-timestamps-encoded :toggles 1)
   (tree-toggle-label-timestamps-encoded :toggles 2)
   (tree-toggle-label-timestamps-encoded
    :toggles 1 :filter "no-tools")
   (tree-toggle-label-timestamps-encoded
    :toggles 1 :filter "labeled-only")
   (tree-toggle-label-timestamps-encoded :toggles 3)))

(defun tree-start-label-edit-encoded (selected-id &key empty-p no-select-p)
  (let* ((entries (if empty-p '() *tree-apply-filter-entries*))
         (current-leaf-id (if empty-p nil "user-3"))
         (state
           (if empty-p
               (cadr-cli::%make-tree-selector-state
                :entries '() :ordered-entries '())
               (cadr-cli::make-tree-selector-state
                :entries entries
                :current-leaf-id current-leaf-id
                :initial-selected-id
                (or selected-id current-leaf-id)))))
    (when no-select-p
      (setf (cadr-cli::tree-selector-state-selected-id state)
            nil))
    (when (and selected-id (not empty-p) (not no-select-p))
      (cadr-cli::tree-selector-select-id state selected-id))
    (cadr-cli::tree-selector-start-label-edit state)
    (format nil "~a|~a|~a"
            (case (cadr-cli::tree-selector-state-mode state)
              (:label "label")
              (otherwise "list"))
            (or (cadr-cli::tree-selector-state-label-edit-id state)
                "null")
            (cadr-cli::tree-selector-state-label-input state))))

(defun run-cli-selectors-tree-start-label-edit ()
  (list
   (tree-start-label-edit-encoded "user-3")
   (tree-start-label-edit-encoded "user-1")
   (tree-start-label-edit-encoded "asst-1")
   (tree-start-label-edit-encoded "label-1")
   (tree-start-label-edit-encoded nil :empty-p t)
   (tree-start-label-edit-encoded nil :no-select-p t)))

(defun tree-confirm-label-encoded (selected-id input &key nop)
  (let* ((entries *tree-apply-filter-entries*)
         (current-leaf-id "user-3")
         (callback-id nil)
         (callback-label nil)
         (state
           (cadr-cli::make-tree-selector-state
            :entries entries
            :current-leaf-id current-leaf-id
            :initial-selected-id selected-id
            :label-callback
            (lambda (id label)
              (setf callback-id id)
              (setf callback-label label)))))
    (unless nop
      (cadr-cli::tree-selector-select-id state selected-id)
      (cadr-cli::tree-selector-start-label-edit state)
      (setf (cadr-cli::tree-selector-state-label-input state)
            input))
    (cadr-cli::tree-selector-confirm-label state)
    (let ((entry
            (find selected-id entries
                  :key (lambda (candidate)
                         (getf candidate :id))
                  :test #'equal)))
      (format nil "~a|~a|~a|~a"
              "list"
              (or callback-id "null")
              (if callback-label callback-label "null")
              (if (and entry (getf entry :label-timestamp))
                  "true"
                  "false")))))

(defun run-cli-selectors-tree-confirm-label ()
  (list
   (tree-confirm-label-encoded "user-1" "newtag")
   (tree-confirm-label-encoded "user-3" "renamed")
   (tree-confirm-label-encoded "user-3" "")
   (tree-confirm-label-encoded "user-1" "  spaced  ")
   (tree-confirm-label-encoded "user-1" "   ")
   (tree-confirm-label-encoded "user-1" "" :nop t)))

(defun tree-cancel-label-encoded (selected-id &key dirty-input nop)
  (let* ((entries *tree-apply-filter-entries*)
         (current-leaf-id "user-3")
         (state
           (cadr-cli::make-tree-selector-state
            :entries entries
            :current-leaf-id current-leaf-id
            :initial-selected-id selected-id)))
    (unless nop
      (cadr-cli::tree-selector-select-id state selected-id)
      (cadr-cli::tree-selector-start-label-edit state)
      (when dirty-input
        (setf (cadr-cli::tree-selector-state-label-input state)
              dirty-input)))
    (cadr-cli::tree-selector-cancel-label state)
    (let ((entry
            (find selected-id entries
                  :key (lambda (candidate)
                         (getf candidate :id))
                  :test #'equal)))
      (format nil "~a|~a|~a"
              "list"
              "null"
              (if (and entry (getf entry :label))
                  (getf entry :label)
                  "null")))))

(defun run-cli-selectors-tree-cancel-label ()
  (list
   (tree-cancel-label-encoded "user-3")
   (tree-cancel-label-encoded "user-1")
   (tree-cancel-label-encoded "asst-1")
   (tree-cancel-label-encoded "label-1")
   (tree-cancel-label-encoded "user-3" :dirty-input "newtag")
   (tree-cancel-label-encoded "user-1" :nop t)))

(defun tree-raw-input-key-data (state key-name)
  (first (cadr-tui:keybinding-keys
          (cadr-cli::tree-selector-state-keybindings state)
          key-name)))

(defun tree-handle-raw-input-encoded-copy (selected-id)
  (let ((copied nil)
        (state
          (cadr-cli::make-tree-selector-state
           :entries *tree-apply-filter-entries*
           :current-leaf-id "user-3"
           :initial-selected-id selected-id
           :copy-callback
           (lambda (text)
             (setf copied text)))))
    (cadr-cli::tree-selector-select-id state selected-id)
    (cadr-cli::tree-selector-handle-raw-input
     state (tree-raw-input-key-data state "app.message.copy"))
    (if copied copied "null")))

(defun tree-handle-raw-input-encoded-edit (selected-id)
  (let ((state
          (cadr-cli::make-tree-selector-state
           :entries *tree-apply-filter-entries*
           :current-leaf-id "user-3"
           :initial-selected-id selected-id)))
    (cadr-cli::tree-selector-select-id state selected-id)
    (cadr-cli::tree-selector-handle-raw-input
     state (tree-raw-input-key-data state "app.tree.editLabel"))
    (format nil "~a|~a|~a"
            (case (cadr-cli::tree-selector-state-mode state)
              (:label "label")
              (otherwise "list"))
            (or (cadr-cli::tree-selector-state-label-edit-id state)
                "null")
            (cadr-cli::tree-selector-state-label-input state))))

(defun tree-handle-raw-input-encoded-fold (selected-id)
  (let ((state (tree-render-state :selected-id selected-id)))
    (cadr-cli::tree-selector-handle-raw-input
     state (tree-raw-input-key-data state "app.tree.foldOrUp"))
    (format nil "~a|~{~a~^,~}"
            (or (cadr-cli::tree-selector-selected-id state)
                "null")
            (cadr-cli::tree-selector-state-visible-ids
             state))))

(defun tree-handle-raw-input-encoded-notools (selected-id)
  (let ((state
          (cadr-cli::make-tree-selector-state
           :entries *tree-apply-filter-entries*
           :current-leaf-id "user-3"
           :initial-selected-id selected-id
           :filter :default)))
    (cadr-cli::tree-selector-select-id state selected-id)
    (cadr-cli::tree-selector-handle-raw-input
     state (tree-raw-input-key-data state "app.tree.filter.noTools"))
    (format nil "~a|~a|~a"
            (format nil "~{~a~^,~}"
                    (cadr-cli::tree-selector-state-visible-ids
                     state))
            (or (cadr-cli::tree-selector-state-selected-id state)
                "null")
            (or (cadr-cli::tree-selector-state-preserved-id state)
                "null"))))

(defun tree-handle-raw-input-encoded-label-cancel (selected-id dirty-input)
  (let ((state
          (cadr-cli::make-tree-selector-state
           :entries *tree-apply-filter-entries*
           :current-leaf-id "user-3"
           :initial-selected-id selected-id)))
    (cadr-cli::tree-selector-select-id state selected-id)
    (cadr-cli::tree-selector-start-label-edit state)
    (setf (cadr-cli::tree-selector-state-label-input state)
          dirty-input)
    (cadr-cli::tree-selector-handle-raw-input
     state (tree-raw-input-key-data state "tui.select.cancel"))
    (let ((entry
            (find selected-id *tree-apply-filter-entries*
                  :key (lambda (candidate)
                         (getf candidate :id))
                  :test #'equal)))
      (format nil "~a|~a|~a"
              "list"
              "null"
              (if (and entry (getf entry :label))
                  (getf entry :label)
                  "null")))))

(defun tree-handle-raw-input-encoded-nop (selected-id)
  (let ((state
          (cadr-cli::make-tree-selector-state
           :entries *tree-apply-filter-entries*
           :current-leaf-id "user-3"
           :initial-selected-id selected-id)))
    (cadr-cli::tree-selector-select-id state selected-id)
    (cadr-cli::tree-selector-handle-raw-input state "q")
    "noop"))

(defun run-cli-selectors-tree-handle-raw-input ()
  (list
   (tree-handle-raw-input-encoded-copy "user-1")
   (tree-handle-raw-input-encoded-edit "user-3")
   (tree-handle-raw-input-encoded-fold "asst-2")
   (tree-handle-raw-input-encoded-notools "user-3")
   (tree-handle-raw-input-encoded-label-cancel "user-3" "newtag")
   (tree-handle-raw-input-encoded-nop "user-1")))

(defun tree-handle-event-encoded (selected-id event-kind &key text query)
  (let ((state
          (cadr-cli::make-tree-selector-state
           :entries *tree-apply-filter-entries*
           :current-leaf-id "user-3"
           :initial-selected-id selected-id)))
    (cadr-cli::tree-selector-select-id state selected-id)
    (when query
      (cadr-cli::tree-selector-set-query state query))
    (let ((event
            (if text
                (cadr-tui:make-input-event
                 :kind event-kind :text text)
                (cadr-tui:make-input-event :kind event-kind))))
      (multiple-value-bind (action value)
          (cadr-cli::tree-selector-handle-event state event)
        (format nil "~a|~a|~a|~a"
                (if action
                    (string-downcase (symbol-name action))
                    "null")
                (or value "null")
                (or (cadr-cli::tree-selector-state-selected-id state)
                    "null")
                (cadr-cli::tree-selector-state-query state))))))

(defun run-cli-selectors-tree-handle-event ()
  (list
   (tree-handle-event-encoded "user-1" :down)
   (tree-handle-event-encoded "user-2" :up)
   (tree-handle-event-encoded "user-3" :enter)
   (tree-handle-event-encoded "user-3" :text :text "pin")
   (tree-handle-event-encoded "user-3" :escape :query "branch")
   (tree-handle-event-encoded "user-1" :tab)))

(defun tree-handle-label-event-encoded (selected-id event-kind &key text initial-input)
  (let* ((entries *tree-apply-filter-entries*)
         (current-leaf-id "user-3")
         (callback-id nil)
         (callback-label nil)
         (state
           (cadr-cli::make-tree-selector-state
            :entries entries
            :current-leaf-id current-leaf-id
            :initial-selected-id selected-id
            :label-callback
            (lambda (id label)
              (setf callback-id id)
              (setf callback-label label)))))
    (cadr-cli::tree-selector-select-id state selected-id)
    (cadr-cli::tree-selector-start-label-edit state)
    (when initial-input
      (setf (cadr-cli::tree-selector-state-label-input state)
            initial-input))
    (let ((event
            (if text
                (cadr-tui:make-input-event
                 :kind event-kind :text text)
                (cadr-tui:make-input-event :kind event-kind))))
      (cadr-cli::tree-selector-handle-label-event state event))
    (if (eq :label (cadr-cli::tree-selector-state-mode state))
        (format nil "label|~a|~a"
                (or (cadr-cli::tree-selector-state-label-edit-id state)
                    "null")
                (cadr-cli::tree-selector-state-label-input state))
        (let ((entry
                (find selected-id entries
                      :key (lambda (candidate)
                             (getf candidate :id))
                      :test #'equal)))
          (if (eq event-kind :escape)
              (format nil "list|null|~a"
                      (if (and entry (getf entry :label))
                          (getf entry :label)
                          "null"))
              (format nil "list|~a|~a|~a"
                      (or callback-id "null")
                      (if callback-label callback-label "null")
                      (if (and entry (getf entry :label-timestamp))
                          "true"
                          "false")))))))

(defun run-cli-selectors-tree-handle-label-event ()
  (list
   (tree-handle-label-event-encoded "user-3" :text :text "x")
   (tree-handle-label-event-encoded "user-3" :backspace
                                    :initial-input "abcd")
   (tree-handle-label-event-encoded "user-3" :enter
                                    :initial-input "newtag")
   (tree-handle-label-event-encoded "user-3" :escape
                                    :initial-input "newtag")
   (tree-handle-label-event-encoded "user-3" :tab)))

(defun tree-selected-entry-encoded (selected-id &key no-select-p)
  (let* ((entries *tree-apply-filter-entries*)
         (current-leaf-id "user-3")
         (state
           (cadr-cli::make-tree-selector-state
            :entries entries
            :current-leaf-id current-leaf-id
            :initial-selected-id
            (unless no-select-p selected-id))))
    (when (and selected-id (not no-select-p))
      (cadr-cli::tree-selector-select-id state selected-id))
    (when no-select-p
      (setf (cadr-cli::tree-selector-state-selected-id state)
            nil))
    (let ((entry (cadr-cli::tree-selector-selected-entry state)))
      (if entry
          (format nil "~a|~a|~a|~a|~a"
                  (getf entry :id)
                  (string-downcase
                   (symbol-name (getf entry :type)))
                  (if (getf entry :role)
                      (string-downcase
                       (symbol-name (getf entry :role)))
                      "null")
                  (if (getf entry :label)
                      (getf entry :label)
                      "null")
                  (if (getf entry :text)
                      (getf entry :text)
                      ""))
          "null|null|null|null|null"))))

(defun run-cli-selectors-tree-selected-entry ()
  (list
   (tree-selected-entry-encoded "user-3")
   (tree-selected-entry-encoded "user-1")
   (tree-selected-entry-encoded "asst-1")
   (tree-selected-entry-encoded "label-1")
   (tree-selected-entry-encoded "asst-empty")
   (tree-selected-entry-encoded nil :no-select-p t)))

(defun tree-selected-id-encoded (selected-id &key no-select-p)
  (let* ((entries *tree-apply-filter-entries*)
         (current-leaf-id "user-3")
         (state
           (cadr-cli::make-tree-selector-state
            :entries entries
            :current-leaf-id current-leaf-id
            :initial-selected-id
            (unless no-select-p selected-id))))
    (when (and selected-id (not no-select-p))
      (cadr-cli::tree-selector-select-id state selected-id))
    (when no-select-p
      (setf (cadr-cli::tree-selector-state-selected-id state)
            nil))
    (or (cadr-cli::tree-selector-selected-id state)
        "null")))

(defun run-cli-selectors-tree-selected-id ()
  (list
   (tree-selected-id-encoded "user-3")
   (tree-selected-id-encoded "user-1")
   (tree-selected-id-encoded "asst-1")
   (tree-selected-id-encoded "label-1")
   (tree-selected-id-encoded "asst-empty")
   (tree-selected-id-encoded nil :no-select-p t)))

(defun tree-select-id-encoded (&key selected-id target-id filter folded-ids)
  (let* ((entries *tree-apply-filter-entries*)
         (current-leaf-id "user-3")
         (state
           (cadr-cli::make-tree-selector-state
            :entries entries
            :current-leaf-id current-leaf-id
            :initial-selected-id selected-id
            :filter (tree-filter-keyword (or filter "default")))))
    (when folded-ids
      (dolist (id folded-ids)
        (setf (gethash id
                       (cadr-cli::tree-selector-state-folded
                        state))
              t))
      (cadr-cli::tree-selector-apply-filter state)
      (cadr-cli::tree-selector-select-id state selected-id))
    (cadr-cli::tree-selector-select-id state target-id)
    (format nil "~a|~a"
            (or (cadr-cli::tree-selector-state-selected-id state)
                "null")
            (or (cadr-cli::tree-selector-state-preserved-id state)
                "null"))))

(defun run-cli-selectors-tree-select-id ()
  (list
   (tree-select-id-encoded :selected-id "user-3" :target-id "user-1")
   (tree-select-id-encoded :selected-id "user-3" :target-id "user-3")
   (tree-select-id-encoded :selected-id "user-3" :target-id "missing")
   (tree-select-id-encoded :selected-id "user-1" :target-id "label-1")
   (tree-select-id-encoded
    :selected-id "user-3" :target-id "asst-1"
    :filter "labeled-only")
   (tree-select-id-encoded
    :selected-id "user-1" :target-id "user-3"
    :folded-ids '("user-2"))))

(defun tree-visible-ids-part (encoded)
  (let ((pos (position #\| encoded)))
    (if pos
        (subseq encoded 0 pos)
        encoded)))

(defun tree-visible-ids-encoded (&key filter query folded-ids)
  (tree-visible-ids-part
   (tree-apply-filter-encoded
    :filter (or filter "default")
    :query query
    :folded-ids folded-ids)))

(defun run-cli-selectors-tree-visible-ids ()
  (list
   (tree-visible-ids-encoded :filter "default")
   (tree-visible-ids-encoded :filter "user-only")
   (tree-visible-ids-encoded :filter "no-tools")
   (tree-visible-ids-encoded :filter "default" :query "branch")
   (tree-visible-ids-encoded
    :filter "default" :folded-ids '("user-2"))
   (tree-visible-ids-encoded :filter "all")))

(defun stage-project-trust-options-fixtures ()
  (let ((parent
          (merge-pathnames "trust-pto-parent/" *scratch-directory*))
        (child
          (merge-pathnames "trust-pto-parent/child/" *scratch-directory*))
        (single
          (merge-pathnames "trust-pto-single/" *scratch-directory*)))
    (ensure-directories-exist parent)
    (ensure-directories-exist child)
    (ensure-directories-exist single)
    (list :parent parent :child child :single single)))

(defun encode-trust-path (path)
  (if path
      (let* ((normalized
               (string-right-trim '(#\/ #\\) path))
             (marker-pos
               (search "trust-pto-" normalized)))
        (if marker-pos
            (subseq normalized marker-pos)
            "scratch-root"))
    "null"))

(defun encode-trust-decision (decision)
  (cond
    ((eq decision t) "true")
    ((eq decision :remove) "null")
    (t "false")))

(defun encode-trust-updates (updates)
  (format nil "~{~a~^,~}"
          (mapcar
           (lambda (update)
             (format nil "~a=~a"
                     (encode-trust-path (getf update :path))
                     (encode-trust-decision
                      (getf update :decision))))
           updates)))

(defun encode-project-trust-option (option)
  (format nil "~a|~a|~a"
          (if (getf option :trusted-p) "true" "false")
          (encode-trust-path (getf option :saved-path))
          (encode-trust-updates (getf option :updates))))

(defun encode-project-trust-options (options)
  (format nil "~{~a~^;~}"
          (mapcar #'encode-project-trust-option options)))

(defun run-cli-selectors-project-trust-options ()
  (let ((fixtures (stage-project-trust-options-fixtures)))
    (list
     (encode-project-trust-options
      (cadr-cli::project-trust-options
       (namestring (getf fixtures :child))))
     (encode-project-trust-options
      (cadr-cli::project-trust-options
       (namestring (getf fixtures :single)))))))

(defun make-trust-selector-state-with-selected (cwd selected)
  (let ((state (cadr-cli::make-trust-selector-state :cwd cwd)))
    (setf (cadr-cli::trust-selector-state-selected state) selected)
    state))

(defun encode-trust-selector-selection (selection)
  (if selection
      (format nil "~a|~a"
              (if (getf selection :trusted-p) "true" "false")
              (encode-trust-updates (getf selection :updates)))
    "null"))

(defun run-cli-selectors-trust-selector-selection ()
  (let ((fixtures (stage-project-trust-options-fixtures)))
    (let ((child (namestring (getf fixtures :child)))
          (single (namestring (getf fixtures :single))))
      (list
       (encode-trust-selector-selection
        (cadr-cli::trust-selector-selection
         (make-trust-selector-state-with-selected child 0)))
       (encode-trust-selector-selection
        (cadr-cli::trust-selector-selection
         (make-trust-selector-state-with-selected child 1)))
       (encode-trust-selector-selection
        (cadr-cli::trust-selector-selection
         (make-trust-selector-state-with-selected child 2)))
       (encode-trust-selector-selection
        (cadr-cli::trust-selector-selection
         (make-trust-selector-state-with-selected single 0)))
       (encode-trust-selector-selection
        (cadr-cli::trust-selector-selection
         (make-trust-selector-state-with-selected single 2)))))))

(defun encode-trust-decision-description (cwd saved-entry)
  (if (null saved-entry)
      "none"
      (let* ((state
               (cadr-cli::make-trust-selector-state
                :cwd cwd :saved-entry saved-entry))
             (entry-path (getf saved-entry :path))
             (decision-label
               (if (getf saved-entry :decision) "trusted" "untrusted")))
        (if (string=
             (cadr-cli::display-directory-name entry-path)
             (cadr-cli::trust-selector-state-cwd state))
            (format nil "~a (~a)"
                    decision-label
                    (encode-trust-path entry-path))
            (format nil "~a (inherited from ~a)"
                    decision-label
                    (encode-trust-path entry-path))))))

(defun run-cli-selectors-trust-decision-description ()
  (let ((fixtures (stage-project-trust-options-fixtures)))
    (let ((child (namestring (getf fixtures :child)))
          (parent (namestring (getf fixtures :parent)))
          (single (namestring (getf fixtures :single))))
      (list
       (encode-trust-decision-description child nil)
       (encode-trust-decision-description
        child `(:path ,child :decision t))
       (encode-trust-decision-description
        child `(:path ,parent :decision t))
       (encode-trust-decision-description
        single `(:path ,single :decision nil))))))

(defun trust-selector-move-encoded (cwd selected delta)
  (let ((state (make-trust-selector-state-with-selected cwd selected)))
    (cadr-cli::trust-selector-move state delta)
    (write-to-string (cadr-cli::trust-selector-state-selected state))))

(defun run-cli-selectors-trust-selector-move ()
  (let ((fixtures (stage-project-trust-options-fixtures)))
    (let ((child (namestring (getf fixtures :child)))
          (single (namestring (getf fixtures :single))))
      (list
       (trust-selector-move-encoded child 0 1)
       (trust-selector-move-encoded child 1 -1)
       (trust-selector-move-encoded child 0 -1)
       (trust-selector-move-encoded child 2 1)
       (trust-selector-move-encoded child 1 10)
       (trust-selector-move-encoded single 0 1)
       (trust-selector-move-encoded single 1 1)))))

(defun encode-trust-handle-event-result (state action value)
  (format nil "~a|~a|~a"
          (if action
              (string-downcase (symbol-name action))
              "null")
          (if (and (eq action :select) value)
              (encode-trust-selector-selection value)
              "null")
          (write-to-string
           (cadr-cli::trust-selector-state-selected state))))

(defun trust-handle-event-encoded (cwd selected event-kind &key text)
  (let* ((state (make-trust-selector-state-with-selected cwd selected))
         (event
           (if text
               (cadr-tui:make-input-event :kind event-kind :text text)
               (cadr-tui:make-input-event :kind event-kind))))
    (multiple-value-bind (action value)
        (cadr-cli::trust-selector-handle-event state event)
      (encode-trust-handle-event-result state action value))))

(defun run-cli-selectors-trust-selector-handle-event ()
  (let ((fixtures (stage-project-trust-options-fixtures)))
    (let ((child (namestring (getf fixtures :child))))
      (list
       (trust-handle-event-encoded child 0 :down)
       (trust-handle-event-encoded child 1 :up)
       (trust-handle-event-encoded child 0 :enter)
       (trust-handle-event-encoded child 1 :text :text "k")
       (trust-handle-event-encoded child 0 :text :text "pin")
       (trust-handle-event-encoded child 1 :escape)
       (trust-handle-event-encoded child 0 :tab)))))

(defun trust-raw-input-key-data (state key-name)
  (first (cadr-tui:keybinding-keys
          (cadr-cli::trust-selector-state-keybindings state)
          key-name)))

(defun encode-trust-handle-raw-input-result (state action value consumed)
  (format nil "~a|~a|~a|~a"
          (if action
              (string-downcase (symbol-name action))
              "null")
          (if (and (eq action :select) value)
              (encode-trust-selector-selection value)
              "null")
          (write-to-string
           (cadr-cli::trust-selector-state-selected state))
          (if consumed "true" "false")))

(defun trust-handle-raw-input-encoded (cwd selected data)
  (let ((state (make-trust-selector-state-with-selected cwd selected)))
    (multiple-value-bind (action value consumed)
        (cadr-cli::trust-selector-handle-raw-input state data)
      (encode-trust-handle-raw-input-result state action value consumed))))

(defun trust-handle-raw-input-encoded-key (cwd selected key-name)
  (let ((state (make-trust-selector-state-with-selected cwd selected)))
    (trust-handle-raw-input-encoded
     cwd selected (trust-raw-input-key-data state key-name))))

(defun run-cli-selectors-trust-selector-handle-raw-input ()
  (let ((fixtures (stage-project-trust-options-fixtures)))
    (let ((child (namestring (getf fixtures :child))))
      (list
       (trust-handle-raw-input-encoded-key child 0 "tui.select.down")
       (trust-handle-raw-input-encoded child 1 "k")
       (trust-handle-raw-input-encoded
        child 0 (string #\Newline))
       (trust-handle-raw-input-encoded-key child 1 "tui.select.cancel")
       (trust-handle-raw-input-encoded child 0 "q")
       (trust-handle-raw-input-encoded child 1 "j")
       (trust-handle-raw-input-encoded-key child 0 "tui.select.confirm")))))

(defun encode-trust-option-label (option)
  (let ((label (getf option :label))
        (saved-path (getf option :saved-path)))
    (if (search "parent folder" label)
        (format nil "Trust parent folder (~a)"
                (encode-trust-path saved-path))
        label)))

(defun trust-selector-ui-encoded (state)
  (format nil "~a|~a|~{~a~^;~}"
          (encode-trust-decision-description
           (cadr-cli::trust-selector-state-cwd state)
           (cadr-cli::trust-selector-state-saved-entry state))
          (if (cadr-cli::trust-selector-state-project-trusted-p state)
              "trusted" "untrusted")
          (loop for index from 0
                below (length (cadr-cli::trust-selector-state-options state))
                collect
                (let ((option
                        (nth index
                             (cadr-cli::trust-selector-state-options state))))
                  (format nil "~a|~a|~a"
                          (encode-trust-option-label option)
                          (if (= index
                                 (cadr-cli::trust-selector-state-selected state))
                              "sel" "nosel")
                          (if (cadr-cli::trust-option-saved-p
                               option
                               (cadr-cli::trust-selector-state-saved-entry state))
                              "saved" "nosaved"))))))

(defun make-trust-render-state (cwd &key saved-entry project-trusted-p)
  (cadr-cli::make-trust-selector-state
   :cwd cwd
   :saved-entry saved-entry
   :project-trusted-p project-trusted-p))

(defun run-cli-selectors-trust-selector-ui-state ()
  (let ((fixtures (stage-project-trust-options-fixtures)))
    (let ((child (namestring (getf fixtures :child)))
          (parent (namestring (getf fixtures :parent)))
          (single (namestring (getf fixtures :single))))
      (list
       (trust-selector-ui-encoded (make-trust-render-state child))
       (trust-selector-ui-encoded
        (make-trust-render-state
         child
         :saved-entry `(:path ,child :decision t)
         :project-trusted-p t))
       (trust-selector-ui-encoded
        (make-trust-render-state
         child
         :saved-entry `(:path ,parent :decision t)
         :project-trusted-p t))
       (trust-selector-ui-encoded
        (make-trust-render-state
         child
         :saved-entry `(:path ,child :decision nil)
         :project-trusted-p nil))
       (trust-selector-ui-encoded (make-trust-render-state single))))))

(defun make-oauth-option-status-fixture
    (&key (id :anthropic) (name "Anthropic")
          (auth-type :oauth) status)
  (cadr-cli::make-oauth-selector-option
   :id id :name name :auth-type auth-type :status status))

(defun run-cli-selectors-oauth-option-status-label ()
  (list
   (cadr-cli::oauth-option-status-label
    (make-oauth-option-status-fixture))
   (cadr-cli::oauth-option-status-label
    (make-oauth-option-status-fixture
     :auth-type :api-key
     :status (list :type :oauth :source "OAuth")))
   (cadr-cli::oauth-option-status-label
    (make-oauth-option-status-fixture
     :status (list :type :api-key :source "stored credential")))
   (cadr-cli::oauth-option-status-label
    (make-oauth-option-status-fixture
     :status (list :type :oauth :source "OAuth")))
   (cadr-cli::oauth-option-status-label
    (make-oauth-option-status-fixture
     :status (list :type :oauth :source "stored credential")))
   (cadr-cli::oauth-option-status-label
    (make-oauth-option-status-fixture
     :auth-type :api-key
     :status (list :type :api-key :source "ANTHROPIC_API_KEY")))
   (cadr-cli::oauth-option-status-label
    (make-oauth-option-status-fixture
     :auth-type :api-key
     :status (list :type :api-key :source "runtime key")))))

(defun run-cli-selectors-oauth-option-status-rendered ()
  (list
   (cadr-cli::oauth-option-status-rendered
    (make-oauth-option-status-fixture))
   (cadr-cli::oauth-option-status-rendered
    (make-oauth-option-status-fixture
     :auth-type :api-key
     :status (list :type :oauth :source "OAuth")))
   (cadr-cli::oauth-option-status-rendered
    (make-oauth-option-status-fixture
     :status (list :type :api-key :source "stored credential")))
   (cadr-cli::oauth-option-status-rendered
    (make-oauth-option-status-fixture
     :status (list :type :oauth :source "OAuth")))
   (cadr-cli::oauth-option-status-rendered
    (make-oauth-option-status-fixture
     :status (list :type :oauth :source "stored credential")))
   (cadr-cli::oauth-option-status-rendered
    (make-oauth-option-status-fixture
     :auth-type :api-key
     :status (list :type :api-key :source "ANTHROPIC_API_KEY")))
   (cadr-cli::oauth-option-status-rendered
    (make-oauth-option-status-fixture
     :auth-type :api-key
     :status (list :type :api-key :source "runtime key")))))

(defun encode-credential-entry-auth-type (kind)
  (let ((auth-type (cadr-cli::credential-entry-auth-type kind)))
    (if (eq auth-type :oauth) "oauth" "api_key")))

(defun run-cli-selectors-credential-entry-auth-type ()
  (list
   (encode-credential-entry-auth-type "oauth")
   (encode-credential-entry-auth-type "api_key")
   (encode-credential-entry-auth-type "api-key")
   (encode-credential-entry-auth-type :oauth)
   (encode-credential-entry-auth-type :api-key)
   (encode-credential-entry-auth-type "OAuth")
   (encode-credential-entry-auth-type "API_KEY")))

(defun encode-oauth-environment-source-p (source)
  (if (cadr-cli::oauth-environment-source-p source) 1 0))

(defun run-cli-selectors-oauth-environment-source-p ()
  (list
   (encode-oauth-environment-source-p nil)
   (encode-oauth-environment-source-p "OAuth")
   (encode-oauth-environment-source-p "ANTHROPIC_API_KEY")
   (encode-oauth-environment-source-p "OPENAI_API_KEY, ANTHROPIC_API_KEY")
   (encode-oauth-environment-source-p "runtime key")
   (encode-oauth-environment-source-p "stored credential")
   (encode-oauth-environment-source-p "anthropic_api_key")))

(defun make-oauth-selector-test-options ()
  (list
   (make-oauth-option-status-fixture :id :anthropic :name "Anthropic")
   (make-oauth-option-status-fixture
    :id :openai :name "OpenAI" :auth-type :api-key)
   (make-oauth-option-status-fixture :id :google :name "Google")))

(defun encode-oauth-selector-option (option)
  (if (null option)
      "null"
      (format nil "~A|~A"
              (cadr-cli::provider-key
               (cadr-cli::oauth-selector-option-id option))
              (if (eq (cadr-cli::oauth-selector-option-auth-type option)
                      :oauth)
                  "oauth"
                  "api_key"))))

(defun oauth-selector-selection-encoded (options selected &key query)
  (let ((state
          (cadr-cli::make-oauth-selector-state
           :options options :query (or query ""))))
    (setf (cadr-cli::oauth-selector-state-selected state) selected)
    (encode-oauth-selector-option
     (cadr-cli::oauth-selector-selection state))))

(defun run-cli-selectors-oauth-selector-selection ()
  (let ((options (make-oauth-selector-test-options)))
    (list
     (oauth-selector-selection-encoded options 0)
     (oauth-selector-selection-encoded options 1)
     (oauth-selector-selection-encoded options 2)
     (oauth-selector-selection-encoded options 0 :query "open")
     (oauth-selector-selection-encoded options 0 :query "nope"))))

(defun oauth-selector-apply-filter-encoded (options query)
  (let ((state
          (cadr-cli::make-oauth-selector-state
           :options options :query "")))
    (setf (cadr-cli::oauth-selector-state-selected state) 2)
    (setf (cadr-cli::oauth-selector-state-query state) query)
    (cadr-cli::oauth-selector-apply-filter state)
    (format nil "~A|~A"
            (length
             (cadr-cli::oauth-selector-state-filtered-options state))
            (cadr-cli::oauth-selector-state-selected state))))

(defun run-cli-selectors-oauth-selector-apply-filter ()
  (let ((options (make-oauth-selector-test-options)))
    (list
     (oauth-selector-apply-filter-encoded options "")
     (oauth-selector-apply-filter-encoded options "open")
     (oauth-selector-apply-filter-encoded options "nope")
     (oauth-selector-apply-filter-encoded options "anth")
     (oauth-selector-apply-filter-encoded options "oogle"))))

(defun encode-oauth-handle-event-result (state action value)
  (format nil "~a|~a|~a|~a"
          (if action
              (string-downcase (symbol-name action))
              "null")
          (if (and (eq action :select) value)
              (encode-oauth-selector-option value)
              "null")
          (write-to-string
           (cadr-cli::oauth-selector-state-selected state))
          (cadr-cli::oauth-selector-state-query state)))

(defun oauth-handle-event-encoded
    (options selected event-kind &key query text)
  (let* ((state
           (cadr-cli::make-oauth-selector-state
            :options options :query (or query "")))
         (event
           (if text
               (cadr-tui:make-input-event :kind event-kind :text text)
               (cadr-tui:make-input-event :kind event-kind))))
    (setf (cadr-cli::oauth-selector-state-selected state) selected)
    (multiple-value-bind (action value)
        (cadr-cli::oauth-selector-handle-event state event)
      (encode-oauth-handle-event-result state action value))))

(defun run-cli-selectors-oauth-selector-handle-event ()
  (let ((options (make-oauth-selector-test-options)))
    (list
     (oauth-handle-event-encoded options 0 :down)
     (oauth-handle-event-encoded options 1 :up)
     (oauth-handle-event-encoded options 0 :enter)
     (oauth-handle-event-encoded options 0 :escape)
     (oauth-handle-event-encoded options 0 :text :text "op")
     (oauth-handle-event-encoded options 0 :backspace :query "op"))))

(defun encode-oauth-handle-raw-input-result (state action value consumed)
  (format nil "~a|~a|~a|~a"
          (if action
              (string-downcase (symbol-name action))
              "null")
          (if (and (eq action :select) value)
              (encode-oauth-selector-option value)
              "null")
          (write-to-string
           (cadr-cli::oauth-selector-state-selected state))
          (if consumed "true" "false")))

(defun oauth-raw-input-key-data (state key-name)
  (first (cadr-tui:keybinding-keys
          (cadr-cli::oauth-selector-state-keybindings state)
          key-name)))

(defun oauth-handle-raw-input-encoded (options selected data)
  (let* ((state (cadr-cli::make-oauth-selector-state :options options)))
    (setf (cadr-cli::oauth-selector-state-selected state) selected)
    (multiple-value-bind (action value consumed)
        (cadr-cli::oauth-selector-handle-raw-input state data)
      (encode-oauth-handle-raw-input-result state action value consumed))))

(defun oauth-handle-raw-input-encoded-key (options selected key-name)
  (let ((state (cadr-cli::make-oauth-selector-state :options options)))
    (oauth-handle-raw-input-encoded
     options selected (oauth-raw-input-key-data state key-name))))

(defun run-cli-selectors-oauth-selector-handle-raw-input ()
  (let ((options (make-oauth-selector-test-options)))
    (list
     (oauth-handle-raw-input-encoded-key options 0 "tui.select.down")
     (oauth-handle-raw-input-encoded options 1 "j")
     (oauth-handle-raw-input-encoded options 0 (string #\Newline))
     (oauth-handle-raw-input-encoded-key options 1 "tui.select.cancel")
     (oauth-handle-raw-input-encoded options 0 "q")
     (oauth-handle-raw-input-encoded options 0 "o")
     (oauth-handle-raw-input-encoded-key options 0 "tui.select.confirm"))))

(defun encode-oauth-selector-search-text (option)
  (format nil "~A ~A ~A ~A"
          (cadr-cli::oauth-selector-option-name option)
          (cadr-cli::provider-key
           (cadr-cli::oauth-selector-option-id option))
          (if (eq (cadr-cli::oauth-selector-option-auth-type option)
                  :oauth)
              "oauth"
              "api_key")
          (or (cadr-cli::oauth-selector-option-method-name option) "")))

(defun run-cli-selectors-oauth-selector-search-text ()
  (list
   (encode-oauth-selector-search-text
    (cadr-cli::make-oauth-selector-option
     :id :anthropic :name "Anthropic" :auth-type :oauth
     :method-name "Anthropic account"))
   (encode-oauth-selector-search-text
    (cadr-cli::make-oauth-selector-option
     :id :openai :name "OpenAI" :auth-type :api-key
     :method-name "OpenAI API key"))
   (encode-oauth-selector-search-text
    (cadr-cli::make-oauth-selector-option
     :id :google :name "Google" :auth-type :oauth))
   (encode-oauth-selector-search-text
    (cadr-cli::make-oauth-selector-option
     :id :mistral :name "Mistral" :auth-type :api-key))))

(defun make-auth-route-oauth-option (&key (id :anthropic) (name "Anthropic")
                                          (login-label nil))
  (cadr-cli::make-oauth-selector-option
   :id id :name name :auth-type :oauth :login-label login-label))

(defun make-auth-route-api-option (&key (id :anthropic) (name "Anthropic"))
  (cadr-cli::make-oauth-selector-option
   :id id :name name :auth-type :api-key))

(defun encode-login-auth-type-route (&rest args)
  (multiple-value-bind (route payload)
      (apply #'cadr-cli::login-auth-type-route args)
    (ecase route
      (:none
       (format nil "none|~A" payload))
      (:direct
       (format nil "direct|~A|~A"
               (cadr-cli::provider-key
                (cadr-cli::oauth-selector-option-id payload))
               (if (eq (cadr-cli::oauth-selector-option-auth-type payload)
                       :oauth)
                   "oauth"
                   "api_key")))
      (:select
       (let ((state payload))
         (format nil "select|~A|~{~A~^|~}"
                 (cadr-cli::login-method-selector-state-title state)
                 (mapcar #'cadr-tui:select-item-label
                         (cadr-tui::select-list-items
                          (cadr-cli::login-method-selector-state-select-list
                           state)))))))))

(defun run-cli-selectors-login-auth-type-route ()
  (list
   (encode-login-auth-type-route nil)
   (encode-login-auth-type-route
    (list (make-auth-route-oauth-option)))
   (encode-login-auth-type-route
    (list (make-auth-route-api-option)))
   (encode-login-auth-type-route
    (list
     (make-auth-route-oauth-option
      :login-label "Sign in with Claude")
     (make-auth-route-api-option)))
   (encode-login-auth-type-route nil :generic-p t)))

(defun login-provider-fixture-definitions ()
  (list
   (cadr-ai::make-provider-definition
    :id :anthropic :name "Anthropic"
    :protocol :anthropic-messages
    :base-url "https://example.invalid"
    :auth-types '(:oauth :api-key)
    :default-model "claude")
   (cadr-ai::make-provider-definition
    :id :google-vertex :name "Google Vertex AI"
    :protocol :google-vertex
    :base-url "https://example.invalid"
    :auth-types '(:api-key)
    :default-model "gemini"
    :api-key-auth-strategy :vertex)))

(defun encode-oauth-selector-status-field (status)
  (if (null status)
      ""
      (format nil "~A:~A"
              (if (eq (getf status :type) :oauth)
                  "oauth"
                  "api_key")
              (getf status :source))))

(defun encode-login-provider-option (option)
  (format nil "~A|~A|~A|~A|~A|~A"
          (cadr-cli::provider-key
           (cadr-cli::oauth-selector-option-id option))
          (if (eq (cadr-cli::oauth-selector-option-auth-type option)
                  :oauth)
              "oauth"
              "api_key")
          (cadr-cli::oauth-selector-option-method-name option)
          (or (cadr-cli::oauth-selector-option-login-label option) "")
          (if (cadr-cli::oauth-selector-option-structured-login-p option)
              "1"
              "0")
          (encode-oauth-selector-status-field
           (cadr-cli::oauth-selector-option-status option))))

(defun encode-login-provider-options (options)
  (format nil "~{~A~^,~}"
          (mapcar #'encode-login-provider-option options)))

(defun run-cli-selectors-login-provider-options ()
  (let ((definitions (login-provider-fixture-definitions)))
    (list
     (encode-login-provider-options
      (cadr-cli::login-provider-options definitions))
     (encode-login-provider-options
      (cadr-cli::login-provider-options
       definitions :auth-type :oauth))
     (encode-login-provider-options
      (cadr-cli::login-provider-options
       definitions :auth-type :api-key))
     (encode-login-provider-options
      (cadr-cli::login-provider-options
       (list (cadr-ai:find-provider-definition :openrouter))))
     (encode-login-provider-options
      (cadr-cli::login-provider-options
       definitions
       :status-function
       (lambda (id)
         (declare (ignore id))
         (list :type :oauth :source "OAuth")))))))

(defun run-cli-selectors-logout-provider-options ()
  (let ((definitions (login-provider-fixture-definitions)))
    (list
     (encode-login-provider-options
      (cadr-cli::logout-provider-options definitions nil))
     (encode-login-provider-options
      (cadr-cli::logout-provider-options
       definitions
       '(("anthropic" . "oauth")
         ("google-vertex" . "api_key"))))
     (encode-login-provider-options
      (cadr-cli::logout-provider-options
       definitions
       '(("unknown-provider" . "api_key"))))
     (encode-login-provider-options
      (cadr-cli::logout-provider-options
       definitions
       '(("openai" . "oauth")
         ("anthropic" . "api_key")
         ("google-vertex" . "oauth")))))))

(defun make-login-method-selector-state-with-selected (selected)
  (let ((state (cadr-cli::make-login-method-selector-state)))
    (setf (cadr-tui::select-list-selected
           (cadr-cli::login-method-selector-state-select-list state))
          selected)
    state))

(defun encode-login-method-selector-value (value)
  (cond
    ((eq value :oauth) "oauth")
    ((eq value :api-key) "api_key")
    ((typep value 'cadr-cli::oauth-selector-option)
     (encode-oauth-selector-option value))
    (t (write-to-string value))))

(defun encode-login-method-handle-event-result (state action value)
  (format nil "~a|~a|~a"
          (if action
              (string-downcase (symbol-name action))
              "null")
          (if (and (eq action :select) value)
              (encode-login-method-selector-value value)
              "null")
          (write-to-string
           (cadr-tui::select-list-selected
            (cadr-cli::login-method-selector-state-select-list
             state)))))

(defun login-method-handle-event-encoded (selected event-kind)
  (let* ((state (make-login-method-selector-state-with-selected selected))
         (event (cadr-tui:make-input-event :kind event-kind)))
    (multiple-value-bind (action value)
        (cadr-cli::login-method-selector-handle-event state event)
      (encode-login-method-handle-event-result state action value))))

(defun run-cli-selectors-login-method-selector-handle-event ()
  (list
   (login-method-handle-event-encoded 0 :down)
   (login-method-handle-event-encoded 1 :up)
   (login-method-handle-event-encoded 0 :enter)
   (login-method-handle-event-encoded 1 :enter)
   (login-method-handle-event-encoded 0 :escape)
   (login-method-handle-event-encoded 1 :clear)
   (login-method-handle-event-encoded 0 :interrupt)))

(defun oauth-selector-move-encoded (options selected delta &key query)
  (let* ((state
           (cadr-cli::make-oauth-selector-state
            :options options :query (or query ""))))
    (cadr-cli::oauth-selector-apply-filter state)
    (setf (cadr-cli::oauth-selector-state-selected state) selected)
    (cadr-cli::oauth-selector-move state delta)
    (write-to-string (cadr-cli::oauth-selector-state-selected state))))

(defun run-cli-selectors-oauth-selector-move ()
  (let ((options (make-oauth-selector-test-options)))
    (list
     (oauth-selector-move-encoded options 0 1)
     (oauth-selector-move-encoded options 2 -1)
     (oauth-selector-move-encoded options 1 1)
     (oauth-selector-move-encoded options 1 -1)
     (oauth-selector-move-encoded options 0 1 :query "open"))))

(defun encode-api-key-input-handle-event-result (state action value)
  (format nil "~a|~a|~a|~a"
          (if action
              (string-downcase (symbol-name action))
              "null")
          (if (and (eq action :select) value)
              (cadr-cli::provider-key
               (cadr-cli::oauth-selector-option-id
                (getf value :option)))
              "null")
          (if (and (eq action :select) value)
              (if (eq (cadr-cli::oauth-selector-option-auth-type
                       (getf value :option))
                      :oauth)
                  "oauth"
                  "api_key")
              "null")
          (if (and (eq action :select) value)
              (getf value :key)
              (write-to-string
               (length
                (cadr-tui:single-line-input-value
                 (cadr-cli::api-key-input-state-input state)))))))

(defun make-api-key-input-state-for-fixture (&key (prefill ""))
  (let ((state
          (cadr-cli::make-api-key-input-state
           (make-oauth-option-status-fixture
            :id :anthropic :name "Anthropic" :auth-type :api-key))))
    (when (plusp (length prefill))
      (feed-single-line-text
       (cadr-cli::api-key-input-state-input state)
       prefill))
    state))

(defun api-key-input-handle-event-encoded (event-kind &key prefill text)
  (let* ((state (make-api-key-input-state-for-fixture :prefill prefill))
         (event
           (if text
               (cadr-tui:make-input-event :kind event-kind :text text)
               (cadr-tui:make-input-event :kind event-kind))))
    (multiple-value-bind (action value)
        (cadr-cli::api-key-input-state-handle-event state event)
      (encode-api-key-input-handle-event-result state action value))))

(defun run-cli-selectors-api-key-input-state-handle-event ()
  (list
   (api-key-input-handle-event-encoded :escape)
   (api-key-input-handle-event-encoded :clear)
   (api-key-input-handle-event-encoded :text :text "sk-test")
   (api-key-input-handle-event-encoded :backspace :prefill "ab")
   (api-key-input-handle-event-encoded :enter)
   (api-key-input-handle-event-encoded :enter :prefill "sk-test")
   (api-key-input-handle-event-encoded :interrupt)))

(defun login-method-selector-ui-encoded (state width)
  (let* ((select-list
           (cadr-cli::login-method-selector-state-select-list state))
         (items
           (cadr-tui::select-list-filtered-items select-list))
         (selected
           (if items
               (min (cadr-tui::select-list-selected select-list)
                    (1- (length items)))
               0))
         (keybindings (cadr-tui:get-keybindings))
         (hints
           (concatenate
            'string
            (cadr-cli::raw-key-hint "↑↓" "navigate") "  "
            (cadr-cli::selector-keybinding-hint
             keybindings "tui.select.confirm" "select") "  "
            (cadr-cli::selector-keybinding-hint
             keybindings "tui.select.cancel" "cancel"))))
    ;; Exercise the render path; observed digest is structural.
    (cadr-cli::render-login-method-selector state width)
    (format nil "~a|~a|~a|~{~a~^;~}|~a"
            (cadr-cli::login-method-selector-state-title state)
            width
            selected
            (loop for item in items
                  for index from 0
                  collect
                  (format nil "~a:~a"
                          (if (= index selected) "sel" "nosel")
                          (cadr-tui:select-item-label item)))
            (cadr-cli::strip-ansi hints))))

(defun run-cli-selectors-login-method-selector-ui-state ()
  (list
   (login-method-selector-ui-encoded
    (cadr-cli::make-login-method-selector-state) 40)
   (login-method-selector-ui-encoded
    (make-login-method-selector-state-with-selected 1) 40)
   (login-method-selector-ui-encoded
    (cadr-cli::make-login-method-selector-state
     :title "Select authentication method for Anthropic:")
    60)
   (login-method-selector-ui-encoded
    (make-login-method-selector-state-with-selected 0) 20)
   (login-method-selector-ui-encoded
    (make-login-method-selector-state-with-selected 1) 28)))

(defun measure-cli-selectors-session-search ()
  (let ((observed (run-cli-selectors-session-search))
        (keys (run-cli-selectors-key-text))
        (fuzzy (run-cli-selectors-fuzzy-filter))
        (delete-query (run-cli-selectors-delete-query))
        (visible-slice (run-cli-selectors-visible-slice))
        (move-index (run-cli-selectors-move-index))
        (align-left-right (run-cli-selectors-align-left-right))
        (fit-line (run-cli-selectors-fit-line))
        (border-line (run-cli-selectors-border-line))
        (selected-line (run-cli-selectors-selected-line))
        (muted-line (run-cli-selectors-muted-line))
        (dim-line (run-cli-selectors-dim-line))
        (modified-cursor-key (run-cli-selectors-modified-cursor-key))
        (title-line (run-cli-selectors-title-line))
        (overlay-title-line (run-cli-selectors-overlay-title-line))
        (input-line (run-cli-selectors-input-line))
        (keybinding-text (run-cli-selectors-keybinding-text))
        (keybinding-hint (run-cli-selectors-keybinding-hint))
        (session-format-age (run-cli-selectors-session-format-age))
        (session-record-label (run-cli-selectors-session-record-label))
        (session-shorten-path (run-cli-selectors-session-shorten-path))
        (session-quoted-search (run-cli-selectors-session-quoted-search))
        (session-thread-records (run-cli-selectors-session-thread-records))
        (session-binding-label (run-cli-selectors-session-binding-label))
        (session-same-path (run-cli-selectors-session-same-path))
        (session-quoted-p (run-cli-selectors-session-quoted-p))
        (session-named-p (run-cli-selectors-session-named-p))
        (settings-thinking-description
          (run-cli-selectors-settings-thinking-description))
        (settings-display-value
          (run-cli-selectors-settings-display-value))
        (settings-automatic-theme-setting
          (run-cli-selectors-settings-automatic-theme-setting))
        (settings-active-automatic-theme
          (run-cli-selectors-settings-active-automatic-theme))
        (settings-cycle
          (run-cli-selectors-settings-cycle))
        (settings-apply-filter
          (run-cli-selectors-settings-apply-filter))
        (tree-entry-filtered
          (run-cli-selectors-tree-entry-filtered))
        (tree-query-matches
          (run-cli-selectors-tree-query-matches))
        (tree-entry-search-text
          (run-cli-selectors-tree-entry-search-text))
        (tree-settings-entry-p
          (run-cli-selectors-tree-settings-entry-p))
        (tree-normalize-display-text
          (run-cli-selectors-tree-normalize-display-text))
        (tree-status-labels
          (run-cli-selectors-tree-status-labels))
        (tree-shorten-path
          (run-cli-selectors-tree-shorten-path))
        (tree-foldable-p
          (run-cli-selectors-tree-foldable-p))
        (tree-tool-argument
          (run-cli-selectors-tree-tool-argument))
        (tree-cycle-filter
          (run-cli-selectors-tree-cycle-filter))
        (tree-format-label-timestamp
          (run-cli-selectors-tree-format-label-timestamp))
        (tree-iso-timestamp
          (run-cli-selectors-tree-iso-timestamp))
        (tree-format-tool-call
          (run-cli-selectors-tree-format-tool-call))
        (tree-entry-display-text
          (run-cli-selectors-tree-entry-display-text))
        (tree-prefix
          (run-cli-selectors-tree-prefix))
        (tree-visual-nodes
          (run-cli-selectors-tree-visual-nodes))
        (tree-horizontal-viewport
          (run-cli-selectors-tree-horizontal-viewport))
        (tree-help-keys
          (run-cli-selectors-tree-help-keys))
        (tree-help-key
          (run-cli-selectors-tree-help-key))
        (tree-app-key-p
          (run-cli-selectors-tree-app-key-p))
        (tree-help-lines
          (run-cli-selectors-tree-help-lines))
        (tree-active-path
          (run-cli-selectors-tree-active-path))
        (tree-nearest-visible-id
          (run-cli-selectors-tree-nearest-visible-id))
        (tree-prioritize-active
          (run-cli-selectors-tree-prioritize-active))
        (tree-entry-map
          (run-cli-selectors-tree-entry-map))
        (tree-order-entries
          (run-cli-selectors-tree-order-entries))
        (tree-rebuild-visible-maps
          (run-cli-selectors-tree-rebuild-visible-maps))
        (tree-apply-filter
          (run-cli-selectors-tree-apply-filter))
        (tree-render-lines
          (run-cli-selectors-tree-render-lines))
        (tree-move
          (run-cli-selectors-tree-move))
        (tree-fold-or-up
          (run-cli-selectors-tree-fold-or-up))
        (tree-unfold-or-down
          (run-cli-selectors-tree-unfold-or-down))
        (tree-branch-segment-id
          (run-cli-selectors-tree-branch-segment-id))
        (tree-set-query
          (run-cli-selectors-tree-set-query))
        (tree-set-filter
          (run-cli-selectors-tree-set-filter))
        (tree-copy-selected
          (run-cli-selectors-tree-copy-selected))
        (tree-toggle-label-timestamps
          (run-cli-selectors-tree-toggle-label-timestamps))
        (tree-start-label-edit
          (run-cli-selectors-tree-start-label-edit))
        (tree-confirm-label
          (run-cli-selectors-tree-confirm-label))
        (tree-cancel-label
          (run-cli-selectors-tree-cancel-label))
        (tree-handle-raw-input
          (run-cli-selectors-tree-handle-raw-input))
        (tree-handle-event
          (run-cli-selectors-tree-handle-event))
        (tree-handle-label-event
          (run-cli-selectors-tree-handle-label-event))
        (tree-selected-entry
          (run-cli-selectors-tree-selected-entry))
        (tree-selected-id
          (run-cli-selectors-tree-selected-id))
        (tree-select-id
          (run-cli-selectors-tree-select-id))
        (tree-visible-ids
          (run-cli-selectors-tree-visible-ids))
        (project-trust-options
          (run-cli-selectors-project-trust-options))
        (trust-selector-selection
          (run-cli-selectors-trust-selector-selection))
        (trust-decision-description
          (run-cli-selectors-trust-decision-description))
        (trust-selector-move
          (run-cli-selectors-trust-selector-move))
        (trust-selector-handle-event
          (run-cli-selectors-trust-selector-handle-event))
        (trust-selector-handle-raw-input
          (run-cli-selectors-trust-selector-handle-raw-input))
        (trust-selector-ui-state
          (run-cli-selectors-trust-selector-ui-state))
        (oauth-option-status-label
          (run-cli-selectors-oauth-option-status-label))
        (oauth-option-status-rendered
          (run-cli-selectors-oauth-option-status-rendered))
        (credential-entry-auth-type
          (run-cli-selectors-credential-entry-auth-type))
        (oauth-environment-source-p
          (run-cli-selectors-oauth-environment-source-p))
        (oauth-selector-selection
          (run-cli-selectors-oauth-selector-selection))
        (oauth-selector-apply-filter
          (run-cli-selectors-oauth-selector-apply-filter))
        (oauth-selector-handle-event
          (run-cli-selectors-oauth-selector-handle-event))
        (oauth-selector-handle-raw-input
          (run-cli-selectors-oauth-selector-handle-raw-input))
        (oauth-selector-search-text
          (run-cli-selectors-oauth-selector-search-text))
        (login-auth-type-route
          (run-cli-selectors-login-auth-type-route))
        (login-provider-options
          (run-cli-selectors-login-provider-options))
        (logout-provider-options
          (run-cli-selectors-logout-provider-options))
        (login-method-selector-handle-event
          (run-cli-selectors-login-method-selector-handle-event))
        (oauth-selector-move
          (run-cli-selectors-oauth-selector-move))
        (api-key-input-state-handle-event
          (run-cli-selectors-api-key-input-state-handle-event))
        (login-method-selector-ui-state
          (run-cli-selectors-login-method-selector-ui-state)))
    (json-object
     "observed"
     (json-object
      "ss_empty" (nth 0 observed)
      "ss_hit" (nth 1 observed)
      "ss_miss" (nth 2 observed)
      "ss_re" (nth 3 observed)
      "ss_badre" (nth 4 observed)
      "ss_named" (nth 5 observed)
      "kt_ctrl" (nth 0 keys)
      "kt_slash" (nth 1 keys)
      "kt_shift" (nth 2 keys)
      "kt_cap" (nth 3 keys)
      "kt_empty" (nth 4 keys)
      "ff_empty" (nth 0 fuzzy)
      "ff_an" (nth 1 fuzzy)
      "ff_app" (nth 2 fuzzy)
      "ff_cl" (nth 3 fuzzy)
      "ff_slash" (nth 4 fuzzy)
      "dq_empty" (nth 0 delete-query)
      "dq_a" (nth 1 delete-query)
      "dq_abc" (nth 2 delete-query)
      "dq_cafe" (nth 3 delete-query)
      "dq_emoji" (nth 4 delete-query)
      "dq_combining" (nth 5 delete-query)
      "vs0" (first (first visible-slice))
      "vs0_end" (second (first visible-slice))
      "vs0_vis" (third (first visible-slice))
      "vs5" (first (second visible-slice))
      "vs5_vis" (third (second visible-slice))
      "vs20_mid" (first (third visible-slice))
      "vs20_mid_vis" (third (third visible-slice))
      "vs20_top" (first (fourth visible-slice))
      "vs20_bot" (first (fifth visible-slice))
      "vs20_bot_vis" (third (fifth visible-slice))
      "vs3_vis" (third (sixth visible-slice))
      "mi_empty" (nth 0 move-index)
      "mi_wrap_up" (nth 1 move-index)
      "mi_wrap_dn" (nth 2 move-index)
      "mi_fwd" (nth 3 move-index)
      "mi_back" (nth 4 move-index)
      "mi_big" (nth 5 move-index)
      "alr_wide" (nth 0 align-left-right)
      "alr_trunc_left" (nth 1 align-left-right)
      "alr_trunc_right" (nth 2 align-left-right)
      "alr_narrow" (nth 3 align-left-right)
      "alr_empty_left" (nth 4 align-left-right)
      "alr_empty_right" (nth 5 align-left-right)
      "fl_short" (nth 0 fit-line)
      "fl_trunc" (nth 1 fit-line)
      "fl_pad" (nth 2 fit-line)
      "fl_ellipsis" (nth 3 fit-line)
      "fl_wide" (nth 4 fit-line)
      "fl_empty" (nth 5 fit-line)
      "bl_w40" (nth 0 border-line)
      "bl_w40_acc" (nth 1 border-line)
      "bl_w1" (nth 2 border-line)
      "bl_w80" (nth 3 border-line)
      "bl_w10_acc" (nth 4 border-line)
      "bl_w20" (nth 5 border-line)
      "sl_short" (nth 0 selected-line)
      "sl_trunc" (nth 1 selected-line)
      "sl_wide" (nth 2 selected-line)
      "sl_empty" (nth 3 selected-line)
      "sl_pad20" (nth 4 selected-line)
      "sl_narrow" (nth 5 selected-line)
      "ml_short" (nth 0 muted-line)
      "ml_trunc" (nth 1 muted-line)
      "ml_wide" (nth 2 muted-line)
      "ml_empty" (nth 3 muted-line)
      "ml_item20" (nth 4 muted-line)
      "ml_narrow" (nth 5 muted-line)
      "dl_short" (nth 0 dim-line)
      "dl_trunc" (nth 1 dim-line)
      "dl_wide" (nth 2 dim-line)
      "dl_empty" (nth 3 dim-line)
      "dl_item20" (nth 4 dim-line)
      "dl_narrow" (nth 5 dim-line)
      "mck_up" (nth 0 modified-cursor-key)
      "mck_shift_dn" (nth 1 modified-cursor-key)
      "mck_ctrl_rt" (nth 2 modified-cursor-key)
      "mck_alt_lt" (nth 3 modified-cursor-key)
      "mck_ctrl_shift_up" (nth 4 modified-cursor-key)
      "mck_super_dn" (nth 5 modified-cursor-key)
      "tl_short" (nth 0 title-line)
      "tl_trunc" (nth 1 title-line)
      "tl_empty" (nth 2 title-line)
      "tl_wide" (nth 3 title-line)
      "tl_narrow" (nth 4 title-line)
      "tl_normal" (nth 5 title-line)
      "otl_short" (nth 0 overlay-title-line)
      "otl_trunc" (nth 1 overlay-title-line)
      "otl_empty" (nth 2 overlay-title-line)
      "otl_wide" (nth 3 overlay-title-line)
      "otl_narrow" (nth 4 overlay-title-line)
      "otl_normal" (nth 5 overlay-title-line)
      "il_empty" (nth 0 input-line)
      "il_short" (nth 1 input-line)
      "il_ab12" (nth 2 input-line)
      "il_grapheme" (nth 3 input-line)
      "il_narrow" (nth 4 input-line)
      "il_scroll" (nth 5 input-line)
      "kbt_confirm" (nth 0 keybinding-text)
      "kbt_cancel" (nth 1 keybinding-text)
      "kbt_left" (nth 2 keybinding-text)
      "kbt_empty" (nth 3 keybinding-text)
      "kbt_custom_confirm" (nth 4 keybinding-text)
      "kbt_custom_cancel" (nth 5 keybinding-text)
      "kbh_confirm" (nth 0 keybinding-hint)
      "kbh_cancel" (nth 1 keybinding-hint)
      "kbh_left" (nth 2 keybinding-hint)
      "kbh_empty" (nth 3 keybinding-hint)
      "kbh_custom_save" (nth 4 keybinding-hint)
      "kbh_custom_cancel" (nth 5 keybinding-hint)
      "sfa_now" (nth 0 session-format-age)
      "sfa_sec" (nth 1 session-format-age)
      "sfa_min" (nth 2 session-format-age)
      "sfa_hour" (nth 3 session-format-age)
      "sfa_day" (nth 4 session-format-age)
      "sfa_week" (nth 5 session-format-age)
      "srl_named" (nth 0 session-record-label)
      "srl_first" (nth 1 session-record-label)
      "srl_empty" (nth 2 session-record-label)
      "srl_ctrl" (nth 3 session-record-label)
      "srl_name_ctrl" (nth 4 session-record-label)
      "ssp_home" (nth 0 session-shorten-path)
      "ssp_prefix" (nth 1 session-shorten-path)
      "ssp_abs" (nth 2 session-shorten-path)
      "ssp_proj" (nth 3 session-shorten-path)
      "ssp_empty" (nth 4 session-shorten-path)
      "sqs_cadr" (nth 0 session-quoted-search)
      "sqs_phrase" (nth 1 session-quoted-search)
      "sqs_miss" (nth 2 session-quoted-search)
      "sqs_other_miss" (nth 3 session-quoted-search)
      "sqs_name" (nth 4 session-quoted-search)
      "sqs_other_hit" (nth 5 session-quoted-search)
      "str_count" (nth 0 session-thread-records)
      "str_depths" (nth 1 session-thread-records)
      "str_ids" (nth 2 session-thread-records)
      "sbl_confirm" (nth 0 session-binding-label)
      "sbl_delete" (nth 1 session-binding-label)
      "sbl_noninvasive" (nth 2 session-binding-label)
      "sbl_fallback" (nth 3 session-binding-label)
      "sbl_custom" (nth 4 session-binding-label)
      "ssp_same" (nth 0 session-same-path)
      "ssp_diff" (nth 1 session-same-path)
      "ssp_nil_left" (nth 2 session-same-path)
      "ssp_nil_right" (nth 3 session-same-path)
      "ssp_nil_both" (nth 4 session-same-path)
      "sqp_phrase" (nth 0 session-quoted-p)
      "sqp_words" (nth 1 session-quoted-p)
      "sqp_plain" (nth 2 session-quoted-p)
      "sqp_empty" (nth 3 session-quoted-p)
      "sqp_one" (nth 4 session-quoted-p)
      "sqp_open" (nth 5 session-quoted-p)
      "snp_named" (nth 0 session-named-p)
      "snp_whitespace" (nth 1 session-named-p)
      "snp_empty" (nth 2 session-named-p)
      "snp_nil" (nth 3 session-named-p)
      "std_off" (nth 0 settings-thinking-description)
      "std_minimal" (nth 1 settings-thinking-description)
      "std_low" (nth 2 settings-thinking-description)
      "std_medium" (nth 3 settings-thinking-description)
      "std_high" (nth 4 settings-thinking-description)
      "std_xhigh" (nth 5 settings-thinking-description)
      "std_max" (nth 6 settings-thinking-description)
      "std_unknown" (nth 7 settings-thinking-description)
      "sdv_true" (nth 0 settings-display-value)
      "sdv_false" (nth 1 settings-display-value)
      "sdv_symbol" (nth 2 settings-display-value)
      "sdv_int" (nth 3 settings-display-value)
      "sdv_string" (nth 4 settings-display-value)
      "sats_solarized" (nth 0 settings-automatic-theme-setting)
      "sats_same" (nth 1 settings-automatic-theme-setting)
      "sats_light_dark" (nth 2 settings-automatic-theme-setting)
      "saat_light_term" (nth 0 settings-active-automatic-theme)
      "saat_dark_term" (nth 1 settings-active-automatic-theme)
      "saat_light_pair" (nth 2 settings-active-automatic-theme)
      "ssc_true" (nth 0 settings-cycle)
      "ssc_transport" (nth 1 settings-cycle)
      "ssc_wrap" (nth 2 settings-cycle)
      "ssc_missing" (nth 3 settings-cycle)
      "sap_empty" (nth 0 settings-apply-filter)
      "sap_trans" (nth 1 settings-apply-filter)
      "sap_none" (nth 2 settings-apply-filter)
      "sap_app" (nth 3 settings-apply-filter)
      "tef_user_def" (nth 0 tree-entry-filtered)
      "tef_label_def" (nth 1 tree-entry-filtered)
      "tef_user_uo" (nth 2 tree-entry-filtered)
      "tef_tool_nt" (nth 3 tree-entry-filtered)
      "tef_labeled_lo" (nth 4 tree-entry-filtered)
      "tef_all_label" (nth 5 tree-entry-filtered)
      "tqm_hit" (nth 0 tree-query-matches)
      "tqm_miss" (nth 1 tree-query-matches)
      "tqm_multi" (nth 2 tree-query-matches)
      "tqm_partial" (nth 3 tree-query-matches)
      "tqm_empty" (nth 4 tree-query-matches)
      "tese_sparse" (nth 0 tree-entry-search-text)
      "tese_label" (nth 1 tree-entry-search-text)
      "tese_empty" (nth 2 tree-entry-search-text)
      "tese_full" (nth 3 tree-entry-search-text)
      "tese_text" (nth 4 tree-entry-search-text)
      "tsep_label" (nth 0 tree-settings-entry-p)
      "tsep_user" (nth 1 tree-settings-entry-p)
      "tsep_custom" (nth 2 tree-settings-entry-p)
      "tsep_model" (nth 3 tree-settings-entry-p)
      "tsep_think" (nth 4 tree-settings-entry-p)
      "tsep_session" (nth 5 tree-settings-entry-p)
      "tnd_hello" (nth 0 tree-normalize-display-text)
      "tnd_spaced" (nth 1 tree-normalize-display-text)
      "tnd_newline" (nth 2 tree-normalize-display-text)
      "tnd_empty" (nth 3 tree-normalize-display-text)
      "tnd_ws" (nth 4 tree-normalize-display-text)
      "tsl_empty" (nth 0 tree-status-labels)
      "tsl_notools" (nth 1 tree-status-labels)
      "tsl_user" (nth 2 tree-status-labels)
      "tsl_labeled" (nth 3 tree-status-labels)
      "tsl_all" (nth 4 tree-status-labels)
      "tsl_time" (nth 5 tree-status-labels)
      "tsl_both" (nth 6 tree-status-labels)
      "tsp_home" (nth 0 tree-shorten-path)
      "tsp_prefix" (nth 1 tree-shorten-path)
      "tsp_abs" (nth 2 tree-shorten-path)
      "tsp_proj" (nth 3 tree-shorten-path)
      "tsp_empty" (nth 4 tree-shorten-path)
      "tfp_root" (nth 0 tree-foldable-p)
      "tfp_leaf" (nth 1 tree-foldable-p)
      "tfp_only_child" (nth 2 tree-foldable-p)
      "tfp_branch" (nth 3 tree-foldable-p)
      "tta_path" (nth 0 tree-tool-argument)
      "tta_file" (nth 1 tree-tool-argument)
      "tta_prio" (nth 2 tree-tool-argument)
      "tta_miss" (nth 3 tree-tool-argument)
      "tta_nil" (nth 4 tree-tool-argument)
      "tcf_def_fwd" (nth 0 tree-cycle-filter)
      "tcf_nt_back" (nth 1 tree-cycle-filter)
      "tcf_all_fwd" (nth 2 tree-cycle-filter)
      "tcf_user_fwd" (nth 3 tree-cycle-filter)
      "09:07" (nth 0 tree-format-label-timestamp)
      "3/28 14:32" (nth 1 tree-format-label-timestamp)
      "25/12/31 23:59" (nth 2 tree-format-label-timestamp)
      "07:30" (nth 3 tree-format-label-timestamp)
      "not-a-date" (nth 4 tree-format-label-timestamp)
      "tis_afternoon" (nth 0 tree-iso-timestamp)
      "tis_epoch" (nth 1 tree-iso-timestamp)
      "tis_eoy" (nth 2 tree-iso-timestamp)
      "tis_midnight" (nth 3 tree-iso-timestamp)
      "tis_noon" (nth 4 tree-iso-timestamp)
      "tfc_read" (nth 0 tree-format-tool-call)
      "tfc_read_rng" (nth 1 tree-format-tool-call)
      "tfc_read_off" (nth 2 tree-format-tool-call)
      "tfc_write" (nth 3 tree-format-tool-call)
      "tfc_edit" (nth 4 tree-format-tool-call)
      "tfc_bash" (nth 5 tree-format-tool-call)
      "tfc_bash_long" (nth 6 tree-format-tool-call)
      "tfc_grep" (nth 7 tree-format-tool-call)
      "tfc_find" (nth 8 tree-format-tool-call)
      "tfc_ls" (nth 9 tree-format-tool-call)
      "tfc_custom" (nth 10 tree-format-tool-call)
      "ted_user" (nth 0 tree-entry-display-text)
      "ted_asst" (nth 1 tree-entry-display-text)
      "ted_empty" (nth 2 tree-entry-display-text)
      "ted_abort" (nth 3 tree-entry-display-text)
      "ted_bash" (nth 4 tree-entry-display-text)
      "ted_compact" (nth 5 tree-entry-display-text)
      "ted_branch" (nth 6 tree-entry-display-text)
      "ted_label" (nth 7 tree-entry-display-text)
      "ted_tool" (nth 8 tree-entry-display-text)
      "ted_custom" (nth 9 tree-entry-display-text)
      "ted_sel" (nth 10 tree-entry-display-text)
      "tp_branch" (nth 0 tree-prefix)
      "tp_last" (nth 1 tree-prefix)
      "tp_open" (nth 2 tree-prefix)
      "tp_fold" (nth 3 tree-prefix)
      "tp_gutter" (nth 4 tree-prefix)
      "tp_deep" (nth 5 tree-prefix)
      "tp_vroot" (nth 6 tree-prefix)
      "tvn_single" (nth 0 tree-visual-nodes)
      "tvn_branch" (nth 1 tree-visual-nodes)
      "tvn_multi" (nth 2 tree-visual-nodes)
      "tvn_chain" (nth 3 tree-visual-nodes)
      "tvn_deep" (nth 4 tree-visual-nodes)
      "thv_short" (nth 0 tree-horizontal-viewport)
      "thv_scroll" (nth 1 tree-horizontal-viewport)
      "thv_narrow" (nth 2 tree-horizontal-viewport)
      "thv_noselect" (nth 3 tree-horizontal-viewport)
      "thv_ansi" (nth 4 tree-horizontal-viewport)
      "thk_move" (nth 0 tree-help-keys)
      "thk_page" (nth 1 tree-help-keys)
      "thk_branch" (nth 2 tree-help-keys)
      "thk_copy" (nth 3 tree-help-keys)
      "thk_filters" (nth 4 tree-help-keys)
      "thk_cycle" (nth 5 tree-help-keys)
      "thk_custom" (nth 6 tree-help-keys)
      "thkey_up" (nth 0 tree-help-key)
      "thkey_fold" (nth 1 tree-help-key)
      "thkey_filter_all" (nth 2 tree-help-key)
      "thkey_left" (nth 3 tree-help-key)
      "thkey_custom_up" (nth 4 tree-help-key)
      "thkey_missing" (nth 5 tree-help-key)
      "tapk_copy_hit" (nth 0 tree-app-key-p)
      "tapk_copy_miss" (nth 1 tree-app-key-p)
      "tapk_up_hit" (nth 2 tree-app-key-p)
      "tapk_filter_hit" (nth 3 tree-app-key-p)
      "tapk_csi_up" (nth 4 tree-app-key-p)
      "tapk_garbage" (nth 5 tree-app-key-p)
      "thl_w80" (nth 0 tree-help-lines)
      "thl_w50" (nth 1 tree-help-lines)
      "thl_w30" (nth 2 tree-help-lines)
      "thl_w20" (nth 3 tree-help-lines)
      "thl_w12" (nth 4 tree-help-lines)
      "tap_leaf" (nth 0 tree-active-path)
      "tap_mid" (nth 1 tree-active-path)
      "tap_root" (nth 2 tree-active-path)
      "tap_nil" (nth 3 tree-active-path)
      "tap_missing" (nth 4 tree-active-path)
      "tnvi_hit" (nth 0 tree-nearest-visible-id)
      "tnvi_ancestor" (nth 1 tree-nearest-visible-id)
      "tnvi_branch" (nth 2 tree-nearest-visible-id)
      "tnvi_fallback" (nth 3 tree-nearest-visible-id)
      "tnvi_missing" (nth 4 tree-nearest-visible-id)
      "tnvi_nil" (nth 5 tree-nearest-visible-id)
      "tpa_leaf_a" (nth 0 tree-prioritize-active)
      "tpa_leaf_b" (nth 1 tree-prioritize-active)
      "tpa_root" (nth 2 tree-prioritize-active)
      "tpa_nil" (nth 3 tree-prioritize-active)
      "tem_branching" (nth 0 tree-entry-map)
      "tem_filter" (nth 1 tree-entry-map)
      "tem_empty" (nth 2 tree-entry-map)
      "tem_solo" (nth 3 tree-entry-map)
      "tem_single" (nth 4 tree-entry-map)
      "toe_leaf_a" (nth 0 tree-order-entries)
      "toe_leaf_b" (nth 1 tree-order-entries)
      "toe_root" (nth 2 tree-order-entries)
      "toe_nil" (nth 3 tree-order-entries)
      "toe_filter" (nth 4 tree-order-entries)
      "trvm_full" (nth 0 tree-rebuild-visible-maps)
      "trvm_sparse" (nth 1 tree-rebuild-visible-maps)
      "trvm_branch_b" (nth 2 tree-rebuild-visible-maps)
      "trvm_single" (nth 3 tree-rebuild-visible-maps)
      "trvm_siblings" (nth 4 tree-rebuild-visible-maps)
      "taf_default" (nth 0 tree-apply-filter)
      "taf_user_only" (nth 1 tree-apply-filter)
      "taf_no_tools" (nth 2 tree-apply-filter)
      "taf_query" (nth 3 tree-apply-filter)
      "taf_fold" (nth 4 tree-apply-filter)
      "taf_reselect" (nth 5 tree-apply-filter)
      "trl_wide" (nth 0 tree-render-lines)
      "trl_mid" (nth 1 tree-render-lines)
      "trl_narrow" (nth 2 tree-render-lines)
      "trl_fold" (nth 3 tree-render-lines)
      "trl_empty" (nth 4 tree-render-lines)
      "trl_short" (nth 5 tree-render-lines)
      "tm_down" (nth 0 tree-move)
      "tm_up" (nth 1 tree-move)
      "tm_wrap_up" (nth 2 tree-move)
      "tm_wrap_down" (nth 3 tree-move)
      "tm_page" (nth 4 tree-move)
      "tm_page_neg" (nth 5 tree-move)
      "tm_empty" (nth 6 tree-move)
      "tfo_fold" (nth 0 tree-fold-or-up)
      "tfo_leaf" (nth 1 tree-fold-or-up)
      "tfo_mid" (nth 2 tree-fold-or-up)
      "tfo_prefold" (nth 3 tree-fold-or-up)
      "tfo_root" (nth 4 tree-fold-or-up)
      "tfo_branch_b" (nth 5 tree-fold-or-up)
      "tuod_unfold" (nth 0 tree-unfold-or-down)
      "tuod_leaf" (nth 1 tree-unfold-or-down)
      "tuod_mid" (nth 2 tree-unfold-or-down)
      "tuod_prefold" (nth 3 tree-unfold-or-down)
      "tuod_root" (nth 4 tree-unfold-or-down)
      "tuod_branch_b" (nth 5 tree-unfold-or-down)
      "tbs_down_branch" (nth 0 tree-branch-segment-id)
      "tbs_down_leaf" (nth 1 tree-branch-segment-id)
      "tbs_down_mid" (nth 2 tree-branch-segment-id)
      "tbs_up_mid" (nth 3 tree-branch-segment-id)
      "tbs_up_root" (nth 4 tree-branch-segment-id)
      "tbs_up_branch_b" (nth 5 tree-branch-segment-id)
      "tsq_empty" (nth 0 tree-set-query)
      "tsq_branch" (nth 1 tree-set-query)
      "tsq_fold_clear" (nth 2 tree-set-query)
      "tsq_miss" (nth 3 tree-set-query)
      "tsq_pinned" (nth 4 tree-set-query)
      "tsq_multi" (nth 5 tree-set-query)
      "tsf_default" (nth 0 tree-set-filter)
      "tsf_user_only" (nth 1 tree-set-filter)
      "tsf_no_tools" (nth 2 tree-set-filter)
      "tsf_fold_clear" (nth 3 tree-set-filter)
      "tsf_labeled_only" (nth 4 tree-set-filter)
      "tsf_reselect" (nth 5 tree-set-filter)
      "tcs_user" (nth 0 tree-copy-selected)
      "tcs_assistant" (nth 1 tree-copy-selected)
      "tcs_tool" (nth 2 tree-copy-selected)
      "tcs_empty" (nth 3 tree-copy-selected)
      "tcs_label" (nth 4 tree-copy-selected)
      "tcs_none" (nth 5 tree-copy-selected)
      "ttlt_off" (nth 0 tree-toggle-label-timestamps)
      "ttlt_on" (nth 1 tree-toggle-label-timestamps)
      "ttlt_twice" (nth 2 tree-toggle-label-timestamps)
      "ttlt_notools" (nth 3 tree-toggle-label-timestamps)
      "ttlt_labeled" (nth 4 tree-toggle-label-timestamps)
      "ttlt_thrice" (nth 5 tree-toggle-label-timestamps)
      "tsle_pinned" (nth 0 tree-start-label-edit)
      "tsle_plain" (nth 1 tree-start-label-edit)
      "tsle_assistant" (nth 2 tree-start-label-edit)
      "tsle_bookmark" (nth 3 tree-start-label-edit)
      "tsle_empty" (nth 4 tree-start-label-edit)
      "tsle_noselect" (nth 5 tree-start-label-edit)
      "tclf_set" (nth 0 tree-confirm-label)
      "tclf_rename" (nth 1 tree-confirm-label)
      "tclf_clear" (nth 2 tree-confirm-label)
      "tclf_trim" (nth 3 tree-confirm-label)
      "tclf_whitespace" (nth 4 tree-confirm-label)
      "tclf_nop" (nth 5 tree-confirm-label)
      "tclc_pinned" (nth 0 tree-cancel-label)
      "tclc_plain" (nth 1 tree-cancel-label)
      "tclc_assistant" (nth 2 tree-cancel-label)
      "tclc_bookmark" (nth 3 tree-cancel-label)
      "tclc_dirty" (nth 4 tree-cancel-label)
      "tclc_nop" (nth 5 tree-cancel-label)
      "thri_copy" (nth 0 tree-handle-raw-input)
      "thri_edit" (nth 1 tree-handle-raw-input)
      "thri_fold" (nth 2 tree-handle-raw-input)
      "thri_notools" (nth 3 tree-handle-raw-input)
      "thri_lcancel" (nth 4 tree-handle-raw-input)
      "thri_nop" (nth 5 tree-handle-raw-input)
      "the_down" (nth 0 tree-handle-event)
      "the_up" (nth 1 tree-handle-event)
      "the_enter" (nth 2 tree-handle-event)
      "the_text" (nth 3 tree-handle-event)
      "the_esc_clear" (nth 4 tree-handle-event)
      "the_nop" (nth 5 tree-handle-event)
      "thle_text" (nth 0 tree-handle-label-event)
      "thle_bs" (nth 1 tree-handle-label-event)
      "thle_enter" (nth 2 tree-handle-label-event)
      "thle_escape" (nth 3 tree-handle-label-event)
      "thle_nop" (nth 4 tree-handle-label-event)
      "tse_pinned" (nth 0 tree-selected-entry)
      "tse_plain" (nth 1 tree-selected-entry)
      "tse_assistant" (nth 2 tree-selected-entry)
      "tse_label" (nth 3 tree-selected-entry)
      "tse_empty" (nth 4 tree-selected-entry)
      "tse_noselect" (nth 5 tree-selected-entry)
      "tslid_pinned" (nth 0 tree-selected-id)
      "tslid_plain" (nth 1 tree-selected-id)
      "tslid_assistant" (nth 2 tree-selected-id)
      "tslid_label" (nth 3 tree-selected-id)
      "tslid_empty" (nth 4 tree-selected-id)
      "tslid_noselect" (nth 5 tree-selected-id)
      "tsid_hit" (nth 0 tree-select-id)
      "tsid_same" (nth 1 tree-select-id)
      "tsid_miss" (nth 2 tree-select-id)
      "tsid_label" (nth 3 tree-select-id)
      "tsid_filter_miss" (nth 4 tree-select-id)
      "tsid_fold_miss" (nth 5 tree-select-id)
      "tvi_default" (nth 0 tree-visible-ids)
      "tvi_user_only" (nth 1 tree-visible-ids)
      "tvi_no_tools" (nth 2 tree-visible-ids)
      "tvi_query" (nth 3 tree-visible-ids)
      "tvi_fold" (nth 4 tree-visible-ids)
      "tvi_all" (nth 5 tree-visible-ids)
      "pto_child" (nth 0 project-trust-options)
      "pto_single" (nth 1 project-trust-options)
      "tss_child_trust" (nth 0 trust-selector-selection)
      "tss_child_parent" (nth 1 trust-selector-selection)
      "tss_child_distrust" (nth 2 trust-selector-selection)
      "tss_single_trust" (nth 3 trust-selector-selection)
      "tss_single_distrust" (nth 4 trust-selector-selection)
      "tdd_none" (nth 0 trust-decision-description)
      "tdd_child_local" (nth 1 trust-decision-description)
      "tdd_child_inherited" (nth 2 trust-decision-description)
      "tdd_single_untrusted" (nth 3 trust-decision-description)
      "tsm_child_down" (nth 0 trust-selector-move)
      "tsm_child_up" (nth 1 trust-selector-move)
      "tsm_child_wrap_up" (nth 2 trust-selector-move)
      "tsm_child_wrap_down" (nth 3 trust-selector-move)
      "tsm_child_page" (nth 4 trust-selector-move)
      "tsm_single_down" (nth 5 trust-selector-move)
      "tsm_single_wrap" (nth 6 trust-selector-move)
      "tshe_child_down" (nth 0 trust-selector-handle-event)
      "tshe_child_up" (nth 1 trust-selector-handle-event)
      "tshe_child_enter" (nth 2 trust-selector-handle-event)
      "tshe_child_k" (nth 3 trust-selector-handle-event)
      "tshe_child_bad" (nth 4 trust-selector-handle-event)
      "tshe_child_esc" (nth 5 trust-selector-handle-event)
      "tshe_child_nop" (nth 6 trust-selector-handle-event)
      "tshri_child_down" (nth 0 trust-selector-handle-raw-input)
      "tshri_child_k" (nth 1 trust-selector-handle-raw-input)
      "tshri_child_enter" (nth 2 trust-selector-handle-raw-input)
      "tshri_child_esc" (nth 3 trust-selector-handle-raw-input)
      "tshri_child_bad" (nth 4 trust-selector-handle-raw-input)
      "tshri_child_j" (nth 5 trust-selector-handle-raw-input)
      "tshri_child_confirm" (nth 6 trust-selector-handle-raw-input)
      "rts_child_default" (nth 0 trust-selector-ui-state)
      "rts_child_saved" (nth 1 trust-selector-ui-state)
      "rts_child_inherited" (nth 2 trust-selector-ui-state)
      "rts_child_distrust" (nth 3 trust-selector-ui-state)
      "rts_single" (nth 4 trust-selector-ui-state)
      "oosl_none" (nth 0 oauth-option-status-label)
      "oosl_api_mismatch" (nth 1 oauth-option-status-label)
      "oosl_oauth_mismatch" (nth 2 oauth-option-status-label)
      "oosl_oauth_configured" (nth 3 oauth-option-status-label)
      "oosl_stored" (nth 4 oauth-option-status-label)
      "oosl_env" (nth 5 oauth-option-status-label)
      "oosl_custom" (nth 6 oauth-option-status-label)
      "oosr_none" (nth 0 oauth-option-status-rendered)
      "oosr_api_mismatch" (nth 1 oauth-option-status-rendered)
      "oosr_oauth_mismatch" (nth 2 oauth-option-status-rendered)
      "oosr_oauth_configured" (nth 3 oauth-option-status-rendered)
      "oosr_stored" (nth 4 oauth-option-status-rendered)
      "oosr_env" (nth 5 oauth-option-status-rendered)
      "oosr_custom" (nth 6 oauth-option-status-rendered)
      "ceat_oauth" (nth 0 credential-entry-auth-type)
      "ceat_api_key" (nth 1 credential-entry-auth-type)
      "ceat_api_key_hyphen" (nth 2 credential-entry-auth-type)
      "ceat_oauth_sym" (nth 3 credential-entry-auth-type)
      "ceat_api_key_sym" (nth 4 credential-entry-auth-type)
      "ceat_oauth_mixed" (nth 5 credential-entry-auth-type)
      "ceat_api_key_upper" (nth 6 credential-entry-auth-type)
      "oesp_nil" (nth 0 oauth-environment-source-p)
      "oesp_oauth" (nth 1 oauth-environment-source-p)
      "oesp_single_env" (nth 2 oauth-environment-source-p)
      "oesp_multi_env" (nth 3 oauth-environment-source-p)
      "oesp_runtime" (nth 4 oauth-environment-source-p)
      "oesp_stored" (nth 5 oauth-environment-source-p)
      "oesp_lower" (nth 6 oauth-environment-source-p)
      "oss_first" (nth 0 oauth-selector-selection)
      "oss_second" (nth 1 oauth-selector-selection)
      "oss_third" (nth 2 oauth-selector-selection)
      "oss_filter_hit" (nth 3 oauth-selector-selection)
      "oss_filter_miss" (nth 4 oauth-selector-selection)
      "osaf_all" (nth 0 oauth-selector-apply-filter)
      "osaf_open" (nth 1 oauth-selector-apply-filter)
      "osaf_miss" (nth 2 oauth-selector-apply-filter)
      "osaf_anth" (nth 3 oauth-selector-apply-filter)
      "osaf_google" (nth 4 oauth-selector-apply-filter)
      "oshe_down" (nth 0 oauth-selector-handle-event)
      "oshe_up" (nth 1 oauth-selector-handle-event)
      "oshe_enter" (nth 2 oauth-selector-handle-event)
      "oshe_esc" (nth 3 oauth-selector-handle-event)
      "oshe_text" (nth 4 oauth-selector-handle-event)
      "oshe_backspace" (nth 5 oauth-selector-handle-event)
      "oshri_down" (nth 0 oauth-selector-handle-raw-input)
      "oshri_j" (nth 1 oauth-selector-handle-raw-input)
      "oshri_enter" (nth 2 oauth-selector-handle-raw-input)
      "oshri_esc" (nth 3 oauth-selector-handle-raw-input)
      "oshri_bad" (nth 4 oauth-selector-handle-raw-input)
      "oshri_o" (nth 5 oauth-selector-handle-raw-input)
      "oshri_confirm" (nth 6 oauth-selector-handle-raw-input)
      "osst_oauth" (nth 0 oauth-selector-search-text)
      "osst_api" (nth 1 oauth-selector-search-text)
      "osst_no_method" (nth 2 oauth-selector-search-text)
      "osst_api_plain" (nth 3 oauth-selector-search-text)
      "latr_none" (nth 0 login-auth-type-route)
      "latr_oauth" (nth 1 login-auth-type-route)
      "latr_api" (nth 2 login-auth-type-route)
      "latr_both" (nth 3 login-auth-type-route)
      "latr_generic" (nth 4 login-auth-type-route)
      "lpo_all" (nth 0 login-provider-options)
      "lpo_oauth" (nth 1 login-provider-options)
      "lpo_api" (nth 2 login-provider-options)
      "lpo_labeled" (nth 3 login-provider-options)
      "lpo_status" (nth 4 login-provider-options)
      "lgo_empty" (nth 0 logout-provider-options)
      "lgo_mixed" (nth 1 logout-provider-options)
      "lgo_unknown" (nth 2 logout-provider-options)
      "lgo_sorted" (nth 3 logout-provider-options)
      "lmhe_down" (nth 0 login-method-selector-handle-event)
      "lmhe_up" (nth 1 login-method-selector-handle-event)
      "lmhe_enter_oauth" (nth 2 login-method-selector-handle-event)
      "lmhe_enter_api" (nth 3 login-method-selector-handle-event)
      "lmhe_esc" (nth 4 login-method-selector-handle-event)
      "lmhe_clear" (nth 5 login-method-selector-handle-event)
      "lmhe_interrupt" (nth 6 login-method-selector-handle-event)
      "osmv_0_1" (nth 0 oauth-selector-move)
      "osmv_2_m1" (nth 1 oauth-selector-move)
      "osmv_1_1" (nth 2 oauth-selector-move)
      "osmv_1_m1" (nth 3 oauth-selector-move)
      "osmv_filter" (nth 4 oauth-selector-move)
      "akhe_esc" (nth 0 api-key-input-state-handle-event)
      "akhe_clear" (nth 1 api-key-input-state-handle-event)
      "akhe_text" (nth 2 api-key-input-state-handle-event)
      "akhe_bs" (nth 3 api-key-input-state-handle-event)
      "akhe_enter_empty" (nth 4 api-key-input-state-handle-event)
      "akhe_enter_key" (nth 5 api-key-input-state-handle-event)
      "akhe_interrupt" (nth 6 api-key-input-state-handle-event)
      "lmsui_default" (nth 0 login-method-selector-ui-state)
      "lmsui_sel1" (nth 1 login-method-selector-ui-state)
      "lmsui_title" (nth 2 login-method-selector-ui-state)
      "lmsui_narrow" (nth 3 login-method-selector-ui-state)
      "lmsui_mid" (nth 4 login-method-selector-ui-state))
     "session_search"
     (collect "cli_selectors.session_search"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-session-search))))
     "key_text"
     (collect "cli_selectors.key_text"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-key-text))))
     "fuzzy_filter"
     (collect "cli_selectors.fuzzy_filter"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-fuzzy-filter))))
     "delete_query"
     (collect "cli_selectors.delete_query"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-delete-query))))
     "visible_slice"
     (collect "cli_selectors.visible_slice"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-visible-slice))))
     "move_index"
     (collect "cli_selectors.move_index"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-move-index))))
     "align_left_right"
     (collect "cli_selectors.align_left_right"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-align-left-right))))
     "fit_line"
     (collect "cli_selectors.fit_line"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-fit-line))))
     "border_line"
     (collect "cli_selectors.border_line"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-border-line))))
     "selected_line"
     (collect "cli_selectors.selected_line"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-selected-line))))
     "muted_line"
     (collect "cli_selectors.muted_line"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-muted-line))))
     "dim_line"
     (collect "cli_selectors.dim_line"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-dim-line))))
     "modified_cursor_key"
     (collect "cli_selectors.modified_cursor_key"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-modified-cursor-key))))
     "title_line"
     (collect "cli_selectors.title_line"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-title-line))))
     "overlay_title_line"
     (collect "cli_selectors.overlay_title_line"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-overlay-title-line))))
     "input_line"
     (collect "cli_selectors.input_line"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-input-line))))
     "keybinding_text"
     (collect "cli_selectors.keybinding_text"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-keybinding-text))))
     "keybinding_hint"
     (collect "cli_selectors.keybinding_hint"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-keybinding-hint))))
     "session_format_age"
     (collect "cli_selectors.session_format_age"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-session-format-age))))
     "session_record_label"
     (collect "cli_selectors.session_record_label"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-session-record-label))))
     "session_shorten_path"
     (collect "cli_selectors.session_shorten_path"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-session-shorten-path))))
     "session_quoted_search"
     (collect "cli_selectors.session_quoted_search"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-session-quoted-search))))
     "session_thread_records"
     (collect "cli_selectors.session_thread_records"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-session-thread-records))))
     "session_binding_label"
     (collect "cli_selectors.session_binding_label"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-session-binding-label))))
     "session_same_path"
     (collect "cli_selectors.session_same_path"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-session-same-path))))
     "session_quoted_p"
     (collect "cli_selectors.session_quoted_p"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-session-quoted-p))))
     "session_named_p"
     (collect "cli_selectors.session_named_p"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-session-named-p))))
     "settings_thinking_description"
     (collect "cli_selectors.settings_thinking_description"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-settings-thinking-description))))
     "settings_display_value"
     (collect "cli_selectors.settings_display_value"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-settings-display-value))))
     "settings_automatic_theme_setting"
     (collect "cli_selectors.settings_automatic_theme_setting"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-settings-automatic-theme-setting))))
     "settings_active_automatic_theme"
     (collect "cli_selectors.settings_active_automatic_theme"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-settings-active-automatic-theme))))
     "settings_cycle"
     (collect "cli_selectors.settings_cycle"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-settings-cycle))))
     "settings_apply_filter"
     (collect "cli_selectors.settings_apply_filter"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-settings-apply-filter))))
     "tree_entry_filtered"
     (collect "cli_selectors.tree_entry_filtered"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-entry-filtered))))
     "tree_query_matches"
     (collect "cli_selectors.tree_query_matches"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-query-matches))))
     "tree_entry_search_text"
     (collect "cli_selectors.tree_entry_search_text"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-entry-search-text))))
     "tree_settings_entry_p"
     (collect "cli_selectors.tree_settings_entry_p"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-settings-entry-p))))
     "tree_normalize_display_text"
     (collect "cli_selectors.tree_normalize_display_text"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-normalize-display-text))))
     "tree_status_labels"
     (collect "cli_selectors.tree_status_labels"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-status-labels))))
     "tree_shorten_path"
     (collect "cli_selectors.tree_shorten_path"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-shorten-path))))
     "tree_foldable_p"
     (collect "cli_selectors.tree_foldable_p"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-foldable-p))))
     "tree_tool_argument"
     (collect "cli_selectors.tree_tool_argument"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-tool-argument))))
     "tree_cycle_filter"
     (collect "cli_selectors.tree_cycle_filter"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-cycle-filter))))
     "tree_format_label_timestamp"
     (collect "cli_selectors.tree_format_label_timestamp"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-format-label-timestamp))))
     "tree_iso_timestamp"
     (collect "cli_selectors.tree_iso_timestamp"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-iso-timestamp))))
     "tree_format_tool_call"
     (collect "cli_selectors.tree_format_tool_call"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-format-tool-call))))
     "tree_entry_display_text"
     (collect "cli_selectors.tree_entry_display_text"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-entry-display-text))))
     "tree_prefix"
     (collect "cli_selectors.tree_prefix"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-prefix))))
     "tree_visual_nodes"
     (collect "cli_selectors.tree_visual_nodes"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-visual-nodes))))
     "tree_horizontal_viewport"
     (collect "cli_selectors.tree_horizontal_viewport"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-horizontal-viewport))))
     "tree_help_keys"
     (collect "cli_selectors.tree_help_keys"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-help-keys))))
     "tree_help_key"
     (collect "cli_selectors.tree_help_key"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-help-key))))
     "tree_app_key_p"
     (collect "cli_selectors.tree_app_key_p"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-app-key-p))))
     "tree_help_lines"
     (collect "cli_selectors.tree_help_lines"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-help-lines))))
     "tree_active_path"
     (collect "cli_selectors.tree_active_path"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-active-path))))
     "tree_nearest_visible_id"
     (collect "cli_selectors.tree_nearest_visible_id"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-nearest-visible-id))))
     "tree_prioritize_active"
     (collect "cli_selectors.tree_prioritize_active"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-prioritize-active))))
     "tree_entry_map"
     (collect "cli_selectors.tree_entry_map"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-entry-map))))
     "tree_order_entries"
     (collect "cli_selectors.tree_order_entries"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-order-entries))))
     "tree_rebuild_visible_maps"
     (collect "cli_selectors.tree_rebuild_visible_maps"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-rebuild-visible-maps))))
     "tree_apply_filter"
     (collect "cli_selectors.tree_apply_filter"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-apply-filter))))
     "tree_render_lines"
     (collect "cli_selectors.tree_render_lines"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-render-lines))))
     "tree_move"
     (collect "cli_selectors.tree_move"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-move))))
     "tree_fold_or_up"
     (collect "cli_selectors.tree_fold_or_up"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-fold-or-up))))
     "tree_unfold_or_down"
     (collect "cli_selectors.tree_unfold_or_down"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-unfold-or-down))))
     "tree_branch_segment_id"
     (collect "cli_selectors.tree_branch_segment_id"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-branch-segment-id))))
     "tree_set_query"
     (collect "cli_selectors.tree_set_query"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-set-query))))
     "tree_set_filter"
     (collect "cli_selectors.tree_set_filter"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-set-filter))))
     "tree_copy_selected"
     (collect "cli_selectors.tree_copy_selected"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-copy-selected))))
     "tree_toggle_label_timestamps"
     (collect "cli_selectors.tree_toggle_label_timestamps"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-toggle-label-timestamps))))
     "tree_start_label_edit"
     (collect "cli_selectors.tree_start_label_edit"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-start-label-edit))))
     "tree_confirm_label"
     (collect "cli_selectors.tree_confirm_label"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-confirm-label))))
     "tree_cancel_label"
     (collect "cli_selectors.tree_cancel_label"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-cancel-label))))
     "tree_handle_raw_input"
     (collect "cli_selectors.tree_handle_raw_input"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-handle-raw-input))))
     "tree_handle_event"
     (collect "cli_selectors.tree_handle_event"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-handle-event))))
     "tree_handle_label_event"
     (collect "cli_selectors.tree_handle_label_event"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-handle-label-event))))
     "tree_selected_entry"
     (collect "cli_selectors.tree_selected_entry"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-selected-entry))))
     "tree_selected_id"
     (collect "cli_selectors.tree_selected_id"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-selected-id))))
     "tree_select_id"
     (collect "cli_selectors.tree_select_id"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-select-id))))
     "tree_visible_ids"
     (collect "cli_selectors.tree_visible_ids"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-tree-visible-ids))))
     "project_trust_options"
     (collect "cli_selectors.project_trust_options"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-project-trust-options))))
     "trust_selector_selection"
     (collect "cli_selectors.trust_selector_selection"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-trust-selector-selection))))
     "trust_decision_description"
     (collect "cli_selectors.trust_decision_description"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-trust-decision-description))))
     "trust_selector_move"
     (collect "cli_selectors.trust_selector_move"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-trust-selector-move))))
     "trust_selector_handle_event"
     (collect "cli_selectors.trust_selector_handle_event"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-trust-selector-handle-event))))
     "trust_selector_handle_raw_input"
     (collect "cli_selectors.trust_selector_handle_raw_input"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-trust-selector-handle-raw-input))))
     "trust_selector_ui_state"
     (collect "cli_selectors.trust_selector_ui_state"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-trust-selector-ui-state))))
     "oauth_option_status_label"
     (collect "cli_selectors.oauth_option_status_label"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-oauth-option-status-label))))
     "oauth_option_status_rendered"
     (collect "cli_selectors.oauth_option_status_rendered"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-oauth-option-status-rendered))))
     "credential_entry_auth_type"
     (collect "cli_selectors.credential_entry_auth_type"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-credential-entry-auth-type))))
     "oauth_environment_source_p"
     (collect "cli_selectors.oauth_environment_source_p"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-oauth-environment-source-p))))
     "oauth_selector_selection"
     (collect "cli_selectors.oauth_selector_selection"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-oauth-selector-selection))))
     "oauth_selector_apply_filter"
     (collect "cli_selectors.oauth_selector_apply_filter"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-oauth-selector-apply-filter))))
     "oauth_selector_handle_event"
     (collect "cli_selectors.oauth_selector_handle_event"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-oauth-selector-handle-event))))
     "oauth_selector_handle_raw_input"
     (collect "cli_selectors.oauth_selector_handle_raw_input"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-oauth-selector-handle-raw-input))))
     "oauth_selector_search_text"
     (collect "cli_selectors.oauth_selector_search_text"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-oauth-selector-search-text))))
     "login_auth_type_route"
     (collect "cli_selectors.login_auth_type_route"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-login-auth-type-route))))
     "login_provider_options"
     (collect "cli_selectors.login_provider_options"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-login-provider-options))))
     "logout_provider_options"
     (collect "cli_selectors.logout_provider_options"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-logout-provider-options))))
     "login_method_selector_handle_event"
     (collect "cli_selectors.login_method_selector_handle_event"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-login-method-selector-handle-event))))
     "oauth_selector_move"
     (collect "cli_selectors.oauth_selector_move"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-oauth-selector-move))))
     "api_key_input_state_handle_event"
     (collect "cli_selectors.api_key_input_state_handle_event"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-api-key-input-state-handle-event))))
     "login_method_selector_ui_state"
     (collect "cli_selectors.login_method_selector_ui_state"
              (lambda ()
                (lambda ()
                  (run-cli-selectors-login-method-selector-ui-state)))))))

(defun websocket-loopback-write-http (stream text)
  (write-sequence
   (babel:string-to-octets text :encoding :utf-8)
   stream)
  (finish-output stream))

(defun websocket-recorded-response-events ()
  (list
   (cadr-ai::json-object
    "type" "response.created"
    "response" (cadr-ai::json-object "id" "resp-1"))
   (cadr-ai::json-object
    "type" "response.output_item.added" "output_index" 0
    "item" (cadr-ai::json-object "type" "message"))
   (cadr-ai::json-object
    "type" "response.content_part.added"
    "part" (cadr-ai::json-object "type" "output_text" "text" ""))
   (cadr-ai::json-object
    "type" "response.output_text.delta" "output_index" 0
    "delta" "Hello")
   (cadr-ai::json-object
    "type" "response.output_item.done" "output_index" 0
    "item"
    (cadr-ai::json-object
     "type" "message" "id" "msg-resp-1"
     "content"
     (vector
      (cadr-ai::json-object "type" "output_text" "text" "Hello"))))
   (cadr-ai::json-object
    "type" "response.completed"
    "response"
    (cadr-ai::json-object
     "id" "resp-1" "status" "completed"
     "usage"
     (cadr-ai::json-object
      "input_tokens" 1 "output_tokens" 1
      "input_tokens_details"
      (cadr-ai::json-object "cached_tokens" 0))))))

(defun websocket-loopback-accept (listener)
  (let* ((client
           (usocket:socket-accept
            listener :element-type '(unsigned-byte 8)))
         (stream (usocket:socket-stream client))
         (key nil))
    (cadr-ai::read-http-line stream)
    (loop for line = (cadr-ai::read-http-line stream)
          until (or (null line) (zerop (length line)))
          when (uiop:string-prefix-p "Sec-WebSocket-Key:" line)
            do (setf key
                     (string-trim '(#\Space #\Tab)
                                  (subseq line (1+ (position #\: line))))))
    (websocket-loopback-write-http
     stream
     (format nil
             "HTTP/1.1 101 Switching Protocols~C~CUpgrade: websocket~C~CConnection: Upgrade~C~CSec-WebSocket-Accept: ~A~C~C~C~C"
             #\Return #\Linefeed #\Return #\Linefeed
             #\Return #\Linefeed
             (cadr-ai::websocket-accept-value key)
             #\Return #\Linefeed #\Return #\Linefeed))
    (values client stream)))

(defun websocket-loopback-write-events (stream)
  (dolist (event (websocket-recorded-response-events))
    (cadr-ai::write-websocket-frame
     stream #x1
     (babel:string-to-octets
      (cadr-ai::stringify-json event) :encoding :utf-8)
     :mask-p nil))
  (finish-output stream))

(defun websocket-stream-context ()
  (cadr-ai:make-context
   :system-prompt "You are a helpful assistant."
   :messages
   (list (cadr-ai:make-user-message :content "Say hello"))))

(defun run-websocket-stream (provider model context)
  (cadr-ai:close-openai-codex-websocket-sessions)
  (cadr-ai::stream-chat
   provider model context
   (lambda (event) (declare (ignore event)) nil)
   :transport :websocket))

(defun measure-websocket-stream ()
  (let* ((stop-p nil)
         (server-error nil)
         (listener
           (usocket:socket-listen
            "127.0.0.1" 0 :reuse-address t
            :element-type '(unsigned-byte 8)))
         (port (usocket:get-local-port listener))
         (server
           (sb-thread:make-thread
            (lambda ()
              (loop
                (when stop-p (return))
                (when (usocket:wait-for-input
                       listener :timeout 0.05 :ready-only t)
                  (handler-case
                      (multiple-value-bind (client stream)
                          (websocket-loopback-accept listener)
                        (unwind-protect
                             (progn
                               (cadr-ai::read-websocket-frame stream)
                               (websocket-loopback-write-events stream))
                          (ignore-errors (usocket:socket-close client))))
                    (error (condition)
                      (when stop-p (return))
                      (setf server-error condition)
                      (format *error-output*
                              "goal20 websocket loopback: ~A~%"
                              condition)
                      (finish-output *error-output*)
                      (return))))))
            :name "goal20-websocket-loopback"))
         (provider
           (cadr-ai:make-openai-codex-provider
            :oauth-access-token *codex-oauth-token*
            :oauth-account-id "goal20-codex-account"))
         (model
           (cadr-ai:make-model
            :id "gpt-5.5"
            :name "Goal 20 Codex WS"
            :api :openai-codex-responses
            :provider :openai-codex
            :base-url (format nil "http://127.0.0.1:~D" port)
            :max-tokens 4096))
         (context (websocket-stream-context)))
    (unwind-protect
         (let ((message (run-websocket-stream provider model context)))
           (unless (eq :stop (cadr-ai:assistant-message-stop-reason message))
             (error "websocket fixture stream produced stop reason ~S ~A"
                    (cadr-ai:assistant-message-stop-reason message)
                    (cadr-ai:assistant-message-error-message message)))
           (let* ((blocks (cadr-ai:assistant-message-content message))
                  (text
                    (apply #'concatenate 'string
                           (mapcar #'cadr-ai:text-content-text
                                   (remove-if-not
                                    (lambda (block)
                                      (typep block 'cadr-ai:text-content))
                                    blocks)))))
             (json-object
              "observed"
              (json-object
               "ws_text" text
               "stop_reason" "stop"
               "text_characters" (length text)
               "usage_input"
               (cadr-ai:usage-input
                (cadr-ai:assistant-message-usage message))
               "usage_output"
               (cadr-ai:usage-output
                (cadr-ai:assistant-message-usage message)))
              "stream_roundtrip"
              (collect "websocket_stream.stream_roundtrip"
                       (lambda ()
                         (lambda ()
                           (run-websocket-stream
                            provider model context)))))))
      (setf stop-p t)
      (ignore-errors (usocket:socket-close listener))
      (ignore-errors (sb-thread:join-thread server))
      (when server-error (error server-error)))))

(defun version-cmp-sign (left right)
  (let ((value (cadr-cli::compare-package-versions left right)))
    (cond
      ((plusp value) 1)
      ((minusp value) -1)
      (t 0))))

(defun run-cli-sdk-version-newer ()
  (list
   (version-cmp-sign "5.0.0-beta.20" "5.0.0-beta.9")
   (version-cmp-sign "1.2.3" "1.2.3")
   (version-cmp-sign "1.2.3" "1.3.0")
   (if (cadr-cli::newer-package-version-p "1.2.4" "1.2.3") 1 0)
   (if (cadr-cli::newer-package-version-p "1.2.3" "1.2.3") 1 0)))

(defun paired-cache-price (provider model)
  (declare (ignore provider model))
  0.3d0)

(defun paired-cache-assistant
    (&key (input 0) (cache-read 0) (cache-write 0)
       (cache-read-cost 0d0) (cache-write-cost 0d0)
       (model "test-model") (timestamp 0))
  (cadr-ai:make-assistant-message
   :content nil
   :api :anthropic-messages
   :provider :test
   :model model
   :usage
   (cadr-ai:make-usage
    :input input
    :output 10
    :cache-read cache-read
    :cache-write cache-write
    :cost
    (cadr-ai:make-cost
     :cache-read cache-read-cost
     :cache-write cache-write-cost))
   :stop-reason :stop
   :timestamp timestamp))

(defun cache-miss-shape (miss)
  (if miss
      (list
       (cadr-cli::cache-miss-missed-tokens miss)
       (cadr-cli::cache-miss-idle-milliseconds miss)
       (if (cadr-cli::cache-miss-model-changed-p miss) 1 0)
       1)
      (list 0 0 0 0)))

(defun run-cli-sdk-cache-miss ()
  (let* ((turn1
           (paired-cache-assistant
            :cache-write 100000
            :cache-write-cost 0.375d0
            :timestamp 0))
         (turn2
           (paired-cache-assistant
            :cache-read 100000
            :cache-write 5000
            :cache-read-cost 0.03d0
            :cache-write-cost 0.019d0
            :timestamp 60000))
         (prior (list turn1 turn2))
         (price #'paired-cache-price)
         (miss
           (cadr-cli::detect-cache-miss
            prior
            (paired-cache-assistant
             :cache-write 110000
             :cache-write-cost 0.4125d0
             :timestamp 600000)
            :model-price-function price))
         (switched
           (cadr-cli::detect-cache-miss
            prior
            (paired-cache-assistant
             :cache-write 110000
             :cache-write-cost 0.4125d0
             :model "other-model"
             :timestamp 120000)
            :model-price-function price))
         (healthy
           (cadr-cli::detect-cache-miss
            prior
            (paired-cache-assistant
             :cache-read 105000
             :cache-write 2000
             :cache-read-cost 0.0315d0
             :cache-write-cost 0.0075d0
             :timestamp 120000)
            :model-price-function price))
         (empty
           (cadr-cli::detect-cache-miss
            nil turn1 :model-price-function price)))
    (append
     (cache-miss-shape miss)
     (cache-miss-shape switched)
     (list (if healthy 1 0) (if empty 1 0)))))

(defun cache-waste-shape (waste)
  (list
   (cadr-cli::cache-waste-missed-tokens waste)
   (cadr-cli::cache-waste-miss-count waste)))

(defun run-cli-sdk-cache-waste ()
  (let* ((price #'paired-cache-price)
         (turn1
           (paired-cache-assistant
            :cache-write 100000
            :cache-write-cost 0.375d0
            :timestamp 0))
         (turn2
           (paired-cache-assistant
            :cache-read 100000
            :cache-write 5000
            :cache-read-cost 0.03d0
            :cache-write-cost 0.019d0
            :timestamp 60000))
         (turn3
           (paired-cache-assistant
            :cache-write 110000
            :cache-write-cost 0.4125d0
            :timestamp 120000))
         (after-reset
           (paired-cache-assistant
            :cache-write 20000
            :cache-write-cost 0.075d0
            :timestamp 180000))
         (switched
           (paired-cache-assistant
            :cache-write 100000
            :cache-write-cost 0.375d0
            :model "other-model"
            :timestamp 60000))
         (nocache-a
           (paired-cache-assistant :input 100000 :timestamp 0))
         (nocache-b
           (paired-cache-assistant :input 110000 :timestamp 60000))
         (miss
           (cadr-cli::compute-cache-waste
            (list turn1 turn2 turn3) :model-price-function price))
         (healthy
           (cadr-cli::compute-cache-waste
            (list turn1 turn2) :model-price-function price))
         (reset
           (cadr-cli::compute-cache-waste
            (list turn1 :compaction after-reset)
            :model-price-function price))
         (switched-waste
           (cadr-cli::compute-cache-waste
            (list turn1 switched) :model-price-function price))
         (nocache
           (cadr-cli::compute-cache-waste
            (list nocache-a nocache-b)
            :model-price-function price)))
    (append
     (cache-waste-shape miss)
     (cache-waste-shape healthy)
     (cache-waste-shape reset)
     (cache-waste-shape switched-waste)
     (cache-waste-shape nocache))))

(defun thinking-level-flag (value)
  (if (cadr-cli::valid-thinking-level-p value) 1 0))

(defun run-cli-sdk-thinking-level ()
  (list
   (thinking-level-flag "off")
   (thinking-level-flag "minimal")
   (thinking-level-flag "low")
   (thinking-level-flag "medium")
   (thinking-level-flag "high")
   (thinking-level-flag "xhigh")
   (thinking-level-flag "max")
   (thinking-level-flag "nope")))

(defparameter *sdk-session-list-id*
  "019f0000-0000-7000-8000-00000000cadr")

(defun rewrite-session-jsonl-cwd (source dest cwd)
  (let* ((text
           (uiop:read-file-string
            source :external-format :utf-8))
         (nl (position #\Newline text))
         (header
           (cadr-ai::parse-json (subseq text 0 nl))))
    (cadr-ai::json-put header "cwd" cwd)
    (ensure-directories-exist dest)
    (with-open-file (stream dest
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create
                            :external-format :utf-8)
      (write-string (cadr-ai::stringify-json header) stream)
      (write-string (subseq text nl) stream)))
  dest)

(defun stage-cli-sdk-session-list ()
  (let* ((cwd
           (namestring
            (truename
             (ensure-directories-exist
              (merge-pathnames
               "sdk-cwd/" *scratch-directory*)))))
         (directory
           (namestring
            (truename
             (ensure-directories-exist
              (merge-pathnames
               "sdk-sessions/" *scratch-directory*)))))
         (empty
           (namestring
            (truename
             (ensure-directories-exist
              (merge-pathnames
               "sdk-sessions-empty/" *scratch-directory*))))))
    (loop for index from 0 below 2
          do
          (rewrite-session-jsonl-cwd
           (fixture-path "session.jsonl")
           (merge-pathnames
            (format nil "sess-~D.jsonl" index)
            (uiop:ensure-directory-pathname directory))
           cwd))
    (list cwd directory empty)))

(defun run-cli-sdk-session-list ()
  (destructuring-bind (cwd directory empty)
      (stage-cli-sdk-session-list)
    (let ((listed
            (cadr-cli:session-manager-list cwd directory))
          (missing
            (cadr-cli:session-manager-list cwd empty)))
      (list
       (length listed)
       (if (find *sdk-session-list-id* listed
                 :key #'cadr-agent:session-id
                 :test #'string=)
           1
           0)
       (length missing)))))

(defparameter *cli-sdk-agent-session-model*
  (cadr-ai:make-model
   :id "dummy"
   :name "dummy"
   :provider :openai
   :api :openai-completions
   :context-window 128000
   :max-tokens 4096))

(defun stage-cli-sdk-agent-session ()
  (let* ((cwd
           (namestring
            (truename
             (ensure-directories-exist
              (merge-pathnames
               "sdk-agent-cwd/" *scratch-directory*)))))
         (agent
           (namestring
            (truename
             (ensure-directories-exist
              (merge-pathnames
               "sdk-agent-dir/" *scratch-directory*))))))
    (ensure-directories-exist
     (merge-pathnames ".cadr/" cwd))
    (ensure-directories-exist
     (merge-pathnames ".pi/" cwd))
    (list cwd agent)))

(defun run-cli-sdk-agent-session ()
  ;; Empty isolated cwd/agentDir, in-memory session, no-tools :all.
  ;; Do not exact fallback copy (cadr vs pi product strings) or
  ;; model catalog 39 vs 40. No socket.
  (destructuring-bind (cwd agent-dir)
      (stage-cli-sdk-agent-session)
    (let* ((settings (cadr-cli::make-memory-sdk-settings-manager))
           (loader
             (cadr-cli::make-sdk-resource-loader
              :cwd cwd
              :agent-directory agent-dir
              :settings-manager settings
              :no-extensions-p t
              :no-skills-p t
              :no-prompts-p t
              :no-themes-p t
              :no-context-files-p t))
           (runtime
             (cadr-cli::make-sdk-model-runtime
              :auth-path
              (merge-pathnames "auth.json" agent-dir)
              :models-path
              (merge-pathnames "models.json" agent-dir)))
           (manager (cadr-cli::session-manager-in-memory cwd))
           session)
      (cadr-cli::sdk-resource-loader-reload loader)
      (unwind-protect
           (multiple-value-bind (created extensions fallback)
               (cadr-cli::create-agent-session
                :cwd cwd
                :agent-directory agent-dir
                :settings-manager settings
                :resource-loader loader
                :model-runtime runtime
                :session-manager manager
                :model *cli-sdk-agent-session-model*
                :no-tools :all)
             (declare (ignore extensions))
             (setf session created)
             (list
              (if session 1 0)
              (if (cadr-agent:agent-model
                   (cadr-cli::agent-session-agent session))
                  1
                  0)
              (if (stringp fallback) 1 0)))
        (when session
          (cadr-cli::agent-session-dispose session))))))

(defun run-cli-sdk-session-services ()
  ;; Isolated cwd/agentDir. Do not exact diagnostics (pi also
  ;; refresh({allowNetwork:false}) + extension flag apply).
  (destructuring-bind (cwd agent-dir)
      (stage-cli-sdk-agent-session)
    (let* ((settings (cadr-cli::make-memory-sdk-settings-manager))
           (runtime
             (cadr-cli::make-sdk-model-runtime
              :auth-path
              (merge-pathnames "auth.json" agent-dir)
              :models-path
              (merge-pathnames "models.json" agent-dir)))
           (services
             (cadr-cli::create-agent-session-services
              :cwd cwd
              :agent-directory agent-dir
              :settings-manager settings
              :model-runtime runtime)))
      (list
       (if services 1 0)
       (if (string=
            (string-right-trim
             "/"
             (namestring
              (truename
               (cadr-cli::agent-session-services-cwd services))))
            (string-right-trim "/" (namestring (truename cwd))))
           1
           0)
       (if (cadr-cli::sdk-resource-loader-snapshot
            (cadr-cli::agent-session-services-resource-loader
             services))
           1
           0)))))

(defun sdk-model-runtime-has-provider-p (runtime id)
  (if (find
       id
       (mapcar
        #'cadr-ai:runtime-provider-id
        (cadr-cli::sdk-model-runtime-providers runtime)))
      1
      0))

(defun run-cli-sdk-model-runtime ()
  ;; Builtin catalog lookup only. Do not exact provider count
  ;; (cadr 40 vs pi 39). Isolated empty auth/models.
  (destructuring-bind (cwd agent-dir)
      (stage-cli-sdk-agent-session)
    (declare (ignore cwd))
    (let ((runtime
            (cadr-cli::make-sdk-model-runtime
             :auth-path
             (merge-pathnames "auth.json" agent-dir)
             :models-path
             (merge-pathnames "models.json" agent-dir))))
      (list
       (sdk-model-runtime-has-provider-p runtime :openai)
       (sdk-model-runtime-has-provider-p runtime :anthropic)
       (sdk-model-runtime-has-provider-p runtime :no-such-provider)
       (if (cadr-cli::sdk-model-runtime-model
            runtime :openai "gpt-4o-mini")
           1
           0)
       (if (cadr-cli::sdk-model-runtime-model
            runtime :openai "no-such")
           1
           0)))))

(defun measure-cli-sdk-version-newer ()
  (let ((observed (run-cli-sdk-version-newer))
        (cache (run-cli-sdk-cache-miss))
        (waste (run-cli-sdk-cache-waste))
        (thinking (run-cli-sdk-thinking-level))
        (sessions (run-cli-sdk-session-list))
        (agent (run-cli-sdk-agent-session))
        (services (run-cli-sdk-session-services))
        (models (run-cli-sdk-model-runtime)))
    (json-object
     "observed"
     (json-object
      "beta" (first observed)
      "eq" (second observed)
      "older" (third observed)
      "newer_flag" (fourth observed)
      "equal_flag" (fifth observed)
      "cm_tok" (nth 0 cache)
      "cm_idle" (nth 1 cache)
      "cm_chg" (nth 2 cache)
      "cm_hit" (nth 3 cache)
      "sw_tok" (nth 4 cache)
      "sw_idle" (nth 5 cache)
      "sw_chg" (nth 6 cache)
      "sw_hit" (nth 7 cache)
      "healthy_hit" (nth 8 cache)
      "empty_hit" (nth 9 cache)
      "cw_tok" (nth 0 waste)
      "cw_n" (nth 1 waste)
      "cw_healthy" (nth 2 waste)
      "cw_reset" (nth 4 waste)
      "cw_sw_tok" (nth 6 waste)
      "cw_sw_n" (nth 7 waste)
      "cw_nocache" (nth 8 waste)
      "tl_off" (nth 0 thinking)
      "tl_min" (nth 1 thinking)
      "tl_low" (nth 2 thinking)
      "tl_med" (nth 3 thinking)
      "tl_high" (nth 4 thinking)
      "tl_xhigh" (nth 5 thinking)
      "tl_max" (nth 6 thinking)
      "tl_miss" (nth 7 thinking)
      "sl_n" (nth 0 sessions)
      "sl_id" (nth 1 sessions)
      "sl_empty" (nth 2 sessions)
      "as_ok" (nth 0 agent)
      "as_model" (nth 1 agent)
      "as_fb" (nth 2 agent)
      "ss_ok" (nth 0 services)
      "ss_cwd" (nth 1 services)
      "ss_snap" (nth 2 services)
      "mr_oa" (nth 0 models)
      "mr_an" (nth 1 models)
      "mr_missp" (nth 2 models)
      "mr_gpt" (nth 3 models)
      "mr_missm" (nth 4 models))
     "version_newer"
     (collect "cli_sdk.version_newer"
              (lambda ()
                (lambda ()
                  (run-cli-sdk-version-newer))))
     "cache_miss"
     (collect "cli_sdk.cache_miss"
              (lambda ()
                (lambda ()
                  (run-cli-sdk-cache-miss))))
     "cache_waste"
     (collect "cli_sdk.cache_waste"
              (lambda ()
                (lambda ()
                  (run-cli-sdk-cache-waste))))
     "thinking_level"
     (collect "cli_sdk.thinking_level"
              (lambda ()
                (lambda ()
                  (run-cli-sdk-thinking-level))))
     "session_list"
     (collect "cli_sdk.session_list"
              (lambda ()
                (lambda ()
                  (run-cli-sdk-session-list))))
     "agent_session"
     (collect "cli_sdk.agent_session"
              (lambda ()
                (lambda ()
                  (run-cli-sdk-agent-session))))
     "session_services"
     (collect "cli_sdk.session_services"
              (lambda ()
                (lambda ()
                  (run-cli-sdk-session-services))))
     "model_runtime"
     (collect "cli_sdk.model_runtime"
              (lambda ()
                (lambda ()
                  (run-cli-sdk-model-runtime)))))))

(defun provider-definition-present-p (id)
  (handler-case
      (progn
        (cadr-ai::find-provider-definition id)
        1)
    (error () 0)))

(defun run-provider-registry-defs ()
  (list
   (provider-definition-present-p :openai)
   (provider-definition-present-p :anthropic)
   (provider-definition-present-p :google)
   (provider-definition-present-p :no-such-provider)))

(defun measure-provider-registry-defs ()
  (let ((observed (run-provider-registry-defs)))
    (json-object
     "observed"
     (json-object
      "openai" (first observed)
      "anthropic" (second observed)
      "google" (third observed)
      "unknown" (fourth observed))
     "lookup"
     (collect "provider_registry_defs.lookup"
              (lambda ()
                (lambda ()
                  (run-provider-registry-defs)))))))

(defun run-skill-prompt-build ()
  (let* ((cwd "/tmp/proj")
         (custom
           (cadr-cli:build-system-prompt
            :custom-prompt "hello"
            :cwd cwd
            :selected-tools '("read")))
         (appended
           (cadr-cli:build-system-prompt
            :custom-prompt "hello"
            :cwd cwd
            :append-system-prompt "extra"
            :selected-tools '("read")))
         (with-ctx
           (cadr-cli:build-system-prompt
            :custom-prompt "hello"
            :cwd cwd
            :selected-tools '("read")
            :context-files
            (list
             (list :path "AGENTS.md"
                   :content "be careful")))))
    (list
     (length custom)
     (length appended)
     (length with-ctx)
     (if (search "Current working directory: /tmp/proj" custom)
         1
         0)
     (if (search "extra" appended) 1 0)
     (if (search "AGENTS.md" with-ctx) 1 0))))

(defun measure-skill-prompt-build ()
  (let ((observed (run-skill-prompt-build)))
    (json-object
     "observed"
     (json-object
      "custom_len" (first observed)
      "append_len" (second observed)
      "ctx_len" (third observed)
      "has_cwd" (fourth observed)
      "has_extra" (fifth observed)
      "has_agents" (sixth observed))
     "build_prompt"
     (collect "skill_prompt_load.build_prompt"
              (lambda ()
                (lambda ()
                  (run-skill-prompt-build)))))))

(defun run-cli-bootstrap-coding-tools ()
  (let* ((tools (cadr-cli:make-coding-tools "/tmp/proj"))
         (names (mapcar #'cadr-ai:tool-name tools))
         (snippets (cadr-cli::tool-prompt-snippets tools)))
    (list
     (length names)
     (if (equal names '("read" "bash" "edit" "write")) 1 0)
     (length snippets)
     (if (equal (car (first snippets)) "read") 1 0))))

(defun measure-cli-bootstrap-coding-tools ()
  (let ((observed (run-cli-bootstrap-coding-tools)))
    (json-object
     "observed"
     (json-object
      "count" (first observed)
      "baseline" (second observed)
      "snippet_count" (third observed)
      "read_first" (fourth observed))
     "coding_tools"
     (collect "cli_bootstrap_sessions.coding_tools"
              (lambda ()
                (lambda ()
                  (run-cli-bootstrap-coding-tools)))))))

(defun run-ai-runtime-faux-blocks ()
  (let ((text (cadr-ai:faux-text "hello"))
        (think (cadr-ai:faux-thinking "hmm")))
    (list
     (length (cadr-ai:text-content-text text))
     (cadr-ai:text-content-text text)
     (length (cadr-ai:thinking-content-thinking think))
     (cadr-ai:thinking-content-thinking think))))

(defun measure-ai-runtime-faux-blocks ()
  (let ((observed (run-ai-runtime-faux-blocks)))
    (json-object
     "observed"
     (json-object
      "text_len" (first observed)
      "text" (second observed)
      "think_len" (third observed)
      "think" (fourth observed))
     "blocks"
     (collect "ai_runtime_faux.blocks"
              (lambda ()
                (lambda ()
                  (run-ai-runtime-faux-blocks)))))))

(defun run-http-transport-parse-url ()
  (let ((https (cadr-ai::parse-http-url "https://example.com/foo"))
        (http (cadr-ai::parse-http-url "http://localhost:8080/bar")))
    (list
     (cadr-ai::parsed-url-scheme https)
     (cadr-ai::parsed-url-host https)
     (cadr-ai::parsed-url-path https)
     (cadr-ai::parsed-url-scheme http)
     (cadr-ai::parsed-url-host http)
     (cadr-ai::parsed-url-port http)
     (cadr-ai::parsed-url-path http))))

(defun measure-http-transport-parse-url ()
  (let ((observed (run-http-transport-parse-url)))
    (json-object
     "observed"
     (json-object
      "https_scheme" (first observed)
      "https_host" (second observed)
      "https_path" (third observed)
      "http_scheme" (fourth observed)
      "http_host" (fifth observed)
      "http_port" (sixth observed)
      "http_path" (seventh observed))
     "parse_url"
     (collect "http_transport.parse_url"
              (lambda ()
                (lambda ()
                  (run-http-transport-parse-url)))))))

(defun slicing-fixtures ()
  (values
   (with-output-to-string (out)
     (dotimes (i 200)
       (format out "~C[38;2;~D;~D;~Dmword~D~C[0m "
               #\Escape (mod (* i 37) 256) (mod (* i 91) 256)
               (mod (* i 53) 256) i #\Escape)))
   (make-string 4000 :initial-element #\a)))

(defun measure-render-slicing ()
  (multiple-value-bind (dense plain) (slicing-fixtures)
    (multiple-value-bind (dense-text dense-width)
        (cadr-tui:slice-with-width dense 40 60 t)
      (multiple-value-bind (plain-text plain-width)
          (cadr-tui:slice-with-width plain 100 60 t)
        (multiple-value-bind (head-text head-width)
            (cadr-tui:slice-with-width dense 0 80 t)
          (json-object
           "observed"
           (json-object
            "dense_clip_text" dense-text
            "dense_clip_width" dense-width
            "dense_head_text" head-text
            "dense_head_width" head-width
            "plain_clip_text" plain-text
            "plain_clip_width" plain-width)
           "slice_ansi_clip"
           (collect "render_slicing.slice_ansi_clip"
                    (lambda ()
                      (lambda ()
                        (cadr-tui:slice-with-width dense 40 60 t))))
           "slice_plain_clip"
           (collect "render_slicing.slice_plain_clip"
                    (lambda ()
                      (lambda ()
                        (cadr-tui:slice-with-width plain 100 60 t))))))))))

(defun provenance-json (staged-digests)
  (let ((project (namestring cl-user::*cadr-bench-project-directory*)))
    (json-object
     "entry_points"
     (json-object
      "cli_dispatch.argv_parse"
      "src/cadr-cli/arguments.lisp parse-cli-arguments"
      "cli_dispatch.help_render"
      "src/cadr-cli/arguments.lisp print-cli-usage"
      "cli_dispatch.list_models_registry"
      "src/cadr-cli/models/registry.lisp make-model-registry"
      "cli_dispatch.list_models_render"
      "src/cadr-cli/bootstrap/main.lisp print-cli-models"
      "provider_stream.stream_roundtrip"
      "src/cadr-ai/provider.lisp stream-chat (openai-completions)"
      "provider_anthropic.stream_roundtrip"
      "src/cadr-ai/providers/anthropic.lisp stream-chat"
      "provider_google.stream_roundtrip"
      "src/cadr-ai/providers/google.lisp stream-chat"
      "provider_bedrock.stream_roundtrip"
      "src/cadr-ai/providers/bedrock.lisp stream-chat"
      "provider_mistral.stream_roundtrip"
      "src/cadr-ai/providers/mistral.lisp stream-chat"
      "provider_openai_responses.stream_roundtrip"
      "src/cadr-ai/providers/openai.lisp stream-chat"
      "provider_azure_openai.stream_roundtrip"
      "src/cadr-ai/providers/azure-openai.lisp stream-chat"
      "provider_vertex.stream_roundtrip"
      "src/cadr-ai/providers/vertex.lisp stream-chat"
      "provider_codex.stream_roundtrip"
      "src/cadr-ai/providers/codex.lisp stream-chat"
      "provider_pi_messages.stream_roundtrip"
      "src/cadr-ai/providers/pi-messages.lisp stream-chat"
      "cli_settings.create"
      "src/cadr-cli/settings/manager.lisp make-settings-manager"
      "settings_load.project_trust"
      "src/cadr-cli/settings/trust.lisp resolve-project-trusted"
      "settings_load.config_value"
      "src/cadr-cli/settings/config-values.lisp resolve-config-value"
      "settings_load.http_idle"
      "src/cadr-cli/bootstrap/settings.lisp http-idle-timeout-label"
      "resource_loader.reload"
      "src/cadr-cli/resource-loader.lisp reload-resources"
      "package_manager.resolve"
      "src/cadr-cli/packages/manifest.lisp package-resource-paths"
      "session_discovery.header_probe"
      "src/cadr-agent/session/discovery.lisp read-session-header-for-discovery"
      "session_export_html.to_html"
      "src/cadr-agent/session/export-html.lisp export-session-html"
      "protocol_cbor.roundtrip"
      "src/cadr-protocol/cbor.lisp encode-cbor + decode-cbor"
      "agent_schema.validate_ok_fail"
      "src/cadr-agent/schema.lisp validate-tool-arguments"
      "harness_storage.open_walk"
      "src/cadr-agent/storage/jsonl.lisp session-repository-open + harness-session-entries"
      "protocol_codec.roundtrip"
      "src/cadr-protocol/codec.lisp encode-client-message + message-decoder-push"
      "agent_proxy.stream_roundtrip"
      "src/cadr-agent/proxy.lisp stream-proxy"
      "oauth_pkce.challenge_urls"
      "src/cadr-ai/oauth/pkce.lisp pkce-challenge + openai/anthropic-authorization-url"
      "oauth_pkce_device.poll"
      "src/cadr-ai/auth/device-code.lisp poll-device-authorization"
      "oauth_pkce_device.auth_json"
      "src/cadr-ai/auth.lisp read-auth-credential"
      "oauth_pkce_device.copilot_url"
      "src/cadr-ai/auth/github-copilot.lisp github-copilot-base-url"
      "oauth_pkce_device.cloudflare_url"
      "src/cadr-ai/auth/radius-cloudflare.lisp materialize-cloudflare-url"
      "oauth_pkce_device.radius_gateway"
      "src/cadr-ai/oauth/providers/radius.lisp normalize-radius-gateway"
      "oauth_pkce_device.copilot_auth"
      "src/cadr-ai/oauth/providers/github-copilot.lisp github-copilot-oauth-to-auth"
      "cli_extensions_install.llama_url"
      "src/cadr-cli/extensions/llama/client.lisp normalize-llama-server-url"
      "cli_extensions_install.hf_token"
      "src/cadr-cli/extensions/llama/huggingface.lisp find-hugging-face-token"
      "cli_extensions_install.llama_catalog"
      "src/cadr-cli/extensions/llama/provider.lisp llama-provider-set-catalog"
      "evals_harness.summarize"
      "src/cadr-evals/summary.lisp summarize-harness-comparisons"
      "evals_harness.group_key"
      "src/cadr-evals/harness-table.lisp derive-eval-group-key"
      "evals_harness.artifact_persist"
      "src/cadr-evals/artifacts.lisp persist-eval-artifact-references"
      "evals_harness.format"
      "src/cadr-evals/summary.lisp format-harness-comparison-report"
      "ai_crypto_model_data.manifest"
      "src/cadr-ai/model-data.lisp create-model-data-manifest"
      "ai_crypto.hmac"
      "src/cadr-ai/crypto.lisp hmac-sha256"
      "cli_models_rest.pattern_match"
      "src/cadr-cli/models/matching.lisp parse-scoped-model-pattern"
      "cli_models_rest.auth_command"
      "src/cadr-cli/models/credential-print.lisp parse-auth-command"
      "image_runtime.dimensions"
      "src/cadr-tui/terminal-image.lisp image-dimensions"
      "image_runtime.mime_type"
      "src/cadr-cli/media.lisp detect-image-mime-type"
      "image_runtime.lookup"
      "src/cadr-ai/image-models.generated.lisp find-image-model"
      "image_runtime.dimension_note"
      "src/cadr-cli/interactive/images.lisp format-image-dimension-note"
      "image_runtime.api_provider"
      "src/cadr-ai/capabilities/image-runtime.lisp get-images-api-provider"
      "cli_print_rpc.jsonl_line"
      "src/cadr-cli/modes/print.lisp write-json-line"
      "cli_print_rpc.jsonl_read"
      "src/cadr-cli/modes/rpc/jsonl.lisp read-rpc-jsonl-lines"
      "cli_print_rpc.clamp_thinking"
      "src/cadr-cli/modes/rpc/models.lisp rpc-clamp-thinking-level"
      "cli_print_rpc.session_stats"
      "src/cadr-cli/modes/rpc/sessions.lisp rpc-session-stats"
      "tui_latex.render"
      "src/cadr-tui/latex.lisp render-latex"
      "tui_mermaid.render"
      "src/cadr-tui/mermaid/index.lisp gm-render"
      "tui_mermaid.source_box"
      "src/cadr-tui/mermaid/source-box.lisp gm-source-box"
      "tui_mermaid.transform"
      "src/cadr-tui/mermaid/transform.lisp transform-mermaid-markdown"
      "tui_editor_helpers.fuzzy_match"
      "src/cadr-tui/fuzzy.lisp fuzzy-match"
      "tui_theme_overlay.osc11_bg"
      "src/cadr-tui/terminal-colors.lisp parse-osc-11-background-color"
      "ai_support.estimate_text"
      "src/cadr-ai/support/token-estimation.lisp estimate-text-tokens"
      "ai_support.context_overflow"
      "src/cadr-ai/support/overflow.lisp context-overflow-p"
      "ai_support.grammar_delta"
      "src/cadr-ai/support/grammar-coercion.lisp append-grammar-json-delta"
      "ai_support.uuid_v7"
      "src/cadr-ai/support/uuid.lisp uuid-v7"
      "ai_support.auth_guidance"
      "src/cadr-ai/support/release.lisp no-models-available-message"
      "tui_select_settings_loaders.filter"
      "src/cadr-tui/components/select-list.lisp select-list-filtered-items"
      "tui_word_navigation.step"
      "src/cadr-tui/word-navigation.lisp find-word-backward + find-word-forward"
      "tui_overlay.composite_line"
      "src/cadr-tui/overlay.lisp composite-overlay-line"
      "tui_kill_ring.push_peek"
      "src/cadr-tui/kill-ring.lisp kill-ring-push + kill-ring-peek + kill-ring-rotate"
      "tui_undo_stack.push_pop"
      "src/cadr-tui/undo-stack.lisp undo-stack-push + undo-stack-pop + undo-stack-clear"
      "tui_autocomplete.suggest_apply"
      "src/cadr-tui/autocomplete.lisp autocomplete-get-suggestions + autocomplete-apply"
      "tui_keybindings.resolve_match"
      "src/cadr-tui/keybindings.lisp make-keybindings-manager + keybinding-keys + keybinding-matches-p"
      "tui_stdin_buffer.process"
      "src/cadr-tui/stdin-buffer.lisp stdin-buffer-process"
      "tui_input_component.edit"
      "src/cadr-tui/input-component.lisp single-line-input-handle-event"
      "tui_native_modifiers.pressed"
      "src/cadr-tui/native-modifiers.lisp is-native-modifier-pressed"
      "tui_settings_list.apply_filter"
      "src/cadr-tui/composition/settings-list.lisp settings-list-apply-filter"
      "ai_capabilities.short_hash"
      "src/cadr-ai/capabilities/streaming-json.lisp short-hash"
      "ai_capabilities.deferred_tools"
      "src/cadr-ai/capabilities/grammar-tools.lisp split-deferred-tools"
      "ai_capabilities.event_stream"
      "src/cadr-ai/capabilities/event-stream.lisp make-event-stream"
      "ai_capabilities.http_proxy"
      "src/cadr-ai/capabilities/proxy-config.lisp resolve-http-proxy-url-for-target"
      "ai_capabilities.session_resources"
      "src/cadr-ai/capabilities/session-resources.lisp register-session-resource-cleanup + cleanup-session-resources"
      "cli_support.strip_ansi"
      "src/cadr-cli/support/changelog-share.lisp strip-ansi"
      "cli_support.normalize_path"
      "src/cadr-cli/support/paths.lisp normalize-path-input"
      "cli_support.timings"
      "src/cadr-cli/support/timings.lisp reset-timings + record-timing + print-timings"
      "cli_support.event_bus"
      "src/cadr-cli/support/event-bus.lisp make-event-bus + event-bus-on + event-bus-emit"
      "cli_support.attribution_headers"
      "src/cadr-cli/support/headers.lisp provider-attribution-headers"
      "cli_support.shell_config"
      "src/cadr-cli/support/shell-process.lisp get-shell-config"
      "cli_support.sanitize_output"
      "src/cadr-cli/support/shell-process.lisp sanitize-binary-output"
      "cli_support.git_source"
      "src/cadr-cli/support/resume-version-git.lisp parse-git-source"
      "cli_support.user_agent"
      "src/cadr-cli/support/resume-version-git.lisp cadr-user-agent"
      "cli_support.parse_changelog"
      "src/cadr-cli/support/changelog-share.lisp parse-changelog"
      "cli_support.experimental"
      "src/cadr-cli/support/html.lisp experimental-features-enabled-p"
      "cli_interactive_controller.decode_entity"
      "src/cadr-cli/interactive/syntax.lisp decode-highlight-entity"
      "cli_interactive_controller.wayland"
      "src/cadr-cli/interactive/clipboard.lisp clipboard-wayland-p"
      "cli_interactive_controller.cwd_footer"
      "src/cadr-cli/interactive/footer.lisp format-cwd-for-footer"
      "cli_interactive_controller.auth_type"
      "src/cadr-cli/interactive/autocomplete.lisp tui-auth-type-label"
      "cli_interactive_controller.parse_auto_theme"
      "src/cadr-cli/interactive/theme.lisp parse-auto-theme-setting"
      "cli_interactive_controller.resolve_theme"
      "src/cadr-cli/interactive/theme.lisp resolve-theme-setting"
      "cli_selectors.session_search"
      "src/cadr-cli/interactive/selectors/sessions.lisp filter-and-sort-sessions"
      "cli_selectors.session_format_age"
      "src/cadr-cli/interactive/selectors/sessions.lisp session-selector-format-age"
      "cli_selectors.session_record_label"
      "src/cadr-cli/interactive/selectors/sessions.lisp session-selector-record-label"
      "cli_selectors.session_shorten_path"
      "src/cadr-cli/interactive/selectors/sessions.lisp session-selector-shorten-path"
      "cli_selectors.session_quoted_search"
      "src/cadr-cli/interactive/selectors/sessions.lisp search-record-position"
      "cli_selectors.session_thread_records"
      "src/cadr-cli/interactive/selectors/sessions.lisp thread-session-records"
      "cli_selectors.session_binding_label"
      "src/cadr-cli/interactive/selectors/sessions.lisp session-selector-binding-label"
      "cli_selectors.session_same_path"
      "src/cadr-cli/interactive/selectors/sessions.lisp same-session-path-p"
      "cli_selectors.session_quoted_p"
      "src/cadr-cli/interactive/selectors/sessions.lisp quoted-search-p"
      "cli_selectors.session_named_p"
      "src/cadr-cli/interactive/selectors/sessions.lisp named-session-p"
      "cli_selectors.settings_thinking_description"
      "src/cadr-cli/interactive/selectors/settings.lisp settings-thinking-description"
      "cli_selectors.settings_display_value"
      "src/cadr-cli/interactive/selectors/settings.lisp settings-display-value"
      "cli_selectors.settings_automatic_theme_setting"
      "src/cadr-cli/interactive/selectors/settings.lisp settings-selector-automatic-theme-setting"
      "cli_selectors.settings_active_automatic_theme"
      "src/cadr-cli/interactive/selectors/settings.lisp settings-selector-active-automatic-theme"
      "cli_selectors.settings_cycle"
      "src/cadr-cli/interactive/selectors/settings.lisp settings-selector-cycle"
      "cli_selectors.settings_apply_filter"
      "src/cadr-cli/interactive/selectors/settings.lisp settings-selector-apply-filter"
      "cli_selectors.tree_entry_filtered"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-entry-filtered-p"
      "cli_selectors.tree_query_matches"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-query-matches-p"
      "cli_selectors.tree_entry_search_text"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-entry-search-text"
      "cli_selectors.tree_settings_entry_p"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-settings-entry-p"
      "cli_selectors.tree_normalize_display_text"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-normalize-display-text"
      "cli_selectors.tree_status_labels"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-status-labels"
      "cli_selectors.tree_shorten_path"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-shorten-path"
      "cli_selectors.tree_foldable_p"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-foldable-p"
      "cli_selectors.tree_tool_argument"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-tool-argument"
      "cli_selectors.tree_cycle_filter"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-cycle-filter"
      "cli_selectors.tree_format_label_timestamp"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-format-label-timestamp"
      "cli_selectors.tree_iso_timestamp"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-iso-timestamp"
      "cli_selectors.tree_format_tool_call"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-format-tool-call"
      "cli_selectors.tree_entry_display_text"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-entry-display-text"
      "cli_selectors.tree_prefix"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-prefix"
      "cli_selectors.tree_visual_nodes"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-visual-nodes"
      "cli_selectors.tree_horizontal_viewport"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-horizontal-viewport"
      "cli_selectors.tree_help_keys"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-help-keys"
      "cli_selectors.tree_help_key"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-help-key"
      "cli_selectors.tree_app_key_p"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-app-key-p"
      "cli_selectors.tree_help_lines"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-help-lines"
      "cli_selectors.tree_active_path"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-active-path"
      "cli_selectors.tree_nearest_visible_id"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-nearest-visible-id"
      "cli_selectors.tree_prioritize_active"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-prioritize-active"
      "cli_selectors.tree_entry_map"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-entry-map"
      "cli_selectors.tree_order_entries"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-order-entries"
      "cli_selectors.tree_rebuild_visible_maps"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-rebuild-visible-maps"
      "cli_selectors.tree_apply_filter"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-apply-filter"
      "cli_selectors.tree_render_lines"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-render-lines"
      "cli_selectors.tree_move"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-move"
      "cli_selectors.tree_fold_or_up"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-fold-or-up"
      "cli_selectors.tree_unfold_or_down"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-unfold-or-down"
      "cli_selectors.tree_branch_segment_id"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-branch-segment-id"
      "cli_selectors.tree_set_query"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-set-query"
      "cli_selectors.tree_set_filter"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-set-filter"
      "cli_selectors.tree_copy_selected"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-copy-selected"
      "cli_selectors.tree_toggle_label_timestamps"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-toggle-label-timestamps"
      "cli_selectors.tree_start_label_edit"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-start-label-edit"
      "cli_selectors.tree_confirm_label"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-confirm-label"
      "cli_selectors.tree_cancel_label"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-cancel-label"
      "cli_selectors.tree_handle_raw_input"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-handle-raw-input"
      "cli_selectors.tree_handle_event"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-handle-event"
      "cli_selectors.tree_handle_label_event"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-handle-label-event"
      "cli_selectors.tree_selected_entry"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-selected-entry"
      "cli_selectors.tree_selected_id"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-selected-id"
      "cli_selectors.tree_select_id"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-select-id"
      "cli_selectors.tree_visible_ids"
      "src/cadr-cli/interactive/selectors/tree.lisp tree-selector-visible-ids"
      "cli_selectors.project_trust_options"
      "src/cadr-cli/interactive/selectors/trust.lisp project-trust-options"
      "cli_selectors.trust_selector_selection"
      "src/cadr-cli/interactive/selectors/trust.lisp trust-selector-selection"
      "cli_selectors.trust_decision_description"
      "src/cadr-cli/interactive/selectors/trust.lisp trust-decision-description"
      "cli_selectors.trust_selector_move"
      "src/cadr-cli/interactive/selectors/trust.lisp trust-selector-move"
      "cli_selectors.trust_selector_handle_event"
      "src/cadr-cli/interactive/selectors/trust.lisp trust-selector-handle-event"
      "cli_selectors.trust_selector_handle_raw_input"
      "src/cadr-cli/interactive/selectors/trust.lisp trust-selector-handle-raw-input"
      "cli_selectors.trust_selector_ui_state"
      "src/cadr-cli/interactive/selectors/trust.lisp render-trust-selector"
      "cli_selectors.oauth_option_status_label"
      "src/cadr-cli/interactive/selectors/auth.lisp oauth-option-status-label"
      "cli_selectors.oauth_option_status_rendered"
      "src/cadr-cli/interactive/selectors/auth.lisp oauth-option-status-rendered"
      "cli_selectors.credential_entry_auth_type"
      "src/cadr-cli/interactive/selectors/auth.lisp credential-entry-auth-type"
      "cli_selectors.oauth_environment_source_p"
      "src/cadr-cli/interactive/selectors/auth.lisp oauth-environment-source-p"
      "cli_selectors.oauth_selector_selection"
      "src/cadr-cli/interactive/selectors/auth.lisp oauth-selector-selection"
      "cli_selectors.oauth_selector_apply_filter"
      "src/cadr-cli/interactive/selectors/auth.lisp oauth-selector-apply-filter"
      "cli_selectors.oauth_selector_handle_event"
      "src/cadr-cli/interactive/selectors/auth.lisp oauth-selector-handle-event"
      "cli_selectors.oauth_selector_handle_raw_input"
      "src/cadr-cli/interactive/selectors/auth.lisp oauth-selector-handle-raw-input"
      "cli_selectors.oauth_selector_search_text"
      "src/cadr-cli/interactive/selectors/auth.lisp oauth-selector-search-text"
      "cli_selectors.login_auth_type_route"
      "src/cadr-cli/interactive/selectors/auth.lisp login-auth-type-route"
      "cli_selectors.login_provider_options"
      "src/cadr-cli/interactive/selectors/auth.lisp login-provider-options"
      "cli_selectors.logout_provider_options"
      "src/cadr-cli/interactive/selectors/auth.lisp logout-provider-options"
      "cli_selectors.login_method_selector_handle_event"
      "src/cadr-cli/interactive/selectors/auth.lisp login-method-selector-handle-event"
      "cli_selectors.oauth_selector_move"
      "src/cadr-cli/interactive/selectors/auth.lisp oauth-selector-move"
      "cli_selectors.api_key_input_state_handle_event"
      "src/cadr-cli/interactive/selectors/auth.lisp api-key-input-state-handle-event"
      "cli_selectors.login_method_selector_ui_state"
      "src/cadr-cli/interactive/selectors/auth.lisp render-login-method-selector"
      "cli_selectors.key_text"
      "src/cadr-cli/interactive/components/loaders.lisp format-key-text"
      "cli_selectors.fuzzy_filter"
      "src/cadr-cli/interactive/selectors/common.lisp selector-fuzzy-filter"
      "cli_selectors.delete_query"
      "src/cadr-cli/interactive/selectors/common.lisp selector-delete-query-character"
      "cli_selectors.visible_slice"
      "src/cadr-cli/interactive/selectors/common.lisp selector-frame-visible-slice"
      "cli_selectors.move_index"
      "src/cadr-cli/interactive/selectors/common.lisp selector-frame-move-index"
      "cli_selectors.align_left_right"
      "src/cadr-cli/interactive/selectors/common.lisp selector-align-left-right"
      "cli_selectors.fit_line"
      "src/cadr-cli/interactive/selectors/common.lisp selector-fit-line"
      "cli_selectors.border_line"
      "src/cadr-cli/interactive/selectors/common.lisp selector-border-line"
      "cli_selectors.selected_line"
      "src/cadr-cli/interactive/selectors/common.lisp selector-selected-line"
      "cli_selectors.muted_line"
      "src/cadr-cli/interactive/selectors/common.lisp selector-muted-line"
      "cli_selectors.dim_line"
      "src/cadr-cli/interactive/selectors/common.lisp selector-dim-line"
      "cli_selectors.modified_cursor_key"
      "src/cadr-cli/interactive/selectors/common.lisp selector-modified-cursor-key"
      "cli_selectors.title_line"
      "src/cadr-cli/interactive/selectors/common.lisp selector-title-line"
      "cli_selectors.overlay_title_line"
      "src/cadr-cli/interactive/selectors/common.lisp selector-overlay-title-line"
      "cli_selectors.input_line"
      "src/cadr-cli/interactive/selectors/common.lisp selector-input-line"
      "cli_selectors.keybinding_text"
      "src/cadr-cli/interactive/selectors/common.lisp selector-keybinding-text"
      "cli_selectors.keybinding_hint"
      "src/cadr-cli/interactive/selectors/common.lisp selector-keybinding-hint"
      "websocket_stream.stream_roundtrip"
      "src/cadr-ai/websocket.lisp stream-chat (openai-codex websocket)"
      "cli_sdk.version_newer"
      "src/cadr-cli/sdk/cache-version.lisp newer-package-version-p"
      "cli_sdk.cache_miss"
      "src/cadr-cli/sdk/cache-version.lisp detect-cache-miss"
      "cli_sdk.cache_waste"
      "src/cadr-cli/sdk/cache-version.lisp compute-cache-waste"
      "cli_sdk.thinking_level"
      "src/cadr-cli/sdk/cache-version.lisp valid-thinking-level-p"
      "cli_sdk.session_list"
      "src/cadr-cli/sdk/session-manager.lisp session-manager-list"
      "cli_sdk.agent_session"
      "src/cadr-cli/sdk/agent-session.lisp create-agent-session"
      "cli_sdk.session_services"
      "src/cadr-cli/sdk/session-runtime.lisp create-agent-session-services"
      "cli_sdk.model_runtime"
      "src/cadr-cli/sdk/model-service.lisp sdk-model-runtime-providers + sdk-model-runtime-model"
      "provider_registry_defs.lookup"
      "src/cadr-ai/providers/definitions.lisp find-provider-definition"
      "skill_prompt_load.build_prompt"
      "src/cadr-cli/sdk/system-prompt.lisp build-system-prompt"
      "cli_bootstrap_sessions.coding_tools"
      "src/cadr-cli/bootstrap/tools.lisp make-coding-tools"
      "ai_runtime_faux.blocks"
      "src/cadr-ai/runtime/faux-provider.lisp faux-text + faux-thinking"
      "http_transport.parse_url"
      "src/cadr-ai/transport/http.lisp parse-http-url"
      "session_pipeline.session_load"
      "src/cadr-agent/session/migration.lisp load-session"
      "session_pipeline.context_walk"
      "src/cadr-agent/session/journal.lisp session-messages"
      "storage_journal.journal_read"
      "src/cadr-agent/session/migration.lisp read-session-objects"
      "storage_journal.journal_append"
      "src/cadr-agent/session/journal.lisp create-session + session-append-message"
      "sqlite_session.open_walk"
      "src/cadr-agent/sqlite-storage.lisp session-repository-open + harness-session-entries + harness-session-branch"
      "tool_read.text_file"
      "src/cadr-cli/tools/read.lisp read-tool-file"
      "tool_grep.context_file"
      "src/cadr-cli/tools/grep.lisp grep-lines"
      "agent_tool_loop.roundtrip"
      "src/cadr-agent/loop/agent-loop.lisp agent-prompt"
      "agent_tool_loop.tool_path"
      "src/cadr-cli/tools/path.lisp resolve-tool-path"
      "agent_tool_loop.line_ending"
      "src/cadr-cli/tools/edit.lisp detect-line-ending"
      "session_compact.compact"
      "src/cadr-agent/compaction.lisp compact-from-preparation"
      "text_truncation.truncate_head"
      "src/cadr-agent/truncate.lisp truncate-harness-head"
      "text_truncation.truncate_tail"
      "src/cadr-agent/truncate.lisp truncate-harness-tail"
      "render_slicing.slice_ansi_clip"
      "src/cadr-tui/unicode.lisp slice-with-width"
      "render_slicing.slice_plain_clip"
      "src/cadr-tui/unicode.lisp slice-with-width")
     "fixture_sha256" (fixture-digests-json)
     "source_revision"
     (handler-case
         (let ((value
                 (string-trim
                  '(#\Space #\Tab #\Newline #\Return)
                  (uiop:run-program
                   (list "git" "-C" project "rev-parse" "HEAD")
                   :output :string
                   :error-output :string))))
           (if (plusp (length value)) value "isolated-copy"))
       (error () "isolated-copy"))
     "staged_agent_dir_sha256" staged-digests)))

(defun run-benchmarks ()
  (let ((scrubbed (scrub-provider-environment))
        (staged-digests (stage-agent-directory)))
    (format *error-output* "goal20 cadr paired paths: cli_dispatch~%")
    (let ((cli (measure-cli-dispatch staged-digests)))
      (format *error-output* "goal20 cadr paired paths: provider_stream~%")
      (let ((provider (measure-provider-stream)))
        (format *error-output* "goal20 cadr paired paths: session_pipeline~%")
        (let ((session (measure-session-pipeline)))
          (format *error-output* "goal20 cadr paired paths: storage_journal~%")
          (let ((storage (measure-storage-journal)))
            (format *error-output* "goal20 cadr paired paths: sqlite_session~%")
            (let ((sqlite (measure-sqlite-session)))
            (format *error-output* "goal20 cadr paired paths: text_truncation~%")
            (let ((truncation (measure-text-truncation)))
              (format *error-output* "goal20 cadr paired paths: tool_read~%")
              (let ((tool-read (measure-tool-read)))
              (format *error-output* "goal20 cadr paired paths: tool_grep~%")
              (let ((tool-grep (measure-tool-grep)))
              (format *error-output* "goal20 cadr paired paths: agent_tool_loop~%")
              (let ((tool-loop (measure-agent-tool-loop)))
              (format *error-output* "goal20 cadr paired paths: session_compact~%")
              (let ((compact (measure-session-compact)))
              (format *error-output* "goal20 cadr paired paths: provider_anthropic~%")
              (let ((anthropic (measure-provider-anthropic)))
              (format *error-output* "goal20 cadr paired paths: provider_google~%")
              (let ((google (measure-provider-google)))
              (format *error-output* "goal20 cadr paired paths: provider_bedrock~%")
              (let ((bedrock (measure-provider-bedrock)))
              (format *error-output* "goal20 cadr paired paths: provider_mistral~%")
              (let ((mistral (measure-provider-mistral)))
              (format *error-output* "goal20 cadr paired paths: provider_openai_responses~%")
              (let ((openai-responses (measure-provider-openai-responses)))
              (format *error-output* "goal20 cadr paired paths: provider_azure_openai~%")
              (let ((azure-openai (measure-provider-azure-openai)))
              (format *error-output* "goal20 cadr paired paths: provider_vertex~%")
              (let ((vertex (measure-provider-vertex)))
              (format *error-output* "goal20 cadr paired paths: provider_codex~%")
              (let ((codex (measure-provider-codex)))
              (format *error-output* "goal20 cadr paired paths: provider_pi_messages~%")
              (let ((pi-messages (measure-provider-pi-messages)))
              (format *error-output* "goal20 cadr paired paths: cli_settings~%")
              (let ((settings (measure-cli-settings)))
              (format *error-output* "goal20 cadr paired paths: settings_load~%")
              (let ((settings-load (measure-settings-load)))
              (format *error-output* "goal20 cadr paired paths: resource_loader~%")
              (let ((resources (measure-resource-loader)))
              (format *error-output* "goal20 cadr paired paths: package_manager~%")
              (let ((packages (measure-package-manager)))
              (format *error-output* "goal20 cadr paired paths: session_discovery~%")
              (let ((discovery (measure-session-discovery)))
              (format *error-output* "goal20 cadr paired paths: session_export_html~%")
              (let ((export-html (measure-session-export-html)))
              (format *error-output* "goal20 cadr paired paths: protocol_cbor~%")
              (let ((cbor (measure-protocol-cbor)))
              (format *error-output* "goal20 cadr paired paths: agent_schema~%")
              (let ((schema (measure-agent-schema)))
              (format *error-output* "goal20 cadr paired paths: harness_storage~%")
              (let ((harness-storage (measure-harness-storage)))
              (format *error-output* "goal20 cadr paired paths: protocol_codec~%")
              (let ((codec (measure-protocol-codec)))
              (format *error-output* "goal20 cadr paired paths: agent_proxy~%")
              (let ((proxy (measure-agent-proxy)))
              (format *error-output* "goal20 cadr paired paths: oauth_pkce~%")
              (let ((oauth (measure-oauth-pkce)))
              (format *error-output* "goal20 cadr paired paths: oauth_pkce_device~%")
              (let ((oauth-device (measure-oauth-pkce-device)))
              (format *error-output* "goal20 cadr paired paths: cli_extensions_install~%")
              (let ((extensions (measure-cli-extensions-install)))
              (format *error-output* "goal20 cadr paired paths: evals_harness~%")
              (let ((evals (measure-evals-harness)))
              (format *error-output* "goal20 cadr paired paths: ai_crypto_model_data~%")
              (let ((crypto (measure-ai-crypto-model-data)))
              (format *error-output* "goal20 cadr paired paths: ai_crypto~%")
              (let ((hmac (measure-ai-crypto-hmac)))
              (format *error-output* "goal20 cadr paired paths: cli_models_rest~%")
              (let ((models-rest (measure-cli-models-rest)))
              (format *error-output* "goal20 cadr paired paths: image_runtime~%")
              (let ((images (measure-image-runtime)))
              (format *error-output* "goal20 cadr paired paths: cli_print_rpc~%")
              (let ((print-rpc (measure-cli-print-rpc)))
              (format *error-output* "goal20 cadr paired paths: tui_latex~%")
              (let ((latex (measure-tui-latex)))
              (format *error-output* "goal20 cadr paired paths: tui_mermaid~%")
              (let ((mermaid (measure-tui-mermaid)))
              (format *error-output* "goal20 cadr paired paths: tui_editor_helpers~%")
              (let ((fuzzy (measure-tui-fuzzy)))
              (format *error-output* "goal20 cadr paired paths: tui_theme_overlay~%")
              (let ((theme-overlay (measure-tui-theme-overlay)))
              (format *error-output* "goal20 cadr paired paths: ai_support~%")
              (let ((estimate (measure-ai-support-estimate)))
              (format *error-output* "goal20 cadr paired paths: tui_select_settings_loaders~%")
              (let ((select-list (measure-tui-select-list)))
              (format *error-output* "goal20 cadr paired paths: tui_word_navigation~%")
              (let ((word-nav (measure-tui-word-navigation)))
              (format *error-output* "goal20 cadr paired paths: tui_overlay~%")
              (let ((overlay (measure-tui-overlay)))
              (format *error-output* "goal20 cadr paired paths: tui_kill_ring~%")
              (let ((kill-ring (measure-tui-kill-ring)))
              (format *error-output* "goal20 cadr paired paths: tui_undo_stack~%")
              (let ((undo-stack (measure-tui-undo-stack)))
              (format *error-output* "goal20 cadr paired paths: tui_autocomplete~%")
              (let ((autocomplete (measure-tui-autocomplete)))
              (format *error-output* "goal20 cadr paired paths: tui_keybindings~%")
              (let ((keybindings (measure-tui-keybindings)))
              (format *error-output* "goal20 cadr paired paths: tui_stdin_buffer~%")
              (let ((stdin-buffer (measure-tui-stdin-buffer)))
              (format *error-output* "goal20 cadr paired paths: tui_input_component~%")
              (let ((input-component (measure-tui-input-component)))
              (format *error-output* "goal20 cadr paired paths: tui_native_modifiers~%")
              (let ((native-modifiers (measure-tui-native-modifiers)))
              (format *error-output* "goal20 cadr paired paths: tui_settings_list~%")
              (let ((settings-list (measure-tui-settings-list)))
              (format *error-output* "goal20 cadr paired paths: ai_capabilities~%")
              (let ((capabilities (measure-ai-capabilities-short-hash)))
              (format *error-output* "goal20 cadr paired paths: cli_support~%")
              (let ((support (measure-cli-support-strip-ansi)))
              (format *error-output* "goal20 cadr paired paths: cli_interactive_controller~%")
              (let ((interactive (measure-cli-interactive-decode-entity)))
              (format *error-output* "goal20 cadr paired paths: cli_selectors~%")
              (let ((selectors (measure-cli-selectors-session-search)))
              (format *error-output* "goal20 cadr paired paths: cli_sdk~%")
              (let ((sdk (measure-cli-sdk-version-newer)))
              (format *error-output* "goal20 cadr paired paths: provider_registry_defs~%")
              (let ((provider-defs (measure-provider-registry-defs)))
              (format *error-output* "goal20 cadr paired paths: skill_prompt_load~%")
              (let ((skill-prompt (measure-skill-prompt-build)))
              (format *error-output* "goal20 cadr paired paths: cli_bootstrap_sessions~%")
              (let ((bootstrap (measure-cli-bootstrap-coding-tools)))
              (format *error-output* "goal20 cadr paired paths: ai_runtime_faux~%")
              (let ((faux (measure-ai-runtime-faux-blocks)))
              (format *error-output* "goal20 cadr paired paths: http_transport~%")
              (let ((http-transport (measure-http-transport-parse-url)))
              (format *error-output* "goal20 cadr paired paths: render_slicing~%")
              (let ((slicing (measure-render-slicing)))
              (format *error-output* "goal20 cadr paired paths: websocket_stream~%")
              (let ((websocket (measure-websocket-stream)))
            (json-object
             "kind" "cadr-goal20-part-h-paired-paths"
             ;; machine_instance / hostname are the field names
             ;; goal11-performance-gate.py's same_machine compares, so the
             ;; pairing gate can call that one function instead of adding a
             ;; second host-match rule.
             "machine"
             (json-object
              "lisp" (lisp-implementation-type)
              "lisp_version" (lisp-implementation-version)
              "machine_instance" (machine-instance)
              "machine_type" (machine-type))
             "metrics"
             (json-object
              "cli_dispatch" cli
              "provider_stream" provider
              "session_pipeline" session
              "storage_journal" storage
              "sqlite_session" sqlite
              "text_truncation" truncation
              "tool_read" tool-read
              "tool_grep" tool-grep
              "agent_tool_loop" tool-loop
              "session_compact" compact
              "provider_anthropic" anthropic
              "provider_google" google
              "provider_bedrock" bedrock
              "provider_mistral" mistral
              "provider_openai_responses" openai-responses
              "provider_azure_openai" azure-openai
              "provider_vertex" vertex
              "provider_codex" codex
              "provider_pi_messages" pi-messages
              "cli_settings" settings
              "settings_load" settings-load
              "resource_loader" resources
              "package_manager" packages
              "session_discovery" discovery
              "session_export_html" export-html
              "protocol_cbor" cbor
              "agent_schema" schema
              "harness_storage" harness-storage
              "protocol_codec" codec
              "agent_proxy" proxy
              "oauth_pkce" oauth
              "oauth_pkce_device" oauth-device
              "cli_extensions_install" extensions
              "evals_harness" evals
              "ai_crypto_model_data" crypto
              "ai_crypto" hmac
              "cli_models_rest" models-rest
              "image_runtime" images
              "cli_print_rpc" print-rpc
              "tui_latex" latex
              "tui_mermaid" mermaid
              "tui_editor_helpers" fuzzy
              "tui_theme_overlay" theme-overlay
              "ai_support" estimate
              "tui_select_settings_loaders" select-list
              "tui_word_navigation" word-nav
              "tui_overlay" overlay
              "tui_kill_ring" kill-ring
              "tui_undo_stack" undo-stack
              "tui_autocomplete" autocomplete
              "tui_keybindings" keybindings
              "tui_stdin_buffer" stdin-buffer
              "tui_input_component" input-component
              "tui_native_modifiers" native-modifiers
              "tui_settings_list" settings-list
              "ai_capabilities" capabilities
              "cli_support" support
              "cli_interactive_controller" interactive
              "cli_selectors" selectors
              "cli_sdk" sdk
              "provider_registry_defs" provider-defs
              "skill_prompt_load" skill-prompt
              "cli_bootstrap_sessions" bootstrap
              "ai_runtime_faux" faux
              "http_transport" http-transport
              "render_slicing" slicing
              "websocket_stream" websocket)
             "parameters"
             (json-object
              "journal_append_entry_count" *journal-append-entry-count*
              "quick" *quick-p*
              "scrubbed_environment" scrubbed
              "repetitions"
              (apply #'json-object
                     (loop for (name . nil) in *repetitions*
                           append (list name (repetitions-for name))))
              "samples" *samples*
              "terminal_sink" "count-only"
              "transport_stub"
              "cadr-ai:*http-request-function* returns the SSE fixture; no socket is opened"
              "warmups" *warmups*)
             "provenance" (provenance-json staged-digests)
             "schema_version" 1))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))

(defun write-result (result)
  (let ((text (cadr-ai::stringify-json result)))
    (if (string= *output-path* "-")
        (write-line text)
        (with-open-file (stream *output-path*
                                :direction :output
                                :if-exists :supersede
                                :if-does-not-exist :create
                                :external-format :utf-8)
          (write-line text stream)))))

(parse-options)
(unwind-protect
     (write-result (run-benchmarks))
  (uiop:delete-directory-tree *scratch-directory*
                              :validate t
                              :if-does-not-exist :ignore))
