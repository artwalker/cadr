(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal28-retry-plist (manager sdk-p)
  (if sdk-p
      (cadr-cli:sdk-settings-retry-settings manager)
      (cadr-cli::settings-retry-settings manager)))

(defun goal28-assert-absent-retry-defaults (manager &key sdk-p)
  (let ((settings (goal28-retry-plist manager sdk-p)))
    (is (= 3 (getf settings :max-retries)))
    (is (= 60000 (getf settings :max-retry-delay-ms)))
    (is (null (getf settings :timeout-ms)))))

(test goal28-provider-retry-settings-reach-existing-policy
  (let ((manager (cadr-cli::make-memory-settings-manager)))
    (goal28-assert-absent-retry-defaults manager)
    (is (eq nil
            (cadr-cli::settings-branch-summary-skip-prompt-p
             manager)))
    (is (= 16384
           (cadr-cli::settings-branch-summary-reserve-tokens
            manager)))
    (let* ((chooser-calls 0)
           (summarize-p
             (cadr-cli::branch-summary-tree-summarize-p
              manager
              :chooser
              (lambda (title labels)
                (incf chooser-calls)
                (is (string= title "Summarize branch?"))
                (is (equal
                     labels
                     '("No summary"
                       "Summarize"
                       "Summarize with custom prompt")))
                "Summarize"))))
      (is (= 1 chooser-calls))
      (is (eq t summarize-p))))
  (let ((settings (cadr-cli::make-memory-sdk-settings-manager)))
    (goal28-assert-absent-retry-defaults settings :sdk-p t)
    (is (= 16384
           (cadr-cli:sdk-settings-branch-summary-reserve-tokens
            settings))))
  (let* ((seen nil)
         (manager (cadr-cli::make-memory-settings-manager))
         (stream
           (cadr-cli::stream-function-with-provider-retry
            (lambda (provider model context on-event &rest options)
              (declare (ignore provider model context on-event))
              (setf seen options))
            (lambda ()
              (cadr-cli::settings-retry-settings manager)))))
    (funcall stream nil nil nil nil)
    (is (= 3 (getf seen :max-retries)))
    (is (= 60000 (getf seen :max-retry-delay-ms)))
    (is (null (getf seen :timeout-ms))))
  (with-test-directory (root)
    (let* ((global (merge-pathnames "settings.json" root))
           (_
             (write-text
              global
              "{\"retry\":{\"provider\":{\"maxRetries\":2}}}"))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global))
           (seen nil)
           (stream
             (cadr-cli::stream-function-with-provider-retry
              (lambda (provider model context on-event &rest options)
                (declare (ignore provider model context on-event))
                (setf seen options))
              (lambda ()
                (cadr-cli::settings-retry-settings manager)))))
      (declare (ignore _))
      (is (= 2
             (getf
              (cadr-cli::settings-retry-settings manager)
              :max-retries)))
      (is (= 60000
             (getf
              (cadr-cli::settings-retry-settings manager)
              :max-retry-delay-ms)))
      (is (null
           (getf
            (cadr-cli::settings-retry-settings manager)
            :timeout-ms)))
      (funcall stream nil nil nil nil)
      (is (= 2 (getf seen :max-retries)))
      (is (= 60000 (getf seen :max-retry-delay-ms)))
      (is (null (getf seen :timeout-ms)))))
  (let* ((seen nil)
         (manager
           (cadr-cli::make-memory-sdk-settings-manager
            (args
             "retry"
             (args
              "provider"
              (args "maxRetries" 2)))))
         (stream
           (cadr-cli::stream-function-with-provider-retry
            (lambda (provider model context on-event &rest options)
              (declare (ignore provider model context on-event))
              (setf seen options))
            (lambda ()
              (cadr-cli:sdk-settings-retry-settings manager)))))
    (is (= 2
           (getf
            (cadr-cli:sdk-settings-retry-settings manager)
            :max-retries)))
    (funcall stream nil nil nil nil)
    (is (= 2 (getf seen :max-retries)))
    (is (= 60000 (getf seen :max-retry-delay-ms)))
    (is (null (getf seen :timeout-ms)))))
