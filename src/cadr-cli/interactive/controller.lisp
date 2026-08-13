(in-package #:cadr-cli)

(defvar *tui-mode-switch-hook* nil
  "When bound, called with the new tuiMode settings value to
live-switch the running renderer; returns true when the switch
happened.  pi@53fa77ccd interactive-mode.ts:4557-4567
onTuiModeChange.")

(defvar *alt-screen-flash-function* nil
  "When non-nil, called with a message string to show a transient
fullscreen flash instead of a status line (pi@53fa77ccd
interactive-mode.ts:5956-5960).")

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
    (write-char
     character
     (notification-stream-buffer stream)))
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

(defun call-with-tui-command-error-notice
    (function notice-function)
  (handler-case
      (funcall function)
    (cadr-ai:authentication-cancelled () nil)
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
     &key show-hardware-cursor-p
       clear-on-shrink-p
       (scrollbar-mode :auto))
  (cadr-tui:make-terminal-renderer
   terminal
   :alt-p alt-p
   :show-hardware-cursor-p
   show-hardware-cursor-p
   :clear-on-shrink-p clear-on-shrink-p
   :scrollbar-mode scrollbar-mode
   :open-url-function
   #'open-tui-url))

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

(defun sanitize-terminal-title-text (text)
  (coerce
   (remove-if
    (lambda (character)
      (member character
              (list #\Escape (code-char 7))))
    (or text ""))
   'string))

(defun tui-terminal-title-cwd-basename (cwd)
  (let* ((cwd-text
           (etypecase cwd
             (null "")
             (pathname (uiop:native-namestring cwd))
             (string cwd)))
         (trimmed
           (string-right-trim
            '(#\/ #\\)
            cwd-text))
         (separator
           (position-if
            (lambda (character)
              (or (char= character #\/)
                  (char= character #\\)))
            trimmed :from-end t)))
    (if separator
        (subseq trimmed (1+ separator))
        trimmed)))

(defun tui-terminal-title (cwd session-name)
  (let ((basename
          (tui-terminal-title-cwd-basename cwd))
        (clean-session
          (sanitize-terminal-title-text session-name)))
    (if (plusp (length clean-session))
        (format nil "cadr - ~A - ~A"
                clean-session basename)
        (format nil "cadr - ~A" basename))))

(defun tui-terminal-title-sequence (cwd session-name)
  (format nil "~C]0;~A~C"
          #\Escape
          (tui-terminal-title cwd session-name)
          (code-char 7)))

(defun run-tui
    (prompt-function
     &key
       command-function
       template-function
       bash-function
       set-event-consumer
       work-rendered-function
       set-notice-consumer
       set-status-consumer
       set-warning-consumer
       set-auth-url-consumer
       set-auth-event-consumer
       set-auth-prompt-consumer
       set-model-consumer
       set-extension-ui-function
       version-update-check-function
       package-update-check-function
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
       debug-messages-function
       busy-input-function
       follow-up-input-function
       dequeue-function
       cycle-model-function
       model-items-function
       login-options-function
       model-selector-function
       scoped-models-selector-function
       model-catalog-refresh-function
       apply-model-catalog-refresh-function
       trust-selector-function
       settings-selector-function
       mermaid-mode-function
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
       on-clone-session
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
       project-trust-warning
       initial-notices
       initial-statuses
       alt-p
       show-hardware-cursor-p
       clear-on-shrink-p
       (scrollbar-mode :auto)
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
            :mermaid-mode
            (if mermaid-mode-function
                (or (funcall mermaid-mode-function) "streaming")
                "streaming")
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
               :base-path cwd
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
            show-hardware-cursor-p
            :clear-on-shrink-p
            clear-on-shrink-p
            :scrollbar-mode scrollbar-mode))
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
         (login-provider-auth-type nil)
         (busy-p nil)
         (abort-requested-p nil)
         (done-p nil)
         (last-clear-at nil)
         (worker nil)
         (version-update-worker nil)
         (package-update-worker nil)
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
         (terminal-progress-active-p nil)
         (terminal-active-p nil)
         (last-terminal-title nil)
         (pending-work-render-p nil))
    (declare (ignore active-theme))
    (when project-trust-warning
      (add-tui-project-trust-warning
       state project-trust-warning))
    (dolist (text initial-notices)
      (add-tui-warning state text))
    (dolist (text initial-statuses)
      (add-tui-status state text))
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
           (let ((work-rendered-p nil))
             (sb-thread:with-mutex (lock)
               (multiple-value-bind
                     (lines cursor-row cursor-column)
                   (render-tui-state
                    state (current-editor)
                    (cadr-tui:terminal-columns terminal)
                    (cadr-tui:terminal-rows terminal)
                    :overlay overlay
                    :busy-p
                    (and
                     (tui-state-agent-working-p state)
                     ;; The settle window keeps the agent marked busy
                     ;; until agent_end, but the baseline never paints
                     ;; the loader there; omit it from these frames.
                     (not (tui-state-settle-window-p state)))
                    :extension-host extension-host
                    :full-document-p alt-p
                    :now (funcall clock-function)
                    :spinner-frame
                    (tui-status-animation-frame
                     status-animation))
                 (cadr-tui:render-frame
                  renderer lines
                  :cursor-row cursor-row
                  :cursor-column cursor-column
                  :overlay-active-p
                  (and
                   (extension-custom-ui-state-p overlay)
                   (extension-custom-ui-state-overlay-p overlay)
                   (extension-custom-ui-visible-p overlay)))
                 (setf
                  work-rendered-p pending-work-render-p
                  pending-work-render-p nil)))
             (when (and work-rendered-p
                        work-rendered-function)
               (funcall work-rendered-function))))
         (request-render (&optional force-p)
           (request-tui-render
            render-coordinator force-p))
         (synchronize-terminal-title ()
           (when terminal-active-p
             (let ((title
                     (tui-terminal-title
                      (or footer-cwd cwd)
                      (tui-state-session-name state))))
               (unless (string= title
                                (or last-terminal-title ""))
                 (cadr-tui:terminal-write
                  terminal
                  (format nil "~C]0;~A~C"
                          #\Escape title (code-char 7)))
                 (setf last-terminal-title title)))))
         (refresh-footer-state
             (&optional (refresh-session-state-p t))
           (when (and refresh-session-state-p
                      footer-state-function)
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
           (synchronize-terminal-title)
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
                      status-animation state
                      (tui-state-agent-working-p state)
                      (funcall clock-function)))))
             (when changed-p
               (request-render))))
         (notice (text)
           (sb-thread:with-mutex (lock)
             (add-tui-notice state text))
           (request-render))
         (status (text &optional (level :status))
           (case level
             (:error (show-error text))
             (:warning (warning text))
             (:success (success text))
             (:rich
              (sb-thread:with-mutex (lock)
                (add-tui-rich-command
                 state
                 (getf text :title)
                 (getf text :markdown)))
              (request-render))
             (otherwise
              (sb-thread:with-mutex (lock)
                (add-tui-status state text))
              (request-render))))
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
         (show-version-update (release)
           (let ((version
                   (and (hash-table-p release)
                        (cadr-ai::json-get
                         release "version")))
                 (note
                   (and (hash-table-p release)
                        (cadr-ai::json-get
                         release "note"))))
             (when (and (stringp version)
                        (plusp (length version)))
               (sb-thread:with-mutex (lock)
                 (add-tui-version-update-notification
                  state version
                  (and (stringp note) note)))
               (request-render))))
         (show-package-updates (packages)
           (when (and (listp packages)
                      packages
                      (every #'stringp packages))
             (sb-thread:with-mutex (lock)
               (add-tui-package-update-notification
                state packages))
             (request-render)))
         (show-auth-url (url)
           (sb-thread:with-mutex (lock)
             (add-tui-auth-url state url))
           (request-render))
         (handle-auth-event (event)
           ;; When the login dialog is open it owns every OAuth event, like
           ;; the baseline notifyAuthDialog.  Without the dialog, keep the
           ;; legacy transcript/status rendering.
           (if (and (eq overlay-kind :login-dialog)
                    (typep overlay 'login-dialog-state))
               (progn
                 (case (getf event :type)
                   (:auth-url
                    (login-dialog-show-auth
                     overlay
                     (getf event :url)
                     (getf event :instructions)))
                   (:device-code
                    (login-dialog-show-device-code
                     overlay
                     (getf event :verification-uri)
                     (getf event :user-code))
                    (login-dialog-show-waiting
                     overlay "Waiting for authentication..."))
                   (:info
                    (when (getf event :message)
                      (login-dialog-show-info
                       overlay
                       (getf event :message)
                       (getf event :links)
                       nil)))
                   (:progress
                    (when (getf event :message)
                      (login-dialog-show-progress
                       overlay (getf event :message)))))
                 (request-render))
               (case (getf event :type)
                 (:auth-url
                  (show-auth-url (getf event :url))
                  (when (getf event :instructions)
                    (status (getf event :instructions))))
                 (:device-code
                  (show-auth-url (getf event :verification-uri))
                  (status
                   (format nil "Device code: ~A"
                           (getf event :user-code))))
                 ((:info :progress)
                  (when (getf event :message)
                    (status (getf event :message)))))))
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
               (stop-thread-for-cleanup monitor))
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
             (note-component-render-channel
              component #'request-render)
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
             (note-component-render-channel
              component #'request-render)
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
                (flet ((run-select ()
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
                  (if (and (eq overlay-kind :login-dialog)
                           (typep overlay 'login-dialog-state))
                      ;; Baseline showAuthSelect: the selector borrows the
                      ;; screen while the login dialog persists; resolving
                      ;; or cancelling the select restores the dialog so
                      ;; later auth events render inside it again.
                      (let ((dialog overlay))
                        (prog1 (run-select)
                          (sb-thread:with-mutex (lock)
                            (setf overlay-kind :login-dialog
                                  overlay dialog))
                          (request-render)))
                      (run-select)))))
             ((:text :secret :manual-code)
              (let ((cancelled-p-function
                      (getf prompt :cancelled-p-function)))
                (if (and (eq overlay-kind :login-dialog)
                         (typep overlay 'login-dialog-state))
                    (progn
                      (sb-thread:with-mutex (custom-ui-lock)
                        (setf custom-ui-done-p nil
                              custom-ui-result nil))
                      (if (eq (getf prompt :type) :manual-code)
                          (login-dialog-show-manual-input
                           overlay
                           (getf prompt :message)
                           (getf prompt :cancel-function))
                          ;; Baseline showPrompt: text and secret prompts
                          ;; append the message, an optional dim "e.g., ..."
                          ;; placeholder line, and the input to the dialog.
                          (login-dialog-show-prompt
                           overlay
                           (getf prompt :message)
                           (getf prompt :placeholder)
                           (getf prompt :cancel-function)))
                      (request-render)
                      ;; Same blocking contract as SHOW-EXTENSION-OVERLAY:
                      ;; the worker-thread prompt function resumes when the
                      ;; dialog submit/cancel calls FINISH-CUSTOM-UI.
                      (sb-thread:with-mutex (custom-ui-lock)
                        (loop until custom-ui-done-p
                              do
                              (sb-thread:condition-wait
                               custom-ui-condition
                               custom-ui-lock))
                        custom-ui-result))
                    (show-extension-overlay
                     (make-runtime-auth-input-state prompt)
                     :signal
                     (and cancelled-p-function
                          (cadr-agent:make-extension-cancellation-signal
                           :aborted-function cancelled-p-function))))))
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
              (let* ((component
                       (make-extension-input-dialog
                        (getf arguments :title)))
                     (custom-state
                       (make-extension-custom-ui-state
                        :component component
                        :done-function #'finish-custom-ui
                        :legacy-p t)))
                (setf active-custom-ui-state custom-state)
                (show-extension-overlay
                 custom-state
                 :signal (getf arguments :signal)
                 :timeout-ms (getf arguments :timeout-ms))))
             (:editor
              (let ((component
                      (make-extension-editor-dialog
                       (getf arguments :title)
                       (getf arguments :prefill))))
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
                      (sanitize-terminal-title-text
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
           (let ((event-type
                   (cadr-agent:agent-event-type event)))
             (when (synchronize-terminal-progress-setting)
               (case
                   event-type
                 ((:agent-start :compaction-start)
                  (set-terminal-progress-state t))
                 ((:agent-end :compaction-end)
                  (set-terminal-progress-state nil))))
             (sb-thread:with-mutex (lock)
               (if
                   (and
                    (eq :compaction-end event-type)
                    (null
                     (cadr-agent:agent-event-error-message
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
             ;; MESSAGE-END is emitted before Cadr persists the final
             ;; assistant message.  Preserve the event-local usage until the
             ;; subsequent turn/agent event can read the committed session.
             (refresh-footer-state
              (not (eq :message-end event-type)))))
         (start-work (line)
           (unless busy-p
             (let ((live-bash-entry nil)
                   (work-kind nil))
               (setf abort-requested-p nil)
               (when reset-abort-function
                 (funcall reset-abort-function))
               (sb-thread:with-mutex (lock)
                 (setf busy-p t)
                 (multiple-value-bind
                       (bash-command exclude-p present-p)
                     (parse-user-bash-input line)
                   (when (and bash-function present-p)
                     (setf
                      live-bash-entry
                      (append-tui-user-bash-running
                       state bash-command exclude-p))))
               (when (typep (current-editor)
                            'cadr-tui:multiline-editor)
                 (cadr-tui:editor-set-border-mode
                  (current-editor) :thinking
                  (or
                   (tui-state-thinking state)
                   :off))))
               (request-render)
               (setf
                worker
                (sb-thread:make-thread
                 (lambda ()
                   (unwind-protect
                        (let
                            ((*bash-live-output*
                               (and
                                live-bash-entry
                                (make-notification-output-stream
                                 (lambda (chunk)
                                   (sb-thread:with-mutex (lock)
                                     (append-tui-user-bash-output
                                      live-bash-entry chunk))
                                   (request-render))))))
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
                           (setf work-kind kind)
                           (when
                               (eq kind
                                   :unknown-command)
                             (show-error
                              "Unknown command"))
                           (cond
                             ((and (eq kind :bash)
                                   (user-bash-result-p result))
                              (sb-thread:with-mutex (lock)
                                (if live-bash-entry
                                    (complete-tui-user-bash-entry
                                     live-bash-entry result)
                                    (append-tui-user-bash-result
                                     state result)))
                              (request-render))
                             ((and (eq kind :bash)
                                   live-bash-entry
                                   (stringp result))
                              (sb-thread:with-mutex (lock)
                                (complete-tui-user-bash-string
                                 live-bash-entry result))
                              (request-render))
                             ((and
                               (eq kind :command)
                               (stringp result)
                               (plusp (length result)))
                              (notice result)))))
                           #'show-error))
                     (sb-thread:with-mutex (lock)
                       (when
                           (and live-bash-entry
                                (getf
                                 (tui-entry-custom-options live-bash-entry)
                                 :running-p))
                         (stop-tui-user-bash-entry live-bash-entry))
                       (when (eq overlay-kind :login-dialog)
                         (setf overlay nil
                               overlay-kind nil))
                       (setf busy-p nil
                             abort-requested-p nil)
                       (when (typep (current-editor)
                                    'cadr-tui:multiline-editor)
                         (cadr-tui:editor-set-border-mode
                          (current-editor) :thinking
                          (or
                           (tui-state-thinking state)
                           :off))))
                     (request-render)
                     (refresh-footer-state)
                     ;; The render-diff harness needs a causal acknowledgement
                     ;; after all worker cleanup state has been applied.  The
                     ;; optional callback is absent in production; when set,
                     ;; repaint the visible region canonically (in place,
                     ;; scrollback intact) so the final checkpoint is a
                     ;; canonical redraw rather than a product of
                     ;; partial-update scheduling.
                     (when (and work-rendered-function
                                (eq work-kind :prompt))
                       (sb-thread:with-mutex (lock)
                         (setf pending-work-render-p t)
                         (cadr-tui:renderer-request-canonical-repaint
                          renderer))
                       (request-render t))))
                 :name "cadr-tui-dispatch")))))
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
                 (request-render)
                 (start-model-catalog-refresh overlay))
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
           (when overlay
             (request-render)
             (start-model-catalog-refresh overlay)))
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
         (current-login-options ()
           (if login-options-function
               (funcall login-options-function)
               (login-provider-options
                (cadr-ai:list-provider-definitions)
                :status-function auth-status-function)))
         (start-login-option (option)
           (setf login-provider-auth-type nil)
           (cond
             ((eq :oauth
                  (oauth-selector-option-auth-type option))
              (setf overlay-kind :login-dialog
                    overlay
                    (make-login-dialog-state
                     (oauth-selector-option-name option)))
              (start-work
               (format nil "/login ~(~A~)"
                       (oauth-selector-option-id option))))
             ((oauth-selector-option-structured-login-p option)
              ;; Baseline showApiKeyLoginDialog: structured API key flows
              ;; (Bedrock, Vertex) run inside the login dialog through the
              ;; auth interaction; Bedrock opens with its details block.
              (setf overlay-kind :login-dialog
                    overlay
                    (make-login-dialog-state
                     (oauth-selector-option-name option)))
              (when (eq :amazon-bedrock
                        (oauth-selector-option-id option))
                (login-dialog-show-details
                 overlay
                 (list
                  (list :text
                        "You can also use an AWS profile, IAM keys, or role-based credentials.")
                  (list :muted "See:")
                  (list :accent
                        (format
                         nil "  ~A"
                         (namestring
                          (merge-pathnames
                           "providers.md"
                           (docs-directory))))))))
              (start-work
               (format nil "/login ~(~A~)"
                       (oauth-selector-option-id option))))
             (t
              (open-api-key-input option))))
         (open-login-method-selector
             (&optional (provider-options nil provider-options-p))
           (multiple-value-bind (action value)
               (login-auth-type-route
                provider-options
                :generic-p (not provider-options-p))
             (case action
               (:none
                (status value))
               (:direct
                (start-login-option value))
               (:select
                (setf
                 login-provider-auth-type nil
                 overlay-kind :login-method
                 overlay value)
                (request-render)))))
         (open-login-provider-selector
             (auth-type &optional (query ""))
           (let ((options
                   (remove-if-not
                    (lambda (option)
                      (or
                       (null auth-type)
                       (eq auth-type
                           (oauth-selector-option-auth-type
                            option))))
                    (current-login-options))))
             (if options
                 (setf
                  login-provider-auth-type auth-type
                  overlay-kind :login-provider
                  overlay
                  (make-oauth-selector-state
                   :mode :login
                   :options options
                   :query query))
                 (status
                  (case auth-type
                    (:oauth
                     "No subscription providers available.")
                    (:api-key
                     "No API key providers available.")
                    (otherwise
                     "No login providers available.")))))
           (request-render))
         (open-login-for-reference (provider-ref)
           (let* ((normalized
                    (string-downcase
                     (string-trim
                      '(#\Space #\Tab #\Newline #\Return)
                      provider-ref)))
                  (alias-id
                    (ignore-errors
                      (parse-auth-provider normalized)))
                  (matches
                    (remove-if-not
                     (lambda (option)
                       (or
                        (and
                         alias-id
                         (eq alias-id
                             (oauth-selector-option-id option)))
                        (string=
                         normalized
                         (string-downcase
                          (provider-key
                           (oauth-selector-option-id option))))
                        (string=
                         normalized
                         (string-downcase
                          (oauth-selector-option-name option)))))
                     (current-login-options))))
             (cond
               ((= 1 (length matches))
                (start-login-option (first matches)))
               ((and
                 (> (length matches) 1)
                 (= 1
                    (length
                     (remove-duplicates
                      matches
                      :key #'oauth-selector-option-id
                      :test #'equal))))
                (open-login-method-selector matches))
               (t
                (open-login-provider-selector nil provider-ref)))))
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
               ((and (string= trimmed "/clone")
                     on-clone-session)
                (multiple-value-bind
                      (selected-session
                       selected-messages
                       selected-path)
                    (funcall on-clone-session)
                  (when selected-session
                    (replace-session-state
                     selected-session
                     selected-messages
                     selected-path)
                    (status
                     "Cloned to new session"))))
               ((string= trimmed "/new")
                (start-new-session))
               ((string= trimmed "/quit")
                (setf done-p t))
               ((string= trimmed "/debug")
                (handle-debug-command))
               ((string= trimmed "/trust")
                (open-trust-selector))
               ((string= trimmed "/settings")
                (open-settings-selector))
               ((string= trimmed "/login")
                (open-login-method-selector))
               ((uiop:string-prefix-p "/login " trimmed)
                (open-login-for-reference
                 (string-trim
                  '(#\Space #\Tab)
                  (subseq trimmed (length "/login ")))))
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
         (start-new-session ()
           ;; Baseline handleClearCommand: shared by /new and the
           ;; app.session.new keybinding action.
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
         (handle-debug-command ()
           ;; Baseline handleDebugCommand
           ;; (interactive-mode.ts:5923-5953): dump every rendered line
           ;; with its visible width plus the session messages as JSONL,
           ;; then confirm with an accent check line and the muted path.
           (let* ((width (cadr-tui:terminal-columns terminal))
                  (height (cadr-tui:terminal-rows terminal))
                  (lines
                    (render-tui-state
                     state (current-editor) width height
                     :overlay overlay
                     :busy-p (tui-state-agent-working-p state)
                     :extension-host extension-host
                     :full-document-p t
                     :now (funcall clock-function)
                     :spinner-frame
                     (tui-status-animation-frame status-animation)))
                  (debug-path
                    (cadr-core:agent-debug-log-path))
                  (messages-jsonl
                    (and debug-messages-function
                         (funcall debug-messages-function))))
             (ensure-directories-exist debug-path)
             (cadr-core:atomic-write-string
              debug-path
              (with-output-to-string (out)
                (format out "Debug output at ~A~%"
                        (cadr-core:current-utc-iso8601))
                (format out "Terminal: ~Dx~D~%" width height)
                (format out "Total lines: ~D~2%" (length lines))
                (format out "=== All rendered lines with visible widths ===~%")
                (loop for line in lines
                      for index from 0
                      do
                      (format out "[~D] (w=~D) " index
                              (cadr-tui:visible-width line))
                      (cadr-ai::write-json-string line out)
                      (terpri out))
                (format out "~%=== Agent messages (JSONL) ===~%")
                (when messages-jsonl
                  (write-string messages-jsonl out))
                (terpri out)))
             (add-tui-debug-written
              state (namestring debug-path))
             (request-render)))
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
         (cycle-model (direction)
           (when cycle-model-function
             (handler-case
                 (let ((message
                         (funcall cycle-model-function direction)))
                   (when (and (stringp message)
                              (plusp (length message)))
                     (status message)))
               (error (condition)
                 (show-error (princ-to-string condition)))))
           (refresh-footer-state))
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
                    (if (typep value 'oauth-selector-option)
                        (start-login-option value)
                        (open-login-provider-selector value)))
                   (:login-provider
                    (start-login-option value))
                   (:logout-provider
                    (when on-logout-selected
                      (multiple-value-bind (provider sync-error)
                          (funcall
                           on-logout-selected
                           (oauth-selector-option-id value))
                        (declare (ignore provider))
                        (if sync-error
                            ;; pi@53fa77ccd interactive-mode.ts:5399 —
                            ;; the synchronization failure replaces the
                            ;; success status.
                            (show-error
                             (format
                              nil
                              "Credentials removed for ~A, but local model state could not be synchronized: ~A"
                              (oauth-selector-option-name value)
                              sync-error))
                            (status
                             (if
                                 (eq
                                  (oauth-selector-option-auth-type value)
                                  :oauth)
                                 (format nil "Logged out of ~A"
                                         (oauth-selector-option-name value))
                                 (format nil
                                         "Removed stored API key for ~A. Environment variables and models.json config are unchanged."
                                         (oauth-selector-option-name value))))))))
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
                      (multiple-value-bind (selection auth-path sync-error)
                          (funcall
                           api-key-login-function
                           provider
                           (getf value :key))
                        (if sync-error
                            ;; pi@53fa77ccd interactive-mode.ts:5548 —
                            ;; the synchronization failure replaces the
                            ;; success status.
                            (show-error
                             (format
                              nil
                              "Saved API key for ~A, but local model state could not be synchronized: ~A"
                              (oauth-selector-option-name
                               option)
                              sync-error))
                            (progn
                              ;; Baseline completeProviderAuthentication text.
                              (status
                               (format
                                nil
                                "Saved API key for ~A.~@[ Selected ~A.~] Credentials saved to ~A"
                                (oauth-selector-option-name
                                 option)
                                (and (stringp selection) selection)
                                auth-path))
                              (when (eq selection :no-default-model)
                                (error
                                 'cadr-ai:configuration-error
                                 :message
                                 (format
                                  nil
                                  "Saved API key for ~A, but no default model is configured for provider \"~(~A~)\". Use /model to select a model."
                                  (oauth-selector-option-name
                                   option)
                                  provider))))))))
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
         (switch-tui-mode (mode)
           ;; pi@53fa77ccd interactive-mode.ts:788-832 switchTuiMode +
           ;; :4557-4567 onTuiModeChange.  The baseline guard ("Close
           ;; active overlays before changing TUI mode") requires a
           ;; stacked overlay above the settings selector; cadr's
           ;; single-overlay model replaces the selector instead, so
           ;; the guard state is unreachable here.
           (let ((fullscreen-p (string= mode "fullscreen")))
             (cond
               ((eq fullscreen-p alt-p) t)
               (fullscreen-p
                (cadr-tui:renderer-enter-alt-screen-live renderer)
                (setf alt-p t)
                (request-render t)
                (status (format nil "TUI mode: ~A" mode))
                t)
               (t
                (cadr-tui:renderer-exit-alt-screen-live renderer)
                (setf alt-p nil)
                (request-render t)
                (status (format nil "TUI mode: ~A" mode))
                t))))
         (start-model-catalog-refresh (selector)
           ;; Baseline selector-open lifecycle: the selector renders the
           ;; cached snapshot with a "Refreshing model catalogs…" status
           ;; row, the registry re-read runs on this worker, and the
           ;; terminal status is applied only while the same selector is
           ;; still open (the baseline's disposed flag).
           (when
               (and model-catalog-refresh-function
                    apply-model-catalog-refresh-function
                    selector)
             (sb-thread:make-thread
              (lambda ()
                (let ((failure nil))
                  (handler-case
                      (funcall model-catalog-refresh-function)
                    (condition (condition)
                      (setf failure (princ-to-string condition))))
                  (sb-thread:with-mutex (lock)
                    (when (eq selector overlay)
                      (funcall
                       apply-model-catalog-refresh-function
                       selector failure)))
                  (request-render)))
              :name "cadr-model-catalog-refresh")))
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
                                 all-session-items-function
                                 (lambda (loaded total)
                                   (sb-thread:with-mutex (lock)
                                     (session-selector-note-load-progress
                                      selector token loaded total))
                                   (request-render))))))
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
              (if (eq overlay-kind :login-dialog)
                  (progn
                    (login-dialog-complete-input overlay value)
                    (finish-custom-ui value)
                    (request-render))
                  (accept-selection value)))
             (:cancel
              (let ((cancelled-kind overlay-kind)
                     (return-to-login-method-p
                      (and
                       (eq overlay-kind :login-provider)
                       login-provider-auth-type)))
                ;; Clear the visible overlay before waking a blocked extension
                ;; UI caller.  That caller may synchronously open the next
                ;; surface as soon as FINISH-CUSTOM-UI broadcasts; clearing it
                ;; afterwards would clobber the replacement overlay.
                (setf overlay nil
                      overlay-kind nil)
                (when
                    (eq cancelled-kind
                        :extension-custom)
                  (finish-custom-ui nil))
                (cond
                  ((eq cancelled-kind :login-dialog)
                   (unless abort-requested-p
                     (setf abort-requested-p t)
                     (when abort-function
                       (funcall abort-function)))
                   (finish-custom-ui nil)
                   (request-render))
                  (return-to-login-method-p
                   (open-login-method-selector))
                  ((eq cancelled-kind
                       :import-confirmation)
                   (status "Import cancelled"))
                  (t
                   (request-render)))))
             (:load-all
              (start-all-session-load
               overlay value)
              (request-render))
             (:changed
              (when (eq overlay-kind :scoped-models)
                (setf
                 (tui-state-multiple-providers-p state)
                 (> (scoped-models-selector-provider-count
                     overlay)
                    1))
                (refresh-footer-state))
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
                (when
                    (and value
                         (string=
                          (getf value :id)
                          "clear-on-shrink"))
                  (cadr-tui:renderer-set-clear-on-shrink
                   renderer (getf value :value)))
                (when
                    (and value
                         (string=
                          (getf value :id)
                          "mermaid-rendering"))
                  (setf (tui-state-mermaid-mode state)
                        (or (getf value :value) "streaming"))
                  (dolist (entry (tui-state-entries state))
                    (invalidate-tui-entry-render-cache entry)
                    (setf (tui-entry-markdown-cache entry) nil)))
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
                             ((login-dialog-state-p overlay)
                              (login-dialog-state-handle-event
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
                  (status
                   (format
                    nil "Tool output: ~A"
                    (if
                        (tui-state-tools-expanded-p state)
                        "expanded"
                        "collapsed"))))
                 (:debug
                  (handle-debug-command))
                 (:session-new
                  (start-new-session))
                 (:session-tree
                  (open-tree-selector))
                 (:session-fork
                  (open-fork-selector))
                 (:session-resume
                  (open-selector
                   :session
                   (if session-items-function
                       (funcall
                        session-items-function)
                       nil)))
                 (:follow-up
                  (submit-follow-up))
                 (:dequeue
                  (restore-queued-messages :notify-p t)
                  (request-render))
                 (:model-cycle-forward
                  (cycle-model :forward))
                 (:model-cycle-backward
                  (cycle-model :backward))
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
      (when set-auth-event-consumer
        (funcall set-auth-event-consumer
                 #'handle-auth-event))
      (when set-auth-prompt-consumer
        (funcall set-auth-prompt-consumer
                 #'show-runtime-auth-prompt))
      (when set-model-consumer
        (funcall set-model-consumer
                 #'show-model))
      (when set-extension-ui-function
        (funcall set-extension-ui-function
                 #'extension-ui-call))
      (when version-update-check-function
        (setf
         version-update-worker
         (sb-thread:make-thread
          (lambda ()
            (handler-case
                (show-version-update
                 (funcall
                  version-update-check-function))
              (condition () nil)))
          :name "cadr-version-update-check")))
      (when package-update-check-function
        (setf
         package-update-worker
         (sb-thread:make-thread
          (lambda ()
            (handler-case
                (show-package-updates
                 (funcall
                  package-update-check-function))
              (condition () nil)))
          :name "cadr-package-update-check")))
      (setf *tui-mode-switch-hook* #'switch-tui-mode
            *alt-screen-flash-function*
            (and alt-p
                 (lambda (message)
                   (cadr-tui:renderer-flash renderer message)
                   (request-render))))
      (unwind-protect
           (cadr-tui:call-with-terminal
            terminal
            (lambda ()
              (setf terminal-active-p t)
              (synchronize-terminal-title)
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
              (setf terminal-active-p nil)
              (when terminal-progress-active-p
                (set-terminal-progress-state nil))
              (cadr-tui:renderer-before-stop
               renderer))
            :after-stop
            (lambda ()
              (cadr-tui:renderer-after-stop
               renderer)))
        (setf *tui-mode-switch-hook* nil
              *alt-screen-flash-function* nil)
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
          (stop-thread-for-cleanup worker))
        (when
            (and session-loader-worker
                 (sb-thread:thread-alive-p
                  session-loader-worker))
          (stop-thread-for-cleanup
           session-loader-worker))
        (dolist (update-worker
                 (list version-update-worker
                       package-update-worker))
          (when (and update-worker
                     (sb-thread:thread-alive-p
                      update-worker))
            (stop-thread-for-cleanup
             update-worker)))
        (when set-event-consumer
          (funcall set-event-consumer nil))
        (when set-notice-consumer
          (funcall set-notice-consumer nil))
        (when set-status-consumer
          (funcall set-status-consumer nil))
        (when set-auth-url-consumer
          (funcall set-auth-url-consumer nil))
        (when set-auth-event-consumer
          (funcall set-auth-event-consumer nil))
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
