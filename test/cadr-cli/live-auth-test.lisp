(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test live-oauth-suite-credential-refreshes-once-and-writes-through-canonical-store
  (with-test-directory (directory)
    (let* ((path (merge-pathnames "auth.json" directory))
           (refreshes 0)
           (accepted-refresh "refresh-0")
           (expires
             (+ (cadr-ai::unix-milliseconds) 3600000)))
      (cadr-ai:write-auth-credential
       path
       (cadr-ai:make-api-key-credential
        :provider :deepseek
        :key "preserve-me"))
      (cadr-ai:write-auth-credential
       path
       (cadr-ai:make-oauth-credential
        :provider :openai-codex
        :access "access-0"
        :refresh "refresh-0"
        :expires 0
        :account-id "account"))
      (flet ((refresh (credential)
               (unless
                   (string=
                    accepted-refresh
                    (cadr-ai:oauth-credential-refresh
                     credential))
                 (error "Refresh token was already rotated"))
               (incf refreshes)
               (setf accepted-refresh "refresh-1")
               (cadr-ai:make-oauth-credential
                :provider :openai-codex
                :access "access-1"
                :refresh accepted-refresh
                :expires expires
                :account-id "account")))
        (let* ((first
                 (uiop:symbol-call
                  :cadr-live-test-support
                  :prepare-openai-codex-credential
                  path #'refresh))
               (second
                 (uiop:symbol-call
                  :cadr-live-test-support
                  :prepare-openai-codex-credential
                  path #'refresh))
               (stored
                 (cadr-ai:read-auth-credential
                  path :openai-codex))
               (unrelated
                 (cadr-ai:read-auth-credential
                  path :deepseek)))
          (is (= 1 refreshes))
          (is (string= "refresh-1"
                       (cadr-ai:oauth-credential-refresh first)))
          (is (string= "refresh-1"
                       (cadr-ai:oauth-credential-refresh second)))
          (is (string= "refresh-1"
                       (cadr-ai:oauth-credential-refresh stored)))
          (is (string= "preserve-me"
                       (cadr-ai:api-key-credential-key unrelated))))))))

(test live-oauth-suite-does-not-rewrite-a-fresh-canonical-credential
  (with-test-directory (directory)
    (let* ((path (merge-pathnames "auth.json" directory))
           (refreshes 0))
      (cadr-ai:write-auth-credential
       path
       (cadr-ai:make-oauth-credential
        :provider :openai-codex
        :access "fresh-access"
        :refresh "fresh-refresh"
        :expires
        (+ (cadr-ai::unix-milliseconds) 3600000)
        :account-id "account"))
      (let ((contents
              (uiop:read-file-string
               path :external-format :utf-8)))
        (flet ((refresh (credential)
                 (declare (ignore credential))
                 (incf refreshes)
                 (error "Fresh credentials must not refresh")))
          (let ((credential
                  (uiop:symbol-call
                   :cadr-live-test-support
                   :prepare-openai-codex-credential
                   path #'refresh)))
            (is (string= "fresh-access"
                         (cadr-ai:oauth-credential-access
                          credential)))
            (is (= 0 refreshes))
            (is
             (string=
              contents
              (uiop:read-file-string
               path :external-format :utf-8)))))))))

(test live-oauth-suite-failed-refresh-keeps-canonical-credential-intact
  (with-test-directory (directory)
    (let ((path (merge-pathnames "auth.json" directory)))
      (cadr-ai:write-auth-credential
       path
       (cadr-ai:make-oauth-credential
        :provider :openai-codex
        :access "old-access"
        :refresh "old-refresh"
        :expires 0
        :account-id "account"))
      (let ((contents
              (uiop:read-file-string
               path :external-format :utf-8)))
        (signals error
          (uiop:symbol-call
           :cadr-live-test-support
           :prepare-openai-codex-credential
           path
           (lambda (credential)
             (declare (ignore credential))
             (error "refresh rejected"))))
        (is
         (string=
          contents
          (uiop:read-file-string
           path :external-format :utf-8)))))))

(test live-oauth-suite-rereads-the-canonical-store-on-every-use
  (with-test-directory (directory)
    (let ((path (merge-pathnames "auth.json" directory)))
      (labels ((write-fresh (access refresh)
                 (cadr-ai:write-auth-credential
                  path
                  (cadr-ai:make-oauth-credential
                   :provider :openai-codex
                   :access access
                   :refresh refresh
                   :expires
                   (+ (cadr-ai::unix-milliseconds) 3600000)
                   :account-id "account")))
               (prepare ()
                 (uiop:symbol-call
                  :cadr-live-test-support
                  :prepare-openai-codex-credential
                  path
                  (lambda (credential)
                    (declare (ignore credential))
                    (error "Fresh credentials must not refresh")))))
        (write-fresh "access-1" "refresh-1")
        (is (string=
             "access-1"
             (cadr-ai:oauth-credential-access
              (prepare))))
        (write-fresh "access-2" "refresh-2")
        (is (string=
             "access-2"
             (cadr-ai:oauth-credential-access
              (prepare))))
        (delete-file path)
        (is (null (prepare)))))))

(defun call-with-environment-value (name value thunk)
  (let ((previous (uiop:getenv name)))
    (unwind-protect
         (progn
           (if value
               (setf (uiop:getenv name) value)
               (sb-posix:unsetenv name))
           (funcall thunk))
      (if previous
          (setf (uiop:getenv name) previous)
          (sb-posix:unsetenv name)))))

(test prepare-opencode-go-credential-accepts-auth-file-or-environment
  (with-test-directory (directory)
    (let ((path (merge-pathnames "auth.json" directory)))
      (call-with-environment-value
       "OPENCODE_API_KEY" nil
       (lambda ()
         (is (null
              (cadr-live-test-support:prepare-opencode-go-credential
               path)))))
      (call-with-environment-value
       "OPENCODE_API_KEY" "env-opencode-key"
       (lambda ()
         (let ((credential
                 (cadr-live-test-support:prepare-opencode-go-credential
                  path)))
           (is (typep credential 'cadr-ai:api-key-credential))
           (is (string=
                "env-opencode-key"
                (cadr-ai:api-key-credential-key credential))))))
      (cadr-ai:write-auth-credential
       path
       (cadr-ai:make-api-key-credential
        :provider :opencode-go
        :key "file-opencode-key"))
      (call-with-environment-value
       "OPENCODE_API_KEY" "env-opencode-key"
       (lambda ()
         (is (string=
              "file-opencode-key"
              (cadr-ai:api-key-credential-key
               (cadr-live-test-support:prepare-opencode-go-credential
                path))))))
      (call-with-environment-value
       "OPENCODE_API_KEY" nil
       (lambda ()
         (is (string=
              "file-opencode-key"
              (cadr-ai:api-key-credential-key
               (cadr-live-test-support:prepare-opencode-go-credential
                path)))))))))

(test live-sse-thinking-content-fields-ignore-usage-and-effort-echo
  (let ((payload
          (cadr-ai::json-object
           "reasoning"
           (cadr-ai::json-object "effort" "medium" "summary" nil)
           "usage"
           (cadr-ai::json-object "reasoning_tokens" 80)
           "delta"
           (cadr-ai::json-object
            "reasoning_content" "step one"
            "content" "answer"))))
    (is (equal
         '("reasoning_content")
         (cadr-live-test-support:live-sse-thinking-content-fields
          payload)))
    (is-true
     (cadr-live-test-support:provider-endpoint-unavailable-p
      "Upstream request failed: Endpoint is unavailable."))
    (is
     (not
      (cadr-live-test-support:provider-endpoint-unavailable-p
       "reasoning_content missing")))))
