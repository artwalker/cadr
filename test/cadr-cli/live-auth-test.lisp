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
