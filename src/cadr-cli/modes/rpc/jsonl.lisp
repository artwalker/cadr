(in-package #:cadr-cli)

(defstruct (rpc-state
            (:constructor %make-rpc-state))
  agent
  extension-manager
  input
  output
  error-output
  (output-lock
    (sb-thread:make-mutex :name "cadr-rpc-output"))
  (pending-lock
    (sb-thread:make-mutex :name "cadr-rpc-pending"))
  (pending
    (make-hash-table :test #'equal)
    :type hash-table)
  (activity-lock
    (sb-thread:make-mutex :name "cadr-rpc-activity"))
  prompt-thread
  bash-thread
  bash-token
  bash-request-id
  (closing-p nil :type boolean)
  (id-counter 0 :type (integer 0 *)))

(defparameter +rpc-no-data+ (gensym "NO-DATA"))
(defparameter +rpc-async-response+ (gensym "ASYNC-RESPONSE"))

(defun rpc-write-object (state object)
  (sb-thread:with-mutex
      ((rpc-state-output-lock state))
    (write-json-line object (rpc-state-output state))))

(defun rpc-response
    (id command success-p
     &key
       (data +rpc-no-data+)
       error)
  (let ((object
          (cadr-ai::json-object
           "type" "response"
           "command" command
           "success" (not (null success-p)))))
    (when id
      (cadr-ai::json-put object "id" id))
    (if success-p
        (unless (eq data +rpc-no-data+)
          (cadr-ai::json-put object "data" data))
        (cadr-ai::json-put
         object "error"
         (or error "RPC command failed")))
    object))

(defun rpc-success (id command &optional
                               (data +rpc-no-data+))
  (rpc-response
   id command t :data data))

(defun rpc-failure (id command condition)
  (rpc-response
   id command nil
   :error
   (if (stringp condition)
       condition
       (princ-to-string condition))))

(defun rpc-next-id (state)
  (sb-thread:with-mutex
      ((rpc-state-pending-lock state))
    (format nil "cadr-ui-~D-~D"
            (cadr-ai::unix-milliseconds)
            (incf (rpc-state-id-counter state)))))

(defun trim-jsonl-carriage-return (line)
  (if
      (and
       (plusp (length line))
       (char= #\Return
              (char line (1- (length line)))))
      (subseq line 0 (1- (length line)))
      line))

(defun read-rpc-jsonl-lines (stream function)
  (loop
    (multiple-value-bind (line missing-newline-p)
        (read-line stream nil :eof)
      (declare (ignore missing-newline-p))
      (when (eq line :eof)
        (return))
      (funcall
       function
       (trim-jsonl-carriage-return line)))))

(defun rpc-command-id (object)
  (let ((id (cadr-ai::json-get object "id")))
    (and (stringp id) id)))

(defun require-rpc-object (value)
  (unless (hash-table-p value)
    (error "RPC frame must be a JSON object"))
  value)

(defun require-rpc-string (object key)
  (let ((value (cadr-ai::json-get object key)))
    (unless (stringp value)
      (error "RPC field ~A must be a string" key))
    value))

(defun require-rpc-boolean (object key)
  (unless (cadr-ai::json-present-p object key)
    (error "RPC field ~A must be a boolean" key))
  (let ((value (cadr-ai::json-get object key)))
    (unless (member value '(nil t))
      (error "RPC field ~A must be a boolean" key))
    value))

(defun rpc-symbol-name (value)
  (string-downcase
   (substitute #\_ #\-
               (symbol-name value))))

(defun rpc-json-nullable (value)
  (or value 'null))
