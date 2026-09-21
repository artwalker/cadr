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
