(in-package #:cadr-ai)

(defun create-initial-system-message (system-prompt tools)
  (let ((has-system-prompt
          (and (stringp system-prompt) (plusp (length system-prompt))))
        (has-tools (and tools (plusp (length tools)))))
    (unless (or has-system-prompt has-tools)
      (return-from create-initial-system-message nil))
    (make-system-message
     :content (or system-prompt "")
     :tools-added (when has-tools (copy-list tools))
     :timestamp 0)))

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

(defun get-initial-system-message (messages)
  (let ((first (first messages)))
    (when (system-message-p first)
      first)))

(defun without-initial-system-message (messages)
  (if (get-initial-system-message messages)
      (rest messages)
      messages))

(defun get-current-tools (messages)
  (let ((tools (make-hash-table :test #'equal))
        (order '()))
    (dolist (message messages)
      (when (system-message-p message)
        (dolist (removed (system-message-tools-removed message))
          (let ((name (tool-reference-name removed)))
            (when (gethash name tools)
              (setf order (remove name order :test #'string=))
              (remhash name tools))))
        (dolist (tool (system-message-tools-added message))
          (let ((name (tool-name tool)))
            (unless (gethash name tools)
              (setf order (nconc order (list name))))
            (setf (gethash name tools) tool)))))
    (mapcar (lambda (name) (gethash name tools)) order)))

(defun %patch-sections (sections name value)
  (if (null value)
      (remove name sections :key #'car :test #'string= :count 1)
      (let ((cell (assoc name sections :test #'string=)))
        (cond
          (cell
           (setf (cdr cell) value)
           sections)
          (t
           (append sections (list (cons name value))))))))

(defun get-current-system-message (messages)
  (let ((content-parts '())
        (sections '())
        (timestamp nil))
    (dolist (message messages)
      (when (system-message-p message)
        (unless timestamp
          (setf timestamp (system-message-timestamp message)))
        (let ((text (content-text (system-message-content message))))
          (when (plusp (length text))
            (push text content-parts)))
        (dolist (pair (system-message-sections message))
          (setf sections
                (%patch-sections sections (car pair) (cdr pair))))))
    (let ((tools (get-current-tools messages)))
      (when (and (null timestamp) (null tools))
        (return-from get-current-system-message nil))
      (make-system-message
       :content (format nil "~{~A~^~%~%~}" (nreverse content-parts))
       :sections (copy-list sections)
       :tools-added (when tools (copy-list tools))
       :timestamp (or timestamp 0)))))

(defun get-current-system-prompt (messages)
  (let ((message (get-current-system-message messages)))
    (if message
        (get-system-message-text message)
        "")))

(defun collapse-system-messages (context)
  (let* ((head (get-current-system-message
                (transcript-context-messages context)))
         (rest (remove-if #'system-message-p
                          (transcript-context-messages context))))
    (make-transcript-context
     :messages (if head (cons head rest) rest))))

(defun resolve-transcript (context supports-mid-convo-system-messages)
  (if supports-mid-convo-system-messages
      context
      (collapse-system-messages context)))

(defun %tool-declaration-json (tool)
  (let ((object
          (json-object
           "name" (tool-name tool)
           "description" (tool-description tool)
           "parameters" (copy-json-value (tool-parameters tool))))
        (cs (tool-constrained-sampling tool)))
    (cond
      ((null cs) object)
      ((eq cs :false)
       (json-put object "constrainedSampling" nil)
       object)
      (t
       (json-put object "constrainedSampling" (copy-tree cs))
       object))))

(defun to-tool-declaration (tool)
  (make-tool
   :name (tool-name tool)
   :description (tool-description tool)
   :parameters (copy-json-value (tool-parameters tool))
   :constrained-sampling
   (let ((cs (tool-constrained-sampling tool)))
     (cond
       ((null cs) nil)
       ((eq cs :false) :false)
       (t (copy-tree cs))))
   :executor nil))

(defun declarations-equal (left right)
  (string= (stringify-json (%tool-declaration-json left))
           (stringify-json (%tool-declaration-json right))))

(defun get-tool-state-changes (previous current)
  (let ((previous-tools (make-hash-table :test #'equal))
        (current-tools (make-hash-table :test #'equal)))
    (dolist (tool previous)
      (setf (gethash (tool-name tool) previous-tools) tool))
    (dolist (tool current)
      (setf (gethash (tool-name tool) current-tools) tool))
    (make-tool-state-changes
     :tools-added
     (mapcar
      #'to-tool-declaration
      (remove-if
       (lambda (tool)
         (let ((previous-tool (gethash (tool-name tool) previous-tools)))
           (and previous-tool (declarations-equal previous-tool tool))))
       current))
     :tools-removed
     (mapcar
      (lambda (tool) (make-tool-reference :name (tool-name tool)))
      (remove-if
       (lambda (tool)
         (let ((current-tool (gethash (tool-name tool) current-tools)))
           (and current-tool (declarations-equal tool current-tool))))
       previous)))))

(defun get-declared-tools (messages)
  (let ((definitions (make-hash-table :test #'equal))
        (order '()))
    (dolist (message messages)
      (when (system-message-p message)
        (dolist (tool (system-message-tools-added message))
          (let ((name (tool-name tool)))
            (unless (gethash name definitions)
              (setf order (nconc order (list name))))
            (setf (gethash name definitions) tool)))))
    (mapcar (lambda (name) (gethash name definitions)) order)))

(defun has-tool-redefinitions (messages)
  (let ((declared (make-hash-table :test #'equal)))
    (dolist (message messages)
      (when (system-message-p message)
        (dolist (tool (system-message-tools-added message))
          (let* ((name (tool-name tool))
                 (previous (gethash name declared)))
            (when (and previous (not (declarations-equal previous tool)))
              (return-from has-tool-redefinitions t))
            (setf (gethash name declared) tool)))))
    nil))

(defun has-non-additive-tool-changes (messages)
  (let ((declared (make-hash-table :test #'equal)))
    (dolist (message messages)
      (when (system-message-p message)
        (when (system-message-tools-removed message)
          (return-from has-non-additive-tool-changes t))
        (dolist (tool (system-message-tools-added message))
          (let ((name (tool-name tool)))
            (when (gethash name declared)
              (return-from has-non-additive-tool-changes t))
            (setf (gethash name declared) t)))))
    nil))

(defun resolve-transcript-tools (messages supports-tool-additions)
  (let ((anchors-additions
          (and supports-tool-additions
               (not (has-non-additive-tool-changes messages)))))
    (make-transcript-tools
     :request-tools
     (if anchors-additions
         (copy-list
          (or (let ((initial (get-initial-system-message messages)))
                (and initial (system-message-tools-added initial)))
              '()))
         (get-current-tools messages))
     :anchors-additions (and anchors-additions t))))

(defun get-system-message-text (message)
  (let ((parts '()))
    (let ((text (content-text (system-message-content message))))
      (push text parts))
    (dolist (pair (system-message-sections message))
      (let ((text (cdr pair)))
        (unless (null text)
          (push text parts))))
    (format nil "~{~A~^~%~%~}"
            (remove-if (lambda (part) (zerop (length part)))
                       (nreverse parts)))))

(defun render-system-message-update (message)
  (let ((parts '()))
    (let ((text (content-text (system-message-content message))))
      (when (plusp (length text))
        (push text parts)))
    (dolist (pair (system-message-sections message))
      (let ((name (car pair))
            (value (cdr pair)))
        (push
         (if (null value)
             (format nil "Removed system prompt section ~S." name)
             (format nil "Updated system prompt section ~S:~%~%~A" name value))
         parts)))
    (format nil "~{~A~^~%~%~}" (nreverse parts))))
