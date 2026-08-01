(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defclass footer-sync-test-terminal
    (cadr-tui::virtual-terminal)
  ((inputs
    :initarg :inputs
    :accessor footer-sync-test-terminal-inputs)
   (reads
    :initform 0
    :accessor footer-sync-test-terminal-reads)
   (before-second-read
    :initarg :before-second-read
    :initform (constantly nil)
    :accessor
    footer-sync-test-terminal-before-second-read)
   (before-read-number
    :initarg :before-read-number
    :initform 2
    :accessor footer-sync-test-terminal-before-read-number)))

(defmethod cadr-tui:terminal-read-input
    ((terminal footer-sync-test-terminal))
  (when
      (= (footer-sync-test-terminal-before-read-number terminal)
         (incf
          (footer-sync-test-terminal-reads terminal)))
    (funcall
     (footer-sync-test-terminal-before-second-read
      terminal)))
  (or
   (pop (footer-sync-test-terminal-inputs terminal))
   ""))

(defclass progress-event-test-terminal
    (footer-sync-test-terminal)
  ((progress-values
    :initform nil
    :accessor progress-event-test-terminal-values)))

(defmethod cadr-tui:terminal-set-progress
    ((terminal progress-event-test-terminal) active-p)
  (push
   (not (null active-p))
   (progress-event-test-terminal-values terminal))
  (not (null active-p)))

(defun footer-sync-submit-input (text)
  (format nil "~A~C" text #\Return))

(defun rendered-footer-text (state)
  (multiple-value-bind (lines row column)
      (cadr-cli::render-tui-state
       state
       (cadr-tui:make-multiline-editor)
       100 8)
    (declare (ignore row column))
    (format nil "~{~A~^~%~}" lines)))

(defun goal9-complete-theme-object
    (&key (name "custom")
          (accent "#010203")
          vars
          omit-thinking-max-p)
  (let ((colors
          (make-hash-table :test #'equal))
        (object
          (make-hash-table :test #'equal)))
    (dolist
        (entry
         cadr-cli::+tui-theme-json-color-map+)
      (unless
          (and
           omit-thinking-max-p
           (string= (car entry)
                    "thinkingMax"))
        (setf
         (gethash (car entry) colors)
         (or
          (cdr
           (assoc
            (cdr entry)
            cadr-tui::+dark-theme-colors+))
          "#010203"))))
    (setf
     (gethash "accent" colors) accent
     (gethash "name" object) name
     (gethash "colors" object) colors)
    (when vars
      (setf
       (gethash "vars" object)
       vars))
    object))

(defun goal9-complete-theme-json
    (&rest arguments)
  (cadr-ai::stringify-json
   (apply #'goal9-complete-theme-object
          arguments)))

(test successful-login-synchronizes-footer-model
  (with-test-directory (directory)
    (let* ((auth-path
             (merge-pathnames "auth.json" directory))
           (model-consumer nil)
           (selected-model "startup-model")
           (changed-provider nil)
           (changed-action nil)
           (terminal
             (make-instance
              'footer-sync-test-terminal
              :columns 100 :rows 8
              :inputs
              (list
               (footer-sync-submit-input
                "/login openai")
               (footer-sync-submit-input "")
               (footer-sync-submit-input
                "/quit"))
              :before-read-number 3))
           (mock-login-function
             (lambda
                 (path &key output auth-url-function)
               (declare (ignore output auth-url-function))
               (cadr-ai:write-auth-credential
                path
                (cadr-ai:make-oauth-credential
                 :provider :openai-codex
                 :access "access"
                 :refresh "refresh"
                 :expires
                 (+ (cadr-ai::unix-milliseconds)
                    1000000)
                 :account-id "account")))))
      (let ((state
              (cadr-cli::run-tui
               (constantly nil)
               :model "startup-model"
               :terminal terminal
               :set-model-consumer
               (lambda (consumer)
                 (setf model-consumer consumer))
               :command-function
               (lambda (line)
                 (let ((cadr-cli::*openai-login-function*
                         mock-login-function))
                   (cadr-cli:handle-auth-command
                    line
                    :auth-path auth-path
                    :output
                    (make-string-output-stream)
                    :on-change
                    (lambda (provider action)
                      (setf changed-provider provider
                            changed-action action)
                      (setf selected-model "gpt-5.5")
                      (funcall model-consumer
                               selected-model))))))))
        (is (eq :openai-codex changed-provider))
        (is (eq :login changed-action))
        (is (typep
             (cadr-ai:read-auth-credential
              auth-path :openai-codex)
             'cadr-ai:oauth-credential))
        (is (string= "gpt-5.5"
                     (cadr-cli::tui-state-model state)))
        (let ((footer (rendered-footer-text state)))
          (is (search "gpt-5.5" footer))
          (is (null (search "startup-model" footer))))))))

(test model-selection-synchronizes-footer-model
  (let* ((model-consumer nil)
         (selected-model "startup-model")
         (target (list :model "gpt-5.6-luna"))
         (terminal
           (make-instance
            'footer-sync-test-terminal
            :columns 100 :rows 8
            :inputs
            (list
             (footer-sync-submit-input
              "/model gpt-5.6-luna")
             (footer-sync-submit-input
              "/quit")))))
    (let ((state
            (cadr-cli::run-tui
             (constantly nil)
             :model "startup-model"
             :terminal terminal
             :set-model-consumer
             (lambda (consumer)
               (setf model-consumer consumer))
             :resolve-model-reference-function
             (lambda (reference)
               (and
                (string= reference "gpt-5.6-luna")
                target))
             :on-model-selected
             (lambda (model)
               (is (eq target model))
               (setf selected-model "gpt-5.6-luna")
               (funcall model-consumer selected-model)
               nil))))
      (is (string= "gpt-5.6-luna"
                   (cadr-cli::tui-state-model state)))
      (let ((footer (rendered-footer-text state)))
        (is (search "gpt-5.6-luna" footer))
        (is (null (search "startup-model" footer)))))))

(test goal9-footer-refreshes-all-live-fields-and-extension-statuses
  (let ((updated-p nil)
        (extension-ui nil)
        (footer-calls 0))
    (let* ((terminal
             (make-instance
              'footer-sync-test-terminal
              :columns 120 :rows 12
              :inputs
              (list
               (footer-sync-submit-input "/refresh")
               (footer-sync-submit-input "/quit"))))
           (state
             (cadr-cli::run-tui
              (constantly nil)
              :model "startup"
              :terminal terminal
              :set-extension-ui-function
              (lambda (function)
                (setf extension-ui function))
              :footer-state-function
              (lambda ()
                (incf footer-calls)
                (if updated-p
                    (list
                     :model "live-model"
                     :provider :openai-codex
                     :thinking :high
                     :context-window 200000
                     :context-percent 12.5d0
                     :auto-compact-p nil
                     :session-name "live-session"
                     :multiple-providers-p t
                     :subscription-p t
                     :input 10
                     :output 20
                     :cache-read 30
                     :cache-write 40
                     :latest-cache-hit-rate 75d0
                     :cost 0.25d0
                     :cost-known-p t)
                    (list :model "startup")))
              :command-function
              (lambda (line)
                (when (string= line "/refresh")
                  (setf updated-p t)
                  (funcall
                   extension-ui
                   :set-status
                   (list
                    :key "extension"
                    :text "ready")))
                t))))
      (is (string=
           "live-model"
           (cadr-cli::tui-state-model state)))
      (is (eq :openai-codex
              (cadr-cli::tui-state-provider state)))
      (is (eq :high
              (cadr-cli::tui-state-thinking state)))
      (is (= 200000
             (cadr-cli::tui-state-context-window
              state)))
      (is (= 12.5d0
             (cadr-cli::tui-state-context-percent
              state)))
      (is (not
           (cadr-cli::tui-state-auto-compact-p
            state)))
      (is (string=
           "live-session"
           (cadr-cli::tui-state-session-name state)))
      (is (cadr-cli::tui-state-multiple-providers-p
           state))
      (is (cadr-cli::tui-state-subscription-p state))
      (is (= 10
             (cadr-cli::tui-state-input-tokens state)))
      (is (= 20
             (cadr-cli::tui-state-output-tokens state)))
      (is (= 30
             (cadr-cli::tui-state-cache-read-tokens
              state)))
      (is (= 40
             (cadr-cli::tui-state-cache-write-tokens
              state)))
      (is (= 75d0
             (cadr-cli::tui-state-latest-cache-hit-rate
              state)))
      (is (= 0.25d0
             (cadr-cli::tui-state-cost state)))
      (is (cadr-cli::tui-state-cost-known-p state))
      (is (string=
           "ready"
           (cdr
            (assoc
             "extension"
             (cadr-cli::tui-state-statuses state)
             :test #'string=)))))))

(test goal9-footer-thinking-refresh-synchronizes-editor-border-without-overwriting-bash
  (let ((state
          (cadr-cli::make-tui-state
           :model "mock"))
        (editor
          (cadr-tui:make-multiline-editor)))
    (cadr-cli::apply-tui-footer-state
     state (list :thinking :high))
    (cadr-cli::synchronize-tui-editor-border
     state editor)
    (is (eq
         :thinking-high
         (cadr-tui::multiline-editor-border-color-key
          editor)))
    (cadr-tui:editor-set-border-mode editor :bash)
    (cadr-cli::apply-tui-footer-state
     state (list :thinking :low))
    (cadr-cli::synchronize-tui-editor-border
     state editor)
    (is (eq
         :bash-mode
         (cadr-tui::multiline-editor-border-color-key
          editor)))
    (cadr-tui:editor-set-border-mode
     editor :thinking :high)
    (cadr-cli::apply-tui-footer-state
     state (list :thinking nil))
    (cadr-cli::synchronize-tui-editor-border
     state editor)
    (is (eq
         :thinking-off
         (cadr-tui::multiline-editor-border-color-key
          editor)))))

(test goal9-terminal-progress-setting-is-read-for-every-agent-event
  (let ((event-consumer nil)
        (enabled-p nil)
        (setting-reads nil))
    (let* ((terminal
             (make-instance
              'progress-event-test-terminal
              :columns 80 :rows 12
              :inputs
              (list
               (footer-sync-submit-input "/progress")
               (footer-sync-submit-input "/quit"))))
           (state
             (cadr-cli::run-tui
              (constantly nil)
              :model "mock"
              :terminal terminal
              :set-event-consumer
              (lambda (consumer)
                (setf event-consumer consumer))
              :show-terminal-progress-function
              (lambda ()
                (push enabled-p setting-reads)
                enabled-p)
              :command-function
              (lambda (line)
                (when (string= line "/progress")
                  (setf enabled-p t)
                  (funcall
                   event-consumer
                   (cadr-agent::make-agent-event
                    :type :agent-start))
                  (setf enabled-p nil)
                  (funcall
                   event-consumer
                   (cadr-agent::make-agent-event
                    :type :message-update))
                  (setf enabled-p t)
                  (funcall
                   event-consumer
                   (cadr-agent::make-agent-event
                    :type :compaction-start))
                  (funcall
                   event-consumer
                   (cadr-agent::make-agent-event
                    :type :compaction-end))
                  (setf enabled-p nil))
                t))))
      (declare (ignore state))
      (is (equal
           '(nil t nil t)
           (progress-event-test-terminal-values
            terminal)))
      (is (equal
           '(t nil t t)
           (subseq
            (reverse setting-reads)
            0 4))))))

(test goal9-footer-auto-compact-follows-live-footer-state
  (let ((state
          (cadr-cli::make-tui-state
           :model "mock"
           :context-window 100000
           :auto-compact-p nil)))
    (is (null
         (search
          "(auto)"
          (rendered-footer-text state))))
    (cadr-cli::apply-tui-footer-state
     state (list :auto-compact-p t))
    (is (search
         "(auto)"
         (rendered-footer-text state)))
    (cadr-cli::apply-tui-footer-state
     state (list :auto-compact-p nil))
    (is (null
         (search
          "(auto)"
          (rendered-footer-text state))))))

(test goal9-live-editor-input-switches-bash-border-from-current-prefix
  (let ((state
          (cadr-cli::make-tui-state
           :model "mock"
           :thinking :high))
        (editor
          (cadr-tui:make-multiline-editor)))
    (cadr-cli::handle-tui-editor-event
     state editor
     (cadr-tui:make-input-event
      :kind :text :text "  !"))
    (is (eq
         :bash-mode
         (cadr-tui::multiline-editor-border-color-key
          editor)))
    (cadr-cli::handle-tui-editor-event
     state editor
     (cadr-tui:make-input-event
      :kind :backspace))
    (is (eq
         :thinking-high
         (cadr-tui::multiline-editor-border-color-key
          editor)))
    (cadr-tui:editor-set-border-mode editor :bash)
    (cadr-cli::synchronize-tui-editor-border
     state editor)
    (is (eq
         :bash-mode
         (cadr-tui::multiline-editor-border-color-key
          editor)))
    (cadr-tui:editor-set-text editor "ordinary")
    (cadr-cli::synchronize-tui-editor-input-border
     state editor)
    (cadr-cli::apply-tui-footer-state
     state (list :thinking :low))
    (cadr-cli::synchronize-tui-editor-border
     state editor)
    (is (eq
         :thinking-low
         (cadr-tui::multiline-editor-border-color-key
          editor)))))

(test goal9-cli-terminal-progress-setting-is-live
  (with-test-directory (directory)
    (let ((manager
            (cadr-cli::make-settings-manager
             :global-path
             (merge-pathnames "settings.json"
                              directory)
             :project-path
             (merge-pathnames "project.json"
                              directory)
             :project-trusted-p nil)))
      (is (not
           (cadr-cli::settings-show-terminal-progress-p
            manager)))
      (cadr-cli::settings-set-nested
       manager "terminal" "showTerminalProgress"
       t :scope :global)
      (is
       (cadr-cli::settings-show-terminal-progress-p
        manager))
      (cadr-cli::settings-set-nested
       manager "terminal" "showTerminalProgress"
       nil :scope :global)
      (is (not
           (cadr-cli::settings-show-terminal-progress-p
            manager))))))

(test goal9-footer-hides-known-zero-cost-without-subscription
  (let ((state
          (cadr-cli::make-tui-state
           :model "mock")))
    (setf
     (cadr-cli::tui-state-cost-known-p state)
     t
     (cadr-cli::tui-state-cost state)
     0d0)
    (is (null
         (search
          "$0.000"
          (rendered-footer-text state))))))

(test goal9-extension-theme-update-is-serialized-with-rendering
  (let* ((extension-ui nil)
         (updated-p nil)
         (object
           (goal9-complete-theme-object
            :name "custom"
            :accent "#112233"))
         (terminal
           (make-instance
            'footer-sync-test-terminal
            :columns 80 :rows 12
            :inputs
            (list
             (footer-sync-submit-input "/theme")
             (footer-sync-submit-input "/quit")))))
    (unwind-protect
         (progn
           (cadr-cli::run-tui
            (constantly nil)
            :model "mock"
            :terminal terminal
            :set-extension-ui-function
            (lambda (function)
              (setf extension-ui function))
            :theme-function
            (lambda ()
              (if updated-p
                  (list
                   :name "custom"
                   :object object)
                  (list :name "dark")))
            :set-theme-function
            (lambda (theme)
              (declare (ignore theme))
              (setf updated-p t)
              (list :success t))
            :command-function
            (lambda (line)
              (when (string= line "/theme")
                (funcall
                 extension-ui
                 :set-theme
                 (list :theme "custom")))
              t))
           (is (string=
                "#112233"
                (cadr-tui:theme-color-value
                 :accent))))
      (cadr-tui:reset-current-theme))))

(test oauth-auth-url-renders-once-without-session-prefix
  (let* ((url
           "https://auth.openai.com/oauth/authorize?response_type=code&client_id=test&redirect_uri=http%3A%2F%2Flocalhost")
         (lines
           (cadr-cli::render-auth-url-lines url 48))
         (plain
           (mapcar #'cadr-tui::strip-ansi lines))
         (joined
           (format nil "~{~A~^~%~}" plain)))
    (is (not
         (search
          "Open this URL"
          joined)))
    (is (not (search "session>" joined)))
    (is (search url
                (format nil "~{~A~}" plain)))
    (is (search "Ctrl+click to open" joined))))

(test goal9-b-tui-bash-stream-does-not-create-session-notices
  (with-test-directory (directory)
    (let* ((notifications nil)
           (state (cadr-cli::make-tui-state))
           (editor (cadr-tui:make-multiline-editor))
           (frontend
             (cadr-cli::make-notification-output-stream
              (lambda (text)
                (push text notifications)
                (cadr-cli::add-tui-notice state text)))))
      ;; Bash writes and flushes each streamed character.  The TUI must keep
      ;; that stream out of the generic notice channel or it renders visible
      ;; `session> <char>` rows.
      (let ((cadr-cli::*bash-live-output*
              (cadr-cli::bash-live-output-for-mode
               :tui frontend)))
        (multiple-value-bind (content details)
            (cadr-cli::run-bash-command
             directory "printf alphadeltagamma" 2)
          (declare (ignore details))
          (is (search
               "alphadeltagamma"
               (cadr-ai:text-content-text
                (first content))))))
      (is (null notifications))
      (multiple-value-bind (lines row column)
          (cadr-cli::render-tui-state state editor 80 24)
        (declare (ignore row column))
        (let ((screen
                (format
                 nil "~{~A~%~}"
                 (mapcar
                  #'cadr-tui:strip-terminal-sequences
                  lines))))
          (is (null (search "session>" screen)))
          (is (null (search "alphadeltagamma" screen))))))))

(test goal9-b-nonzero-bash-tool-renders-error-state
  (with-test-directory (directory)
    (let* ((handle
             (cadr-ai:make-faux-provider
              :token-min 64 :token-max 64))
           (model (cadr-ai:faux-get-model handle))
           (state
             (cadr-cli::make-tui-state
              :model "faux-1"))
           (tool (cadr-cli::make-bash-tool directory)))
      (cadr-ai:faux-set-responses
       handle
       (list
        (cadr-ai:faux-assistant-message
         (list
          (cadr-ai:faux-tool-call
           "bash"
           (args
            "command"
            "printf 'expected-error\\n' >&2; exit 7")
           :id "goal9-bash-error"))
         :stop-reason :tool-use)
        (cadr-ai:faux-assistant-message "done")))
      (let ((agent
              (cadr-agent:make-agent
               :provider :faux
               :model model
               :tools (list tool)
               :stream-function
               (lambda (provider selected-model context on-event
                        &rest options)
                 (declare (ignore provider))
                 (apply
                  #'cadr-ai:faux-stream
                  handle selected-model context on-event options))
               :on-event
               (lambda (event)
                 (cadr-cli::tui-handle-agent-event
                  state event)))))
        (unwind-protect
             (cadr-agent:agent-prompt agent "run the failing command")
          (cadr-agent:agent-shutdown agent)))
      (let* ((entry
               (find
                :tool
                (cadr-cli::tui-state-entries state)
                :key #'cadr-cli::tui-entry-type))
             (block
               (and entry
                    (cadr-cli::tui-entry-tool-block entry))))
        (is (not (null block)))
        (when block
          (is (eq :error
                  (cadr-tui:tool-block-status block)))
          (is (search
               "Command exited with code 7"
               (cadr-tui:tool-block-output block)))
          (let ((rendered
                  (format
                   nil "~{~A~^~%~}"
                   (cadr-tui:render-tool-block block 80))))
            (is (search "$ printf" rendered))
            (is (null (search "×" rendered)))
            (is (null (search "✓" rendered)))))))))

(test goal9-b-tool-events-record-runtime-for-the-live-tui
  (let* ((now 20d0)
         (state (cadr-cli::make-tui-state))
         (call
           (cadr-ai:make-tool-call
            :id "timed-bash"
            :name "bash"
            :arguments (args "command" "exit 7")))
         (result
           (cadr-ai:make-tool-result-message
            :tool-call-id "timed-bash"
            :tool-name "bash"
            :is-error t
            :content
            (list
             (cadr-ai:make-text-content
              :text "Command exited with code 7")))))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :tool-execution-start
      :tool-call call)
     :clock-function (lambda () now))
    (incf now 0.04d0)
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :tool-execution-end
      :tool-call call
      :tool-result result)
     :clock-function (lambda () now))
    (let* ((entry
             (find
              :tool
              (cadr-cli::tui-state-entries state)
              :key #'cadr-cli::tui-entry-type))
           (block (cadr-cli::tui-entry-tool-block entry))
           (rendered
             (cadr-tui:strip-terminal-sequences
              (format
               nil "~{~A~%~}"
               (cadr-tui:render-tool-block
                block 60 :now now)))))
      (is (search "Command exited with code 7" rendered))
      (is (search "Took 0.0s" rendered)))))

(test dispatch-user-input-is-shared-by-frontends
  (let ((prompts nil)
        (commands nil))
    (is (eq :prompt
            (cadr-cli::dispatch-user-input
             "hello"
             (lambda (text) (push text prompts))
             :command-function
             (lambda (line) (push line commands) nil))))
    (is (equal '("hello") prompts))
    (is (eq :command
            (cadr-cli::dispatch-user-input
             "/known arg"
             (lambda (text) (push text prompts))
             :command-function
             (lambda (line)
               (push line commands)
               (values t "done")))))
    (multiple-value-bind (kind value)
        (cadr-cli::dispatch-user-input
         "/template x"
         (lambda (text) (push text prompts))
         :command-function (constantly nil)
         :template-function
         (lambda (line)
           (declare (ignore line))
           (values "expanded" t)))
      (declare (ignore value))
      (is (eq :prompt kind)))
    (is (equal '("expanded" "hello") prompts))
    (is (eq :unknown-command
            (cadr-cli::dispatch-user-input
             "/missing"
             (lambda (text) (push text prompts))
             :command-function (constantly nil))))))

(test tui-editor-autocomplete-exposes-only-real-cli-commands
  (let* ((provider
           (cadr-cli::make-tui-autocomplete-provider
            :base-path (uiop:getcwd)))
         (suggestions
           (cadr-tui:autocomplete-get-suggestions
            provider '("/") 0 1))
         (values
           (mapcar
            #'cadr-tui:autocomplete-item-value
            (cadr-tui:autocomplete-suggestions-items
             suggestions))))
    (is (member "model" values :test #'string=))
    (is (member "scoped-models" values
                :test #'string=))
    (is (not (member "sessions" values :test #'string=)))
    (is (member "settings" values :test #'string=))
    (is (member "login" values :test #'string=))
    (is (member "reload" values :test #'string=))
    (is (not (member "redo" values :test #'string=)))))

(test tui-selection-policy-honors-flag-and-tty-state
  (flet ((terminal-p (stream direction)
           (declare (ignore stream direction))
           t)
         (not-terminal-p (stream direction)
           (declare (ignore stream direction))
           nil))
    (is (cadr-cli::should-use-tui-p
         nil
         :terminal-p-function #'terminal-p))
    (is (not (cadr-cli::should-use-tui-p
              t
              :terminal-p-function #'terminal-p)))
    (is (not (cadr-cli::should-use-tui-p
              nil
              :terminal-p-function #'not-terminal-p)))))

(test cli-advertises-tui-renderer-selection
  (let ((usage
          (with-output-to-string (stream)
            (cadr-cli::print-cli-usage stream))))
    (is (search "--no-tui" usage))
    (is (search "--alt" usage))
    (is (null (search "--yolo" usage)))))

(test native-cli-parser-handles-values-flags-and-repeats
  (let ((arguments
          (cadr-cli::parse-cli-arguments
           '("--provider=deepseek"
             "--model" "deepseek-v4-flash"
             "--extension" "one.lisp"
             "--extension=two.lisp"
             "--continue"
             "--alt"
             "--no-tui"))))
    (is (string=
         "deepseek"
         (cadr-cli::cli-arguments-provider
          arguments)))
    (is (string=
         "deepseek-v4-flash"
         (cadr-cli::cli-arguments-model
          arguments)))
    (is (equal
         '("one.lisp" "two.lisp")
         (cadr-cli::cli-arguments-extensions
          arguments)))
    (is (cadr-cli::cli-arguments-continue-p
         arguments))
    (is (cadr-cli::cli-arguments-alt-p
         arguments))
    (is (cadr-cli::cli-arguments-no-tui-p
         arguments)))
  (signals cadr-ai:configuration-error
    (cadr-cli::parse-cli-arguments
     '("--model" "--continue"))))

(test alt-screen-tui-state-preserves-full-document
  (let ((state
          (cadr-cli::make-tui-state
           :model "gpt-5.6-luna"
           :session "session-alt"))
        (editor
          (cadr-tui:make-multiline-editor)))
    (loop for index from 1 to 12
          do
          (cadr-cli::add-tui-notice
           state
           (format nil "notice-~D" index)))
    (multiple-value-bind
          (main-lines main-row main-column)
        (cadr-cli::render-tui-state
         state editor 40 8)
      (declare (ignore main-row main-column))
      (is (= 8 (length main-lines)))
      (is (null
           (find "session> notice-1"
                 main-lines
                 :test #'string=))))
    (multiple-value-bind
          (alt-lines alt-row alt-column)
        (cadr-cli::render-tui-state
         state editor 40 8
         :full-document-p t)
      (declare (ignore alt-column))
      (is (> (length alt-lines) 8))
      (is (find "session> notice-1"
                alt-lines
                :test #'string=))
      (is (< alt-row
             (length alt-lines))))))

(test idle-status-spacing-is-reserved-only-on-main-screen
  (is (= 2
         (length
          (cadr-cli::render-tui-status-indicator
           nil 20 :reserve-idle-p t))))
  (is (null
       (cadr-cli::render-tui-status-indicator
        nil 20 :reserve-idle-p nil)))
  (is (= 2
         (length
          (cadr-cli::render-tui-status-indicator
           "Working..." 20
           :reserve-idle-p nil)))))

(test interactive-renderer-selects-alternate-screen-only-when-requested
  (let* ((main-terminal
           (cadr-tui:make-virtual-terminal))
         (main-renderer
           (cadr-cli::make-interactive-renderer
            main-terminal nil))
         (alt-terminal
           (cadr-tui:make-virtual-terminal))
         (alt-renderer
           (cadr-cli::make-interactive-renderer
            alt-terminal t)))
    (is
     (not
      (cadr-tui:alt-screen-renderer-p
       main-renderer)))
    (is
     (cadr-tui:alt-screen-renderer-p
      alt-renderer))
    (cadr-tui:renderer-start main-renderer)
    (cadr-tui:renderer-start alt-renderer)
    (is
     (null
      (find-if
       (lambda (write)
         (search
          (format nil "~C[?1049h" #\Escape)
          write))
       (cadr-tui::virtual-writes
        main-terminal))))
    (is
     (find-if
      (lambda (write)
        (search
         (format nil "~C[?1049h" #\Escape)
         write))
      (cadr-tui::virtual-writes
       alt-terminal)))
    (cadr-tui:renderer-before-stop
     main-renderer)
    (cadr-tui:renderer-after-stop
     main-renderer)
    (cadr-tui:renderer-before-stop
     alt-renderer)
    (cadr-tui:renderer-after-stop
     alt-renderer)))

(test tui-state-projects-stream-tools-and-usage
  (let* ((state
           (cadr-cli::make-tui-state
            :model "gemini-3.6-flash"
            :context-window 100
            :session "session-1"))
         (message
           (cadr-ai:make-assistant-message
            :api :google-generative-ai
            :provider :google
            :model "gemini-3.6-flash"
            :usage
            (cadr-ai:make-usage
             :input 10 :output 4 :cache-read 2)
            :stop-reason :stop))
         (call
           (cadr-ai:make-tool-call
            :id "call-1"
            :name "read"
            :arguments (args "path" "README.md")))
         (result
           (cadr-ai:make-tool-result-message
            :tool-call-id "call-1"
            :tool-name "read"
            :content
            (list
             (cadr-ai:make-text-content
              :text "file text")))))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :message-start
      :message message))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :message-update
      :message message
      :stream-event
      (cadr-ai:make-stream-event
       :type :text-delta
       :delta "你好 **cadr**")))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :tool-execution-start
      :tool-call call))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :tool-execution-end
      :tool-call call
      :tool-result result))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :message-end
      :message message))
    (let ((editor (cadr-tui:make-multiline-editor)))
      (multiple-value-bind (lines row column)
          (cadr-cli::render-tui-state state editor 40 20)
        (declare (ignore row column))
        (let ((screen
                (cadr-tui:strip-terminal-sequences
                 (format nil "~{~A~%~}" lines))))
          (is (search "你好 cadr" screen))
          (is (search "read" screen))
          (is (search "↑10" screen))
          (is (search "↓4" screen))
          (is (search "R2" screen))
          (is (= 16d0
                 (cadr-cli::tui-state-context-percent
                  state))))))))

(test goal9-built-in-tool-titles-summarize-real-arguments
  (dolist
      (case
       (list
        (list
         "bash"
         (args "command" "printf ok" "timeout" 7)
         "printf ok")
        (list
         "read"
         (args "path" "README.md" "offset" 2
               "limit" 3)
         "README.md:2-4")
        (list
         "write"
         (args "path" "notes.txt" "content" "body")
         "notes.txt")
        (list
         "edit"
         (args
          "path" "code.lisp"
          "edits"
          (vector
           (args "oldText" "old" "newText" "new")))
         "code.lisp")
        (list
         "grep"
         (args "pattern" "needle" "path" "src"
               "glob" "*.lisp" "limit" 5)
         "/needle/ in src (*.lisp) limit 5")
        (list
         "find"
         (args "pattern" "*.lisp" "path" "src"
               "limit" 6)
         "*.lisp in src (limit 6)")
        (list
         "ls"
         (args "path" "src" "limit" 7)
         "src (limit 7)")))
    (destructuring-bind
          (name arguments expected)
        case
      (let* ((state
               (cadr-cli::make-tui-state
                :model "mock"))
             (call
               (cadr-ai:make-tool-call
                :id (format nil "call-~A" name)
                :name name
                :arguments arguments)))
        (cadr-cli::tui-handle-agent-event
         state
         (cadr-agent::make-agent-event
          :type :tool-execution-start
          :tool-call call))
        (let* ((entry
                 (car
                  (cadr-cli::tui-state-entries state)))
               (summary
                 (cadr-tui:tool-block-summary
                  (cadr-cli::tui-entry-tool-block
                   entry))))
          (is (string= expected summary))
          (is (null (search "{" summary)))
          (is (null (search "\"" summary))))))))

(test goal9-b3-user-block-spacing-and-wrapping-match-baseline
  (let* ((assistant
           (cadr-cli::make-tui-entry
            :type :assistant
            :text "previous answer"
            :content-blocks
            (list (cons :assistant "previous answer"))))
         (user
           (cadr-cli::make-tui-entry
            :type :user
            :text
            "Think for several seconds, then give exactly 12 numbered one-line steps for checking a CLI release."))
         (lines
           (mapcar
            #'cadr-tui:strip-terminal-sequences
            (cadr-cli::render-tui-entries
             (list assistant user) 86))))
    (is (equal
         '(""
           " previous answer                                                                      "
           ""
           "                                                                                      "
           " Think for several seconds, then give exactly 12 numbered one-line steps for checking "
           " a CLI release.                                                                       "
           "                                                                                      ")
         lines))))

(test goal9-b3-tool-title-copy-has-no-status-glyph-or-default-timeout
  (let* ((tool (cadr-cli:make-bash-tool #P"/tmp/"))
         (properties
           (cadr-ai::json-get
            (cadr-ai:tool-parameters tool) "properties"))
         (command
           (cadr-ai::json-get properties "command"))
         (timeout
           (cadr-ai::json-get properties "timeout")))
    (is (string= "Bash command to execute"
                 (cadr-ai::json-get command "description")))
    (is (string=
         "Timeout in seconds (optional, no default timeout)"
         (cadr-ai::json-get timeout "description")))
    (is (not (cadr-ai::json-present-p timeout "default"))))
  (let* ((state
           (cadr-cli::make-tui-state))
         (call
           (cadr-ai:make-tool-call
            :id "no-default-timeout"
            :name "bash"
            :arguments
            (args "command" "printf ok"))))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :tool-execution-start
      :tool-call call))
    (let ((block
            (cadr-cli::tui-entry-tool-block
             (first
              (cadr-cli::tui-state-entries state)))))
      (is (string=
           "printf ok"
           (cadr-tui:tool-block-summary block)))
      (setf (cadr-tui:tool-block-status block)
            :complete)
      (let ((plain
              (mapcar
               (lambda (line)
                 (string-trim
                  " "
                  (cadr-tui:strip-terminal-sequences
                   line)))
               (cadr-tui:render-tool-block block 40))))
        (is (member "$ printf ok" plain
                    :test #'string=))
        (is (null
             (search
              "timeout"
              (format nil "~{~A~%~}" plain)))))))
  (dolist
      (case
       (list
        (list :complete "printf ok"
              '("" "                                        "
                " $ printf ok                            "
                "                                        "))
        (list :error "exit 7"
              '("" "                                        "
                " $ exit 7                               "
                "                                        "))))
    (destructuring-bind (status summary expected) case
      (let* ((block
               (cadr-tui:make-tool-block
                :name "bash"
                :summary summary
                :status status
                :output ""))
             (plain
               (mapcar
                #'cadr-tui:strip-terminal-sequences
                (cadr-tui:render-tool-block block 40))))
        (is (equal expected plain)))))
  (let ((call
          (cadr-ai:make-tool-call
           :id "explicit-timeout"
           :name "bash"
           :arguments
           (args "command" "sleep 1" "timeout" 7))))
    (is (string=
         "sleep 1"
         (cadr-cli::tool-arguments-summary call)))))

(test goal9-b3-explicit-bash-timeout-never-appears-in-title
  (let* ((state (cadr-cli::make-tui-state))
         (call
           (cadr-ai:make-tool-call
            :id "explicit-timeout-title"
            :name "bash"
            :arguments
            (args "command" "sleep 1" "timeout" 10))))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :tool-execution-start
      :tool-call call))
    (let* ((block
             (cadr-cli::tui-entry-tool-block
              (first (cadr-cli::tui-state-entries state))))
           (rendered
             (format nil "~{~A~^~%~}"
                     (mapcar
                      #'cadr-tui:strip-terminal-sequences
                      (cadr-tui:render-tool-block block 60)))))
      (is (string= "sleep 1"
                   (cadr-tui:tool-block-summary block)))
      (is (search "$ sleep 1" rendered))
      (is (null (search " (timeout 10s)" rendered)))
      (is (null (search "timeout" rendered))))))

(test goal9-b3-bash-failure-tool-frame-is-an-exact-baseline-snapshot
  (let* ((block
           (cadr-tui:make-tool-block
            :name "bash"
            :summary "exit 7"
            :output "Command exited with code 7"
            :status :error
            :started-at 10d0
            :ended-at 10d0
            :collapsed-p t))
         (plain
           (mapcar
            #'cadr-tui:strip-terminal-sequences
            (cadr-tui:render-tool-block block 60))))
    (is
     (equal
      '(""
        "                                                            "
        " $ exit 7                                                   "
        " Command exited with code 7                                 "
        " Took 0.0s                                                  "
        "                                                            ")
      plain))))

(test goal9-b3-write-tool-displays-request-content-not-byte-receipt
  (let* ((state (cadr-cli::make-tui-state))
         (content (format nil "alpha~%beta~%gamma"))
         (call
           (cadr-ai:make-tool-call
            :id "write-content"
            :name "write"
            :arguments
            (args "path" "notes.txt" "content" content)))
         (result
           (cadr-ai:make-tool-result-message
            :tool-call-id "write-content"
            :tool-name "write"
            :content
            (list
             (cadr-ai:make-text-content
              :text "Successfully wrote 16 bytes to notes.txt"))
            :is-error nil)))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :tool-execution-start
      :tool-call call))
    (let ((block
            (cadr-cli::tui-entry-tool-block
             (first (cadr-cli::tui-state-entries state)))))
      (is (string= content (cadr-tui:tool-block-output block)))
      (is
       (equal
        '(""
          "                                                            "
          " write notes.txt                                            "
          " alpha                                                      "
          " beta                                                       "
          " gamma                                                      "
          "                                                            ")
        (mapcar
         #'cadr-tui:strip-terminal-sequences
         (cadr-tui:render-tool-block block 60)))))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :tool-execution-end
      :tool-call call
      :tool-result result))
    (let* ((block
             (cadr-cli::tui-entry-tool-block
              (first (cadr-cli::tui-state-entries state))))
           (plain
             (mapcar
              #'cadr-tui:strip-terminal-sequences
              (cadr-tui:render-tool-block block 60))))
      (is (string= content (cadr-tui:tool-block-output block)))
      (is
       (equal
        '(""
          "                                                            "
          " write notes.txt                                            "
          " alpha                                                      "
          " beta                                                       "
          " gamma                                                      "
          "                                                            ")
        plain)))))

(test goal9-b3-login-without-arguments-renders-auth-method-selector
  (let ((plain
          (mapcar
           #'cadr-tui:strip-terminal-sequences
           (cadr-cli::render-login-method-selector
            (cadr-cli::make-login-method-selector-state)
            80))))
    (is
     (equal
      (list
       (make-string 80 :initial-element #\─)
       ""
       " Select authentication method:"
       ""
       " → Sign in with an account"
       "   Sign in with an API key"
       ""
       " ↑↓ navigate  enter select  escape/ctrl+c cancel"
       ""
       (make-string 80 :initial-element #\─))
      plain)))
  (let ((commands nil))
    (let (terminal)
      (setf
       terminal
       (make-instance
        'footer-sync-test-terminal
        :columns 80 :rows 12
        :inputs
        (list
         (footer-sync-submit-input "/login")
         (string #\Escape)
         (footer-sync-submit-input "/quit"))
        :before-second-read
        (constantly nil)))
      (cadr-cli::run-tui
       (constantly nil)
       :model "mock"
       :terminal terminal
       :command-function
       (lambda (line)
         (push line commands)))
      (is (null commands)))))

(test goal9-b3-logout-opens-stored-provider-selector-and-removes-selection
  (let ((commands nil)
        (selected nil))
    (let (terminal)
      (setf
       terminal
       (make-instance
        'footer-sync-test-terminal
        :columns 80 :rows 14
        :inputs
        (list
         (footer-sync-submit-input "/logout")
         (footer-sync-submit-input "")
         (footer-sync-submit-input "/quit"))
        :before-second-read
        (constantly nil)))
      (cadr-cli::run-tui
       (constantly nil)
       :model "mock"
       :terminal terminal
       :command-function
       (lambda (line)
         (push line commands))
       :logout-options-function
       (lambda ()
         (list
          (cadr-cli::make-oauth-selector-option
           :id :openai-codex
           :name "OpenAI Codex"
           :auth-type :oauth
           :status
           '(:type :oauth :source "stored credential"))))
       :on-logout-selected
       (lambda (provider)
         (setf selected provider)))
      (is (eq :openai-codex selected))
      (is (null commands)))))

(test goal9-b3-api-key-login-is-masked-cancellable-and-persistent
  (let* ((option
           (cadr-cli::make-oauth-selector-option
            :id :anthropic
            :name "Anthropic"
            :auth-type :api-key
            :method-name "Anthropic API key"))
         (state
           (cadr-cli::make-api-key-input-state option)))
    (multiple-value-bind (action value)
        (cadr-cli::api-key-input-state-handle-event
         state
         (cadr-tui:make-input-event
          :kind :text
          :text "secret-value"))
      (declare (ignore value))
      (is (null action)))
    (let ((rendered
            (format
             nil "~{~A~^~%~}"
             (mapcar
              #'cadr-tui:strip-terminal-sequences
              (cadr-cli::render-api-key-input-state
               state 80)))))
      (is (search "Login to Anthropic" rendered))
      (is (search "************" rendered))
      (is (null (search "secret-value" rendered))))
    (multiple-value-bind (action value)
        (cadr-cli::api-key-input-state-handle-event
         state
         (cadr-tui:make-input-event :kind :escape))
      (is (eq :cancel action))
      (is (null value))))
  (with-test-directory (directory)
    (let* ((auth-path
             (merge-pathnames "auth.json" directory))
           (registry
             (cadr-cli:make-model-registry
              :path
              (merge-pathnames "models.json" directory)
              :credentials
              (cadr-cli:make-file-auth-storage
               auth-path)))
           (provider-options
             (cadr-cli::login-provider-options
              (cadr-ai:list-provider-definitions)
              :auth-type :api-key))
           (provider-index
             (position
              :anthropic provider-options
              :key
              #'cadr-cli::oauth-selector-option-id))
           (selected-provider nil)
           (refresh-count 0)
           (terminal
             (make-instance
              'footer-sync-test-terminal
              :columns 80 :rows 16
              :inputs
              (append
               (list
                (footer-sync-submit-input "/login")
                (format nil "~C[B" #\Escape)
                (string #\Return))
               (loop repeat provider-index
                     collect
                     (format nil "~C[B" #\Escape))
               (list
                (string #\Return)
                (footer-sync-submit-input
                 "persisted-secret")
                (footer-sync-submit-input "/quit")))
              :before-second-read
              (constantly nil))))
      (cadr-cli::run-tui
       (constantly nil)
       :model "mock"
       :terminal terminal
       :api-key-login-function
       (lambda (provider key)
         (setf selected-provider provider)
         (cadr-cli::model-registry-login-api-key
          registry provider key)
         (incf refresh-count)))
      (is (eq :anthropic selected-provider))
      (is (= 1 refresh-count))
      (let ((credential
              (cadr-cli:auth-storage-read
               (cadr-cli::model-registry-credentials registry)
               selected-provider)))
        (is (typep credential
                   'cadr-ai:api-key-credential))
        (is (string=
             "persisted-secret"
             (cadr-ai:api-key-credential-key
              credential))))
      (is (find
           selected-provider
           (cadr-cli::model-registry-available-models
            registry
            :auth-path auth-path)
           :key #'cadr-ai:model-provider)))))

(test goal9-real-edit-tool-result-reaches-semantic-diff-rendering
  (with-test-directory (directory)
    (let* ((file
             (merge-pathnames "code.txt" directory))
           (tool
             (cadr-cli:make-edit-tool directory))
           (call
             (cadr-ai:make-tool-call
              :id "real-edit"
              :name "edit"
              :arguments
              (args
               "path" "code.txt"
               "edits"
               (vector
                (args "oldText" "beta"
                      "newText" "BETA")))))
           (agent
             (cadr-agent:make-agent
              :tools (list tool)))
           (prepared nil)
           (outcome nil)
           (result nil)
           (state
             (cadr-cli::make-tui-state
              :model "mock")))
      (write-text
       file
       (format nil "alpha~%beta~%gamma~%"))
      ;; Execution must occur after the fixture exists.
      (setf
       prepared
       (cadr-agent::prepare-tool-execution agent call)
       outcome
       (cadr-agent::execute-prepared-tool prepared)
       result
       (cadr-agent::tool-outcome-result outcome))
      (is (not
           (cadr-ai:tool-result-message-is-error
            result)))
      (let ((diff
              (getf
               (cadr-ai:tool-result-message-details
                result)
               :diff)))
        (is (stringp diff))
        (is (search "-2 beta" diff))
        (is (search "+2 BETA" diff)))
      (let ((details
              (cadr-ai:tool-result-message-details
               result)))
        (is (= 2 (getf details :first-changed-line)))
        (is (search "--- code.txt"
                    (getf details :patch)))
        (is (search "@@ -1,3 +1,3 @@"
                    (getf details :patch))))
      (multiple-value-bind (diff first-changed-line)
          (cadr-cli::generate-edit-display-diff
           (format nil "alpha~%beta~%")
           (format nil "alpha~%")
           (list
            (cadr-cli::make-replacement
             :start 6 :end 11
             :old (format nil "beta~%")
             :new "")))
        (is (= 2 first-changed-line))
        (is (search "-2 beta" diff)))
      (cadr-cli::tui-handle-agent-event
       state
       (cadr-agent::make-agent-event
        :type :tool-execution-start
        :tool-call call))
      (cadr-cli::tui-handle-agent-event
       state
       (cadr-agent::make-agent-event
        :type :tool-execution-end
        :tool-call call
        :tool-result result))
      (let* ((entry
               (car
                (cadr-cli::tui-state-entries state)))
             (block
               (cadr-cli::tui-entry-tool-block entry))
             (caps
               (cadr-tui:make-terminal-capabilities
                :true-color-p t)))
        (is (string=
             "code.txt"
             (cadr-tui:tool-block-summary block)))
        (is (search "-2 beta"
                    (cadr-tui:tool-block-output block)))
        (is (search "+2 BETA"
                    (cadr-tui:tool-block-output block)))
        (is (null
             (search "Applied 1 replacement"
                     (cadr-tui:tool-block-output block))))
        (cadr-tui:set-current-theme
         :dark :capabilities caps)
        (unwind-protect
             (let ((rendered
                     (format
                      nil "~{~A~^~%~}"
                      (cadr-cli::render-tui-entry
                       entry 80))))
               (is (search
                    (cadr-tui:theme-foreground-ansi
                     :tool-diff-removed)
                    rendered))
               (is (search
                    (cadr-tui:theme-foreground-ansi
                     :tool-diff-added)
                    rendered)))
          (cadr-tui:reset-current-theme))))))

(test goal9-compaction-preserves-totals-and-hides-context-until-next-usage
  (let* ((state
           (cadr-cli::make-tui-state
            :model "mock"
            :context-window 100))
         (before
           (cadr-ai:make-assistant-message
            :api :openai-responses
            :provider :openai
            :model "mock"
            :usage
            (cadr-ai:make-usage
             :input 10 :output 5)
            :stop-reason :stop))
         (after
           (cadr-ai:make-assistant-message
            :api :openai-responses
            :provider :openai
            :model "mock"
            :usage
            (cadr-ai:make-usage
             :input 20 :output 5)
            :stop-reason :stop)))
    (cadr-cli::seed-tui-message state before)
    (is (= 15d0
           (cadr-cli::tui-state-context-percent
            state)))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :compaction-end)
     :display-messages nil
     :compaction-summary "summary")
    (is (null
         (cadr-cli::tui-state-context-percent
          state)))
    (is (= 10
           (cadr-cli::tui-state-input-tokens state)))
    (is (= 5
           (cadr-cli::tui-state-output-tokens state)))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :message-start
      :message after))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :message-end
      :message after))
    (is (= 25d0
           (cadr-cli::tui-state-context-percent
            state)))
    (is (= 30
           (cadr-cli::tui-state-input-tokens state)))
    (is (= 10
           (cadr-cli::tui-state-output-tokens state)))))

(test goal9-tui-markdown-transformers-cover-user-text-thinking-streaming-and-cache
  (let ((calls nil))
    (let* ((bundle
             (cadr-agent::make-extension-bundle
              :id "markdown"
              :path "/tmp/markdown.lisp"
              :scope :project))
           (host
             (cadr-agent::make-extension-host
              :cwd #P"/tmp/"))
           (state
             (cadr-cli::make-tui-state
              :model "mock"
              :messages
              (list
               (cadr-ai:make-user-message
                :content "input"))))
           (assistant
             (cadr-ai:make-assistant-message
              :api :openai-responses
              :provider :openai
              :model "mock"
              :content
              (list
               (cadr-ai:make-text-content
                :text "answer")
               (cadr-ai:make-thinking-content
                :thinking "reasoning"))
              :stop-reason :stop))
           (editor
             (cadr-tui:make-multiline-editor)))
      (cadr-agent::call-with-extension-registration
       bundle
       (lambda ()
         (cadr-agent:define-markdown-transformer
          (lambda (markdown context)
            (push
             (list markdown (copy-list context))
             calls)
            (format nil "~(~A~):~A"
                    (getf context :message-type)
                    markdown)))))
      (cadr-agent::replace-extension-bundles
       host (list bundle))
      (cadr-cli::tui-handle-agent-event
       state
       (cadr-agent::make-agent-event
        :type :message-start
        :message assistant))
      (multiple-value-bind (lines row column)
          (cadr-cli::render-tui-state
           state editor 80 20
           :extension-host host)
        (declare (ignore row column))
        (let ((screen
                (format nil "~{~A~^~%~}" lines)))
          (is (search "user:input" screen))
          (is (search "assistant:answer"
                      screen))
          (is (search
               "assistant-thinking:reasoning"
               screen))))
      (let ((count (length calls)))
        (cadr-cli::render-tui-state
         state editor 80 20
         :extension-host host)
        (is (= count (length calls))))
      (is
       (some
        (lambda (call)
          (and
           (eq :assistant
               (getf (second call)
                     :message-type))
           (getf (second call) :streaming-p)
           (= 78
              (getf (second call)
                    :available-width))))
        calls))
      (cadr-cli::tui-handle-agent-event
       state
       (cadr-agent::make-agent-event
        :type :message-end
        :message assistant))
      (cadr-cli::render-tui-state
       state editor 60 20
       :extension-host host)
      (is
       (some
        (lambda (call)
          (and
           (eq :assistant-thinking
               (getf (second call)
                     :message-type))
           (null
            (getf (second call)
                  :streaming-p))
           (= 58
              (getf (second call)
                    :available-width))))
        calls))
      (is
       (some
        (lambda (call)
          (and
           (eq :user
               (getf (second call)
                     :message-type))
           (= 78
              (getf (second call)
                    :available-width))))
        calls)))))

(test markdown-transformer-cache-is-bounded-and-user-output-is-parsed
  (let* ((bundle
           (cadr-agent::make-extension-bundle
            :id "bounded-markdown"
            :path "/tmp/bounded-markdown.lisp"
            :scope :project))
         (host
           (cadr-agent::make-extension-host
            :cwd #P"/tmp/"))
         (state
           (cadr-cli::make-tui-state
            :model "mock"
            :messages
            (list
             (cadr-ai:make-user-message
              :content "input"))))
         (assistant
           (cadr-ai:make-assistant-message
            :api :openai-responses
            :provider :openai
            :model "mock"
            :stop-reason :pending))
         (editor
           (cadr-tui:make-multiline-editor)))
    (cadr-agent::call-with-extension-registration
     bundle
     (lambda ()
       (cadr-agent:define-markdown-transformer
        (lambda (markdown context)
          (if (eq :user
                  (getf context :message-type))
              "**parsed-user**"
              markdown)))))
    (cadr-agent::replace-extension-bundles
     host (list bundle))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :message-start
      :message assistant))
    (let ((entry
            (cadr-cli::tui-state-current-assistant
             state)))
      (loop for index from 1 to 50
            for source =
            (make-string index
                         :initial-element #\x)
            do
            (setf
             (cadr-cli::tui-entry-text entry)
             source
             (cadr-cli::tui-entry-content-blocks
              entry)
             (list (cons :assistant source)))
            (cadr-cli::render-tui-state
             state editor 80 20
             :extension-host host))
      (is (<=
           (length
            (cadr-cli::tui-entry-markdown-cache
             entry))
           1)))
    (multiple-value-bind (lines row column)
        (cadr-cli::render-tui-state
         state editor 80 20
         :extension-host host)
      (declare (ignore row column))
      (let ((screen
              (format nil "~{~A~^~%~}" lines)))
        (is (search "parsed-user" screen))
        (is (null (search "**parsed-user**"
                          screen)))))))

(test assistant-blocks-trim-merge-and-surface-stop-errors
  (let ((message
          (cadr-ai:make-assistant-message
           :api :openai-responses
           :provider :openai
           :model "mock"
           :content
           (list
            (cadr-ai:make-text-content
             :text "  first  ")
            (cadr-ai:make-text-content
             :text "   ")
            (cadr-ai:make-thinking-content
             :thinking "  one ")
            (cadr-ai:make-thinking-content
             :thinking " two  ")
            (cadr-ai:make-text-content
             :text " tail "))
           :stop-reason :length)))
    (is (equal
         (list
          (cons :assistant "first")
          (cons :assistant-thinking
                (format nil "one~%~%two"))
          (cons :assistant "tail"))
         (cadr-cli::assistant-display-blocks
          message)))
    (let* ((state
             (cadr-cli::make-tui-state
              :model "mock"
              :messages (list message)))
           (editor
             (cadr-tui:make-multiline-editor)))
      (multiple-value-bind (lines row column)
          (cadr-cli::render-tui-state
           state editor 100 20)
        (declare (ignore row column))
        (is
         (search
          "maximum output token limit"
          (format nil "~{~A~^~%~}" lines))))))
  (dolist
      (case
       (list
        (list :aborted
              "Request was aborted"
              "Operation aborted")
        (list :aborted
              "provider cancelled"
              "provider cancelled")
        (list :error
              "bad gateway"
              "Error: bad gateway")))
    (destructuring-bind
        (stop-reason error-message expected)
        case
      (let* ((message
               (cadr-ai:make-assistant-message
                :api :openai-responses
                :provider :openai
                :model "mock"
                :stop-reason stop-reason
                :error-message error-message))
             (state
               (cadr-cli::make-tui-state
                :model "mock"
                :messages (list message)))
             (editor
               (cadr-tui:make-multiline-editor)))
        (multiple-value-bind (lines row column)
            (cadr-cli::render-tui-state
             state editor 80 12)
          (declare (ignore row column))
          (is
           (search
            expected
            (format nil "~{~A~^~%~}"
                    lines))))))))

(test tui-compaction-rebuilds-chat-appends-summary-and-keeps-steering-input
  (let* ((old
           (cadr-ai:make-user-message
            :content "old"))
         (answer
           (cadr-ai:make-assistant-message
            :content
            (list
             (cadr-ai:make-text-content
              :text "answer"))
            :api :openai-responses
            :provider :openai
            :model "mock"
            :stop-reason :stop))
         (state
           (cadr-cli::make-tui-state
            :model "mock"
            :messages
            (list
             (cadr-ai:make-user-message
              :content "stale")))))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :compaction-end)
     :display-messages (list old answer)
     :compaction-summary "summary"
     :compaction-tokens-before 123)
    (is (= 3
           (length
            (cadr-cli::tui-state-entries
             state))))
    (is (eq
         :compaction-summary
         (cadr-cli::tui-entry-type
          (car
           (last
            (cadr-cli::tui-state-entries
             state))))))
    (let ((editor
            (cadr-tui:make-multiline-editor)))
      (multiple-value-bind (lines row column)
          (cadr-cli::render-tui-state
           state editor 80 16)
        (declare (ignore row column))
        (let ((screen
                (format nil "~{~A~^~%~}"
                        lines)))
          (is (search "old" screen))
          (is (search "answer" screen))
          (is (search "summary" screen))
          (is (search "123 tokens" screen))))))
  (let ((queued nil)
        (started nil))
    (is (eq
         :queued
         (cadr-cli::route-tui-submission
          "change direction" t
          (lambda (text)
            (push text queued))
          (lambda (text)
            (push text started)))))
    (is (equal '("change direction")
               queued))
    (is (null started))))

(test tui-suspend-restores-on-continue-and-cleans-up-on-failure
  (let ((events nil))
    (is (null
         (cadr-cli::suspend-tui
          :windows
          (lambda () (push :stop events))
          (lambda () (push :start events))
          (lambda () (push :render events))
          (lambda () (push :suspend events))
          (lambda (handler thunk)
            (declare (ignore handler thunk))
            (push :install events))
          :notice-function
          (lambda (text)
            (push text events)))))
    (is (equal
         '("Suspend to background is not supported on Windows")
         events)))
  (let ((events nil)
        (continue-handler nil))
    (is
     (cadr-cli::suspend-tui
      :linux
      (lambda () (push :stop events))
      (lambda () (push :start events))
      (lambda () (push :render events))
      (lambda () (push :suspend events))
      (lambda (handler thunk)
        (setf continue-handler handler)
        (push :install events)
        (unwind-protect
             (funcall thunk)
          (push :cleanup events)))))
    (is (equal
         '(:cleanup :suspend :install :stop)
         events))
    (funcall continue-handler)
    (is (equal
         '(:render :start
           :cleanup :suspend :install :stop)
         events)))
  (let ((events nil))
    (signals error
      (cadr-cli::suspend-tui
       :linux
       (lambda () (push :stop events))
       (lambda () (push :start events))
       (lambda () (push :render events))
       (lambda ()
         (push :suspend events)
         (error "suspend failed"))
       (lambda (handler thunk)
         (declare (ignore handler))
         (unwind-protect
              (funcall thunk)
           (push :cleanup events)))))
    (is (equal
         '(:cleanup :suspend :stop)
         events))))

(test tui-input-sequence-produces-virtual-screen-snapshot
  (let* ((terminal
           (cadr-tui:make-virtual-terminal
            :columns 48 :rows 8))
         (renderer
           (cadr-tui:make-terminal-renderer
            terminal))
         (state
           (cadr-cli::make-tui-state
            :model "gemini-3.6-flash"
            :session "s1"))
         (editor
           (cadr-tui:make-multiline-editor))
         (decoder
           (cadr-tui:make-input-decoder)))
    (dolist
        (event
         (cadr-tui:feed-input
          decoder
          (format nil "中文👩‍💻~C[13;2u下一行"
                  #\Escape)))
      (cadr-tui:editor-handle-event
       editor event))
    (multiple-value-bind (lines row column)
        (cadr-cli::render-tui-state
         state editor 48 8)
      (cadr-tui:render-frame
       renderer lines
       :cursor-row row
       :cursor-column column))
    (let ((snapshot
            (format
             nil "~{~A~%~}"
             (cadr-tui:virtual-terminal-snapshot
              terminal))))
      (is (search "中文👩‍💻" snapshot))
      (is (search "下一行" snapshot))
      (is (search "gemini-3.6-flash" snapshot)))))

(test tui-import-confirmation-defaults-to-an-explicit-yes-choice
  (let* ((state
          (cadr-cli::make-import-confirmation-list
           "/import '/tmp/session.jsonl'"
           "/tmp/session.jsonl"))
         (selector
           (cadr-cli::framed-select-state-select-list
            state)))
    (let ((rendered
            (format
             nil "~{~A~^~%~}"
             (cadr-cli::render-framed-select-state
              state 80))))
      (is (search "Yes" rendered))
      (is (search "No" rendered)))
    (multiple-value-bind (action value)
        (cadr-tui:select-list-handle-event
         selector
         (cadr-tui:make-input-event
          :kind :enter))
      (is (eq :select action))
      (is (eq t (getf value :confirmed-p)))
      (is (string=
           "/import '/tmp/session.jsonl'"
           (getf value :line))))))

(test tui-session-selector-stays-in-cli-glue-and-honors-configurable-bindings
  (let* ((selector
           (cadr-cli::make-session-selector-state
            :current-sessions
            (list
             (cadr-cli:make-session-search-record
              :id "one"
              :path "/tmp/one.jsonl"
              :name "One"
              :modified 1
              :all-messages-text "hello"))
            :show-rename-hint-p t
            :rename-function
            (lambda (path name)
              (declare (ignore path))
              name)
            :keybindings
            (cadr-cli::make-session-selector-keybindings
             '(("app.session.rename"
                . ("ctrl+x"))))))
         (state
           (cadr-cli::make-tui-state
            :model "mock"))
         (editor
           (cadr-tui:make-multiline-editor)))
    (multiple-value-bind (lines row column)
        (cadr-cli::render-tui-state
         state editor 140 18
         :overlay selector)
      (declare (ignore row column))
      (let ((screen
              (format nil "~{~A~^~%~}" lines)))
        (is (search "Resume Session" screen))
        (is (search "ctrl+x rename" screen))
        (is (not (search "ctrl+r rename" screen)))))
    (multiple-value-bind (action value handled-p)
        (cadr-cli::session-selector-handle-raw-input
         selector
         (format nil "~C[114;5u" #\Escape))
      (declare (ignore action value))
      (is (null handled-p)))
    (multiple-value-bind (action value handled-p)
        (cadr-cli::session-selector-handle-raw-input
         selector
         (format nil "~C[120;5u" #\Escape))
      (declare (ignore value))
      (is (eq :changed action))
      (is (eq t handled-p))
      (is (eq :rename
              (cadr-cli::session-selector-state-mode
               selector))))))

(test tui-tree-selector-stays-in-cli-glue-and-honors-configurable-bindings
  (let* ((copied nil)
         (selector
           (cadr-cli::make-tree-selector-state
            :entries
            '((:id "user" :parent-id nil
               :type :message :role :user
               :text "hello")
              (:id "assistant" :parent-id "user"
               :type :message :role :assistant
               :text "full response"))
            :current-leaf-id "assistant"
            :copy-callback
            (lambda (text)
              (setf copied text))
            :keybindings
            (cadr-cli::make-tree-selector-keybindings
             '(("app.message.copy"
                . ("ctrl+y"))))))
         (state
           (cadr-cli::make-tui-state
            :model "mock"))
         (editor
           (cadr-tui:make-multiline-editor)))
    (multiple-value-bind (lines row column)
        (cadr-cli::render-tui-state
         state editor 40 28
         :overlay selector)
      (declare (ignore row column))
      (let ((screen
              (format nil "~{~A~^~%~}" lines)))
        (is (search "Session Tree" screen))
        (is (search "full response" screen))
        (is (search "branch" screen))
        (is (search "copy" screen))))
    (multiple-value-bind (action value handled-p)
        (cadr-cli::tree-selector-handle-raw-input
         selector
         (string (code-char 24)))
      (declare (ignore action value))
      (is (null handled-p))
      (is (null copied)))
    (multiple-value-bind (action value handled-p)
        (cadr-cli::tree-selector-handle-raw-input
         selector
         (string (code-char 25)))
      (declare (ignore value))
      (is (eq :changed action))
      (is (eq t handled-p))
      (is (string= "full response" copied)))
    (multiple-value-bind (action value)
        (cadr-cli::tree-selector-handle-event
         selector
         (cadr-tui:make-input-event
          :kind :enter))
      (is (eq :select action))
      (is (string= "assistant" value)))))

(test tui-model-selectors-stay-in-cli-glue
  (let* ((one
           (cadr-cli/tests::selector-test-model
            :faux "one" "One"))
         (two
           (cadr-cli/tests::selector-test-model
            :faux "two" "Two"))
         (model-selector
           (cadr-cli::make-model-selector-state
            :all-models (list one two)
            :scoped-models (list two one)
            :current-model one))
         (scoped-selector
           (cadr-cli::make-scoped-models-selector-state
            :all-models (list one two)
            :enabled-ids
            '("faux/unavailable" "faux/two")))
         (state
           (cadr-cli::make-tui-state
            :model "one"))
         (editor
           (cadr-tui:make-multiline-editor)))
    (dolist
        (case
         `((,model-selector
            "Scope: all | scoped" "two")
           (,scoped-selector
            "Model Configuration"
            "faux/unavailable"
            "unavailable")))
      (destructuring-bind
            (overlay &rest expected)
          case
        (multiple-value-bind (lines row column)
            (cadr-cli::render-tui-state
             state editor 100 18
             :overlay overlay)
          (declare (ignore row column))
          (let ((screen
                  (cadr-tui:strip-terminal-sequences
                   (format nil "~{~A~^~%~}"
                           lines))))
            (dolist (text expected)
              (is (search text screen)))))))))

(test tui-settings-selector-stays-in-cli-glue
  (let* ((selector
           (cadr-cli::make-settings-selector-state
            :options
            (list
             (cadr-cli::make-settings-option
              :id "autocompact"
              :label "Auto-compact"
              :description
              "Automatically compact context"
              :value t
              :values (list t nil)))))
         (state
           (cadr-cli::make-tui-state
            :model "mock"))
         (editor
           (cadr-tui:make-multiline-editor)))
    (multiple-value-bind (lines row column)
        (cadr-cli::render-tui-state
         state editor 80 12
         :overlay selector)
      (declare (ignore row column))
      (let ((screen
              (cadr-tui:strip-terminal-sequences
               (format nil "~{~A~^~%~}" lines))))
        (is (null (search "Settings" screen)))
        (is (search "Auto-compact  true" screen))))))

(test goal9-user-and-assistant-message-shells-match-baseline
  (let ((caps
          (cadr-tui:make-terminal-capabilities
           :images nil :true-color-p t
           :hyperlinks-p nil)))
    (cadr-tui:set-current-theme
     :dark :capabilities caps)
    (unwind-protect
         (let* ((user
                  (cadr-cli::make-tui-entry
                   :type :user :text "hello"))
                (assistant
                  (cadr-cli::make-tui-entry
                   :type :assistant
                   :content-blocks
                   (list
                    (cons :assistant-thinking
                          "reasoning")
                    (cons :assistant
                          "answer"))))
                (user-lines
                  (cadr-cli::render-tui-entry
                   user 24))
                (assistant-lines
                  (cadr-cli::render-tui-entry
                   assistant 24))
                (user-ansi
                  (format nil "~{~A~^~%~}"
                          user-lines))
                (assistant-ansi
                  (format nil "~{~A~^~%~}"
                          assistant-lines)))
           (is (= 3 (length user-lines)))
           (is (= 0
                  (search
                   cadr-cli::+osc-133-start+
                   (first user-lines))))
           (is (= 0
                  (search
                   (concatenate
                    'string
                    cadr-cli::+osc-133-end+
                    cadr-cli::+osc-133-final+)
                   (car (last user-lines)))))
           (is (every
                (lambda (line)
                  (= 24
                     (cadr-tui:visible-width line)))
                user-lines))
           (is (search
                (format nil "~C[48;2;52;53;65m"
                        #\Escape)
                user-ansi))
           (is (string=
                cadr-cli::+osc-133-start+
                (first assistant-lines)))
           (is (= 0
                  (search
                   cadr-cli::+osc-133-start+
                   (first assistant-lines))))
           (is (= 0
                  (search
                   (concatenate
                    'string
                    cadr-cli::+osc-133-end+
                    cadr-cli::+osc-133-final+)
                   (car (last assistant-lines)))))
           (is (search
                (format nil "~C[3m"
                        #\Escape)
                assistant-ansi))
           (is (search
                (format nil "~C[38;2;128;128;128m"
                        #\Escape)
                assistant-ansi)))
      (cadr-tui:reset-current-theme))))

(test goal9-assistant-tool-call-messages-do-not-open-osc133-zones
  (let* ((entry
           (cadr-cli::make-tui-entry
            :type :assistant
            :content-blocks
            (list (cons :assistant "calling tool"))
            :has-tool-calls-p t))
         (rendered
           (format
            nil "~{~A~^~%~}"
            (cadr-cli::render-tui-entry
             entry 60))))
    (is (null
         (search cadr-cli::+osc-133-start+
                 rendered)))
    (is (null
         (search cadr-cli::+osc-133-end+
                 rendered)))
    (is (null
         (search cadr-cli::+osc-133-final+
                 rendered)))))

(test goal9-root-layout-puts-editor-before-two-line-footer
  (let* ((state
           (cadr-cli::make-tui-state
            :model "gpt-5.6-luna"
            :provider "openai-codex"
            :thinking :high
            :cwd "~/work"
            :branch "main"
            :session-name "visual"))
         (editor
           (cadr-tui:make-multiline-editor
            :text "prompt")))
    (multiple-value-bind (lines row column)
        (cadr-cli::render-tui-state
         state editor 60 14
         :full-document-p t)
      (declare (ignore row column))
      (let* ((plain
               (mapcar
                #'cadr-tui:strip-terminal-sequences
                lines))
             (top-border
               (position-if
                (lambda (line)
                  (and
                   (plusp (length line))
                   (every
                    (lambda (character)
                      (char= character #\─))
                    line)))
                plain))
             (cwd-line
               (position-if
                (lambda (line)
                  (search "~/work (main) • visual"
                          line))
                plain))
             (model-line
               (position-if
                (lambda (line)
                  (search "gpt-5.6-luna • high"
                          line))
                plain)))
        (is (integerp top-border))
        (is (integerp cwd-line))
        (is (integerp model-line))
        (is (< top-border cwd-line))
        (is (= (1+ cwd-line)
               model-line))))))

(test goal9-custom-theme-summary-is-applied-to-live-rendering
  (let ((object
          (goal9-complete-theme-object
           :accent "#010203")))
    (cadr-cli::apply-tui-theme-summary
     (list :name "custom"
           :object object)
     :background :dark
     :capabilities
     (cadr-tui:make-terminal-capabilities
      :true-color-p t))
    (unwind-protect
         (is (string=
              "#010203"
              (cadr-tui:theme-color-value
               :accent)))
      (cadr-tui:reset-current-theme))))

(test goal9-status-indicator-uses-baseline-spinner-colors-and-spacing
  (is (equal
       '("⠋" "⠙" "⠹" "⠸" "⠼"
         "⠴" "⠦" "⠧" "⠇" "⠏")
       (coerce cadr-cli::+tui-spinner-frames+
               'list)))
  (is (= 0.08d0
         cadr-cli::+tui-spinner-interval-seconds+))
  (let ((caps
          (cadr-tui:make-terminal-capabilities
           :true-color-p t)))
    (cadr-tui:set-current-theme
     :dark :capabilities caps)
    (unwind-protect
         (let* ((working
                  (cadr-cli::render-tui-status-indicator
                   "Working..." 40 :spinner-frame "⠋"))
                (retry
                  (cadr-cli::render-tui-status-indicator
                   "Retrying (1/3) in 2s..." 40
                   :spinner-frame "⠙"))
                (working-ansi (second working))
                (retry-ansi (second retry)))
           (is (string= "" (first working)))
           (is (string=
                "⠋ Working..."
                (cadr-tui:strip-terminal-sequences
                 working-ansi)))
           (is (search
                (format nil "~C[38;2;138;190;183m"
                        #\Escape)
                working-ansi))
           (is (search
                (format nil "~C[38;2;128;128;128m"
                        #\Escape)
                working-ansi))
           (is (search
                (format nil "~C[38;2;255;255;0m"
                        #\Escape)
                retry-ansi))
           (dolist (message
                    '("Compacting context..."
                      "Summarizing branch..."))
             (is (search
                  (format nil "~C[38;2;138;190;183m"
                          #\Escape)
                  (second
                   (cadr-cli::render-tui-status-indicator
                    message 40 :spinner-frame "⠹")))))
           (is (equal
                (list
                 (make-string 40
                              :initial-element #\Space)
                 (make-string 40
                              :initial-element #\Space))
                (cadr-cli::render-tui-status-indicator
                 nil 40 :reserve-idle-p t))))
      (cadr-tui:reset-current-theme))))

(test goal9-overlay-clipping-keeps-the-selected-row-visible
  (let ((caps
          (cadr-tui:make-terminal-capabilities
           :true-color-p t)))
    (cadr-tui:set-current-theme
     :dark :capabilities caps)
    (unwind-protect
         (let* ((selected
                  (cadr-tui:theme-background
                   :selected-bg
                   "→ selected item"
                   :enabled-p t))
                (lines
                  (append
                   '("top border" "title" "search")
                   (loop for index below 20
                         collect
                         (if (= index 16)
                             selected
                             (format nil
                                     "  item ~D"
                                     index)))
                   '("bottom border")))
                (fitted
                  (cadr-cli::fit-overlay-lines
                   lines 8))
                (plain
                  (mapcar
                   #'cadr-tui:strip-terminal-sequences
                   fitted)))
           (is (= 8 (length fitted)))
           (is (find "→ selected item"
                     plain :test #'string=))
           (is (find "top border"
                     plain :test #'string=))
           (is (find "bottom border"
                     plain :test #'string=)))
      (cadr-tui:reset-current-theme))))

(test goal9-render-coordinator-coalesces-and-keeps-final-request
  (let* ((now 0d0)
         (renders 0)
         (coordinator
           (cadr-cli::make-tui-render-coordinator
            :clock-function (lambda () now))))
    (cadr-cli::request-tui-render coordinator)
    (cadr-cli::request-tui-render coordinator)
    (cadr-cli::request-tui-render coordinator)
    (is
     (cadr-cli::flush-tui-render
      coordinator
      (lambda ()
        (incf renders)
        (cadr-cli::request-tui-render
         coordinator))))
    (is (= 1 renders))
    (is (not
         (cadr-cli::flush-tui-render
          coordinator (lambda () (incf renders)))))
    (setf now 0.015d0)
    (is (not
         (cadr-cli::flush-tui-render
          coordinator (lambda () (incf renders)))))
    (setf now 0.016d0)
    (is
     (cadr-cli::flush-tui-render
      coordinator (lambda () (incf renders))))
    (is (= 2 renders))
    (cadr-cli::stop-tui-render-coordinator coordinator)
    (cadr-cli::request-tui-render coordinator)
    (setf now 1d0)
    (is (not
         (cadr-cli::flush-tui-render
          coordinator (lambda () (incf renders)))))
    (is (= 2 renders))))

(test goal9-render-coordinator-accepts-concurrent-requests
  (let* ((now 0d0)
         (renders 0)
         (coordinator
           (cadr-cli::make-tui-render-coordinator
            :clock-function (lambda () now)))
         (workers
           (loop repeat 8
                 collect
                 (sb-thread:make-thread
                  (lambda ()
                    (loop repeat 100
                          do
                          (cadr-cli::request-tui-render
                           coordinator)))))))
    (dolist (worker workers)
      (sb-thread:join-thread worker))
    (is
     (cadr-cli::flush-tui-render
      coordinator (lambda () (incf renders))))
    (is (= 1 renders))
    (is (not
         (cadr-cli::flush-tui-render
          coordinator (lambda () (incf renders)))))
    (is (= 1 renders))))

(test goal9-spinner-and-retry-countdown-use-injected-time
  (let* ((state
           (cadr-cli::make-tui-state :model "mock"))
         (animation
           (cadr-cli::make-tui-status-animation)))
    (setf
     (cadr-cli::tui-state-status-message state)
     "Retrying (2/4) in 2s...")
    (is
     (cadr-cli::advance-tui-status-animation
      animation state t 0d0))
    (is (string=
         "⠋"
         (cadr-cli::tui-status-animation-frame
          animation)))
    (is
     (cadr-cli::advance-tui-status-animation
      animation state t 0.08d0))
    (is (string=
         "⠙"
         (cadr-cli::tui-status-animation-frame
          animation)))
    (is
     (cadr-cli::advance-tui-status-animation
      animation state t 1d0))
    (is (string=
         "Retrying (2/4) in 1s..."
         (cadr-cli::tui-state-status-message state)))
    (is
     (cadr-cli::advance-tui-status-animation
      animation state t 2d0))
    (is (string=
         "Retrying (2/4) in 0s..."
         (cadr-cli::tui-state-status-message state)))
    (setf
     (cadr-cli::tui-state-status-message state) nil)
    (is
     (cadr-cli::advance-tui-status-animation
      animation state nil 2.01d0))
    (is (null
         (cadr-cli::tui-status-animation-active-p
          animation)))))

(test goal9-animated-status-renders-on-virtual-terminal-without-sleep
  (let* ((terminal
           (cadr-tui:make-virtual-terminal
            :columns 40 :rows 8))
         (renderer
           (cadr-tui:make-terminal-renderer terminal))
         (state
           (cadr-cli::make-tui-state :model "mock"))
         (editor
           (cadr-tui:make-multiline-editor)))
    (setf
     (cadr-cli::tui-state-status-message state)
     "Compacting context...")
    (multiple-value-bind (lines row column)
        (cadr-cli::render-tui-state
         state editor 40 8 :spinner-frame "⠹")
      (cadr-tui:render-frame
       renderer lines
       :cursor-row row
       :cursor-column column))
    (let ((screen
            (format
             nil "~{~A~^~%~}"
             (cadr-tui:virtual-terminal-snapshot
              terminal))))
      (is (search "⠹ Compacting context..."
                  screen)))))

(test goal9-startup-header-precedes-chat-and-expands-with-tools
  (let* ((state
           (cadr-cli::make-tui-state
            :model "mock"
            :startup-compact-lines
            '("cadr v0.1.0"
              "escape interrupt · ctrl+c/ctrl+d clear/exit · / commands · ! bash"
              "Press ctrl+o to show full startup help and loaded resources.")
            :startup-expanded-lines
            '("cadr v0.1.0"
              "escape to interrupt"
              "ctrl+c twice to exit"
              "/ for commands"
              "! to run bash")))
         (editor
           (cadr-tui:make-multiline-editor)))
    (cadr-cli::add-tui-notice state "restored chat")
    (flet ((plain-render ()
             (multiple-value-bind
                   (lines row column)
                 (cadr-cli::render-tui-state
                  state editor 80 20
                  :full-document-p t)
               (declare (ignore row column))
               (mapcar
                #'cadr-tui:strip-terminal-sequences
                lines))))
      (let* ((compact (plain-render))
             (logo (position "cadr v0.1.0"
                             compact :test #'string=))
             (chat
               (position-if
                (lambda (line)
                  (search "restored chat" line))
                compact)))
        (is (integerp logo))
        (is (integerp chat))
        (is (< logo chat))
        (is (find-if
             (lambda (line)
               (search "show full startup help" line))
             compact)))
      (cadr-cli::set-tui-tools-expanded state t)
      (let ((expanded (plain-render)))
        (is (find "ctrl+c twice to exit"
                  expanded :test #'string=))
        (is (null
             (find-if
              (lambda (line)
                (search "show full startup help" line))
              expanded)))))))

(defclass background-query-test-terminal
    (cadr-tui::virtual-terminal)
  ((inputs
    :initarg :inputs
    :accessor background-query-test-inputs)
   (query-count
    :initform 0
    :accessor background-query-test-query-count)))

(defmethod cadr-tui:terminal-read-input
    ((terminal background-query-test-terminal))
  (or (pop (background-query-test-inputs terminal))
      ""))

(defmethod cadr-tui:terminal-query-background-color
    ((terminal background-query-test-terminal)
     &key timeout-seconds)
  (is (= 0.1d0 timeout-seconds))
  (incf
   (background-query-test-query-count terminal))
  (cadr-tui::make-rgb-color
   :red 250 :green 250 :blue 250))

(test goal9-auto-theme-falls-back-to-osc11-after-dsr-timeout
  (let ((detected nil)
        (terminal
          (make-instance
           'background-query-test-terminal
           :columns 80 :rows 12
           :inputs
           (list
            (footer-sync-submit-input "/quit")))))
    (unwind-protect
         (progn
           (cadr-cli::run-tui
            (constantly nil)
            :model "mock"
            :terminal terminal
            :theme-mode-function
            (constantly :auto)
            :detected-theme-function
            (lambda (background)
              (setf detected background)
              (list :name
                    (string-downcase
                     (symbol-name background))
                    :path nil)))
           (is (= 1
                  (background-query-test-query-count
                   terminal)))
           (is (eq :light detected))
           (is (eq :light
                   (cadr-tui:terminal-theme-name
                    (cadr-tui:current-theme)))))
      (cadr-tui:reset-current-theme))))

(defclass color-scheme-test-terminal
    (background-query-test-terminal)
  ((scheme-query-count
    :initform 0
    :accessor color-scheme-test-query-count)
   (scheme-changes
    :initarg :scheme-changes
    :initform nil
    :accessor color-scheme-test-changes)
   (notification-values
    :initform nil
    :accessor color-scheme-test-notification-values)))

(defmethod cadr-tui:terminal-query-color-scheme
    ((terminal color-scheme-test-terminal)
     &key timeout-seconds)
  (is (= 0.1d0 timeout-seconds))
  (incf (color-scheme-test-query-count terminal))
  :dark)

(defmethod cadr-tui:terminal-color-scheme-change
    ((terminal color-scheme-test-terminal))
  (pop (color-scheme-test-changes terminal)))

(defmethod cadr-tui:terminal-set-color-scheme-notifications
    ((terminal color-scheme-test-terminal) enabled)
  (push
   (not (null enabled))
   (color-scheme-test-notification-values terminal))
  (not (null enabled)))

(defclass dynamic-theme-test-terminal
    (color-scheme-test-terminal)
  ((reads
    :initform 0
    :accessor dynamic-theme-test-terminal-reads)
   (before-second-read
    :initarg :before-second-read
    :initform (constantly nil)
    :reader dynamic-theme-test-terminal-before-second-read)))

(defmethod cadr-tui:terminal-read-input
    ((terminal dynamic-theme-test-terminal))
  (when
      (= 2
         (incf
          (dynamic-theme-test-terminal-reads terminal)))
    (funcall
     (dynamic-theme-test-terminal-before-second-read
      terminal)))
  (or (pop (background-query-test-inputs terminal))
      ""))

(test goal9-auto-theme-prefers-dsr-and-applies-live-notifications
  (let ((detected nil)
        (terminal
          (make-instance
           'color-scheme-test-terminal
           :columns 80 :rows 12
           :scheme-changes (list :light)
           :inputs
           (list
            (footer-sync-submit-input "/quit")))))
    (unwind-protect
         (progn
           (cadr-cli::run-tui
            (constantly nil)
            :model "mock"
            :terminal terminal
            :theme-mode-function
            (constantly :auto)
            :detected-theme-function
            (lambda (background)
              (push background detected)
              (list
               :name
               (string-downcase
                (symbol-name background))
               :path nil)))
           (is (= 1
                  (color-scheme-test-query-count
                   terminal)))
           (is (zerop
                (background-query-test-query-count
                 terminal)))
           (is (equal
                '(:light :dark)
                detected))
           (is (equal
                '(t)
                (color-scheme-test-notification-values
                 terminal)))
           (is (eq :light
                   (cadr-tui:terminal-theme-name
                    (cadr-tui:current-theme)))))
      (cadr-tui:reset-current-theme))))

(test goal9-unconfigured-theme-detects-osc11-once-without-live-sync
  (let ((detected nil)
        (terminal
          (make-instance
           'color-scheme-test-terminal
           :columns 80 :rows 12
           :scheme-changes (list :dark)
           :inputs
           (list
            (footer-sync-submit-input "/quit")))))
    (unwind-protect
         (progn
           (cadr-cli::run-tui
            (constantly nil)
            :model "mock"
            :terminal terminal
            :theme-mode-function
            (constantly :detect-once)
            :detected-theme-function
            (lambda (background)
              (push background detected)
              (list
               :name
               (string-downcase
                (symbol-name background))
               :path nil)))
           (is (zerop
                (color-scheme-test-query-count
                 terminal)))
           (is (= 1
                  (background-query-test-query-count
                   terminal)))
           (is (equal '(:light) detected))
           (is (equal
                '(nil)
                (color-scheme-test-notification-values
                 terminal))))
      (cadr-tui:reset-current-theme))))

(test goal9-fixed-theme-skips-terminal-detection
  (let ((terminal
          (make-instance
           'color-scheme-test-terminal
           :columns 80 :rows 12
           :inputs
           (list
            (footer-sync-submit-input "/quit")))))
    (cadr-cli::run-tui
     (constantly nil)
     :model "mock"
     :terminal terminal
     :theme-mode-function
     (constantly :fixed)
     :detected-theme-function
     (lambda (background)
       (declare (ignore background))
       (error "fixed themes must not detect terminal colors")))
    (is (zerop
         (color-scheme-test-query-count terminal)))
    (is (zerop
         (background-query-test-query-count terminal)))
    (is (equal
         '(nil)
         (color-scheme-test-notification-values
          terminal)))))

(test goal9-theme-mode-dynamically-disables-live-notifications
  (let ((extension-ui nil)
        (mode :auto)
        (updated-p nil))
    (let* ((terminal
             (make-instance
              'dynamic-theme-test-terminal
              :columns 80 :rows 12
              :inputs
              (list
               (footer-sync-submit-input "/theme")
               (footer-sync-submit-input "/quit"))))
           (state
             (cadr-cli::run-tui
              (constantly nil)
              :model "mock"
              :terminal terminal
              :theme-mode-function
              (lambda () mode)
              :detected-theme-function
              (lambda (background)
                (list
                 :name
                 (string-downcase
                  (symbol-name background))
                 :path nil))
              :theme-function
              (lambda () (list :name "dark"))
              :set-extension-ui-function
              (lambda (function)
                (setf extension-ui function))
              :set-theme-function
              (lambda (theme)
                (declare (ignore theme))
                (setf mode :fixed)
                (list :success t))
              :command-function
              (lambda (line)
                (when (string= line "/theme")
                  (funcall
                   extension-ui
                   :set-theme
                   (list :theme "dark"))
                  (setf updated-p t))
                t))))
      (declare (ignore state))
      (is (eq t updated-p))
      (is (equal
           '(nil t)
           (color-scheme-test-notification-values
            terminal)))
      (is (= 1
             (color-scheme-test-query-count
              terminal)))
      (is (zerop
           (background-query-test-query-count
            terminal))))))

(test goal9-custom-theme-watcher-reloads-valid-writes-and-keeps-last-valid
  (with-test-directory (directory)
    (let* ((path
             (merge-pathnames "watch.json" directory))
           (initial-object
             (goal9-complete-theme-object
              :name "watch"
              :accent "#010203"))
           (summary
             (list :name "watch"
                   :path path
                   :object initial-object))
           (watcher nil)
           (now 0d0)
           (caps
             (cadr-tui:make-terminal-capabilities
              :true-color-p t)))
      (labels
          ((write-theme (text)
             (with-open-file
                 (stream path
                         :direction :output
                         :if-exists :supersede
                         :if-does-not-exist :create)
               (write-string text stream)))
           (poll ()
             (cadr-cli::poll-tui-theme-watcher
              watcher
              :clock-function (lambda () now)
              :capabilities caps))
           (settle ()
             (is (not (poll)))
             (incf now 0.101d0)
             (poll)))
        (write-theme
         (cadr-ai::stringify-json
          initial-object))
        (setf watcher
              (cadr-cli::make-tui-theme-watcher
               summary))
        (cadr-cli::apply-tui-theme-summary
         summary :capabilities caps)
        (unwind-protect
             (progn
               (write-theme
                (goal9-complete-theme-json
                 :name "watch"
                 :accent "#aabbcc"))
               (is (settle))
               (is (string=
                    "#aabbcc"
                    (cadr-tui:theme-color-value
                     :accent)))
               (write-theme "{not-json")
               (is (not (settle)))
               (is (string=
                    "#aabbcc"
                    (cadr-tui:theme-color-value
                     :accent)))
               (write-theme
                (goal9-complete-theme-json
                 :name "watch"
                 :accent "not-a-color"))
               (is (not (settle)))
               (is (string=
                    "#aabbcc"
                    (cadr-tui:theme-color-value
                     :accent)))
               (write-theme
                "{\"name\":\"watch\",\"colors\":{\"accent\":\"missing\"},\"vars\":{}}")
               (is (not (settle)))
               (is (string=
                    "#aabbcc"
                    (cadr-tui:theme-color-value
                     :accent)))
               (let ((variables
                       (make-hash-table
                        :test #'equal)))
                 (setf
                  (gethash "first" variables)
                  "second"
                  (gethash "second" variables)
                  "first")
                 (write-theme
                  (goal9-complete-theme-json
                   :name "watch"
                   :accent "first"
                   :vars variables)))
               (is (not (settle)))
               (is (string=
                    "#aabbcc"
                    (cadr-tui:theme-color-value
                     :accent)))
               (write-theme
                (goal9-complete-theme-json
                 :name "watch"
                 :accent 42))
               (is (settle))
               (is (= 42
                      (cadr-tui:theme-color-value
                       :accent)))
               (is (string=
                    (format nil "~C[38;5;42m"
                            #\Escape)
                    (cadr-tui:theme-foreground-ansi
                     :accent)))
               (write-theme
                (goal9-complete-theme-json
                 :name "watch"
                 :accent ""))
               (is (settle))
               (is (string=
                    ""
                    (cadr-tui:theme-color-value
                     :accent)))
               (is (string=
                    (format nil "~C[39m"
                            #\Escape)
                    (cadr-tui:theme-foreground-ansi
                     :accent))))
          (cadr-tui:reset-current-theme))))))

(test goal9-custom-theme-requires-complete-schema-and-falls-back-thinking-max
  (let* ((caps
           (cadr-tui:make-terminal-capabilities
            :true-color-p t))
         (partial
           (cadr-ai::parse-json
            "{\"name\":\"partial\",\"colors\":{\"accent\":\"#010203\"}}"))
         (complete
           (goal9-complete-theme-object
            :name "complete"
            :omit-thinking-max-p t)))
    (cadr-tui:set-current-theme
     :dark :capabilities caps)
    (unwind-protect
         (progn
           (is (not
                (cadr-cli::apply-tui-theme-summary
                 (list
                  :name "partial"
                  :object partial)
                 :keep-current-on-error-p t
                 :capabilities caps)))
           (is (string=
                "#8abeb7"
                (cadr-tui:theme-color-value
                 :accent)))
           (is
            (cadr-cli::apply-tui-theme-summary
             (list
              :name "complete"
              :object complete)
             :keep-current-on-error-p t
             :capabilities caps))
           (is (equal
                (cadr-tui:theme-color-value
                 :thinking-xhigh)
                (cadr-tui:theme-color-value
                 :thinking-max))))
      (cadr-tui:reset-current-theme))))

(test goal9-custom-theme-rejects-invalid-optional-schema-values
  (let ((caps
          (cadr-tui:make-terminal-capabilities
           :true-color-p t)))
    (cadr-tui:set-current-theme
     :dark :capabilities caps)
    (unwind-protect
         (dolist
             (mutate
              (list
               (lambda (object)
                 (setf (gethash "name" object) ""))
               (lambda (object)
                 (setf (gethash "$schema" object) 42))
               (lambda (object)
                 (setf (gethash "vars" object) nil))
               (lambda (object)
                 (setf (gethash "export" object) nil))))
           (let ((object
                   (goal9-complete-theme-object
                    :name "invalid")))
             (funcall mutate object)
             (is (not
                  (cadr-cli::apply-tui-theme-summary
                   (list
                    :name "invalid"
                    :object object)
                   :keep-current-on-error-p t
                   :capabilities caps)))
             (is (string=
                  "#8abeb7"
                  (cadr-tui:theme-color-value
                   :accent)))))
      (cadr-tui:reset-current-theme))))

(test goal9-assistant-fenced-code-uses-semantic-syntax-colors
  (let ((caps
          (cadr-tui:make-terminal-capabilities
           :true-color-p t)))
    (cadr-tui:set-current-theme
     :dark :capabilities caps)
    (unwind-protect
         (let* ((entry
                  (cadr-cli::make-tui-entry
                   :type :assistant
                   :content-blocks
                   (list
                    (cons
                     :assistant
                     (format nil
                             "```javascript~%const answer = 42;~%```")))))
                (rendered
                  (format
                   nil "~{~A~^~%~}"
                   (cadr-cli::render-tui-entry
                    entry 60))))
           (is (search
                (cadr-tui:theme-foreground-ansi
                 :syntax-keyword)
                rendered))
           (is (search
                (cadr-tui:theme-foreground-ansi
                 :syntax-number)
                rendered)))
      (cadr-tui:reset-current-theme))))

(test goal11-stable-entry-render-cache-matches-baseline-invalidation
  (let ((caps
          (cadr-tui:make-terminal-capabilities
           :true-color-p t)))
    (cadr-tui:set-current-theme
     :dark :capabilities caps)
    (unwind-protect
         (let* ((entry
                  (cadr-cli::make-tui-entry
                   :type :user
                   :text
                   "Cache **this** 中文 and emoji 🚀 exactly."))
                (first
                  (cadr-cli::render-tui-entry entry 48))
                (second
                  (cadr-cli::render-tui-entry entry 48))
                (narrow
                  (cadr-cli::render-tui-entry entry 24)))
           (is (eq first second))
           (is (not (eq second narrow)))
           (is (equal
                narrow
                (cadr-cli::render-tui-entry entry 24)))
           (cadr-tui:set-current-theme
            :light :capabilities caps)
           (let ((light
                   (cadr-cli::render-tui-entry
                    entry 24)))
             (is (not (eq narrow light)))
             (is (not (equal narrow light)))))
      (cadr-tui:reset-current-theme))))

(test goal11-streaming-and-tool-mutations-invalidate-entry-render-cache
  (let* ((streaming
           (cadr-cli::make-tui-entry
            :type :assistant
            :streaming-p t
            :content-blocks
            (list (cons :assistant "partial"))))
         (stream-first
           (cadr-cli::render-tui-entry streaming 48))
         (stream-second
           (cadr-cli::render-tui-entry streaming 48))
         (state (cadr-cli::make-tui-state))
         (tool
           (cadr-cli::make-tui-entry
            :type :tool
            :tool-block
            (cadr-tui:make-tool-block
             :name "bash"
             :summary "printf ok"
             :output "ok"
             :status :complete
             :started-at 1d0
             :ended-at 1.01d0
             :collapsed-p t))))
    (is (not (eq stream-first stream-second)))
    (setf (cadr-cli::tui-entry-streaming-p streaming)
          nil)
    (let ((finished
            (cadr-cli::render-tui-entry
             streaming 48)))
      (is (eq
           finished
           (cadr-cli::render-tui-entry
            streaming 48))))
    (cadr-cli::replace-tui-entries state (list tool))
    (let ((collapsed
            (cadr-cli::render-tui-entry tool 48)))
      (is (eq
           collapsed
           (cadr-cli::render-tui-entry tool 48)))
      (cadr-cli::set-tui-tools-expanded state t)
      (let ((expanded
              (cadr-cli::render-tui-entry tool 48)))
        (is (not (eq collapsed expanded)))
        (is (search "ok"
                    (format nil "~{~A~^~%~}"
                            expanded)))
        (is (eq
             expanded
             (cadr-cli::render-tui-entry
              tool 48)))))))

(test goal11-tui-entry-append-maintains-o1-tail-invariant
  (let* ((state (cadr-cli::make-tui-state))
         (entries
           (loop for index below 5000
                 collect
                 (cadr-cli::make-tui-entry
                  :type :notice
                  :text (write-to-string index))))
         (head entries)
         (old-tail (last entries))
         (appended
           (cadr-cli::make-tui-entry
            :type :notice :text "appended")))
    (cadr-cli::replace-tui-entries state entries)
    (is (eq old-tail
            (cadr-cli::tui-state-entries-tail state)))
    (cadr-cli::append-tui-entry state appended)
    (is (eq head (cadr-cli::tui-state-entries state)))
    (is (eq appended (cadr old-tail)))
    (is (eq (cdr old-tail)
            (cadr-cli::tui-state-entries-tail state)))
    (is (eq head
            (cadr-cli::tui-state-entries-tail-head state)))
    ;; Direct SETF is tolerated for internal fixtures: the next append repairs
    ;; the tail without corrupting the previously owned list.
    (let* ((replacement
             (cadr-cli::make-tui-entry
              :type :notice :text "replacement"))
           (next
             (cadr-cli::make-tui-entry
              :type :notice :text "next")))
      (setf (cadr-cli::tui-state-entries state)
            (list replacement))
      (cadr-cli::append-tui-entry state next)
      (is (equal (list replacement next)
                 (cadr-cli::tui-state-entries state)))
      (is (= 5001 (length head))))))

(test goal11-cached-mixed-transcript-is-byte-identical
  (let* ((tool
           (cadr-tui:make-tool-block
            :name "read"
            :summary "docs/example.md:1-4"
            :output (format nil "alpha~%beta~%gamma~%delta")
            :status :complete
            :started-at 1d0
            :ended-at 1.02d0
            :collapsed-p t))
         (entries
           (list
            (cadr-cli::make-tui-entry
             :type :user
             :text "Explain **cache behavior** 中文 🚀.")
            (cadr-cli::make-tui-entry
             :type :assistant
             :content-blocks
             (list
              (cons :assistant-thinking "checking")
              (cons :assistant "Stable `answer`.")))
            (cadr-cli::make-tui-entry
             :type :tool :tool-block tool)
            (cadr-cli::make-tui-entry
             :type :notice :text "done")))
         (first
           (cadr-cli::render-tui-entries
            entries 52 :now 2d0))
         (second
           (cadr-cli::render-tui-entries
            entries 52 :now 3d0)))
    (is (equal first second))
    (is (every #'string=
               first second))))
