(in-package #:cadr-cli)

(defstruct tui-entry
  type
  (text "" :type string)
  label
  tokens-before
  (expanded-p nil :type boolean)
  (content-blocks nil :type list)
  (streaming-p nil :type boolean)
  (markdown-cache nil :type list)
  (stop-reason :pending :type symbol)
  error-message
  (has-tool-calls-p nil :type boolean)
  tool-call-id
  tool-block
  (tool-render-state (make-hash-table)
                     :type hash-table)
  custom-call-render
  (custom-call-rendered-p nil :type boolean)
  custom-result-render
  (custom-result-rendered-p nil :type boolean)
  custom-type
  custom-payload
  (custom-options nil :type list)
  custom-component
  custom-component-theme
  custom-component-snapshot
  custom-component-options
  (render-cache-valid-p nil :type boolean)
  render-cache-width
  render-cache-theme
  render-cache-extension-snapshot
  render-cache-mermaid-mode
  (render-cache-lines nil :type list))

(defstruct (tui-state
            (:constructor %make-tui-state))
  ;; NIL is the baseline unknown-model sentinel (agent.ts DEFAULT_MODEL);
  ;; the footer renders it as "unknown".
  (model nil :type (or null string))
  provider
  thinking
  (cwd "" :type string)
  branch
  session-name
  (startup-compact-lines nil :type list)
  (startup-expanded-lines nil :type list)
  session
  (entries nil :type list)
  entries-tail
  entries-tail-head
  current-assistant
  (input-tokens 0 :type (integer 0 *))
  (output-tokens 0 :type (integer 0 *))
  (cache-tokens 0 :type (integer 0 *))
  (cache-read-tokens 0 :type (integer 0 *))
  (cache-write-tokens 0 :type (integer 0 *))
  latest-cache-hit-rate
  (context-window 0 :type (integer 0 *))
  (context-percent 0d0)
  (auto-compact-p t :type boolean)
  (cost 0d0 :type double-float)
  (cost-known-p nil :type boolean)
  (multiple-providers-p nil :type boolean)
  (subscription-p nil :type boolean)
  (statuses nil :type list)
  (steering-messages nil :type list)
  (follow-up-messages nil :type list)
  (widgets-above nil :type list)
  (widgets-below nil :type list)
  (tools-expanded-p nil :type boolean)
  header-component
  footer-component
  (working-visible-p t :type boolean)
  (agent-working-p nil :type boolean)
  ;; Set between an assistant message-end or a completed tool-end
  ;; (no sibling still running) and the event that resolves the turn
  ;; (agent-end, agent-settled, retry, next tool or user message).
  ;; Assistant message-start does not lift it. While set, frames omit
  ;; the loader; see tool-rendering.lisp :message-end / :tool-execution-end.
  (settle-window-p nil :type boolean)
  working-message
  working-indicator-frames
  working-indicator-interval-ms
  hidden-thinking-label
  (hide-thinking-block-p nil :type boolean)
  status-message
  (mermaid-mode "streaming" :type string))

(defun make-tui-state
    (&key model provider thinking cwd branch
       session-name
       multiple-providers-p
       subscription-p
       statuses
       startup-compact-lines
       startup-expanded-lines
       session messages
       hide-thinking-block-p
       (auto-compact-p t)
       (context-window 0)
       (mermaid-mode "streaming"))
  (let ((state
          (%make-tui-state
           :model model
           :provider provider
           :thinking thinking
           :cwd (or cwd "")
           :branch branch
           :session-name session-name
           :multiple-providers-p
           (not (null multiple-providers-p))
           :subscription-p
           (not (null subscription-p))
           :statuses (copy-tree statuses)
           :startup-compact-lines
           (copy-list startup-compact-lines)
           :startup-expanded-lines
           (copy-list startup-expanded-lines)
           :context-window
           (max 0 context-window)
           :auto-compact-p
           (not (null auto-compact-p))
           :hide-thinking-block-p
           (not (null hide-thinking-block-p))
           :mermaid-mode
           (or mermaid-mode "streaming")
           :session session)))
    (dolist (message messages)
      (seed-tui-message state message))
    state))

(defun apply-tui-footer-state (state values)
  (let ((missing (gensym "MISSING")))
    (labels
        ((value (key)
           (getf values key missing))
         (assign (key setter)
           (let ((current (value key)))
             (unless (eq current missing)
               (funcall setter current)))))
      (assign
       :model
       (lambda (value)
         (when value
           (setf (tui-state-model state)
                 value))))
      (assign
       :provider
       (lambda (value)
         (setf (tui-state-provider state)
               value)))
      (assign
       :thinking
       (lambda (value)
         (setf (tui-state-thinking state)
               value)))
      (assign
       :context-window
       (lambda (value)
         (setf (tui-state-context-window state)
               (max 0 (or value 0)))))
      (assign
       :context-percent
       (lambda (value)
         (setf (tui-state-context-percent state)
               value)))
      (assign
       :session-name
       (lambda (value)
         (setf (tui-state-session-name state)
               value)))
      (assign
       :multiple-providers-p
       (lambda (value)
         (setf
          (tui-state-multiple-providers-p state)
          (not (null value)))))
      (assign
       :subscription-p
       (lambda (value)
         (setf
          (tui-state-subscription-p state)
          (not (null value)))))
      (assign
       :input
       (lambda (value)
         (setf (tui-state-input-tokens state)
               (max 0 (or value 0)))))
      (assign
       :output
       (lambda (value)
         (setf (tui-state-output-tokens state)
               (max 0 (or value 0)))))
      (assign
       :cache-read
       (lambda (value)
         (setf
          (tui-state-cache-read-tokens state)
          (max 0 (or value 0)))))
      (assign
       :cache-write
       (lambda (value)
         (setf
          (tui-state-cache-write-tokens state)
          (max 0 (or value 0)))))
      (assign
       :latest-cache-hit-rate
       (lambda (value)
         (setf
          (tui-state-latest-cache-hit-rate state)
          value)))
      (assign
       :cost
       (lambda (value)
         (setf
          (tui-state-cost state)
          (coerce (or value 0d0)
                  'double-float))))
      (assign
       :cost-known-p
       (lambda (value)
         (setf
          (tui-state-cost-known-p state)
          (not (null value)))))
      (assign
       :auto-compact-p
       (lambda (value)
         (setf
          (tui-state-auto-compact-p state)
          (not (null value)))))))
  state)

(defun model-footer-thinking-level (model thinking)
  (and
   model
   (cadr-ai:model-reasoning-p model)
   thinking))

(defun tui-multiline-editor-p (editor)
  (typep editor 'cadr-tui:multiline-editor))

(defun synchronize-tui-editor-border (state editor)
  (when (tui-multiline-editor-p editor)
    (unless
        (eq
         :bash-mode
         (cadr-tui:multiline-editor-border-color-key
          editor))
      (cadr-tui:editor-set-border-mode
       editor :thinking
       (or (tui-state-thinking state) :off))))
  editor)

(defun tui-editor-component-text (editor)
  (if (tui-multiline-editor-p editor)
      (cadr-tui:editor-text editor)
      (cadr-tui:editor-component-text editor)))

(defun tui-editor-component-set-text (editor text)
  (if (tui-multiline-editor-p editor)
      (cadr-tui:editor-set-text editor text)
      (cadr-tui:editor-component-set-text editor text)))

(defun tui-editor-component-clear (editor)
  (if (tui-multiline-editor-p editor)
      (cadr-tui:editor-clear editor)
      (cadr-tui:editor-component-set-text editor "")))

(defun tui-editor-bash-input-p (editor)
  (let ((text
          (string-left-trim
           '(#\Space #\Tab #\Newline #\Return)
           (tui-editor-component-text editor))))
    (and
     (plusp (length text))
     (char= (char text 0) #\!))))

(defun synchronize-tui-editor-input-border
    (state editor)
  (when (tui-multiline-editor-p editor)
    (if (tui-editor-bash-input-p editor)
        (cadr-tui:editor-set-border-mode
         editor :bash)
        (cadr-tui:editor-set-border-mode
         editor :thinking
         (or (tui-state-thinking state) :off))))
  editor)

(defun handle-tui-editor-event
    (state editor event)
  (multiple-value-bind (action value)
      (if (tui-multiline-editor-p editor)
          (cadr-tui:editor-handle-event editor event)
          (cadr-tui:component-handle-event editor event))
    ;; Submission owns its border until dispatched work settles.
    ;; Every non-submit edit follows the current input immediately.
    (unless (eq action :submit)
      (synchronize-tui-editor-input-border
       state editor))
    (values action value)))
