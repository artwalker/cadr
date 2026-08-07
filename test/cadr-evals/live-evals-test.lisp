(in-package #:cadr-evals/live-tests)
(in-suite cadr-evals-live-suite)

(defun live-eval-environment-value (name)
  (let ((value (uiop:getenv name)))
    (and value
         (let ((trimmed
                 (string-trim
                  '(#\Space #\Tab #\Newline #\Return)
                  value)))
           (and (plusp (length trimmed))
                trimmed)))))

(defun make-live-deepseek-eval-resolver
    (api-key)
  (lambda (provider model)
    (unless (string= provider "deepseek")
      (error "Unexpected live DeepSeek provider: ~A"
             provider))
    (multiple-value-bind
          (provider-object model-object)
        (cadr-ai:instantiate-provider
         :deepseek
         :api-key api-key
         :model-id model)
      (values provider-object
              model-object
              #'cadr-ai:stream-chat))))

(defun make-live-kimi-coding-eval-resolver
    (credential)
  (lambda (provider model)
    (unless (string= provider "kimi-coding")
      (error
       "Unexpected live Kimi For Coding provider: ~A"
       provider))
    (multiple-value-bind
          (provider-object model-object)
        (cadr-ai:instantiate-provider
         :kimi-coding
         :api-key
         (cadr-ai:api-key-credential-key
          credential)
         :model-id model)
      (values provider-object
              model-object
              #'cadr-ai:stream-chat))))

(defmacro with-live-deepseek (&body body)
  `(let ((api-key
           (live-eval-environment-value
            "DEEPSEEK_API_KEY")))
     (if api-key
         (let ((cadr-evals::*eval-model-resolver*
                 (make-live-deepseek-eval-resolver
                  api-key)))
           ,@body)
         (skip "DEEPSEEK_API_KEY is not set"))))

(defmacro with-live-kimi-coding
    (&body body)
  `(let ((credential
           (cadr-live-test-support:prepare-kimi-coding-credential)))
     (if
         (typep credential
                'cadr-ai:api-key-credential)
         (let ((cadr-evals::*eval-model-resolver*
                  (make-live-kimi-coding-eval-resolver
                   credential)))
           ,@body)
         (skip "Kimi For Coding API key is not configured"))))

(defun assert-live-smoke-eval
    (result expected-provider)
  (is (string=
       "Paris"
       (string-trim
        '(#\Space #\Tab #\Newline #\Return)
        (cadr-evals:eval-result-output
         result))))
  (is (null
       (cadr-evals:eval-result-errors
        result)))
  (is (string=
       expected-provider
       (cadr-ai::json-get
        (cadr-evals:eval-result-usage
         result)
        "provider")))
  (is (plusp
       (cadr-ai::json-get
        (cadr-evals:eval-result-usage
         result)
        "totalTokens"))))

(test live-deepseek-eval-smoke
  (with-live-deepseek
    (assert-live-smoke-eval
     (cadr-evals:run-smoke-eval
      :provider "deepseek"
      :model "deepseek-v4-flash")
     "deepseek")))

(test live-kimi-coding-eval-smoke-uses-explicit-model-and-api-key
  (with-live-kimi-coding
    (assert-live-smoke-eval
     (cadr-evals:run-smoke-eval
      :provider "kimi-coding"
      :model "kimi-for-coding")
     "kimi-coding")))

(test live-deepseek-self-extension-write-reload-and-invoke
  (with-live-deepseek
    (let* ((extension-text
             "(define-tool \"live-echo\" :description \"Return the supplied value with a live prefix.\" :parameters (cadr-ai::json-object \"type\" \"object\" \"properties\" (cadr-ai::json-object \"value\" (cadr-ai::json-object \"type\" \"string\")) \"required\" (vector \"value\") \"additionalProperties\" nil) :handler (lambda (call-id arguments context) (declare (ignore call-id context)) (values (list (cadr-ai:make-text-content :text (format nil \"live:~A\" (cadr-ai::json-get arguments \"value\")))) nil)))")
           (result
             (cadr-evals:run-coding-agent-eval
              (list
               (cadr-evals:make-eval-prompt-step
                (format
                 nil
                 "Use the write tool exactly once to create .cadr/extensions/live/extension.lisp with exactly this one-line content, then reply exactly WRITTEN: ~A"
                 extension-text))
               (cadr-evals:make-eval-reload-step)
               (cadr-evals:make-eval-prompt-step
                "Call the live-echo tool with value phase7. After it succeeds, reply exactly SELF_EXTENSION_OK."))
              :provider "deepseek"
              :model "deepseek-v4-flash"
              :no-tools
              '("read" "edit" "bash"
                "find" "grep" "ls")
              :selector
              (lambda (response agent manager)
                (declare (ignore manager))
                (cadr-ai::json-object
                 "response" response
                 "extensionPaths"
                 (cadr-ai::list-json-array
                  (cadr-evals::eval-extension-paths
                   agent))
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
                   (cadr-evals::eval-agent-tools
                    agent)))))))
           (output
             (cadr-evals:eval-result-output
              result))
           (events
             (cadr-evals:eval-result-events
              result))
           (hello-result
             (find-if
              (lambda (event)
                (and
                 (string=
                  "tool_result"
                  (or
                   (cadr-ai::json-get
                    event "type")
                   ""))
                 (string=
                  "live-echo"
                  (or
                   (cadr-ai::json-get
                    event "name")
                   ""))))
              events)))
      (is (= 1
             (length
              (cadr-ai::json-get
               output "extensionPaths"))))
      (is (find
           "live-echo"
           (cadr-ai::json-get
            output "toolDefinitions")
           :key
           (lambda (definition)
             (cadr-ai::json-get
              definition "name"))
           :test #'string=))
      (is (not (null hello-result)))
      (is (search
           "live:phase7"
           (or
            (and hello-result
                 (cadr-ai::json-get
                  hello-result "content"))
            "")))
      (is (string=
           "SELF_EXTENSION_OK"
           (string-trim
            '(#\Space #\Tab #\Newline #\Return)
            (cadr-ai::json-get
             output "response"))))
      (is (plusp
           (cadr-ai::json-get
            (cadr-evals:eval-result-usage
             result)
            "toolCalls"))))))

(defun write-live-eval-file (path text)
  (ensure-directories-exist path)
  (with-open-file
      (stream path
       :direction :output
       :if-exists :supersede
       :if-does-not-exist :create
       :external-format :utf-8)
    (write-string text stream)))

(defun live-eval-tool-result-containing
    (events needle)
  (find-if
   (lambda (event)
     (and
      (string=
       "tool_result"
       (or
        (cadr-ai::json-get
         event "type")
        ""))
      (search
       needle
       (or
        (cadr-ai::json-get
         event "content")
        ""))))
   events))

(defparameter +live-repository-test-script+
  "#!/usr/bin/env bash
set -eu
. ./calc.sh
actual=\"$(add 2 3)\"
marker=.cadr-initial-failure-observed
if [ ! -e \"$marker\" ]; then
  : >\"$marker\"
  if [ \"$actual\" = \"5\" ]; then
    echo \"fixture was repaired before its initial failing run\" >&2
    exit 2
  fi
fi
if [ \"$actual\" != \"5\" ]; then
  echo \"expected 5, got $actual\" >&2
  exit 1
fi
echo \"test passed\"
")

(defun run-live-repository-eval ()
  (let ((cadr-evals::*eval-root-observer*
          (lambda (root)
            (let ((workspace
                    (merge-pathnames
                     "workspace/" root)))
              (write-live-eval-file
               (merge-pathnames
                "calc.sh" workspace)
               "#!/usr/bin/env bash\nadd() {\n  printf '%s\\n' \"$(($1 - $2))\"\n}\n")
              (write-live-eval-file
               (merge-pathnames
                "test.sh" workspace)
               +live-repository-test-script+)))))
    (cadr-evals:run-coding-agent-eval
     (list
      (cadr-evals:make-eval-prompt-step
       "Do not inspect or edit any file. Call the bash tool once with command exactly bash ./test.sh. Do not reply before it reports Command exited with code 1; then reply exactly INITIAL_FAILURE_OBSERVED.")
      (cadr-evals:make-eval-prompt-step
       "Read calc.sh, correct only the subtraction to addition with the edit tool, then call bash with command exactly bash ./test.sh. Do not edit test.sh. Do not stop until its output reports test passed, then reply exactly REPAIR_VERIFIED."))
     :provider "deepseek"
     :model "deepseek-v4-flash"
     :no-tools
     '("write" "find" "grep" "ls")
     :selector
     (lambda (response agent manager)
       (declare
        (ignore response manager))
       (let* ((cwd
                (pathname
                 (cadr-agent:session-cwd
                  (cadr-agent:agent-session
                   agent))))
              (test-output
                (uiop:run-program
                 '("bash" "./test.sh")
                 :directory cwd
                 :output :string
                 :error-output :output
                 :ignore-error-status t)))
         (cadr-ai::json-object
          "calc"
          (uiop:read-file-string
           (merge-pathnames
            "calc.sh" cwd)
           :external-format :utf-8)
          "testScript"
          (uiop:read-file-string
           (merge-pathnames
            "test.sh" cwd)
           :external-format :utf-8)
          "testOutput"
          test-output))))))

(defun live-repository-eval-valid-p
    (result)
  (let ((output
          (cadr-evals:eval-result-output
           result))
        (events
          (cadr-evals:eval-result-events
           result)))
    (and
     (search
      "$1 + $2"
      (cadr-ai::json-get
       output "calc"))
     (string=
      +live-repository-test-script+
      (cadr-ai::json-get
       output "testScript"))
     (search
      "test passed"
      (cadr-ai::json-get
       output "testOutput"))
     (live-eval-tool-result-containing
      events "Command exited with code 1")
     (live-eval-tool-result-containing
      events "test passed"))))

(test live-deepseek-repository-fail-fix-pass-loop
  (with-live-deepseek
    (let* ((result
             (loop
               repeat 3
               for candidate =
                 (run-live-repository-eval)
               when
                 (live-repository-eval-valid-p
                  candidate)
                 return candidate
               finally (return candidate)))
             (output
               (cadr-evals:eval-result-output
                result))
             (events
               (cadr-evals:eval-result-events
                result)))
        (is (search
             "$1 + $2"
             (cadr-ai::json-get
              output "calc")))
        (is (string=
             +live-repository-test-script+
             (cadr-ai::json-get
              output "testScript")))
        (is (search
             "test passed"
             (cadr-ai::json-get
              output "testOutput")))
        (is
         (not
          (null
           (live-eval-tool-result-containing
            events "Command exited with code 1"))))
        (is
         (not
          (null
           (live-eval-tool-result-containing
            events "test passed")))))))
