(in-package #:cadr-ai)

(defparameter *ai-telemetry-schema*
  (labels ((attribute (type description &key required values cardinality)
             (cadr-telemetry:make-telemetry-attribute-definition
              :type type
              :description description
              :required required
              :values values
              :cardinality cardinality)))
    (let* ((provider (attribute "string" "Provider identifier." :required t))
           (model (attribute "string" "Requested model identifier." :required t))
           (stop-values '("pending" "stop" "length" "toolUse" "error"
                          "aborted" "deferred"))
           (stop (attribute "string" "Normalized stop reason."
                            :values stop-values))
           (metric-stop (attribute "string" "Normalized stop reason."
                                   :values stop-values :required t))
           (start-attributes
             (list (cons "provider" provider)
                   (cons "api" (attribute "string" "API identifier." :required t))
                   (cons "model" model)
                   (cons "reasoning"
                         (attribute "string" "Scalar requested reasoning level."
                                    :required nil))))
           (end-attributes
             (list (cons "stop" stop)
                   (cons "usage.input"
                         (attribute "number" "Uncached input tokens."))
                   (cons "usage.output" (attribute "number" "Output tokens."))
                   (cons "usage.cache_read"
                         (attribute "number" "Cache-read tokens."))
                   (cons "usage.cache_write"
                         (attribute "number" "Cache-write tokens."))
                   (cons "cost.total"
                         (attribute "number" "Total request cost in USD."))
                   (cons "response.id"
                         (attribute "string" "Provider response identifier."
                                    :cardinality "high"))))
           (events
             (list (cons "pi.ai.first_chunk"
                         '(:description "First normalized stream event delivered."
                           :attributes nil))
                   (cons "pi.ai.block"
                         (list :description
                               "A completed content block; content is never recorded."
                               :attributes
                               (list (cons "type"
                                           (attribute "string" "Block kind."
                                                      :values '("text" "thinking"
                                                                "tool_call")
                                                      :required t))
                                     (cons "index"
                                           (attribute "number" "Content block index."
                                                      :required t))
                                     (cons "chars"
                                           (attribute "number" "UTF-16 character count."
                                                      :required t))
                                     (cons "tool"
                                           (attribute "string"
                                                      "Tool name, for tool-call blocks only."
                                                      :required nil)))))))
           (status
             '(:default "ok"
               :error-when
               "Stop reason is error: provider_error with at most 500 error-message characters. Aborted stays ok."))
           (parents '(:kind "any"))
           (request
             (cadr-telemetry:make-telemetry-span-definition
              :description "One logical model request, including authentication and provider setup."
              :parents parents
              :start-attributes start-attributes
              :end-attributes end-attributes
              :events events
              :status status)))
      (cadr-telemetry:make-telemetry-schema
       :version 1
       :spans
       (list (cons "pi.ai.request" request)
             (cons "pi.ai.poll"
                   (cadr-telemetry:make-telemetry-span-definition
                    :description "One deferred-response poll, not the deferred request's lifetime."
                    :parents parents
                    :start-attributes start-attributes
                    :end-attributes end-attributes
                    :events events
                    :status status)))
       :metrics
       (list (cons "pi.ai.request.duration"
                   (cadr-telemetry:make-telemetry-metric-definition
                    :kind "histogram"
                    :description "Logical request or poll duration."
                    :unit "ms"
                    :attributes (list (cons "provider" provider)
                                      (cons "model" model)
                                      (cons "stop" metric-stop))))
             (cons "pi.ai.first_chunk.duration"
                   (cadr-telemetry:make-telemetry-metric-definition
                    :kind "histogram"
                    :description "Time to the first normalized stream event."
                    :unit "ms"
                    :attributes (list (cons "provider" provider)
                                      (cons "model" model))))
             (cons "pi.ai.tokens"
                   (cadr-telemetry:make-telemetry-metric-definition
                    :kind "counter"
                    :description "Reported model token usage; pending and deferred polls are excluded."
                    :unit "token"
                    :attributes
                    (list (cons "provider" provider)
                          (cons "model" model)
                          (cons "kind"
                                (attribute "string" "Token usage category."
                                           :values '("input" "output"
                                                     "cache_read" "cache_write")
                                           :required t)))))
             (cons "pi.ai.cost"
                   (cadr-telemetry:make-telemetry-metric-definition
                    :kind "counter"
                    :description "Reported model cost; pending and deferred polls are excluded."
                    :unit "USD"
                    :attributes (list (cons "provider" provider)
                                      (cons "model" model)))))))))

(defvar *ai-instrument-cache*
  (make-hash-table :test 'eq :weakness :key))

(defun telemetry-symbol-text (value)
  (string-downcase (symbol-name value)))

(defun telemetry-stop-text (reason)
  (case reason
    (:tool-use "toolUse")
    (otherwise (telemetry-symbol-text reason))))

(defun telemetry-utf16-length (text)
  (loop for character across (or text "")
        sum (if (> (char-code character) #xFFFF) 2 1)))

(defun telemetry-utf16-high-surrogate (character)
  (code-char
   (+ #xD800
      (ldb (byte 10 10) (- (char-code character) #x10000)))))

(defun telemetry-utf16-slice (text limit)
  (let ((text (or text ""))
        (count 0)
        (end 0)
        (split nil))
    (loop for character across text
          for units = (if (> (char-code character) #xFFFF) 2 1)
          do (cond
               ((<= (+ count units) limit)
                (incf count units)
                (incf end))
               ((and (> units 1) (< count limit))
                (setf split (telemetry-utf16-high-surrogate character))
                (loop-finish))
               (t (loop-finish))))
    (if split
        (concatenate 'string (subseq text 0 end) (string split))
        (subseq text 0 end))))

(defun telemetry-event-name (event)
  (let ((type (stream-event-type event)))
    (if (symbolp type)
        (string-downcase (symbol-name type))
        (or type ""))))

(defun ai-instruments (metrics)
  (or (gethash metrics *ai-instrument-cache*)
      (let ((typed (cadr-telemetry:create-typed-metrics
                    metrics (list *ai-telemetry-schema*))))
        (setf (gethash metrics *ai-instrument-cache*)
              (list (cadr-telemetry:typed-metrics-histogram
                     typed "pi.ai.request.duration")
                    (cadr-telemetry:typed-metrics-histogram
                     typed "pi.ai.first_chunk.duration")
                    (cadr-telemetry:typed-metrics-counter
                     typed "pi.ai.tokens")
                    (cadr-telemetry:typed-metrics-counter
                     typed "pi.ai.cost"))))))

(defun call-with-observed-model-request (model options poll function)
  (let* ((span (or (getf options :telemetry)
                   cadr-telemetry:*noop-telemetry-context*))
         (metrics (or (cadr-telemetry:telemetry-span-metrics span)
                      cadr-telemetry:*noop-telemetry-metrics*))
         (instruments (ai-instruments metrics))
         (request-duration (first instruments))
         (first-chunk-duration (second instruments))
         (tokens (third instruments))
         (cost (fourth instruments))
         (started (cadr-telemetry:telemetry-monotonic-milliseconds))
         (provider (telemetry-symbol-text (model-provider model)))
         (model-id (model-id model))
         (identity-attributes
           (list (cons "provider" provider)
                 (cons "model" model-id)))
         (reasoning (getf options :reasoning))
         (start-attributes
           (append (list (cons "provider" provider)
                         (cons "api" (telemetry-symbol-text (model-api model)))
                         (cons "model" model-id))
                   (when (stringp reasoning)
                     (list (cons "reasoning" reasoning)))))
         (tool-chars (make-hash-table))
         (first-p t)
         (finished-p nil)
         (active nil))
    (cadr-telemetry:telemetry-start-span
     span
     (if poll "pi.ai.poll" "pi.ai.request")
     (lambda (request-span)
       (setf active request-span)
       (flet ((observe (event)
                (when first-p
                  (setf first-p nil)
                  (cadr-telemetry:telemetry-add-event
                   active "pi.ai.first_chunk")
                  (cadr-telemetry:telemetry-histogram-record
                   first-chunk-duration
                   (- (cadr-telemetry:telemetry-monotonic-milliseconds) started)
                   identity-attributes
                   active))
                (let ((type (telemetry-event-name event)))
                  (cond
                    ((string= type "tool-call-delta")
                     (let ((index (stream-event-content-index event)))
                       (setf (gethash index tool-chars)
                             (+ (or (gethash index tool-chars) 0)
                                (telemetry-utf16-length
                                 (stream-event-delta event))))))
                    ((or (string= type "text-end")
                         (string= type "thinking-end"))
                     (cadr-telemetry:telemetry-add-event
                      active "pi.ai.block"
                      (list (cons "type"
                                  (if (string= type "text-end")
                                      "text"
                                      "thinking"))
                            (cons "index" (stream-event-content-index event))
                            (cons "chars"
                                  (telemetry-utf16-length
                                   (stream-event-content event))))))
                    ((string= type "tool-call-end")
                     (let* ((index (stream-event-content-index event))
                            (chars (or (gethash index tool-chars) 0))
                            (call (stream-event-tool-call event)))
                       (remhash index tool-chars)
                       (cadr-telemetry:telemetry-add-event
                        active "pi.ai.block"
                        (list (cons "type" "tool_call")
                              (cons "index" index)
                              (cons "chars" chars)
                              (cons "tool"
                                    (if call (tool-call-name call) "")))))))))
              (finish (message)
                (unless finished-p
                  (setf finished-p t)
                  (when message
                    (let ((stop (telemetry-stop-text
                                 (assistant-message-stop-reason message))))
                      (cadr-telemetry:telemetry-set-attributes
                       active
                       (list (cons "stop" stop)
                             (cons "usage.input"
                                   (usage-input
                                    (assistant-message-usage message)))
                             (cons "usage.output"
                                   (usage-output
                                    (assistant-message-usage message)))
                             (cons "usage.cache_read"
                                   (usage-cache-read
                                    (assistant-message-usage message)))
                             (cons "usage.cache_write"
                                   (usage-cache-write
                                    (assistant-message-usage message)))
                             (cons "cost.total"
                                   (cost-total
                                    (usage-cost
                                     (assistant-message-usage message))))
                             (cons "response.id"
                                   (or (assistant-message-response-id message)
                                       :undefined))))
                      (when (eq :error (assistant-message-stop-reason message))
                        (cadr-telemetry:telemetry-set-status
                         active
                         :kind :error
                         :error-name "provider_error"
                         :error-message
                         (telemetry-utf16-slice
                          (assistant-message-error-message message)
                          500)))
                      (cadr-telemetry:telemetry-histogram-record
                       request-duration
                       (- (cadr-telemetry:telemetry-monotonic-milliseconds)
                          started)
                       (append identity-attributes
                               (list (cons "stop" stop)))
                       active)
                      (unless (and poll
                                   (member (assistant-message-stop-reason message)
                                           '(:pending :deferred)))
                        (let ((usage (assistant-message-usage message)))
                          (dolist (kind '(("input" . input)
                                          ("output" . output)
                                          ("cache_read" . cache-read)
                                          ("cache_write" . cache-write)))
                            (cadr-telemetry:telemetry-counter-add
                             tokens
                             (ecase (cdr kind)
                               (input (usage-input usage))
                               (output (usage-output usage))
                               (cache-read (usage-cache-read usage))
                               (cache-write (usage-cache-write usage)))
                             (append identity-attributes
                                     (list (cons "kind" (car kind))))))
                          (cadr-telemetry:telemetry-counter-add
                           cost
                           (cost-total (usage-cost usage))
                           identity-attributes))))))))
         (funcall function #'observe #'finish)))
     :attributes start-attributes)))
