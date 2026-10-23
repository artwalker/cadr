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
  ;; v1.4.0 exportSessionToHtml writes the default basename with
  ;; writeFileSync, which is relative to process.cwd(), and returns that
  ;; basename for the status line.
  (with-test-directory (root)
    (let* ((sessions (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "project/" root))
           (launch (merge-pathnames "launch/" root))
           (_
             (ensure-directories-exist
              (merge-pathnames "anchor" cwd)))
           (_2 (ensure-directories-exist launch))
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
             (merge-pathnames expected-name launch))
           (output (make-string-output-stream)))
      (declare (ignore _ _2))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message :content "export me"))
      (uiop:with-current-directory (launch)
        (is
         (cadr-cli::handle-session-command
          "/export" agent
          :directory sessions :cwd cwd :output output))
        (is (probe-file expected-path))
        (is (not (probe-file (merge-pathnames expected-name cwd))))
        (is (string=
             (format nil "Session exported to: ~A~%"
                     expected-name)
             (get-output-stream-string output)))))))

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
            (cadr-cli::hotkeys-command-markdown
             nil
             (cadr-tui:default-keybinding-definitions
              :platform "linux" :environment nil))
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

(test fork-during-active-tool-keeps-only-the-tool-baseline
  ;; Baseline #8724: fork while a tool is running settles that turn on
  ;; the outgoing session. The replacement keeps the tools-only system
  ;; ancestor but no conversation turn.
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
                      (cadr-ai:system-message :system)
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
                 (let ((messages
                         (cadr-agent:session-messages fork)))
                   (is (= 1 (length messages)))
                   (is (typep (first messages)
                              'cadr-ai:system-message))
                   (is (string=
                        ""
                        (cadr-ai:system-message-content
                         (first messages))))
                   (is
                    (equal
                     '("block")
                     (mapcar
                      #'cadr-ai:tool-name
                      (cadr-ai:system-message-tools-added
                       (first messages)))))
                   (is (notany
                        (lambda (message)
                          (or
                           (typep message 'cadr-ai:user-message)
                           (typep message 'cadr-ai:assistant-message)
                           (typep message
                                  'cadr-ai:tool-result-message)))
                        messages)))
                 (is
                  (find-if
                   (lambda (message)
                     (typep
                      message
                      'cadr-ai:tool-result-message))
                   (cadr-agent:session-messages source)))
                 (setf
                  (cadr-agent::agent-tool-filter-function agent)
                  (constantly nil))
                 (cadr-agent::refresh-agent-extension-tools agent)
                 (cadr-agent:agent-prompt agent "next prompt")
                 (is (equal '(:system :system :user)
                            (first captured))))))
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

(test offline-bug-report-writes-a-local-zip
  (with-test-directory (root)
    (let ((agent
            (cadr-agent:make-agent
             :provider :mock
             :model (cli-mock-model)))
          (output (make-string-output-stream))
          (previous (uiop:getenv "CADR_OFFLINE")))
      (unwind-protect
           (uiop:with-current-directory (root)
             (setf (uiop:getenv "CADR_OFFLINE") "1")
             (is (cadr-cli::handle-session-command
                  "/bug" agent
                  :cwd root
                  :output output))
             (let ((zips
                     (directory
                      (merge-pathnames
                       "cadr-bug-report-*.zip" root))))
               (is (= 1 (length zips))))
             (let ((text (get-output-stream-string output)))
               (is (search "Bug report exported to:" text))
               (is (null (search "Upload" text)))))
        (if previous
            (setf (uiop:getenv "CADR_OFFLINE") previous)
            (sb-posix:unsetenv "CADR_OFFLINE"))))))

(defun read-export-jsonl (path)
  (with-open-file (stream path :external-format :utf-8)
    (loop for line = (read-line stream nil nil)
          while line
          collect (cadr-ai::parse-json line))))

(defun export-jsonl-text (path)
  (let ((text (uiop:read-file-string path)))
    (is (plusp (length text)))
    (is (char= #\Newline (char text (1- (length text)))))
    (is (or (< (length text) 2)
            (not (char= #\Newline
                        (char text (- (length text) 2))))))
    text))

(test jsonl-export-rewrites-the-current-branch-and-leaves-the-tree
  ;; v1.4.0 session-export.ts serializeSessionBranch and
  ;; export-jsonl-share.test.ts: header is a fresh session record,
  ;; parentId follows the branch, and a normal export has no pi.share.
  (with-test-directory (root)
    (let* ((sessions (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "project/" root))
           (_ (ensure-directories-exist
               (merge-pathnames "anchor" cwd)))
           (session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :timestamp 0
              :parent-session "/tmp/parent.jsonl"))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (cli-mock-model)
              :session session))
           (model-id
             (cadr-agent:session-append-model-change
              session "openai" "mock"))
           (user-id
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message :content "hello")))
           (abandoned-id
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-assistant-message
               :content
               (list (cadr-ai:make-text-content
                      :text "abandoned-answer"))
               :api :openai-responses
               :provider :openai
               :model "mock"
               :stop-reason :stop)))
           (kept-id
             (progn
               (cadr-agent:session-branch session user-id)
               (cadr-agent:session-append-message
                session
                (cadr-ai:make-assistant-message
                 :content
                 (list (cadr-ai:make-text-content
                        :text "kept-answer"))
                 :api :openai-responses
                 :provider :openai
                 :model "mock"
                 :stop-reason :stop))))
           (output (make-string-output-stream))
           (status nil)
           (export-path (merge-pathnames "nested/out.jsonl" cwd)))
      (declare (ignore _ abandoned-id))
      (uiop:with-current-directory (cwd)
        (is (cadr-cli::handle-session-command
             "/export \"nested/out.jsonl\" extra"
             agent
             :directory sessions :cwd cwd :output output
             :status-function
             (lambda (message &optional level)
               (setf status (list message level))))))
      (is (probe-file export-path))
      (is (equal (list (format nil "Session exported to: ~A"
                               (namestring export-path))
                       nil)
                 status))
      (let* ((text (export-jsonl-text export-path))
             (records (read-export-jsonl export-path))
             (header (first records))
             (entries (rest records)))
        (is (null (search "abandoned-answer" text)))
        (is (null (search "pi.share" text)))
        (is (string= "session" (cadr-ai::json-get header "type")))
        (is (= 3 (cadr-ai::json-get header "version")))
        (is (string= (cadr-agent:session-id session)
                     (cadr-ai::json-get header "id")))
        (is (string= (cadr-agent:session-cwd session)
                     (cadr-ai::json-get header "cwd")))
        (is (not (cadr-ai::json-present-p header "parentSession")))
        (is (cl-ppcre:scan
             "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z$"
             (cadr-ai::json-get header "timestamp")))
        (is (string/= "1970-01-01T00:00:00.000Z"
                      (cadr-ai::json-get header "timestamp")))
        (is (= 3 (length entries)))
        (is (equal (list model-id user-id kept-id)
                   (mapcar (lambda (record)
                             (cadr-ai::json-get record "id"))
                           entries)))
        (is (cadr-ai::json-null-p
             (cadr-ai::json-get (first entries) "parentId")))
        (is (equal (list model-id user-id)
                   (mapcar (lambda (record)
                             (cadr-ai::json-get record "parentId"))
                           (rest entries))))
        (is (string= "model_change"
                     (cadr-ai::json-get (first entries) "type")))
        (is (string= "openai"
                     (cadr-ai::json-get (first entries) "provider")))
        (is (string= "mock"
                     (cadr-ai::json-get (first entries) "modelId")))
        (is (string= "user"
                     (cadr-ai::json-get
                      (cadr-ai::json-get (second entries) "message")
                      "role")))
        (is (string= "hello"
                     (cadr-ai::json-get
                      (cadr-ai::json-get (second entries) "message")
                      "content")))
        (is (search "kept-answer" text))
        (is (string= user-id
                     (cadr-agent:session-entry-parent-id
                      (gethash kept-id
                               (cadr-agent::session-by-id
                                session)))))))))

(test jsonl-export-stops-when-a-parent-is-missing
  ;; v1.4.0 SessionManager.getBranch includes the entry whose parent
  ;; is absent and then stops. It does not signal.
  (with-test-directory (root)
    (let* ((sessions (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "project/" root))
           (_ (ensure-directories-exist
               (merge-pathnames "anchor" cwd)))
           (session
             (cadr-agent:create-session
              :directory sessions :cwd cwd :timestamp 0))
           (user-id
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message :content "root-text")))
           (kept-id
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-assistant-message
               :content
               (list (cadr-ai:make-text-content :text "kept"))
               :api :openai-responses
               :provider :openai
               :model "mock"
               :stop-reason :stop)))
           (path (merge-pathnames "branch.jsonl" cwd)))
      (declare (ignore _))
      (setf (cadr-agent:session-entry-parent-id
             (gethash user-id (cadr-agent::session-by-id session)))
            "missing")
      (uiop:with-current-directory (cwd)
        (cadr-cli::export-session-jsonl session "branch.jsonl" cwd))
      (let ((records (read-export-jsonl path)))
        (is (= 3 (length records)))
        (is (equal (list user-id kept-id)
                   (mapcar (lambda (record)
                             (cadr-ai::json-get record "id"))
                           (rest records))))
        (is (cadr-ai::json-null-p
             (cadr-ai::json-get (second records) "parentId")))
        (is (string= user-id
                     (cadr-ai::json-get (third records) "parentId")))))))

(test jsonl-export-other-paths-stay-html
  ;; v1.4.0 handleExportCommand: endsWith(".jsonl") is case sensitive.
  ;; A missing path, .JSONL, and any other suffix stay HTML.
  ;; export-html/index.ts normalizePath leaves the relative string,
  ;; writeFileSync writes it against process.cwd(), and that string
  ;; is the status line. Node 22 keeps "./page.html", "../side.html",
  ;; and "foo/./bar.html"; it does not call path.resolve on them.
  ;; writeFileSync does not create a missing parent. Node 22.22.0
  ;; reports ENOENT for nested/report.html and foo/./bar.html and
  ;; leaves the directory absent. The same paths succeed once the
  ;; parent exists, and the status line keeps the normalizePath string.
  (with-test-directory (root)
    (let* ((sessions (merge-pathnames "sessions/" root))
           (session-dir (merge-pathnames "project/" root))
           (launch (merge-pathnames "launch/" root))
           (_ (progn
                (ensure-directories-exist
                 (merge-pathnames "anchor" session-dir))
                (ensure-directories-exist
                 (merge-pathnames "anchor" launch))))
           (session
             (cadr-agent:create-session
              :directory sessions :cwd session-dir :timestamp 0))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (cli-mock-model)
              :session session))
           (output (make-string-output-stream))
           (errors nil)
           (basename nil))
      (declare (ignore _))
      (cadr-agent:session-append-message
       session (cadr-ai:make-user-message :content "export me"))
      (uiop:with-current-directory (launch)
        (dolist (line '("/export report.JSONL"
                        "/export report.jsonl.bak"
                        "/export ./page.html"
                        "/export ../side.html"
                        "/export"))
          (is (cadr-cli::handle-session-command
               line agent
               :directory sessions :cwd session-dir :output output)))
        (dolist (line '("/export \"nested/report.html\""
                        "/export foo/./bar.html"))
          (is (cadr-cli::handle-session-command
               line agent
               :directory sessions :cwd session-dir :output output
               :status-function
               (lambda (message &optional level)
                 (push (list message level) errors)))))
        (setf errors (nreverse errors))
        (is (equal
             errors
             '(("Failed to export session: ENOENT: no such file or directory, open 'nested/report.html'"
                :error)
               ("Failed to export session: ENOENT: no such file or directory, open 'foo/./bar.html'"
                :error))))
        (is (not (probe-file (merge-pathnames "nested/" launch))))
        (is (not (probe-file (merge-pathnames "foo/" launch))))
        (is (not (probe-file
                  (merge-pathnames "nested/report.html" launch))))
        (is (not (probe-file
                  (merge-pathnames "foo/bar.html" launch))))
        (ensure-directories-exist
         (merge-pathnames "nested/anchor" launch))
        (ensure-directories-exist
         (merge-pathnames "foo/anchor" launch))
        (dolist (line '("/export \"nested/report.html\""
                        "/export foo/./bar.html"))
          (is (cadr-cli::handle-session-command
               line agent
               :directory sessions :cwd session-dir :output output)))
        (setf basename
              (cadr-cli::session-export-basename session)))
      (dolist (name '("report.JSONL" "report.jsonl.bak"
                      "nested/report.html" "page.html"
                      "foo/bar.html"))
        (let ((path (merge-pathnames name launch)))
          (is (probe-file path))
          (is (not (probe-file (merge-pathnames name session-dir))))
          (with-open-file (stream path :external-format :utf-8)
            (is (char= #\< (peek-char t stream))))))
      (is (probe-file (merge-pathnames "foo/./bar.html" launch)))
      (is (probe-file (merge-pathnames "../side.html" launch)))
      (is (probe-file (merge-pathnames basename launch)))
      (is (not (probe-file (merge-pathnames basename session-dir))))
      (let ((text (get-output-stream-string output)))
        (is (search "Session exported to: report.JSONL" text))
        (is (search "Session exported to: report.jsonl.bak" text))
        (is (search "Session exported to: nested/report.html" text))
        (is (search "Session exported to: ./page.html" text))
        (is (search "Session exported to: ../side.html" text))
        (is (search "Session exported to: foo/./bar.html" text))
        (is (search (format nil "Session exported to: ~A~%" basename)
                    text))
        (is (not (search "Session exported to: report.html" text)))
        (is (not (search "Session exported to: page.html" text)))
        (is (not (search "Session exported to: side.html" text)))
        (is (not (search "Session exported to: bar.html" text)))))))

(test jsonl-export-default-name-uses-a-fresh-stamp
  ;; v1.4.0 exportSessionToJsonl omits the path and writes
  ;; session-<ISO with : and . replaced>.jsonl in cwd. The header
  ;; timestamp is its own clock read.
  (with-test-directory (root)
    (let* ((cwd (merge-pathnames "project/" root))
           (_ (ensure-directories-exist
               (merge-pathnames "anchor" cwd)))
           (session
             (cadr-agent:create-session
              :directory (merge-pathnames "sessions/" root)
              :cwd cwd :timestamp 0 :persist-p nil))
           (written nil)
           (records nil))
      (declare (ignore _))
      (uiop:with-current-directory (cwd)
        (setf written
              (cadr-cli::export-session-jsonl session nil cwd))
        (setf records (read-export-jsonl written))
        (is (cl-ppcre:scan
             "^session-[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{3}Z\\.jsonl$"
             (file-namestring written)))
        (is (= 1 (length records)))
        (is (string= "session"
                     (cadr-ai::json-get (first records) "type")))
        (cadr-cli::export-session-jsonl
         session "trail.jsonl" cwd
         :trailing-entries
         (lambda (parent-id timestamp)
           (list
            (cadr-ai::json-object
             "type" "custom"
             "customType" "pi.share"
             "id" "deadbeef"
             "parentId" (or parent-id 'null)
             "timestamp" timestamp)))))
      (let ((records
              (read-export-jsonl
               (merge-pathnames "trail.jsonl" cwd))))
        (is (= 2 (length records)))
        (is (string= "pi.share"
                     (cadr-ai::json-get (second records) "customType")))
        (is (cadr-ai::json-null-p
             (cadr-ai::json-get (second records) "parentId")))
        (is (string= (cadr-ai::json-get (first records) "timestamp")
                     (cadr-ai::json-get (second records) "timestamp")))))))

(test jsonl-export-reports-a-write-failure
  ;; v1.4.0 handleExportCommand: Failed to export session: <message>
  (with-test-directory (root)
    (let* ((sessions (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "project/" root))
           (_ (ensure-directories-exist
               (merge-pathnames "blocked.jsonl/anchor" cwd)))
           (session
             (cadr-agent:create-session
              :directory sessions :cwd cwd :timestamp 0))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (cli-mock-model)
              :session session))
           (output (make-string-output-stream))
           (status nil))
      (declare (ignore _))
      (uiop:with-current-directory (cwd)
        (is (cadr-cli::handle-session-command
             "/export blocked.jsonl" agent
             :directory sessions :cwd cwd :output output
             :status-function
             (lambda (message &optional level)
               (setf status (list message level))))))
      (is (eq :error (second status)))
      (is (uiop:string-prefix-p
           "Failed to export session: "
           (first status)))
      (is (zerop (length (get-output-stream-string output)))))))

(defun jsonl-export-resolved-name (directory relative)
  ;; Node 22 path.posix.resolve. Drops ".", "..", and empty segments.
  ;; Does not call realpath, so a symlink component stays in the string.
  ;; Checked against node path.resolve on 2026-10-23: "./out.jsonl" and
  ;; "foo/./bar.jsonl" lose the dot segment.
  (let* ((base (string-right-trim "/" (namestring directory)))
         (absolute (and (plusp (length relative))
                        (char= #\/ (char relative 0))))
         (combined (if absolute
                       relative
                       (concatenate 'string base "/" relative)))
         (parts nil)
         (start 0))
    (loop for index from 0 to (length combined)
          do (when (or (= index (length combined))
                       (char= #\/ (char combined index)))
               (let ((segment (subseq combined start index)))
                 (cond
                   ((or (zerop (length segment))
                        (string= segment ".")))
                   ((string= segment "..")
                    (when parts (pop parts)))
                   (t (push segment parts))))
               (setf start (1+ index))))
    (if parts
        (with-output-to-string (out)
          (dolist (part (nreverse parts))
            (write-char #\/ out)
            (write-string part out)))
        "/")))

(test jsonl-export-relative-path-uses-the-process-directory
  ;; v1.4.0 exportSessionToJsonl calls resolvePath(outputPath,
  ;; process.cwd()). path.resolve does not follow symlinks. The
  ;; status line is that absolute path. The session directory passed
  ;; as cwd is not the base.
  (with-test-directory (root)
    (let* ((real (merge-pathnames "real/" root))
           (link (merge-pathnames "link" root))
           (launch (merge-pathnames "launch/" root))
           (session-dir (merge-pathnames "other-project/" root))
           (_ (progn
                (ensure-directories-exist
                 (merge-pathnames "anchor" real))
                (ensure-directories-exist
                 (merge-pathnames "anchor" launch))
                (ensure-directories-exist
                 (merge-pathnames "anchor" session-dir))
                (sb-posix:symlink
                 (string-right-trim
                  "/" (namestring (truename real)))
                 (namestring link))))
           (sessions (merge-pathnames "sessions/" root))
           (session
             (cadr-agent:create-session
              :directory sessions :cwd session-dir :timestamp 0))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (cli-mock-model)
              :session session))
           (output (make-string-output-stream))
           (status nil))
      (declare (ignore _))
      (cadr-agent:session-append-message
       session (cadr-ai:make-user-message :content "from-other"))
      (uiop:with-current-directory (launch)
        (is (cadr-cli::handle-session-command
             "/export out.jsonl" agent
             :directory sessions :cwd session-dir
             :output output
             :status-function
             (lambda (message &optional level)
               (setf status (list message level)))))
        (is (equal
             (list
              (format nil "Session exported to: ~A"
                      (jsonl-export-resolved-name
                       (uiop:getcwd) "out.jsonl"))
              nil)
             status))
        (is (probe-file (merge-pathnames "out.jsonl" launch)))
        (is (not (probe-file
                  (merge-pathnames "out.jsonl" session-dir))))
        (setf status nil)
        (is (cadr-cli::handle-session-command
             "/export ../link/out.jsonl" agent
             :directory sessions :cwd session-dir
             :output output
             :status-function
             (lambda (message &optional level)
               (setf status (list message level))))))
      (let ((expected
              (jsonl-export-resolved-name root "link/out.jsonl")))
        (is (equal (list (format nil "Session exported to: ~A"
                                 expected)
                         nil)
                   status))
        (is (probe-file expected))
        (is (probe-file (merge-pathnames "out.jsonl" real)))
        (is (not (search "/real/" (first status))))
        (is (not (probe-file
                  (merge-pathnames "out.jsonl" session-dir))))))))

(test jsonl-export-keeps-at-prefix-and-unicode-spaces
  ;; v1.4.0 resolvePath strips a leading @ and rewrites U+00A0,
  ;; U+2000-U+200A, U+202F, U+205F, and U+3000 only when
  ;; stripAtPrefix or normalizeUnicodeSpaces is true. Both default
  ;; to false, so /export @notes.jsonl keeps the @.
  ;; getPathCommandArgument uses search(/\s/). Node 22.22.0 splits an
  ;; unquoted argument on U+00A0, U+2000, U+200A, U+202F, U+205F, and
  ;; U+3000, so the piece does not end with ".jsonl" and /export writes
  ;; HTML whose status line is that piece. A quoted argument keeps the
  ;; space and, when it ends with ".jsonl", stays JSONL.
  (with-test-directory (root)
    (let* ((launch (merge-pathnames "launch/" root))
           (session-dir (merge-pathnames "other-project/" root))
           (_ (progn
                (ensure-directories-exist
                 (merge-pathnames "anchor" launch))
                (ensure-directories-exist
                 (merge-pathnames "anchor" session-dir))))
           (sessions (merge-pathnames "sessions/" root))
           (session
             (cadr-agent:create-session
              :directory sessions :cwd session-dir :timestamp 0))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (cli-mock-model)
              :session session))
           (output (make-string-output-stream))
           (status nil))
      (declare (ignore _))
      (uiop:with-current-directory (launch)
        (is (cadr-cli::handle-session-command
             "/export @notes.jsonl" agent
             :directory sessions :cwd session-dir
             :output output
             :status-function
             (lambda (message &optional level)
               (setf status (list message level)))))
        (is (equal
             (list
              (format nil "Session exported to: ~A"
                      (jsonl-export-resolved-name
                       (uiop:getcwd) "@notes.jsonl"))
              nil)
             status))
        (is (probe-file (merge-pathnames "@notes.jsonl" launch)))
        (is (not (probe-file
                  (merge-pathnames "notes.jsonl" launch))))
        (is (not (probe-file
                  (merge-pathnames "@notes.jsonl" session-dir))))
        (dolist (code '(#x09 #x0a #x0b #x0c #x0d #x20
                        #xa0 #x1680
                        #x2000 #x2001 #x2002 #x2003 #x2004
                        #x2005 #x2006 #x2007 #x2008 #x2009 #x200a
                        #x2028 #x2029 #x202f #x205f #x3000 #xfeff))
          (let* ((gap (code-char code))
                 (jsonl-name (format nil "a~Cb.jsonl" gap))
                 (html (merge-pathnames "a" launch))
                 (quoted (merge-pathnames jsonl-name launch)))
            (setf status nil)
            (is (cadr-cli::handle-session-command
                 (format nil "/export a~Cb.jsonl" gap)
                 agent
                 :directory sessions :cwd session-dir
                 :output output
                 :status-function
                 (lambda (message &optional level)
                   (setf status (list message level)))))
            (is (equal '("Session exported to: a" nil) status))
            (is (probe-file html))
            (is (not (probe-file quoted)))
            (with-open-file (stream html :external-format :utf-8)
              (is (char= #\< (peek-char t stream))))
            (delete-file html)
            (setf status nil)
            (is (cadr-cli::handle-session-command
                 (format nil "/export \"a~Cb.jsonl\"" gap)
                 agent
                 :directory sessions :cwd session-dir
                 :output output
                 :status-function
                 (lambda (message &optional level)
                   (setf status (list message level)))))
            (is (equal
                 (list
                  (format nil "Session exported to: ~A"
                          (jsonl-export-resolved-name
                           (uiop:getcwd) jsonl-name))
                  nil)
                 status))
            (is (probe-file quoted))
            (unless (= code #x20)
              (is (not (probe-file
                        (merge-pathnames "a b.jsonl" launch)))))
            (delete-file quoted)))))))

(test jsonl-export-drops-dot-segments
  ;; Node 22.22.0 path.resolve("./out.jsonl") and
  ;; path.resolve("foo/./bar.jsonl") drop the "." segment. The status
  ;; line is that absolute path. "foo/../baz.jsonl" drops the parent
  ;; segment the same way. Symlinks are still not followed.
  (with-test-directory (root)
    (let* ((launch (merge-pathnames "launch/" root))
           (session-dir (merge-pathnames "other-project/" root))
           (_ (progn
                (ensure-directories-exist
                 (merge-pathnames "anchor" launch))
                (ensure-directories-exist
                 (merge-pathnames "anchor" session-dir))))
           (sessions (merge-pathnames "sessions/" root))
           (session
             (cadr-agent:create-session
              :directory sessions :cwd session-dir :timestamp 0))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (cli-mock-model)
              :session session))
           (output (make-string-output-stream))
           (status nil))
      (declare (ignore _))
      (uiop:with-current-directory (launch)
        (is (string=
             (concatenate
              'string
              (string-right-trim "/" (namestring (uiop:getcwd)))
              "/out.jsonl")
             (jsonl-export-resolved-name (uiop:getcwd) "./out.jsonl")))
        (is (string=
             (concatenate
              'string
              (string-right-trim "/" (namestring (uiop:getcwd)))
              "/foo/bar.jsonl")
             (jsonl-export-resolved-name
              (uiop:getcwd) "foo/./bar.jsonl")))
        (dolist (relative '("./out.jsonl" "foo/./bar.jsonl"
                            "foo/../baz.jsonl"))
          (setf status nil)
          (is (cadr-cli::handle-session-command
               (format nil "/export ~A" relative)
               agent
               :directory sessions :cwd session-dir
               :output output
               :status-function
               (lambda (message &optional level)
                 (setf status (list message level)))))
          (is (equal
               (list
                (format nil "Session exported to: ~A"
                        (jsonl-export-resolved-name
                         (uiop:getcwd) relative))
                nil)
               status))
          (is (not (search "/./" (first status))))
          (is (not (search "/../" (first status))))
          (is (probe-file
               (jsonl-export-resolved-name (uiop:getcwd) relative))))))))

(test jsonl-export-resolve-path-matches-v140
  ;; v1.4.0 paths.test.ts resolvePath, which exportSessionToJsonl calls.
  ;; Node 22.22.0: ~/ joins and collapses, ~draft stays a relative name,
  ;; fileURLToPath collapses "." and decodes %20, a bad percent throws
  ;; "URI malformed", and a native absolute path keeps a literal %20.
  ;; HTML uses normalizePath. path.join collapses ~/foo/./bar.html to
  ;; <home>/foo/bar.html. writeFileSync does not create foo/. Node
  ;; 22.22.0 reports ENOENT with that absolute path. Once foo/ exists,
  ;; the status line is the collapsed path and the file is written there.
  (with-test-directory (root)
    (let* ((launch (merge-pathnames "launch/" root))
           (session-dir (merge-pathnames "other-project/" root))
           (_ (progn
                (ensure-directories-exist
                 (merge-pathnames "anchor" launch))
                (ensure-directories-exist
                 (merge-pathnames "anchor" session-dir))))
           (sessions (merge-pathnames "sessions/" root))
           (session
             (cadr-agent:create-session
              :directory sessions :cwd session-dir :timestamp 0))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (cli-mock-model)
              :session session))
           (output (make-string-output-stream))
           (home (user-homedir-pathname))
           (home-jsonl
             (merge-pathnames "cadr-g27g-tilde.jsonl" home))
           (status nil))
      (declare (ignore _))
      (uiop:with-current-directory (launch)
        (unwind-protect
             (progn
               (setf status nil)
               (is (cadr-cli::handle-session-command
                    "/export ~/cadr-g27g-tilde.jsonl" agent
                    :directory sessions :cwd session-dir
                    :output output
                    :status-function
                    (lambda (message &optional level)
                      (setf status (list message level)))))
               (is (equal
                    (list
                     (format nil "Session exported to: ~A"
                             (jsonl-export-resolved-name
                              home "cadr-g27g-tilde.jsonl"))
                     nil)
                    status))
               (is (probe-file home-jsonl))
               (setf status nil)
               (is (cadr-cli::handle-session-command
                    "/export ~draft.jsonl" agent
                    :directory sessions :cwd session-dir
                    :output output
                    :status-function
                    (lambda (message &optional level)
                      (setf status (list message level)))))
               (is (equal
                    (list
                     (format nil "Session exported to: ~A"
                             (jsonl-export-resolved-name
                              (uiop:getcwd) "~draft.jsonl"))
                     nil)
                    status))
               (is (probe-file (merge-pathnames "~draft.jsonl" launch)))
               (is (not (probe-file
                         (merge-pathnames "~draft.jsonl" home))))
               (let* ((base
                        (string-right-trim
                         "/" (namestring launch)))
                      (url
                        (format nil "file://~A/dir/./a%20b.jsonl" base))
                      (written
                        (jsonl-export-resolved-name
                         launch "dir/a b.jsonl")))
                 (setf status nil)
                 (is (cadr-cli::handle-session-command
                      (format nil "/export ~A" url) agent
                      :directory sessions :cwd session-dir
                      :output output
                      :status-function
                      (lambda (message &optional level)
                        (setf status (list message level)))))
                 (is (equal
                      (list
                       (format nil "Session exported to: ~A" written)
                       nil)
                      status))
                 (is (probe-file written)))
               (let* ((base
                        (string-right-trim
                         "/" (namestring launch)))
                      (literal
                        (format nil "~A/report%2026.jsonl" base)))
                 (setf status nil)
                 (is (cadr-cli::handle-session-command
                      (format nil "/export ~A" literal) agent
                      :directory sessions :cwd session-dir
                      :output output
                      :status-function
                      (lambda (message &optional level)
                        (setf status (list message level)))))
                 (is (equal
                      (list
                       (format nil "Session exported to: ~A" literal)
                       nil)
                      status))
                 (is (search "report%2026.jsonl" (first status)))
                 (is (not (search "report 2026.jsonl" (first status))))
                 (is (probe-file literal)))
               (setf status nil)
               (is (cadr-cli::handle-session-command
                    "/export file:///%E0%A4%A.jsonl" agent
                    :directory sessions :cwd session-dir
                    :output output
                    :status-function
                    (lambda (message &optional level)
                      (setf status (list message level)))))
               (is (equal
                    '("Failed to export session: URI malformed" :error)
                    status))
               (let ((html
                       (jsonl-export-resolved-name
                        home "foo/bar.html")))
                 (setf status nil)
                 (is (cadr-cli::handle-session-command
                      "/export ~/foo/./bar.html" agent
                      :directory sessions :cwd session-dir
                      :output output
                      :status-function
                      (lambda (message &optional level)
                        (setf status (list message level)))))
                 (is (equal
                      (list
                       (format nil
                               "Failed to export session: ENOENT: no such file or directory, open '~A'"
                               html)
                       :error)
                      status))
                 (is (not (probe-file html)))
                 (is (not (probe-file
                           (merge-pathnames "foo/" home))))
                 (ensure-directories-exist
                  (merge-pathnames "foo/anchor" home))
                 (setf status nil)
                 (is (cadr-cli::handle-session-command
                      "/export ~/foo/./bar.html" agent
                      :directory sessions :cwd session-dir
                      :output output
                      :status-function
                      (lambda (message &optional level)
                        (setf status (list message level)))))
                 (is (equal
                      (list
                       (format nil "Session exported to: ~A" html)
                       nil)
                      status))
                 (is (probe-file html))
                 (delete-file html)))
          (when (probe-file home-jsonl)
            (delete-file home-jsonl)))))))

(test path-command-argument-matches-v140-get-path-command-argument
  ;; v1.4.0 interactive-mode-import-command.test.ts, plus the
  ;; getPathCommandArgument whitespace rules /export shares.
  (is (string= "path/to/session.jsonl"
               (cadr-cli::path-command-argument
                "/import \"path/to/session.jsonl\"" "/import")))
  (is (string= "path with spaces/session.jsonl"
               (cadr-cli::path-command-argument
                "/import \"path with spaces/session.jsonl\"" "/import")))
  (is (string= "john's/session.jsonl"
               (cadr-cli::path-command-argument
                "/import john's/session.jsonl" "/import")))
  (is (null (cadr-cli::path-command-argument
             "/important /tmp/session.jsonl" "/import")))
  (is (null (cadr-cli::path-command-argument
             "/exporter out.html" "/export")))
  (is (string= "/tmp/session.jsonl"
               (cadr-cli::path-command-argument
                "/import /tmp/session.jsonl" "/import")))
  (is (null (cadr-cli::path-command-argument
             (format nil "/export~Cout.jsonl" #\Tab) "/export")))
  (is (string= "notes.jsonl"
               (cadr-cli::path-command-argument
                (format nil "/export ~Cnotes.jsonl" (code-char #xa0))
                "/export"))))
