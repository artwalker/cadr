(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

;;; pi@4a080252f packages/codemode/src/source.ts, identifier.ts,
;;; packages/coding-agent/src/extensions/codemode/{tool,execute,index}.ts

(defun codemode-result-text (content)
  (cadr-ai::content-text content (string #\Newline)))

(test codemode-source-options-match-upstream
  ;; packages/codemode/test/source.test.ts at v1.4.0.
  (multiple-value-bind (code options)
      (cadr-cli::codemode-parse-source "text('hi')")
    (is (string= "text('hi')" code))
    (is (null options)))
  (multiple-value-bind (code options)
      (cadr-cli::codemode-parse-source (format nil "// just a comment~%return 1"))
    (is (string= (format nil "// just a comment~%return 1") code))
    (is (null options)))
  (multiple-value-bind (code options)
      (cadr-cli::codemode-parse-source
       (format nil "// @optionsx {}~%text(1)"))
    (is (string= (format nil "// @optionsx {}~%text(1)") code))
    (is (null options)))
  (multiple-value-bind (code options)
      (cadr-cli::codemode-parse-source "text(\"// @options: {}\")")
    (is (string= "text(\"// @options: {}\")" code))
    (is (null options)))
  (multiple-value-bind (code options)
      (cadr-cli::codemode-parse-source
       (format nil "// @options: {\"timeout_ms\": 10}~%const a = 1;~%text(a)"))
    (is (string= (format nil "~%const a = 1;~%text(a)") code))
    (is (= 10 (getf options :timeout-ms))))
  (multiple-value-bind (code options)
      (cadr-cli::codemode-parse-source
       (format nil "  // @options:{\"max_output_tokens\":0,\"timeout_ms\":1500}~C~%text(1)" #\Return))
    (declare (ignore code))
    (is (= 0 (getf options :max-output-tokens)))
    (is (= 1500 (getf options :timeout-ms))))
  (multiple-value-bind (code options)
      (cadr-cli::codemode-parse-source
       (format nil "// @options: {}~%text(1)"))
    (is (string= (format nil "~%text(1)") code))
    (is (null options)))
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
                  (cadr-cli::codemode-source-error-text condition)))))
  (dolist (pair (list
                 (list (format nil "// count things~%// @options: {\"timeout_ms\": 1000}~%while (true) {}")
                       "found one on line 2")
                 (list (format nil "~%  // @options: {\"timeout_ms\": 1000}~%while (true) {}")
                       "found one on line 2")
                 (list (format nil "text(1)~C~%// @options: {\"timeout_ms\": 1}" #\Return)
                       "found one on line 2")
                 (list (format nil "// @options: {\"timeout_ms\": 1}~%text(1)~%// @options: {\"timeout_ms\": 2}")
                       "found one on line 3")
                 (list "" "Expected JavaScript source text (non-empty)")
                 (list (format nil "  ~%") "Expected JavaScript source text (non-empty)")
                 (list (format nil "// @options:~%text(1)")
                       "@options must be a JSON object with supported fields")
                 (list (format nil "// @options: {timeout_ms: 1}~%text(1)")
                       "@options must be valid JSON with supported fields")
                 (list (format nil "// @options: [1]~%text(1)")
                       "@options must be a JSON object with supported fields")
                 (list (format nil "// @options: {\"yield\": 1}~%text(1)")
                       "@options only supports `max_output_tokens` and `timeout_ms`; got `yield`")
                 (list (format nil "// @options: {\"max_output_tokens\": 1.5}~%text(1)")
                       "@options field `max_output_tokens` must be a non-negative safe integer")
                 (list "// @options: {\"timeout_ms\": 1}"
                       "The @options line must be followed by JavaScript source on subsequent lines")
                 (list (format nil "// @options: {\"timeout_ms\": 1}~%  ~%")
                       "The @options line must be followed by JavaScript source on subsequent lines")))
    (handler-case
        (progn (cadr-cli::codemode-parse-source (first pair))
               (fail (format nil "accepted ~S" (first pair))))
      (cadr-cli::codemode-source-error (condition)
        (is (search (second pair)
                    (cadr-cli::codemode-source-error-text condition)))))))

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
  ;; cadr-cli does not depend on cadr-wasm. The host loads the asd
  ;; on the first script; this check has to do the same.
  (asdf:load-asd
   (asdf:system-relative-pathname "cadr-cli" "cadr-wasm.asd"))
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

(defun codemode-signal-text (function)
  (handler-case
      (progn (funcall function) nil)
    (error (condition)
      (princ-to-string condition))))

(test codemode-models-discovery-images-and-schema-match-v140
  (let ((cadr-cli::*codemode-model-runtime* nil)
        (cadr-cli::*active-native-model-registry* nil)
        (cadr-cli::*codemode-tool-namespaces* nil))
    (let ((info (cadr-cli::codemode-model-call
                 "models.getModelOfType"
                 (vector "classifier" "typesafe" "jev-latest"))))
      (is (hash-table-p info))
      (is (string= "jev-latest" (gethash "id" info)))
      (is (string= "typesafe" (gethash "provider" info)))
      (is (string= "classifier" (gethash "type" info)))
      (is (= 64000 (gethash "contextWindow" info)))
      (is (cadr-ai::json-present-p info "input"))
      (is (not (cadr-ai::json-present-p info "headers")))
      (let ((cost (gethash "cost" info))
            (compat (gethash "compat" info)))
        (is (hash-table-p cost))
        (is (= 0 (gethash "input" cost)))
        (is (= 0 (gethash "output" cost)))
        (is (= 0 (gethash "cacheRead" cost)))
        (is (= 0 (gethash "cacheWrite" cost)))
        (is (string= "assets" (gethash "imageInput" compat)))
        (is (eq t (gethash "sendImageOptInHeader" compat)))))
    (is (eq :codemode-undefined
            (cadr-cli::codemode-model-call
             "models.getModelOfType"
             (vector "classifier" "typesafe" "missing"))))
    (let ((image (cadr-cli::codemode-model-call
                  "models.getModelOfType"
                  (vector "image" "openrouter" "black-forest-labs/flux-3-image"))))
      (is (string= "image" (gethash "type" image)))
      (is (find "image" (gethash "output" image) :test #'string=))
      (is (hash-table-p (gethash "cost" image)))
      (is (not (cadr-ai::json-present-p image "headers")))
      (is (not (cadr-ai::json-present-p image "contextWindow"))))
    (is (zerop (length (cadr-cli::codemode-model-call
                        "models.getAvailableOfType"
                        (vector "classifier")))))
    (is (find "jev-latest"
              (cadr-cli::codemode-model-call
               "models.getModelsOfType" (vector "classifier" "typesafe"))
              :key (lambda (model) (gethash "id" model))
              :test #'string=))
    (let ((text (codemode-signal-text
                 (lambda ()
                   (cadr-cli::codemode-model-call
                    "models.getModelOfType" (vector "video"))))))
      (is (search "Unknown model type \"video\". Use \"chat\", \"image\", or \"classifier\"."
                  text)))
    (let ((text (codemode-signal-text
                 (lambda ()
                   (cadr-cli::codemode-model-call
                    "models.getModelOfType" (vector "classifier" "typesafe"))))))
      (is (search "models.getModelOfType(type, provider, id) expects three strings, got (a string, a string)."
                  text))
      (is (search "models.getModelOfType(\"classifier\", \"typesafe\", \"jev-latest\")" text)))
    (let ((text (codemode-signal-text
                 (lambda ()
                   (cadr-cli::codemode-model-call
                    "models.classify"
                    (vector (cadr-ai::json-object "provider" "scorer" "id" "nope")
                            (cadr-ai::json-object)))))))
      (is (search "Unknown classifier model \"scorer/nope\"." text))
      (is (search "models.getAvailableOfType(\"classifier\")" text)))
    (let ((text (codemode-signal-text
                 (lambda ()
                   (cadr-cli::codemode-model-call
                    "models.classify"
                    (vector (cadr-ai::json-object
                             "provider" "openrouter"
                             "id" "black-forest-labs/flux-3-image")
                            (cadr-ai::json-object)))))))
      (is (search "\"openrouter/black-forest-labs/flux-3-image\" is an image model, not a classifier model."
                  text)))
    (let ((text (codemode-signal-text
                 (lambda ()
                   (cadr-cli::codemode-model-call
                    "models.classify"
                    (cadr-cli::codemode-parse-ordered
                     "[{\"provider\":\"typesafe\",\"id\":\"jev-latest\"},{\"prompt\":\"x\"}]"))))))
      (is (search "models.classify() context.state must be an object, got undefined." text))
      (is (search "See \"Classify\" in " text))
      (is (search "codemode.md" text)))
    (let ((text (codemode-signal-text
                 (lambda ()
                   (cadr-cli::codemode-model-call
                    "models.classify"
                    (cadr-cli::codemode-parse-ordered
                     "[{\"provider\":\"typesafe\",\"id\":\"jev-latest\"},[]]"))))))
      (is (search "models.classify() expects a context object as its second argument, got an empty array."
                  text)))
    (let ((result (cadr-cli::codemode-handle-call
                   nil nil
                   (list :call 1 "global" "models.generateImages"
                         "[{\"provider\":\"openrouter\",\"id\":\"black-forest-labs/flux-3-image\"},{\"input\":[{\"type\":\"text\",\"text\":\"x\"},{\"type\":\"file\",\"data\":\"zz\"}]}]")
                   (list 0))))
      (is (search "models.generateImages() context.input[1] must be a text or image block, got { type, data }."
                  (second result))))
    (let ((text (codemode-signal-text
                 (lambda ()
                   (cadr-cli::codemode-model-call
                    "models.generateImages"
                    (cadr-cli::codemode-parse-ordered
                     "[{\"provider\":\"openrouter\",\"id\":\"black-forest-labs/flux-3-image\"},{\"prompt\":\"x\"}]"))))))
      (is (search "models.generateImages() context.input must be a non-empty array of blocks, got undefined."
                  text))
      (is (search "See \"Generate images\" in " text)))
    (let ((result (cadr-cli::codemode-model-call
                   "models.classify"
                   (cadr-cli::codemode-parse-ordered
                    "[{\"provider\":\"typesafe\",\"id\":\"jev-latest\"},{\"state\":{},\"questions\":{\"kind\":{\"type\":\"bool\",\"instructions\":\"Is it?\",\"criteria\":{\"true\":\"yes\",\"false\":\"no\"}}}}]"))))
      (is (string= "error" (gethash "stopReason" result)))
      (is (search "API key" (gethash "errorMessage" result))))
    (let ((called (list nil)))
      (let ((cadr-cli::*codemode-model-runtime*
              (cadr-cli::make-codemode-model-backend
               :models (list (cadr-cli::make-codemode-resolved-model
                              :type "classifier" :provider "scorer" :id "textonly"
                              :name "Text" :api "test" :input '("text")))
               :classify-function (lambda (model context)
                                    (declare (ignore model context))
                                    (setf (car called) t)))))
        (let ((result (cadr-cli::codemode-model-call
                       "models.classify"
                       (cadr-cli::codemode-parse-ordered
                        "[{\"provider\":\"scorer\",\"id\":\"textonly\"},{\"state\":{},\"images\":[{\"type\":\"image\",\"data\":\"aa\",\"mimeType\":\"image/png\"}],\"questions\":{\"k\":{\"type\":\"bool\",\"instructions\":\"q\",\"criteria\":{\"true\":\"y\",\"false\":\"n\"}}}}]"))))
          (is (null (car called)))
          (is (string= "error" (gethash "stopReason" result)))
          (is (search "Model scorer/textonly does not accept image input"
                      (gethash "errorMessage" result))))))
    (let* ((tools (append
                   (loop for index from 1 to 9
                         collect (cadr-ai:make-tool
                                  :name (format nil "widget~A" index)
                                  :description "widget catalog"
                                  :parameters (cadr-ai::json-object "type" "object")))
                   (list (cadr-ai:make-tool
                          :name "mcp__docs__search"
                          :description "Search the docs"
                          :parameters (cadr-ai::json-object "type" "object"))
                         (cadr-ai:make-tool
                          :name "list_radius"
                          :description "List radius"
                          :parameters (cadr-ai::json-object "type" "object")))))
           (cadr-cli::*codemode-tool-namespaces*
             (list (cadr-cli::make-codemode-namespace
                    :name "dev_radius"
                    :aliases '("dev-radius")
                    :description "Radius tools"
                    :instructions "Use list."
                    :tool-names '("list_radius")))))
      (is (search "searchTools() expects a query string"
                  (codemode-signal-text
                   (lambda ()
                     (cadr-cli::codemode-discovery tools "searchTools" (vector 1))))))
      (is (search "searchTools() limit must be a positive integer"
                  (codemode-signal-text
                   (lambda ()
                     (cadr-cli::codemode-discovery
                      tools "searchTools"
                      (cadr-cli::codemode-parse-ordered "[\"widget\",{\"limit\":0}]"))))))
      (is (search "searchTools() namespace must be a string"
                  (codemode-signal-text
                   (lambda ()
                     (cadr-cli::codemode-discovery
                      tools "searchTools"
                      (cadr-cli::codemode-parse-ordered "[\"widget\",{\"namespace\":1}]"))))))
      (let* ((stats (cadr-ai:make-tool
                     :name "stats" :description "Count files"
                     :parameters (cadr-ai::json-object "type" "object")
                     :output-schema (cadr-ai::json-object "type" "object")))
             (bare (cadr-ai:make-tool
                    :name "bare" :description "No schema"
                    :parameters (cadr-ai::json-object "type" "object")))
             (typed (cadr-cli::codemode-discovery
                     (list stats bare) "searchTools" (vector "stats")))
             (plain (cadr-cli::codemode-discovery
                     (list bare) "searchTools" (vector "bare"))))
        (is (search "Promise<{ [key: string]: unknown; }>"
                    (gethash "description" (aref typed 0))))
        (is (not (search "Promise<string>"
                         (gethash "description" (aref typed 0)))))
        (is (search "Promise<unknown>"
                    (gethash "description" (aref plain 0)))))
      (is (= 8 (length (cadr-cli::codemode-discovery
                        tools "searchTools" (vector "widget")))))
      (is (= 8 (length (cadr-cli::codemode-discovery
                        tools "searchTools"
                        (cadr-cli::codemode-parse-ordered
                         "[\"widget\",{\"limit\":null}]")))))
      (is (= 1 (length (cadr-cli::codemode-discovery
                        tools "searchTools"
                        (cadr-cli::codemode-parse-ordered
                         "[\"widget\",{\"limit\":1}]")))))
      (let ((namespace (cadr-cli::codemode-discovery
                        tools "describeNamespace" (vector "dev-radius"))))
        (is (string= "dev_radius" (gethash "name" namespace)))
        (is (string= "Radius tools" (gethash "description" namespace)))
        (is (string= "Use list." (gethash "instructions" namespace)))
        (is (find "list_radius" (gethash "tools" namespace) :test #'string=)))
      (let ((namespace (cadr-cli::codemode-discovery
                        tools "describeNamespace" (vector "mcp__docs"))))
        (is (string= "mcp__docs" (gethash "name" namespace)))
        (is (not (cadr-ai::json-present-p namespace "description")))
        (is (find "mcp__docs__search" (gethash "tools" namespace) :test #'string=)))
      (is (eq :codemode-undefined
              (cadr-cli::codemode-discovery
               tools "describeNamespace" (vector "missing"))))
      (is (search "describeNamespace() expects a namespace name"
                  (codemode-signal-text
                   (lambda ()
                     (cadr-cli::codemode-discovery
                      tools "describeNamespace" (vector))))))
      (is (search "describeTool() expects a tool name"
                  (codemode-signal-text
                   (lambda ()
                     (cadr-cli::codemode-discovery tools "describeTool" #())))))
    (let* ((data "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==")
           (saved (cadr-cli::codemode-save-images
                   (list (list :image data "image/png")
                         (list :image data "image/png"))))
           (label (cadr-ai:text-content-text (first saved))))
      (is (search "[Image saved to " label))
      (is (search "pi-codemode" label))
      (is (search ".png (image/png, " label))
      (is (string= label (cadr-ai:text-content-text (third saved))))
      (is (typep (second saved) 'cadr-ai:image-content))
      (let* ((start (length "[Image saved to "))
             (end (position #\Space label :start start))
             (path (subseq label start end)))
        (is (equalp (cadr-cli::decode-base64-bytes data)
                    (with-open-file (stream path :element-type '(unsigned-byte 8))
                      (let ((bytes (make-array (file-length stream)
                                               :element-type '(unsigned-byte 8))))
                        (read-sequence bytes stream)
                        bytes)))))
    (is (search "No file extension for image type image/bmp"
                (codemode-signal-text
                 (lambda ()
                   (cadr-cli::codemode-save-images
                    (list (list :image "aaaa" "image/bmp")))))))
    (let ((truncated (cadr-cli::codemode-truncate
                      (list (cadr-ai:make-text-content
                             :text (make-string 100000 :initial-element #\a)))
                      10)))
      (is (search "pi-codemode" (cadr-ai:text-content-text (first truncated)))))
    (let ((schema (cadr-ai::json-object "type" "object")))
      (is (equalp (cadr-ai::json-object "files" 2)
                  (cadr-cli::codemode-script-value
                   (cadr-ai:make-tool :name "stats" :output-schema schema)
                   t "disk full" (cadr-ai::json-object "files" 2))))
      (is (string= "Tool \"bare\" failed"
                  (codemode-signal-text
                   (lambda ()
                     (cadr-cli::codemode-script-value
                      (cadr-ai:make-tool :name "bare")
                      t nil nil)))))
      (is (string= "disk full"
                  (codemode-signal-text
                   (lambda ()
                     (cadr-cli::codemode-script-value
                      (cadr-ai:make-tool :name "bash")
                      t "disk full" nil)))))
      (is (string= "hello-text"
                   (cadr-cli::codemode-script-value
                    (cadr-ai:make-tool :name "plain")
                    nil "hello-text" (cadr-ai::json-object "hidden" t)))))))))

(defun codemode-schema (text)
  (cadr-ai::parse-json text))

(test codemode-declarations-match-v140
  ;; packages/codemode/test/declarations.test.ts at v1.4.0.
  (let ((type #'cadr-cli::codemode-schema-type))
    (is (string= "string" (funcall type (codemode-schema "{\"type\":\"string\"}"))))
    (is (string= "number" (funcall type (codemode-schema "{\"type\":\"integer\"}"))))
    (is (string= "string | null" (funcall type (codemode-schema "{\"type\":[\"string\",\"null\"]}"))))
    (is (string= "\"a\"" (funcall type (codemode-schema "{\"const\":\"a\"}"))))
    (is (string= "\"a\" | 1 | null" (funcall type (codemode-schema "{\"enum\":[\"a\",1,null]}"))))
    (is (string= "string | number"
                 (funcall type (codemode-schema "{\"anyOf\":[{\"type\":\"string\"},{\"type\":\"number\"}]}"))))
    (is (string= "unknown" (funcall type (codemode-schema "{\"anyOf\":[{\"type\":\"string\"},{}]}"))))
    (is (string= "(string | number) & 1"
                 (funcall type (codemode-schema "{\"allOf\":[{\"anyOf\":[{\"type\":\"string\"},{\"type\":\"number\"}]},{\"const\":1}]}"))))
    (is (string= "unknown" (funcall type (codemode-schema "{\"$ref\":\"#/defs/x\"}"))))
    (is (string= "unknown" (funcall type t)))
    (is (string= "never" (funcall type nil)))
    (is (string= "{ city: string; \"max-lines\"?: number; }"
                 (funcall type (codemode-schema "{\"type\":\"object\",\"properties\":{\"city\":{\"type\":\"string\"},\"max-lines\":{\"type\":\"number\"}},\"required\":[\"city\"],\"additionalProperties\":false}"))))
    (is (string= "{ [key: string]: number; }"
                 (funcall type (codemode-schema "{\"type\":\"object\",\"additionalProperties\":{\"type\":\"number\"}}"))))
    (is (string= "{ [key: string]: unknown; }"
                 (funcall type (codemode-schema "{\"type\":\"object\"}"))))
    (is (string= "{}"
                 (funcall type (codemode-schema "{\"type\":\"object\",\"properties\":{},\"additionalProperties\":false}"))))
    (is (string= (format nil "{~%  // look up weather for a given list of locations~%  weather: Array<{ location: string; }>;~%}")
                 (funcall type (codemode-schema "{\"type\":\"object\",\"properties\":{\"weather\":{\"type\":\"array\",\"description\":\"look up weather for a given list of locations\",\"items\":{\"type\":\"object\",\"properties\":{\"location\":{\"type\":\"string\"}},\"required\":[\"location\"]}}},\"required\":[\"weather\"]}"))))
    (is (string= (format nil "{~%  // Outer~%  outer?: {~%    // Inner~%    inner?: string;~%  };~%}")
                 (funcall type (codemode-schema "{\"type\":\"object\",\"properties\":{\"outer\":{\"type\":\"object\",\"description\":\"Outer\",\"properties\":{\"inner\":{\"type\":\"string\",\"description\":\"Inner\"}}}}}"))))
    (is (string= (format nil "{~%  // @maxLength 8 @pattern ^[a-z]+$~%  id: string;~%  name?: string;~%  // @maxItems 5 @uniqueItems @deprecated~%  tags?: Array<string>;~%  // Wait in milliseconds.~%  // @integer @minimum 0 @maximum 30000 @default 0~%  timeoutMs?: number;~%}")
                 (funcall type (codemode-schema "{\"type\":\"object\",\"properties\":{\"timeoutMs\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":30000,\"default\":0,\"description\":\"Wait in milliseconds.\"},\"id\":{\"type\":\"string\",\"pattern\":\"^[a-z]+$\",\"maxLength\":8},\"tags\":{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"maxItems\":5,\"uniqueItems\":true,\"deprecated\":true},\"name\":{\"type\":\"string\"}},\"required\":[\"id\"]}"))))
    (is (string= (format nil "{~%  // @integer @minimum 1 @maximum 100~%  limit?: number | null;~%}")
                 (funcall type (codemode-schema "{\"type\":\"object\",\"properties\":{\"limit\":{\"anyOf\":[{\"type\":\"integer\",\"minimum\":1,\"maximum\":100},{\"type\":\"null\"}],\"default\":null,\"title\":\"Limit\"}}}"))))
    (is (string= (format nil "{~%  // @integer @minimum 10 @maximum 20 @format port @format int32~%  n?: number | null;~%}")
                 (funcall type (codemode-schema "{\"type\":\"object\",\"properties\":{\"n\":{\"anyOf\":[{\"type\":\"integer\",\"minimum\":10,\"maximum\":50,\"format\":\"int32\"},{\"type\":\"null\"}],\"minimum\":0,\"maximum\":20,\"format\":\"port\"}}}"))))
    (is (string= (format nil "{~%  // @maximum 8 @exclusiveMaximum 5~%  m?: number | null;~%  // @integer @exclusiveMinimum 0 @maximum 10~%  n?: number;~%}")
                 (funcall type (codemode-schema "{\"type\":\"object\",\"properties\":{\"n\":{\"type\":\"integer\",\"minimum\":0,\"exclusiveMinimum\":true,\"maximum\":10,\"exclusiveMaximum\":false},\"m\":{\"anyOf\":[{\"type\":\"number\",\"maximum\":5,\"exclusiveMaximum\":true},{\"type\":\"null\"}],\"maximum\":8}}}"))))
    (is (string= "{ config?: { [key: string]: unknown; }; }"
                 (funcall type (codemode-schema (format nil "{\"type\":\"object\",\"properties\":{\"config\":{\"type\":\"object\",\"default\":{\"text\":\"~A\"}}}}" (make-string 100 :initial-element #\x))))))
    (is (string= (format nil "{~%  // a~%  // b~%  // @pattern ^[\\u000d\\u000a\\u2028\\u2029]$ @default \"\\u2028\"~%  sep?: string;~%}")
                 (funcall type (let ((sep (cadr-ai::json-object
                                           "type" "string"
                                           "pattern" (format nil "^[~C~C~C~C]$"
                                                             #\Return #\Newline
                                                             (code-char #x2028)
                                                             (code-char #x2029))
                                           "default" (string (code-char #x2028))
                                           "description" (format nil "a~Cb" (code-char #x2028)))))
                                 (cadr-ai::json-object
                                  "type" "object"
                                  "properties" (cadr-ai::json-object "sep" sep))))))
    (let ((budget (codemode-schema "{\"type\":\"object\",\"properties\":{\"n\":{\"type\":\"integer\",\"minimum\":1}}}")))
      (is (string= (format nil "{~%  // @integer @minimum 1~%  n?: number;~%}") (funcall type budget)))
      (is (string= "{ n?: number; }" (funcall type budget :max-chars 20)))
      (is (string= "unknown" (funcall type budget :max-chars 10))))
    (is (string= "{ item: { id: string; parent?: unknown; }; legacy?: \"a\" | \"b\"; remote?: unknown; }"
                 (funcall type (codemode-schema "{\"type\":\"object\",\"properties\":{\"item\":{\"$ref\":\"#/$defs/Item\"},\"legacy\":{\"$ref\":\"#/definitions/Legacy\"},\"remote\":{\"$ref\":\"https://example.com/schema.json\"}},\"required\":[\"item\"],\"$defs\":{\"Item\":{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"},\"parent\":{\"$ref\":\"#/$defs/Item\"}},\"required\":[\"id\"]}},\"definitions\":{\"Legacy\":{\"enum\":[\"a\",\"b\"]}}}"))))
    (is (string= "Array<string>" (funcall type (codemode-schema "{\"type\":\"array\",\"items\":{\"type\":\"string\"}}"))))
    (is (string= "[string, number]" (funcall type (codemode-schema "{\"type\":\"array\",\"prefixItems\":[{\"type\":\"string\"},{\"type\":\"number\"}]}"))))
    (is (string= "unknown[]" (funcall type (codemode-schema "{\"type\":\"array\"}"))))
    (let ((wide (cadr-ai::json-object "type" "object" "properties" (cadr-ai::json-object))))
      (dotimes (index 50)
        (setf (gethash (format nil "field~A" index) (gethash "properties" wide))
              (cadr-ai::json-object "type" "string")))
      (is (string= "unknown" (funcall type wide :max-chars 100)))
      (is (search "field49?: string;" (funcall type wide)))))
  (is (string= "hidden_dynamic_tool(args: { city: string; }): Promise<{ ok: boolean; }>;"
               (cadr-cli::codemode-render-signature
                "hidden-dynamic-tool"
                :input (codemode-schema "{\"type\":\"object\",\"properties\":{\"city\":{\"type\":\"string\"}},\"required\":[\"city\"],\"additionalProperties\":false}")
                :output (codemode-schema "{\"type\":\"object\",\"properties\":{\"ok\":{\"type\":\"boolean\"}},\"required\":[\"ok\"]}"))))
  (is (string= "free(args: unknown): Promise<unknown>;"
               (cadr-cli::codemode-render-signature "free")))
  (is (string= "plain(args: { [key: string]: unknown; }): Promise<{ _meta?: { [key: string]: unknown; }; content: Array<{ [key: string]: unknown; }>; isError?: boolean; }>;"
               (cadr-cli::codemode-render-signature
                "plain"
                :input (codemode-schema "{\"type\":\"object\",\"properties\":{}}")
                :output (codemode-schema "{\"type\":\"object\",\"properties\":{\"content\":{\"type\":\"array\",\"items\":{\"type\":\"object\"}},\"isError\":{\"type\":\"boolean\"},\"_meta\":{\"type\":\"object\"}},\"required\":[\"content\"]}"))))
  (is (string= (format nil "bar~%~%codemode tool declaration:~%```ts~%declare const tools: { foo(args: string): Promise<unknown>; };~%```")
               (cadr-cli::codemode-tool-sample
                "foo" "bar" (codemode-schema "{\"type\":\"string\"}"))))
  (is (string= (format nil "declare const tools: {~%  /**~%   * Read a file.~%   * Second line.~%   */~%  read(args: { path: string; }): Promise<string>;~%  remote_api(args: unknown): Promise<unknown>;~%};~%~%/** Attach it. */~%declare function attach(args: string): Promise<unknown>;")
               (cadr-cli::codemode-render-declarations
                :tools (list (cadr-cli::make-codemode-decl-item
                              :name "read"
                              :description (format nil "Read a file.~%Second line.")
                              :input (codemode-schema "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}},\"required\":[\"path\"]}")
                              :input-p t
                              :output (codemode-schema "{\"type\":\"string\"}")
                              :output-p t)
                             (cadr-cli::make-codemode-decl-item :name "remote-api"))
                :globals (list (cadr-cli::make-codemode-decl-item
                                :name "attach"
                                :description "Attach it."
                                :input (codemode-schema "{\"type\":\"string\"}")
                                :input-p t)))))
  (is (string= (format nil "declare function plain(): void;~%~%declare const models: {~%  /** List models. */~%  list(type: string): Promise<string[]>;~%  get(args: string): Promise<unknown>;~%};")
               (cadr-cli::codemode-render-declarations
                :globals (list (cadr-cli::make-codemode-decl-item
                                :name "models.list"
                                :description "List models."
                                :signature "(type: string): Promise<string[]>")
                               (cadr-cli::make-codemode-decl-item
                                :name "models.get"
                                :input (codemode-schema "{\"type\":\"string\"}")
                                :input-p t)
                               (cadr-cli::make-codemode-decl-item
                                :name "plain"
                                :signature "(): void")))))
  (is (search "/** a *\\/ b */"
              (cadr-cli::codemode-render-declarations
               :tools (list (cadr-cli::make-codemode-decl-item
                             :name "x"
                             :description "a */ b"))))))

(test codemode-classify-usage-and-per-script-limiter-match-v140
  ;; packages/coding-agent/test/suite/agent-session-codemode.test.ts
  ;; "lists models and classifies with catalog auth, ignoring script-supplied fields":
  ;; Promise.all of 6 models.classify calls, at most 4 in flight, usage summed.
  (let* ((usage (cadr-ai:make-usage
                 :input 300 :output 0 :cache-read 0 :cache-write 0 :total 300
                 :cost (cadr-ai:make-cost :input 0d0 :output 0d0 :cache-read 0d0
                                          :cache-write 0d0 :total 0.001d0)))
         (cadr-cli::*codemode-model-runtime*
           (cadr-cli::make-codemode-model-backend
            :models (list (cadr-cli::make-codemode-resolved-model
                           :type "classifier" :provider "scorer" :id "judge"
                           :name "Judge" :api "test-classifier" :input '("text")))
            :classify-function
            (lambda (model context)
              (declare (ignore model context))
              (cadr-ai::make-classifier-result
               :api :test-classifier :provider :scorer :model "judge"
               :answers (cadr-ai::json-object)
               :stop-reason :stop
               :usage usage))))
         (cadr-cli::*codemode-collect-usage* t)
         (cadr-cli::*codemode-script-usage* nil)
         (record (cadr-ai::json-object "name" "models.classify" "status" "running"))
         (arguments "[{\"provider\":\"scorer\",\"id\":\"judge\"},{\"state\":{},\"questions\":{\"approved\":{\"type\":\"bool\",\"instructions\":\"Approval?\",\"criteria\":{\"true\":\"yes\",\"false\":\"no\"}}}}]"))
    (let ((result (cadr-cli::codemode-handle-call
                   nil nil (list :call 1 "global" "models.classify" arguments)
                   (list 0) record)))
      (is (string= "ok" (third result)))
      (is (< (abs (- 0.001d0
                     (coerce (gethash "total"
                                      (gethash "cost"
                                               (gethash "usage"
                                                        (cadr-ai::parse-json
                                                         (second result)))))
                             'double-float)))
             1d-12)))
    (cadr-cli::codemode-handle-call
     nil nil (list :call 2 "global" "models.classify" arguments) (list 0) record)
    (is (string= "scorer/judge" (gethash "args" record)))
    (is (< (abs (- 0.001d0 (coerce (gethash "cost" record) 'double-float))) 1d-12))
    (is (= 600 (cadr-ai:usage-input cadr-cli::*codemode-script-usage*)))
    (is (< (abs (- 0.002d0 (cadr-ai:cost-total
                            (cadr-ai:usage-cost cadr-cli::*codemode-script-usage*))))
           1d-12)))
  (let ((first (cadr-cli::make-codemode-call-limiter))
        (second (cadr-cli::make-codemode-call-limiter))
        (release (sb-thread:make-semaphore :name "codemode-release"))
        (entered (sb-thread:make-semaphore :name "codemode-entered"))
        (finished (sb-thread:make-semaphore :name "codemode-finished"))
        (other (sb-thread:make-semaphore :name "codemode-other"))
        (threads nil))
    (unwind-protect
         (progn
           (loop repeat 4
                 do (push (sb-thread:make-thread
                           (lambda ()
                             (cadr-cli::codemode-limiter-call
                              first
                              (lambda ()
                                (sb-thread:signal-semaphore entered)
                                (sb-thread:wait-on-semaphore release)))))
                          threads))
           (loop repeat 4
                 do (is (not (null (sb-thread:wait-on-semaphore entered :timeout 2)))))
           (push (sb-thread:make-thread
                  (lambda ()
                    (cadr-cli::codemode-limiter-call
                     first
                     (lambda () (sb-thread:signal-semaphore finished)))))
                 threads)
           (push (sb-thread:make-thread
                  (lambda ()
                    (cadr-cli::codemode-limiter-call
                     second
                     (lambda () (sb-thread:signal-semaphore other)))))
                 threads)
           (is (not (null (sb-thread:wait-on-semaphore other :timeout 2))))
           (sleep 0.05)
           (is (= 4 (cadr-cli::codemode-call-limiter-active first)))
           (is (= 1 (length (cadr-cli::codemode-call-limiter-queue first))))
           (is (zerop (cadr-cli::codemode-call-limiter-active second)))
           (is (null (sb-thread:wait-on-semaphore finished :timeout 0.05)))
           (sb-thread:signal-semaphore release)
           (is (not (null (sb-thread:wait-on-semaphore finished :timeout 2)))))
      (loop repeat 4 do (sb-thread:signal-semaphore release))
      (dolist (thread threads)
        (when (sb-thread:thread-alive-p thread)
          (sb-thread:join-thread thread :timeout 2)))))
  ;; The batch has to cross codemode-run-calls. A same-thread limiter-call
  ;; never sees the special-binding gap.
  (let* ((active 0)
         (max-active 0)
         (lock (sb-thread:make-mutex :name "codemode-classify-inflight"))
         (one (cadr-ai:make-usage
               :input 300 :output 0 :cache-read 0 :cache-write 0 :total 300
               :cost (cadr-ai:make-cost :input 0d0 :output 0d0 :cache-read 0d0
                                        :cache-write 0d0 :total 0.001d0)))
         (cadr-cli::*codemode-model-runtime*
           (cadr-cli::make-codemode-model-backend
            :models (list (cadr-cli::make-codemode-resolved-model
                           :type "classifier" :provider "scorer" :id "judge"
                           :name "Judge" :api "test-classifier" :input '("text")))
            :classify-function
            (lambda (model context)
              (declare (ignore model context))
              (sb-thread:with-mutex (lock)
                (incf active)
                (setf max-active (max max-active active)))
              (sleep 0.05)
              (sb-thread:with-mutex (lock)
                (decf active))
              (cadr-ai::make-classifier-result
               :api :test-classifier :provider :scorer :model "judge"
               :answers (cadr-ai::json-object)
               :stop-reason :stop
               :usage one)))))
    (multiple-value-bind (content details terminate structured result-usage is-error)
        (cadr-cli::execute-codemode
         nil "script"
         (cadr-ai::json-object
          "code"
          (concatenate
           'string
           "const questions = { approved: { type: \"bool\", instructions: \"Approval?\","
           " criteria: { true: \"yes\", false: \"no\" } } };"
           "const texts = [\"good\", \"bad\", \"good\", \"bad\", \"good\", \"bad\"];"
           "const results = await Promise.all(texts.map((text) =>"
           " models.classify({ provider: \"scorer\", id: \"judge\", baseUrl: \"https://evil.test\" },"
           " { state: { text }, questions })));"
           "return { cost: results[0].usage.cost.total, n: results.length };"))
         nil nil nil)
      (declare (ignore terminate structured))
      (is (not is-error)
          "parallel classify script failed:~%~A"
          (codemode-result-text content))
      (is (= 4 max-active))
      (is (and result-usage (= 1800 (cadr-ai:usage-input result-usage))))
      (is (and result-usage
               (< (abs (- 0.006d0
                          (cadr-ai:cost-total (cadr-ai:usage-cost result-usage))))
                  1d-9)))
      (let ((rows (and (hash-table-p details) (gethash "calls" details))))
        (is (and (vectorp rows) (= 6 (length rows))))
        (when (vectorp rows)
          (loop for row across rows
                do (is (string= "models.classify" (gethash "name" row)))
                   (is (string= "scorer/judge" (gethash "args" row)))
                   (is (string= "ok" (gethash "status" row)))
                   (is (< (abs (- 0.001d0
                                  (coerce (gethash "cost" row) 'double-float)))
                          1d-12)))))
      (let ((text (codemode-result-text content)))
        (is (search "\"cost\":0.001" text))
        (is (search "\"n\":6" text))))))

(defun codemode-quickjs-contract ()
  (let ((cadr-cli::*codemode-script-tools*
          (list (cadr-ai:make-tool
                 :name "echo"
                 :description "Echo the text"
                 :parameters (cadr-ai::json-object "type" "object")
                 :executor (lambda (id arguments)
                             (declare (ignore id))
                             (gethash "text" arguments)))
                (cadr-ai:make-tool
                 :name "stats"
                 :description "Count files"
                 :parameters (cadr-ai::json-object "type" "object")
                 :output-schema (cadr-ai::json-object "type" "object")
                 :executor (lambda (id arguments)
                             (declare (ignore id arguments))
                             (cadr-ai:make-tool-result-message
                              :content (list (cadr-ai:make-text-content :text "2 files"))
                              :structured-content (cadr-ai::json-object "files" 2)
                              :is-error nil)))
                (cadr-ai:make-tool
                 :name "broken"
                 :description "Fails with a schema"
                 :parameters (cadr-ai::json-object "type" "object")
                 :output-schema (cadr-ai::json-object "type" "object")
                 :executor (lambda (id arguments)
                             (declare (ignore id arguments))
                             (cadr-ai:make-tool-result-message
                              :content (list (cadr-ai:make-text-content :text "disk full"))
                              :structured-content (cadr-ai::json-object "code" "full")
                              :is-error t)))
                (cadr-ai:make-tool
                 :name "plain"
                 :description "Text only"
                 :parameters (cadr-ai::json-object "type" "object")
                 :executor (lambda (id arguments)
                             (declare (ignore id arguments))
                             (cadr-ai:make-tool-result-message
                              :content (list (cadr-ai:make-text-content :text "hello-text"))
                              :structured-content (cadr-ai::json-object "hidden" t)
                              :is-error nil)))
                (cadr-ai:make-tool
                 :name "nope"
                 :description "Fails without a schema"
                 :parameters (cadr-ai::json-object "type" "object")
                 :executor (lambda (id arguments)
                             (declare (ignore id arguments))
                             (cadr-ai:make-tool-result-message
                              :content nil
                              :is-error t)))
                (cadr-ai:make-tool
                 :name "bash"
                 :description "Fails with text"
                 :parameters (cadr-ai::json-object "type" "object")
                 :executor (lambda (id arguments)
                             (declare (ignore id arguments))
                             (cadr-ai:make-tool-result-message
                              :content (list (cadr-ai:make-text-content :text "disk full"))
                              :is-error t)))
                (cadr-ai:make-tool
                 :name "mcp__docs__search"
                 :description "Search the docs"
                 :parameters (cadr-ai::json-object "type" "object"))))
        (cadr-cli::*codemode-tool-namespaces* nil)
        (cadr-cli::*codemode-model-runtime*
          (cadr-cli::make-codemode-model-backend
           :models (list (cadr-cli::make-codemode-resolved-model
                          :type "classifier" :provider "test" :id "c"
                          :name "C" :api "test" :input '("text"))
                         (cadr-cli::make-codemode-resolved-model
                          :type "image" :provider "test" :id "img"
                          :name "Img" :api "test" :input '("text")))
           :classify-function
           (lambda (model context)
             (declare (ignore context))
             (cadr-ai::json-object
              "label" (cadr-cli::codemode-resolved-model-id model)
              "provider" (cadr-cli::codemode-resolved-model-provider model)
              "model" (cadr-cli::codemode-resolved-model-id model)
              "stopReason" "stop"
              "usage" (cadr-ai::json-object
                       "input" 300 "output" 0 "cacheRead" 0 "cacheWrite" 0
                       "totalTokens" 300
                       "cost" (cadr-ai::json-object
                               "input" 0 "output" 0 "cacheRead" 0
                               "cacheWrite" 0 "total" 0.001d0))))
           :images-function
           (lambda (model context)
             (declare (ignore model context))
             (cadr-ai::json-object
              "stopReason" "stop"
              "output" (vector (cadr-ai::json-object
                                "type" "image" "data" "aaaa" "mimeType" "image/png"))))))
        (failures nil))
    (labels ((run-script (code)
               (cadr-cli::execute-codemode
                nil "script"
                (cadr-ai::json-object "code" code)
                nil nil nil))
             (check (name code needle)
               (multiple-value-bind (content details terminate structured usage is-error)
                   (run-script code)
                 (declare (ignore terminate structured))
                 (let* ((text (codemode-result-text content))
                        (at (search "Output:" text))
                        (body (if at (subseq text at) text)))
                   (unless (and (search needle body)
                                (or (search "Script completed" text)
                                    (search "Script failed" text)))
                     (push (format nil "~A: ~A" name text) failures))
                   (list text is-error details usage)))))
      (check "return" "return 1 + 1;" "2")
      (unless (codemode-wasm-call "LAST-COMPILE-CACHED-P")
        (push "first script compiled the quickjs module on the default heap" failures))
      (check "tool" "return await tools.echo({ text: \"hi\" });" "hi")
      (check "store" (format nil "store(\"k\", 7); return load(\"k\");") "7")
      (let* ((report (check "contract"
                                 (concatenate 'string
                                  "const lines = [];"
                                  "async function grab(label, fn) {"
                                  "  try { lines.push(label + \"=\" + JSON.stringify(await fn())); }"
                                  "  catch (e) { lines.push(label + \"=\" + e.message); }"
                                  "}"
                                  "await grab(\"classify\", () => models.classify({ provider: \"test\", id: \"c\" }, { prompt: \"x\" }));"
                                  "await grab(\"images\", () => models.generateImages({ provider: \"test\", id: \"img\" }, { prompt: \"x\" }));"
                                  "await grab(\"search\", () => searchTools(1));"
                                  "await grab(\"ns\", () => describeNamespace(\"mcp__docs\"));"
                                  "await grab(\"missing\", () => describeNamespace(\"no-such\"));"
                                  "await grab(\"decl\", () => describeTool(\"stats\"));"
                                  "await grab(\"stats\", () => tools.stats({}));"
                                  "await grab(\"broken\", () => tools.broken({}));"
                                  "await grab(\"plain\", () => tools.plain({}));"
                                  "await grab(\"failtext\", () => tools.bash({}));"
                                  "try { await tools.nope({}); lines.push(\"nope=unexpected\"); }"
                                  "catch (e) { lines.push(\"nope=\" + e.message); }"
                                  "const ok = await models.classify({ provider: \"test\", id: \"c\" }, { state: {}, questions: { k: { type: \"bool\", instructions: \"q\", criteria: { true: \"y\", false: \"n\" } } } });"
                                  "lines.push(\"ok=\" + ok.label);"
                                  "lines.push(\"cost=\" + ok.usage.cost.total);"
                                  "await models.generateImages({ provider: \"test\", id: \"img\" }, { input: [{ type: \"text\", text: \"x\" }] });"
                                  "return lines.join(\"\\n\");")
                                 "ok=c"))
             (text (first report))
             (details (third report))
             (usage (fourth report)))
        (dolist (needle '("models.classify() context.state must be an object, got undefined."
                          "models.generateImages() context.input must be a non-empty array of blocks, got undefined."
                          "searchTools() expects a query string"
                          "mcp__docs"
                          "mcp__docs__search"
                          "missing=undefined"
                          "\"files\":2"
                          "\"code\":\"full\""
                          "hello-text"
                          "Tool \"nope\" failed"
                          "failtext=disk full"
                          "cost=0.001"
                          "Promise<{ [key: string]: unknown; }>"
                          "Note: models.generateImages() returned 1 image"))
          (unless (search needle text)
            (push (format nil "missing ~A in ~A" needle text) failures)))
        (when (search "Tool \"bash\" failed" text)
          (push (format nil "failure text was prefixed: ~A" text) failures))
        (when (search "hidden" text)
          (push (format nil "plain tool leaked structured content: ~A" text) failures))
        (let ((row (find-if (lambda (call)
                              (and (string= (gethash "name" call) "models.classify")
                                   (string= (gethash "status" call) "ok")))
                            (gethash "calls" details))))
          (unless (and row
                       (string= "test/c" (gethash "args" row))
                       (< (abs (- 0.001d0 (coerce (gethash "cost" row) 'double-float))) 1d-12))
            (push (format nil "classify call row: ~A" details) failures)))
        (unless (and usage
                     (= 300 (cadr-ai:usage-input usage))
                     (< (abs (- 0.001d0 (cadr-ai:cost-total (cadr-ai:usage-cost usage)))) 1d-12))
          (push (format nil "script usage: ~A" usage) failures)))
      (let ((text (first
                   (check "image"
                          "image(\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==\"); return \"shown\";"
                          "[Image saved to "))))
        (unless (and (search "pi-codemode" text) (search ".png (image/png, " text))
          (push (format nil "image label: ~A" text) failures)))
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
  (is (eq t (codemode-quickjs-contract))))
