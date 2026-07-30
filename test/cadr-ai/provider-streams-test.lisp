(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(test recorded-sse-fixtures-normalize-events-and-final-message
  (dolist (provider-name '(:anthropic :openai :google))
    (multiple-value-bind (provider model)
        (provider-case provider-name)
      (let ((events nil))
        (let ((*http-request-function*
                (lambda (url &rest arguments)
                  (declare (ignore url arguments))
                  (values
                   (open (fixture-path
                          (format nil
                                  "test/fixtures/sse/~(~A~)-tool.sse"
                                  provider-name))
                         :direction :input
                         :element-type '(unsigned-byte 8))
                   200
                   '(("content-type" . "text/event-stream"))))))
        (let ((message (stream-chat
                        provider model (sample-context)
                        (lambda (event) (push event events))
                        :max-tokens 4096)))
          (setf events (nreverse events))
          (is (eq :tool-use (assistant-message-stop-reason message)))
          (is (= (ecase provider-name
                   (:anthropic 677)
                   (:openai 79)
                   (:google 188))
                 (usage-total (assistant-message-usage message))))
          (is (member :tool-call-start (collect-event-types events)))
          (is (member :tool-call-delta (collect-event-types events)))
          (is (member :tool-call-end (collect-event-types events)))
          (is (eq :done (stream-event-type (car (last events)))))
          (is (eq :tool-use
                  (stream-event-reason (car (last events)))))))))))

(test stream-ending-without-provider-terminal-event-is-an-error
  (multiple-value-bind (provider model)
      (provider-case :openai)
    (let ((events nil))
      (let ((*http-request-function*
              (lambda (url &rest arguments)
                (declare (ignore url arguments))
                (values
                 (make-string-input-stream
                  (format nil
                          "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_early\"}}~%~%"))
                 200
                 '(("content-type" . "text/event-stream"))))))
      (let ((message (stream-chat provider model (sample-context)
                                  (lambda (event) (push event events)))))
        (is (eq :error (assistant-message-stop-reason message)))
        (is (search "terminal"
                    (assistant-message-error-message message)))
        (is (eq :error (stream-event-type (first events)))))))))

(test stream-abort-preserves-partial-content-and-terminates
  (multiple-value-bind (provider model)
      (provider-case :openai)
    (let ((events nil)
          (abort-p nil))
      (let ((*http-request-function*
              (lambda (url &rest arguments)
                (declare (ignore url arguments))
                (values
                 (make-string-input-stream
                  (format
                   nil
                   "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_abort\"}}~%~%data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"message\",\"id\":\"msg_abort\",\"role\":\"assistant\",\"content\":[]}}~%~%data: {\"type\":\"response.output_text.delta\",\"output_index\":0,\"delta\":\"partial\"}~%~%data: {\"type\":\"response.output_text.delta\",\"output_index\":0,\"delta\":\" ignored\"}~%~%data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_abort\",\"status\":\"completed\",\"usage\":{\"input_tokens\":1,\"output_tokens\":2,\"total_tokens\":3}}}~%~%"))
                 200
                 '(("content-type" . "text/event-stream"))))))
        (let ((message
                (stream-chat
                 provider model (sample-context)
                 (lambda (event)
                   (push event events)
                   (when (eq :text-delta (stream-event-type event))
                     (setf abort-p t)))
                 :abort-p (lambda () abort-p))))
          (setf events (nreverse events))
          (is (eq :aborted (assistant-message-stop-reason message)))
          (is (string= "partial" (first-text message)))
          (is (eq :error (stream-event-type (car (last events)))))
          (is (eq :aborted
                  (stream-event-reason (car (last events))))))))))

(test stream-request-lifecycle-callbacks-cover-payload-headers-and-response
  (multiple-value-bind (provider model)
      (provider-case :openai)
    (let ((payload-seen-p nil)
          (headers-seen nil)
          (response-seen nil))
      (let ((*http-request-function*
              (lambda (url &rest arguments)
                (declare (ignore url))
                (setf headers-seen
                      (copy-tree
                       (getf arguments :headers)))
                (values
                 (open
                  (fixture-path
                   "test/fixtures/sse/openai-tool.sse")
                  :direction :input
                  :element-type '(unsigned-byte 8))
                 200
                 '(("X-Provider" . "ok"))))))
        (let ((message
                (stream-chat
                 provider model (sample-context)
                 (lambda (event)
                   (declare (ignore event)))
                 :on-payload
                 (lambda (payload callback-model)
                   (is (eq model callback-model))
                   (setf payload-seen-p t)
                   (cadr-ai::json-put
                    payload "metadata"
                    (cadr-ai::json-object
                     "trace" "payload"))
                   payload)
                 :transform-headers
                 (lambda (headers)
                   (append headers
                           '(("X-Trace" . "headers"))))
                 :on-response
                 (lambda (response callback-model)
                   (is (eq model callback-model))
                   (setf response-seen response)))))
          (is (not (null payload-seen-p)))
          (is (string=
               "headers"
               (cdr
                (assoc "X-Trace" headers-seen
                       :test #'string-equal))))
          (is (= 200
                 (getf response-seen :status)))
          (is (string=
               "ok"
               (cdr
                (assoc "X-Provider"
                       (getf response-seen :headers)
                       :test #'string-equal))))
          (is (eq :tool-use
                  (assistant-message-stop-reason
                   message))))))))
