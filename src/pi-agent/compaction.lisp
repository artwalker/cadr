(in-package #:pi-agent)

(defun content-block-estimated-characters (block)
  (cond
    ((typep block 'pi-ai:text-content)
     (length (pi-ai:text-content-text block)))
    ((typep block 'pi-ai:thinking-content)
     (length (pi-ai:thinking-content-thinking block)))
    ((typep block 'pi-ai:image-content)
     4800)
    ((typep block 'pi-ai:tool-call)
     (+ (length (pi-ai:tool-call-name block))
        (length
         (pi-ai::stringify-json
          (json-safe-value
           (pi-ai:tool-call-arguments block))))))
    (t 0)))

(defun message-estimated-tokens (message)
  (ceiling
   (max
    1
    (cond
      ((typep message 'pi-ai:user-message)
       (let ((content
               (pi-ai:user-message-content message)))
         (if (stringp content)
             (length content)
             (reduce #'+ content
                     :key
                     #'content-block-estimated-characters
                     :initial-value 0))))
      ((typep message 'pi-ai:assistant-message)
       (reduce #'+
               (pi-ai:assistant-message-content message)
               :key #'content-block-estimated-characters
               :initial-value 0))
      ((typep message 'pi-ai:tool-result-message)
       (reduce #'+
               (pi-ai:tool-result-message-content message)
               :key #'content-block-estimated-characters
               :initial-value 0))
      (t 0)))
   4))

(defun valid-assistant-usage-p (message)
  (and (typep message 'pi-ai:assistant-message)
       (not
        (member
         (pi-ai:assistant-message-stop-reason message)
         '(:error :aborted)))
       (plusp
        (pi-ai:usage-total
         (pi-ai:assistant-message-usage message)))))

(defun context-estimated-tokens (messages)
  (let ((last-usage-position
          (position-if
           #'valid-assistant-usage-p
           messages
           :from-end t)))
    (if last-usage-position
        (+ (pi-ai:usage-total
            (pi-ai:assistant-message-usage
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
                      (typep message 'pi-ai:user-message)
                      (typep message
                             'pi-ai:assistant-message))))
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

(defun message-summary-text (message)
  (cond
    ((typep message 'pi-ai:user-message)
     (let ((content
             (pi-ai:user-message-content message)))
       (format nil
               "[User]: ~A"
               (if (stringp content)
                   content
                   (format nil "~{~A~^~%~}"
                           (mapcar
                            #'content-block-display-text
                            (coerce content 'list)))))))
    ((typep message 'pi-ai:assistant-message)
     (format nil
             "[Assistant]: ~{~A~^~%~}"
             (mapcar
              #'content-block-display-text
              (pi-ai:assistant-message-content message))))
    ((typep message 'pi-ai:tool-result-message)
     (format nil
             "[Tool result ~A]: ~A"
             (pi-ai:tool-result-message-tool-name message)
             (truncate-summary-tool-result
              (format nil
                      "~{~A~^~%~}"
                      (mapcar
                       #'content-block-display-text
                       (pi-ai:tool-result-message-content
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
           (pi-ai:assistant-message-content message)
         when (typep block 'pi-ai:text-content)
           collect (pi-ai:text-content-text block))))

(defun generate-compaction-summary
    (agent source-entries max-output-tokens)
  (let* ((prompt
           (format
            nil
            "Summarize the conversation below into a compact checkpoint for another coding agent. Preserve the user's goal, constraints, decisions, completed work, exact paths/symbols/errors, pending work, and anything needed to continue. Do not continue the conversation and do not answer its questions.~%~%~A"
            (entries-summary-text source-entries)))
         (response
           (funcall
            (agent-stream-function agent)
            (agent-provider agent)
            (agent-model agent)
            (pi-ai:make-context
             :system-prompt
             "You produce faithful context checkpoint summaries."
             :messages
             (list
              (pi-ai:make-user-message :content prompt))
             :tools nil)
            (lambda (event)
              (declare (ignore event)))
            :max-tokens
            (min max-output-tokens
                 (pi-ai:model-max-tokens
                  (agent-model agent)))
            :abort-p (agent-abort-p agent)))
         (summary
           (and response
                (assistant-message-text response))))
    (when
        (or (null response)
            (member
             (pi-ai:assistant-message-stop-reason response)
             '(:error :aborted))
            (null summary)
            (zerop
             (length
              (string-trim
               '(#\Space #\Tab #\Newline #\Return)
               summary))))
      (error "The current model did not produce a compaction summary"))
    summary))

(defun effective-compaction-limit
    (configured context-window divisor)
  (min configured
       (max 1 (floor context-window divisor))))

(defun compact-agent (agent &key force-p)
  (let* ((session (agent-session agent))
         (model (agent-model agent))
         (context-window
           (and model
                (pi-ai:model-context-window model))))
    (unless (and session
                 context-window
                 (plusp context-window))
      (return-from compact-agent nil))
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
        (return-from compact-agent nil))
      (let* ((entries
               (session-context-entries session))
             (cut-point
               (compaction-cut-point
                entries keep-recent)))
        (unless cut-point
          (return-from compact-agent nil))
        (let* ((source-entries
                 (subseq entries 0 cut-point))
               (kept-entry
                 (nth cut-point entries))
               (source-ids
                 (mapcar #'session-entry-id
                         source-entries)))
          (when
              (eq :compaction
                  (session-entry-type
                   (car (last entries))))
            (return-from compact-agent nil))
          (emit-agent-event
           agent :compaction-start)
          (handler-case
              (let ((summary
                      (generate-compaction-summary
                       agent source-entries reserve)))
                (session-append-compaction
                 session summary source-ids
                 (session-entry-id kept-entry)
                 tokens-before)
                (setf (agent-messages agent)
                      (session-messages session))
                (emit-agent-event
                 agent :compaction-end)
                t)
            (error (condition)
              (emit-agent-event
               agent :compaction-error
               :error-message
               (princ-to-string condition))
              nil)))))))

(defun maybe-compact-agent (agent)
  (when (agent-auto-compact-p agent)
    (compact-agent agent)))

(defun context-overflow-message-p (message)
  (when
      (and
       (typep message 'pi-ai:assistant-message)
       (eq :error
           (pi-ai:assistant-message-stop-reason message))
       (pi-ai:assistant-message-error-message message))
    (let ((text
            (string-downcase
             (pi-ai:assistant-message-error-message
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
