(in-package #:cadr-evals/tests)

(in-suite cadr-evals-suite)

(defun faux-eval-resolver (handle)
  (lambda (provider model)
    (unless
        (and
         (string= provider "faux")
         (string= model "faux-1"))
      (error "Unexpected faux selection: ~A/~A"
             provider model))
    (values
     (cadr-ai:faux-handle-provider
      handle)
     (cadr-ai:faux-get-model handle)
     (lambda
         (provider selected-model
          context on-event
          &rest options)
       (declare (ignore provider))
       (apply
        #'cadr-ai:faux-stream
        handle selected-model
        context on-event
        options)))))

(defmacro with-faux-eval
    ((handle responses) &body body)
  `(let ((,handle
           (cadr-ai:make-faux-provider)))
     (cadr-ai:faux-set-responses
      ,handle ,responses)
     (let ((cadr-evals::*eval-model-resolver*
             (faux-eval-resolver ,handle)))
       ,@body)))

(test eval-selection-is-explicit-and-never-falls-back
  (let ((cadr-evals::*eval-environment-function*
          (constantly nil))
        (cadr-evals::*eval-model-resolver*
          (lambda (&rest arguments)
            (declare (ignore arguments))
            (error "resolver must not run"))))
    (signals cadr-ai:configuration-error
      (cadr-evals:run-coding-agent-eval
       "hello"))
    (signals cadr-ai:configuration-error
      (cadr-evals:run-coding-agent-eval
       "hello"
       :provider "faux"))))

(test faux-smoke-runs-real-agent-and-normalizes-transcript-usage
  (let ((observed-root nil))
    (with-faux-eval
        (handle
         (list
          (cadr-ai:faux-assistant-message
           "Paris")))
      (let ((cadr-evals::*eval-root-observer*
              (lambda (root)
                (setf observed-root root))))
        (let* ((result
                 (cadr-evals:run-coding-agent-eval
                  "What's the capital of France? Respond with only the city name."
                  :provider "faux"
                  :model "faux-1"
                  :no-tools :all))
               (usage
                 (cadr-evals:eval-result-usage
                  result))
               (events
                 (cadr-evals:eval-result-events
                  result)))
          (is (string=
               "Paris"
               (cadr-evals:eval-result-output
                result)))
          (is (null
               (cadr-evals:eval-result-errors
                result)))
          (is (string=
               "faux"
               (cadr-ai::json-get
                usage "provider")))
          (is (string=
               "faux-1"
               (cadr-ai::json-get
                usage "model")))
          (is (plusp
               (cadr-ai::json-get
                usage "totalTokens")))
          (is (= 2 (length events)))
          (is (equal
               '("user" "assistant")
               (mapcar
                (lambda (event)
                  (cadr-ai::json-get
                   event "role"))
                events)))
          (is (not
               (probe-file
                observed-root))))))))

(test self-extension-eval-writes-reloads-and-invokes-hello-tool
  (let ((extension-text
          (format
           nil
           "(define-tool \"hello\"~%  :description \"Greet one person\"~%  :parameters (cadr-ai::json-object \"type\" \"object\" \"properties\" (cadr-ai::json-object \"name\" (cadr-ai::json-object \"type\" \"string\")) \"required\" (vector \"name\") \"additionalProperties\" nil)~%  :handler (lambda (call-id arguments context)~%             (declare (ignore call-id context))~%             (values (list (cadr-ai:make-text-content :text (format nil \"Hello, ~~A!\" (cadr-ai::json-get arguments \"name\")))) nil)))~%")))
    (with-faux-eval
        (handle
         (list
          (cadr-ai:faux-assistant-message
           (cadr-ai:faux-tool-call
            "write"
            (cadr-ai::json-object
             "path"
             ".cadr/extensions/hello/extension.lisp"
             "content" extension-text)
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
      (let* ((result
               (cadr-evals:run-coding-agent-eval
                (list
                 (cadr-evals:make-eval-prompt-step
                  "Create a hello extension.")
                 (cadr-evals:make-eval-reload-step)
                 (cadr-evals:make-eval-prompt-step
                  "Use the hello tool to greet Bob."))
                :provider "faux"
                :model "faux-1"
                :selector
                (lambda (response agent manager)
                  (declare (ignore manager))
                  (cadr-ai::json-object
                   "response" response
                   "extensionPaths"
                   (cadr-ai::list-json-array
                    (cadr-evals::eval-extension-paths
                     agent))
                   "toolNames"
                   (cadr-ai::list-json-array
                    (mapcar
                     #'cadr-ai:tool-name
                     (cadr-evals::eval-agent-tools
                      agent)))))))
             (output
               (cadr-evals:eval-result-output
                result))
             (events
               (cadr-evals:eval-result-events
                result))
             (hello-result
               (find
                "tool_result"
                events
                :key
                (lambda (event)
                  (cadr-ai::json-get
                   event "type"))
                :test #'string=)))
        (is (string=
             "Hello, Bob!"
             (cadr-ai::json-get
              output "response")))
        (is (= 1
               (length
                (cadr-ai::json-get
                 output
                 "extensionPaths"))))
        (is (find
             "hello"
             (cadr-ai::json-get
              output "toolNames")
             :test #'string=))
        (is (string=
             "hello"
             (cadr-ai::json-get
              hello-result "name")))
        (is (string=
             "Hello, Bob!"
             (cadr-ai::json-get
              hello-result "content")))
        (is (= 2
               (cadr-ai::json-get
                (cadr-evals:eval-result-usage
                 result)
                "toolCalls")))))))
