(in-package #:pi-ai)

(defclass provider ()
  ((api-key
    :initarg :api-key
    :initform nil
    :reader provider-api-key)
   (oauth-access-token
    :initarg :oauth-access-token
    :initform nil
    :reader provider-oauth-access-token)
   (oauth-account-id
    :initarg :oauth-account-id
    :initform nil
    :reader provider-oauth-account-id)
   (authentication-required-p
    :initarg :authentication-required-p
    :initform t
    :reader provider-authentication-required-p)))

(defclass anthropic-provider (provider) ())
(defclass openai-provider (provider) ())
(defclass openai-completions-provider (provider) ())
(defclass google-provider (provider) ())

(defparameter *max-provider-retries* 2)
(defparameter *retry-base-delay* 0.25)
(defparameter *retry-sleep-function* #'sleep)

(defun provider-secrets (provider)
  (remove-if-not
   #'non-empty-string-p
   (list
    (provider-api-key provider)
    (provider-oauth-access-token provider))))

(defun make-anthropic-provider (&key api-key oauth-access-token)
  (make-instance 'anthropic-provider
                 :api-key api-key
                 :oauth-access-token oauth-access-token))

(defun make-openai-provider
    (&key api-key oauth-access-token oauth-account-id)
  (make-instance 'openai-provider
                 :api-key api-key
                 :oauth-access-token oauth-access-token
                 :oauth-account-id oauth-account-id))

(defun make-openai-completions-provider
    (&key api-key (authentication-required-p t))
  (make-instance 'openai-completions-provider
                 :api-key api-key
                 :authentication-required-p authentication-required-p))

(defun make-google-provider (&key api-key)
  (make-instance 'google-provider :api-key api-key))

(defgeneric build-request
    (provider model context &key stream-p max-tokens temperature))

(defgeneric parse-complete-response (provider model response))

(defgeneric reduce-provider-sse-event
    (provider state event emit))

(defstruct provider-stream-state
  (message nil :type (or null assistant-message))
  (block-indices (make-hash-table) :type hash-table)
  (partial-json (make-hash-table) :type hash-table)
  (terminal-p nil :type boolean)
  (current-block-index nil :type (or null (integer 0 *))))

(defun require-api-key (provider)
  (let ((key (provider-api-key provider)))
    (unless (non-empty-string-p key)
      (error 'configuration-error
             :message "Provider API key is missing"))
    key))

(defun provider-bearer-token (provider)
  (or (provider-oauth-access-token provider)
      (let ((key (provider-api-key provider)))
        (cond
          ((non-empty-string-p key) key)
          ((provider-authentication-required-p provider)
           (error 'configuration-error
                  :message "Provider API key is missing"))
          (t nil)))))

(defun content-has-images-p (content)
  (and (or (listp content) (vectorp content))
       (find-if (lambda (item) (typep item 'image-content))
                (coerce content 'list))))

(defun context-has-images-p (context)
  (some
   (lambda (message)
     (cond
       ((typep message 'user-message)
        (content-has-images-p (user-message-content message)))
       ((typep message 'tool-result-message)
        (content-has-images-p (tool-result-message-content message)))
       (t nil)))
   (context-messages context)))

(defun ensure-supported-content (model context)
  (when (and (context-has-images-p context)
             (not (model-supports-images-p model)))
    (error 'unsupported-content-error
           :message
           (format nil "Model ~A does not support image input"
                   (model-id model)))))

(defun strip-trailing-slash (url)
  (string-right-trim "/" url))

(defun empty-assistant-message (model)
  (make-assistant-message
   :api (model-api model)
   :provider (model-provider model)
   :model (model-id model)))

(defun same-model-message-p (message model)
  (and (eq (assistant-message-provider message)
           (model-provider model))
       (eq (assistant-message-api message)
           (model-api model))
       (string= (assistant-message-model message)
                (model-id model))))

(defun copy-history-content-block (block same-model-p normalize-id)
  (cond
    ((typep block 'text-content)
     (list
      (make-text-content
       :text (text-content-text block)
       :signature (and same-model-p
                       (text-content-signature block)))))
    ((typep block 'thinking-content)
     (cond
       ((thinking-content-redacted-p block)
        (if same-model-p
            (list
             (make-thinking-content
              :thinking (thinking-content-thinking block)
              :signature (thinking-content-signature block)
              :redacted-p t))
            nil))
       (same-model-p
        (list
         (make-thinking-content
          :thinking (thinking-content-thinking block)
          :signature (thinking-content-signature block))))
       ((non-empty-string-p (thinking-content-thinking block))
        (list
         (make-text-content
          :text (thinking-content-thinking block))))
       (t nil)))
    ((typep block 'tool-call)
     (let ((normalized-id
             (if same-model-p
                 (tool-call-id block)
                 (funcall normalize-id (tool-call-id block)))))
       (list
        (make-tool-call
         :id normalized-id
         :name (tool-call-name block)
         :arguments (tool-call-arguments block)
         :thought-signature
         (and same-model-p
              (tool-call-thought-signature block))))))
    (t nil)))

(defun prepare-messages-for-model (messages model normalize-id)
  "Make stored history valid for MODEL without mutating the session objects."
  (let ((id-map (make-hash-table :test #'equal))
        (transformed nil))
    (dolist (message messages)
      (cond
        ((typep message 'assistant-message)
         (unless (member (assistant-message-stop-reason message)
                         '(:error :aborted))
           (let* ((same-model-p (same-model-message-p message model))
                  (content
                    (loop for block in (assistant-message-content message)
                          append
                          (let ((copies
                                  (copy-history-content-block
                                   block same-model-p normalize-id)))
                            (when (and (typep block 'tool-call)
                                       copies)
                              (setf
                               (gethash (tool-call-id block) id-map)
                               (tool-call-id (first copies))))
                            copies))))
             (push
              (make-assistant-message
               :content content
               :api (assistant-message-api message)
               :provider (assistant-message-provider message)
               :model (assistant-message-model message)
               :response-id (assistant-message-response-id message)
               :usage (assistant-message-usage message)
               :stop-reason (assistant-message-stop-reason message)
               :error-message (assistant-message-error-message message)
               :raw-stop-reason
               (assistant-message-raw-stop-reason message)
               :timestamp (assistant-message-timestamp message))
              transformed))))
        ((typep message 'tool-result-message)
         (push
          (make-tool-result-message
           :tool-call-id
           (or (gethash (tool-result-message-tool-call-id message)
                        id-map)
               (tool-result-message-tool-call-id message))
           :tool-name (tool-result-message-tool-name message)
           :content (tool-result-message-content message)
           :details (tool-result-message-details message)
           :is-error (tool-result-message-is-error message)
           :timestamp (tool-result-message-timestamp message))
          transformed))
        (t
         (push message transformed))))
    (setf transformed (nreverse transformed))
    (let ((result nil)
          (pending-tool-calls nil)
          (existing-results (make-hash-table :test #'equal)))
      (labels
          ((insert-missing-results ()
             (dolist (call pending-tool-calls)
               (unless (gethash (tool-call-id call) existing-results)
                 (push
                  (make-tool-result-message
                   :tool-call-id (tool-call-id call)
                   :tool-name (tool-call-name call)
                   :content
                   (list
                    (make-text-content :text "No result provided"))
                   :is-error t)
                  result)))
             (setf pending-tool-calls nil
                   existing-results
                   (make-hash-table :test #'equal))))
        (dolist (message transformed)
          (cond
            ((typep message 'assistant-message)
             (insert-missing-results)
             (setf pending-tool-calls
                   (remove-if-not
                    (lambda (block) (typep block 'tool-call))
                    (assistant-message-content message)))
             (push message result))
            ((typep message 'tool-result-message)
             (setf (gethash
                    (tool-result-message-tool-call-id message)
                    existing-results)
                   t)
             (push message result))
            ((typep message 'user-message)
             (insert-missing-results)
             (push message result))))
        (insert-missing-results))
      (nreverse result))))

(defun normalize-provider-id (id)
  (let ((normalized
          (map 'string
               (lambda (character)
                 (if (or (alphanumericp character)
                         (char= character #\_)
                         (char= character #\-))
                     character
                     #\_))
               id)))
    (subseq normalized 0 (min 64 (length normalized)))))

(defun append-content-block (message block)
  (let ((index (length (assistant-message-content message))))
    (setf (assistant-message-content message)
          (nconc (assistant-message-content message) (list block)))
    index))

(defun emit-event (emit type message
                   &key content-index delta content tool-call reason)
  (funcall emit
           (make-stream-event
            :type type
            :content-index content-index
            :delta delta
            :content content
            :tool-call tool-call
            :message message
            :reason reason)))

(defun condition-text (condition &optional provider)
  (redact-secrets
   (if (typep condition 'pi-error)
       (pi-error-message condition)
       (princ-to-string condition))
   (if provider
       (provider-secrets provider)
       nil)))

(defun error-assistant-message
    (model condition &optional provider)
  (let ((message (empty-assistant-message model)))
    (setf (assistant-message-stop-reason message)
          (if (typep condition 'request-aborted) :aborted :error)
          (assistant-message-error-message message)
          (condition-text condition provider))
    message))

(defun check-abort (abort-p)
  (when (and abort-p (funcall abort-p))
    (error 'request-aborted :message "Request was aborted")))

(defun retry-after-seconds (condition)
  (when (typep condition 'api-error)
    (let ((value (api-error-retry-after condition)))
      (when (and (stringp value)
                 (plusp (length value))
                 (every #'digit-char-p value))
        (min 60 (parse-integer value))))))

(defun provider-retry-delay (condition retry-index)
  (or (retry-after-seconds condition)
      (* *retry-base-delay* (expt 2 retry-index))))

(defun call-with-provider-retries
    (function &key (retry-allowed-p (constantly t)))
  (loop for retry-index from 0
        do
        (handler-case
            (return (funcall function))
          (error (condition)
            (unless
                (and (< retry-index *max-provider-retries*)
                     (typep condition 'pi-error)
                     (pi-error-retryable-p condition)
                     (funcall retry-allowed-p condition))
              (error condition))
            (funcall
             *retry-sleep-function*
             (provider-retry-delay condition retry-index))))))

(defun complete-chat (provider model context
                      &key max-tokens temperature abort-p)
  (handler-case
      (progn
        (check-abort abort-p)
        (let* ((request (build-request provider model context
                                       :stream-p nil
                                       :max-tokens max-tokens
                                       :temperature temperature))
               (response
                 (call-with-provider-retries
                  (lambda ()
                    (check-abort abort-p)
                    (request-json request)))))
          (check-abort abort-p)
          (parse-complete-response provider model response)))
    (error (condition)
      (error-assistant-message
       model condition provider))))

(defun stream-chat (provider model context on-event
                    &key max-tokens temperature abort-p)
  (let* ((message (empty-assistant-message model))
         (state (make-provider-stream-state :message message))
         (saw-provider-event-p nil))
    (handler-case
        (progn
          (check-abort abort-p)
          (let ((request (build-request provider model context
                                        :stream-p t
                                        :max-tokens max-tokens
                                        :temperature temperature)))
            (emit-event on-event :start message)
            (call-with-provider-retries
             (lambda ()
               (check-abort abort-p)
               (request-sse
                request
                (lambda (event)
                  (setf saw-provider-event-p t)
                  (check-abort abort-p)
                  (reduce-provider-sse-event
                   provider state event on-event)
                  (check-abort abort-p))))
             :retry-allowed-p
             (lambda (condition)
               (declare (ignore condition))
               (not saw-provider-event-p))))
          (unless (provider-stream-state-terminal-p state)
            (error 'sse-protocol-error
                   :message "Provider stream ended without a terminal event"))
          (when (eq :pending (assistant-message-stop-reason message))
            (error 'sse-protocol-error
                   :message "Provider stream ended without a stop reason"))
          (if (member (assistant-message-stop-reason message)
                      '(:stop :length :tool-use))
              (progn
                (emit-event on-event
                            :done
                            message
                            :reason (assistant-message-stop-reason message))
                message)
              (error 'sse-protocol-error
                     :message (or (assistant-message-error-message message)
                                  "Provider stream failed"))))
      (error (condition)
        (let ((reason
                (if (typep condition 'request-aborted)
                    :aborted
                    :error)))
          (setf (assistant-message-stop-reason message) reason
              (assistant-message-error-message message)
              (condition-text condition provider))
          (emit-event on-event :error message :reason reason))
        message))))

(defun map-simple-stop-reason (raw)
  (cond
    ((member raw '("end_turn" "stop_sequence" "STOP" "completed")
             :test #'string=)
     :stop)
    ((member raw '("max_tokens" "MAX_TOKENS" "incomplete")
             :test #'string=)
     :length)
    ((string= raw "tool_use")
     :tool-use)
    (t
     :error)))

(defun update-message-usage (message input output cache-read cache-write
                             &optional reasoning total)
  (setf (assistant-message-usage message)
        (make-usage :input (or input 0)
                    :output (or output 0)
                    :cache-read (or cache-read 0)
                    :cache-write (or cache-write 0)
                    :reasoning reasoning
                    :total total))
  message)

(defun apply-known-model-cost (message)
  (let ((metadata
          (ignore-errors
            (find-model-metadata
             (assistant-message-provider message)
             (assistant-message-model message)))))
    (when metadata
      (calculate-usage-cost
       (assistant-message-usage message)
       metadata)))
  message)

(defun tool-call-present-p (message)
  (some (lambda (block) (typep block 'tool-call))
        (assistant-message-content message)))
