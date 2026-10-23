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
      (is (cadr-ai::json-present-p info "input"))
      (is (not (cadr-ai::json-present-p info "headers"))))
    (is (eq :codemode-undefined
            (cadr-cli::codemode-model-call
             "models.getModelOfType"
             (vector "classifier" "typesafe" "missing"))))
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
      (is (search "Tool \"bare\" failed"
                  (codemode-signal-text
                   (lambda ()
                     (cadr-cli::codemode-script-value
                      (cadr-ai:make-tool :name "bare")
                      t nil nil)))))
      (is (string= "hello-text"
                   (cadr-cli::codemode-script-value
                    (cadr-ai:make-tool :name "plain")
                    nil "hello-text" (cadr-ai::json-object "hidden" t)))))))))

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
              "stopReason" "stop"))
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
      (unless (codemode-wasm-call "LAST-COMPILE-CACHED-P")
        (push "first script compiled the quickjs module on the default heap" failures))
      (check "tool" "return await tools.echo({ text: \"hi\" });" "hi")
      (check "store" (format nil "store(\"k\", 7); return load(\"k\");") "7")
      (let ((text (first
                   (check "contract"
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
                           "await grab(\"stats\", () => tools.stats({}));"
                           "await grab(\"broken\", () => tools.broken({}));"
                           "await grab(\"plain\", () => tools.plain({}));"
                           "try { await tools.nope({}); lines.push(\"nope=unexpected\"); }"
                           "catch (e) { lines.push(\"nope=\" + e.message); }"
                           "const ok = await models.classify({ provider: \"test\", id: \"c\" }, { state: {}, questions: { k: { type: \"bool\", instructions: \"q\", criteria: { true: \"y\", false: \"n\" } } } });"
                           "lines.push(\"ok=\" + ok.label);"
                           "await models.generateImages({ provider: \"test\", id: \"img\" }, { input: [{ type: \"text\", text: \"x\" }] });"
                           "return lines.join(\"\\n\");")
                          "ok=c"))))
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
                          "Note: models.generateImages() returned 1 image"))
          (unless (search needle text)
            (push (format nil "missing ~A in ~A" needle text) failures)))
        (when (search "hidden" text)
          (push (format nil "plain tool leaked structured content: ~A" text) failures)))
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
