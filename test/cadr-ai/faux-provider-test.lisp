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
          (retained-events nil)
          (deltas nil)
          (text-start-snapshot nil))
      (cadr-ai:faux-stream
       handle
       (cadr-ai:faux-get-model handle)
       (cadr-ai:make-context)
       (lambda (event)
         (setf retained-events
               (append retained-events (list event)))
         (setf events
               (append events
                       (list
                        (cadr-ai:stream-event-type event))))
         (when (eq :text-start
                   (cadr-ai:stream-event-type event))
           (setf text-start-snapshot
                 (cadr-ai:text-content-text
                  (first
                   (last
                    (cadr-ai:assistant-message-content
                     (cadr-ai:stream-event-message event)))))))
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
             :tool-call-start)
           (subseq events 0 8)))
      (is (equal '(:tool-call-end :done) (last events 2)))
      (is (= (ceiling
              (length
               (cadr-ai::stringify-json
                (cadr-ai::json-object "text" "hi" "count" 12)))
              4)
             (count :tool-call-delta events)))
      (is (string= "ok" text-start-snapshot))
      (let* ((start
               (find :start retained-events
                     :key #'cadr-ai:stream-event-type))
             (thinking-start
               (find :thinking-start retained-events
                     :key #'cadr-ai:stream-event-type))
             (thinking-delta
               (find :thinking-delta retained-events
                     :key #'cadr-ai:stream-event-type))
             (text-start
               (find :text-start retained-events
                     :key #'cadr-ai:stream-event-type))
             (tool-start
               (find :tool-call-start retained-events
                     :key #'cadr-ai:stream-event-type))
             (tool-end
               (find :tool-call-end retained-events
                     :key #'cadr-ai:stream-event-type)))
        ;; Fixed Pi faux.ts shallow-copies the AssistantMessage shell while
        ;; retaining its content-block objects.  With zero-delay scheduling,
        ;; the producer finishes mutating those blocks before the consumer
        ;; serializes the queued events.  Earlier event shells therefore keep
        ;; their original content array shape but expose each block's final
        ;; value.
        (is (null
             (cadr-ai:assistant-message-content
              (cadr-ai:stream-event-message start))))
        (is (= 1
               (length
                (cadr-ai:assistant-message-content
                 (cadr-ai:stream-event-message thinking-start)))))
        (is (string=
             "go"
             (cadr-ai:thinking-content-thinking
              (first
               (cadr-ai:assistant-message-content
                (cadr-ai:stream-event-message thinking-start))))))
        (is (string=
             "go"
             (cadr-ai:thinking-content-thinking
              (first
               (cadr-ai:assistant-message-content
                (cadr-ai:stream-event-message thinking-delta))))))
        (let ((blocks
                (cadr-ai:assistant-message-content
                 (cadr-ai:stream-event-message text-start))))
          (is (= 2 (length blocks)))
          (is (string= "go"
                       (cadr-ai:thinking-content-thinking (first blocks))))
          (is (string= "ok"
                       (cadr-ai:text-content-text (second blocks)))))
        (is (= 3
               (length
                (cadr-ai:assistant-message-content
                 (cadr-ai:stream-event-message tool-start)))))
        (is (= 2
               (hash-table-count
                (cadr-ai:tool-call-arguments
                 (third
                  (cadr-ai:assistant-message-content
                   (cadr-ai:stream-event-message tool-start)))))))
        (is (= 2
               (hash-table-count
                (cadr-ai:tool-call-arguments
                 (third
                  (cadr-ai:assistant-message-content
                   (cadr-ai:stream-event-message tool-end)))))))
        (is (not (eq (cadr-ai:stream-event-message start)
                     (cadr-ai:stream-event-message thinking-start))))
        (is (not (eq (cadr-ai:stream-event-message thinking-start)
                     (cadr-ai:stream-event-message thinking-delta))))
        (is (eq
             (first
              (cadr-ai:assistant-message-content
               (cadr-ai:stream-event-message thinking-start)))
             (first
              (cadr-ai:assistant-message-content
               (cadr-ai:stream-event-message thinking-delta)))))
        (is (eq
             (cadr-ai:assistant-message-usage
              (cadr-ai:stream-event-message thinking-start))
             (cadr-ai:assistant-message-usage
              (cadr-ai:stream-event-message thinking-delta))))
        (is (not (eq (cadr-ai:stream-event-message thinking-delta)
                     (cadr-ai:stream-event-message text-start)))))
      (let ((arguments
              (cadr-ai::parse-json
               (apply #'concatenate 'string deltas))))
        (is (string=
             "hi" (cadr-ai::json-get arguments "text")))
        (is (= 12 (cadr-ai::json-get arguments "count")))))))

(test faux-provider-stream-chunks-and-aborts-with-finalized-partials
  (let ((handle
          (cadr-ai:make-faux-provider
           :token-min 1 :token-max 1
           :tokens-per-second 1000000))
        (events nil)
        (deltas nil)
        (abort-p nil)
        (text-start-snapshot nil)
        (aborted-message nil))
    (cadr-ai:faux-set-responses
     handle
     (list (cadr-ai:faux-assistant-message "abcdefghij")))
    (setf
     aborted-message
     (cadr-ai:faux-stream
      handle
      (cadr-ai:faux-get-model handle)
      (cadr-ai:make-context)
      (lambda (event)
        (push (cadr-ai:stream-event-type event) events)
        (when (eq :text-start
                  (cadr-ai:stream-event-type event))
          (setf text-start-snapshot
                (cadr-ai:text-content-text
                 (first
                  (cadr-ai:assistant-message-content
                   (cadr-ai:stream-event-message event))))))
        (when (eq :text-delta
                  (cadr-ai:stream-event-type event))
          (push (cadr-ai:stream-event-delta event) deltas)
          (setf abort-p t)))
      :abort-p (lambda () abort-p)))
    (is (equal
         '(:start :text-start :text-delta :error)
         (nreverse events)))
    (is (equal '("abcd") (nreverse deltas)))
    (is (string= "" text-start-snapshot))
    (is (eq :aborted
            (cadr-ai:assistant-message-stop-reason
             aborted-message)))
    (is (string=
         "abcd"
         (cadr-ai:text-content-text
          (first
           (cadr-ai:assistant-message-content
            aborted-message)))))))

(test faux-provider-stream-error-and-empty-queue-match-baseline-lifecycle
  (let ((handle (cadr-ai:make-faux-provider))
        (events nil))
    (cadr-ai:faux-set-responses
     handle
     (list
      (cadr-ai:faux-assistant-message
       nil :stop-reason :error :error-message "terminated")))
    (cadr-ai:faux-stream
     handle (cadr-ai:faux-get-model handle)
     (cadr-ai:make-context)
     (lambda (event)
       (push (cadr-ai:stream-event-type event) events)))
    (is (equal '(:start :error) (nreverse events)))
    (setf events nil)
    (let ((exhausted
            (cadr-ai:faux-stream
             handle (cadr-ai:faux-get-model handle)
             (cadr-ai:make-context
              :system-prompt "usage is still estimated")
             (lambda (event)
               (push (cadr-ai:stream-event-type event) events)))))
      (is (equal '(:error) (nreverse events)))
      (is (plusp
           (cadr-ai:usage-input
            (cadr-ai:assistant-message-usage exhausted)))))))

(test faux-provider-response-factory-exception-is-error-only
  ;; Fixed Pi faux.ts catches response-step exceptions before entering
  ;; streamWithDeltas, so no synthetic start event precedes the error.
  (let ((handle (cadr-ai:make-faux-provider))
        (events nil))
    (cadr-ai:faux-set-responses
     handle
     (list
      (lambda (&rest ignored)
        (declare (ignore ignored))
        (error "boom"))))
    (let ((message
            (cadr-ai:faux-stream
             handle (cadr-ai:faux-get-model handle)
             (cadr-ai:make-context)
             (lambda (event)
               (push event events)))))
      (setf events (nreverse events))
      (is (equal '(:error)
                 (mapcar #'cadr-ai:stream-event-type events)))
      (is (eq :error
              (cadr-ai:assistant-message-stop-reason message)))
      (is (string= "boom"
                   (cadr-ai:assistant-message-error-message message))))))

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

(test faux-provider-usage-counts-the-complete-tool-contract
  ;; pi@4e58f324f providers/faux.ts:197-212 serializes each complete tool
  ;; object.  Counting names alone materially under-reports footer context.
  (let* ((parameters
           (cadr-ai::json-object
            "type" "object"
            "properties"
            (cadr-ai::json-object
             "path" (cadr-ai::json-object "type" "string"))
            "required" (cadr-ai::json-array "path")))
         (tool
           (cadr-ai:make-tool
            :name "read" :description "Read file"
            :parameters parameters))
         (context
           (cadr-ai:make-context
            :system-prompt "S"
            :messages
            (list
             (cadr-ai:make-user-message :content "U" :timestamp 1))
            :tools (list tool)))
         (expected-prompt
           (format
            nil "system:S~%~%user:U~%~%tools:~A"
            (cadr-ai::stringify-json
             (cadr-ai::list-json-array
              (list
               (cadr-ai::json-object
                "name" "read"
                "description" "Read file"
                "parameters" parameters))))))
         (handle (cadr-ai:make-faux-provider)))
    (cadr-ai:faux-set-responses
     handle (list (cadr-ai:faux-assistant-message "ok")))
    (let* ((message
             (cadr-ai:faux-complete
              handle (cadr-ai:faux-get-model handle) context))
           (usage (cadr-ai:assistant-message-usage message)))
      (is
       (= (cadr-ai:estimate-text-tokens expected-prompt)
          (cadr-ai:usage-input usage))))))

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
