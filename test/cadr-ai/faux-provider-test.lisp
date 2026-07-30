(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(test faux-provider-queues-factories-and-rewrites-identity
  (let* ((handle
           (cadr-ai:make-faux-provider
            :api :faux-test
            :provider-id :faux-provider
            :model-definitions
            '((:id "fast" :reasoning-p nil)
              (:id "thinker" :reasoning-p t))))
         (runtime (cadr-ai:make-models-runtime)))
    (cadr-ai:models-runtime-set-provider
     runtime (cadr-ai:faux-handle-provider handle))
    (cadr-ai:faux-set-responses
     handle
     (list
      (lambda (context options state model)
        (declare (ignore context options))
        (cadr-ai:faux-assistant-message
         (format nil "~A:~A:~D"
                 (cadr-ai:model-id model)
                 (cadr-ai:model-reasoning-p model)
                 (cadr-ai:faux-state-call-count state))))
      (cadr-ai:faux-assistant-message "second")))
    (let ((first
            (cadr-ai:models-runtime-complete
             runtime
             (cadr-ai:faux-get-model handle "fast")
             (cadr-ai:make-context)))
          (second
            (cadr-ai:models-runtime-complete
             runtime
             (cadr-ai:faux-get-model handle "thinker")
             (cadr-ai:make-context))))
      (is (string=
           "fast:NIL:1"
           (cadr-ai:text-content-text
            (first (cadr-ai:assistant-message-content first)))))
      (is (string=
           "second"
           (cadr-ai:text-content-text
            (first (cadr-ai:assistant-message-content second)))))
      (is (eq :faux-test
              (cadr-ai:assistant-message-api first)))
      (is (eq :faux-provider
              (cadr-ai:assistant-message-provider first)))
      (is (= 0 (cadr-ai:faux-pending-response-count handle))))
    (let ((exhausted
            (cadr-ai:models-runtime-complete
             runtime
             (cadr-ai:faux-get-model handle)
             (cadr-ai:make-context))))
      (is (eq :error
              (cadr-ai:assistant-message-stop-reason exhausted)))
      (is (string=
           "No more faux responses queued"
           (cadr-ai:assistant-message-error-message exhausted))))))

(test faux-provider-streams-fixed-event-order-and-partial-json
  (let ((handle
          (cadr-ai:make-faux-provider
           :token-min 1 :token-max 1)))
    (cadr-ai:faux-set-responses
     handle
     (list
      (cadr-ai:faux-assistant-message
       (list
        (cadr-ai:faux-thinking "go")
        (cadr-ai:faux-text "ok")
        (cadr-ai:faux-tool-call
         "echo"
         (cadr-ai::json-object "text" "hi" "count" 12)
         :id "tool-1"))
       :stop-reason :tool-use)))
    (let ((events nil)
          (deltas nil))
      (cadr-ai:faux-stream
       handle
       (cadr-ai:faux-get-model handle)
       (cadr-ai:make-context)
       (lambda (event)
         (setf events
               (append events
                       (list
                        (cadr-ai:stream-event-type event))))
         (when (eq :tool-call-delta
                   (cadr-ai:stream-event-type event))
           (setf deltas
                 (append deltas
                         (list
                          (cadr-ai:stream-event-delta event)))))))
      (is (equal
           '(:start
             :thinking-start :thinking-delta :thinking-end
             :text-start :text-delta :text-end
             :tool-call-start :tool-call-delta :tool-call-end
             :done)
           events))
      (let ((arguments
              (cadr-ai::parse-json
               (apply #'concatenate 'string deltas))))
        (is (string=
             "hi" (cadr-ai::json-get arguments "text")))
        (is (= 12 (cadr-ai::json-get arguments "count")))))))

(test faux-provider-estimates-usage-and-session-cache
  (let* ((handle (cadr-ai:make-faux-provider))
         (runtime (cadr-ai:make-models-runtime))
         (context
           (cadr-ai:make-context
            :system-prompt "Be concise."
            :messages
            (list
             (cadr-ai:make-user-message
              :content "hello" :timestamp 1)))))
    (cadr-ai:models-runtime-set-provider
     runtime (cadr-ai:faux-handle-provider handle))
    (cadr-ai:faux-set-responses
     handle
     (list
      (cadr-ai:faux-assistant-message "first")
      (cadr-ai:faux-assistant-message "second")))
    (let ((first
            (cadr-ai:models-runtime-complete
             runtime (cadr-ai:faux-get-model handle) context
             :session-id "session-1"
             :cache-retention :short)))
      (is (plusp
           (cadr-ai:usage-input
            (cadr-ai:assistant-message-usage first))))
      (is (plusp
           (cadr-ai:usage-cache-write
            (cadr-ai:assistant-message-usage first))))
      (setf
       (cadr-ai:context-messages context)
       (append
        (cadr-ai:context-messages context)
        (list
         first
         (cadr-ai:make-user-message
          :content "follow up" :timestamp 2))))
      (let ((second
              (cadr-ai:models-runtime-complete
               runtime (cadr-ai:faux-get-model handle) context
               :session-id "session-1"
               :cache-retention :short)))
        (is (plusp
             (cadr-ai:usage-cache-read
              (cadr-ai:assistant-message-usage second))))))))

(test faux-provider-abort-and-invalid-terminal-are-errors
  (let ((handle (cadr-ai:make-faux-provider)))
    (cadr-ai:faux-set-responses
     handle
     (list
      (cadr-ai:faux-assistant-message
       "partial" :stop-reason :pending)
      (cadr-ai:faux-assistant-message "ignored")))
    (let ((pending
            (cadr-ai:faux-complete
             handle (cadr-ai:faux-get-model handle)
             (cadr-ai:make-context))))
      (is (eq :error
              (cadr-ai:assistant-message-stop-reason pending)))
      (is (string=
           "Faux response ended without a stop reason"
           (cadr-ai:assistant-message-error-message pending))))
    (let ((aborted
            (cadr-ai:faux-complete
             handle (cadr-ai:faux-get-model handle)
             (cadr-ai:make-context)
             :abort-p (constantly t))))
      (is (eq :aborted
              (cadr-ai:assistant-message-stop-reason aborted))))))
