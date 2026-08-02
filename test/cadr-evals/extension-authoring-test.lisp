(in-package #:cadr-evals/tests)

(in-suite cadr-evals-suite)

(defparameter +extension-authoring-test-source+
  (format
   nil
   "(define-tool \"hello\"~%  :description \"Greet one person\"~%  :parameters (cadr-ai::json-object \"type\" \"object\" \"properties\" (cadr-ai::json-object \"name\" (cadr-ai::json-object \"type\" \"string\")) \"required\" (vector \"name\") \"additionalProperties\" nil)~%  :handler (lambda (call-id arguments context)~%             (declare (ignore call-id context))~%             (values (list (cadr-ai:make-text-content :text (format nil \"Hello, ~~A!\" (cadr-ai::json-get arguments \"name\")))) nil)))~%"))

(test extension-authoring-prompt-variants-match-baseline-boundaries
  (let ((prompt
          (format nil
                  "head~%Guidelines:~%rules~%Cadr documentation (read only when asked): docs~%Current working directory: /tmp")))
    (is (string=
         "head"
         (cadr-evals::exclude-guidelines-and-documentation
          prompt)))
    (is (string=
         (format nil
                 "head~%Guidelines:~%rules~%Cadr documentation (read only when asked): docs")
         (cadr-evals::prepare-default-prompt-override
          prompt)))
    (signals error
      (cadr-evals::exclude-guidelines-and-documentation
       "no boundary"))
    (signals error
      (cadr-evals::prepare-default-prompt-override
       "no boundary"))))

(test extension-authoring-harness-table-registers-baseline-and-candidate
  (let ((rows
          (cadr-evals:extension-authoring-harness-table
           :provider "faux"
           :model "faux-1")))
    (is (equal
         '("system-prompt-without-docs"
           "default-system-prompt")
         (mapcar
          #'cadr-evals:eval-harness-row-name
          rows)))))

(test extension-authoring-judge-requires-source-api-loader-tool-and-response
  (let* ((output
           (cadr-ai::json-object
            "response" "Hello, Bob!"
            "systemPromptHasGuidelines" t
            "systemPromptHasCadrDocs" t
            "extensionErrors" #()
            "loadedExtensions"
            (vector
             (cadr-ai::json-object
              "path" "/tmp/hello/extension.lisp"
              "tools" #( "hello" )))
            "extensionSource"
            +extension-authoring-test-source+))
         (events
           (list
            (cadr-ai::json-object
             "type" "tool_call"
             "id" "hello-call"
             "name" "hello"
             "arguments"
             (cadr-ai::json-object
              "name" "Bob"))
            (cadr-ai::json-object
             "type" "tool_result"
             "toolCallId" "hello-call"
             "name" "hello"
             "content" "Hello, Bob!")))
         (result
           (cadr-evals::make-eval-result
            :output output
            :events events))
         (passing
           (cadr-evals:judge-extension-authoring-result
            result)))
    (is (= 1
           (cadr-ai::json-get passing "score")))
    (setf (gethash "extensionSource" output)
          "(defun unrelated () nil)")
    (let* ((failing
             (cadr-evals:judge-extension-authoring-result
              result))
           (rationale
             (cadr-ai::json-get
              (cadr-ai::json-get
               failing "metadata")
              "rationale")))
      (is (= 0
             (cadr-ai::json-get failing "score")))
      (is (search "canonical cadr-agent extension API"
                  rationale)))))

(test extension-authoring-harness-captures-source-errors-tools-and-artifact
  (with-faux-eval
      (handle
       (list
        (cadr-ai:faux-assistant-message
         (cadr-ai:faux-tool-call
          "write"
          (cadr-ai::json-object
           "path"
           ".cadr/extensions/hello/extension.lisp"
           "content"
           +extension-authoring-test-source+)
          :id "write-extension")
         :stop-reason :tool-use)
        (cadr-ai:faux-assistant-message
         "Extension created.")
        (cadr-ai:faux-assistant-message
         (cadr-ai:faux-tool-call
          "hello"
          (cadr-ai::json-object
           "name" "Bob")
          :id "hello-call")
         :stop-reason :tool-use)
        (cadr-ai:faux-assistant-message
         "Hello, Bob!")))
    (let* ((harness
             (cadr-evals:make-extension-authoring-harness
              "default-system-prompt"
              :provider "faux"
              :model "faux-1"
              :transform-system-prompt
              #'cadr-evals::prepare-default-prompt-override))
           (result
             (cadr-evals:run-eval-harness
              harness
              (cadr-evals:extension-authoring-input)))
           (output
             (cadr-evals:eval-result-output result))
           (judge
             (cadr-evals:judge-extension-authoring-result
              result)))
      (is (string=
           "Hello, Bob!"
           (cadr-ai::json-get output "response")))
      (is (cadr-ai::json-get
           output "systemPromptHasGuidelines"))
      (is (cadr-ai::json-get
           output "systemPromptHasCadrDocs"))
      (is (= 0
             (length
              (cadr-ai::json-get
               output "extensionErrors"))))
      (is (find
           "hello"
           (cadr-ai::json-get
            output "loadedExtensions")
           :test #'string=
           :key
           (lambda (extension)
             (find
              "hello"
              (cadr-ai::json-get
               extension "tools")
              :test #'string=))))
      (is (string=
           +extension-authoring-test-source+
           (cadr-ai::json-get
            output "extensionSource")))
      (is (= 1
             (length
              (cadr-evals::eval-result-recorded-artifacts
               result))))
      (is (= 1
             (cadr-ai::json-get judge "score"))))))

(defun extension-authoring-faux-responses ()
  (loop
    repeat 2
    append
    (list
     (cadr-ai:faux-assistant-message
      (cadr-ai:faux-tool-call
       "write"
       (cadr-ai::json-object
        "path"
        ".cadr/extensions/hello/extension.lisp"
        "content"
        +extension-authoring-test-source+)
       :id "write-extension")
      :stop-reason :tool-use)
     (cadr-ai:faux-assistant-message
      "Extension created.")
     (cadr-ai:faux-assistant-message
      (cadr-ai:faux-tool-call
       "hello"
       (cadr-ai::json-object
        "name" "Bob")
       :id "hello-call")
      :stop-reason :tool-use)
     (cadr-ai:faux-assistant-message
      "Hello, Bob!"))))

(test extension-authoring-suite-runs-both-rows-through-reporter-lifecycle
  (with-faux-eval
      (handle
       (extension-authoring-faux-responses))
    (let* ((output
             (make-string-output-stream))
           (reporter
             (cadr-evals:make-eval-harness-reporter
              :output output))
           (runs
             (cadr-evals:run-extension-authoring-eval-suite
              :provider "faux"
              :model "faux-1"
              :reporter reporter)))
      (is (= 2 (length runs)))
      (is (= 2
             (length
              (cadr-evals:eval-harness-reporter-observations
               reporter))))
      (is (every
           (lambda (run)
             (= 1
                (cadr-ai::json-get
                 (cadr-ai::json-get
                  run "judge")
                 "score")))
           runs))
      (is (search
           "Eval Comparisons"
           (get-output-stream-string
            output))))))
