(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(defun goal24-ignore-stream-event (event)
  (declare (ignore event)))

(defun goal24-assistant-input-transformations-diagnostic (message)
  (find :anthropic-input-transformations
        (cadr-ai:assistant-message-diagnostics message)
        :key #'cadr-ai:assistant-message-diagnostic-type))

(test goal24-anthropic-sse-appends-input-transformations-diagnostic
  (multiple-value-bind (provider model)
      (provider-case :anthropic)
    (let ((state
            (cadr-ai::make-provider-stream-state
             :message (cadr-ai::empty-assistant-message model))))
      (cadr-ai::reduce-provider-sse-event
       provider state
       (cadr-ai::make-sse-event
        :data
        "{\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\",\"usage\":{\"input_tokens\":1,\"output_tokens\":0},\"input_transformations\":[{\"type\":\"thinking_dropped\",\"path\":\"/messages/0\",\"reason\":\"first\"},{\"type\":\"thinking_dropped\",\"path\":\"/messages/1\",\"reason\":\"second\"}]}}")
       #'goal24-ignore-stream-event)
      (cadr-ai::reduce-provider-sse-event
       provider state
       (cadr-ai::make-sse-event
        :data
        "{\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":2},\"input_transformations\":[{\"type\":\"thinking_dropped\",\"path\":\"/messages/0\",\"reason\":\"first\"},{\"type\":\"thinking_dropped\",\"path\":\"/messages/1\",\"reason\":\"second\"},{\"type\":\"thinking_dropped\",\"path\":\"/messages/2\",\"reason\":\"third\"}]}")
       #'goal24-ignore-stream-event)
      (cadr-ai::reduce-provider-sse-event
       provider state
       (cadr-ai::make-sse-event
        :data "{\"type\":\"message_stop\"}")
       #'goal24-ignore-stream-event)
      (let* ((message
               (cadr-ai::provider-stream-state-message state))
             (diagnostic
               (goal24-assistant-input-transformations-diagnostic
                message))
             (transformations
               (getf
                (cadr-ai:assistant-message-diagnostic-details
                 diagnostic)
                :transformations)))
        (is (not (null diagnostic)))
        (is (= 3 (length transformations)))
        (is (every
             (lambda (item)
               (string=
                "thinking_dropped"
                (getf item :type)))
             transformations))
        (is (string= "third"
                     (getf (third transformations) :reason)))))))
