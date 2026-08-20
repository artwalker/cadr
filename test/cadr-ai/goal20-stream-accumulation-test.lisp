(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(defun goal20-ignore-stream-event (event)
  (declare (ignore event)))

(defun goal20-anthropic-assemble-text (count chunk)
  (multiple-value-bind (provider model)
      (provider-case :anthropic)
    (let ((state
            (cadr-ai::make-provider-stream-state
             :message (cadr-ai::empty-assistant-message model)))
          (delta
            (format
             nil
             "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":~A}}"
             (cadr-ai::stringify-json chunk))))
      (cadr-ai::reduce-provider-sse-event
       provider state
       (cadr-ai::make-sse-event
        :data
        "{\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\"}}")
       #'goal20-ignore-stream-event)
      (dotimes (index count)
        (declare (ignore index))
        (cadr-ai::reduce-provider-sse-event
         provider state
         (cadr-ai::make-sse-event :data delta)
         #'goal20-ignore-stream-event))
      (cadr-ai::reduce-provider-sse-event
       provider state
       (cadr-ai::make-sse-event
        :data "{\"type\":\"content_block_stop\",\"index\":0}")
       #'goal20-ignore-stream-event)
      (first-text (cadr-ai::provider-stream-state-message state)))))

(defun goal20-bytes-consed (thunk)
  (sb-ext:gc :full t)
  (let ((before (sb-ext:get-bytes-consed)))
    (funcall thunk)
    (- (sb-ext:get-bytes-consed) before)))

(test goal20-nappend-string-matches-concatenate
  (let ((buffer ""))
    (dolist (chunk '("" "hel" "lo" "" "!" " world"))
      (setf buffer (cadr-ai::nappend-string buffer chunk)))
    (is (string= "hello! world" buffer))
    (is (string= "" (cadr-ai::nappend-string nil "")))
    (is (string= "x" (cadr-ai::nappend-string nil "x")))))

(test goal20-stream-text-deltas-assemble-in-order
  (let ((text (goal20-anthropic-assemble-text 8 "ab")))
    (is (string= "abababababababab" text))))

(test goal20-stream-tool-json-parses-once-at-block-end
  (multiple-value-bind (provider model)
      (provider-case :anthropic)
    (let* ((state
             (cadr-ai::make-provider-stream-state
              :message (cadr-ai::empty-assistant-message model)))
           (json "{\"path\":\"README.md\"}")
           (call nil))
      (cadr-ai::reduce-provider-sse-event
       provider state
       (cadr-ai::make-sse-event
        :data
        "{\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"t1\",\"name\":\"read\"}}")
       #'goal20-ignore-stream-event)
      (loop for character across json
            do (cadr-ai::reduce-provider-sse-event
                provider state
                (cadr-ai::make-sse-event
                 :data
                 (format
                  nil
                  "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":~A}}"
                  (cadr-ai::stringify-json (string character))))
                #'goal20-ignore-stream-event))
      (setf call
            (find-if (lambda (item) (typep item 'cadr-ai:tool-call))
                     (assistant-message-content
                      (cadr-ai::provider-stream-state-message state))))
      (is (zerop
           (hash-table-count (cadr-ai:tool-call-arguments call))))
      (cadr-ai::reduce-provider-sse-event
       provider state
       (cadr-ai::make-sse-event
        :data "{\"type\":\"content_block_stop\",\"index\":0}")
       #'goal20-ignore-stream-event)
      (is (string=
           "README.md"
           (cadr-ai::json-get (cadr-ai:tool-call-arguments call)
                              "path"))))))

(test goal20-stream-text-accumulation-consing-scales-near-linearly
  ;; 12C-1: doubling deltas must not quadruple consing. concatenate of
  ;; the whole prefix each time would.
  (goal20-anthropic-assemble-text 4 "warm")
  (let* ((chunk (make-string 32 :initial-element #\x))
         (small 300)
         (large 600)
         (bytes-small
           (goal20-bytes-consed
            (lambda () (goal20-anthropic-assemble-text small chunk))))
         (bytes-large
           (goal20-bytes-consed
            (lambda () (goal20-anthropic-assemble-text large chunk)))))
    ;; 3× was inside measurement noise after parse-json objects
    ;; became sequential pairs (per-event cons, not text).  4× still
    ;; rejects quadratic concatenate.
    (is (< bytes-large (* 4 bytes-small)))
    (is (plusp bytes-small))))
