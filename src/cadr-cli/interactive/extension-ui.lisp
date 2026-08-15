(in-package #:cadr-cli)

(defstruct extension-custom-ui-state
  component
  done-function
  (overlay-p nil :type boolean)
  overlay-options
  handle
  (legacy-p nil :type boolean)
  (disposed-p nil :type boolean))

(defclass extension-input-dialog (cadr-tui:component)
  ((title
    :initarg :title
    :reader extension-input-dialog-title)
   (input
    :initarg :input
    :reader extension-input-dialog-input)))

(defun make-extension-input-dialog (title)
  (make-instance
   'extension-input-dialog
   :title title
   :input (cadr-tui:make-single-line-input :prompt "> ")))

(defmethod cadr-tui:component-render
    ((dialog extension-input-dialog) width &key focused-p)
  (declare (ignore focused-p))
  (multiple-value-bind (input-lines input-row input-column)
      (cadr-tui:render-single-line-input
       (extension-input-dialog-input dialog)
       width)
    (let ((prefix
            (list
             (selector-border-line width)
             ""
             (selector-component-text-line
              (cadr-tui:theme-foreground
               :accent (extension-input-dialog-title dialog)
               :enabled-p t)
              width)
             "")))
      (values
       (append
        prefix input-lines
        (append
         (list "")
         (component-text-lines
          (format
           nil "~A  ~A"
           (selector-keybinding-hint
            (cadr-tui:get-keybindings)
            "tui.select.confirm" "submit")
           (selector-keybinding-hint
            (cadr-tui:get-keybindings)
            "tui.select.cancel" "cancel"))
          width)
         (list "" (selector-border-line width))))
       (+ (length prefix) input-row)
       input-column))))

(defmethod cadr-tui:component-handle-event
    ((dialog extension-input-dialog) event)
  (if (member (cadr-tui:input-event-kind event)
              '(:escape :cancel :interrupt))
      (values :cancel nil)
      (multiple-value-bind (action value)
          (cadr-tui:component-handle-event
           (extension-input-dialog-input dialog) event)
        (values (if (eq action :submit) :select action)
                value))))

(defclass extension-editor-dialog (cadr-tui:component)
  ((title
    :initarg :title
    :reader extension-editor-dialog-title)
   (editor
    :initarg :editor
    :reader extension-editor-dialog-editor)))

(defun make-extension-editor-dialog (title prefill)
  (let ((editor (cadr-tui:make-multiline-editor)))
    (cadr-tui:editor-set-text editor (or prefill ""))
    (make-instance
     'extension-editor-dialog
     :title title :editor editor)))

(defmethod cadr-tui:component-render
    ((dialog extension-editor-dialog) width &key focused-p)
  (declare (ignore focused-p))
  (multiple-value-bind (editor-lines editor-row editor-column)
      (cadr-tui:render-editor
       (extension-editor-dialog-editor dialog)
       width :focused-p t)
    (let ((prefix
            (list
             (selector-border-line width)
             ""
             (selector-component-text-line
              (cadr-tui:theme-foreground
               :accent (extension-editor-dialog-title dialog)
               :enabled-p t)
              width)
             "")))
      (values
       (append
        prefix editor-lines
        (append
         (list "")
         (component-text-lines
          (format
           nil "~A  ~A  ~A  ~A"
           (selector-keybinding-hint
            (cadr-tui:get-keybindings)
            "tui.select.confirm" "submit")
           (selector-keybinding-hint
            (cadr-tui:get-keybindings)
            "tui.input.newLine" "newline")
           (selector-keybinding-hint
            (cadr-tui:get-keybindings)
            "tui.select.cancel" "cancel")
           (selector-keybinding-hint
            (cadr-tui:get-keybindings)
            "app.editor.external" "external editor"))
          width)
         (list "" (selector-border-line width))))
       (+ (length prefix) editor-row)
       editor-column))))

(defmethod cadr-tui:component-handle-event
    ((dialog extension-editor-dialog) event)
  (if (member (cadr-tui:input-event-kind event)
              '(:escape :cancel :interrupt))
      (values :cancel nil)
      (cadr-tui:component-handle-event
       (extension-editor-dialog-editor dialog) event)))

(defstruct (runtime-auth-input-state
            (:constructor %make-runtime-auth-input-state))
  prompt
  input)

(cadr-core:define-redacted-print-object
    (runtime-auth-input-state value stream)
  (format stream ":type ~A :input [REDACTED]"
          (getf (runtime-auth-input-state-prompt value) :type)))

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
      (progn
        (let ((cancel-function
                (getf
                 (runtime-auth-input-state-prompt state)
                 :cancel-function)))
          (when cancel-function
            (ignore-errors (funcall cancel-function))))
        (values :cancel nil))
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
         (manual-code-p
           (eq :manual-code (getf prompt :type)))
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
      (if manual-code-p
          (let* ((url-lines
                   (mapcar
                    (lambda (line)
                      (selector-component-text-line line width))
                    (render-auth-url-lines
                     (getf prompt :url)
                     (max 1 (- width 2)))))
                 (prefix
                   (append
                    (list
                     (selector-border-line width)
                     (selector-component-text-line
                      (cadr-tui:theme-foreground
                       :accent
                       (cadr-tui:theme-bold
                        (getf prompt :title)
                        :enabled-p t)
                       :enabled-p t)
                      width)
                     "")
                    url-lines
                    (list "")
                    (component-text-lines
                     (cadr-tui:theme-foreground
                      :warning (getf prompt :instructions)
                      :enabled-p t)
                     width)
                    (list "")
                    (component-text-lines
                     (cadr-tui:theme-foreground
                      :dim (getf prompt :message)
                      :enabled-p t)
                     width))))
            (values
             (append
              prefix input-lines
              (list
               (selector-component-text-line
                (format
                 nil "(~A)"
                 (selector-keybinding-hint
                  (cadr-tui:get-keybindings)
                  "tui.select.cancel" "to cancel"))
                width)
               (selector-border-line width)))
             (+ (length prefix) row)
             column))
          (let ((prefix
                  (append
                   (list
                    (selector-border-line width)
                    (selector-component-text-line
                     (cadr-tui:theme-foreground
                      :accent
                      (cadr-tui:theme-bold
                       (getf prompt :message)
                       :enabled-p t)
                      :enabled-p t)
                     width))
                   (when (getf prompt :placeholder)
                     (list
                      (selector-component-text-line
                       (cadr-tui:theme-foreground
                        :dim (getf prompt :placeholder)
                        :enabled-p t)
                       width))))))
            (values
             (append
              prefix input-lines
              (list
               (selector-component-text-line
                (format
                 nil "(~A  ~A)"
                 (selector-keybinding-hint
                  (cadr-tui:get-keybindings)
                  "tui.select.cancel" "to cancel,")
                 (selector-keybinding-hint
                  (cadr-tui:get-keybindings)
                  "tui.select.confirm" "to submit"))
                width)
               (selector-border-line width)))
             (+ (length prefix) row)
             column))))))

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

(defun framed-select-title (state now)
  (let ((deadline (framed-select-state-deadline state))
        (base-title
          (if (framed-select-state-message state)
              (format nil "~A~%~A"
                      (framed-select-state-title state)
                      (framed-select-state-message state))
              (framed-select-state-title state))))
    (if deadline
        (format nil "~A (~Ds)"
                base-title
                (max 0 (ceiling (- deadline now))))
        base-title)))

(defun render-framed-select-state
    (state width &key (now (tui-monotonic-seconds)))
  (labels ((framed-text-lines (text)
             (component-text-lines text width :padding-x 1))
           (framed-title-lines ()
             (let* ((content-width (max 1 (- width 2)))
                    (lines
                      (mapcan
                       (lambda (line)
                         (cadr-tui:wrap-text line content-width))
                       (uiop:split-string
                        (framed-select-title state now)
                        :separator '(#\Newline))))
                    (last-index (1- (length lines))))
               (loop for line in lines
                     for index from 0
                     collect
                     (if (= index last-index)
                         (component-text-line
                          (cadr-tui:theme-foreground
                           :accent
                           (cadr-tui:theme-bold
                            line :enabled-p t)
                           :enabled-p t)
                          width :padding-x 1)
                         (concatenate
                          'string
                          " "
                          (cadr-tui:theme-foreground
                           :accent
                           (concatenate
                            'string
                            (cadr-tui:theme-bold
                             line :enabled-p t)
                            (make-string
                             (max 0
                                  (- width 1
                                     (cadr-tui:visible-width line)))
                             :initial-element #\Space))
                           :enabled-p t)))))))
    (append
     (list
      (cadr-tui:theme-foreground
       :border
       (make-string width :initial-element #\─))
      "")
     (framed-title-lines)
     (list "")
     (mapcan
      (lambda (line)
        (framed-text-lines
         (if (find #\Escape line)
             line
             (concatenate
              'string
              (subseq line 0 (min 2 (length line)))
              (cadr-tui:theme-foreground
               :text
               (subseq line (min 2 (length line)))
               :enabled-p t)))))
      (cadr-tui:render-select-list
       (framed-select-state-select-list state)
       (max 1 (- width 2))
       :ansi-theme-p t))
     (list "")
     (component-text-lines
      (concatenate
       'string
       (raw-key-hint "↑↓" "navigate") "  "
       (selector-keybinding-hint
        (framed-select-state-keybindings state)
        "tui.select.confirm" "select") "  "
       (selector-keybinding-hint
        (framed-select-state-keybindings state)
        "tui.select.cancel" "cancel"))
      width)
     (list
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

(defclass render-aware-component ()
  ((render-request-function
    :initform nil
    :accessor component-render-request-function))
  (:documentation
   "Mixin for extension custom components that mutate state from a
non-TUI thread (the baseline tui.requestRender() channel).  The host
injects the TUI render request when the component is shown."))

(defun note-component-render-channel (component request-render)
  (when (typep component 'render-aware-component)
    (setf
     (component-render-request-function component)
     request-render))
  component)

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
     ;; Unformatted Lisp values must not reach the transcript.
     nil)))

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
                  ;; Baseline skips custom entries with no renderer
                  ;; (interactive-mode.ts:3432-3434). princ-to-string of
                  ;; NIL here printed a bare "NIL" after /snake Q.
                  (:custom-entry nil))))
        (setf
         (tui-entry-custom-component entry) rendered
         (tui-entry-custom-component-theme entry) theme
         (tui-entry-custom-component-snapshot entry) snapshot
         (tui-entry-custom-component-options entry) options
         component rendered)))
    (when (typep component 'cadr-tui:component)
      (cadr-tui:component-invalidate component))
    (extension-render-value-lines component width)))

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

(defvar *tui-input-thread* nil
  "The thread that owns `run-tui`'s input/render loop. send-message
with trigger-turn must not call agent-prompt on this thread: the loop
only flush-renders after each input read, so a blocking turn freezes
the screen (goal 20 P0-4).")

(defun tui-input-thread-p ()
  (and *tui-input-thread*
       (eq sb-thread:*current-thread* *tui-input-thread*)))

(defun call-extension-host-turn-without-blocking-tui
    (start-turn-function thunk)
  "Run THUNK via START-TURN-FUNCTION when called from the TUI input
thread; otherwise run it inline. START-TURN-FUNCTION receives a
zero-argument function."
  (if (tui-input-thread-p)
      (funcall start-turn-function thunk)
      (funcall thunk)))

(defun wrap-extension-host-tui-turn-dispatch
    (host start-turn-function)
  "Make trigger-turn send-message/send-user-message return before the
LLM turn finishes when invoked from the TUI input thread.

Baseline `sendCustomMessage` is async; tic-tac-toe.ts does not await
it, so the TUI keeps painting streaming text and tool blocks. Cadr's
API is synchronous, so the same call used to run `agent-prompt` on the
input thread and hold `flush-render` for the whole turn.

Returns a restorer that puts the previous host functions back."
  (let ((previous-send
          (cadr-agent::extension-host-send-message-function host))
        (previous-user
          (cadr-agent::extension-host-send-user-message-function
           host)))
    (when previous-send
      (setf
       (cadr-agent::extension-host-send-message-function host)
       (lambda (message &key trigger-turn-p deliver-as)
         (if (and trigger-turn-p (null deliver-as) (tui-input-thread-p))
             (progn
               (call-extension-host-turn-without-blocking-tui
                start-turn-function
                (lambda ()
                  (funcall previous-send message
                           :trigger-turn-p t
                           :deliver-as nil)))
               message)
             (funcall previous-send message
                      :trigger-turn-p trigger-turn-p
                      :deliver-as deliver-as)))))
    (when previous-user
      (setf
       (cadr-agent::extension-host-send-user-message-function host)
       (lambda (content &key deliver-as)
         (if (and (null deliver-as) (tui-input-thread-p))
             (progn
               (call-extension-host-turn-without-blocking-tui
                start-turn-function
                (lambda ()
                  (funcall previous-user content :deliver-as nil)))
               content)
             (funcall previous-user content
                      :deliver-as deliver-as)))))
    (lambda ()
      (setf
       (cadr-agent::extension-host-send-message-function host)
       previous-send
       (cadr-agent::extension-host-send-user-message-function host)
       previous-user)
      nil)))
