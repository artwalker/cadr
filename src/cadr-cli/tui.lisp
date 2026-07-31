(in-package #:cadr-cli)

(defstruct tui-entry
  type
  (text "" :type string)
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
  session
  (entries nil :type list)
  current-assistant
  (input-tokens 0 :type (integer 0 *))
  (output-tokens 0 :type (integer 0 *))
  (cache-tokens 0 :type (integer 0 *))
  (cost 0d0 :type double-float)
  (cost-known-p nil :type boolean)
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

(defun make-tui-state (&key model session messages)
  (let ((state
          (%make-tui-state
           :model (or model "—")
           :session session)))
    (dolist (message messages)
      (seed-tui-message state message))
    state))

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

(defun render-tui-status-indicator
    (message width)
  (let ((blank
          (make-string width
                       :initial-element #\Space)))
    (if message
        (list
         (cadr-tui:truncate-to-width
          (format nil "… ~A" message)
          width "")
         blank)
        (list blank blank))))

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
         (cost (cadr-ai:usage-cost usage)))
    (incf (tui-state-input-tokens state)
          (cadr-ai:usage-input usage))
    (incf (tui-state-output-tokens state)
          (cadr-ai:usage-output usage))
    (incf (tui-state-cache-tokens state)
          (+ (cadr-ai:usage-cache-read usage)
             (cadr-ai:usage-cache-write usage)))
    (when (assistant-price-known-p message)
      (setf (tui-state-cost-known-p state) t)
      (incf (tui-state-cost state)
            (cadr-ai:cost-total cost)))))

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
       :text (response-text message)))
     (accumulate-message-usage state message)))
  state)

(defun reset-tui-messages (state messages)
  (setf
   (tui-state-entries state) nil
   (tui-state-current-assistant state) nil
   (tui-state-input-tokens state) 0
   (tui-state-output-tokens state) 0
   (tui-state-cache-tokens state) 0
   (tui-state-cost state) 0d0
   (tui-state-cost-known-p state) nil)
  (dolist (message messages)
    (seed-tui-message state message))
  state)

(defun tool-arguments-summary (call)
  (handler-case
      (cadr-ai::stringify-json
       (cadr-ai:tool-call-arguments call))
    (condition ()
      (princ-to-string
       (cadr-ai:tool-call-arguments call)))))

(defun tool-result-text (result)
  (format
   nil "~{~A~^~%~}"
   (loop for block in
         (cadr-ai:tool-result-message-content result)
         when (typep block 'cadr-ai:text-content)
           collect (cadr-ai:text-content-text block))))

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
       compaction-tokens-before)
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
                    :type :assistant))))
            (setf
             (tui-state-current-assistant state)
             entry)))))
      (:message-update
       (when
           (and
            (tui-state-current-assistant state)
            stream-event
            (eq :text-delta
                (cadr-ai:stream-event-type
                 stream-event)))
         (setf
          (tui-entry-text
           (tui-state-current-assistant state))
          (concatenate
           'string
           (tui-entry-text
            (tui-state-current-assistant state))
           (or
            (cadr-ai:stream-event-delta
             stream-event)
            "")))))
      (:message-end
       (when (typep message 'cadr-ai:assistant-message)
         (let ((entry
                 (tui-state-current-assistant state)))
           (when (and entry
                      (zerop
                       (length
                        (tui-entry-text entry))))
             (setf
              (tui-entry-text entry)
              (response-text message))))
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
            (tool-result-text result)
            (cadr-tui:tool-block-status
             (tui-entry-tool-block entry))
            (if
                (cadr-ai:tool-result-message-is-error
                 result)
                :error
                :complete)
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
        nil)
       (when display-messages
         (reset-tui-messages
          state display-messages))
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

(defun render-tui-entry (entry width)
  (case (tui-entry-type entry)
    (:user
     (cadr-tui:wrap-text
      (format nil "you> ~A"
              (tui-entry-text entry))
      width))
    (:assistant
     (cadr-tui:render-markdown
      (tui-entry-text entry)
      width))
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
            width))))
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

(defun render-tui-state
    (state editor width rows
     &key overlay busy-p)
  (multiple-value-bind
        (editor-lines editor-row editor-column)
      (cadr-tui:render-editor editor width)
    (let* ((status-lines 3)
           (content-height
             (max 0
                  (- rows
                     status-lines
                     (length editor-lines))))
           (all-content
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
                        entry width))))
           (visible
             (if
                 (and
                  overlay
                  (plusp content-height)
                  (> (length all-content)
                     content-height))
                 (cons
                  (first all-content)
                  (trailing-lines
                   (rest all-content)
                   (1- content-height)))
                 (trailing-lines
                  all-content content-height)))
           (padding
             (make-list
              (max 0
                   (- content-height
                      (length visible)))
              :initial-element ""))
           (status
             (cadr-tui:render-status-bar
              width
              :model
              (if busy-p
                  (format nil "~A • working"
                          (tui-state-model state))
                  (tui-state-model state))
              :input
              (tui-state-input-tokens state)
              :output
              (tui-state-output-tokens state)
              :cache
              (tui-state-cache-tokens state)
              :cost
              (and
               (tui-state-cost-known-p state)
               (tui-state-cost state))
              :session
              (tui-state-session state))))
      (values
       (nconc padding visible
              (render-tui-status-indicator
               (tui-state-status-message state)
               width)
              (list status)
              editor-lines)
       (+ content-height
          status-lines
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
  '("ctrl+c" "ctrl+d" "ctrl+z"))

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

(defun run-tui
    (prompt-function
     &key
       command-function
       template-function
       bash-function
       set-event-consumer
       set-notice-consumer
       set-auth-url-consumer
       set-extension-ui-function
       theme-function
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
       session
       messages
       initial-notices
       (terminal
         (cadr-tui:make-process-terminal)))
  (let* ((state
           (make-tui-state
            :model model
            :session session
            :messages messages))
         (editor
           (let ((editor
                   (cadr-tui:make-multiline-editor)))
             (cadr-tui:editor-set-autocomplete-provider
              editor
              (make-tui-autocomplete-provider))
             editor))
         (decoder
           (cadr-tui:make-input-decoder))
         (renderer
           (cadr-tui:make-terminal-renderer
            terminal))
         (lock
           (sb-thread:make-mutex
            :name "cadr-tui-state"))
         (overlay nil)
         (overlay-kind nil)
         (busy-p nil)
         (done-p nil)
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
         (active-session-path current-session-path))
    (dolist (text initial-notices)
      (add-tui-notice state text))
    (labels
        ((render ()
           (sb-thread:with-mutex (lock)
             (multiple-value-bind
                   (lines cursor-row cursor-column)
                 (render-tui-state
                  state editor
                  (cadr-tui:terminal-columns terminal)
                  (cadr-tui:terminal-rows terminal)
                  :overlay overlay
                  :busy-p busy-p)
               (cadr-tui:render-frame
                renderer lines
                :cursor-row cursor-row
                :cursor-column cursor-column))))
         (notice (text)
           (sb-thread:with-mutex (lock)
             (add-tui-notice state text))
           (render))
         (show-auth-url (url)
           (sb-thread:with-mutex (lock)
             (add-tui-auth-url state url))
           (render))
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
               (render))
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
              (and set-theme-function
                   (funcall set-theme-function
                            (getf arguments :theme))))
             (:tools-expanded-p
              (tui-state-tools-expanded-p state))
             (:set-tools-expanded
              (set-tui-tools-expanded
               state
               (getf arguments :expanded-p))
              (render)
              nil)
             (otherwise nil)))
         (consume-event (event)
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
                    compaction-tokens-before))
                 (tui-handle-agent-event
                  state event
                  :extension-host extension-host)))
           (render))
         (start-work (line)
           (unless busy-p
             (when reset-abort-function
               (funcall reset-abort-function))
             (setf busy-p t)
             (render)
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
                   (setf busy-p nil)
                   (render)))
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
           (render))
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
               :keybindings
               (if tree-selector-keybindings-function
                   (funcall
                    tree-selector-keybindings-function)
                   tree-selector-keybindings)
               :copy-callback
               tree-copy-function
               :label-callback
               on-tree-label))
             (render)))
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
                 (render))
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
               (render)
               (notice "No models available")))
         (open-trust-selector ()
           (setf
            overlay-kind :trust
            overlay
            (and trust-selector-function
                 (funcall trust-selector-function)))
           (if overlay
               (render)
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
               (render)
               (notice "Settings are unavailable")))
         (open-import-confirmation (line path)
           (setf
            overlay-kind :import-confirmation
            overlay
            (make-import-confirmation-list
             line path))
           (render))
         (open-fork-selector ()
           (let ((items
                   (and fork-items-function
                        (funcall
                         fork-items-function))))
             (if items
                 (progn
                   (open-selector :fork items)
                   (setf
                    (cadr-tui::select-list-selected
                     overlay)
                    (1- (length items)))
                   (render))
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
            (tui-state-cache-tokens state)
            0
            (tui-state-cost state)
            0d0
            (tui-state-cost-known-p state)
            nil)
           (dolist (message selected-messages)
             (seed-tui-message state message)))
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
                           (render)
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
           (render))
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
                   (render))
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
              (render))
             (:load-all
              (start-all-session-load
               overlay value)
              (render))
             (otherwise
              (render))))
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
                 (:interrupt
                  (cond
                    (busy-p
                     (when abort-function
                       (funcall abort-function))
                     (notice "Abort requested"))
                    ((plusp
                      (length
                       (cadr-tui:editor-text
                        editor)))
                     (cadr-tui:editor-handle-event
                      editor
                      (cadr-tui:make-input-event
                       :kind :clear))
                     (render))
                    (t (setf done-p t))))
                 (:eof
                  (unless busy-p
                    (setf done-p t)))
                 (:toggle-tools
                  (toggle-last-tool-block state)
                  (render))
                 (otherwise
                  (multiple-value-bind
                        (action value)
                      (cadr-tui:editor-handle-event
                       editor event)
                    (if (eq action :submit)
                        (submit value)
                        (render))))))))
      (when set-event-consumer
        (funcall set-event-consumer
                 #'consume-event))
      (when set-notice-consumer
        (funcall set-notice-consumer
                 #'notice))
      (when set-auth-url-consumer
        (funcall set-auth-url-consumer
                 #'show-auth-url))
      (when set-extension-ui-function
        (funcall set-extension-ui-function
                 #'extension-ui-call))
      (unwind-protect
           (cadr-tui:call-with-terminal
            terminal
            (lambda ()
              (render)
              (loop until done-p
                    do
                    (when
                        (cadr-tui:terminal-resized-p
                         terminal)
                      (cadr-tui:invalidate-renderer
                       renderer)
                      (render))
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
                        (extension-shortcut
                         (cadr-agent::invoke-extension-shortcut
                          extension-host
                          (cadr-agent::extension-shortcut-definition-key
                           extension-shortcut))
                         (render))
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
                             (cadr-tui:terminal-stop
                              terminal))
                           (lambda ()
                             (cadr-tui:terminal-start
                              terminal)
                             (cadr-tui:invalidate-renderer
                              renderer))
                           #'render
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
                    (sleep 0.02))))
        (finish-custom-ui nil)
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
        (when set-extension-ui-function
          (funcall set-extension-ui-function nil))))
    state))
