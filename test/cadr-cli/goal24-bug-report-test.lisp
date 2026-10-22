(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test bug-report-redacts-urls-and-secret-keys
  (is (string=
       "https://example.com/path"
       (cadr-cli::bug-report-redact-url
        "https://user:secret@example.com/path")))
  (is (string=
       "https://example.com?api_key=<redacted>&ok=1"
       (cadr-cli::bug-report-redact-url
        "https://example.com?api_key=hunter2&ok=1")))
  (let ((redacted
          (cadr-cli::bug-report-redact-json-value
           (list :token "secret"
                 :url "https://x:y@host/z"
                 :ok "fine"))))
    (is (string= "<redacted>" (getf redacted :token)))
    (is (string= "https://host/z" (getf redacted :url)))
    (is (string= "fine" (getf redacted :ok)))))

(test bug-report-slash-command-is-registered
  (let ((names
          (mapcar
           #'first
           cadr-cli::+tui-autocomplete-command-specifications+)))
    (is (find "bug" names :test #'string=)))
  (is (string=
       "cadr-bug-report-abc.zip"
       (cadr-cli::bug-report-archive-file-name "abc"))))

(test bug-command-writes-a-zip-archive
  (with-test-directory (root)
    (uiop:with-current-directory (root)
      (let* ((sessions (merge-pathnames "sessions/" root))
             (cwd (merge-pathnames "cwd/" root))
             (_
               (progn
                 (ensure-directories-exist sessions)
                 (ensure-directories-exist cwd)))
             (session
               (cadr-agent:create-session
                :directory sessions
                :cwd cwd
                :id "bug"
                :timestamp 1))
             (agent
               (cadr-agent:make-agent
                :session session
                :provider nil
                :model nil))
             (out (make-string-output-stream)))
        (declare (ignore _))
        (is (eq t
                (cadr-cli::handle-session-command
                 "/bug crashed on save" agent
                 :directory sessions
                 :cwd cwd
                 :output out)))
        (let* ((text (get-output-stream-string out))
               (path
                 (let ((start
                         (search "Bug report exported to: " text)))
                   (and start
                        (let* ((rest
                                 (subseq text
                                         (+ start
                                            (length
                                             "Bug report exported to: "))))
                               (end
                                 (or (position #\Newline rest)
                                     (length rest))))
                          (string-trim
                           '(#\Space #\Tab #\Newline #\Return)
                           (subseq rest 0 end)))))))
          (is (search "Bug report exported to: " text))
          (is (search "Report ID: " text))
          (is (and path (probe-file path)))
          (when path
            (is (uiop:string-suffix-p path ".zip"))
            (let ((listing
                    (uiop:run-program
                     (list "unzip" "-l"
                           (uiop:native-namestring path))
                     :output :string)))
              (is (search "report.json" listing))
              (is (search "diagnostics.json" listing)))))))))

(test bug-report-files-include-session-jsonl-when-provided
  (let* ((bundle
           (list
            :metadata
            (list :schema-version 1 :id "bundle-1")
            :diagnostics
            (list :schema-version 1 :session-id "s1"
                  :entry-count 0 :assistant-message-count 0
                  :assistant nil :crashes nil)
            :session-jsonl
            (format nil "{\"type\":\"session\",\"id\":\"s1\"}~%")
            :summary nil))
         (files (cadr-cli::bug-report-files bundle))
         (names (mapcar (lambda (file) (getf file :name)) files)))
    (is (equal '("report.json" "diagnostics.json" "session.jsonl")
               names))
    (is (search "\"type\":\"session\""
                (getf (third files) :data)))))

(test upload-bug-report-posts-multipart-and-returns-id
  (let* ((seen nil)
         (bundle
           (list
            :metadata
            (list :schema-version 1 :id "local-id"
                  :hint "boom"
                  :session (list :included nil
                                 :summary-included nil))
            :diagnostics
            (list :schema-version 1 :session-id "s"
                  :entry-count 0 :assistant-message-count 0
                  :assistant nil :crashes nil)
            :session-jsonl nil
            :summary nil))
         (result
           (cadr-cli::upload-bug-report
            bundle
            :token "radius-token"
            :gateway-url "https://radius.invalid"
            :http
            (lambda (request)
              (setf seen request)
              (let ((report (make-hash-table :test #'equal))
                    (table (make-hash-table :test #'equal)))
                (setf (gethash "id" report) "remote-bug-42")
                (setf (gethash "ok" table) t)
                (setf (gethash "bug_report" table) report)
                table)))))
    (is (string= "remote-bug-42" (getf result :id)))
    (is (search "/v1/bug-reports"
                (cadr-ai::request-spec-url seen)))
    (is (equal "Bearer radius-token"
               (cdr (assoc "Authorization"
                           (cadr-ai::request-spec-headers seen)
                           :test #'string=))))
    (let* ((content-type
             (cdr (assoc "Content-Type"
                         (cadr-ai::request-spec-headers seen)
                         :test #'string=)))
           (body (cadr-ai::request-spec-raw-body seen))
           (text
             (sb-ext:octets-to-string
              body :external-format :utf-8)))
      (is (search "multipart/form-data; boundary=" content-type))
      (is (search "name=\"report.json\"" text))
      (is (search "name=\"diagnostics.json\"" text))
      (is (search "\"hint\":\"boom\"" text)))))

(test prompt-bug-report-cancel-returns-cancelled-status
  (with-test-directory (root)
    (uiop:with-current-directory (root)
      (let* ((sessions (merge-pathnames "sessions/" root))
             (cwd (merge-pathnames "cwd/" root))
             (_
               (progn
                 (ensure-directories-exist sessions)
                 (ensure-directories-exist cwd)))
             (session
               (cadr-agent:create-session
                :directory sessions
                :cwd cwd
                :id "bug-cancel"
                :timestamp 1))
             (agent
               (cadr-agent:make-agent
                :session session
                :provider nil
                :model nil))
             (out (make-string-output-stream))
             (ui
               (lambda (method arguments)
                 (declare (ignore arguments))
                 (ecase method
                   (:input nil)
                   (:select nil)))))
        (declare (ignore _))
        (is (eq t
                (cadr-cli::run-bug-report
                 agent
                 :initial-hint "never mind"
                 :ui-function ui
                 :output out)))
        (is (search "Bug report cancelled"
                    (get-output-stream-string out)))
        (is (null
             (directory
              (merge-pathnames "cadr-bug-report-*.zip"
                               root))))))))

(defun bug-summary-condition-text (function)
  (handler-case
      (progn (funcall function) nil)
    (error (condition)
      (princ-to-string condition))))

(defun bug-summary-user-message (text)
  (cadr-ai:make-user-message :content text))

(defun bug-summary-agent
    (response &key (context-window 128000) (max-tokens 4096)
               (name "Summary Model") messages abort-p
               (reasoning-p nil) seen)
  (cadr-agent:make-agent
   :model
   (cadr-ai:make-model
    :id "summary-model"
    :name name
    :provider :test
    :api :openai-completions
    :max-tokens max-tokens
    :context-window context-window
    :reasoning-p reasoning-p)
   :messages messages
   :abort-p abort-p
   :auto-retry-p nil
   :stream-function
   (lambda (provider model context callback
            &key max-tokens cache-retention session-id abort-p
              reasoning
            &allow-other-keys)
     (declare (ignore provider model callback abort-p))
     (when seen
       (setf (gethash :context seen) context
             (gethash :max-tokens seen) max-tokens
             (gethash :cache-retention seen) cache-retention
             (gethash :session-id seen) session-id
             (gethash :reasoning seen) reasoning))
     response)))

(test bug-report-select-messages-keeps-newest-within-budget
  (let* ((messages
           (mapcar #'bug-summary-user-message
                   '("aaaa" "bbbb" "cccc" "dddd")))
         (selected
           (cadr-cli::bug-report-select-messages messages 2)))
    (is (equal '("cccc" "dddd")
               (mapcar #'cadr-ai:user-message-content selected)))))

(test bug-report-summary-returns-markdown-and-baseline-prompt
  (let* ((seen (make-hash-table))
         (messages
           (mapcar #'bug-summary-user-message
                   '("aaaa" "bbbb" "cccc" "dddd" "eeee" "ffff")))
         (agent
           (bug-summary-agent
            (cadr-ai:make-assistant-message
             :content
             (list
              (cadr-ai:make-text-content
               :text
               (format nil "  ## What the user was doing~%Saved.~%")))
             :stop-reason :stop)
            :context-window 8
            :max-tokens 100
            :reasoning-p t
            :messages messages
            :seen seen))
         (text
           (progn
             (setf (cadr-agent::agent-thinking-level agent) :high)
             (cadr-cli::generate-bug-report-summary
              agent messages :hint "  save crashed  "))))
    (is (eq :high (gethash :reasoning seen)))
    (is (string=
         (format nil "## What the user was doing~%Saved.")
         text))
    (is (eql 100 (gethash :max-tokens seen)))
    (is (eq :none (gethash :cache-retention seen)))
    (is (and (stringp (gethash :session-id seen))
             (plusp (length (gethash :session-id seen)))))
    (let* ((context (gethash :context seen))
           (prompt
             (cadr-ai:user-message-content
              (first (cadr-ai:context-messages context)))))
      (is (string=
           "You are helping a user file a bug report about cadr, the coding agent they are talking to. You will be shown the conversation transcript. Write a report for the cadr developers describing what the user was doing and what went wrong.

Do NOT continue the conversation. Do NOT respond to any questions in the conversation. ONLY output the report."
           (cadr-ai:context-system-prompt context)))
      (is (search
           "Note: only the last 4 of 6 messages are shown."
           prompt))
      (is (search
           (format nil "<user-report>~%save crashed~%</user-report>")
           prompt))
      (is (search "[User]: cccc" prompt))
      (is (not (search "[User]: aaaa" prompt)))
      (is (search "## What the user was doing" prompt))
      (is (search "## What went wrong" prompt))
      (is (search "## Steps to reproduce" prompt))
      (is (search "## Relevant details" prompt))
      (is (search
           "Do not include file contents, secrets, or credentials"
           prompt)))))

(test bug-report-summary-default-window-keeps-short-transcript
  (let* ((seen (make-hash-table))
         (messages
           (mapcar #'bug-summary-user-message '("aaaa" "bbbb")))
         (agent
           (bug-summary-agent
            (cadr-ai:make-assistant-message
             :content
             (list (cadr-ai:make-text-content :text "kept"))
             :stop-reason :stop)
            :context-window 0
            :messages messages
            :seen seen)))
    (is (string=
         "kept"
         (cadr-cli::generate-bug-report-summary agent messages)))
    (is (not
         (search
          "messages are shown."
          (cadr-ai:user-message-content
           (first
            (cadr-ai:context-messages
             (gethash :context seen)))))))))

(test bug-report-summary-rejects-empty-tool-call-abort-and-error
  (let ((messages (list (bug-summary-user-message "aaaa"))))
    (is (string=
         "Bug report summary was empty"
         (bug-summary-condition-text
          (lambda ()
            (cadr-cli::generate-bug-report-summary
             (bug-summary-agent
              (cadr-ai:make-assistant-message
               :content
               (list
                (cadr-ai:make-text-content
                 :text (format nil "  ~%")))
               :stop-reason :stop))
             messages)))))
    (is (string=
         "Bug report summary attempted to call a tool"
         (bug-summary-condition-text
          (lambda ()
            (cadr-cli::generate-bug-report-summary
             (bug-summary-agent
              (cadr-ai:make-assistant-message
               :content
               (list (cadr-ai:make-tool-call :id "call-1" :name "bash"))
               :stop-reason :stop))
             messages)))))
    (is (string=
         "Bug report summary was cancelled"
         (bug-summary-condition-text
          (lambda ()
            (cadr-cli::generate-bug-report-summary
             (bug-summary-agent
              (cadr-ai:make-assistant-message
               :content nil
               :stop-reason :aborted))
             messages)))))
    (is (string=
         "Bug report summary failed: provider exploded"
         (bug-summary-condition-text
          (lambda ()
            (cadr-cli::generate-bug-report-summary
             (bug-summary-agent
              (cadr-ai:make-assistant-message
               :content nil
               :stop-reason :error
               :error-message "provider exploded"))
             messages)))))))

(test bug-report-with-summary-writes-summary-md
  (with-test-directory (root)
    (uiop:with-current-directory (root)
      (let* ((sessions (merge-pathnames "sessions/" root))
             (cwd (merge-pathnames "cwd/" root))
             (_
               (progn
                 (ensure-directories-exist sessions)
                 (ensure-directories-exist cwd)))
             (session
               (cadr-agent:create-session
                :directory sessions
                :cwd cwd
                :id "bug-summary"
                :timestamp 1))
             (markdown "The save button crashed.")
             (agent
               (bug-summary-agent
                (cadr-ai:make-assistant-message
                 :content
                 (list (cadr-ai:make-text-content :text markdown))
                 :stop-reason :stop)
                :name "Summary Model"
                :messages
                (list (bug-summary-user-message "save crashed"))))
             (out (make-string-output-stream))
             (step 0)
             (ui
               (lambda (method arguments)
                 (declare (ignore arguments))
                 (ecase method
                   (:input "save crashed")
                   (:select
                    (incf step)
                    (case step
                      (1 "No")
                      (2 "Yes, generate a summary")
                      (3 "Export as Zip")))))))
        (declare (ignore _))
        (setf (cadr-agent:agent-session agent) session)
        (is (eq t
                (cadr-cli::run-bug-report
                 agent
                 :initial-hint "save crashed"
                 :ui-function ui
                 :output out)))
        (let* ((text (get-output-stream-string out))
               (path
                 (let ((start
                         (search "Bug report exported to: " text)))
                   (and start
                        (let* ((rest
                                 (subseq
                                  text
                                  (+ start
                                     (length
                                      "Bug report exported to: "))))
                               (end
                                 (or (position #\Newline rest)
                                     (length rest))))
                          (string-trim
                           '(#\Space #\Tab #\Newline #\Return)
                           (subseq rest 0 end)))))))
          (is (search "Writing summary with Summary Model..." text))
          (is (not (search "not available yet" text)))
          (is (and path (probe-file path)))
          (when path
            (let ((summary
                    (uiop:run-program
                     (list "unzip" "-p"
                           (uiop:native-namestring path)
                           "summary.md")
                     :output :string)))
              (is (search "The save button crashed." summary)))))))))

(test bug-report-summary-failure-and-abort-skip-the-archive
  (with-test-directory (root)
    (uiop:with-current-directory (root)
      (let* ((sessions (merge-pathnames "sessions/" root))
             (cwd (merge-pathnames "cwd/" root))
             (_
               (progn
                 (ensure-directories-exist sessions)
                 (ensure-directories-exist cwd)))
             (session
               (cadr-agent:create-session
                :directory sessions
                :cwd cwd
                :id "bug-summary-fail"
                :timestamp 1))
             (agent
               (bug-summary-agent
                (cadr-ai:make-assistant-message
                 :content nil
                 :stop-reason :error
                 :error-message "provider exploded")))
             (out (make-string-output-stream))
             (step 0)
             (ui
               (lambda (method arguments)
                 (declare (ignore arguments))
                 (ecase method
                   (:input "save crashed")
                   (:select
                    (incf step)
                    (case step
                      (1 "No")
                      (2 "Yes, generate a summary")
                      (3 "Export as Zip")))))))
        (declare (ignore _))
        (setf (cadr-agent:agent-session agent) session)
        (is (eq t
                (cadr-cli::run-bug-report
                 agent
                 :ui-function ui
                 :output out)))
        (is (search
             "Failed to write bug report summary: Bug report summary failed: provider exploded"
             (get-output-stream-string out)))
        (is (null
             (directory
              (merge-pathnames "cadr-bug-report-*.zip" root)))))
      (let* ((session
               (cadr-agent:create-session
                :directory (merge-pathnames "sessions/" root)
                :cwd (merge-pathnames "cwd/" root)
                :id "bug-summary-abort"
                :timestamp 2))
             (agent
               (bug-summary-agent
                (cadr-ai:make-assistant-message
                 :content
                 (list (cadr-ai:make-text-content :text "should not run"))
                 :stop-reason :stop)))
             (out (make-string-output-stream))
             (step 0)
             (ui
               (lambda (method arguments)
                 (declare (ignore arguments))
                 (ecase method
                   (:input "save crashed")
                   (:select
                    (incf step)
                    (case step
                      (1 "No")
                      (2 "Yes, generate a summary")
                      (3 "Export as Zip"))))))
             (text nil))
        (setf (cadr-agent:agent-session agent) session)
        (is (eq t
                (cadr-cli::run-bug-report
                 agent
                 :ui-function ui
                 :output out
                 :abort-p (lambda () t))))
        (setf text (get-output-stream-string out))
        (is (search "Bug report cancelled" text))
        (is (not (search "Failed to write bug report summary" text)))
        (is (null
             (directory
              (merge-pathnames "cadr-bug-report-*.zip" root))))))))

(test crash-log-round-trips-and-announces
  (with-test-directory (root)
    (let* ((agent-dir (merge-pathnames "agent/" root))
           (path (merge-pathnames "crashes.json" agent-dir)))
      (ensure-directories-exist agent-dir)
      (let ((record
              (cadr-cli::record-crash
               :kind "fatal_error"
               :message "boom from test"
               :cwd root
               :path path)))
        (is (string= "boom from test" (getf record :message)))
        (is (probe-file path))
        (let ((taken
                (cadr-cli::take-unnotified-crash path)))
          (is (string= "boom from test" (getf taken :message)))
          (is (search
               "Run /bug to report it"
               (cadr-cli::crash-announcement-text taken))))
        (is (null (cadr-cli::take-unnotified-crash path)))
        (let ((diag (cadr-cli::crash-log-for-diagnostics path)))
          (is (= 1 (length diag)))
          (is (null (getf (first diag) :notified))))
        (cadr-cli::clear-crash-log path)
        (is (null (probe-file path)))))))

(test bug-report-payload-keeps-multiline-diagnostics
  (with-test-directory (root)
    (uiop:with-current-directory (root)
      (let* ((sessions (merge-pathnames "sessions/" root))
             (cwd (merge-pathnames "cwd/" root))
             (_
               (progn
                 (ensure-directories-exist sessions)
                 (ensure-directories-exist cwd)))
             (session
               (cadr-agent:create-session
                :directory sessions
                :cwd cwd
                :id "bug-lines"
                :timestamp 1))
             (agent
               (cadr-agent:make-agent
                :session session
                :provider nil
                :model nil))
             (diagnostic
               (format nil
                       "Request failed~C~%  ↳ pi exiting...~C~%stack trace"
                       #\Return #\Return))
             (expected
               "Request failed
  ↳ pi exiting...
stack trace")
             (out (make-string-output-stream)))
        (declare (ignore _))
        (is (eq t
                (cadr-cli::handle-session-command
                 (format nil "/bug ~A" diagnostic)
                 agent
                 :directory sessions
                 :cwd cwd
                 :output out)))
        (let* ((text (get-output-stream-string out))
               (start (search "Bug report exported to: " text))
               (path
                 (and start
                      (let* ((rest
                               (subseq text
                                       (+ start
                                          (length
                                           "Bug report exported to: "))))
                             (end
                               (or (position #\Newline rest)
                                   (length rest))))
                        (string-trim
                         '(#\Space #\Tab #\Newline #\Return)
                         (subseq rest 0 end)))))
               (report
                 (and path
                      (cadr-ai::parse-json
                       (uiop:run-program
                        (list "unzip" "-p"
                              (uiop:native-namestring path)
                              "report.json")
                        :output :string))))
               (hint (and report (cadr-ai::json-get report "hint"))))
          (is (and path (probe-file path)))
          (is (string= expected hint)))))))

(test bug-report-hint-skips-cancel-and-retryable-failures
  (labels ((message (text &optional (reason :error))
             (cadr-ai:make-assistant-message
              :api :faux
              :provider :faux
              :model "faux-1"
              :stop-reason reason
              :error-message text)))
    (dolist (text '("This operation was aborted"
                    "Request cancelled"
                    "503 Service Unavailable"))
      (is (null
           (cadr-cli::bug-report-hint (message text)))))
    (is (null
         (cadr-cli::bug-report-hint
          (message nil :aborted))))
    (let ((hint
            (cadr-cli::bug-report-hint
             (message "Unexpected internal state"))))
      (is (and (stringp hint) (search "/bug" hint))))))

(test bug-report-hint-shows-once-on-message-end
  (labels ((message (text)
             (cadr-ai:make-assistant-message
              :api :faux
              :provider :faux
              :model "faux-1"
              :stop-reason :error
              :error-message text))
           (end (state text)
             (cadr-cli::tui-handle-agent-event
              state
              (cadr-agent::make-agent-event
               :type :message-end
               :message (message text))))
           (turn (state text)
             (let ((msg (message text)))
               (cadr-cli::tui-handle-agent-event
                state
                (cadr-agent::make-agent-event
                 :type :message-start
                 :message msg))
               (cadr-cli::tui-handle-agent-event
                state
                (cadr-agent::make-agent-event
                 :type :message-end
                 :message msg))))
           (bug-notices (state)
             (remove-if-not
              (lambda (entry)
                (and (eq :notice
                         (cadr-cli::tui-entry-type entry))
                     (search "/bug"
                             (cadr-cli::tui-entry-text entry))))
              (cadr-cli::tui-state-entries state))))
    (let ((state (cadr-cli::make-tui-state)))
      (end state "Unexpected internal state")
      (is (null (bug-notices state)))
      (is (null
           (cadr-cli::tui-state-bug-report-hint-shown-p state))))
    (let ((state (cadr-cli::make-tui-state)))
      (turn state "Unexpected internal state")
      (is (= 1 (length (bug-notices state))))
      (is (eq t
              (cadr-cli::tui-state-bug-report-hint-shown-p state)))
      (turn state "Unexpected internal state")
      (is (= 1 (length (bug-notices state)))))
    (dolist (text '("Request cancelled"
                    "503 Service Unavailable"))
      (let ((state (cadr-cli::make-tui-state)))
        (turn state text)
        (is (null (bug-notices state)))
        (is (null
             (cadr-cli::tui-state-bug-report-hint-shown-p state)))))
    (let ((state (cadr-cli::make-tui-state)))
      (turn state "Request cancelled")
      (turn state "Unexpected internal state")
      (is (= 1 (length (bug-notices state))))
      (is (eq t
              (cadr-cli::tui-state-bug-report-hint-shown-p
               state))))))
