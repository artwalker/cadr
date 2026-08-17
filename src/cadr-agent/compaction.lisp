(in-package #:cadr-agent)

(defun text-estimated-tokens (text)
  (ceiling (utf16-code-unit-length text) 4))

(defun text-and-image-content-estimated-characters (content)
  (if (stringp content)
      (utf16-code-unit-length content)
      (reduce
       #'+ content
       :key
       (lambda (block)
         (cond
           ((typep block 'cadr-ai:text-content)
            (utf16-code-unit-length
             (cadr-ai:text-content-text block)))
           ((typep block 'cadr-ai:image-content) 4800)
           (t 0)))
       :initial-value 0)))

(defun assistant-content-block-estimated-characters (block)
  (cond
    ((typep block 'cadr-ai:text-content)
     (utf16-code-unit-length
      (cadr-ai:text-content-text block)))
    ((typep block 'cadr-ai:thinking-content)
     (utf16-code-unit-length
      (cadr-ai:thinking-content-thinking block)))
    ((typep block 'cadr-ai:tool-call)
     (+ (utf16-code-unit-length
         (cadr-ai:tool-call-name block))
        (utf16-code-unit-length
         (cadr-ai::stringify-json
          (json-safe-value
           (cadr-ai:tool-call-arguments block))))))
    (t 0)))

(defun message-estimated-tokens (message)
  (ceiling
   (cond
     ((typep message 'cadr-ai:user-message)
      (text-and-image-content-estimated-characters
       (cadr-ai:user-message-content message)))
     ((typep message 'cadr-ai:assistant-message)
      (reduce
       #'+ (cadr-ai:assistant-message-content message)
       :key #'assistant-content-block-estimated-characters
       :initial-value 0))
     ((typep message 'cadr-ai:tool-result-message)
      (text-and-image-content-estimated-characters
       (cadr-ai:tool-result-message-content message)))
     ((typep message 'bash-execution-message)
      (+ (utf16-code-unit-length
          (bash-execution-message-command message))
         (utf16-code-unit-length
          (bash-execution-message-output message))))
     ((typep message 'custom-agent-message)
      (text-and-image-content-estimated-characters
       (custom-agent-message-content message)))
     ((typep message 'branch-summary-message)
      (utf16-code-unit-length
       (branch-summary-message-summary message)))
     ((typep message 'compaction-summary-agent-message)
      (utf16-code-unit-length
       (compaction-summary-agent-message-summary message)))
     (t 0))
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
  ;; One reverse walk: last valid usage plus the tail after that
  ;; cons. position-if/nth/subseq was three list walks.
  (let ((tail messages)
        (after-usage messages)
        (usage nil))
    (dolist (message messages)
      (when (valid-assistant-usage-p message)
        (setf usage (cadr-ai:assistant-message-usage message)
              after-usage (cdr tail)))
      (setf tail (cdr tail)))
    (if usage
        (+ (cadr-ai:usage-total usage)
           (reduce #'+ after-usage
                   :key #'message-estimated-tokens
                   :initial-value 0))
        (reduce #'+ messages
                :key #'message-estimated-tokens
                :initial-value 0))))

(defun compaction-field
    (from-extension-p extension key fallback)
  ;; One owner of the extension-vs-generated pick. Five copies
  ;; of (if from-extension-p (getf ...) fallback) drifted independently.
  (if from-extension-p
      (getf extension key)
      fallback))

(defun compaction-entry-estimated-tokens (entry)
  (case (session-entry-type entry)
    (:message
     (message-estimated-tokens
      (session-entry-message entry)))
    (:compaction
     (text-estimated-tokens
      (session-entry-summary entry)))
    (:branch-summary
     (text-estimated-tokens
      (session-entry-summary entry)))
    (:custom-message
     (ceiling
      (text-and-image-content-estimated-characters
       (session-entry-content entry))
      4))
    (otherwise 0)))

(defun session-context-estimated-tokens (session)
  (reduce
   #'+ (session-context-entries session)
   :key #'compaction-entry-estimated-tokens
   :initial-value 0))

(defun compaction-cut-point (entries keep-recent-tokens)
  ;; Reverse-then-forward is the same walk as the old (nth index …)
  ;; downfrom loop, in O(n) instead of O(n·k) (goal 20, 12F-3).
  (let ((accumulated 0)
        (candidate nil)
        (entry-count (length entries)))
    (loop for entry in (reverse entries)
          for reverse-index from 0
          for index = (- (1- entry-count) reverse-index)
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
  (let ((total-units (utf16-code-unit-length text)))
    (if (<= total-units 2000)
        text
        (let ((prefix
                (with-output-to-string (output)
                  (loop with units = 0
                        for character across text
                        for code = (char-code character)
                        for width = (if (> code #xffff) 2 1)
                        while (< units 2000)
                        do
                        (cond
                          ((<= (+ units width) 2000)
                           (write-char character output)
                           (incf units width))
                          (t
                           ;; JavaScript String.slice may end between the two
                           ;; UTF-16 code units of an astral character.
                           (write-char
                            (code-char
                             (+ #xd800
                                (ash (- code #x10000) -10)))
                            output)
                           (incf units)))))))
          (format nil "~A~%~%[... ~D more characters truncated]"
                  prefix
                  (- total-units 2000))))))

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
   (loop
     for entry in entries
     for text =
       (case (session-entry-type entry)
         (:message
          (message-summary-text
           (session-entry-message entry)))
         (:compaction
          (format nil
                  "[Previous compaction summary]: ~A"
                  (session-entry-summary entry))))
     when text collect text)))

(defun assistant-message-text (message)
  (format
   nil "~{~A~^~%~}"
   (loop for block in
           (cadr-ai:assistant-message-content message)
         when (typep block 'cadr-ai:text-content)
           collect (cadr-ai:text-content-text block))))

(defparameter +compaction-summarization-system-prompt+
  "You are a context summarization assistant. Your task is to read a conversation between a user and an AI assistant, then produce a structured summary following the exact format specified.

Do NOT continue the conversation. Do NOT respond to any questions in the conversation. ONLY output the structured summary.")

(defparameter +compaction-summarization-prompt+
  "The messages above are a conversation to summarize. Create a structured context checkpoint summary that another LLM will use to continue the work.

Use this EXACT format:

## Goal
[What is the user trying to accomplish? Can be multiple items if the session covers different tasks.]

## Constraints & Preferences
- [Any constraints, preferences, or requirements mentioned by user]
- [Or \"(none)\" if none were mentioned]

## Progress
### Done
- [x] [Completed tasks/changes]

### In Progress
- [ ] [Current work]

### Blocked
- [Issues preventing progress, if any]

## Key Decisions
- **[Decision]**: [Brief rationale]

## Next Steps
1. [Ordered list of what should happen next]

## Critical Context
- [Any data, examples, or references needed to continue]
- [Or \"(none)\" if not applicable]

Keep each section concise. Preserve exact file paths, function names, and error messages.")

(defparameter +compaction-update-summarization-prompt+
  "The messages above are NEW conversation messages to incorporate into the existing summary provided in <previous-summary> tags.

Update the existing structured summary with new information. RULES:
- PRESERVE all existing information from the previous summary
- ADD new progress, decisions, and context from the new messages
- UPDATE the Progress section: move items from \"In Progress\" to \"Done\" when completed
- UPDATE \"Next Steps\" based on what was accomplished
- PRESERVE exact file paths, function names, and error messages
- If something is no longer relevant, you may remove it

Use this EXACT format:

## Goal
[Preserve existing goals, add new ones if the task expanded]

## Constraints & Preferences
- [Preserve existing, add new ones discovered]

## Progress
### Done
- [x] [Include previously done items AND newly completed items]

### In Progress
- [ ] [Current work - update based on progress]

### Blocked
- [Current blockers - remove if resolved]

## Key Decisions
- **[Decision]**: [Brief rationale] (preserve all previous, add new)

## Next Steps
1. [Update based on current state]

## Critical Context
- [Preserve important context, add new if needed]

Keep each section concise. Preserve exact file paths, function names, and error messages.")

(defun generate-compaction-summary
    (agent messages max-output-tokens
     &optional custom-instructions (reason :manual)
               previous-summary)
  (let* ((conversation
           (serialize-conversation
            (convert-agent-messages-to-llm messages)))
         (base-prompt
           (if previous-summary
               +compaction-update-summarization-prompt+
               +compaction-summarization-prompt+))
         (base-prompt
           (if (and custom-instructions
                    (plusp (length custom-instructions)))
               (format nil "~A~%~%Additional focus: ~A"
                       base-prompt custom-instructions)
               base-prompt))
         (prompt
           (format
            nil
            "<conversation>~%~A~%</conversation>~%~%~A~A"
            conversation
            (if previous-summary
                (format nil
                        "<previous-summary>~%~A~%</previous-summary>~%~%"
                        previous-summary)
                "")
            base-prompt))
         (response
           (complete-summarization
            agent
            (cadr-ai:make-context
             :system-prompt
             +compaction-summarization-system-prompt+
             :messages
             (list
              (cadr-ai:make-user-message :content prompt))
             :tools nil)
            (min (floor (* 4 max-output-tokens) 5)
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
    (values
     summary
     (and response
          (cadr-ai:assistant-message-usage response)))))

(defparameter +turn-prefix-summarization-prompt+
  "This is the PREFIX of a turn that was too large to keep. The SUFFIX (recent work) is retained.

Summarize the prefix to provide context for the retained suffix:

## Original Request
[What did the user ask for in this turn?]

## Early Progress
- [Key decisions and work done in the prefix]

## Context for Suffix
- [Information needed to understand the retained recent work]

Be concise. Focus on what's needed to understand the kept suffix.")

(defun generate-turn-prefix-summary
    (agent messages max-output-tokens reason)
  (let* ((prompt
           (format
            nil "<conversation>~%~A~%</conversation>~%~%~A"
            (serialize-conversation
             (convert-agent-messages-to-llm messages))
            +turn-prefix-summarization-prompt+))
         (response
           (complete-summarization
            agent
            (cadr-ai:make-context
             :system-prompt
             +compaction-summarization-system-prompt+
             :messages
             (list (cadr-ai:make-user-message :content prompt))
             :tools nil)
            (min (floor max-output-tokens 2)
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
         (eq :error
             (cadr-ai:assistant-message-stop-reason response)))
      (error
       "Turn prefix summarization failed: ~A"
       (or
        (cadr-ai:assistant-message-error-message response)
        "Unknown error")))
    (values
     summary
     (and response
          (cadr-ai:assistant-message-usage response)))))

(defun optional-usage-value-sum (first second accessor)
  (let ((first-value (funcall accessor first))
        (second-value (funcall accessor second)))
    (and (or first-value second-value)
         (+ (or first-value 0)
            (or second-value 0)))))

(defun combine-compaction-usage (first second)
  (let ((first-cost (cadr-ai:usage-cost first))
        (second-cost (cadr-ai:usage-cost second)))
    (cadr-ai:make-usage
     :input (+ (cadr-ai:usage-input first)
               (cadr-ai:usage-input second))
     :output (+ (cadr-ai:usage-output first)
                (cadr-ai:usage-output second))
     :cache-read (+ (cadr-ai:usage-cache-read first)
                    (cadr-ai:usage-cache-read second))
     :cache-write (+ (cadr-ai:usage-cache-write first)
                     (cadr-ai:usage-cache-write second))
     :cache-write-1h
     (optional-usage-value-sum
      first second #'cadr-ai:usage-cache-write-1h)
     :reasoning
     (optional-usage-value-sum
      first second #'cadr-ai:usage-reasoning)
     :total (+ (cadr-ai:usage-total first)
               (cadr-ai:usage-total second))
     :cost
     (cadr-ai:make-cost
      :input (+ (cadr-ai:cost-input first-cost)
                (cadr-ai:cost-input second-cost))
      :output (+ (cadr-ai:cost-output first-cost)
                 (cadr-ai:cost-output second-cost))
      :cache-read (+ (cadr-ai:cost-cache-read first-cost)
                     (cadr-ai:cost-cache-read second-cost))
      :cache-write (+ (cadr-ai:cost-cache-write first-cost)
                      (cadr-ai:cost-cache-write second-cost))
      :total (+ (cadr-ai:cost-total first-cost)
                (cadr-ai:cost-total second-cost))))))

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

(defun generate-prepared-compaction-summary
    (agent source-entries preparation reserve
     custom-instructions reason)
  (declare (ignore source-entries))
  (multiple-value-bind (summary usage)
      (if (and (getf preparation :is-split-turn-p)
               (getf preparation :turn-prefix-messages))
          (let ((history-text "No prior history.")
                (history-usage nil))
            (when (getf preparation :messages-to-summarize)
              (multiple-value-setq
                  (history-text history-usage)
                (generate-compaction-summary
                 agent
                 (getf preparation :messages-to-summarize)
                 reserve custom-instructions reason
                 (getf preparation :previous-summary))))
            (when (agent-aborted-p agent)
              (return-from generate-prepared-compaction-summary
                (values nil nil)))
            (multiple-value-bind (prefix-text prefix-usage)
                (generate-turn-prefix-summary
                 agent
                 (getf preparation :turn-prefix-messages)
                 reserve reason)
              (values
               (format
                nil
                "~A~%~%---~%~%**Turn Context (split turn):**~%~%~A"
                history-text prefix-text)
               (if history-usage
                   (combine-compaction-usage
                    history-usage prefix-usage)
                   prefix-usage))))
          (generate-compaction-summary
           agent (getf preparation :messages-to-summarize)
           reserve custom-instructions reason
           (getf preparation :previous-summary)))
    (let ((file-ops (getf preparation :file-ops)))
      (values
       (concatenate
        'string summary
        (format-file-operations
         (getf file-ops :read-files)
         (getf file-ops :modified-files)))
       usage))))

(defun %compact-agent
    (agent &key force-p custom-instructions
                (reason :manual) will-retry-p)
  (let* ((session (agent-session agent))
         (model (agent-model agent))
         (context-window
           (and model
                (cadr-ai:model-context-window model))))
    ;; Baseline agent-session.ts:1790-1800,1905-1916 — a manual compact
    ;; with the unknown sentinel model still emits compaction_start and
    ;; then fails inside the summarization auth check; the failure
    ;; wrapper carries "Compaction failed: <NoApiKeyFound text>".
    (when (and (null model)
               (or force-p (eq reason :manual)))
      (emit-agent-event agent :compaction-start :reason reason)
      (emit-agent-event
       agent :compaction-end
       :reason reason
       :result nil
       :aborted nil
       :will-retry nil
       :error-message
       (format nil "Compaction failed: ~A"
               (cadr-ai::no-api-key-found-message "unknown")))
      (return-from %compact-agent nil))
    (unless (and session
                 context-window
                 (plusp context-window))
      (return-from %compact-agent nil))
    (let* ((messages (session-messages session))
           (tokens-before
             (context-estimated-tokens messages))
           (reserve
             (agent-compaction-reserve-tokens agent))
           (keep-recent
             (agent-compaction-keep-recent-tokens agent)))
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
                  (emit-agent-event
                   agent :compaction-end
                   :reason reason
                   :result nil
                   :aborted t
                   :will-retry nil)
                  (return-from %compact-agent nil))
                (unless (usable-extension-compaction-p
                         extension-compaction)
                  (setf extension-compaction nil))
                (let* ((from-extension-p
                         (not (null extension-compaction)))
                       (generated
                         (unless from-extension-p
                           (multiple-value-list
                            (generate-prepared-compaction-summary
                             agent source-entries preparation reserve
                             custom-instructions reason))))
                       (summary
                         (compaction-field
                          from-extension-p extension-compaction
                          :summary (first generated)))
                       (first-kept-entry-id
                         (compaction-field
                          from-extension-p extension-compaction
                          :first-kept-entry-id
                          (session-entry-id kept-entry)))
                       (effective-tokens-before
                         (compaction-field
                          from-extension-p extension-compaction
                          :tokens-before tokens-before))
                       (usage
                         (compaction-field
                          from-extension-p extension-compaction
                          :usage (second generated)))
                       (details
                         (compaction-field
                          from-extension-p extension-compaction
                          :details
                          (getf preparation :file-ops))))
                (when
                    (extension-cancellation-aborted-p signal)
                  (emit-agent-event
                   agent :compaction-end
                   :reason reason
                   :result nil
                   :aborted t
                   :will-retry nil)
                  (return-from %compact-agent nil))
                (assert-agent-not-shutdown agent)
                (let* ((entry-id
                         (session-append-compaction
                          session summary source-ids
                          first-kept-entry-id
                          effective-tokens-before
                          :details details
                          :usage usage
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
                (let ((result
                        (list
                         :summary summary
                         :first-kept-entry-id first-kept-entry-id
                         :tokens-before effective-tokens-before
                         :estimated-tokens-after
                         (session-context-estimated-tokens session)
                         :usage usage
                         :details details)))
                  (emit-agent-event
                   agent :compaction-end
                   :reason reason
                   :result result
                   :aborted nil
                   :will-retry (not (null will-retry-p)))
                  result)))
            (error (condition)
              (emit-agent-event
               agent :compaction-end
               :reason reason
               :result nil
               :aborted nil
               :will-retry nil
               :error-message
               (format
                nil
                (case reason
                  (:overflow
                   "Context overflow recovery failed: ~A")
                  (:threshold
                   "Auto-compaction failed: ~A")
                  (otherwise
                   "Compaction failed: ~A"))
                (princ-to-string condition)))
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
    (%compact-agent agent :reason :threshold)))

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
