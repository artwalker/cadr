(in-package #:cadr-protocol/tests)
(in-suite cadr-protocol-suite)

(defun empty-server-snapshot ()
  (protocol-object
   "serverId" "server-1"
   "protocolVersion" cadr-protocol:+protocol-version+
   "revision" 0
   "sessions" #()
   "models" #()))

(defun client-hello (&optional (version cadr-protocol:+protocol-version+))
  (protocol-object
   "type" "hello"
   "version" version
   "token" "secret"))

(defun server-hello ()
  (protocol-object
   "type" "hello"
   "version" cadr-protocol:+protocol-version+
   "connectionId" "connection-1"
   "snapshot" (empty-server-snapshot)))

(test protocol-uses-version-2
  (is (= 2 cadr-protocol:+protocol-version+))
  (is (cadr-protocol:supported-protocol-version-p 2))
  (is (not (cadr-protocol:supported-protocol-version-p 1)))
  (is (not (cadr-protocol:supported-protocol-version-p 2.5d0))))

(test protocol-accepts-integer-client-hello-for-negotiation
  (dolist (version (list 0 1 cadr-protocol:+protocol-version+))
    (let ((message (client-hello version)))
      (is (eq message
              (cadr-protocol:parse-client-message message))))))

(test protocol-rejects-invalid-strict-client-handshake
  (dolist (message
           (list
            (protocol-object
             "type" "hello" "version" "2" "token" "secret")
            (protocol-object
             "type" "hello" "version" 2.5d0 "token" "secret")
            (protocol-object
             "type" "hello" "version" 2 "token" "")
            (protocol-object
             "type" "hello" "version" 2 "token" "secret"
             "extra" t)))
    (signals cadr-protocol:protocol-validation-error
      (cadr-protocol:parse-client-message message))))

(test protocol-does-not-parse-json-strings-as-wire-messages
  (signals cadr-protocol:protocol-validation-error
    (cadr-protocol:parse-client-message
     "{\"type\":\"hello\",\"version\":2,\"token\":\"secret\"}"))
  (signals cadr-protocol:protocol-validation-error
    (cadr-protocol:parse-server-message
     "{\"type\":\"hello\",\"version\":2}")))

(test protocol-rejects-image-input-while-text-only
  (signals cadr-protocol:protocol-validation-error
    (cadr-protocol:parse-client-message
     (protocol-object
      "type" "request"
      "id" "request-1"
      "request"
      (protocol-object
       "command" "prompt"
       "sessionId" "session-1"
       "text" "inspect"
       "images"
       (vector
        (protocol-object
         "type" "image"
         "data" "abc"
         "mimeType" "image/png")))))))

(test protocol-parses-server-handshake-snapshot
  (let ((message (server-hello)))
    (is (eq message
            (cadr-protocol:parse-server-message message)))))

(test protocol-rejects-invalid-server-messages
  (dolist (wire
           (list
            (protocol-object
             "type" "hello"
             "version" 1
             "connectionId" "connection-1"
             "snapshot" (empty-server-snapshot))
            (protocol-object
             "type" "response"
             "id" "request-1"
             "ok" t
             "result" (protocol-object "command" "unknown"))
            (protocol-object
             "type" "event"
             "event"
             (protocol-object
              "type" "session_removed"
              "sessionId" 42))))
    (signals cadr-protocol:protocol-validation-error
      (cadr-protocol:parse-server-message wire))))

(test protocol-preserves-existing-command-and-error-schema-coverage
  (let ((request
          (protocol-object
           "type" "request"
           "id" "request-1"
           "request"
           (protocol-object
            "command" "create"
            "cwd" "/tmp/work"
            "name" "demo"))))
    (is (eq request
            (cadr-protocol:parse-client-message request))))
  (signals cadr-protocol:protocol-validation-error
    (cadr-protocol:parse-server-message
     (protocol-object
      "type" "hello_error"
      "error"
      (protocol-object "code" "bogus" "message" "bad")))))

(test protocol-validates-nested-json-tool-details
  (let ((message
          (protocol-object
           "type" "event"
           "event"
           (protocol-object
            "type" "session_progress"
            "sessionId" "session-1"
            "progress"
            (protocol-object
             "type" "item_finished"
             "item"
             (protocol-object
              "id" "tool-1"
              "role" "tool"
              "toolCallId" "call-1"
              "toolName" "read"
              "input" (protocol-object "path" "/tmp/file")
              "content"
              (vector (protocol-object "type" "text"
                                       "text" "done"))
              "details"
              (protocol-object "lines" #(1 2 3)
                               "cached" nil)
              "status" "complete"
              "isError" nil
              "timestamp" 1))))))
    (is (eq message
            (cadr-protocol:parse-server-message message)))))

(test protocol-rejects-cyclic-values-as-validation-errors
  (let* ((details (protocol-object))
         (message
           (protocol-object
            "type" "response"
            "id" "request-1"
            "ok" nil
            "error"
            (protocol-object
             "code" "invalid_request"
             "message" "invalid"
             "details" details))))
    (setf (gethash "self" details) details)
    (signals cadr-protocol:protocol-validation-error
      (cadr-protocol:parse-server-message message))))

(test protocol-validation-errors-do-not-retain-rejected-payloads
  (let ((condition nil))
    (handler-case
        (cadr-protocol:parse-client-message
         (protocol-object
          "type" "hello"
          "version" "2"
          "token" (make-string 2000000
                               :initial-element #\x)))
      (cadr-protocol:protocol-validation-error (error)
        (setf condition error)))
    (is (typep condition
               'cadr-protocol:protocol-validation-error))
    (is (< (length (princ-to-string condition)) 1000))
    (is (not (search (make-string 1000 :initial-element #\x)
                     (princ-to-string condition))))))

(test protocol-encodes-complete-client-and-server-frames
  (let* ((hello (client-hello))
         (frame-decoder (cadr-protocol:make-frame-decoder))
         (frames
           (cadr-protocol:frame-decoder-push
            frame-decoder
            (cadr-protocol:encode-client-message hello))))
    (is (= 1 (length frames)))
    (is (protocol-value=
         hello
         (cadr-protocol:parse-client-message
          (cadr-protocol:decode-cbor (first frames))))))
  (let* ((hello (server-hello))
         (frame-decoder (cadr-protocol:make-frame-decoder))
         (frames
           (cadr-protocol:frame-decoder-push
            frame-decoder
            (cadr-protocol:encode-server-message hello))))
    (is (= 1 (length frames)))
    (is (protocol-value=
         hello
         (cadr-protocol:parse-server-message
          (cadr-protocol:decode-cbor (first frames)))))))

(test protocol-enforces-outbound-frame-limit
  (signals cadr-protocol:protocol-validation-error
    (cadr-protocol:encode-client-message
     (client-hello) :max-frame-length 8))
  (signals cadr-protocol:protocol-validation-error
    (cadr-protocol:encode-server-message
     (server-hello) :max-frame-length 8)))

(test protocol-validates-before-encoding
  (signals cadr-protocol:protocol-validation-error
    (cadr-protocol:encode-client-message
     (protocol-object
      "type" "hello"
      "version" 2
      "token" ""))))

(test protocol-omits-absent-optional-properties-on-wire
  (let* ((message
           (protocol-object
            "type" "request"
            "id" "request-1"
            "request" (protocol-object "command" "create")))
         (decoder (cadr-protocol:make-frame-decoder))
         (payload
           (first
            (cadr-protocol:frame-decoder-push
             decoder
             (cadr-protocol:encode-client-message message))))
         (decoded (cadr-protocol:decode-cbor payload)))
    (is (protocol-value= message decoded))
    (is (= 1 (hash-table-count
              (object-get decoded "request"))))))

(test protocol-incrementally-decodes-fragmented-and-coalesced-client-messages
  (let* ((hello (client-hello))
         (request
           (protocol-object
            "type" "request"
            "id" "request-1"
            "request" (protocol-object "command" "list")))
         (wire
           (concatenate-octets
            (cadr-protocol:encode-client-message hello)
            (cadr-protocol:encode-client-message request))))
    (loop for split from 0 to (length wire)
          do (let* ((decoder
                      (cadr-protocol:make-client-message-decoder))
                    (messages
                      (nconc
                       (cadr-protocol:message-decoder-push
                        decoder (subseq wire 0 split))
                       (cadr-protocol:message-decoder-push
                        decoder (subseq wire split)))))
               (cadr-protocol:message-decoder-end decoder)
               (is (= 2 (length messages)))
               (is (protocol-value= hello (first messages)))
               (is (protocol-value= request (second messages)))))))

(test protocol-incrementally-decodes-server-messages
  (let* ((message
           (protocol-object
            "type" "hello_error"
            "error"
            (protocol-object
             "code" "auth"
             "message" "Invalid token")))
         (decoder
           (cadr-protocol:make-server-message-decoder))
         (messages
           (cadr-protocol:message-decoder-push
            decoder
            (cadr-protocol:encode-server-message message))))
    (is (= 1 (length messages)))
    (is (protocol-value= message (first messages)))
    (cadr-protocol:message-decoder-end decoder)))

(test protocol-rejects-invalid-framed-client-input
  (dolist (wire
           (list
            (cadr-protocol:encode-frame (octets))
            (cadr-protocol:encode-frame (octets #xff))
            (cadr-protocol:encode-frame
             (cadr-protocol:encode-cbor
              (protocol-object
               "type" "hello"
               "version" 2
               "token" ""
               "extra" t)))))
    (let ((decoder
            (cadr-protocol:make-client-message-decoder)))
      (signals cadr-protocol:protocol-validation-error
        (cadr-protocol:message-decoder-push decoder wire))
      (signals-message
          cadr-protocol:protocol-validation-error "failed"
        (cadr-protocol:message-decoder-push
         decoder
         (cadr-protocol:encode-client-message
          (client-hello)))))))

(test protocol-rejects-byte-strings-in-json-valued-fields
  (let ((wire
          (cadr-protocol:encode-frame
           (cadr-protocol:encode-cbor
            (protocol-object
             "type" "response"
             "id" "request-1"
             "ok" nil
             "error"
             (protocol-object
              "code" "invalid_request"
              "message" "invalid"
              "details"
              (protocol-object
               "nested"
               (cadr-protocol:make-byte-string
                (octets 1 2 3)))))))))
    (signals cadr-protocol:protocol-validation-error
      (cadr-protocol:message-decoder-push
       (cadr-protocol:make-server-message-decoder)
       wire))))

(test protocol-rejects-truncated-and-oversized-framing
  (let ((truncated
          (cadr-protocol:make-server-message-decoder)))
    (is (null
         (cadr-protocol:message-decoder-push
          truncated (octets 0 0 0 2 1))))
    (signals cadr-protocol:protocol-validation-error
      (cadr-protocol:message-decoder-end truncated)))
  (let ((oversized
          (cadr-protocol:make-client-message-decoder
           :max-frame-length 3)))
    (signals cadr-protocol:protocol-validation-error
      (cadr-protocol:message-decoder-push
       oversized (octets 0 0 0 4)))))
