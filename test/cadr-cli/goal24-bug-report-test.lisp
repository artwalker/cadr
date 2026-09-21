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
                         (search "Bug report written: " text)))
                   (and start
                        (string-trim
                         '(#\Space #\Tab #\Newline #\Return)
                         (subseq text
                                 (+ start
                                    (length
                                     "Bug report written: "))))))))
          (is (search "Bug report written: " text))
          (is (and path (probe-file path)))
          (when path
            (is (uiop:string-suffix-p path ".zip"))
            (uiop:run-program
             (list "unzip" "-l" (uiop:native-namestring path))
             :output :string)
            (is (search "report.json"
                        (uiop:run-program
                         (list "unzip" "-l"
                               (uiop:native-namestring path))
                         :output :string)))
            (is (search "diagnostics.json"
                        (uiop:run-program
                         (list "unzip" "-l"
                               (uiop:native-namestring path))
                         :output :string)))))))))

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
               (start (search "Bug report written: " text))
               (path
                 (and start
                      (string-trim
                       '(#\Space #\Tab #\Newline #\Return)
                       (subseq text
                               (+ start
                                  (length
                                   "Bug report written: "))))))
               (report
                 (cadr-ai::parse-json
                  (uiop:run-program
                   (list "unzip" "-p"
                         (uiop:native-namestring path)
                         "report.json")
                   :output :string)))
               (hint (cadr-ai::json-get report "hint")))
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
              (cadr-cli::tui-state-bug-report-hint-shown-p state))))))
