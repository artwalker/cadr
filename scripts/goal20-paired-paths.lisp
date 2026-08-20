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
                  "cadr-cli.asd"))
    (asdf:load-asd
     (truename
      (merge-pathnames
       name cl-user::*cadr-bench-project-directory*))))
  (asdf:load-system "cadr-cli" :verbose nil))

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
             "schema_version" 1))))))))))))))))))))))))))

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
