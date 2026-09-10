(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal28-assert-sibling-settings-readers (manager)
  (is (eq t (cadr-cli::settings-boolean-value
             manager "compaction" t "enabled")))
  (is (= 20000
         (cadr-cli::settings-compaction-keep-recent-tokens
          manager)))
  (is (= 16384
         (cadr-cli::settings-compaction-reserve-tokens
          manager)))
  (is (= 16384
         (cadr-cli::settings-branch-summary-reserve-tokens
          manager)))
  (is (eq nil
          (cadr-cli::settings-branch-summary-skip-prompt-p
           manager)))
  (is (null (cadr-cli::settings-shell-path manager)))
  (is (null
       (cadr-cli::settings-shell-command-prefix manager)))
  (is (null (cadr-cli::settings-session-dir manager))))

(test goal28-websocket-connect-timeout-ms-reaches-connect-arg
  (let ((manager (cadr-cli::make-memory-settings-manager)))
    (is (null
         (cadr-cli::settings-websocket-connect-timeout-ms
          manager)))
    (is (= 10
           (cadr-ai::websocket-connect-timeout-seconds
            (cadr-cli::settings-websocket-connect-timeout-ms
             manager))))
    (is (= 10
           (cadr-ai::websocket-connect-timeout-seconds 0)))
    (is (= 10
           (cadr-ai::websocket-connect-timeout-seconds -5)))
    (goal28-assert-sibling-settings-readers manager))
  (with-test-directory (root)
    (let* ((global (merge-pathnames "settings.json" root))
           (_
             (write-text
              global
              "{\"websocketConnectTimeoutMs\":15000}"))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global)))
      (declare (ignore _))
      (is (= 15000
             (cadr-cli::settings-websocket-connect-timeout-ms
              manager)))
      (is (= 15
             (cadr-ai::websocket-connect-timeout-seconds
              (cadr-cli::settings-websocket-connect-timeout-ms
               manager))))))
  (with-test-directory (root)
    (let* ((global (merge-pathnames "settings.json" root))
           (_
             (write-text
              global
              "{\"websocketConnectTimeoutMs\":0}"))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global)))
      (declare (ignore _))
      (is (null
           (cadr-cli::settings-websocket-connect-timeout-ms
            manager)))
      (is (= 10
             (cadr-ai::websocket-connect-timeout-seconds
              (cadr-cli::settings-websocket-connect-timeout-ms
               manager))))))
  (let* ((first-seen nil)
         (second-seen nil)
         (first-manager
           (cadr-cli::make-memory-sdk-settings-manager
            (args "websocketConnectTimeoutMs" 15000)))
         (second-manager
           (cadr-cli::make-memory-sdk-settings-manager
            (args "websocketConnectTimeoutMs" 30000)))
         (first-stream
           (cadr-cli::stream-function-with-websocket-connect-timeout
            (lambda (provider model context on-event &rest options)
              (declare (ignore provider model context on-event))
              (setf first-seen
                    (getf options :websocket-connect-timeout-ms)))
            (lambda ()
              (cadr-cli:sdk-settings-websocket-connect-timeout-ms
               first-manager))))
         (second-stream
           (cadr-cli::stream-function-with-websocket-connect-timeout
            (lambda (provider model context on-event &rest options)
              (declare (ignore provider model context on-event))
              (setf second-seen
                    (getf options :websocket-connect-timeout-ms)))
            (lambda ()
              (cadr-cli:sdk-settings-websocket-connect-timeout-ms
               second-manager)))))
    (is (= 15000
           (cadr-cli:sdk-settings-websocket-connect-timeout-ms
            first-manager)))
    (is (= 30000
           (cadr-cli:sdk-settings-websocket-connect-timeout-ms
            second-manager)))
    (funcall first-stream nil nil nil nil)
    (funcall second-stream nil nil nil nil)
    (is (= 15000 first-seen))
    (is (= 30000 second-seen))
    (is (= 15
           (cadr-ai::websocket-connect-timeout-seconds
            first-seen)))
    (is (= 30
           (cadr-ai::websocket-connect-timeout-seconds
            second-seen)))
    (funcall first-stream nil nil nil nil)
    (is (= 15000 first-seen)))
  (let ((settings
          (cadr-cli::make-memory-sdk-settings-manager)))
    (is (null
         (cadr-cli:sdk-settings-websocket-connect-timeout-ms
          settings)))
    (is (= 10
           (cadr-ai::websocket-connect-timeout-seconds
            (cadr-cli:sdk-settings-websocket-connect-timeout-ms
             settings))))
    (is (eq t
            (cadr-cli:sdk-settings-compaction-enabled-p
             settings)))
    (is (= 20000
           (cadr-cli:sdk-settings-compaction-keep-recent-tokens
            settings)))
    (is (= 16384
           (cadr-cli:sdk-settings-branch-summary-reserve-tokens
            settings)))
    (is (null (cadr-cli:sdk-settings-shell-path settings)))
    (is (null (cadr-cli:sdk-settings-session-dir settings)))))
