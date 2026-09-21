(in-package #:cadr-cli)

(defparameter +bug-report-custom-entry-type+ "pi.bug-report")
(defparameter +bug-report-schema-version+ 1)
(defparameter +bug-report-redacted+ "<redacted>")

(defparameter +bug-report-sensitive-key+
  (cl-ppcre:create-scanner
   "(?:^|[-_])(api[-_]?key|secret|token|password|passwd|credential|authorization|cookie)(?:$|[-_])"
   :case-insensitive-mode t))

(defun bug-report-sensitive-key-p (key)
  (and (stringp key)
       (cl-ppcre:scan
        +bug-report-sensitive-key+
        (cl-ppcre:regex-replace-all
         "([a-z0-9])([A-Z])" key "\\1_\\2"))))

(defun bug-report-redact-url (value)
  (unless (stringp value)
    (return-from bug-report-redact-url value))
  (cl-ppcre:register-groups-bind (scheme rest)
      ("(?i)^([a-z][a-z0-9+.-]*:)([a-z][a-z0-9+.-]*://.*)$" value)
    (return-from bug-report-redact-url
      (concatenate 'string scheme (bug-report-redact-url rest))))
  (cl-ppcre:register-groups-bind (prefix userinfo host-and-rest)
      ("(?i)^(https?://)([^/@]+)@(.+)$" value)
    (declare (ignore userinfo))
    (return-from bug-report-redact-url
      (bug-report-redact-url
       (concatenate 'string prefix host-and-rest))))
  (let ((query-start (position #\? value)))
    (unless query-start
      (return-from bug-report-redact-url value))
    (let* ((base (subseq value 0 query-start))
           (query (subseq value (1+ query-start)))
           (changed-p nil)
           (parts
             (mapcar
              (lambda (pair)
                (let ((eq-at (position #\= pair)))
                  (if eq-at
                      (let ((key (subseq pair 0 eq-at))
                            (val (subseq pair (1+ eq-at))))
                        (if (bug-report-sensitive-key-p key)
                            (progn
                              (setf changed-p t)
                              (concatenate
                               'string key "=" +bug-report-redacted+))
                            pair))
                      pair)))
              (uiop:split-string query :separator '(#\&)))))
      (if changed-p
          (format nil "~A?~{~A~^&~}" base parts)
          value))))

(defun bug-report-redact-json-value (value)
  (cond
    ((null value) nil)
    ((stringp value) (bug-report-redact-url value))
    ((hash-table-p value)
     (let ((next (make-hash-table :test (hash-table-test value))))
       (maphash
        (lambda (key child)
          (setf (gethash key next)
                (if (bug-report-sensitive-key-p
                     (if (stringp key) key (princ-to-string key)))
                    +bug-report-redacted+
                    (bug-report-redact-json-value child))))
        value)
       next))
    ((and (consp value) (keywordp (car value)))
     (loop for (key val) on value by #'cddr
           append
           (list key
                 (if (bug-report-sensitive-key-p (string key))
                     +bug-report-redacted+
                     (bug-report-redact-json-value val)))))
    ((consp value)
     (mapcar #'bug-report-redact-json-value value))
    (t value)))

(defun bug-report-archive-file-name (id)
  (format nil "~A-bug-report-~A.zip"
          (cadr-ai::cadr-product-slug)
          id))

(defun bug-report-collect-environment ()
  (flet ((env (name)
           (let ((value (uiop:getenv name)))
             (and value (plusp (length value)) value))))
    (list
     :version (cadr-ai::cadr-version)
     :user-agent (cadr-user-agent (cadr-ai::cadr-version))
     :runtime
     (format nil "sbcl/~A" (lisp-implementation-version))
     :platform (string-downcase (princ-to-string (uiop:operating-system)))
     :arch (string-downcase (princ-to-string (uiop:architecture)))
     :shell
     (let ((shell (env "SHELL")))
       (and shell
            (let ((slash (position #\/ shell :from-end t)))
              (if slash (subseq shell (1+ slash)) shell))))
     :terminal
     (list
      :term (env "TERM")
      :program (env "TERM_PROGRAM")
      :program-version (env "TERM_PROGRAM_VERSION")
      :colorterm (env "COLORTERM")
      :tmux (and (env "TMUX") t)
      :ssh
      (and (or (env "SSH_CONNECTION")
               (env "SSH_CLIENT")
               (env "SSH_TTY"))
           t)
      :ci (and (env "CI") t))
     :cadr-environment-variables
     (sort
      (loop for pair in (sb-ext:posix-environ)
            for name = (subseq pair 0 (or (position #\= pair) 0))
            when (uiop:string-prefix-p "CADR_" name)
              collect name)
      #'string<))))

(defun bug-report-write-zip (path entries)
  (let ((temporary
          (merge-pathnames
           (format nil "cadr-bug-report-~A/"
                   (cadr-ai:uuid-v7))
           (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (ensure-directories-exist temporary)
           (dolist (entry entries)
             (let ((file (merge-pathnames (car entry) temporary)))
               (ensure-directories-exist file)
               (cadr-core:atomic-write-string file (cdr entry))))
           (uiop:run-program
            (list*
             "python3" "-c"
             (format
              nil
              "import pathlib, sys, zipfile~%~
path = pathlib.Path(sys.argv[1])~%~
with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as archive:~%~
~2Tfor name in sys.argv[2:]:~%~
~4Tsrc = pathlib.Path(name)~%~
~4Tarchive.write(src, arcname=src.name)~%")
             (uiop:native-namestring path)
             (mapcar
              (lambda (entry)
                (uiop:native-namestring
                 (merge-pathnames (car entry) temporary)))
              entries))
            :output nil
            :error-output :string)
           path)
      (uiop:delete-directory-tree temporary
                                  :validate t
                                  :if-does-not-exist :ignore))))
(defparameter +bug-report-disclaimer+
  "This report goes to the Pi developers (Earendil) and is not shared publicly. It includes your pi version, operating system, the current model and provider configuration (without API keys), loaded extensions, settings, and provider error diagnostics from this session.")

(defparameter +bug-report-transcript-note+
  "The transcript contains your messages, model output, tool calls and their results, including file contents and command output read during this session.")

(defun bug-report-json-document (value)
  (with-output-to-string (out)
    (cadr-ai::write-json-value
     (cadr-agent::json-safe-value value)
     out)
    (terpri out)))

(defun bug-report-redact-settings (settings)
  (let ((redacted (bug-report-redact-json-value settings)))
    (cond
      ((hash-table-p redacted)
       (remhash "trackingId" redacted)
       redacted)
      ((and (consp redacted) (keywordp (car redacted)))
       (loop for (key val) on redacted by #'cddr
             unless (member key '(:tracking-id :trackingid) :test #'eq)
               append (list key val)))
      (t redacted))))

(defun bug-report-describe-model (model)
  (when model
    (list
     :provider (cadr-ai:model-provider model)
     :id (cadr-ai:model-id model)
     :name (cadr-ai::model-name model)
     :api (cadr-ai:model-api model)
     :base-url
     (bug-report-redact-url (cadr-ai:model-base-url model))
     :reasoning (cadr-ai:model-reasoning-p model)
     :context-window (cadr-ai:model-context-window model)
     :max-tokens (cadr-ai:model-max-tokens model)
     :header-names
     (sort
      (mapcar #'car (cadr-ai::model-headers model))
      #'string<
      :key (lambda (name)
             (if (stringp name) name (princ-to-string name)))))))

(defun collect-bug-report-metadata
    (&key
       id
       hint
       session-id
       cwd
       include-session
       include-summary
       (message-count 0)
       model
       thinking-level
       (extensions nil)
       (extension-errors nil)
       global-settings
       project-settings)
  (let ((trimmed
          (and hint
               (let ((text (string-trim
                            '(#\Space #\Tab #\Newline #\Return)
                            hint)))
                 (and (plusp (length text)) text)))))
    (list
     :schema-version +bug-report-schema-version+
     :id (or id (cadr-ai:uuid-v7))
     :created-at (cadr-core:current-utc-iso8601)
     :hint trimmed
     :environment (bug-report-collect-environment)
     :session
     (append
      (list
       :id session-id
       :included (and include-session t)
       :summary-included (and include-summary t)
       :message-count message-count)
      (when include-session
        (list :cwd cwd)))
     :model (bug-report-describe-model model)
     :provider nil
     :thinking-level thinking-level
     :extensions (or extensions nil)
     :extension-errors (or extension-errors nil)
     :settings
     (list
      :global (bug-report-redact-settings
               (or global-settings (cadr-ai::json-object)))
      :project (bug-report-redact-settings
                (or project-settings (cadr-ai::json-object)))))))

(defun collect-bug-report-diagnostics (session &optional crashes)
  (let* ((entries
           (and session
                (cadr-agent::session-path-entries session)))
         (assistant nil)
         (assistant-count 0))
    (dolist (entry entries)
      (when (eq :message (cadr-agent:session-entry-type entry))
        (let ((message (cadr-agent:session-entry-message entry)))
          (when (typep message 'cadr-ai:assistant-message)
            (incf assistant-count)
            (let ((diagnostics
                    (cadr-ai:assistant-message-diagnostics message))
                  (stop
                    (cadr-ai:assistant-message-stop-reason message))
                  (error-message
                    (cadr-ai:assistant-message-error-message
                     message)))
              (when
                  (or diagnostics
                      (member stop '(:error :aborted))
                      error-message)
                (push
                 (append
                  (list
                   :entry-id (cadr-agent:session-entry-id entry)
                   :timestamp
                   (cadr-agent::session-timestamp-json
                    (cadr-agent:session-entry-timestamp entry))
                   :provider
                   (cadr-ai:assistant-message-provider message)
                   :model (cadr-ai:assistant-message-model message)
                   :api (cadr-ai:assistant-message-api message)
                   :stop-reason stop)
                  (let ((raw
                          (cadr-ai:assistant-message-raw-stop-reason
                           message)))
                    (and raw (list :raw-stop-reason raw)))
                  (and error-message
                       (list :error-message error-message))
                  (list :diagnostics (or diagnostics nil)))
                 assistant)))))))
    (list
     :schema-version +bug-report-schema-version+
     :session-id (and session (cadr-agent:session-id session))
     :entry-count (length entries)
     :assistant-message-count assistant-count
     :assistant (nreverse assistant)
     :crashes (or crashes nil))))

(defun bug-report-files (bundle)
  (let ((files
          (list
           (list
            :name "report.json"
            :content-type "application/json"
            :data
            (bug-report-json-document
             (getf bundle :metadata)))
           (list
            :name "diagnostics.json"
            :content-type "application/json"
            :data
            (bug-report-json-document
             (getf bundle :diagnostics))))))
    (when (getf bundle :session-jsonl)
      (setf files
            (append
             files
             (list
              (list
               :name "session.jsonl"
               :content-type "application/x-ndjson"
               :data (getf bundle :session-jsonl))))))
    (when (getf bundle :summary)
      (let* ((summary (getf bundle :summary))
             (data
               (if (and (plusp (length summary))
                        (char= (char summary
                                     (1- (length summary)))
                               #\Newline))
                   summary
                   (concatenate 'string summary
                                (string #\Newline)))))
        (setf files
              (append
               files
               (list
                (list
                 :name "summary.md"
                 :content-type "text/markdown"
                 :data data))))))
    files))

(defun bug-report-write-archive (bundle path)
  (bug-report-write-zip
   path
   (mapcar
    (lambda (file)
      (cons (getf file :name) (getf file :data)))
    (bug-report-files bundle))))

(defun bug-report-session-jsonl (session &key agent)
  (unless session
    (return-from bug-report-session-jsonl nil))
  (let* ((directory
           (merge-pathnames
            (format nil "cadr-bug-session-~A/"
                    (cadr-ai:uuid-v7))
            (uiop:temporary-directory)))
         (path (merge-pathnames "session.jsonl" directory)))
    (unwind-protect
         (progn
           (export-session-for-share
            session path
            :system-prompt
            (or (and agent
                     (cadr-agent::agent-system-prompt agent))
                "")
            :tools
            (and agent
                 (cadr-agent::merged-agent-tools agent)))
           (uiop:read-file-string path))
      (when (probe-file directory)
        (uiop:delete-directory-tree
         directory
         :validate t
         :if-does-not-exist :ignore)))))

(defun build-bug-report-bundle (agent options &optional summary)
  (let* ((session (and agent (cadr-agent:agent-session agent)))
         (model (and agent (cadr-agent:agent-model agent)))
         (include-session (getf options :include-session))
         (metadata
           (collect-bug-report-metadata
            :hint (getf options :hint)
            :session-id
            (and session (cadr-agent:session-id session))
            :cwd
            (and session (cadr-agent:session-cwd session))
            :include-session include-session
            :include-summary (not (null summary))
            :message-count
            (if session
                (count
                 :message
                 (cadr-agent::session-path-entries session)
                 :key #'cadr-agent:session-entry-type)
                0)
            :model model
            :thinking-level
            (and agent
                 (cadr-agent::agent-thinking-level agent))))
         (diagnostics
           (collect-bug-report-diagnostics
            session
            (crash-log-for-diagnostics))))
    (list
     :metadata metadata
     :diagnostics diagnostics
     :session-jsonl
     (and include-session
          (bug-report-session-jsonl session :agent agent))
     :summary summary)))

(defun bug-report-gateway-url (&optional gateway)
  (or (and gateway (plusp (length gateway)) gateway)
      (let ((configured (uiop:getenv "RADIUS_GATEWAY_URL")))
        (and configured (plusp (length configured)) configured))
      (default-radius-gateway)))

(defun bug-report-gateway-host (gateway)
  (or
   (cl-ppcre:register-groups-bind (host)
       ("(?i)^[a-z][a-z0-9+.-]*://([^/?#:]+)" gateway)
     host)
   gateway))

(defun bug-report-multipart-octets (files boundary)
  (let ((chunks nil))
    (dolist (file files)
      (let* ((name (getf file :name))
             (type (getf file :content-type))
             (data (getf file :data))
             (head
               (format
                nil
                "--~A~C~CContent-Disposition: form-data; name=~S; filename=~S~C~CContent-Type: ~A~C~C~C~C"
                boundary #\Return #\Newline
                name name #\Return #\Newline
                type #\Return #\Newline
                #\Return #\Newline))
             (tail
               (format nil "~C~C" #\Return #\Newline)))
        (push (cadr-ai::utf8-octets head) chunks)
        (push
         (if (typep data
                    '(simple-array (unsigned-byte 8) (*)))
             data
             (cadr-ai::utf8-octets (or data "")))
         chunks)
        (push (cadr-ai::utf8-octets tail) chunks)))
    (push
     (cadr-ai::utf8-octets
      (format nil "--~A--~C~C" boundary #\Return #\Newline))
     chunks)
    (apply
     #'concatenate
     '(simple-array (unsigned-byte 8) (*))
     (nreverse chunks))))

(defun upload-bug-report
    (bundle
     &key
       token
       gateway-url
       (http #'cadr-ai:request-json)
       auth-path)
  (let* ((gateway (bug-report-gateway-url gateway-url))
         (bearer
           (or token
               (radius-share-token auth-path)))
         (boundary
           (format nil "cadr-bug-~A" (cadr-ai:uuid-v7)))
         (body
           (bug-report-multipart-octets
            (bug-report-files bundle) boundary))
         (headers
           (list
            (cons "Content-Type"
                  (format nil
                          "multipart/form-data; boundary=~A"
                          boundary))))
         (request
           (cadr-ai::make-request-spec
            :method :post
            :url
            (format nil "~A/v1/bug-reports"
                    (string-right-trim "/" gateway))
            :headers
            (if bearer
                (cons
                 (cons "Authorization"
                       (format nil "Bearer ~A" bearer))
                 headers)
                headers)
            :raw-body body)))
    (let* ((response
             (if (eq http #'cadr-ai:request-json)
                 (cadr-ai:request-json request)
                 (funcall http request)))
           (ok (cadr-ai::json-get response "ok"))
           (report
             (cadr-ai::json-get response "bug_report"))
           (id
             (and report
                  (cadr-ai::json-get report "id")))
           (detail
             (and (not (eq ok t))
                  (or (cadr-ai::json-get response "description")
                      (cadr-ai::json-get response "error")))))
      (unless (and (eq ok t) (stringp id) (plusp (length id)))
        (error
         "Bug report upload failed: ~A"
         (or detail "unknown error")))
      (list :id id))))

(defun bug-report-emit
    (message output &key status-function (kind :info))
  (if status-function
      (funcall status-function message kind)
      (format output "~A~%" message))
  (finish-output output)
  message)

(defun bug-report-ui-input
    (ui-function title description &optional initial-value)
  (funcall
   ui-function :input
   (list
    :title title
    :description description
    :initial-value initial-value)))

(defun bug-report-ui-select
    (ui-function title options &optional description)
  (funcall
   ui-function :select
   (list
    :title title
    :options options
    :message description
    :description description)))

(defun prompt-bug-report-options
    (ui-function initial-hint &key model)
  (let* ((hint
           (bug-report-ui-input
            ui-function
            "Report a bug"
            (format nil "~A~%~%What went wrong? (optional)"
                    +bug-report-disclaimer+)
            initial-hint)))
    (unless (stringp hint)
      (return-from prompt-bug-report-options nil))
    (let ((transcript
            (bug-report-ui-select
             ui-function
             "Include the session transcript?"
             '("Yes, include the transcript" "No")
             +bug-report-transcript-note+)))
      (unless transcript
        (return-from prompt-bug-report-options nil))
      (let* ((include-session
               (not (string= transcript "No")))
             (include-summary nil)
             (model-name
               (or (and model (cadr-ai::model-name model))
                   "the current model"))
             (model-provider
               (or (and model
                        (princ-to-string
                         (cadr-ai:model-provider model)))
                   "your provider")))
        (unless include-session
          (let ((summary-choice
                  (bug-report-ui-select
                   ui-function
                   (format nil
                           "Attach a summary written by ~A instead?"
                           model-name)
                   '("Yes, generate a summary" "No")
                   (format
                    nil
                    "The transcript is sent to ~A with your credentials and tokens. Only the generated summary is attached; the transcript stays on your machine."
                    model-provider))))
            (unless summary-choice
              (return-from prompt-bug-report-options nil))
            (setf include-summary
                  (not (string= summary-choice "No")))))
        (let* ((description
                 (string-trim
                  '(#\Space #\Tab #\Newline #\Return)
                  hint))
               (gateway (bug-report-gateway-url))
               (delivery
                 (bug-report-ui-select
                  ui-function
                  "Bug report"
                  '("Upload Report" "Export as Zip" "Cancel")
                  (format
                   nil
                   "Description: ~A~%Transcript: ~A~%Summary: ~A~%~%Upload sends the report to ~A. Export writes a zip archive to the current directory instead."
                   (if (plusp (length description))
                       description
                       "none")
                   (if include-session "included" "not included")
                   (if include-summary
                       (format nil "written by ~A" model-name)
                       "none")
                   (bug-report-gateway-host gateway)))))
          (when (or (null delivery)
                    (string= delivery "Cancel"))
            (return-from prompt-bug-report-options nil))
          (list
           :hint
           (and (plusp (length description)) description)
           :include-session include-session
           :include-summary include-summary
           :delivery
           (if (string= delivery "Upload Report")
               :upload
               :zip)))))))

(defun bug-report-record-in-session
    (session bundle delivery &optional path)
  (when session
    (let ((metadata (getf bundle :metadata)))
      (cadr-agent:session-append-custom
       session
       +bug-report-custom-entry-type+
       (append
        (list
         :id (getf metadata :id)
         :created-at (getf metadata :created-at)
         :hint (getf metadata :hint)
         :session-included
         (getf (getf metadata :session) :included)
         :summary-included
         (getf (getf metadata :session) :summary-included)
         :delivery delivery)
        (and path (list :path (uiop:native-namestring path)))))))
  (when (getf (getf bundle :diagnostics) :crashes)
    (clear-crash-log)))

(defun bug-report-export-zip
    (agent bundle
     &key output status-function)
  (let* ((metadata (getf bundle :metadata))
         (path
           (merge-pathnames
            (bug-report-archive-file-name
             (getf metadata :id))
            (uiop:getcwd))))
    (handler-case
        (progn
          (bug-report-write-archive bundle path)
          (bug-report-record-in-session
           (and agent (cadr-agent:agent-session agent))
           bundle :zip path)
          (bug-report-emit
           (format
            nil
            "Bug report exported to: ~A~%Report ID: ~A"
            (uiop:native-namestring path)
            (getf metadata :id))
           output
           :status-function status-function
           :kind :success)
          path)
      (error (condition)
        (bug-report-emit
         (format nil "Failed to write bug report: ~A"
                 condition)
         output
         :status-function status-function
         :kind :error)
        nil))))

(defun bug-report-try-upload
    (agent bundle
     &key output status-function http auth-path token gateway-url)
  (handler-case
      (let ((result
              (upload-bug-report
               bundle
               :token token
               :gateway-url gateway-url
               :http http
               :auth-path auth-path)))
        (bug-report-record-in-session
         (and agent (cadr-agent:agent-session agent))
         bundle :upload)
        (bug-report-emit
         (format nil "Bug report uploaded. Report ID: ~A"
                 (getf result :id))
         output
         :status-function status-function
         :kind :success)
        t)
    (error (condition)
      (bug-report-emit
       (format nil "~A" condition)
       output
       :status-function status-function
       :kind :error)
      nil)))

(defun run-bug-report
    (agent
     &key
       initial-hint
       ui-function
       status-function
       (output *standard-output*)
       (http #'cadr-ai:request-json)
       auth-path
       token
       gateway-url)
  (let ((options
          (if ui-function
              (prompt-bug-report-options
               ui-function initial-hint
               :model
               (and agent (cadr-agent:agent-model agent)))
              (list
               :hint
               (and initial-hint
                    (plusp (length initial-hint))
                    initial-hint)
               :include-session nil
               :include-summary nil
               :delivery :zip))))
    (unless options
      (bug-report-emit
       "Bug report cancelled" output
       :status-function status-function)
      (return-from run-bug-report t))
    (when (getf options :include-summary)
      (bug-report-emit
       "Bug report summary is not available yet"
       output
       :status-function status-function
       :kind :error)
      (return-from run-bug-report t))
    (let ((bundle
            (handler-case
                (build-bug-report-bundle agent options)
              (error (condition)
                (bug-report-emit
                 (format nil "Failed to build bug report: ~A"
                         condition)
                 output
                 :status-function status-function
                 :kind :error)
                nil))))
      (unless bundle
        (return-from run-bug-report t))
      (when (eq (getf options :delivery) :upload)
        (when
            (bug-report-try-upload
             agent bundle
             :output output
             :status-function status-function
             :http http
             :auth-path auth-path
             :token token
             :gateway-url gateway-url)
          (return-from run-bug-report t))
        (if ui-function
            (let ((fallback
                    (bug-report-ui-select
                     ui-function
                     "Upload failed"
                     '("Export as Zip" "Cancel")
                     "Export the report as a zip archive instead?")))
              (unless (string= fallback "Export as Zip")
                (bug-report-emit
                 "Bug report cancelled" output
                 :status-function status-function)
                (return-from run-bug-report t)))
            (return-from run-bug-report t)))
      (bug-report-export-zip
       agent bundle
       :output output
       :status-function status-function)
      t)))
