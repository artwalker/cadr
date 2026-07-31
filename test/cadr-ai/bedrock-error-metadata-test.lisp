(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(defparameter +bedrock-diagnostic-request-id+
  "11111111-2222-3333-4444-555555555555")

(defparameter +bedrock-validation-message+
  "The provided model identifier is invalid.")

(defun bedrock-error-metadata-fixture ()
  (cadr-ai:instantiate-provider
   :amazon-bedrock
   :model-id "us.anthropic.claude-opus-4-8"
   :api-key "bearer"))

(defun bedrock-diagnostic (message)
  (find :bedrock-response-failure
        (cadr-ai:assistant-message-diagnostics message)
        :key #'cadr-ai:assistant-message-diagnostic-type))

(defun bedrock-diagnostic-details (message)
  (let ((diagnostic (bedrock-diagnostic message)))
    (and diagnostic
         (cadr-ai:assistant-message-diagnostic-details diagnostic))))

(defun u32-big-endian-octets (value)
  (make-array
   4 :element-type '(unsigned-byte 8)
   :initial-contents
   (list (ldb (byte 8 24) value)
         (ldb (byte 8 16) value)
         (ldb (byte 8 8) value)
         (ldb (byte 8 0) value))))

(defun aws-event-stream-header-octets (name value)
  (let ((name-octets
          (babel:string-to-octets name :encoding :utf-8))
        (value-octets
          (babel:string-to-octets value :encoding :utf-8)))
    (concatenate
     '(vector (unsigned-byte 8))
     (vector (length name-octets))
     name-octets
     ;; AWS event-stream header type 7 is a UTF-8 string.
     (vector 7)
     (make-array
      2 :element-type '(unsigned-byte 8)
      :initial-contents
      (list (ldb (byte 8 8) (length value-octets))
            (ldb (byte 8 0) (length value-octets))))
     value-octets)))

(defun aws-event-stream-frame (headers payload)
  (let* ((header-octets
           (apply
            #'concatenate
            '(vector (unsigned-byte 8))
            (mapcar
             (lambda (header)
               (aws-event-stream-header-octets
                (car header) (cdr header)))
             headers)))
         (payload-octets
           (babel:string-to-octets payload :encoding :utf-8))
         (total-length (+ 16 (length header-octets)
                          (length payload-octets)))
         (prelude-body
           (concatenate
            '(vector (unsigned-byte 8))
            (u32-big-endian-octets total-length)
            (u32-big-endian-octets (length header-octets))))
         (prelude
           (concatenate
            '(vector (unsigned-byte 8))
            prelude-body
            (u32-big-endian-octets
             (cadr-ai::crc32-octets prelude-body))))
         (without-message-crc
           (concatenate
            '(vector (unsigned-byte 8))
            prelude header-octets payload-octets)))
    (concatenate
     '(vector (unsigned-byte 8))
     without-message-crc
     (u32-big-endian-octets
      (cadr-ai::crc32-octets without-message-crc)))))

(defun bedrock-failing-stream (message-type code message)
  (let ((start
          (aws-event-stream-frame
           '((":message-type" . "event")
             (":event-type" . "messageStart"))
           "{\"role\":\"assistant\"}"))
        (failure
          (aws-event-stream-frame
           (if (string= message-type "exception")
               `((":message-type" . "exception")
                 (":exception-type" . ,code))
               `((":message-type" . "error")
                 (":error-code" . ,code)
                 (":error-message" . ,message)))
           (if (string= message-type "exception")
               (cadr-ai::stringify-json
                (cadr-ai::json-object "message" message))
               ""))))
    (flexi-streams:make-in-memory-input-stream
     (concatenate
      '(vector (unsigned-byte 8)) start failure))))

(defun run-bedrock-error-case (http-function &key abort-p)
  (multiple-value-bind (provider model)
      (bedrock-error-metadata-fixture)
    (let ((cadr-ai:*http-request-function* http-function)
          (cadr-ai::*max-provider-retries* 0))
      (cadr-ai:stream-chat
       provider model
       (cadr-ai:make-context
        :messages
        (list
         (cadr-ai:make-user-message :content "hello")))
       (constantly nil)
       :cache-retention :none
       :abort-p abort-p))))

(defun bedrock-http-error (status code request-id)
  (lambda (url &rest arguments)
    (declare (ignore url arguments))
    (values
     (make-string-input-stream
      (cadr-ai::stringify-json
       (cadr-ai::json-object
        "error"
        (cadr-ai::json-object
         "message" +bedrock-validation-message+)
        "__type" code)))
     status
     `(("x-amzn-requestid" . ,request-id)))))

(defun bedrock-midstream-error (message-type code message)
  (lambda (url &rest arguments)
    (declare (ignore url arguments))
    (values
     (bedrock-failing-stream message-type code message)
     200
     `(("x-amzn-requestid"
        . ,+bedrock-diagnostic-request-id+)))))

(test bedrock-http-failure-records-status-code-request-id-and-no-error-object
  (let* ((message
           (run-bedrock-error-case
            (bedrock-http-error
             400 "ValidationException"
             +bedrock-diagnostic-request-id+)))
         (diagnostic (bedrock-diagnostic message)))
    (is (eq :error
            (cadr-ai:assistant-message-stop-reason message)))
    (is (equal
         `(:request-id ,+bedrock-diagnostic-request-id+
           :error-code "ValidationException"
           :status 400)
         (cadr-ai:assistant-message-diagnostic-details diagnostic)))
    (is (null
         (cadr-ai:assistant-message-diagnostic-error diagnostic)))))

(test bedrock-failure-diagnostic-leaves-error-message-unchanged
  (let ((message
          (run-bedrock-error-case
           (bedrock-http-error
            400 "ValidationException"
            +bedrock-diagnostic-request-id+))))
    (is (string=
         +bedrock-validation-message+
         (cadr-ai:assistant-message-error-message message)))))

(test bedrock-modeled-midstream-failure-reports-only-response-request-id
  (let ((message
          (run-bedrock-error-case
           (bedrock-midstream-error
            "exception" "throttlingException"
            "Too many requests, please wait."))))
    (is (eq :error
            (cadr-ai:assistant-message-stop-reason message)))
    (is (equal
         `(:request-id ,+bedrock-diagnostic-request-id+)
         (bedrock-diagnostic-details message)))))

(test bedrock-unmodeled-midstream-failure-captures-error-code
  (let ((message
          (run-bedrock-error-case
           (bedrock-midstream-error
            "error" "ModelStreamErrorException"
            "Model stream terminated unexpectedly."))))
    (is (equal
         `(:request-id ,+bedrock-diagnostic-request-id+
           :error-code "ModelStreamErrorException")
         (bedrock-diagnostic-details message)))))

(test bedrock-midstream-transport-name-is-not-a-provider-error-code
  (let ((message
          (run-bedrock-error-case
           (bedrock-midstream-error
            "error" "TimeoutError"
            "Connection timed out after 1000 ms"))))
    (is (equal
         `(:request-id ,+bedrock-diagnostic-request-id+)
         (bedrock-diagnostic-details message)))))

(test bedrock-transport-failure-without-provider-metadata-has-no-diagnostic
  (let ((message
          (run-bedrock-error-case
           (lambda (url &rest arguments)
             (declare (ignore url arguments))
             (error "socket hang up")))))
    (is (eq :error
            (cadr-ai:assistant-message-stop-reason message)))
    (is (null (bedrock-diagnostic message)))))

(test bedrock-aborted-turn-has-no-failure-diagnostic
  (let ((message
          (run-bedrock-error-case
           (bedrock-http-error
            400 "ValidationException"
            +bedrock-diagnostic-request-id+)
           :abort-p (constantly t))))
    (is (eq :aborted
            (cadr-ai:assistant-message-stop-reason message)))
    (is (null (bedrock-diagnostic message)))))

(test bedrock-failure-diagnostic-drops-overlong-header-derived-values
  (let ((message
          (run-bedrock-error-case
           (bedrock-http-error
            400
            (concatenate 'string
                         (make-string 5000 :initial-element #\E)
                         "Exception")
            (make-string 5000 :initial-element #\R)))))
    (is (equal '(:status 400)
               (bedrock-diagnostic-details message)))))

(test bedrock-failure-diagnostic-omits-unknown-code-placeholder
  (let ((message
          (run-bedrock-error-case
           (bedrock-http-error
            403 "Unknown"
            +bedrock-diagnostic-request-id+))))
    (is (equal
         `(:request-id ,+bedrock-diagnostic-request-id+
           :status 403)
         (bedrock-diagnostic-details message)))))
