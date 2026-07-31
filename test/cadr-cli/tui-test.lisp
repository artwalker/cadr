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
    :accessor
    footer-sync-test-terminal-before-second-read)))

(defmethod cadr-tui:terminal-read-input
    ((terminal footer-sync-test-terminal))
  (when
      (= 2
         (incf
          (footer-sync-test-terminal-reads terminal)))
    (funcall
     (footer-sync-test-terminal-before-second-read
      terminal)))
  (or
   (pop (footer-sync-test-terminal-inputs terminal))
   ""))

(defun footer-sync-submit-input (text)
  (format nil "~A~C" text #\Return))

(defun wait-for-footer-sync (predicate)
  (loop repeat 200
        when (funcall predicate)
          do (return t)
        do (sleep 0.005)
        finally
        (error "Timed out waiting for footer model synchronization")))

(defun rendered-footer-text (state)
  (multiple-value-bind (lines row column)
      (cadr-cli::render-tui-state
       state
       (cadr-tui:make-multiline-editor)
       100 8)
    (declare (ignore row column))
    (format nil "~{~A~^~%~}" lines)))

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
               (footer-sync-submit-input
                "/quit"))
              :before-second-read
              (lambda ()
                (wait-for-footer-sync
                 (lambda ()
                   (string= selected-model
                            "gpt-5.5"))))))
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
              "/quit"))
            :before-second-read
            (lambda ()
              (wait-for-footer-sync
               (lambda ()
                 (string= selected-model
                          "gpt-5.6-luna")))))))
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
      (is (= (1- (length alt-lines))
             alt-row)))))

(test idle-status-spacing-is-reserved-only-on-main-screen
  (is (= 1
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
