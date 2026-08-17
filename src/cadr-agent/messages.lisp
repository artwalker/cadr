(in-package #:cadr-agent)

(defparameter +compaction-summary-prefix+
  "The conversation history before this point was compacted into the following summary:\n\n<summary>\n")
(defparameter +compaction-summary-suffix+ "\n</summary>")
(defparameter +branch-summary-prefix+
  "The following is a summary of a branch that this conversation came back from:\n\n<summary>\n")
(defparameter +branch-summary-suffix+ "</summary>")

(defstruct bash-execution-message
  (command "" :type string)
  (output "" :type string)
  exit-code
  (cancelled-p nil :type boolean)
  (truncated-p nil :type boolean)
  full-output-path
  (timestamp (cadr-ai::unix-milliseconds) :type integer)
  (exclude-from-context-p nil :type boolean))

(defstruct custom-agent-message
  (custom-type "" :type string)
  content
  (display-p nil :type boolean)
  details
  (timestamp (cadr-ai::unix-milliseconds) :type integer))

(defstruct branch-summary-message
  (summary "" :type string)
  (from-id "" :type string)
  (timestamp (cadr-ai::unix-milliseconds) :type integer))

(defstruct compaction-summary-agent-message
  (summary "" :type string)
  (tokens-before 0 :type (integer 0 *))
  (timestamp (cadr-ai::unix-milliseconds) :type integer))

(defun bash-execution-to-text (message)
  (with-output-to-string (output)
    (format output "Ran `~A`~%" (bash-execution-message-command message))
    (if (plusp (length (bash-execution-message-output message)))
        (format output "```~%~A~%```"
                (bash-execution-message-output message))
        (write-string "(no output)" output))
    (cond
      ((bash-execution-message-cancelled-p message)
       (write-string "\n\n(command cancelled)" output))
      ((and (integerp (bash-execution-message-exit-code message))
            (not (zerop (bash-execution-message-exit-code message))))
       (format output "~%~%Command exited with code ~D"
               (bash-execution-message-exit-code message))))
    (when (and (bash-execution-message-truncated-p message)
               (bash-execution-message-full-output-path message))
      (format output "~%~%[Output truncated. Full output: ~A]"
              (bash-execution-message-full-output-path message)))))

(defun custom-agent-message-to-llm (message)
  (cadr-ai:make-user-message
   :content (custom-agent-message-content message)
   :timestamp (custom-agent-message-timestamp message)))

(defun branch-summary-message-to-llm (message)
  (cadr-ai:make-user-message
   :content
   (concatenate 'string
                +branch-summary-prefix+
                (branch-summary-message-summary message)
                +branch-summary-suffix+)
   :timestamp (branch-summary-message-timestamp message)))

(defun compaction-summary-agent-message-to-llm (message)
  (cadr-ai:make-user-message
   :content
   (concatenate 'string
                +compaction-summary-prefix+
                (compaction-summary-agent-message-summary message)
                +compaction-summary-suffix+)
   :timestamp (compaction-summary-agent-message-timestamp message)))

(defgeneric agent-message-to-llm (message)
  (:documentation
   "Project one agent-side message to an LLM-facing message, or NIL to drop it.")
  (:method ((message bash-execution-message))
    (unless (bash-execution-message-exclude-from-context-p message)
      (cadr-ai:make-user-message
       :content (bash-execution-to-text message)
       :timestamp (bash-execution-message-timestamp message))))
  (:method ((message custom-agent-message))
    (custom-agent-message-to-llm message))
  (:method ((message branch-summary-message))
    (branch-summary-message-to-llm message))
  (:method ((message compaction-summary-agent-message))
    (compaction-summary-agent-message-to-llm message))
  (:method ((message cadr-ai:user-message)) message)
  (:method ((message cadr-ai:assistant-message)) message)
  (:method ((message cadr-ai:tool-result-message)) message)
  (:method ((message t))
    nil))

(defun llm-passthrough-message-p (message)
  (typep message
         '(or cadr-ai:user-message
           cadr-ai:assistant-message
           cadr-ai:tool-result-message)))

(defun convert-agent-messages-to-llm (messages)
  (loop for message in messages
        for converted = (agent-message-to-llm message)
        when converted collect converted))

(defstruct (file-operations (:constructor %make-file-operations))
  (read (make-hash-table :test #'equal) :type hash-table)
  (written (make-hash-table :test #'equal) :type hash-table)
  (edited (make-hash-table :test #'equal) :type hash-table))

(defun make-file-operations ()
  (%make-file-operations))

(defun argument-path (arguments)
  (cond
    ((hash-table-p arguments)
     (let ((value (gethash "path" arguments)))
       (and (stringp value) value)))
    ((listp arguments)
     (let ((value (or (getf arguments :path)
                      (cdr (assoc "path" arguments :test #'string=)))))
       (and (stringp value) value)))))

(defun extract-file-operations-from-message (message operations)
  (when (typep message 'cadr-ai:assistant-message)
    (dolist (block (cadr-ai:assistant-message-content message))
      (when (typep block 'cadr-ai:tool-call)
        (let ((path (argument-path (cadr-ai:tool-call-arguments block))))
          (when path
            (cond
              ((string= "read" (cadr-ai:tool-call-name block))
               (setf (gethash path (file-operations-read operations)) t))
              ((string= "write" (cadr-ai:tool-call-name block))
               (setf (gethash path (file-operations-written operations)) t))
              ((string= "edit" (cadr-ai:tool-call-name block))
               (setf (gethash path (file-operations-edited operations)) t))))))))
  operations)

(defun hash-table-sorted-keys (table)
  (sort (loop for key being the hash-keys of table collect key) #'string<))

(defun compute-file-operation-lists (operations)
  (let ((modified (make-hash-table :test #'equal)))
    (maphash (lambda (path value)
               (declare (ignore value))
               (setf (gethash path modified) t))
             (file-operations-written operations))
    (maphash (lambda (path value)
               (declare (ignore value))
               (setf (gethash path modified) t))
             (file-operations-edited operations))
    (values
     (sort
      (loop for path being the hash-keys of (file-operations-read operations)
            unless (gethash path modified) collect path)
      #'string<)
     (hash-table-sorted-keys modified))))

(defun format-file-operations (read-files modified-files)
  (let ((sections nil))
    (when read-files
      (push (format nil "<read-files>~%~{~A~%~}</read-files>" read-files)
            sections))
    (when modified-files
      (push (format nil "<modified-files>~%~{~A~%~}</modified-files>"
                    modified-files)
            sections))
    (if sections
        (format nil "~%~%~{~A~^~%~%~}" (nreverse sections))
        "")))

(defun content-text (content &optional (separator ""))
  (if (stringp content)
      content
      (with-output-to-string (output)
        (loop with first-p = t
              for block in (coerce (or content nil) 'list)
              when (typep block 'cadr-ai:text-content)
                do (unless first-p (write-string separator output))
                   (write-string (cadr-ai:text-content-text block) output)
                   (setf first-p nil)))))

(defun safe-json-string (value)
  (handler-case
      (cadr-ai::stringify-json (json-safe-value value))
    (error () "[unserializable]")))

(defun truncate-summary-text (text)
  (if (<= (length text) 2000)
      text
      (format nil "~A~%~%[... ~D more characters truncated]"
              (subseq text 0 2000)
              (- (length text) 2000))))

(defun serialize-conversation (messages)
  (let ((parts nil))
    (dolist (message messages)
      (cond
        ((typep message 'cadr-ai:user-message)
         (let ((text (content-text (cadr-ai:user-message-content message) "")))
           (when (plusp (length text))
             (push (format nil "[User]: ~A" text) parts))))
        ((typep message 'cadr-ai:assistant-message)
         (let ((thinking nil)
               (tool-calls nil)
               (has-text-p nil))
           (dolist (block (cadr-ai:assistant-message-content message))
             (cond
               ((typep block 'cadr-ai:thinking-content)
                (push (cadr-ai:thinking-content-thinking block) thinking))
               ((typep block 'cadr-ai:text-content)
                (setf has-text-p t))
               ((typep block 'cadr-ai:tool-call)
                (let ((arguments (cadr-ai:tool-call-arguments block)))
                  (push
                   (format nil "~A(~{~A~^, ~})"
                           (cadr-ai:tool-call-name block)
                           (cond
                             ((hash-table-p arguments)
                              (sort
                               (loop for key being the hash-keys of arguments
                                     collect
                                     (format nil "~A=~A" key
                                             (safe-json-string
                                              (gethash key arguments))))
                               #'string<))
                             (t (list (safe-json-string arguments)))))
                   tool-calls)))))
           (when thinking
             (push (format nil "[Assistant thinking]: ~{~A~^~%~}"
                           (nreverse thinking))
                   parts))
           (when has-text-p
             (push (format nil "[Assistant]: ~A"
                           (content-text
                            (cadr-ai:assistant-message-content message) ""))
                   parts))
           (when tool-calls
             (push (format nil "[Assistant tool calls]: ~{~A~^; ~}"
                           (nreverse tool-calls))
                   parts))))
        ((typep message 'cadr-ai:tool-result-message)
         (let ((text (content-text
                      (cadr-ai:tool-result-message-content message) "")))
           (when (plusp (length text))
             (push (format nil "[Tool result]: ~A"
                           (truncate-summary-text text))
                   parts))))))
    (format nil "~{~A~^~%~%~}" (nreverse parts))))
