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
               :name "cadr-extension-events")))

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
  (aborted-p nil :type boolean)
  aborted-function
  abort-function
  (lock
    (sb-thread:make-mutex
     :name "cadr-extension-cancellation")))

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
   :aborted-function aborted-function
   :abort-function abort-function))

(defun extension-cancellation-aborted-p (signal)
  (unless (typep signal 'extension-cancellation-signal)
    (error
     'extension-execution-error
     :message "Expected an extension cancellation signal"))
  (let ((local-p
          (sb-thread:with-mutex
              ((%extension-cancellation-signal-lock signal))
            (%extension-cancellation-signal-aborted-p signal)))
        (external
          (%extension-cancellation-signal-aborted-function signal)))
    (or local-p
        (and external (not (null (funcall external)))))))

(defun abort-extension-cancellation-signal (signal)
  (unless (typep signal 'extension-cancellation-signal)
    (error
     'extension-execution-error
     :message "Expected an extension cancellation signal"))
  (sb-thread:with-mutex
      ((%extension-cancellation-signal-lock signal))
    (setf
     (%extension-cancellation-signal-aborted-p signal)
     t))
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
   :with-session-function with-session-function))

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
    (and function
         (funcall function method arguments))))

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
  (or (invoke-extension-ui context :all-themes nil)
      nil))

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
  (unless
      (member deliver-as
              '(nil :steer :follow-up :next-turn))
    (error
     'extension-execution-error
     :message
     "send-message deliver-as must be :STEER, :FOLLOW-UP, :NEXT-TURN, or NIL"))
  (call-extension-host-action
   context #'extension-host-send-message-function
   "send-message"
   message
   :trigger-turn-p (not (null trigger-turn-p))
   :deliver-as deliver-as))

(defun extension-context-send-user-message
    (context content &key deliver-as)
  (unless (member deliver-as '(nil :steer :follow-up))
    (error
     'extension-execution-error
     :message
     "send-user-message deliver-as must be :STEER, :FOLLOW-UP, or NIL"))
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

(defun active-extension-api-p (api)
  (and
   (typep api 'extension-api)
   (let ((host (%extension-api-host api))
         (bundle (%extension-api-bundle api)))
     (and
      (= (%extension-api-attachment-generation api)
         (extension-host-attachment-generation host))
      (or
       (eq bundle *extension-registration-bundle*)
       (member
        bundle
        (extension-snapshot-bundles
         (extension-host-current-snapshot host))
        :test #'eq))))))

(defun assert-active-extension-api (api)
  (unless (active-extension-api-p api)
    (error
     'stale-extension-context
     :message
     "Extension API is stale after reload, bundle retirement, or session replacement"))
  api)

(defun call-extension-api-action
    (api accessor name &rest arguments)
  (assert-active-extension-api api)
  (let* ((host (%extension-api-host api))
         (function (funcall accessor host)))
    (unless function
      (error
       'extension-execution-error
       :message
       (format nil "Extension action ~A is unavailable in this host"
               name)))
    (apply function arguments)))

(defun extension-api-send-message
    (api message &key (trigger-turn-p nil) deliver-as)
  (unless
      (member deliver-as
              '(nil :steer :follow-up :next-turn))
    (error
     'extension-execution-error
     :message
     "send-message deliver-as must be :STEER, :FOLLOW-UP, :NEXT-TURN, or NIL"))
  (call-extension-api-action
   api #'extension-host-send-message-function
   "send-message" message
   :trigger-turn-p (not (null trigger-turn-p))
   :deliver-as deliver-as))

(defun extension-api-send-user-message
    (api content &key deliver-as)
  (unless (member deliver-as '(nil :steer :follow-up))
    (error
     'extension-execution-error
     :message
     "send-user-message deliver-as must be :STEER, :FOLLOW-UP, or NIL"))
  (call-extension-api-action
   api #'extension-host-send-user-message-function
   "send-user-message" content
   :deliver-as deliver-as))

(defun extension-api-exec
    (api command arguments
     &key cwd environment timeout-ms)
  (unless
      (and
       (stringp command)
       (plusp (length command))
       (listp arguments)
       (every #'stringp arguments)
       (or (null cwd) (stringp cwd))
       (or
        (null environment)
        (and
         (listp environment)
         (every
          (lambda (entry)
            (and
             (consp entry)
             (stringp (car entry))
             (stringp (cdr entry))))
          environment)))
       (or
        (null timeout-ms)
        (and (integerp timeout-ms)
             (not (minusp timeout-ms)))))
    (error
     'extension-execution-error
     :message
     "exec requires command/argument strings, optional string cwd/environment alist, and non-negative timeout-ms"))
  (call-extension-api-action
   api #'extension-host-exec-function
   "exec" command (copy-list arguments)
   :cwd cwd
   :environment (copy-tree environment)
   :timeout-ms timeout-ms))

(defun extension-api-get-flag (api name)
  (assert-active-extension-api api)
  (unless (stringp name)
    (error
     'extension-execution-error
     :message "get-flag requires a string name"))
  (let* ((bundle (%extension-api-bundle api))
         (registered
           (extension-api-registered-flag-p
            bundle name)))
    (unless registered
      (return-from extension-api-get-flag nil))
    (let* ((host (%extension-api-host api))
           (function
             (extension-host-get-flag-function host)))
      (if function
          (funcall function name)
          (gethash name
                   (extension-host-flag-values host))))))

(defun extension-api-get-active-tools (api)
  (copy-list
   (call-extension-api-action
    api #'extension-host-get-active-tools-function
    "get-active-tools")))

(defun extension-api-set-active-tools (api tool-names)
  (unless
      (and
       (listp tool-names)
       (every #'stringp tool-names)
       (= (length tool-names)
          (length
           (remove-duplicates
            tool-names :test #'string=))))
    (error
     'extension-execution-error
     :message
     "set-active-tools requires a list of unique tool-name strings"))
  (call-extension-api-action
   api #'extension-host-set-active-tools-function
   "set-active-tools" (copy-list tool-names)))

(defun extension-api-host-action (api action &rest arguments)
  (assert-active-extension-api api)
  (let* ((host (%extension-api-host api))
         (function (extension-host-action-function host)))
    (unless function
      (error 'extension-execution-error
             :message
             (format nil "Extension action ~(~A~) is unavailable in this host"
                     action)))
    (funcall function action arguments)))

(defun extension-api-get-commands (api)
  (copy-tree (or (extension-api-host-action api :commands) nil)))

(defun extension-api-get-all-tools (api)
  (copy-tree (or (extension-api-host-action api :all-tools) nil)))

(defun extension-api-get-thinking-level (api)
  (extension-api-host-action api :thinking-level))

(defun extension-api-set-thinking-level (api level)
  (extension-api-host-action api :set-thinking-level level))

(defun extension-api-set-model (api model)
  (extension-api-host-action api :set-model model))

(defun extension-api-get-session-name (api)
  (extension-api-host-action api :get-session-name))

(defun extension-api-append-entry (api custom-type &optional data)
  (unless (and (stringp custom-type) (plusp (length custom-type)))
    (error 'extension-execution-error
           :message "append-entry requires a non-empty custom type"))
  (extension-api-host-action api :append-entry custom-type data))

(defun extension-api-set-label (api entry-id label)
  (unless (and (stringp entry-id)
               (or (null label) (stringp label)))
    (error 'extension-execution-error
           :message "set-label requires an entry id and string or NIL label"))
  (extension-api-host-action api :set-label entry-id label))

(defun extension-api-events-on (api name handler)
  (assert-active-extension-api api)
  (unless (and (stringp name) (plusp (length name))
               (functionp handler))
    (error 'extension-execution-error
           :message "events-on requires a non-empty name and handler function"))
  (let ((host (%extension-api-host api)))
    (sb-thread:with-mutex ((extension-host-event-lock host))
      (setf
       (gethash name (extension-host-event-listeners host))
       (nconc
        (gethash name (extension-host-event-listeners host))
        (list
         (make-extension-event-listener
          :name name :handler handler :bundle (%extension-api-bundle api)))))))
  (lambda ()
    (let ((host (%extension-api-host api))
          (bundle (%extension-api-bundle api)))
      (sb-thread:with-mutex ((extension-host-event-lock host))
        (setf
         (gethash name (extension-host-event-listeners host))
         (remove-if
          (lambda (listener)
            (and (eq bundle (extension-event-listener-bundle listener))
                 (eq handler (extension-event-listener-handler listener))))
          (gethash name (extension-host-event-listeners host))))))))

(defun extension-api-events-emit (api name payload)
  (assert-active-extension-api api)
  (unless (and (stringp name) (plusp (length name)))
    (error 'extension-execution-error
           :message "events-emit requires a non-empty name"))
  (let* ((host (%extension-api-host api))
         (active-bundles
           (extension-snapshot-bundles
            (extension-host-current-snapshot host)))
         (listeners
           (sb-thread:with-mutex ((extension-host-event-lock host))
             (let* ((all (gethash name (extension-host-event-listeners host)))
                    (active
                      (remove-if-not
                       (lambda (listener)
                         (member (extension-event-listener-bundle listener)
                                 active-bundles :test #'eq))
                       all)))
               (setf (gethash name (extension-host-event-listeners host)) active)
               (copy-list active)))))
    (dolist (listener listeners)
      (handler-case
          (funcall (extension-event-listener-handler listener)
                   (copy-extension-value payload))
        (condition (condition)
          (funcall (extension-host-notify-function host)
                   (format nil "Extension event ~A failed: ~A" name condition)
                   :error)))))
  nil)

(defun extension-event-type (event)
  (%extension-event-type event))

(defun extension-event-turn-index (event)
  (%extension-event-turn-index event))

(defun extension-event-message (event)
  (%extension-event-message event))

(defun extension-event-tool-call (event)
  (%extension-event-tool-call event))

(defun extension-event-tool-result (event)
  (%extension-event-tool-result event))

(defun extension-event-tool-results (event)
  (%extension-event-tool-results event))

(defun copy-extension-value (value)
  (cond
    ((stringp value)
     (copy-seq value))
    ((hash-table-p value)
     (let ((copy
             (make-hash-table
              :test (hash-table-test value)
              :size (hash-table-size value))))
       (maphash
        (lambda (key item)
          (setf
           (gethash (copy-extension-value key) copy)
           (copy-extension-value item)))
        value)
       copy))
    ((consp value)
     (cons
      (copy-extension-value (car value))
      (copy-extension-value (cdr value))))
    ((vectorp value)
     (map 'vector #'copy-extension-value value))
    (t value)))

(defun extension-event-payload (event)
  (unless (typep event 'extension-event)
    (error
     'extension-execution-error
     :message "Expected an EXTENSION-EVENT"))
  (if (eq :tool-call-error
          (%extension-event-type event))
      (copy-extension-value
       (%extension-event-payload event))
      (copy-tree (%extension-event-payload event))))

;;; Registration model

(defstruct extension-bundle
  (id "" :type string)
  (path "" :type string)
  (scope :global :type symbol)
  (rank 0 :type integer)
  (order 0 :type integer)
  package
  (tools nil :type list)
  (commands nil :type list)
  (hooks nil :type list)
  (templates nil :type list)
  (providers nil :type list)
  (native-providers nil :type list)
  (shortcuts nil :type list)
  (flags nil :type list)
  (message-renderers nil :type list)
  markdown-transformer
  (entry-renderers nil :type list)
  (tool-renderers nil :type list)
  (hidden-p nil :type boolean)
  (snapshot-references 0 :type (integer 0 *)))

(defstruct extension-tool-definition
  name
  label
  description
  prompt-snippet
  (prompt-guidelines nil :type list)
  parameters
  constrained-sampling
  render-shell
  prepare-arguments
  execution-mode
  (full-handler-p nil :type boolean)
  handler
  render-call
  render-result
  bundle)

(defstruct extension-command-definition
  name
  description
  argument-hint
  handler
  bundle)

(defstruct extension-hook-definition
  event
  priority
  handler
  bundle
  order)

(defstruct extension-template-definition
  name
  description
  argument-hint
  template
  bundle)

(defstruct extension-provider-definition
  definition
  (models nil :type list)
  bundle)

(defstruct extension-native-provider-definition
  provider
  bundle)

(defstruct extension-shortcut-definition
  key
  description
  handler
  bundle)

(defstruct extension-flag-definition
  name
  description
  type
  default
  bundle)

(defstruct extension-renderer-definition
  custom-type
  renderer
  bundle)

(defstruct extension-markdown-transformer-definition
  transformer
  bundle)

(defstruct extension-tool-renderer-definition
  tool-name
  call
  result
  bundle)

(defun extension-api-registered-flag-p
    (bundle name)
  (find
   name
   (extension-bundle-flags bundle)
   :key #'extension-flag-definition-name
   :test #'string=))

(defun call-with-extension-registration (bundle function)
  (let ((*extension-registration-bundle* bundle))
    (funcall function)))

(defun call-with-extension-load (host bundle function)
  (let ((*extension-registration-bundle* bundle)
        (*extension-registration-api*
          (%make-extension-api
           :host host
           :bundle bundle
           :attachment-generation
           (extension-host-attachment-generation host))))
    (funcall function)))

(defun current-extension-api ()
  (or
   *extension-registration-api*
   (error
    'extension-registration-error
    :message
    "CURRENT-EXTENSION-API is only available while loading an extension")))

(defun require-extension-registration-bundle ()
  (or
   *extension-registration-bundle*
   (error
    'extension-registration-error
    :message
    "Extension definitions are only valid while loading an extension")))

(defun valid-extension-resource-name-p (name)
  (and
   (stringp name)
   (plusp (length name))
   (every
    (lambda (character)
      (or
       (and (char>= character #\a)
            (char<= character #\z))
       (digit-char-p character)
       (member character '(#\- #\_ #\:))))
    name)))

(defun validate-extension-resource-name (kind name)
  (unless (valid-extension-resource-name-p name)
    (error
     'extension-registration-error
     :message
     (format nil
             "Invalid ~A name ~S; use lowercase ASCII letters, digits, -, _, or :"
             kind name)))
  name)

(defun validate-extension-schema (name schema)
  (unless (hash-table-p schema)
    (error
     'extension-registration-error
     :message
     (format nil "Tool ~A parameters must be a JSON Schema hash-table"
             name)))
  (handler-case
      (validate-json-schema-definition schema)
    (error (condition)
      (error
       'extension-registration-error
       :cause condition
       :message
       (format nil "Tool ~A has an invalid JSON Schema: ~A"
               name condition))))
  schema)

(defun ensure-unique-extension-definition
    (definitions name key kind)
  (when (find name definitions :key key :test #'string=)
    (error
     'extension-registration-error
     :message
     (format nil "~A ~A is registered more than once in the same extension"
             kind name))))

(defun register-extension-tool
    (name description parameters execution-mode handler)
  (let ((bundle (require-extension-registration-bundle)))
    (validate-extension-resource-name "tool" name)
    (unless (stringp description)
      (error
       'extension-registration-error
       :message (format nil "Tool ~A description must be a string"
                        name)))
    (validate-extension-schema name parameters)
    (unless (member execution-mode '(:parallel :sequential))
      (error
       'extension-registration-error
       :message
       (format nil "Tool ~A execution mode must be :parallel or :sequential"
               name)))
    (unless (functionp handler)
      (error
       'extension-registration-error
       :message (format nil "Tool ~A handler must be a function"
                        name)))
    (ensure-unique-extension-definition
     (extension-bundle-tools bundle)
     name
     #'extension-tool-definition-name
     "Tool")
    (setf
     (extension-bundle-tools bundle)
     (nconc
      (extension-bundle-tools bundle)
      (list
       (make-extension-tool-definition
        :name name
        :label name
        :description description
        :parameters parameters
        :execution-mode execution-mode
        :handler handler
        :bundle bundle)))))
  name)

(defun register-rich-extension-tool
    (name &key label description prompt-snippet prompt-guidelines
            parameters constrained-sampling render-shell
            prepare-arguments (execution-mode :parallel)
            handler render-call render-result)
  (let ((bundle (require-extension-registration-bundle)))
    (validate-extension-resource-name "tool" name)
    (unless (and (stringp label) (plusp (length label)))
      (error 'extension-registration-error
             :message (format nil "Tool ~A label must be a non-empty string" name)))
    (unless (stringp description)
      (error 'extension-registration-error
             :message (format nil "Tool ~A description must be a string" name)))
    (unless (or (null prompt-snippet) (stringp prompt-snippet))
      (error 'extension-registration-error
             :message (format nil "Tool ~A prompt snippet must be a string or NIL" name)))
    (unless (and (listp prompt-guidelines) (every #'stringp prompt-guidelines))
      (error 'extension-registration-error
             :message (format nil "Tool ~A prompt guidelines must be strings" name)))
    (validate-extension-schema name parameters)
    (unless (or (null constrained-sampling) (listp constrained-sampling))
      (error 'extension-registration-error
             :message (format nil "Tool ~A constrained sampling must be a plist or NIL" name)))
    (unless (member render-shell '(nil :default :self))
      (error 'extension-registration-error
             :message (format nil "Tool ~A render shell must be :DEFAULT, :SELF, or NIL" name)))
    (unless (or (null prepare-arguments) (functionp prepare-arguments))
      (error 'extension-registration-error
             :message (format nil "Tool ~A prepare-arguments must be a function or NIL" name)))
    (unless (member execution-mode '(:parallel :sequential))
      (error 'extension-registration-error
             :message (format nil "Tool ~A execution mode must be :PARALLEL or :SEQUENTIAL" name)))
    (unless (functionp handler)
      (error 'extension-registration-error
             :message (format nil "Tool ~A handler must be a function" name)))
    (unless (and (or (null render-call) (functionp render-call))
                 (or (null render-result) (functionp render-result)))
      (error 'extension-registration-error
             :message (format nil "Tool ~A renderers must be functions or NIL" name)))
    (ensure-unique-extension-definition
     (extension-bundle-tools bundle) name
     #'extension-tool-definition-name "Tool")
    (setf
     (extension-bundle-tools bundle)
     (nconc
      (extension-bundle-tools bundle)
      (list
       (make-extension-tool-definition
        :name name :label label :description description
        :prompt-snippet prompt-snippet
        :prompt-guidelines (copy-list prompt-guidelines)
        :parameters parameters
        :constrained-sampling (copy-tree constrained-sampling)
        :render-shell render-shell
        :prepare-arguments prepare-arguments
        :execution-mode execution-mode :full-handler-p t
        :handler handler :render-call render-call :render-result render-result
        :bundle bundle)))))
  name)

(defun register-extension-command
    (name description argument-hint handler)
  (let ((bundle (require-extension-registration-bundle)))
    (validate-extension-resource-name "command" name)
    (unless (or (null description) (stringp description))
      (error
       'extension-registration-error
       :message
       (format nil "Command ~A description must be a string or NIL"
               name)))
    (unless (or (null argument-hint) (stringp argument-hint))
      (error
       'extension-registration-error
       :message
       (format nil "Command ~A argument hint must be a string or NIL"
               name)))
    (unless (functionp handler)
      (error
       'extension-registration-error
       :message
       (format nil "Command ~A handler must be a function"
               name)))
    (ensure-unique-extension-definition
     (extension-bundle-commands bundle)
     name
     #'extension-command-definition-name
     "Command")
    (setf
     (extension-bundle-commands bundle)
     (nconc
      (extension-bundle-commands bundle)
      (list
       (make-extension-command-definition
        :name name
        :description description
        :argument-hint argument-hint
        :handler handler
        :bundle bundle)))))
  name)

(defparameter +extension-hook-events+
  '(:turn-start
    :turn-end
    :tool-call-before
    :tool-call-after
    :tool-call-error
    :session-start
    :session-info-changed
    :session-before-switch
    :session-before-fork
    :session-before-compact
    :session-compact
    :session-shutdown
    :session-before-tree
    :session-tree
    :context
    :before-agent-start
    :agent-start
    :agent-end
    :agent-settled
    :message-start
    :message-update
    :message-end
    :input
    :tool-execution-start
    :tool-execution-update
    :tool-execution-end
    :model-select
    :thinking-level-select
    :project-trust
    :resources-discover
    :before-provider-request
    :before-provider-headers
    :after-provider-response
    :user-bash))

(defun register-extension-hook
    (event priority handler)
  (let ((bundle (require-extension-registration-bundle)))
    (unless (member event +extension-hook-events+)
      (error
       'extension-registration-error
       :message
       (format nil "Unsupported extension hook event: ~S"
               event)))
    (unless (integerp priority)
      (error
       'extension-registration-error
       :message "Extension hook priority must be an integer"))
    (unless (functionp handler)
      (error
       'extension-registration-error
       :message "Extension hook handler must be a function"))
    (setf
     (extension-bundle-hooks bundle)
     (nconc
      (extension-bundle-hooks bundle)
      (list
       (make-extension-hook-definition
        :event event
        :priority priority
        :handler handler
        :bundle bundle
        :order (length (extension-bundle-hooks bundle)))))))
  event)

(defun register-extension-template
    (name description argument-hint template)
  (let ((bundle (require-extension-registration-bundle)))
    (validate-extension-resource-name "prompt template" name)
    (unless (or (null description) (stringp description))
      (error
       'extension-registration-error
       :message
       (format nil "Prompt template ~A description must be a string or NIL"
               name)))
    (unless (or (null argument-hint) (stringp argument-hint))
      (error
       'extension-registration-error
       :message
       (format nil "Prompt template ~A argument hint must be a string or NIL"
               name)))
    (unless (or (stringp template) (functionp template))
      (error
       'extension-registration-error
       :message
       (format nil "Prompt template ~A must be a string or function"
               name)))
    (ensure-unique-extension-definition
     (extension-bundle-templates bundle)
     name
     #'extension-template-definition-name
     "Prompt template")
    (setf
     (extension-bundle-templates bundle)
     (nconc
      (extension-bundle-templates bundle)
      (list
       (make-extension-template-definition
        :name name
        :description description
        :argument-hint argument-hint
        :template template
        :bundle bundle)))))
  name)

(defun validate-extension-provider
    (definition models)
  (unless (typep definition 'cadr-ai:provider-definition)
    (error
     'extension-registration-error
     :message
     "Provider definition must be a CADR-AI:PROVIDER-DEFINITION"))
  (unless
      (and
       (listp models)
       (every
        (lambda (model)
          (and
           (typep model 'cadr-ai:model-metadata)
           (eq
            (cadr-ai:model-metadata-provider model)
            (cadr-ai:provider-definition-id definition))))
        models))
    (error
     'extension-registration-error
     :message
     "Provider models must be a list of matching CADR-AI:MODEL-METADATA values"))
  definition)

(defun extension-provider-id (entry)
  (cadr-ai:provider-definition-id
   (extension-provider-definition-definition entry)))

(defun register-extension-provider
    (definition models)
  (let ((bundle (require-extension-registration-bundle)))
    (validate-extension-provider definition models)
    (let ((existing
            (find
             (cadr-ai:provider-definition-id definition)
             (extension-bundle-providers bundle)
             :key #'extension-provider-id)))
      (if existing
          (setf
           (extension-provider-definition-definition existing)
           definition
           (extension-provider-definition-models existing)
           (copy-list models))
          (setf
           (extension-bundle-providers bundle)
           (nconc
            (extension-bundle-providers bundle)
            (list
             (make-extension-provider-definition
              :definition definition
              :models (copy-list models)
              :bundle bundle)))))))
  definition)

(defun register-extension-native-provider (provider)
  (unless (typep provider 'cadr-ai:runtime-provider)
    (error
     'extension-registration-error
     :message
     "Native provider must be a CADR-AI:RUNTIME-PROVIDER"))
  (let* ((bundle (require-extension-registration-bundle))
         (id (cadr-ai:runtime-provider-id provider))
         (existing
           (find
            id
            (extension-bundle-native-providers bundle)
            :key
            (lambda (entry)
              (cadr-ai:runtime-provider-id
               (extension-native-provider-definition-provider
                entry))))))
    (unless (keywordp id)
      (error
       'extension-registration-error
       :message "Native provider ID must be a keyword"))
    (when existing
      (error
       'extension-registration-error
       :message
       (format nil
               "Native provider ~A is registered more than once in the same extension"
               id)))
    (setf
     (extension-bundle-native-providers bundle)
     (nconc
      (extension-bundle-native-providers bundle)
      (list
       (make-extension-native-provider-definition
        :provider provider
        :bundle bundle)))))
  provider)

(defun validate-extension-renderer-type
    (kind custom-type)
  (unless
      (and (stringp custom-type)
           (plusp (length custom-type)))
    (error
     'extension-registration-error
     :message
     (format nil "~A type must be a non-empty string"
             kind)))
  custom-type)

(defun register-extension-shortcut
    (key description handler)
  (let ((bundle (require-extension-registration-bundle)))
    (unless
        (and (stringp key)
             (plusp (length key)))
      (error
       'extension-registration-error
       :message
       "Shortcut key must be a non-empty string"))
    (unless (or (null description)
                (stringp description))
      (error
       'extension-registration-error
       :message
       "Shortcut description must be a string or NIL"))
    (unless (functionp handler)
      (error
       'extension-registration-error
       :message "Shortcut handler must be a function"))
    (let ((definition
            (make-extension-shortcut-definition
             :key (string-downcase key)
             :description description
             :handler handler
             :bundle bundle)))
      (setf
       (extension-bundle-shortcuts bundle)
       (nconc
        (remove
         key
         (extension-bundle-shortcuts bundle)
         :key #'extension-shortcut-definition-key
         :test #'string-equal)
        (list definition)))))
  key)

(defun valid-extension-flag-default-p
    (type default)
  (ecase type
    (:boolean
     (or (null default) (eq default t)))
    (:string
     (or (null default) (stringp default)))))

(defun register-extension-flag
    (name description type default)
  (let ((bundle (require-extension-registration-bundle)))
    (validate-extension-resource-name "flag" name)
    (unless (or (null description)
                (stringp description))
      (error
       'extension-registration-error
       :message
       (format nil "Flag ~A description must be a string or NIL"
               name)))
    (unless (member type '(:boolean :string))
      (error
       'extension-registration-error
       :message
       (format nil "Flag ~A type must be :BOOLEAN or :STRING"
               name)))
    (unless (valid-extension-flag-default-p type default)
      (error
       'extension-registration-error
       :message
       (format nil "Flag ~A default does not match type ~S"
               name type)))
    (let ((definition
            (make-extension-flag-definition
             :name name
             :description description
             :type type
             :default default
             :bundle bundle)))
      (setf
       (extension-bundle-flags bundle)
       (nconc
        (remove
         name
         (extension-bundle-flags bundle)
         :key #'extension-flag-definition-name
         :test #'string=)
        (list definition)))))
  name)

(defun register-extension-renderer
    (kind custom-type renderer)
  (let ((bundle (require-extension-registration-bundle)))
    (validate-extension-renderer-type kind custom-type)
    (unless (functionp renderer)
      (error
       'extension-registration-error
       :message
       (format nil "~A renderer must be a function"
               kind)))
    (let* ((accessor
             (ecase kind
               (:message
                #'extension-bundle-message-renderers)
               (:entry
                #'extension-bundle-entry-renderers)))
           (definitions (funcall accessor bundle))
           (definition
             (make-extension-renderer-definition
              :custom-type custom-type
              :renderer renderer
              :bundle bundle))
           (updated
             (nconc
              (remove
               custom-type definitions
               :key
               #'extension-renderer-definition-custom-type
               :test #'string=)
              (list definition))))
      (ecase kind
        (:message
         (setf
          (extension-bundle-message-renderers bundle)
          updated))
        (:entry
         (setf
          (extension-bundle-entry-renderers bundle)
          updated)))))
  custom-type)

(defun register-extension-markdown-transformer
    (transformer)
  (let ((bundle (require-extension-registration-bundle)))
    (unless (functionp transformer)
      (error
       'extension-registration-error
       :message
       "Markdown transformer must be a function"))
    (setf
     (extension-bundle-markdown-transformer bundle)
     (make-extension-markdown-transformer-definition
      :transformer transformer
      :bundle bundle)))
  transformer)

(defun register-extension-tool-renderer
    (tool-name call result)
  (let ((bundle (require-extension-registration-bundle)))
    (validate-extension-resource-name
     "tool renderer" tool-name)
    (unless
        (and
         (or (null call) (functionp call))
         (or (null result) (functionp result))
         (or call result))
      (error
       'extension-registration-error
       :message
       "Tool renderer requires at least one function-valued :CALL or :RESULT"))
    (let ((existing
            (find
             tool-name
             (extension-bundle-tool-renderers bundle)
             :key
             #'extension-tool-renderer-definition-tool-name
             :test #'string=)))
      (if existing
          (setf
           (extension-tool-renderer-definition-call
            existing)
           (or call
               (extension-tool-renderer-definition-call
                existing))
           (extension-tool-renderer-definition-result
            existing)
           (or result
               (extension-tool-renderer-definition-result
                existing)))
          (setf
           (extension-bundle-tool-renderers bundle)
           (nconc
            (extension-bundle-tool-renderers bundle)
            (list
             (make-extension-tool-renderer-definition
              :tool-name tool-name
              :call call
              :result result
              :bundle bundle)))))))
  tool-name)

(defmacro define-tool
    (name &key description parameters
                 (execution-mode :parallel)
                 handler)
  `(register-extension-tool
    ,name ,description ,parameters ,execution-mode ,handler))

(defmacro define-rich-tool
    (name &key label description prompt-snippet prompt-guidelines
               parameters constrained-sampling render-shell
               prepare-arguments (execution-mode :parallel)
               handler render-call render-result)
  `(register-rich-extension-tool
    ,name :label ,label :description ,description
    :prompt-snippet ,prompt-snippet
    :prompt-guidelines ,prompt-guidelines
    :parameters ,parameters
    :constrained-sampling ,constrained-sampling
    :render-shell ,render-shell
    :prepare-arguments ,prepare-arguments
    :execution-mode ,execution-mode
    :handler ,handler :render-call ,render-call :render-result ,render-result))

(defmacro define-command
    (name &key description argument-hint handler)
  `(register-extension-command
    ,name ,description ,argument-hint ,handler))

(defmacro define-event-hook
    (event &key (priority 0) handler)
  `(register-extension-hook ,event ,priority ,handler))

(defmacro define-prompt-template
    (name &key description argument-hint template)
  `(register-extension-template
    ,name ,description ,argument-hint ,template))

(defmacro define-provider (definition &key models)
  `(register-extension-provider ,definition ,models))

(defmacro define-native-provider (provider)
  `(register-extension-native-provider ,provider))

(defmacro define-shortcut
    (key &key description handler)
  `(register-extension-shortcut
    ,key ,description ,handler))

(defmacro define-flag
    (name &key description type default)
  `(register-extension-flag
    ,name ,description ,type ,default))

(defmacro define-message-renderer
    (custom-type &key renderer)
  `(register-extension-renderer
    :message ,custom-type ,renderer))

(defmacro define-markdown-transformer (transformer)
  `(register-extension-markdown-transformer
    ,transformer))

(defmacro define-entry-renderer
    (custom-type &key renderer)
  `(register-extension-renderer
    :entry ,custom-type ,renderer))

(defmacro define-tool-renderer
    (tool-name &key call result)
  `(register-extension-tool-renderer
    ,tool-name ,call ,result))

(defun make-extension-host
    (&key
       (cwd (uiop:getcwd))
       (mode :repl)
       notify-function
       reload-function
       ui-function
       send-message-function
       send-user-message-function
       set-session-name-function
       exec-function
       action-function
       get-flag-function
       get-active-tools-function
       set-active-tools-function)
  (%make-extension-host
   :cwd
   (uiop:ensure-directory-pathname
    (pathname cwd))
   :mode mode
   :notify-function
   (or
    notify-function
    (lambda (message level)
      (format *error-output*
              "~&extension[~(~A~)]> ~A~%"
              level message)
      (finish-output *error-output*)))
   :reload-function reload-function
   :ui-function ui-function
   :send-message-function send-message-function
   :send-user-message-function send-user-message-function
   :set-session-name-function set-session-name-function
   :exec-function exec-function
   :action-function action-function
   :get-flag-function get-flag-function
   :get-active-tools-function get-active-tools-function
   :set-active-tools-function set-active-tools-function))

(defun extension-definition-origin (definition)
  (extension-bundle-path
   (etypecase definition
     (extension-tool-definition
      (extension-tool-definition-bundle definition))
     (extension-command-definition
      (extension-command-definition-bundle definition))
     (extension-hook-definition
      (extension-hook-definition-bundle definition))
     (extension-template-definition
      (extension-template-definition-bundle definition))
     (extension-provider-definition
      (extension-provider-definition-bundle definition))
     (extension-native-provider-definition
      (extension-native-provider-definition-bundle
       definition))
     (extension-shortcut-definition
      (extension-shortcut-definition-bundle definition))
     (extension-flag-definition
      (extension-flag-definition-bundle definition))
     (extension-renderer-definition
      (extension-renderer-definition-bundle definition))
     (extension-markdown-transformer-definition
      (extension-markdown-transformer-definition-bundle
       definition))
     (extension-tool-renderer-definition
      (extension-tool-renderer-definition-bundle
       definition)))))

(defun extension-conflict
    (kind name winner loser)
  (format nil
          "~A ~S from ~A conflicts with ~A; using ~A"
          kind name
          (extension-definition-origin loser)
          (extension-definition-origin winner)
          (extension-definition-origin winner)))

(defun add-first-definition
    (table ordered definition key kind conflicts)
  (let* ((name (funcall key definition))
         (winner (gethash name table)))
    (if winner
        (push
         (extension-conflict kind name winner definition)
         (symbol-value conflicts))
        (progn
          (setf (gethash name table) definition)
          (setf (symbol-value ordered)
                (nconc
                 (symbol-value ordered)
                 (list definition)))))))

(defun add-last-definition
    (table ordered definition key kind conflicts)
  (let* ((name (funcall key definition))
         (previous (gethash name table)))
    (when previous
      (push
       (extension-conflict kind name definition previous)
       (symbol-value conflicts))
      (setf
       (symbol-value ordered)
       (remove previous
               (symbol-value ordered)
               :test #'eq)))
    (setf (gethash name table) definition)
    (setf
     (symbol-value ordered)
     (nconc (symbol-value ordered)
            (list definition)))))

(defun make-extension-snapshot-from-bundles (bundles)
  (let ((tool-table (make-hash-table :test #'equal))
        (command-table (make-hash-table :test #'equal))
        (template-table (make-hash-table :test #'equal))
        (native-provider-table
          (make-hash-table :test #'eq))
        (shortcut-table (make-hash-table :test #'equal))
        (flag-table (make-hash-table :test #'equal))
        (message-renderer-table
          (make-hash-table :test #'equal))
        (entry-renderer-table
          (make-hash-table :test #'equal))
        (tool-renderer-table
          (make-hash-table :test #'equal))
        (*tools* nil)
        (*commands* nil)
        (*templates* nil)
        (*native-providers* nil)
        (*shortcuts* nil)
        (*flags* nil)
        (*message-renderers* nil)
        (*markdown-transformers* nil)
        (*entry-renderers* nil)
        (*tool-renderers* nil)
        (*conflicts* nil)
        (hooks (make-hash-table :test #'eq)))
    (declare
     (special *tools* *commands* *templates*
              *native-providers*
              *shortcuts* *flags*
              *message-renderers* *markdown-transformers*
              *entry-renderers*
              *tool-renderers*
              *conflicts*))
    (dolist (bundle bundles)
      (dolist (definition (extension-bundle-tools bundle))
        (add-first-definition
         tool-table '*tools* definition
         #'extension-tool-definition-name
         "Tool" '*conflicts*))
      (dolist (definition (extension-bundle-commands bundle))
        (add-first-definition
         command-table '*commands* definition
         #'extension-command-definition-name
         "Command" '*conflicts*))
      (dolist (definition (extension-bundle-templates bundle))
        (add-first-definition
         template-table '*templates* definition
         #'extension-template-definition-name
         "Prompt template" '*conflicts*))
      (dolist
          (definition
           (extension-bundle-native-providers bundle))
        (add-first-definition
         native-provider-table
         '*native-providers*
         definition
         (lambda (entry)
           (cadr-ai:runtime-provider-id
            (extension-native-provider-definition-provider
             entry)))
         "Native provider" '*conflicts*))
      (dolist (definition
               (extension-bundle-shortcuts bundle))
        (add-last-definition
         shortcut-table '*shortcuts* definition
         #'extension-shortcut-definition-key
         "Shortcut" '*conflicts*))
      (dolist (definition
               (extension-bundle-flags bundle))
        (add-first-definition
         flag-table '*flags* definition
         #'extension-flag-definition-name
         "Flag" '*conflicts*))
      (dolist (definition
               (extension-bundle-message-renderers
                bundle))
        (add-first-definition
         message-renderer-table
         '*message-renderers* definition
         #'extension-renderer-definition-custom-type
         "Message renderer" '*conflicts*))
      (when
          (extension-bundle-markdown-transformer bundle)
        (setf
         *markdown-transformers*
         (nconc
          *markdown-transformers*
          (list
           (extension-bundle-markdown-transformer
            bundle)))))
      (dolist (definition
               (extension-bundle-entry-renderers
                bundle))
        (add-first-definition
         entry-renderer-table
         '*entry-renderers* definition
         #'extension-renderer-definition-custom-type
         "Entry renderer" '*conflicts*))
      (dolist (definition
               (extension-bundle-tool-renderers bundle))
        (add-first-definition
         tool-renderer-table
         '*tool-renderers* definition
         #'extension-tool-renderer-definition-tool-name
         "Tool renderer" '*conflicts*))
      (dolist (definition (extension-bundle-hooks bundle))
        (push definition
              (gethash
               (extension-hook-definition-event definition)
               hooks))))
    (maphash
     (lambda (event definitions)
       (declare (ignore event))
       (setf definitions (nreverse definitions))
       (setf
        (gethash
         (extension-hook-definition-event
          (first definitions))
         hooks)
        (stable-sort
         definitions
         #'<
         :key #'extension-hook-definition-priority)))
     hooks)
    (make-extension-snapshot
     :bundles (copy-list bundles)
     :tools *tools*
     :commands *commands*
     :templates *templates*
     :native-providers *native-providers*
     :shortcuts *shortcuts*
     :flags *flags*
     :message-renderers *message-renderers*
     :markdown-transformers *markdown-transformers*
     :entry-renderers *entry-renderers*
     :tool-renderers *tool-renderers*
     :hooks hooks
     :conflicts (nreverse *conflicts*))))

(defun release-extension-snapshot (snapshot)
  (unless (extension-snapshot-released-p snapshot)
    (setf (extension-snapshot-released-p snapshot) t)
    (dolist (bundle (extension-snapshot-bundles snapshot))
      (decf (extension-bundle-snapshot-references bundle))
      (when
          (and
           (zerop
            (extension-bundle-snapshot-references bundle))
           (extension-bundle-package bundle)
           (find-package
            (package-name
             (extension-bundle-package bundle))))
        (ignore-errors
          (delete-package
           (extension-bundle-package bundle)))))))

(defun maybe-release-extension-snapshot (snapshot)
  (when
      (and
       (extension-snapshot-retired-p snapshot)
       (zerop (extension-snapshot-active-count snapshot)))
    (release-extension-snapshot snapshot)))

(defun replace-extension-bundles (host bundles)
  (let ((snapshot
          (make-extension-snapshot-from-bundles bundles))
        (old nil))
    (sb-thread:with-mutex
        ((extension-host-lock host))
      (dolist (bundle
               (extension-snapshot-bundles snapshot))
        (incf
         (extension-bundle-snapshot-references bundle)))
      (setf old (extension-host-snapshot host)
            (extension-host-snapshot host) snapshot)
      (dolist (flag (extension-snapshot-flags snapshot))
        (multiple-value-bind (value present-p)
            (gethash
             (extension-flag-definition-name flag)
             (extension-host-flag-values host))
          (declare (ignore value))
          (unless present-p
            (setf
             (gethash
              (extension-flag-definition-name flag)
              (extension-host-flag-values host))
             (extension-flag-definition-default flag)))))
      (setf (extension-snapshot-retired-p old) t)
      (maybe-release-extension-snapshot old))
    (when (extension-host-agent host)
      (refresh-agent-extension-tools
       (extension-host-agent host))
      (apply-extension-provider-overlays host))
    (copy-list
     (extension-snapshot-conflicts snapshot))))

(defun acquire-extension-snapshot
    (host &optional snapshot)
  (sb-thread:with-mutex
      ((extension-host-lock host))
    (let ((resolved
            (or snapshot
                (extension-host-snapshot host))))
      (incf (extension-snapshot-active-count resolved))
      resolved)))

(defun release-acquired-extension-snapshot
    (host snapshot)
  (sb-thread:with-mutex
      ((extension-host-lock host))
    (decf (extension-snapshot-active-count snapshot))
    (maybe-release-extension-snapshot snapshot)))

(defun call-with-extension-definition
    (host snapshot definition function)
  (let* ((held
           (acquire-extension-snapshot host snapshot))
         (context
           (%make-extension-context
            :host host
            :source-path
            (extension-definition-origin definition)
            :bundle
            (etypecase definition
              (extension-tool-definition
               (extension-tool-definition-bundle definition))
              (extension-command-definition
               (extension-command-definition-bundle definition))
              (extension-hook-definition
               (extension-hook-definition-bundle definition))
              (extension-template-definition
               (extension-template-definition-bundle definition))
              (extension-provider-definition
               (extension-provider-definition-bundle
                definition))
              (extension-shortcut-definition
               (extension-shortcut-definition-bundle
                definition))
              (extension-flag-definition
               (extension-flag-definition-bundle
                definition))
              (extension-renderer-definition
               (extension-renderer-definition-bundle
                definition))
              (extension-tool-renderer-definition
               (extension-tool-renderer-definition-bundle
                definition)))
            :kind
            (etypecase definition
              (extension-tool-definition :tool)
              (extension-command-definition :command)
              (extension-hook-definition :event)
              (extension-template-definition :template)
              (extension-provider-definition :provider)
              (extension-shortcut-definition :shortcut)
              (extension-flag-definition :flag)
              (extension-renderer-definition :renderer)
              (extension-tool-renderer-definition
               :tool-renderer)))))
    (unwind-protect
         (funcall function context)
      (setf (%extension-context-active-p context) nil)
      (release-acquired-extension-snapshot host held))))

(defun notify-extension-failure
    (host definition phase condition)
  (funcall
   (extension-host-notify-function host)
   (format nil "~A ~A failed in ~A: ~A"
           phase
           (extension-definition-origin definition)
           (typecase definition
             (extension-tool-definition
              (extension-tool-definition-name definition))
             (extension-command-definition
              (extension-command-definition-name definition))
             (extension-hook-definition
              (extension-hook-definition-event definition))
             (extension-template-definition
              (extension-template-definition-name definition))
             (extension-provider-definition
              (extension-provider-id definition))
             (extension-shortcut-definition
              (extension-shortcut-definition-key definition))
             (extension-flag-definition
              (extension-flag-definition-name definition))
             (extension-renderer-definition
              (extension-renderer-definition-custom-type
               definition))
             (extension-markdown-transformer-definition
              :markdown)
             (extension-tool-renderer-definition
              (extension-tool-renderer-definition-tool-name
               definition)))
           condition)
   :error))

(defun extension-host-current-snapshot (host)
  (sb-thread:with-mutex
      ((extension-host-lock host))
    (extension-host-snapshot host)))

(defun extension-host-conflicts (host)
  (copy-list
   (extension-snapshot-conflicts
    (extension-host-current-snapshot host))))

(defun extension-host-shortcuts (host)
  (copy-list
   (extension-snapshot-shortcuts
    (extension-host-current-snapshot host))))

(defun extension-host-flags (host)
  (copy-list
   (extension-snapshot-flags
    (extension-host-current-snapshot host))))

(defun find-extension-renderer
    (host custom-type accessor)
  (find
   custom-type
   (funcall
    accessor
    (extension-host-current-snapshot host))
   :key #'extension-renderer-definition-custom-type
   :test #'string=))

(defun find-extension-message-renderer
    (host custom-type)
  (find-extension-renderer
   host custom-type
   #'extension-snapshot-message-renderers))

(defun extension-host-markdown-transformers (host)
  (copy-list
   (extension-snapshot-markdown-transformers
    (extension-host-current-snapshot host))))

(defun transform-extension-markdown
    (host markdown context)
  (let* ((snapshot
           (extension-host-current-snapshot host))
         (current markdown))
    (acquire-extension-snapshot host snapshot)
    (unwind-protect
         (dolist
             (definition
              (extension-snapshot-markdown-transformers
               snapshot)
              current)
           (handler-case
               (let ((transformed
                       (funcall
                        (extension-markdown-transformer-definition-transformer
                         definition)
                        current
                        (copy-list context))))
                 (when (stringp transformed)
                   (setf current transformed)))
             (condition (condition)
               (notify-extension-failure
                host definition
                "Markdown transformer"
                condition))))
      (release-acquired-extension-snapshot
       host snapshot))))

(defun find-extension-entry-renderer
    (host custom-type)
  (find-extension-renderer
   host custom-type
   #'extension-snapshot-entry-renderers))

(defun find-extension-tool-renderer
    (host tool-name)
  (find
   tool-name
   (extension-snapshot-tool-renderers
    (extension-host-current-snapshot host))
   :key
   #'extension-tool-renderer-definition-tool-name
   :test #'string=))

(defun call-extension-renderer
    (host definition phase function arguments)
  (let ((snapshot
          (extension-host-current-snapshot host)))
    (acquire-extension-snapshot host snapshot)
    (unwind-protect
         (handler-case
             (values
              (apply function arguments)
              t)
           (condition (condition)
             (notify-extension-failure
              host definition phase condition)
             (values nil nil)))
      (release-acquired-extension-snapshot
       host snapshot))))

(defun render-extension-message
    (host custom-type message options)
  (let ((definition
          (find-extension-message-renderer
           host custom-type)))
    (if definition
        (call-extension-renderer
         host definition "Message renderer"
         (extension-renderer-definition-renderer
          definition)
         (list message options))
        (values nil nil))))

(defun render-extension-entry
    (host custom-type entry options)
  (let ((definition
          (find-extension-entry-renderer
           host custom-type)))
    (if definition
        (call-extension-renderer
         host definition "Entry renderer"
         (extension-renderer-definition-renderer
          definition)
         (list entry options))
        (values nil nil))))

(defun render-extension-tool-call
    (host tool-name arguments context)
  (let* ((definition
           (find-extension-tool-renderer
            host tool-name))
         (function
           (and
            definition
            (extension-tool-renderer-definition-call
             definition)))
         (rich-definition
           (and (null function)
                (find tool-name
                      (extension-snapshot-tools
                       (extension-host-current-snapshot host))
                      :key #'extension-tool-definition-name
                      :test #'string=)))
         (rich-function
           (and rich-definition
                (extension-tool-definition-render-call rich-definition))))
    (cond
      (function
        (call-extension-renderer
         host definition "Tool call renderer"
         function (list arguments context)))
      (rich-function
       (call-extension-renderer
        host rich-definition "Rich tool call renderer"
        rich-function
        (list arguments (getf context :theme) context)))
      (t (values nil nil)))))

(defun render-extension-tool-result
    (host tool-name result options context)
  (let* ((definition
           (find-extension-tool-renderer
            host tool-name))
         (function
           (and
            definition
             (extension-tool-renderer-definition-result
              definition)))
         (rich-definition
           (and (null function)
                (find tool-name
                      (extension-snapshot-tools
                       (extension-host-current-snapshot host))
                      :key #'extension-tool-definition-name
                      :test #'string=)))
         (rich-function
           (and rich-definition
                (extension-tool-definition-render-result rich-definition))))
    (cond
      (function
        (call-extension-renderer
         host definition "Tool result renderer"
         function
         (list result options context)))
      (rich-function
       (call-extension-renderer
        host rich-definition "Rich tool result renderer"
        rich-function
        (list result options (getf context :theme) context)))
      (t (values nil nil)))))

(defun invoke-extension-shortcut
    (host key)
  (let* ((snapshot
           (extension-host-current-snapshot host))
         (definition
           (find
            key
            (extension-snapshot-shortcuts snapshot)
            :key #'extension-shortcut-definition-key
            :test #'string-equal)))
    (unless definition
      (return-from invoke-extension-shortcut nil))
    (handler-case
        (call-with-extension-definition
         host snapshot definition
         (lambda (context)
           (funcall
            (extension-shortcut-definition-handler
             definition)
            context)))
      (condition (condition)
        (notify-extension-failure
         host definition "Shortcut" condition)))
    t))

(defun extension-host-tools (host)
  (let ((snapshot
          (extension-host-current-snapshot host)))
    (loop
      for definition in
      (extension-snapshot-tools snapshot)
      collect
      (let ((captured definition)
            (captured-snapshot snapshot))
        (cadr-ai:make-tool
         :name
         (extension-tool-definition-name captured)
         :description
         (extension-tool-definition-description captured)
         :parameters
         (extension-tool-definition-parameters captured)
         :constrained-sampling
         (extension-tool-definition-constrained-sampling captured)
         :execution-mode
         (extension-tool-definition-execution-mode captured)
         :executor
         (lambda (call-id arguments)
           (handler-case
               (call-with-extension-definition
                host captured-snapshot captured
                (lambda (context)
                  (let* ((prepared
                           (if (extension-tool-definition-prepare-arguments
                                captured)
                               (funcall
                                (extension-tool-definition-prepare-arguments captured)
                                arguments)
                               arguments))
                         (signal
                           (or (current-tool-cancellation-signal)
                               (make-extension-cancellation-signal)))
                         (update (current-tool-update-function)))
                    (if (extension-tool-definition-full-handler-p captured)
                        (funcall
                         (extension-tool-definition-handler captured)
                         call-id prepared signal update context)
                        (funcall
                         (extension-tool-definition-handler captured)
                         call-id prepared context)))))
             (extension-execution-error (condition)
               (error condition))
             (condition (condition)
               (error
                'extension-execution-error
                :cause condition
                :message
                (format nil
                        "Extension tool ~A from ~A failed: ~A"
                        (extension-tool-definition-name
                         captured)
                        (extension-definition-origin captured)
                        condition))))))))))

(defun extension-host-tool-metadata (host tool-name)
  (let ((definition
          (find tool-name
                (extension-snapshot-tools
                 (extension-host-current-snapshot host))
                :key #'extension-tool-definition-name
                :test #'string=)))
    (and definition
         (list :name (extension-tool-definition-name definition)
               :label (extension-tool-definition-label definition)
               :prompt-snippet
               (extension-tool-definition-prompt-snippet definition)
               :prompt-guidelines
               (copy-list
                (extension-tool-definition-prompt-guidelines definition))
               :render-shell
               (extension-tool-definition-render-shell definition)
               :source
               (extension-definition-origin definition)))))

(defun extension-host-current-active-tools (host)
  (let ((agent (extension-host-agent host)))
    (unless agent
      (error
       'extension-execution-error
       :message
       "get-active-tools requires an attached agent"))
    (mapcar
     #'cadr-ai:tool-name
     (registry-tools
      (agent-tool-registry agent)))))

(defun extension-host-set-active-tools
    (host names)
  (let ((agent (extension-host-agent host)))
    (unless agent
      (error
       'extension-execution-error
       :message
       "set-active-tools requires an attached agent"))
    (let* ((available
             (mapcar
              #'cadr-ai:tool-name
              (merged-agent-tools agent)))
           (unknown
             (set-difference
              names available :test #'string=)))
      (when unknown
        (error
         'extension-execution-error
         :message
         (format nil
                 "~D unknown active tool~:P: ~{~A~^, ~}"
                 (length unknown) unknown)))
      (setf
       (extension-host-active-tool-names host)
       (copy-list names)
       (extension-host-active-tools-overridden-p host)
       t)
      (refresh-agent-extension-tools agent)
      (copy-list names))))

(defun invalidate-extension-host-generation (host)
  (sb-thread:with-mutex
      ((extension-host-lock host))
    (incf
     (extension-host-attachment-generation host)))
  host)

(defun attach-extension-host (host agent)
  (when
      (and
       (extension-host-agent host)
       (not (eq (extension-host-agent host)
                agent)))
    (invalidate-extension-host-generation host))
  (setf (extension-host-agent host) agent
        (extension-host-base-agent-provider host)
        (agent-provider agent)
        (extension-host-base-agent-model host)
        (agent-model agent)
        (agent-extension-host agent) host)
  (unless (extension-host-send-message-function host)
    (setf
     (extension-host-send-message-function host)
     (lambda (message &key trigger-turn-p deliver-as)
       (extension-host-send-message
        host message
        :trigger-turn-p trigger-turn-p
        :deliver-as deliver-as))))
  (unless (extension-host-send-user-message-function host)
    (setf
     (extension-host-send-user-message-function host)
     (lambda (content &key deliver-as)
       (extension-host-send-user-message
        host content :deliver-as deliver-as))))
  (unless (extension-host-set-session-name-function host)
    (setf
     (extension-host-set-session-name-function host)
     (lambda (name)
       (extension-host-set-session-name host name))))
  (unless (extension-host-get-flag-function host)
    (setf
     (extension-host-get-flag-function host)
     (lambda (name)
       (gethash name
                (extension-host-flag-values host)))))
  (unless (extension-host-get-active-tools-function host)
    (setf
     (extension-host-get-active-tools-function host)
     (lambda ()
       (extension-host-current-active-tools host))))
  (unless (extension-host-set-active-tools-function host)
    (setf
     (extension-host-set-active-tools-function host)
     (lambda (names)
       (extension-host-set-active-tools
        host names))))
  (refresh-agent-extension-tools agent)
  (apply-extension-provider-overlays host)
  host)

(defun extension-custom-message-value
    (message key &optional default)
  (getf message key default))

(defun extension-custom-message-p (message)
  (and
   (listp message)
   (stringp
    (extension-custom-message-value
     message :custom-type))
   (valid-custom-message-content-p
    (extension-custom-message-value
     message :content))))

(defun extension-custom-message-as-user-message (message)
  (cadr-ai:make-user-message
   :content
   (extension-custom-message-value
    message :content)))

(defun persist-extension-custom-message (agent message)
  (let ((session (agent-session agent)))
    (when session
      (session-append-custom-message
       session
       (extension-custom-message-value
        message :custom-type)
       (extension-custom-message-value
        message :content)
       :details
       (extension-custom-message-value
        message :details)
       :display-p
       (extension-custom-message-value
        message :display-p))))
  message)

(defun deliver-extension-message
    (agent message deliver-as)
  (ecase deliver-as
    (:steer (agent-steer agent message))
    (:follow-up (agent-follow-up agent message))
    (:next-turn (agent-next-turn agent message))))

(defun extension-host-send-message
    (host message &key trigger-turn-p deliver-as)
  (let ((agent (extension-host-agent host)))
    (unless agent
      (error
       'extension-execution-error
       :message "send-message requires an attached agent"))
    (let ((queued-message
            (cond
              ((extension-custom-message-p message)
               (persist-extension-custom-message
                agent message)
               (extension-custom-message-as-user-message
                message))
              ((typep message 'cadr-ai:user-message)
               message)
              (t
               (error
                'extension-execution-error
                :message
                "send-message requires a custom message plist or USER-MESSAGE")))))
      (cond
        (deliver-as
         (deliver-extension-message
          agent queued-message deliver-as))
        ((and trigger-turn-p
              (agent-busy-p agent))
         (error
          'extension-execution-error
          :message
          "send-message requires DELIVER-AS while the agent is running"))
        (trigger-turn-p
         (agent-prompt agent queued-message))
        (t message)))))

(defun extension-host-send-user-message
    (host content &key deliver-as)
  (let ((agent (extension-host-agent host)))
    (unless agent
      (error
       'extension-execution-error
       :message
       "send-user-message requires an attached agent"))
    (let ((message
            (if (typep content 'cadr-ai:user-message)
                content
                (handler-case
                    (cadr-ai:make-user-message
                     :content content)
                  (error (condition)
                    (error
                     'extension-execution-error
                     :cause condition
                     :message
                     "send-user-message requires valid user content"))))))
      (cond
        (deliver-as
         (multiple-value-bind
               (processed handled-p)
             (apply-agent-input-hooks
              agent message :extension
              :streaming-behavior deliver-as)
           (unless handled-p
             (deliver-extension-message
              agent processed deliver-as))))
        ((agent-busy-p agent)
         (error
          'extension-execution-error
          :message
          "send-user-message requires DELIVER-AS while the agent is running"))
        (t
         (agent-prompt
          agent message
          :source :extension))))))

(defun extension-host-set-session-name (host name)
  (let* ((agent (extension-host-agent host))
         (session (and agent (agent-session agent))))
    (unless session
      (error
       'extension-execution-error
       :message
       "set-session-name requires an attached session"))
    (session-set-name session name)
    (run-extension-lifecycle-hooks
     host :session-info-changed
     :payload (list :name (session-name session)))
    (session-name session)))

(defun extension-host-provider-definitions (host)
  (let ((seen (make-hash-table))
        (result nil))
    (dolist
        (bundle
         (extension-snapshot-bundles
          (extension-host-current-snapshot host)))
      (dolist (entry (extension-bundle-providers bundle))
        (unless (gethash (extension-provider-id entry) seen)
          (setf
           (gethash (extension-provider-id entry) seen)
           t)
          (push entry result))))
    (nreverse result)))

(defun extension-host-native-providers (host)
  (mapcar
   #'extension-native-provider-definition-provider
   (extension-snapshot-native-providers
    (extension-host-current-snapshot host))))

(defun metadata-model-copy (metadata)
  (cadr-ai:make-model
   :id (cadr-ai:model-metadata-id metadata)
   :name (cadr-ai:model-metadata-name metadata)
   :provider (cadr-ai:model-metadata-provider metadata)
   :api (cadr-ai:model-metadata-api metadata)
   :base-url (cadr-ai:model-metadata-base-url metadata)
   :max-tokens
   (cadr-ai:model-metadata-max-output-tokens metadata)
   :context-window
   (cadr-ai:model-metadata-context-window metadata)
   :supports-images-p
   (cadr-ai:model-metadata-supports-images-p metadata)
   :supports-tools-p
   (cadr-ai:model-metadata-supports-tools-p metadata)
   :reasoning-p
   (cadr-ai:model-metadata-reasoning-p metadata)
   :thinking-level-map
   (cadr-ai:model-metadata-thinking-level-map metadata)
   :headers (cadr-ai:model-metadata-headers metadata)
   :compat (cadr-ai:model-metadata-compat metadata)))

(defun provider-overlay-model
    (entry model)
  (let* ((definition
           (extension-provider-definition-definition entry))
         (metadata
           (find
            (cadr-ai:model-id model)
            (extension-provider-definition-models entry)
            :key #'cadr-ai:model-metadata-id
            :test #'string=)))
    (if metadata
        (metadata-model-copy metadata)
        (cadr-ai:make-model
         :id (cadr-ai:model-id model)
         :name (cadr-ai::model-name model)
         :provider (cadr-ai:model-provider model)
         :api
         (or
          (cadr-ai:provider-definition-protocol definition)
          (cadr-ai:model-api model))
         :base-url
         (cadr-ai:provider-definition-base-url definition)
         :max-tokens (cadr-ai:model-max-tokens model)
         :context-window (cadr-ai:model-context-window model)
         :supports-images-p
         (cadr-ai:provider-definition-supports-images-p
          definition)
         :supports-tools-p
         (cadr-ai:provider-definition-supports-tools-p
          definition)
         :reasoning-p
         (cadr-ai:provider-definition-reasoning-p
          definition)
         :thinking-level-map
         (cadr-ai::model-thinking-level-map model)
         :headers (cadr-ai::model-headers model)
         :compat (cadr-ai::model-compat model)))))

(defun apply-extension-provider-overlays (host)
  (let ((agent (extension-host-agent host)))
    (when agent
      (let* ((baseline
               (or
                (extension-host-base-agent-model host)
                (agent-model agent)))
             (entry
               (find
                (cadr-ai:model-provider baseline)
                (extension-host-provider-definitions host)
                :key #'extension-provider-id)))
        (setf
         (agent-model agent)
         (if entry
             (provider-overlay-model entry baseline)
             baseline)
         (agent-provider agent)
         (or
          (extension-host-base-agent-provider host)
          (agent-provider agent))))))
  host)

(defun extension-context-register-tool (context tool)
  (assert-active-extension-context context)
  (unless (typep tool 'cadr-ai:tool)
    (error
     'extension-execution-error
     :message "register-tool requires a CADR-AI:TOOL"))
  (let* ((host (%extension-context-host context))
         (bundle (%extension-context-bundle context))
         (name (cadr-ai:tool-name tool))
         (definition
           (make-extension-tool-definition
            :name name
            :description (cadr-ai:tool-description tool)
            :parameters (cadr-ai:tool-parameters tool)
            :execution-mode
            (cadr-ai:tool-execution-mode tool)
            :handler
            (lambda (call-id arguments ignored-context)
              (declare (ignore ignored-context))
              (funcall
               (cadr-ai:tool-executor tool)
               call-id arguments))
            :bundle bundle)))
    (validate-extension-resource-name "tool" name)
    (validate-extension-schema
     name (cadr-ai:tool-parameters tool))
    (setf
     (extension-bundle-tools bundle)
     (nconc
      (remove
       name
       (extension-bundle-tools bundle)
       :key #'extension-tool-definition-name
       :test #'string=)
      (list definition)))
    (replace-extension-bundles
     host
     (extension-snapshot-bundles
      (extension-host-current-snapshot host)))
    tool))

(defun extension-context-register-provider
    (context definition &key models)
  (assert-active-extension-context context)
  (handler-case
      (validate-extension-provider definition models)
    (extension-registration-error (condition)
      (error
       'extension-execution-error
       :cause condition
       :message (princ-to-string condition))))
  (let* ((host (%extension-context-host context))
         (bundle (%extension-context-bundle context))
         (id (cadr-ai:provider-definition-id definition))
         (entry
           (make-extension-provider-definition
            :definition definition
            :models (copy-list models)
            :bundle bundle)))
    (setf
     (extension-bundle-providers bundle)
     (nconc
      (remove
       id
       (extension-bundle-providers bundle)
       :key #'extension-provider-id)
      (list entry)))
    (replace-extension-bundles
     host
     (extension-snapshot-bundles
      (extension-host-current-snapshot host)))
    definition))

;;; Commands and prompt templates

(defun find-extension-command (snapshot name)
  (find name
        (extension-snapshot-commands snapshot)
        :key #'extension-command-definition-name
        :test #'string=))

(defun invoke-extension-command
    (host name arguments)
  (let* ((snapshot
           (extension-host-current-snapshot host))
         (definition
           (find-extension-command snapshot name)))
    (unless definition
      (return-from invoke-extension-command nil))
    (handler-case
        (call-with-extension-definition
         host snapshot definition
         (lambda (context)
           (funcall
            (extension-command-definition-handler definition)
            arguments context)))
      (condition (condition)
        (notify-extension-failure
         host definition "Command" condition)))
    t))

(defun parse-extension-command-arguments (text)
  (let ((arguments nil)
        (current
          (make-array
           16 :element-type 'character
           :adjustable t :fill-pointer 0))
        (quote nil))
    (labels
        ((finish-current ()
           (when (plusp (fill-pointer current))
             (push (copy-seq current) arguments)
             (setf (fill-pointer current) 0))))
      (loop for character across text
            do
            (cond
              (quote
               (if (char= character quote)
                   (setf quote nil)
                   (vector-push-extend character current)))
              ((or (char= character #\")
                   (char= character #\'))
               (setf quote character))
              ((member character
                       '(#\Space #\Tab #\Newline #\Return))
               (finish-current))
              (t
               (vector-push-extend character current))))
      (finish-current))
    (nreverse arguments)))

(defun join-extension-arguments (arguments)
  (format nil "~{~A~^ ~}" arguments))

(defun extension-argument (arguments index)
  (and
   (plusp index)
   (nth (1- index) arguments)))

(defun parse-positive-index (text)
  (and
   (plusp (length text))
   (every #'digit-char-p text)
   (parse-integer text)))

(defun expand-braced-template-token
    (token arguments)
  (let ((default-position (search ":-" token))
        (slice-prefix-p
          (and
           (>= (length token) 2)
           (char= (char token 0) #\@)
           (char= (char token 1) #\:))))
    (cond
      (default-position
       (let* ((target
                (subseq token 0 default-position))
              (default
                (subseq token (+ default-position 2)))
              (value
                (cond
                  ((or (string= target "@")
                       (string= target "ARGUMENTS"))
                   (join-extension-arguments arguments))
                  (t
                   (let ((index
                           (parse-positive-index target)))
                     (and index
                          (extension-argument
                           arguments index)))))))
         (if (and value (plusp (length value)))
             value
             default)))
      (slice-prefix-p
       (let* ((parts
                (loop with start = 2
                      for position =
                        (position #\: token :start start)
                      collect
                      (subseq token start position)
                      while position
                      do (setf start (1+ position))))
              (start
                (parse-positive-index (first parts)))
              (length-value
                (and (second parts)
                     (parse-positive-index
                      (second parts)))))
         (if start
             (join-extension-arguments
              (if length-value
                  (subseq
                   arguments
                   (min (1- start)
                        (length arguments))
                   (min
                    (+ (1- start) length-value)
                    (length arguments)))
                  (nthcdr
                   (min (1- start)
                        (length arguments))
                   arguments)))
             nil)))
      ((or (string= token "@")
           (string= token "ARGUMENTS"))
       (join-extension-arguments arguments))
      (t
       (let ((index (parse-positive-index token)))
         (and index
              (or
               (extension-argument arguments index)
               "")))))))

(defun expand-simple-template-token
    (template start arguments)
  (cond
    ((and
      (< (1+ start) (length template))
      (char= (char template (1+ start)) #\@))
     (values
      (join-extension-arguments arguments)
      (+ start 2)))
    ((and
      (<= (+ start 10) (length template))
      (string=
       "ARGUMENTS"
       template
       :start2 (1+ start)
       :end2 (+ start 10)))
     (values
      (join-extension-arguments arguments)
      (+ start 10)))
    (t
     (let ((end (1+ start)))
       (loop
         while
         (and
          (< end (length template))
          (digit-char-p (char template end)))
         do (incf end))
       (if (> end (1+ start))
           (values
            (or
             (extension-argument
              arguments
              (parse-integer
               template
               :start (1+ start)
               :end end))
             "")
            end)
           (values "$" (1+ start)))))))

(defun substitute-extension-template
    (template arguments)
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length template))
          do
          (if (char/= (char template index) #\$)
              (progn
                (write-char (char template index) output)
                (incf index))
              (if
                  (and
                   (< (1+ index) (length template))
                   (char= (char template (1+ index)) #\{))
                  (let ((close
                          (position
                           #\} template
                           :start (+ index 2))))
                    (if close
                        (let ((replacement
                                (expand-braced-template-token
                                 (subseq
                                  template
                                  (+ index 2)
                                  close)
                                 arguments)))
                          (if replacement
                              (write-string replacement output)
                              (write-string
                               (subseq
                                template index
                                (1+ close))
                               output))
                          (setf index (1+ close)))
                        (progn
                          (write-char #\$ output)
                          (incf index))))
                  (multiple-value-bind
                        (replacement next)
                      (expand-simple-template-token
                       template index arguments)
                    (write-string replacement output)
                    (setf index next)))))))

(defun split-slash-invocation (text)
  (unless
      (and
       (plusp (length text))
       (char= (char text 0) #\/))
    (return-from split-slash-invocation
      (values nil nil)))
  (let ((separator
          (position-if
           (lambda (character)
             (member character
                     '(#\Space #\Tab #\Newline #\Return)))
           text
           :start 1)))
    (values
     (subseq text 1 separator)
     (if separator
         (string-left-trim
          '(#\Space #\Tab #\Newline #\Return)
          (subseq text separator))
         ""))))

(defun expand-extension-prompt (host text)
  (multiple-value-bind (name argument-text)
      (split-slash-invocation text)
    (unless name
      (return-from expand-extension-prompt
        (values text nil)))
    (let* ((snapshot
             (extension-host-current-snapshot host))
           (definition
             (find
              name
              (extension-snapshot-templates snapshot)
              :key #'extension-template-definition-name
              :test #'string=)))
      (unless definition
        (return-from expand-extension-prompt
          (values text nil)))
      (let ((arguments
              (parse-extension-command-arguments
               argument-text)))
        (handler-case
            (values
             (if
                 (stringp
                  (extension-template-definition-template
                   definition))
                 (substitute-extension-template
                  (extension-template-definition-template
                   definition)
                  arguments)
                 (call-with-extension-definition
                  host snapshot definition
                  (lambda (context)
                    (let ((expanded
                            (funcall
                             (extension-template-definition-template
                              definition)
                             arguments context)))
                      (unless (stringp expanded)
                        (error
                         "Prompt template returned ~S instead of a string"
                         expanded))
                      expanded))))
             t)
          (condition (condition)
            (notify-extension-failure
             host definition "Prompt template" condition)
            (values text t)))))))

;;; Hook dispatch

(defun extension-message-p (value)
  (or
   (typep value 'cadr-ai:user-message)
   (typep value 'cadr-ai:assistant-message)
   (typep value 'cadr-ai:tool-result-message)))

(defun assistant-tool-call-signature (message)
  (loop
    for block in
    (cadr-ai:assistant-message-content message)
    when (typep block 'cadr-ai:tool-call)
      collect
      (list
       (cadr-ai:tool-call-id block)
       (cadr-ai:tool-call-name block))))

(defun valid-extension-replacement-p
    (event-type replacement original)
  (case event-type
    (:turn-start
     (or
      (null replacement)
      (typep replacement 'cadr-ai:user-message)))
    (:turn-end
     (and
      (typep replacement 'cadr-ai:assistant-message)
      (equal
       (assistant-tool-call-signature replacement)
       (assistant-tool-call-signature original))))
    (:tool-call-before
     (and
      (typep replacement 'cadr-ai:tool-call)
      (string=
       (cadr-ai:tool-call-id replacement)
       (cadr-ai:tool-call-id original))))
    (:tool-call-after
     (and
      (typep replacement 'cadr-ai:tool-result-message)
      (string=
       (cadr-ai:tool-result-message-tool-call-id replacement)
       (cadr-ai:tool-result-message-tool-call-id original))
      (string=
       (cadr-ai:tool-result-message-tool-name replacement)
       (cadr-ai:tool-result-message-tool-name original))))
    (otherwise nil)))

(defun make-hook-event
    (type turn-index primary tool-call
     tool-result tool-results appended)
  (%make-extension-event
   :type type
   :turn-index turn-index
   :message
   (and (member type '(:turn-start :turn-end))
        primary)
   :tool-call
   (if (eq type :tool-call-before)
       primary
       tool-call)
   :tool-result
   (if (eq type :tool-call-after)
       primary
       tool-result)
   :tool-results tool-results
   :appended-messages appended))

(defun run-extension-hooks
    (host event-type
     &key
       turn-index
       message
       tool-call
       tool-result
       tool-results)
  (let* ((snapshot
           (extension-host-current-snapshot host))
         (definitions
           (copy-list
            (gethash event-type
                     (extension-snapshot-hooks
                      snapshot))))
         (primary
           (case event-type
             ((:turn-start :turn-end) message)
             (:tool-call-before tool-call)
             (:tool-call-after tool-result)))
         (appended nil)
         (blocked-p nil)
         (reason nil)
         (terminate-p nil)
         (terminate-supplied-p nil))
    (let ((held
            (acquire-extension-snapshot
             host snapshot)))
      (unwind-protect
           (sb-thread:with-mutex
               ((extension-host-hook-lock host))
             (dolist (definition definitions)
               (handler-case
                   (let ((result
                           (call-with-extension-definition
                            host snapshot definition
                            (lambda (context)
                              (funcall
                               (extension-hook-definition-handler
                                definition)
                               (make-hook-event
                                event-type turn-index primary
                                tool-call tool-result tool-results
                                appended)
                               context)))))
                     (when result
                       (unless
                           (typep
                            result
                            'extension-hook-result)
                         (error
                          "Hook returned ~S instead of EXTENSION-HOOK-RESULT or NIL"
                          result))
                       (let* ((replacement-p
                                (extension-hook-result-replacement-p
                                 result))
                              (replacement
                                (if replacement-p
                                    (extension-hook-result-replacement
                                     result)
                                    primary))
                              (messages
                                (extension-hook-result-append-messages
                                 result))
                              (result-block-p
                                (extension-hook-result-block-p
                                 result))
                              (result-reason
                                (extension-hook-result-reason
                                 result))
                              (result-terminate-supplied-p
                                (extension-hook-result-terminate-supplied-p
                                 result))
                              (result-terminate-p
                                (extension-hook-result-terminate-p
                                 result)))
                         (when
                             (and
                              replacement-p
                              (not
                               (valid-extension-replacement-p
                                event-type replacement
                                primary)))
                           (error
                            "Invalid replacement for ~S"
                            event-type))
                         (unless
                             (and
                              (listp messages)
                              (every
                               #'extension-message-p
                               messages))
                           (error
                            "Hook append-messages must be a list of CADR-AI messages"))
                         (when result-block-p
                           (unless
                               (eq
                                event-type
                                :tool-call-before)
                             (error
                              "Only :tool-call-before hooks may block"))
                           (unless
                               (or
                                (null result-reason)
                                (stringp result-reason))
                             (error
                              "Hook block reason must be a string or NIL")))
                         (when result-terminate-supplied-p
                           (unless (eq event-type :tool-call-after)
                             (error
                              "Only :tool-call-after hooks may override terminate")))
                         ;; Commit only after the entire hook result validates.
                         (setf primary replacement
                                appended
                                (nconc
                                 appended
                                 (copy-list messages)))
                         (when result-terminate-supplied-p
                           (setf terminate-p result-terminate-p
                                 terminate-supplied-p t))
                         (when result-block-p
                           (setf
                            blocked-p t
                            reason
                            (or
                             result-reason
                             "Tool execution was blocked"))
                           (return)))))
                 (condition (condition)
                   (notify-extension-failure
                    host definition "Hook" condition)))))
        (release-acquired-extension-snapshot
         host held)))
    (values primary appended blocked-p reason
            terminate-p terminate-supplied-p)))

;;; Wave 2 lifecycle dispatch. The original four hooks above deliberately keep
;;; their frozen EXTENSION-HOOK-RESULT contract.

(defparameter +extension-lifecycle-no-result-events+
  '(:session-start
    :session-info-changed
    :session-compact
    :session-shutdown
    :session-tree
    :agent-start
    :agent-end
    :agent-settled
    :message-start
    :message-update
    :tool-execution-start
    :tool-execution-update
    :tool-execution-end
    :model-select
    :thinking-level-select
    :after-provider-response))

(defun strict-keyword-plist-p (value)
  (and
   (listp value)
   (evenp (length value))
   (loop for tail on value by #'cddr
         always (keywordp (first tail)))))

(defun validate-lifecycle-result-keys
    (event result allowed)
  (unless (strict-keyword-plist-p result)
    (error
     "~S handler returned ~S instead of a keyword plist or NIL"
     event result))
  (loop for tail on result by #'cddr
        for key = (first tail)
        do
        (unless (member key allowed)
          (error
           "~S handler returned unsupported key ~S"
           event key)))
  result)

(defun extension-boolean-p (value)
  (or (null value) (eq value t)))

(defun extension-message-role (message)
  (cond
    ((typep message 'cadr-ai:user-message) :user)
    ((typep message 'cadr-ai:assistant-message) :assistant)
    ((typep message 'cadr-ai:tool-result-message) :tool-result)
    (t nil)))

(defun validate-session-before-result (event result)
  (let ((allowed
          (case event
            (:session-before-switch
             '(:cancel-p))
            (:session-before-fork
             '(:cancel-p
               :skip-conversation-restore-p))
            (:session-before-compact
             '(:cancel-p :compaction))
            (:session-before-tree
             '(:cancel-p
               :summary
               :details
               :usage
               :custom-instructions
               :replace-instructions-p
               :label)))))
    (validate-lifecycle-result-keys
     event result allowed)
    (dolist (key
             '(:cancel-p
               :skip-conversation-restore-p
               :replace-instructions-p))
      (let ((sentinel (list :missing)))
        (let ((value (getf result key sentinel)))
          (unless
              (or
               (eq value sentinel)
               (extension-boolean-p value))
            (error "~S result key ~S must be boolean"
                   event key)))))
    (dolist (key '(:summary :custom-instructions :label))
      (let ((sentinel (list :missing)))
        (let ((value (getf result key sentinel)))
          (unless
              (or
               (eq value sentinel)
               (null value)
               (stringp value))
            (error "~S result key ~S must be a string or NIL"
                   event key)))))
    result))

(defun validate-lifecycle-result (event result current-payload)
  (cond
    ((member event +extension-lifecycle-no-result-events+)
     (when result
       (error "~S handlers must return NIL" event))
     nil)
    ((member
      event
      '(:session-before-switch
        :session-before-fork
        :session-before-compact
        :session-before-tree))
     (and result
          (validate-session-before-result event result)))
    ((eq event :tool-call-error)
     (when result
       (unless (strict-keyword-plist-p result)
         (error
          ":TOOL-CALL-ERROR handler must return a keyword plist or NIL"))
       (let ((action (getf result :action)))
         (case action
           (:retry
            (validate-lifecycle-result-keys
             event result '(:action :arguments))
            (unless (hash-table-p
                     (getf result :arguments))
              (error
               ":TOOL-CALL-ERROR :RETRY requires hash-table :ARGUMENTS")))
           ((:skip :abort)
            (validate-lifecycle-result-keys
             event result '(:action :reason))
            (let ((reason (getf result :reason)))
              (unless (or (null reason)
                          (stringp reason))
                (error
                 ":TOOL-CALL-ERROR :REASON must be a string or NIL"))))
           (otherwise
            (error
             ":TOOL-CALL-ERROR :ACTION must be :RETRY, :SKIP, or :ABORT")))))
     result)
    ((eq event :context)
     (when result
       (validate-lifecycle-result-keys
        event result '(:messages))
       (let ((messages (getf result :messages)))
         (unless
             (and
              (listp messages)
              (every #'extension-message-p messages))
           (error
            ":CONTEXT :MESSAGES must be a list of CADR-AI messages"))))
     result)
    ((eq event :before-agent-start)
     (when result
       (validate-lifecycle-result-keys
        event result '(:message :system-prompt))
       (let ((sentinel (list :missing)))
         (let ((message (getf result :message sentinel))
               (system-prompt
                 (getf result :system-prompt sentinel)))
           (unless
               (or
                (eq message sentinel)
                (extension-message-p message))
             (error
              ":BEFORE-AGENT-START :MESSAGE must be a CADR-AI message"))
           (unless
               (or
                (eq system-prompt sentinel)
                (stringp system-prompt))
             (error
              ":BEFORE-AGENT-START :SYSTEM-PROMPT must be a string")))))
     result)
    ((eq event :message-end)
     (when result
       (validate-lifecycle-result-keys
        event result '(:message))
       (let ((replacement (getf result :message))
             (original (getf current-payload :message)))
         (unless
             (and
              (extension-message-p replacement)
              (eq
               (extension-message-role replacement)
               (extension-message-role original)))
           (error
            ":MESSAGE-END replacement must preserve the message role"))))
     result)
    ((eq event :input)
     (when result
       (validate-lifecycle-result-keys
        event result '(:action :text :images))
       (let ((action (getf result :action)))
         (unless (member action '(:continue :transform :handled))
           (error
            ":INPUT :ACTION must be :CONTINUE, :TRANSFORM, or :HANDLED"))
         (case action
           ((:continue :handled)
            (unless (= 2 (length result))
              (error
               ":INPUT ~S result accepts only :ACTION"
               action)))
           (:transform
            (unless (stringp (getf result :text))
              (error
               ":INPUT :TRANSFORM requires string :TEXT"))
            (let ((sentinel (list :missing)))
              (let ((images (getf result :images sentinel)))
                (unless
                    (or
                     (eq images sentinel)
                     (null images)
                     (typep images 'sequence))
                  (error
                   ":INPUT :IMAGES must be a sequence or NIL"))))))))
     result)
    ((eq event :project-trust)
     (when result
       (validate-lifecycle-result-keys
        event result '(:trusted :remember-p))
       (unless
           (member
            (getf result :trusted)
            '(:yes :no :undecided))
         (error
          ":PROJECT-TRUST :TRUSTED must be :YES, :NO, or :UNDECIDED"))
       (let ((sentinel (list :missing)))
         (let ((remember
                 (getf result
                       :remember-p sentinel)))
           (unless
               (or
                (eq remember sentinel)
                (extension-boolean-p remember))
             (error
              ":PROJECT-TRUST :REMEMBER-P must be boolean")))))
     result)
    ((eq event :resources-discover)
     (when result
       (validate-lifecycle-result-keys
        event result
        '(:skill-paths
          :prompt-paths
          :theme-paths))
       (dolist
           (key
            '(:skill-paths
              :prompt-paths
              :theme-paths))
         (let ((value (getf result key)))
           (unless
               (or
                (null value)
                (and
                 (listp value)
                 (every #'stringp value)))
             (error
              ":RESOURCES-DISCOVER ~S must be a list of strings"
              key)))))
     result)
    ((eq event :before-provider-request)
     result)
    ((eq event :before-provider-headers)
     (when result
       (error
        ":BEFORE-PROVIDER-HEADERS handlers must return NIL"))
     nil)
    ((eq event :user-bash)
     (when result
       (validate-lifecycle-result-keys
        event result '(:operations :result)))
     result)
    (t
     (error "No lifecycle result contract for ~S" event))))

(defun make-lifecycle-event (event payload)
  (%make-extension-event
   :type event
   :payload
   (if (eq event :tool-call-error)
       (copy-extension-value payload)
       (copy-tree payload))
   :message (getf payload :message)
   :tool-call (getf payload :tool-call)
   :tool-result (getf payload :tool-result)
   :tool-results (getf payload :tool-results)))

(defun lifecycle-event-payload-for-handler
    (event original state)
  (case event
    (:tool-call-error
     (copy-extension-value original))
    (:context
     (list :messages (copy-list (getf state :messages))))
    (:before-agent-start
     (let ((copy (copy-list original)))
       (setf
        (getf copy :system-prompt)
        (getf state :system-prompt))
       copy))
    (:message-end
     (let ((copy (copy-list original)))
       (setf
        (getf copy :message)
        (getf state :message))
       copy))
    (:input
     (let ((copy (copy-list original)))
       (setf
        (getf copy :text) (getf state :text)
       (getf copy :images) (getf state :images))
       copy))
    (:before-provider-request
     (list
      :payload
      (copy-tree (getf state :payload))))
    (:before-provider-headers
     (list :headers (getf state :headers)))
    (otherwise (copy-tree original))))

(defun initial-lifecycle-state (event payload)
  (case event
    (:context
     (list :messages (copy-list (getf payload :messages))))
    (:before-agent-start
     (list
      :messages nil
      :system-prompt (getf payload :system-prompt)
      :modified-p nil))
    (:message-end
     (list :message (getf payload :message)
           :modified-p nil))
    (:input
     (list
      :text (getf payload :text)
      :images (getf payload :images)
      :modified-p nil))
    (:resources-discover
     (list
      :skill-paths nil
      :prompt-paths nil
      :theme-paths nil))
    (:before-provider-request
     (list :payload (getf payload :payload)))
    (:before-provider-headers
     (list :headers (getf payload :headers)))
    (otherwise nil)))

(defun merge-lifecycle-result
    (event state result)
  (case event
    ((:session-before-switch
      :session-before-fork
      :session-before-compact
      :session-before-tree)
     result)
    (:context
     (when result
       (setf
        (getf state :messages)
        (copy-list (getf result :messages))))
     state)
    (:before-agent-start
     (when result
       (let ((sentinel (list :missing)))
         (let ((message (getf result :message sentinel))
               (system-prompt
                 (getf result :system-prompt sentinel)))
           (unless (eq message sentinel)
             (setf
              (getf state :messages)
              (nconc
               (getf state :messages)
               (list message))))
           (unless (eq system-prompt sentinel)
             (setf
              (getf state :system-prompt)
              system-prompt
              (getf state :modified-p)
              t)))))
     state)
    (:message-end
     (when result
       (setf
        (getf state :message)
        (getf result :message)
        (getf state :modified-p)
        t))
     state)
    (:input
     (when result
       (case (getf result :action)
         (:transform
          (setf
           (getf state :text) (getf result :text)
           (getf state :modified-p) t)
          (let ((sentinel (list :missing)))
            (let ((images
                    (getf result :images sentinel)))
              (unless (eq images sentinel)
                (setf
                 (getf state :images) images)))))
         (:handled
          (setf (getf state :handled-p) t))))
     state)
    (:resources-discover
     (when result
       (dolist
           (key
            '(:skill-paths
              :prompt-paths
              :theme-paths))
         (setf
          (getf state key)
          (nconc
           (getf state key)
           (copy-list (getf result key))))))
     state)
    (:before-provider-request
     (cond
       ((typep result
               'provider-request-replacement)
        (setf
         (getf state :payload)
         (provider-request-replacement-payload
          result)))
       (result
        (setf (getf state :payload)
              result)))
     state)
    (otherwise state)))

(defun finalize-lifecycle-state (event state last-result)
  (case event
    ((:session-before-switch
      :session-before-fork
      :session-before-compact
      :session-before-tree)
     last-result)
    (:tool-call-error last-result)
    (:context
     (list :messages (copy-list (getf state :messages))))
    (:before-agent-start
     (let ((result nil))
       (when (getf state :messages)
         (setf
          (getf result :messages)
          (copy-list (getf state :messages))))
       (when (getf state :modified-p)
         (setf
          (getf result :system-prompt)
          (getf state :system-prompt)))
       result))
    (:message-end
     (list :message (getf state :message)))
    (:input
     (cond
       ((getf state :handled-p)
        '(:action :handled))
       ((getf state :modified-p)
        (list
         :action :transform
         :text (getf state :text)
         :images (getf state :images)))
       (t '(:action :continue))))
    (:project-trust
     last-result)
    (:resources-discover
     (list
      :skill-paths
      (copy-list (getf state :skill-paths))
      :prompt-paths
      (copy-list (getf state :prompt-paths))
      :theme-paths
      (copy-list (getf state :theme-paths))))
    (:before-provider-request
     (getf state :payload))
    (:before-provider-headers
     (getf state :headers))
    (:user-bash
     last-result)
    (otherwise nil)))

(defun run-extension-lifecycle-hooks
    (host event &key payload)
  (unless
      (and
       (member event +extension-hook-events+)
       (not
        (member
         event
         '(:turn-start
           :turn-end
           :tool-call-before
           :tool-call-after))))
    (error
     'extension-execution-error
     :message
     (format nil "Unsupported lifecycle event: ~S" event)))
  (let* ((snapshot
           (extension-host-current-snapshot host))
         (definitions
           (copy-list
            (gethash
             event
             (extension-snapshot-hooks snapshot))))
         (state (initial-lifecycle-state event payload))
         (last-result nil)
         (held (acquire-extension-snapshot host snapshot)))
    (unwind-protect
         (sb-thread:with-recursive-lock
             ((extension-host-hook-lock host))
           (dolist (definition definitions)
             (handler-case
                 (let* ((handler-payload
                          (lifecycle-event-payload-for-handler
                           event payload state))
                        (result
                          (call-with-extension-definition
                           host snapshot definition
                           (lambda (context)
                             (funcall
                              (extension-hook-definition-handler
                               definition)
                              (make-lifecycle-event
                               event handler-payload)
                              context)))))
                   (validate-lifecycle-result
                    event result handler-payload)
                   (when result
                     (setf last-result result))
                   (setf
                    state
                    (merge-lifecycle-result
                     event state result))
                   (when
                       (or
                        (and
                         (member
                          event
                          '(:session-before-switch
                            :session-before-fork
                            :session-before-compact
                            :session-before-tree))
                         result
                         (getf result :cancel-p))
                        (and
                         (eq event :input)
                         (getf state :handled-p))
                        (and
                         (eq event :project-trust)
                         result
                         (member
                          (getf result :trusted)
                          '(:yes :no)))
                        (and
                         (eq event :user-bash)
                         result)
                        (and
                         (eq event :tool-call-error)
                         result))
                     (return)))
               (condition (condition)
                 (notify-extension-failure
                  host definition "Lifecycle hook"
                  condition)))))
      (release-acquired-extension-snapshot host held))
    (finalize-lifecycle-state
     event state last-result)))
