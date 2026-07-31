(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun live-cli-environment-value (name)
  (let ((value (uiop:getenv name)))
    (and value
         (let ((trimmed
                 (string-trim
                  '(#\Space #\Tab #\Newline #\Return)
                  value)))
           (and (plusp (length trimmed))
                trimmed)))))

(defun live-cli-auth-credential (provider)
  (let ((path (cadr-cli::default-auth-path)))
    (and (probe-file path)
         (handler-case
             (cadr-ai:read-auth-credential
              path provider)
           (condition () nil)))))

(defun run-live-cli (arguments)
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (let ((*standard-input*
            (make-string-input-stream ""))
          (*standard-output* output)
          (*error-output* errors))
      (values
       (cadr-cli::cli-handler
        (cadr-cli::parse-cli-arguments
         arguments))
       (get-output-stream-string output)
       (get-output-stream-string errors)))))

(defun live-default-model-settings ()
  (let ((path
          (merge-pathnames
           ".cadr/settings.json"
           (user-homedir-pathname))))
    (and
     (probe-file path)
     (handler-case
         (let ((object
                 (cadr-ai::parse-json
                  (uiop:read-file-string
                   path :external-format :utf-8))))
           (values
            (cadr-ai::json-get
             object "defaultProvider")
            (cadr-ai::json-get
             object "defaultModel")))
       (condition ()
         (values nil nil))))))

(test live-deepseek-print-mode-emits-only-final-text
  (if
      (not
       (live-cli-environment-value
        "DEEPSEEK_API_KEY"))
      (skip "DEEPSEEK_API_KEY is not set")
      (with-test-directory (directory)
        (uiop:with-current-directory (directory)
          (multiple-value-bind
                (status output errors)
              (run-live-cli
               '("--provider" "deepseek"
                 "--model" "deepseek-v4-flash"
                 "--print"
                 "--no-session"
                 "--no-tools"
                 "--no-extensions"
                 "--no-skills"
                 "--no-prompt-templates"
                 "--no-context-files"
                 "--system-prompt"
                 "Follow the requested output format exactly and do not call tools."
                 "Reply with exactly DEEPSEEK_PRINT_OK and nothing else."))
            (is (= 0 status))
            (is (string=
                 "DEEPSEEK_PRINT_OK"
                 (string-trim
                  '(#\Space #\Tab #\Newline #\Return)
                  output)))
            (is (string= "" errors)))))))

(test live-openai-oauth-login-default-route-is-directly-usable
  (let ((credential
          (live-cli-auth-credential
           :openai-codex))
        (misidentified
          (live-cli-auth-credential
           :openai)))
    (cond
      ((typep credential
              'cadr-ai:oauth-credential)
       (multiple-value-bind
             (provider model)
           (live-default-model-settings)
         (is (string=
              "openai-codex"
              (or provider "")))
         (is (string=
              (cadr-ai:provider-definition-default-model
               (cadr-ai:find-provider-definition
                :openai-codex))
              (or model ""))))
       (with-test-directory (directory)
         (uiop:with-current-directory (directory)
           (multiple-value-bind
                 (status output errors)
               (run-live-cli
                '("--print"
                  "--no-session"
                  "--no-tools"
                  "--no-extensions"
                  "--no-skills"
                  "--no-prompt-templates"
                  "--no-context-files"
                  "--system-prompt"
                  "Follow the requested output format exactly and do not call tools."
                  "Reply with exactly OAUTH_DEFAULT_OK and nothing else."))
             (is (= 0 status))
             (is (string=
                  "OAUTH_DEFAULT_OK"
                  (string-trim
                   '(#\Space #\Tab #\Newline #\Return)
                   output)))
             (is (string= "" errors))))))
      ((typep misidentified
              'cadr-ai:oauth-credential)
       (error
        "OpenAI OAuth is still stored under provider openai; run /login openai with the corrected cadr build"))
      (t
       (skip "OpenAI Codex OAuth is not configured")))))
