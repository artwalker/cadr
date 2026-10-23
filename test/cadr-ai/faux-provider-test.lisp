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
  ;; pi@4a080252f providers/faux.ts:197-212 serializes each complete tool
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
         (handle (cadr-ai:make-faux-provider)))
    (cadr-ai:faux-set-responses
     handle (list (cadr-ai:faux-assistant-message "ok")))
    (let* ((message
             (cadr-ai:faux-complete
              handle (cadr-ai:faux-get-model handle) context))
           (usage (cadr-ai:assistant-message-usage message)))
      ;; v1.4.0 faux.ts withUsageEstimate on normalizeContext of this
      ;; prompt and tool. Node createFauxCore at pi-ai 1.4.0: input 39,
      ;; output 1. Math.ceil(utf16Length / 4), not chars*2/7.
      (is (= 39 (cadr-ai:usage-input usage)))
      (is (= 1 (cadr-ai:usage-output usage)))
      (is (= 0 (cadr-ai:usage-cache-read usage)))
      (is (= 0 (cadr-ai:usage-cache-write usage))))))

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

(defun gap66-read-tool ()
  (cadr-ai:make-tool
   :name "read"
   :description "Read file"
   :parameters
   (cadr-ai::json-object
    "type" "object"
    "properties"
    (cadr-ai::json-object
     "path" (cadr-ai::json-object "type" "string"))
    "required" (cadr-ai::json-array "path"))))

(defun gap66-usage (message)
  (cadr-ai:assistant-message-usage message))

(test faux-provider-estimates-tokens-by-utf16-quarters
  ;; Numbers are v1.4.0 createFauxCore().stream().result().usage
  ;; (packages/ai/src/providers/faux.ts withUsageEstimate).
  (let ((handle (cadr-ai:make-faux-provider))
        (tool (gap66-read-tool)))
    (cadr-ai:faux-set-responses
     handle
     (list
      (cadr-ai:faux-assistant-message "first")
      (cadr-ai:faux-assistant-message "abcd")
      (cadr-ai:faux-assistant-message "🙂🙂🙂🙂")
      (cadr-ai:faux-assistant-message "x")
      (cadr-ai:faux-assistant-message "")
      (cadr-ai:faux-assistant-message "ok")))
    (let ((hello
            (cadr-ai:faux-complete
             handle (cadr-ai:faux-get-model handle)
             (cadr-ai:make-context
              :messages
              (list (cadr-ai:make-user-message
                     :content "hello" :timestamp 1))))))
      (is (= 3 (cadr-ai:usage-input (gap66-usage hello))))
      (is (= 2 (cadr-ai:usage-output (gap66-usage hello))))
      (is (= 5 (cadr-ai:usage-total (gap66-usage hello)))))
    (let ((abcd
            (cadr-ai:faux-complete
             handle (cadr-ai:faux-get-model handle)
             (cadr-ai:make-context
              :messages
              (list (cadr-ai:make-user-message
                     :content "abcd" :timestamp 1))))))
      (is (= 3 (cadr-ai:usage-input (gap66-usage abcd))))
      (is (= 1 (cadr-ai:usage-output (gap66-usage abcd)))))
    (let ((emoji
            (cadr-ai:faux-complete
             handle (cadr-ai:faux-get-model handle)
             (cadr-ai:make-context
              :messages
              (list (cadr-ai:make-user-message
                     :content "hi" :timestamp 1))))))
      (is (= 2 (cadr-ai:usage-input (gap66-usage emoji))))
      (is (= 2 (cadr-ai:usage-output (gap66-usage emoji)))))
    (let ((image
            (cadr-ai:faux-complete
             handle (cadr-ai:faux-get-model handle)
             (cadr-ai:make-context
              :messages
              (list
               (cadr-ai:make-user-message
                :content
                (list (cadr-ai:make-image-content
                       :mime-type "image/png" :data "abcd"))
                :timestamp 1))))))
      (is (= 6 (cadr-ai:usage-input (gap66-usage image))))
      (is (= 1 (cadr-ai:usage-output (gap66-usage image)))))
    (let ((removed
            (cadr-ai:faux-complete
             handle (cadr-ai:faux-get-model handle)
             (cadr-ai:make-context
              :messages
              (list
               (cadr-ai:make-system-message
                :content "P"
                :tools-removed
                (list (cadr-ai:make-tool-reference :name "bash"))
                :tools-added (list tool)
                :timestamp 1))))))
      (is (= 43 (cadr-ai:usage-input (gap66-usage removed))))
      (is (= 0 (cadr-ai:usage-output (gap66-usage removed)))))
    (let ((sections
            (cadr-ai:faux-complete
             handle (cadr-ai:faux-get-model handle)
             (cadr-ai:make-context
              :messages
              (list
               (cadr-ai:make-system-message
                :content ""
                :sections
                '(("preamble" . "Be concise.")
                  ("cwd" . "<cwd>
/tmp
</cwd>"))
                :tools-added (list tool)
                :timestamp 1)
               (cadr-ai:make-user-message
                :content "U" :timestamp 2))))))
      (is (= 46 (cadr-ai:usage-input (gap66-usage sections))))
      (is (= 1 (cadr-ai:usage-output (gap66-usage sections)))))
    (let ((preset (cadr-ai:faux-assistant-message "z")))
      (setf (cadr-ai:assistant-message-usage preset)
            (cadr-ai:make-usage :input 999 :output 999))
      (cadr-ai:faux-set-responses handle (list preset))
      (let ((empty
              (cadr-ai:faux-complete
               handle (cadr-ai:faux-get-model handle)
               (cadr-ai:make-context :messages nil))))
        (is (= 0 (cadr-ai:usage-input (gap66-usage empty))))
        (is (= 1 (cadr-ai:usage-output (gap66-usage empty))))))))

(test faux-provider-session-cache-splits-the-shared-prefix
  ;; v1.4.0 createFauxCore, sessionId session-1, cacheRetention short.
  ;; First usage is input 43, output 8, cacheRead 0, cacheWrite 43.
  ;; Second is input 19, output 2, cacheRead 43, cacheWrite 20.
  (let* ((handle (cadr-ai:make-faux-provider))
         (tool (gap66-read-tool))
         (context
           (cadr-ai:make-context
            :messages
            (list
             (cadr-ai:make-system-message
              :content "Be concise."
              :tools-added (list tool)
              :timestamp 1)
             (cadr-ai:make-user-message
              :content "hello" :timestamp 2)))))
    (cadr-ai:faux-set-responses
     handle
     (list
      (cadr-ai:faux-assistant-message
       (list
        (cadr-ai:faux-thinking "think")
        (cadr-ai:faux-text "hi")
        (cadr-ai:faux-tool-call
         "grep" (cadr-ai::json-object "pattern" "a") :id "t1")))
      (cadr-ai:faux-assistant-message "second")))
    (let ((first
            (cadr-ai:faux-complete
             handle (cadr-ai:faux-get-model handle) context
             :session-id "session-1"
             :cache-retention :short)))
      (is (= 43 (cadr-ai:usage-input (gap66-usage first))))
      (is (= 8 (cadr-ai:usage-output (gap66-usage first))))
      (is (= 0 (cadr-ai:usage-cache-read (gap66-usage first))))
      (is (= 43 (cadr-ai:usage-cache-write (gap66-usage first))))
      (is (= 94 (cadr-ai:usage-total (gap66-usage first))))
      (setf (cadr-ai:context-messages context)
            (append
             (cadr-ai:context-messages context)
             (list
              first
              (cadr-ai:make-tool-result-message
               :tool-call-id "t1"
               :tool-name "grep"
               :content (list (cadr-ai:faux-text "hit"))
               :is-error nil
               :timestamp 3)
              (cadr-ai:make-user-message
               :content "follow up" :timestamp 4))))
      (let ((second
              (cadr-ai:faux-complete
               handle (cadr-ai:faux-get-model handle) context
               :session-id "session-1"
               :cache-retention :short)))
        (is (= 19 (cadr-ai:usage-input (gap66-usage second))))
        (is (= 2 (cadr-ai:usage-output (gap66-usage second))))
        (is (= 43 (cadr-ai:usage-cache-read (gap66-usage second))))
        (is (= 20 (cadr-ai:usage-cache-write (gap66-usage second)))))
      (cadr-ai:faux-set-responses
       handle (list (cadr-ai:faux-assistant-message "z")))
      (let ((uncached
              (cadr-ai:faux-complete
               handle (cadr-ai:faux-get-model handle)
               (cadr-ai:make-context
                :messages
                (list
                 (cadr-ai:make-system-message
                  :content "Be concise."
                  :tools-added (list tool)
                  :timestamp 1)
                 (cadr-ai:make-user-message
                  :content "hello" :timestamp 2)))
               :session-id "s"
               :cache-retention :none)))
        (is (= 43 (cadr-ai:usage-input (gap66-usage uncached))))
        (is (= 1 (cadr-ai:usage-output (gap66-usage uncached))))
        (is (= 0 (cadr-ai:usage-cache-read (gap66-usage uncached))))
        (is (= 0 (cadr-ai:usage-cache-write (gap66-usage uncached))))))))

(test faux-provider-counts-prompt-text-and-constrained-sampling
  ;; node, pi-ai 1.4.0 toToolDeclaration JSON plus
  ;; getSystemMessageText of the render-diff prompt
  ;; (preamble, blank line, <cwd> section) and user "plain prompt":
  ;; prompt length 302, ceil(302/4) = 76. Output is
  ;; ceil("Fixed plain response.".length/4) = 6. Same session and
  ;; cacheRetention short writes the whole prompt on the first call.
  ;; Empty content is 57; the prompt without constrainedSampling is 60.
  (let* ((handle (cadr-ai:make-faux-provider))
         (tool
           (cadr-ai:make-tool
            :name "read"
            :description "Read file"
            :parameters
            (cadr-ai::json-object
             "type" "object"
             "properties"
             (cadr-ai::json-object
              "path" (cadr-ai::json-object "type" "string"))
             "required" (cadr-ai::json-array "path"))
            :constrained-sampling
            '(:type :json-schema :strict :prefer)))
         (prompt
           (format nil "Render differential fixed system prompt.~%~%<cwd>~%/tmp/pi00/workspace~%</cwd>"))
         (context
           (cadr-ai:make-context
            :messages
            (list
             (cadr-ai:make-system-message
              :content prompt
              :tools-added (list tool)
              :timestamp 1)
             (cadr-ai:make-user-message
              :content "plain prompt" :timestamp 2)))))
    (cadr-ai:faux-set-responses
     handle
     (list (cadr-ai:faux-assistant-message "Fixed plain response.")))
    (let* ((message
             (cadr-ai:faux-complete
              handle (cadr-ai:faux-get-model handle) context
              :session-id "render-diff"
              :cache-retention :short))
           (usage (cadr-ai:assistant-message-usage message))
           (encoded
             (cadr-ai::stringify-json
              (cadr-ai::faux-tool-json-object tool))))
      (is (search "\"constrainedSampling\":{" encoded))
      (is (search "\"type\":\"json_schema\"" encoded))
      (is (search "\"strict\":\"prefer\"" encoded))
      (is (= 76 (cadr-ai:usage-input usage)))
      (is (= 6 (cadr-ai:usage-output usage)))
      (is (= 0 (cadr-ai:usage-cache-read usage)))
      (is (= 76 (cadr-ai:usage-cache-write usage))))))
