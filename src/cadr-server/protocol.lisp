(in-package #:cadr-server)

(defun encode-server-message (message)
  (concatenate
   'string
   (cadr-ai::stringify-json message)
   (string #\Newline)))

(defun parse-server-line (line)
  (cadr-ai::parse-json
   (string-trim
    '(#\Space #\Tab #\Return #\Newline)
    line)))

(defun error-response (message)
  (cadr-ai::json-object
   "type" "error"
   "ok" nil
   "error" message))

(defun unknown-instance-response (instance-id)
  (error-response
   (format nil
           "Unknown instance: ~A"
           instance-id)))

(defun instance-summary-json (record)
  (let ((object
          (cadr-ai::json-object
           "id" (instance-record-id record)
           "status"
           (string-downcase
            (symbol-name
             (instance-record-status record)))
           "cwd" (instance-record-cwd record))))
    (dolist
        (entry
         `(("label" . ,(instance-record-label
                        record))
           ("sessionId" . ,(instance-record-session-id
                            record))
           ("sessionFile" . ,(instance-record-session-file
                              record))
           ("radiusPiId" . ,(instance-record-radius-pi-id
                             record))))
      (when (cdr entry)
        (cadr-ai::json-put
         object (car entry) (cdr entry))))
    object))
