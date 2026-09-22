(in-package #:cadr-agent)

(defvar *extension-registration-bundle* nil)
(defvar *extension-registration-api* nil)

;;; Immutable effective registry containers

(defstruct extension-snapshot
  (bundles nil :type list)
  (tools nil :type list)
  (commands nil :type list)
  (templates nil :type list)
  (native-providers nil :type list)
  (shortcuts nil :type list)
  (flags nil :type list)
  (message-renderers nil :type list)
  (markdown-transformers nil :type list)
  (entry-renderers nil :type list)
  (tool-renderers nil :type list)
  (hooks (make-hash-table :test #'eq) :type hash-table)
  (conflicts nil :type list)
  (active-count 0 :type (integer 0 *))
  (retired-p nil :type boolean)
  (released-p nil :type boolean))

(defstruct (extension-host
            (:constructor %make-extension-host))
  (cwd (uiop:getcwd) :type pathname)
  (mode :repl :type symbol)
  (notify-function
   (lambda (message level)
     (format *error-output*
             "~&extension[~(~A~)]> ~A~%"
             level message))
   :type function)
  reload-function
  ui-function
  send-message-function
  send-user-message-function
  set-session-name-function
  exec-function
  http-request-function
  action-function
  get-flag-function
  get-active-tools-function
  set-active-tools-function
  (flag-values (make-hash-table :test #'equal)
               :type hash-table)
  (active-tool-names nil :type list)
  (active-tools-overridden-p nil :type boolean)
  (attachment-generation 0 :type (integer 0 *))
  (session-started-p nil :type boolean)
  agent
  base-agent-model
  base-agent-provider
  (snapshot (make-extension-snapshot)
            :type extension-snapshot)
  (lock (sb-thread:make-mutex
         :name "cadr-extension-host"))
  (hook-lock (sb-thread:make-mutex
              :name "cadr-extension-hooks"))
  (event-listeners (make-hash-table :test #'equal)
                   :type hash-table)
  (event-lock (sb-thread:make-mutex
               :name "cadr-extension-events"))
  (ui-prompt-depth 0 :type (integer 0 *))
  active-ui-prompt
  (pending-custom-messages nil :type list))

;;; Public handler values

(defstruct (extension-context
            (:constructor %make-extension-context)
            (:conc-name %extension-context-))
  host
  source-path
  bundle
  kind
  (active-p t :type boolean))

(defstruct (extension-api
            (:constructor %make-extension-api)
            (:conc-name %extension-api-))
  host
  bundle
  (attachment-generation 0 :type (integer 0 *)))

(defstruct (extension-event
            (:constructor %make-extension-event)
            (:conc-name %extension-event-))
  type
  turn-index
  message
  tool-call
  tool-result
  tool-results
  appended-messages
  payload)

(defstruct (extension-cancellation-signal
            (:constructor %make-extension-cancellation-signal)
            (:conc-name %extension-cancellation-signal-))
  state
  abort-function)

(defun make-extension-cancellation-signal
    (&key aborted-function abort-function)
  (unless (or (null aborted-function)
              (functionp aborted-function))
    (error 'extension-execution-error
           :message "ABORTED-FUNCTION must be a function or NIL"))
  (unless (or (null abort-function)
              (functionp abort-function))
    (error 'extension-execution-error
           :message "ABORT-FUNCTION must be a function or NIL"))
  (%make-extension-cancellation-signal
   :state
   (cadr-core:make-cancellation-state
    :aborted-function aborted-function)
   :abort-function abort-function))

(defun extension-cancellation-aborted-p (signal)
  (unless (typep signal 'extension-cancellation-signal)
    (error
     'extension-execution-error
     :message "Expected an extension cancellation signal"))
  (cadr-core:cancellation-aborted-p
   (%extension-cancellation-signal-state signal)))

(defun abort-extension-cancellation-signal (signal)
  (unless (typep signal 'extension-cancellation-signal)
    (error
     'extension-execution-error
     :message "Expected an extension cancellation signal"))
  (cadr-core:abort-cancellation
   (%extension-cancellation-signal-state signal))
  (let ((function
          (%extension-cancellation-signal-abort-function signal)))
    (when function
      (funcall function)))
  signal)

(defstruct (extension-hook-result
            (:constructor %make-extension-hook-result))
  replacement
  (replacement-p nil :type boolean)
  (append-messages nil :type list)
  (block-p nil :type boolean)
  reason
  terminate-p
  (terminate-supplied-p nil :type boolean))

(defstruct extension-event-listener
  name
  handler
  bundle)

(defstruct (provider-request-replacement
            (:constructor
                make-provider-request-replacement
                (payload)))
  payload)

(defun make-extension-hook-result
    (&key
       (replacement nil replacement-p)
       append-messages
       block-p
       reason
       (terminate-p nil terminate-supplied-p))
  (%make-extension-hook-result
   :replacement replacement
   :replacement-p replacement-p
   :append-messages append-messages
   :block-p (not (null block-p))
   :reason reason
   :terminate-p (not (null terminate-p))
   :terminate-supplied-p terminate-supplied-p))

(defun assert-active-extension-context (context)
  (unless
      (and (typep context 'extension-context)
           (%extension-context-active-p context))
    (error
     'stale-extension-context
     :message
     "Extension context is stale outside its handler or after reload"))
  context)

(defun extension-context-cwd (context)
  (assert-active-extension-context context)
  (extension-host-cwd (%extension-context-host context)))

(defun extension-context-agent (context)
  (assert-active-extension-context context)
  (extension-host-agent (%extension-context-host context)))

(defun extension-context-session (context)
  (let ((agent (extension-context-agent context)))
    (and agent (agent-session agent))))

(defun extension-context-source-path (context)
  (assert-active-extension-context context)
  (%extension-context-source-path context))

(defun extension-context-mode (context)
  (assert-active-extension-context context)
  (extension-host-mode (%extension-context-host context)))

(defun extension-context-has-ui-p (context)
  (not (null (member (extension-context-mode context) '(:tui :rpc)))))

(defun invoke-extension-action (context action &rest arguments)
  (assert-active-extension-context context)
  (let* ((host (%extension-context-host context))
         (function (extension-host-action-function host)))
    (unless function
      (error 'extension-execution-error
             :message
             (format nil "Extension action ~(~A~) is unavailable in this host"
                     action)))
    (funcall function action arguments)))

(defun extension-context-model (context)
  (invoke-extension-action context :model))

(defun extension-context-scoped-models (context)
  (copy-list (or (invoke-extension-action context :scoped-models) nil)))

(defun extension-context-thinking-level (context)
  (invoke-extension-action context :thinking-level))

(defun extension-context-signal (context)
  (invoke-extension-action context :signal))

(defun extension-context-abort (context)
  (invoke-extension-action context :abort))

(defun extension-context-shutdown (context)
  (invoke-extension-action context :shutdown))

(defun extension-context-has-pending-messages-p (context)
  (not (null (invoke-extension-action context :has-pending-messages-p))))

(defun extension-context-context-usage (context)
  (invoke-extension-action context :context-usage))

(defun extension-context-system-prompt (context)
  (invoke-extension-action context :system-prompt))

(defun extension-command-context-system-prompt-options (context)
  (unless (eq (%extension-context-kind
               (assert-active-extension-context context))
              :command)
    (error 'extension-execution-error
           :message
           "get-system-prompt-options is only available to extension command contexts"))
  (invoke-extension-action context :system-prompt-options))

(defun extension-command-context-new-session
    (context &key parent-session setup-function with-session-function)
  (unless (eq (%extension-context-kind
               (assert-active-extension-context context))
              :command)
    (error 'extension-execution-error
           :message
           "new-session is only available to extension command contexts"))
  (invoke-extension-action
   context :new-session
   :parent-session parent-session
   :setup-function setup-function
   :with-session-function with-session-function
   :source-context context))

(defun extension-context-model-registry-find
    (context provider model-id)
  (invoke-extension-action context :model-registry-find provider model-id))

(defun extension-context-model-registry-resolve-auth
    (context model)
  (invoke-extension-action context :model-registry-resolve-auth model))

(defun extension-context-idle-p (context)
  (let ((agent (extension-context-agent context)))
    (or (null agent)
        (not (agent-busy-p agent)))))

(defun extension-command-context-wait-for-idle (context)
  (assert-active-extension-context context)
  (unless (eq (%extension-context-kind context) :command)
    (error
     'extension-execution-error
     :message
     "wait-for-idle is only available to extension command contexts"))
  (let ((agent (extension-context-agent context)))
    (unless agent
      (error
       'extension-execution-error
       :message
       "wait-for-idle requires an attached agent"))
    (agent-wait-for-idle agent)))

(defun extension-context-notify
    (context message &key (level :info))
  (assert-active-extension-context context)
  (unless (member level '(:info :warning :error))
    (error
     'extension-execution-error
     :message
     (format nil "Invalid extension notification level: ~S"
             level)))
  (let* ((host (%extension-context-host context))
         (ui-function
           (extension-host-ui-function host)))
    (if ui-function
        (funcall
         ui-function :notify
         (list
          :message (princ-to-string message)
          :level level))
        (funcall
         (extension-host-notify-function host)
         (princ-to-string message)
         level)))
  nil)

(defun extension-context-compact
    (context &key (force-p t))
  (let ((agent (extension-context-agent context)))
    (unless agent
      (error
       'extension-execution-error
       :message "Extension context has no attached agent"))
    (compact-agent agent :force-p force-p)))

(defun extension-context-reload (context)
  (assert-active-extension-context context)
  (let* ((host (%extension-context-host context))
         (reload (extension-host-reload-function host)))
    (unless reload
      (error
       'extension-execution-error
       :message "Extension reload is unavailable in this host"))
    (prog1
        (funcall reload)
      (setf (%extension-context-active-p context) nil))))

(defun validate-extension-ui-signal (signal)
  (unless
      (or
       (null signal)
       (typep signal 'extension-cancellation-signal))
    (error
     'extension-execution-error
     :message "UI signal must be an EXTENSION-CANCELLATION-SIGNAL or NIL"))
  signal)

(defun validate-extension-timeout (timeout-ms)
  (unless
      (or
       (null timeout-ms)
       (and (integerp timeout-ms)
            (not (minusp timeout-ms))))
    (error
     'extension-execution-error
     :message "UI timeout-ms must be a non-negative integer or NIL"))
  timeout-ms)

(defun invoke-extension-ui (context method arguments)
  (assert-active-extension-context context)
  (let* ((host (%extension-context-host context))
         (function (extension-host-ui-function host)))
    (if (and function
             (member method
                     '(:select :confirm :input :editor :custom)))
        (call-with-extension-ui-prompt
         host method (getf arguments :title)
         (lambda ()
           (funcall function method arguments)))
        (and function
             (funcall function method arguments)))))

(defun call-with-extension-ui-prompt (host kind title thunk)
  ;; pi@16787ad5b extensions/runner.ts withUIPrompt: nest prompts, emit
  ;; ui_prompt_start/end only on the outermost wait.
  (let ((outer-p
          (zerop (extension-host-ui-prompt-depth host))))
    (incf (extension-host-ui-prompt-depth host))
    (when outer-p
      (setf (extension-host-active-ui-prompt host)
            (list :kind kind :title title))
      (emit-ui-prompt-event host :ui-prompt-start kind title))
    (unwind-protect
         (funcall thunk)
      (when (plusp (extension-host-ui-prompt-depth host))
        (decf (extension-host-ui-prompt-depth host)))
      (when (zerop (extension-host-ui-prompt-depth host))
        (let ((prompt
                (or (extension-host-active-ui-prompt host)
                    (list :kind kind :title title))))
          (setf (extension-host-active-ui-prompt host) nil)
          (emit-ui-prompt-event
           host :ui-prompt-end
           (getf prompt :kind)
           (getf prompt :title)))))))

(defun emit-ui-prompt-event (host type kind title)
  (ignore-errors
    (run-extension-lifecycle-hooks
     host type
     :payload
     (append
      (list :reason :ui-prompt :kind kind)
      (and (stringp title)
           (plusp (length title))
           (list :title title))))))

(defun extension-context-select
    (context title options &key signal timeout-ms)
  (assert-active-extension-context context)
  (unless
      (and
       (stringp title)
       (typep options 'sequence)
       (every #'stringp options))
    (error
     'extension-execution-error
     :message "select requires a string title and a sequence of strings"))
  (validate-extension-ui-signal signal)
  (validate-extension-timeout timeout-ms)
  (invoke-extension-ui
   context :select
   (list
    :title title
    :options (coerce options 'list)
    :signal signal
    :timeout-ms timeout-ms)))

(defun extension-context-confirm
    (context title message &key signal timeout-ms)
  (assert-active-extension-context context)
  (unless (and (stringp title) (stringp message))
    (error
     'extension-execution-error
     :message "confirm requires string title and message values"))
  (validate-extension-ui-signal signal)
  (validate-extension-timeout timeout-ms)
  (not
   (null
    (invoke-extension-ui
     context :confirm
     (list
      :title title
      :message message
      :signal signal
      :timeout-ms timeout-ms)))))

(defun extension-context-input
    (context title &key placeholder signal timeout-ms)
  (assert-active-extension-context context)
  (unless
      (and
       (stringp title)
       (or (null placeholder) (stringp placeholder)))
    (error
     'extension-execution-error
     :message "input requires a string title and optional placeholder"))
  (validate-extension-ui-signal signal)
  (validate-extension-timeout timeout-ms)
  (invoke-extension-ui
   context :input
   (list
    :title title
    :placeholder placeholder
    :signal signal
    :timeout-ms timeout-ms)))

(defun extension-context-editor
    (context title &key prefill)
  (assert-active-extension-context context)
  (unless
      (and
       (stringp title)
       (or (null prefill) (stringp prefill)))
    (error
     'extension-execution-error
     :message "editor requires a string title and optional prefill"))
  (invoke-extension-ui
   context :editor
   (list :title title :prefill prefill)))

(defun extension-context-set-status (context key text)
  (assert-active-extension-context context)
  (unless
      (and
       (stringp key)
       (or (null text) (stringp text)))
    (error
     'extension-execution-error
     :message "set-status requires a string key and string or NIL text"))
  (invoke-extension-ui
   context :set-status
   (list :key key :text text))
  nil)

(defun extension-context-set-widget
    (context key lines &key (placement :above-editor))
  (assert-active-extension-context context)
  (unless
      (and
       (stringp key)
       (or
        (null lines)
        (and
         (typep lines 'sequence)
         (every #'stringp lines)))
       (member placement '(:above-editor :below-editor)))
    (error
     'extension-execution-error
     :message
     "set-widget requires a string key, string sequence or NIL, and valid placement"))
  (invoke-extension-ui
   context :set-widget
   (list
    :key key
    :lines (and lines (coerce lines 'list))
    :placement placement))
  nil)

(defun extension-context-set-title (context title)
  (assert-active-extension-context context)
  (unless (stringp title)
    (error
     'extension-execution-error
     :message "set-title requires a string"))
  (invoke-extension-ui
   context :set-title
   (list :title title))
  nil)

(defun extension-context-set-editor-text (context text)
  (assert-active-extension-context context)
  (unless (stringp text)
    (error
     'extension-execution-error
     :message "set-editor-text requires a string"))
  (invoke-extension-ui
   context :set-editor-text
   (list :text text))
  nil)

(defun extension-context-get-editor-text (context)
  (or (invoke-extension-ui context :get-editor-text nil) ""))

(defun extension-context-paste-to-editor (context text)
  (unless (stringp text)
    (error 'extension-execution-error
           :message "paste-to-editor requires a string"))
  (invoke-extension-ui context :paste-to-editor (list :text text)))

(defun validate-optional-component-factory (name factory)
  (unless (or (null factory) (functionp factory))
    (error 'extension-execution-error
           :message (format nil "~A requires a function or NIL" name)))
  factory)

(defun extension-context-set-header (context factory)
  (invoke-extension-ui
   context :set-header
   (list :factory (validate-optional-component-factory "set-header" factory))))

(defun extension-context-set-footer (context factory)
  (invoke-extension-ui
   context :set-footer
   (list :factory (validate-optional-component-factory "set-footer" factory))))

(defun extension-context-set-editor-component (context factory)
  (invoke-extension-ui
   context :set-editor-component
   (list :factory
         (validate-optional-component-factory "set-editor-component" factory))))

(defun extension-context-get-editor-component (context)
  (invoke-extension-ui context :get-editor-component nil))

(defun extension-context-set-working-visible (context visible-p)
  (invoke-extension-ui
   context :set-working-visible (list :visible-p (not (null visible-p)))))

(defun extension-context-set-working-message
    (context &optional message)
  (unless (or (null message) (stringp message))
    (error 'extension-execution-error
           :message "set-working-message requires a string or NIL"))
  (invoke-extension-ui context :set-working-message (list :message message)))

(defun extension-context-set-working-indicator
    (context &key (frames nil frames-supplied-p) interval-ms)
  (unless (or (not frames-supplied-p)
              (and (listp frames) (every #'stringp frames)))
    (error 'extension-execution-error
           :message "working indicator frames must be a list of strings"))
  (unless (or (null interval-ms)
              (and (integerp interval-ms) (plusp interval-ms)))
    (error 'extension-execution-error
           :message "working indicator interval-ms must be a positive integer or NIL"))
  (invoke-extension-ui
   context :set-working-indicator
   (list :frames frames :frames-supplied-p frames-supplied-p
         :interval-ms interval-ms)))

(defun extension-context-set-hidden-thinking-label
    (context &optional label)
  (unless (or (null label) (stringp label))
    (error 'extension-execution-error
           :message "hidden thinking label must be a string or NIL"))
  (invoke-extension-ui
   context :set-hidden-thinking-label (list :label label)))

(defun extension-context-custom
    (context factory &key overlay-p overlay-options)
  (unless (functionp factory)
    (error
     'extension-execution-error
     :message "custom requires a component factory function"))
  (invoke-extension-ui
   context :custom
   (list :factory factory
         :overlay-p (not (null overlay-p))
         :overlay-options overlay-options)))

(defun extension-context-custom-component
    (context factory &key overlay-p overlay-options on-handle)
  (unless (functionp factory)
    (error 'extension-execution-error
           :message "custom-component requires a component factory function"))
  (unless (or (null on-handle) (functionp on-handle))
    (error 'extension-execution-error
           :message "custom-component on-handle must be a function or NIL"))
  (invoke-extension-ui
   context :custom-component
   (list :factory factory :overlay-p (not (null overlay-p))
         :overlay-options overlay-options :on-handle on-handle)))

(defun extension-context-add-autocomplete-provider
    (context factory)
  (unless (functionp factory)
    (error
     'extension-execution-error
     :message
     "add-autocomplete-provider requires a factory function"))
  (invoke-extension-ui
   context :add-autocomplete-provider
   (list :factory factory))
  nil)

(defun extension-context-theme (context)
  (invoke-extension-ui context :theme nil))

(defun extension-context-all-themes (context)
  (invoke-extension-ui context :all-themes nil))

(defun extension-context-get-theme (context name)
  (unless (stringp name)
    (error
     'extension-execution-error
     :message "get-theme requires a string name"))
  (invoke-extension-ui
   context :get-theme (list :name name)))

(defun extension-context-set-theme (context theme)
  (unless
      (or (stringp theme)
          (listp theme)
          (hash-table-p theme))
    (error
     'extension-execution-error
     :message
     "set-theme requires a theme name or theme object"))
  (or
   (invoke-extension-ui
    context :set-theme (list :theme theme))
   (list :success nil
         :error "Theme switching is unavailable")))

(defun extension-context-tools-expanded-p (context)
  (not
   (null
    (invoke-extension-ui
     context :tools-expanded-p nil))))

(defun extension-context-set-tools-expanded
    (context expanded-p)
  (invoke-extension-ui
   context :set-tools-expanded
   (list :expanded-p (not (null expanded-p))))
  nil)

(defun assert-extension-deliver-as
    (deliver-as allowed message)
  (unless (member deliver-as allowed)
    (error
     'extension-execution-error
     :message message)))

(defun call-extension-host-action
    (context accessor name &rest arguments)
  (assert-active-extension-context context)
  (let* ((host (%extension-context-host context))
         (function (funcall accessor host)))
    (unless function
      (error
       'extension-execution-error
       :message
       (format nil "Extension action ~A is unavailable in this host"
               name)))
    (apply function arguments)))

(defun extension-context-send-message
    (context message &key
                       (trigger-turn-p nil)
                       deliver-as)
  (assert-extension-deliver-as
   deliver-as
   '(nil :steer :follow-up :next-turn)
   "send-message deliver-as must be :STEER, :FOLLOW-UP, :NEXT-TURN, or NIL")
  (call-extension-host-action
   context #'extension-host-send-message-function
   "send-message"
   message
   :trigger-turn-p (not (null trigger-turn-p))
   :deliver-as deliver-as))

(defun extension-context-send-user-message
    (context content &key deliver-as)
  (assert-extension-deliver-as
   deliver-as
   '(nil :steer :follow-up)
   "send-user-message deliver-as must be :STEER, :FOLLOW-UP, or NIL")
  (call-extension-host-action
   context #'extension-host-send-user-message-function
   "send-user-message"
   content :deliver-as deliver-as))

(defun extension-context-set-session-name (context name)
  (unless (stringp name)
    (error
     'extension-execution-error
     :message "set-session-name requires a string"))
  (call-extension-host-action
   context #'extension-host-set-session-name-function
   "set-session-name" name))
