(in-package #:cadr-agent)

(defun content-block-estimated-characters (block)
  (cond
    ((typep block 'cadr-ai:text-content)
     (length (cadr-ai:text-content-text block)))
    ((typep block 'cadr-ai:thinking-content)
     (length (cadr-ai:thinking-content-thinking block)))
    ((typep block 'cadr-ai:image-content)
     4800)
    ((typep block 'cadr-ai:tool-call)
     (+ (length (cadr-ai:tool-call-name block))
        (length
         (cadr-ai::stringify-json
          (json-safe-value
           (cadr-ai:tool-call-arguments block))))))
    (t 0)))

(defun message-estimated-tokens (message)
  (ceiling
   (max
    1
    (cond
      ((typep message 'cadr-ai:user-message)
       (let ((content
               (cadr-ai:user-message-content message)))
         (if (stringp content)
             (length content)
             (reduce #'+ content
                     :key
                     #'content-block-estimated-characters
                     :initial-value 0))))
      ((typep message 'cadr-ai:assistant-message)
       (reduce #'+
               (cadr-ai:assistant-message-content message)
               :key #'content-block-estimated-characters
               :initial-value 0))
      ((typep message 'cadr-ai:tool-result-message)
       (reduce #'+
               (cadr-ai:tool-result-message-content message)
               :key #'content-block-estimated-characters
               :initial-value 0))
      (t 0)))
   4))

(defun valid-assistant-usage-p (message)
  (and (typep message 'cadr-ai:assistant-message)
       (not
        (member
         (cadr-ai:assistant-message-stop-reason message)
         '(:error :aborted)))
       (plusp
        (cadr-ai:usage-total
         (cadr-ai:assistant-message-usage message)))))

(defun context-estimated-tokens (messages)
  (let ((last-usage-position
          (position-if
           #'valid-assistant-usage-p
           messages
           :from-end t)))
    (if last-usage-position
        (+ (cadr-ai:usage-total
            (cadr-ai:assistant-message-usage
             (nth last-usage-position messages)))
           (reduce #'+
                   (subseq messages
                           (1+ last-usage-position))
                   :key #'message-estimated-tokens
                   :initial-value 0))
        (reduce #'+ messages
                :key #'message-estimated-tokens
                :initial-value 0))))

(defun compaction-entry-estimated-tokens (entry)
  (ecase (session-entry-type entry)
    (:message
     (message-estimated-tokens
      (session-entry-message entry)))
    (:compaction
     (message-estimated-tokens
      (compaction-summary-message entry)))))

(defun compaction-cut-point (entries keep-recent-tokens)
  (let ((accumulated 0)
        (candidate nil))
    (loop for index downfrom (1- (length entries)) to 0
          for entry = (nth index entries)
          do
          (incf accumulated
                (compaction-entry-estimated-tokens entry))
          (when
              (and (eq :message
                       (session-entry-type entry))
                   (let ((message
                           (session-entry-message entry)))
                     (or
                      (typep message 'cadr-ai:user-message)
                      (typep message
                             'cadr-ai:assistant-message))))
            (setf candidate index))
          (when (and candidate
                     (>= accumulated keep-recent-tokens))
            (return)))
    (and candidate
         (> candidate 0)
         candidate)))

(defun truncate-summary-tool-result (text)
  (if (<= (length text) 2000)
      text
      (format nil "~A~%[... ~D characters truncated]"
              (subseq text 0 2000)
              (- (length text) 2000))))

(defun content-block-display-text (block)
  (cond
    ((typep block 'cadr-ai:text-content)
     (cadr-ai:text-content-text block))
    ((typep block 'cadr-ai:thinking-content)
     (format nil "[thinking] ~A"
             (cadr-ai:thinking-content-thinking block)))
    ((typep block 'cadr-ai:image-content)
     (format nil "[image ~A, ~D base64 characters]"
             (cadr-ai:image-content-mime-type block)
             (length (cadr-ai:image-content-data block))))
    ((typep block 'cadr-ai:tool-call)
     (format nil "[tool ~A ~A]"
             (cadr-ai:tool-call-name block)
             (cadr-ai::stringify-json
              (json-safe-value
               (cadr-ai:tool-call-arguments block)))))
    (t (princ-to-string block))))

(defun message-summary-text (message)
  (cond
    ((typep message 'cadr-ai:user-message)
     (let ((content
             (cadr-ai:user-message-content message)))
       (format nil
               "[User]: ~A"
               (if (stringp content)
                   content
                   (format nil "~{~A~^~%~}"
                           (mapcar
                            #'content-block-display-text
                            (coerce content 'list)))))))
    ((typep message 'cadr-ai:assistant-message)
     (format nil
             "[Assistant]: ~{~A~^~%~}"
             (mapcar
              #'content-block-display-text
              (cadr-ai:assistant-message-content message))))
    ((typep message 'cadr-ai:tool-result-message)
     (format nil
             "[Tool result ~A]: ~A"
             (cadr-ai:tool-result-message-tool-name message)
             (truncate-summary-tool-result
              (format nil
                      "~{~A~^~%~}"
                      (mapcar
                       #'content-block-display-text
                       (cadr-ai:tool-result-message-content
                        message))))))
    (t (princ-to-string message))))

(defun entries-summary-text (entries)
  (format
   nil "~{~A~^~%~%~}"
   (loop for entry in entries
         collect
         (ecase (session-entry-type entry)
           (:message
            (message-summary-text
             (session-entry-message entry)))
           (:compaction
            (format nil
                    "[Previous compaction summary]: ~A"
                    (session-entry-summary entry)))))))

(defun assistant-message-text (message)
  (format
   nil "~{~A~^~%~}"
   (loop for block in
           (cadr-ai:assistant-message-content message)
         when (typep block 'cadr-ai:text-content)
           collect (cadr-ai:text-content-text block))))

(defun generate-compaction-summary
    (agent source-entries max-output-tokens
     &optional custom-instructions (reason :manual))
  (let* ((prompt
           (format
            nil
            "Summarize the conversation below into a compact checkpoint for another coding agent. Preserve the user's goal, constraints, decisions, completed work, exact paths/symbols/errors, pending work, and anything needed to continue. Do not continue the conversation and do not answer its questions.~@[~%~%Additional focus: ~A~]~%~%~A"
            (and
             custom-instructions
             (plusp
              (length
               (string-trim
                '(#\Space #\Tab #\Newline #\Return)
                custom-instructions)))
             custom-instructions)
            (entries-summary-text source-entries)))
         (response
           (complete-summarization
            agent
            (cadr-ai:make-context
             :system-prompt
             "You produce faithful context checkpoint summaries."
             :messages
             (list
              (cadr-ai:make-user-message :content prompt))
             :tools nil)
            (min max-output-tokens
                 (cadr-ai:model-max-tokens
                  (agent-model agent)))
            :compaction
            :reason reason))
         (summary
           (if response
               (assistant-message-text response)
               "")))
    (when
        (and
         response
         (eq
          :error
          (cadr-ai:assistant-message-stop-reason response)))
      (error
       "Summarization failed: ~A"
       (or
        (cadr-ai:assistant-message-error-message response)
        "Unknown error")))
    summary))

(defun effective-compaction-limit
    (configured context-window divisor)
  (min configured
       (max 1 (floor context-window divisor))))

(defun compaction-entry-message (entry)
  (and (eq :message (session-entry-type entry))
       (session-entry-message entry)))

(defun compaction-user-entry-p (entry)
  (let ((message (compaction-entry-message entry)))
    (and message (typep message 'cadr-ai:user-message))))

(defun compaction-file-operations (entries)
  (let ((operations (make-file-operations)))
    (dolist (entry entries)
      (let ((message (compaction-entry-message entry)))
        (when message
          (extract-file-operations-from-message message operations)))
      (when (and (eq :compaction (session-entry-type entry))
                 (session-entry-details entry))
        (dolist (path (branch-details-files
                       (session-entry-details entry) :read-files))
          (setf (gethash path (file-operations-read operations)) t))
        (dolist (path (branch-details-files
                       (session-entry-details entry) :modified-files))
          (setf (gethash path (file-operations-edited operations)) t))))
    (multiple-value-bind (read-files modified-files)
        (compute-file-operation-lists operations)
      (list :read-files read-files
            :modified-files modified-files))))

(defun make-compaction-preparation
    (source-entries kept-entry tokens-before
     keep-recent reserve)
  (let* ((previous
           (find :compaction source-entries
                 :key #'session-entry-type
                 :from-end t))
         (split-turn-p
           (let ((message (compaction-entry-message kept-entry)))
             (and message
                  (not (typep message 'cadr-ai:user-message)))))
         (turn-start
           (and split-turn-p
                (position-if #'compaction-user-entry-p
                             source-entries :from-end t)))
         (split-turn-p (not (null turn-start)))
         (history-entries
           (if split-turn-p
               (subseq source-entries 0 turn-start)
               source-entries))
         (turn-prefix-entries
           (if split-turn-p
               (subseq source-entries turn-start)
               nil))
         (file-entries
           (append history-entries turn-prefix-entries)))
    (list
     :first-kept-entry-id (session-entry-id kept-entry)
     :messages-to-summarize
     (remove nil (mapcar #'compaction-entry-message
                         history-entries))
     :turn-prefix-messages
     (remove nil (mapcar #'compaction-entry-message
                         turn-prefix-entries))
     :is-split-turn-p split-turn-p
     :tokens-before tokens-before
     :previous-summary (and previous
                            (session-entry-summary previous))
     :file-ops (compaction-file-operations file-entries)
     :settings
     (list :enabled-p t
           :reserve-tokens reserve
           :keep-recent-tokens keep-recent))))

(defun usable-extension-compaction-p (value)
  (and
   (strict-keyword-plist-p value)
   (let ((summary (getf value :summary))
         (first-kept-entry-id
           (getf value :first-kept-entry-id))
         (tokens-before (getf value :tokens-before)))
     (and
      (stringp summary)
      (stringp first-kept-entry-id)
      (integerp tokens-before)
      (not (minusp tokens-before))))))

(defun run-compaction-lifecycle
    (agent event payload)
  (let ((host (agent-extension-host agent)))
    (and host
         (run-extension-lifecycle-hooks
          host event :payload payload))))

(defun %compact-agent
    (agent &key force-p custom-instructions
                (reason :manual) will-retry-p)
  (let* ((session (agent-session agent))
         (model (agent-model agent))
         (context-window
           (and model
                (cadr-ai:model-context-window model))))
    (unless (and session
                 context-window
                 (plusp context-window))
      (return-from %compact-agent nil))
    (let* ((messages (agent-messages agent))
           (tokens-before
             (context-estimated-tokens messages))
           (reserve
             (effective-compaction-limit
              (agent-compaction-reserve-tokens agent)
              context-window 4))
           (keep-recent
             (effective-compaction-limit
              (agent-compaction-keep-recent-tokens agent)
              context-window 4)))
      (unless
          (or force-p
              (> tokens-before
                 (- context-window reserve)))
        (return-from %compact-agent nil))
      (let* ((entries
               (session-context-entries session))
             (cut-point
               (compaction-cut-point
                entries keep-recent)))
        (unless cut-point
          (return-from %compact-agent nil))
        (let* ((source-entries
                 (subseq entries 0 cut-point))
               (kept-entry
                 (nth cut-point entries))
               (source-ids
                 (mapcar #'session-entry-id
                         source-entries))
               (preparation
                 (make-compaction-preparation
                  source-entries kept-entry tokens-before
                  keep-recent reserve))
               (signal
                 (make-extension-cancellation-signal
                  :aborted-function
                  (lambda () (agent-aborted-p agent)))))
          (when
              (eq :compaction
                  (session-entry-type
                   (car (last entries))))
            (return-from %compact-agent nil))
          (emit-agent-event
           agent :compaction-start
           :reason reason)
          (handler-case
              (let* ((before
                       (run-compaction-lifecycle
                        agent :session-before-compact
                        (list
                         :preparation preparation
                         :branch-entries (copy-list entries)
                         :custom-instructions custom-instructions
                         :reason reason
                         :will-retry-p (not (null will-retry-p))
                         :signal signal)))
                     (extension-compaction
                       (and before
                            (getf before :compaction))))
                (when (or (getf before :cancel-p)
                          (extension-cancellation-aborted-p signal))
                  (emit-agent-event agent :compaction-end)
                  (return-from %compact-agent nil))
                (unless (usable-extension-compaction-p
                         extension-compaction)
                  (setf extension-compaction nil))
                (let* ((from-extension-p
                         (not (null extension-compaction)))
                       (summary
                         (if from-extension-p
                             (getf extension-compaction :summary)
                             (generate-compaction-summary
                              agent source-entries reserve
                              custom-instructions reason)))
                       (first-kept-entry-id
                         (if from-extension-p
                             (getf extension-compaction
                                   :first-kept-entry-id)
                             (session-entry-id kept-entry)))
                       (effective-tokens-before
                         (if from-extension-p
                             (getf extension-compaction
                                   :tokens-before)
                             tokens-before)))
                (when
                    (extension-cancellation-aborted-p signal)
                  (emit-agent-event agent :compaction-end)
                  (return-from %compact-agent nil))
                (assert-agent-not-shutdown agent)
                (let* ((entry-id
                         (session-append-compaction
                          session summary source-ids
                          first-kept-entry-id
                          effective-tokens-before
                          :details
                          (and from-extension-p
                               (getf extension-compaction :details))
                          :usage
                          (and from-extension-p
                               (getf extension-compaction :usage))
                          :from-hook-p from-extension-p))
                       (entry
                         (gethash entry-id
                                  (session-by-id session))))
                  (run-compaction-lifecycle
                   agent :session-compact
                   (list
                    :compaction-entry entry
                    :from-extension-p from-extension-p
                    :reason reason
                    :will-retry-p
                    (not (null will-retry-p)))))
                (setf (agent-messages agent)
                      (session-messages session))
                (emit-agent-event
                 agent :compaction-end)
                t))
            (error (condition)
              (emit-agent-event
               agent :compaction-error
               :error-message
               (princ-to-string condition))
              nil)))))))

(defun compact-agent
    (agent &key force-p custom-instructions
                (reason :manual) will-retry-p)
  (call-with-agent-operation
   agent
   (lambda ()
     (%compact-agent
      agent
      :force-p force-p
      :custom-instructions custom-instructions
      :reason reason
      :will-retry-p will-retry-p))))

(defun maybe-compact-agent (agent)
  (when (agent-auto-compact-p agent)
    (compact-agent agent :reason :threshold)))

(defun context-overflow-message-p (message)
  (when
      (and
       (typep message 'cadr-ai:assistant-message)
       (eq :error
           (cadr-ai:assistant-message-stop-reason message))
       (cadr-ai:assistant-message-error-message message))
    (let ((text
            (string-downcase
             (cadr-ai:assistant-message-error-message
              message))))
      (some
       (lambda (needle)
         (search needle text))
       '("context_length_exceeded"
         "context length"
         "context window"
         "maximum context"
         "too many tokens"
         "prompt is too long"
         "input is too long"
         "exceeds the context")))))
