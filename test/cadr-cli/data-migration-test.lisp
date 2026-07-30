(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test interactive-user-data-migration-moves-the-complete-tree
  (with-test-directory (home)
    (let* ((project (merge-pathnames "project/" home))
           (old-directory
             (cadr-cli::legacy-data-directory home))
           (new-directory
             (cadr-cli::data-directory home))
           (old-session-directory
             (merge-pathnames "sessions/" old-directory))
           (extension
             (merge-pathnames
              "extensions/example/extension.lisp"
              old-directory))
           (migrated-extension
             (merge-pathnames
              "extensions/example/extension.lisp"
              new-directory))
           (old-auth
             (merge-pathnames "auth.json" old-directory))
           (output (make-string-output-stream)))
      (ensure-directories-exist
       (merge-pathnames "anchor" project))
      (let ((session
              (cadr-agent:create-session
               :directory old-session-directory
               :cwd project
               :id "legacy-session")))
        (cadr-agent:session-append-message
         session
         (cadr-ai:make-user-message :content "legacy")))
      (write-text extension "(define-command \"legacy\" (lambda (context) context))")
      (cadr-ai:write-auth-credential
       old-auth
       (cadr-ai:make-oauth-credential
        :provider :openai
        :access "access"
        :refresh "refresh"
        :expires 1))
      (sb-posix:chmod old-auth #o644)
      (is (eq
           :migrated
           (cadr-cli::ensure-user-data-migrated
            :home home
            :argv '()
            :input (make-string-input-stream
                    (format nil "yes~%"))
            :output output
            :interactive-p t)))
      (is (null (probe-file old-directory)))
      (is (probe-file migrated-extension))
      (is (= #o600
             (cadr-ai:auth-file-mode
              (merge-pathnames "auth.json" new-directory))))
      (let ((resumed
              (cadr-cli::resolve-cli-session
               :continue-p t
               :cwd project
               :directory
               (merge-pathnames "sessions/" new-directory))))
        (is (string= "legacy-session"
                     (cadr-agent:session-id resumed)))
        (is (string=
             "legacy"
             (cadr-ai:user-message-content
              (first
               (cadr-agent:session-messages resumed))))))
      (is (search "Move it" (get-output-stream-string output))))))

(test noninteractive-user-data-migration-fails-closed
  (with-test-directory (home)
    (let* ((old-directory
             (cadr-cli::legacy-data-directory home))
           (new-directory
             (cadr-cli::data-directory home))
           (output (make-string-output-stream)))
      (ensure-directories-exist
       (merge-pathnames "sessions/anchor" old-directory))
      (handler-case
          (progn
            (cadr-cli::ensure-user-data-migrated
             :home home
             :argv '()
             :input (make-string-input-stream "")
             :output output
             :interactive-p nil)
            (fail "Expected migration refusal"))
        (cadr-ai:configuration-error (condition)
          (is (search
               "mv "
               (cadr-ai:cadr-error-message condition)))))
      (is (probe-file old-directory))
      (is (null (probe-file new-directory))))))

(test yolo-never-authorizes-user-data-migration
  (with-test-directory (home)
    (let ((old-directory
            (cadr-cli::legacy-data-directory home)))
      (ensure-directories-exist
       (merge-pathnames "sessions/anchor" old-directory))
      (signals cadr-ai:configuration-error
        (cadr-cli::ensure-user-data-migrated
         :home home
         :argv '("--yolo")
         :input (make-string-input-stream
                 (format nil "yes~%"))
         :output (make-string-output-stream)
         :interactive-p t))
      (is (probe-file old-directory))
      (is (null
           (probe-file
            (cadr-cli::data-directory home)))))))

(test declined-user-data-migration-keeps-the-old-tree
  (with-test-directory (home)
    (let ((old-directory
            (cadr-cli::legacy-data-directory home)))
      (ensure-directories-exist
       (merge-pathnames "sessions/anchor" old-directory))
      (signals cadr-ai:configuration-error
        (cadr-cli::ensure-user-data-migrated
         :home home
         :argv '()
         :input (make-string-input-stream
                 (format nil "no~%"))
         :output (make-string-output-stream)
         :interactive-p t))
      (is (probe-file old-directory))
      (is (null
           (probe-file
            (cadr-cli::data-directory home)))))))
