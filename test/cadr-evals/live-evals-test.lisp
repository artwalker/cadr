(in-package #:cadr-evals/tests)
(in-suite cadr-evals-suite)

(defun live-eval-environment-value (name)
  (let ((value (uiop:getenv name)))
    (and value
         (let ((trimmed
                 (string-trim
                  '(#\Space #\Tab #\Newline #\Return)
                  value)))
           (and (plusp (length trimmed))
                trimmed)))))

(defun live-eval-auth-credential (provider)
  (let ((path (cadr-cli::default-auth-path)))
    (and (probe-file path)
         (handler-case
             (cadr-ai:read-auth-credential
              path provider)
           (condition () nil)))))

(defmacro with-live-deepseek (&body body)
  `(if
       (live-eval-environment-value
        "DEEPSEEK_API_KEY")
       (progn ,@body)
       (skip "DEEPSEEK_API_KEY is not set")))

(defmacro with-live-openai-codex
    (&body body)
  `(let ((credential
           (live-eval-auth-credential
            :openai-codex))
         (misidentified
           (live-eval-auth-credential
            :openai)))
     (cond
       ((typep credential
               'cadr-ai:oauth-credential)
        ,@body)
       ((typep misidentified
               'cadr-ai:oauth-credential)
        (error
         "OpenAI OAuth is still stored under provider openai; run /login openai with the corrected cadr build"))
       (t
        (skip "OpenAI Codex OAuth is not configured")))))

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

(test live-openai-codex-eval-smoke-uses-real-auth-file
  (with-live-openai-codex
    (assert-live-smoke-eval
     (cadr-evals:run-smoke-eval
      :provider "openai-codex"
      :model "gpt-5.5")
     "openai-codex")))

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

(test live-deepseek-repository-fail-fix-pass-loop
  (with-live-deepseek
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
                 "#!/usr/bin/env bash\nset -eu\n. ./calc.sh\nactual=\"$(add 2 3)\"\nif [ \"$actual\" != \"5\" ]; then\n  echo \"expected 5, got $actual\" >&2\n  exit 1\nfi\necho \"test passed\"\n")))))
      (let* ((result
               (cadr-evals:run-coding-agent-eval
                "First run bash ./test.sh and observe its failure. Then inspect the files, fix the add function, rerun bash ./test.sh, and do not stop until it passes."
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
                     "testOutput"
                     test-output)))))
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
        (is (search
             "test passed"
             (cadr-ai::json-get
              output "testOutput")))
        (is
         (not
          (null
           (live-eval-tool-result-containing
            events "Process exited with code 1"))))
        (is
         (not
          (null
           (live-eval-tool-result-containing
            events "Process exited with code 0"))))))))
