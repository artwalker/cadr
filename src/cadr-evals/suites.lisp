(in-package #:cadr-evals)

(defun run-smoke-eval
    (&key provider model)
  (run-coding-agent-eval
   "What's the capital of France? Respond with only the city name."
   :provider provider
   :model model
   :no-tools :all))

(defparameter +extension-authoring-eval-name+
  "creates, reloads, and uses a hello extension")

(defun extension-authoring-input ()
  (vector
   (cadr-ai::json-object
    "type" "prompt"
    "content"
    "Create a cadr extension with a hello tool that takes a name and returns a greeting. For example, passing Bob should return `Hello, Bob!`.")
   (cadr-ai::json-object
    "type" "reload")
   (cadr-ai::json-object
    "type" "prompt"
    "content"
    "Use the hello tool to greet Bob. Respond with exactly the tool's greeting and nothing else.")))

(defun required-prompt-boundary
    (prompt marker description
     &key from-end)
  (let ((position
          (if from-end
              (search marker prompt
                      :from-end t)
              (search marker prompt))))
    (unless position
      (error
       "Default cadr system prompt has no ~A section."
       description))
    position))

(defun exclude-guidelines-and-documentation
    (default-prompt)
  (subseq
   default-prompt 0
   (required-prompt-boundary
    default-prompt
    (format nil "~%Guidelines:~%")
    "Guidelines")))

(defun prepare-default-prompt-override
    (default-prompt)
  (subseq
   default-prompt 0
   (required-prompt-boundary
    default-prompt
    (format nil
            "~%Current working directory: ")
    "working-directory"
    :from-end t)))

(defun visible-extension-bundles (manager)
  (loop
    for bundle in
    (cadr-agent::extension-snapshot-bundles
     (cadr-agent::extension-host-current-snapshot
      (cadr-cli::cli-extension-manager-host
       manager)))
    unless
    (cadr-agent::extension-bundle-hidden-p
     bundle)
      collect bundle))

(defun extension-bundle-tool-names (bundle)
  (mapcar
   #'cadr-agent::extension-tool-definition-name
   (cadr-agent::extension-bundle-tools
    bundle)))

(defun extension-source-bundle (bundles)
  (or
   (find-if
    (lambda (bundle)
      (member
       "hello"
       (extension-bundle-tool-names bundle)
       :test #'string=))
    bundles)
   (first bundles)))

(defun read-extension-source (bundles)
  (let* ((bundle
           (extension-source-bundle bundles))
         (path
           (and bundle
                (cadr-agent::extension-bundle-path
                 bundle))))
    (and path
         (probe-file path)
         (uiop:read-file-string
          path :external-format :utf-8))))

(defun extension-error-json (error)
  (cadr-ai::json-object
   "path" ""
   "error" error))

(defun extension-output-selector
    (response agent manager)
  (let* ((bundles
           (visible-extension-bundles manager))
         (prompt
           (cadr-agent::agent-system-prompt
            agent))
         (source
           (read-extension-source bundles))
         (errors
           (loop
             for report in
             (reverse *eval-reload-reports*)
             append
             (copy-list
              (getf report :errors)))))
    (cadr-ai::json-object
     "response" response
     "systemPromptHasGuidelines"
     (not
      (null
       (search
        (format nil "~%Guidelines:~%")
        prompt)))
     "systemPromptHasCadrDocs"
     (not
      (null
       (search
        (format nil
                "~%Cadr documentation (read only")
        prompt)))
     "extensionErrors"
     (coerce
      (mapcar #'extension-error-json errors)
      'vector)
     "loadedExtensions"
     (coerce
      (mapcar
       (lambda (bundle)
         (cadr-ai::json-object
          "path"
          (cadr-agent::extension-bundle-path
           bundle)
          "tools"
          (coerce
           (extension-bundle-tool-names bundle)
           'vector)))
       bundles)
      'vector)
     "extensionSource"
     (or source 'null))))

(defun make-extension-authoring-harness
    (name
     &key provider model
       transform-system-prompt)
  (make-eval-harness
   :name name
   :run
   (lambda (input set-artifact)
     (let ((result
             (run-coding-agent-eval
              input
              :provider provider
              :model model
              :selector
              #'extension-output-selector
              :transform-system-prompt
              transform-system-prompt
              :allow-extension-errors-p t)))
       (maphash
        set-artifact
        (eval-result-artifacts result))
       (let* ((output
                (eval-result-output result))
              (source
                (cadr-ai::json-get
                 output "extensionSource"))
              (run-id
                (cadr-ai::json-get
                 (eval-result-artifacts result)
                 "runId")))
         (when (and (stringp source)
                    (stringp run-id))
           (push
            (record-eval-source-artifact
             run-id
             (make-eval-attachment
              :name "hello.lisp"
              :content-type
              "text/x-common-lisp"
              :body source))
            (eval-result-recorded-artifacts
             result))))
       result))))

(defun extension-authoring-harness-table
    (&key provider model)
  (eval-harness-table
   "cadr extension authoring system prompt"
   :baseline
   (make-extension-authoring-harness
    "system-prompt-without-docs"
    :provider provider
    :model model
    :transform-system-prompt
    #'exclude-guidelines-and-documentation)
   :candidate
   (make-extension-authoring-harness
    "default-system-prompt"
    :provider provider
    :model model
    :transform-system-prompt
    #'prepare-default-prompt-override)))

(defun json-array-items (value)
  (cond
    ((vectorp value) (coerce value 'list))
    ((listp value) value)
    (t nil)))

(defun source-uses-canonical-extension-api-p
    (source)
  (or
   (search "(define-tool" source
           :test #'char-equal)
   (search "(cadr-agent:define-tool"
           source
           :test #'char-equal)))

(defun source-uses-legacy-extension-api-p
    (source)
  (some
   (lambda (needle)
     (search needle source
             :test #'char-equal))
   '("@mariozechner/"
     "@sinclair/typebox"
     "@earendil-works/pi-coding-agent")))

(defun matching-hello-tool-call-p
    (events)
  (some
   (lambda (call)
     (when
         (and
          (string=
           "tool_call"
           (or
            (cadr-ai::json-get call "type")
            ""))
          (string=
           "hello"
           (or
            (cadr-ai::json-get call "name")
            ""))
          (string=
           "Bob"
           (or
            (cadr-ai::json-get
             (cadr-ai::json-get
              call "arguments")
             "name")
            "")))
       (let ((call-id
               (cadr-ai::json-get call "id")))
         (some
          (lambda (result)
            (and
             (string=
              "tool_result"
              (or
               (cadr-ai::json-get
                result "type")
               ""))
             (string=
              call-id
              (or
               (cadr-ai::json-get
                result "toolCallId")
               ""))
             (null
              (cadr-ai::json-get
               result "error"))
             (string=
              "Hello, Bob!"
              (or
               (cadr-ai::json-get
                result "content")
               ""))))
          events))))
   events))

(defun judge-extension-authoring-result
    (result)
  (let* ((output
           (eval-result-output result))
         (source
           (cadr-ai::json-get
            output "extensionSource"))
         (failures nil))
    (cond
      ((not (stringp source))
       (push
        "generated extension source is unavailable"
        failures))
      ((not
        (source-uses-canonical-extension-api-p
         source))
       (push
        "extension does not use the canonical cadr-agent extension API"
        failures))
      ((source-uses-legacy-extension-api-p
        source)
       (push
        "extension uses a legacy TypeScript extension API"
        failures)))
    (when
        (plusp
         (length
          (json-array-items
           (cadr-ai::json-get
            output "extensionErrors"))))
      (push
       "extension loader reported errors"
       failures))
    (unless
        (some
         (lambda (extension)
           (member
            "hello"
            (json-array-items
             (cadr-ai::json-get
              extension "tools"))
            :test #'string=))
         (json-array-items
          (cadr-ai::json-get
           output "loadedExtensions")))
      (push
       "no loaded extension registered the hello tool"
       failures))
    (unless
        (matching-hello-tool-call-p
         (eval-result-events result))
      (push
       "no successful hello({ name: Bob }) call returned Hello, Bob!"
       failures))
    (unless
        (string=
         "Hello, Bob!"
         (or
          (cadr-ai::json-get
           output "response")
          ""))
      (push
       "final response was not exactly Hello, Bob!"
       failures))
    (setf failures (nreverse failures))
    (cadr-ai::json-object
     "score"
     (if failures 0 1)
     "metadata"
     (cadr-ai::json-object
      "rationale"
      (if failures
          (format nil "~{~A~^; ~}"
                  failures)
          "Extension authoring workflow completed.")))))

(defun run-extension-authoring-eval-suite
    (&key provider model reporter)
  (let ((selected-reporter
          (or reporter
              (make-eval-harness-reporter
               :output *error-output*)))
        (outputs nil))
    (dolist
        (row
         (extension-authoring-harness-table
          :provider provider
          :model model))
      (let* ((result
               (run-eval-harness
                (eval-harness-row-harness row)
                (extension-authoring-input)))
             (judge
               (judge-extension-authoring-result
                result))
             (name
               (eval-harness-row-name row))
             (expects-full-prompt
               (string=
                name
                "default-system-prompt"))
             (output
               (eval-result-output result)))
        (unless
            (and
             (eq expects-full-prompt
                 (not
                  (null
                   (cadr-ai::json-get
                    output
                    "systemPromptHasGuidelines"))))
             (eq expects-full-prompt
                 (not
                  (null
                   (cadr-ai::json-get
                    output
                    "systemPromptHasCadrDocs")))))
          (error
           "Extension authoring harness ~A used the wrong system prompt variant"
           name))
        (eval-reporter-record-case
         selected-reporter
         (make-eval-reporter-case
          :id
          (format nil "extension-authoring-~A"
                  name)
          :file "src/extensions.eval.lisp"
          :name +extension-authoring-eval-name+
          :full-name
          (format nil "~A > ~A"
                  name
                  +extension-authoring-eval-name+)
          :status :passed
          :harness-name name
          :score
          (cadr-ai::json-get judge "score")
          :result result))
        (push
         (cadr-ai::json-object
          "harness" name
          "result"
          (eval-result-json result)
          "judge" judge)
         outputs)))
    (eval-reporter-finish
     selected-reporter :completed)
    (coerce (nreverse outputs)
            'vector)))

(defun run-extension-eval
    (&key provider model)
  (run-coding-agent-eval
   (list
    (make-eval-prompt-step
     "Create a cadr extension with a hello tool that takes a name and returns a greeting. For example, passing Bob should return `Hello, Bob!`.")
    (make-eval-reload-step)
    (make-eval-prompt-step
     "Use the hello tool to greet Bob."))
   :provider provider
   :model model
   :selector
   (lambda (response agent manager)
     (declare (ignore manager))
     (cadr-ai::json-object
      "response" response
      "extensionPaths"
      (cadr-ai::list-json-array
       (eval-extension-paths agent))
      "toolDefinitions"
      (cadr-ai::list-json-array
       (mapcar
        (lambda (tool)
          (cadr-ai::json-object
           "name"
           (cadr-ai:tool-name tool)
           "description"
           (cadr-ai:tool-description
            tool)))
        (eval-agent-tools
         agent)))))))
