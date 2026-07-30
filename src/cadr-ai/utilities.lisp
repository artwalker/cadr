(in-package #:cadr-ai)

(defparameter +non-retryable-assistant-error-fragments+
  '("gousagelimiterror"
    "freeusagelimiterror"
    "monthly usage limit reached"
    "available balance"
    "insufficient_quota"
    "out of budget"
    "quota exceeded"
    "billing"))

(defparameter +retryable-assistant-error-fragments+
  '("overloaded" "rate limit" "rate-limit" "ratelimit"
    "too many requests" "429" "500" "502" "503" "504" "524"
    "service unavailable" "server error" "internal error"
    "provider returned error" "network error" "connection error"
    "connection refused" "connection lost" "other side closed"
    "fetch failed" "getaddrinfo" "enotfound" "eai_again"
    "upstream connect" "reset before headers" "socket hang up"
    "socket connection was closed" "timed out" "timeout"
    "terminated" "websocket closed" "websocket error"
    "ended without" "stream ended before message_stop"
    "stream ended before a terminal response event"
    "http2 request did not get a response" "retry delay"
    "you can retry your request" "try your request again"
    "please retry your request" "resourceexhausted"))

(defun text-contains-any-p (text fragments)
  (some
   (lambda (fragment)
     (search fragment text :test #'char-equal))
   fragments))

(defun retryable-assistant-error-p (message)
  (let ((text (assistant-message-error-message message)))
    (and (eq :error
             (assistant-message-stop-reason message))
         (non-empty-string-p text)
         (not
          (text-contains-any-p
           text +non-retryable-assistant-error-fragments+))
         (text-contains-any-p
          text +retryable-assistant-error-fragments+))))

(defstruct retry-policy
  (enabled-p t :type boolean)
  (max-retries 3 :type (integer 0 *))
  (base-delay-milliseconds 1000
                           :type (integer 0 *)))

(defun retry-assistant-call
    (produce policy
     &key abort-p
       on-retry-scheduled
       on-retry-attempt-start
       on-retry-finished
       (sleep-function #'sleep))
  (let ((attempt 0)
        (last-error nil)
        (maximum
          (if (and policy (retry-policy-enabled-p policy))
              (retry-policy-max-retries policy)
              0)))
    (loop
      (let ((message (funcall produce)))
        (cond
          ((eq :aborted
               (assistant-message-stop-reason message))
           (when (and (plusp attempt)
                      on-retry-finished)
             (funcall on-retry-finished nil attempt nil))
           (return message))
          ((not (eq :error
                    (assistant-message-stop-reason message)))
           (when (and (plusp attempt)
                      on-retry-finished)
             (funcall on-retry-finished t attempt nil))
           (return message))
          ((or (>= attempt maximum)
               (not (retryable-assistant-error-p message)))
           (when (and (plusp attempt)
                      on-retry-finished)
             (funcall
              on-retry-finished nil attempt
              (assistant-message-error-message message)))
           (return message))
          (t
           (incf attempt)
           (setf last-error
                 (or (assistant-message-error-message message)
                     "Unknown error"))
           (let ((delay
                   (* (retry-policy-base-delay-milliseconds policy)
                      (expt 2 (1- attempt)))))
             (when on-retry-scheduled
               (funcall on-retry-scheduled
                        attempt maximum delay last-error))
             (when (and abort-p (funcall abort-p))
               (when on-retry-finished
                 (funcall on-retry-finished
                          nil attempt last-error))
               (return
                 (make-assistant-message
                  :api (assistant-message-api message)
                  :provider (assistant-message-provider message)
                  :model (assistant-message-model message)
                  :content
                  (assistant-message-content message)
                  :usage (assistant-message-usage message)
                  :stop-reason :aborted)))
             (when (plusp delay)
               (funcall sleep-function
                        (/ delay 1000d0)))
             (when (and abort-p (funcall abort-p))
               (when on-retry-finished
                 (funcall on-retry-finished
                          nil attempt last-error))
               (return
                 (make-assistant-message
                  :api (assistant-message-api message)
                  :provider (assistant-message-provider message)
                  :model (assistant-message-model message)
                  :content
                  (assistant-message-content message)
                  :usage (assistant-message-usage message)
                  :stop-reason :aborted)))
             (when on-retry-attempt-start
               (funcall on-retry-attempt-start)))))))))

(defstruct context-usage-estimate
  (tokens 0 :type (integer 0 *))
  (usage-tokens 0 :type (integer 0 *))
  (trailing-tokens 0 :type (integer 0 *))
  (last-usage-index nil :type (or null (integer 0 *))))

(defconstant +estimated-image-characters+ 4800)

(defun estimate-text-tokens (text)
  (ceiling (length text) 4))

(defun estimated-content-characters (content)
  (if (stringp content)
      (length content)
      (loop for block in (coerce (or content nil) 'list)
            sum
            (cond
              ((typep block 'text-content)
               (length (text-content-text block)))
              ((typep block 'image-content)
               +estimated-image-characters+)
              (t 0)))))

(defun estimate-content-tokens (content)
  (ceiling (estimated-content-characters content) 4))

(defun safely-stringify (value)
  (handler-case
      (stringify-json value)
    (error () "[unserializable]")))

(defun estimate-message-tokens (message)
  (cond
    ((typep message 'user-message)
     (estimate-content-tokens (user-message-content message)))
    ((typep message 'tool-result-message)
     (estimate-content-tokens (tool-result-message-content message)))
    ((typep message 'assistant-message)
     (ceiling
      (loop for block in (assistant-message-content message)
            sum
            (cond
              ((typep block 'text-content)
               (length (text-content-text block)))
              ((typep block 'thinking-content)
               (length (thinking-content-thinking block)))
              ((typep block 'tool-call)
               (+ (length (tool-call-name block))
                  (length
                   (safely-stringify
                    (tool-call-arguments block)))))
              (t 0)))
      4))
    (t 0)))

(defun message-timestamp (message)
  (etypecase message
    (user-message (user-message-timestamp message))
    (assistant-message (assistant-message-timestamp message))
    (tool-result-message (tool-result-message-timestamp message))))

(defun applicable-usage-info (messages)
  (loop with latest-prefix-timestamp = most-negative-fixnum
        with result = nil
        for message in messages
        for index from 0
        do
        (when (typep message 'assistant-message)
          (let ((usage (assistant-message-usage message)))
            (when (and
                   (>= (assistant-message-timestamp message)
                       latest-prefix-timestamp)
                   (not
                    (member (assistant-message-stop-reason message)
                            '(:aborted :error)))
                   (plusp (usage-total usage)))
              (setf result (cons index usage)))))
        (setf latest-prefix-timestamp
              (max latest-prefix-timestamp
                   (message-timestamp message)))
        finally (return result)))

(defun estimate-message-list (messages)
  (let ((usage-info (applicable-usage-info messages)))
    (if usage-info
        (let* ((index (car usage-info))
               (usage-tokens (usage-total (cdr usage-info)))
               (trailing
                 (loop for message in (nthcdr (1+ index) messages)
                       sum (estimate-message-tokens message))))
          (make-context-usage-estimate
           :tokens (+ usage-tokens trailing)
           :usage-tokens usage-tokens
           :trailing-tokens trailing
           :last-usage-index index))
        (let ((tokens
                (loop for message in messages
                      sum (estimate-message-tokens message))))
          (make-context-usage-estimate
           :tokens tokens
           :trailing-tokens tokens)))))

(defun tool-estimate-object (tool)
  (json-object
   "name" (tool-name tool)
   "description" (tool-description tool)
   "parameters" (tool-parameters tool)))

(defun estimate-tools-tokens (tools)
  (if tools
      (estimate-text-tokens
       (safely-stringify
        (list-json-array
         (mapcar #'tool-estimate-object tools))))
      0))

(defun estimate-context-tokens (context-or-messages)
  (if (typep context-or-messages 'context)
      (let* ((context context-or-messages)
             (messages (context-messages context))
             (estimate (estimate-message-list messages))
             (last-index
               (context-usage-estimate-last-usage-index estimate))
             (prefix-tokens
               (if last-index
                   (let ((names
                           (loop for message in
                                 (nthcdr (1+ last-index) messages)
                                 when
                                 (typep message 'tool-result-message)
                                   append
                                   (tool-result-message-added-tool-names
                                    message))))
                     (estimate-tools-tokens
                      (remove-if-not
                       (lambda (tool)
                         (member (tool-name tool)
                                 names :test #'string=))
                       (context-tools context))))
                   (+
                    (if (context-system-prompt context)
                        (estimate-text-tokens
                         (context-system-prompt context))
                        0)
                    (estimate-tools-tokens
                     (context-tools context))))))
        (incf (context-usage-estimate-tokens estimate)
              prefix-tokens)
        (incf (context-usage-estimate-trailing-tokens estimate)
              prefix-tokens)
        estimate)
      (estimate-message-list context-or-messages)))

(defparameter +overflow-fragments+
  '("prompt is too long"
    "request_too_large"
    "input is too long for requested model"
    "exceeds the context window"
    "maximum context length"
    "input token count"
    "maximum prompt length is"
    "reduce the length of the messages"
    "maximum allowed input length"
    "is longer than the model's context length"
    "exceeds the limit of"
    "exceeds the available context size"
    "greater than the context length"
    "context window exceeds limit"
    "exceeded model token limit"
    "too large for model with"
    "configured context size"
    "model_context_window_exceeded"
    "prompt too long; exceeded"
    "range of input length should be"
    "context_length_exceeded"
    "context length exceeded"
    "too many tokens"
    "token limit exceeded"))

(defparameter +non-overflow-fragments+
  '("throttling error:"
    "service unavailable:"
    "rate limit"
    "too many requests"))

(defun contains-ci-p (needle haystack)
  (and (search needle haystack :test #'char-equal) t))

(defun bare-overflow-http-status-p (text)
  (let ((trimmed
          (string-left-trim '(#\Space #\Tab #\Newline) text)))
    (and
     (or (uiop:string-prefix-p "400" trimmed)
         (uiop:string-prefix-p "413" trimmed))
     (contains-ci-p "no body" trimmed))))

(defun context-overflow-p (message &optional context-window)
  (or
   (and
    (eq :error (assistant-message-stop-reason message))
    (assistant-message-error-message message)
    (notany
     (lambda (fragment)
       (contains-ci-p
        fragment (assistant-message-error-message message)))
     +non-overflow-fragments+)
    (or
     (some
      (lambda (fragment)
        (contains-ci-p
         fragment (assistant-message-error-message message)))
      +overflow-fragments+)
     (bare-overflow-http-status-p
      (assistant-message-error-message message))))
   (and
    context-window
    (eq :stop (assistant-message-stop-reason message))
    (>
     (+ (usage-input (assistant-message-usage message))
        (usage-cache-read (assistant-message-usage message)))
     context-window))
   (and
    context-window
    (eq :length (assistant-message-stop-reason message))
    (zerop (usage-output (assistant-message-usage message)))
    (>=
     (+ (usage-input (assistant-message-usage message))
        (usage-cache-read (assistant-message-usage message)))
     (* context-window 0.99d0)))))

(defstruct grammar-json-buffer
  (input "" :type string)
  (started-p nil :type boolean)
  (closed-p nil :type boolean))

(defun json-string-interior (value)
  (let ((encoded (stringify-json value)))
    (subseq encoded 1 (1- (length encoded)))))

(defun append-grammar-json-delta
    (buffer input-property next-input close-p)
  (when (grammar-json-buffer-closed-p buffer)
    (if (and close-p
             (string=
              next-input (grammar-json-buffer-input buffer)))
        (return-from append-grammar-json-delta nil)
        (error
         "grammar tool input for property ~S changed after it was closed"
         input-property)))
  (unless
      (uiop:string-prefix-p
       (grammar-json-buffer-input buffer) next-input)
    (error
     "grammar tool input for property ~S changed non-monotonically"
     input-property))
  (let* ((old (grammar-json-buffer-input buffer))
         (input-delta (subseq next-input (length old))))
    (when (and (not close-p)
               (zerop (length input-delta)))
      (return-from append-grammar-json-delta nil))
    (prog1
        (with-output-to-string (output)
          (unless (grammar-json-buffer-started-p buffer)
            (format output "{~A:\""
                    (stringify-json input-property))
            (setf (grammar-json-buffer-started-p buffer) t))
          (write-string (json-string-interior input-delta) output)
          (when close-p
            (write-string "\"}" output)
            (setf (grammar-json-buffer-closed-p buffer) t)))
      (setf (grammar-json-buffer-input buffer) next-input))))

(defun schema-types (schema)
  (let ((type (json-get schema "type")))
    (cond
      ((stringp type) (list type))
      ((vectorp type)
       (remove-if-not #'stringp (coerce type 'list)))
      ((listp type) (remove-if-not #'stringp type))
      (t nil))))

(defun json-object-p (value)
  (hash-table-p value))

(defun json-type-p (value type)
  (cond
    ((string= type "number") (numberp value))
    ((string= type "integer") (integerp value))
    ((string= type "boolean") (or (eq value t) (null value)))
    ((string= type "string") (stringp value))
    ((string= type "null") (json-null-p value))
    ((string= type "array") (or (vectorp value) (listp value)))
    ((string= type "object") (json-object-p value))
    (t nil)))

(defun parse-coercible-number (value integer-p)
  (when (and (stringp value)
             (plusp (length (string-trim '(#\Space #\Tab) value))))
    (handler-case
        (multiple-value-bind (number position)
            (read-from-string value)
          (when (and (numberp number)
                     (or (not integer-p) (integerp number))
                     (= position (length value)))
            number))
      (error () nil))))

(defun coerce-primitive (value type)
  (cond
    ((string= type "number")
     (cond
       ((json-null-p value) (values 0 t))
       ((or (eq value t) (null value))
        (values (if value 1 0) t))
       ((parse-coercible-number value nil)
        (values (parse-coercible-number value nil) t))
       (t (values value nil))))
    ((string= type "integer")
     (cond
       ((json-null-p value) (values 0 t))
       ((or (eq value t) (null value))
        (values (if value 1 0) t))
       ((parse-coercible-number value t)
        (values (parse-coercible-number value t) t))
       (t (values value nil))))
    ((string= type "boolean")
     (cond
       ((json-null-p value) (values nil t))
       ((and (stringp value) (string= value "true"))
        (values t t))
       ((and (stringp value) (string= value "false"))
        (values nil t))
       ((and (numberp value) (= value 1)) (values t t))
       ((and (numberp value) (zerop value)) (values nil t))
       (t (values value nil))))
    ((string= type "string")
     (cond
       ((json-null-p value) (values "" t))
       ((eq value t) (values "true" t))
       ((null value) (values "false" t))
       ((numberp value) (values (princ-to-string value) t))
       (t (values value nil))))
    ((string= type "null")
     (if (or (and (stringp value) (string= value ""))
             (and (numberp value) (zerop value))
             (null value))
         (values 'null t)
         (values value nil)))
    (t (values value nil))))

(defun schema-valid-p (value schema)
  (let ((types (schema-types schema)))
    (and
     (or (null types)
         (some (lambda (type) (json-type-p value type)) types))
     (or
      (not (json-object-p value))
      (not (member "object" types :test #'string=))
      (let ((properties (json-get schema "properties"))
            (required
              (coerce (or (json-get schema "required") #()) 'list)))
        (and
         (every
          (lambda (name) (json-present-p value name))
          required)
         (or
          (not (hash-table-p properties))
          (loop for key being the hash-keys of properties
                always
                (or
                 (not (json-present-p value key))
                 (schema-valid-p
                  (json-get value key)
                  (json-get properties key))))))))
     (or
      (not
       (and (member "array" types :test #'string=)
            (or (vectorp value) (listp value))))
      (let ((items (json-get schema "items")))
        (or
         (not (hash-table-p items))
         (every
          (lambda (item) (schema-valid-p item items))
          (coerce value 'list))))))))

(defun coerce-schema-value (value schema)
  (let ((types (schema-types schema))
        (next value))
    (unless
        (and (> (length types) 1)
             (some (lambda (type) (json-type-p next type)) types))
      (dolist (type types)
        (multiple-value-bind (candidate changed-p)
            (coerce-primitive next type)
          (when changed-p
            (setf next candidate)
            (return)))))
    (when
        (and (hash-table-p next)
             (member "object" types :test #'string=))
      (let ((properties (json-get schema "properties"))
            (additional (json-get schema "additionalProperties")))
        (when (hash-table-p properties)
          (loop for key being the hash-keys of next
                for nested =
                (if (json-present-p properties key)
                    (json-get properties key)
                    (and (hash-table-p additional) additional))
                when nested
                  do
                  (setf (gethash key next)
                        (coerce-schema-value
                         (gethash key next) nested))))))
    (when
        (and (or (vectorp next) (listp next))
             (member "array" types :test #'string=)
             (hash-table-p (json-get schema "items")))
      (if (vectorp next)
          (loop for index below (length next)
                do
                (setf (aref next index)
                      (coerce-schema-value
                       (aref next index)
                       (json-get schema "items"))))
          (setf next
                (mapcar
                 (lambda (item)
                   (coerce-schema-value
                    item (json-get schema "items")))
                 next))))
    next))

(defun copy-json-value (value)
  (parse-json (stringify-json value)))

(defun validate-tool-arguments (tool call)
  (let* ((schema (tool-parameters tool))
         (arguments
           (copy-json-value (tool-call-arguments call)))
         (coerced (coerce-schema-value arguments schema)))
    (unless (schema-valid-p coerced schema)
      (error
       "Validation failed for tool ~S.~%Received arguments:~%~A"
       (tool-call-name call)
       (stringify-json (tool-call-arguments call))))
    coerced))

(defun validate-tool-call (tools call)
  (let ((tool
          (find
           (tool-call-name call) tools
           :key #'tool-name :test #'string=)))
    (unless tool
      (error "Tool ~S not found" (tool-call-name call)))
    (validate-tool-arguments tool call)))

(defparameter *uuid-last-timestamp* -1)
(defparameter *uuid-sequence* 0)

(defun default-random-octets (count)
  (let ((result
          (make-array count :element-type '(unsigned-byte 8))))
    (with-open-file
        (stream #P"/dev/urandom"
                :direction :input
                :element-type '(unsigned-byte 8))
      (read-sequence result stream))
    result))

(defun uuid-v7
    (&key
       (timestamp (unix-milliseconds))
       (random-source #'default-random-octets))
  (let ((random (funcall random-source 16)))
    (if (> timestamp *uuid-last-timestamp*)
        (setf
         *uuid-sequence*
         (+ (ash (aref random 6) 24)
            (ash (aref random 7) 16)
            (ash (aref random 8) 8)
            (aref random 9))
         *uuid-last-timestamp* timestamp)
        (progn
          (setf *uuid-sequence*
                (ldb (byte 32 0) (1+ *uuid-sequence*)))
          (when (zerop *uuid-sequence*)
            (incf *uuid-last-timestamp*))))
    (let ((bytes
            (make-array
             16 :element-type '(unsigned-byte 8)
             :initial-element 0)))
      (dotimes (index 6)
        (setf
         (aref bytes index)
         (ldb
          (byte 8 (* 8 (- 5 index)))
          *uuid-last-timestamp*)))
      (setf
       (aref bytes 6)
       (logior #x70 (ldb (byte 4 28) *uuid-sequence*))
       (aref bytes 7)
       (ldb (byte 8 20) *uuid-sequence*)
       (aref bytes 8)
       (logior #x80 (ldb (byte 6 14) *uuid-sequence*))
       (aref bytes 9)
       (ldb (byte 8 6) *uuid-sequence*)
       (aref bytes 10)
       (logior
        (ash (ldb (byte 6 0) *uuid-sequence*) 2)
        (logand (aref random 10) #x03)))
      (loop for index from 11 below 16
            do (setf (aref bytes index) (aref random index)))
      (let ((hex (octets-hex bytes)))
        (format nil "~A-~A-~A-~A-~A"
                (subseq hex 0 8)
                (subseq hex 8 12)
                (subseq hex 12 16)
                (subseq hex 16 20)
                (subseq hex 20 32))))))
