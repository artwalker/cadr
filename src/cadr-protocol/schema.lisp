(in-package #:cadr-protocol)

(defconstant +protocol-version+ 2)

(define-condition protocol-validation-error (error)
  ((message
    :initarg :message
    :reader protocol-validation-error-message))
  (:report
   (lambda (condition stream)
     (write-string
      (protocol-validation-error-message condition)
      stream))))

(defun protocol-fail (message)
  (error 'protocol-validation-error
         :message message))

(defun protocol-object-p (value)
  (hash-table-p value))

(defun object-present-p (object key)
  (and (protocol-object-p object)
       (nth-value 1 (gethash key object))))

(defun object-value (object key)
  (and (protocol-object-p object)
       (gethash key object)))

(defun optional-field-p (object key predicate)
  ;; Absent-or-valid is one decision. The copied
  ;; (or (not present) (pred ...)) form made each new optional
  ;; key a second owner of the same guard.
  (or (not (object-present-p object key))
      (funcall predicate (object-value object key))))

(defun sequence-value-p (value)
  (and (vectorp value)
       (not (typep value
                   '(vector (unsigned-byte 8))))))

(defun exact-object-keys-p (object required optional)
  (and
   (protocol-object-p object)
   (every
    (lambda (key)
      (object-present-p object key))
    required)
   (loop for key being the hash-keys of object
         always (or (member key required :test #'string=)
                    (member key optional :test #'string=)))))

(defun nonempty-string-p (value)
  (and (stringp value)
       (plusp (length value))))

(defun timestamp-p (value)
  (and (integerp value)
       (not (minusp value))))

(defun json-value-p
    (value &optional (ancestors (make-hash-table :test #'eq)))
  (cond
    ((or (eq value 'null)
         (null value)
         (eq value t)
         (stringp value))
     t)
    ((realp value)
     (finite-real-p value))
    ((sequence-value-p value)
     (unless (gethash value ancestors)
       (setf (gethash value ancestors) t)
       (unwind-protect
            (loop for item across value
                  always (json-value-p item ancestors))
         (remhash value ancestors))))
    ((protocol-object-p value)
     (unless (gethash value ancestors)
       (setf (gethash value ancestors) t)
       (unwind-protect
            (loop for key being the hash-keys of value
                    using (hash-value item)
                  always (and (stringp key)
                              (json-value-p item ancestors)))
         (remhash value ancestors))))
    (t nil)))

(defun one-of-string-p (value choices)
  (and (stringp value)
       (member value choices :test #'string=)))

(defun model-ref-p (value)
  (and
   (exact-object-keys-p
    value '("provider" "id") nil)
   (nonempty-string-p (object-value value "provider"))
   (nonempty-string-p (object-value value "id"))))

(defun thinking-level-p (value)
  (one-of-string-p
   value
   '("off" "minimal" "low" "medium"
     "high" "xhigh" "max")))

(defun session-phase-p (value)
  (one-of-string-p
   value
   '("idle" "turn" "compaction"
     "branch_summary" "retry")))

(defun all-sequence-p (value predicate)
  (and (sequence-value-p value)
       (loop for item across value
             always (funcall predicate item))))

(defun cost-p (value)
  (and
   (exact-object-keys-p
    value
    '("input" "output" "cacheRead" "cacheWrite")
    nil)
   (every
    (lambda (key)
      (let ((number (object-value value key)))
        (and (realp number)
             (not (minusp number))
             (finite-real-p number))))
    '("input" "output" "cacheRead" "cacheWrite"))))

(defun model-metadata-p (value)
  (and
   (exact-object-keys-p
    value
    '("provider" "id" "name" "api" "reasoning"
      "input" "contextWindow" "maxTokens" "cost"
      "supportedThinkingLevels" "authenticated")
    nil)
   (every
    (lambda (key)
      (nonempty-string-p (object-value value key)))
    '("provider" "id" "name" "api"))
   (member (object-value value "reasoning") '(nil t))
   (all-sequence-p
    (object-value value "input")
    (lambda (item)
      (one-of-string-p item '("text" "image"))))
   (every
    (lambda (key)
      (let ((number (object-value value key)))
        (and (integerp number) (plusp number))))
    '("contextWindow" "maxTokens"))
   (cost-p (object-value value "cost"))
   (let ((levels
           (object-value value "supportedThinkingLevels")))
     (and (sequence-value-p levels)
          (plusp (length levels))
          (loop for level across levels
                always (thinking-level-p level))))
   (member (object-value value "authenticated") '(nil t))))

(defun usage-p (value)
  (and
   (exact-object-keys-p
    value
    '("input" "output" "cacheRead" "cacheWrite"
      "totalTokens" "cost")
    '("reasoning"))
   (every
    (lambda (key)
      (timestamp-p (object-value value key)))
    '("input" "output" "cacheRead" "cacheWrite"
      "totalTokens"))
   (optional-field-p value "reasoning" #'timestamp-p)
   (let ((cost (object-value value "cost")))
     (and (exact-object-keys-p
           cost
           '("input" "output" "cacheRead" "cacheWrite"
             "total")
           nil)
          (every
           (lambda (key)
             (let ((number (object-value cost key)))
               (and (realp number)
                    (not (minusp number))
                    (finite-real-p number))))
           '("input" "output" "cacheRead" "cacheWrite"
             "total"))))))

(defun content-p (value allowed)
  (and
   (protocol-object-p value)
   (let ((type (object-value value "type")))
     (cond
       ((and (member "text" allowed :test #'string=)
             (string= type "text"))
        (and
         (exact-object-keys-p
          value '("type" "text") nil)
         (stringp (object-value value "text"))))
       ((and (member "thinking" allowed :test #'string=)
             (string= type "thinking"))
        (and
         (exact-object-keys-p
          value '("type" "thinking") '("redacted"))
         (stringp (object-value value "thinking"))
         (optional-field-p
          value "redacted"
          (lambda (item)
            (member item '(nil t))))))
       ((and (member "image" allowed :test #'string=)
             (string= type "image"))
        (and
         (exact-object-keys-p
          value '("type" "data" "mimeType") nil)
         (stringp (object-value value "data"))
         (nonempty-string-p
          (object-value value "mimeType"))))
       ((and (member "tool_call" allowed :test #'string=)
             (string= type "tool_call"))
        (and
         (exact-object-keys-p
          value
          '("type" "toolCallId" "toolName" "input")
          nil)
         (nonempty-string-p
          (object-value value "toolCallId"))
         (nonempty-string-p
          (object-value value "toolName"))
         (json-value-p
          (object-value value "input"))))
       (t nil)))))

(defun transcript-item-p (value)
  (and
   (protocol-object-p value)
   (let ((role (object-value value "role")))
     (cond
       ((string= role "user")
        (and
         (exact-object-keys-p
          value '("id" "role" "content" "timestamp") nil)
         (nonempty-string-p (object-value value "id"))
         (all-sequence-p
          (object-value value "content")
          (lambda (content)
            (content-p content '("text" "image"))))
         (timestamp-p (object-value value "timestamp"))))
       ((string= role "assistant")
        (and
         (exact-object-keys-p
          value
          '("id" "role" "content" "status" "model"
            "timestamp")
          '("responseModel" "usage" "stopReason"
            "errorMessage"))
         (nonempty-string-p (object-value value "id"))
         (all-sequence-p
          (object-value value "content")
          (lambda (content)
            (content-p
             content '("text" "thinking" "tool_call"))))
         (one-of-string-p
          (object-value value "status")
          '("streaming" "complete" "error" "aborted"))
         (model-ref-p (object-value value "model"))
         (optional-field-p
          value "responseModel" #'nonempty-string-p)
         (optional-field-p value "usage" #'usage-p)
         (optional-field-p
          value "stopReason"
          (lambda (item)
            (one-of-string-p
             item
             '("stop" "length" "tool_use"
               "error" "aborted"))))
         (optional-field-p value "errorMessage" #'stringp)
         (timestamp-p (object-value value "timestamp"))))
       ((string= role "tool")
        (and
         (exact-object-keys-p
          value
          '("id" "role" "toolCallId" "toolName" "input"
            "content" "status" "isError" "timestamp")
          '("details" "usage"))
         (every
          (lambda (key)
            (nonempty-string-p (object-value value key)))
          '("id" "toolCallId" "toolName"))
         (json-value-p (object-value value "input"))
         (all-sequence-p
          (object-value value "content")
          (lambda (content)
            (content-p content '("text" "image"))))
         (optional-field-p value "details" #'json-value-p)
         (one-of-string-p
          (object-value value "status")
          '("running" "complete" "error"))
         (member (object-value value "isError") '(nil t))
         (optional-field-p value "usage" #'usage-p)
         (timestamp-p (object-value value "timestamp"))))
       (t nil)))))

(defun session-summary-p (value &optional snapshot-p)
  (and
   (exact-object-keys-p
    value
    (append
     '("id" "cwd" "createdAt" "updatedAt" "phase"
       "model" "thinkingLevel" "attached" "locked")
     (when snapshot-p
       '("revision" "transcript" "queuedSteer"
         "queuedSteerCount")))
    '("name"))
   (nonempty-string-p (object-value value "id"))
   (optional-field-p value "name" #'stringp)
   (nonempty-string-p (object-value value "cwd"))
   (timestamp-p (object-value value "createdAt"))
   (timestamp-p (object-value value "updatedAt"))
   (session-phase-p (object-value value "phase"))
   (model-ref-p (object-value value "model"))
   (thinking-level-p
    (object-value value "thinkingLevel"))
   (member (object-value value "attached") '(nil t))
   (member (object-value value "locked") '(nil t))
   (or
    (not snapshot-p)
    (and
     (timestamp-p (object-value value "revision"))
     (all-sequence-p
      (object-value value "transcript")
      #'transcript-item-p)
     (all-sequence-p
      (object-value value "queuedSteer")
      (lambda (item)
        (and (transcript-item-p item)
             (string=
              "user" (object-value item "role")))))
     (timestamp-p
      (object-value value "queuedSteerCount"))))))

(defun server-snapshot-p (value)
  (and
   (exact-object-keys-p
    value
    '("serverId" "protocolVersion" "revision"
      "sessions" "models")
    nil)
   (nonempty-string-p (object-value value "serverId"))
   (eql +protocol-version+
        (object-value value "protocolVersion"))
   (timestamp-p (object-value value "revision"))
   (all-sequence-p
    (object-value value "sessions")
    #'session-summary-p)
   (all-sequence-p
    (object-value value "models")
    #'model-metadata-p)))

(defun protocol-error-p (value)
  (and
   (exact-object-keys-p
    value '("code" "message") '("details"))
   (one-of-string-p
    (object-value value "code")
    '("auth" "version" "busy" "session_locked"
      "not_found" "invalid_request"))
   (stringp (object-value value "message"))
   (optional-field-p value "details" #'json-value-p)))

(defun command-p (value)
  (and
   (protocol-object-p value)
   (let ((command (object-value value "command")))
     (cond
       ((string= command "list")
        (exact-object-keys-p value '("command") nil))
       ((string= command "create")
        (and
         (exact-object-keys-p
          value '("command")
          '("cwd" "name" "model" "thinkingLevel"))
         (optional-field-p
          value "cwd" #'nonempty-string-p)
         (optional-field-p value "name" #'stringp)
         (optional-field-p value "model" #'model-ref-p)
         (optional-field-p
          value "thinkingLevel" #'thinking-level-p)))
       ((member command '("attach" "detach" "abort")
                :test #'string=)
        (and
         (exact-object-keys-p
          value '("command" "sessionId") nil)
         (nonempty-string-p
          (object-value value "sessionId"))))
       ((member command '("prompt" "steer")
                :test #'string=)
        (and
         (exact-object-keys-p
          value '("command" "sessionId" "text") nil)
         (nonempty-string-p
          (object-value value "sessionId"))
         (stringp (object-value value "text"))))
       ((string= command "set_model")
        (and
         (exact-object-keys-p
          value '("command" "sessionId" "model") nil)
         (nonempty-string-p
          (object-value value "sessionId"))
         (model-ref-p (object-value value "model"))))
       ((string= command "set_thinking")
        (and
         (exact-object-keys-p
          value
          '("command" "sessionId" "thinkingLevel")
          nil)
         (nonempty-string-p
          (object-value value "sessionId"))
         (thinking-level-p
          (object-value value "thinkingLevel"))))
       (t nil)))))

(defun command-result-p (value)
  (and
   (protocol-object-p value)
   (let ((command (object-value value "command")))
     (cond
       ((string= command "list")
        (and
         (exact-object-keys-p
          value '("command" "sessions") nil)
         (all-sequence-p
          (object-value value "sessions")
          #'session-summary-p)))
       ((string= command "detach")
        (and
         (exact-object-keys-p
          value '("command" "sessionId") nil)
         (nonempty-string-p
          (object-value value "sessionId"))))
       ((member
         command
         '("create" "attach" "prompt" "steer" "abort"
           "set_model" "set_thinking")
         :test #'string=)
        (and
         (exact-object-keys-p
          value '("command" "session") nil)
         (session-summary-p
          (object-value value "session") t)))
       (t nil)))))

(defun transcript-progress-p (value)
  (and
   (protocol-object-p value)
   (let ((type (object-value value "type")))
     (cond
       ((string= type "item_started")
        (and
         (exact-object-keys-p value '("type" "item") nil)
         (transcript-item-p (object-value value "item"))))
       ((string= type "assistant_delta")
        (and
         (exact-object-keys-p
          value
          '("type" "messageId" "contentIndex" "kind"
            "delta")
          nil)
         (nonempty-string-p
          (object-value value "messageId"))
         (timestamp-p (object-value value "contentIndex"))
         (one-of-string-p
          (object-value value "kind")
          '("text" "thinking" "tool_call"))
         (stringp (object-value value "delta"))))
       ((member type '("item_updated" "item_finished")
                :test #'string=)
        (and
         (exact-object-keys-p value '("type" "item") nil)
         (let ((item (object-value value "item")))
           (and (transcript-item-p item)
                (member
                 (object-value item "role")
                 '("assistant" "tool")
                 :test #'string=)))))
       (t nil)))))

(defun server-event-p (value)
  (and
   (protocol-object-p value)
   (let ((type (object-value value "type")))
     (cond
       ((string= type "server_snapshot")
        (and
         (exact-object-keys-p
          value '("type" "snapshot") nil)
         (server-snapshot-p
          (object-value value "snapshot"))))
       ((string= type "session_snapshot")
        (and
         (exact-object-keys-p
          value '("type" "snapshot") nil)
         (session-summary-p
          (object-value value "snapshot") t)))
       ((string= type "session_progress")
        (and
         (exact-object-keys-p
          value
          '("type" "sessionId" "progress") nil)
         (nonempty-string-p
          (object-value value "sessionId"))
         (transcript-progress-p
          (object-value value "progress"))))
       ((string= type "session_removed")
        (and
         (exact-object-keys-p
          value '("type" "sessionId") nil)
         (nonempty-string-p
          (object-value value "sessionId"))))
       (t nil)))))

(defun client-message-p (value)
  (and
   (protocol-object-p value)
   (let ((type (object-value value "type")))
     (cond
       ((string= type "hello")
        (and
         (exact-object-keys-p
          value '("type" "version" "token") nil)
         (let ((version (object-value value "version")))
           (and (integerp version)
                (not (minusp version))))
         (nonempty-string-p (object-value value "token"))))
       ((string= type "request")
        (and
         (exact-object-keys-p
          value '("type" "id" "request") nil)
         (nonempty-string-p (object-value value "id"))
         (command-p (object-value value "request"))))
       (t nil)))))

(defun server-message-p (value)
  (and
   (protocol-object-p value)
   (let ((type (object-value value "type")))
     (cond
       ((string= type "hello")
        (and
         (exact-object-keys-p
          value
          '("type" "version" "connectionId" "snapshot")
          nil)
         (eql +protocol-version+
              (object-value value "version"))
         (nonempty-string-p
          (object-value value "connectionId"))
         (server-snapshot-p
          (object-value value "snapshot"))))
       ((string= type "hello_error")
        (and
         (exact-object-keys-p
          value '("type" "error") nil)
         (protocol-error-p
          (object-value value "error"))))
       ((string= type "response")
        (and
         (nonempty-string-p (object-value value "id"))
         (let ((ok (object-value value "ok")))
           (cond
             ((eq ok t)
              (and
               (exact-object-keys-p
                value
                '("type" "id" "ok" "result") nil)
               (command-result-p
                (object-value value "result"))))
             ((null ok)
              (and
               (exact-object-keys-p
                value
                '("type" "id" "ok" "error") nil)
               (protocol-error-p
                (object-value value "error"))))
             (t nil)))))
       ((string= type "event")
        (and
         (exact-object-keys-p
          value '("type" "event") nil)
         (server-event-p
          (object-value value "event"))))
       (t nil)))))

(defun parse-client-message (value)
  (unless (and (json-value-p value)
               (client-message-p value))
    (protocol-fail
     "Invalid client protocol message"))
  value)

(defun parse-server-message (value)
  (unless (and (json-value-p value)
               (server-message-p value))
    (protocol-fail
     "Invalid server protocol message"))
  value)

(defun supported-protocol-version-p (version)
  (and (integerp version)
       (= version +protocol-version+)))
