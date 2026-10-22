(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(test retryable-complete-requests-respect-cap-and-retry-after
  (multiple-value-bind (provider model)
      (provider-case :anthropic)
    (let* ((attempts 0)
           (delays nil)
           (cadr-ai::*retry-base-delay* 0.25)
           (cadr-ai::*retry-sleep-function*
             (lambda (seconds) (push seconds delays))))
      (declare
       (special cadr-ai::*retry-base-delay*
                cadr-ai::*retry-sleep-function*))
      (let ((*http-request-function*
              (lambda (url &rest arguments)
                (declare (ignore url arguments))
                (incf attempts)
                (if (< attempts 3)
                    (error "temporary network failure")
                    (values
                     (read-fixture
                      "test/fixtures/responses/anthropic-complete.json")
                     200 nil)))))
        (let ((message
                (complete-chat provider model (sample-context))))
          (is (eq :stop
                  (assistant-message-stop-reason message)))
          (is (= 3 attempts))
          (is (equal '(0.25 0.5) (nreverse delays))))))
    (let* ((attempts 0)
           (delays nil)
           (cadr-ai::*retry-sleep-function*
             (lambda (seconds) (push seconds delays))))
      (declare (special cadr-ai::*retry-sleep-function*))
      (let ((*http-request-function*
              (lambda (url &rest arguments)
                (declare (ignore url arguments))
                (incf attempts)
                (if (= attempts 1)
                    (values
                     "{\"error\":{\"message\":\"slow down\"}}"
                     429
                     '(("retry-after" . "3")))
                    (values
                     (read-fixture
                      "test/fixtures/responses/anthropic-complete.json")
                     200 nil)))))
        (let ((message
                (complete-chat provider model (sample-context))))
          (is (eq :stop
                  (assistant-message-stop-reason message)))
          (is (= 2 attempts))
          (is (equal '(3) delays)))))
    (let* ((attempts 0)
           (cadr-ai::*retry-sleep-function*
             (lambda (seconds) (declare (ignore seconds)))))
      (declare (special cadr-ai::*retry-sleep-function*))
      (let ((*http-request-function*
              (lambda (url &rest arguments)
                (declare (ignore url arguments))
                (incf attempts)
                (error "still down"))))
        (let ((message
                (complete-chat provider model (sample-context))))
          (is (eq :error
                  (assistant-message-stop-reason message)))
          (is (= 3 attempts)))))))

(test nonretryable-complete-request-is-not-retried
  (multiple-value-bind (provider model)
      (provider-case :anthropic)
    (let* ((attempts 0)
           (cadr-ai::*retry-sleep-function*
             (lambda (seconds)
               (declare (ignore seconds))
               (error "must not sleep"))))
      (declare (special cadr-ai::*retry-sleep-function*))
      (let ((*http-request-function*
              (lambda (url &rest arguments)
                (declare (ignore url arguments))
                (incf attempts)
                (values
                 "{\"error\":{\"message\":\"bad request\"}}"
                 400 nil))))
        (let ((message
                (complete-chat provider model (sample-context))))
          (is (eq :error
                  (assistant-message-stop-reason message)))
          (is (= 1 attempts)))))))

(test native-http-statuses-retain-api-body-and-retry-policy
  (multiple-value-bind (provider model)
      (provider-case :anthropic)
    (let ((attempts 0)
          (headers (make-hash-table :test #'equalp))
          (cadr-ai::*retry-sleep-function*
            (lambda (seconds)
              (declare (ignore seconds))
              (error "400 must not retry"))))
      (declare (special cadr-ai::*retry-sleep-function*))
      (setf (gethash "retry-after" headers) "9")
      (let ((*http-request-function*
              (lambda (url &rest arguments)
                (declare (ignore url arguments))
                (incf attempts)
                (values
                 "{\"error\":{\"message\":\"invalid model\"}}"
                 400
                 headers))))
        (let ((message
                (complete-chat provider model (sample-context))))
          (is (= 1 attempts))
          (is (eq :error
                  (assistant-message-stop-reason message)))
          (is (search "invalid model"
                      (assistant-message-error-message
                       message))))))))

(test terminal-go-usage-limit-429-is-not-retried
  ;; OpenCode Go weekly/monthly wall: pi isTerminalRateLimitError.
  ;; 429 + GoUsageLimitError must not sleep or retry. Error text
  ;; keeps status + type so the TUI is not "Weekly usage limit…" only.
  (multiple-value-bind (provider model)
      (provider-case :openai)
    (let* ((attempts 0)
           (cadr-ai::*retry-sleep-function*
             (lambda (seconds)
               (declare (ignore seconds))
               (error "must not sleep on GoUsageLimitError"))))
      (declare (special cadr-ai::*retry-sleep-function*))
      (let ((*http-request-function*
              (lambda (url &rest arguments)
                (declare (ignore url arguments))
                (incf attempts)
                (values
                 "{\"type\":\"GoUsageLimitError\",\"message\":\"Weekly usage limit reached. Enable available balance.\"}"
                 429
                 '(("retry-after" . "3600"))))))
        (let ((message
                (complete-chat provider model (sample-context))))
          (is (= 1 attempts))
          (is (eq :error
                  (assistant-message-stop-reason message)))
          (let ((text (assistant-message-error-message message)))
            (is (search "429:" text))
            (is (search "GoUsageLimitError" text))))))))

(defparameter *workspace-limit-body*
  "{\"code\":\"subscription_sharing_workplace_individual_usage_limit_exceeded\",\"message\":\"Usage limit reached.\"}")

(defun workspace-limit-body-stream ()
  (flexi-streams:make-in-memory-input-stream
   (babel:string-to-octets *workspace-limit-body* :encoding :utf-8)))

(test chatgpt-business-workspace-limit-is-not-retried-and-names-the-admin
  ;; pi@4a080252f openai-responses.ts stream catch. complete() is
  ;; stream().result(), so the non-stream path carries the same hint.
  ;; Codex responses formats the error without this sentence.
  (let ((hint
          "You've reached your ChatGPT workspace's usage limit. Ask your workspace admin to increase it at admin.openai.com → Workspace → Usage limits."))
    (dolist (entry '(:openai :codex))
      (multiple-value-bind (provider model)
          (provider-case entry)
        (dolist (caller '(complete-chat stream-chat))
          (let* ((attempts 0)
                 (cadr-ai::*retry-sleep-function*
                   (lambda (seconds)
                     (declare (ignore seconds))
                     (error "must not sleep on a ChatGPT Business workspace limit"))))
            (declare (special cadr-ai::*retry-sleep-function*))
            (let* ((*http-request-function*
                     (lambda (url &rest arguments)
                       (declare (ignore url arguments))
                       (incf attempts)
                       (values
                        (if (eq caller 'stream-chat)
                            (workspace-limit-body-stream)
                            *workspace-limit-body*)
                        429
                        nil)))
                   (message
                     (if (eq caller 'complete-chat)
                         (complete-chat provider model (sample-context))
                         (stream-chat
                          provider model (sample-context)
                          (lambda (event) (declare (ignore event)))))))
              (is (= 1 attempts))
              (is (eq :error (assistant-message-stop-reason message)))
              (let ((text (assistant-message-error-message message)))
                (is (search
                     "subscription_sharing_workplace_individual_usage_limit_exceeded"
                     text))
                (if (eq (cadr-ai:model-api model) :openai-responses)
                    (is (search (format nil "~%~A" hint) text))
                    (is (not (search hint text))))))))))))

(test transient-429-without-quota-markers-still-retries
  (multiple-value-bind (provider model)
      (provider-case :anthropic)
    (let* ((attempts 0)
           (delays nil)
           (cadr-ai::*retry-sleep-function*
             (lambda (seconds) (push seconds delays))))
      (declare (special cadr-ai::*retry-sleep-function*))
      (let ((*http-request-function*
              (lambda (url &rest arguments)
                (declare (ignore url arguments))
                (incf attempts)
                (if (= attempts 1)
                    (values
                     "{\"error\":{\"message\":\"slow down\"}}"
                     429
                     '(("retry-after" . "2")))
                    (values
                     (read-fixture
                      "test/fixtures/responses/anthropic-complete.json")
                     200 nil)))))
        (let ((message
                (complete-chat provider model (sample-context))))
          (is (eq :stop
                  (assistant-message-stop-reason message)))
          (is (= 2 attempts))
          (is (equal '(2) delays)))))))

(test stream-retries-before-provider-events-without-duplicating-start
  (multiple-value-bind (provider model)
      (provider-case :anthropic)
    (let* ((attempts 0)
           (events nil)
           (cadr-ai::*retry-sleep-function*
             (lambda (seconds) (declare (ignore seconds)))))
      (declare (special cadr-ai::*retry-sleep-function*))
      (let ((*http-request-function*
              (lambda (url &rest arguments)
                (declare (ignore url arguments))
                (incf attempts)
                (if (= attempts 1)
                    (error "connect reset")
                    (values
                     (flexi-streams:make-in-memory-input-stream
                      (babel:string-to-octets
                       (read-fixture
                        "test/fixtures/sse/anthropic-tool.sse")
                       :encoding :utf-8))
                     200 nil)))))
        (let ((message
                (stream-chat
                 provider model (sample-context)
                 (lambda (event) (push event events)))))
          (is (member
               (assistant-message-stop-reason message)
               '(:stop :tool-use :length)))
          (is (= 2 attempts))
          (is (= 1 (count :start
                          (collect-event-types events)))))))))
