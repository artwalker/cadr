(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun cli-mock-model ()
  (cadr-ai:make-model
   :id "mock"
   :provider :openai
   :api :openai-responses
   :base-url "https://example.invalid"
   :max-tokens 128))

(test session-argument-path-p-matches-jsonl-suffix
  ;; Regression: reversed uiop:string-suffix-p arguments made real
  ;; session file paths (".jsonl" suffix) fail the check.
  (is-true (cadr-cli::session-argument-path-p "session.jsonl"))
  (is-true (cadr-cli::session-argument-path-p ".jsonl"))
  (is-true (cadr-cli::session-argument-path-p
            "/abs/path/session.jsonl"))
  (is-true (cadr-cli::session-argument-path-p
            "sub\\dir\\session.jsonl"))
  (is-false (cadr-cli::session-argument-path-p "019fabc")))

(test non-changelog-commands-never-resolve-the-changelog-path
  (let ((calls 0)
        (output (make-string-output-stream))
        (original
          (symbol-function
           'cadr-cli::default-changelog-path)))
    (unwind-protect
         (progn
           (setf
            (symbol-function
             'cadr-cli::default-changelog-path)
            (lambda ()
              (incf calls)
              (error "changelog path must stay lazy")))
           (is
            (cadr-cli::handle-session-command
             "/hotkeys" nil :output output))
           (is (zerop calls))
           (is (search "Keyboard Shortcuts"
                       (get-output-stream-string output))))
      (setf
       (symbol-function
        'cadr-cli::default-changelog-path)
       original))))

(test resume-option-opens-the-picker-session
  (with-test-directory (root)
    (let ((sessions (merge-pathnames "sessions/" root))
          (cwd (merge-pathnames "project/" root))
          (wanted-path nil)
          (output (make-string-output-stream)))
      (ensure-directories-exist
       (merge-pathnames "anchor" sessions))
      (ensure-directories-exist
       (merge-pathnames "anchor" cwd))
      (let ((wanted
              (cadr-agent:create-session
               :directory sessions :cwd cwd :id "wanted")))
        (setf
         wanted-path
         (namestring (cadr-agent:session-path wanted)))
        (cadr-agent:session-append-message
         wanted
         (cadr-ai:make-assistant-message
          :content
          (list (cadr-ai:make-text-content :text "persist"))
          :api :openai-responses
          :provider :openai
          :model "mock"
          :stop-reason :stop)))
      (let ((session
              (cadr-cli::resolve-cli-session
               :resume-selector-p t
               :picker-function
               (lambda (picker-cwd picker-directory)
                 (is (string=
                      (namestring cwd)
                      (namestring picker-cwd)))
               (is (string=
                      (namestring sessions)
                      (namestring picker-directory)))
                (values wanted-path nil))
               :cwd cwd
               :directory sessions
               :output output)))
        (is (string= "wanted"
                     (cadr-agent:session-id session))))
      ;; Baseline has no --continue/--resume conflict check; the named
      ;; session resolution precedes --continue (main.ts:341-377).
      (is (string= "wanted"
                   (cadr-agent:session-id
                    (cadr-cli::resolve-cli-session
                     :continue-p t
                     :resume-selector-p t
                     :picker-function
                     (lambda (picker-cwd picker-directory)
                       (declare (ignore picker-cwd picker-directory))
                       (values wanted-path nil))
                     :cwd cwd
                     :directory sessions
                     :output output))))
      ;; Baseline main.ts:376-379 — picker cancel prints dim
      ;; "No session selected" on stdout and exits 0; interrupt exits 0
      ;; silently (cli/session-picker.ts onExit).
      (let ((captured (make-string-output-stream)))
        (let ((*standard-output* captured))
          (handler-case
              (progn
                (cadr-cli::resolve-cli-session
                 :resume-selector-p t
                 :picker-function
                 (lambda (picker-cwd picker-directory)
                   (declare (ignore picker-cwd picker-directory))
                   (values nil nil))
                 :cwd cwd
                 :directory sessions
                 :output output)
                (is nil "picker cancel did not signal cli-session-abort"))
            (cadr-cli::cli-session-abort () t)))
        (is (search
             "No session selected"
             (cadr-tui:strip-terminal-sequences
              (get-output-stream-string captured)))))
      (let ((captured (make-string-output-stream)))
        (let ((*standard-output* captured))
          (handler-case
              (progn
                (cadr-cli::resolve-cli-session
                 :resume-selector-p t
                 :picker-function
                 (lambda (picker-cwd picker-directory)
                   (declare (ignore picker-cwd picker-directory))
                   (values nil t))
                 :cwd cwd
                 :directory sessions
                 :output output)
                (is nil "picker interrupt did not signal cli-session-abort"))
            (cadr-cli::cli-session-abort () t)))
        (is (string=
             ""
             (get-output-stream-string captured)))))))

(test nonbaseline-session-aliases-stay-out-of-slash-surface-and-export-works
  (with-test-directory (root)
    (let* ((sessions (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "project/" root))
           (_
             (ensure-directories-exist
              (merge-pathnames "anchor" cwd)))
           (first
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "first"))
           (second
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "second"))
           (first-node
             (cadr-agent:session-append-message
              first
              (cadr-ai:make-user-message :content "first root")))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (cli-mock-model)
              :session second))
           (output (make-string-output-stream))
           (export-path (merge-pathnames "export.html" root)))
      (declare (ignore _))
      (cadr-agent:session-append-message
       first
       (cadr-ai:make-assistant-message
        :content (list (cadr-ai:make-text-content :text "first answer"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (cadr-agent:session-append-message
       second
       (cadr-ai:make-assistant-message
        :content (list (cadr-ai:make-text-content :text "second answer"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (dolist (line '("/sessions" "/switch first" "/branch first"))
        (is (null
             (cadr-cli::handle-session-command
              line agent
              :directory sessions :cwd cwd :output output))))
      (cadr-cli::switch-agent-session agent first)
      (is (string= "first"
                   (cadr-agent:session-id
                    (cadr-agent:agent-session agent))))
      (cadr-agent:session-branch first first-node)
      (is (cadr-cli::handle-session-command
           (format nil "/export ~A" (namestring export-path))
           agent
           :directory sessions :cwd cwd :output output))
      (is (probe-file export-path))
      (let ((text (get-output-stream-string output)))
        (is (null (search "Switched to session" text)))
        (is (null (search "Branch point" text)))
        (is (search "Session exported to:" text))))))

(test goal13-default-html-export-name-and-status-match-the-baseline-rule
  (with-test-directory (root)
    (let* ((sessions (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "project/" root))
           (_
             (ensure-directories-exist
              (merge-pathnames "anchor" cwd)))
           (id "018f22b2-5aa0-7ab1-8a44-0123456789ab")
           (session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id id :timestamp 0))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (cli-mock-model)
              :session session))
           (expected-name
             (format
              nil
              "cadr-session-1970-01-01T00-00-00-000Z_~A.html"
              id))
           (expected-path
             (merge-pathnames expected-name cwd))
           (output (make-string-output-stream)))
      (declare (ignore _))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message :content "export me"))
      (is
       (cadr-cli::handle-session-command
        "/export" agent
        :directory sessions :cwd cwd :output output))
      (is (probe-file expected-path))
      (is (string=
           (format nil "Session exported to: ~A~%"
                   expected-name)
           (get-output-stream-string output))))))

(test goal13-session-ids-and-post-tui-resume-copy-match-the-baseline
  (with-test-directory (root)
    (let* ((sessions (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "project/" root))
           (_
             (ensure-directories-exist
              (merge-pathnames "anchor" cwd)))
           (session
             (cadr-agent:create-session
              :directory sessions :cwd cwd))
           (output (make-string-output-stream)))
      (declare (ignore _))
      (is
       (cl-ppcre:scan
        "^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
        (cadr-agent:session-id session)))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message :content "persist"))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content :text "persisted"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (is
       (cadr-cli::write-session-resume-hint
        session sessions
        :output output
        :terminal-p t
        :default-session-directory-p nil))
      (is
       (string=
        (format
         nil "To resume this session: cadr --session-dir ~A --session ~A~%"
         (cadr-cli::shell-quote
          (cadr-cli::display-directory-name sessions))
         (cadr-agent:session-id session))
        (cadr-tui:strip-terminal-sequences
         (get-output-stream-string output))))
      (let* ((arguments
               (cadr-cli::parse-cli-arguments
                (list
                 "--session-dir" (namestring sessions)
                 "--session" (cadr-agent:session-id session))))
             (resumed
               (cadr-cli::resolve-cli-session
                :session-path
                (cadr-cli::cli-arguments-session arguments)
                :directory
                (pathname
                 (cadr-cli::cli-arguments-session-directory arguments))
                :cwd cwd)))
        (is
         (string=
          (cadr-agent:session-id session)
          (cadr-agent:session-id resumed)))
        (is
         (string=
          (namestring (cadr-agent:session-path session))
          (namestring (cadr-agent:session-path resumed))))))))

(test copy-clone-and-import-commands-match-interactive-session-semantics
  (with-test-directory (root)
    (let* ((sessions
             (merge-pathnames "sessions/" root))
           (imports
             (merge-pathnames "imports/" root))
           (cwd
             (merge-pathnames "project/" root))
           (_
             (ensure-directories-exist
              (merge-pathnames "anchor" cwd)))
           (source
             (cadr-agent:create-session
              :directory sessions
              :cwd cwd
              :id "source"))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (cli-mock-model)
              :session source))
           (copied nil)
           (output
             (make-string-output-stream)))
      (declare (ignore _))
      (cadr-agent:session-append-message
       source
       (cadr-ai:make-user-message
        :content "question"))
      (cadr-agent:session-append-message
       source
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content
          :text " first ")
         (cadr-ai:make-thinking-content
          :thinking "hidden")
         (cadr-ai:make-text-content
          :text "second "))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (setf
       (cadr-agent:agent-messages agent)
       (cadr-agent:session-messages source))
      (is
       (cadr-cli::handle-session-command
        "/copy" agent
        :directory sessions
        :cwd cwd
        :output output
        :copy-function
        (lambda (text)
          (setf copied text))))
      (is (string= "first second" copied))
      (let ((old-path
              (cadr-agent:session-path source)))
        (is
         (cadr-cli::handle-session-command
          "/clone" agent
          :directory sessions
          :cwd cwd
          :output output))
        (is (not
             (string=
              "source"
              (cadr-agent:session-id
               (cadr-agent:agent-session agent)))))
        (is (string=
             (namestring old-path)
             (cadr-agent:session-parent-session
              (cadr-agent:agent-session agent))))
        (is (= 2
               (length
                (cadr-agent:session-messages
                 (cadr-agent:agent-session agent))))))
      (let ((imported
              (cadr-agent:create-session
               :directory imports
               :cwd cwd
               :id "outside")))
        (cadr-agent:session-append-message
         imported
         (cadr-ai:make-assistant-message
          :content
          (list
           (cadr-ai:make-text-content
            :text "imported"))
          :api :openai-responses
          :provider :openai
          :model "mock"
          :stop-reason :stop))
        (is
         (cadr-cli::handle-session-command
          (format nil "/import \"~A\""
                  (namestring
                   (cadr-agent:session-path imported)))
          agent
          :directory sessions
          :cwd cwd
          :output output
          :confirm-function
          (lambda (title message)
            (is (string= "Import session" title))
            (is (search "Replace current session"
                        message))
            t)))
        (is (string= "outside"
                     (cadr-agent:session-id
                      (cadr-agent:agent-session
                       agent))))
        (is (probe-file
             (merge-pathnames
              "outside.jsonl" sessions))))
      (is
       (cadr-cli::handle-session-command
        "/import /does/not/exist.jsonl"
        agent
        :directory sessions
        :cwd cwd
        :output output
        :confirm-function
        (lambda (title message)
          (declare (ignore title message))
          t)))
      (let ((text
              (get-output-stream-string
               output)))
        (is (search
             "Copied last agent message to clipboard"
             text))
        (is (search
             "Cloned to new session" text))
        (is (search
             "Session imported from:" text))
        (is (search
             "Failed to import session: File not found:"
             text))))))

(test name-session-new-and-fork-commands-match-interactive-semantics
  (with-test-directory (root)
    (let* ((sessions
             (merge-pathnames "sessions/" root))
           (cwd
             (merge-pathnames "project/" root))
           (_
             (ensure-directories-exist
              (merge-pathnames "anchor" cwd)))
           (source
             (cadr-agent:create-session
              :directory sessions
              :cwd cwd
              :id "source"))
           (lifecycle-events nil)
           (bundle
             (cadr-agent::make-extension-bundle
              :id "session-production-events"
              :path "/tmp/session-production-events.lisp"))
           (host (cadr-agent::make-extension-host :cwd cwd))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (cli-mock-model)
              :session source
              :extension-host host))
           (output
             (make-string-output-stream)))
      (declare (ignore _))
      (cadr-agent::call-with-extension-registration
       bundle
       (lambda ()
         (dolist (event '(:session-info-changed
                          :session-before-switch
                          :session-before-fork
                          :session-shutdown
                          :session-start))
           (cadr-agent:define-event-hook
            event
            :handler
            (lambda (value context)
              (declare (ignore context))
              (push (cadr-agent:extension-event-type value)
                    lifecycle-events)
              nil)))))
      (cadr-agent::replace-extension-bundles host (list bundle))
      (let ((first-user
              (cadr-agent:session-append-message
               source
               (cadr-ai:make-user-message
                :content "first question"))))
        (cadr-agent:session-append-message
         source
         (cadr-ai:make-assistant-message
          :content
          (list
           (cadr-ai:make-text-content
            :text "answer"))
          :api :openai-responses
          :provider :openai
          :model "mock"
          :usage
          (cadr-ai:make-usage
           :input 10
           :output 5
           :cache-read 2
           :cache-write 3
           :cost
           (cadr-ai:make-cost
            :input 0.01d0
            :output 0.02d0
            :cache-read 0.003d0
            :cache-write 0.004d0
            :total 0.037d0))
          :stop-reason :stop))
        (cadr-agent:session-append-compaction
         source
         "summary"
         (list first-user)
         first-user
         20
         :usage
         (cadr-ai:make-usage
          :input 4
          :output 2
          :cache-read 1
          :cost
          (cadr-ai:make-cost
           :input 0.004d0
           :output 0.005d0
           :cache-read 0.001d0
           :total 0.01d0)))
        (setf
         (cadr-agent:agent-messages agent)
         (cadr-agent:session-messages source))
        (is
         (cadr-cli::handle-session-command
          (format nil "/name   sprint~%review  ")
          agent
          :directory sessions
          :cwd cwd
          :output output))
        (is (string=
             "sprint review"
             (cadr-agent:session-name source)))
        (is
         (cadr-cli::handle-session-command
          "/name"
          agent
          :directory sessions
          :cwd cwd
          :output output))
        (is
         (cadr-cli::handle-session-command
          "/session"
          agent
          :directory sessions
          :cwd cwd
          :output output))
        (multiple-value-bind
              (fork selected-text)
            (cadr-cli::fork-agent-session
             agent first-user sessions)
          (is (typep fork 'cadr-agent:session))
          (is (string= "first question"
                       selected-text))
          (is (null
               (cadr-agent:session-messages
                fork)))
          (is (string=
               (namestring
                (cadr-agent:session-path source))
               (cadr-agent:session-parent-session
                fork))))
        (let ((new
                (cadr-cli::new-agent-session
                 agent sessions cwd)))
          (is (typep new 'cadr-agent:session))
          (is (null
               (cadr-agent:session-messages new)))
          (is (eq new
                  (cadr-agent:agent-session
                   agent)))))
      (dolist (event '(:session-info-changed
                       :session-before-switch
                       :session-before-fork
                       :session-shutdown
                       :session-start))
        (is (member event lifecycle-events)))
      (let ((text
              (get-output-stream-string
               output)))
        (is (search "Session name set: sprint review"
                    text))
        (is (search "Session name: sprint review"
                    text))
        (is (search "Session Info" text))
        (is (search "User: 1" text))
        (is (search "Assistant: 1" text))
        (is (search "Input: 20" text))
        (is (search "Output: 7" text))
        (is (search "Total: 27" text))
        (is (search "Cost" text))
        (is (search "$0.047" text))))))

(test goal17-name-without-argument-uses-baseline-warning-channel
  (with-test-directory (root)
    (let* ((sessions (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "project/" root))
           (_
             (ensure-directories-exist
              (merge-pathnames "anchor" cwd)))
           (session
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "unnamed"))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (cli-mock-model)
              :session session))
           (output (make-string-output-stream))
           (statuses nil))
      (declare (ignore _))
      (is
       (cadr-cli::handle-session-command
        "/name" agent
        :directory sessions
        :cwd cwd
        :output output
        :status-function
        (lambda (text &optional (level :status))
          (push (list text level) statuses))))
      (is
       (equal
        '(("Usage: /name <name>" :warning))
        statuses))
      (is (string= "" (get-output-stream-string output))))))

(test post-goal15-session-info-matches-baseline-spacing-styles-percent-and-cost-breakdown
  (with-test-directory (root)
    (let* ((sessions (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "project/" root))
           (_
             (ensure-directories-exist
              (merge-pathnames "anchor" cwd)))
           (session
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "session-stats"))
           (agent
             (cadr-agent:make-agent
              :provider :openai-codex
              :model (cli-mock-model)
              :session session))
           (output (make-string-output-stream)))
      (declare (ignore _))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message :content "first"))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content (list (cadr-ai:make-text-content :text "one"))
        :api :openai-responses
        :provider :openai-codex
        :model "gpt-5.6-luna"
        :response-model "gpt-5.6-luna-2026-07-01"
        :usage
        (cadr-ai:make-usage
         :input 10000 :output 1000 :cache-write 90000
         :cost
         (cadr-ai:make-cost
          :input 0.010d0 :output 0.010d0
          :cache-write 0.090d0 :total 0.110d0))
        :stop-reason :stop :timestamp 1000))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message :content "second"))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content (list (cadr-ai:make-text-content :text "two"))
        :api :openai-responses
        :provider :openai-codex
        :model "gpt-5.6-luna"
        :usage
        (cadr-ai:make-usage
         :input 60000 :output 2000 :cache-read 50000
         :cost
         (cadr-ai:make-cost
          :input 0.060d0 :output 0.020d0
          :cache-read 0.005d0 :total 0.085d0))
        :stop-reason :stop :timestamp 2000))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content (list (cadr-ai:make-text-content :text "three"))
        :api :openai-completions
        :provider :deepseek
        :model "deepseek-v4-flash"
        :usage
        (cadr-ai:make-usage
         :input 0 :output 400 :cache-read 3000
         :cost
         (cadr-ai:make-cost
          :cache-read 0.003d0 :output 0.001d0 :total 0.004d0))
        :stop-reason :stop :timestamp 3000))
      (let ((first-id
              (cadr-agent:session-entry-id
               (first (cadr-agent:session-entries session)))))
        (cadr-agent:session-append-compaction
         session "summary" (list first-id) first-id 1000
         :usage
         (cadr-ai:make-usage
          :input 500 :output 100
          :cost
          (cadr-ai:make-cost
           :input 0.001d0 :output 0.001d0 :total 0.002d0))))
      (is
       (cadr-cli::handle-session-command
        "/session" agent
        :directory sessions :cwd cwd :output output
        :ansi-theme-p t))
      (let* ((styled (get-output-stream-string output))
             (plain
               (cadr-tui:strip-terminal-sequences styled)))
        (is (search (format nil "Session Info~%~%File:") plain))
        (is (search (format nil "Messages~%Total:") plain))
        (is (search (format nil "Tokens~%Input:") plain))
        (is (search "Cached: 53,000 (24.8%)" plain))
        (is (search "Uncached: 160,500 (90,000 written to cache)" plain))
        (is (search (format nil "Cache Warming~%Mode: streaming") plain))
        (is (search "Status: Inactive (waiting for first request)" plain))
        (is (search "openai-codex/gpt-5.6-luna-2026-07-01: $0.110 (101k tokens)" plain))
        (is (search "openai-codex/gpt-5.6-luna: $0.085 (112k tokens)" plain))
        (is (search "deepseek/deepseek-v4-flash: $0.004 (3.4k tokens)" plain))
        (is (search "Tools/summaries: $0.002 (600 tokens)" plain))
        (is (search "Cache Re-billed: $0.045 (50,000 tokens, 1 miss)" plain))
        (is (search (format nil "~C[1mSession Info" #\Escape) styled))
        (is (search (format nil "~C[1mMessages" #\Escape) styled))
        (is (search (format nil "~C[1mTokens" #\Escape) styled))
        (is (search (format nil "~C[1mCache Warming" #\Escape) styled))
        (is (search (format nil "~C[1mCost" #\Escape) styled))))))

(test post-goal15-hotkeys-table-uses-baseline-natural-column-widths
  (let* ((lines
           (cadr-tui:render-markdown
            (cadr-cli::hotkeys-command-markdown)
            100 :padding-x 1))
         (plain
           (mapcar
            (lambda (line)
              (string-right-trim
               " "
               (cadr-tui:strip-terminal-sequences
                line)))
            lines)))
    (is
     (find
      " │ Ctrl+P / Shift+Ctrl+P │ Cycle models                             │"
      plain :test #'string=))
    (is
     (find
      " │ !!                    │ Run bash command (excluded from context) │"
      plain :test #'string=))))

(test fork-during-active-tool-leaves-replacement-empty
  ;; Baseline #8724: fork while a tool is running settles that turn on
  ;; the outgoing session. The replacement starts empty, and the next
  ;; prompt sees only the new user message.
  (with-test-directory (directory)
    (let* ((started (sb-thread:make-semaphore :count 0))
           (captured nil)
           (responses
             (list
              (cadr-ai:make-assistant-message
               :content
               (list
                (cadr-ai:make-text-content
                 :text "first response"))
               :api :openai-responses
               :provider :openai
               :model "mock"
               :stop-reason :stop)
              (cadr-ai:make-assistant-message
               :content
               (list
                (cadr-ai:make-tool-call
                 :id "block-1"
                 :name "block"
                 :arguments (cadr-ai::json-object)))
               :api :openai-responses
               :provider :openai
               :model "mock"
               :stop-reason :tool-use)
              (cadr-ai:make-assistant-message
               :content
               (list
                (cadr-ai:make-text-content
                 :text "next response"))
               :api :openai-responses
               :provider :openai
               :model "mock"
               :stop-reason :stop)))
           (tool
             (cadr-ai:make-tool
              :name "block"
              :description "Wait until aborted"
              :parameters
              (cadr-ai::json-object "type" "object")
              :executor
              (lambda (call-id arguments)
                (declare (ignore call-id arguments))
                (sb-thread:signal-semaphore started)
                (cadr-core:wait-for-cancellation
                 (cadr-agent::%extension-cancellation-signal-state
                  (cadr-agent::current-tool-cancellation-signal))
                 :timeout 5.0d0)
                (values
                 (list
                  (cadr-ai:make-text-content
                   :text "tool aborted"))
                 nil))))
           (source
             (cadr-agent:create-session
              :directory directory
              :cwd directory
              :id "fork-during-tool"))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (cli-mock-model)
              :session source
              :auto-compact-p nil
              :auto-retry-p nil
              :tools (list tool)
              :stream-function
              (lambda (provider model context on-event
                       &key abort-p &allow-other-keys)
                (declare (ignore provider model))
                (push
                 (mapcar
                  (lambda (message)
                    (typecase message
                      (cadr-ai:user-message :user)
                      (cadr-ai:assistant-message :assistant)
                      (cadr-ai:tool-result-message :tool)
                      (t :other)))
                  (cadr-ai:context-messages context))
                 captured)
                (let ((message
                        (if (and abort-p (funcall abort-p))
                            (cadr-ai:make-assistant-message
                             :content nil
                             :api :openai-responses
                             :provider :openai
                             :model "mock"
                             :stop-reason :error
                             :error-message
                             "This operation was aborted")
                            (pop responses))))
                  (funcall
                   on-event
                   (cadr-ai:make-stream-event
                    :type :start :message message))
                  message)))))
      (unwind-protect
           (progn
             (cadr-agent:agent-prompt agent "first prompt")
             (let* ((entry-id
                      (getf
                       (first
                        (cadr-cli::session-user-messages-for-forking
                         source))
                       :entry-id))
                    (thread
                      (sb-thread:make-thread
                       (lambda ()
                         (cadr-agent:agent-prompt
                          agent "start blocking tool"))
                       :name "fork-during-tool")))
               (is-true
                (sb-thread:wait-on-semaphore
                 started :timeout 5))
               (multiple-value-bind (fork text)
                   (cadr-cli::fork-agent-session
                    agent entry-id directory)
                 (sb-thread:join-thread thread)
                 (is (string= "first prompt" text))
                 (is (eq fork
                         (cadr-agent:agent-session agent)))
                 (is (null
                      (cadr-agent:session-messages fork)))
                 (is
                  (find-if
                   (lambda (message)
                     (typep
                      message
                      'cadr-ai:tool-result-message))
                   (cadr-agent:session-messages source)))
                 (cadr-agent:agent-prompt agent "next prompt")
                 (is (equal '(:user) (first captured))))))
        (cadr-agent:agent-shutdown agent)))))

(test unflushed-persisted-fork-waits-for-the-first-assistant
  ;; Baseline agent-session-runtime.test.ts: the session file stays
  ;; unwritten until the first assistant entry. Clone and a non-root
  ;; fork say so instead of branching from memory.
  (with-test-directory (directory)
    (let* ((session
             (cadr-agent:create-session
              :directory directory
              :cwd directory
              :id "unflushed-fork"))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (cli-mock-model)
              :session session
              :auto-compact-p nil))
           (expected
             "This session has not been saved yet. Wait for the first assistant response before cloning or forking it."))
      (cadr-agent:session-append-model-change
       session "openai" "mock")
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message :content "hello"))
      (is (null
           (probe-file
            (cadr-agent:session-path session))))
      (let ((entry-id
              (getf
               (first
                (cadr-cli::session-user-messages-for-forking
                 session))
               :entry-id)))
        (flet ((message-of (thunk)
                 (handler-case
                     (progn (funcall thunk) nil)
                   (cadr-ai:configuration-error (condition)
                     (cadr-ai:cadr-error-message
                      condition)))))
          (is (string=
               expected
               (message-of
                (lambda ()
                  (cadr-cli::fork-agent-session
                   agent entry-id directory)))))
          (is (string=
               expected
               (message-of
                (lambda ()
                  (cadr-cli::clone-agent-session
                   agent directory)))))))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content :text "ok"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (is (probe-file
           (cadr-agent:session-path session)))
      (is (typep
           (cadr-cli::clone-agent-session
            agent directory)
           'cadr-agent:session)))))

(test exact-session-id-resolves-without-list-session-infos
  ;; pi#9601: exact ids use find-session-path-by-id (headers only).
  (with-test-directory (root)
    (let* ((sessions (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "project/" root))
           (_
             (ensure-directories-exist
              (merge-pathnames "anchor" cwd)))
           (alpha
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "exact-alpha-id"))
           (beta
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "exact-beta-id"))
           (original
             (symbol-function
              'cadr-agent:list-session-infos)))
      (declare (ignore _))
      (flet ((persist (session text)
               (cadr-agent:session-append-message
                session
                (cadr-ai:make-user-message :content text))
               (cadr-agent:session-append-message
                session
                (cadr-ai:make-assistant-message
                 :content
                 (list
                  (cadr-ai:make-text-content :text text))
                 :api :openai-responses
                 :provider :openai
                 :model "mock"
                 :stop-reason :stop))))
        (persist alpha "alpha body")
        (persist beta "beta body"))
      (is (probe-file (cadr-agent:session-path alpha)))
      (is (probe-file (cadr-agent:session-path beta)))
      (unwind-protect
           (progn
             (setf
              (symbol-function
               'cadr-agent:list-session-infos)
              (lambda (&rest args)
                (declare (ignore args))
                (error
                 "list-session-infos must not run for exact id")))
             (let ((resolved
                     (cadr-cli::resolve-session-reference
                      "exact-alpha-id" sessions cwd)))
               (is (string=
                    "exact-alpha-id"
                    (cadr-agent:session-id resolved)))
               (is
                (string=
                 (namestring
                  (cadr-agent:session-path alpha))
                 (namestring
                  (cadr-agent:session-path resolved)))))
             (let ((opened
                     (cadr-cli::resolve-cli-session
                      :session-id "exact-beta-id"
                      :directory sessions
                      :cwd cwd
                      :output (make-string-output-stream))))
               (is (string=
                    "exact-beta-id"
                    (cadr-agent:session-id opened)))))
        (setf
         (symbol-function
          'cadr-agent:list-session-infos)
         original)))))

(test prefix-session-id-still-uses-list-session-infos
  (with-test-directory (root)
    (let* ((sessions (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "project/" root))
           (_
             (ensure-directories-exist
              (merge-pathnames "anchor" cwd)))
           (session
             (cadr-agent:create-session
              :directory sessions
              :cwd cwd
              :id "prefix-target-full"))
           (list-calls 0)
           (original
             (symbol-function
              'cadr-agent:list-session-infos)))
      (declare (ignore _))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message :content "prefix body"))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content :text "prefix body"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (is (probe-file (cadr-agent:session-path session)))
      (unwind-protect
           (progn
             (setf
              (symbol-function
               'cadr-agent:list-session-infos)
              (lambda (&rest args)
                (incf list-calls)
                (apply original args)))
             (let ((resolved
                     (cadr-cli::resolve-session-reference
                      "prefix-target" sessions cwd)))
               (is (string=
                    "prefix-target-full"
                    (cadr-agent:session-id resolved)))
               (is (plusp list-calls))))
        (setf
         (symbol-function
          'cadr-agent:list-session-infos)
         original)))))
