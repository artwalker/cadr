(defparameter *example-api* (cadr-agent:current-extension-api))

(defun example-object-schema (&rest required-properties)
  (let ((properties (cadr-ai::json-object)))
    (loop for (name type description) on required-properties by #'cdddr
          do
          (cadr-ai::json-put
           properties name
           (cadr-ai::json-object
            "type" type
            "description" description)))
    (cadr-ai::json-object
     "type" "object"
     "properties" properties
     "required"
     (coerce
      (loop for tail on required-properties by #'cdddr
            collect (first tail))
      'vector)
     "additionalProperties" nil)))

(defun example-event-value (event key)
  (getf (cadr-agent:extension-event-payload event) key))

(defun example-exec (program arguments &key cwd timeout-ms environment)
  (cadr-agent:extension-api-exec
   *example-api* program arguments
   :cwd cwd :timeout-ms timeout-ms :environment environment))

(defun example-exec-code (result)
  (or (getf result :exit-code) 0))

(defun example-exec-output (result)
  (or (getf result :stdout) ""))

(defun example-exec-error (result)
  (or (getf result :stderr) ""))

(defun example-session-entries (context)
  (let ((session (cadr-agent:extension-context-session context)))
    (and session (cadr-agent:session-entries session))))

(defun example-session-branch (context)
  (let ((session (cadr-agent:extension-context-session context)))
    (and session
         (cadr-agent:session-branch
          session (cadr-agent:session-leaf-id session)))))

(defun example-entry-role (entry)
  (let ((message (cadr-agent:session-entry-message entry)))
    (cond
      ((typep message 'cadr-ai:user-message) :user)
      ((typep message 'cadr-ai:assistant-message) :assistant)
      ((typep message 'cadr-ai:tool-result-message) :tool-result)
      (t nil))))

(defun example-entry-text (entry)
  (let ((message (cadr-agent:session-entry-message entry)))
    (cond
      ((typep message 'cadr-ai:user-message)
       (cadr-ai:user-message-content message))
      ((typep message 'cadr-ai:assistant-message)
       (with-output-to-string (output)
         (dolist (block (cadr-ai:assistant-message-content message))
           (when (typep block 'cadr-ai:text-content)
             (write-string (cadr-ai:text-content-text block) output)))))
      (t ""))))

(defun example-text-result (text &optional details)
  (values
   (list (cadr-ai:make-text-content :text text))
   details))

(defun example-tool-result-text (result)
  (if (typep result 'cadr-ai:tool-result-message)
      (with-output-to-string (output)
        (dolist (block (cadr-ai:tool-result-message-content result))
          (when (typep block 'cadr-ai:text-content)
            (write-string (cadr-ai:text-content-text block) output))))
      ""))

(defun example-trim (text)
  (string-trim '(#\Space #\Tab #\Newline #\Return) text))

(defun example-load-support () nil)
