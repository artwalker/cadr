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
    ("evals_harness.summarize" . 20)
    ("ai_crypto_model_data.manifest" . 50)
    ("ai_crypto.hmac" . 50)
    ("cli_models_rest.pattern_match" . 50)
    ("image_runtime.dimensions" . 50)
    ("image_runtime.mime_type" . 50)
    ("image_runtime.lookup" . 50)
    ("image_runtime.dimension_note" . 50)
    ("image_runtime.api_provider" . 50)
    ("cli_print_rpc.jsonl_line" . 50)
    ("cli_print_rpc.jsonl_read" . 50)
    ("tui_latex.render" . 20)
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
    ("cli_interactive_controller.decode_entity" . 50)
    ("cli_sdk.version_newer" . 50)
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

(defun measure-agent-tool-loop ()
  (multiple-value-bind (agent executed)
      (run-paired-tool-loop)
    (let* ((messages (cadr-agent:agent-messages agent))
           (last (car (last messages)))
           (result (third messages)))
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
        "tool_value" (or executed ""))
       "roundtrip"
       (collect "agent_tool_loop.roundtrip"
                (lambda ()
                  (lambda ()
                    (run-paired-tool-loop))))))))

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

(defun measure-evals-harness ()
  (let ((observed (run-evals-harness-summarize)))
    (json-object
     "observed"
     (json-object
      "eval_sets" (first observed)
      "comparisons" (second observed)
      "candidate_wins" (third observed)
      "ties" (fourth observed))
     "summarize"
     (collect "evals_harness.summarize"
              (lambda ()
                (lambda ()
                  (run-evals-harness-summarize)))))))

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

(defun measure-cli-models-rest ()
  (let* ((models
           (cadr-cli::model-registry-available-models
            (list-models-registry)))
         (rows (run-cli-models-rest models))
         (exact (first rows))
         (bare (second rows))
         (partial (third rows))
         (scoped (fourth rows))
         (missing (fifth rows)))
    (json-object
     "observed"
     (json-object
      "exact_id" (second exact)
      "exact_provider" (third exact)
      "bare_id" (second bare)
      "partial_id" (second partial)
      "scoped_id" (second scoped)
      "scoped_thinking" (fourth scoped)
      "miss" (if (string= (second missing) "") 1 0))
     "pattern_match"
     (collect "cli_models_rest.pattern_match"
              (lambda ()
                (lambda ()
                  (run-cli-models-rest models)))))))

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

(defun measure-cli-print-rpc ()
  (let* ((line (run-cli-print-rpc))
         (newline-p
           (and (plusp (length line))
                (char= #\Newline (char line (1- (length line))))))
         (payload
           (if newline-p
               (subseq line 0 (1- (length line)))
               line))
         (read-lines (run-cli-print-rpc-read)))
    (json-object
     "observed"
     (json-object
      "line_chars" (length line)
      "newline" (if newline-p 1 0)
      "payload" payload
      "line_count" (length read-lines)
      "first" (or (first read-lines) "")
      "second" (or (second read-lines) "")
      "last_line" (or (third read-lines) ""))
     "jsonl_line"
     (collect "cli_print_rpc.jsonl_line"
              (lambda ()
                (lambda ()
                  (run-cli-print-rpc))))
     "jsonl_read"
     (collect "cli_print_rpc.jsonl_read"
              (lambda ()
                (lambda ()
                  (run-cli-print-rpc-read)))))))

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

(defun measure-cli-support-strip-ansi ()
  (let ((ansi (run-cli-support-strip-ansi))
        (paths (run-cli-support-normalize-path))
        (timings (run-cli-support-timings))
        (bus (run-cli-support-event-bus))
        (headers (run-cli-support-attribution-headers))
        (shell (run-cli-support-shell-config))
        (sanitize (run-cli-support-sanitize-output))
        (git (run-cli-support-git-source))
        (ua (run-cli-support-user-agent)))
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
      "ua_semi" (third ua))
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
                  (run-cli-support-user-agent)))))))

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

(defun measure-cli-interactive-decode-entity ()
  (let ((observed (run-cli-interactive-decode-entity)))
    (json-object
     "observed"
     (json-object
      "amp" (first observed)
      "lt" (second observed)
      "gt" (third observed)
      "quot" (fourth observed)
      "apos" (fifth observed)
      "hash65" (sixth observed)
      "miss" (seventh observed))
     "decode_entity"
     (collect "cli_interactive_controller.decode_entity"
              (lambda ()
                (lambda ()
                  (run-cli-interactive-decode-entity)))))))

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

(defun measure-cli-sdk-version-newer ()
  (let ((observed (run-cli-sdk-version-newer)))
    (json-object
     "observed"
     (json-object
      "beta" (first observed)
      "eq" (second observed)
      "older" (third observed)
      "newer_flag" (fourth observed)
      "equal_flag" (fifth observed))
     "version_newer"
     (collect "cli_sdk.version_newer"
              (lambda ()
                (lambda ()
                  (run-cli-sdk-version-newer)))))))

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
      "evals_harness.summarize"
      "src/cadr-evals/summary.lisp summarize-harness-comparisons"
      "ai_crypto_model_data.manifest"
      "src/cadr-ai/model-data.lisp create-model-data-manifest"
      "ai_crypto.hmac"
      "src/cadr-ai/crypto.lisp hmac-sha256"
      "cli_models_rest.pattern_match"
      "src/cadr-cli/models/matching.lisp parse-scoped-model-pattern"
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
      "tui_latex.render"
      "src/cadr-tui/latex.lisp render-latex"
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
      "cli_interactive_controller.decode_entity"
      "src/cadr-cli/interactive/syntax.lisp decode-highlight-entity"
      "cli_sdk.version_newer"
      "src/cadr-cli/sdk/cache-version.lisp newer-package-version-p"
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
              "evals_harness" evals
              "ai_crypto_model_data" crypto
              "ai_crypto" hmac
              "cli_models_rest" models-rest
              "image_runtime" images
              "cli_print_rpc" print-rpc
              "tui_latex" latex
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
              "cli_sdk" sdk
              "provider_registry_defs" provider-defs
              "skill_prompt_load" skill-prompt
              "cli_bootstrap_sessions" bootstrap
              "ai_runtime_faux" faux
              "http_transport" http-transport
              "render_slicing" slicing)
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
             "schema_version" 1))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))

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
