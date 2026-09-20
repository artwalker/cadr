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

(test crash-log-round-trips-take-and-trim
  (with-test-directory (root)
    (let* ((agent-dir (merge-pathnames "agent/" root))
           (path (merge-pathnames "crashes.json" agent-dir)))
      (ensure-directories-exist agent-dir)
      (let ((record
              (cadr-cli::record-crash
               :kind :fatal-error
               :message "boom from test"
               :cwd root
               :path path)))
        (is (string= "boom from test" (getf record :message)))
        (is (eq :fatal-error (getf record :kind)))
        (is (probe-file path))
        (let ((taken (cadr-cli::take-unnotified-crash path)))
          (is (string= "boom from test" (getf taken :message)))
          (is (search "Run /bug to report it"
                      (cadr-cli::crash-announcement-text taken)))
          (is (search (cadr-ai::cadr-product-display-name)
                      (cadr-cli::crash-announcement-text taken))))
        (is (null (cadr-cli::take-unnotified-crash path)))
        (let ((diag (cadr-cli::crash-log-for-diagnostics path)))
          (is (= 1 (length diag)))
          (is (hash-table-p (first diag)))
          (is (null (gethash "notified" (first diag))))
          (is (string= "boom from test"
                       (gethash "message" (first diag)))))
        (cadr-cli::clear-crash-log path)
        (is (null (probe-file path))))
      (dotimes (index 7)
        (cadr-cli::record-crash
         :kind :uncaught-exception
         :message (format nil "crash-~D" index)
         :cwd root
         :path path))
      (let ((records (cadr-cli::read-crash-log path)))
        (is (= 5 (length records)))
        (is (string= "crash-2" (getf (first records) :message)))
        (is (string= "crash-6"
                     (getf (car (last records)) :message)))))))

(test bug-command-attaches-crashes-without-notified
  (with-test-directory (root)
    (uiop:with-current-directory (root)
      (let* ((agent-dir (merge-pathnames "agent/" root))
             (crash-path (merge-pathnames "crashes.json" agent-dir))
             (sessions (merge-pathnames "sessions/" root))
             (cwd (merge-pathnames "cwd/" root))
             (agent-dir-native (uiop:native-namestring agent-dir)))
        (let ((cadr-core::*path-environment-function*
                (lambda (name)
                  (and (string= name "CADR_CODING_AGENT_DIR")
                       agent-dir-native))))
          (ensure-directories-exist agent-dir)
          (ensure-directories-exist sessions)
          (ensure-directories-exist cwd)
          (cadr-cli::record-crash
           :kind :fatal-error
           :message "attached crash"
           :cwd cwd
           :path crash-path)
          (let* ((session
                   (cadr-agent:create-session
                    :directory sessions
                    :cwd cwd
                    :id "bug-crash"
                    :timestamp 1))
                 (agent
                   (cadr-agent:make-agent
                    :session session
                    :provider nil
                    :model nil))
                 (out (make-string-output-stream)))
            (is (eq t
                    (cadr-cli::handle-session-command
                     "/bug attach crashes" agent
                     :directory sessions
                     :cwd cwd
                     :output out)))
            (let* ((text (get-output-stream-string out))
                   (marker "Bug report written: ")
                   (zip-start (search marker text))
                   (zip-path
                     (and zip-start
                          (string-trim
                           '(#\Space #\Tab #\Newline #\Return)
                           (subseq text
                                   (+ zip-start (length marker))))))
                   (extracted (merge-pathnames "unzipped/" root)))
              (is (and zip-path (probe-file zip-path)))
              (ensure-directories-exist extracted)
              (uiop:run-program
               (list "unzip" "-o" "-q"
                     (uiop:native-namestring zip-path)
                     "-d" (uiop:native-namestring extracted)))
              (let* ((diag-path
                       (merge-pathnames "diagnostics.json" extracted))
                     (parsed
                       (cadr-ai::parse-json
                        (uiop:read-file-string diag-path)))
                     (crashes (cadr-ai::json-get parsed "crashes")))
                (is (and (vectorp crashes) (= 1 (length crashes))))
                (let ((crash (aref crashes 0)))
                  (is (string= "attached crash"
                               (cadr-ai::json-get crash "message")))
                  (is (not (cadr-ai::json-present-p crash "notified"))))
                (is (null (probe-file crash-path)))))))))))
