(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

;;; pi@4a080252f packages/codemode/src/source.ts, identifier.ts,
;;; packages/coding-agent/src/extensions/codemode/{tool,execute,index}.ts

(defun codemode-result-text (content)
  (cadr-ai::content-text content (string #\Newline)))

(test codemode-source-options-match-upstream
  (multiple-value-bind (code options)
      (cadr-cli::codemode-parse-source
       (format nil "// @options: {\"max_output_tokens\": 2000, \"timeout_ms\": 30000}~%return 1;"))
    (is (string= (format nil "~%return 1;") code))
    (is (= 2000 (getf options :max-output-tokens)))
    (is (= 30000 (getf options :timeout-ms))))
  (handler-case
      (progn (cadr-cli::codemode-parse-source "  ")
             (fail "empty source was accepted"))
    (cadr-cli::codemode-source-error (condition)
      (is (string= "Expected JavaScript source text (non-empty). Provide JS only, optionally with a first line `// @options: {\"max_output_tokens\": 1000}`."
                   (cadr-cli::codemode-source-error-text condition)))))
  (handler-case
      (progn (cadr-cli::codemode-parse-source (format nil "return 1;~%// @options: {}"))
             (fail "misplaced options were accepted"))
    (cadr-cli::codemode-source-error (condition)
      (is (search "found one on line 2" (cadr-cli::codemode-source-error-text condition)))))
  (handler-case
      (progn (cadr-cli::codemode-parse-source
              (format nil "// @options: {\"timeout_ms\": 0}~%return 1;"))
             (fail "zero timeout was accepted"))
    (cadr-cli::codemode-source-error (condition)
      (is (search "positive integer up to 2147483647"
                  (cadr-cli::codemode-source-error-text condition))))))

(test codemode-identifiers-replace-non-js-characters
  (is (string= "my_tool" (cadr-cli::codemode-identifier "my-tool")))
  (is (string= "mcp__docs__search" (cadr-cli::codemode-identifier "mcp__docs__search")))
  (is (string= "_" (cadr-cli::codemode-identifier ""))))

(test codemode-worker-cap-defaults-to-two-and-reads-cadr-env
  (sb-posix:unsetenv "CADR_CODEMODE_MAX_WORKERS")
  (is (= 2 (cadr-cli::codemode-max-workers)))
  (sb-posix:setenv "CADR_CODEMODE_MAX_WORKERS" "4" 1)
  (is (= 4 (cadr-cli::codemode-max-workers)))
  (sb-posix:setenv "CADR_CODEMODE_MAX_WORKERS" "0" 1)
  (is (= 2 (cadr-cli::codemode-max-workers)))
  (sb-posix:setenv "CADR_CODEMODE_MAX_WORKERS" "nope" 1)
  (is (= 2 (cadr-cli::codemode-max-workers)))
  (sb-posix:unsetenv "CADR_CODEMODE_MAX_WORKERS"))

(test codemode-worker-wait-is-arrival-order-and-does-not-start
  (sb-posix:unsetenv "CADR_CODEMODE_MAX_WORKERS")
  (let ((held nil))
    (unwind-protect
         (progn
           (setf held
                 (loop repeat 2
                       collect (cadr-cli::codemode-reserve-worker 1000 nil)))
           (is (every (lambda (value) (eq value :reserved)) held))
           (is (eq :timeout (cadr-cli::codemode-reserve-worker 30 nil)))
           (is (eq :aborted
                   (cadr-cli::codemode-reserve-worker 60000 (lambda () t))))
           (let* ((code (format nil "// @options: {\"timeout_ms\": 40}~%return 1;"))
                  (arguments (cadr-ai::json-object "code" code)))
             (multiple-value-bind (content details terminate structured usage is-error)
                 (cadr-cli::execute-codemode nil "call" arguments nil nil nil)
               (declare (ignore details terminate structured usage))
               (let ((text (codemode-result-text content)))
                 (is (eq is-error t))
                 (is (search "Script failed" text))
                 (is (search "Script timed out: Execution timed out after 40 ms while waiting for a free codemode worker" text))
                 (is (search "The script did not start." text))))))
      (dolist (value held)
        (when (eq value :reserved)
          (cadr-cli::codemode-release-worker))))))

(test codemode-settings-mode-and-inline-budget
  (let ((cadr-cli::*codemode-settings-manager*
          (cadr-cli::make-memory-settings-manager
           (cadr-ai::json-object
            "codemode" (cadr-ai::json-object
                        "mode" "only"
                        "inlineBudget" 12)))))
    (is (string= "only" (cadr-cli::codemode-mode)))
    (is (= 12 (cadr-cli::codemode-inline-budget))))
  (let ((cadr-cli::*codemode-settings-manager*
          (cadr-cli::make-memory-settings-manager
           (cadr-ai::json-object
            "codemode" (cadr-ai::json-object
                        "mode" "sometimes"
                        "inlineBudget" -1)))))
    (is (string= "on" (cadr-cli::codemode-mode)))
    (is (= 3000 (cadr-cli::codemode-inline-budget)))))

(test codemode-description-lists-within-budget-and-skips-deferred
  (let* ((small (cadr-ai:make-tool :name "read" :description "Read a file"
                                   :parameters (cadr-ai::json-object
                                                "type" "object"
                                                "properties" (cadr-ai::json-object
                                                              "path" (cadr-ai::json-object "type" "string"))
                                                "required" (vector "path"))))
         (large (cadr-ai:make-tool :name "bash" :description (make-string 400 :initial-element #\a)
                                   :parameters (cadr-ai::json-object "type" "object")))
         (deferred (cadr-ai:make-tool :name "later" :description "Later"
                                      :parameters (cadr-ai::json-object "type" "object")))
         (tight (cadr-cli::codemode-description (list small large) :budget 80))
         (with-deferred (cadr-cli::codemode-description
                         (list small deferred) :budget nil :deferred '("later")))
         (without (cadr-cli::codemode-description (list small) :budget nil)))
    (is (search "### `read`" tight))
    (is (search "Read a file" tight))
    (is (not (search "### `bash`" tight)))
    (is (string= with-deferred without))
    (is (search "resolves to a string" (cadr-cli::codemode-script-call small)))))

(test codemode-cli-does-not-depend-on-the-wasm-system
  (let ((text (uiop:read-file-string
               (asdf:system-relative-pathname "cadr-cli" "cadr-cli.asd"))))
    (is (null (search "cadr-wasm" text)))))

(defun codemode-wasm-call (name &rest arguments)
  (apply (find-symbol name "CADR-WASM") arguments))

(test codemode-vendored-quickjs-matches-the-published-sha256
  (asdf:load-system "cadr-wasm")
  (is (string= "d4c9375f2b1ca4dc95f72c8aa2982a7a9951ac8011490d79c6582df732b4bbd9"
               (codemode-wasm-call "QUICKJS-WASM-SHA256")))
  (is (string= "d4c9375f2b1ca4dc95f72c8aa2982a7a9951ac8011490d79c6582df732b4bbd9"
               (codemode-wasm-call "SHA256-HEX" (codemode-wasm-call "QUICKJS-WASM-BYTES"))))
  (is (= 637405 (length (codemode-wasm-call "QUICKJS-WASM-BYTES"))))
  (is (search "MIT"
              (uiop:read-file-string
               (asdf:system-relative-pathname
                "cadr-wasm" "src/cadr-wasm/cache.lisp")))))

(defun codemode-quickjs-contract ()
  (let ((cadr-cli::*codemode-script-tools*
          (list (cadr-ai:make-tool
                 :name "echo"
                 :description "Echo"
                 :parameters (cadr-ai::json-object "type" "object")
                 :executor (lambda (id arguments)
                             (declare (ignore id))
                             (gethash "text" arguments)))))
        (cadr-cli::*codemode-model-runtime*
          (cadr-ai::json-object))
        (failures nil))
    (setf (gethash "classify" cadr-cli::*codemode-model-runtime*)
          (lambda (model context)
            (declare (ignore context))
            (cadr-ai::json-object "label" (gethash "id" model) "stopReason" "stop")))
    (setf (gethash "generateImages" cadr-cli::*codemode-model-runtime*)
          (lambda (model context)
            (declare (ignore model context))
            (cadr-ai::json-object
             "stopReason" "stop"
             "output" (vector (cadr-ai::json-object
                               "type" "image" "data" "aaaa" "mimeType" "image/png")))))
    (labels ((run-script (code)
               (cadr-cli::execute-codemode
                nil "script"
                (cadr-ai::json-object "code" code)
                nil nil nil))
             (check (name code needle)
               (multiple-value-bind (content details terminate structured usage is-error)
                   (run-script code)
                 (declare (ignore details terminate structured usage))
                 (let* ((text (codemode-result-text content))
                        (at (search "Output:" text))
                        (body (if at (subseq text at) text)))
                   (unless (and (search needle body)
                                (or (search "Script completed" text)
                                    (search "Script failed" text)))
                     (push (format nil "~A: ~A" name text) failures))
                   (list text is-error)))))
      (check "return" "return 1 + 1;" "2")
      (let ((first (codemode-wasm-call "LAST-COMPILE-CACHED-P")))
        (check "tool" "return await tools.echo({ text: \"hi\" });" "hi")
        (unless (or first (codemode-wasm-call "LAST-COMPILE-CACHED-P"))
          (push "second script did not use the compile cache" failures)))
      (check "store" (format nil "store(\"k\", 7); return load(\"k\");") "7")
      (check "classify"
             "const model = { provider: \"test\", id: \"c\" }; return await models.classify(model, { prompt: \"x\" });"
             "c")
      (let ((pair (check "images"
                         "const model = { provider: \"test\", id: \"img\" }; await models.generateImages(model, { prompt: \"x\" }); return \"done\";"
                         "Note: models.generateImages() returned 1 image")))
        (declare (ignore pair)))
      (let ((pair (check "interrupt"
                         (format nil "// @options: {\"timeout_ms\": 500}~%while (true) {}")
                         "Script timed out: Execution timed out after")))
        (unless (second pair)
          (push "interrupt was not an error result" failures)))
      (let ((pair (check "oom"
                         "let s = \"x\".repeat(300000000); return s.length;"
                         "InternalError: out of memory")))
        (unless (second pair)
          (push "oom was not an error result" failures))))
    (when failures
      (error "codemode quickjs contract failed:~%~{~A~%~}" failures))
    t))

(test codemode-quickjs-runs-the-upstream-contract
  (if (>= (sb-ext:dynamic-space-size) (* 6 1024 1024 1024))
      (is (eq t (codemode-quickjs-contract)))
      (let* ((root (asdf:system-source-directory "cadr-cli"))
             (asds '("cadr-core.asd" "cadr-chord.asd" "cadr-durable.asd"
                     "cadr-telemetry.asd" "cadr-ai.asd" "cadr-agent.asd"
                     "cadr-tui.asd" "cadr-cli.asd" "cadr-live-test-support.asd"
                     "cadr-wasm.asd"))
             (args (append
                    (list "sbcl" "--dynamic-space-size" "8192" "--noinform"
                          "--non-interactive" "--disable-debugger"
                          "--load" (namestring
                                    (uiop:parse-native-namestring
                                     (or (uiop:getenv "QUICKLISP_SETUP")
                                         (merge-pathnames "quicklisp/setup.lisp"
                                                          (user-homedir-pathname))))))
                    (loop for name in asds
                          append (list "--eval"
                                       (format nil "(asdf:load-asd ~S)"
                                               (namestring (merge-pathnames name root)))))
                    (list "--eval" "(asdf:load-system \"cadr-cli/tests\")"
                          "--eval" "(cadr-cli/tests::codemode-quickjs-contract)"
                          "--quit")))
             (code (nth-value 2 (uiop:run-program args :output nil :error-output nil
                                                  :ignore-error-status t))))
        (is (zerop code)))))
