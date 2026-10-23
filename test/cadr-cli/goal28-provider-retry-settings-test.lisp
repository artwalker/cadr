(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal28-retry-plist (manager sdk-p)
  (if sdk-p
      (cadr-cli:sdk-settings-retry-settings manager)
      (cadr-cli::settings-retry-settings manager)))

(defun goal28-assert-absent-retry-defaults (manager &key sdk-p)
  (let ((settings (goal28-retry-plist manager sdk-p)))
    ;; v1.4.0 getRetrySettings defaults maxRetries to 3.
    ;; getProviderRetrySettings leaves provider maxRetries unset.
    (is (= 3 (getf settings :max-retries)))
    (is (null (getf settings :provider-max-retries)))
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
    ;; provider-retry.ts: options.maxRetries ?? 0. One attempt.
    (is (= 0 (getf seen :max-retries)))
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
      ;; Project provider.maxRetries does not replace agent maxRetries.
      ;; v1.4.0 getRetrySettings still reads top-level retry.maxRetries.
      (is (= 3
             (getf
              (cadr-cli::settings-retry-settings manager)
              :max-retries)))
      (is (= 2
             (getf
              (cadr-cli::settings-retry-settings manager)
              :provider-max-retries)))
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
    (is (= 3
           (getf
            (cadr-cli:sdk-settings-retry-settings manager)
            :max-retries)))
    (is (= 2
           (getf
            (cadr-cli:sdk-settings-retry-settings manager)
            :provider-max-retries)))
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
        (is (= 3 (getf plist :max-retries)))
        (is (= 2 (getf plist :provider-max-retries)))
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
    (is (= 0 (getf seen :max-retries)))
    (is (= 30000 (getf seen :timeout-ms)))
    (is (= 30 (getf seen :read-timeout)))
    (is (= 45000 (getf seen :max-retry-delay-ms)))
    (funcall stream nil nil nil nil
             :timeout-ms 0
             :max-retry-delay-ms 0)
    (is (= 0 (getf seen :timeout-ms)))
    (is (= 0 (getf seen :read-timeout)))
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
    (is (= 30 (getf captured :read-timeout))))
  (let ((captured nil)
        (provider
          (cadr-ai:make-openai-provider :api-key "retry-fields-zero"))
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
                       (args "timeoutMs" 0
                             "maxRetryDelayMs" 0))))))
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
       provider model context nil)
      (is (= 0 (getf captured :connect-timeout)))
      (is (= 0 (getf captured :read-timeout)))
      (setf captured nil)
      (funcall
       (cadr-cli::stream-function-with-provider-retry
        (cadr-cli::stream-function-with-http-idle-timeout
         (lambda (provider model context on-event &rest options)
           (apply #'cadr-ai:stream-chat
                  provider model context on-event options))
         (lambda ()
           (cadr-cli::settings-http-idle-timeout-ms manager)))
        (lambda ()
          (cadr-cli::settings-retry-settings manager)))
       provider model context (lambda (&rest ignored)
                                (declare (ignore ignored)))))
    (is (= 0 (getf captured :connect-timeout)))
    (is (= 0 (getf captured :read-timeout)))))

(defun goal45-retry-chat-model ()
  (cadr-ai:make-model
   :id "gpt-test"
   :provider :openai
   :api :openai-responses
   :base-url "https://api.openai.com"
   :max-tokens 4096))

(defun goal45-retry-chat-context ()
  (cadr-ai:make-context
   :messages
   (list
    (cadr-ai:make-user-message
     :content "hi"
     :timestamp 1))))

(defun goal45-wrapped-complete (manager)
  (cadr-cli::stream-function-with-provider-retry
   (cadr-cli::stream-function-with-http-idle-timeout
    (lambda (provider model context on-event &rest options)
      (declare (ignore on-event))
      (apply #'cadr-ai:complete-chat
             provider model context options))
    (lambda ()
      (cadr-cli::settings-http-idle-timeout-ms manager)))
   (lambda ()
     (cadr-cli::settings-retry-settings manager))))

(defun goal45-count-retryable-timeouts
    (manager &key (request-max-retries nil request-max-retries-p))
  (let ((calls 0)
        (slept nil))
    (let ((cadr-ai:*http-request-function*
            (lambda (url &rest arguments)
              (declare (ignore url arguments))
              (incf calls)
              (error 'cadr-ai:timeout-error
                     :message
                     "HTTP request timed out: Condition CADR-AI::NATIVE-HTTP-TIMEOUT was signalled."
                     :retryable-p t)))
          (cadr-ai::*retry-sleep-function*
            (lambda (seconds)
              (declare (ignore seconds))
              (setf slept t))))
      (declare (special cadr-ai::*retry-sleep-function*))
      (let ((message
              (apply (goal45-wrapped-complete manager)
                     (cadr-ai:make-openai-provider
                      :api-key "retry-count")
                     (goal45-retry-chat-model)
                     (goal45-retry-chat-context)
                     nil
                     (when request-max-retries-p
                       (list :max-retries request-max-retries)))))
        (values calls slept message)))))

(test goal45-provider-max-retries-does-not-change-agent-retries
  ;; v1.4.0 settings-manager.ts getRetrySettings reads
  ;; retry.maxRetries (default 3). getProviderRetrySettings reads
  ;; retry.provider.maxRetries and leaves it undefined.
  ;; provider-retry.ts uses options.maxRetries ?? 0.
  (let ((split
          (cadr-cli::make-memory-settings-manager
           (args "retry"
                 (args "maxRetries" 4
                       "provider"
                       (args "maxRetries" 1)))))
        (sdk
          (cadr-cli::make-memory-sdk-settings-manager
           (args "retry"
                 (args "maxRetries" 4
                       "provider"
                       (args "maxRetries" 1))))))
    (dolist (plist (list (goal28-retry-plist split nil)
                         (goal28-retry-plist sdk t)))
      (is (= 4 (getf plist :max-retries)))
      (is (= 1 (getf plist :provider-max-retries)))))
  (multiple-value-bind (calls slept message)
      (goal45-count-retryable-timeouts
       (cadr-cli::make-memory-settings-manager
        (args "retry"
              (args "maxRetries" 5
                    "provider"
                    (args "timeoutMs" 0
                          "maxRetryDelayMs" 0)))))
    (is (= 1 calls))
    (is (null slept))
    (is (eq :error (cadr-ai:assistant-message-stop-reason message)))
    (is (search "timed out"
                (cadr-ai:assistant-message-error-message message))))
  (multiple-value-bind (calls slept message)
      (goal45-count-retryable-timeouts
       (cadr-cli::make-memory-settings-manager
        (args "retry"
              (args "provider" (args "maxRetries" 2)))))
    (declare (ignore message))
    (is (= 3 calls))
    (is (eq t slept)))
  (multiple-value-bind (calls slept)
      (goal45-count-retryable-timeouts
       (cadr-cli::make-memory-settings-manager
        (args "retry"
              (args "maxRetries" 4
                    "provider" (args "maxRetries" 1)))))
    (declare (ignore slept))
    (is (= 2 calls)))
  (multiple-value-bind (calls slept)
      (goal45-count-retryable-timeouts
       (cadr-cli::make-memory-settings-manager
        (args "retry"
              (args "provider" (args "maxRetries" 2))))
       :request-max-retries 0)
    (declare (ignore slept))
    (is (= 1 calls))))

(test goal45-timeout-zero-sends-one-request-to-a-blackhole
  ;; Advisor repro: timeoutMs 0 and maxRetryDelayMs 0, no provider
  ;; maxRetries. A listener that never accepts must fail one connection
  ;; and must not take the 0.25+0.5+1 backoff of three retries.
  (let* ((listener
           (usocket:socket-listen
            "127.0.0.1" 0
            :reuse-address t
            :element-type '(unsigned-byte 8)))
         (port (usocket:get-local-port listener))
         (calls 0)
         (slept nil)
         (message nil)
         (caught nil)
         (manager
           (cadr-cli::make-memory-settings-manager
            (args "httpIdleTimeoutMs" 300000
                  "retry"
                  (args "maxRetries" 3
                        "provider"
                        (args "timeoutMs" 0
                              "maxRetryDelayMs" 0)))))
         (model
           (cadr-ai:make-model
            :id "gpt-test"
            :provider :openai
            :api :openai-responses
            :base-url (format nil "http://127.0.0.1:~D" port)
            :max-tokens 4096))
         (started (get-internal-real-time))
         (worker
           (sb-thread:make-thread
            (lambda ()
              (let ((cadr-ai:*http-request-function*
                      (lambda (&rest arguments)
                        (incf calls)
                        (apply #'cadr-ai::native-http-request
                               arguments)))
                    (cadr-ai::*retry-sleep-function*
                      (lambda (seconds)
                        (declare (ignore seconds))
                        (setf slept t))))
                (declare (special cadr-ai::*retry-sleep-function*))
                (handler-case
                    (setf message
                          (funcall
                           (goal45-wrapped-complete manager)
                           (cadr-ai:make-openai-provider
                            :api-key "blackhole")
                           model
                           (goal45-retry-chat-context)
                           nil))
                  (error (condition)
                    (setf caught condition)))))
            :name "cadr-test-gap45-blackhole")))
    (unwind-protect
         (progn
           (sb-thread:join-thread worker :timeout 2)
           (is (not (sb-thread:thread-alive-p worker)))
           (is (null caught))
           (is (= 1 calls))
           (is (null slept))
           (is (= 3
                  (getf
                   (cadr-cli::settings-retry-settings manager)
                   :max-retries)))
           (is (null
                (getf
                 (cadr-cli::settings-retry-settings manager)
                 :provider-max-retries)))
           (is (eq :error
                   (cadr-ai:assistant-message-stop-reason message)))
           (is (search "timed out"
                       (cadr-ai:assistant-message-error-message
                        message)))
           (is (< (/ (- (get-internal-real-time) started)
                     internal-time-units-per-second)
                  1)))
      (when (sb-thread:thread-alive-p worker)
        (ignore-errors (sb-thread:terminate-thread worker))
        (ignore-errors (sb-thread:join-thread worker :timeout 1)))
      (ignore-errors (usocket:socket-close listener)))))
