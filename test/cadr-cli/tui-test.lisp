(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

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
    (is (member "sessions" values :test #'string=))
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

(test cli-advertises-no-tui
  (let ((usage
          (with-output-to-string (stream)
            (cadr-cli::print-cli-usage stream))))
    (is (search "--no-tui" usage))
    (is (null (search "--yolo" usage)))))

(test native-cli-parser-handles-values-flags-and-repeats
  (let ((arguments
          (cadr-cli::parse-cli-arguments
           '("--provider=deepseek"
             "--model" "deepseek-v4-flash"
             "--extension" "one.lisp"
             "--extension=two.lisp"
             "--continue"
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
    (is (cadr-cli::cli-arguments-no-tui-p
         arguments)))
  (signals cadr-ai:configuration-error
    (cadr-cli::parse-cli-arguments
     '("--model" "--continue"))))

(test tui-state-projects-stream-tools-and-usage
  (let* ((state
           (cadr-cli::make-tui-state
            :model "gemini-3.6-flash"
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
          (cadr-cli::render-tui-state state editor 40 12)
        (declare (ignore row column))
        (let ((screen (format nil "~{~A~%~}" lines)))
          (is (search "你好 cadr" screen))
          (is (search "read" screen))
          (is (search "in:10" screen))
          (is (search "out:4" screen))
          (is (search "cache:2" screen)))))))

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
            :columns 24 :rows 6))
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
         state editor 24 6)
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
  (let ((selector
          (cadr-cli::make-import-confirmation-list
           "/import '/tmp/session.jsonl'"
           "/tmp/session.jsonl")))
    (let ((rendered
            (format
             nil "~{~A~^~%~}"
             (cadr-tui:render-select-list
              selector 80))))
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
         state editor 140 12
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
         state editor 40 16
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
            "Select Model" "Scope: scoped" "two")
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
                  (format nil "~{~A~^~%~}" lines)))
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
              (format nil "~{~A~^~%~}" lines)))
        (is (search "Settings" screen))
        (is (search "Auto-compact: on" screen))))))
