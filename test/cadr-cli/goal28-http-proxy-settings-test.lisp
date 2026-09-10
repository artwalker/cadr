(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal28-http-proxy-resolve (environment http-proxy)
  (cadr-ai:resolve-http-proxy-url-for-target
   "https://api.example.com/v1"
   (cadr-ai::environment-with-http-proxy environment http-proxy)))

(test goal28-http-proxy-settings-reach-existing-resolver
  (let ((manager (cadr-cli::make-memory-settings-manager))
        (env-proxy-url "http://env-proxy.example:8080"))
    (is (null (cadr-cli::settings-http-proxy manager)))
    (is (string=
         "http://env-proxy.example:8080"
         (goal28-http-proxy-resolve
          `(("HTTPS_PROXY" . ,env-proxy-url))
          (cadr-cli::settings-http-proxy manager))))
    (is (null
         (cadr-cli::settings-websocket-connect-timeout-ms
          manager)))
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
  (with-test-directory (root)
    (let* ((global (merge-pathnames "settings.json" root))
           (_
             (write-text
              global
              "{\"httpProxy\":\"http://settings-proxy.example:3128\"}"))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global)))
      (declare (ignore _))
      (is (string=
           "http://settings-proxy.example:3128"
           (cadr-cli::settings-http-proxy manager)))
      (is (string=
           "http://settings-proxy.example:3128"
           (goal28-http-proxy-resolve
            nil
            (cadr-cli::settings-http-proxy manager))))
      (is (string=
           "http://env-proxy.example:8080"
           (goal28-http-proxy-resolve
            '(("HTTPS_PROXY" . "http://env-proxy.example:8080"))
            (cadr-cli::settings-http-proxy manager))))))
  (let* ((first-seen nil)
         (second-seen nil)
         (first-manager
           (cadr-cli::make-memory-sdk-settings-manager
            (args
             "httpProxy"
             "http://first-proxy.example:8080")))
         (second-manager
           (cadr-cli::make-memory-sdk-settings-manager
            (args
             "httpProxy"
             "http://second-proxy.example:8080")))
         (first-stream
           (cadr-cli::stream-function-with-http-proxy
            (lambda (provider model context on-event &rest options)
              (declare (ignore provider model context on-event))
              (setf first-seen (getf options :http-proxy)))
            (lambda ()
              (cadr-cli:sdk-settings-http-proxy first-manager))))
         (second-stream
           (cadr-cli::stream-function-with-http-proxy
            (lambda (provider model context on-event &rest options)
              (declare (ignore provider model context on-event))
              (setf second-seen (getf options :http-proxy)))
            (lambda ()
              (cadr-cli:sdk-settings-http-proxy second-manager)))))
    (is (string=
         "http://first-proxy.example:8080"
         (cadr-cli:sdk-settings-http-proxy first-manager)))
    (is (string=
         "http://second-proxy.example:8080"
         (cadr-cli:sdk-settings-http-proxy second-manager)))
    (funcall first-stream nil nil nil nil)
    (funcall second-stream nil nil nil nil)
    (is (string=
         "http://first-proxy.example:8080"
         first-seen))
    (is (string=
         "http://second-proxy.example:8080"
         second-seen))
    (is (string=
         "http://first-proxy.example:8080"
         (goal28-http-proxy-resolve nil first-seen)))
    (is (string=
         "http://second-proxy.example:8080"
         (goal28-http-proxy-resolve nil second-seen)))
    (funcall first-stream nil nil nil nil)
    (is (string=
         "http://first-proxy.example:8080"
         first-seen)))
  (let ((settings
          (cadr-cli::make-memory-sdk-settings-manager)))
    (is (null (cadr-cli:sdk-settings-http-proxy settings)))
    (is (string=
         "http://env-proxy.example:8080"
         (goal28-http-proxy-resolve
          '(("HTTPS_PROXY" . "http://env-proxy.example:8080"))
          (cadr-cli:sdk-settings-http-proxy settings))))
    (is (null
         (cadr-cli:sdk-settings-websocket-connect-timeout-ms
          settings)))
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
