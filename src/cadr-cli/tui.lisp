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
  (render-cache-lines nil :type list))

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
  context-percent
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
  working-message
  working-indicator-frames
  working-indicator-interval-ms
  hidden-thinking-label
  (hide-thinking-block-p nil :type boolean)
  status-message)

(defstruct extension-custom-ui-state
  component
  done-function
  (overlay-p nil :type boolean)
  overlay-options
  handle
  (legacy-p nil :type boolean)
  (disposed-p nil :type boolean))

(defstruct (runtime-auth-input-state
            (:constructor %make-runtime-auth-input-state))
  prompt
  input)

(defun make-runtime-auth-input-state (prompt)
  (%make-runtime-auth-input-state
   :prompt (copy-list prompt)
   :input
   (cadr-tui:make-single-line-input :prompt "> ")))

(defun runtime-auth-input-state-handle-event
    (state event)
  (if
      (member
       (cadr-tui:input-event-kind event)
       '(:escape :cancel :clear :interrupt :eof))
      (values :cancel nil)
      (multiple-value-bind (action value)
          (cadr-tui:single-line-input-handle-event
           (runtime-auth-input-state-input state)
           event)
        (values
         (if (eq action :submit) :select action)
         value))))

(defun render-runtime-auth-input-state (state width)
  (let* ((prompt (runtime-auth-input-state-prompt state))
         (input (runtime-auth-input-state-input state))
         (secret-p (eq :secret (getf prompt :type)))
         (display-input
           (if secret-p
               (let ((masked
                       (cadr-tui:make-single-line-input
                        :value
                        (make-string
                         (length
                          (cadr-tui:single-line-input-value input))
                         :initial-element #\*)
                        :prompt "> ")))
                 (setf
                  (cadr-tui::single-line-input-cursor masked)
                  (cadr-tui::single-line-input-cursor input))
                 masked)
               input)))
    (multiple-value-bind (input-lines row column)
        (cadr-tui:render-single-line-input display-input width)
      (declare (ignore row column))
      (append
       (list
        (selector-border-line width)
        ""
        (selector-fit-line
         (concatenate
          'string " "
          (cadr-tui:theme-foreground
           :accent
           (cadr-tui:theme-bold
            (getf prompt :message)
            :enabled-p t)
           :enabled-p t))
         width))
       (when (getf prompt :placeholder)
         (list
          (selector-fit-line
           (format nil " ~A" (getf prompt :placeholder))
           width)))
       input-lines
       (list
        (selector-fit-line
         " (escape/ctrl+c to cancel, enter to submit)"
         width)
        ""
        (selector-border-line width))))))

(defstruct (framed-select-state
            (:constructor %make-framed-select-state))
  (title "" :type string)
  message
  select-list
  deadline
  toggle-tools-function
  keybindings)

(defun make-framed-select-state
    (title labels values
     &key message timeout-ms toggle-tools-function keybindings)
  (%make-framed-select-state
   :title title
   :message message
   :deadline
   (and timeout-ms
        (plusp timeout-ms)
        (+ (tui-monotonic-seconds)
           (/ timeout-ms 1000d0)))
   :toggle-tools-function toggle-tools-function
   :keybindings
   (or keybindings
       (cadr-tui:get-keybindings))
   :select-list
   (cadr-tui:make-select-list
    :items
    (loop for label in labels
          for value in values
          collect
          (cadr-tui:make-select-item
           :label label :value value))
    :height (max 1 (length labels))
    :show-filter-p nil)))

(defun framed-select-key-hint (state name)
  (let ((keys
          (cadr-tui:keybinding-keys
           (framed-select-state-keybindings state)
           name)))
    (format nil "~{~A~^/~}" keys)))

(defun framed-select-title (state now)
  (let ((deadline (framed-select-state-deadline state)))
    (if deadline
        (format nil "~A (~Ds)"
                (framed-select-state-title state)
                (max 0 (ceiling (- deadline now))))
        (framed-select-state-title state))))

(defun render-framed-select-state
    (state width &key (now (tui-monotonic-seconds)))
  (labels ((indented (line)
             (cadr-tui:truncate-to-width
              (concatenate 'string " " line)
              width "")))
    (append
     (list
      (cadr-tui:theme-foreground
       :border
       (make-string width :initial-element #\─))
      "")
     (mapcar
      (lambda (line)
        (indented
         (cadr-tui:theme-foreground
          :accent
          (cadr-tui:theme-bold line :enabled-p t)
          :enabled-p t)))
      (uiop:split-string
       (framed-select-title state now)
       :separator '(#\Newline)))
     (when (framed-select-state-message state)
       (mapcar
        #'indented
        (uiop:split-string
         (framed-select-state-message state)
         :separator '(#\Newline))))
     (list "")
     (mapcar
      #'indented
      (cadr-tui:render-select-list
       (framed-select-state-select-list state)
       (max 1 (1- width))
       :ansi-theme-p t))
     (list
      ""
      (indented
       (format nil "↑↓ navigate  ~A select  ~A cancel"
               (framed-select-key-hint
                state "tui.select.confirm")
               (framed-select-key-hint
                state "tui.select.cancel")))
      ""
      (cadr-tui:theme-foreground
       :border
       (make-string width :initial-element #\─))))))

(defun framed-select-state-handle-event (state event)
  (if (eq (cadr-tui:input-event-kind event)
          :toggle-tools)
      (progn
        (when (framed-select-state-toggle-tools-function state)
          (funcall
           (framed-select-state-toggle-tools-function state)))
        (values :changed nil))
      (multiple-value-bind (action value)
          (cadr-tui:select-list-handle-event
           (framed-select-state-select-list state)
           event)
        (if (or action
                (not
                 (member
                  (cadr-tui:input-event-kind event)
                  '(:up :down :page-up :page-down
                    :text :backspace))))
            (values action value)
            (values :changed nil)))))

(defun framed-select-state-handle-raw-input (state data)
  (let ((keybindings
          (framed-select-state-keybindings state)))
    (cond
      ((or (string= data "k")
           (selector-keybinding-matches-p
            keybindings data "tui.select.up"))
       (multiple-value-bind (action value)
           (framed-select-state-handle-event
            state (cadr-tui:make-input-event :kind :up))
         (values action value t)))
      ((or (string= data "j")
           (selector-keybinding-matches-p
            keybindings data "tui.select.down"))
       (multiple-value-bind (action value)
           (framed-select-state-handle-event
            state (cadr-tui:make-input-event :kind :down))
         (values action value t)))
      ((selector-keybinding-matches-p
        keybindings data "tui.select.confirm")
       (multiple-value-bind (action value)
           (framed-select-state-handle-event
            state (cadr-tui:make-input-event :kind :enter))
         (values action value t)))
      ((selector-keybinding-matches-p
        keybindings data "tui.select.cancel")
       (multiple-value-bind (action value)
           (framed-select-state-handle-event
            state (cadr-tui:make-input-event :kind :escape))
         (values action value t)))
      ((and (= (length data) 1)
            (= (char-code (char data 0)) 15))
       (multiple-value-bind (action value)
           (framed-select-state-handle-event
            state (cadr-tui:make-input-event
                   :kind :toggle-tools))
         (values action value t)))
      (t (values nil nil nil)))))

(defun tui-component-protocol-p (value)
  (or (typep value 'cadr-tui:component)
      (typep value 'cadr-tui:multiline-editor)
      (typep value 'cadr-tui:single-line-input)))

(defun render-extension-custom-ui
    (state width)
  (let ((component
          (extension-custom-ui-state-component
           state)))
    (cond
      ((tui-component-protocol-p component)
       (cadr-tui:component-render component width
                                  :focused-p t))
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
      ((tui-component-protocol-p component)
       (multiple-value-bind (action value)
           (cadr-tui:component-handle-event component event)
         (if (or action
                 (not (extension-custom-ui-state-legacy-p state))
                 (not (eq :escape
                          (cadr-tui:input-event-kind event))))
             (values action value)
             (values :cancel nil))))
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
       hide-thinking-block-p
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
           :hide-thinking-block-p
           (not (null hide-thinking-block-p))
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
  (when (typep editor 'cadr-tui:multiline-editor)
    (unless
        (eq
         :bash-mode
         (cadr-tui::multiline-editor-border-color-key
          editor))
      (cadr-tui:editor-set-border-mode
       editor :thinking
       (or (tui-state-thinking state) :off))))
  editor)

(defun tui-editor-component-text (editor)
  (if (typep editor 'cadr-tui:multiline-editor)
      (cadr-tui:editor-text editor)
      (cadr-tui:editor-component-text editor)))

(defun tui-editor-component-set-text (editor text)
  (if (typep editor 'cadr-tui:multiline-editor)
      (cadr-tui:editor-set-text editor text)
      (cadr-tui:editor-component-set-text editor text)))

(defun tui-editor-component-clear (editor)
  (if (typep editor 'cadr-tui:multiline-editor)
      (cadr-tui::editor-clear editor)
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
  (when (typep editor 'cadr-tui:multiline-editor)
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
      (if (typep editor 'cadr-tui:multiline-editor)
          (cadr-tui:editor-handle-event editor event)
          (cadr-tui:component-handle-event editor event))
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

(defun render-tui-widgets
    (entries width &key spacer-when-empty-p leading-spacer-p)
  (if
      (null entries)
      (and spacer-when-empty-p (list ""))
      (nconc
       (and leading-spacer-p (list ""))
       (loop for entry in
             (sort (copy-list entries)
                   #'string< :key #'car)
             append
             (loop for line in (cdr entry)
                   append
                   (cadr-tui:wrap-text line width))))))

(defun replace-tui-entries (state entries)
  (dolist (entry (tui-state-entries state))
    (when (tui-entry-custom-component entry)
      (ignore-errors
        (cadr-tui:component-dispose
         (tui-entry-custom-component entry)))))
  (let ((tail (last entries)))
    (setf
     (tui-state-entries state) entries
     (tui-state-entries-tail state) tail
     (tui-state-entries-tail-head state) entries))
  state)

(defun append-tui-entry (state entry)
  (let* ((entries (tui-state-entries state))
         (tail (tui-state-entries-tail state))
         (cell (list entry)))
    (cond
      ((null entries)
       (setf
        (tui-state-entries state) cell
        (tui-state-entries-tail state) cell
        (tui-state-entries-tail-head state) cell))
      ((and tail
            (eq entries
                (tui-state-entries-tail-head state))
            (null (cdr tail)))
       (setf
        (cdr tail) cell
        (tui-state-entries-tail state) cell))
      (t
       ;; Internal fixtures historically SETF ENTRIES directly. Repair that
       ;; boundary once; production replacements use REPLACE-TUI-ENTRIES.
       (let ((recovered-tail (last entries)))
         (setf
          (cdr recovered-tail) cell
          (tui-state-entries-tail state) cell
          (tui-state-entries-tail-head state)
          entries)))))
  entry)

(defun invalidate-tui-entry-render-cache (entry)
  (setf
   (tui-entry-render-cache-valid-p entry) nil
   (tui-entry-render-cache-width entry) nil
   (tui-entry-render-cache-theme entry) nil
   (tui-entry-render-cache-extension-snapshot entry)
   nil
   (tui-entry-render-cache-lines entry) nil)
  entry)

(defun add-tui-message-entry (state type text)
  (let ((trimmed
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           (or text ""))))
    (when (plusp (length trimmed))
      (append-tui-entry
       state
       (make-tui-entry
        :type type
        :text trimmed))))
  state)

(defun add-tui-status (state text)
  (let ((trimmed
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           (or text ""))))
    (when (plusp (length trimmed))
      (let ((last-entry
              (and (tui-state-entries state)
                   (car (tui-state-entries-tail state)))))
        (if (and last-entry
                 (eq (tui-entry-type last-entry) :status))
            (progn
              (setf (tui-entry-text last-entry) trimmed)
              (invalidate-tui-entry-render-cache last-entry))
            (append-tui-entry
             state
             (make-tui-entry
              :type :status
              :text trimmed))))))
  state)

(defun add-tui-notice (state text)
  ;; NOTICE carries arbitrary frontend output.  It uses the same visual shape
  ;; as baseline status text, but must not coalesce adjacent lines.
  (add-tui-message-entry state :notice text))

(defun add-tui-error (state text)
  (add-tui-message-entry state :error text))

(defun add-tui-warning (state text)
  (add-tui-message-entry state :warning text))

(defun add-tui-success (state text)
  (add-tui-message-entry state :success text))

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
    (resources
     &key (version (cadr-ai::cadr-version)))
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
     (accumulate-message-usage state message))
    (cadr-agent:custom-agent-message
     (when (cadr-agent::custom-agent-message-display-p message)
       (append-tui-entry
        state
        (make-tui-entry
         :type :custom-message
         :custom-type
         (cadr-agent::custom-agent-message-custom-type message)
         :custom-payload
         (list
          :custom-type
          (cadr-agent::custom-agent-message-custom-type message)
          :content
          (cadr-agent::custom-agent-message-content message)
          :details
          (cadr-agent::custom-agent-message-details message)
          :display-p t)
         :custom-options
         '(:expanded-p nil :output-pad 1))))))
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
    (replace-tui-entries state nil)
    (setf
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
         (let ((command
                 (safe-tool-summary-value
                  (value "command")
                  "[invalid command]"))
               (timeout (value "timeout")))
           (if (numberp timeout)
               (format nil "~A (timeout ~As)" command timeout)
               command)))
        ((string-equal name "read")
         (let ((offset (value "offset"))
               (limit (value "limit")))
           (format
            nil "~A~A"
            (cadr-tui:shortened-home-path (path))
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
         (cadr-tui:shortened-home-path (path)))
        ((string-equal name "grep")
         (let ((pattern
                 (safe-tool-summary-value
                  (value "pattern")
                  "[invalid pattern]"))
               (base
                 (cadr-tui:shortened-home-path
                  (safe-tool-summary-value
                   (or (value "path") ".") ".")))
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
          (cadr-tui:shortened-home-path
           (safe-tool-summary-value
            (or (value "path") ".") "."))
          (limit-suffix " (limit ~A)")))
        ((string-equal name "ls")
         (format
          nil "~A~A"
          (cadr-tui:shortened-home-path
           (safe-tool-summary-value
            (or (value "path") ".") "."))
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
    (cond
      ((cadr-ai:tool-result-message-is-error result)
       text)
      ((string-equal
        (cadr-ai:tool-call-name call) "write")
       (let ((content
               (cadr-ai::json-get
                (cadr-ai:tool-call-arguments call)
                "content")))
         (if (stringp content) content text)))
      ((string-equal
        (cadr-ai:tool-call-name call) "edit")
       (let ((diff
               (tool-result-detail
                result :diff "diff")))
         (if (and (stringp diff)
                  (plusp (length diff)))
             diff
             text)))
      (t text))))

(defun tool-call-preview-output (call)
  (when (string-equal
         (cadr-ai:tool-call-name call) "write")
    (let ((content
            (cadr-ai::json-get
             (cadr-ai:tool-call-arguments call)
             "content")))
      (and (stringp content) content))))

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
      (:queue-update
       (setf
        (tui-state-steering-messages state)
        (copy-list
         (cadr-agent:agent-event-steering event))
        (tui-state-follow-up-messages state)
        (copy-list
         (cadr-agent:agent-event-follow-up event))))
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
                    :output
                    (or (tool-call-preview-output call) "")
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
           (invalidate-tui-entry-render-cache entry)
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
        "Compacting context..."))
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
           (add-tui-status state
                           "Context compacted")))
      (:compaction-error
       (setf
        (tui-state-status-message state)
        nil)
       (add-tui-error
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
    ((typep value 'cadr-tui:component)
     (cadr-tui:component-render
      value width :focused-p nil))
    ((cadr-tui::select-list-p value)
     (cadr-tui:render-select-list value width))
    (t
     (cadr-tui:wrap-text
      (princ-to-string value)
     width))))

(defun tui-extension-theme-runtime ()
  (list
   :fg (lambda (token text)
         (cadr-tui:theme-foreground token text :enabled-p t))
   :bg (lambda (token text)
         (cadr-tui:theme-background token text :enabled-p t))
   :bold (lambda (text)
           (cadr-tui:theme-bold text :enabled-p t))
   :italic (lambda (text)
             (cadr-tui:theme-italic text :enabled-p t))))

(defun render-extension-custom-entry
    (entry width extension-host)
  (unless extension-host
    (return-from render-extension-custom-entry nil))
  (let* ((theme (cadr-tui:current-theme))
         (snapshot
           (cadr-agent::extension-host-current-snapshot extension-host))
         (options (copy-list (tui-entry-custom-options entry)))
         (component (tui-entry-custom-component entry)))
    (unless
        (and component
             (eq theme (tui-entry-custom-component-theme entry))
             (eq snapshot
                 (tui-entry-custom-component-snapshot entry))
             (equal options
                    (tui-entry-custom-component-options entry)))
      (when component
        (ignore-errors
          (cadr-tui:component-dispose component)))
      (multiple-value-bind (rendered handled-p)
          (ecase (tui-entry-type entry)
            (:custom-message
             (cadr-agent::render-extension-message
              extension-host
              (tui-entry-custom-type entry)
              (tui-entry-custom-payload entry)
              options
              (tui-extension-theme-runtime)))
            (:custom-entry
             (cadr-agent::render-extension-entry
              extension-host
              (tui-entry-custom-type entry)
              (tui-entry-custom-payload entry)
              options
              (tui-extension-theme-runtime))))
        (unless handled-p
          (setf rendered
                (case (tui-entry-type entry)
                  (:custom-message
                   (or (getf (tui-entry-custom-payload entry) :content) ""))
                  (:custom-entry
                   (princ-to-string
                    (getf (tui-entry-custom-payload entry) :data))))))
        (setf
         (tui-entry-custom-component entry) rendered
         (tui-entry-custom-component-theme entry) theme
         (tui-entry-custom-component-snapshot entry) snapshot
         (tui-entry-custom-component-options entry) options
         component rendered)))
    (when (typep component 'cadr-tui:component)
      (cadr-tui:component-invalidate component))
    (extension-render-value-lines component width)))

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
    (entry width extension-host
     &key hide-thinking-block-p hidden-thinking-label)
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
            for display-source =
              (if (and hide-thinking-block-p
                       (eq message-type :assistant-thinking))
                  (or hidden-thinking-label "Thinking...")
                  source)
            for transformed =
              (transform-tui-markdown
               entry display-source message-type
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
        (when rendered
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

(defun render-tui-entry-uncached
    (entry width &key extension-host now
                      hide-thinking-block-p
                      hidden-thinking-label)
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
              entry width extension-host
              :hide-thinking-block-p hide-thinking-block-p
              :hidden-thinking-label hidden-thinking-label)))
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
    ((:custom-message :custom-entry)
     (render-extension-custom-entry
      entry width extension-host))
    (:compaction-summary
     (cadr-tui:wrap-text
      (format nil "Compaction summary: ~A"
              (tui-entry-text entry))
      width))
    (:notice
     (cons
      ""
      (loop for line in
            (cadr-tui:wrap-text
             (tui-entry-text entry)
             (max 1 (- width 2)))
            collect
            (concatenate
             'string " "
             (cadr-tui:theme-foreground
              :dim line :enabled-p t)))))
    (:status
     (cons
      ""
      (loop for line in
            (cadr-tui:wrap-text
             (tui-entry-text entry)
             (max 1 (- width 2)))
            collect
            (concatenate
             'string " "
             (cadr-tui:theme-foreground
              :dim line :enabled-p t)))))
    (:error
     (cons
      ""
      (loop for line in
            (cadr-tui:wrap-text
             (format nil "Error: ~A"
                     (tui-entry-text entry))
             (max 1 (- width 2)))
            collect
            (concatenate
             'string " "
             (cadr-tui:theme-foreground
              :error line :enabled-p t)))))
    (:warning
     (cons
      ""
      (loop for line in
            (cadr-tui:wrap-text
             (format nil "Warning: ~A"
                     (tui-entry-text entry))
             (max 1 (- width 2)))
            collect
            (concatenate
             'string " "
             (cadr-tui:theme-foreground
              :warning line :enabled-p t)))))
    (:success
     (append
      '("" "")
      (loop for line in
            (cadr-tui:wrap-text
             (format nil "✓ ~A"
                     (tui-entry-text entry))
             (max 1 (- width 2)))
            collect
            (concatenate
             'string " "
             (cadr-tui:theme-foreground
              :accent line :enabled-p t)))
      '("")))
    (:auth-url
     (render-auth-url-lines
      (tui-entry-text entry)
      width))
    (otherwise nil)))

(defun tui-entry-render-cacheable-p (entry)
  (and
   (not (tui-entry-streaming-p entry))
   (or
    (not (eq (tui-entry-type entry) :tool))
    (let ((block (tui-entry-tool-block entry)))
      (and
       block
       (not
        (eq (cadr-tui:tool-block-status block)
            :running))
       (not (tui-entry-custom-call-rendered-p entry))
       (not
        (tui-entry-custom-result-rendered-p entry)))))))

(defun render-tui-entry
    (entry width &key extension-host now
                      hide-thinking-block-p
                      hidden-thinking-label)
  (let* ((cacheable-p
           (tui-entry-render-cacheable-p entry))
         (theme
           (and cacheable-p
                (cadr-tui:current-theme)))
         (snapshot
           (and
            cacheable-p
            extension-host
            (cadr-agent::extension-host-current-snapshot
             extension-host))))
    (if
        (and
         cacheable-p
         (tui-entry-render-cache-valid-p entry)
         (= width
            (tui-entry-render-cache-width entry))
         (eq theme
             (tui-entry-render-cache-theme entry))
         (eq
          snapshot
          (tui-entry-render-cache-extension-snapshot
           entry)))
        (tui-entry-render-cache-lines entry)
        (let ((lines
                (render-tui-entry-uncached
                 entry width
                 :extension-host extension-host
                 :now now
                 :hide-thinking-block-p hide-thinking-block-p
                 :hidden-thinking-label hidden-thinking-label)))
          (when cacheable-p
            (setf
             (tui-entry-render-cache-valid-p entry) t
             (tui-entry-render-cache-width entry) width
             (tui-entry-render-cache-theme entry) theme
             (tui-entry-render-cache-extension-snapshot
              entry)
             snapshot
             (tui-entry-render-cache-lines entry) lines))
          lines))))

(defun render-tui-entries
    (entries width &key extension-host now
                        hide-thinking-block-p
                        hidden-thinking-label)
  (loop
    for entry in entries
    for index from 0
    for rendered =
      (render-tui-entry
       entry width
       :extension-host extension-host
       :now now
       :hide-thinking-block-p hide-thinking-block-p
       :hidden-thinking-label hidden-thinking-label)
    append
      (if
          (and
           (plusp index)
           (eq (tui-entry-type entry) :user))
          (cons "" rendered)
          rendered)))

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

(defun tui-queued-message-text (message)
  (typecase message
    (cadr-ai:user-message
     (cadr-ai::content-text
      (cadr-ai:user-message-content message)))
    (string message)
    (t (princ-to-string message))))

(defun restore-queued-messages-to-editor (editor queued)
  (let ((count (length queued)))
    (when (plusp count)
      (let* ((queued-text
               (format nil "~{~A~^~%~%~}" queued))
             (current
               (cadr-tui:editor-text editor))
             (combined
               (if
                   (zerop
                    (length
                     (string-trim
                      '(#\Space #\Tab #\Newline #\Return)
                      current)))
                   queued-text
                   (format nil "~A~%~%~A"
                           queued-text current))))
        (tui-editor-component-set-text editor combined)))
    count))

(defun render-tui-pending-message-lines (state width)
  (let ((steering
          (tui-state-steering-messages state))
        (follow-up
          (tui-state-follow-up-messages state)))
    (when (or steering follow-up)
      (flet ((pending-line (text)
               (cadr-tui:theme-foreground
                :dim
                (cadr-tui:truncate-to-width
                 (concatenate 'string " " text)
                 width "")
                :enabled-p t)))
        (nconc
         (list "")
         (mapcar
          (lambda (message)
            (pending-line
             (format nil "Steering: ~A"
                     (tui-queued-message-text message))))
          steering)
         (mapcar
          (lambda (message)
            (pending-line
             (format nil "Follow-up: ~A"
                     (tui-queued-message-text message))))
          follow-up)
         (list
          (pending-line
           (format
            nil "↳ ~A to edit all queued messages"
            (or
             (first
              (cadr-tui:keybinding-keys
               (cadr-tui:get-keybindings)
               "app.message.dequeue"))
             "alt+up")))))))))

(defun render-tui-overlay-lines (overlay width now)
  (cond
    ((session-selector-state-p overlay)
     (render-session-selector overlay width))
    ((tree-selector-state-p overlay)
     (render-tree-selector overlay width))
    ((user-message-selector-state-p overlay)
     (render-user-message-selector overlay width))
    ((model-selector-state-p overlay)
     (render-model-selector overlay width))
    ((scoped-models-selector-state-p overlay)
     (render-scoped-models-selector overlay width))
    ((trust-selector-state-p overlay)
     (render-trust-selector overlay width))
    ((settings-selector-state-p overlay)
     (render-settings-selector overlay width))
    ((login-method-selector-state-p overlay)
     (render-login-method-selector overlay width))
    ((api-key-input-state-p overlay)
     (render-api-key-input-state overlay width))
    ((runtime-auth-input-state-p overlay)
     (render-runtime-auth-input-state overlay width))
    ((oauth-selector-state-p overlay)
     (render-oauth-selector overlay width))
    ((extension-custom-ui-state-p overlay)
     (render-extension-custom-ui overlay width))
    ((framed-select-state-p overlay)
     (render-framed-select-state
      overlay width :now now))
    (t
     (cadr-tui:render-select-list overlay width))))

(defun extension-overlay-options (state)
  (let ((options
          (extension-custom-ui-state-overlay-options state)))
    (if (functionp options)
        (funcall options)
        options)))

(defun extension-custom-ui-visible-p (state)
  (let* ((handle (extension-custom-ui-state-handle state))
         (options (or (extension-overlay-options state) nil))
         (missing (gensym "MISSING"))
         (visible (getf options :visible missing))
         (visible-p (getf options :visible-p missing)))
    (and
     (or (null handle)
         (not (cadr-tui:overlay-handle-hidden-p handle)))
     (not (or (and (not (eq visible missing))
                   (null visible))
              (and (not (eq visible-p missing))
                   (null visible-p)))))))

(defun render-editor-component (editor width rows focused-p)
  (if (typep editor 'cadr-tui:multiline-editor)
      (cadr-tui:render-editor
       editor width :terminal-rows rows :focused-p focused-p)
      (values
       (cadr-tui:component-render editor width
                                  :focused-p focused-p)
       0 0)))

(defun render-tui-extension-overlay
    (state editor width rows overlay
     &key busy-p extension-host full-document-p now spinner-frame)
  (multiple-value-bind (base cursor-row cursor-column)
      (render-tui-state
       state editor width rows
       :busy-p busy-p :extension-host extension-host
       :full-document-p full-document-p :now now
       :spinner-frame spinner-frame)
    (unless (extension-custom-ui-visible-p overlay)
      (return-from render-tui-extension-overlay
        (values base cursor-row cursor-column)))
    (let ((options (or (extension-overlay-options overlay) nil)))
      (multiple-value-bind (overlay-width ignored-row ignored-column
                            ignored-max-height)
          (cadr-tui:resolve-overlay-layout
           width rows 0
           :width (getf options :width)
           :min-width (getf options :min-width)
           :max-height (getf options :max-height)
           :anchor (or (getf options :anchor) :center)
           :offset-x (or (getf options :offset-x) 0)
           :offset-y (or (getf options :offset-y) 0)
           :row (getf options :row)
           :col (getf options :col)
           :margin (getf options :margin))
        (declare (ignore ignored-row ignored-column ignored-max-height))
        (values
         (cadr-tui:composite-overlay-frame
          base
          (list
           (cadr-tui:make-overlay-placement
            :lines
            (render-extension-custom-ui overlay overlay-width)
            :width (getf options :width)
            :min-width (getf options :min-width)
            :max-height (getf options :max-height)
            :anchor (or (getf options :anchor) :center)
            :offset-x (or (getf options :offset-x) 0)
            :offset-y (or (getf options :offset-y) 0)
            :row (getf options :row)
            :col (getf options :col)
            :margin (getf options :margin)
            :visible-p t))
          width rows)
         cursor-row cursor-column)))))

(defun render-tui-state
    (state editor width rows
     &key overlay busy-p extension-host
       full-document-p
       (now (tui-monotonic-seconds))
       (spinner-frame
         (aref +tui-spinner-frames+ 0)))
  (when (and (extension-custom-ui-state-p overlay)
             (extension-custom-ui-state-overlay-p overlay))
    (return-from render-tui-state
      (render-tui-extension-overlay
       state editor width rows overlay
       :busy-p busy-p :extension-host extension-host
       :full-document-p full-document-p :now now
       :spinner-frame spinner-frame)))
  (multiple-value-bind
        (editor-lines editor-row editor-column)
      (render-editor-component editor width rows (null overlay))
    (let* ((pending-message-lines
             (render-tui-pending-message-lines
              state width))
           (status-indicator
             (or
              (render-tui-status-indicator
               (tui-state-status-message state)
               width :reserve-idle-p nil
               :spinner-frame spinner-frame)
              (and
               busy-p
               (tui-state-working-visible-p state)
               (render-tui-status-indicator
                (or (tui-state-working-message state)
                    "Working...") width
                :reserve-idle-p nil
                :spinner-frame
                (let ((frames
                        (tui-state-working-indicator-frames state)))
                  (if (consp frames)
                      (nth
                       (mod
                        (floor
                         (* now 1000)
                         (or
                          (tui-state-working-indicator-interval-ms state)
                          80))
                        (length frames))
                       frames)
                      spinner-frame))))
              (and
               (not full-document-p)
               (render-tui-status-indicator
                nil width :reserve-idle-p t
                :spinner-frame spinner-frame))))
           (header-lines
             (and (tui-state-header-component state)
                  (cadr-tui:component-render
                   (tui-state-header-component state) width)))
           (footer-lines
             (if (tui-state-footer-component state)
                 (cadr-tui:component-render
                  (tui-state-footer-component state) width)
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
              :ansi-theme-p t)))
           (widget-above-lines
             (render-tui-widgets
              (tui-state-widgets-above state)
              width
              :spacer-when-empty-p t
              :leading-spacer-p t))
           (widget-below-lines
             (render-tui-widgets
              (tui-state-widgets-below state)
              width
              :spacer-when-empty-p nil
              :leading-spacer-p nil))
           (overlay-lines
             (and overlay
                  (render-tui-overlay-lines
                   overlay width now)))
           (fixed-lines-without-editor
             (+ (length pending-message-lines)
                (length status-indicator)
                (length widget-above-lines)
                (length widget-below-lines)
                (length footer-lines)))
           (active-editor-lines
             (if overlay
                 (fit-overlay-lines
                  overlay-lines
                  (max 0
                       (- rows
                          fixed-lines-without-editor)))
                 editor-lines))
           (non-content-lines
             (+ (length pending-message-lines)
                (length status-indicator)
                (length widget-above-lines)
                (length active-editor-lines)
                (length widget-below-lines)
                (length footer-lines)))
           (content-height
             (max 0
                  (- rows
                     non-content-lines)))
           (entry-content
             (render-tui-entries
              (tui-state-entries state)
              width
              :extension-host extension-host
              :now now
              :hide-thinking-block-p
              (tui-state-hide-thinking-block-p state)
              :hidden-thinking-label
              (tui-state-hidden-thinking-label state)))
           (startup-lines
             (if
                 (tui-state-tools-expanded-p state)
                 (or
                  (tui-state-startup-expanded-lines
                   state)
                  (tui-state-startup-compact-lines
                   state))
                 (tui-state-startup-compact-lines
                  state)))
           (startup-lines
             (and startup-lines
                  (render-tui-startup-lines
                   startup-lines width)))
           (all-content
             (append
              header-lines
              (if startup-lines
                  (nconc
                   (list "")
                   (copy-list startup-lines)
                   (list "")
                   entry-content)
                  entry-content)))
           (visible
             (cond
               ((and full-document-p
                     (null overlay))
                all-content)
               (t
                (trailing-lines
                 all-content content-height))))
           (overlay-padding
             ;; Editor-slot overlays keep their fixed viewport geometry;
             ;; ordinary transcript composition keeps its natural height.
             (and overlay
                  (make-list
                   (max 0
                        (- content-height
                           (length visible)))
                   :initial-element "")))
           (cursor-row
             (+ (if overlay
                    (max content-height
                         (length visible))
                    (length visible))
                (length pending-message-lines)
                (length status-indicator)
                (length widget-above-lines)
                (if overlay 0 editor-row))))
      (values
       (nconc overlay-padding
              visible
              pending-message-lines
              status-indicator
              widget-above-lines
              active-editor-lines
              widget-below-lines
              footer-lines)
       cursor-row
       (if overlay 0 editor-column)))))

(defun set-tui-tools-expanded
    (state expanded-p)
  (setf
   (tui-state-tools-expanded-p state)
   (not (null expanded-p)))
  (dolist (entry (tui-state-entries state))
    (case (tui-entry-type entry)
      (:tool
       (invalidate-tui-entry-render-cache entry)
       (setf
        (cadr-tui:tool-block-collapsed-p
         (tui-entry-tool-block entry))
        (not expanded-p)))
      ((:custom-message :custom-entry)
       (setf (getf (tui-entry-custom-options entry) :expanded-p)
             (not (null expanded-p)))
       (invalidate-tui-entry-render-cache entry))))
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
  (make-framed-select-state
   "Import session"
   '("Yes" "No")
   (list
    (list :confirmed-p t
          :line line
          :path path)
    (list :confirmed-p nil
          :line line
          :path path))
   :message
   (format nil "Replace current session with ~A?" path)))

(defparameter +tui-autocomplete-command-specifications+
  '(("settings" "Open settings menu" nil)
    ("model" "Select model (opens selector UI)"
     "<provider/model>")
    ("scoped-models"
     "Enable/disable models for Ctrl+P cycling" nil)
    ("export"
     "Export session (HTML default, or specify path: .html/.jsonl)"
     nil)
    ("import"
     "Import and resume a session from a JSONL file" nil)
    ("share" "Share session as a secret GitHub gist" nil)
    ("copy" "Copy last agent message to clipboard" nil)
    ("name" "Set session display name" nil)
    ("session" "Show session info and stats" nil)
    ("changelog" "Show changelog entries" nil)
    ("hotkeys" "Show all keyboard shortcuts" nil)
    ("fork"
     "Create a new fork from a previous user message" nil)
    ("clone"
     "Duplicate the current session at the current position" nil)
    ("tree" "Navigate session tree (switch branches)" nil)
    ("trust"
     "Save project trust decision for future sessions" nil)
    ("login" "Configure provider authentication" "<provider>")
    ("logout" "Remove provider authentication" nil)
    ("new" "Start a new session" nil)
    ("compact" "Manually compact the session context" nil)
    ("resume" "Resume a different session" nil)
    ("reload"
     "Reload keybindings, extensions, skills, prompts, themes, and context files"
     nil)
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

(defun tui-model-autocomplete-items
    (model-items-function prefix)
  (let* ((models
           (loop for item in (and model-items-function
                                  (funcall model-items-function))
                 for model = (cadr-tui:select-item-value item)
                 when (typep model 'cadr-ai:model)
                   collect model))
         (filtered
           (cadr-tui::fuzzy-filter
            models prefix
            (lambda (model)
              (format nil "~(~A~)/~A ~A"
                      (cadr-ai:model-provider model)
                      (cadr-ai:model-id model)
                      (cadr-ai::model-name model))))))
    (loop for model in filtered
          for provider =
            (format nil "~(~A~)"
                    (cadr-ai:model-provider model))
          for id = (cadr-ai:model-id model)
          collect
          (cadr-tui:make-autocomplete-item
           :value (format nil "~A/~A" provider id)
           :label id
           :description provider))))

(defun tui-login-autocomplete-records (options)
  (let ((records nil))
    (dolist (option options)
      (let* ((id
               (format nil "~(~A~)"
                       (oauth-selector-option-id option)))
             (record
               (find id records
                     :key (lambda (entry) (getf entry :id))
                     :test #'string=)))
        (if record
            (pushnew
             (oauth-selector-option-auth-type option)
             (getf record :auth-types))
            (push
             (list
              :id id
              :name (oauth-selector-option-name option)
              :auth-types
              (list
               (oauth-selector-option-auth-type option)))
             records))))
    (sort records #'string<
          :key (lambda (entry) (getf entry :name)))))

(defun tui-auth-type-label (auth-type)
  (if (eq auth-type :oauth)
      "subscription"
      "API key"))

(defun tui-login-autocomplete-items
    (login-options-function prefix)
  (let* ((records
           (tui-login-autocomplete-records
            (and login-options-function
                 (funcall login-options-function))))
         (filtered
           (cadr-tui::fuzzy-filter
            records prefix
            (lambda (record)
              (format nil "~A ~A ~{~A~^ ~}"
                      (getf record :id)
                      (getf record :name)
                      (mapcar
                       #'tui-auth-type-label
                       (getf record :auth-types)))))))
    (loop for record in filtered
          for id = (getf record :id)
          for name = (getf record :name)
          for types =
            (sort
             (copy-list (getf record :auth-types))
             #'<
             :key
             (lambda (auth-type)
               (if (eq auth-type :oauth) 0 1)))
          for auth-label =
            (format nil "~{~A~^/~}"
                    (mapcar #'tui-auth-type-label types))
          collect
          (cadr-tui:make-autocomplete-item
           :value id
           :label id
           :description
           (if (string= name id)
               auth-label
               (format nil "~A · ~A" name auth-label))))))

(defun make-tui-autocomplete-provider
    (&key
       (base-path (uiop:getcwd))
       model-items-function
       (login-options-function
         (lambda ()
           (login-provider-options
            (cadr-ai:list-provider-definitions)))))
  (cadr-tui:make-autocomplete-provider
   :commands
   (loop for (name description argument-hint)
         in +tui-autocomplete-command-specifications+
         collect
         (cadr-tui:make-autocomplete-command
          :name name
          :description description
          :argument-hint argument-hint
          :argument-completer
          (cond
            ((string= name "model")
             (lambda (prefix)
               (tui-model-autocomplete-items
                model-items-function prefix)))
            ((string= name "login")
             (lambda (prefix)
               (tui-login-autocomplete-items
                login-options-function prefix))))))
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

(defun call-with-tui-command-error-notice
    (function notice-function)
  (handler-case
      (funcall function)
    (error (condition)
      (funcall
       notice-function
       (format nil "~A" condition)))))

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
   :output nil
   :error-output nil))

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
       set-status-consumer
       set-warning-consumer
       set-auth-url-consumer
       set-auth-prompt-consumer
       set-model-consumer
       set-extension-ui-function
       extension-overlay-opened-function
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
       preview-theme-function
       session-state-function
       busy-input-function
       follow-up-input-function
       dequeue-function
       model-items-function
       login-options-function
       model-selector-function
       scoped-models-selector-function
       trust-selector-function
       settings-selector-function
       extension-host
       fork-items-function
       session-items-function
       all-session-items-function
       tree-state-function
       api-key-login-function
       auth-status-function
       logout-options-function
       on-model-selected
       on-logout-selected
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
       hide-thinking-block-p
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
            :hide-thinking-block-p hide-thinking-block-p
            :session session
            :messages messages))
         (editor
           (let ((editor
                   (cadr-tui:make-multiline-editor
                    :autocomplete-max-visible
                    autocomplete-max-visible)))
             (cadr-tui:editor-set-autocomplete-provider
              editor
              (make-tui-autocomplete-provider
               :model-items-function
               model-items-function
               :login-options-function
               (or
                login-options-function
                (lambda ()
                  (login-provider-options
                   (cadr-ai:list-provider-definitions))))))
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
         (abort-requested-p nil)
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
         (active-custom-ui-state nil)
         (custom-editor-component nil)
         (custom-editor-factory nil)
         (extension-ui-root nil)
         (active-session-path current-session-path)
         (active-theme-mode nil)
         (terminal-progress-active-p nil))
    (declare (ignore active-theme))
    (dolist (text initial-notices)
      (add-tui-warning state text))
    (labels
        ((current-editor ()
           (or custom-editor-component editor))
         (extension-runtime ()
           (or extension-ui-root
               (setf
                extension-ui-root
                (cadr-tui:make-tui-root
                 :terminal terminal
                 :render-function
                 (lambda (lines)
                   (declare (ignore lines))
                   (request-render))))))
         (extension-theme-runtime ()
           (tui-extension-theme-runtime))
         (dispose-component (component)
           (when (tui-component-protocol-p component)
             (ignore-errors
               (cadr-tui:component-dispose component))))
         (overlay-captures-input-p ()
           (and
            overlay
            (or
             (not (extension-custom-ui-state-p overlay))
             (not (extension-custom-ui-state-overlay-p overlay))
             (let ((options (or (extension-overlay-options overlay) nil)))
               (and
                (extension-custom-ui-visible-p overlay)
                (not
                 (or (getf options :non-capturing)
                     (getf options :non-capturing-p))))))))
         (render-now ()
           (sb-thread:with-mutex (lock)
             (multiple-value-bind
                   (lines cursor-row cursor-column)
                 (render-tui-state
                  state (current-editor)
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
                    state (current-editor))))))
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
         (status (text)
           (sb-thread:with-mutex (lock)
             (add-tui-status state text))
           (request-render))
         (warning (text)
           (sb-thread:with-mutex (lock)
             (add-tui-warning state text))
           (request-render))
         (show-error (text)
           (sb-thread:with-mutex (lock)
             (add-tui-error state text))
           (request-render))
         (success (text)
           (sb-thread:with-mutex (lock)
             (add-tui-success state text))
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
                state (current-editor))
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
               (when active-custom-ui-state
                 (let ((handle
                         (extension-custom-ui-state-handle
                          active-custom-ui-state)))
                   (when handle
                     (cadr-tui:overlay-handle-hide handle)))
                 (unless
                     (extension-custom-ui-state-disposed-p
                      active-custom-ui-state)
                   (dispose-component
                    (extension-custom-ui-state-component
                     active-custom-ui-state))
                   (setf
                    (extension-custom-ui-state-disposed-p
                     active-custom-ui-state)
                    t))
                 (setf active-custom-ui-state nil))
               (setf
                custom-ui-result result
                custom-ui-done-p t)
               (sb-thread:condition-broadcast
                custom-ui-condition))))
         (show-extension-overlay
             (component &key signal timeout-ms)
           (sb-thread:with-mutex (custom-ui-lock)
             (setf
              custom-ui-done-p nil
              custom-ui-result nil))
           (unless custom-ui-done-p
             (sb-thread:with-mutex (lock)
               (setf overlay-kind :extension-custom
                     overlay component))
             (request-render)
             (when extension-overlay-opened-function
               (funcall extension-overlay-opened-function)))
           (let* ((deadline
                    (and timeout-ms
                         (+ (get-internal-real-time)
                            (ceiling
                             (* timeout-ms
                                internal-time-units-per-second)
                             1000))))
                  (monitor
                    (and
                     (or signal deadline)
                     (sb-thread:make-thread
                      (lambda ()
                        (loop with last-countdown = nil
                          when
                            (and deadline
                                 (framed-select-state-p component))
                          do
                            (let ((remaining
                                    (max
                                     0
                                     (ceiling
                                      (/ (- deadline
                                            (get-internal-real-time))
                                         internal-time-units-per-second)))))
                              (unless (eql remaining last-countdown)
                                (setf last-countdown remaining)
                                (request-render)))
                          (when
                              (sb-thread:with-mutex (custom-ui-lock)
                                custom-ui-done-p)
                            (return))
                          (when
                              (or
                               (and signal
                                    (cadr-agent::extension-cancellation-aborted-p
                                     signal))
                               (and deadline
                                    (>= (get-internal-real-time)
                                        deadline)))
                            (finish-custom-ui nil)
                            (return))
                          (sleep 0.01)))
                      :name "cadr-extension-ui-timeout")))
                  (result
                    (sb-thread:with-mutex (custom-ui-lock)
                      (loop until custom-ui-done-p
                            do
                            (sb-thread:condition-wait
                             custom-ui-condition
                             custom-ui-lock))
                      custom-ui-result)))
             (when monitor
               (sb-thread:join-thread monitor))
             (sb-thread:with-mutex (lock)
               (when (eq overlay component)
                 (setf overlay nil
                       overlay-kind nil)))
             (request-render)
             result))
         (show-custom-ui
             (factory overlay-p overlay-options)
           (sb-thread:with-mutex (custom-ui-lock)
             (setf custom-ui-done-p nil
                   custom-ui-result nil))
           (let ((component
                   (funcall factory
                            #'finish-custom-ui)))
             (if custom-ui-done-p
                 custom-ui-result
                 (let ((state
                         (make-extension-custom-ui-state
                          :component component
                          :done-function #'finish-custom-ui
                          :overlay-p (not (null overlay-p))
                          :overlay-options overlay-options
                          :legacy-p t)))
                   (when overlay-p
                     (setf
                      (extension-custom-ui-state-handle state)
                      (cadr-tui:overlay-stack-show
                       (cadr-tui:make-overlay-stack
                        :focused-component (current-editor))
                       component nil)))
                   (setf active-custom-ui-state state)
                   (show-extension-overlay state)))))
         (show-custom-component-ui
             (factory overlay-p overlay-options on-handle)
           (sb-thread:with-mutex (custom-ui-lock)
             (setf custom-ui-done-p nil
                   custom-ui-result nil))
           (let ((component
                   (funcall
                    factory
                    (extension-runtime)
                    (extension-theme-runtime)
                    (cadr-tui:get-keybindings)
                    #'finish-custom-ui)))
             (unless (tui-component-protocol-p component)
               (error
                'cadr-agent:extension-execution-error
                :message
                "Custom component factory must return a CADR-TUI:COMPONENT"))
             (if custom-ui-done-p
                 custom-ui-result
                 (let ((state
                         (make-extension-custom-ui-state
                          :component component
                          :done-function #'finish-custom-ui
                          :overlay-p (not (null overlay-p))
                          :overlay-options overlay-options)))
                   (when overlay-p
                     (let* ((options
                              (if (functionp overlay-options)
                                  (funcall overlay-options)
                                  overlay-options))
                            (non-capturing-p
                              (or (getf options :non-capturing)
                                  (getf options :non-capturing-p)))
                            (handle
                              (cadr-tui:overlay-stack-show
                               (cadr-tui:make-overlay-stack
                                :focused-component (current-editor))
                               component nil
                               :non-capturing-p non-capturing-p)))
                       (setf
                        (extension-custom-ui-state-handle state)
                        handle)
                       (when on-handle
                         (funcall on-handle handle))))
                   (setf active-custom-ui-state state)
                   (show-extension-overlay state)))))
         (set-extension-header (factory)
           (let ((previous (tui-state-header-component state))
                 (replacement
                   (and factory
                        (funcall factory
                                 (extension-runtime)
                                 (extension-theme-runtime)))))
             (when (and replacement
                        (not (tui-component-protocol-p replacement)))
               (error 'cadr-agent:extension-execution-error
                      :message "Header factory must return a CADR-TUI:COMPONENT"))
             (unless (eq previous replacement)
               (dispose-component previous))
             (setf (tui-state-header-component state) replacement)
             (request-render)
             nil))
         (set-extension-footer (factory)
           (let ((previous (tui-state-footer-component state))
                 (replacement
                   (and factory
                        (funcall factory
                                 (extension-runtime)
                                 (extension-theme-runtime)
                                 footer-provider))))
             (when (and replacement
                        (not (tui-component-protocol-p replacement)))
               (error 'cadr-agent:extension-execution-error
                      :message "Footer factory must return a CADR-TUI:COMPONENT"))
             (unless (eq previous replacement)
               (dispose-component previous))
             (setf (tui-state-footer-component state) replacement)
             (request-render)
             nil))
         (set-extension-editor (factory)
           (let* ((current (current-editor))
                  (text (tui-editor-component-text current))
                  (replacement
                    (and factory
                         (funcall factory
                                  (extension-runtime)
                                  (extension-theme-runtime)
                                  (cadr-tui:get-keybindings)))))
             (when (and replacement
                        (not (tui-component-protocol-p replacement)))
               (error 'cadr-agent:extension-execution-error
                      :message "Editor factory must return a CADR-TUI:COMPONENT"))
             (when replacement
               (tui-editor-component-set-text replacement text))
             (when custom-editor-component
               (dispose-component custom-editor-component))
             (setf custom-editor-component replacement
                   custom-editor-factory factory)
             (unless replacement
               (tui-editor-component-set-text editor text))
             (request-render)
             nil))
         (show-extension-selection
             (title options &key message signal timeout-ms)
           (show-extension-overlay
            (make-framed-select-state
             title options options
             :message message
             :timeout-ms timeout-ms
             :toggle-tools-function
             (lambda ()
             (toggle-last-tool-block state)))
            :signal signal :timeout-ms timeout-ms))
         (show-runtime-auth-prompt (prompt)
           (case (getf prompt :type)
             (:select
              (let ((options (getf prompt :options)))
                (show-extension-overlay
                 (make-framed-select-state
                  (getf prompt :message)
                  (mapcar
                   (lambda (option)
                     (let ((description
                             (getf option :description)))
                       (if description
                           (format nil "~A · ~A"
                                   (getf option :label)
                                   description)
                           (getf option :label))))
                   options)
                  (mapcar
                   (lambda (option) (getf option :id))
                   options)
                  :message (getf prompt :placeholder)
                  :toggle-tools-function
                  (lambda ()
                    (toggle-last-tool-block state))))))
             ((:text :secret :manual-code)
              (show-extension-overlay
               (make-runtime-auth-input-state prompt)))
             (otherwise nil)))
         (add-extension-autocomplete-provider
             (factory)
           (let* ((target
                    (if (typep (current-editor)
                               'cadr-tui:multiline-editor)
                        (current-editor)
                        editor))
                  (current
                    (cadr-tui::multiline-editor-autocomplete-provider
                     target))
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
                target replacement)))
           nil)
         (extension-ui-call (method arguments)
           (case method
             (:select
              (show-extension-selection
               (getf arguments :title)
               (getf arguments :options)
               :signal (getf arguments :signal)
               :timeout-ms (getf arguments :timeout-ms)))
             (:confirm
              (show-extension-overlay
               (make-framed-select-state
                (getf arguments :title)
                '("Yes" "No") '(t nil)
                :message (getf arguments :message)
                :timeout-ms (getf arguments :timeout-ms)
                :toggle-tools-function
                (lambda ()
                  (toggle-last-tool-block state)))
               :signal (getf arguments :signal)
               :timeout-ms (getf arguments :timeout-ms)))
             (:custom
              (show-custom-ui
               (getf arguments :factory)
               (getf arguments :overlay-p)
               (getf arguments :overlay-options)))
             (:custom-component
              (show-custom-component-ui
               (getf arguments :factory)
               (getf arguments :overlay-p)
               (getf arguments :overlay-options)
               (getf arguments :on-handle)))
             (:input
              (show-extension-overlay
               (make-runtime-auth-input-state
                (list :type :text
                      :message (getf arguments :title)
                      :placeholder (getf arguments :placeholder)))
               :signal (getf arguments :signal)
               :timeout-ms (getf arguments :timeout-ms)))
             (:editor
              (let ((component (cadr-tui:make-multiline-editor)))
                (cadr-tui:editor-set-text
                 component (or (getf arguments :prefill) ""))
                (let ((custom-state
                        (make-extension-custom-ui-state
                         :component component
                         :done-function #'finish-custom-ui
                         :legacy-p t)))
                  (setf active-custom-ui-state custom-state)
                  (show-extension-overlay custom-state))))
             (:add-autocomplete-provider
              (add-extension-autocomplete-provider
               (getf arguments :factory)))
             (:append-custom-message
              (sb-thread:with-mutex (lock)
                (append-tui-entry
                 state
                 (make-tui-entry
                  :type :custom-message
                  :custom-type (getf arguments :custom-type)
                  :custom-payload (copy-tree arguments)
                  :custom-options
                  (list :expanded-p
                        (tui-state-tools-expanded-p state)
                        :output-pad 1))))
              (request-render)
              nil)
             (:append-custom-entry
              (sb-thread:with-mutex (lock)
                (append-tui-entry
                 state
                 (make-tui-entry
                  :type :custom-entry
                  :custom-type (getf arguments :custom-type)
                  :custom-payload (copy-tree arguments)
                  :custom-options
                  (list :expanded-p
                        (tui-state-tools-expanded-p state)))))
              (request-render)
              nil)
             (:notify
              (case (getf arguments :level)
                (:error
                 (show-error
                  (getf arguments :message)))
                (:warning
                 (warning
                  (getf arguments :message)))
                (otherwise
                 (status
                  (getf arguments :message))))
              nil)
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
                (tui-editor-component-set-text
                 (current-editor)
                 (getf arguments :text))
                (synchronize-tui-editor-input-border
                 state (current-editor)))
              (request-render)
              nil)
             (:get-editor-text
              (tui-editor-component-text (current-editor)))
             (:paste-to-editor
              (handle-tui-editor-event
               state (current-editor)
               (cadr-tui:make-input-event
                :kind :paste :text (getf arguments :text)))
              (request-render)
              nil)
             (:set-title
              (let ((title
                      (remove-if
                       (lambda (character)
                         (member character
                                 (list #\Escape (code-char 7))))
                       (getf arguments :title))))
                (cadr-tui:terminal-write
                 terminal
                 (format nil "~C]0;~A~C"
                         #\Escape title (code-char 7))))
              nil)
             (:set-header
              (set-extension-header (getf arguments :factory)))
             (:set-footer
              (set-extension-footer (getf arguments :factory)))
             (:set-editor-component
              (set-extension-editor (getf arguments :factory)))
             (:get-editor-component custom-editor-factory)
             (:set-working-visible
              (setf (tui-state-working-visible-p state)
                    (not (null (getf arguments :visible-p))))
              (request-render)
              nil)
             (:set-working-message
              (setf (tui-state-working-message state)
                    (getf arguments :message))
              (request-render)
              nil)
             (:set-working-indicator
              (setf
               (tui-state-working-indicator-frames state)
               (and (getf arguments :frames-supplied-p)
                    (copy-list (getf arguments :frames)))
               (tui-state-working-indicator-interval-ms state)
               (getf arguments :interval-ms))
              (request-render)
              nil)
             (:set-hidden-thinking-label
              (setf (tui-state-hidden-thinking-label state)
                    (getf arguments :label))
              (dolist (entry (tui-state-entries state))
                (invalidate-tui-entry-render-cache entry))
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
             (setf abort-requested-p nil)
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
                   (when (typep (current-editor)
                                'cadr-tui:multiline-editor)
                     (cadr-tui:editor-set-border-mode
                      (current-editor) :bash))
                   (when (typep (current-editor)
                                'cadr-tui:multiline-editor)
                     (cadr-tui:editor-set-border-mode
                      (current-editor) :thinking
                      (or
                       (tui-state-thinking state)
                       :off)))))
             (request-render)
             (setf
              worker
              (sb-thread:make-thread
               (lambda ()
                 (unwind-protect
                      (call-with-tui-command-error-notice
                       (lambda ()
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
                             (show-error
                              "Unknown command"))
                           (when
                               (and
                                (eq kind :command)
                                (stringp result)
                                (plusp
                                 (length result)))
                             (notice result))))
                       #'show-error)
                   (sb-thread:with-mutex (lock)
                     (setf busy-p nil
                           abort-requested-p nil)
                     (when (typep (current-editor)
                                  'cadr-tui:multiline-editor)
                       (cadr-tui:editor-set-border-mode
                        (current-editor) :thinking
                        (or
                         (tui-state-thinking state)
                         :off))))
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
               (status "No models available")))
         (open-trust-selector ()
           (setf
            overlay-kind :trust
            overlay
            (and trust-selector-function
                 (funcall trust-selector-function)))
           (if overlay
               (request-render)
               (status
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
               (status "Settings are unavailable")))
         (open-import-confirmation (line path)
           (setf
            overlay-kind :import-confirmation
            overlay
            (make-import-confirmation-list
             line path))
           (request-render))
         (open-login-method-selector ()
           (setf
            overlay-kind :login-method
            overlay
            (make-login-method-selector-state))
           (request-render))
         (open-login-provider-selector (auth-type)
           (let ((options
                   (if login-options-function
                       (remove-if-not
                        (lambda (option)
                          (eq auth-type
                              (oauth-selector-option-auth-type
                               option)))
                        (funcall login-options-function))
                       (login-provider-options
                        (cadr-ai:list-provider-definitions)
                        :auth-type auth-type
                        :status-function
                        auth-status-function))))
             (if options
                 (setf
                  overlay-kind :login-provider
                  overlay
                  (make-oauth-selector-state
                   :mode :login
                   :options options))
                 (status
                  "No login methods available")))
           (request-render))
         (open-logout-provider-selector ()
           (let ((options
                   (and logout-options-function
                        (funcall logout-options-function))))
             (if options
                 (progn
                   (setf
                    overlay-kind :logout-provider
                    overlay
                    (make-oauth-selector-state
                     :mode :logout
                     :options options))
                   (request-render))
                 (status
                  "No stored credentials to remove. /logout only removes credentials saved by /login; environment variables and models.json config are unchanged."))))
         (open-api-key-input (option)
           (setf
            overlay-kind :api-key-input
            overlay
            (make-api-key-input-state option))
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
                 (status
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
           (replace-tui-entries state nil)
           (setf
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
                      (success
                       "New session started")))))
               ((string= trimmed "/quit")
                (setf done-p t))
               ((string= trimmed "/trust")
                (open-trust-selector))
               ((string= trimmed "/settings")
                (open-settings-selector))
               ((string= trimmed "/login")
                (open-login-method-selector))
               ((string= trimmed "/logout")
                (open-logout-provider-selector))
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
               ((string= trimmed "/resume")
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
         (submit-follow-up ()
           (let ((text
                   (string-trim
                    '(#\Space #\Tab #\Newline #\Return)
                    (if (typep (current-editor)
                               'cadr-tui:multiline-editor)
                        (cadr-tui::editor-expanded-text
                         (current-editor))
                        (tui-editor-component-text
                         (current-editor))))))
             (when (plusp (length text))
               (when (typep (current-editor)
                            'cadr-tui:multiline-editor)
                 (cadr-tui:editor-add-history
                  (current-editor) text))
               (tui-editor-component-clear
                (current-editor))
               (if (and busy-p follow-up-input-function)
                   (funcall follow-up-input-function text)
                   (submit text))
               (request-render))))
         (restore-queued-messages (&key notify-p)
           (let* ((queued
                    (and dequeue-function
                         (funcall dequeue-function)))
                  (count
                    (restore-queued-messages-to-editor
                     (current-editor) queued)))
             (if (zerop count)
                 (when notify-p
                   (status "No queued messages to restore"))
                 (when notify-p
                   (status
                    (format
                     nil
                     "Restored ~D queued message~:P to editor"
                     count))))
             count))
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
                   (:login-method
                    (open-login-provider-selector value))
                   (:login-provider
                    (if
                        (eq
                         (oauth-selector-option-auth-type
                          value)
                         :oauth)
                        (start-work
                         (format
                          nil "/login ~(~A~)"
                          (oauth-selector-option-id value)))
                        (open-api-key-input value)))
                   (:logout-provider
                    (when on-logout-selected
                      (funcall
                       on-logout-selected
                       (oauth-selector-option-id value))
                      (status
                       (if
                           (eq
                            (oauth-selector-option-auth-type value)
                            :oauth)
                           (format nil "Logged out of ~A"
                                   (oauth-selector-option-name value))
                           (format nil
                                   "Removed stored API key for ~A. Environment variables and models.json config are unchanged."
                                   (oauth-selector-option-name value))))))
                   (:api-key-input
                    (let* ((option
                             (getf value :option))
                           (provider
                             (oauth-selector-option-id
                              option)))
                      (unless api-key-login-function
                        (error
                         'cadr-ai:configuration-error
                         :message
                         "API key login is unavailable"))
                      (funcall
                       api-key-login-function
                       provider
                       (getf value :key))
                      (status
                       (format
                        nil "Saved API key for ~A"
                        (oauth-selector-option-name
                         option)))))
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
                        (status "Import cancelled")))
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
                          (tui-editor-component-set-text
                           (current-editor)
                           (or editor-text ""))
                          (synchronize-tui-editor-input-border
                           state (current-editor))
                          (add-tui-status
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
               (error (condition)
                 (add-tui-error
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
                    "theme-preview")
                   preview-theme-function)
                (let ((summary
                        (funcall
                         preview-theme-function
                         (getf value :value))))
                  (sb-thread:with-mutex (lock)
                    (apply-tui-theme-summary summary)
                    (reset-theme-watcher summary))))
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
           (if (overlay-captures-input-p)
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
                             ((login-method-selector-state-p
                               overlay)
                              (login-method-selector-handle-event
                               overlay event))
                             ((api-key-input-state-p overlay)
                              (api-key-input-state-handle-event
                               overlay event))
                             ((runtime-auth-input-state-p overlay)
                              (runtime-auth-input-state-handle-event
                               overlay event))
                             ((oauth-selector-state-p overlay)
                              (oauth-selector-handle-event
                               overlay event))
                             ((extension-custom-ui-state-p
                               overlay)
                              (extension-custom-ui-handle-event
                               overlay event))
                             ((framed-select-state-p overlay)
                              (framed-select-state-handle-event
                               overlay event))
                             (t
                              (cadr-tui:select-list-handle-event
                               overlay event)))))
                 (handle-overlay-action
                  action value)
                 (request-render))
               (case (cadr-tui:input-event-kind event)
                 ((:escape :interrupt)
                  (if busy-p
                      (unless abort-requested-p
                        (setf abort-requested-p t)
                        (restore-queued-messages)
                        (when abort-function
                          (funcall abort-function)))
                      (progn
                        (handle-tui-editor-event
                         state (current-editor) event)
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
                           state (current-editor) event)
                          (setf last-clear-at now)
                          (request-render)))))
                 (:eof
                  (if
                      (zerop
                       (length
                        (tui-editor-component-text
                         (current-editor))))
                      (unless busy-p
                        (setf done-p t))
                      (progn
                        (handle-tui-editor-event
                         state (current-editor)
                         (cadr-tui:make-input-event
                          :kind :delete))
                        (request-render))))
                 (:toggle-tools
                  (toggle-last-tool-block state)
                  (request-render))
                 (:follow-up
                  (submit-follow-up))
                 (:dequeue
                  (restore-queued-messages :notify-p t)
                  (request-render))
                 (otherwise
                  (multiple-value-bind
                        (action value)
                      (handle-tui-editor-event
                       state (current-editor) event)
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
      (when set-status-consumer
        (funcall set-status-consumer
                 #'status))
      (when set-warning-consumer
        (funcall set-warning-consumer
                 #'warning))
      (when set-auth-url-consumer
        (funcall set-auth-url-consumer
                 #'show-auth-url))
      (when set-auth-prompt-consumer
        (funcall set-auth-prompt-consumer
                 #'show-runtime-auth-prompt))
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
                           :notice-function #'status))
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
                            ((and
                              (plusp (length input))
                              (framed-select-state-p overlay))
                             (framed-select-state-handle-raw-input
                              overlay input))
                            (t
                             (values nil nil nil)))
                        (if handled-p
                            (progn
                              (handle-overlay-action
                               action value)
                              (request-render))
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
                        (and
                         (typep (current-editor)
                                'cadr-tui:multiline-editor)
                         (sb-thread:with-mutex (lock)
                           (cadr-tui:editor-poll-autocomplete
                            (current-editor))))
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
        (when set-status-consumer
          (funcall set-status-consumer nil))
        (when set-auth-url-consumer
          (funcall set-auth-url-consumer nil))
        (when set-auth-prompt-consumer
          (funcall set-auth-prompt-consumer nil))
        (when set-model-consumer
          (funcall set-model-consumer nil))
        (when set-extension-ui-function
          (funcall set-extension-ui-function nil))
        (when footer-unsubscribe
          (funcall footer-unsubscribe))
        (dispose-component (tui-state-header-component state))
        (dispose-component (tui-state-footer-component state))
        (dispose-component custom-editor-component)
        (when extension-ui-root
          (cadr-tui:component-dispose extension-ui-root))
        (when footer-provider
          (footer-data-provider-dispose
           footer-provider))))
    state))
