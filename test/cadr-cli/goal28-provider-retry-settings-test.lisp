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

(defun goal45-provider-retry-case (json)
  (with-test-directory (root)
    (let* ((global (merge-pathnames "settings.json" root))
           (_ (write-text global json))
           (manager
             (cadr-cli::make-settings-manager :global-path global))
           (sdk
             (cadr-cli::make-sdk-settings-manager
              :global-path global)))
      (declare (ignore _))
      (values manager sdk))))

(test goal45-provider-retry-timeout-ms-and-max-retry-delay-ms
  ;; pi@4a080252f getProviderRetrySettings, settings.md, and
  ;; sdk.ts buildRequestOptions. Names are the JSON fields.
  (let ((manager
          (cadr-cli::make-memory-settings-manager
           (args "retry"
                 (args "provider"
                       (args "timeoutMs" 30000
                             "maxRetryDelayMs" 45000)))))
        (sdk
          (cadr-cli::make-memory-sdk-settings-manager
           (args "retry"
                 (args "provider"
                       (args "timeoutMs" 30000
                             "maxRetryDelayMs" 45000))))))
    (dolist (plist (list (goal28-retry-plist manager nil)
                         (goal28-retry-plist sdk t)))
      (is (= 30000 (getf plist :timeout-ms)))
      (is (= 45000 (getf plist :max-retry-delay-ms)))))
  (let ((manager
          (cadr-cli::make-memory-settings-manager
           (args "retry"
                 (args "timeoutMs" 111
                       "maxRetryDelayMs" 1000))))
        (sdk
          (cadr-cli::make-memory-sdk-settings-manager
           (args "retry"
                 (args "timeoutMs" 111
                       "maxRetryDelayMs" 1000)))))
    (dolist (plist (list (goal28-retry-plist manager nil)
                         (goal28-retry-plist sdk t)))
      (is (null (getf plist :timeout-ms)))
      (is (= 60000 (getf plist :max-retry-delay-ms)))))
  (let ((manager
          (cadr-cli::make-memory-settings-manager
           (args "retry"
                 (args "provider"
                       (args "timeoutMs" 0
                             "maxRetryDelayMs" 0)))))
        (sdk
          (cadr-cli::make-memory-sdk-settings-manager
           (args "retry"
                 (args "provider"
                       (args "timeoutMs" 0
                             "maxRetryDelayMs" 0))))))
    (dolist (plist (list (goal28-retry-plist manager nil)
                         (goal28-retry-plist sdk t)))
      (is (= 0 (getf plist :timeout-ms)))
      (is (= 0 (getf plist :max-retry-delay-ms)))))
  (multiple-value-bind (manager sdk)
      (goal45-provider-retry-case
       "{\"retry\":{\"provider\":{\"timeoutMs\":null,\"maxRetryDelayMs\":null}}}")
    (dolist (plist (list (goal28-retry-plist manager nil)
                         (goal28-retry-plist sdk t)))
      (is (null (getf plist :timeout-ms)))
      (is (= 60000 (getf plist :max-retry-delay-ms)))))
  (multiple-value-bind (manager sdk)
      (goal45-provider-retry-case
       "{\"retry\":{\"maxDelayMs\":1000,\"provider\":{\"timeoutMs\":2500}}}")
    (dolist (pair (list (cons manager nil) (cons sdk t)))
      (let* ((plist (goal28-retry-plist (car pair) (cdr pair)))
             (retry
               (if (cdr pair)
                   (cadr-cli:sdk-settings-value (car pair) "retry")
                   (cadr-cli::settings-value (car pair) "retry"))))
        (is (= 2500 (getf plist :timeout-ms)))
        (is (= 1000 (getf plist :max-retry-delay-ms)))
        (is (not (cadr-ai::json-present-p retry "maxDelayMs"))))))
  (multiple-value-bind (manager sdk)
      (goal45-provider-retry-case
       "{\"retry\":{\"maxDelayMs\":1000,\"provider\":{\"maxRetryDelayMs\":45000}}}")
    (dolist (plist (list (goal28-retry-plist manager nil)
                         (goal28-retry-plist sdk t)))
      (is (= 45000 (getf plist :max-retry-delay-ms)))))
  (multiple-value-bind (manager sdk)
      (goal45-provider-retry-case
       "{\"retry\":{\"maxDelayMs\":1000,\"provider\":{\"maxRetryDelayMs\":null}}}")
    (dolist (plist (list (goal28-retry-plist manager nil)
                         (goal28-retry-plist sdk t)))
      (is (= 1000 (getf plist :max-retry-delay-ms)))))
  (multiple-value-bind (manager sdk)
      (goal45-provider-retry-case
       "{\"retry\":{\"maxDelayMs\":\"1000\"}}")
    (dolist (pair (list (cons manager nil) (cons sdk t)))
      (let* ((plist (goal28-retry-plist (car pair) (cdr pair)))
             (retry
               (if (cdr pair)
                   (cadr-cli:sdk-settings-value (car pair) "retry")
                   (cadr-cli::settings-value (car pair) "retry"))))
        (is (= 60000 (getf plist :max-retry-delay-ms)))
        (is (not (cadr-ai::json-present-p retry "maxDelayMs"))))))
  (with-test-directory (root)
    (let* ((global (merge-pathnames "global.json" root))
           (project (merge-pathnames "project.json" root))
           (_g
             (write-text
              global
              "{\"retry\":{\"provider\":{\"timeoutMs\":30000,\"maxRetryDelayMs\":45000}}}"))
           (_p
             (write-text
              project
              "{\"retry\":{\"provider\":{\"maxRetries\":2}}}"))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global
              :project-path project))
           (sdk
             (cadr-cli::make-sdk-settings-manager
              :global-path global
              :project-path project)))
      (declare (ignore _g _p))
      (dolist (plist (list (goal28-retry-plist manager nil)
                           (goal28-retry-plist sdk t)))
        (is (= 30000 (getf plist :timeout-ms)))
        (is (= 2 (getf plist :max-retries)))
        (is (= 45000 (getf plist :max-retry-delay-ms))))))
  (let* ((seen nil)
         (manager
           (cadr-cli::make-memory-settings-manager
            (args "httpIdleTimeoutMs" 1234
                  "retry"
                  (args "provider"
                        (args "timeoutMs" 30000
                              "maxRetryDelayMs" 45000)))))
         (stream
           (cadr-cli::stream-function-with-provider-retry
            (cadr-cli::stream-function-with-http-idle-timeout
             (lambda (provider model context on-event &rest options)
               (declare (ignore provider model context on-event))
               (setf seen options))
             (lambda ()
               (cadr-cli::settings-http-idle-timeout-ms manager)))
            (lambda ()
              (cadr-cli::settings-retry-settings manager)))))
    (funcall stream nil nil nil nil)
    (is (= 30000 (getf seen :timeout-ms)))
    (is (= 30 (getf seen :read-timeout)))
    (is (= 45000 (getf seen :max-retry-delay-ms)))
    (funcall stream nil nil nil nil
             :timeout-ms 0
             :max-retry-delay-ms 0)
    (is (= 0 (getf seen :timeout-ms)))
    (is (null (getf seen :read-timeout)))
    (is (= 0 (getf seen :max-retry-delay-ms))))
  (let* ((seen nil)
         (manager
           (cadr-cli::make-memory-settings-manager
            (args "httpIdleTimeoutMs" 1234)))
         (stream
           (cadr-cli::stream-function-with-provider-retry
            (cadr-cli::stream-function-with-http-idle-timeout
             (lambda (provider model context on-event &rest options)
               (declare (ignore provider model context on-event))
               (setf seen options))
             (lambda ()
               (cadr-cli::settings-http-idle-timeout-ms manager)))
            (lambda ()
              (cadr-cli::settings-retry-settings manager)))))
    (funcall stream nil nil nil nil)
    (is (= 1234 (getf seen :timeout-ms)))
    (is (= (/ 1234 1000) (getf seen :read-timeout)))
    (is (= 60000 (getf seen :max-retry-delay-ms))))
  (let* ((seen nil)
         (manager
           (cadr-cli::make-memory-settings-manager
            (args "httpIdleTimeoutMs" 0)))
         (stream
           (cadr-cli::stream-function-with-http-idle-timeout
            (lambda (provider model context on-event &rest options)
              (declare (ignore provider model context on-event))
              (setf seen options))
            (lambda ()
              (cadr-cli::settings-http-idle-timeout-ms manager)))))
    (funcall stream nil nil nil nil)
    (is (= 2147483647 (getf seen :timeout-ms)))
    (is (null (getf seen :read-timeout))))
  (let ((captured nil)
        (provider
          (cadr-ai:make-openai-provider :api-key "retry-fields"))
        (model
          (cadr-ai:make-model
           :id "gpt-test"
           :provider :openai
           :api :openai-responses
           :base-url "https://api.openai.com"
           :max-tokens 4096))
        (context
          (cadr-ai:make-context
           :messages
           (list
            (cadr-ai:make-user-message
             :content "hi"
             :timestamp 1))))
        (manager
          (cadr-cli::make-memory-settings-manager
           (args "httpIdleTimeoutMs" 5000
                 "retry"
                 (args "provider"
                       (args "timeoutMs" 30000
                             "maxRetryDelayMs" 45000))))))
    (let ((cadr-ai:*http-request-function*
            (lambda (url &rest arguments)
              (declare (ignore url))
              (setf captured arguments)
              (values "{}" 200 nil))))
      (funcall
       (cadr-cli::stream-function-with-provider-retry
        (cadr-cli::stream-function-with-http-idle-timeout
         (lambda (provider model context on-event &rest options)
           (declare (ignore on-event))
           (apply #'cadr-ai:complete-chat
                  provider model context options))
         (lambda ()
           (cadr-cli::settings-http-idle-timeout-ms manager)))
        (lambda ()
          (cadr-cli::settings-retry-settings manager)))
       provider model context nil))
    (is (= 30 (getf captured :connect-timeout)))
    (is (= 30 (getf captured :read-timeout)))))
