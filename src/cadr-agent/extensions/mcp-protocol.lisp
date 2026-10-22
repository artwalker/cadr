(in-package #:cadr-agent)

;;; pi@4a080252f packages/mcp protocol, JSON-RPC, and toLlmContent.
;;; Wire values stay :json-object / vectors so equal-strength tests can
;;; walk them without a second parser.

(defparameter +mcp-latest-protocol-version+ "2025-11-25")

(defparameter +mcp-supported-protocol-versions+
  '("2025-11-25" "2025-06-18" "2025-03-26" "2024-11-05"))

(defconstant +mcp-parse-error+ -32700)
(defconstant +mcp-invalid-request+ -32600)
(defconstant +mcp-method-not-found+ -32601)
(defconstant +mcp-invalid-params+ -32602)
(defconstant +mcp-internal-error+ -32603)

(defconstant +mcp-max-message-bytes+ (* 16 1024 1024))

(define-condition mcp-error (error)
  ((code :initarg :code :reader mcp-error-code)
   (data :initarg :data :initform nil :reader mcp-error-data)
   (data-p :initarg :data-p :initform nil :reader mcp-error-data-p)
   (message :initarg :message :reader mcp-error-message))
  (:report (lambda (condition stream)
             (write-string (mcp-error-message condition) stream))))

(define-condition mcp-connection-closed-error (error)
  ((message :initarg :message :initform "MCP connection closed"
            :reader mcp-error-message))
  (:report (lambda (condition stream)
             (write-string (mcp-error-message condition) stream))))

(define-condition mcp-timeout-error (error)
  ((timeout-ms :initarg :timeout-ms :reader mcp-timeout-error-timeout-ms))
  (:report (lambda (condition stream)
             (format stream "MCP request timed out after ~Ams"
                     (mcp-timeout-error-timeout-ms condition)))))

(define-condition mcp-abort-error (error) ()
  (:report (lambda (condition stream)
             (declare (ignore condition))
             (write-string "MCP request aborted" stream))))

(define-condition mcp-http-error (error)
  ((status :initarg :status :reader mcp-http-error-status)
   (body :initarg :body :initform "" :reader mcp-http-error-body)
   (message :initarg :message :reader mcp-error-message))
  (:report (lambda (condition stream)
             (write-string (mcp-error-message condition) stream))))

(define-condition mcp-auth-required-error (mcp-http-error)
  ((www-authenticate :initarg :www-authenticate
                     :initform nil
                     :reader mcp-auth-required-www-authenticate)))

(define-condition mcp-session-expired-error (mcp-http-error) ())

(defun mcp-invalid (message)
  (error 'mcp-error
         :code +mcp-invalid-request+
         :message message))

(defun mcp-obj (&rest pairs)
  (list* :json-object pairs))

(defun mcp-read-json (text)
  (mcp-normalize (cadr-ai::parse-json text)))

(defun mcp-write-json (value)
  (let ((cadr-ai::*json-sort-object-keys* nil))
    (cadr-ai::stringify-json value)))

(defun mcp-copy-json (value)
  (mcp-read-json (mcp-write-json value)))

(defun mcp-jsonrpc-id-p (value)
  (or (stringp value)
      (and (integerp value))
      (and (floatp value)
           (not (sb-ext:float-infinity-p value))
           (not (sb-ext:float-nan-p value)))))

(defun mcp-jsonrpc-request-p (message)
  (and (mcp-object-p message)
       (equal (mcp-get message "jsonrpc") "2.0")
       (nth-value 1 (mcp-get message "id"))
       (mcp-jsonrpc-id-p (mcp-get message "id"))
       (stringp (mcp-get message "method"))))

(defun mcp-jsonrpc-notification-p (message)
  (and (mcp-object-p message)
       (equal (mcp-get message "jsonrpc") "2.0")
       (not (nth-value 1 (mcp-get message "id")))
       (stringp (mcp-get message "method"))))

(defun mcp-jsonrpc-error-object-p (value)
  (and (mcp-object-p value)
       (numberp (mcp-get value "code"))
       (stringp (mcp-get value "message"))))

(defun mcp-jsonrpc-response-p (message)
  (and (mcp-object-p message)
       (equal (mcp-get message "jsonrpc") "2.0")
       (nth-value 1 (mcp-get message "id"))
       (mcp-jsonrpc-id-p (mcp-get message "id"))
       (cond
         ((nth-value 1 (mcp-get message "result"))
          (not (nth-value 1 (mcp-get message "error"))))
         ((nth-value 1 (mcp-get message "error"))
          (mcp-jsonrpc-error-object-p (mcp-get message "error")))
         (t nil))))

(defun mcp-parse-jsonrpc (value)
  (cond
    ((or (mcp-jsonrpc-request-p value)
         (mcp-jsonrpc-notification-p value)
         (mcp-jsonrpc-response-p value))
     value)
    (t (mcp-invalid "Invalid JSON-RPC message"))))

(defun mcp-json-sequence-p (value)
  (and (typep value 'sequence)
       (not (stringp value))
       (not (mcp-object-p value))))

(defun mcp-json-pretty (value &optional (indent 0))
  (cond
    ((mcp-object-p value)
     (if (null (cdr value))
         "{}"
         (let ((pad (make-string (* 2 (1+ indent)) :initial-element #\Space))
               (end (make-string (* 2 indent) :initial-element #\Space)))
           (format nil "{~%~{~A~^,~%~}~%~A}"
                   (loop for (key item) on (cdr value) by #'cddr
                         collect (format nil "~A~A: ~A"
                                         pad
                                         (cadr-ai::stringify-json key)
                                         (mcp-json-pretty item (1+ indent))))
                   end))))
    ((mcp-json-sequence-p value)
     (if (zerop (length value))
         "[]"
         (let ((pad (make-string (* 2 (1+ indent)) :initial-element #\Space))
               (end (make-string (* 2 indent) :initial-element #\Space)))
           (format nil "[~%~{~A~^,~%~}~%~A]"
                   (loop for item across (coerce value 'vector)
                         collect (format nil "~A~A"
                                         pad
                                         (mcp-json-pretty item (1+ indent))))
                   end))))
    (t (cadr-ai::stringify-json value))))

(defun mcp-content-type (block)
  (mcp-get block "type"))

(defun mcp-block-to-llm (block)
  (let ((type (mcp-content-type block)))
    (cond
      ((and (stringp type) (string= type "text"))
       (mcp-obj "type" "text" "text" (or (mcp-get block "text") "")))
      ((and (stringp type) (string= type "image"))
       (mcp-obj "type" "image"
                "data" (or (mcp-get block "data") "")
                "mimeType" (or (mcp-get block "mimeType") "")))
      ((and (stringp type) (string= type "audio"))
       (mcp-obj "type" "text"
                "text" (format nil "[audio ~A omitted]"
                               (or (mcp-get block "mimeType") ""))))
      ((and (stringp type) (string= type "resource_link"))
       (mcp-obj "type" "text"
                "text" (format nil "~A: ~A"
                               (or (mcp-get block "name") "")
                               (or (mcp-get block "uri") ""))))
      ((and (stringp type) (string= type "resource"))
       (let ((resource (mcp-get block "resource")))
         (cond
           ((and (mcp-object-p resource)
                 (nth-value 1 (mcp-get resource "text")))
            (mcp-obj "type" "text" "text" (mcp-get resource "text")))
           ((and (mcp-object-p resource)
                 (stringp (mcp-get resource "mimeType"))
                 (uiop:string-prefix-p "image/" (mcp-get resource "mimeType")))
            (mcp-obj "type" "image"
                     "data" (or (mcp-get resource "blob") "")
                     "mimeType" (mcp-get resource "mimeType")))
           (t
            (mcp-obj "type" "text"
                     "text"
                     (format nil "[binary resource ~A (~A) omitted]"
                             (if (mcp-object-p resource)
                                 (or (mcp-get resource "uri") "")
                                 "")
                             (or (and (mcp-object-p resource)
                                      (mcp-get resource "mimeType"))
                                 "unknown type")))))))
      (t
       (mcp-obj "type" "text"
                "text" (format nil "[unsupported MCP content ~A]"
                               (or type "")))))))

(defun mcp-to-llm-content (result)
  ;; pi@4a080252f toLlmContent. Empty blocks fall back to pretty JSON
  ;; of structuredContent, including null.
  (let ((content
          (let ((blocks (mcp-get result "content")))
            (if (mcp-json-sequence-p blocks)
                (loop for block across (coerce blocks 'vector)
                      collect (mcp-block-to-llm block))
                nil))))
    (when (and (null content)
               (nth-value 1 (mcp-get result "structuredContent")))
      (setf content
            (list (mcp-obj "type" "text"
                           "text" (mcp-json-pretty
                                   (mcp-get result "structuredContent"))))))
    content))

(defstruct (mcp-abort (:constructor %make-mcp-abort))
  (aborted-p nil :type boolean)
  reason
  (callbacks nil :type list)
  (lock (sb-thread:make-mutex :name "mcp abort")))

(defun make-mcp-abort ()
  (%make-mcp-abort))

(defun mcp-abort (abort &optional reason)
  (let ((callbacks nil))
    (sb-thread:with-mutex ((mcp-abort-lock abort))
      (unless (mcp-abort-aborted-p abort)
        (setf (mcp-abort-aborted-p abort) t
              (mcp-abort-reason abort) reason
              callbacks (mcp-abort-callbacks abort)
              (mcp-abort-callbacks abort) nil)))
    (dolist (callback callbacks)
      (funcall callback))
    abort))

(defun mcp-abort-subscribe (abort callback)
  (sb-thread:with-mutex ((mcp-abort-lock abort))
    (if (mcp-abort-aborted-p abort)
        (setf callback callback)
        (progn
          (push callback (mcp-abort-callbacks abort))
          (setf callback nil))))
  (when callback
    (funcall callback))
  nil)

(defgeneric mcp-transport-start (transport))
(defgeneric mcp-transport-send (transport message &key abort))
(defgeneric mcp-transport-close (transport))
(defgeneric mcp-transport-on-message (transport listener))
(defgeneric mcp-transport-on-error (transport listener))
(defgeneric mcp-transport-on-close (transport listener))
(defgeneric mcp-transport-set-protocol-version (transport version))

(defmethod mcp-transport-set-protocol-version (transport version)
  (declare (ignore transport version))
  nil)
