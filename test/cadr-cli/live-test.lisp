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

(defun run-isolated-live-cli
    (directory arguments &key oauth-credential)
  (let* ((home
           (merge-pathnames "home/" directory))
         (workspace
           (merge-pathnames "workspace/" directory))
         (isolated-auth
           (merge-pathnames
            ".cadr/auth.json" home))
         (original-home
           (uiop:getenv "HOME")))
    (ensure-directories-exist
     (merge-pathnames "anchor" home))
    (ensure-directories-exist
     (merge-pathnames "anchor" workspace))
    (when oauth-credential
      (ensure-directories-exist isolated-auth)
      (cadr-ai:write-auth-credential
       isolated-auth oauth-credential))
    (unwind-protect
         (progn
           (setf (uiop:getenv "HOME")
                 (namestring home))
           (uiop:with-current-directory
               (workspace)
             (run-live-cli arguments)))
      (setf (uiop:getenv "HOME")
            original-home))))

(test live-deepseek-print-mode-emits-only-final-text
  (if
      (not
       (live-cli-environment-value
        "DEEPSEEK_API_KEY"))
      (skip "DEEPSEEK_API_KEY is not set")
      (with-test-directory (directory)
        (multiple-value-bind
              (status output errors)
            (run-isolated-live-cli
             directory
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
          (is (string= "" errors))))))

(test live-openai-codex-explicit-model-uses-oauth-credential
  (let* ((auth-path
           (cadr-cli:default-auth-path))
         (credential
           (cadr-live-test-support:prepare-openai-codex-credential
            auth-path)))
    (if
        (not
         (typep credential
                'cadr-ai:oauth-credential))
        (skip "OpenAI Codex OAuth is not configured")
        (with-test-directory (directory)
          (let ((auth-contents
                  (uiop:read-file-string
                   auth-path :external-format :utf-8)))
            (multiple-value-bind
                  (status output errors)
                (run-isolated-live-cli
                 directory
                 '("--provider" "openai-codex"
                   "--model" "gpt-5.5"
                   "--print"
                   "--no-session"
                   "--no-tools"
                   "--no-extensions"
                   "--no-skills"
                   "--no-prompt-templates"
                   "--no-context-files"
                   "--system-prompt"
                   "Follow the requested output format exactly and do not call tools."
                   "Reply with exactly OAUTH_EXPLICIT_OK and nothing else.")
                 :oauth-credential credential)
              (is (= 0 status)
                  "CLI stderr: ~A" errors)
              (is (string=
                   "OAUTH_EXPLICIT_OK"
                   (string-trim
                    '(#\Space #\Tab #\Newline #\Return)
                    output)))
              (is (string= "" errors))
              (is
               (string=
                auth-contents
                (uiop:read-file-string
                 auth-path
                 :external-format :utf-8)))))))))
