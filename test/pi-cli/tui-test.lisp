(in-package #:pi-cli/tests)
(in-suite pi-cli-suite)

(test dispatch-user-input-is-shared-by-frontends
  (let ((prompts nil)
        (commands nil))
    (is (eq :prompt
            (pi-cli::dispatch-user-input
             "hello"
             (lambda (text) (push text prompts))
             :command-function
             (lambda (line) (push line commands) nil))))
    (is (equal '("hello") prompts))
    (is (eq :command
            (pi-cli::dispatch-user-input
             "/known arg"
             (lambda (text) (push text prompts))
             :command-function
             (lambda (line)
               (push line commands)
               (values t "done")))))
    (multiple-value-bind (kind value)
        (pi-cli::dispatch-user-input
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
            (pi-cli::dispatch-user-input
             "/missing"
             (lambda (text) (push text prompts))
             :command-function (constantly nil))))))

(test tui-selection-policy-honors-flag-and-tty-state
  (flet ((terminal-p (stream direction)
           (declare (ignore stream direction))
           t)
         (not-terminal-p (stream direction)
           (declare (ignore stream direction))
           nil))
    (is (pi-cli::should-use-tui-p
         nil
         :terminal-p-function #'terminal-p))
    (is (not (pi-cli::should-use-tui-p
              t
              :terminal-p-function #'terminal-p)))
    (is (not (pi-cli::should-use-tui-p
              nil
              :terminal-p-function #'not-terminal-p)))))

(test cli-advertises-no-tui
  (let ((usage
          (with-output-to-string (stream)
            (pi-cli::print-cli-usage stream))))
    (is (search "--no-tui" usage))
    (is (null (search "--yolo" usage)))))

(test native-cli-parser-handles-values-flags-and-repeats
  (let ((arguments
          (pi-cli::parse-cli-arguments
           '("--provider=deepseek"
             "--model" "deepseek-v4-flash"
             "--extension" "one.lisp"
             "--extension=two.lisp"
             "--continue"
             "--no-tui"))))
    (is (string=
         "deepseek"
         (pi-cli::cli-arguments-provider
          arguments)))
    (is (string=
         "deepseek-v4-flash"
         (pi-cli::cli-arguments-model
          arguments)))
    (is (equal
         '("one.lisp" "two.lisp")
         (pi-cli::cli-arguments-extensions
          arguments)))
    (is (pi-cli::cli-arguments-continue-p
         arguments))
    (is (pi-cli::cli-arguments-no-tui-p
         arguments)))
  (signals pi-ai:configuration-error
    (pi-cli::parse-cli-arguments
     '("--model" "--continue"))))

(test tui-state-projects-stream-tools-and-usage
  (let* ((state
           (pi-cli::make-tui-state
            :model "gemini-3.6-flash"
            :session "session-1"))
         (message
           (pi-ai:make-assistant-message
            :api :google-generative-ai
            :provider :google
            :model "gemini-3.6-flash"
            :usage
            (pi-ai:make-usage
             :input 10 :output 4 :cache-read 2)
            :stop-reason :stop))
         (call
           (pi-ai:make-tool-call
            :id "call-1"
            :name "read"
            :arguments (args "path" "README.md")))
         (result
           (pi-ai:make-tool-result-message
            :tool-call-id "call-1"
            :tool-name "read"
            :content
            (list
             (pi-ai:make-text-content
              :text "file text")))))
    (pi-cli::tui-handle-agent-event
     state
     (pi-agent::make-agent-event
      :type :message-start
      :message message))
    (pi-cli::tui-handle-agent-event
     state
     (pi-agent::make-agent-event
      :type :message-update
      :message message
      :stream-event
      (pi-ai:make-stream-event
       :type :text-delta
       :delta "你好 **pi**")))
    (pi-cli::tui-handle-agent-event
     state
     (pi-agent::make-agent-event
      :type :tool-execution-start
      :tool-call call))
    (pi-cli::tui-handle-agent-event
     state
     (pi-agent::make-agent-event
      :type :tool-execution-end
      :tool-call call
      :tool-result result))
    (pi-cli::tui-handle-agent-event
     state
     (pi-agent::make-agent-event
      :type :message-end
      :message message))
    (let ((editor (pi-tui:make-multiline-editor)))
      (multiple-value-bind (lines row column)
          (pi-cli::render-tui-state state editor 40 12)
        (declare (ignore row column))
        (let ((screen (format nil "~{~A~%~}" lines)))
          (is (search "你好 pi" screen))
          (is (search "read" screen))
          (is (search "in:10" screen))
          (is (search "out:4" screen))
          (is (search "cache:2" screen)))))))

(test tui-input-sequence-produces-virtual-screen-snapshot
  (let* ((terminal
           (pi-tui:make-virtual-terminal
            :columns 24 :rows 6))
         (renderer
           (pi-tui:make-terminal-renderer
            terminal))
         (state
           (pi-cli::make-tui-state
            :model "gemini-3.6-flash"
            :session "s1"))
         (editor
           (pi-tui:make-multiline-editor))
         (decoder
           (pi-tui:make-input-decoder)))
    (dolist
        (event
         (pi-tui:feed-input
          decoder
          (format nil "中文👩‍💻~C[13;2u下一行"
                  #\Escape)))
      (pi-tui:editor-handle-event
       editor event))
    (multiple-value-bind (lines row column)
        (pi-cli::render-tui-state
         state editor 24 6)
      (pi-tui:render-frame
       renderer lines
       :cursor-row row
       :cursor-column column))
    (let ((snapshot
            (format
             nil "~{~A~%~}"
             (pi-tui:virtual-terminal-snapshot
              terminal))))
      (is (search "中文👩‍💻" snapshot))
      (is (search "下一行" snapshot))
      (is (search "gemini-3.6-flash" snapshot)))))
