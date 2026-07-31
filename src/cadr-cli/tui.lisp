(in-package #:cadr-cli)

(defstruct tui-entry
  type
  (text "" :type string)
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
  (custom-result-rendered-p nil :type boolean))

(defstruct (tui-state
            (:constructor %make-tui-state))
  (model "—" :type string)
  provider
  thinking
  (cwd "" :type string)
  branch
  session-name
  (startup-compact-lines nil :type list)
  (startup-expanded-lines nil :type list)
  session
  (entries nil :type list)
  current-assistant
  (input-tokens 0 :type (integer 0 *))
  (output-tokens 0 :type (integer 0 *))
  (cache-tokens 0 :type (integer 0 *))
  (cache-read-tokens 0 :type (integer 0 *))
  (cache-write-tokens 0 :type (integer 0 *))
  latest-cache-hit-rate
  (context-window 0 :type (integer 0 *))
  context-percent
  (auto-compact-p t :type boolean)
  (cost 0d0 :type double-float)
  (cost-known-p nil :type boolean)
  (multiple-providers-p nil :type boolean)
  (subscription-p nil :type boolean)
  (statuses nil :type list)
  (widgets-above nil :type list)
  (widgets-below nil :type list)
  (tools-expanded-p nil :type boolean)
  status-message)

(defstruct extension-custom-ui-state
  component
  done-function)

(defun render-extension-custom-ui
    (state width)
  (let ((component
          (extension-custom-ui-state-component
           state)))
    (cond
      ((cadr-tui::select-list-p component)
       (cadr-tui:render-select-list
        component width))
      (t
       (extension-render-value-lines
        component width)))))

(defun extension-custom-ui-handle-event
    (state event)
  (let ((component
          (extension-custom-ui-state-component
           state)))
    (cond
      ((cadr-tui::select-list-p component)
       (cadr-tui:select-list-handle-event
        component event))
      ((eq (cadr-tui:input-event-kind event)
           :escape)
       (values :cancel nil))
      ((eq (cadr-tui:input-event-kind event)
           :enter)
       (values :select component))
      (t
       (values nil nil)))))

(defun make-tui-state
    (&key model provider thinking cwd branch
       session-name
       multiple-providers-p
       subscription-p
       statuses
       startup-compact-lines
       startup-expanded-lines
       session messages
       (auto-compact-p t)
       (context-window 0))
  (let ((state
          (%make-tui-state
           :model (or model "—")
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

(defun synchronize-tui-editor-border (state editor)
  (unless
      (eq
       :bash-mode
       (cadr-tui::multiline-editor-border-color-key
        editor))
    (cadr-tui:editor-set-border-mode
     editor :thinking
     (or (tui-state-thinking state) :off)))
  editor)

(defun tui-editor-bash-input-p (editor)
  (let ((text
          (string-left-trim
           '(#\Space #\Tab #\Newline #\Return)
           (cadr-tui:editor-text editor))))
    (and
     (plusp (length text))
     (char= (char text 0) #\!))))

(defun synchronize-tui-editor-input-border
    (state editor)
  (if (tui-editor-bash-input-p editor)
      (cadr-tui:editor-set-border-mode
       editor :bash)
      (cadr-tui:editor-set-border-mode
       editor :thinking
       (or (tui-state-thinking state) :off)))
  editor)

(defun handle-tui-editor-event
    (state editor event)
  (multiple-value-bind (action value)
      (cadr-tui:editor-handle-event editor event)
    ;; Submission owns its border until dispatched work settles.
    ;; Every non-submit edit follows the current input immediately.
    (unless (eq action :submit)
      (synchronize-tui-editor-input-border
       state editor))
    (values action value)))

(defun set-tui-keyed-lines
    (entries key lines)
  (if lines
      (acons
       key (copy-list lines)
       (remove key entries
               :key #'car
               :test #'string=))
      (remove key entries
              :key #'car
              :test #'string=)))

(defun set-tui-widget
    (state key lines placement)
  (ecase placement
    (:above-editor
     (setf
      (tui-state-widgets-above state)
      (set-tui-keyed-lines
       (tui-state-widgets-above state)
       key lines)))
    (:below-editor
     (setf
      (tui-state-widgets-below state)
      (set-tui-keyed-lines
       (tui-state-widgets-below state)
       key lines))))
  state)

(defun render-tui-widgets (entries width)
  (loop for entry in
        (sort (copy-list entries)
              #'string< :key #'car)
        append
        (loop for line in (cdr entry)
              append
              (cadr-tui:wrap-text line width))))

(defun append-tui-entry (state entry)
  (setf
   (tui-state-entries state)
   (nconc (tui-state-entries state)
          (list entry)))
  entry)

(defun add-tui-notice (state text)
  (let ((trimmed
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           (or text ""))))
    (when (plusp (length trimmed))
      (append-tui-entry
       state
       (make-tui-entry
        :type :notice
        :text trimmed))))
  state)

(defun terminal-hyperlink (url label)
  (format nil "~C]8;;~A~C~A~C]8;;~C"
          #\Escape url (code-char 7) label
          #\Escape (code-char 7)))

(defun render-auth-url-lines (url width)
  (let* ((linked
           (terminal-hyperlink url url))
         (hint
           (terminal-hyperlink
            url "Ctrl+click to open")))
    (append
     (cadr-tui:wrap-text linked width)
     (list hint))))

(defun add-tui-auth-url (state url)
  (append-tui-entry
   state
   (make-tui-entry
    :type :auth-url
    :text url))
  state)

(defun startup-resource-names (resources accessor)
  (mapcar accessor resources))

(defun make-tui-startup-lines
    (resources &key (version "0.1.0"))
  (labels
      ((section (title names)
         (when names
           (list
            (format nil "[~A]" title)
            (format nil "  ~{~A~^, ~}"
                    (sort
                     (remove-duplicates
                      (copy-list names)
                      :test #'string=)
                     #'string<)))))
       (sections ()
         (append
          (section
           "Skills"
           (startup-resource-names
            (resource-snapshot-skills resources)
            #'cadr-agent:skill-name))
          (section
           "Prompt Templates"
           (startup-resource-names
            (resource-snapshot-prompts resources)
            #'cadr-agent:prompt-template-name))
          (section
           "Themes"
           (startup-resource-names
            (resource-snapshot-themes resources)
            (lambda (theme)
              (or (getf theme :name) "unnamed"))))
          (section
           "Context"
           (mapcar
            #'namestring
            (resource-snapshot-context-files
             resources))))))
    (let* ((logo (format nil "cadr v~A" version))
           (compact
             (list
              logo
              "escape interrupt · ctrl+c/ctrl+d clear/exit · / commands · ! bash · ctrl+o more"
              "Press ctrl+o to show full startup help and loaded resources."
              ""
              "Cadr can explain its own features and look up its docs. Ask it how to use or extend Cadr."))
           (expanded
             (append
              (list
               logo
               "escape to interrupt"
               "ctrl+c to clear"
               "ctrl+c twice to exit"
               "ctrl+d to exit (empty)"
               "ctrl+z to suspend"
               "ctrl+k to delete to end"
               "ctrl+p/ctrl+n to cycle models"
               "ctrl+o to expand tools"
               "/ for commands"
               "! to run bash"
               ""
               "Cadr can explain its own features and look up its docs. Ask it how to use or extend Cadr.")
              (when (sections)
                (cons "" (sections))))))
      (values
       (append compact
               (when (sections)
                 (cons "" (sections))))
       expanded))))

(defun render-tui-startup-lines (lines width)
  (loop for line in lines
        for index from 0
        for styled =
          (cond
            ((zerop index)
             (cadr-tui:theme-foreground
              :accent
              (cadr-tui:theme-bold line)
              :enabled-p t))
            ((and
              (plusp (length line))
              (char= (char line 0) #\[))
             (cadr-tui:theme-foreground
              :md-heading line
              :enabled-p t))
            (t
             (cadr-tui:theme-foreground
              :dim line
              :enabled-p t)))
        append
        (cadr-tui:wrap-text styled width)))

(defparameter +tui-spinner-frames+
  #("⠋" "⠙" "⠹" "⠸" "⠼"
    "⠴" "⠦" "⠧" "⠇" "⠏"))

(defconstant +tui-spinner-interval-seconds+
  0.08d0)

(defconstant +tui-min-render-interval-seconds+
  0.016d0)

(defun tui-monotonic-seconds ()
  (/ (get-internal-real-time)
     (coerce internal-time-units-per-second
             'double-float)))

(defstruct (tui-render-coordinator
            (:constructor
                %make-tui-render-coordinator))
  (lock
    (sb-thread:make-mutex
     :name "cadr-tui-render-coordinator"))
  (clock-function #'tui-monotonic-seconds
                  :type function)
  (interval +tui-min-render-interval-seconds+
            :type double-float)
  last-render-at
  (pending-p nil :type boolean)
  (force-p nil :type boolean)
  (stopped-p nil :type boolean))

(defun make-tui-render-coordinator
    (&key
       (clock-function #'tui-monotonic-seconds)
       (interval +tui-min-render-interval-seconds+))
  (%make-tui-render-coordinator
   :clock-function clock-function
   :interval (coerce interval 'double-float)))

(defun request-tui-render
    (coordinator &optional force-p)
  (sb-thread:with-mutex
      ((tui-render-coordinator-lock coordinator))
    (unless
        (tui-render-coordinator-stopped-p
         coordinator)
      (setf
       (tui-render-coordinator-pending-p
        coordinator)
       t
       (tui-render-coordinator-force-p
        coordinator)
       (or force-p
           (tui-render-coordinator-force-p
            coordinator)))))
  nil)

(defun flush-tui-render
    (coordinator render-function
     &key force-p)
  (let ((render-p nil))
    (sb-thread:with-mutex
        ((tui-render-coordinator-lock coordinator))
      (unless
          (tui-render-coordinator-stopped-p
           coordinator)
        (let* ((now
                 (funcall
                  (tui-render-coordinator-clock-function
                   coordinator)))
               (last-render-at
                 (tui-render-coordinator-last-render-at
                  coordinator))
               (due-p
                 (or force-p
                     (tui-render-coordinator-force-p
                      coordinator)
                     (null last-render-at)
                     (>= (- now last-render-at)
                         (tui-render-coordinator-interval
                          coordinator)))))
          (when
              (and
               (or force-p
                   (tui-render-coordinator-pending-p
                    coordinator))
               due-p)
            (setf
             render-p t
             (tui-render-coordinator-pending-p
              coordinator)
             nil
             (tui-render-coordinator-force-p
              coordinator)
             nil
             (tui-render-coordinator-last-render-at
              coordinator)
             now)))))
    (when render-p
      ;; Rendering takes the independent TUI state mutex.  Never
      ;; call it while holding the coordinator mutex: a render may
      ;; itself enqueue the next, final frame.
      (funcall render-function))
    render-p))

(defun stop-tui-render-coordinator (coordinator)
  (sb-thread:with-mutex
      ((tui-render-coordinator-lock coordinator))
    (setf
     (tui-render-coordinator-stopped-p coordinator)
     t
     (tui-render-coordinator-pending-p coordinator)
     nil
     (tui-render-coordinator-force-p coordinator)
     nil))
  nil)

(defstruct tui-status-animation
  (active-p nil :type boolean)
  (frame-index 0 :type (integer 0 *))
  (frame (aref +tui-spinner-frames+ 0)
         :type string)
  next-frame-at
  tracked-status
  retry-attempt
  retry-maximum
  retry-deadline
  retry-seconds)

(defun parse-tui-retry-status (message)
  (when message
    (multiple-value-bind (match registers)
        (cl-ppcre:scan-to-strings
         "^Retrying \\(([0-9]+)/([0-9]+)\\) in ([0-9]+)s\\.\\.\\.$"
         message)
      (declare (ignore match))
      (when registers
        (values
         (parse-integer (aref registers 0))
         (parse-integer (aref registers 1))
         (parse-integer (aref registers 2)))))))

(defun reset-tui-status-animation
    (animation message now)
  (setf
   (tui-status-animation-active-p animation) t
   (tui-status-animation-frame-index animation) 0
   (tui-status-animation-frame animation)
   (aref +tui-spinner-frames+ 0)
   (tui-status-animation-next-frame-at animation)
   (+ now +tui-spinner-interval-seconds+)
   (tui-status-animation-tracked-status animation)
   message
   (tui-status-animation-retry-attempt animation)
   nil
   (tui-status-animation-retry-maximum animation)
   nil
   (tui-status-animation-retry-deadline animation)
   nil
   (tui-status-animation-retry-seconds animation)
   nil)
  (multiple-value-bind (attempt maximum seconds)
      (parse-tui-retry-status message)
    (when attempt
      (setf
       (tui-status-animation-retry-attempt animation)
       attempt
       (tui-status-animation-retry-maximum animation)
       maximum
       (tui-status-animation-retry-deadline animation)
       (+ now seconds)
       (tui-status-animation-retry-seconds animation)
       seconds))))

(defun advance-tui-status-animation
    (animation state busy-p now)
  (let* ((message
           (tui-state-status-message state))
         (active-p
           (not (null (or message busy-p))))
         (changed-p nil))
    (cond
      ((not active-p)
       (when
           (tui-status-animation-active-p animation)
         (setf changed-p t))
       (setf
        (tui-status-animation-active-p animation)
        nil
        (tui-status-animation-frame-index animation)
        0
        (tui-status-animation-frame animation)
        (aref +tui-spinner-frames+ 0)
        (tui-status-animation-next-frame-at animation)
        nil
        (tui-status-animation-tracked-status animation)
        nil
        (tui-status-animation-retry-deadline animation)
        nil))
      ((or
        (not
         (tui-status-animation-active-p animation))
        (not
         (equal message
                (tui-status-animation-tracked-status
                 animation))))
       (reset-tui-status-animation
        animation message now)
       (setf changed-p t)))
    (when
        (tui-status-animation-active-p animation)
      (let ((next
              (tui-status-animation-next-frame-at
               animation)))
        (when (and next (>= now next))
          (let ((steps
                  (1+
                   (floor
                    (- now next)
                    +tui-spinner-interval-seconds+))))
            (setf
             (tui-status-animation-frame-index
              animation)
             (mod
              (+
               (tui-status-animation-frame-index
                animation)
               steps)
              (length +tui-spinner-frames+))
             (tui-status-animation-next-frame-at
              animation)
             (+ next
                (* steps
                   +tui-spinner-interval-seconds+))
             (tui-status-animation-frame animation)
             (aref
              +tui-spinner-frames+
              (tui-status-animation-frame-index
               animation))
             changed-p t))))
      (let ((deadline
              (tui-status-animation-retry-deadline
               animation)))
        (when deadline
          (let ((seconds
                  (max 0
                       (ceiling (- deadline now)))))
            (unless
                (eql
                 seconds
                 (tui-status-animation-retry-seconds
                  animation))
              (let ((updated
                      (format
                       nil "Retrying (~D/~D) in ~Ds..."
                       (tui-status-animation-retry-attempt
                        animation)
                       (tui-status-animation-retry-maximum
                        animation)
                       seconds)))
                (setf
                 (tui-status-animation-retry-seconds
                  animation)
                 seconds
                 (tui-status-animation-tracked-status
                  animation)
                 updated
                 (tui-state-status-message state)
                 updated
                 changed-p t)))))))
    changed-p))

(defun render-tui-status-indicator
    (message width &key
                     (reserve-idle-p t)
                     (spinner-frame
                       (aref
                        +tui-spinner-frames+ 0)))
  (let ((blank
          (make-string width
                       :initial-element #\Space)))
    (if message
        (let* ((frame
                 (or spinner-frame ""))
               (separator
                 (if (plusp (length frame))
                     " " ""))
               (available
                 (max
                  0
                  (- width
                     (cadr-tui:visible-width frame)
                     (length separator))))
               (trimmed-message
                 (cadr-tui:truncate-to-width
                  message available ""))
               (spinner-token
                 (if
                     (uiop:string-prefix-p
                      "Retrying (" message)
                     :warning
                     :accent)))
          (list
           ""
           (concatenate
            'string
            (cadr-tui:theme-foreground
             spinner-token frame
             :enabled-p t)
            separator
            (cadr-tui:theme-foreground
             :muted trimmed-message
             :enabled-p t))))
        (and reserve-idle-p
             (list blank blank)))))

(defun assistant-price-known-p (message)
  (not
   (null
    (ignore-errors
      (cadr-ai:find-model-metadata
       (cadr-ai:assistant-message-provider message)
       (cadr-ai:assistant-message-model message))))))

(defun accumulate-message-usage (state message)
  (let* ((usage
           (cadr-ai:assistant-message-usage message))
         (cost (cadr-ai:usage-cost usage))
         (input (cadr-ai:usage-input usage))
         (cache-read
           (cadr-ai:usage-cache-read usage))
         (cache-write
           (cadr-ai:usage-cache-write usage))
         (prompt-total
           (+ input cache-read cache-write))
         (context-total
           (or
            (and
             (plusp (cadr-ai:usage-total usage))
             (cadr-ai:usage-total usage))
            (+ prompt-total
               (cadr-ai:usage-output usage)))))
    (incf (tui-state-input-tokens state)
          input)
    (incf (tui-state-output-tokens state)
          (cadr-ai:usage-output usage))
    (incf
     (tui-state-cache-read-tokens state)
     cache-read)
    (incf
     (tui-state-cache-write-tokens state)
     cache-write)
    (incf
     (tui-state-cache-tokens state)
     (+ cache-read cache-write))
    (setf
     (tui-state-latest-cache-hit-rate state)
     (and
      (plusp prompt-total)
      (* 100d0
         (/ cache-read prompt-total)))
     (tui-state-context-percent state)
     (and
      (plusp
       (tui-state-context-window state))
      (* 100d0
         (/ context-total
            (tui-state-context-window
             state)))))
    (when (assistant-price-known-p message)
      (setf (tui-state-cost-known-p state) t)
      (incf (tui-state-cost state)
            (cadr-ai:cost-total cost)))))

(defun assistant-message-has-tool-calls-p
    (message)
  (some
   (lambda (block)
     (typep block 'cadr-ai:tool-call))
   (cadr-ai:assistant-message-content message)))

(defun assistant-display-blocks (message)
  (let ((result nil))
    (dolist
        (block
         (cadr-ai:assistant-message-content
          message))
      (cond
        ((typep block 'cadr-ai:text-content)
         (let ((text
                 (string-trim
                  '(#\Space #\Tab #\Newline
                    #\Return)
                  (cadr-ai:text-content-text
                   block))))
           (when (plusp (length text))
             (setf result
                   (nconc
                    result
                    (list
                     (cons :assistant text)))))))
        ((typep block 'cadr-ai:thinking-content)
         (let ((thinking
                 (string-trim
                  '(#\Space #\Tab #\Newline
                    #\Return)
                  (cadr-ai:thinking-content-thinking
                   block))))
           (when (plusp (length thinking))
             (let ((last (car (last result))))
               (if
                   (and last
                        (eq :assistant-thinking
                            (car last)))
                   (setf
                    (cdr last)
                    (format nil "~A~%~%~A"
                            (cdr last) thinking))
                   (setf result
                         (nconc
                          result
                          (list
                           (cons
                            :assistant-thinking
                            thinking)))))))))))
    result))

(defun seed-tui-message (state message)
  (typecase message
    (cadr-ai:user-message
     (append-tui-entry
      state
      (make-tui-entry
       :type :user
       :text
       (cadr-ai::content-text
        (cadr-ai:user-message-content message)))))
    (cadr-ai:assistant-message
     (append-tui-entry
      state
      (make-tui-entry
       :type :assistant
       :text (response-text message)
       :content-blocks
       (assistant-display-blocks message)
       :stop-reason
       (cadr-ai:assistant-message-stop-reason
        message)
       :error-message
       (cadr-ai:assistant-message-error-message
        message)
       :has-tool-calls-p
       (assistant-message-has-tool-calls-p
        message)))
     (accumulate-message-usage state message)))
  state)

(defun reset-tui-messages
    (state messages &key preserve-usage-p
                         context-unknown-p)
  (let ((saved-usage
          (and
           preserve-usage-p
           (list
            (tui-state-input-tokens state)
            (tui-state-output-tokens state)
            (tui-state-cache-tokens state)
            (tui-state-cache-read-tokens state)
            (tui-state-cache-write-tokens state)
            (tui-state-latest-cache-hit-rate state)
            (tui-state-cost state)
            (tui-state-cost-known-p state)))))
    (setf
     (tui-state-entries state) nil
     (tui-state-current-assistant state) nil
     (tui-state-input-tokens state) 0
     (tui-state-output-tokens state) 0
     (tui-state-cache-tokens state) 0
     (tui-state-cache-read-tokens state) 0
     (tui-state-cache-write-tokens state) 0
     (tui-state-latest-cache-hit-rate state) nil
     (tui-state-context-percent state) nil
     (tui-state-cost state) 0d0
     (tui-state-cost-known-p state) nil)
    (dolist (message messages)
      (seed-tui-message state message))
    (when saved-usage
      (setf
       (tui-state-input-tokens state)
       (pop saved-usage)
       (tui-state-output-tokens state)
       (pop saved-usage)
       (tui-state-cache-tokens state)
       (pop saved-usage)
       (tui-state-cache-read-tokens state)
       (pop saved-usage)
       (tui-state-cache-write-tokens state)
       (pop saved-usage)
       (tui-state-latest-cache-hit-rate state)
       (pop saved-usage)
       (tui-state-cost state)
       (pop saved-usage)
       (tui-state-cost-known-p state)
       (pop saved-usage)))
    (when context-unknown-p
      (setf
       (tui-state-context-percent state)
       nil)))
  state)

(defun safe-tool-summary-value
    (value &optional (fallback "[invalid argument]"))
  (if (stringp value)
      (cadr-tui:strip-terminal-sequences value)
      fallback))

(defun generic-tool-arguments-summary (arguments)
  (handler-case
      (cadr-tui:strip-terminal-sequences
       (cadr-ai::stringify-json arguments))
    (condition ()
      (cadr-tui:strip-terminal-sequences
       (princ-to-string arguments)))))

(defun tool-arguments-summary (call)
  (let* ((name
           (cadr-ai:tool-call-name call))
         (arguments
           (cadr-ai:tool-call-arguments call)))
    (labels
        ((value (key)
           (cadr-ai::json-get arguments key))
         (path (&optional (fallback "[invalid path]"))
           (safe-tool-summary-value
            (value "path") fallback))
         (limit-suffix (format-control)
           (let ((limit (value "limit")))
             (if (numberp limit)
                 (format nil format-control limit)
                 ""))))
      (cond
        ((string-equal name "bash")
         (format
          nil "~A~A"
          (safe-tool-summary-value
           (value "command")
           "[invalid command]")
          (let ((timeout (value "timeout")))
            (if (numberp timeout)
                (format nil " (timeout ~As)" timeout)
                ""))))
        ((string-equal name "read")
         (let ((offset (value "offset"))
               (limit (value "limit")))
           (format
            nil "~A~A"
            (path)
            (if (or (numberp offset)
                    (numberp limit))
                (let* ((start
                         (if (numberp offset)
                             offset 1))
                       (end
                         (and
                          (numberp limit)
                          (+ start limit -1))))
                  (format nil ":~A~@[-~A~]"
                          start end))
                ""))))
        ((or (string-equal name "write")
             (string-equal name "edit"))
         (path))
        ((string-equal name "grep")
         (let ((pattern
                 (safe-tool-summary-value
                  (value "pattern")
                  "[invalid pattern]"))
               (base
                 (safe-tool-summary-value
                  (or (value "path") ".") "."))
               (glob (value "glob")))
           (format
            nil "/~A/ in ~A~A~A"
            pattern base
            (if (stringp glob)
                (format
                 nil " (~A)"
                 (safe-tool-summary-value glob))
                "")
            (limit-suffix " limit ~A"))))
        ((string-equal name "find")
         (format
          nil "~A in ~A~A"
          (safe-tool-summary-value
           (value "pattern")
           "[invalid pattern]")
          (safe-tool-summary-value
           (or (value "path") ".") ".")
          (limit-suffix " (limit ~A)")))
        ((string-equal name "ls")
         (format
          nil "~A~A"
          (safe-tool-summary-value
           (or (value "path") ".") ".")
          (limit-suffix " (limit ~A)")))
        (t
         (generic-tool-arguments-summary
          arguments))))))

(defun tool-result-text (result)
  (format
   nil "~{~A~^~%~}"
   (loop for block in
         (cadr-ai:tool-result-message-content result)
         when (typep block 'cadr-ai:text-content)
           collect (cadr-ai:text-content-text block))))

(defun tool-result-detail (result key json-key)
  (let ((details
          (cadr-ai:tool-result-message-details result)))
    (cond
      ((hash-table-p details)
       (cadr-ai::json-get details json-key))
      ((listp details)
       (getf details key))
      (t nil))))

(defun rendered-tool-result-text (call result)
  (let ((text (tool-result-text result)))
    (if
        (and
         (string-equal
          (cadr-ai:tool-call-name call) "edit")
         (not
          (cadr-ai:tool-result-message-is-error result)))
        (let ((diff
                (tool-result-detail
                 result :diff "diff")))
          (if (and (stringp diff)
                   (plusp (length diff)))
              diff
              text))
        text)))

(defun find-tool-entry (state call-id)
  (find
   call-id
   (tui-state-entries state)
   :from-end t
   :key #'tui-entry-tool-call-id
   :test #'string=))

(defun tui-handle-agent-event
    (state event
     &key
       extension-host
       display-messages
       compaction-summary
       compaction-tokens-before
       (clock-function #'tui-monotonic-seconds))
  (let ((type (cadr-agent:agent-event-type event))
        (message (cadr-agent:agent-event-message event))
        (stream-event
          (cadr-agent:agent-event-stream-event event)))
    (case type
      (:agent-start
       (setf
        (tui-state-status-message state)
        "Working..."))
      (:auto-retry-start
       (setf
        (tui-state-status-message state)
        (format
         nil "Retrying (~D/~D) in ~Ds..."
         (or
          (cadr-agent:agent-event-attempt event)
          1)
         (or
          (cadr-agent:agent-event-max-attempts
           event)
          1)
         (ceiling
          (or
           (cadr-agent:agent-event-delay-ms
            event)
           0)
          1000))))
      (:agent-settled
       (setf
        (tui-state-status-message state)
        nil))
      (:message-start
       (typecase message
         (cadr-ai:user-message
          (append-tui-entry
           state
           (make-tui-entry
            :type :user
            :text
            (cadr-ai::content-text
             (cadr-ai:user-message-content message)))))
         (cadr-ai:assistant-message
          (let ((entry
                  (append-tui-entry
                   state
                   (make-tui-entry
                   :type :assistant
                    :streaming-p t
                    :stop-reason
                    (cadr-ai:assistant-message-stop-reason
                     message)
                    :error-message
                    (cadr-ai:assistant-message-error-message
                     message)
                    :has-tool-calls-p
                    (assistant-message-has-tool-calls-p
                     message)
                    :content-blocks
                    (assistant-display-blocks
                     message)))))
            (setf
             (tui-state-current-assistant state)
             entry)))))
      (:message-update
       (when
           (and
            (tui-state-current-assistant state)
            stream-event)
         (let* ((entry
                  (tui-state-current-assistant state))
                (event-type
                  (cadr-ai:stream-event-type
                   stream-event))
                (message-type
                  (case event-type
                    (:text-delta :assistant)
                    (:thinking-delta
                     :assistant-thinking)))
                (delta
                  (or
                   (cadr-ai:stream-event-delta
                    stream-event)
                   "")))
           (when message-type
             (when (eq message-type :assistant)
               (setf
                (tui-entry-text entry)
                (concatenate
                 'string
                 (tui-entry-text entry)
                 delta)))
             (let ((last
                     (car
                      (last
                       (tui-entry-content-blocks
                        entry)))))
               (if
                   (and last
                        (eq (car last)
                            message-type))
                   (setf
                    (cdr last)
                    (concatenate
                     'string (cdr last) delta))
                   (setf
                    (tui-entry-content-blocks entry)
                    (nconc
                     (tui-entry-content-blocks entry)
                     (list
                      (cons message-type
                            delta))))))))))
      (:message-end
       (when (typep message 'cadr-ai:assistant-message)
         (let ((entry
                 (tui-state-current-assistant state)))
           (when entry
             (let ((blocks
                     (assistant-display-blocks
                      message)))
               (when blocks
                 (setf
                  (tui-entry-content-blocks entry)
                  blocks
                  (tui-entry-text entry)
                  (response-text message)))
               (setf
                (tui-entry-stop-reason entry)
                (cadr-ai:assistant-message-stop-reason
                 message)
                (tui-entry-error-message entry)
                (cadr-ai:assistant-message-error-message
                 message)
                (tui-entry-has-tool-calls-p entry)
                (assistant-message-has-tool-calls-p
                 message))
             (setf
              (tui-entry-streaming-p entry)
              nil))))
         (accumulate-message-usage state message)
         (setf
          (tui-state-current-assistant state)
          nil)))
      (:tool-execution-start
       (let ((call
               (cadr-agent:agent-event-tool-call event)))
         (let* ((render-state
                  (make-hash-table))
                (entry
                  (make-tui-entry
                   :type :tool
                   :tool-call-id
                   (cadr-ai:tool-call-id call)
                   :tool-render-state render-state
                   :tool-block
                   (cadr-tui:make-tool-block
                    :name (cadr-ai:tool-call-name call)
                   :summary
                   (tool-arguments-summary call)
                    :started-at
                    (funcall clock-function)
                    :collapsed-p
                    (not
                     (tui-state-tools-expanded-p
                      state))
                    :status :running))))
           (when extension-host
             (multiple-value-bind
                   (rendered handled-p)
                 (cadr-agent::render-extension-tool-call
                  extension-host
                  (cadr-ai:tool-call-name call)
                  (cadr-ai:tool-call-arguments call)
                  (list
                   :state render-state
                   :tool-call-id
                   (cadr-ai:tool-call-id call)
                   :cwd
                   (namestring
                    (cadr-agent::extension-host-cwd
                     extension-host))
                   :execution-started-p t
                   :args-complete-p t
                   :partial-p nil
                   :expanded-p
                   (tui-state-tools-expanded-p state)))
               (setf
                (tui-entry-custom-call-render
                 entry)
                rendered
                (tui-entry-custom-call-rendered-p
                 entry)
                (not (null handled-p)))))
           (append-tui-entry state entry))))
      (:tool-execution-end
       (let* ((call
                (cadr-agent:agent-event-tool-call event))
              (result
                (cadr-agent:agent-event-tool-result event))
              (entry
                (and call
                     (find-tool-entry
                      state
                      (cadr-ai:tool-call-id call)))))
         (when entry
           (setf
            (cadr-tui:tool-block-output
             (tui-entry-tool-block entry))
            (rendered-tool-result-text call result)
            (cadr-tui:tool-block-status
             (tui-entry-tool-block entry))
            (if
                (cadr-ai:tool-result-message-is-error
                 result)
                :error
                :complete)
            (cadr-tui:tool-block-ended-at
             (tui-entry-tool-block entry))
            (funcall clock-function)
            (cadr-tui:tool-block-collapsed-p
             (tui-entry-tool-block entry))
            (not
             (tui-state-tools-expanded-p state)))
           (when extension-host
             (multiple-value-bind
                   (rendered handled-p)
                 (cadr-agent::render-extension-tool-result
                  extension-host
                  (cadr-ai:tool-call-name call)
                  result
                  (list
                   :expanded-p
                   (tui-state-tools-expanded-p state)
                   :partial-p nil)
                  (list
                   :state
                   (tui-entry-tool-render-state entry)
                   :tool-call-id
                   (cadr-ai:tool-call-id call)
                   :cwd
                   (namestring
                    (cadr-agent::extension-host-cwd
                     extension-host))
                   :execution-started-p t
                   :args-complete-p t
                   :partial-p nil
                   :expanded-p
                   (tui-state-tools-expanded-p state)
                   :is-error-p
                   (cadr-ai:tool-result-message-is-error
                    result)))
               (setf
                (tui-entry-custom-result-render
                 entry)
                rendered
                (tui-entry-custom-result-rendered-p
                 entry)
                (not (null handled-p))))))))
      (:compaction-start
       (setf
        (tui-state-status-message state)
        "Compacting context...")
       (add-tui-notice state
                       "Compacting context…"))
      (:compaction-end
       (setf
        (tui-state-status-message state)
        nil
        (tui-state-context-percent state)
        nil)
       (when display-messages
         (reset-tui-messages
          state display-messages
          :preserve-usage-p t
          :context-unknown-p t))
       (if compaction-summary
           (append-tui-entry
            state
            (make-tui-entry
             :type :compaction-summary
             :text
             (format
              nil
              "~@[~:D tokens compacted~]~@[~%~A~]"
              compaction-tokens-before
              compaction-summary)))
           (add-tui-notice state
                           "Context compacted")))
      (:compaction-error
       (setf
        (tui-state-status-message state)
        nil)
       (add-tui-notice
        state
        (format nil
                "Context compaction failed: ~A"
                (cadr-agent:agent-event-error-message
                 event))))))
  state)

(defun extension-render-value-lines
    (value width)
  (cond
    ((null value) nil)
    ((stringp value)
     (cadr-tui:wrap-text value width))
    ((and (listp value)
          (every #'stringp value))
     (loop for line in value
           append
           (cadr-tui:wrap-text line width)))
    ((cadr-tui::select-list-p value)
     (cadr-tui:render-select-list value width))
    (t
     (cadr-tui:wrap-text
      (princ-to-string value)
      width))))

(defun transform-tui-markdown
    (entry source message-type width extension-host
     &optional (cache-key message-type))
  (unless extension-host
    (return-from transform-tui-markdown source))
  (let* ((snapshot
           (cadr-agent::extension-host-current-snapshot
            extension-host))
         (context
           (list
            :message-type message-type
            :streaming-p
            (tui-entry-streaming-p entry)
            :available-width width)))
    (let ((cached
            (find-if
             (lambda (item)
               (and
                (equal cache-key (first item))
                (string= source (second item))
                (eq
                 (tui-entry-streaming-p entry)
                 (third item))
                (= width (fourth item))
                (eq snapshot (fifth item))))
             (tui-entry-markdown-cache entry))))
      (if cached
          (sixth cached)
          (let ((transformed
                  (cadr-agent::transform-extension-markdown
                   extension-host source context)))
            (setf
             (tui-entry-markdown-cache entry)
             (cons
              (list
               cache-key source
               (tui-entry-streaming-p entry)
               width snapshot transformed)
              (remove
               cache-key
               (tui-entry-markdown-cache entry)
               :key #'first
               :test #'equal)))
            transformed)))))

(defun assistant-stop-error-lines
    (entry width)
  (let ((message
          (case (tui-entry-stop-reason entry)
            (:length
             "Error: Model stopped because it reached the maximum output token limit. The response may be incomplete.")
            (:aborted
             (let ((error-message
                     (tui-entry-error-message
                      entry)))
               (if
                   (and error-message
                        (not
                         (string=
                          error-message
                          "Request was aborted")))
                   error-message
                   "Operation aborted")))
            (:error
             (unless
                 (tui-entry-has-tool-calls-p entry)
               (format
                nil "Error: ~A"
                (or
                 (tui-entry-error-message entry)
                 "Unknown error")))))))
    (when message
      (cons
       ""
       (loop for line in
             (cadr-tui:render-markdown
              message width
              :padding-x 1
              :ansi-theme-p t)
             collect
             (cadr-tui:theme-foreground
              :error line
              :enabled-p t))))))

(defun tui-syntax-highlight (language source)
  (simple-syntax-highlight
   source language
   (list
    (cons
     "keyword"
     (lambda (text)
       (cadr-tui:theme-foreground
        :syntax-keyword text
        :enabled-p t)))
    (cons
     "number"
     (lambda (text)
       (cadr-tui:theme-foreground
        :syntax-number text
        :enabled-p t))))))

(defun render-assistant-blocks
    (entry width extension-host)
  (let ((available-width
          (max 1 (- width 2))))
    (let ((blocks
            (or
             (tui-entry-content-blocks entry)
             (and
              (plusp
               (length
                (string-trim
                 '(#\Space #\Tab #\Newline
                   #\Return)
                 (tui-entry-text entry))))
              (list
               (cons
                :assistant
                (string-trim
                 '(#\Space #\Tab #\Newline
                   #\Return)
                 (tui-entry-text entry)))))))
          (rendered nil))
      (loop for (message-type . source)
              in blocks
            for block-index from 0
            for transformed =
              (transform-tui-markdown
               entry source message-type
               available-width extension-host
               (list message-type block-index))
            for lines =
              (cadr-tui:render-markdown
               transformed width
               :padding-x 1
               :ansi-theme-p t
               :default-style-function
               (and
                (eq message-type
                    :assistant-thinking)
                (lambda (text)
                  (cadr-tui:theme-foreground
                   :thinking-text
                   (cadr-tui:theme-italic text)
                   :enabled-p t)))
               :syntax-highlight-function
               #'tui-syntax-highlight)
            do
            (when rendered
              (setf rendered
                    (nconc rendered
                           (list ""))))
            (setf rendered
                  (nconc rendered lines)))
      (let ((errors
              (assistant-stop-error-lines
               entry width)))
        (when (or rendered errors)
          (setf rendered
                (cons "" rendered)))
        (nconc rendered errors)))))

(defun theme-message-background-lines
    (lines background-token)
  (loop for line in lines
        collect
        (cadr-tui:theme-background
         background-token line
         :enabled-p t)))

(defun render-tui-entry
    (entry width &key extension-host now)
  (case (tui-entry-type entry)
    (:user
     (let ((lines
             (theme-message-background-lines
              (cadr-tui:render-markdown
               (transform-tui-markdown
                entry
                (tui-entry-text entry)
                :user
                (max 1 (- width 2))
                extension-host)
               width
               :padding-x 1
               :padding-y 1
               :ansi-theme-p t
               :default-style-function
               (lambda (text)
                 (cadr-tui:theme-foreground
                  :user-message-text text
                  :enabled-p t))
               :preserve-list-markers-p t
               :syntax-highlight-function
               #'tui-syntax-highlight)
              :user-message-bg)))
       (when lines
         (setf
          (first lines)
          (concatenate
           'string +osc-133-start+ (first lines))
          (car (last lines))
          (concatenate
           'string +osc-133-end+ +osc-133-final+
           (car (last lines)))))
       lines))
    (:assistant
     (let ((lines
             (render-assistant-blocks
              entry width extension-host)))
       (when
           (and
            lines
            (not
             (tui-entry-has-tool-calls-p entry)))
         (setf
          (first lines)
          (concatenate
           'string +osc-133-start+ (first lines))
          (car (last lines))
          (concatenate
           'string +osc-133-end+ +osc-133-final+
           (car (last lines)))))
       lines))
    (:tool
     (let ((custom-call
             (and
              (tui-entry-custom-call-rendered-p entry)
              (extension-render-value-lines
               (tui-entry-custom-call-render entry)
               width)))
           (custom-result
             (and
              (tui-entry-custom-result-rendered-p
               entry)
              (extension-render-value-lines
               (tui-entry-custom-result-render entry)
               width))))
       (if
           (or
            (tui-entry-custom-call-rendered-p entry)
            (tui-entry-custom-result-rendered-p entry))
           (nconc
            (or
             custom-call
             (cadr-tui:wrap-text
              (format nil "~A ~A"
                      (cadr-tui:tool-block-name
                       (tui-entry-tool-block entry))
                      (cadr-tui:tool-block-summary
                       (tui-entry-tool-block entry)))
              width))
            (if
                (tui-entry-custom-result-rendered-p
                 entry)
                custom-result
                (let ((output
                        (cadr-tui:tool-block-output
                         (tui-entry-tool-block entry))))
                  (and
                   (plusp (length output))
                   (cadr-tui:wrap-text
                    output width)))))
           (cadr-tui:render-tool-block
            (tui-entry-tool-block entry)
            width
            :ansi-theme-p t
            :now now))))
    (:compaction-summary
     (cadr-tui:wrap-text
      (format nil "Compaction summary: ~A"
              (tui-entry-text entry))
      width))
    (:notice
     (cadr-tui:wrap-text
      (format nil "session> ~A"
              (tui-entry-text entry))
      width))
    (:auth-url
     (render-auth-url-lines
      (tui-entry-text entry)
      width))
    (otherwise nil)))

(defun trailing-lines (lines count)
  (if (<= (length lines) count)
      lines
      (nthcdr (- (length lines) count)
              lines)))

(defun blank-render-line-p (line)
  (zerop
   (length
    (string-trim
     '(#\Space #\Tab #\Newline #\Return)
     (cadr-tui:strip-terminal-sequences
      line)))))

(defun selected-overlay-line-p (line)
  (let ((plain
          (cadr-tui:strip-terminal-sequences
           line)))
    (or
     (search
      (cadr-tui:theme-background-ansi
       :selected-bg :enabled-p t)
      line)
     (uiop:string-prefix-p "→ " plain)
     (uiop:string-prefix-p "› " plain)
     (uiop:string-prefix-p "> " plain))))

(defun fit-overlay-lines (lines height)
  (let ((available (max 0 height)))
    (when (zerop available)
      (return-from fit-overlay-lines nil))
    (when (<= (length lines) available)
      (return-from fit-overlay-lines lines))
    (let* ((compact
             (remove-if #'blank-render-line-p
                        lines))
           (selected
             (position-if
              #'selected-overlay-line-p compact)))
      (when (<= (length compact) available)
        (return-from fit-overlay-lines compact))
      (unless selected
        (let* ((head-count
                 (min 4
                      (max 1
                           (ceiling available 2))))
               (tail-count
                 (- available head-count)))
          (return-from fit-overlay-lines
            (nconc
             (subseq compact 0 head-count)
             (when (plusp tail-count)
               (copy-list
                (nthcdr
                 (- (length compact)
                    tail-count)
                 compact)))))))
      (let* ((last-index
               (1- (length compact)))
             (head-count
               (min 3
                    (max 0 (- available 2))))
             (reserved
               (remove-duplicates
                (append
                 (loop for index below head-count
                       collect index)
                 (when (> available head-count)
                   (list last-index)))
                :test #'=))
             (body-budget
               (- available (length reserved)))
             (body-start
               (max
                head-count
                (min
                 (- selected
                    (floor body-budget 2))
                 (max
                  head-count
                  (- last-index body-budget)))))
             (body
               (loop for index from body-start
                     below
                     (min last-index
                          (+ body-start
                             body-budget))
                     collect index))
             (indices
               (sort
                (remove-duplicates
                 (append reserved
                         body
                         (list selected))
                 :test #'=)
                #'<)))
        (when (> (length indices) available)
          (setf
           indices
           (subseq indices
                   (- (length indices)
                      available))))
        (mapcar
         (lambda (index)
           (nth index compact))
         indices)))))

(defun render-tui-state
    (state editor width rows
     &key overlay busy-p extension-host
       full-document-p
       (now (tui-monotonic-seconds))
       (spinner-frame
         (aref +tui-spinner-frames+ 0)))
  (multiple-value-bind
        (editor-lines editor-row editor-column)
      (cadr-tui:render-editor
       editor width
       :terminal-rows rows
       :focused-p (null overlay))
    (let* ((status-indicator
             (or
              (render-tui-status-indicator
               (tui-state-status-message state)
               width
               :reserve-idle-p
               (not full-document-p)
               :spinner-frame spinner-frame)
              (and
               busy-p
               (render-tui-status-indicator
                "Working..." width
                :reserve-idle-p
                (not full-document-p)
                :spinner-frame spinner-frame))))
           (footer-lines
             (cadr-tui:render-footer
              width
              :cwd (tui-state-cwd state)
              :branch
              (tui-state-branch state)
              :session-name
              (tui-state-session-name state)
              :model
              (tui-state-model state)
              :provider
              (tui-state-provider state)
              :thinking
              (tui-state-thinking state)
              :input
              (tui-state-input-tokens state)
              :output
              (tui-state-output-tokens state)
              :cache-read
              (tui-state-cache-read-tokens state)
              :cache-write
              (tui-state-cache-write-tokens state)
              :latest-cache-hit-rate
              (tui-state-latest-cache-hit-rate
               state)
              :cost
              (and
               (tui-state-cost-known-p state)
               (plusp
                (tui-state-cost state))
               (tui-state-cost state))
              :subscription-p
              (tui-state-subscription-p state)
              :context-percent
              (tui-state-context-percent state)
              :context-window
              (tui-state-context-window state)
              :auto-compact-p
              (tui-state-auto-compact-p state)
              :multiple-providers-p
              (tui-state-multiple-providers-p
               state)
              :statuses
              (tui-state-statuses state)
              :ansi-theme-p t))
           (widget-above-lines
             (render-tui-widgets
              (tui-state-widgets-above state)
              width))
           (widget-below-lines
             (render-tui-widgets
              (tui-state-widgets-below state)
              width))
           (non-content-lines
             (+ (length status-indicator)
                (length widget-above-lines)
                (length editor-lines)
                (length widget-below-lines)
                (length footer-lines)))
           (content-height
             (max 0
                  (- rows
                     non-content-lines)))
           (entry-content
             (if overlay
                 (cond
                   ((session-selector-state-p
                     overlay)
                    (render-session-selector
                     overlay width))
                   ((tree-selector-state-p
                     overlay)
                    (render-tree-selector
                     overlay width))
                   ((user-message-selector-state-p
                     overlay)
                    (render-user-message-selector
                     overlay width))
                   ((model-selector-state-p
                     overlay)
                    (render-model-selector
                     overlay width))
                   ((scoped-models-selector-state-p
                     overlay)
                    (render-scoped-models-selector
                     overlay width))
                   ((trust-selector-state-p
                     overlay)
                    (render-trust-selector
                     overlay width))
                   ((settings-selector-state-p
                     overlay)
                    (render-settings-selector
                     overlay width))
                   ((extension-custom-ui-state-p
                     overlay)
                    (render-extension-custom-ui
                     overlay width))
                   (t
                    (cadr-tui:render-select-list
                     overlay width)))
                 (loop for entry in
                       (tui-state-entries state)
                       append
                       (render-tui-entry
                       entry width
                       :extension-host
                       extension-host
                       :now now))))
           (startup-lines
             (and
              (null overlay)
              (if
                  (tui-state-tools-expanded-p state)
                  (or
                   (tui-state-startup-expanded-lines
                    state)
                   (tui-state-startup-compact-lines
                    state))
                  (tui-state-startup-compact-lines
                   state))))
           (startup-lines
             (and startup-lines
                  (render-tui-startup-lines
                   startup-lines width)))
           (all-content
             (if startup-lines
                 (nconc
                  (list "")
                  (copy-list startup-lines)
                  (list "")
                  entry-content)
                 entry-content))
           (visible
             (cond
               ((and full-document-p
                     (null overlay))
                all-content)
               ((and
                 overlay
                 (plusp content-height)
                 (> (length all-content)
                    content-height))
                (fit-overlay-lines
                 all-content content-height))
               (t
                (trailing-lines
                 all-content content-height))))
           (rendered-content-height
             (max content-height
                  (length visible)))
           (padding
             (make-list
              (max 0
                   (- rendered-content-height
                      (length visible)))
              :initial-element "")))
      (values
       (nconc padding visible
              status-indicator
              widget-above-lines
              editor-lines
              widget-below-lines
              footer-lines)
       (+ rendered-content-height
          (length status-indicator)
          (length widget-above-lines)
          editor-row)
       editor-column))))

(defun set-tui-tools-expanded
    (state expanded-p)
  (setf
   (tui-state-tools-expanded-p state)
   (not (null expanded-p)))
  (dolist (entry (tui-state-entries state))
    (when (eq (tui-entry-type entry) :tool)
      (setf
       (cadr-tui:tool-block-collapsed-p
        (tui-entry-tool-block entry))
       (not expanded-p))))
  (tui-state-tools-expanded-p state))

(defun toggle-last-tool-block (state)
  (set-tui-tools-expanded
   state
   (not (tui-state-tools-expanded-p state))))

(defun should-use-tui-p
    (no-tui-p
     &key
       (input *standard-input*)
       (output *standard-output*)
       (terminal-p-function
         #'cadr-tui:terminal-stream-p))
  (and
   (not no-tui-p)
   (funcall terminal-p-function input :input)
   (funcall terminal-p-function output :output)))

#+sbcl
(defclass notification-output-stream
    (sb-gray:fundamental-character-output-stream)
  ((callback
    :initarg :callback
    :reader notification-stream-callback)
   (buffer
    :initform (make-string-output-stream)
    :accessor notification-stream-buffer)
   (lock
    :initform
    (sb-thread:make-mutex
     :name "cadr-tui-notifications")
    :reader notification-stream-lock)))

#+sbcl
(defun notification-stream-flush (stream)
  (let ((text
          (get-output-stream-string
           (notification-stream-buffer stream))))
    (when (plusp (length text))
      (funcall
       (notification-stream-callback stream)
       text))))

#+sbcl
(defmethod sb-gray:stream-write-char
    ((stream notification-output-stream) character)
  (sb-thread:with-mutex
      ((notification-stream-lock stream))
    (if (char= character #\Newline)
        (notification-stream-flush stream)
        (write-char
         character
         (notification-stream-buffer stream))))
  character)

#+sbcl
(defmethod sb-gray:stream-finish-output
    ((stream notification-output-stream))
  (sb-thread:with-mutex
      ((notification-stream-lock stream))
    (notification-stream-flush stream))
  nil)

(defun make-notification-output-stream (callback)
  #+sbcl
  (make-instance
   'notification-output-stream
   :callback callback)
  #-sbcl
  (declare (ignore callback))
  #-sbcl
  *standard-output*)

(defun make-import-confirmation-list
    (line path)
  (cadr-tui:make-select-list
   :items
   (list
    (cadr-tui:make-select-item
     :label "Yes"
     :value
     (list :confirmed-p t
           :line line
           :path path))
    (cadr-tui:make-select-item
     :label "No"
     :value
     (list :confirmed-p nil
           :line line
           :path path)))))

(defparameter +tui-autocomplete-command-specifications+
  '(("model" "Select the active model" nil)
    ("scoped-models"
     "Configure models used for cycling" nil)
    ("tree" "Navigate the session tree" nil)
    ("trust"
     "Save project trust for future sessions" nil)
    ("settings" "Configure cadr settings" nil)
    ("resume" "Resume a saved session" nil)
    ("sessions" "Select a saved session" nil)
    ("switch" "Switch to a session" "<session-id>")
    ("branch" "Set the session branch point" "<entry-id>")
    ("name" "Set the session display name" "<name>")
    ("session" "Show session info and stats" nil)
    ("share" "Share session as a secret GitHub gist" nil)
    ("changelog" "Show changelog entries" nil)
    ("hotkeys" "Show keyboard shortcuts" nil)
    ("fork" "Fork from a previous user message" nil)
    ("new" "Start a new session" nil)
    ("compact" "Compact the current context"
     "[instructions]")
    ("copy" "Copy the last agent message" nil)
    ("clone" "Duplicate the current session" nil)
    ("import" "Import a JSONL session" "<path>")
    ("export" "Export the current session" "[path]")
    ("login" "Authenticate a provider" "[provider]")
    ("logout" "Remove provider authentication" "[provider]")
    ("reload" "Reload settings and resources" nil)
    ("install" "Install an extension" "<source>")
    ("quit" "Quit cadr" nil)))

(defun find-tui-fd-program ()
  (loop for directory
        in (uiop:split-string
            (or (uiop:getenv "PATH") "")
            :separator '(#\:))
        when (plusp (length directory))
          do
          (dolist (name '("fd" "fdfind"))
            (let ((candidate
                    (merge-pathnames
                     name
                     (uiop:ensure-directory-pathname
                      directory))))
              (when (probe-file candidate)
                (return-from find-tui-fd-program
                  candidate))))))

(defun make-tui-autocomplete-provider
    (&key (base-path (uiop:getcwd)))
  (cadr-tui:make-autocomplete-provider
   :commands
   (loop for (name description argument-hint)
         in +tui-autocomplete-command-specifications+
         collect
         (cadr-tui:make-autocomplete-command
          :name name
          :description description
          :argument-hint argument-hint))
   :base-path base-path
   :fd-path
   (find-tui-fd-program)))

(defparameter +reserved-extension-shortcut-keys+
  '("escape" "ctrl+c" "ctrl+d" "ctrl+z"))

(defun effective-extension-shortcuts (host)
  (remove-if
   (lambda (definition)
     (member
      (cadr-agent::extension-shortcut-definition-key
       definition)
      +reserved-extension-shortcut-keys+
      :test #'string-equal))
   (cadr-agent::extension-host-shortcuts host)))

(defun find-extension-shortcut-for-input
    (host input)
  (find-if
   (lambda (definition)
     (cadr-tui:matches-key
      input
      (cadr-agent::extension-shortcut-definition-key
       definition)))
   (effective-extension-shortcuts host)))

(defun route-tui-submission
    (line busy-p busy-input-function
     start-function)
  (if busy-p
      (when busy-input-function
        (funcall busy-input-function line)
        :queued)
      (progn
        (funcall start-function line)
        :started)))

(defun call-with-sigcont-handler
    (handler thunk)
  #+sbcl
  (sb-sys:with-interrupt-bindings
    (sb-sys:enable-interrupt
     sb-unix:sigcont
     (lambda (signal code context)
       (declare (ignore signal code context))
       (funcall handler)))
    (funcall thunk))
  #-sbcl
  (declare (ignore handler))
  #-sbcl
  (funcall thunk))

(defun suspend-current-process ()
  #+sbcl
  (sb-posix:kill
   (sb-posix:getpid)
   sb-unix:sigtstp)
  #-sbcl
  (error "Suspend is unsupported on this Lisp runtime"))

(defun open-tui-url (url)
  (uiop:launch-program
   #+darwin
   (list "open" url)
   #+win32
   (list "cmd" "/c" "start" "" url)
   #-(or darwin win32)
   (list "xdg-open" url)
   :output :interactive
   :error-output :interactive))

(defun suspend-tui
    (platform
     stop-function
     start-function
     render-function
     suspend-function
     signal-wrapper
     &key notice-function)
  (when (eq platform :windows)
    (when notice-function
      (funcall
       notice-function
       "Suspend to background is not supported on Windows"))
    (return-from suspend-tui nil))
  (funcall stop-function)
  (funcall
   signal-wrapper
   (lambda ()
     (funcall start-function)
     (funcall render-function))
   suspend-function)
  t)

(defun make-interactive-renderer
    (terminal alt-p
     &key show-hardware-cursor-p)
  (cadr-tui:make-terminal-renderer
   terminal
   :alt-p alt-p
   :show-hardware-cursor-p
   show-hardware-cursor-p
   :open-url-function
   #'open-tui-url))

(defparameter +tui-theme-json-color-map+
  '(("accent" . :accent)
    ("border" . :border)
    ("borderAccent" . :border-accent)
    ("borderMuted" . :border-muted)
    ("success" . :success)
    ("error" . :error)
    ("warning" . :warning)
    ("muted" . :muted)
    ("dim" . :dim)
    ("text" . :text)
    ("thinkingText" . :thinking-text)
    ("selectedBg" . :selected-bg)
    ("userMessageBg" . :user-message-bg)
    ("userMessageText" . :user-message-text)
    ("customMessageBg" . :custom-message-bg)
    ("customMessageText" . :custom-message-text)
    ("customMessageLabel" . :custom-message-label)
    ("toolPendingBg" . :tool-pending-bg)
    ("toolSuccessBg" . :tool-success-bg)
    ("toolErrorBg" . :tool-error-bg)
    ("toolTitle" . :tool-title)
    ("toolOutput" . :tool-output)
    ("mdHeading" . :md-heading)
    ("mdLink" . :md-link)
    ("mdLinkUrl" . :md-link-url)
    ("mdCode" . :md-code)
    ("mdCodeBlock" . :md-code-block)
    ("mdCodeBlockBorder"
     . :md-code-block-border)
    ("mdQuote" . :md-quote)
    ("mdQuoteBorder" . :md-quote-border)
    ("mdHr" . :md-hr)
    ("mdListBullet" . :md-list-bullet)
    ("toolDiffAdded" . :tool-diff-added)
    ("toolDiffRemoved" . :tool-diff-removed)
    ("toolDiffContext" . :tool-diff-context)
    ("syntaxComment" . :syntax-comment)
    ("syntaxKeyword" . :syntax-keyword)
    ("syntaxFunction" . :syntax-function)
    ("syntaxVariable" . :syntax-variable)
    ("syntaxString" . :syntax-string)
    ("syntaxNumber" . :syntax-number)
    ("syntaxType" . :syntax-type)
    ("syntaxOperator" . :syntax-operator)
    ("syntaxPunctuation" . :syntax-punctuation)
    ("thinkingOff" . :thinking-off)
    ("thinkingMinimal" . :thinking-minimal)
    ("thinkingLow" . :thinking-low)
    ("thinkingMedium" . :thinking-medium)
    ("thinkingHigh" . :thinking-high)
    ("thinkingXhigh" . :thinking-xhigh)
    ("thinkingMax" . :thinking-max)
    ("bashMode" . :bash-mode)))

(defparameter +tui-theme-json-export-map+
  '(("pageBg" . :page-bg)
    ("cardBg" . :card-bg)
    ("infoBg" . :info-bg)))

(defun valid-tui-theme-primitive-p (value)
  (or
   (stringp value)
   (and
    (integerp value)
    (<= 0 value 255))))

(defun validate-tui-theme-object
    (object variables variables-present-p
     colors export export-present-p)
  (maphash
   (lambda (name value)
     (declare (ignore value))
     (unless
         (member name
                 '("$schema" "name" "vars"
                   "colors" "export")
                 :test #'string=)
       (error "Unknown theme property: ~A"
              name)))
   object)
  (multiple-value-bind (schema present-p)
      (gethash "$schema" object)
    (when
        (and present-p
             (not (stringp schema)))
      (error "Theme $schema must be a string")))
  (let ((name
          (cadr-ai::json-get object "name")))
    (unless (and
             (stringp name)
             (plusp (length name))
             (not (search "/" name)))
      (error "Theme requires a valid name without '/'")))
  (unless (hash-table-p colors)
    (error "Theme requires a colors object"))
  (unless
      (or
       (not variables-present-p)
       (hash-table-p variables))
    (error "Theme vars must be an object"))
  (maphash
   (lambda (name value)
     (declare (ignore name))
     (unless (valid-tui-theme-primitive-p value)
       (error "Invalid theme variable value: ~S"
              value)))
   variables)
  (let ((known
          (mapcar #'car
                  +tui-theme-json-color-map+)))
    (maphash
     (lambda (name value)
       (unless
           (member name known :test #'string=)
         (error "Unknown theme color token: ~A"
                name))
       (unless (valid-tui-theme-primitive-p value)
         (error "Invalid theme color value: ~S"
                value)))
     colors)
    (dolist (name known)
      (unless
          (or
           (string= name "thinkingMax")
           (nth-value 1
                      (gethash name colors)))
        (error "Missing required theme color token: ~A"
               name))))
  (when export-present-p
    (unless (hash-table-p export)
      (error "Theme export must be an object"))
    (let ((known
            (mapcar #'car
                    +tui-theme-json-export-map+)))
      (maphash
       (lambda (name value)
         (unless
             (member name known :test #'string=)
           (error "Unknown theme export token: ~A"
                  name))
         (unless (valid-tui-theme-primitive-p value)
           (error "Invalid theme export value: ~S"
                  value)))
       export)))
  t)

(defun resolve-tui-theme-value
    (value variables &optional seen)
  (cond
    ((integerp value)
     (unless (<= 0 value 255)
       (error "Theme color index is outside 0..255: ~S"
              value))
     value)
    ((not (stringp value))
     (error "Theme color must be a string or integer: ~S"
            value))
    ((zerop (length value))
     "")
    ((char= (char value 0) #\#)
     (cadr-tui:parse-theme-hex-color value)
     (string-downcase value))
    ((member value seen :test #'string=)
     (error "Cyclic theme variable reference: ~A"
            value))
    (t
     (multiple-value-bind (resolved present-p)
         (gethash value variables)
       (unless present-p
         (error "Unknown theme variable: ~A"
                value))
       (resolve-tui-theme-value
        resolved variables (cons value seen))))))

(defun theme-object-overrides (object)
  (when (hash-table-p object)
    (multiple-value-bind (raw-variables variables-present-p)
        (gethash "vars" object)
      (multiple-value-bind (export export-present-p)
          (gethash "export" object)
        (let ((variables
                (if variables-present-p
                    raw-variables
                    (make-hash-table :test #'equal)))
              (colors
                (cadr-ai::json-get object "colors"))
              (overrides nil))
          (validate-tui-theme-object
           object variables variables-present-p
           colors export export-present-p)
      (labels
          ((collect-values (container mapping)
             (when (hash-table-p container)
               (dolist (entry mapping)
                 (multiple-value-bind (raw present-p)
                     (gethash (car entry) container)
                   (when present-p
                     (push
                      (cons
                       (cdr entry)
                       (resolve-tui-theme-value
                        raw variables))
                      overrides)))))))
        (collect-values
         colors
         +tui-theme-json-color-map+)
        (unless
            (nth-value 1
                       (gethash "thinkingMax"
                                colors))
          (push
           (cons
            :thinking-max
            (resolve-tui-theme-value
             (gethash "thinkingXhigh" colors)
             variables))
           overrides))
        (collect-values
         export
         +tui-theme-json-export-map+))
            (nreverse overrides))))))

(defun apply-tui-theme-summary
    (summary
     &key background
       (keep-current-on-error-p nil)
       (capabilities
         (cadr-tui:get-terminal-capabilities)))
  (let* ((name
           (cond
             ((stringp summary) summary)
             ((listp summary)
              (getf summary :name))
             (t nil)))
         (object
           (and (listp summary)
                (getf summary :object)))
         (background
           (or
            background
            (theme-detection-theme
             (detect-background-from-environment))))
         (base
           (cond
             ((and name
                   (string-equal name "light"))
              :light)
             ((and name
                   (string-equal name "dark"))
              :dark)
             ((eq background :light)
              :light)
             (t :dark))))
    (handler-case
        (cadr-tui:set-current-theme
         base
         :overrides
         (theme-object-overrides object)
         :capabilities capabilities)
      (condition ()
        (unless keep-current-on-error-p
          (cadr-tui:set-current-theme
           :dark
           :capabilities capabilities))
        nil))))

(defstruct (tui-theme-watcher
            (:constructor %make-tui-theme-watcher))
  path
  signature
  pending-signature
  pending-since
  summary
  background)

(defconstant +tui-theme-watch-poll-seconds+
  0.005d0)

(defun load-tui-theme-file (path)
  (handler-case
      (let ((object
              (cadr-ai::parse-json
               (uiop:read-file-string
                path :external-format :utf-8))))
        (when (hash-table-p object)
          (list
           :name
           (or
            (cadr-ai::json-get object "name")
            (pathname-name path))
           :path path
           :object object)))
    (condition () nil)))

(defun make-tui-theme-watcher
    (summary &key background)
  (let ((path
          (and (listp summary)
               (getf summary :path))))
    (when path
      (%make-tui-theme-watcher
       :path path
       :signature
       (binary-file-signature path)
       :summary summary
       :background background))))

(defun poll-tui-theme-watcher
    (watcher
     &key
       (clock-function #'tui-monotonic-seconds)
       (capabilities
         (cadr-tui:get-terminal-capabilities)))
  (let* ((path
           (tui-theme-watcher-path watcher))
         (signature
           (binary-file-signature path)))
    (when
        (equal
         signature
         (tui-theme-watcher-signature watcher))
      (setf
       (tui-theme-watcher-pending-signature watcher)
       nil
       (tui-theme-watcher-pending-since watcher)
       nil)
      (return-from poll-tui-theme-watcher nil))
    (let ((now
            (funcall clock-function)))
      (unless
          (equal
           signature
           (tui-theme-watcher-pending-signature
            watcher))
        (setf
         (tui-theme-watcher-pending-signature watcher)
         signature
         (tui-theme-watcher-pending-since watcher)
         now)
        (return-from poll-tui-theme-watcher nil))
      (when
          (<
           (- now
              (tui-theme-watcher-pending-since
               watcher))
           0.1d0)
        (return-from poll-tui-theme-watcher nil)))
    (setf
     (tui-theme-watcher-signature watcher)
     signature
     (tui-theme-watcher-pending-signature watcher)
     nil
     (tui-theme-watcher-pending-since watcher)
     nil)
    (let ((summary
            (and signature
                 (load-tui-theme-file path))))
      (when
          (and
           summary
           (apply-tui-theme-summary
            summary
            :background
            (tui-theme-watcher-background watcher)
            :keep-current-on-error-p t
            :capabilities capabilities))
        (setf
         (tui-theme-watcher-summary watcher)
         summary)
        t))))

(defun run-tui
    (prompt-function
     &key
       command-function
       template-function
       bash-function
       set-event-consumer
       set-notice-consumer
       set-auth-url-consumer
       set-model-consumer
       set-extension-ui-function
       footer-state-function
       footer-cwd
       (available-provider-count 0)
       subscription-p
       (autocomplete-max-visible 5)
       show-terminal-progress-p
       show-terminal-progress-function
       theme-function
       theme-mode-function
       detected-theme-function
       all-themes-function
       get-theme-function
       set-theme-function
       session-state-function
       busy-input-function
       model-items-function
       model-selector-function
       scoped-models-selector-function
       trust-selector-function
       settings-selector-function
       extension-host
       fork-items-function
       session-items-function
       all-session-items-function
       tree-state-function
       on-model-selected
       resolve-model-reference-function
       on-trust-selected
       on-import-confirmed
       on-fork-selected
       on-new-session
       on-session-selected
       on-tree-selected
       on-tree-label
       tree-copy-function
       current-session-path
       session-selector-keybindings
       session-selector-keybindings-function
       tree-selector-keybindings
       tree-selector-keybindings-function
       (session-selector-show-rename-hint-p t)
       abort-function
       reset-abort-function
       model
       provider
       thinking
       cwd
       branch
       session-name
       startup-compact-lines
       startup-expanded-lines
       (context-window 0)
       session
       messages
       initial-notices
       alt-p
       show-hardware-cursor-p
       (clock-function #'tui-monotonic-seconds)
       (sleep-function #'sleep)
       (terminal
         (cadr-tui:make-process-terminal)))
  (let* ((theme-summary
           (and theme-function
                (funcall theme-function)))
         (active-theme
           (apply-tui-theme-summary
            theme-summary))
         (theme-watcher
           (make-tui-theme-watcher
            theme-summary))
         (next-theme-poll-at
           (+ (funcall clock-function)
              +tui-theme-watch-poll-seconds+))
         (footer-provider
           (and footer-cwd
                (make-footer-data-provider
                 footer-cwd)))
         (footer-unsubscribe nil)
         (state
           (make-tui-state
            :model model
            :provider provider
            :thinking thinking
            :cwd cwd
            :branch
            (or
             (and
              footer-provider
              (footer-data-provider-git-branch
               footer-provider))
             branch)
            :session-name session-name
            :multiple-providers-p
            (> available-provider-count 1)
            :subscription-p subscription-p
            :statuses
            (and footer-provider
                 (footer-data-provider-statuses
                  footer-provider))
            :startup-compact-lines
            startup-compact-lines
            :startup-expanded-lines
            startup-expanded-lines
            :context-window context-window
            :session session
            :messages messages))
         (editor
           (let ((editor
                   (cadr-tui:make-multiline-editor
                    :autocomplete-max-visible
                    autocomplete-max-visible)))
             (cadr-tui:editor-set-autocomplete-provider
              editor
              (make-tui-autocomplete-provider))
             (cadr-tui:editor-set-autocomplete-clock
              editor clock-function)
             (cadr-tui:editor-set-border-mode
              editor :thinking
              (or thinking :off))
             editor))
         (decoder
           (cadr-tui:make-input-decoder))
         (renderer
           (make-interactive-renderer
            terminal alt-p
            :show-hardware-cursor-p
            show-hardware-cursor-p))
         (lock
           (sb-thread:make-mutex
            :name "cadr-tui-state"))
         (render-coordinator
           (make-tui-render-coordinator
            :clock-function clock-function))
         (status-animation
           (make-tui-status-animation))
         (overlay nil)
         (overlay-kind nil)
         (busy-p nil)
         (done-p nil)
         (last-clear-at nil)
         (worker nil)
         (session-loader-worker nil)
         (custom-ui-lock
           (sb-thread:make-mutex
            :name "cadr-extension-custom-ui"))
         (custom-ui-condition
           (sb-thread:make-waitqueue
            :name "cadr-extension-custom-ui"))
         (custom-ui-done-p nil)
         (custom-ui-result nil)
         (active-session-path current-session-path)
         (active-theme-mode nil)
         (terminal-progress-active-p nil))
    (declare (ignore active-theme))
    (dolist (text initial-notices)
      (add-tui-notice state text))
    (labels
        ((render-now ()
           (sb-thread:with-mutex (lock)
             (multiple-value-bind
                   (lines cursor-row cursor-column)
                 (render-tui-state
                  state editor
                  (cadr-tui:terminal-columns terminal)
                  (cadr-tui:terminal-rows terminal)
                  :overlay overlay
                  :busy-p busy-p
                  :extension-host extension-host
                  :full-document-p alt-p
                  :now (funcall clock-function)
                  :spinner-frame
                  (tui-status-animation-frame
                   status-animation))
               (cadr-tui:render-frame
                renderer lines
                :cursor-row cursor-row
                :cursor-column cursor-column))))
         (request-render (&optional force-p)
           (request-tui-render
            render-coordinator force-p))
         (refresh-footer-state ()
           (when footer-state-function
             (let ((values
                     (funcall
                      footer-state-function)))
               (when values
                 (sb-thread:with-mutex (lock)
                   (apply-tui-footer-state
                    state values)
                   (synchronize-tui-editor-border
                    state editor)))))
           (when footer-provider
             (sb-thread:with-mutex (lock)
               (setf
                (tui-state-branch state)
                (footer-data-provider-git-branch
                 footer-provider)
                (tui-state-statuses state)
                (footer-data-provider-statuses
                 footer-provider))))
           (request-render))
         (reset-theme-watcher
             (summary &optional background)
           (setf
            theme-watcher
            (make-tui-theme-watcher
             summary :background background)
            next-theme-poll-at
            (+ (funcall clock-function)
               +tui-theme-watch-poll-seconds+)))
         (apply-detected-background (background)
           (when
               (and
                detected-theme-function
                background)
             (let ((summary
                     (funcall
                      detected-theme-function
                      background)))
               (sb-thread:with-mutex (lock)
                 (apply-tui-theme-summary
                  summary
                  :background background)
                 (reset-theme-watcher
                  summary background))
               (request-render))))
         (current-theme-mode ()
           (let ((mode
                   (if theme-mode-function
                       (funcall theme-mode-function)
                       (if detected-theme-function
                           :auto
                           :fixed))))
             (unless
                 (member mode
                         '(:auto :detect-once :fixed))
               (error "Invalid terminal theme mode: ~S"
                      mode))
             mode))
         (query-osc11-background ()
           (let ((color
                   (cadr-tui:terminal-query-background-color
                    terminal
                    :timeout-seconds 0.1d0)))
             (and
              color
              (rgb-background-theme
               (cadr-tui:rgb-color-red color)
               (cadr-tui:rgb-color-green color)
               (cadr-tui:rgb-color-blue color)))))
         (refresh-terminal-theme-policy ()
           (let ((mode (current-theme-mode)))
             (setf active-theme-mode mode)
             (case mode
               (:auto
                (let ((background
                        (or
                         (cadr-tui:terminal-query-color-scheme
                          terminal
                          :timeout-seconds 0.1d0)
                         (query-osc11-background))))
                  (apply-detected-background background)))
               (:detect-once
                (apply-detected-background
                 (query-osc11-background))))
             (cadr-tui:terminal-set-color-scheme-notifications
              terminal (eq mode :auto))
             mode))
         (terminal-progress-enabled-p ()
           (not
            (null
             (if show-terminal-progress-function
                 (funcall
                  show-terminal-progress-function)
                 show-terminal-progress-p))))
         (set-terminal-progress-state (active-p)
           (let ((active-p (not (null active-p))))
             (unless (eq active-p
                         terminal-progress-active-p)
               (cadr-tui:terminal-set-progress
                terminal active-p)
               (setf terminal-progress-active-p
                     active-p)))
           terminal-progress-active-p)
         (synchronize-terminal-progress-setting ()
           (let ((enabled-p
                   (terminal-progress-enabled-p)))
             (when
                 (and
                  (not enabled-p)
                  terminal-progress-active-p)
               (set-terminal-progress-state nil))
             enabled-p))
         (poll-theme-watcher ()
           (let ((now
                   (funcall clock-function)))
             (when
                 (and theme-watcher
                      (>= now next-theme-poll-at))
               (setf next-theme-poll-at
                     (+ now
                        +tui-theme-watch-poll-seconds+))
               (when
                   (sb-thread:with-mutex (lock)
                     (poll-tui-theme-watcher
                      theme-watcher))
                 (request-render)))))
         (flush-render (&optional force-p)
           (flush-tui-render
            render-coordinator #'render-now
            :force-p force-p))
         (tick-status-animation ()
           (let ((changed-p
                   (sb-thread:with-mutex (lock)
                     (advance-tui-status-animation
                      status-animation state busy-p
                      (funcall clock-function)))))
             (when changed-p
               (request-render))))
         (notice (text)
           (sb-thread:with-mutex (lock)
             (add-tui-notice state text))
           (request-render))
         (show-auth-url (url)
           (sb-thread:with-mutex (lock)
             (add-tui-auth-url state url))
           (request-render))
         (show-model
             (model-id &optional provider
                       context-window
                       (updated-thinking nil
                                         updated-thinking-p)
                       updated-subscription-p)
           (when
               (and
                (stringp model-id)
                (plusp (length model-id)))
             (sb-thread:with-mutex (lock)
               (setf
                (tui-state-model state)
                model-id)
               (when provider
                 (setf
                  (tui-state-provider state)
                  (if (symbolp provider)
                      (string-downcase
                       (symbol-name provider))
                      (princ-to-string
                       provider))))
               (when context-window
                 (setf
                  (tui-state-context-window state)
                  context-window))
               (when updated-thinking-p
                 (setf
                  (tui-state-thinking state)
                  updated-thinking))
               (synchronize-tui-editor-border
                state editor)
               (when
                   (not
                    (null updated-subscription-p))
                 (setf
                  (tui-state-subscription-p state)
                  (not
                   (eq updated-subscription-p
                       :not-subscription)))))
             (request-render))
           (tui-state-model state))
         (finish-custom-ui (result)
           (sb-thread:with-mutex (custom-ui-lock)
             (unless custom-ui-done-p
               (setf
                custom-ui-result result
                custom-ui-done-p t)
               (sb-thread:condition-broadcast
                custom-ui-condition))))
         (show-custom-ui
             (factory overlay-p overlay-options)
           (declare (ignore overlay-p overlay-options))
           (sb-thread:with-mutex (custom-ui-lock)
             (setf
              custom-ui-done-p nil
              custom-ui-result nil))
           (let ((component
                   (funcall factory
                            #'finish-custom-ui)))
             (unless custom-ui-done-p
               (sb-thread:with-mutex (lock)
                 (setf
                  overlay-kind :extension-custom
                  overlay
                  (make-extension-custom-ui-state
                   :component component
                   :done-function
                   #'finish-custom-ui)))
               (request-render))
             (sb-thread:with-mutex (custom-ui-lock)
               (loop until custom-ui-done-p
                     do
                     (sb-thread:condition-wait
                      custom-ui-condition
                      custom-ui-lock))
               custom-ui-result)))
         (add-extension-autocomplete-provider
             (factory)
           (let* ((current
                    (cadr-tui::multiline-editor-autocomplete-provider
                     editor))
                  (replacement
                    (funcall factory current)))
             (when replacement
               (unless
                   (typep replacement
                          'cadr-tui:autocomplete-provider)
                 (error
                  'cadr-agent:extension-execution-error
                  :message
                  "Autocomplete factory must return an AUTOCOMPLETE-PROVIDER or NIL"))
               (cadr-tui:editor-set-autocomplete-provider
                editor replacement)))
           nil)
         (extension-ui-call (method arguments)
           (case method
             (:custom
              (show-custom-ui
               (getf arguments :factory)
               (getf arguments :overlay-p)
               (getf arguments :overlay-options)))
             (:add-autocomplete-provider
              (add-extension-autocomplete-provider
               (getf arguments :factory)))
             (:set-status
              (let ((key (getf arguments :key))
                    (text (getf arguments :text)))
                (if footer-provider
                    (footer-data-provider-set-status
                     footer-provider key text)
                    (sb-thread:with-mutex (lock)
                      (setf
                       (tui-state-statuses state)
                       (if text
                           (acons
                            key text
                            (remove
                             key
                             (tui-state-statuses state)
                             :key #'car
                             :test #'string=))
                           (remove
                            key
                            (tui-state-statuses state)
                            :key #'car
                            :test #'string=)))))
                (refresh-footer-state)
                nil))
             (:set-widget
              (sb-thread:with-mutex (lock)
                (set-tui-widget
                 state
                 (getf arguments :key)
                 (getf arguments :lines)
                 (getf arguments :placement)))
              (request-render)
              nil)
             (:set-editor-text
              (sb-thread:with-mutex (lock)
                (cadr-tui:editor-set-text
                 editor
                 (getf arguments :text))
                (synchronize-tui-editor-input-border
                 state editor))
              (request-render)
              nil)
             (:theme
              (and theme-function
                   (funcall theme-function)))
             (:all-themes
              (and all-themes-function
                   (funcall all-themes-function)))
             (:get-theme
              (and get-theme-function
                   (funcall get-theme-function
                            (getf arguments :name))))
             (:set-theme
              (when set-theme-function
                (let ((result
                        (funcall
                         set-theme-function
                         (getf arguments
                               :theme))))
                  (when
                      (getf result :success)
                    (let ((summary
                            (and theme-function
                                 (funcall
                                  theme-function))))
                      (sb-thread:with-mutex (lock)
                        (apply-tui-theme-summary
                         summary)
                        (reset-theme-watcher
                         summary)))
                    (refresh-terminal-theme-policy)
                    (request-render))
                  result)))
             (:tools-expanded-p
              (tui-state-tools-expanded-p state))
             (:set-tools-expanded
              (sb-thread:with-mutex (lock)
                (set-tui-tools-expanded
                 state
                 (getf arguments :expanded-p)))
              (request-render)
              nil)
             (otherwise nil)))
         (consume-event (event)
           (when (synchronize-terminal-progress-setting)
             (case
                 (cadr-agent:agent-event-type event)
               ((:agent-start :compaction-start)
                (set-terminal-progress-state t))
               ((:agent-end :compaction-end)
                (set-terminal-progress-state nil))))
           (sb-thread:with-mutex (lock)
             (if
                 (and
                  (eq
                   :compaction-end
                   (cadr-agent:agent-event-type
                    event))
                  session-state-function)
                 (multiple-value-bind
                       (display-messages
                        compaction-summary
                        compaction-tokens-before)
                     (funcall
                      session-state-function)
                   (tui-handle-agent-event
                    state event
                    :extension-host extension-host
                    :display-messages
                    display-messages
                    :compaction-summary
                    compaction-summary
                    :compaction-tokens-before
                    compaction-tokens-before
                    :clock-function clock-function))
                 (tui-handle-agent-event
                 state event
                  :extension-host extension-host
                  :clock-function clock-function)))
           (refresh-footer-state))
         (start-work (line)
           (unless busy-p
             (when reset-abort-function
               (funcall reset-abort-function))
             (sb-thread:with-mutex (lock)
               (setf busy-p t)
               (if
                   (let ((trimmed
                           (string-left-trim
                            '(#\Space #\Tab
                              #\Newline #\Return)
                            line)))
                     (and
                      (plusp (length trimmed))
                      (char= (char trimmed 0)
                             #\!)))
                   (cadr-tui:editor-set-border-mode
                    editor :bash)
                   (cadr-tui:editor-set-border-mode
                    editor :thinking
                    (or
                     (tui-state-thinking state)
                     :off))))
             (request-render)
             (setf
              worker
              (sb-thread:make-thread
               (lambda ()
                 (unwind-protect
                      (handler-case
                          (multiple-value-bind
                                (kind result)
                              (dispatch-user-input
                               line prompt-function
                               :command-function
                               command-function
                               :template-function
                               template-function
                               :bash-function
                               bash-function)
                            (when
                                (eq kind
                                    :unknown-command)
                              (notice
                               "Unknown command"))
                            (when
                                (and
                                 (eq kind :command)
                                 (stringp result)
                                 (plusp
                                  (length result)))
                              (notice result)))
                        (condition (condition)
                          (notice
                           (format nil "~A"
                                   condition))))
                   (sb-thread:with-mutex (lock)
                     (setf busy-p nil)
                     (cadr-tui:editor-set-border-mode
                      editor :thinking
                      (or
                       (tui-state-thinking state)
                       :off)))
                   (refresh-footer-state)))
               :name "cadr-tui-dispatch"))))
         (open-selector (kind items)
           (setf
            overlay-kind kind
            overlay
            (if (eq kind :session)
                (make-session-selector-state
                 :current-sessions
                 (session-select-items-to-records
                  items)
                 :current-session-path
                 active-session-path
                 :show-rename-hint-p
                 session-selector-show-rename-hint-p
                 :keybindings
                 (if session-selector-keybindings-function
                     (funcall
                      session-selector-keybindings-function)
                     session-selector-keybindings)
                 :rename-function
                 #'rename-session-at-path
                 :delete-function
                 #'delete-session-file)
                (cadr-tui:make-select-list
                 :items items
                 :height
                 (max 3
                      (- (cadr-tui:terminal-rows
                          terminal)
                         5)))))
           (request-render))
         (open-tree-selector ()
           (multiple-value-bind
                 (entries current-leaf-id)
               (if tree-state-function
                   (funcall tree-state-function)
                   (values nil nil))
             (setf
              overlay-kind :tree
              overlay
              (make-tree-selector-state
               :entries entries
               :current-leaf-id current-leaf-id
               :max-visible-lines
               (max
                5
                (floor
                 (cadr-tui:terminal-rows terminal)
                 2))
               :keybindings
               (if tree-selector-keybindings-function
                   (funcall
                    tree-selector-keybindings-function)
                   tree-selector-keybindings)
               :copy-callback
               tree-copy-function
               :label-callback
               on-tree-label))
             (request-render)))
         (open-model-selector (&optional query)
           (if model-selector-function
               (progn
                 (setf
                  overlay-kind :model
                  overlay
                  (if query
                      (funcall
                       model-selector-function query)
                      (funcall
                       model-selector-function)))
                 (request-render))
               (open-selector
                :model
                (if model-items-function
                    (funcall
                     model-items-function)
                    nil))))
         (open-scoped-models-selector ()
           (setf
            overlay-kind :scoped-models
            overlay
            (and scoped-models-selector-function
                 (funcall
                  scoped-models-selector-function)))
           (if overlay
               (request-render)
               (notice "No models available")))
         (open-trust-selector ()
           (setf
            overlay-kind :trust
            overlay
            (and trust-selector-function
                 (funcall trust-selector-function)))
           (if overlay
               (request-render)
               (notice
                "Project trust is unavailable")))
         (open-settings-selector ()
           (setf
            overlay-kind :settings
            overlay
            (and settings-selector-function
                 (funcall
                  settings-selector-function)))
           (if overlay
               (request-render)
               (notice "Settings are unavailable")))
         (open-import-confirmation (line path)
           (setf
            overlay-kind :import-confirmation
            overlay
            (make-import-confirmation-list
             line path))
           (request-render))
         (open-fork-selector ()
           (let ((items
                   (and fork-items-function
                        (funcall
                         fork-items-function))))
             (if items
                 (progn
                   (setf
                    overlay-kind :fork
                    overlay
                    (make-user-message-selector-state
                     :items items))
                   (request-render))
                 (notice
                  "No messages to fork from"))))
         (replace-session-state
             (selected-session selected-messages
              selected-path)
           (setf
            (tui-state-session state)
            (or selected-session
                (tui-state-session state)))
           (when selected-path
             (setf
              active-session-path selected-path))
           (setf
            (tui-state-entries state) nil
            (tui-state-current-assistant state)
            nil
            (tui-state-input-tokens state)
            0
            (tui-state-output-tokens state)
            0
            (tui-state-cache-read-tokens state)
            0
            (tui-state-cache-write-tokens state)
            0
            (tui-state-cache-tokens state)
            0
            (tui-state-latest-cache-hit-rate state)
            nil
            (tui-state-context-percent state)
            nil
            (tui-state-cost state)
            0d0
            (tui-state-cost-known-p state)
           nil)
           (dolist (message selected-messages)
             (seed-tui-message state message))
           (refresh-footer-state))
         (submit (line)
           (let ((trimmed
                   (string-trim
                    '(#\Space #\Tab #\Newline
                      #\Return)
                    line)))
             (cond
               ((or
                 (string= trimmed "/model")
                 (uiop:string-prefix-p
                  "/model " trimmed))
                (let ((query
                        (and
                         (> (length trimmed) 7)
                         (string-trim
                          '(#\Space #\Tab)
                          (subseq trimmed 7)))))
                  (if
                      (and
                       query
                       (plusp (length query))
                       resolve-model-reference-function
                       (let ((matched
                               (funcall
                                resolve-model-reference-function
                                query)))
                         (when matched
                           (when on-model-selected
                             (setf
                              (tui-state-model state)
                              (or
                               (funcall
                                on-model-selected
                                matched)
                               (tui-state-model
                                state))))
                           (refresh-footer-state)
                           (request-render)
                           t)))
                      nil
                      (open-model-selector query))))
               ((string= trimmed
                         "/scoped-models")
                (open-scoped-models-selector))
               ((string= trimmed "/fork")
                (open-fork-selector))
               ((string= trimmed "/new")
                (when on-new-session
                  (multiple-value-bind
                        (selected-session
                         selected-messages
                         selected-path)
                      (funcall on-new-session)
                    (when selected-session
                      (replace-session-state
                       selected-session
                       selected-messages
                       selected-path)
                      (notice
                       "New session started")))))
               ((string= trimmed "/quit")
                (setf done-p t))
               ((string= trimmed "/trust")
                (open-trust-selector))
               ((string= trimmed "/settings")
                (open-settings-selector))
               ((and
                 (or
                  (string= trimmed "/import")
                  (uiop:string-prefix-p
                   "/import " trimmed))
                 (path-command-argument
                  trimmed "/import"))
                (open-import-confirmation
                 trimmed
                 (path-command-argument
                  trimmed "/import")))
               ((member trimmed
                        '("/resume" "/sessions")
                        :test #'string=)
                (open-selector
                 :session
                 (if session-items-function
                     (funcall
                      session-items-function)
                     nil)))
               ((string= trimmed "/tree")
                (open-tree-selector))
               (t
                (route-tui-submission
                 line busy-p
                 busy-input-function
                 #'start-work)))))
         (accept-selection (value)
           (let ((kind overlay-kind))
             (setf overlay nil
                   overlay-kind nil)
             (handler-case
                 (case kind
                   (:model
                    (when on-model-selected
                      (setf
                       (tui-state-model state)
                       (or
                        (funcall
                         on-model-selected
                         value)
                         (tui-state-model
                         state)))))
                   (:trust
                    (when on-trust-selected
                      (funcall
                       on-trust-selected value)))
                   (:import-confirmation
                    (if
                        (getf value :confirmed-p)
                        (when on-import-confirmed
                          (funcall
                           on-import-confirmed
                           (getf value :line)))
                        (notice "Import cancelled")))
                   (:session
                    (when on-session-selected
                      (multiple-value-bind
                            (selected-session
                             selected-messages
                             selected-path)
                          (funcall
                           on-session-selected
                           value)
                        (replace-session-state
                         selected-session
                         selected-messages
                         selected-path))))
                   (:fork
                    (when on-fork-selected
                      (multiple-value-bind
                            (selected-session
                             selected-messages
                             selected-path
                             editor-text)
                          (funcall
                           on-fork-selected value)
                        (when selected-session
                          (replace-session-state
                           selected-session
                           selected-messages
                           selected-path)
                          (cadr-tui:editor-set-text
                           editor
                           (or editor-text ""))
                          (synchronize-tui-editor-input-border
                           state editor)
                          (add-tui-notice
                           state
                           "Forked to new session")))))
                   (:tree
                    (when on-tree-selected
                      (let ((selected-messages
                              (funcall
                               on-tree-selected
                               value)))
                        (when selected-messages
                          (reset-tui-messages
                           state
                           selected-messages)))))
                   (:extension-custom
                    (finish-custom-ui value)))
               (condition (condition)
                 (add-tui-notice
                  state
                  (format nil "~A" condition)))))
           (refresh-footer-state))
         (start-all-session-load (selector token)
           (if all-session-items-function
               (setf
                session-loader-worker
                (sb-thread:make-thread
                 (lambda ()
                   (handler-case
                       (let ((records
                               (session-select-items-to-records
                                (funcall
                                 all-session-items-function))))
                         (sb-thread:with-mutex (lock)
                           (session-selector-complete-all-load
                            selector token records)))
                     (condition (condition)
                       (sb-thread:with-mutex (lock)
                         (session-selector-fail-all-load
                          selector token condition))))
                   (request-render))
                 :name "cadr-session-selector-load"))
               (session-selector-complete-all-load
                selector token nil)))
         (handle-overlay-action (action value)
           (case action
             (:select
              (accept-selection value))
             (:cancel
              (when
                  (eq overlay-kind
                      :extension-custom)
                (finish-custom-ui nil))
              (setf overlay nil
                    overlay-kind nil)
              (request-render))
             (:load-all
              (start-all-session-load
               overlay value)
              (request-render))
             (:changed
              (when
                  (and
                   (eq overlay-kind :settings)
                   value
                   (string=
                    (getf value :id)
                    "theme")
                   theme-function)
                (let ((summary
                        (funcall theme-function)))
                  (sb-thread:with-mutex (lock)
                    (apply-tui-theme-summary
                     summary)
                    (reset-theme-watcher
                     summary))))
              (when
                  (and
                   (eq overlay-kind :settings)
                   value
                   (string=
                    (getf value :id)
                    "theme"))
                (refresh-terminal-theme-policy))
              (when (eq overlay-kind :settings)
                (synchronize-terminal-progress-setting)
                (refresh-footer-state))
              (request-render))
             (otherwise
              (request-render))))
         (handle-event (event)
           (if overlay
               (multiple-value-bind
                     (action value)
                   (if
                       (session-selector-state-p overlay)
                       (session-selector-handle-event
                        overlay event)
                       (if
                           (tree-selector-state-p overlay)
                           (tree-selector-handle-event
                            overlay event)
                           (cond
                             ((user-message-selector-state-p
                               overlay)
                              (user-message-selector-handle-event
                               overlay event))
                             ((model-selector-state-p
                               overlay)
                              (model-selector-handle-event
                               overlay event))
                             ((scoped-models-selector-state-p
                               overlay)
                              (scoped-models-selector-handle-event
                               overlay event))
                             ((trust-selector-state-p
                               overlay)
                              (trust-selector-handle-event
                               overlay event))
                             ((settings-selector-state-p
                               overlay)
                              (settings-selector-handle-event
                               overlay event))
                             ((extension-custom-ui-state-p
                               overlay)
                              (extension-custom-ui-handle-event
                               overlay event))
                             (t
                              (cadr-tui:select-list-handle-event
                               overlay event)))))
                 (handle-overlay-action
                  action value))
               (case (cadr-tui:input-event-kind event)
                 ((:escape :interrupt)
                  (if busy-p
                      (progn
                        (when abort-function
                          (funcall abort-function))
                        (notice "Abort requested"))
                      (progn
                        (handle-tui-editor-event
                         state editor event)
                        (request-render))))
                 (:clear
                  (let ((now
                          (funcall clock-function)))
                    (if
                        (and last-clear-at
                             (< (- now last-clear-at)
                                0.5d0))
                        (setf done-p t)
                        (progn
                          (handle-tui-editor-event
                           state editor event)
                          (setf last-clear-at now)
                          (request-render)))))
                 (:eof
                  (if
                      (zerop
                       (length
                        (cadr-tui:editor-text editor)))
                      (unless busy-p
                        (setf done-p t))
                      (progn
                        (handle-tui-editor-event
                         state editor
                         (cadr-tui:make-input-event
                          :kind :delete))
                        (request-render))))
                 (:toggle-tools
                  (toggle-last-tool-block state)
                  (request-render))
                 (otherwise
                  (multiple-value-bind
                        (action value)
                      (handle-tui-editor-event
                       state editor event)
                    (if (eq action :submit)
                        (submit value)
                        (request-render))))))))
      (when footer-provider
        (setf
         footer-unsubscribe
         (footer-data-provider-on-branch-change
          footer-provider
          #'refresh-footer-state)))
      (refresh-footer-state)
      (when set-event-consumer
        (funcall set-event-consumer
                 #'consume-event))
      (when set-notice-consumer
        (funcall set-notice-consumer
                 #'notice))
      (when set-auth-url-consumer
        (funcall set-auth-url-consumer
                 #'show-auth-url))
      (when set-model-consumer
        (funcall set-model-consumer
                 #'show-model))
      (when set-extension-ui-function
        (funcall set-extension-ui-function
                 #'extension-ui-call))
      (unwind-protect
           (cadr-tui:call-with-terminal
            terminal
            (lambda ()
              (refresh-terminal-theme-policy)
              (tick-status-animation)
              (request-render t)
              (flush-render)
              (loop until done-p
                    do
                    (unless
                        (eq active-theme-mode
                            (current-theme-mode))
                      (refresh-terminal-theme-policy))
                    (let ((background
                            (cadr-tui:terminal-color-scheme-change
                             terminal)))
                      (when background
                        (when (eq active-theme-mode :auto)
                          (apply-detected-background
                           background))))
                    (when
                        (cadr-tui:terminal-resized-p
                         terminal)
                      (cadr-tui:invalidate-renderer
                       renderer)
                      (request-render t))
                    (let ((input
                            (cadr-tui:terminal-read-input
                             terminal)))
                      (let ((extension-shortcut
                              (and
                               (null overlay)
                               extension-host
                               (plusp (length input))
                               (find-extension-shortcut-for-input
                                extension-host input))))
                      (cond
                        ((cadr-tui:renderer-handle-input
                          renderer input)
                         (request-render))
                        (extension-shortcut
                         (cadr-agent::invoke-extension-shortcut
                          extension-host
                         (cadr-agent::extension-shortcut-definition-key
                           extension-shortcut))
                         (request-render))
                        ((and
                          (null overlay)
                          (= 1 (length input))
                          (= 26
                             (char-code
                              (char input 0))))
                          (suspend-tui
                           #+win32 :windows
                           #-win32 :linux
                           (lambda ()
                             (cadr-tui:renderer-before-stop
                              renderer)
                             (cadr-tui:terminal-stop
                              terminal)
                             (cadr-tui:renderer-after-stop
                              renderer))
                           (lambda ()
                             (cadr-tui:renderer-start
                              renderer)
                             (cadr-tui:terminal-start
                              terminal)
                             (cadr-tui:invalidate-renderer
                              renderer))
                           (lambda ()
                             (request-render t)
                             (flush-render))
                           #'suspend-current-process
                           #'call-with-sigcont-handler
                           :notice-function #'notice))
                        (t
                         (multiple-value-bind
                            (action value handled-p)
                          (cond
                            ((and
                              (plusp (length input))
                              (session-selector-state-p
                               overlay))
                             (session-selector-handle-raw-input
                              overlay input))
                            ((and
                              (plusp (length input))
                              (tree-selector-state-p
                               overlay))
                             (tree-selector-handle-raw-input
                              overlay input))
                            ((and
                              (plusp (length input))
                              (user-message-selector-state-p
                               overlay))
                             (user-message-selector-handle-raw-input
                              overlay input))
                            ((and
                              (plusp (length input))
                              (model-selector-state-p
                               overlay))
                             (model-selector-handle-raw-input
                              overlay input))
                            ((and
                              (plusp (length input))
                              (scoped-models-selector-state-p
                               overlay))
                             (scoped-models-selector-handle-raw-input
                              overlay input))
                            ((and
                              (plusp (length input))
                              (trust-selector-state-p
                               overlay))
                             (trust-selector-handle-raw-input
                              overlay input))
                            ((and
                              (plusp (length input))
                              (settings-selector-state-p
                               overlay))
                             (settings-selector-handle-raw-input
                              overlay input))
                            (t
                             (values nil nil nil)))
                        (if handled-p
                            (handle-overlay-action
                             action value)
                            (dolist
                                (event
                                 (if
                                     (plusp
                                      (length input))
                                     (cadr-tui:feed-input
                                      decoder input)
                                     (cadr-tui:flush-input
                                      decoder)))
                              (handle-event event)))))))
                      )
                    (tick-status-animation)
                    (when
                        (sb-thread:with-mutex (lock)
                          (cadr-tui:editor-poll-autocomplete
                           editor))
                      (request-render))
                    (cadr-tui:terminal-poll-progress
                     terminal)
                    (poll-theme-watcher)
                    (flush-render)
                    (funcall sleep-function 0.005d0))
              (tick-status-animation)
              (flush-render t))
            :before-start
            (lambda ()
              (cadr-tui:renderer-start renderer))
            :before-stop
            (lambda ()
              (when terminal-progress-active-p
                (set-terminal-progress-state nil))
              (cadr-tui:renderer-before-stop
               renderer))
            :after-stop
            (lambda ()
              (cadr-tui:renderer-after-stop
               renderer)))
        (finish-custom-ui nil)
        (when terminal-progress-active-p
          (set-terminal-progress-state nil))
        (stop-tui-render-coordinator
         render-coordinator)
        (when (and worker
                   (sb-thread:thread-alive-p
                    worker))
          (when abort-function
            (funcall abort-function))
          (sb-thread:join-thread worker))
        (when
            (and session-loader-worker
                 (sb-thread:thread-alive-p
                  session-loader-worker))
          (sb-thread:join-thread
           session-loader-worker))
        (when set-event-consumer
          (funcall set-event-consumer nil))
        (when set-notice-consumer
          (funcall set-notice-consumer nil))
        (when set-auth-url-consumer
          (funcall set-auth-url-consumer nil))
        (when set-model-consumer
          (funcall set-model-consumer nil))
        (when set-extension-ui-function
          (funcall set-extension-ui-function nil))
        (when footer-unsubscribe
          (funcall footer-unsubscribe))
        (when footer-provider
          (footer-data-provider-dispose
           footer-provider))))
    state))
