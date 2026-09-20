(in-package #:cadr-ai)

(defun create-initial-system-message (system-prompt tools)
  (let ((has-prompt-p (non-empty-string-p system-prompt))
        (has-tools-p (and tools (plusp (length tools)))))
    (when (or has-prompt-p has-tools-p)
      (make-system-message
       :content (or system-prompt "")
       :tools-added (when has-tools-p (copy-list tools))
       :timestamp 0))))

(defun normalize-context (context)
  (let* ((initial
           (create-initial-system-message
            (context-system-prompt context)
            (context-tools context)))
         (messages
           (if initial
               (cons initial (copy-list (context-messages context)))
               (copy-list (context-messages context)))))
    (make-transcript-context :messages messages)))

(defun ensure-transcript-context (value)
  (etypecase value
    (transcript-context value)
    (context (normalize-context value))))

(defun get-initial-system-message (messages)
  (let ((first (first messages)))
    (when (typep first 'system-message)
      first)))

(defun without-initial-system-message (messages)
  (if (get-initial-system-message messages)
      (rest messages)
      messages))

(defun system-message-content-text (message)
  (content-text (system-message-content message)))

(defun get-system-message-text (message)
  (let ((parts (list (system-message-content-text message))))
    (dolist (entry (system-message-sections message))
      (let ((value (cdr entry)))
        (when (stringp value)
          (push value parts))))
    (format nil "~{~A~^~%~%~}"
            (remove-if (lambda (part) (zerop (length part)))
                       (nreverse parts)))))

(defun get-current-tools (messages)
  (let ((tools (make-hash-table :test #'equal))
        (order nil))
    (dolist (message messages)
      (when (typep message 'system-message)
        (dolist (ref (system-message-tools-removed message))
          (let ((name (if (typep ref 'tool-reference)
                          (tool-reference-name ref)
                          (tool-name ref))))
            (when (gethash name tools)
              (setf order (remove name order :test #'string=))
              (remhash name tools))))
        (dolist (tool (system-message-tools-added message))
          (let ((name (tool-name tool)))
            (unless (gethash name tools)
              (push name order))
            (setf (gethash name tools) tool)))))
    (mapcar (lambda (name) (gethash name tools))
            (nreverse order))))

(defun get-current-system-message (messages)
  (let ((content nil)
        (sections (make-hash-table :test #'equal))
        (section-order nil)
        (timestamp nil))
    (dolist (message messages)
      (when (typep message 'system-message)
        (unless timestamp
          (setf timestamp (system-message-timestamp message)))
        (let ((text (system-message-content-text message)))
          (when (plusp (length text))
            (push text content)))
        (dolist (entry (system-message-sections message))
          (let ((name (car entry))
                (value (cdr entry)))
            (cond
              ((null value)
               (when (gethash name sections)
                 (setf section-order
                       (remove name section-order :test #'string=))
                 (remhash name sections)))
              (t
               (unless (gethash name sections)
                 (push name section-order))
               (setf (gethash name sections) value)))))))
    (let ((tools (get-current-tools messages)))
      (when (or timestamp tools)
        (make-system-message
         :content (format nil "~{~A~^~%~%~}" (nreverse content))
         :sections
         (mapcar (lambda (name)
                   (cons name (gethash name sections)))
                 (nreverse section-order))
         :tools-added (copy-list tools)
         :timestamp (or timestamp 0))))))

(defun get-current-system-prompt (messages)
  (let ((message (get-current-system-message messages)))
    (if message
        (get-system-message-text message)
        "")))

(defun collapse-system-messages (transcript)
  (let* ((messages (transcript-context-messages transcript))
         (head (get-current-system-message messages))
         (rest
           (remove-if (lambda (message)
                        (typep message 'system-message))
                      messages)))
    (make-transcript-context
     :messages (if head (cons head rest) rest))))

(defun resolve-transcript (transcript supports-mid-convo-system-messages)
  (if supports-mid-convo-system-messages
      transcript
      (collapse-system-messages transcript)))

(defun get-declared-tools (messages)
  (let ((definitions (make-hash-table :test #'equal))
        (order nil))
    (dolist (message messages)
      (when (typep message 'system-message)
        (dolist (tool (system-message-tools-added message))
          (let ((name (tool-name tool)))
            (unless (gethash name definitions)
              (push name order))
            (setf (gethash name definitions) tool)))))
    (mapcar (lambda (name) (gethash name definitions))
            (nreverse order))))

(defun has-non-additive-tool-changes-p (messages)
  (let ((declared (make-hash-table :test #'equal)))
    (dolist (message messages)
      (when (typep message 'system-message)
        (when (system-message-tools-removed message)
          (return-from has-non-additive-tool-changes-p t))
        (dolist (tool (system-message-tools-added message))
          (let ((name (tool-name tool)))
            (when (gethash name declared)
              (return-from has-non-additive-tool-changes-p t))
            (setf (gethash name declared) t)))))
    nil))

(defun resolve-transcript-tools (messages supports-tool-additions)
  (let ((anchors-additions
          (and supports-tool-additions
               (not (has-non-additive-tool-changes-p messages)))))
    (list
     :request-tools
     (if anchors-additions
         (copy-list
          (system-message-tools-added
           (or (get-initial-system-message messages)
               (make-system-message))))
         (get-current-tools messages))
     :anchors-additions anchors-additions)))

(defun transcript-context-as-request-context (model transcript)
  (let* ((resolved
           (resolve-transcript
            transcript
            (model-compat-value
             model :supports-mid-convo-system-messages nil)))
         (messages (transcript-context-messages resolved))
         (prompt (get-current-system-prompt messages))
         (tools (get-current-tools messages)))
    (make-context
     :system-prompt (when (plusp (length prompt)) prompt)
     :messages (without-initial-system-message messages)
     :tools tools)))

(defun coerce-provider-request-context (model context)
  (etypecase context
    (context context)
    (transcript-context
     (transcript-context-as-request-context model context))))
