(in-package #:cadr-ai)

(defclass provider ()
  ((provider-id
    :initarg :provider-id
    :initform nil
    :reader provider-id)
   (options
    :initarg :options
    :initform nil
    :reader provider-options)
   (api-key
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
(defclass azure-openai-provider (openai-provider) ())
(defclass bedrock-provider (provider) ())
(defclass vertex-provider (google-provider) ())
(defclass mistral-provider (openai-completions-provider) ())
(defclass openai-codex-provider (openai-provider) ())
(defclass pi-messages-provider (provider) ())

(cadr-core:define-redacted-print-object (provider value stream)
  (format stream ":provider-id ~A :credentials [REDACTED]"
          (provider-id value)))

(defparameter *max-provider-retries* 2)
(defparameter *retry-base-delay* 0.25)
(defparameter *retry-sleep-function* #'sleep)

(defun provider-secrets (provider)
  (remove-if-not
   #'non-empty-string-p
   (list
    (provider-api-key provider)
    (provider-oauth-access-token provider))))

(defun make-anthropic-provider
    (&key api-key oauth-access-token oauth-account-id
            provider-id options)
  (declare (ignore oauth-account-id))
  (make-instance 'anthropic-provider
                 :api-key api-key
                 :oauth-access-token oauth-access-token
                 :provider-id provider-id
                 :options options))

(defun make-openai-provider
    (&key api-key oauth-access-token oauth-account-id
            provider-id options)
  (make-instance 'openai-provider
                 :api-key api-key
                 :oauth-access-token oauth-access-token
                 :oauth-account-id oauth-account-id
                 :provider-id provider-id
                 :options options))

(defun make-openai-completions-provider
    (&key api-key oauth-access-token oauth-account-id
            (authentication-required-p t) provider-id options)
  (declare (ignore oauth-account-id))
  (make-instance 'openai-completions-provider
                 :api-key api-key
                 :oauth-access-token oauth-access-token
                 :authentication-required-p authentication-required-p
                 :provider-id provider-id
                 :options options))

(defun make-google-provider
    (&key api-key oauth-access-token oauth-account-id
            provider-id options)
  (declare (ignore oauth-access-token oauth-account-id))
  (make-instance 'google-provider
                 :api-key api-key
                 :provider-id provider-id
                 :options options))

(defmacro define-provider-constructor (name class)
  `(defun ,name
       (&key api-key oauth-access-token oauth-account-id
               provider-id options)
     (make-instance
      ',class
      :api-key api-key
      :oauth-access-token oauth-access-token
      :oauth-account-id oauth-account-id
      :provider-id provider-id
      :options options)))

(define-provider-constructor make-azure-openai-provider
  azure-openai-provider)
(define-provider-constructor make-bedrock-provider
  bedrock-provider)
(define-provider-constructor make-vertex-provider
  vertex-provider)
(define-provider-constructor make-mistral-provider
  mistral-provider)
(define-provider-constructor make-openai-codex-provider
  openai-codex-provider)
(define-provider-constructor make-pi-messages-provider
  pi-messages-provider)

(defgeneric build-request
    (provider model context
     &key stream-p max-tokens temperature reasoning cache-retention
       session-id tool-choice metadata thinking-budgets))

(defgeneric parse-complete-response (provider model response))

(defgeneric reduce-provider-sse-event
    (provider state event emit))

(defgeneric finalize-provider-stream
    (provider model state emit))

(defgeneric try-provider-websocket-stream
    (provider model context request state emit
     &key transport session-id abort-p on-response
       websocket-connect-timeout-ms http-proxy)
  (:documentation
   "Handle REQUEST over a provider-specific WebSocket transport.
Return two values: whether the request was handled and, when handled, the
completed assistant message."))

(defmethod try-provider-websocket-stream
    ((provider provider) model context request state emit
     &key transport session-id abort-p on-response
       websocket-connect-timeout-ms http-proxy)
  (declare (ignore provider model context request state emit
                   transport session-id abort-p on-response
                   websocket-connect-timeout-ms http-proxy))
  (values nil nil))

(defgeneric prepare-provider-sse-request (provider request))

(defmethod prepare-provider-sse-request ((provider provider) request)
  (declare (ignore provider))
  request)

(defmethod finalize-provider-stream
    ((provider provider) model state emit)
  (declare (ignore provider model state emit))
  nil)

(defun plist-entry (plist key)
  (let ((tail (member key plist :test #'eq)))
    (if tail
        (values (cadr tail) t)
        (values nil nil))))

(defun model-compat-value (model key default)
  (multiple-value-bind (value present-p)
      (plist-entry (model-compat model) key)
    (if present-p value default)))

(defun model-thinking-level-value (model level)
  (cdr (assoc level
              (model-thinking-level-map model)
              :test #'eq)))

(defun model-thinking-level-present-p (model level)
  (not
   (null
    (assoc level
           (model-thinking-level-map model)
           :test #'eq))))

(defun thinking-budget-for-level (level &optional custom-budgets)
  (let* ((mapped
           (if (member level '(:xhigh :max))
               :high
               level))
         (custom
           (and custom-budgets
                (getf custom-budgets mapped))))
    (or custom
        (case mapped
          (:minimal 1024)
          (:low 2048)
          (:medium 8192)
          (otherwise 16384)))))

(defun anthropic-effort-p (value)
  (and (stringp value)
       (member value '("low" "medium" "high" "xhigh" "max")
               :test #'string=)))

(defun anthropic-active-effort (model reasoning)
  (or (when reasoning
        (let ((mapped (model-thinking-level-value model reasoning)))
          (if (anthropic-effort-p mapped)
              mapped
              (let ((down (string-downcase
                           (if (symbolp reasoning)
                               (symbol-name reasoning)
                               (princ-to-string reasoning)))))
                (when (anthropic-effort-p down) down)))))
      "high"))

(defun mid-convo-thinking-level (model reasoning)
  (when (model-compat-value model :supports-mid-convo-effort nil)
    (anthropic-active-effort model reasoning)))

(defun normalize-cache-retention (value)
  (let ((retention (or value :short)))
    (unless (member retention '(:none :short :long))
      (error 'configuration-error
             :message
             (format nil "Invalid cache retention: ~A" retention)))
    retention))

(defun clamp-openai-cache-key (value)
  (when (non-empty-string-p value)
    (subseq value 0 (min 64 (length value)))))

(defun tool-strict-p (tool)
  (let ((constraint (tool-constrained-sampling tool)))
    (and (eq :json-schema (getf constraint :type))
         (not
          (null
           (member (getf constraint :strict)
                   '(:prefer :require)))))))

(defstruct provider-stream-state
  (message nil :type (or null assistant-message))
  (block-indices (make-hash-table) :type hash-table)
  (partial-json (make-hash-table) :type hash-table)
  (terminal-p nil :type boolean)
  (current-block-index nil :type (or null (integer 0 *)))
  (json-scratch nil :type (or null json-parse-scratch))
  (model nil :type (or null model)))

(defun nappend-string (buffer chunk)
  "Append CHUNK onto BUFFER in amortized linear time.

BUFFER may be NIL, a simple string, or an adjustable fill-pointer
string. Returns the buffer to store back. Per-delta
`concatenate 'string` of the whole accumulation is quadratic."
  (let* ((addition (if (stringp chunk) chunk ""))
         (add-length (length addition)))
    (when (zerop add-length)
      (return-from nappend-string (if (stringp buffer) buffer "")))
    (let ((base
            (if (and (stringp buffer)
                     (array-has-fill-pointer-p buffer)
                     (adjustable-array-p buffer))
                buffer
                (let* ((old (if (stringp buffer) buffer ""))
                       (fresh
                         (make-array (max 16 (* 2 (length old)))
                                     :element-type 'character
                                     :adjustable t
                                     :fill-pointer (length old))))
                  (replace fresh old)
                  fresh))))
      (let* ((start (fill-pointer base))
             (needed (+ start add-length)))
        (when (> needed (array-dimension base 0))
          (adjust-array
           base (max needed (* 2 (array-dimension base 0)))))
        (setf (fill-pointer base) needed)
        (replace base addition :start1 start)
        base))))

(defun require-api-key (provider)
  (let ((key (provider-api-key provider)))
    (unless (non-empty-string-p key)
      ;; Baseline agent-session.ts _getRequiredRequestAuth surfaces the
      ;; auth-guidance message, not a bare "key missing" note.
      (error 'configuration-error
             :message
             (no-api-key-found-message
              (string-downcase
               (symbol-name (provider-id provider))))))
    key))

(defun provider-bearer-token (provider)
  (or (provider-oauth-access-token provider)
      (let ((key (provider-api-key provider)))
        (cond
          ((non-empty-string-p key) key)
          ((provider-authentication-required-p provider)
           (error 'configuration-error
                  :message
                  (no-api-key-found-message
                   (string-downcase
                    (symbol-name (provider-id provider))))))
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

(defun empty-assistant-message (model &optional reasoning)
  (make-assistant-message
   :api (model-api model)
   :provider (model-provider model)
   :model (model-id model)
   :provider-thinking-level
   (mid-convo-thinking-level model reasoning)))

(defun same-model-message-p (message model)
  (and (eq (assistant-message-provider message)
           (model-provider model))
       (eq (assistant-message-api message)
           (model-api model))
       (string= (assistant-message-model message)
                (model-id model))))

(defun copy-history-content-block
    (block same-model-p normalize-id source-message target-model
     foreign-id-normalizer)
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
                 (if foreign-id-normalizer
                     (funcall foreign-id-normalizer
                              (tool-call-id block)
                              target-model
                              source-message)
                     (funcall normalize-id (tool-call-id block))))))
       (list
        (make-tool-call
         :id normalized-id
         :name (tool-call-name block)
         :arguments (tool-call-arguments block)
         :thought-signature
         (and same-model-p
              (tool-call-thought-signature block))))))
    (t nil)))

(defun prepare-messages-for-model
    (messages model normalize-id &optional foreign-id-normalizer)
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
                                   block same-model-p normalize-id
                                   message model foreign-id-normalizer)))
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
               :response-model
               (assistant-message-response-model message)
               :response-id (assistant-message-response-id message)
               :usage (assistant-message-usage message)
               :stop-reason (assistant-message-stop-reason message)
               :error-message (assistant-message-error-message message)
               :raw-stop-reason
               (assistant-message-raw-stop-reason message)
               :diagnostics
               (copy-list
                (assistant-message-diagnostics message))
               :timestamp (assistant-message-timestamp message)
               :provider-thinking-level
               (assistant-message-provider-thinking-level message))
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
           :added-tool-names
           (copy-list (tool-result-message-added-tool-names message))
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
   (if (typep condition 'cadr-error)
       (cadr-error-message condition)
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
    (function &key (retry-allowed-p (constantly t))
                   (max-retries *max-provider-retries*)
                   max-retry-delay-ms
                   timeout-ms)
  (declare (ignore timeout-ms))
  (let ((limit
          (if (integerp max-retries)
              max-retries
              *max-provider-retries*)))
    (loop for retry-index from 0
          do
          (handler-case
              (return (funcall function))
            (error (condition)
              (unless
                  (and (< retry-index limit)
                       (typep condition 'cadr-error)
                       (cadr-error-retryable-p condition)
                       (funcall retry-allowed-p condition)
                       (let ((delay (retry-after-seconds condition)))
                         (or (null max-retry-delay-ms)
                             (zerop max-retry-delay-ms)
                             (null delay)
                             (<= (* 1000 delay)
                                 max-retry-delay-ms))))
                (error condition))
              (funcall
               *retry-sleep-function*
               (provider-retry-delay condition retry-index)))))))

(defun apply-provider-request-callbacks
    (request model on-payload transform-headers)
  (when on-payload
    (multiple-value-bind
          (replacement supplied-p)
        (funcall
         on-payload
         (request-spec-payload request)
         model)
      (when (or supplied-p replacement)
        (setf
         (request-spec-payload request)
         replacement))))
  (when transform-headers
    (let ((replacement
            (funcall
             transform-headers
             (copy-tree
              (request-spec-headers request)))))
      (when replacement
        (setf
         (request-spec-headers request)
         replacement))))
  request)

(defun notify-provider-response
    (callback status headers model)
  (when callback
    (funcall
     callback
     (list
      :status status
      :headers headers)
     model)))

(defun complete-chat (provider model context
                      &key max-tokens temperature reasoning cache-retention
                        session-id tool-choice metadata abort-p
                        on-payload transform-headers on-response
                        thinking-budgets
                        max-retries max-retry-delay-ms timeout-ms
                        (read-timeout nil read-timeout-supplied-p)
                      &allow-other-keys)
  (handler-case
      (progn
        (check-abort abort-p)
        (let* ((request (build-request provider model context
                                       :stream-p nil
                                       :max-tokens max-tokens
                                       :temperature temperature
                                       :reasoning reasoning
                                       :cache-retention cache-retention
                                       :session-id session-id
                                       :tool-choice tool-choice
                                       :metadata metadata
                                       :thinking-budgets thinking-budgets))
               (_prepared
                 (apply-provider-request-callbacks
                  request model
                  on-payload transform-headers))
               (timeout-seconds
                 (and (integerp timeout-ms) (plusp timeout-ms)
                      (/ timeout-ms 1000)))
               (response
                 (call-with-provider-retries
                  (lambda ()
                    (check-abort abort-p)
                    (apply
                     #'request-json
                     request
                     (append
                      (list
                       :abort-p abort-p
                       :environment
                       (getf (provider-options provider) :environment)
                       :on-response
                       (lambda (status headers)
                         (notify-provider-response
                          on-response
                          status headers model)))
                      (when timeout-seconds
                        (list :connect-timeout timeout-seconds))
                      (cond
                        (read-timeout-supplied-p
                         (list :read-timeout read-timeout))
                        (timeout-seconds
                         (list :read-timeout timeout-seconds))))))
                  :max-retries max-retries
                  :max-retry-delay-ms max-retry-delay-ms
                  :timeout-ms timeout-ms)))
          (declare (ignore _prepared))
          (check-abort abort-p)
          (let ((message
                  (parse-complete-response provider model response)))
            (setf (assistant-message-provider-thinking-level message)
                  (mid-convo-thinking-level model reasoning))
            message)))
    (error (condition)
      (error-assistant-message
       model condition provider))))

(defun stream-chat (provider model context on-event
                    &key max-tokens temperature reasoning cache-retention
                      session-id tool-choice metadata abort-p
                      on-payload transform-headers on-response transport
                      websocket-connect-timeout-ms http-proxy
                      thinking-budgets
                      max-retries max-retry-delay-ms timeout-ms
                      (read-timeout nil read-timeout-supplied-p)
                    &allow-other-keys)
  (let* ((message (empty-assistant-message model reasoning))
         (state (make-provider-stream-state :message message :model model))
         (saw-provider-event-p nil)
         (response-request-id nil)
         (timeout-seconds
           (and (integerp timeout-ms) (plusp timeout-ms)
                (/ timeout-ms 1000))))
    (handler-case
        (progn
          (check-abort abort-p)
          (let ((request (build-request provider model context
                                        :stream-p t
                                        :max-tokens max-tokens
                                        :temperature temperature
                                        :reasoning reasoning
                                        :cache-retention cache-retention
                                        :session-id session-id
                                        :tool-choice tool-choice
                                        :metadata metadata
                                        :thinking-budgets thinking-budgets)))
            (apply-provider-request-callbacks
             request model
             on-payload transform-headers)
            (multiple-value-bind (handled-p websocket-message)
                (try-provider-websocket-stream
                 provider model context request state on-event
                 :transport transport
                 :session-id session-id
                 :abort-p abort-p
                 :on-response on-response
                 :websocket-connect-timeout-ms
                 websocket-connect-timeout-ms
                 :http-proxy http-proxy)
              (when handled-p
                (return-from stream-chat websocket-message)))
            (emit-event on-event :start message)
            (call-with-provider-retries
             (lambda ()
               (check-abort abort-p)
               (apply
                #'request-provider-events
                (prepare-provider-sse-request provider request)
                (lambda (event)
                  (setf saw-provider-event-p t)
                  (check-abort abort-p)
                  (reduce-provider-sse-event
                   provider state event on-event)
                  (check-abort abort-p))
                (append
                 (list
                  :abort-p abort-p
                  :environment
                  (environment-with-http-proxy
                   (getf (provider-options provider) :environment)
                   http-proxy)
                  :on-response
                  (lambda (status headers)
                    (when (typep provider 'bedrock-provider)
                      (setf response-request-id
                            (normalize-bedrock-diagnostic-value
                             (or
                              (header-value
                               headers "x-amzn-requestid")
                              (header-value
                               headers "x-amz-request-id")))))
                    (notify-provider-response
                     on-response status headers
                     model)))
                 (when timeout-seconds
                   (list :connect-timeout timeout-seconds))
                 (when read-timeout-supplied-p
                   (list :read-timeout read-timeout)))))
             :retry-allowed-p
             (lambda (condition)
               (declare (ignore condition))
               (not saw-provider-event-p))
             :max-retries max-retries
             :max-retry-delay-ms max-retry-delay-ms
             :timeout-ms timeout-ms))
          (finalize-provider-stream
           provider model state on-event)
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
          (when (and (eq reason :error)
                     (typep provider 'bedrock-provider))
            (append-bedrock-failure-diagnostic
             message condition response-request-id))
          (emit-event on-event :error message :reason reason))
        message))))

(defconstant +maximum-bedrock-diagnostic-value-characters+ 200)

(defun normalize-bedrock-diagnostic-value (value)
  (when (stringp value)
    (let ((trimmed
            (string-trim
             '(#\Space #\Tab #\Return #\Newline)
             value)))
      (when (<= 1 (length trimmed)
                +maximum-bedrock-diagnostic-value-characters+)
        trimmed))))

(defun bedrock-error-code (condition)
  (let ((code
          (and (typep condition 'api-error)
               (api-error-code condition))))
    (when (and
           (stringp code)
           (uiop:string-suffix-p code "Exception")
           (not (string= code "Unknown")))
      (normalize-bedrock-diagnostic-value code))))

(defun append-bedrock-failure-diagnostic
    (message condition fallback-request-id)
  (let ((details nil))
    (when (and (typep condition 'api-error)
               (numberp (api-error-status condition)))
      (setf (getf details :status)
            (api-error-status condition)))
    (let ((code (bedrock-error-code condition)))
      (when code
        (setf (getf details :error-code) code)))
    (let ((request-id
            (normalize-bedrock-diagnostic-value
             fallback-request-id)))
      (when request-id
        (setf (getf details :request-id) request-id)))
    (when details
      (setf
       (assistant-message-diagnostics message)
       (append
        (assistant-message-diagnostics message)
        (list
         (make-assistant-message-diagnostic
          :type :bedrock-response-failure
          :details details))))))
  message)

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
