# Changelog

All notable changes to Cadr are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project has not
yet cut a Cadr release tag. The `0.2.0` entry is frozen for the user-approved
tag/Release step.

## [Unreleased]

### Changed

- Goal 20 leftover: pair `cli_interactive_controller.bash_append_running`
  (`append-tui-user-bash-running` on
  `src/cadr-cli/interactive/user-bash.lisp` vs BashExecutionComponent
  addChild running). Observed `bar_n` / `bar_label` / `bar_run` /
  `bar_stream` / `bar_ex` / `bar_run2` exact. n=5 **2.059×** (0.735 /
  0.357 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 640). Gate `--only-enforce`; py rc=2 from known METRICS
  observed-key pollution (`parsed_provider`); this metric did not fail
  observed-exact. Over-1× booked. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_interactive_controller.bash_complete_string`
  (`complete-tui-user-bash-string` vs setComplete exit 0 string). Observed
  `cs_text` / `cs_run` / `cs_stream` / `cs_exit` / `cs_cache` / `cs_empty`
  exact. n=5 **2.719×** (0.745 / 0.274 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 641). Over-1× booked. `nextPairNum` left
  unchanged.
- Goal 20 leftover: pair `cli_interactive_controller.bash_stop_entry`
  (`stop-tui-user-bash-entry` vs loader.stop without setComplete). Observed
  `st_run` / `st_stream` / `st_text` / `st_cache` / `st_exit` exact. n=5
  **2.843×** (0.621 / 0.219 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 642). Over-1× booked. `nextPairNum` left
  unchanged.
- Goal 20 leftover: pair `cli_interactive_controller.theme_object_overrides`
  (`theme-object-overrides` on
  `src/cadr-cli/interactive/themes.lisp` vs
  withThemeColorFallbacks + resolveThemeColors). Observed `too_n` /
  `too_accent` / `too_tmax` / `too_scroll` / `too_nil` exact. n=5
  **0.651×** (22.839 / 35.090 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 637). Gate `--only-enforce`; py rc=2 from
  known METRICS observed-key pollution (`parsed_provider`); this metric
  did not fail observed-exact. cadr leads. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_interactive_controller.apply_tui_theme_summary`
  (`apply-tui-theme-summary` vs setTheme). Observed `tas_dark` /
  `tas_light` / `tas_obj` / `tas_bad` / `tas_name` exact. n=5 **3.211×**
  (52.489 / 16.348 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 638). Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_interactive_controller.load_tui_theme_file`
  (`load-tui-theme-file` vs loadThemeFromPath). Observed `ltf_name` /
  `ltf_ok` / `ltf_miss` / `ltf_bad` / `ltf_empty` exact. n=5 **2.383×**
  (233.265 / 97.883 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 639). Over-1× booked. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.daxnuts_rgb_at`
  (`daxnuts-rgb-at` on
  `src/cadr-cli/interactive/components/daxnuts.lisp` vs
  parseImage pixel lookup). Observed `dra_00` / `dra_0x` / `dra_mid` /
  `dra_last` / `dra_10` exact. n=5 **1.831×** (0.910 / 0.497 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 634). Gate
  `--only-enforce`; py rc=2 from known METRICS observed-key pollution
  (`parsed_provider`); this metric did not fail observed-exact.
  `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.make_daxnuts_component`
  (`make-daxnuts-component` vs DaxnutsComponent constructor without
  startAnimation). Observed `dmc_tick` / `dmc_stop` / `dmc_thread` /
  `dmc_cache` / `dmc_second` exact. n=5 **3.472×** (0.688 / 0.198 µs)
  on host `cursor`, ceiling 8.0. Measure-only leftover (Pair 635).
  Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.daxnuts_component_tick`
  (`daxnuts-component-tick` vs DaxnutsComponent interval body). Observed
  `dct_one` / `dct_max` / `dct_stop` / `dct_after` / `dct_renders`
  exact. n=5 **1.119×** (3.787 / 3.384 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 636). Over-1× booked. `nextPairNum` left
  unchanged.
- Goal 20 leftover: pair `cli_selectors.make_models_selector_keybindings`
  (`make-models-selector-keybindings` on
  `src/cadr-cli/interactive/selectors/models.lisp` vs
  KEYBINDINGS `app.models.*` KeybindingsManager constructor). Observed
  `mmskb_save` / `mmskb_enable` / `mmskb_confirm` / `mmskb_custom` /
  `mmskb_reorder` exact. n=5 **1.496×** (32.105 / 21.468 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 631). Gate
  `--only-enforce`; py rc=2 from known METRICS observed-key pollution
  (`parsed_provider`); this metric did not fail observed-exact.
  `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.make_scoped_models_selector_state`
  (`make-scoped-models-selector-state` vs ScopedModelsSelectorComponent
  constructor). Observed `msmksc_all` / `msmksc_partial` / `msmksc_empty` /
  `msmksc_status` / `msmksc_copy` exact. n=5 **20.997×** (97.005 / 4.620 µs)
  on host `cursor`, ceiling 40.0 first-freeze headroom. Measure-only leftover
  (Pair 632). Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.render_model_selector`
  (`render-model-selector` vs ModelSelectorComponent layout). Observed
  `rms_default` / `rms_sel2` / `rms_scoped` / `rms_narrow` / `rms_miss`
  exact. n=5 **26.593×** (247.317 / 9.300 µs) on host `cursor`, ceiling
  50.0 first-freeze headroom. Measure-only leftover (Pair 633). Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.user_message_handle_event`
  (`user-message-selector-handle-event` on
  `src/cadr-cli/interactive/selectors/fork.lisp` vs
  UserMessageList.handleInput structured events). Observed
  `umhe_down` / `umhe_enter` / `umhe_esc` / `umhe_text` / `umhe_empty`
  exact. n=5 **0.766×** (1.754 / 2.288 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 628). Gate `--only-enforce`; py rc=2 from
  known METRICS observed-key pollution (`parsed_provider`); this metric
  did not fail observed-exact. cadr leads. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.user_message_handle_raw`
  (`user-message-selector-handle-raw-input` vs UserMessageList.handleInput
  raw keys). Observed `umhr_down` / `umhr_up` / `umhr_enter` / `umhr_esc` /
  `umhr_nop` exact. n=5 **15.827×** (85.983 / 5.433 µs) on host `cursor`,
  ceiling 30.0 first-freeze headroom. Measure-only leftover (Pair 629).
  Booked in `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left
  unchanged.
- Goal 20 leftover: pair `cli_selectors.render_user_message_selector`
  (`render-user-message-selector` vs UserMessageSelectorComponent layout).
  Observed `umrd_three` / `umrd_one` / `umrd_empty` / `umrd_narrow` /
  `umrd_hit` exact. n=5 **65.009×** (265.302 / 4.081 µs) on host `cursor`,
  ceiling 100.0 first-freeze headroom. Measure-only leftover (Pair 630).
  Booked in `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left
  unchanged.
- Goal 20 leftover: pair `cli_selectors.login_dialog_complete_input`
  (`login-dialog-complete-input` on
  `src/cadr-cli/interactive/selectors/login-dialog.lisp` vs
  LoginDialogComponent.replaceInputWithSubmittedText). Observed
  `ldci_manual` / `ldci_prompt` / `ldci_none` / `ldci_blank` / `ldci_auth`
  exact. n=5 **1.643×** (5.722 / 3.482 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 625). Gate `--only-enforce`; py rc=2 from
  known METRICS observed-key pollution (`parsed_provider`); this metric
  did not fail observed-exact. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.login_dialog_handle_event`
  (`login-dialog-state-handle-event` vs LoginDialogComponent.handleInput).
  Observed `ldhe_esc` / `ldhe_cancel` / `ldhe_enter` / `ldhe_type` /
  `ldhe_down` exact. n=5 **1.923×** (6.392 / 3.325 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 626). Over-1× booked.
  `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.render_login_dialog`
  (`render-login-dialog-state` vs LoginDialogComponent layout). Observed
  `ldrd_wait` / `ldrd_auth` / `ldrd_manual` / `ldrd_prompt` /
  `ldrd_details` exact. n=5 **32.688×** (135.552 / 4.147 µs) on host
  `cursor`, ceiling 50.0 first-freeze headroom. Measure-only leftover
  (Pair 627). Over-1× booked. `nextPairNum` left unchanged.

- Goal 20 leftover: pair `cli_selectors.login_dialog_show_prompt`
  (`login-dialog-show-prompt` on
  `src/cadr-cli/interactive/selectors/login-dialog.lisp` vs
  LoginDialogComponent.showPrompt). Observed `ldpr_empty` / `ldpr_auth` /
  `ldpr_noplace` / `ldpr_nocancel` / `ldpr_wait` exact. n=5 **1.771×**
  (6.781 / 3.830 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 622). Gate `--only-enforce`; py rc=2 from known METRICS
  observed-key pollution (`parsed_provider`); this metric did not fail
  observed-exact. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.login_dialog_show_info`
  (`login-dialog-show-info` vs LoginDialogComponent.showInfo). Observed
  `ldi_labeled` / `ldi_auth` / `ldi_bare` / `ldi_nolink` / `ldi_wait`
  exact. n=5 **1.567×** (8.766 / 5.594 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 623). Over-1× booked. `nextPairNum` left
  unchanged.
- Goal 20 leftover: pair `cli_selectors.login_dialog_show_details`
  (`login-dialog-show-details` vs LoginDialogComponent.showDetails).
  Observed `lddt_two` / `lddt_auth` / `lddt_empty` / `lddt_styles` /
  `lddt_wait` exact. n=5 **0.756×** (2.598 / 3.435 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 624). cadr leads. `nextPairNum`
  left unchanged.

- Goal 20 leftover: pair `cli_selectors.login_dialog_show_waiting`
  (`login-dialog-show-waiting` on
  `src/cadr-cli/interactive/selectors/login-dialog.lisp` vs
  LoginDialogComponent.showWaiting). Observed `ldw_empty` / `ldw_auth` /
  `ldw_twice` / `ldw_blank` / `ldw_device` exact. n=5 **1.338×** (5.469 /
  4.088 µs) on host `cursor`, ceiling 8.0. Measure-only leftover (Pair 619).
  Gate `--only-enforce`; py rc=2 from known METRICS observed-key pollution
  (`parsed_provider`); this metric did not fail observed-exact. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.login_dialog_show_progress`
  (`login-dialog-show-progress` vs LoginDialogComponent.showProgress).
  Observed `ldp_empty` / `ldp_auth` / `ldp_two` / `ldp_blank` / `ldp_wait`
  exact. n=5 **1.281×** (3.159 / 2.466 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 620). Over-1× booked. `nextPairNum` left
  unchanged.
- Goal 20 leftover: pair `cli_selectors.login_dialog_show_manual_input`
  (`login-dialog-show-manual-input` vs LoginDialogComponent.showManualInput).
  Observed `ldmi_empty` / `ldmi_auth` / `ldmi_blank` / `ldmi_nocancel` /
  `ldmi_wait` exact. n=5 **1.683×** (5.131 / 3.050 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 621). Over-1× booked.
  `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.make_login_method_selector_state`
  (`make-login-method-selector-state` on
  `src/cadr-cli/interactive/selectors/auth.lisp` vs ExtensionSelectorComponent
  constructor). Observed `mlms_default` / `mlms_title` / `mlms_custom` /
  `mlms_one` / `mlms_three` exact. n=5 **1.143×** (2.654 / 2.323 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 616). Gate
  `--only-enforce`; py rc=2 from known METRICS observed-key pollution
  (`parsed_provider`); this metric did not fail observed-exact. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.make_api_key_input_state`
  (`make-api-key-input-state` vs login-dialog api key Input constructor).
  Observed `makis_anth` / `makis_openai` / `makis_google` / `makis_oauth_opt` /
  `makis_named` exact. n=5 **1.803×** (2.203 / 1.222 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 617). Over-1× booked.
  `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.make_oauth_selector_state`
  (`make-oauth-selector-state` vs OauthSelectorComponent constructor).
  Observed `moss_default` / `moss_filter` / `moss_miss` / `moss_logout_empty` /
  `moss_logout` exact. Cached keybindings. n=5 **1.204×** (7.245 / 6.020 µs)
  on host `cursor`, ceiling 8.0. Measure-only leftover (Pair 618). Over-1×
  booked. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.trust_option_saved_p`
  (`trust-option-saved-p` on
  `src/cadr-cli/interactive/selectors/trust.lisp` vs isSavedOption). Observed
  `tosp_nil` / `tosp_trust` / `tosp_parent` / `tosp_mismatch` /
  `tosp_distrust` exact. n=5 **2.292×** (35.594 / 15.530 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 613). Gate
  `--only-enforce`; py rc=2 from known METRICS observed-key pollution
  (`parsed_provider`); this metric did not fail observed-exact. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.make_trust_selector_state`
  (`make-trust-selector-state` vs TrustSelectorComponent constructor).
  Observed `mtss_child` / `mtss_saved` / `mtss_inherited` / `mtss_distrust` /
  `mtss_single` exact. Cached keybindings. n=5 **1.715×** (91.097 / 53.106
  µs) on host `cursor`, ceiling 8.0. Measure-only leftover (Pair 614).
  Over-1× booked. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.render_trust_selector`
  (`render-trust-selector` vs TrustSelectorComponent layout). Observed
  `rtrs_default` / `rtrs_saved` / `rtrs_inherited` / `rtrs_distrust` /
  `rtrs_single` exact. n=5 **8.798×** (1074.462 / 122.128 µs) on host
  `cursor`, ceiling 15.0 first-freeze headroom. Measure-only leftover
  (Pair 615). Over-1× booked. Same commit no optimize. `nextPairNum` left
  unchanged.

- Goal 20 leftover: pair `cli_selectors.thinking_selector_selected_level`
  (`thinking-selector-selected-level` on
  `src/cadr-cli/interactive/selectors/thinking.lisp` vs selected SelectList
  item). Observed `tssl_first` / `tssl_mid` / `tssl_last` / `tssl_empty` /
  `tssl_oob` exact. n=5 **0.608×** (0.467 / 0.768 µs) on host `cursor`,
  ceiling 8.0. cadr leads. Measure-only leftover (Pair 610). Gate
  `--only-enforce`; py rc=2 from known METRICS observed-key pollution
  (`parsed_provider`); this metric did not fail observed-exact.
  `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.thinking_level_description_line`
  (`thinking-level-description-line` vs LEVEL_DESCRIPTIONS · default
  suffix). Observed `tsdl_off_def` / `tsdl_high` / `tsdl_high_def` /
  `tsdl_bogus` / `tsdl_min` exact. n=5 **1.155×** (0.268 / 0.232 µs) on
  host `cursor`, ceiling 8.0. Measure-only leftover (Pair 611). Over-1×
  booked. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.render_thinking_selector`
  (`render-thinking-selector` vs ThinkingSelectorComponent layout). Observed
  `tsrd_default` / `tsrd_sel` / `tsrd_query` / `tsrd_empty` / `tsrd_wide`
  exact. n=5 **44.726×** (316.671 / 7.080 µs) on host `cursor`, ceiling
  60.0 first-freeze headroom. Measure-only leftover (Pair 612). Over-1×
  booked. Same commit no optimize. `nextPairNum` left unchanged.

- Goal 20 leftover: pair `cli_selectors.thinking_selector_move`
  (`thinking-selector-move` on
  `src/cadr-cli/interactive/selectors/thinking.lisp` vs wrap selected
  index). Observed `tsmv_down` / `tsmv_up_wrap` / `tsmv_down_wrap` /
  `tsmv_page` / `tsmv_empty` exact. n=5 **1.353×** (0.637 / 0.471 µs) on
  host `cursor`, ceiling 8.0. Measure-only leftover (Pair 607). Gate
  `--only-enforce`; py rc=2 from known METRICS observed-key pollution
  (`parsed_provider`); this metric did not fail observed-exact. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.thinking_selector_handle_raw_input`
  (`thinking-selector-handle-raw-input` vs handleInput keybindings). Observed
  `tshri_down` / `tshri_up` / `tshri_enter` / `tshri_save` / `tshri_nop`
  exact. Raw CSI/CR/ctrl+s bytes. n=5 **20.910×** (144.448 / 6.908 µs) on
  host `cursor`, ceiling 30.0 first-freeze headroom. Cached
  `*default-thinking-selector-keybindings*`; do not time
  `make-thinking-selector-keybindings`. Measure-only leftover (Pair 608).
  Over-1× booked. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.thinking_selector_handle_event`
  (`thinking-selector-handle-event` vs typed input event dispatch). Observed
  `tshe_down` / `tshe_enter` / `tshe_esc` / `tshe_text` / `tshe_tab` exact.
  n=5 **0.834×** (3.312 / 3.974 µs) on host `cursor`, ceiling 8.0. cadr
  leads. Measure-only leftover (Pair 609). `nextPairNum` left unchanged.

- Goal 20 leftover: pair `cli_selectors.thinking_selector_apply_filter`
  (`thinking-selector-apply-filter` on
  `src/cadr-cli/interactive/selectors/thinking.lisp` vs `applyFilter`).
  Observed `tsaf_high` / `tsaf_off` / `tsaf_miss` / `tsaf_empty` /
  `tsaf_low` exact. n=5 **1.149×** (13.399 / 11.664 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 604). Gate `--only-enforce`; py
  rc=2 from known METRICS observed-key pollution (`parsed_provider`); this
  metric did not fail observed-exact. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.thinking_selector_clamp_selected`
  (`thinking-selector-clamp-selected` vs clamp selected index). Observed
  `tscl_high` / `tscl_zero` / `tscl_ok` / `tscl_last` / `tscl_one` exact.
  n=5 **0.753×** (0.637 / 0.847 µs) on host `cursor`, ceiling 8.0. cadr
  leads. Measure-only leftover (Pair 605). `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.thinking_selector_select_current`
  (`thinking-selector-select-current` vs select current thinking level).
  Observed `tssc_high` / `tssc_off` / `tssc_miss` / `tssc_empty` /
  `tssc_only` exact. n=5 **0.854×** (0.981 / 1.149 µs) on host `cursor`,
  ceiling 8.0. cadr leads. Measure-only leftover (Pair 606). `nextPairNum`
  left unchanged.

- Goal 20 leftover: pair `cli_selectors.thinking_selector_key_p`
  (`thinking-selector-key-p` on
  `src/cadr-cli/interactive/selectors/thinking.lisp` vs
  `KeybindingsManager.matches` + CSI). Observed `tskp_tab_hit` /
  `tskp_tab_miss` / `tskp_up_hit` / `tskp_csi_up` / `tskp_save_hit` exact.
  n=5 **19.196×** (15.469 / 0.806 µs) on host `cursor`, ceiling 30.0
  first-freeze headroom. Cached `*default-thinking-selector-keybindings*`;
  do not time `make-thinking-selector-keybindings`. Measure-only leftover
  (Pair 601). Gate `--only-enforce`; py rc=2 from known METRICS observed-key
  pollution (`parsed_provider`); this metric did not fail observed-exact.
  Booked in `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left
  unchanged.
- Goal 20 leftover: pair `cli_selectors.thinking_selector_keybindings`
  (`thinking-selector-keybindings` vs `getKeybindings` slot-or-default).
  Observed `tskb_nil` / `tskb_default` / `tskb_custom` / `tskb_cancel` /
  `tskb_confirm` exact. n=5 **5.685×** (3.014 / 0.530 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 602). Over-1× booked.
  `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.make_thinking_selector_state`
  (`make-thinking-selector-state` vs constructor filter + select current).
  Observed `tms_high` / `tms_off` / `tms_miss` / `tms_empty` / `tms_default`
  exact. n=5 **0.638×** (1.623 / 2.545 µs) on host `cursor`, ceiling 8.0.
  cadr leads. Measure-only leftover (Pair 603). `nextPairNum` left
  unchanged. Also restores dropped leftover collect wiring for thinking.lisp
  slugs 532–534.

- Goal 20 leftover: pair `cli_selectors.model_selector_key_p`
  (`model-selector-key-p` on
  `src/cadr-cli/interactive/selectors/models.lisp` vs
  `KeybindingsManager.matches` + CSI). Observed `mskp_tab_hit` /
  `mskp_tab_miss` / `mskp_up_hit` / `mskp_csi_up` / `mskp_save_hit` exact.
  n=5 **18.605×** (16.140 / 0.868 µs) on host `cursor`, ceiling 30.0
  first-freeze headroom. Cached `*default-models-selector-keybindings*`; do
  not time `make-keybindings-manager`. Measure-only leftover (Pair 598).
  Gate `--only-enforce`; py rc=2 from known METRICS observed-key pollution
  (`parsed_provider`); this metric did not fail observed-exact. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.model_selector_keybindings`
  (`model-selector-keybindings` vs `getKeybindings` slot-or-default).
  Observed `mskb_nil` / `mskb_default` / `mskb_custom` / `mskb_enable` /
  `mskb_confirm` exact. n=5 **8.076×** (4.144 / 0.513 µs) on host `cursor`,
  ceiling 12.0 first-freeze headroom. Measure-only leftover (Pair 599).
  Over-1× booked. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.make_model_selector_state`
  (`make-model-selector-state` vs constructor sort + filter + select
  current). Observed `msmk_all` / `msmk_last` / `msmk_scoped` / `msmk_extra`
  / `msmk_one` exact. n=5 **3.037×** (21.230 / 6.989 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 600). Over-1× booked.
  `nextPairNum` left unchanged.

- Goal 20 leftover: pair `cli_selectors.scoped_models_selector_finish_refresh`
  (`scoped-models-selector-finish-refresh` on
  `src/cadr-cli/interactive/selectors/models.lisp` vs `updateModels` +
  `setRefreshStatus`). Observed `smfrf_ok` / `smfrf_success` / `smfrf_rev` /
  `smfrf_enabled` / `smfrf_filter` exact. n=5 **3.243×** (68.310 / 21.063 µs)
  on host `cursor`, ceiling 8.0. Measure-only leftover (Pair 595). Gate
  `--only-enforce`; py rc=2 from known METRICS observed-key pollution
  (`parsed_provider`); this metric did not fail observed-exact. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.scoped_models_selector_key_p`
  (`scoped-models-selector-key-p` vs `KeybindingsManager.matches`). Observed
  `smskp_save_hit` / `smskp_save_miss` / `smskp_up_hit` / `smskp_csi_up` /
  `smskp_garbage` exact. n=5 **18.835×** (22.914 / 1.217 µs) on host
  `cursor`, ceiling 30.0 first-freeze headroom. Cached
  `*default-models-selector-keybindings*`; do not time
  `make-keybindings-manager`. Measure-only leftover (Pair 596). Over-1×
  booked. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.scoped_models_binding_label`
  (`scoped-models-binding-label` vs `getKeys` first-or-fallback). Observed
  `smbl_save` / `smbl_enable` / `smbl_confirm` / `smbl_fallback` /
  `smbl_custom` exact. n=5 **16.362×** (5.542 / 0.339 µs) on host `cursor`,
  ceiling 25.0 first-freeze headroom. Measure-only leftover (Pair 597).
  Over-1× booked. `nextPairNum` left unchanged. Also restores dropped leftover
  collect wiring for models.lisp slugs 559–594.

- Goal 20 leftover: pair `cli_selectors.scoped_models_selector_refresh_items`
  (`scoped-models-selector-refresh-items` on
  `src/cadr-cli/interactive/selectors/models.lisp` vs refresh items). Observed
  `smref_all` / `smref_gpt` / `smref_miss` / `smref_empty` / `smref_partial`
  exact. n=5 **2.471×** (33.511 / 13.561 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 592). Gate rc=1 only from known old holes.
  Booked in `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left
  unchanged.
- Goal 20 leftover: pair `cli_selectors.scoped_models_selector_clamp_selected`
  (`scoped-models-selector-clamp-selected` vs clamp selected). Observed
  `smcl_high` / `smcl_zero` / `smcl_miss` / `smcl_gpt` / `smcl_empty` exact.
  n=5 **2.365×** (30.415 / 12.863 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 593). Gate rc=1 only from known old holes.
  Booked in `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left
  unchanged. Reuses JS `scopedModelsSelectorClampSelected`.
- Goal 20 leftover: pair `cli_selectors.scoped_models_selector_mark_changed`
  (`scoped-models-selector-mark-changed` vs mark changed). Observed
  `smmc_all` / `smmc_partial` / `smmc_empty` / `smmc_nocb` / `smmc_filter`
  exact. n=5 **1.359×** (35.327 / 25.989 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 594). Gate rc=1 only from known old holes.
  Booked in `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left
  unchanged.
- Goal 20 leftover: pair `cli_selectors.scoped_models_selector_rebuild_items`
  (`scoped-models-selector-rebuild-items` on
  `src/cadr-cli/interactive/selectors/models.lisp` vs rebuild items). Observed
  `smri_all` / `smri_partial` / `smri_none` / `smri_empty` / `smri_single`
  exact. n=5 **4.448×** (27.154 / 6.105 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 589). Gate rc=1 only from known old holes.
  Booked in `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left
  unchanged.
- Goal 20 leftover: pair `cli_selectors.scoped_models_selector_apply_filter`
  (`scoped-models-selector-apply-filter` vs apply filter). Observed
  `smaf_all` / `smaf_gpt` / `smaf_miss` / `smaf_partial` / `smaf_empty`
  exact. n=5 **1.464×** (34.896 / 23.842 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 590). Gate rc=1 only from known old holes.
  Booked in `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left
  unchanged.
- Goal 20 leftover: pair `cli_selectors.scoped_models_selector_visible_items`
  (`scoped-models-selector-visible-items` vs lazy visible items). Observed
  `smvi_all` / `smvi_gpt` / `smvi_miss` / `smvi_empty` / `smvi_partial`
  exact. n=5 **2.422×** (32.039 / 13.230 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 591). Gate rc=1 only from known old holes.
  Booked in `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left
  unchanged.
- Goal 20 leftover: pair `cli_selectors.scoped_models_selector_selected_item`
  (`scoped-models-selector-selected-item` on
  `src/cadr-cli/interactive/selectors/models.lisp` vs selected visible item).
  Observed `smsel_first` / `smsel_mid` / `smsel_oob` / `smsel_empty` /
  `smsel_gpt` exact. n=5 **3.417×** (26.636 / 7.796 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 586). Gate rc=1 only from known
  old holes. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.scoped_models_selector_select_id`
  (`scoped-models-selector-select-id` vs select by qualified id). Observed
  `smsid_first` / `smsid_last` / `smsid_miss` / `smsid_empty` / `smsid_gpt`
  exact. n=5 **3.323×** (26.954 / 8.112 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 587). Gate rc=1 only from known old holes.
  Booked in `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left
  unchanged.
- Goal 20 leftover: pair `cli_selectors.scoped_models_selector_notify_change`
  (`scoped-models-selector-notify-change` vs `onChange`). Observed
  `smnc_all` / `smnc_partial` / `smnc_none` / `smnc_twice` / `smnc_empty`
  exact. n=5 **1.745×** (1.398 / 0.801 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 588). Gate rc=1 only from known old holes.
  Booked in `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left
  unchanged.
- Goal 20 leftover: pair `cli_selectors.scoped_models_copy_enabled`
  (`scoped-models-copy-enabled` on
  `src/cadr-cli/interactive/selectors/models.lisp` vs enabled-ids copy).
  Observed `smce_all` / `smce_two` / `smce_empty` / `smce_one` / `smce_copy`
  exact. n=5 **1.604×** (0.743 / 0.463 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 583). Gate rc=1 only from known old holes.
  Booked in `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left
  unchanged.
- Goal 20 leftover: pair `cli_selectors.scoped_models_selector_items`
  (`scoped-models-selector-items` vs items after rebuild). Observed
  `smsi_all` / `smsi_partial` / `smsi_none` / `smsi_empty` / `smsi_single`
  exact. n=5 **4.189×** (26.959 / 6.435 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 584). Gate rc=1 only from known old holes.
  Booked in `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left
  unchanged.
- Goal 20 leftover: pair `cli_selectors.scoped_models_selector_cancel`
  (`scoped-models-selector-cancel` vs `onCancel`). Observed `smsc_once` /
  `smsc_twice` / `smsc_none` / `smsc_none2` / `smsc_zero` exact. n=5
  **1.746×** (0.667 / 0.382 µs) on host `cursor`, ceiling 8.0. Measure-only
  leftover (Pair 585). Gate rc=1 only from known old holes. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.scoped_models_selector_rebuild_models_by_id`
  (`scoped-models-selector-rebuild-models-by-id` on
  `src/cadr-cli/interactive/selectors/models.lisp` vs `modelsById` rebuild).
  Observed `smrm_all` / `smrm_partial` / `smrm_empty` / `smrm_single` /
  `smrm_extra` exact. n=5 **2.096×** (10.000 / 4.771 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 580). Gate rc=1 only from known
  old holes. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.scoped_models_model_by_id`
  (`scoped-models-model-by-id` vs `modelsById` lookup). Observed
  `smbid_hit` / `smbid_google` / `smbid_miss` / `smbid_empty` /
  `smbid_openrouter` exact. n=5 **3.185×** (9.193 / 2.886 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 581). Gate rc=1 only
  from known old holes. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.scoped_model_item_search_text`
  (`scoped-model-item-search-text` vs `getModelSearchText` on a scoped
  item). Observed `smist_gpt` / `smist_claude` / `smist_codex` /
  `smist_cached` / `smist_noid` exact. n=5 **3.735×** (2.879 / 0.771 µs)
  on host `cursor`, ceiling 8.0. Measure-only leftover (Pair 582). Gate
  rc=1 only from known old holes. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.model_selector_rebuild_search_text_table`
  (`model-selector-rebuild-search-text-table` on
  `src/cadr-cli/interactive/selectors/models.lisp` vs search-text table
  rebuild). Observed `msrst_all` / `msrst_overlap` / `msrst_extra` /
  `msrst_empty` / `msrst_scoped_only` exact. n=5 **3.240×**
  (16.001 / 4.939 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 577). Gate rc=1 only from known old holes. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.model_selector_filter_search_text`
  (`model-selector-filter-search-text` vs table lookup / fallback).
  Observed `msfst_hit` / `msfst_last` / `msfst_extra` / `msfst_miss` /
  `msfst_empty` exact. n=5 **4.389×** (13.376 / 3.048 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 578). Gate rc=1 only from known
  old holes. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.model_selector_finish_refresh`
  (`model-selector-finish-refresh` vs catalog refresh completion). Observed
  `msfr_ok` / `msfr_err` / `msfr_kind` / `msfr_rev` / `msfr_query` exact.
  n=5 **4.278×** (46.658 / 10.907 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 579). Gate rc=1 only from known old holes.
  Booked in `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left
  unchanged.
- Goal 20 leftover: pair `cli_selectors.sort_model_selector_models`
  (`sort-model-selector-models` on
  `src/cadr-cli/interactive/selectors/models.lisp` vs current-first then
  provider `localeCompare`). Observed `smsort_first` / `smsort_last` /
  `smsort_mid` / `smsort_rev` / `smsort_single` exact. n=5 **2.928×**
  (8.603 / 2.939 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 574). Gate rc=1 only from known old holes. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.model_selector_visible_models`
  (`model-selector-visible-models` vs `filteredModels` after filter).
  Observed `msvm_all` / `msvm_gpt` / `msvm_nope` / `msvm_anth` / `msvm_oogle`
  exact. n=5 **1.879×** (37.867 / 20.148 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 575). Gate rc=1 only from known old holes.
  Booked in `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left
  unchanged.
- Goal 20 leftover: pair `cli_selectors.model_selector_visible_slice`
  (`model-selector-visible-slice` vs filteredModels viewport slice). Distinct
  from `cli_selectors.visible_slice`. Observed `msvs_all` / `msvs_mid` /
  `msvs_filter` / `msvs_empty` / `msvs_max1` exact. n=5 **2.710×**
  (31.486 / 11.617 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 576). Gate rc=1 only from known old holes. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.model_selector_active_models`
  (`model-selector-active-models` on
  `src/cadr-cli/interactive/selectors/models.lisp` vs `activeModels` scope
  switch). Observed `msa_all` / `msa_scoped` / `msa_empty` / `msa_one` /
  `msa_force_all` / `msa_force_scoped` exact. n=5 **11.315×**
  (20.408 / 1.804 µs) on host `cursor`, ceiling 15.0. Measure-only leftover
  (Pair 571). Gate rc=1 only from known old holes, not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.model_selector_clamp_selected`
  (`model-selector-clamp-selected` on
  `src/cadr-cli/interactive/selectors/models.lisp` vs `filterModels`
  selectedIndex clamp). Observed `msc_ok` / `msc_high` / `msc_zero` /
  `msc_one` / `msc_keep` / `msc_filter` exact. n=5 **4.015×**
  (21.011 / 5.234 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 572). Gate rc=1 only from known old holes, not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.model_selector_select_current`
  (`model-selector-select-current` on
  `src/cadr-cli/interactive/selectors/models.lisp` vs `setScope`
  currentIndex). Observed `msel_hit` / `msel_first` / `msel_last` /
  `msel_miss` / `msel_nil` / `msel_empty` exact. n=5 **43.943×**
  (19.744 / 0.449 µs) on host `cursor`, ceiling 55.0. Measure-only leftover
  (Pair 573). Gate rc=1 only from known old holes, not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.scoped_models_enabled_set`
  (`scoped-models-enabled-set` on
  `src/cadr-cli/interactive/selectors/models.lisp` vs `getSortedIds`
  `enabledSet`). Observed `smes_empty` / `smes_one` / `smes_two` /
  `smes_dup` / `smes_sort` / `smes_three` exact. n=5 **2.540×**
  (2.709 / 1.067 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 568). Gate rc=1 only from known old holes, not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.model_equal_p`
  (`model-equal-p` on
  `src/cadr-cli/interactive/selectors/models.lisp` vs `modelsAreEqual`).
  Observed `meq_same` / `meq_diff_id` / `meq_diff_prov` / `meq_nil_left` /
  `meq_nil_right` / `meq_both_nil` exact. n=5 **1.840×** (0.458 / 0.249 µs)
  on host `cursor`, ceiling 8.0. Measure-only leftover (Pair 569). Gate rc=1
  only from known old holes, not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.scoped_model_selector_search_text`
  (`scoped-model-selector-search-text` on
  `src/cadr-cli/interactive/selectors/models.lisp` vs `getModelSearchText`).
  Observed `smsst_openai` / `smsst_anthropic` / `smsst_codex` /
  `smsst_openrouter` / `smsst_google` / `smsst_noname` exact. n=5 **8.503×**
  (4.242 / 0.499 µs) on host `cursor`, ceiling 12.0. Measure-only leftover
  (Pair 570). Gate rc=1 only from known old holes, not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.all_known_model_ids_enabled_p`
  (`all-known-model-ids-enabled-p` on
  `src/cadr-cli/interactive/selectors/models.lisp` vs enableAll
  collapse-to-null). Observed `ake_all` / `ake_full` / `ake_partial` /
  `ake_empty` / `ake_vacuous` / `ake_wrong` exact. n=5 **2.035×**
  (1.679 / 0.825 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 565). Gate rc=1 only from known old holes, not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.scoped_models_enable_ids`
  (`scoped-models-enable-ids` on
  `src/cadr-cli/interactive/selectors/models.lisp` vs enableAll id union).
  Observed `smei_all` / `smei_one` / `smei_rest` / `smei_add` / `smei_fill` /
  `smei_none` exact. n=5 **1.519×** (2.605 / 1.715 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 566). Gate rc=1 only from known
  old holes, not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 leftover: pair `cli_selectors.scoped_models_clear_ids`
  (`scoped-models-clear-ids` on
  `src/cadr-cli/interactive/selectors/models.lisp` vs clearAll id subtract).
  Observed `smci_all_one` / `smci_list` / `smci_all_all` / `smci_empty` /
  `smci_keep` / `smci_all_none` exact. n=5 **2.015×** (2.931 / 1.455 µs) on
  host `cursor`, ceiling 8.0. Measure-only leftover (Pair 567). Gate rc=1
  only from known old holes, not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_selectors.session_scoped_models`
  (`session-scoped-models` on
  `src/cadr-cli/interactive/selectors/models.lisp` vs session-scoped
  model filter). Observed `ssm_all` / `ssm_partial` / `ssm_unavail` /
  `ssm_empty` / `ssm_full` / `ssm_single` exact. n=5 **2.563×**
  (11.473 / 4.477 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 562). Gate rc=1 only from known old holes, not this metric.
  Booked over-1×. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_selectors.scoped_model_id_enabled_p`
  (`scoped-model-id-enabled-p` vs `isEnabled`). Observed `smie_all` /
  `smie_hit` / `smie_miss` / `smie_empty` / `smie_stale` /
  `smie_all_stale` exact. n=5 **0.775×** (0.167 / 0.215 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 563). Gate rc=1 only
  from known old holes, not this metric.
- Goal 20 P.13 leftover: pair `cli_selectors.scoped_models_toggle_id`
  (`scoped-models-toggle-id` vs `toggle`). Observed `smti_from_all` /
  `smti_remove` / `smti_add` / `smti_empty` / `smti_again` /
  `smti_unavail` exact. n=5 **1.191×** (1.098 / 0.922 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 564). Gate rc=1 only
  from known old holes, not this metric. Booked over-1×.
- Goal 20 P.13 leftover: pair `cli_selectors.model_selector_provider_badge`
  (`model-selector-provider-badge` on
  `src/cadr-cli/interactive/selectors/models.lisp` vs baseline
  `` [`${provider}`] ``). Observed `mspb_openai` / `mspb_anthropic` /
  `mspb_codex` / `mspb_google` / `mspb_openrouter` / `mspb_hit` exact.
  n=5 **0.307×** (0.126 / 0.411 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 559). Gate rc=1 only from known old holes,
  not this metric. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_selectors.scoped_models_copy_enabled`
  (`scoped-models-copy-enabled` vs `enabledModelIds` copy). Observed
  `smce_all` / `smce_two` / `smce_empty` / `smce_one` / `smce_three` /
  `smce_unavail` exact. n=5 **1.960×** (1.074 / 0.548 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 560). Gate rc=1 only
  from known old holes, not this metric. Booked over-1×.
- Goal 20 P.13 leftover: pair `cli_selectors.move_list_item`
  (`move-list-item` vs `move()` index swap). Observed `mli_swap` /
  `mli_ends` / `mli_neg` / `mli_over` / `mli_same` / `mli_empty` exact.
  n=5 **1.357×** (1.317 / 0.971 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 561). Gate rc=1 only from known old holes,
  not this metric. Booked over-1×.
- Goal 20 P.13 leftover: pair `cli_selectors.countdown_seconds`
  (`make-countdown-timer` remaining seconds on
  `src/cadr-cli/interactive/components/countdown.lisp` vs baseline
  `Math.ceil(timeoutMs / 1000)`). Observed `cds_0` / `cds_1` /
  `cds_1000` / `cds_1001` / `cds_1500` / `cds_999` exact. n=5 **2.292×**
  (0.768 / 0.335 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 556). Gate rc=1 only from known old holes, not this metric.
  Booked in `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum`
  left unchanged.
- Goal 20 P.13 leftover: pair `cli_selectors.countdown_tick`
  (`countdown-timer-tick` vs CountdownTimer interval body). Observed
  `cdt_make` / `cdt_remain` / `cdt_expired` / `cdt_ticks` / `cdt_expires` /
  `cdt_renders` exact. n=5 **3.006×** (0.700 / 0.233 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 557). Gate rc=1 only
  from known old holes, not this metric. Booked over-1×.
- Goal 20 P.13 leftover: pair `cli_selectors.countdown_render`
  (`countdown-request-render` vs `tui?.requestRender`). Observed
  `cdr_fn1` / `cdr_fn2` / `cdr_nil` / `cdr_sym` / `cdr_zero` / `cdr_fn3`
  exact. n=5 **1.928×** (0.892 / 0.463 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 558). Gate rc=1 only from known old holes,
  not this metric. Booked over-1×.
- Goal 20 P.13 leftover: pair `cli_bootstrap_sessions.session_argument_path`
  (`session-argument-path-p` on `src/cadr-cli/bootstrap/sessions.lisp` vs
  baseline `resolveSessionPath` path test). Observed `sap_slash` /
  `sap_backslash` / `sap_jsonl` / `sap_id` / `sap_empty` / `sap_json` exact.
  n=5 **0.852×** (0.371 / 0.436 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 553). Gate rc=1 only from known old holes,
  not this metric. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_bootstrap_sessions.split_command`
  (`split-command` vs interactive-mode first-space slash-command split).
  Observed `sc_name` / `sc_name_arg` / `sc_pad` / `sc_import` / `sc_empty` /
  `sc_tab` exact. n=5 **0.568×** (1.339 / 2.356 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 554). Gate rc=1 only from known
  old holes, not this metric.
- Goal 20 P.13 leftover: pair `cli_bootstrap_sessions.path_command_argument`
  (`path-command-argument` vs `getPathCommandArgument`). Observed
  `pca_none` / `pca_plain` / `pca_dq` / `pca_sq` / `pca_unclosed` /
  `pca_extra` exact. n=5 **0.802×** (0.713 / 0.889 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 555). Gate rc=1 only from known
  old holes, not this metric.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.framed_select_title`
  (`framed-select-title` on `src/cadr-cli/interactive/extension-ui.lisp` vs
  baseline ExtensionSelector countdown title). Observed `fst_plain` /
  `fst_ceil` / `fst_exact` / `fst_zero` / `fst_neg` / `fst_empty` exact.
  n=5 **1.406×** (0.775 / 0.551 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 550). Gate rc=1 only from known old holes,
  not this metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.extension_overlay_options`
  (`extension-overlay-options` vs `showExtensionCustom` resolveOptions).
  Observed `eoo_nil` / `eoo_static` / `eoo_fn` / `eoo_pct` / `eoo_zero` /
  `eoo_width` exact. n=5 **2.114×** (1.270 / 0.601 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 551). Gate rc=1 only from known
  old holes, not this metric. Booked over-1×.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.extension_custom_ui_visible`
  (`extension-custom-ui-visible-p` vs overlay hidden/visible flags). Observed
  `ecu_default` / `ecu_width` / `ecu_vis_nil` / `ecu_visp_nil` / `ecu_vis_t` /
  `ecu_fn_nil` exact. n=5 **1.866×** (1.027 / 0.551 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 552). Gate rc=1 only from known
  old holes, not this metric. Booked over-1×.
- Goal 20 P.13 leftover: pair `cli_selectors.daxnuts_parse_image`
  (`parse-daxnuts-rgb-grid` on `src/cadr-cli/interactive/components/daxnuts.lisp`
  vs baseline `parseImage`). Observed `dpi_00` / `dpi_0x` / `dpi_mid` /
  `dpi_last` / `dpi_h` / `dpi_w` exact. n=5 **0.557×** (50.293 / 90.217 µs)
  on host `cursor`, ceiling 8.0. Measure-only leftover (Pair 547). Gate rc=1
  only from known old holes, not this metric. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_selectors.daxnuts_image_line`
  (`daxnuts-image-line` vs baseline `buildImage` half-block row). Observed
  `dil_0` / `dil_7` / `dil_15` / `dil_0_len` / `dil_15_len` / `dil_reset`
  exact. n=5 **2.220×** (36.319 / 16.357 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 548). Gate rc=1 only from known old holes,
  not this metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `cli_selectors.daxnuts_center_line`
  (`center-component-line` vs baseline `render()` `center`). Observed
  `dcl_plain` / `dcl_odd` / `dcl_narrow` / `dcl_empty` / `dcl_ansi` /
  `dcl_wide` exact. n=5 **0.970×** (0.896 / 0.924 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 549). Gate rc=1 only from known
  old holes, not this metric.
- Goal 20 P.13 leftover: pair `cli_extensions_install.llama_context_label` (`llama-context-label` on
  `src/cadr-cli/extensions/llama/ui.lisp` vs baseline `contextLabel`). Observed
  `cl_meta` / `cl_train` / `cl_args` / `cl_small` / `cl_none` / `cl_dashc` exact.
  n=5 **1.143×** (1.279 / 1.119 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 544). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_extensions_install.llama_model_description` (`llama-model-description` on
  `src/cadr-cli/extensions/llama/ui.lisp` vs baseline `modelDescription`). Observed
  `md_loaded` / `md_sleep` / `md_unload` / `md_load` / `md_down` / `md_nocontext` exact.
  n=5 **1.130×** (1.450 / 1.283 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 545). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_extensions_install.llama_compact_count` (`llama-compact-count` on
  `src/cadr-cli/extensions/llama/ui.lisp` vs baseline `compactCount`). Observed
  `cc_small` / `cc_k` / `cc_k0` / `cc_m` / `cc_m0` / `cc_999` exact.
  n=5 **1.511×** (0.968 / 0.641 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 546). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.fit_footer_text` (`fit-footer-text` on
  `src/cadr-cli/interactive/footer.lisp` vs baseline `truncateToWidth`). Observed
  `fft_short` / `fft_long` / `fft_cjk` / `fft_empty` / `fft_zero` / `fft_emoji` exact.
  n=5 **1.038×** (21.385 / 20.600 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 541). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.footer_usage` (`footer-usage-summary` on
  `src/cadr-cli/interactive/footer.lisp` vs baseline `addUsageToTotals` plus cadr format). Observed
  `fu_kimi` / `fu_plain` / `fu_zero` / `fu_nocache` / `fu_case` / `fu_cost0` exact.
  n=5 **2.049×** (7.216 / 3.522 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 542). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.footer_git_paths` (`find-git-footer-paths` on
  `src/cadr-cli/interactive/footer.lisp` vs baseline `findGitPaths`). Observed
  `fgp_repo` / `fgp_nested` / `fgp_worktree` / `fgp_common` / `fgp_nohead` / `fgp_none` exact.
  n=5 **1.649×** (214.734 / 130.225 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 543). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.colorfgbg_index`
  (`colorfgbg-background-index` on
  `src/cadr-cli/interactive/theme.lisp`). Observed `cfg_plain` /
  `cfg_last` / `cfg_skip` / `cfg_miss` / `cfg_pad` / `cfg_empty` exact.
  n=5 **1.605×** (1.430 / 0.891 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 538). Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.rgb_background`
  (`rgb-background-theme` on
  `src/cadr-cli/interactive/theme.lisp`). Observed `rgb_black` /
  `rgb_white` / `rgb_mid` / `rgb_187` / `rgb_188` / `rgb_red` exact.
  n=5 **0.659×** (2.180 / 3.309 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 539). cadr leads. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.detect_background`
  (`detect-background-from-environment` on
  `src/cadr-cli/interactive/theme.lisp`). Observed `dbg_white` /
  `dbg_black` / `dbg_none` / `dbg_empty` / `dbg_bad` / `dbg_pair` exact.
  n=5 **0.863×** (3.025 / 3.504 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 540). cadr leads. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.clipboard_candidates`
  (`clipboard-command-candidates` on
  `src/cadr-cli/interactive/clipboard.lisp`). Observed `ccand_darwin` /
  `ccand_win` / `ccand_none` / `ccand_termux` / `ccand_wl` / `ccand_x11`
  exact. n=5 **1.405×** (2.349 / 1.672 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 535). Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.osc52_copy`
  (`osc52-copy-sequence` on
  `src/cadr-cli/interactive/clipboard.lisp`). Observed `osc_hello` /
  `osc_empty` / `osc_cjk` / `osc_over` / `osc_emoji` / `osc_bound` exact.
  n=5 **1.043×** (1.614 / 1.547 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 536). Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.clipboard_copy`
  (`copy-to-clipboard` on
  `src/cadr-cli/interactive/clipboard.lisp`). Observed `cc_darwin` /
  `cc_linux_shell` / `cc_remote` / `cc_osc` / `cc_win` / `cc_termux` exact.
  n=5 **1.137×** (1.911 / 1.680 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 537). Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_selectors.thinking_level_label`
  (`thinking-level-label` on
  `src/cadr-cli/interactive/selectors/thinking.lisp`). Observed `tll_off` /
  `tll_minimal` / `tll_xhigh` / `tll_max` / `tll_low` / `tll_bogus` exact.
  n=5 **0.887×** (0.223 / 0.251 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 532). cadr leads. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_selectors.thinking_level_search_text`
  (`thinking-level-search-text` on
  `src/cadr-cli/interactive/selectors/thinking.lisp`). Observed `tlst_off` /
  `tlst_minimal` / `tlst_high` / `tlst_xhigh` / `tlst_max` / `tlst_bogus`
  exact. n=5 **2.096×** (1.090 / 0.520 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 533). Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_selectors.thinking_selector_set_query`
  (`thinking-selector-set-query` on
  `src/cadr-cli/interactive/selectors/thinking.lisp`). Observed `tsq_empty` /
  `tsq_off` / `tsq_high` / `tsq_miss` / `tsq_nil` / `tsq_clear` exact.
  n=5 **1.081×** (11.827 / 10.942 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 534). Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_selectors.login_dialog_make`
  (`make-login-dialog-state` on
  `src/cadr-cli/interactive/selectors/login-dialog.lisp`). Observed
  `ldm_empty_n` / `ldm_named` / `ldm_named_sec` / `ldm_long` / `ldm_input` /
  `ldm_long_n` exact. n=5 **0.543×** (0.169 / 0.312 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 529). cadr leads.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_selectors.login_dialog_auth`
  (`login-dialog-show-auth` on
  `src/cadr-cli/interactive/selectors/login-dialog.lisp`). Observed
  `lda_plain` / `lda_instr` / `lda_empty_instr` / `lda_replace` /
  `lda_provider` / `lda_n` exact. n=5 **1.039×** (1.925 / 1.853 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 530). Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_selectors.login_dialog_device`
  (`login-dialog-show-device-code` on
  `src/cadr-cli/interactive/selectors/login-dialog.lisp`). Observed
  `ldd_code` / `ldd_empty` / `ldd_replace` / `ldd_provider` / `ldd_n` /
  `ldd_hint` exact. n=5 **2.148×** (3.653 / 1.701 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 531). Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_selectors.user_message_make`
  (`make-user-message-selector-state` on
  `src/cadr-cli/interactive/selectors/fork.lisp`). Observed `umm_empty` /
  `umm_one` / `umm_two` / `umm_hit` / `umm_miss` / `umm_copy` exact.
  n=5 **0.530×** (0.760 / 1.434 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 526). cadr leads. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_selectors.user_message_move`
  (`user-message-selector-move` on
  `src/cadr-cli/interactive/selectors/fork.lisp`). Observed `umv_empty` /
  `umv_wrap_fwd` / `umv_back` / `umv_full` / `umv_three_back` /
  `umv_three_fwd` exact. n=5 **0.526×** (0.826 / 1.572 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 527). cadr leads.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_selectors.user_message_selection`
  (`user-message-selector-selection` on
  `src/cadr-cli/interactive/selectors/fork.lisp`). Observed `ums_empty` /
  `ums_last` / `ums_hit` / `ums_wrap` / `ums_miss` / `ums_one` exact.
  n=5 **0.553×** (0.862 / 1.559 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 528). cadr leads. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.theme_primitive`
  (`valid-tui-theme-primitive-p` on `src/cadr-cli/interactive/themes.lisp`).
  Observed `tp_str` / `tp_int` / `tp_255` / `tp_256` / `tp_neg` / `tp_nil` exact.
  n=5 **0.472×** (0.110 / 0.233 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 523). cadr leads. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.theme_resolve`
  (`resolve-tui-theme-value` on `src/cadr-cli/interactive/themes.lisp`).
  Observed `tr_int` / `tr_empty` / `tr_hex` / `tr_var` / `tr_cycle` /
  `tr_miss` exact. n=5 **0.184×** (1.442 / 7.853 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 524). cadr leads.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.theme_validate`
  (`validate-tui-theme-object` on `src/cadr-cli/interactive/themes.lisp`).
  Observed `tv_ok` / `tv_slash` / `tv_unknown` exact. n=5 **0.795×**
  (20.435 / 25.698 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 525). cadr leads. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.tool_session_make`
  (`make-tool-render-session` on `src/cadr-cli/interactive/tool-render-session.lisp`).
  Observed `tsm_name` / `tsm_pending` / `tsm_nil` exact. n=5 **1.224×**
  (0.257 / 0.210 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 520). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text / `execution_env.tmp_*`), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.tool_session_update`
  (`update-tool-render-session` on `src/cadr-cli/interactive/tool-render-session.lisp`).
  Observed `tsu_result` / `tsu_pending` / `tsu_cleared` exact. n=5
  **1.151×** (0.266 / 0.231 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 521). Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`), not this metric.
  Booked in `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.tool_session_render`
  (`render-tool-session` on `src/cadr-cli/interactive/tool-render-session.lisp`).
  Observed `trr_pending_n` / `trr_pending_call` / `trr_done_n` /
  `trr_done_result` / `trr_custom` / `trr_empty` exact. n=5 **0.969×**
  (1.733 / 1.789 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 522). cadr leads. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.wrap_transcript`
  (`wrap-transcript-lines` on `src/cadr-cli/interactive/transcript.lisp`).
  Observed `wt_nil` / `wt_one_n` / `wt_one_order` / `wt_two_n` /
  `wt_two_first` / `wt_two_last` exact. n=5 **1.003×**
  (0.601 / 0.599 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 517). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text / `execution_env.tmp_*`), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.output_padding`
  (`output-padding-string` on `src/cadr-cli/interactive/transcript.lisp`).
  Observed `op_0` / `op_1` / `op_other` / `op_space` exact. n=5
  **0.987×** (0.226 / 0.229 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 518). cadr leads. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.render_cacheable`
  (`tui-entry-render-cacheable-p` on `src/cadr-cli/interactive/transcript.lisp`).
  Observed `rc_assist` / `rc_stream` / `rc_tool_nil` / `rc_tool_done` /
  `rc_tool_run` / `rc_custom` exact. n=5 **2.515×** (1.461 / 0.581 µs)
  on host `cursor`, ceiling 8.0. Measure-only leftover (Pair 519).
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text /
  `execution_env.tmp_*`), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_selectors.armin_pixel`
  (`armin-pixel-p` on `src/cadr-cli/interactive/components/armin.lisp`).
  Observed `ap_blank` / `ap_ink` / `ap_out` exact. n=5 **0.548×**
  (0.126 / 0.230 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 514). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text / `execution_env.tmp_*`), not this metric. cadr leads.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_selectors.armin_cell`
  (`armin-cell` on `src/cadr-cli/interactive/components/armin.lisp`).
  Observed `ac_space` / `ac_lower` / `ac_upper` / `ac_full` exact. n=5
  **0.444×** (0.307 / 0.691 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 515). cadr leads. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_selectors.armin_grid_height`
  (`armin-grid-height` on `src/cadr-cli/interactive/components/armin.lisp`).
  Observed `ag_h` exact. n=5 **0.870×** (0.081 / 0.093 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 516). cadr leads.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.sanitize_title`
  (`sanitize-terminal-title-text` on `src/cadr-cli/interactive/controller.lisp`).
  Observed `st_plain` / `st_esc` / `st_bel` / `st_nil` / `st_empty` exact.
  n=5 **0.895×** (0.586 / 0.655 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 511). Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`), not this
  metric. cadr leads. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.title_basename`
  (`tui-terminal-title-cwd-basename` on `src/cadr-cli/interactive/controller.lisp`).
  Observed `bn_unix` / `bn_win` / `bn_plain` / `bn_empty` / `bn_nil` exact.
  n=5 **0.393×** (0.353 / 0.898 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 512). cadr leads. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.terminal_title`
  (`tui-terminal-title` on `src/cadr-cli/interactive/controller.lisp`).
  Observed `tt_none` / `tt_session` / `tt_esc` / `tt_empty` exact.
  n=5 **0.645×** (1.530 / 2.370 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 513). cadr leads. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `bash_tool.live_output`
  (`bash-live-output-for-mode` on `src/cadr-cli/tools/bash.lisp`).
  Observed `lo_repl` / `lo_tui` / `lo_print` / `lo_rpc` exact. n=5
  **0.479×** (0.105 / 0.218 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 508). Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`), not this
  metric. cadr leads. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `bash_tool.strip_status`
  (`bash-strip-status-footer` on `src/cadr-cli/tools/bash.lisp`). Observed
  `ss_exact` / `ss_nl` / `ss_plain` / `ss_trim` exact. n=5 **0.773×**
  (0.417 / 0.540 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 509). cadr leads. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `bash_tool.strip_truncation`
  (`bash-strip-truncation-footer` on `src/cadr-cli/tools/bash.lisp`).
  Observed `st_none` / `st_footer` / `st_no_full` / `st_plain` exact. n=5
  **5.885×** (2.331 / 0.396 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 510). Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`), not this
  metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_extensions_install.gated_approval`
  (`llama-gated-approval-text` on
  `src/cadr-cli/extensions/llama/extension.lisp`). Observed `ga_manual` /
  `ga_auto` / `ga_str` / `ga_nil` exact. n=5 **0.579×** (0.120 / 0.208 µs)
  on host `cursor`, ceiling 8.0. Measure-only leftover (Pair 505). Gate
  rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text /
  `execution_env.tmp_*`), not this metric. cadr leads. `nextPairNum`
  left unchanged.
- Goal 20 P.13 leftover: pair `cli_extensions_install.split_args`
  (`split-llama-command-arguments` on
  `src/cadr-cli/extensions/llama/extension.lisp`). Observed `sa_login` /
  `sa_view` / `sa_bare` / `sa_tab` exact. n=5 **0.408×** (0.827 / 2.025 µs)
  on host `cursor`, ceiling 8.0. Measure-only leftover (Pair 506). cadr
  leads. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_extensions_install.quant_label`
  (`llama-quantization-option-label` on
  `src/cadr-cli/extensions/llama/extension.lisp`). Observed `ql_name` /
  `ql_rec` / `ql_bytes` / `ql_both` exact. n=5 **1.249×** (1.033 / 0.827 µs)
  on host `cursor`, ceiling 8.0. Measure-only leftover (Pair 507). Gate
  rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text /
  `execution_env.tmp_*`), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left
  unchanged.
- Goal 20 P.13 leftover: pair `cli_extensions_install.package_fragment`
  (`extension-package-fragment` on `src/cadr-cli/extensions/loader.lisp`).
  Observed `pf_plain` / `pf_hyphen` / `pf_keep` / `pf_empty` exact. n=5
  **0.351×** (0.468 / 1.334 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 502). Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`), not this
  metric. cadr leads. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_extensions_install.local_system_name`
  (`extension-local-system-name-p` on
  `src/cadr-cli/extensions/loader.lisp`). Observed `ls_ok` / `ls_empty` /
  `ls_dot` / `ls_slash` exact. n=5 **0.273×** (0.192 / 0.704 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 503). cadr leads.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_extensions_install.inline_factory`
  (`valid-inline-extension-factory-p` on
  `src/cadr-cli/extensions/loader.lisp` vs `loadExtensionFromFactory`
  input check). Observed `if_fn` / `if_plist` / `if_empty_name` /
  `if_no_factory` exact. n=5 **0.260×** (0.188 / 0.725 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 504). cadr leads.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_extensions_install.unsafe_git`
  (`unsafe-git-source-p` on `src/cadr-cli/extensions/installer.lisp` vs
  `hasUnsafeGitInstallPart`). Observed `ug_empty` / `ug_dash` / `ug_ok`
  / `ug_n` exact. n=5 **1.159×** (0.762 / 0.658 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 499). Gate rc=1 only from
  known old holes (`lc_n` / `lc_sleep` / help text /
  `execution_env.tmp_*`), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left
  unchanged.
- Goal 20 P.13 leftover: pair `cli_extensions_install.git_path`
  (`git-source-path` on `src/cadr-cli/extensions/installer.lisp` vs git
  URL path slice). Observed `gp_https` / `gp_scp` / `gp_slash` /
  `gp_miss` exact. n=5 **1.852×** (1.055 / 0.569 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 500). Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left
  unchanged.
- Goal 20 P.13 leftover: pair `cli_extensions_install.normalize_git`
  (`normalize-git-install-source` on
  `src/cadr-cli/extensions/installer.lisp` vs `parseGitUrl` + extension
  name). Observed `ng_https` / `ng_git` / `ng_file` / `ng_empty` /
  `ng_bare` exact. n=5 **0.369×** (4.884 / 13.233 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 501). cadr leads.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_print_rpc.handle_bad_json`
  (`rpc-handle-line` on `src/cadr-cli/modes/rpc/mode.lisp` vs
  `handleInputLine` JSON.parse catch). Observed `bj_cmd` / `bj_ok` /
  `bj_id` / `bj_nl` exact. n=5 **1.092×** (5.390 / 4.937 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 496). Gate rc=1
  only from known old holes (`lc_n` / `lc_sleep` / help text /
  `execution_env.tmp_*`), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left
  unchanged.
- Goal 20 P.13 leftover: pair `cli_print_rpc.handle_not_object`
  (`rpc-handle-line` on `src/cadr-cli/modes/rpc/mode.lisp` vs
  require-object). Observed `no_cmd` / `no_ok` / `no_id` / `no_nl`
  exact. n=5 **1.066×** (5.213 / 4.889 µs) on host `cursor`, ceiling
  8.0. Measure-only leftover (Pair 497). Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left
  unchanged.
- Goal 20 P.13 leftover: pair `cli_print_rpc.handle_ui_miss`
  (`rpc-handle-line` on `src/cadr-cli/modes/rpc/mode.lisp` vs
  unknown `extension_ui_response`). Observed `um_cmd` / `um_ok` /
  `um_id` / `um_nl` / `um_unk` exact. n=5 **4.070×** (6.190 / 1.521 µs)
  on host `cursor`, ceiling 8.0. Measure-only leftover (Pair 498).
  Booked in `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum`
  left unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.make_entry`
  (`make-tui-user-bash-entry` on
  `src/cadr-cli/interactive/user-bash.lisp` vs
  `BashExecutionComponent` constructor). Observed `me_label` / `me_run`
  / `me_ex` / `me_n` exact. n=5 **5.982×** (1.424 / 0.238 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 493). Gate rc=1
  only from known old holes (`lc_n` / `lc_sleep` / help text /
  `execution_env.tmp_*`), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left
  unchanged.
- Goal 20 P.13 leftover: pair `cli_interactive_controller.append_output`
  (`append-tui-user-bash-output` on
  `src/cadr-cli/interactive/user-bash.lisp` vs `appendOutput`). Observed
  `ao_text` / `ao_n` / `ao_skip` exact. n=5 **2.670×** (0.776 / 0.290 µs)
  on host `cursor`, ceiling 8.0. Measure-only leftover (Pair 494).
  Booked in `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum`
  left unchanged.
- Goal 20 P.13 leftover: pair
  `cli_interactive_controller.complete_entry`
  (`complete-tui-user-bash-entry` on
  `src/cadr-cli/interactive/user-bash.lisp` vs `setComplete`). Observed
  `ce_text` / `ce_exit` / `ce_path` / `ce_err` exact. n=5 **2.411×**
  (0.974 / 0.404 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 495). Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_bootstrap_sessions.parse_bash`
  (`parse-user-bash-input` on `src/cadr-cli/repl.lisp` vs interactive
  `!` / `!!` extract). Observed `pb_ls` / `pb_excl` / `pb_ws` / `pb_n`
  exact. n=5 **0.421×** (0.528 / 1.252 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 490). Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`), not this
  metric. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_bootstrap_sessions.response_text`
  (`response-text` on `src/cadr-cli/repl.lisp` vs `textParts.join`).
  Observed `rt_one` / `rt_two` / `rt_empty` / `rt_n` exact. n=5
  **1.314×** (0.939 / 0.714 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 491). Gate rc=1 only from known old holes,
  not this metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_bootstrap_sessions.dispatch_plain`
  (`dispatch-user-input` on `src/cadr-cli/repl.lisp` vs submit
  classify). Observed `dp_empty` / `dp_plain` / `dp_slash` / `dp_bash`
  / `dp_n` exact. n=5 **0.446×** (0.543 / 1.216 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 492). Gate rc=1 only from
  known old holes, not this metric. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_extensions_install.split_command`
  (`split-extension-command` on
  `src/cadr-cli/extensions/commands.lisp` vs `_tryExecuteExtensionCommand`
  spaceIndex split).   Observed `sc_reload` / `sc_foo` / `sc_plain` /
  `sc_blank` exact. n=5 **0.282×** (0.465 / 1.652 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 487). Gate rc=1 only from
  known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_extensions_install.handle_plain`
  (`handle-extension-command` on
  `src/cadr-cli/extensions/commands.lisp` vs non-slash miss). Observed
  `hp_hello` / `hp_ws` / `hp_blank` exact. n=5 **0.449×** (0.344 /
  0.766 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 488). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_extensions_install.handle_unknown`
  (`handle-extension-command` unknown slash on
  `src/cadr-cli/extensions/commands.lisp` vs `getCommand` miss). Observed
  `hu_nope` / `hu_miss` / `hu_n` exact. n=5 **0.561×** (0.474 /
  0.845 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 489). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_bootstrap_sessions.model_cycle`
  (`model-cycle-target-entry` on
  `src/cadr-cli/bootstrap/commands.lisp` vs `_cycleScopedModel` index wrap).
  Observed `mc_fwd` / `mc_bwd` / `mc_wrap` / `mc_miss` / `mc_one` /
  `mc_empty` exact. n=5 **0.622×** (0.632 / 1.017 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 484). Gate rc=1 only from
  known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_bootstrap_sessions.model_scope_line`
  (`model-scope-startup-line` on
  `src/cadr-cli/bootstrap/commands.lisp` vs interactive-mode init
  `Model scope:` line).   Observed `ms_quiet` / `ms_empty` / `ms_text` /
  `ms_n` / `ms_disabled` exact. n=5 **1.608×** (37.431 / 23.274 µs) on
  host `cursor`, ceiling 8.0. Measure-only leftover (Pair 485). Gate
  rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_bootstrap_sessions.process_files`
  (`process-cli-file-arguments` on
  `src/cadr-cli/bootstrap/commands.lisp` vs `processFileArguments`).
  Observed `pf_hello` / `pf_n` / `pf_img` exact. n=5
  **0.419×** (61.164 / 146.148 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 486). Gate rc=1 only from known old
  holes (`lc_n` / `lc_sleep` / help text), not this metric.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_support.watch_retry_delay`
  (`+fs-watch-retry-delay-milliseconds+` on
  `src/cadr-cli/support/file-watcher.lisp` vs `FS_WATCH_RETRY_DELAY_MS`).
  Observed `rd_eq` / `rd_ms` / `rd_pos` exact. n=5 **0.669×** (0.067 /
  0.101 µs) on host `cursor`, ceiling 8.0. Measure-only leftover (Pair
  481). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help
  text), not this metric. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_support.close_watcher`
  (`close-watcher` on `src/cadr-cli/support/file-watcher.lisp` vs
  `closeWatcher`). Observed `cl_nil` / `cl_twice` / `cl_ok` exact. n=5
  **0.645×** (0.068 / 0.105 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 482). Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13 leftover: pair `cli_support.watch_signature`
  (`watched-path-signature` on `src/cadr-cli/support/file-watcher.lisp` vs
  `statSync` mtime+size presence). Observed `sg_miss` / `sg_hit` / `sg_n`
  exact. n=5 **5.379×** (12.165 / 2.262 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 483). Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `skill_prompt_load.sdk_prompt_input`
  (`sdk-resolve-prompt-input` on `src/cadr-cli/sdk/resource-service.lisp` vs
  `resolvePromptInput`). Observed `si_nil` / `si_lit` / `si_file` exact.
  n=5 **4.322×** (15.179 / 3.512 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 478). Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `skill_prompt_load.sdk_list_override`
  (`sdk-apply-resource-list-override` on
  `src/cadr-cli/sdk/resource-service.lisp` vs DefaultResourceLoader
  `skillsOverride` apply). Observed `ov_none` / `ov_replace` / `ov_keep`
  exact. n=5 **0.365×** (0.188 / 0.516 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 479). Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13 leftover: pair `skill_prompt_load.sdk_context_files`
  (`sdk-context-file-records` on `src/cadr-cli/sdk/resource-service.lisp` vs
  agentsFiles path+content records). Observed `cf_n` / `cf_path` /
  `cf_text` exact. n=5 **2.879×** (7.556 / 2.625 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 480). Gate rc=1 only from known
  old holes (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `cli_print_rpc.queue_mode`
  (`parse-queue-mode` on `src/cadr-cli/modes/rpc/commands.lisp` vs RPC
  steering/follow-up mode strings). Observed `qm_all` / `qm_one` / `qm_bad`
  exact. n=5 **0.116×** (0.316 / 2.720 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 475). Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric. `nextPairNum` left
  unchanged.
- Goal 20 P.13 leftover: pair `cli_print_rpc.last_assistant`
  (`rpc-last-assistant-text` on `src/cadr-cli/modes/rpc/commands.lisp` vs
  `getLastAssistantText`). Observed `la_hit` / `la_len` / `la_miss` exact.
  n=5 **0.713×** (0.285 / 0.400 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 476). Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13 leftover: pair `cli_print_rpc.command_list`
  (`rpc-command-list` on `src/cadr-cli/modes/rpc/commands.lisp` vs
  `get_commands` extension+prompt walk). Observed `cl_n` / `cl_ext` /
  `cl_prompt` exact. n=5 **4.151×** (1.490 / 0.359 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 477). Gate rc=1 only from known
  old holes (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `skill_prompt_load.resolve_prompt`
  (`resolve-system-prompt` on `src/cadr-cli/system-prompt.lisp` vs
  `resolvePromptInput`). Observed `rp_lit` / `rp_file` / `rp_miss` exact.
  n=5 **3.636×** (16.882 / 4.643 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 472). Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `skill_prompt_load.node_read_error`
  (`node-read-error-message` on `src/cadr-cli/system-prompt.lisp` vs Node
  fs errno text). Observed `nr_eisdir` / `nr_eacces` / `nr_other` exact.
  n=5 **3.120×** (10.042 / 3.219 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 473). Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `skill_prompt_load.prompt_appends`
  (`resolve-system-prompt-with-appends` on `src/cadr-cli/system-prompt.lisp`
  vs appendSystemPrompt join). Observed `pa_len` / `pa_join` / `pa_base`
  exact. n=5 **3.268×** (6.306 / 1.930 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 474). Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `settings_load.sdk_nonempty`
  (`sdk-nonempty-setting-string` on `src/cadr-cli/sdk/settings-service.lisp` vs
  SettingsManager nonempty defaultProvider). Observed `sn_prov` / `sn_empty` /
  `sn_miss` exact. n=5 **3.319×** (20.855 / 6.284 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 469). Gate rc=1 only from known
  old holes (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `settings_load.sdk_boolean`
  (`sdk-settings-boolean` on `src/cadr-cli/sdk/settings-service.lisp` vs
  compaction.enabled boolean). Observed `sb_on` / `sb_def` / `sb_miss` exact.
  n=5 **2.136×** (13.423 / 6.283 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 470). Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `settings_load.sdk_tools`
  (`sdk-settings-enabled-tools` on `src/cadr-cli/sdk/settings-service.lisp` vs
  defaultTools list). Observed `st_n` / `st_read` / `st_none` exact. n=5
  **2.037×** (12.769 / 6.268 µs) on host `cursor`, ceiling 8.0. Measure-only
  leftover (Pair 471). Gate rc=1 only from known old holes (`lc_n` /
  `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `cli_print_rpc.dialog_request`
  (`rpc-dialog-request-object` on `src/cadr-cli/modes/rpc/ui.lisp` vs
  `createDialogPromise` request object). Observed `dr_type` / `dr_method` /
  `dr_msg` / `dr_opt_n` / `dr_ph` / `dr_to` exact. n=5 **3.471×** (1.129 /
  0.325 µs) on host `cursor`, ceiling 8.0. Measure-only leftover (Pair 466).
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text), not
  this metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_print_rpc.dialog_result`
  (`rpc-dialog-result` on `src/cadr-cli/modes/rpc/ui.lisp` vs
  `createDialogPromise` parseResponse). Observed `rs_nil` / `rs_can` /
  `rs_ok` / `rs_val` / `rs_num` exact. n=5 **4.257×** (1.233 / 0.290 µs) on
  host `cursor`, ceiling 8.0. Measure-only leftover (Pair 467). Gate rc=1
  only from known old holes (`lc_n` / `lc_sleep` / help text), not this
  metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `cli_print_rpc.dialog_expired`
  (`rpc-dialog-expired-p` on `src/cadr-cli/modes/rpc/ui.lisp` vs
  `createDialogPromise` timeout). Observed `ex_nil` / `ex_zero` / `ex_future`
  exact. n=5 **0.410×** (0.094 / 0.229 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 468). Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13 leftover: pair `cli_print_rpc.rpc_images`
  (`rpc-images-from-json` on `src/cadr-cli/modes/rpc/prompt-bash.lisp` vs
  RPC prompt `command.images`). Observed `img_nil` / `img_n` / `img_mime` /
  `img_bad` exact. n=5 **0.657×** (2.260 / 3.439 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 463). Gate rc=1 only from known
  old holes (`lc_n` / `lc_sleep` / help text), not this metric.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_print_rpc.rpc_prompt`
  (`rpc-prompt-message` on `src/cadr-cli/modes/rpc/prompt-bash.lisp` vs RPC
  prompt message+images). Observed `rp_str` / `rp_len` / `rp_parts` /
  `rp_mime` exact. n=5 **2.266×** (1.323 / 0.584 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 464). Gate rc=1 only from known
  old holes (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `cli_print_rpc.bash_result`
  (`rpc-bash-result-json` on `src/cadr-cli/modes/rpc/prompt-bash.lisp` vs RPC
  bash result payload). Observed `br_out` / `br_code` / `br_can` / `br_tr` /
  `br_path` / `br_null` exact. n=5 **2.913×** (2.165 / 0.743 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 465). Gate rc=1 only
  from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
  Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `cli_support.no_models_help`
  (`format-no-models-available-message` on `src/cadr-cli/support/model-help.lisp`
  vs `formatNoModelsAvailableMessage`). Observed `nm_pref` / `nm_login` /
  `nm_prov` exact. n=5 **27.45×** (244.9 / 8.92 µs) on host `cursor`, ceiling
  50.0 (same docs-dir sibling as `ai_support.auth_guidance`). Measure-only
  leftover (Pair 460). Gate rc=1 only from known old holes (`lc_n` /
  `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_support.no_model_selected`
  (`format-no-model-selected-message` on `src/cadr-cli/support/model-help.lisp`
  vs `formatNoModelSelectedMessage`). Observed `ns_pref` / `ns_then` / `ns_nl`
  exact. n=5 **27.67×** (245.4 / 8.87 µs) on host `cursor`, ceiling 50.0.
  Measure-only leftover (Pair 461). Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `cli_support.no_api_key`
  (`format-no-api-key-found-message` on `src/cadr-cli/support/model-help.lisp`
  vs `formatNoApiKeyFoundMessage`). Observed `nk_oai` / `nk_unk` / `nk_sel`
  exact. n=5 **27.48×** (480.3 / 17.48 µs) on host `cursor`, ceiling 50.0.
  Measure-only leftover (Pair 462). Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `cli_bootstrap_sessions.legacy_product`
  (`legacy-product-name` on `src/cadr-cli/migration.lisp`). Observed `lp_len` /
  `lp_p` / `lp_i` exact. n=5 **1.178×** (0.171 / 0.145 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 457). Gate rc=1 only from known old
  holes (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_bootstrap_sessions.shell_quote`
  (`shell-single-quote` on `src/cadr-cli/migration.lisp`). Observed `sq_plain` /
  `sq_space` / `sq_quote` / `sq_empty` exact. n=5 **0.714×** (0.461 / 0.645 µs)
  on host `cursor`, ceiling 8.0. Measure-only leftover (Pair 458). Gate rc=1
  only from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13 leftover: pair `cli_bootstrap_sessions.affirmative`
  (`affirmative-response-p` on `src/cadr-cli/migration.lisp`). Observed `af_y` /
  `af_yes` / `af_trim` / `af_no` exact. n=5 **0.584×** (0.371 / 0.635 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 459). Gate rc=1 only from
  known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13 leftover: pair `settings_load.provider_symbol` (`provider-symbol` on
  `src/cadr-cli/config.lisp` vs upcase keyword intern). Observed `ps_openai` /
  `ps_mixed` / `ps_hyphen` exact. n=5 **1.351×** (0.313 / 0.231 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 454). Gate rc=1 only from
  known old holes (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `settings_load.parse_auth_provider`
  (`parse-auth-provider` on `src/cadr-cli/config.lisp` vs openai/anthropic OAuth
  identity). Observed `pap_openai` / `pap_anth` / `pap_codex` / `pap_bad` exact.
  n=5 **0.365×** (0.846 / 2.314 µs) on host `cursor`, ceiling 8.0. Measure-only
  leftover (Pair 455). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric.
- Goal 20 P.13 leftover: pair `settings_load.split_command_line`
  (`split-command-line` on `src/cadr-cli/config.lisp` vs space/tab split). Observed
  `scl_two` / `scl_trim` / `scl_empty` exact. n=5 **0.967×** (0.939 / 0.971 µs)
  on host `cursor`, ceiling 8.0. Measure-only leftover (Pair 456). Gate rc=1 only
  from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13 leftover: pair `cli_bootstrap_sessions.session_path`
  (`session-argument-path-p` on `src/cadr-cli/bootstrap/sessions.lisp` vs
  `resolveSessionPath` path heuristic). Observed `sp_id` / `sp_slash` /
  `sp_win` / `sp_jsonl` / `sp_plain` exact. n=5 **0.752×** (0.294 / 0.391 µs)
  on host `cursor`, ceiling 8.0. Measure-only leftover (Pair 451).
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `cli_bootstrap_sessions.split_command`
  (`split-command` on `src/cadr-cli/bootstrap/sessions.lisp`). Observed
  `sc_cmd` / `sc_arg` / `sc_only` / `sc_noarg` / `sc_cmd3` / `sc_rest` exact.
  n=5 **0.937×** (0.491 / 0.524 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 452).
- Goal 20 P.13 leftover: pair `cli_bootstrap_sessions.path_argument`
  (`path-command-argument` on `src/cadr-cli/bootstrap/sessions.lisp`).
  Observed `pa_plain` / `pa_quote` / `pa_empty` / `pa_miss` exact. n=5
  **0.598×** (0.379 / 0.633 µs) on host `cursor`, ceiling 8.0. Measure-only
  leftover (Pair 453).
- Goal 20 P.13 leftover: pair `find_tool.glob_regex` (`glob-regex-source` on
  `src/cadr-cli/tools/glob.lisp` vs glob pattern compile). Observed `gr_star` /
  `gr_glob` / `gr_q` / `gr_dot` exact. n=5 **2.403×** (0.527 / 0.220 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 448). Gate rc=1 only from
  known old holes (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `find_tool.glob_special` (`regex-special-p` on
  `src/cadr-cli/tools/glob.lisp` vs glob metacharacters). Observed `gs_dot` /
  `gs_star` / `gs_pipe` / `gs_bs` exact. n=5 **0.549×** (0.082 / 0.149 µs)
  on host `cursor`, ceiling 8.0. Measure-only leftover (Pair 449). Gate rc=1
  only from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13 leftover: pair `find_tool.gitignore_regex`
  (`gitignore-regex-source` on `src/cadr-cli/tools/glob.lisp` vs gitignore glob
  compile). Observed `gi_plain` / `gi_anch` / `gi_dir` exact. n=5 **1.142×**
  (0.693 / 0.607 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 450). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help
  text), not this metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `package_manager.update_argv`
  (`package-update-check-process-argv` on `src/cadr-cli/packages/update-checks.lisp`
  vs baseline git argv wrap). Observed `ua_setsid` / `ua_fork` / `ua_tail` /
  `ua_rest` exact. n=5 **3.587×** (5.696 / 1.588 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 445). Gate rc=1 only from known
  old holes (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `package_manager.update_env`
  (`package-update-check-environment` on `src/cadr-cli/packages/update-checks.lisp`
  vs `GIT_TERMINAL_PROMPT=0`). Observed `ue_first` / `ue_one` exact.
  n=5 **0.108×** (3.829 / 35.512 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 446). Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13 leftover: pair `package_manager.git_object_id`
  (`package-update-git-object-id` on `src/cadr-cli/packages/update-checks.lisp`
  vs `getRemoteGitHead` 40-hex extract). Observed `go_plain` / `go_nl` /
  `go_ls` / `go_upper` / `go_bad` exact. n=5 **1.916×** (2.328 / 1.215 µs)
  on host `cursor`, ceiling 8.0. Measure-only leftover (Pair 447). Gate rc=1
  only from known old holes (`lc_n` / `lc_sleep` / help text), not this
  metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `package_manager.normalize_pattern`
  (`config-normalize-pattern-path` on `src/cadr-cli/packages/config-selector.lisp`
  vs baseline `normalizeExactPattern`). Observed `np_dot` / `np_plain` /
  `np_win` exact. n=5 **0.650×** (0.444 / 0.683 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 442). Gate rc=1 only from known
  old holes (`lc_n` / `lc_sleep` / help text), not this metric.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `package_manager.resource_kinds`
  (`config-resource-kinds` on `src/cadr-cli/packages/config-selector.lisp`
  vs `RESOURCE_TYPES`). Observed `rk_n` / `rk_ext` / `rk_sk` / `rk_pr` /
  `rk_th` exact. n=5 **0.756×** (0.117 / 0.155 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 443). Gate rc=1 only from known
  old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13 leftover: pair `package_manager.type_label`
  (`config-resource-type-label` on `src/cadr-cli/packages/config-selector.lisp`
  vs `RESOURCE_TYPE_LABELS`). Observed `tl_ext` / `tl_sk` / `tl_pr` /
  `tl_th` exact. n=5 **1.002×** (0.135 / 0.134 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 444). Gate rc=1 only from known
  old holes (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `evals_harness.extension_authoring_input`
  (`extension-authoring-input` on `src/cadr-evals/suites.lisp` vs baseline
  `describeEval` input steps). Types/length only. Observed `ei_n` / `ei_t0` /
  `ei_t1` / `ei_t2` / `ei_c0` exact. n=5 **4.662×** (1.148 / 0.246 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 439). Gate rc=1 only
  from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
  Booked in `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left
  unchanged.
- Goal 20 P.13 leftover: pair `evals_harness.json_array_items`
  (`json-array-items` on `src/cadr-evals/suites.lisp` vs `Array.isArray`).
  Observed `ja_vec` / `ja_list` / `ja_atom` / `ja_nil` exact. n=5 **0.766×**
  (0.162 / 0.212 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 440). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric.
- Goal 20 P.13 leftover: pair `evals_harness.json_string` (`json-string` on
  `src/cadr-evals/suites.lisp` vs missing/false JSON string accessor).
  Observed `js_hit` / `js_miss` / `js_empty` exact. n=5 **5.012×** (0.902 /
  0.180 µs) on host `cursor`, ceiling 8.0. Measure-only leftover (Pair 441).
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `evals_harness.make_reporter` (`make-eval-harness-reporter`
  on `src/cadr-evals/reporter.lisp` vs baseline `EvalHarnessReporter` constructor plus
  `PI_EVAL_ARTIFACT_DIR` trim). Observed `mr_explicit` / `mr_env` / `mr_miss` / `mr_n`
  exact. n=5 **0.917×** (0.346 / 0.377 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 430). Gate rc=1 only from known old holes (`lc_n` /
  `lc_sleep` / help text), not this metric. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `evals_harness.finite_number` (`reporter-finite-number`
  on `src/cadr-evals/reporter.lisp` vs baseline `readFiniteNumber`). Observed
  `fn_int` / `fn_float` / `fn_nil` / `fn_inf` / `fn_str` / `fn_n` exact.
  n=5 **0.531×** (0.117 / 0.220 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 431). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric.
- Goal 20 P.13 leftover: pair `evals_harness.artifact_metadata` (`reporter-artifact-metadata`
  on `src/cadr-evals/reporter.lisp` vs baseline `appendHarnessRunReport` metadata filter).
  Observed `am_keep` / `am_runid` / `am_snap` / `am_n` exact.
  n=5 **1.182×** (1.025 / 0.868 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 432). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `tui_stdin_buffer.flush` (`stdin-buffer-flush`
  on `src/cadr-tui/stdin-buffer.lisp` vs baseline `StdinBuffer.flush`).
  Observed `fl_empty` / `fl_before` / `fl_n` / `fl_seq` / `fl_after` exact.
  n=5 **0.139×** (0.392 / 2.818 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric. Pairs 424–426. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `tui_stdin_buffer.clear` (`stdin-buffer-clear`
  on `src/cadr-tui/stdin-buffer.lisp` vs baseline `StdinBuffer.clear`).
  Observed `cl_before` / `cl_after` / `cl_hello` / `cl_final` exact.
  n=5 **0.172×** (0.710 / 4.129 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric.
- Goal 20 P.13 leftover: pair `tui_stdin_buffer.contents`
  (`stdin-buffer-contents` on `src/cadr-tui/stdin-buffer.lisp` vs baseline
  `StdinBuffer.getBuffer`). Observed `ct_empty` / `ct_csi` / `ct_done` /
  `ct_again` / `ct_n` exact. n=5 **0.155×** (0.715 / 4.615 µs) on host
  `cursor`, ceiling 8.0. Measure-only. Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13 leftover: pair `output_accumulator.last_line_bytes`
  (`output-accumulator-last-line-bytes` on
  `src/cadr-cli/output-accumulator.lisp` vs
  `OutputAccumulator.getLastLineBytes`). Observed `oa_ll_open` / `oa_ll_nl` /
  `oa_ll_utf8` / `oa_ll_n` exact. n=5 **0.341×** (1.761 / 5.158 µs) on host
  `cursor`, ceiling 8.0. Measure-only. Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric. `nextPairNum` left
  unchanged.
- Goal 20 P.13 leftover: pair `output_accumulator.needs_file`
  (`output-accumulator-needs-file-p` on
  `src/cadr-cli/output-accumulator.lisp` vs
  `OutputAccumulator.shouldUseTempFile`). Observed `oa_nf_empty` /
  `oa_nf_under` / `oa_nf_bytes` / `oa_nf_lines` / `oa_nf_n` exact. n=5
  **2.464×** (50.564 / 20.524 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `output_accumulator.close_temp_file`
  (`output-accumulator-close-temp-file` on
  `src/cadr-cli/output-accumulator.lisp` vs
  `OutputAccumulator.closeTempFile`). Observed `oa_close_path` /
  `oa_close_stream` / `oa_close_n` exact. n=5 **0.463×** (36.231 / 78.272 µs)
  on host `cursor`, ceiling 8.0. Measure-only. Gate rc=1 only from known old
  holes (`lc_n` / `lc_sleep` / help text), not this metric. `nextPairNum`
  left unchanged.
- Goal 20 P.13 leftover: pair `oauth_pkce_device.openrouter_input`
  (`parse-openrouter-authorization-input` on
  `src/cadr-ai/oauth/providers/openrouter.lisp` vs baseline
  `parseAuthorizationInput` in `packages/ai/src/auth/oauth/openrouter.ts`).
  Observed `ori_url` / `ori_qs` / `ori_plain` / `ori_n` exact.
  n=5 **0.754×** (7.131 / 9.458 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover (Pair 436). Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric. `nextPairNum` left
  unchanged.
- Goal 20 P.13 leftover: pair `oauth_pkce_device.openrouter_refresh`
  (`refresh-openrouter-oauth-credential` on
  `src/cadr-ai/oauth/providers/openrouter.lisp` vs baseline
  `openRouterOAuth.refresh`). Observed `orr_same` / `orr_access` /
  `orr_empty` / `orr_n` exact. n=5 **0.698×** (0.210 / 0.301 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 437). Gate rc=1 only
  from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13 leftover: pair `oauth_pkce_device.openrouter_exchange`
  (`openrouter-exchange-code` on `src/cadr-ai/oauth/providers/openrouter.lisp`
  vs baseline `exchangeAuthorizationCode`, stubbed HTTP). Observed `ox_ok` /
  `ox_fail` / `ox_bad` / `ox_n` exact. n=5 **1.486×** (10.390 / 6.991 µs) on
  host `cursor`, ceiling 8.0. Measure-only leftover (Pair 438). Gate rc=1
  only from known old holes (`lc_n` / `lc_sleep` / help text), not this
  metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `tui_select_settings_loaders.update_display`
  (`loader-component-update-display` on `src/cadr-tui/composition/loaders.lisp`
  vs baseline `Loader.updateDisplay`). Skip start/stop/run threads. Observed
  `ud_has_a` / `ud_frames` / `ud_n` exact. n=5 **1.225×** (0.282 / 0.230 µs)
  on host `cursor`, ceiling 8.0. Measure-only leftover (Pair 433). Gate rc=1
  only from known old holes (`lc_n` / `lc_sleep` / help text), not this
  metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `tui_select_settings_loaders.make_cancellable_loader`
  (`make-cancellable-loader-component` on `src/cadr-tui/composition/loaders.lisp`
  vs baseline `CancellableLoader` constructor). Skip start/stop/run threads.
  Observed `cl_has_a` / `cl_aborted` / `cl_n` exact. n=5 **0.205×**
  (0.600 / 2.934 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 434). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `tui_select_settings_loaders.cancellation_token_aborted`
  (`cancellation-token-aborted-p` on `src/cadr-tui/composition/loaders.lisp`
  vs baseline `CancellableLoader.aborted`). Observed `ct_before` / `ct_after`
  / `ct_n` exact. n=5 **0.868×** (0.103 / 0.119 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 435). Gate rc=1 only from known
  old holes (`lc_n` / `lc_sleep` / help text), not this metric.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `evals_harness.eval_layout` (isolated eval
  workspace/agent/sessions layout on `src/cadr-evals/harness.lisp` vs
  `runPiCodingAgent` path join). Observed `el_ws` / `el_agent` / `el_sess` /
  `el_n` exact. n=5 **3.071×** (3.297 / 1.074 µs) on host `cursor`,
  ceiling 8.0. Measure-only. Gate rc=1 only from known old holes (`lc_n` /
  `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
  Pair 418.
- Goal 20 P.13 leftover: pair `evals_harness.system_prompt`
  (`transform-system-prompt` empty rejection on `src/cadr-evals/harness.lisp`
  vs `transformSystemPrompt`). Observed `sp_id` / `sp_map` / `sp_empty` /
  `sp_blank` / `sp_n` exact. n=5 **0.115×** (0.569 / 4.934 µs) on host
  `cursor`, ceiling 8.0. Measure-only. Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric. `nextPairNum` left
  unchanged. Pair 419.
- Goal 20 P.13 leftover: pair `evals_harness.output_selector`
  (`run-coding-agent-eval` `:selector` on `src/cadr-evals/harness.lisp` vs
  `options.output`). Observed `os_none` / `os_id` / `os_map` / `os_n` exact.
  n=5 **1.007×** (0.189 / 0.188 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
  Pair 420.
- Goal 20 P.13: pair `file_mutation_queue.waitqueue` (`file-mutation-queue-state-waitqueue`
  on `src/cadr-agent/file-mutation-queue.lisp` vs baseline queue `state.current`
  Promise). Observed `fmqb_present` / `fmqb_shared` / `fmqb_other` /
  `fmqb_repeat` / `fmqb_n` exact. n=5 **1.120×** (120.311 / 107.377 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 328). Gate rc=1 only from
  known old holes (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. No `src/` perf.
- Goal 20 P.13: pair `file_mutation_queue.registry` (`*file-mutation-queues*`
  membership on `src/cadr-agent/file-mutation-queue.lisp` vs baseline
  `fileMutationQueues.has`). Observed `fmqg_hit` / `fmqg_alias` / `fmqg_miss` /
  `fmqg_repeat` / `fmqg_n` exact. n=5 **0.779×** (96.436 / 123.778 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover (Pair 329). Gate rc=1 only from
  known old holes (`lc_n` / `lc_sleep` / help text), not this metric. cadr
  leads. No `src/` perf.
- Goal 20 P.13: pair `file_mutation_queue.state_p` (`file-mutation-queue-state-p`
  on `src/cadr-agent/file-mutation-queue.lisp` vs baseline queue-state object
  predicate). Observed `fmqc_target` / `fmqc_other` / `fmqc_list` / `fmqc_null` /
  `fmqc_n` exact. n=5 **1.440×** (100.853 / 70.044 µs) on host `cursor`,
  ceiling 8.0. Measure-only leftover (Pair 330). Gate rc=1 only from known old
  holes (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. No `src/` perf.
- Goal 20 P.13 leftover: pair `grep_tool.read_utf8` (`read-utf8-file` on
  `src/cadr-cli/tools/grep.lisp` vs baseline `defaultGrepOperations.readFile`).
  Observed `gru_ascii` / `gru_empty` / `gru_n` exact.
  n=5 **0.500×** (101.136 / 202.336 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric.
- Goal 20 P.13 leftover: pair `grep_tool.file_lines` (`ripgrep-file-lines` on
  `src/cadr-cli/tools/grep.lisp` vs baseline `getFileLines`).
  Observed `gfl_n` / `gfl_first` / `gfl_cache` / `gfl_count` exact.
  n=5 **0.644×** (97.236 / 151.098 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric.
- Goal 20 P.13 leftover: pair `grep_tool.context_block` (`ripgrep-context-block`
  on `src/cadr-cli/tools/grep.lisp` vs baseline `formatBlock`).
  Observed `gcb_lines` / `gcb_match` / `gcb_missing` / `gcb_n` exact.
  n=5 **0.598×** (113.423 / 189.556 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric. `nextPairNum` stays 328. Does not re-pair
  `tool_grep.context_file` or PR #48 `match_event` / `line_text` / `make_tool`.
- Goal 20 P.13 leftover: pair `oauth_pkce_device.json_copy` /
  `interval_seconds` / `device_start` on
  `src/cadr-ai/oauth/providers/openai-device.lisp` vs baseline
  `startOpenAICodexDeviceAuth` error-body copy / interval parse / device start
  (`packages/ai/src/auth/oauth/openai-codex.ts`). Observed `jc_*` / `iv_*` /
  `ds_*` exact. n=5 **2.191×** / **0.711×** / **1.116×** (0.936 / 0.427 µs,
  3.764 / 5.293 µs, 8.710 / 7.805 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not these metrics. Pairs 421 and 423 booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `evals_harness.status_name` (`reporter-status-name`
  on `src/cadr-evals/reporter.lisp` vs baseline `test.result().state`
  lowercasing). Observed `sn_kw` / `sn_str` / `sn_mixed` / `sn_n` exact.
  n=5 **1.726×** (0.352 / 0.204 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `evals_harness.case_observation`
  (`reporter-case-observation` on `src/cadr-evals/reporter.lisp` vs baseline
  `collectHarnessObservations`). Observed `co_scored` / `co_err` /
  `co_unscored` / `co_fail` / `co_miss` / `co_n` exact. n=5 **3.069×**
  (9.383 / 3.057 µs) on host `cursor`, ceiling 8.0. Measure-only. Gate rc=1
  only from known old holes (`lc_n` / `lc_sleep` / help text), not this
  metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum`
  left unchanged.
- Goal 20 P.13 leftover: pair `evals_harness.finish` (`eval-reporter-finish`
  on `src/cadr-evals/reporter.lisp` vs baseline `onTestRunEnd`). Observed
  `rf_int` / `rf_cmp` / `rf_empty` / `rf_n` exact. n=5 **0.701×**
  (20.345 / 29.007 µs) on host `cursor`, ceiling 8.0. Measure-only. Gate rc=1
  only from known old holes (`lc_n` / `lc_sleep` / help text), not this
  metric. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `tui_select_settings_loaders.make_loader_component`
  (`make-loader-component` on `src/cadr-tui/composition/loaders.lisp` vs baseline
  `Loader` constructor). Skip start/stop/run threads. Observed `ml_has_a` /
  `ml_frames` / `ml_n` exact. n=5 **0.182×** (0.402 / 2.207 µs) on host
  `cursor`, ceiling 8.0. Measure-only. Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric. `nextPairNum` left
  unchanged.
- Goal 20 P.13 leftover: pair `tui_select_settings_loaders.set_message`
  (`loader-component-set-message` on `src/cadr-tui/composition/loaders.lisp` vs
  baseline `Loader.setMessage`). Observed `sm_working` / `sm_kept_a` / `sm_n`
  exact. n=5 **1.269×** (0.244 / 0.192 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `tui_select_settings_loaders.set_indicator`
  (`loader-component-set-indicator` on `src/cadr-tui/composition/loaders.lisp`
  vs baseline `Loader.setIndicator`). Skip start/stop/run threads. Observed
  `si_has_x` / `si_frames` / `si_n` exact. n=5 **0.201×** (0.341 / 1.700 µs)
  on host `cursor`, ceiling 8.0. Measure-only. Gate rc=1 only from known old
  holes (`lc_n` / `lc_sleep` / help text), not this metric. `nextPairNum` left
  unchanged.
  `src/cadr-evals/harness.lisp` vs baseline step property access).
  Observed `sv_hash` / `sv_plist` / `sv_intern` / `sv_miss` / `sv_n` exact.
  n=5 **3.693×** (0.774 / 0.210 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `tool_manager.release_asset` (`tool-release-asset`
  on `src/cadr-cli/tool-manager.lisp` vs baseline `TOOLS.getAssetName`).
  Observed `ra_fd_darwin_arm` / `ra_fd_linux_x64` / `ra_fd_win_x64` /
  `ra_rg_linux_x64` / `ra_rg_linux_arm` / `ra_rg_darwin_arm` / `ra_n` exact.
  n=5 **1.465×** (1.532 / 1.046 µs) on host `cursor`, ceiling 8.0. Measure-only.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text), not
  this metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `tool_manager.find_binary` (`find-file-recursively`
  on `src/cadr-cli/tool-manager.lisp` vs baseline `findBinaryRecursively`).
  Observed `fb_nested` / `fb_root` / `fb_miss` / `fb_n` exact. n=5
  **1.568×** (339.3 / 216.5 µs) on host `cursor`, ceiling 8.0. Measure-only.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text), not
  this metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `tool_manager.quarantine_native`
  (`quarantine-windows-native-dependencies` on `src/cadr-cli/tool-manager.lisp`
  vs baseline `quarantineWindowsNativeDependencies`). Observed `qn_restored` /
  `qn_stashed` / `qn_noop` / `qn_n` exact. n=5 **0.961×** (560.4 / 583.0 µs)
  on host `cursor`, ceiling 8.0. Measure-only. Gate rc=1 only from known old
  holes (`lc_n` / `lc_sleep` / help text), not this metric. `nextPairNum` left
  unchanged.
- Goal 20 P.13 leftover: pair `provider_registry_defs.api_key_strategy`
  (`api-key-auth-strategy-entry` on
  `src/cadr-ai/providers/runtime-projection.lisp` vs Bedrock/Vertex
  structured ApiKeyAuth table + environment default). Observed `as_bedrock` /
  `as_vertex` / `as_env` / `as_miss` / `as_hit` exact. n=5 **0.417×**
  (0.114 / 0.274 µs) on host `cursor`, ceiling 8.0. Measure-only. Gate rc=1
  only from known old holes (`lc_n` / `lc_sleep` / help text), not this
  metric. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `provider_registry_defs.provider_options`
  (`built-in-provider-options` on
  `src/cadr-ai/providers/runtime-projection.lisp` vs Azure/Cloudflare/Google
  env-key option projection). Observed `po_azure` / `po_project` /
  `po_location` / `po_cf` / `po_res` exact. n=5 **1.697×** (0.560 / 0.330 µs)
  on host `cursor`, ceiling 8.0. Measure-only. Gate rc=1 only from known old
  holes (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `provider_registry_defs.strip_runtime_options`
  (`remove-runtime-only-options` on
  `src/cadr-ai/providers/runtime-projection.lisp` vs omit
  `apiKey`/`headers`/`environment`/`authType`). Observed `sro_keep` /
  `sro_drop` / `sro_n` / `sro_empty` / `sro_temp` exact. n=5 **0.0627×**
  (0.134 / 2.131 µs) on host `cursor`, ceiling 8.0. Measure-only. Gate rc=1
  only from known old holes (`lc_n` / `lc_sleep` / help text), not this
  metric. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `execution_env.absolute_path` /
  `join_path` / `file_info` (`src/cadr-agent/execution-env.lisp` vs
  baseline `NodeExecutionEnv.absolutePath` / `joinPath` / `fileInfo`).
  Observed `ap_*` / `jp_*` / `fi_*` exact. Live `--only-enforce` n=5
  **3.301×** / **10.091×** / **0.408×** (11.920 / 3.612 µs, 9.267 / 0.918 µs,
  5.834 / 14.284 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pairs 391–393). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not these metrics. Pairs 391–392 are on the over-1× ledger.
  No `src/` optimization. Does not touch `file-mutation-queue.lisp`.
  `nextPairNum` stays 328.
- Goal 20 P.13 leftover: pair `evals_harness.eval_result` /
  `root_observer` / `model_resolver` (`src/cadr-evals/harness.lisp` vs
  baseline SimpleHarnessResult construction / isolated eval root handoff /
  ModelRuntime.getModel stub). Observed `er_*` / `ro_*` / `mr_*` exact.
  n=5 **1.734×** / **2.239×** / **0.601×** (0.762 / 0.440 µs, 0.362 / 0.162 µs,
  0.153 / 0.254 µs) on host `cursor`, ceiling 8.0. Measure-only. Gate rc=1
  only from known old holes (`lc_n` / `lc_sleep` / help text), not these
  metrics. Does not pair `default-eval-model-resolver` (skipped; ~54×).
  Pairs 376–377 are on the over-1× ledger. Pairs 376–378.
- Goal 20 P.13 leftover: pair `core_rest.cancellation_predicate`
  (`cancellation-predicate-aborted-p` on `src/cadr-core/cancellation.lisp` vs
  `Boolean(fn())` try/catch). Observed `cp_nil` / `cp_true` / `cp_false` /
  `cp_err` exact. n=5 **0.106×** (0.296 / 2.788 µs) on host `cursor`,
  ceiling 8.0. Measure-only. Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric. Pairs 385–387.
- Goal 20 P.13 leftover: pair `core_rest.redacted_register`
  (`register-redacted-object-type` on `src/cadr-core/redacted-print.lisp` vs
  array push-if-absent). Observed `rr_new` / `rr_dup` / `rr_sort` exact.
  n=5 **0.698×** (0.216 / 0.309 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric.
- Goal 20 P.13 leftover: pair `core_rest.redacted_replace` (`replace-all` on
  `src/cadr-core/redacted-print.lisp` vs String.split/join one needle).
  Observed `ra_hit` / `ra_mark` / `ra_miss` / `ra_empty` exact. n=5 **3.383×**
  (1.464 / 0.433 µs) on host `cursor`, ceiling 8.0. Measure-only. Gate rc=1
  only from known old holes (`lc_n` / `lc_sleep` / help text), not this
  metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13: pair `oauth_pkce_device.error_detail` (`oauth-response-error-detail`
  on `src/cadr-ai/oauth/providers/xai.lisp` vs baseline `requestFailure` detail
  in `packages/ai/src/auth/oauth/xai.ts`). Observed `ed_desc` / `ed_error` /
  `ed_n` exact. n=5 **2.301×** (0.838 / 0.364 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover sibling. Gate rc=1 only from known old holes (`lc_n` /
  `lc_sleep` / help text), not this metric. No `src/` perf. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. Pairs 379–381.
- Goal 20 P.13: pair `oauth_pkce_device.ensure_success`
  (`ensure-oauth-response-success` on `src/cadr-ai/oauth/providers/xai.lisp`
  vs baseline `!ok` throw `requestFailure`). Observed `es_ok` / `es_created`
  / `es_fail` / `es_n` exact. n=5 **0.701×** (1.779 / 2.538 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover sibling. Gate rc=1 only from
  known old holes (`lc_n` / `lc_sleep` / help text), not this metric. No
  `src/` perf.
- Goal 20 P.13: pair `oauth_pkce_device.notify_device`
  (`notify-device-authorization` on `src/cadr-ai/oauth/providers/xai.lisp`
  vs baseline `interaction.notify` device_code). Observed `nd_complete` /
  `nd_plain` / `nd_code` / `nd_n` exact. n=5 **2.586×** (0.960 / 0.371 µs) on
  host `cursor`, ceiling 8.0. Measure-only leftover sibling. Gate rc=1 only
  from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
  No `src/` perf. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `tui_select_settings_loaders.loader_frames`
  (`loader-frames` on `src/cadr-tui/composition/loaders.lisp` vs baseline
  `Loader` `DEFAULT_FRAMES` copy). Observed `lf_default_n` / `lf_default_first`
  / `lf_custom_n` / `lf_one_n` exact. n=5 **1.051×** (0.200 / 0.190 µs) on host
  `cursor`, ceiling 8.0. Measure-only. Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `tui_select_settings_loaders.loader_interval`
  (`loader-interval-seconds` on `src/cadr-tui/composition/loaders.lisp` vs
  baseline `Loader` `intervalMs` default 80). Observed `li_default` / `li_pos`
  / `li_zero` / `li_n` exact. n=5 **1.464×** (0.201 / 0.138 µs) on host
  `cursor`, ceiling 8.0. Measure-only. Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `tui_select_settings_loaders.loader_step`
  (`loader-component-step` on `src/cadr-tui/composition/loaders.lisp` vs
  baseline `Loader` animation tick). Skip start/stop/run threads. Observed
  `ls_initial` / `ls_next` / `ls_wrap` / `ls_n` exact. n=5 **1.543×** (0.339 /
  0.219 µs) on host `cursor`, ceiling 8.0. Measure-only. Gate rc=1 only from
  known old holes (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `resource_loader.context_from_dir` /
  `project_context` / `nearest_config` (`src/cadr-cli/resource-loader.lisp` vs
  baseline `loadContextFileFromDir` / `loadProjectContextFiles` / project
  `SYSTEM.md` existsSync). Observed `cfd_*` / `pc_*` / `nc_*` exact. n=5
  **2.413×** / **1.913×** / **5.401×** (64.741 / 26.834 µs, 56.791 / 29.679 µs,
  30.226 / 5.596 µs) on host `cursor`, ceiling 8.0. Measure-only. Gate rc=1
  only from known old holes (`lc_n` / `lc_sleep` / help text), not these
  metrics. All three booked on `docs/benchmarks/goal20-paired-over-1x.md`.
  Pairs 394–396.
- Goal 20 P.13: pair `evals_harness.argument_prefix` (`argument-after-prefix`
  on `src/cadr-evals/main.lisp` vs baseline `run-evals.mjs` startsWith+slice).
  Observed `apr_val` / `apr_empty` / `apr_miss` / `apr_model` / `apr_n` exact.
  n=5 **0.904×** (0.216 / 0.239 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric.
- Goal 20 P.13: pair `evals_harness.parse_arguments` (`parse-eval-arguments`
  on `src/cadr-evals/main.lisp` vs baseline `run-evals.mjs` argv loop).
  Observed `pa_space` / `pa_eq` / `pa_mix` / `pa_miss` / `pa_empty` /
  `pa_unknown` / `pa_n` exact. n=5 **0.134×** (1.186 / 8.837 µs) on host
  `cursor`, ceiling 8.0. Measure-only. Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13: pair `evals_harness.validate_smoke` (`validate-smoke-result`
  on `src/cadr-evals/main.lisp` vs baseline `smoke.eval.ts` Paris/tokens).
  Observed `vs_ok` / `vs_trim` / `vs_city` / `vs_tok` / `vs_n` exact.
  n=5 **0.512×** (2.384 / 4.654 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric.
- Goal 20 P.13: pair `edit_tool.normalize_line_endings` (`normalize-line-endings`
  on `src/cadr-cli/tools/edit.lisp` vs baseline `normalizeToLF`).
  Observed `nlf_lf` / `nlf_crlf` / `nlf_cr` / `nlf_empty` / `nlf_n` exact.
  n=5 **2.792×** (1.574 / 0.564 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. Pairs 388–390.
- Goal 20 P.13: pair `edit_tool.restore_line_endings` (`restore-line-endings`
  on `src/cadr-cli/tools/edit.lisp` vs baseline `restoreLineEndings`).
  Observed `rle_lf` / `rle_crlf` / `rle_none` / `rle_empty` / `rle_n` exact.
  n=5 **1.944×** (0.773 / 0.398 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13: pair `edit_tool.make_tool` (`make-edit-tool` on
  `src/cadr-cli/tools/edit.lisp` vs baseline `createEditToolDefinition`).
  Observed `emt_name` / `emt_desc` / `emt_req` / `emt_n` exact.
  n=5 **5.850×** (3.313 / 0.566 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `grep_tool.match_event` (`ripgrep-match-event` on
  `src/cadr-cli/tools/grep.lisp` vs baseline JSON.parse of rg `--json` match
  events). Observed `rme_match` / `rme_begin` / `rme_bad` / `rme_n` exact.
  n=5 **0.954×** (4.205 / 4.407 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric. Pairs 373–375.
- Goal 20 P.13 leftover: pair `grep_tool.line_text` (`ripgrep-line-text` on
  `src/cadr-cli/tools/grep.lisp` vs baseline match.lineText CR/LF sanitize).
  Observed `rlt_crlf` / `rlt_nl` / `rlt_plain` / `rlt_cr` / `rlt_n` exact.
  n=5 **0.962×** (0.712 / 0.741 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric.
- Goal 20 P.13 leftover: pair `grep_tool.make_tool` (`make-grep-tool` on
  `src/cadr-cli/tools/grep.lisp` vs baseline `createGrepToolDefinition`).
  Observed `gmt_name` / `gmt_desc` / `gmt_req` / `gmt_n` exact.
  n=5 **10.006×** (4.152 / 0.415 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric. Printed ratio is above the named 8.0× ceiling;
  the gate bound is the 10 µs variance floor. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13 leftover: pair `evals_harness.release_extensions` /
  `agent_tools` / `extension_paths` (`src/cadr-evals/harness.lisp` vs
  baseline eval session extension cleanup / session tools list /
  `ExtensionRunner.getExtensionPaths`). Observed `re_*` / `at_*` / `ep_*`
  exact. n=5 **21.13×** / **5.118×** / **6.381×** (6.187 / 0.293 µs,
  1.466 / 0.286 µs, 2.963 / 0.464 µs) on host `cursor`, ceiling 8.0.
  `release_extensions` is above 8.0× but passed on the variance/µs floor.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not these metrics. All three on the over-1× ledger. `nextPairNum`
  stays 328. Pairs 370–372.
- Goal 20 P.13 leftover: pair `core_rest.cancellation_make` /
  `cancellation_aborted` / `cancellation_set` (`make-cancellation-state` /
  `cancellation-aborted-p` / `set-cancellation-aborted-p` on
  `src/cadr-core/cancellation.lisp` vs `AbortController` constructor /
  `AbortSignal.aborted` / `abort` + fresh controller). Observed `cm_*` /
  `cab_*` / `cs_*` exact. n=5 **0.972×** / **0.0965×** / **0.148×**
  (0.2446 / 0.2518 µs, 0.6703 / 6.943 µs, 0.5152 / 3.478 µs) on host
  `cursor`, ceiling 8.0. Measure-only. Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not these metrics. Pairs 361–363.
  Does not re-pair 322–324 or 337–339.
- Goal 20 P.13 leftover: pair `image_runtime.openrouter_usage` /
  `parse_openrouter_images` / `error_result` on `src/cadr-ai/images.lisp`
  (`openrouter-image-usage` / `parse-openrouter-images` /
  `image-error-result` vs baseline `parseUsage` / generateImages response
  parse / catch). Observed `us_*` / `poi_*` / `er_*` exact. n=5
  **4.218×** / **2.986×** / **3.028×** (2.167 / 0.514 µs, 3.188 / 1.068 µs,
  1.047 / 0.346 µs) on host `cursor`, ceiling 8.0. Measure-only. Gate rc=1
  only from known old holes (`lc_n` / `lc_sleep` / help text), not these
  metrics. All three booked on the over-1× ledger. Pairs 367–369. No
  `src/` perf.
- Goal 20 P.13 leftover: pair `evals_harness.content_text` /
  `transcript_event` / `elapsed` (`src/cadr-evals/harness.lisp` vs baseline
  `contentText` / transcript message object / `performance.now`
  timings.totalMs). Observed `ct_*` / `te_*` / `el_*` exact. n=5
  **1.386×** / **5.702×** / **0.275×** (0.997 / 0.719 µs, 1.016 / 0.178 µs,
  0.182 / 0.663 µs) on host `cursor`, ceiling 8.0. Measure-only. Gate rc=1
  only from known old holes (`lc_n` / `lc_sleep` / help text), not these
  metrics. Pairs 364–365 are on the over-1× ledger. Pairs 364–366.
  `nextPairNum` still 328.
- Goal 20 P.13 leftover: pair `oauth_pkce_device.base64url_value` /
  `base64url_decode` / `account_id` (`src/cadr-ai/oauth/openai-anthropic.lisp`
  vs baseline RFC 4648 §5 alphabet / `decodeJwt` `atob` / `getAccountId`).
  Observed `bv_*` / `bd_*` / `aid_*` exact. n=5 **2.692×** / **6.544×** /
  **5.986×** (0.736 / 0.273 µs, 2.969 / 0.454 µs, 6.112 / 1.021 µs) on host
  `cursor`, ceiling 8.0. Measure-only. Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not these metrics. Pairs 358–360 are on
  the over-1× ledger. No `src/` perf. Pairs 358–360.
- Goal 20 P.13 leftover: pair `core_rest.cancellation_wait` /
  `redacted_types` / `threads_join` (`wait-for-cancellation` /
  `redacted-object-types` / `join-active-thread` on `src/cadr-core/` vs
  `Atomics.wait` timeout + aborted `AbortSignal` / sorted type-list copy /
  `worker_threads` message+exit). Observed `cw_*` / `rt_*` / `tj_*` exact.
  n=5 **6.041×** / **4.494×** / **0.00575×** (53.40 / 8.840 µs, 2.375 /
  0.528 µs, 128.7 / 22383 µs) on host `cursor`, ceiling 8.0. Measure-only.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not these metrics. Pairs 337–338 are on the over-1× ledger. Pairs 337–339.
  Does not re-pair 322–324.
- Goal 20 P.13: pair `oauth_pkce_device.provider_key`
  (`oauth-callback-provider-key` on `src/cadr-ai/oauth/callback.lisp` vs
  Anthropic/Radius display-name branches). Observed `pk_anth` / `pk_rad` /
  `pk_other` / `pk_n` exact. n=5 **0.498×** (0.139 / 0.279 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover sibling of Pairs 310–312.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric. No `src/` perf.
- Goal 20 P.13: pair `oauth_pkce_device.http_status_text`
  (`oauth-http-status-text` on `src/cadr-ai/oauth/callback.lisp` vs
  `node:http` `STATUS_CODES`). Observed `st_ok` / `st_bad` / `st_miss` /
  `st_err` / `st_n` exact. n=5 **0.528×** (0.137 / 0.260 µs) on host
  `cursor`, ceiling 8.0. Measure-only leftover sibling of Pair 334.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric. No `src/` perf.
- Goal 20 P.13: pair `oauth_pkce_device.parse_callback_request`
  (`parse-oauth-callback-request` on `src/cadr-ai/oauth/callback.lisp` vs
  openai-codex `startLocalOAuthServer` pathname/state/code). Observed
  `pcr_ok` / `pcr_state` / `pcr_path` / `pcr_code` / `pcr_n` exact. n=5
  **3.699×** (12.588 / 3.403 µs) on host `cursor`, ceiling 8.0.
  Measure-only leftover sibling of Pairs 334–335. Gate rc=1 only from
  known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
  No `src/` perf.
- Goal 20 P.13: pair `evals_harness.prompt_eval_agent` (`prompt-eval-agent` on
  `src/cadr-evals/harness.lisp` vs baseline `promptAgent`). Observed
  `pea_out` / `pea_msgs` / `pea_stop` / `pea_n` exact.
  n=5 **10.47×** (19.3 / 1.84 µs) on host `cursor`, ceiling 20.0. Measure-only leftover
  (Pair 355). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric.
- Goal 20 P.13: pair `evals_harness.reload_shutdown` (`reload-eval-extensions` +
  `shutdown-eval-agent` on `src/cadr-evals/harness.lisp` vs baseline reload +
  dispose). Observed `rld_err` / `rld_active` / `rld_reports` / `rld_n` exact.
  n=5 **1.872×** (222.4 / 118.8 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 356). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric.
- Goal 20 P.13: pair `evals_harness.run_coding_agent_eval` (`run-coding-agent-eval`
  on `src/cadr-evals/harness.lisp` vs baseline `runPiCodingAgent`). Observed
  `rca_out` / `rca_events` / `rca_err` / `rca_ms` / `rca_n` exact.
  n=5 **7.979×** (940.1 / 117.8 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 357). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric.
- Goal 20 P.13: pair `evals_harness.make_eval_root` (`make-eval-root` on
  `src/cadr-evals/harness.lisp` vs baseline isolated eval directory). Observed
  `mer_exists` / `mer_prefix` / `mer_no_ws` / `mer_n` exact.
  n=5 **1.672×** (73.6 / 44.0 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 349). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric.
- Goal 20 P.13: pair `evals_harness.normalize_step_type` (`normalize-step-type` on
  `src/cadr-evals/harness.lisp` vs baseline step type coercion). Observed
  `nst_kw` / `nst_sym` / `nst_str` / `nst_bad` / `nst_n` exact.
  n=5 **1.003×** (0.256 / 0.255 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 350). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric.
- Goal 20 P.13: pair `evals_harness.selected_eval_tools` (`selected-eval-tools` on
  `src/cadr-evals/harness.lisp` vs baseline coding-tool selection). Observed
  `set_n` / `set_names` / `set_all` / `set_filt_n` / `set_no_bash` / `set_cases` exact.
  n=5 **1.506×** (19.9 / 13.2 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 351). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric.
- Goal 20 P.13: pair `harness_events.make_end` (`make-run-end-event` on
  `src/cadr-agent/harness-events.lisp` vs baseline `RunEndEvent` object).
  Observed `hee_type` / `hee_lane` / `hee_run` / `hee_outcome` /
  `hee_abort` exact. n=5 **1.574×** (0.216 / 0.137 µs) on host `cursor`,
  ceiling 8.0. Measure-only. Gate rc=1 only from known old holes (`lc_n` /
  `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Live process: Cursor cloud agents merge READY Goal 20 leftover pairing
  PRs into `cadr-migration` (serial; rebase the next PR first). Tags,
  force-push, and spend stay with Ethan. See
  `docs/acceptance/team-dev-platform.md`.
- Goal 20 P.13 leftover: pair `evals_harness.eval_environment` (`eval-environment` on
  `src/cadr-evals/harness.lisp` vs baseline `resolveModelSelection` environment
  trim). Observed `ee_trim` / `ee_model` / `ee_ws` / `ee_miss` / `ee_n` exact.
  n=5 **2.692×** (0.758 / 0.282 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 346). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
  `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `evals_harness.prompt_step` (`make-eval-prompt-step` on
  `src/cadr-evals/harness.lisp` vs baseline prompt step object). Observed
  `ps_type` / `ps_content` / `ps_n` exact.
  n=5 **0.956×** (0.109 / 0.114 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 347). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric.
- Goal 20 P.13 leftover: pair `evals_harness.reload_step` (`make-eval-reload-step` on
  `src/cadr-evals/harness.lisp` vs baseline reload step object). Observed
  `rs_type` / `rs_no_content` / `rs_n` exact.
  n=5 **0.738×** (0.078 / 0.105 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 348). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric.
- Goal 20 P.13 leftover: pair `evals_harness.step_value` (`step-value` on
  `src/cadr-evals/harness.lisp` vs baseline step property access).
  Observed `sv_hash` / `sv_plist` / `sv_intern` / `sv_miss` / `sv_n` exact.
  n=5 **3.693×** (0.774 / 0.210 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `evals_harness.usage` (`eval-usage` on
  `src/cadr-evals/harness.lisp` vs baseline usage object assembly).
  Observed `us_in` / `us_out` / `us_total` / `us_tools` / `us_prov` /
  `us_model` / `us_cost` / `us_n` exact. n=5 **2.148×** (2.240 / 1.042 µs)
  on host `cursor`, ceiling 8.0. Measure-only. Gate rc=1 only from known
  old holes (`lc_n` / `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13 leftover: pair `evals_harness.result_json` (`eval-result-json`
  on `src/cadr-evals/harness.lisp` vs baseline `SimpleHarnessResult` JSON
  shape). Observed `rj_out` / `rj_ev` / `rj_err` / `rj_art` / `rj_time` /
  `rj_n` exact. n=5 **5.225×** (1.933 / 0.370 µs) on host `cursor`,
  ceiling 8.0. Measure-only. Gate rc=1 only from known old holes (`lc_n` /
  `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`. `nextPairNum` left unchanged.
- Goal 20 P.13: pair `write_tool.ensure_parent` (`ensure-write-parent-directories`
  on `src/cadr-cli/tools/write.lisp` vs baseline `defaultWriteOperations.mkdir`).
  Observed `ep_nested` / `ep_exists` / `ep_eexist` / `ep_n` exact.
  n=5 **0.594×** (64.978 / 109.366 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric.
- Goal 20 P.13: pair `write_tool.write_utf8` (`write-utf8-file` on
  `src/cadr-cli/tools/write.lisp` vs baseline `defaultWriteOperations.writeFile`).
  Observed `wu_ok` / `wu_ascii` / `wu_cjk` / `wu_n` exact.
  n=5 **1.254×** (169.771 / 135.369 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13: pair `write_tool.make_tool` (`make-write-tool` on
  `src/cadr-cli/tools/write.lisp` vs baseline `createWriteToolDefinition`).
  Observed `wmt_name` / `wmt_desc` / `wmt_req` / `wmt_n` exact.
  n=5 **3.139×** (13.633 / 4.343 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13: pair `core_rest.cancellation_abort` (`abort-cancellation` /
  `cancellation-aborted-p` on `src/cadr-core/cancellation.lisp` vs
  `AbortController.abort` / `AbortSignal.aborted`). Observed `ca_live` /
  `ca_abort` / `ca_clear` / `ca_pred` exact. n=5 **0.0712×** (0.579 / 8.130 µs)
  on host `cursor`, ceiling 8.0. Measure-only. Gate rc=1 only from known old
  holes (`lc_n` / `lc_sleep` / help text), not this metric. Pairs 322–324.
- Goal 20 P.13: pair `core_rest.redacted_secrets` (`redact-secrets` on
  `src/cadr-core/redacted-print.lisp` vs String.split/join `[REDACTED]`).
  Observed `rd_keep` / `rd_secret` / `rd_token` / `rd_mark` exact. n=5 **2.488×**
  (2.750 / 1.105 µs) on host `cursor`, ceiling 8.0. Measure-only. Gate rc=1 only
  from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13: pair `core_rest.threads_cleanup` (`stop-thread-for-cleanup` on
  `src/cadr-core/threads.lisp` vs `worker_threads` Worker eval-exit). Observed
  `th_absent` / `th_current` / `th_joined` exact. n=5 **0.00799×** (181.6 /
  22730 µs) on host `cursor`, ceiling 8.0. Measure-only. Gate rc=1 only from
  known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13 leftover: pair `evals_harness.resolve_selection` /
  `transcript` / `last_assistant` (`src/cadr-evals/harness.lisp` vs baseline
  `resolveModelSelection` / `toTranscriptEvents` / `promptAgent` assistant
  slice). Observed `rs_*` / `tr_*` / `la_*` exact. n=5 **0.170×** / **1.743×** /
  **1.034×** (1.06 / 6.22 µs, 3.80 / 2.18 µs, 0.579 / 0.560 µs) on host
  `cursor`, ceiling 8.0. Measure-only. Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not these metrics. Pairs 326–327 are on
  the over-1× ledger. Pairs 325–327.
- Goal 20 P.13: pair `oauth_pkce_device.percent_decode` (`percent-decode` on
  `src/cadr-ai/oauth/callback.lisp` vs baseline URLSearchParams percent-decode
  in `packages/ai/src/auth/oauth/openai-codex.ts`). Observed `pd_plain` /
  `pd_plus` / `pd_slash` / `pd_space` / `pd_utf8` / `pd_n` exact. n=5
  **1.525×** (1.592 / 1.044 µs) on host `cursor`, ceiling 8.0. Measure-only.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric. No `src/` perf.
- Goal 20 P.13: pair `oauth_pkce_device.parse_query` (`parse-query` on
  `src/cadr-ai/oauth/callback.lisp` vs baseline `URLSearchParams`). Observed
  `pq_code` / `pq_state` / `pq_plus` / `pq_empty` / `pq_n` exact. n=5
  **1.944×** (6.672 / 3.431 µs) on host `cursor`, ceiling 8.0. Measure-only.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric. No `src/` perf.
- Goal 20 P.13: pair `oauth_pkce_device.parse_authorization_input`
  (`parse-oauth-authorization-input` on `src/cadr-ai/oauth/callback.lisp` vs
  baseline `parseAuthorizationInput`). Observed `pai_url` / `pai_hash` /
  `pai_qs` / `pai_plain` / `pai_n` exact. n=5 **0.535×** (6.292 / 11.750 µs)
  on host `cursor`, ceiling 8.0. Measure-only. Gate rc=1 only from known
  old holes (`lc_n` / `lc_sleep` / help text), not this metric. No `src/`
  perf.
- Goal 20 P.13: pair `file_mutation_queue.pending_count` (`file-mutation-queue-state-pending-count` on
  `src/cadr-agent/file-mutation-queue.lisp` vs baseline queue `state.pending` after enqueue).
  Observed `fmqp_shared` / `fmqp_other` / `fmqp_missing` / `fmqp_alias` /
  `fmqp_n` exact. n=5 **1.435×** (194.6 / 135.5 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric.
- Goal 20 P.13: pair `file_mutation_queue.next_ticket` (`file-mutation-queue-state-next-ticket` on
  `src/cadr-agent/file-mutation-queue.lisp` vs baseline queue `state.nextTicket` after enqueue).
  Observed `fmqi_shared` / `fmqi_other` / `fmqi_missing` / `fmqi_alias` /
  `fmqi_n` exact. n=5 **1.147×** (157.9 / 137.6 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric.
- Goal 20 P.13: pair `file_mutation_queue.serving_ticket` (`file-mutation-queue-state-serving-ticket` on
  `src/cadr-agent/file-mutation-queue.lisp` vs baseline queue `state.serving` after enqueue).
  Observed `fmqv_zero` / `fmqv_other` / `fmqv_missing` / `fmqv_alias` /
  `fmqv_n` exact. n=5 **0.985×** (139.5 / 141.7 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric.
- Goal 20 P.13: pair `ls_tool.directory_entry_name` (`directory-entry-name` on
  `src/cadr-cli/tools/ls.lisp` vs baseline directory suffix in
  `packages/coding-agent/src/core/tools/ls.ts`). Observed `lden_file` /
  `lden_dir` / `lden_nested` / `lden_n` exact.
  n=5 **0.969×** (4.659 / 4.808 µs) on host `cursor`, ceiling 8.0. Measure-only.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13: pair `ls_tool.list_directory` (`list-directory` on
  `src/cadr-cli/tools/ls.lisp` vs baseline ls execute listing assembly).
  Observed `ld_empty` / `ld_mixed` / `ld_first` / `ld_limit` / `ld_n` exact.
  n=5 **1.119×** (352.2 / 314.9 µs) on host `cursor`, ceiling 8.0. Measure-only.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13: pair `ls_tool.make_tool` (`make-ls-tool` on
  `src/cadr-cli/tools/ls.lisp` vs baseline `createLsToolDefinition`).
  Observed `lst_name` / `lst_desc` / `lst_req` / `lst_n` exact.
  n=5 **1.017×** (284.4 / 279.6 µs) on host `cursor`, ceiling 8.0. Measure-only.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13: pair `powershell_tool.utf8_prefix` (`+powershell-utf8-output-prefix+` on
  `src/cadr-cli/tools/powershell.lisp` vs baseline `UTF8_OUTPUT_PREFIX`). Observed
  `psu_len` / `psu_nl` / `psu_try` / `psu_utf8` / `psu_n` exact.
  n=5 **3.79×** (0.647 / 0.171 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 301). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric.
- Goal 20 P.13: pair `powershell_tool.prefix_command` (UTF-8 prefix + command concatenate
  on `src/cadr-cli/tools/powershell.lisp` vs baseline `createLocalPowerShellOperations`
  wrap). Observed `psc_empty` / `psc_date` / `psc_write` / `psc_n` exact.
  n=5 **1.39×** (0.468 / 0.336 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 302). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric.
- Goal 20 P.13: pair `powershell_tool.make_tool` (`make-powershell-tool` on
  `src/cadr-cli/tools/powershell.lisp` vs baseline `createPowerShellToolDefinition`).
  Observed `pmt_name` / `pmt_desc` / `pmt_req` / `pmt_n` exact.
  n=5 **1.34×** (1.936 / 1.448 µs) on host `cursor`, ceiling 8.0. Measure-only leftover
  (Pair 303). Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text),
  not this metric.
- Goal 20 P.13 leftover: pair `tui_theme_overlay.rgb_to_ansi_256` /
  `parse_hex_color` / `theme_foreground_ansi` (`src/cadr-tui/theme.lisp` vs
  baseline `rgbTo256` / `hexToRgb` / `Theme.getFgAnsi`). Observed `r256_*` /
  `ph_*` / `tfa_*` exact. n=5 **1.955×** / **1.127×** / **14.724×**
  (2.52 / 1.29 µs, 0.944 / 0.837 µs, 5.58 / 0.379 µs) on host `cursor`,
  ceiling 8.0. Measure-only. Gate rc=1 only from known old holes (`lc_n` /
  `lc_sleep` / help text), not these metrics. Pair 321 is on the 10 µs
  floor. Over-1× booked. Pairs 319–321.- Goal 20 P.13: pair `harness_events.make_end` (`make-run-end-event` on
  `src/cadr-agent/harness-events.lisp` vs baseline `RunEndEvent` object).
  Observed `hee_type` / `hee_lane` / `hee_run` / `hee_outcome` /
  `hee_abort` exact. n=5 **1.574×** (0.216 / 0.137 µs) on host `cursor`,
  ceiling 8.0. Measure-only. Gate rc=1 only from known old holes (`lc_n` /
  `lc_sleep` / help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13: pair `harness_events.event_type` (`harness-event-type` on
  `src/cadr-agent/harness-events.lisp` vs baseline `event.type`).
  Observed `het_start` / `het_end` / `het_fail` exact.
  n=5 **1.468×** (0.175 / 0.119 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13: pair `harness_events.make_bus` (`make-harness-event-bus` on
  `src/cadr-agent/harness-events.lisp` vs baseline `new HarnessEventBus()`).
  Observed `heb_distinct` / `heb_a` / `heb_b` exact.
  n=5 **1.351×** (0.344 / 0.255 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric. Booked in
  `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13: pair `file_mutation_queue.call_with` (`call-with-file-mutation-queue` on
  `src/cadr-agent/file-mutation-queue.lisp` vs baseline `withFileMutationQueue` as a
  function). Observed `fmqf_alias` / `fmqf_other` / `fmqf_fifo` / `fmqf_run` /
  `fmqf_n` exact. n=5 **0.523×** (124.1 / 237.4 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric.
- Goal 20 P.13: pair `file_mutation_queue.make_state` (`make-file-mutation-queue-state` on
  `src/cadr-agent/file-mutation-queue.lisp` vs baseline queue-state object construction).
  Observed `fmqm_pending` / `fmqm_ticket` / `fmqm_serving` / `fmqm_other` /
  `fmqm_n` exact. n=5 **1.597×** (105.7 / 66.2 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric.
- Goal 20 P.13: pair `file_mutation_queue.state_key` (`file-mutation-queue-state-key` on
  `src/cadr-agent/file-mutation-queue.lisp` vs baseline queue `state.key` after
  get-or-create). Observed `fmqt_alias` / `fmqt_other` / `fmqt_missing` /
  `fmqt_repeat` / `fmqt_n` exact. n=5 **1.009×** (134.3 / 133.1 µs) on host `cursor`,
  ceiling 8.0. Measure-only. Gate rc=1 only from known old holes (`lc_n` /
  `lc_sleep` / help text), not this metric.
- Goal 20 P.13: pair `harness_events.on` (`harness-event-bus-on` on
  `src/cadr-agent/harness-events.lisp` vs baseline `HarnessEventBus.on`).
  Observed `heon_off` / `heon_keep` / `heon_type` exact.
  n=5 **0.325×** (0.58 / 1.79 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric.
- Goal 20 P.13: pair `harness_events.watch` (`harness-event-bus-watch` on
  `src/cadr-agent/harness-events.lisp` vs baseline `HarnessEventBus.watch`).
  Observed `hew_snap` / `hew_count` / `hew_start` / `hew_end` exact.
  n=5 **0.250×** (0.57 / 2.27 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric.
- Goal 20 P.13: pair `harness_events.make_start` (`make-run-start-event` on
  `src/cadr-agent/harness-events.lisp` vs baseline `RunStartEvent` object).
  Observed `hes_type` / `hes_lane` / `hes_run` exact.
  n=5 **1.18×** (0.14 / 0.12 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
- Goal 20 P.13: pair `find_tool.pattern_match` (`find-pattern-match-p` on
  `src/cadr-cli/tools/find.lisp` vs baseline basename vs path-containing glob
  match in `packages/coding-agent/src/core/tools/find.ts`). Observed
  `fpm_star_a` / `fpm_star_src` / `fpm_star_txt` / `fpm_path_src` /
  `fpm_path_root` / `fpm_src_star` / `fpm_n` exact.
  n=5 **7.16×** (30.5 / 4.26 µs) on host `cursor`, ceiling 8.0. Measure-only.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13: pair `find_tool.find_files` (`find-files` on
  `src/cadr-cli/tools/find.lisp` vs baseline find execute output assembly +
  `relativizeFindResultPath`). Observed `ff_empty` / `ff_lisp` / `ff_path` /
  `ff_src_star` / `ff_n` exact.
  n=5 **3.44×** (633.4 / 184.1 µs) on host `cursor`, ceiling 8.0. Measure-only.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13: pair `find_tool.make_tool` (`make-find-tool` on
  `src/cadr-cli/tools/find.lisp` vs baseline `createFindToolDefinition`).
  Observed `fmt_name` / `fmt_desc` / `fmt_req` / `fmt_n` exact.
  n=5 **1.41×** (131.9 / 93.3 µs) on host `cursor`, ceiling 8.0. Measure-only.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13 leftover: pair `tool_manager.get_tool_path` / `ensure_tool` /
  `cleanup_quarantine` (`src/cadr-cli/tool-manager.lisp` vs baseline
  `getToolPath` / `ensureTool` / `cleanupWindowsSelfUpdateQuarantine`).
  Observed `gtp_*` / `et_*` / `cq_*` exact. n=5 **0.014×** / **0.013×** /
  **1.365×** (107.8 / 7742.0 µs, 65.1 / 5129.9 µs, 120.1 / 88.0 µs) on host
  `cursor`, ceiling 8.0. Measure-only. Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not these metrics. Pair 294 is on the
  over-1× ledger. Pairs 292–294.
- Goal 20 P.13 leftover: pair `cli_settings.default_model` /
  `default_provider` / `output_padding` (`src/cadr-cli/settings/manager.lisp`
  vs baseline `SettingsManager.getDefaultModel` / `getDefaultProvider` /
  `getOutputPad`). Observed `dm_*` / `dp_*` / `op_*` exact. First n=5 freeze
  **7.544×** / **6.737×** / **6.289×** (15.69 / 2.080 µs, 15.67 / 2.327 µs,
  17.54 / 2.788 µs) on host `cursor`, ceiling 8.0. Measure-only. Gate rc=1
  only from known old holes (`lc_n` / `lc_sleep` / help text), not these
  metrics. Pairs 352–354 are on the over-1× ledger.
- Goal 20 P.13 leftover: pair `cli_settings.reload` / `enabled_models` /
  `block_images` (`src/cadr-cli/settings/manager.lisp` vs baseline
  `SettingsManager.reload` / `getEnabledModels` / `getBlockImages`).
  Observed `rl_*` / `em_*` / `bi_*` exact. First n=5 freeze **0.593×** /
  **5.735×** / **5.623×** (84.8 / 143.0 µs, 18.7 / 3.26 µs, 19.1 / 3.41 µs)
  on host `cursor`, ceiling 8.0. Measure-only. Gate rc=1 only from known
  old holes (`lc_n` / `lc_sleep` / help text), not these metrics. Pairs
  308–309 are on the over-1× ledger. Pairs 307–309.
- Goal 20 P.13: pair `provider_registry_defs.merge_environment` (`merge-provider-environment` on
  `src/cadr-ai/providers/runtime-projection.lisp` vs baseline `getProviderEnvValue`).
  Observed `me_oa` / `me_gemini` / `me_azure` / `me_miss` exact.
  n=5 **0.114×** (0.320 / 2.803 µs) on host `cursor`, ceiling 8.0. Measure-only.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13: pair `provider_registry_defs.runtime_models` (`provider-runtime-models` on
  `src/cadr-ai/providers/runtime-projection.lisp` vs baseline `getBuiltinModels`).
  Observed `rm_openai` / `rm_anthropic` / `rm_google` / `rm_unknown` exact.
  n=5 **3.733×** (17.89 / 4.794 µs) on host `cursor`, ceiling 8.0. Measure-only.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13: pair `provider_registry_defs.structured_api_key_login`
  (`provider-definition-structured-api-key-login-p` on
  `src/cadr-ai/providers/runtime-projection.lisp` vs baseline Bedrock/Vertex
  `ApiKeyAuth.login` select flow). Observed `sl_openai` / `sl_anthropic` / `sl_google` /
  `sl_bedrock` / `sl_vertex` exact.
  n=5 **0.000831×** (0.176 / 211.2 µs) on host `cursor`, ceiling 8.0. Measure-only.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13: pair `image_runtime.output_modalities` /
  `image_runtime.openrouter_content` /
  `image_runtime.parse_data_image` on `src/cadr-ai/images.lisp` (Pairs
  298–300). Observed `om_*` / `oc_*` / `pd_*` exact. Measure-only. No
  `src/` optimization. n=5 on host `cursor`: **0.657×** (0.196 / 0.299
  µs), **3.34×** (1.367 / 0.409 µs), **1.43×** (0.555 / 0.387 µs);
  ceiling 8.0. Gate rc=1 only from known old holes (`lc_n` /
  `lc_sleep` / help text), not these metrics.
- Goal 20 P.13: pair `harness_events.emit` (`harness-event-bus-emit` on
  `src/cadr-agent/harness-events.lisp` vs baseline `HarnessEventBus.emit`).
  Observed `he_direct` / `he_watch` / `he_start` / `he_end` / `he_second`
  exact. n=5 **0.306×** (0.75 / 2.45 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` /
  help text), not this metric.
- Goal 20 P.13: pair `bash_tool.strip_exit_footer` (`bash-strip-exit-footer` on
  `src/cadr-cli/tools/bash.lisp` vs the same Process-exited suffix strip; pi's
  tool path never injects that footer). Observed `sef_exact` / `sef_nl` /
  `sef_no_nl` / `sef_plain` / `sef_empty` / `sef_n` exact.
  n=5 **1.599×** (0.989 / 0.619 µs) on host `cursor`, ceiling 8.0. Measure-only.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13: pair `bash_tool.append_status` (`append-bash-status` on
  `src/cadr-cli/tools/bash.lisp` vs baseline `appendStatus` in
  `packages/coding-agent/src/core/tools/bash.ts`). Observed `abs_empty` /
  `abs_abort` / `abs_exit` / `abs_timeout` / `abs_n` exact.
  n=5 **2.911×** (1.109 / 0.381 µs) on host `cursor`, ceiling 8.0. Measure-only.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13: pair `bash_tool.truncation_notice` (`bash-truncation-notice` on
  `src/cadr-cli/tools/bash.lisp` vs baseline `formatOutput` truncation notice
  in `packages/coding-agent/src/core/tools/bash.ts`). Observed `btn_none` /
  `btn_partial` / `btn_lines` / `btn_bytes` / `btn_n` exact.
  n=5 **3.363×** (2.798 / 0.832 µs) on host `cursor`, ceiling 8.0. Measure-only.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13 leftover: pair `output_accumulator.append` / `snapshot` /
  `finish` (`src/cadr-cli/output-accumulator.lisp` vs baseline
  `OutputAccumulator.append` / `snapshot` / `finish`). Observed
  `oa_append_*` / `oa_snap_*` / `oa_fin_*` exact.
  n=5 append **0.690×** (3.149 / 4.561 µs), snapshot **0.716×** (3.157 / 4.409 µs),
  finish **0.658×** (1.670 / 2.537 µs) on host `cursor`, ceiling 8.0.
  Measure-only. Pairs 280–282. Gate rc=1 only from known old holes
  (`lc_n` / `lc_sleep` / help text), not these metrics.
- Goal 20 P.13: pair `file_mutation_queue.ensure_state` (`ensure-file-mutation-queue-state` on
  `src/cadr-agent/file-mutation-queue.lisp` vs baseline `fileMutationQueues.get(key) ?? set`
  given a canonical key). Observed `fmqs_alias` / `fmqs_other` / `fmqs_missing` /
  `fmqs_repeat` / `fmqs_n` exact.
  n=5 **0.879×** (109.2 / 124.3 µs) on host `cursor`, ceiling 8.0. Measure-only.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13: pair `file_mutation_queue.release_turn` (`release-file-mutation-turn` on
  `src/cadr-agent/file-mutation-queue.lisp` vs baseline `withFileMutationQueue`
  finally / pending-- / delete-when-empty after wait). Observed `fmqe_serving` /
  `fmqe_pending` / `fmqe_other` / `fmqe_missing` / `fmqe_n` exact.
  n=5 **0.918×** (155.2 / 169.1 µs) on host `cursor`, ceiling 8.0. Measure-only.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13: pair `file_mutation_queue.wait_turn` (`wait-for-file-mutation-turn` on
  `src/cadr-agent/file-mutation-queue.lisp` vs baseline `withFileMutationQueue`
  await-current / ticket wait after enqueue). Observed `fmqw_serving` /
  `fmqw_pending` / `fmqw_other` / `fmqw_missing` / `fmqw_n` exact.
  n=5 **0.767×** (101.7 / 132.5 µs) on host `cursor`, ceiling 8.0. Measure-only.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13: pair `file_mutation_queue.register` (`register-file-mutation` on
  `src/cadr-agent/file-mutation-queue.lisp` vs baseline `withFileMutationQueue`
  ticket enqueue after the same key encoding). Observed `fmqr_alias` /
  `fmqr_other` / `fmqr_pending` / `fmqr_ticket` / `fmqr_n` exact.
  n=5 **0.996×** (126.0 / 126.5 µs) on host `cursor`, ceiling 8.0. Measure-only.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13: pair `file_mutation_queue.lock` (`file-mutation-queue-lock` on
  `src/cadr-agent/file-mutation-queue.lisp` vs baseline `fileMutationQueues`
  get-or-create after the same key encoding). Observed `fmql_alias` /
  `fmql_other` / `fmql_missing` / `fmql_repeat` / `fmql_n` exact.
  n=5 **1.24×** (183.3 / 148.0 µs) on host `cursor`, ceiling 8.0. Measure-only.
  Gate rc=1 only from known old holes (`lc_n` / `lc_sleep` / help text), not this metric.
- Goal 20 P.13: pair `file_mutation_queue.queue_key` (`file-mutation-queue-key` on
  `src/cadr-agent/file-mutation-queue.lisp` vs baseline queue-map key / `realpath`).
  Observed `fmqk_alias` / `fmqk_missing` / `fmqk_other` / `fmqk_n` exact.
  n=5 **1.08×** (169.3 / 156.2 µs) on host `cursor`, ceiling 8.0. Measure-only.
- Goal 21 gate: full `scripts/goal21-gate-run.sh` does not run a second
  `scripts/test-cl.sh` when `verify.sh` already recorded `deterministic
  FiveAM` as a timed PASS. `scripts/test-cl-fiveam.sh` is summary-only by
  default; `CADR_TEST_CL_VERBOSE=1` or `--verbose` restores the old tee.
- Goal 21: re-anchored the fixed pi baseline to v0.84.3.
  cadr 0.2.0 · aligned with pi v0.84.3 (+0, 4e58f324f). `/thinking`
  selector, session-level model/thinking defaults, `modelThinkingLevels`,
  `session_compact_failed`, compaction summary not persisted (#7048),
  `GoogleApiThinkingLevel` rename, PowerShell tool (Windows), and
  v0.84.3 source-parity disposition updates.

### Fixed

- Goal 20 P.13: pair `agent_tool_loop.runtime` (steering/follow-up queue
  enqueue/drain/clear; cadr `agent-steer`/`drain-agent-queue` vs pi
  `PendingMessageQueue`). Friend-MachineD n=5 **6.30×**, ceiling 8.0.
  Measure-only.

- Bash FORMAT + `(` quoting report classified **not-product**: model
  fed Lisp `(format t "gethash equal 6-char (hit): …")` to `bash -c`.
  Wrapper still passes `command` as `bash -lc "$2"` argv
  (`docs/bugs/bash-format-shell-quoting.md`). Not G.17.
- Interactive TUI shows `Working...` during live follow-up streaming
  after a tool (assistant `message-start` / text and thinking
  deltas). Settle-window still hides the loader only in the persist
  gap after a completed assistant turn or tool-end with no sibling
  (`docs/bugs/working-indicator-missing.md`). Not G.17.

### Changed

- Goal 20 P.13: pair `file_mutation_queue.with_queue` (`with-file-mutation-queue` on
  `src/cadr-agent/file-mutation-queue.lisp` vs pi `withFileMutationQueue`). Observed
  `fmq_alias_key` / `fmq_missing_key` / `fmq_other_key` / `fmq_fifo_sum` /
  `fmq_other_run` / `fmq_clean` exact. Friend-MachineD n=5 **0.55×**.
  Measure-only.
- Goal 20 P.13: pair `execution_env.exists_remove_temps` (exists/remove/temp
  helpers on `src/cadr-agent/execution-env.lisp` vs pi `NodeExecutionEnv`).
  Observed `ex_missing` / `ex_present` / `ex_after_rm` / `tmp_dir` / `tmp_file` /
  `tmp_suffix` / `rm_force` / `rm_recursive` exact. Measure-only.
- Goal 20 P.13: pair `resource_loader.dedupe_by_name` (same collision
  fixture as `reload`; time `dedupe-resources-by-name` only, not
  `reload-resources`). Observed `dbn_skill_count` / `dbn_skill_collisions` /
  `dbn_skill_project` / `dbn_prompt_count` / `dbn_prompt_collisions` /
  `dbn_prompt_project` exact. Friend-MachineD n=5 **0.50×** (253.5 / 505.5 µs),
  ceiling 8.0. Measure-only.
- Goal 20 P.13: pair `session_compact.prepare_branch_entries` (collect e4→e5 then `prepare-branch-entries` only; same token-budget encoding as `generate-branch-summary`, no model call). Observed `prepared` / `message_count` / `total_tokens` / `read_file_count` / `modified_file_count` exact. Friend-MachineD n=5 **RATIO_PLACEHOLDER**. Measure-only.
- Goal 20 P.13: pair `session_compact.branch_summarize` (forked
  five-message tree; `collect-entries-for-branch-summary` +
  `generate-branch-summary` vs pi branch summarization). Observed
  `summarized` / `entry_count` / `branch_summary_chars` exact.
  Friend-MachineD n=5 **1.15×** (37.3 / 32.5 µs), ceiling 20.0.
  Measure-only.
- Goal 20 P.13: pair `agent_conditions.error_probe` (condition slot reads +
  subtype/catch probe on `src/cadr-agent/conditions.lisp`; fixture-aligned
  pi harness). Measure-only.
- Goal 20 P.13: pair `cli_extensions_install.extension_discovery`
  (flat/subdir scan, project/global dirs, explicit `-e` paths; cadr
  `discover-extension-sources` vs pi `discoverAndLoadExtensions` path
  discovery). Observed `ed_n`/`ed_cli`/`ed_proj`/`ed_glob`/`ed_probe`/`ed_miss`
  exact. Friend-MachineD n=5 **1.98×** (1954.5 / 987.2 µs), ceiling 8.0.
  Measure-only.
- Goal 20 P.13: pair `settings_load.config_paths` (agent-dir auth/config
  path resolution; cadr `default-config-path`/`default-auth-path` vs pi
  `getSettingsPath`/`getAuthPath`). Friend-MachineD n=5 **RATIO_PLACEHOLDER**.
  Measure-only.
- Goal 20 P.13: pair `settings_load.stored_auth_secrets` (stored auth.json
  key/access/refresh collection; cadr `stored-auth-secrets` vs pi auth.json
  scan). Friend-MachineD n=5 **4.19×** (426.6 / 101.8 µs), ceiling 8.0.
  Measure-only.
- Goal 20 P.13: pair `package_manager.manifest_parse` (package.json `pi`
  manifest read; cadr `read-package-pi-manifest` vs pi `readPiManifest`).
  Friend-MachineD n=5 **5.09×** (52.9 / 10.4 µs), ceiling 8.0. Measure-only.
- Goal 20 P.13: pair `agent_tool_loop.tool_result_digest` (tool-result
  summary truncation; cadr `truncate-summary-tool-result` vs pi
  `truncateForSummary`). Friend-MachineD n=5 **107.57×** (289.4 / 2.7 µs),
  ceiling 125.0. Measure-only.
- Goal 20 P.13: pair `session_pipeline.session_leaf_id` (leaf-id accessor on
  an open session; cadr `session-leaf-id` vs pi `SessionManager.getLeafId`).
  Friend-MachineD freeze 0.74× (0.04 / 0.05 µs), ceiling 8.0. Measure-only.
- Goal 20 P.13: pair `text_truncation.truncate_middle` (head+tail with omission
  marker; cadr `truncate-harness-middle` vs pi `truncateMiddle`). Friend-MachineD
  n=5 **0.12×** (1777.8 / 14420.3 µs), ceiling 8.0. Measure-only.
- Goal 20 P.13: pair `evals_harness.normalize_steps` (step input
  coercion; cadr `normalize-eval-steps` vs pi `pi-harness.ts` string/
  sequence normalization). Friend-MachineD freeze 0.11× (1.30 / 12.15 µs),
  ceiling 8.0. Measure-only.
- Goal 20 P.13: pair `cli_selectors.scoped_models_selector_counts` (scoped
  models footer counts; cadr `scoped-models-selector-counts` vs pi `getFooterText`
  count logic). Friend-MachineD n=5 **43.32×** (158.5 / 3.7 µs), ceiling 55.0.
  Measure-only; no optimize.
- Goal 20 P.13: pair `cli_selectors.scoped_models_selector_sorted_ids` (scoped
  models enabled-first sort; cadr `scoped-models-sorted-ids` vs pi `getSortedIds`).
  Friend-MachineD n=5 **37.36×** (145.0 / 3.9 µs), ceiling 50.0. Measure-only; no
  optimize.
- Goal 20 P.13: pair `cli_selectors.scoped_models_selector_clear_all` (scoped
  models clear-all; cadr `scoped-models-selector-clear-all` vs pi `clearAll`).
  Friend-MachineD n=5 **21.18×** (287.2 / 13.6 µs), ceiling 25.0. Measure-only;
  no optimize.
- Goal 20 P.13: pair `cli_selectors.scoped_models_selector_toggle_provider` (scoped
  models toggleProvider; cadr `scoped-models-selector-toggle-provider` vs pi
  `toggleProvider`) — Friend-MachineD freeze 4.55×, ceiling 8.0.
- Goal 20 P.13: pair `cli_selectors.scoped_models_selector_enable_all` (scoped
  models enable-all; cadr `scoped-models-selector-enable-all` vs pi `enableAll`).
  Friend-MachineD n=5 **20.77×** (384.3 / 18.5 µs), ceiling 25.0. Measure-only;
  no optimize.
- Goal 20 P.13: pair `cli_selectors.scoped_models_selector_target_ids` (scoped
  models enableAll/clearAll target set; cadr `scoped-models-selector-target-ids`
  vs pi `enableAll`/`clearAll` targetIds). Friend-MachineD n=5 **5.27×**
  (240.6 / 45.7 µs), ceiling 8.0. Measure-only; no optimize.
- Goal 20 P.13: pair `cli_selectors.scoped_models_selector_toggle_selected`
  (scoped models confirm toggle; cadr `scoped-models-selector-toggle-selected`
  vs pi `handleInput` confirm). Friend-MachineD n=5 **2.95×** (247.0 / 83.7 µs),
  ceiling 8.0. Measure-only; no optimize.
- Goal 20 P.13: pair `cli_selectors.scoped_models_selector_handle_event` (scoped
  models event dispatch; cadr `scoped-models-selector-handle-event` vs pi
  handleInput). Friend-MachineD n=5 **6.76×** (246.1 / 36.4 µs), ceiling 12.0
  (bumped from 8.0 on first freeze 10.40×). Measure-only; no optimize.
- Goal 20 P.13: pair `cli_selectors.scoped_models_selector_handle_raw_input`
  (scoped models raw keys; cadr `scoped-models-selector-handle-raw-input` vs pi
  `handleInput` raw key dispatch). Friend-MachineD n=5 **9.03×** (1638.3 /
  181.4 µs), ceiling 8.0. Measure-only; no optimize.
- Goal 20 P.13: pair `cli_selectors.scoped_models_selector_ui_state` (scoped
  models UI render; cadr `render-scoped-models-selector` vs pi `updateList`).
  Friend-MachineD n=5 **33.04×** (1,636.7 / 49.5 µs), ceiling 35.0.
  Measure-only; no optimize.
- Goal 20 P.13: pair `cli_selectors.scoped_models_selector_set_query` (scoped
  models query update; cadr `scoped-models-selector-set-query` vs pi refresh
  clamp). Friend-MachineD n=5 **6.80×** (272.7 / 40.1 µs), ceiling 8.0.
  Measure-only; no optimize.
- Goal 20 P.13: pair `cli_selectors.model_selector_ui_state` (model selector UI
  render; cadr `render-model-selector` vs pi `updateList`). Friend-MachineD n=5
  **21.70×** (648.3 / 29.9 µs), ceiling 35.0. Measure-only; no optimize.
- Goal 20 P.13: pair `cli_selectors.model_selector_toggle_scope` (model selector
  scope toggle; cadr `model-selector-toggle-scope` vs pi tab scope toggle).
  Friend-MachineD n=5 **5.45×** (141.1 / 25.9 µs), ceiling 8.0. Measure-only;
  no optimize.
- Goal 20 P.13: pair `cli_selectors.model_selector_selected_model` (model
  selector selected lookup; cadr `model-selector-selected-model` vs pi
  `filteredModels[selectedIndex]`). Friend-MachineD n=5 **7.90×** (160.3 /
  20.3 µs), ceiling 12.0 (bumped from 8.0). Measure-only; no optimize.
- Goal 20 P.13: pair `cli_selectors.model_selector_set_query` (model selector
  query update; cadr `model-selector-set-query` vs pi `filterModels` query).
  Friend-MachineD n=5 **3.85×** (148.5 / 38.6 µs), ceiling 8.0. Measure-only;
  no optimize.
- Goal 20 P.13: pair `cli_selectors.model_selector_handle_raw_input`
  (model selector raw keys; cadr `model-selector-handle-raw-input` vs pi
  `handleInput`). Friend-MachineD n=5 **7.08×** (823.0 / 116.3 µs), ceiling
  8.0. Measure-only; no optimize.
- Goal 20 P.13: pair `cli_selectors.model_selector_handle_event`
  (model selector events; cadr `model-selector-handle-event` vs pi event
  dispatch). Friend-MachineD n=5 **5.37×** (147.6 / 27.5 µs), ceiling 8.0.
  Measure-only; no optimize.
- Goal 20 P.13: pair `cli_selectors.model_selector_move`
  (model selector wrap move; cadr `model-selector-move` vs pi
  `handleInput` up/down). Friend-MachineD n=5 **18.60×** (102.3 / 5.5 µs),
  ceiling 20.0. Measure-only; no optimize.
- Goal 20 P.13: pair `cli_selectors.model_selector_apply_filter`
  (model selector fuzzy filter; cadr `model-selector-apply-filter` vs pi
  `filterModels`). Friend-MachineD n=5 **5.53×** (130.9 / 23.7 µs), ceiling
  8.0. Measure-only; no optimize.
- Goal 20 P.13: pair `cli_selectors.qualified_model_id`
  (provider/id label; cadr `qualified-model-id` vs pi model-selector
  label). Friend-MachineD n=5 **7.65×** (2.1 / 0.3 µs), ceiling 8.0.
  Measure-only; no optimize.
- Goal 20 P.13: pair `cli_selectors.model_selector_search_text`
  (model selector search text; cadr `model-selector-search-text` vs pi
  `getModelSelectorSearchText`). Friend-MachineD n=5 **6.78×**
  (5.6 / 0.8 µs), ceiling 8.0. Measure-only; no optimize.
- Goal 20 P.13: pair `cli_selectors.oauth_selector_ui_state`
  (oauth selector UI; cadr `render-oauth-selector` vs pi
  `OauthSelectorComponent`). Friend-MachineD n=5 **24.66×**
  (372.1 / 15.1 µs), ceiling 35.0. Measure-only; no optimize.
- Goal 20 P.13: pair `cli_selectors.api_key_input_ui_state`
  (api key overlay UI; cadr `render-api-key-input-state` vs pi
  `LoginDialogComponent` showPrompt). Friend-MachineD n=5 **4.86×**
  (263.5 / 54.2 µs), ceiling 8.0. Measure-only; no optimize.
- Goal 20 P.13: pair `cli_selectors.login_method_selector_ui_state`
  (login method selector UI; cadr `render-login-method-selector` vs pi
  `ExtensionSelectorComponent`). Friend-MachineD n=5 **10.07×**
  (622.6 / 61.8 µs), ceiling 12.0. Measure-only; no optimize.
- Goal 20 P.13: pair `cli_selectors.api_key_input_state_handle_event`
  (api key overlay dispatch; cadr `api-key-input-state-handle-event` vs pi
  `LoginDialogComponent` prompt flow). Friend-MachineD n=5 **1.66×**
  (7.0 / 4.2 µs), ceiling 8.0. Measure-only; no optimize.
- Goal 20 P.13: pair `cli_selectors.oauth_option_status_rendered`
  (themed status indicator; cadr `oauth-option-status-rendered` vs pi
  `formatStatusIndicator`). Friend-MachineD n=5 **10.02×** (13.9 / 1.4 µs),
  ceiling 15.0. Measure-only; no optimize.
- Goal 20 P.13: pair `cli_selectors.oauth_selector_move`
  (move fixtures; cadr `oauth-selector-move` wrap index vs pi clamp at
  boundary). Friend-MachineD n=5 **27.34×** (83.8 / 3.1 µs), ceiling
  50.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.login_method_selector_handle_event`
  (event fixtures; cadr `login-method-selector-handle-event`
  vs pi `ExtensionSelectorComponent` dispatch). Friend-MachineD n=5
  **0.97×** (4.2 / 4.3 µs), ceiling 8.0. Same commit no optimize. G.17
  missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.logout_provider_options`
  (credential fixtures; cadr `logout-provider-options`
  vs pi `getLogoutProviderOptions`). Friend-MachineD n=5 **2.71×**
  (10.4 / 3.8 µs), ceiling 8.0. Same commit no optimize. G.17 missing.
  Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.login_provider_options`
  (provider-option fixtures; cadr `login-provider-options`
  vs pi `getLoginProviderOptions`). Friend-MachineD n=5 **0.87×**
  (14.8 / 17.1 µs), ceiling 8.0. Same commit no optimize. G.17 missing.
  Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.login_auth_type_route`
  (routing fixtures; cadr `login-auth-type-route`
  vs pi `showLoginAuthTypeSelector`). Friend-MachineD n=5 **3.44×**
  (3.8 / 1.1 µs), ceiling 8.0. Same commit no optimize. G.17 missing.
  Not Goal 20 complete.
- Goal 20: add `--only-enforce` to `goal20-paired-paths.sh` so new-pair
  freezes can gate on the new metric only when full-suite ceiling noise
  blocks unrelated metrics.
- Goal 20 P.13: pair `cli_selectors.oauth_selector_search_text`
  (search-text fixtures; cadr `oauth-selector-search-text`
  vs pi `filterProviders` search text). Friend-MachineD n=5 **1.52×**
  (9.5 / 6.2 µs), ceiling 8.0. Same commit no optimize. G.17 missing.
  Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.oauth_selector_handle_raw_input`
  (raw-input fixtures; cadr `oauth-selector-handle-raw-input`
  vs pi `handleInput` raw dispatch). Friend-MachineD n=5 **5.02×**
  (691.4 / 137.7 µs), ceiling 8.0. Same commit no optimize. G.17 missing.
  Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.oauth_selector_handle_event`
  (event fixtures; cadr `oauth-selector-handle-event`
  vs pi `handleInput` dispatch). Friend-MachineD n=5 **1.22×**
  (138.2 / 113.6 µs), ceiling 8.0. Same commit no optimize. G.17 missing.
  Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.oauth_selector_apply_filter`
  (filter fixtures; cadr `oauth-selector-apply-filter`
  vs pi `filterProviders`). Friend-MachineD n=5 **3.84×**
  (113.2 / 29.5 µs), ceiling 8.0. Same commit no optimize. G.17 missing.
  Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.oauth_selector_selection`
  (selection fixtures; cadr `oauth-selector-selection`
  vs pi `filteredProviders[selectedIndex]`). Friend-MachineD n=5
  **3.80×** (103.4 / 27.2 µs), ceiling 8.0. Same commit no optimize.
  G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.oauth_environment_source_p`
  (env-source regex fixtures; cadr `oauth-environment-source-p`
  vs pi `formatStatusIndicator` env detection). Friend-MachineD n=5
  **3.51×** (1.2 / 0.3 µs), ceiling 8.0. Same commit no optimize.
  G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.credential_entry_auth_type`
  (credential-kind fixtures; cadr `credential-entry-auth-type`
  vs pi logout authType normalization). Friend-MachineD n=5 **1.87×**
  (0.6 / 0.3 µs), ceiling 8.0. Same commit no optimize. G.17 missing.
  Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.oauth_option_status_label`
  (status-label fixtures; cadr `oauth-option-status-label`
  vs pi `formatStatusIndicator` plain label). Friend-MachineD n=5
  **2.46×** (2.1 / 0.8 µs), ceiling 8.0. Same commit no optimize.
  G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.trust_selector_ui_state`
  (structural UI digest fixtures; cadr `trust-selector-ui-encoded`
  vs pi trust selector UI state digest). Friend-MachineD n=5 **2.27×**
  (394.9 / 173.7 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.trust_selector_handle_raw_input`
  (raw-input fixtures; cadr `trust-selector-handle-raw-input`
  vs pi raw-input dispatch). Friend-MachineD n=5 **2.98×**
  (693.8 / 233.2 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.trust_selector_handle_event`
  (event fixtures; cadr `trust-selector-handle-event`
  vs pi event dispatch). Friend-MachineD n=5 **2.35×**
  (333.3 / 142.1 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.trust_selector_move`
  (wrap-move fixtures; cadr `trust-selector-move`
  vs pi wrap index on trust option count). Friend-MachineD n=5 **2.46×**
  (328.1 / 133.3 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.trust_decision_description`
  (saved-decision fixtures; cadr `trust-decision-description`
  vs pi `formatDecision`). Friend-MachineD n=5 **2.36×**
  (156.7 / 66.4 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.trust_selector_selection`
  (trust-selection fixtures; cadr `trust-selector-selection`
  vs pi `getProjectTrustOptions` index). Friend-MachineD n=5 **3.78×**
  (242.4 / 64.1 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.project_trust_options`
  (trust-option fixtures; cadr `project-trust-options`
  vs pi `getProjectTrustOptions`). Friend-MachineD n=5 **1.16×**
  (72.9 / 62.9 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_app_key_p`
  (keybinding-match fixtures; cadr `tree-selector-app-key-p`
  vs pi `selector-keybinding-matches-p`). Friend-MachineD n=5 **0.63×**
  (74.8 / 119.1 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_help_key`
  (help-key fixtures; cadr `tree-selector-help-key`
  vs pi keybinding lookup with fallbacks). Friend-MachineD n=5 **1.70×**
  (58.4 / 34.4 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_iso_timestamp`
  (ISO timestamp fixtures under `TZ=UTC`; cadr `tree-selector-iso-timestamp`
  vs pi local `YYYY-MM-DDTHH:MM:SS` formatter). Friend-MachineD n=5 **1.43×**
  (6.1 / 4.3 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_order_entries`
  (order-entries fixtures; cadr `tree-selector-order-entries`
  vs pi DFS entry order). Friend-MachineD n=5 **1.21×**
  (38.4 / 31.7 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_entry_map`
  (entry-map fixtures; cadr `tree-selector-entry-map`
  vs pi flat-entry id map). Friend-MachineD n=5 **2.76×**
  (11.6 / 4.2 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_selected_id`
  (selected-id fixtures; cadr `tree-selector-selected-id`
  vs pi `TreeList.filteredNodes` selected id). Friend-MachineD n=5 **2.50×**
  (213.4 / 85.3 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_visible_ids`
  (visible-id list fixtures; cadr `tree-selector-visible-ids`
  vs pi `TreeList.filteredNodes` ids). Friend-MachineD n=5 **5.78×**
  (82.1 / 14.2 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_select_id`
  (visible-id selection fixtures; cadr `tree-selector-select-id`
  vs pi `TreeList` index by id). Friend-MachineD n=5 **4.64×**
  (217.0 / 46.7 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_selected_entry`
  (selected entry fixtures; cadr `tree-selector-selected-entry`
  vs pi `TreeList.getSelectedNode`). Friend-MachineD n=5 **5.14×**
  (199.5 / 38.8 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_handle_label_event`
  (label-mode event fixtures; cadr `tree-selector-handle-label-event`
  vs pi `LabelInput.handleInput`). Friend-MachineD n=5 **0.69×**
  (159.7 / 232.7 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_handle_event`
  (structured event fixtures; cadr `tree-selector-handle-event`
  vs pi `TreeList.handleInput`). Friend-MachineD n=5 **0.73×**
  (245.2 / 333.8 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_handle_raw_input`
  (keybinding dispatch fixtures; cadr `tree-selector-handle-raw-input`
  vs pi `TreeList.handleInput`). Friend-MachineD n=5 **4.06×**
  (1068.1 / 263.3 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_cancel_label`
  (label cancel fixtures; cadr `tree-selector-cancel-label`
  vs pi `LabelInput` onCancel). Friend-MachineD n=5 **1.57×**
  (214.6 / 136.7 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_confirm_label`
  (label confirm fixtures; cadr `tree-selector-confirm-label`
  vs pi `LabelInput` onSubmit). Friend-MachineD n=5 **4.37×**
  (260.2 / 59.5 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_start_label_edit`
  (label-edit start fixtures; cadr `tree-selector-start-label-edit`
  vs pi `showLabelInput`). Friend-MachineD n=5 **2.40×**
  (150.8 / 62.9 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_toggle_label_timestamps`
  (label-timestamp toggle fixtures; cadr `tree-selector-toggle-label-timestamps`
  vs pi `showLabelTimestamps` toggle). Friend-MachineD n=5 **0.04×**
  (4.3 / 118.4 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_copy_selected`
  (copy-text fixtures; cadr `tree-selector-copy-selected`
  vs pi `copySelected`). Friend-MachineD n=5 **2.87×**
  (142.5 / 49.6 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_set_filter`
  (filter-mode fixtures; cadr `tree-selector-set-filter`
  vs pi `TreeList` filterMode + applyFilter). Friend-MachineD n=5 **0.60×**
  (71.4 / 119.0 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_set_query`
  (search-query fixtures; cadr `tree-selector-set-query`
  vs pi `TreeList` searchQuery + applyFilter). Friend-MachineD n=5 **0.66×**
  (88.9 / 135.2 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_branch_segment_id`
  (branch-segment fixtures; cadr `tree-selector-branch-segment-id`
  vs pi `findBranchSegmentStart`). Friend-MachineD n=5 **1.82×**
  (264.9 / 145.6 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_unfold_or_down`
  (unfold/down fixtures; cadr `tree-selector-unfold-or-down`
  vs pi `unfoldOrDown` handleInput). Friend-MachineD n=5 **1.82×**
  (324.4 / 178.0 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_fold_or_up`
  (fold/branch-segment fixtures; cadr `tree-selector-fold-or-up`
  vs pi `foldOrUp` handleInput). Friend-MachineD n=5 **1.76×**
  (316.9 / 179.6 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_move`
  (visible-id selection move fixtures; cadr `tree-selector-move`
  vs pi `TreeList` index wrap). Friend-MachineD n=5 **1.74×**
  (331.4 / 190.3 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_render_lines`
  (tree list render fixtures; cadr `tree-selector-render-lines`
  vs pi `TreeList.render`). Friend-MachineD n=5 **0.83×**
  (1,236.6 / 1,484.2 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_apply_filter`
  (filter/fold/query fixtures; cadr `tree-selector-apply-filter`
  vs pi `applyFilter`). Friend-MachineD n=5 **3.60×**
  (71.6 / 19.9 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_rebuild_visible_maps`
  (visible parent/children map fixtures; cadr `tree-selector-rebuild-visible-maps`
  vs pi `recalculateVisualStructure`). Friend-MachineD n=5 **1.49×**
  (41.3 / 27.7 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_prioritize_active`
  (active-path entry reorder fixtures; cadr `tree-selector-prioritize-active`
  vs pi `flattenTree` active-branch ordering). Friend-MachineD n=5 **1.83×**
  (16.3 / 8.9 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_nearest_visible_id`
  (visible-id ancestor walk fixtures; cadr `tree-selector-nearest-visible-id`
  vs pi `findNearestVisibleIndex` id walk). Friend-MachineD n=5 **2.34×**
  (14.9 / 6.4 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_active_path`
  (leaf-to-root path walk fixtures; cadr `tree-selector-active-path`
  vs pi `buildActivePath`). Friend-MachineD n=5 **2.43×** (11.8 / 4.8 µs),
  ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_help_lines`
  (tree help footer wrap fixtures; cadr `tree-selector-help-lines`
  vs pi `TreeHelp.render`). Friend-MachineD n=5 **3.33×** (979.6 / 293.8 µs),
  ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_help_keys`
  (tree help keybinding compaction fixtures; cadr `tree-selector-help-keys`
  vs pi `formatHelpKeys`). Friend-MachineD n=5 **4.56×** (190.2 / 41.7 µs),
  ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_horizontal_viewport`
  (horizontal pan/truncate fixtures; cadr `tree-selector-horizontal-viewport`
  vs pi `renderHorizontalViewport`). Friend-MachineD n=5 **0.89×**
  (66.2 / 74.5 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not
  Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_visual_nodes`
  (visible-tree indent/connector/gutter fixtures; cadr `tree-selector-visual-nodes`
  vs pi `recalculateVisualStructure` DFS). Friend-MachineD n=5 **0.92×**
  (17.2 / 18.7 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not
  Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_prefix`
  (tree gutter prefix fixtures; cadr `tree-selector-prefix` vs pi render prefix
  char loop). Friend-MachineD n=5 **0.48×** (4.2 / 8.9 µs), ceiling 8.0. Same
  commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_entry_display_text`
  (tree entry display fixtures; cadr `tree-selector-entry-display-text` vs pi
  `getEntryDisplayText`). Friend-MachineD n=5 **5.79×** (19.2 / 3.3 µs),
  ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_format_tool_call`
  (tree tool-call format fixtures; cadr `tree-selector-format-tool-call` vs pi
  `formatToolCall`). Friend-MachineD n=5 **5.86×** (14.1 / 2.4 µs), ceiling 8.0.
  Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_format_label_timestamp`
  (tree label timestamp fixtures; cadr `tree-selector-format-label-timestamp` vs
  pi `formatLabelTimestamp`). Friend-MachineD n=5 **1.85×** (9.2 / 4.9 µs),
  ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_cycle_filter`
  (tree filter cycle fixtures; cadr `tree-selector-cycle-filter` vs pi filter
  cycle keybindings). Friend-MachineD n=5 **17.08×** (4.8 / 0.3 µs), ceiling 8.0.
  Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_tool_argument`
  (tree tool-arg fixtures; cadr `tree-selector-tool-argument` vs pi formatToolCall
  path lookup). Friend-MachineD n=5 **3.32×** (24.7 / 7.4 µs), ceiling 8.0. Same
  commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_foldable_p`
  (tree foldable fixtures; cadr `tree-selector-foldable-p` vs pi `isFoldable`).
  Friend-MachineD n=5 **2.79×** (4.1 / 1.5 µs), ceiling 8.0. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_shorten_path`
  (tree path shorten fixtures; cadr `tree-selector-shorten-path` vs pi
  `formatToolCall` shortenPath). Friend-MachineD n=5 **1.76×** (2.7 / 1.6 µs),
  ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_status_labels`
  (tree status suffix fixtures; cadr `tree-selector-status-labels` vs pi
  `getStatusLabels`). Friend-MachineD n=5 **8.92×** (4.1 / 0.5 µs), ceiling 8.0.
  Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_normalize_display_text`
  (tree display normalize fixtures; cadr `tree-selector-normalize-display-text` vs
  pi `getEntryDisplayText` normalize). Friend-MachineD n=5 **2.88×**
  (4.3 / 1.5 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_settings_entry_p`
  (tree settings-entry fixtures; cadr `tree-selector-settings-entry-p` vs pi
  `isSettingsEntry`). Friend-MachineD n=5 **0.65×** (0.3 / 0.5 µs), ceiling 8.0.
  Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_entry_search_text`
  (tree search haystack fixtures; cadr `tree-selector-entry-search-text` vs pi
  `getSearchableText` field join). Friend-MachineD n=5 **1.22×** (1.8 / 1.5 µs),
  ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_query_matches`
  (tree search token fixtures; cadr `tree-selector-query-matches-p` vs pi
  tree search predicate). Friend-MachineD n=5 **2.20×** (5.2 / 2.3 µs),
  ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.tree_entry_filtered`
  (tree filter fixtures; cadr `tree-selector-entry-filtered-p` vs pi filter
  mode predicate). Friend-MachineD n=5 **0.56×** (0.4 / 0.6 µs), ceiling 8.0.
  Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.settings_apply_filter`
  (settings filter fixtures; cadr `settings-selector-apply-filter` vs pi
  `SettingsList.applyFilter`). Friend-MachineD n=5 **1.61×**
  (7.8 / 4.8 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.settings_cycle`
  (settings value cycle fixtures; cadr `settings-selector-cycle` vs pi
  `SettingsList` value advance). Friend-MachineD n=5 **4.13×**
  (2.0 / 0.5 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.settings_active_automatic_theme`
  (active automatic theme fixtures; cadr `settings-selector-active-automatic-theme`
  vs pi `ThemeSubmenu.getActiveAutomaticTheme`). Friend-MachineD n=5 **1.33×**
  (0.2 / 0.1 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.settings_automatic_theme_setting`
  (automatic theme format fixtures; cadr `settings-selector-automatic-theme-setting`
  vs pi `ThemeSubmenu.getAutomaticThemeSetting`). Friend-MachineD n=5 **2.42×**
  (0.4 / 0.2 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_interactive_controller.resolve_theme`
  (theme resolve fixtures; cadr `resolve-theme-setting` vs pi
  `resolveThemeSetting`). Friend-MachineD n=5 **1.16×** (0.8 / 0.7 µs),
  ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_interactive_controller.parse_auto_theme`
  (auto theme parse fixtures; cadr `parse-auto-theme-setting` vs pi
  `parseAutoThemeSetting`). Friend-MachineD n=5 **1.96×** (1.0 / 0.5 µs),
  ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.settings_display_value`
  (settings value label fixtures; cadr `settings-display-value` vs pi
  boolean/value formatting). Friend-MachineD n=5 **3.39×** (0.6 / 0.2 µs),
  ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.settings_thinking_description`
  (thinking-level description fixtures; cadr `settings-thinking-description`
  vs pi `THINKING_DESCRIPTIONS`). Friend-MachineD n=5 **0.80×** (0.3 / 0.3 µs),
  ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.session_named_p`
  (named session predicate fixtures; cadr `named-session-p` vs pi
  `hasSessionName`). Friend-MachineD n=5 **2.11×** (0.6 / 0.3 µs),
  ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.session_quoted_p`
  (quoted phrase predicate fixtures; cadr `quoted-search-p` vs pi
  `quotedSearchPi`). Friend-MachineD n=5 **0.43×** (0.3 / 0.7 µs),
  ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.session_same_path`
  (session path equality fixtures; cadr `same-session-path-p` vs pi
  `canonicalizePath` equality). Friend-MachineD n=5 **0.65×** (22.1 / 33.9 µs),
  ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.session_binding_label`
  (session selector keybinding fixtures; cadr `session-selector-binding-label`
  vs pi `KeybindingsManager.getKeys` first-or-name). Friend-MachineD n=5
  **1.43×** (41.2 / 28.9 µs), ceiling 8.0. Same commit no optimize.
  G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.session_thread_records`
  (parent/child session tree fixtures; cadr `thread-session-records`
  vs pi `buildSessionTree` + `flattenSessionTree`). Friend-MachineD n=5
  **13.07×** (165.9 / 12.7 µs), ceiling 30.0. Same commit no optimize.
  G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.session_quoted_search`
  (quoted phrase position fixtures; cadr `search-record-position`
  vs pi phrase indexOf). Friend-MachineD n=5 **1.29×** (11.0 / 8.6 µs),
  ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `cli_selectors.session_shorten_path`
  (session path tilde fixtures; cadr `session-selector-shorten-path`
  vs pi `shortenPath`). Friend-MachineD n=5 **5.05×** (5.5 / 1.1 µs),
  ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `cli_selectors.session_record_label`
  (session row label fixtures; cadr `session-selector-record-label`
  vs pi session list label). Friend-MachineD n=5 **1.84×** (2.6 /
  1.4 µs), ceiling 8.0. Same commit no optimize. G.17 missing. Not
  Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.session_format_age`
  (session age label fixtures; cadr `session-selector-format-age` vs pi
  `formatSessionDate`). Friend-MachineD n=5 **1.00×** (0.7 / 0.7 µs),
  ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `cli_selectors.keybinding_hint`
  (selector footer hint fixtures; cadr `selector-keybinding-hint` vs pi
  `rawKeyHint`). Friend-MachineD n=5 **1.32×** (59.9 / 23.2 µs),
  ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `cli_selectors.keybinding_text`
  (selector footer key join fixtures; cadr `selector-keybinding-text`
  vs pi `KeybindingsManager.getKeys` join). Friend-MachineD n=5
  **0.61×** (36.7 / 23.3 µs), ceiling 8.0. Same commit no optimize.
  G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.input_line`
  (selector search input render fixtures; cadr `selector-input-line` vs
  pi `Input.render`). Friend-MachineD n=5 **0.05×** (39.4 / 272.8 µs),
  ceiling 8.0. Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `cli_selectors.overlay_title_line`
  (auth overlay accent bold title fixtures; cadr
  `selector-overlay-title-line` vs pi oauth `TruncatedText` margins).
  Friend-MachineD n=5 **0.16×** (33.4 / 205.6 µs), ceiling 8.0. Same
  commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.title_line`
  (accent bold title fixtures; cadr `selector-title-line` vs pi
  `theme.fg accent` + `theme.bold` + Text margins). Friend-MachineD
  n=5 **0.61×** (33.3 / 51.3 µs), ceiling 8.0. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.modified_cursor_key`
  (CSI modified-arrow fixtures; cadr `selector-modified-cursor-key`
  vs pi `parseKey`). Friend-MachineD n=5 **11.56×** (47.3 / 4.1 µs),
  ceiling 20.0. Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `cli_selectors.dim_line`
  (dim fg + truncate fixtures; cadr `selector-dim-line` vs pi
  `theme.fg dim` + truncate). Friend-MachineD n=5 **0.61×**
  (18.9 / 30.9 µs), ceiling 8.0. Same commit no optimize. G.17
  missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.muted_line`
  (muted fg + truncate fixtures; cadr `selector-muted-line` vs pi
  `theme.fg muted` + truncate). Friend-MachineD n=5 **0.24×**
  (19.2 / 80.9 µs), ceiling 8.0. Same commit no optimize. G.17
  missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.selected_line`
  (selected-bg fit fixtures; cadr `selector-selected-line` vs pi
  `theme.bg selectedBg` + pad). Friend-MachineD n=5 **0.83×**
  (22.0 / 26.4 µs), ceiling 8.0. Same commit no optimize. G.17
  missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.border_line`
  (themed rule fixtures; cadr `selector-border-line` vs pi
  `DynamicBorder.render`). Friend-MachineD n=5 **0.65×**
  (8.6 / 13.2 µs), ceiling 8.0. Same commit no optimize. G.17
  missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.fit_line`
  (truncate/pad fixtures; cadr `selector-fit-line` vs pi
  `truncateToWidth` + pad). Friend-MachineD n=5 **0.32×**
  (10.3 / 31.7 µs), ceiling 8.0. Same commit no optimize. G.17
  missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.align_left_right`
  (truncate/pad fixtures; cadr `selector-align-left-right` vs pi
  session-selector header align). Friend-MachineD n=5 **3.79×**
  (27.2 / 7.2 µs), ceiling 8.0. Same commit no optimize. G.17
  missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.move_index`
  (wrap fixtures; cadr `selector-frame-move-index` vs pi mod-wrap).
  Friend-MachineD n=5 **1.44×** (4.5 / 3.1 µs), ceiling 8.0. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.visible_slice`
  (centered viewport fixtures; cadr
  `selector-frame-visible-slice` vs pi selector slice formula).
  Friend-MachineD n=5 **2.23×** (2.5 / 1.1 µs), ceiling 8.0.
  Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.delete_query`
  (grapheme backspace fixtures; cadr
  `selector-delete-query-character` vs pi `Input` backspace).
  Friend-MachineD n=5 **0.19×** (2.2 / 11.3 µs), ceiling 8.0. cadr
  leads. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.fuzzy_filter`
  (empty / token / slash fixtures; cadr `selector-fuzzy-filter` vs pi
  `fuzzyFilter`). Friend-MachineD n=5 **0.34×** (8.2 / 23.7 µs),
  ceiling 8.0. cadr leads. Same commit no optimize. G.17 missing.
  Not Goal 20 complete.
- Goal 20 P.13: pair `agent_tool_loop.line_ending`
  (LF / CRLF / none / empty; cadr `detect-line-ending` vs pi
  `detectLineEnding`). Do not exact mixed LF-then-CRLF. Friend-
  MachineD n=5 **1.99×** (0.75 / 0.38 µs), ceiling 8.0. Same
  commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `agent_tool_loop.tool_path`
  (relative / abs / `@` / nbsp / parent; cadr
  `resolve-tool-path` vs pi `resolveToCwd`). Do not
  exact empty or `~` (trailing slash). Friend-MachineD
  n=5 **2.44×** (12.74 / 5.23 µs), ceiling 8.0. Same
  commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `settings_load.http_idle`
  (named timeout choices; cadr
  `http-idle-timeout-label` vs pi
  `formatHttpIdleTimeoutMs`). Do not exact custom
  timeouts. Friend-MachineD n=5 **0.47×** (0.25 / 0.53 µs),
  ceiling 8.0. cadr leads. Same commit no optimize. G.17
  missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_interactive_controller.auth_type`
  (`:oauth` / `:api-key`; cadr `tui-auth-type-label` vs pi
  `formatAuthSelectorProviderType`). Do not exact other
  types. Friend-MachineD n=5 **1.44×** (0.21 / 0.15 µs),
  ceiling 8.0 (microsecond-floor). Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `evals_harness.format`
  (empty + four scored observations; cadr
  `format-harness-comparison-report` vs pi
  `formatHarnessComparisonReport`). Strip ANSI
  for flags; do not exact full report text.
  Friend-MachineD n=5 **1.14×** (20.62 / 18.10 µs),
  ceiling 8.0. Same commit no optimize. G.17
  missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.key_text`
  (`ctrl+c` / slash / `shift+tab` / capitalize / empty;
  cadr `format-key-text` vs pi `formatKeyText`).
  Friend-MachineD n=5 **2.86×** (5.76 / 2.01 µs), ceiling
  8.0. Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `cli_support.experimental`
  (`"1"` / empty / `"0"` / `"true"` / nil; cadr
  `experimental-features-enabled-p` vs pi
  `areExperimentalFeaturesEnabled`). Friend-MachineD n=5
  **0.05×** (0.23 / 4.77 µs), ceiling 8.0. cadr leads.
  Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `evals_harness.artifact_persist`
  (session+source fixture; cadr
  `persist-eval-artifact-references` vs pi
  `persistEvalArtifactReferences`). Friend-MachineD n=5
  **0.53×** (595 / 1130 µs), ceiling 8.0. cadr leads.
  `atomic-file.lisp` covered-as-callee. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `websocket_stream.stream_roundtrip`
  (recorded Codex WS frames; cadr Goal 12 loopback vs
  pi MockWebSocket). Friend-MachineD n=5 **507.72×**
  (44298 / 87.25 µs), ceiling 800.0. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_selectors.session_search`
  (empty / substring / miss / `re:` / invalid regex /
  named filter; cadr `filter-and-sort-sessions` vs pi
  `filterAndSortSessions`). Friend-MachineD n=5 **2.48×**
  (42.40 / 17.10 µs), ceiling 8.0. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `tui_mermaid.transform`
  (fence / mode off / thinking / too-wide; cadr
  `transform-mermaid-markdown` vs pi
  `createMermaidMarkdownTransformer`). Friend-MachineD n=5
  **0.65×** (69.67 / 107.87 µs), ceiling 8.0. cadr leads.
  Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `tui_mermaid.source_box`
  (flowchart LR at 80/12 cols + empty; cadr `gm-source-box`
  vs grok-mermaid `sourceBox`). Friend-MachineD n=5
  **0.38×** (58.73 / 155.58 µs), ceiling 8.0. cadr leads.
  Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `tui_mermaid.render`
  (flowchart LR / empty / unknown / CJK; cadr `gm-render` vs
  grok-mermaid `render`). Friend-MachineD n=5 **0.30×**
  (75.31 / 255.24 µs), ceiling 8.0. cadr leads. Same commit
  no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `oauth_pkce_device.copilot_auth`
  (default / proxy-ep / enterprise domain; cadr
  `github-copilot-oauth-to-auth` vs pi
  `githubCopilotOAuth.toAuth`). Friend-MachineD n=5
  **1.35×** (3.21 / 2.38 µs), ceiling 8.0. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_print_rpc.session_stats`
  (fixture session.jsonl; cadr `rpc-session-stats` vs pi
  `AgentSession.getSessionStats`). Friend-MachineD n=5
  **0.19×** (13.16 / 70.76 µs), ceiling 8.0. cadr leads.
  Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `cli_sdk.model_runtime`
  (builtin providers + `gpt-4o-mini`; cadr
  `sdk-model-runtime-providers` vs pi
  `ModelRuntime.getProviders`). Friend-MachineD n=5 **0.58×**
  (2243 / 3858 µs), ceiling 8.0. cadr leads. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_sdk.session_services`
  (isolated cwd; cadr `create-agent-session-services` vs pi
  `createAgentSessionServices`). Friend-MachineD n=5 **0.24×**
  (2306 / 9493 µs), ceiling 8.0. cadr leads. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_sdk.agent_session`
  (isolated cwd, in-memory session, explicit model,
  no-tools; cadr `create-agent-session` vs pi
  `createAgentSession`). Friend-MachineD n=5 **0.36×**
  (3151 / 8769 µs), ceiling 8.0. cadr leads. Same commit
  no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_interactive_controller.cwd_footer`
  (POSIX home/`~/proj`/outside; cadr `format-cwd-for-footer` vs
  pi `formatCwdForFooter`). Friend-MachineD n=5 **0.34×**
  (0.78 / 2.31 µs), ceiling 8.0. cadr leads. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_extensions_install.llama_catalog`
  (loaded catalog only; cadr `llama-provider-set-catalog` vs pi
  `createLlamaProvider().setCatalog`). Friend-MachineD n=5
  **0.36×** (4.78 / 13.41 µs), ceiling 8.0. cadr leads. Same
  commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `evals_harness.group_key`
  (id-bearing inputs + artifact parse; cadr
  `derive-eval-group-key` vs pi `deriveEvalGroupKey`).
  Friend-MachineD n=5 **4.06×** (5.01 / 1.23 µs), ceiling
  8.0 (variance). Same commit no optimize. G.17 missing.
  Not Goal 20 complete.
- Goal 20 P.13: pair `cli_interactive_controller.wayland`
  (injected env; cadr `clipboard-wayland-p` vs pi
  `isWaylandSession`). Friend-MachineD n=5 **1.17×**
  (0.36 / 0.30 µs), ceiling 8.0 (variance). Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `oauth_pkce_device.radius_gateway`
  (already-schemed URLs only; cadr
  `normalize-radius-gateway` vs pi
  `normalizeRadiusGatewayUrl`). Friend-MachineD n=5 **1.05×**
  (0.57 / 0.54 µs), ceiling 8.0 (variance). Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `oauth_pkce_device.cloudflare_url`
  (plain URL / account+gateway placeholders / gateway-only;
  cadr `materialize-cloudflare-url` vs pi
  `resolveCloudflareModel`). Friend-MachineD n=5 **6.66×**
  (9.27 / 1.39 µs), ceiling 8.0 (variance). Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_sdk.session_list`
  (two rewritten-cwd copies of session.jsonl + empty dir;
  cadr `session-manager-list` vs pi `SessionManager.list`).
  Friend-MachineD n=5 **1.93×** (15402 / 7989 µs), ceiling
  8.0. Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `oauth_pkce_device.copilot_url`
  (default / individual proxy-ep / enterprise proxy-ep /
  enterprise domain; cadr `github-copilot-base-url` vs pi
  `githubCopilotOAuth.toAuth`). Friend-MachineD n=5 **1.15×**
  (2.12 / 1.85 µs), ceiling 8.0. Same commit no optimize.
  G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `oauth_pkce_device.auth_json`
  (api_key / oauth / miss / invalid JSON; cadr
  `read-auth-credential` vs pi `ReadOnlyAuthStorage.read`).
  Friend-MachineD n=5 **1.21×** (257.5 / 212.9 µs), ceiling
  8.0. Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `cli_print_rpc.clamp_thinking`
  (off/high/xhigh/max + xhigh-down + unknown; cadr
  `rpc-clamp-thinking-level` vs pi `clampThinkingLevel`).
  Friend-MachineD n=5 **0.59×** (1.37 / 2.33 µs), ceiling
  8.0. cadr leads. Same commit no optimize. G.17 missing.
  Not Goal 20 complete.
- Goal 20 P.13: pair `settings_load.config_value`
  (literal / `$FOO` / `${FOO}` / `$$` / `$!` / miss / mix;
  `!command` flag only, no spawn; cadr `resolve-config-value`
  vs pi `resolveConfigValue`). Friend-MachineD n=5 **0.43×**
  (2.70 / 6.21 µs), ceiling 8.0. cadr leads. Same commit
  no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_extensions_install.hf_token`
  (env / token-path / HF_HOME / miss / blank; isolated HOME;
  cadr `find-hugging-face-token` vs pi `findHuggingFaceToken`).
  Friend-MachineD n=5 **0.28×** (277.4 / 1002.4 µs), ceiling
  8.0. cadr leads. Same commit no optimize. G.17 missing.
  Not Goal 20 complete.
- Goal 20 P.13: pair `cli_extensions_install.llama_url`
  (strip `/v1`+query+hash, file:// error, `/v1` inference,
  byte units; cadr `normalize-llama-server-url` vs pi
  `normalizeLlamaServerUrl`). Friend-MachineD n=5 **0.45×**
  (4.79 / 10.52 µs), ceiling 8.0. cadr leads. Same commit
  no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `oauth_pkce_device.poll`
  (injected poll, no socket; cadr
  `poll-device-authorization` vs pi
  `pollOAuthDeviceCodeFlow`). Friend-MachineD n=5 **0.09×**
  (1.01 / 11.51 µs), ceiling 8.0. cadr leads. Same commit
  no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `settings_load.project_trust`
  (empty vs project resources; ask/always/never/override;
  cadr `resolve-project-trusted` vs pi
  `resolveProjectTrusted`). Friend-MachineD n=5 **0.24×**
  (330.6 / 1402.9 µs), ceiling 8.0. cadr leads. Same
  commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_sdk.thinking_level`
  (lowercase off/minimal/low/medium/high/xhigh/max + miss;
  cadr `valid-thinking-level-p` vs pi `isValidThinkingLevel`).
  Friend-MachineD n=5 **3.21×** (0.72 / 0.22 µs), ceiling 8.0
  (variance). Same commit no optimize. G.17 missing. Not
  Goal 20 complete.
- Goal 20 P.13: pair `cli_sdk.cache_waste`
  (3-turn miss / healthy / compaction skip / model-switch /
  no-cache; cadr `compute-cache-waste` vs pi
  `computeCacheWaste`). Friend-MachineD n=5 **0.60×**
  (3.96 / 6.56 µs), ceiling 8.0. cadr leads. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_sdk.cache_miss`
  (in-memory assistant usage miss/healthy/empty; cadr
  `detect-cache-miss` vs pi `detectCacheMiss`). Friend-MachineD
  n=5 **0.55×** (2.29 / 4.13 µs), ceiling 8.0. cadr leads.
  Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `cli_models_rest.auth_command`
  (argv-only parse, no live auth; cadr `parse-auth-command`
  vs pi `parseAuthCommand`). Friend-MachineD n=5 **0.47×**
  (3.56 / 7.54 µs), ceiling 8.0. cadr leads. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_models_rest.login_selection`
  (post-login model pick; cadr `classify-post-login-model` /
  `post-login-selection-result` vs pi
  `completeProviderAuthentication`). Friend-MachineD n=5
  **1.78×** (7.53 / 4.22 µs), ceiling 8.0. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_support.parse_changelog`
  (`0.2.0` / malformed / `0.1.0` + missing empty; cadr
  `parse-changelog` vs pi `parseChangelog`). Friend-MachineD
  n=5 **2.96×** (36.04 / 12.20 µs), ceiling 8.0. Same
  commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_support.user_agent`
  (version substring / parens / two semicolons; cadr
  `cadr-user-agent` vs pi `getPiUserAgent`). Friend-MachineD
  n=5 **3.14×** (1.41 / 0.45 µs), ceiling 8.0 (variance).
  Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `cli_support.git_source`
  (HTTPS+ref / git: scp / git: shorthand; cadr
  `parse-git-source` vs pi `parseGitUrl`). Friend-MachineD
  n=5 **0.48×** (26.85 / 55.99 µs), ceiling 8.0. cadr
  leads. Same commit no optimize. G.17 missing. Not
  Goal 20 complete.
- Goal 20 P.13: pair `cli_support.sanitize_output`
  (NUL/BEL/ESC/U+FFF9 stripped, tab/LF/CR kept; cadr
  `sanitize-binary-output` vs pi `sanitizeBinaryOutput`).
  Friend-MachineD n=5 **0.91×** (1.26 / 1.39 µs), ceiling
  8.0 (variance). cadr leads. Same commit no optimize.
  G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_support.shell_config`
  (default + custom `/bin/bash` + missing path; cadr
  `get-shell-config` vs pi `getShellConfig`).
  Friend-MachineD n=5 **2.47×** (21.07 / 8.54 µs),
  ceiling 8.0. Same commit no optimize. G.17 missing.
  Not Goal 20 complete.
- Goal 20 P.13: pair `cli_support.attribution_headers`
  (OpenRouter/NVIDIA/Cloudflare/OpenCode presence flags;
  cadr `provider-attribution-headers` vs pi
  `mergeProviderAttributionHeaders`). Friend-MachineD
  n=5 **0.29×** (2.70 / 9.31 µs), ceiling 8.0. cadr leads.
  Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `cli_support.event_bus`
  (on/emit/unsub/thrower/clear; cadr `make-event-bus`
  vs pi `createEventBus`). Friend-MachineD n=5 **0.33×**
  (2.68 / 8.21 µs), ceiling 8.0. cadr leads. Same
  commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `ai_capabilities.session_resources`
  (register + cleanup recorder/thrower; cadr
  `register-session-resource-cleanup` /
  `cleanup-session-resources` vs pi
  `registerSessionResourceCleanup` /
  `cleanupSessionResources`). Friend-MachineD n=5
  **0.16×** (1.41 / 9.04 µs), ceiling 8.0. cadr leads.
  Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `ai_capabilities.http_proxy`
  (HTTPS_PROXY hit / NO_PROXY skip; cadr
  `resolve-http-proxy-url-for-target` vs pi
  `resolveHttpProxyUrlForTarget`). Friend-MachineD n=5
  **0.45×** (5.71 / 12.59 µs), ceiling 8.0. cadr leads.
  Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `cli_support.timings`
  (reset + boot/load print; cadr `reset-timings` /
  `record-timing` / `print-timings` vs pi `resetTimings` /
  `time` / `printTimings`). Friend-MachineD n=5 **1.71×**
  (4.55 / 2.66 µs), ceiling 8.0. Same commit no optimize.
  G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `ai_capabilities.event_stream`
  (FIFO a/b/end; cadr `make-event-stream` vs pi
  `EventStream`). Friend-MachineD n=5 **1.44×**
  (1.73 / 1.20 µs), ceiling 8.0 (variance). Same
  commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `ai_support.auth_guidance`
  (no-models / no-selected / no-key prefixes; cadr
  `no-models-available-message` vs pi
  `formatNoModelsAvailableMessage`). Friend-MachineD
  n=5 **27.66×** (1922 / 69.5 µs), ceiling 50.0
  (ASDF docs-dir). Same commit no optimize. G.17
  missing. Not Goal 20 complete.
- Goal 20 P.13: pair `ai_capabilities.deferred_tools`
  (grep/bash immediate, read deferred when enabled;
  cadr `split-deferred-tools` vs pi
  `splitDeferredTools`). Friend-MachineD n=5
  **2.04×** (5.51 / 2.70 µs), ceiling 8.0. Same
  commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `ai_support.uuid_v7`
  (format 36/4/7/variant, two distinct; cadr
  `uuid-v7` vs pi `uuidv7`). Friend-MachineD n=5
  **0.32×** (3.08 / 9.49 µs), ceiling 8.0. cadr
  leads. Same commit no optimize. G.17 missing.
  Not Goal 20 complete.
- Goal 20 P.13: pair `cli_print_rpc.jsonl_read`
  (3 JSONL lines including CRLF; cadr
  `read-rpc-jsonl-lines` vs pi
  `attachJsonlLineReader`). Friend-MachineD n=5
  **0.03×** (0.63 / 23.84 µs), ceiling 8.0. cadr
  leads. Same commit no optimize. G.17 missing.
  Not Goal 20 complete.
- Goal 20 P.13: pair `image_runtime.api_provider`
  (fixture API present / nope missing; cadr
  `get-images-api-provider` vs pi
  `getImagesApiProvider`). Friend-MachineD n=5
  **1.09×** (0.23 / 0.21 µs), ceiling 8.0 (variance).
  Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `image_runtime.dimension_note`
  (resized 2000×1000→1000×500 / 1000×800→400×320 /
  unresized 64×64; cadr `format-image-dimension-note`
  vs pi `formatDimensionNote`). Friend-MachineD n=5
  **1.73×** (3.67 / 2.12 µs), ceiling 8.0. Same commit
  no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `image_runtime.lookup`
  (gemini / flux / nope; cadr `find-image-model` vs pi
  `getImageModel`). Friend-MachineD n=5 **7.38×**
  (1.51 / 0.20 µs), ceiling 8.0 (variance). Same commit
  no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `image_runtime.mime_type`
  (PNG / JPEG SOI / GIF89a / WEBP / miss; cadr
  `detect-image-mime-type` vs pi
  `detectSupportedImageMimeType`). Friend-MachineD n=5
  **1.62×** (6.63 / 4.09 µs), ceiling 8.0. Same commit
  no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `ai_support.grammar_delta`
  (`hel`→`hello`→close; cadr `append-grammar-json-delta`
  vs pi `appendGrammarToolInputJsonDelta`).
  Friend-MachineD n=5 **2.87×** (1.52 / 0.53 µs),
  ceiling 8.0 (variance). Same commit no optimize.
  G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `ai_crypto.hmac` (fox / empty /
  70-byte key; cadr `hmac-sha256` vs `node:crypto`
  `createHmac`). Friend-MachineD n=5 **18.81×**
  (133.9 / 7.1 µs), ceiling 30.0. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `ai_support.context_overflow`
  (prompt-too-long / rate-limit / silent stop /
  length-full; cadr `context-overflow-p` vs pi
  `isContextOverflow`). Friend-MachineD n=5 **1.67×**
  (1.85 / 1.11 µs), ceiling 8.0 (variance). Same commit
  no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_support.normalize_path`
  (trim / @strip / unicode-nbsp / tilde+home /
  `file:///tmp/z`; cadr `normalize-path-input` vs pi
  `normalizePath`). Friend-MachineD n=5 **2.82×**
  (4.58 / 1.63 µs), ceiling 8.0. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `http_transport.parse_url`
  (`https://example.com/foo` + `http://localhost:8080/bar`;
  cadr `parse-http-url` vs WHATWG `URL`). Friend-MachineD
  n=5 **0.99×** (1.16 / 1.17 µs), ceiling 8.0 (variance).
  Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `ai_runtime_faux.blocks`
  (`hello`/`hmm`; cadr `faux-text`+`faux-thinking` vs pi
  `fauxText`+`fauxThinking`). Friend-MachineD n=5
  **1.76×** (0.27 / 0.15 µs), ceiling 8.0 (variance).
  Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `cli_bootstrap_sessions.coding_tools`
  (cwd `/tmp/proj`; cadr `make-coding-tools` vs pi
  `createCodingTools`). Friend-MachineD n=5 **2.40×**
  (11.1 / 4.6 µs), ceiling 8.0. Same commit no optimize.
  G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `skill_prompt_load.build_prompt`
  (custom/append/context; cadr `build-system-prompt` vs
  pi `buildSystemPrompt`). Friend-MachineD n=5
  **1170.57×** (2196 / 1.88 µs), ceiling 3000.0. Same
  commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `storage_journal.journal_entry_count`
  (in-memory count on append journal; cadr `session-entry-count` vs pi
  `SessionManager.getEntries().length`). Observed `session_entry_count`
  exact (128). Friend-MachineD n=5 **0.09×** (0.22 / 2.4 µs), ceiling 8.0.
  cadr leads. Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_bootstrap_sessions.bootstrap_auth`
  (built-in login option projection; cadr `model-registry-login-options` vs
  pi `getLoginProviderOptions`). Observed `option_count` / `auth_pairs_digest`
  / `vertex_structured` / `bedrock_structured` exact. Friend-MachineD n=5
  **0.64×** (3928.6 / 6134.0 µs), ceiling 8.0. cadr leads. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `provider_registry_defs.definition_ids`
  (built-in catalog ids; cadr `list-provider-definition-ids` vs pi
  `getBuiltinProviders`). Observed `count` / `sorted_digest` exact.
  Friend-MachineD n=5 **99.97×** (728.7 / 7.3 µs), ceiling 125.0. Same
  commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `provider_registry_defs.lookup`
  (openai/anthropic/google; cadr
  `find-provider-definition` vs pi `getBuiltinProviders`).
  Friend-MachineD n=5 **4.44×** (1.03 / 0.23 µs), ceiling
  8.0 (variance). Same commit no optimize. G.17 missing.
  Not Goal 20 complete.
- Goal 20 P.13: pair `cli_sdk.version_newer` (valid
  semver; cadr `newer-package-version-p` vs pi
  `isNewerPackageVersion`). Friend-MachineD n=5
  **0.40×** (4.1 / 10.3 µs), ceiling 8.0. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair
  `cli_interactive_controller.decode_entity` (amp/lt/`#65`;
  cadr `decode-highlight-entity` vs pi
  `decodeHtmlEntity`). Friend-MachineD n=5 **1.49×**
  (0.63 / 0.42 µs), ceiling 8.0 (variance). Same commit
  no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_support.strip_ansi` (CSI+OSC /
  RIS / ESC m / plain; cadr `strip-ansi` vs pi
  `stripAnsi`). Friend-MachineD n=5 **2.73×**
  (1.3 / 0.5 µs), ceiling 8.0 (variance). Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `ai_capabilities.short_hash` (empty /
  `abc` / CJK+emoji; cadr `short-hash` vs pi `shortHash`).
  Friend-MachineD n=5 **1.70×** (1.5 / 0.9 µs), ceiling
  8.0 (variance). Same commit no optimize. G.17 missing.
  Not Goal 20 complete.
- Goal 20 P.13: pair `tui_settings_list.apply_filter`
  (Hello/Help/World; cadr `settings-list-apply-filter` vs
  pi `SettingsList.applyFilter`). Friend-MachineD n=5
  **0.47×** (5.3 / 11.4 µs), ceiling 8.0. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `tui_native_modifiers.pressed`
  (shift/control/option/command; cadr
  `is-native-modifier-pressed` vs pi
  `isNativeModifierPressed`). Friend-MachineD n=5 **7.50×**
  (1.22 / 0.16 µs), ceiling 8.0 (variance). Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `tui_input_component.edit` (type /
  backspace / kill-to-start / yank; cadr
  `single-line-input-handle-event` vs pi
  `Input.handleInput`). Friend-MachineD n=5 **0.06×**
  (5.5 / 97.8 µs), ceiling 8.0. Same commit no optimize.
  G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `tui_stdin_buffer.process` (`hello` +
  incomplete CSI + up + bracketed paste; cadr
  `stdin-buffer-process` vs pi `StdinBuffer.process`).
  Friend-MachineD n=5 **0.33×** (2.3 / 6.9 µs), ceiling
  8.0. Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `tui_keybindings.resolve_match` (default
  TUI registry + `ctrl+k` clash; cadr
  `make-keybindings-manager` vs pi `KeybindingsManager`).
  Friend-MachineD n=5 **1.88×** (27.7 / 14.8 µs), ceiling
  8.0. Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `tui_autocomplete.suggest_apply` (slash
  `/he`, quoted `"hel`, force Tab, `@he` no fd; cadr
  `autocomplete-get-suggestions/apply` vs pi
  `CombinedAutocompleteProvider`). Friend-MachineD n=5
  **5.17×** (136.4 / 26.4 µs), ceiling 8.0. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `tui_undo_stack.push_pop` (clone-on-push
  `{text,n}`; cadr `undo-stack-*` vs pi `UndoStack`).
  Friend-MachineD n=5 **0.21×** (0.51 / 2.42 µs), ceiling
  8.0. Same commit no optimize. G.17 missing. Not Goal 20
  complete.
- Goal 20 P.13: pair `tui_kill_ring.push_peek` (push/peek/
  rotate n=2 + accumulate; cadr `kill-ring-*` vs pi
  `KillRing`). Friend-MachineD n=5 **0.85×**
  (0.58 / 0.68 µs), ceiling 8.0 (variance). Same commit
  no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `tui_overlay.composite_line` (ASCII
  overlay at col 6; cadr `composite-overlay-line` vs pi
  `compositeTuiLine`). Friend-MachineD n=5 **0.87×**
  (19.1 / 22.0 µs), ceiling 8.0. Same commit no optimize.
  G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `tui_word_navigation.step` (`hello world`;
  cadr `find-word-backward/forward` vs pi
  `findWordBackward/Forward`). Friend-MachineD n=5 **0.17×**
  (0.94 / 5.4 µs), ceiling 8.0. Same commit no optimize.
  G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `tui_select_settings_loaders.filter`
  (hello/help/world; cadr `select-list-filtered-items` vs pi
  `SelectList.setFilter`). Friend-MachineD n=5 **1.27×**
  (1.2 / 1.0 µs), ceiling 8.0 (variance). Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `ai_support.estimate_text` (empty /
  hello / 100 `a`; cadr `estimate-text-tokens` vs pi
  `estimateTextTokens`). Friend-MachineD n=5 **3.10×**
  (0.54 / 0.17 µs), ceiling 8.0 (variance). Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `tui_theme_overlay.osc11_bg` (OSC 11
  rgb/hex; cadr `parse-osc-11-background-color` vs pi
  `parseOsc11BackgroundColor`). Friend-MachineD n=5
  **1.16×** (3.8 / 3.3 µs), ceiling 8.0. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `tui_editor_helpers.fuzzy_match`
  (`gpt-4o` queries; cadr `fuzzy-match` vs pi `fuzzyMatch`).
  Friend-MachineD n=5 **0.45×** (1.8 / 4.0 µs), ceiling 8.0.
  Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `tui_latex.normalize_output` (marker/whitespace
  cleanup fixtures; cadr `latex-normalize-output` vs pi
  `normalizeOutput`). Friend-MachineD n=5 **1.46×** (12.7 / 8.7 µs),
  ceiling 20.0. Gate used `--only-enforce`. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `tui_latex.render` (reference snippets;
  cadr `render-latex` vs pi `renderLatex`). Friend-MachineD
  n=5 **2.49×** (64.4 / 25.8 µs), ceiling 3.0. Same commit
  no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_print_rpc.jsonl_line` (RPC
  `get_state` response; cadr `write-json-line` vs pi
  `serializeJsonLine`). Friend-MachineD n=5 **13.21×**
  (3.3 / 0.25 µs), ceiling 8.0 (variance). Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `image_runtime.dimensions` (1x1 PNG +
  2x3 GIF; cadr `image-dimensions` vs pi
  `getImageDimensions`). Friend-MachineD n=5 **5.44×**
  (7.8 / 1.4 µs), ceiling 8.0. Same commit no optimize.
  G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `cli_models_rest.pattern_match`
  (staged models.json; cadr `parse-scoped-model-pattern` vs
  pi `parseModelPattern`). Friend-MachineD n=5 **1.65×**
  (31.9 / 19.4 µs), ceiling 3.0. Same commit no optimize.
  G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `ai_crypto_model_data.manifest`
  (two-provider fixture; cadr `create-model-data-manifest`
  vs pi `createModelDataManifest`). Friend-MachineD n=5
  **8.97×** (77.3 / 8.6 µs), ceiling 20.0. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `evals_harness.summarize` (four scored
  observations; cadr `summarize-harness-comparisons` vs pi
  `summarizeHarnessComparisons`). Friend-MachineD n=5 **0.88×**
  (8.0 / 9.0 µs), ceiling 1.5. Same commit no optimize. G.17
  missing. Not Goal 20 complete.
- Goal 20 P.13: pair `oauth_pkce.challenge_urls` (RFC 7636
  verifier; cadr `pkce-challenge` + authorize URLs vs pi
  SHA-256 S256 + openai/anthropic URLs). Friend-MachineD n=5
  **0.37×** (50.6 / 135.3 µs), ceiling 1.5. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `agent_proxy.stream_roundtrip` (stub SSE;
  cadr `stream-proxy` vs pi `streamProxy`). Friend-MachineD n=5
  **1.59×** (25.4 / 16.0 µs), ceiling 1.5. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `protocol_codec.roundtrip` (client
  `list` request; cadr `encode-client-message` vs pi
  `encodeClientMessage`). Friend-MachineD n=5 **0.10×**
  (9.6 / 94.2 µs), ceiling 1.5. Same commit no optimize.
  G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `harness_storage.open_walk` (JSONL
  harness repo; cadr `session-repository-open` vs pi
  `JsonlSessionRepo.open`). Friend-MachineD n=5 **1.80×**
  (11643.5 / 6484.9 µs), ceiling 8.0. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `agent_schema.validate_ok_fail`
  (FiveAM edit-tool JSON Schema; cadr `validate-tool-arguments`
  vs pi `validateToolArguments`). Friend-MachineD n=5 **0.38×**
  (34.2 / 89.4 µs), ceiling 1.5. Same commit no optimize.
  G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `protocol_cbor.roundtrip` (16 RFC 8949
  vectors; cadr encode/decode vs pi encodeCbor/decodeCbor).
  Friend-MachineD n=5 **0.25×** (17.7 / 70.1 µs), ceiling 1.5.
  Same commit no optimize. G.17 missing. Not Goal 20 complete.
- Goal 20 P.13: pair `session_export_html.to_html`
  (`session.jsonl` → HTML; cadr `export-session-html` vs pi
  `exportSessionToHtml`). Friend-MachineD n=5 **3.55×**
  (29217.8 / 8239.7 µs), ceiling 20.0. `html_chars` size gap
  booked, not exact. Same commit no optimize. G.17 missing.
  Not Goal 20 complete.
- Goal 20 P.13: pair `session_discovery.header_probe`
  (32 copies of `session.jsonl`; cadr header probe vs pi
  `findMostRecentSession`). Friend-MachineD n=5 **2.05×**
  (1449.6 / 708.6 µs), ceiling 8.0. Same commit no
  optimize. G.17 missing. Not Goal 20 complete.
- Goal 20: docs-only disposition for paired paths still
  >1.0× (load / journal_read / pi_messages / mistral /
  compact). Invent pause; 待本质提案. No optimize.
- Goal 20: refresh Part P acceptance (P.1 walker ~1763 /
  invent pause; P.8 deferred; P.13 schema 0% + required
  holes; Not claimed still G.17/`met`). No optimize.
- Goal 20 P.13: required holes all have H metrics
  (sqlite / tool_loop / compact / providers / settings /
  package / skills). No new pair. No optimize. G.17 missing.
- Goal 20 P.13: unpaired-paths schema books
  `covered-as-callee` and `needs-pair`. `--check`
  requires `pairable-uncovered` lines = 0 (295 files /
  127,389 lines; uncovered 82,256 → 0). No new
  unpairable. No file-level idle bench. G.17 missing.
- Goal 20: user pause on circling invent (2026-08-21).
  Walker remains `0084f0703` / load ~1763 µs. G.17 stays
  missing. Resume only with a concrete algorithm/DS
  proposal or user reopen (`docs/adjudications.md`).
- Goal 20: withdraw interned-ascii value length-gate
  (skip intern labels when n is outside 4–18).
  Friend-MachineD n=5: load cadr **1763→1901 µs**
  (worse; samples 1767–2802). Product restored to
  `0084f0703`. EQUAL test kept. Not intern-grow.
  Ceiling not lowered. Not G.17.
- Goal 20: remesure load `PARSE-SESSION-RECORD-OCTETS`
  sprof on walker `0084f0703`. Self%: parse 10.2,
  SCAN-KEY 8.2, SCAN-BUFFER 7.9, PARSE-STRING-VALUE 7.0,
  PARSE-USAGE 4.5, COPY-UNESCAPED 4.1. Not G.17.
- Goal 20: withdraw pi_messages pre-size EQUAL hash
  (`:size` / `:rehash-size` from known key counts).
  Friend-MachineD n=5: `provider_pi_messages`
  **1081→1225 µs** (worse; samples 1088–1344); load
  **1763→1971 µs**. Product restored. Not pairs. Not
  WRITE-JSON-STRING unescaped. Ceiling not lowered.
  Not G.17.
- Goal 20: withdraw pi_messages request `:json-object`
  pairs (not EQUAL hash tables). Friend-MachineD n=5:
  `provider_pi_messages` **1081→1153 µs** (worse;
  samples 1056–1955); load **1763→1952 µs**. Product
  restored. Not parse-json-octets. Not WRITE-JSON-STRING
  unescaped. Ceiling not lowered. Not G.17.
- Goal 20: remesure `provider_pi_messages` sprof on
  walker `0084f0703`. Leftover = character
  `PARSE-JSON-SOURCE` on SSE + `WRITE-JSON-STRING` +
  EQUAL hash grow. Not G.17.
- Goal 20: withdraw usage ASCII number value fast
  path (not usage key first-byte). Friend-MachineD
  n=5: load cadr **1763→1951 µs** (worse; samples
  1817–2327). Product restored to `0084f0703`.
  EQUAL test kept. Ceiling not lowered. Not G.17.
- Goal 20: withdraw WRITE-JSON-STRING unescaped
  simple-string shortcut (request stringify).
  Friend-MachineD n=5: `provider_pi_messages`
  **1081→1189 µs** (worse; samples 1105–1293); load
  **1763→1838 µs**. Product restored. EQUAL tests kept.
  Not event parse-json-octets. Ceiling not lowered.
  Not G.17.
- Goal 20: withdraw single-element content array
  shortcut (skip list+nreverse after compact-prefix).
  Friend-MachineD n=5: load cadr **1763→1929 µs**
  (worse; samples 1762–2538). Product restored to
  `0084f0703` walker. EQUAL test kept. Not bag / D
  svref / first-byte. Ceiling not lowered. Not G.17.
- Goal 20: withdraw SSE `data-octets` + `parse-json-octets`
  on openai-completions (mistral). Friend-MachineD n=5:
  mistral **2046→2219 µs**; load **1763→2152 µs**. Product
  restored. Ceiling not lowered. Not G.17.
- Goal 20: remesure `provider_mistral` sprof on walker
  `0084f0703`. Leftover = character `PARSE-JSON-SOURCE` on
  SSE data. Not G.17.
- Goal 20: withdraw `pi-event-data` `parse-json-octets`.
  Friend-MachineD n=5: `provider_pi_messages` cadr
  **1081→1190 µs** (worse); load **1763→1841 µs**. Product
  restored. Not intern-grow. Ceiling not lowered. Not G.17.
- Goal 20: remesure `provider_pi_messages` sprof on walker
  `0084f0703`. Leftover = character `PARSE-JSON-SOURCE` on
  SSE event payloads. Not G.17.
- Goal 20: withdraw inline `consume-line` into JSONL
  `scan-buffer`. Friend-MachineD n=5: load cadr
  **1763→1916 µs** (worse). Product restored to
  `0084f0703`. Not E tagbody. Ceiling not lowered. Not G.17.
- Goal 20: remesure `journal_read` sprof on walker
  `0084f0703`. Leftover = `SCAN-BUFFER` wrapping
  `consume-line` per JSONL line (not load first-byte).
  Not G.17.
- Goal 20: withdraw generic `parse-content-block` first-byte
  (`put-block-field`). Friend-MachineD n=5: load cadr
  **1763→2470 µs** (worse; samples 2345–3571). Product
  restored to `0084f0703` walker. Not bag reuse. Ceiling
  not lowered. Not G.17.
- Goal 20: withdraw `parse-usage` first-byte field dispatch.
  Friend-MachineD n=5: load cadr **1763→1996 µs** (worse;
  samples 1773–2127). Product restored to `0084f0703`
  walker. Not usage compact-prefix. Ceiling not lowered.
  Not G.17.
- Goal 20: silent stop after invent miss is invalid
  (`docs/adjudications.md`). Named next: `parse-usage`
  first-byte field dispatch, then generic
  `parse-content-block` first-byte. G.17 stays missing.
  Not G.17.
- Goal 20: withdraw invent usage compact-prefix (pairing
  fixture key order). Friend-MachineD n=5: load cadr
  **1763→1805 µs** (worse; samples 1768–1832). Product
  restored to `0084f0703` walker. Not bag reuse. Not EQ
  table. Ceiling not lowered. Not G.17.
- Goal 20: withdraw proposal 4 per-load ephemeral EQ
  dedupe. Friend-MachineD n=5: load cadr **1763→2217 µs**
  (worse; samples 2108–2295). Product restored to
  `0084f0703` walker. Not intern-grow. Ceiling not
  lowered. Not G.17.
- Goal 20: withdraw E `tagbody` merge of `put-entry-field`
  into the record-object walk. Friend-MachineD n=5: load
  cadr **1763→2004 µs** (worse; samples 1874–2315).
  Product restored to `0084f0703` walker. Not SCAN-KEY
  macrolet. Ceiling not lowered. Not G.17.
- Goal 20: recapture `PARSE-SESSION-RECORD-OCTETS` split on
  walker `0084f0703` / Friend-MachineD **~1763 µs**. Inclusive
  `CLOCK_MONOTONIC` ns around shipped labels (this-host
  `get-internal-real-time` is 1 ms). Production walker has no
  timer. Not G.17.
- Goal 20: user YES on proposal 4 (per-load ephemeral EQ
  dedupe). No global or cross-load intern. E `tagbody`
  stays a separate knife. G.17 stays missing. Not G.17.
- Goal 20: withdraw per-load string-arena / displaced ASCII
  views (item 10 A). Friend-MachineD n=5: load cadr
  **1763→3667 µs** (worse). Product restored. Fill kernel
  untouched. Ceiling not lowered. Not G.17.
- Goal 20: withdraw content exact-length / `svref` fill
  (item 10 D). Friend-MachineD n=5: load cadr **1763→1838 µs**
  (worse). Product restored. Not bag reuse. Ceiling not
  lowered. Not G.17.
- Goal 20: put-message-field first-byte dispatch (proposal 3).
  Friend-MachineD n=5 load **1821→1763 µs**. Not length-case.
  Not bag reuse. Ceiling not lowered. Not G.17.
- Goal 20: put-entry-field unique 4-byte prefix dispatch
  (gperf-style; fromId/fromHook share `from`). Friend-MachineD
  n=5 load **1829→1821 µs**. Not length-case. Not knife 1.
  Ceiling not lowered. Not G.17.
- Goal 20: content compact-prefix fast path (type-first
  `text` / `thinking` / `toolCall`) fills typed content without
  `session-json-block`; miss rewinds to the generic walker.
  Friend-MachineD n=5 load cadr **1879→1829 µs**. Not bag
  reuse. Not knife 1. Ceiling not lowered. Not G.17.
- Goal 20: book missing Working… indicator while agent busy
  (`docs/bugs/working-indicator-missing.md`). Not G.17.
  Part P still `[open]`.
- Goal 20: OpenCode Go / terminal quota HTTP 429 is not
  retryable (`GoUsageLimitError` and the pi
  `isTerminalRateLimitError` set). Display `429: <body>`.
  Transient 429 still retries. Not G.17. Part P still `[open]`.
- Goal 20: book OpenCode Go usage-limit 429 parity —
  cadr retries terminal GoUsageLimitError (slow Working…);
  pi fails fast with `429: {…}`. Fix signal-api-error
  (`docs/bugs/opencode-go-usage-limit-429-retry.md`). Not G.17.
  Part P still `[open]`.
- Goal 20: book user-facing bash tool failure
  (`FORMAT: No more arguments` + bash `(` quoting on
  `gethash equal 6-char`). Classify model misuse vs product
  path (`docs/bugs/bash-format-shell-quoting.md`). Not G.17.
  Part P still `[open]`.
- Goal 20: withdraw quote-scan high-byte + check-less ASCII
  copier (`108d9184a`). Friend-MachineD n=5: load cadr
  **1879→2045 µs** (worse; samples 1978–2222). Product
  restored to `aa2d4a89a` walker. Fill kernel was never
  rewritten. Not intern. Not FFI. Ceiling not lowered.
  Not G.17. Part P still `[open]`.
- Goal 20: COPY-UNESCAPED ban = fill-kernel only; try knife 1
  (quote-scan high-byte + check-less ASCII copier) then knife 2
  (content shape fast-path). Proposals 3/4/5 not next without
  residual / ruling (`docs/adjudications.md`; `goal20-draft.md`
  十B item 11). Not G.17. Part P still `[open]`.
- Goal 20: load knife priority after bag-reuse falsifications
  (DeepSeek review) — prefer string-arena (A) or exact content
  arrays (D); default-reject key-tag `case` redo of length-case
  unless Friend-MachineD proves a distinct encoding; reject
  三连-shaped schema knives; lazy octet-span needs adjudication
  (`docs/adjudications.md`; `goal20-draft.md` 十B item 10).
  Not G.17. Part P still `[open]`.
- Goal 20: withdraw session-json-block scratch reuse
  (`767b4c452`). Friend-MachineD n=5: load cadr **1879→2083 µs**
  (worse). Product restored. Honest split note kept. Not intern.
  Not FFI. Ceiling not lowered. Not G.17. Part P still `[open]`.
- Goal 20: reuse one `session-json-block` scratch per walker
  (lexer token reuse). `finish-block` still copies to typed
  content. Split note recaptured with shipped-label timers
  (not wall fractions). Not parse-message 三连. Not intern.
  Not FFI. Ceiling not lowered. Not G.17. Part P still `[open]`.
- Goal 20: mature algorithms/DS are fair design sources;
  keep Lisp-encoding load knives (`docs/adjudications.md`).
  Local `goal20-draft.md` 十B item 9. Not G.17.
  Part P still `[open]`.
- Goal 20: user rules Lisp 屠龙刀 after load leftover booking —
  invent Lisp DS/algorithms if surface V8-shape knives lost;
  leftover md is bookkeeping not a park; empty banned-class
  ⚑ rejected (`docs/adjudications.md`). Not G.17.
  Part P still `[open]`.
- Goal 20: book session_load leftover after parse-message 三连 —
  `docs/benchmarks/goal20-session-load-leftover.md`. Friend-MachineD
  n=5 ISO-kept load **1879 / 1634 µs (1.15×)**. Three V8-shape knives
  withdrew (2015 / 1917 / 1974 µs). Not G.17. Part P still `[open]`.
- Goal 20: withdraw ParseString delayed materialization
  (`3ad720098`). Friend-MachineD n=5: load cadr **1857→1974 µs**
  (worse). Product restored to ISO-kept walker. Shape note kept.
  Not intern. Not FFI. Ceiling not lowered. Not G.17.
  Part P still `[open]`.
- Goal 20: walker ParseString delayed materialization — scan
  records start/length; intern / COPY-UNESCAPED at object close
  (`MakeString`). Contrast
  `docs/benchmarks/goal20-v8-parse-message-shape.md`. Not bag
  reuse. Not stack-local typed fill. Not intern grow. Not FFI.
  Ceiling not lowered. Not G.17. Part P still `[open]`.
- Goal 20: withdraw parse-message stack locals (`8530c25a1`).
  Friend-MachineD n=5: load cadr **1857→1917 µs** (worse).
  Product restored to ISO-kept walker. Shape note kept.
  Not intern. Not FFI. Ceiling not lowered. Not G.17.
  Part P still `[open]`.
- Goal 20: parse-message fills typed messages from stack locals
  (V8 SmallVector then BuildJsonObject; no heap
  `session-json-message`). Contrast
  `docs/benchmarks/goal20-v8-parse-message-shape.md`. Not bag
  reuse. Not intern. Not FFI. Ceiling not lowered. Not G.17.
  Part P still `[open]`.
- Goal 20: withdraw parse-message scratch bag (`cc29bec17`,
  `f98d0b410`). Friend-MachineD n=5: load cadr **1857→2015 µs**
  (worse). Split-bucket note kept. Not intern. Not FFI.
  Ceiling not lowered. Not G.17. Part P still `[open]`.
- Goal 20: adjudicate study-shape vs port-V8-VM —
  `docs/adjudications.md`; tighten Part P / Class C Method
  (name stickers ≠ essence; no required HiddenClass/Zone;
  knife needs green tests + Friend-MachineD cadr µs). Local
  `goal20-draft.md` 十B synced (gitignored). Not G.17.
  Part P still `[open]`.
- Goal 20: parse-message reuses one scratch
  `session-json-message` then `message-from-json` (V8
  SmallVector then BuildJsonObject). `message-from-json`
  is identity on cadr-ai messages (journal_append /
  finalize re-entry). Split-bucket note
  `docs/benchmarks/goal20-parse-session-record-split.md`.
  Not labels macrolet. Not intern. Not FFI. Ceiling not
  lowered. Not G.17. Part P still `[open]`.
- Goal 20: land callee / 屠龙 rulings in-repo —
  `docs/adjudications.md` (beat pi; study callee; bucket-split;
  empty ⚑ ≠ exhausted), Class C in
  `docs/acceptance/goal-v20-ds-audit.md`, Part P pointers in
  `docs/acceptance/goal-v20-part-p.md`. Local `goal20-draft.md`
  十B「Callee / 屠龙」updated (gitignored `/goal*.md`). Not G.17.
  Part P still `[open]`.
- Goal 20: withdraw ISO DIGITS unroll (`ebbea846f`).
  Friend-MachineD n=5: load cadr **1857→1928 µs** (worse).
  Reverted `7a3f07520`. V8 ParseNumber vs DIGITS flet; unroll
  lost. Not SCAN-KEY macrolet. Not intern. Not FFI. Ceiling
  not lowered. Not G.17. Part P still `[open]`.
- Goal 20: walker timestamp `ParseString` — fixed-width ISO
  then one quote (V8 sequential scan, not a per-byte walk).
  sprof load @ `7517049cb`: PARSE-TIMESTAMP-VALUE 3.3% self.
  Friend-MachineD n=5: load cadr **1882→1857 µs** (1.17×→**1.27×**
  pi jitter; cadr µs down). Not labels macrolet. Not empty
  SWAR. Not intern. Not FFI. Ceiling not lowered. Not G.17.
  Part P still `[open]`.
- Goal 20: Friend-MachineD n=5 remesure @ `ab251cd30` (no src).
  Truncate head/tail **0.69× / 0.84×** (361.4 / 526.6 µs, 466.3 /
  554.1 µs). load **1.17×** / journal **1.16×**. Ceiling not
  lowered. Not G.17. Part P still `[open]`. Not P.13 complete.
- Goal 20: withdraw closed-set session enum intern
  (`4de854bdd`). Friend-MachineD n=5: load cadr **1958→1976 µs**
  (no win), journal **1563→1668 µs**. Reverted `8018b6f53`.
  Not a growing intern table. Not FFI. Ceiling not lowered.
  Not G.17. Part P still `[open]`.
- Goal 20: withdraw closed-schema key dispatch (`789bec858`).
  Friend-MachineD n=5: load cadr **1958→1986 µs** (no win),
  journal **1563→1580 µs**. Reverted `157300eae`. Not labels
  macrolet. Not intern. Not FFI. Ceiling not lowered. Not
  G.17. Part P still `[open]`.
- Goal 20: withdraw walker `scan-key` macrolet (`f87bea405`).
  Friend-MachineD n=5: load cadr **1958→2260 µs**, journal
  **1563→1904 µs**. Reverted `64e564968`. sprof leftover
  SCAN-KEY 8.7% self vs V8 in-place property-name scan; the
  inline lost. Not empty SWAR. Not intern. Not FFI. Ceiling
  not lowered. Not G.17. Part P still `[open]`.
- Goal 20: inline walker `skip-space` / `expect-code` as
  macrolet (V8 SkipWhiteSpace / Expect in the descent). sprof
  load @ `9b1678b20`: SKIP-SPACE 8.2% self, EXPECT-CODE 3.5%.
  Friend-MachineD n=5: load cadr **2069→1958 µs** (1.28×→**1.16×**),
  journal **1638→1563 µs** (1.05×→**1.04×**). Not empty SWAR. Not
  intern. Not FFI. Ceiling not lowered. Not G.17. Part P still
  `[open]`.
- Goal 20: inline walker string-scan helpers (`swar-eq-msb`,
  quote/backslash/ctrl masks, `octet-find-quote-or-backslash`)
  into SCAN-KEY / PARSE-STRING-VALUE. Friend-MachineD n=5: load
  cadr **2678→2069 µs** (1.83×→**1.28×**), journal **2418→1638 µs**
  (1.84×→**1.05×**). Not empty SWAR. Not intern. Not FFI. Ceiling
  not lowered. Not G.17. Part P still `[open]`.
- Goal 20: inline 4-byte octet load (`octet-u32-le` compiler-macro
  + walker `%octet-u32-le`) on session JSONL SCAN-KEY / quote /
  LF / space. sprof `session_load` @ `335718c2e`: OCTET-U32-LE
  12.2% self. Friend-MachineD n=5: load cadr **3106→2678 µs**
  (1.98×→**1.83×**), journal **2716→2418 µs** (1.88×→**1.84×**).
  Not empty SWAR. Not intern. Not FFI. Ceiling not lowered.
  Not G.17. Part P still `[open]`.
- Goal 20: Friend-MachineD n=5 remesure @ `da3d7322f` (no src).
  Truncate head/tail **0.71× / 0.87×** (387.3 / 544.0 µs, 533.8 /
  613.3 µs). load **1.98×** / journal **1.88×**. Load/journal Lisp
  object encodings exhausted this drain (walker vs V8). Ceiling
  not lowered. Not G.17. Part P still `[open]`.
- Goal 20: archive V8/`JSON.parse` compare plus Friend-MachineD
  n=5 withdrawals (`a78ee0171` public cons-plist parse-json:
  journal_read 1.62×→2.59×; `28e0eae06` session simple-vector:
  cadr session_load 2878→3110 µs). Public parse-json stays hash.
  `docs/benchmarks/goal20-v8-json-parse-compare.md`. No `src/`
  speedup. Ceiling not lowered. Not G.17. Part P still `[open]`.
- Goal 20: sprof `provider_codex` leftover after stringify skip is
  `PARSE-JSON-SOURCE` / `READ-SSE-STREAM` vs V8 `JSON.parse` (Class
  C). 1.08× leftover. Ceiling 1.5 not lowered. No `src/`. Not G.17.
  Part P still `[open]`.
- Goal 20: Codex SSE prepare skips `stringify-json` when zstd is
  unbound (pi stringifies the request body once). Pairing leftover
  sprof `WRITE-JSON-STRING` 21.8%. Friend-MachineD 1.26×→**1.08×**
  (1327 / 1226 µs). Ceiling 1.5 not lowered. Not G.17. Part P still
  `[open]`.

### Added

- Goal 20 Part H: pair `provider_pi_messages.stream_roundtrip`
  (recorded pi-messages SSE, no socket). Production `stream-chat`
  vs `pi-messages.ts stream`. Same `provider-context.json`. Seam is
  `*http-request-function*` / `options.fetch`. First Friend-MachineD
  freeze 1.25× (1103 / 885 µs), ceiling 1.5. Not G.17. Part P still
  `[open]`.
- Goal 20 Part H: pair `package_manager.resolve` (fixture local
  package path, no npm/TUI/socket). Production
  `configured-package-records` + `package-resource-paths` vs
  `DefaultPackageManager.resolve`. First Friend-MachineD freeze
  0.36× (200 / 551 µs), ceiling 1.5. Not G.17. Part P still `[open]`.
- Goal 20 Part H: pair `provider_codex.stream_roundtrip`
  (recorded Codex Responses SSE + fixture OAuth JWT, no socket).
  Production `stream-chat` vs `openai-codex-responses.ts stream`.
  Same `provider-context.json`. Seam is `*http-request-function*` /
  `options.fetch`. `transport=sse`. First Friend-MachineD freeze
  1.26× (1582 / 1258 µs), ceiling 1.5. Not G.17. Part P still `[open]`.
- Goal 20 Part H: pair `provider_vertex.stream_roundtrip`
  (recorded Vertex SSE + fixture ADC JSON, no socket). Production
  `stream-chat` vs `google-vertex.ts stream`. Same
  `provider-context.json`. Seam is `*http-request-function*` /
  `globalThis.fetch`. First Friend-MachineD freeze 0.49×
  (2641 / 5443 µs), ceiling 1.5. Not G.17. Part P still `[open]`.
- Goal 20 Part H: pair `provider_azure_openai.stream_roundtrip`
  (recorded Azure OpenAI Responses SSE, no socket). Production
  `stream-chat` vs `azure-openai-responses.ts stream`. Same
  `provider-context.json`. Seam is `*http-request-function*` /
  `options.fetch`. First Friend-MachineD freeze 0.33×
  (1369 / 4152 µs), ceiling 1.5. Not G.17. Part P still `[open]`.
- Goal 20 Part H: pair `provider_openai_responses.stream_roundtrip`
  (recorded OpenAI Responses SSE, no socket). Production
  `stream-chat` vs `openai-responses.ts stream`. Same
  `provider-context.json`. Seam is `*http-request-function*` /
  `options.fetch`. First Friend-MachineD freeze 0.37×
  (1460 / 3901 µs), ceiling 1.5. Not G.17. Part P still `[open]`.
- Goal 20 Part H: pair `provider_mistral.stream_roundtrip`
  (recorded Mistral Conversations SSE, no socket). Production
  `stream-chat` vs `mistral-conversations.ts stream`. Same
  `provider-context.json`. Seam is `*http-request-function*` /
  `options.fetch`. First Friend-MachineD freeze 1.89×
  (3401 / 1801 µs), ceiling 3.0. Not G.17. Part P still `[open]`.
- Goal 20 Part H: pair `resource_loader.reload` (fixture skills +
  prompt templates, no TUI, no socket). Production
  `reload-resources` vs `DefaultResourceLoader.reload`. First
  Friend-MachineD freeze 0.29× (568 / 1978 µs), ceiling 1.5.
  Not G.17. Part P still `[open]`.
- Goal 20 Part H: pair `cli_settings.create` (fixture settings JSON,
  no TUI, no socket). Production `make-settings-manager` vs
  `SettingsManager.create`. First Friend-MachineD freeze 0.13×
  (105 / 813 µs), ceiling 1.5. Not G.17. Part P still `[open]`.
- Goal 20 Part H: pair `provider_bedrock.stream_roundtrip`
  (recorded Bedrock event-stream, no socket). Production
  `stream-chat` vs `bedrock-converse-stream.ts stream`. Same
  `provider-context.json`. Seam is `*http-request-function*` /
  stubbed Smithy `NodeHttpHandler`. Auth is a fixture bearer.
  First Friend-MachineD freeze 0.67× (4316 / 6406 µs), ceiling
  1.5. `sanitize-bedrock-document` keeps JSON strings atomic
  (CL strings are character vectors). Identity 127088→127091.
  Not G.17. Part P still `[open]`.
- Goal 20 Part H: pair `provider_google.stream_roundtrip`
  (recorded Gemini SSE, no socket). Production `stream-chat` vs
  `google-generative-ai.ts stream`. Same `provider-context.json`.
  Seam is `*http-request-function*` / stubbed `globalThis.fetch`
  (the adapter rejects `options.fetch`). First Friend-MachineD
  freeze 0.58× (4378 / 7498 µs), ceiling 1.5. Not G.17. Part P
  still `[open]`.
- Goal 20 Part H: pair `provider_anthropic.stream_roundtrip`
  (recorded Anthropic SSE, no socket). Production `stream-chat` vs
  `anthropic-messages.ts stream`. Same `provider-context.json`.
  First Friend-MachineD freeze 0.97× (2508 / 2585 µs), ceiling 1.5.
  Not G.17. Part P still `[open]`.
- Goal 20 Part P: UUIDv7 entropy pool copies Node `getRandomValues`
  (keep `/dev/urandom` stream + 256-byte buffer). sprof of
  `session_compact` @ `66b7403b6` was `uuid-v7` open/read/close
  (`read` 79%). Friend-MachineD 4.54×→0.56× (164→43 µs). Ceiling
  20.0 unchanged. Identity 127060→127088. Not G.17. Part P still
  `[open]`.
- Goal 20 Part P: copy pi in-memory `prepareCompaction` + `compact`
  for `session_compact.compact`. Shipped `compact-from-preparation`;
  persist stays `session-append-compaction` after the core. Timed
  thunk no longer mkdir/JSONL. Friend-MachineD 11.33×→4.54×
  (965→164 µs). Ceiling 20.0 unchanged. Identity 127050→127060.
  Not G.17. Part P still `[open]`.
- Goal 20 Part H: pair `session_compact.compact` (faux summarizer,
  no socket). Production `compact-agent` vs `prepareCompaction` /
  `compact`. Deterministic five-message fixture over the compact
  token budget. First Friend-MachineD freeze 11.33× (965 / 85 µs),
  ceiling 20.0. Loading an already-compacted session stays
  `session_load`. Not G.17. Part P still `[open]`.
- Goal 20 Part H: pair `agent_tool_loop.roundtrip` (faux provider,
  no socket). Production `agent-prompt` vs `Agent.prompt` /
  `runAgentLoop`. Same FiveAM echo fixture. First Friend-MachineD
  freeze 0.77× (329 / 428 µs), ceiling 1.5. Not G.17. Part P
  still `[open]`.
- Goal 20 Part P: sprof of `session_load` / `journal_read` after
  `9a9a96d73`. Leftover is still the octet walker (`OCTET-U32-LE`
  11.3% / 12.9%; `PARSE-SESSION-RECORD-OCTETS` 73.9% / 80.2%
  total). Index `coerce` is not in the samples. No `src/`.
  G.17 still `missing`.
- Goal 20 Part H: Friend-MachineD remesure of `9a9a96d73`
  `session_load` 2.09×→1.85× (3111 / 1686 µs). `journal_read`
  1.97×→1.65× (unchanged product path; jitter). Ceilings 9.0 /
  8.0 unchanged. No extra `src/`. G.17 still `missing`.
- Goal 20 Part P: `load-session` indexes a simple-vector of
  parsed records (pi `FileEntry[]` + `_buildIndex`). Runtime
  `%entries` stays a cons list. Not a third JSON parser. Not
  intern. Not `:size`. Identity 127038→127050. FiveAM
  19567→19571. G.17 still `missing`.
- Goal 20 Part P: P.13 inventory refresh. Truncate head/tail
  `e2a4dfad6` **0.70× / 0.82×**. Load/journal still 2.09× / 1.97×.
  Not P.13 complete. G.17 still `missing`. Part P still `[open]`.
- Goal 20 Part H: Friend-MachineD remesure of `e2a4dfad6`
  `session_load` 2.09× (2957 / 1417 µs), `journal_read` 1.97×
  (2718 / 1382 µs). Ceilings 9.0 / 8.0 unchanged. sprof leftover
  is the octet walker (Class C). Product knife blocked. No `src/`.
  G.17 still `missing`.
- Goal 20 Part H: Friend-MachineD remesure of `d939b3bd4`
  `truncate_head` 1.33×→0.70× (708→377 µs). Faster than pi.
  `truncate_tail` 0.85×→0.82× (held). Ceiling 20.0 / 18.0
  unchanged. No `src/`. G.17 still `missing`.
- Goal 20 Part P: `truncate-harness-head` ASCII-run fill (same
  encoding as tail: ASCII 1×run, newline closes, non-ASCII
  `utf8-char-length`). this-host ~240 µs. Identity 126997→127038.
  FiveAM 19540→19567. Not intern. Not FFI. Not empty SWAR.
  G.17 still `missing`.
- Goal 20 Part H: Friend-MachineD remesure of `9b70e7a09`
  `truncate_tail` 1.44×→0.85× (758→461 µs). Faster than pi.
  Ceiling 18.0 unchanged. No `src/`. G.17 still `missing`.
- Goal 20 Part P: `truncate-harness-tail` ASCII-run fill. ASCII
  runs add 1×run; newline still closes a line; non-ASCII still
  `utf8-char-length`. Same start/width table. this-host ~558→319 µs.
  Identity 126974→126997. FiveAM 19513→19540. sprof:
  `docs/benchmarks/goal20-part-p-truncate-tail-sprof-ascii-run.md`.
  Not intern. Not FFI. Not empty SWAR. G.17 still `missing`.
- Goal 20 Part H: Friend-MachineD remesure of `07facd8fd`
  `truncate_tail` 1.45×→1.44× (760→758 µs). Same band as
  the revert. Ceiling 18.0 unchanged. No `src/`. G.17 still
  `missing`.
- Goal 20 Part P: `truncate-harness-tail` fills starts/widths in
  one pass (hint 64..8192, grow by doubling, exact-size copy).
  Not a prior newline-count pass. this-host ~631 µs. Identity
  126959→126974. Not intern. Not FFI. G.17 still `missing`.
- Goal 20 Part H: Friend-MachineD remesure of `c451b14e7`
  (revert of exact-size tail). `truncate_tail` 1.76×→1.45×
  (948→760 µs). Ceiling 18.0 unchanged. No `src/`. G.17
  still `missing`.
- Goal 20 Part H: Friend-MachineD remesure of `7ab5d7d3c`
  `text_truncation.truncate_tail` 1.42×→1.76× (cadr 948 µs /
  pi 540 µs). Extra newline count pass is slower on the
  pairing fixture. Reverted. Ceiling 18.0 unchanged. G.17
  still `missing`.
- Goal 20 Part H: Friend-MachineD remesure of `bc3b2b755`
  `tool_read.text_file` 0.41×→0.45× (1757→1634 µs; pi also
  faster). Ceiling 8.0 unchanged. No `src/`. G.17 still
  `missing`.
- Goal 20 Part P: `split-octet-line-starts` fills in one pass
  (truncate hint 64..8192, grow by doubling, exact-size copy).
  Kills the second `0x0A` walk named by sprof at `ad1e91711`.
  Identity 126947→126959. FiveAM 19508→19513. sprof:
  `docs/benchmarks/goal20-part-p-tool-read-sprof-one-pass-octet-starts.md`.
  Not intern. Not FFI. Not empty SWAR.
  G.17 still `missing`.
- Goal 20 Part H: Friend-MachineD remesure of `ad1e91711`
  `tool_read.text_file` 1.35×→0.41× (5813→1757 µs).
  `tool_grep.context_file` 0.92×→0.98×. Ceiling 8.0
  unchanged. No `src/`. G.17 still `missing`.
- Goal 20 Part P: `read-tool-file` builds the line table on
  ub8 `0x0A` and `utf8-string`s only the offset/limit window
  plus one overflowing line for `truncate-head`. this-host
  ~4695→800 µs. Identity 126866→126947. FiveAM 19464→19508.
  sprof:
  `docs/benchmarks/goal20-part-p-tool-read-sprof-utf8-window.md`.
  Not FFI. Not intern. G.17 still `missing`.
- Goal 20 Part H: Friend-MachineD remesure of `1aedb4e45`
  `tool_grep.context_file` 1.38×→0.92× (23713→15243 µs).
  `tool_read.text_file` 1.32×→1.35× (5460→5813 µs).
  Ceilings 3.0 and 8.0 unchanged. No `src/`. G.17 still
  `missing`.
- Goal 20 Part P: grep ingest is octet `read-sequence` then
  `utf8-string`, then the existing line table. Not
  `uiop:read-file-string`. this-host ~21895→15487 µs.
  Identity 126856→126866. FiveAM 19456→19464. Not intern.
  Not FFI. G.17 still
  `missing`.
- Goal 20 Part H: Friend-MachineD remesure of `0e785406e`
  `tool_read.text_file` 2.42×→1.32× (11131→5460 µs).
  `tool_grep.context_file` 1.62×→1.38× (30986→23713 µs).
  Ceilings 8.0 and 3.0 unchanged. No `src/`. G.17 still
  `missing`.
- Goal 20 Part P: `utf8-string` copies ASCII runs into a
  pre-sized `simple-base-string` via `copy-unescaped-json-octets`
  (ub32 schar). Mixed buffers pre-size a character string and
  decode only non-ASCII scalars. this-host ~5512→3103 µs.
  Identity 126691→126856. Not FFI. Not intern. sprof:
  `docs/benchmarks/goal20-part-p-tool-read-sprof-utf8-ascii-run.md`.
  G.17 still `missing`.
- Goal 20 Part P: grep `text-lines` / `ripgrep-file-lines`
  use the shared fixnum line-start table (drop trailing
  empty, trim CR). Not `uiop:split-string` on the hot path.
  this-host pairing fixture ~20939 µs. Identity
  126666→126691. Not intern. Not FFI. G.17 still
  `missing`.
- Goal 20 Part P: this-host sb-sprof of `tool_read.text_file`
  on `ab4a52ea4`. Leftover is `octets-to-string`
  (`UTF8->STRING-AREF` 58.3% total). Line-table
  `vector-push-extend` is gone. Capture:
  `docs/benchmarks/goal20-part-p-tool-read-sprof-ab4a52ea4.md`.
  G.17 still `missing`.
- Goal 20 Part H: Friend-MachineD remesure of `ab4a52ea4`
  `tool_read.text_file` 2.39×→2.42× (10299→11131 µs). Same
  ratio band; pi also slower. Ceiling 8.0 unchanged. No
  `src/`. G.17 still `missing`.
- Goal 20 Part P: `split-line-starts` exact-sizes the fixnum
  vector (count newlines, then fill). Kills
  `vector-push-extend` named by sprof at `39b3707bf`. Same
  JS split encoding. this-host ~6505→5512 µs. Identity
  126659→126666. Not intern. Not FFI. G.17 still
  `missing`.
- Goal 20 Part P: this-host sb-sprof of `tool_read.text_file`
  on `39b3707bf`. Leftover is `octets-to-string`
  (`UTF8->STRING-AREF` 17.3%) plus
  `PREPARE-VECTOR-PUSH-EXTEND` on `split-line-starts` (12.7%).
  Capture: `docs/benchmarks/goal20-part-p-tool-read-sprof-39b3707bf.md`.
  G.17 still `missing`.
- Goal 20 Part H: Friend-MachineD remesure of `39b3707bf`
  `tool_read.text_file` 2.88×→2.39× (12786→10299 µs).
  Ceiling 8.0 unchanged. No `src/`. G.17 still `missing`.
- Goal 20 Part P: `read-tool-file` reads `(unsigned-byte 8)`
  then `utf8-string` once, matching pi `readFile` +
  `toString("utf-8")`. this-host ~9763→6505 µs. Identity
  126643→126659. Not mmap. Not FFI. G.17 still `missing`.
- Goal 20 Part H: `tool_grep.context_file` pair. Same 4000-line
  fixture; timed work is production `grep-lines` vs pi
  `createGrepToolDefinition.execute` with `context=2`. First
  Friend-MachineD freeze 1.77× (28357 / 16053 µs), ceiling
  3.0. No product optimize. G.17 still `missing`.
- Goal 20 Part P: this-host sb-sprof of `tool_read.text_file`
  on `c2828e831`. Leftover is SBCL `INPUT-CHAR/UTF-8/LF` on
  `read-file-string` (47.3% self), not the line table (2.0%).
  Capture: `docs/benchmarks/goal20-part-p-tool-read-sprof-c2828e831.md`.
  G.17 still `missing`.
- Goal 20 Part H: Friend-MachineD remesure of `c2828e831`
  `tool_read.text_file` 5.32×→2.88× (21747→12786 µs).
  Ceiling 8.0 unchanged. No `src/`. G.17 still `missing`.
- Goal 20 Part P: `read-tool-file` fills a fixnum line-start
  table then one `subseq` for the selected range. Matches JS
  `split("\n")` / `slice` / `join`. Not `uiop:split-string`
  on the hot path. this-host ~21747→9763 µs. Identity
  126591→126643. Not intern. Not FFI. G.17 still `missing`.
- Goal 20 Part H: `tool_read.text_file` pair. Same 4000-line
  fixture ingested as a text file; timed work is production
  `read-tool-file` vs pi `createReadToolDefinition.execute`.
  First Friend-MachineD freeze 5.32× (21747 / 4087 µs),
  ceiling 8.0. No product optimize. G.17 still `missing`.
- Goal 20 Part P: `truncate-harness-tail` pre-sizes the
  fixnum line table (hint cap 8192) so 4000 lines do not
  realloc from 64. Same algorithm. this-host ~749→635 µs.
  Identity 126589→126591. Not intern. Not FFI. G.17 still
  `missing`.
- Goal 20 Part P: CLI `utf8-length` delegates to
  `harness-utf8-length`. Does not encode the whole string
  to count. this-host pairing fixture ~1111→477 µs.
  Identity 126583→126589. Not intern. Not FFI. G.17 still
  `missing`.
- Goal 20 Part P: `truncate-harness-tail` builds a fixnum
  line-start/width table in one walk, then indexes from the
  end like pi `truncateTail`. Not `uiop:split-string`. Not
  FFI Buffer. this-host ~819→749 µs. Identity 126546→126583.
  FiveAM 19359→19361. Not intern. G.17 still `missing`.
- Goal 20 Part P: `cli-token-tail=` compares with `schar`
  on `simple-string`. sprof named it 14.2% self on
  `argv_parse`. this-host 3.0→1.96 µs. Identity
  126542→126546. Not intern. Not FFI. G.17 still
  `missing`.
- Goal 20 Part P: `truncate-harness-head` counts remainder
  totals after the selected prefix. Friend-MachineD head
  was 4.27× (2277 µs). this-host 2040→549 µs. Identity
  126512→126542. FiveAM 19357→19359. Not intern. Not FFI.
  G.17 still `missing`.
- Goal 20 Part P: `truncate-harness-tail` counts lines and
  UTF-8 bytes in one walk. Friend-MachineD remesure still
  4.57× / 3.09× (head/tail) before this knife. Not intern.
  Not FFI. G.17 still `missing`.
- Goal 20 Part P: `sqlite-row-to-entry` decodes payload
  TEXT with `parse-session-record-octets` instead of
  `parse-json`. Identity 126497→126502. Not intern. Not
  FFI. G.17 still `missing`.
- Goal 20 Part P: this-host sb-sprof of
  `sqlite_session.open_walk` on `e3eb0d956`. Leftover is
  `PARSE-JSON-SOURCE` on SQLite payload TEXT (49.8% total)
  plus CFFI/Babel string conversion. Capture:
  `docs/benchmarks/goal20-part-p-sqlite-sprof.md`. G.17 still
  `missing`.
- Goal 20 Part H: `sqlite_session.open_walk` pair. Same
  `session.jsonl` ingested into cadr SQLite and pi
  `sqlite-node`; timed work is open + read-all + leaf walk.
  First Friend-MachineD non-quick freeze. No product optimize
  in this commit. G.17 still `missing`.
- Goal 20 Part P.13: after a pair lands, keep refining.
  Beating pi is not a stop. Floor = not slower than pi;
  ceiling = CL leftover. Empty SWAR is not refining.
  Ruling: `docs/adjudications.md` 2026-08-19 19:21. G.17
  still `missing`.

- Goal 20 Part P.13 inventory: every `src/**/*.lisp` is
  `paired`, `unpairable`, `covered-as-callee`, or
  `needs-pair`. 219 files still need an H pair (SQLite,
  tool loop, compact, remaining providers, settings /
  package / skill / prompt, and the rest). H JSON schema
  unchanged. No new pairs. No `src/`. G.17 still
  `missing`.
- Goal 20 Part P.13: every pairable path must be measured,
  then optimized. Path unit, not per-file benches.
  `pairable-uncovered` is not a terminal state. Ruling:
  `docs/adjudications.md` 2026-08-19 P.13. G.17 still
  `missing`.

- Goal 20 Part P: this-host sb-sprof of `session_load` and
  `journal_read` on `5cc895b84`. `ALLOC-UNSIGNED-BIGNUM`
  gone. Leftover is walker / `OCTET-U32-LE` / runtime /
  foreign `read`. No unused legal named structure. Capture:
  `docs/benchmarks/goal20-part-p-load-read-sprof-5cc895b84.md`.
  No `src/`. G.17 still `missing`.

- Goal 20 Part P: this-host sb-sprof of `session_load` and
  `journal_read` on `2a3aa47ba`. Leftover is walker / SWAR
  helpers / runtime / foreign `read`. `COPY-UNESCAPED`
  3.1%→2.4% self. No unused legal named structure. Capture:
  `docs/benchmarks/goal20-part-p-load-read-sprof-2a3aa47ba.md`.
  No `src/`. G.17 still `missing`.

- Goal 20 Part P: this-host sb-sprof of `context_walk`,
  `argv_parse`, and `help_render`. Walk leftover is EQUAL
  hash in `session-path-entries`. argv is `assoc`/`string=`.
  help is `format` (not guessed). Capture:
  `docs/benchmarks/goal20-part-p-walk-argv-help-sprof.md`.
  G.17 still `missing`.

- Goal 20 Part P: this-host sb-sprof of `session_load` and
  `journal_read` on `67a2d43fb`. Leftover is the session
  JSONL octet walker / runtime / foreign `read`. No EQUAL
  hash, no `parse-json-octets` re-entry. Capture:
  `docs/benchmarks/goal20-part-p-load-read-sprof.md`. No
  `src/`. G.17 still `missing`.

### Changed

- Goal 20 Part P: sprof `provider_mistral` @ `6b203dcdc`.
  Leftover after SSE `utf8-string` is `PARSE-JSON-SOURCE`
  56.5% vs V8 `JSON.parse` (Class C). Capture:
  `docs/benchmarks/goal20-part-p-mistral-sprof-6b203dcdc.md`.
  No `src/`. Not FFI. G.17 still `missing`. Part P still
  `[open]`.

- Goal 20 Part P: Friend-MachineD remesure of `2f9036b4a`
  (n=5, enforced). `agent_tool_loop.roundtrip`
  1.75×→**0.16×** (45 / 278 µs). Ceiling 1.5 not raised.
  No extra `src/`. G.17 still `missing`. Part P still `[open]`.

- Goal 20 Part P: one parallel tool runs inline (no
  `pthread_create`). sprof leftover of `agent_tool_loop` was
  `pthread_sigmask` 53%. pi `executeToolCallsParallel` is
  `Promise.all` on the event loop. Identity 127067→127076.
  Not intern. Not FFI. G.17 still `missing`. Part P still
  `[open]`.

- Goal 20 Part P: Friend-MachineD remesure of `a54c022f0`
  (n=5, enforced). `provider_mistral.stream_roundtrip`
  1.89×→**1.19×** (2149 / 1804 µs). Ceiling 3.0 not lowered.
  No extra `src/`. G.17 still `missing`. Part P still `[open]`.

- Goal 20 Part P: SSE binary payload decode uses `utf8-string`
  ASCII-run (same decoder as tool_read). sprof at `3374ac197`
  named `UTF8->STRING-AREF` 25.6% of
  `provider_mistral.stream_roundtrip`. Capture:
  `docs/benchmarks/goal20-part-p-mistral-sprof-3374ac197.md`.
  Identity 127091→127067. Not intern. Not FFI. G.17 still
  `missing`. Part P still `[open]`.

- Goal 20 Part P: Friend-MachineD remesure of `208838a39`
  (n=5, enforced). truncate_head 1.17× (667 / 570 µs).
  truncate_tail 1.47× (856 / 581 µs). Same ratios as
  `c074a85ec`. Ceiling unchanged. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: this-host sb-sprof of truncate line table
  at `c074a85ec`. Tail leftover encoding is
  `PREPARE-VECTOR-PUSH-EXTEND` 7.9% total. Capture:
  `docs/benchmarks/goal20-part-p-truncate-sprof-c074a85ec.md`.
  No `src/`. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of `c074a85ec`
  (n=5, enforced). truncate_head 0.97×→1.17× (cadr
  618→592 µs). truncate_tail 1.30×→1.47× (819→790 µs).
  Absolute cadr improved; ratio up is pi faster. Ceiling
  unchanged. No `src/`. G.17 still `missing`.

- Goal 20: standing policy section 1 item 6 — speed
  design copies pi's algorithm and data structure, encoded
  in Lisp. Product alignment stays observable behavior.
  sprof of a worse scan is not a design source. Audit:
  `docs/acceptance/goal-v20-ds-audit.md`. G.17 still
  `missing`.

- Goal 20 Part P.13: read pi first. Copy its passes and
  data structure in Lisp; sprof of a worse scan is not the
  design source. truncate_tail leftover is a line-start
  vector, not another character-loop direction. Ruling:
  `docs/adjudications.md` 2026-08-19 22:18 / 22:27. G.17
  still `missing`.

- Goal 20 Part P: revert one-reverse-walk `truncate-harness-tail`.
  Friend-MachineD n=5: tail 1.30×→1.59× (cadr 819→870 µs).
  Full reverse scan lost to forward totals plus short reverse
  select. Identity back to 126546. G.17 still `missing`.

- Goal 20 Part P: this-host sb-sprof of `truncate_tail` at
  `19ca40947`. Leftover is `HARNESS-LINE-AND-UTF8-LENGTH`
  67.5% then reverse `HARNESS-UTF8-LENGTH-RANGE` 13.2%.
  Capture: `docs/benchmarks/goal20-part-p-truncate-tail-sprof-19ca40947.md`.
  No `src/`. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of `19ca40947`
  (n=5, enforced; booked at `c688da095`). truncate_head
  4.27×→0.97× (cadr 2277→618 µs). truncate_tail
  1.38×→1.30× (763→819 µs). Ceiling unchanged. No `src/`
  in the remesure booking. G.17 still `missing`.

- Goal 20 Part P: this-host sb-sprof of load/read at
  `19ca40947`. Leftover is the octet walker
  (`OCTET-U32-LE` 11%, quote/LF/space SWAR, `SCAN-KEY`)
  plus pthread / foreign `read`. No unused legal named
  structure. No `src/`. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of `17df52451`
  (n=5, enforced). truncate_head 4.57×→4.27× (cadr
  2566→2277 µs). truncate_tail 3.09×→1.38× (1783→763 µs).
  Ceiling unchanged. No `src/` in the remesure booking.
  G.17 still `missing`.

- Goal 20 Part P: `SCAN-KEY` / `PARSE-STRING-VALUE` /
  `skip-string` find `"` and `\\` with two ub32 haszero.
  Backslash falls back to a byte walk of that escape.
  Not intern. Not FFI. Session JSONL bytes unchanged.
  Identity 126439→126497. FiveAM 19338→19346. this-host
  wall did not drop hundreds of µs. G.17 still `missing`.

- Goal 20 Part P: `SWAR-EQ-MSB` is two ub32 haszero
  operations. Result stays a fixnum. Not intern. Not FFI.
  Session JSONL bytes unchanged. Identity 126415→126439.
  FiveAM 19331→19338. G.17 still `missing`.

- Goal 20 Part P: `copy-unescaped-json-octets` writes
  ASCII windows as ub32 `schar` stores. High bytes stay
  UTF-8. Not intern. Not FFI. Session JSONL bytes
  unchanged. Identity 126391→126415. FiveAM
  19320→19331. G.17 still `missing`.

- Goal 20 Part P: `octet-window-equals` compares short
  ASCII keys as ub32 chunks (constant literals fold).
  Not intern. Not FFI. Session JSONL bytes unchanged.
  Identity 126304→126391. FiveAM 19304→19320. Not
  `sb-simd`. G.17 still `missing`.

- Goal 20 Part P: `SCAN-BUFFER` / `SKIP-SPACE` scan 8
  bytes at a time (SWAR haszero after splat). Not FFI.
  Not `sb-simd`. Session JSONL bytes unchanged. Identity
  126223→126304. FiveAM 19291→19304. Not intern. G.17
  still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of `e908ebad9`
  (n=5, enforced). help_render 5.59×→0.07× (cadr 4.7→0.0 µs).
  context_walk 1.05×→0.03× (113.3→3.2 µs). argv 1.69×→1.54×.
  Ceiling unchanged. No `src/` in the remesure booking.

- Goal 20 Part P: `print-cli-usage` writes literal blocks
  with `write-string`. No per-line `format`. Help bytes
  match the previous non-color output. Identity
  126116→126223. FiveAM 19289→19291. Not intern. Not FFI.
  G.17 still `missing`.

- Goal 20 Part P: `parse-cli-arguments` looks up known CLI
  flags in a closed length/octet table. No per-flag
  `assoc` `string=`. Output/behavior aligned. Help
  unchanged. Identity 125935→126116. FiveAM 19275→19289.
  Not intern. Not FFI. G.17 still `missing`.

- Goal 20 Part P: `session-messages` reuses the derived
  message list until append or branch. Pairing
  `context_walk` is that function. Not intern. Not FFI.
  Identity 125921→125935. FiveAM 19267→19275. G.17 still
  `missing`.

- Goal 20 Part P: Friend-MachineD remesure of `8d7917472`
  (n=5, enforced). list_models_render 1.57×→0.06× (cadr
  2088→97 µs). Ceiling unchanged. No `src/` in the remesure
  booking.

- Goal 20 Part P: `model-registry-available-models` caches
  the configured list on the registry. Invalidate with the
  same models.json / auth.json write-dates as the CLI
  registry cache. Callers get a copy so SORT/FILTER cannot
  mutate the cache. this-host list_models_render 2189 µs /
  1,691,418 B → 199 µs / 45,485 B. Table bytes stay the
  baseline. Not intern. Not FFI. Not session. Identity
  125894→125921. FiveAM 19259→19267. G.17 still
  `missing`.

- Goal 20 Part P: session JSONL first line fills
  `session-file-header` from the octet window. Not EQUAL
  hash. this-host load 2387 µs / 920,544 B → 1586 µs /
  920,512 B; journal_read 1591 µs / 862,611 B → 1586 µs /
  862,774 B. Wall is timer alias; no Friend-MachineD
  remesure of this knife. Not intern. Not FFI. Identity
  125811→125894. FiveAM 19250→19259. G.17 still
  `missing`.

- Goal 20 Part P: Friend-MachineD remesure of `98f27fdd8`
  (n=5, enforced). load 1.19×→1.06× (cadr 2007→1905 µs),
  read 1.09×→1.10× (cadr 1898→1627 µs), append 0.81×→0.89×
  (cadr 1698→1624 µs). Ceiling unchanged. No `src/` in the
  remesure booking.

- Goal 20 Part P: session JSONL `PARSE-STRING-VALUE` decodes
  escaped strings from the octet window. It no longer
  `octets-to-string` the quoted span and re-enters
  `parse-json-source`. this-host load-session 1593 µs /
  993,056 B → 2387 µs / 920,544 B; journal_read 1593 µs /
  928,429 B → 1591 µs / 862,611 B. Wall is the 800 µs timer
  alias; bytes dropped. No Friend-MachineD remesure. Not
  intern. Not FFI. Identity 125692→125811. FiveAM
  19240→19250. G.17 still `missing`.

- Goal 20 Part P: `print-cli-models` writes token counts and
  provider names from model slots. No per-model
  `format-list-models-token-count` / `string-downcase` /
  six-cell list. Table bytes stay the baseline. this-host
  2178 µs / 1,717,788 B → 2197 µs / 1,691,678 B. Wall did
  not move hundreds of µs; no Friend-MachineD remesure.
  Not intern. Not FFI. Identity 125610→125692. FiveAM
  19232→19240. G.17 still `missing`.

- Goal 20 Part P: this-host `list_models_render` of
  `9065ffe30` (pairing fixture pattern `goal20`, broadcast
  sink) 2178 µs / 1,717,788 B. Pairing cadr last booked
  2182 µs. Wall did not move hundreds of µs; no
  Friend-MachineD remesure. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: `print-cli-models` writes the six-column
  table into one string buffer. No per-cell `format nil`
  pad and no per-row `format ~{~A~^  ~}`. Table bytes
  stay the baseline. Not intern. Not FFI. G.17 still
  `missing`.

- Goal 20 Part P: remaining session JSONL generic values
  fill scalars / `(:json-object . pairs)` / vectors in the
  octet walker. They no longer re-enter parse-json-octets
  (EQUAL hash). this-host load-session 2361 µs / 992,000 B
  → 1579 µs / 993,056 B; journal_read 2361 µs / 928,557 B
  → 1578 µs / 928,429 B. Wall is the 800 µs timer step;
  no Friend-MachineD remesure. Not intern. Not FFI.
  Identity 125554→125602. FiveAM 19226→19232. G.17 still
  `missing`.

- Goal 20 Part P: journal_append fills a schema-specific
  octet buffer. ASCII keys/numbers are written in place;
  UTF-8 is only used on string payloads. Journal fd is
  `(unsigned-byte 8)`. Session JSONL bytes match
  stringify of session-entry-to-json. this-host
  create+128 append 1314 µs / 163,621 B → 1311 µs /
  185,013 B. Wall did not move hundreds of µs; no
  Friend-MachineD remesure. Not intern. Not FFI.
  Identity 125336→125554. FiveAM 19223→19226. G.17
  still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `1f4322c51` (non-quick, samples=5, enforced).
  journal_append 1.11×→0.81×. cadr append 2800 µs
  → 1698 µs. RATIO_CEILINGS unchanged. No `src/`.
  G.17 still `missing`.

- Goal 20 Part P: journal_append keeps the session
  file open after first persist. Same
  write-session-entry-jsonl bytes. this-host
  create+128 append 2627 µs / 338,139 B → 1314 µs
  / 163,621 B. Not intern. Not FFI. Identity
  125313→125336. FiveAM 19217→19223. G.17 still
  `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `feb2d5450` (non-quick, samples=5, enforced).
  journal_append 1.93×→1.11×. cadr append 3676 µs
  → 2800 µs. load 1.03×→1.01×, read 1.04×→1.18×.
  RATIO_CEILINGS unchanged. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: journal_append emits message
  entries from typed structs. No EQUAL hash then
  stringify. Key order stays string< so JSONL
  bytes match the old path. this-host create+128
  append 4069 µs / 1,273,115 B → 2627 µs /
  338,139 B. Not intern. Not FFI. Identity
  125064→125313. FiveAM 19214→19217. G.17 still
  `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `2155a80e5` (non-quick, samples=5, enforced).
  session_load 1.85×→1.03×, journal_read 1.58×→1.04×.
  cadr load 3026 µs → 2005 µs, read 2659 µs → 1745 µs.
  RATIO_CEILINGS unchanged. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: session JSONL v3 records use a
  schema-specific octet walker. Known keys fill
  session-entry / message / usage / content slots;
  unknown values are skipped; integers and
  `YYYY-MM-DDTHH:MM:SS.sssZ` timestamps are read
  in place. Public parse-json is unchanged.
  Session file bytes unchanged. this-host
  load-session 3243 µs / 1,215,670 B → 1584 µs /
  991,987 B; journal_read 3243 µs / 1,138,106 B →
  1584 µs / 928,557 B. Not intern. Not :size.
  Not FFI. Identity 124280→125064.
  FiveAM 19200→19214. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `d89b76cc9` (non-quick, samples=5, enforced).
  session_load 1.62×→1.85×, journal_read 1.62×→1.58×.
  cadr load 3033 µs → 3026 µs. Ratio up is pi drift
  (1870→1638 µs). RATIO_CEILINGS unchanged. No `src/`.
  G.17 still `missing`.

- Goal 20 Part P: load-session sizes the by-id EQUAL
  table to the record count so GROW-HASH-TABLE does
  not recopy on the pairing fixture. Session file
  bytes unchanged. load-session 1,260,915 B →
  1,215,670 B. Wall unchanged. Not intern. Not 7b.
  Identity 124277→124280. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `857270409` (non-quick, samples=5, enforced).
  session_load 1.74×→1.62×, journal_read 1.72×→1.62×.
  cadr load 3037 µs → 3033 µs, read 2562 µs → 2647 µs.
  Ratio drop is mostly pi drift. RATIO_CEILINGS
  unchanged. No `src/`. G.17 still `missing`.

- Goal 20 Part P: load-session maps closed record types
  and message vocab to keywords without SUBSTITUTE /
  STRING-UPCASE / INTERN. Already-typed content blocks
  skip the EQUAL-hash rewalk. Session file bytes
  unchanged. Pairing fixture load-session 3173 µs →
  2379 µs / 1,346,195 B → 1,260,915 B. journal_read
  unchanged. Not intern expand. Not 7b. Identity
  124236→124277. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `a7013eb1a` (non-quick, samples=5, enforced).
  session_load 2.02×→1.74×, journal_read 1.46×→1.72×.
  cadr load 3127 µs → 3037 µs, read 2589 µs → 2562 µs.
  RATIO_CEILINGS unchanged. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: session ISO-8601 timestamps of the
  form `YYYY-MM-DDTHH:MM:SS.sssZ` parse digits in place.
  No SUBSEQ/CONCATENATE per entry. Pairing fixture
  load-session 3156 µs → 2383 µs / 1,385,181 B →
  1,346,195 B. journal_read unchanged. Not intern.
  Not 7b. Identity 124174→124236. G.17 still
  `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `c78cef0a9` (non-quick, samples=5, enforced).
  session_load 2.52×→2.02×, journal_read 2.17×→1.46×.
  cadr load 3866 µs → 3127 µs, read 3357 µs → 2589 µs.
  RATIO_CEILINGS unchanged. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: session JSONL parse walks the octet
  window. UTF-8 decode only unescaped string values
  with high bytes. Public parse-json unchanged.
  Pairing fixture journal_read 1,571,942 B → 1,138,106 B
  / 3136 µs → 2367 µs; load-session 1,816,608 B →
  1,385,181 B / 3920 µs → 3156 µs. Not intern. Not 7b.
  Identity 123687→124174. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `bc5d70b08` (non-quick, samples=5, enforced).
  session_load 2.15×→2.52×, journal_read 2.22×→2.17×.
  cadr load 3807 µs → 3866 µs, read 3316 µs → 3357 µs.
  Ratio up on load is pi drift (1773→1532 µs).
  RATIO_CEILINGS unchanged. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: session JSONL is one exact-size octet
  `READ-SEQUENCE` (1MiB cap) then LF split. ASCII lines
  reuse a simple-base-string and parse a START/END window.
  Session file bytes unchanged. Pairing fixture
  journal_read 1,942,410 B → 1,571,942 B; load-session
  2,182,371 B → 1,816,608 B. Wall unchanged. Not intern.
  Not 7b. Identity 123579→123687. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `67cdb71fa` (non-quick, samples=5, enforced).
  session_load 2.48×→2.15×, journal_read 2.41×→2.22×.
  cadr load 4128 µs → 3807 µs, read 3508 µs → 3316 µs.
  RATIO_CEILINGS unchanged. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: tool-call `arguments` decode into
  tagged string-key pairs, not an EQUAL hash.
  `json-get` / stringify treat the tag as an object.
  Session file bytes unchanged. Pairing fixture
  journal_read 1,975,830 B → 1,942,410 B; load-session
  2,214,272 B → 2,182,371 B. Wall unchanged. Not intern.
  Not 7b. Identity 123521→123579. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `b655bbb11` (non-quick, samples=5, enforced).
  session_load 2.37×→2.48×, journal_read 2.00×→2.41×.
  cadr load 4356 µs → 4128 µs, read 3616 µs → 3508 µs.
  Ratio up is pi drift. RATIO_CEILINGS unchanged.
  No `src/`. G.17 still `missing`.

- Goal 20 Part P: v3 `content` array elements walk
  into typed text/thinking/image/tool-call. No EQUAL
  hash per block. `arguments` stay hashes. Session
  file bytes unchanged. Pairing fixture journal_read
  2,134,624 B → 1,975,830 B; load-session
  2,399,405 B → 2,214,272 B / 4756 µs → 3943 µs.
  Not intern. Not 7b. Identity 123365→123521. G.17
  still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `eee817672` (non-quick, samples=5, enforced).
  session_load 3.02×→2.37×, journal_read 2.07×→2.00×.
  cadr load 4781 µs → 4356 µs. RATIO_CEILINGS unchanged.
  No `src/`. G.17 still `missing`.

- Goal 20 Part P: v3 nested `message` / `usage` /
  `cost` walk into `session-json-message` + typed
  usage/cost. No EQUAL hash for those envelopes.
  Content blocks stay hashes until load. Session file
  bytes unchanged. Pairing fixture journal_read
  2,375,210 B → 2,134,624 B; wall unchanged.
  load-session 2,694,035 B → 2,399,405 B. Not intern.
  Not 7b. Identity 123071→123365. G.17 still
  `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `5161d512f` (non-quick, samples=5, enforced).
  session_load 2.96×→3.02×, journal_read 2.14×→2.07×.
  cadr load 5196 µs → 4781 µs. RATIO_CEILINGS unchanged.
  No `src/`. G.17 still `missing`.

- Goal 20 Part P: v3 session JSONL body lines decode
  into `session-entry` (visitor, no top-level EQUAL
  hash). Nested message/usage stay hashes. Header and
  v1/v2 stay hashes for migrate. Session file bytes
  unchanged. Pairing fixture journal_read
  2,463,475 B → 2,375,210 B; wall 3168 µs → 3176 µs.
  parse-json-lines bytes unchanged. Not intern. Not 7b.
  Identity 122900→123071. FiveAM 19150→19164. G.17
  still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `882b49595` (non-quick, samples=5, enforced).
  session_load 2.83×→2.96×, journal_read 2.24×→2.14×.
  RATIO_CEILINGS unchanged. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: PARSE-STRING scan no longer tracks
  ASCII/unicode per character; `base-p` is decided only
  when COPY-UNESCAPED runs. Pairing fixture parse
  2440 µs → 2376 µs; journal_read 4067 µs → 3961 µs;
  bytes unchanged. Not intern. Not 7b. Identity
  122898→122900. FiveAM 19147→19150. G.17 still
  `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `30bd91cf6` (non-quick, samples=5, enforced).
  session_load 2.89×→2.83×, journal_read 2.34×→2.24×.
  RATIO_CEILINGS unchanged. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: object keys that already live in the
  closed JSON value intern set (`thinking`, …) skip
  `COPY-UNESCAPED-JSON-STRING`. No new intern entries.
  Pairing fixture parse 1,235,971 B → 1,229,597 B;
  journal_read 2,477,290 B → 2,463,475 B. Not 7b.
  Identity 122892→122898. FiveAM 19145→19147.
  G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `6cd292ab9` (non-quick, samples=5, enforced).
  session_load 2.66×→2.89×, journal_read 2.22×→2.34×.
  RATIO_CEILINGS unchanged. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: `parse-object` stacks ≤8 pairs, then
  `MAKE-HASH-TABLE :size` count (spill past 8). Pairing
  fixture parse 1,328,669 B → 1,235,971 B; journal_read
  2,559,514 B → 2,477,290 B. Wall unchanged. Not 7b. No
  intern-table expand. Identity 122851→122892. FiveAM
  19070→19145. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `fef648a60` (non-quick, samples=5, enforced).
  session_load 3.32×→2.66×, journal_read 2.23×→2.22×.
  RATIO_CEILINGS unchanged. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: interned JSON object-key lookup
  dispatches on the first character (same closed set,
  no new keys). Pairing fixture journal_read 4634 µs →
  3096 µs; bytes unchanged (2,559,514). Not 7b. Identity
  122842→122851. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `a882dfe96` (non-quick, samples=5, enforced).
  session_load 2.91×→3.32×, journal_read 2.45×→2.23×,
  journal_append 1.75×→1.38×. RATIO_CEILINGS unchanged.
  No `src/`. G.17 still `missing`.

- Goal 20 Part P: `copy-unescaped-json-string` is one
  typed window copy (`REPLACE` into a declared
  `SIMPLE-BASE-STRING`; same-type source uses `SUBSEQ`).
  Pairing fixture parse-json-lines 3200 µs → 2400 µs;
  bytes unchanged (1,328,669). Not 7b. No intern-table
  expand. Identity 122836→122842. FiveAM 19062→19070.
  G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `64c367dfc` (non-quick, samples=5, enforced).
  session_load 3.27×→2.91×, journal_read 3.16×→2.45×,
  journal_append 1.76×→1.75×. RATIO_CEILINGS unchanged.
  No `src/`. G.17 still `missing`.

- Goal 20 Part P: intern repeated ASCII JSON *values*
  (`message`, `assistant`, `user`, `text`, …) so they
  skip `COPY-UNESCAPED-JSON-STRING`. Keys unchanged.
  Pairing fixture parse 1,400,749 B → 1,328,669 B;
  journal_read 2,638,423 B → 2,559,514 B. Not 7b.
  Identity 122802→122836. FiveAM 19057→19062.
  G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `c949668cd` (non-quick, samples=5, enforced).
  session_load 3.80×→3.27×, journal_read 3.38×→3.16×,
  journal_append 1.95×→1.76×, truncate_head 13.86×→3.77×,
  truncate_tail 13.08×→3.00×. RATIO_CEILINGS unchanged.
  No `src/`. G.17 still `missing`.

- Goal 20 Part P: intern session JSONL object keys
  (`parentId`, `timestamp`, `message`, …) so they skip
  `COPY-UNESCAPED-JSON-STRING`. Same-machine pairing
  fixture: parse-json-lines 1,564,496 B → 1,400,749 B;
  journal_read 2,805,066 B → 2,638,423 B / 5596 µs →
  4803 µs. Identity 122785→122802. FiveAM
  19051→19057. Not 7b. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD sprof of
  session_load / journal_read after remesure. Heat is
  PARSE-VALUE / COPY-UNESCAPED / hash / REPLACE (already
  shipped JSON). Not a lever. Not 7b. G.17 still
  `missing`.

- Goal 20 Part P: `truncate-harness-head` / `truncate-harness-tail`
  scan the source string once instead of
  `uiop:split-string` + `format` join. Pairing fixture
  (4000 lines) same-machine 7.276 ms / 2,561,572 B →
  2.319 ms / 197,488 B (head); 7.446 ms / 2,749,241 B →
  1.679 ms / 197,568 B (tail). Observed pairing fields
  unchanged. Identity 122701→122785. FiveAM
  19042→19051. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure after
  P.1–P.12/P0 (non-quick, samples=5, enforced).
  stream_roundtrip 1.29×→0.67×, list_models_render
  3.18×→1.70×, journal_read 3.93×→3.38×, session_load
  4.28×→3.80×, journal_append 2.21×→1.95×. Truncate
  still 13.86×/13.08×. RATIO_CEILINGS unchanged. No
  `src/`. G.17 still `missing`.

- Goal 20 P.8: user 2026-08-18 18:09 deferred
  three-game hand-play; leftover recorded as pass
  until a new defect is opened. Overlay SHAs
  unchanged. G.17 still `missing`.

- Goal 20 P0: tic-tac-toe `move_*` no longer `sleep`s
  0.3s. `:execution-mode :sequential` kept. FiveAM locks
  20-call median < 50ms and no `sleep` in source.
  FiveAM 19037→19042. G.17 still `missing`.

- Goal 20 P.12: alt-screen `last-document` is a
  simple-vector. Per-row selection uses `AREF`. Isolated
  400-row × 80 walk 0.100 ms (`NTH` list) → 0.000 ms
  (`AREF`). Identity 122685→122701. G.17 still `missing`.

- Goal 20 P.12: mermaid `gm-read-shape` writes the label
  to a stream instead of per-char `concatenate`.
  Same-machine 200× 800-char label 1,342,124 B → 24,717 B
  / call; 0.340 ms → 0.040 ms. Identity 122678→122685.
  G.17 still `missing`.

- Goal 20 P.12: `editor-lines` is a simple-vector.
  Per-line lookup is `AREF`, not list `NTH`. Same-machine
  80× 200-line editor-lines+render 183,349 B → 177,188 B
  / call. 0.300 ms (timer step). Identity 122644→122678.
  FiveAM 19036→19037. G.17 still `missing`.

- Goal 20 P0: FiveAM locks a registered move renderer
  that errors does not dump `Player X played at`.

- Goal 20 P0: tic-tac-toe overlay visual board writes
  each row to a stream instead of repeated `concatenate`.
  Same-machine 80× render 54,372 B → 47,819 B / frame;
  0.150 ms (timer step). `sleep 0.3` kept. No spinner.
  FiveAM 19025→19032. G.17 still `missing`.

- Goal 20 P0: custom-message fallback does not dump
  `:content` when a message renderer is registered.
  Move banners start collapsed.

- Goal 20 P0: tic-tac-toe `board-ascii` matches baseline
  `boardToAscii` (`<>`, 9-wide cells). Expanded move banner
  paints the visual board snapshot, not the LLM ascii.
  FiveAM 19008→19025. G.17 still `missing`.

- Goal 20 Part P.1: one-element JSON arrays allocate
  `(vector first)` instead of list + `nreverse` +
  `coerce`. Stream-chat 2,357,254 B → 2,350,697 B.
  FiveAM 18999→19008. Identity 122626→122637. G.17 still
  `missing`.

- Goal 20 Part P.1: JSON integers parse from the source
  window (no SUBSEQ token). Decimals and exponents stay on
  the existing token path. Same-machine session.jsonl
  8727 ns → 6794 ns / line; 1.83 MB → 1.58 MB / pass.
  Stream-chat 2,432,214 B → 2,357,254 B. FiveAM
  18987→18999. Identity 122584→122626. G.17 still
  `missing`.

- Goal 20 Part P.4: file-stream SSE scans newlines in the
  8192 `read-sequence` chunk and decodes complete lines
  from that simple array. Sockets stay on `read-byte`.
  Same-machine stream-chat 5.604 ms → 4.995 ms; SSE-only
  2.199 ms → 1.698 ms. Bytes unchanged (2.43 MB /
  1.23 MB). FiveAM 18977→18987. Identity 122563→122584.
  G.17 still `missing`.

- Goal 20 P0: tic-tac-toe `render-call` takes
  `(arguments theme context)` and paints tool-title + muted
  action. Expanded `render-result` is the banner. Tool
  description matches the baseline no-batched-form contract.
  Host passes `:theme` into rich tool renderers. FiveAM
  18949→18977. Identity 122561→122563.

- Goal 20 G.17 stays `missing` (advisor vetoed `blocked` on
  `7e4ec5201`). P.8 leftover. Not a Goal 20 pass.

- Goal 20 Part G.17 is `blocked`, not `met`: P.8 hand-play
  is unavailable and the advisor has not written G.17 may
  be `met`. Not a Goal 20 pass.

- Goal 20 Part P draft: P.8 is `blocked` (user has not
  played; FiveAM is not hand-play). P.10 this-host
  key→overlay 0.050 ms, spinner=NIL. P.11 14/14. G.17
  still `missing`. Not a Goal 20 pass.

- Goal 20 Part P.8: snake and invaders overlays read the
  live global when bound (`*snake-state*`,
  `*space-invaders-state*`), matching tic-tac-toe. User
  hand-play still leftover. G.17 still `missing`.

- Goal 20 Part P.4: object keys on the OpenAI completions
  chunk set reuse string literals instead of a fresh
  SIMPLE-BASE-STRING each time. Same-machine stream-chat
  4.797 ms / 2,545,901 B → 4.797 ms / 2,432,299 B. G.17
  still `missing`.

- Goal 20 Part P.4: `parse-json-source` allocates the escape
  scratch only when a string has escapes. Same-machine
  stream-chat 5.402 ms / 2,677,288 B → 4.797 ms / 2,545,901 B.
  G.17 still `missing`.

- Goal 20 Part P.4: binary SSE `data`/`event`/`id` lines
  decode only the payload octets (specialized copy, not
  coerce of the adjustable line). Same-machine stream-chat
  5.397 ms / 3,108,022 B → 5.402 ms / 2,677,288 B; SSE-only
  1,659,406 B → 1,229,201 B. G.17 still `missing`.

- Goal 20 Part P.4: `split-sse-field` keeps `data`/`event`/`id`
  literals and takes one payload `subseq`. Same-machine
  stream-chat 6.004 ms / 3,415,114 B → 5.397 ms / 3,108,022 B;
  SSE-only 2.500 ms / 1,970,208 B → 2.199 ms / 1,659,406 B.
  G.17 still `missing`.

- Goal 20 Part P.4: `read-sse-stream` joins a single data line
  without `format`. File-stream binary bodies use specialized
  `read-sequence`; sockets stay on `read-byte` so incremental
  SSE can flush (NATIVE-HTTP). Same-machine stream-chat
  6.398 ms / 3,750,979 B → 6.004 ms / 3,415,114 B; SSE-only
  2.899 ms / 2,327,510 B → 2.500 ms / 1,970,208 B. G.17
  still `missing`.

- Goal 20 Part P draft: this-host stream 5.400 ms / 3.75 MB;
  key-to-overlay 0.100 ms; restart FiveAM 14/14. Advisor
  vetoed G.17 `met` (`c53e13c47`). G.17 is `missing`. P.4
  stream leftover until an `sse.lisp` lever. Not a Goal 20 pass.

- Goal 20 Part P.3: `--list-models` reuses a refreshed registry while
  `models.json` / `auth.json` write-dates stay the same. Same-machine
  `print-cli-models` median 4.30 ms → 2.45 ms (80 calls). Not
  Friend-MachineD pairing. Probe 7d (table format) not repeated.

- Goal 20 Part P.2: journal_append harness mkdir/create is reported
  separately from product `session-append-message`
  (`docs/benchmarks/goal20-part-p-append-tax.md`). Same-machine
  create-session 0.40ms vs 128 appends 3.00ms. Paired metric unchanged.

- Goal 20 Part P.2: `terminating-rational-json-text` writes digits
  once instead of a padded copy plus four concatenate/subseq results.
  Same-machine median 210 ns → 170 ns / call. Own commit.

- Goal 20 Part P.2: `write-json-string` emits unescaped spans with
  one `write-string` instead of per-character `write-char`. Same-machine
  session-object stringify median 6596 ns → 5636 ns (40×515;
  HEAD 6209/6596/6791 vs 5625/5636/6012). Not Friend-MachineD pairing.

- Goal 20 Part P.1: `parse-json-source` coerces to `simple-string`,
  scans with `schar`/`fixnum`, and copies unescaped ASCII windows as
  `simple-base-string`. Same-machine `session.jsonl` parse median
  6489 ns → 5663 ns (300×515 lines; HEAD 6411/6489/6851 vs
  5562/5663/6080). Not Friend-MachineD pairing. Probe 7b not repeated.

- Goal 20 Part K9: `cadr-cli` 54 rewrite files share one
  owner each (flag table, hotkeys rows, OSC splice, gutter
  walk, `:component` input, llama `:manual`, installer
  `GIT:` case, optional-integer JSON null). Selectors not
  merged. FiveAM 18841 → 18880.

- Goal 20 Part K8: `cadr-tui` 29 rewrite files share one
  owner each (char/string walks, rebuild key dispatch,
  layout vectors, compiled scanners). Generated
  `mermaid/width-data.lisp` untouched. FiveAM 18768 → 18841.

- Goal 20 Part K7: `cadr-ai` 28 rewrite files share one
  owner each (device parse, reserved keys, PKCE login,
  stream blocks, runtime error wrap). Generated catalogs
  untouched. FiveAM 18748 → 18768.

- Docs: live Slynk is first on a running cadr, not a last resort after
  guessing (`development-policy` §6.1, `AGENTS.md`). Load-and-probe is
  not a substitute. Do not add restarts on pairable user-visible paths
  to look native. Performance floor is pi; beating pi is not a stop —
  the target is this SBCL image's limit for cost and interactivity
  (Goal 20 Part P). Concurrent agents: disjoint worktrees and an
  ownership table; never two writers in one checkout.

- Goal 20 Part K6 follow-up: `with-present` owns every schema
  present-p bind; `call-signaled-operation` owns abort/classify
  for remove and temps. FiveAM 18738 → 18748.

- Goal 20 Part K6: `cadr-agent` 23 rewrite files share one
  owner each (queue slots, when-present, authoring macros,
  message generic, tail pointer). FiveAM 18725 → 18738.

- CI runs only on `workflow_dispatch`. Push and pull-request
  triggers are gone. Daily path is local `test-cl.sh` / `verify.sh`.
  FiveAM 18722 → 18725.

- Goal 20 Part K5: `cadr-evals` flag prefix, harness merge,
  message tail, reporter push, JSON string accessor, and
  one-argument signed format each have one owner.
  FiveAM 18699 → 18722.

- Goal 20 Part K4: `cadr-server` instance lookup, IPC client
  wrap, instance upsert, and Radius heartbeat share one owner
  each. FiveAM 18691 → 18699.

- Goal 20 Part K3: `cadr-protocol` encoder limits live on
  `cbor-writer`, frame decode uses a cursor, optional schema
  fields share `optional-field-p`. FiveAM 18683 → 18691.

- Goal 20 Part K2: `cadr-storage` stays `no-rewrite` (I verdicts
  undrifted). Theme index recount 197 → 198.

- Default live vehicle is OpenCode Go `mimo-v2.5`. `prepare-opencode-go-credential`
  accepts `auth.json` or `OPENCODE_API_KEY`. A default live item locks a
  nonempty thinking stream. Native DeepSeek FiveAM items still skip
  without `DEEPSEEK_API_KEY`.

- `unix-milliseconds` reads real milliseconds from
  `sb-ext:get-time-of-day`. The old `get-universal-time * 1000` path
  quantized every timestamp and ID to a whole second. Matches
  baseline `Date.now()`. FiveAM 18670 → 18673.

- Statistical liveness default path is documented as the P0-4 silence
  lock only (`liveness-ttt-agent-turn`). The booked table is a local
  `--all` instrument and does not enter CI (board 2026-08-17 A).

- Healed two source-parity mapping positions after the unused-helper
  deletions (`credential-for-print` 192→183,
  `render-truncated-text` 1524→1514). Verdicts and key set unchanged.

- Goal 20: model and session selectors cache filter and haystack
  work across frames. Fuzzy matching downcases each candidate once
  per filter instead of once per token.

- Provider SSE reducers append stream text, thinking, signatures, and
  partial tool JSON with an amortized-linear buffer instead of
  concatenating the whole prefix on every delta. Tool-argument JSON is
  parsed when the block ends, not on each fragment.

- Goal 20 Part O: `parse-json-source` copies unescaped strings from the
  source window and inlines peek/take. Escaped strings still decode
  into a fill-pointer buffer. Enforced paired-path `journal_read`
  5.42× → 3.92× and `session_load` 6.71× → 4.48×.

- Goal 20 Part O: `make-session-entry-id` seeds one random state per
  image instead of calling `make-random-state` on every attempt, which
  dominated `journal_append`.

- Goal 18 Part L: re-anchored the fixed pi baseline to v0.84.1.
  cadr 0.2.0 · aligned with pi v0.84.2 (+0, 914cf1472).  `--alt` is replaced
  by `--tui-mode regular|fullscreen` with the baseline diagnostics; the
  `tuiMode`, `fullscreenScrollbar`, and `markdown.mermaid` settings are
  honored; alt-screen navigation defaults moved to the baseline's
  unshifted keys with new half-page and prompt-jump actions plus
  editor prompt-history actions; `scrollbarThumb` joins the theme
  tokens; baseten and qwen-token-plan-individual providers registered
  with the regenerated 0.84.1 model catalog; child processes learn
  `CADR_CODING_AGENT=true` and `AI_AGENT=cadr`.

- Aligned `--resume` with the baseline (goal 18 adjudication): the flag
  no longer consumes a session id (`--session <id>` remains the exact-id
  path); a following token is a prompt message, matching baseline
  args.ts.  Bare `--resume`/`-r` now opens the baseline pre-TUI session
  picker (cli/session-picker.ts) instead of silently resuming the latest
  session: current-folder scope with Tab to all sessions, lazy all-scope
  load, search/sort/name/path toggles, delete confirmation, and the
  baseline cancel (dim "No session selected", exit 0) and interrupt
  (silent exit 0) paths.

- User keybindings now load from `~/.cadr/agent/keybindings.json`
  (baseline KeybindingsManager.create), coexisting with the settings.json
  `keybindings` key with the file taking precedence; legacy names
  migrate identically, and a malformed file falls back to the settings
  value like the baseline loadRawConfig.

- Bare-environment startup now keeps the baseline no-model sentinel
  instead of an openai default: the footer reads "no-model" with a
  0-token context window, sending fails with the baseline
  NoModelSelected guidance before any append, manual /compact fails with
  the baseline compaction event pair, and non-interactive modes exit 1
  with the red NoModelsAvailable text (baseline main.ts:852-854).

- Aligned the user-level layout with the baseline: agent data (settings,
  auth, models, sessions, themes, prompts, tools, bin, extensions, and
  crash logs) now lives in `~/.cadr/agent/` instead of flat `~/.cadr/`,
  with `CADR_CODING_AGENT_DIR` as the override; `~/.cadr/server/` stays at
  the home root.  Startup automatically migrates a pre-agent-layer flat
  layout by renaming the residents (preserving the `0600` auth mode),
  refuses to choose when both layouts hold data, and skips when the
  override is set.  All path decisions now derive from a single owner in
  `cadr-core`, enforced by the code-organization gate.

### Added

- P0-2 / P0-3 request-render pairing: timer ticks share
  `snake-component-advance` / `space-invaders-advance` (baseline
  snake.ts:90-97, space-invaders.ts:144-151). User-input sites stay
  on `tui-dispatch-event` (root.lisp:207-208). Behavior tests now
  assert the timer requested a frame. Gate-validity in
  `docs/acceptance/goal-v20-p0-2-request-render.md`.
  FiveAM 18668 → 18670.

- Theme index in `docs/test-matrix.md`: every `test/**/*.lisp` and
  `test/**/*.py` file (197) under the nine FiveAM systems plus live
  runner, Python gates, and fixtures. Anchor unchanged.

- Statistical liveness stage (goal 20 12E-1): booked per-scenario
  `N_i` from the 2026-08-15 measurement, `verify.sh` checks the
  silence-injection scenario n=3, and a failure prints the full
  gap list. Outside `render-diff.py gate --tier core`.
  FiveAM anchor 18633 → 18636.

### Removed

- Goal 20 sb-cover third-tier: deleted six unused helpers
  (`auth-credential-value`, `content-text-blocks`, `gm-to-ansi`,
  `markdown-ordered-prefix-end`, `package-source-with-ref`,
  `trailing-lines`). Each had no caller; live paths already own
  the work. Denominator 122640 → 122575.

### Fixed

- Tic-tac-toe overlay follows the live global after reconstruct
  replaces the state object (baseline `updateState`). Thinking
  footer only when it is O's turn.
  FiveAM 18925 → 18932.

- Busy `send-message` with `trigger-turn` steers the running agent
  (baseline `isStreaming` + `triggerTurn`). Tic-tac-toe no longer
  throws DELIVER-AS or leaves a half-played board; tool lines
  render `move_down` / `play` instead of raw JSON.
  FiveAM 18880 → 18925.

- Statistical liveness runs from the git checkout, not the isolated
  tar copy. render-diff capture needs `git -C <repo>`; the isolated
  tree has no `.git` and CI died in 1s with "fatal: not a git
  repository". Thresholds unchanged. FiveAM 18665 → 18668.

- Completions streams read the first nonempty of
  `reasoning_content`, `reasoning`, and `reasoning_text`
  (baseline openai-completions.ts:489-509). Dual emit does not
  double the thinking block. OpenCode Go `reasoning` uses the
  `reasoning_content` signature so history replay matches.
  FiveAM 18657 → 18665.

- Settings-list space matches the baseline: activate only when
  search is off or the query is empty; otherwise space and paste
  keep spaces in the search box (baseline settings-list.ts:187).
  FiveAM 18652 → 18657.

- `write-websocket-frame` now calls `write-websocket-length` for
  the 16-bit and 64-bit extended fields. The helper no longer
  writes the first length byte, so a masked 16-bit frame cannot
  be mistaken for a 64-bit form. Not a write-side pair of the
  64-bit read bug. FiveAM 18640 → 18652.

- Wire `oauth-selector-handle-raw-input` into the overlay
  raw-input dispatch, matching the other selectors. Paste and
  custom keybindings now reach the OAuth selector. FiveAM
  18636 → 18640.

- Re-pin `example-commands/narrow/commands-path` cadr
  `screenSha256` after wrapped `<CADR_ROOT>` path join. Baseline-side
  and wide SHAs unchanged. Local official core gate EXIT:0
  (120/122). Does not declare the CI differential green.

- Render-diff `<CADR_ROOT>` paths absorb a hard wrap and the
  continuation-line pad so CI and local wrap points converge.
  Does not re-pin I04 pairs in this change.

- RPC `steer` / `follow_up` and busy `prompt` +
  `streamingBehavior` run `:input` hooks off the JSONL reader,
  matching a new prompt. A second hook invocation can no longer
  block confirm/editor answers. Unconditional `rpc-ui-diag`
  prints removed from the RPC UI product path.

- Booked the unpaired-path denominator at 122613 after completions
  reasoning-field coverage.

- Booked the unpaired-path denominator at 122586 after aligning
  settings-list space with the baseline.

- Booked the unpaired-path denominator at 122575 after deleting
  six unused sb-cover A-class helpers.

- Booked the unpaired-path denominator at 122640 after wiring
  the WebSocket extended-length helper.

- Booked the unpaired-path denominator at 122638 after wiring
  OAuth selector raw-input.

- Booked the unpaired-path denominator at 122632 after moving
  RPC steer/follow-up input hooks off the JSONL reader.

- RPC process-modes UI path prints hook/dispatch/client
  diagnostics for confirm and editor so a missing pair can be
  located on the next CI run. Required method set unchanged.

- Re-pin `fatal-crash/narrow/fatal-crash` baseline-side
  `screenSha256` after the wrapped `node:internal` module collapse.
  cadr and wide SHAs unchanged. Does not declare the render
  differential green.

- Render-diff `node:internal/<module>:N:M` collapse now allows a
  hard wrap inside the module name (narrow `processTimers` splits
  `timers` so `521:7` / `523:7` no longer leak). Does not re-pin
  I04 pairs in this change.

- Re-pin `example-commands/{wide,narrow}/commands-path` cadr
  `screenSha256` after checkout root collapsed to `<CADR_ROOT>`.
  Baseline-side SHAs unchanged. Does not declare the render
  differential green.

- Recorded the 2026-08-17 role rulings in the adjudication log and
  advisor playbook (executor never writes a ruling; advisor is
  read-only on shared CI state; differential pins are local truth).

- After a bash tool completes, the settle window stays open through the
  following assistant message and its text deltas (user messages and
  the next tool still lift it), so a wall-clock tick during persist or
  the short "observed" text cannot paint Took+loader and ratchet the
  previous Took line off the render-diff viewport.

- RPC `get_state` now emits JSON `null` for a missing model instead of
  raising on the no-model sentinel. cadr-server spawn retries
  `get_state` until the child reports a non-empty `sessionId` before
  marking the instance online.

- RPC `get_state` omits the `model` key when no model is selected,
  matching baseline `JSON.stringify` of an undefined optional field.

- Render-diff semantic screens collapse `node:internal/<module>:N:M`
  line numbers to `<NODE_LINE>:<NODE_COLUMN>` so Node patch releases
  do not move fatal-crash I04 pairs.

- Re-pin `fatal-crash/{wide,narrow}/fatal-crash` baseline-side
  `screenSha256` after the node:internal collapse. cadr SHAs
  unchanged.

- Goal 20 P0-4: extension `send-message` with trigger-turn no longer
  runs the agent turn on the TUI input thread, so streaming text, tool
  blocks, and the working indicator can paint during the turn. The
  tic-tac-toe move custom message uses the compact banner renderer
  instead of the raw board content.

- WebSocket frames with payload length 65536 or more now read all eight
  length octets (the 64-bit branch used to skip the first), and
  fragmented messages are assembled until FIN. Codex WebSocket debug
  stats take the cache mutex on write as well as read.
  `wss://`/`ws://` URLs convert to `https://`/`http://` for the HTTP
  upgrade.

- `parse-json` signals `json-parse-error` instead of relabeling every
  JSON failure as `sse-protocol-error`. HTTP `request-json` maps a
  damaged body to `transport-error`; streaming JSON repair catches
  `json-parse-error`.

- Startup loaded-resource blocks now follow the baseline (goal 18 Part H):
  section order Context -> Skills -> Prompts -> Extensions -> Themes with
  the baseline labels, locale-compare sorting (Context keeps insertion
  order), banner/sections split at the baseline padding boundary, and the
  three warning blocks ([Skill conflicts], [Prompt conflicts],
  [Extension issues]) with collision groups and severity colors.  Resource
  name collisions keep the baseline winner (project scope) but now record
  the collision diagnostic instead of dropping the loser silently.  A new
  `startup-resources` render-diff scenario captures the populated startup
  in compact and ctrl+o-expanded form on both terminal sizes while the
  empty startup scenarios stay pinned, and the state-coverage sweep is
  documented in `docs/goal18-startup-resources-audit.md`.

- Render-diff harness hygiene (goal 18 Part G): a single-owned sweeper now
  removes tmux `cadr-rd-*` servers whose owning run died and stale
  `/tmp/cadr-render-screen-*` replay dirs at every CLI start, and the
  tmux_screen failure branch is regression-tested to kill its server.
  The two stray `/export` HTML artifacts at the repository root are covered
  by the existing `cadr-*.html` gitignore rule (mirroring the
  baseline's export-artifact ignore rule).

### Added

- Goal 20: `docs/profiling.md` is the standing `sb-sprof` runbook.
  `scripts/goal20-profile.sh` is the driver; neither is a gate.

- Goal 20 Part H: `scripts/goal20-unpaired-paths.py` books which
  `src/**/*.lisp` files are paired, unpairable, or still uncovered.
  The report is section 6 of `docs/acceptance/goal-v20-part-h.md`.

- Goal 20 Part O: `scripts/goal20-profile.sh` captures `sb-sprof` for
  paired paths that still miss 1.0×; the report is
  `docs/benchmarks/goal20-part-o-remaining-sprof.md`.

- Goal 20 Part B: paired-path ratios and FiveAM check counts are written by
  scripts into `docs/performance.md` and the `GOAL20_TEST_CHECKS` comment in
  `docs/test-matrix.md`. `scripts/record-paired-paths.py` books a run from
  the paired-path summary; `scripts/write-test-check-anchor.py` fails
  `test-cl.sh` when the committed check count drifted.

- Goal 18 L2.1: the fixed pi baseline anchor now has a single owner — the
  `BASELINE` file at the repository root (commit, release tag, distance).
  The product release identity derives from it at load time, the diff and
  verify scripts read it instead of embedded literals, a new
  `baseline anchor consistency` stage in `verify.sh` fails when any
  operational reference disagrees, and `scripts/set-baseline.sh` performs
  the mechanical rewrite on upgrade.

- Goal 18 Part L preparation: `scripts/enumerate-baseline-diff.py`
  mechanically enumerates every named user-observable or contract set
  between two baseline commits (flags, settings keys, events, providers,
  env vars, theme tokens, error classes, RPC methods, exit codes, session
  format, ...).  Its first run caught four classes the hand-maintained
  list missed; the v0.84.1 enumeration result is recorded in
  `docs/source-parity-upgrade.md`.

- Goal 18 I7 tail and Part J/K: the startup content migrations are ported
  (oauth.json/settings apiKeys into auth.json with 0600 preserved,
  agent-root sessions into sessions/, managed binaries tools/ -> bin/,
  commands/ -> prompts/ for the global and project roots, and the
  deprecated hooks//tools/ warnings with the interactive any-key pause,
  in the baseline startup order); `--list-models` prints the baseline
  auth-filtered six-column table with fuzzy filtering and the corrupt
  models.json warning envelope; a broken extension is now a fatal
  startup error with the baseline reportDiagnostics lines and the
  `cadr -ne` hint; extension shortcut conflicts follow the baseline
  getShortcuts semantics (reserved keys skip, later registration wins,
  warnings land in the [Extension issues] block); unreadable
  --system-prompt/@file paths produce the baseline Node-style error
  wording instead of raw conditions; the legacy keybinding-name
  migration covers the full 62-name baseline table; the system prompt's
  documentation paths now resolve to the real repository docs instead of
  a hardcoded /usr/local prefix; the twelve user docs the product text
  references (the eleven system-prompt documents plus providers.md) now
  exist and every docs//examples/ reference in product text is
  gate-enforced to resolve (Part J); and the seven coding tools'
  model-visible contract (description, full parameter schema with
  per-property descriptions, prompt snippets) is locked against a
  fixture the gate regenerates from the fixed baseline at capture time
  (Part K — this also renamed grep's `ignore_case` to the baseline
  `ignoreCase` and dropped a non-baseline `minItems` from edit).

- Goal 18 I2 mechanically derived coverage: the login dialog's eight
  `show*` forms and the 33-leaf ExtensionEvent union are extracted from
  the baseline commit's git objects at analysis time and drift-checked
  against the interface inventory, with each dialog form mapped to a
  scenario checkpoint or the construction suite; the unmodeled-sink
  reverse scan (I7.3) fails the gate on any output call with fixed text
  that no inventory site covers, with the 14 current candidates under
  per-site reviewed verdicts; and REQUIRED_COVERAGE now locks the full
  declared tag set so no scenario or tag can silently disappear.  The
  diff report is `docs/goal18-i2-derived-coverage.md`; ten defensive or
  privilege-dependent branches await exemption adjudication in
  `docs/proposals/goal18-i7-tail-exemptions.md`.

- Goal 18 Part I gate hardening and capability completion: the reused
  pi baseline checkout is now verified blob-for-blob against the
  repository's immutable object store before any differential run (I5);
  `verify-release.sh` can no longer exit 0 with live stages skipped —
  `CADR_RELEASE_GATE=1` turns a live SKIP into a named failure while
  everyday `verify.sh` keeps the skip behavior (I6); the presentation
  ledger's scale numbers are machine-reconciled by a FiveAM gate that
  recomputes them from the real artifacts (I4); the four baseline
  session keybinding actions `app.session.{new,tree,fork,resume}` are
  registered unbound, bindable via settings.json, and dispatch to the
  same handlers as their slash commands (I7); and the bundled llama
  extension gained the full baseline `ui.ts` surface — context-size
  labels, model descriptions, compact counts, the framed model selector,
  live Hugging Face search with debounce, and the cancellable progress
  view over a persistent custom component with a render channel (I8).

- Goal 18 Part E/F audit deliverables: the intentional-difference ledger grew
  from 72 to 77 rows after recasting five component-export rows
  (extension/show-images/skill-invocation/theme/thinking selectors) with
  baseline-consumption evidence, and the `settings-state-sweep` render-diff
  scenario now enables terminal image support so the `Show images` and
  `Image width` rows are captured and pinned on both sides.  The full audit
  report lives in `docs/goal18-part-e-audit.md`, and the package-boundary map
  in `docs/source-parity.md` §1a now records the `cadr-core` path-owner and
  the `agent/src/harness/tools/` routing refinement.

- Implemented the baseline `/debug` command and its `shift+ctrl+d` binding:
  the terminal's rendered lines (with visible widths) and the agent messages
  (JSONL) are written to `~/.cadr/agent/cadr-debug.log` (I04 filename), and
  the chat confirms with the baseline accent "✓ Debug log written" + muted
  path block.  Recorded that the baseline's `getToolsDir` is dead code (zero
  callers) and is deliberately not implemented.

- Completed the login dialog's baseline surface: auth selects now borrow the
  screen and restore the dialog (the Radius/OpenAI method choice no longer
  strands later auth events into the transcript), text/secret prompts render
  through the dialog's prompt form, and the info (message + links) and
  details forms exist.  Bedrock and Vertex API key logins run their baseline
  structured flows (method select, per-method prompts, info notice with
  links) through the dialog, and the login completion messages follow the
  baseline "Logged in to … Credentials saved to …" text.  New render-diff
  scenarios cover the manual-code and browser-callback flows end to end —
  cancel with post-cancel probes and a completion path each.

- Added the fourth parity ledger for visible presentation semantics, including
  production probes for all 55 theme tokens and machine-checked ledger totals.
- Added a self-contained baseline-compatible session HTML exporter with the
  approved vendored Marked and Highlight.js browser assets.

### Changed

- Reduced alternate-screen continuous-input p99 from 52ms to 8ms at the
  5,000-entry stress tier while preserving the complete logical document.
- Replaced the OAuth callback page's interim block-C mark with Cadr's
  single-path square-grid cons-cell identity.
- Changed `/share` to use `https://cadr.dev/session/` by default, with
  `CADR_SHARE_VIEWER_URL` as the sole environment override.
- Replaced the remaining 14 production `PI_*` environment names with their
  `CADR_*` equivalents without legacy aliases.

### Fixed

- Fixed ESC-cancelling an xAI, Kimi, GitHub Copilot, or Radius device-code
  login never reaching the shared device poller's cancellation flag, so the
  login worker ran until token expiry and every later message stalled in the
  Steering queue; the flows now poll through `poll-device-authorization`'s
  `cancelled-p` like the OpenAI Codex route, and each cancel-path render-diff
  scenario ends with a post-cancel message exchange.
  Attribution (goal 18 A4.5): the mechanism — `busy-p` cleared only when the
  login worker ends, with ESC setting flags but never guaranteeing that end —
  predates the goal 17 login-dialog rework (74fe2c0b8); the rework exposed it
  by giving ESC a dialog-closing path that made "cancelled UI, living worker"
  reachable.  It is not a goal 17 regression.
- Cancelling OpenAI or Anthropic login now stops the loopback/manual workers,
  releases the listener, clears the working state, and returns to the editor.
- Interactive cleanup now bounds every background-thread join and forcibly
  stops an unresponsive worker instead of deadlocking exit.
- `/export` now reports the baseline-aligned bare output filename.
- Fixed automatic version checks comparing upstream pi `0.83.x` releases with
  Cadr `0.2.x`; checks are now disabled unless `CADR_VERSION_CHECK_URL` names a
  Cadr-compatible endpoint.
- Fixed outbound provider attribution, changelog links, browser storage,
  temporary files, synthetic tool IDs, examples, and Radius diagnostics that
  still presented Cadr as pi.

### Security

- Unhandled conditions now use a sanitized fatal boundary: terminal output
  contains no backtrace or object dump, diagnostics are exact/pattern redacted
  into mode-0600 crash logs, and credential-bearing objects print redacted.

## [0.2.0] - 2026-08-01

**cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)**

### Added

- Goal 1: established the Common Lisp/ASDF architecture and the provider,
  streaming, message, tool, usage, and error foundations.
- Goal 2: implemented the agent loop, lifecycle event spine, tool execution,
  retry/abort handling, and session state.
- Goal 3: added the native CLI, REPL, built-in coding tools, provider/model
  configuration, system prompt, and recorded provider parity fixtures.
- Goal 4: added JSONL persistence, continuation, retry policy, native image
  builds, migration acceptance, and executable smoke coverage.
- Goal 5: delivered the pure Common Lisp TUI, Unicode/grapheme-safe editor,
  overlays, images, resize handling, differential rendering, and terminal
  lifecycle recovery.
- Goal 6: expanded provider/catalog, OAuth, image, model-runtime, extension,
  package, session-tree, compaction, and RPC compatibility with original pi.
- Goal 7: completed the audited extension lifecycle/UI/runtime API, session and
  queue surfaces, print/JSON/RPC modes, SQLite storage, Unix-socket server, and
  eval harnesses.
- Goal 8: closed the exhaustive TypeScript test parity ledger, added the CBOR
  protocol package, completed the dependency audit, and separated deterministic
  and credential-gated live FiveAM entry points.
- Goal 9: upgraded the behavioral baseline to
  `earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`, automated the
  former manual acceptance paths, completed mechanical/runtime TUI parity,
  identified OpenAI traffic as `originator=cadr`, and added the local
  deterministic/build/process/PTY/live verification gate.
- Goal 10: established the private backup and real CI gate, retained the
  newer-than-tag baseline by explicit no-op adjudication, and added the
  approved Lisp-native tool restarts plus opt-in loopback Slynk REPL.
- Goal 11: added deterministic performance, allocation, cold-start, long-run
  memory/resource, and large-session latency release gates.

### Changed

- Renamed the implementation, packages, executable, configuration directory,
  and environment namespace from the migration-era `pi-cl` names to Cadr while
  preserving the historical reference and migration path.
- Aligned the security model with original pi: tools execute directly by
  default, optional approval is an extension hook, and containerization remains
  the strong isolation boundary.
- Released version `0.2.0` from the single `version.sexp` production source;
  the CLI identity also records alignment with pi `v0.83.0` plus 38 commits at
  `74caa2649`.
- Removed the completed `0.1.x` fallback for `PI_CL_PROVIDER`, `PI_CL_MODEL`,
  and `PI_CL_BASE_URL`; use the `CADR_*` names.

### Fixed

- Corrected provider stream text preservation, OpenAI Responses reasoning
  summaries, unknown-model thinking capabilities, OAuth provider identity, and
  model-facing tool result text/counting semantics.
- Corrected selector empty/wrap boundaries, CJK/emoji editing, streamed TUI
  output, tool error states, Markdown/code rendering, overlay copy/layout,
  footer model refresh, terminal positioning, and PTY restoration.
- Removed test timing races, OAuth refresh-token copy pollution, shell-smoke
  credential rewriting, wrapper stderr leakage, and user-settings coupling from
  deterministic/live evidence.

### Security

- OAuth credentials use a single `~/.cadr/auth.json` store with atomic writes,
  mode `0600`, refresh locking, provider-consistent identities, and redaction
  from errors, sessions, transport logs, and reports.
- Third-party dependencies are frozen by the audited allowlist; any new direct
  or transitive dependency blocks implementation until explicit pre-approval.
- Slynk is default-off, loopback-only, explicitly enabled, and documented as
  an arbitrary-evaluation debugging service rather than a sandbox.
