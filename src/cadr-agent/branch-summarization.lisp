(in-package #:cadr-agent)

(defstruct branch-summary-preparation
  (messages nil :type list)
  (file-operations (make-file-operations) :type file-operations)
  (total-tokens 0 :type (integer 0 *)))

(defstruct branch-summary-result
  (summary "" :type string)
  usage
  (read-files nil :type list)
  (modified-files nil :type list))

(defun session-entry-at (session entry-id)
  (find entry-id (session-entries session)
        :key #'session-entry-id :test #'string=))

(defun collect-entries-for-branch-summary (session old-leaf-id target-id)
  (unless old-leaf-id
    (return-from collect-entries-for-branch-summary (values nil nil)))
  (let* ((old-path (session-path-entries session old-leaf-id))
         (target-path (session-path-entries session target-id))
         (old-ids (make-hash-table :test #'equal))
         (common-ancestor-id nil))
    (dolist (entry old-path)
      (setf (gethash (session-entry-id entry) old-ids) t))
    (dolist (entry (reverse target-path))
      (when (gethash (session-entry-id entry) old-ids)
        (setf common-ancestor-id (session-entry-id entry))
        (return)))
    (let ((entries nil)
          (current old-leaf-id))
      (loop while (and current
                       (not (and common-ancestor-id
                                 (string= current common-ancestor-id))))
            for entry = (session-entry-at session current)
            do
            (unless entry
              (error 'session-error
                     :message (format nil "Entry ~A not found" current)))
            (push entry entries)
            (setf current (session-entry-parent-id entry)))
      (values entries common-ancestor-id))))

(defun session-entry-summary-agent-message (entry)
  (case (session-entry-type entry)
    (:message
     (unless (typep (session-entry-message entry)
                    'cadr-ai:tool-result-message)
       (session-entry-message entry)))
    (:custom-message
     (make-custom-agent-message
      :custom-type (session-entry-custom-type entry)
      :content (session-entry-content entry)
      :display-p (session-entry-display-p entry)
      :details (session-entry-details entry)
      :timestamp (session-entry-timestamp entry)))
    (:branch-summary
     (make-branch-summary-message
      :summary (session-entry-summary entry)
      :from-id (session-entry-from-id entry)
      :timestamp (session-entry-timestamp entry)))
    (:compaction
     (make-compaction-summary-agent-message
      :summary (session-entry-summary entry)
      :tokens-before (session-entry-tokens-before entry)
      :timestamp (session-entry-timestamp entry)))))

(defun branch-details-files (details key)
  (let ((value
          (cond
            ((hash-table-p details)
             (or (gethash key details)
                 (gethash (string-downcase (symbol-name key)) details)))
            ((listp details) (getf details key)))))
    (and (listp value) value)))

(defun prepare-branch-entries (entries &optional (token-budget 0))
  (let ((messages nil)
        (operations (make-file-operations))
        (total 0))
    (dolist (entry entries)
      (when (and (eq :branch-summary (session-entry-type entry))
                 (not (session-entry-from-hook-p entry))
                 (session-entry-details entry))
        (dolist (path (branch-details-files
                       (session-entry-details entry) :read-files))
          (setf (gethash path (file-operations-read operations)) t))
        (dolist (path (branch-details-files
                       (session-entry-details entry) :modified-files))
          (setf (gethash path (file-operations-edited operations)) t))))
    (dolist (entry (reverse entries))
      (let ((message (session-entry-summary-agent-message entry)))
        (when message
          (extract-file-operations-from-message message operations)
          (let ((tokens (message-estimated-tokens
                         (if (llm-passthrough-message-p message)
                             message
                             (or
                              (agent-message-to-llm message)
                              message)))))
            (when (and (plusp token-budget)
                       (> (+ total tokens) token-budget))
              (when (and (member (session-entry-type entry)
                                 '(:compaction :branch-summary))
                         (< total (* token-budget 0.9)))
                (push message messages)
                (incf total tokens))
              (return))
            (push message messages)
            (incf total tokens)))))
    (make-branch-summary-preparation
     :messages messages
     :file-operations operations
     :total-tokens total)))

(defparameter +branch-summary-preamble+
  "The user explored a different conversation branch before returning here.\nSummary of that exploration:\n\n")

(defparameter +branch-summary-prompt+
  "Create a structured summary of this conversation branch for context when returning later.\n\nUse this EXACT format:\n\n## Goal\n[What was the user trying to accomplish in this branch?]\n\n## Constraints & Preferences\n- [Any constraints, preferences, or requirements mentioned]\n- [Or \"(none)\" if none were mentioned]\n\n## Progress\n### Done\n- [x] [Completed tasks/changes]\n\n### In Progress\n- [ ] [Work that was started but not finished]\n\n### Blocked\n- [Issues preventing progress, if any]\n\n## Key Decisions\n- **[Decision]**: [Brief rationale]\n\n## Next Steps\n1. [What should happen next to continue this work]\n\nKeep each section concise. Preserve exact file paths, function names, and error messages.")

(defparameter +summarization-system-prompt+
  "You are a context summarization assistant. Your task is to read a conversation between a user and an AI assistant, then produce a structured summary following the exact format specified.\n\nDo NOT continue the conversation. Do NOT respond to any questions in the conversation. ONLY output the structured summary.")

(defun generate-branch-summary
    (agent entries &key custom-instructions replace-instructions-p
                         (reserve-tokens 16384))
  (let* ((model (agent-model agent))
         (context-window (or (and model (cadr-ai:model-context-window model))
                             128000))
         (preparation
           (prepare-branch-entries
            entries (max 0 (- context-window reserve-tokens))))
         (messages (branch-summary-preparation-messages preparation)))
    (unless messages
      (return-from generate-branch-summary
        (make-branch-summary-result :summary "No content to summarize")))
    (let* ((conversation
             (serialize-conversation
              (convert-agent-messages-to-llm messages)))
           (instructions
             (cond
               ((and replace-instructions-p custom-instructions)
                custom-instructions)
               (custom-instructions
                (format nil "~A~%~%Additional focus: ~A"
                        +branch-summary-prompt+ custom-instructions))
               (t +branch-summary-prompt+)))
           (prompt
             (format nil "<conversation>~%~A~%</conversation>~%~%~A"
                     conversation instructions))
           (response
             (complete-summarization
              agent
              (cadr-ai:make-context
               :system-prompt +summarization-system-prompt+
               :messages (list (cadr-ai:make-user-message :content prompt))
               :tools nil)
              2048
              :branch-summary)))
      (when (or (null response)
                (eq :aborted (cadr-ai:assistant-message-stop-reason response)))
        (return-from generate-branch-summary nil))
      (when (eq :error (cadr-ai:assistant-message-stop-reason response))
        (error "~A"
               (or (cadr-ai:assistant-message-error-message response)
                   "Summarization failed")))
      (multiple-value-bind (read-files modified-files)
          (compute-file-operation-lists
           (branch-summary-preparation-file-operations preparation))
        (let ((summary
                (concatenate
                 'string +branch-summary-preamble+
                 (assistant-message-text response)
                 (format-file-operations
                  read-files modified-files))))
          (make-branch-summary-result
           :summary
           (if (plusp (length summary))
               summary
               "No summary generated")
           :usage (cadr-ai:assistant-message-usage response)
           :read-files read-files
           :modified-files modified-files))))))
