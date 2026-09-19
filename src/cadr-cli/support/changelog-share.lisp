(in-package #:cadr-cli)

(defun strip-ansi (value)
  (unless (stringp value)
    (error 'type-error
           :datum value
           :expected-type 'string))
  (when (loop for character across value
              never (or (char= character #\Escape)
                        (= (char-code character) #x9b)))
    (return-from strip-ansi value))
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length value))
          for character = (char value index)
          do
          (cond
            ((= (char-code character) #x9b)
             (incf index)
             (loop while (< index (length value))
                   for code = (char-code (char value index))
                   do (incf index)
                   when (<= #x40 code #x7e)
                     do (return)))
            ((char/= character #\Escape)
             (write-char character output)
             (incf index))
            ((= (1+ index) (length value))
             (write-char character output)
             (incf index))
            (t
             (let ((next (char value (1+ index))))
               (cond
                 ((char= next #\])
                  (let ((end nil)
                        (position (+ index 2)))
                    (loop while (< position (length value))
                          for code =
                          (char-code (char value position))
                          do
                          (cond
                            ((or (= code 7) (= code #x9c))
                             (setf end (1+ position))
                             (return))
                            ((and
                              (char= (char value position)
                                     #\Escape)
                              (< (1+ position)
                                 (length value))
                              (char=
                               (char value (1+ position))
                               #\\))
                             (setf end (+ position 2))
                             (return)))
                          (incf position))
                    (if end
                        (setf index end)
                        (progn
                          (write-char character output)
                          (incf index)))))
                 ((char= next #\[)
                  (incf index 2)
                  (loop while (< index (length value))
                        for code =
                        (char-code (char value index))
                        do (incf index)
                        when (<= #x40 code #x7e)
                          do (return)))
                 ((member next
                          '(#\( #\) #\* #\+ #\- #\. #\/))
                  (incf index
                        (if (< (+ index 2)
                               (length value))
                            3
                            2)))
                 ((or (char= next #\c)
                      (char= next #\\)
                      (char<= #\g next #\m)
                      (char<= #\r next #\t))
                  (incf index 2))
                 (t
                  (write-char character output)
                  (incf index)))))))))

(defun normalize-version-tag (version)
  (if (uiop:string-prefix-p "v" version)
      version
      (concatenate 'string "v" version)))

(defun normalize-repository-relative-path (target)
  (let ((parts nil))
    (dolist
        (part
         (uiop:split-string
          (substitute #\/ #\\ target)
          :separator '(#\/)))
      (cond
        ((or (string= part "")
             (string= part "."))
         nil)
        ((string= part "..")
         (if parts
             (pop parts)
             (return-from
                 normalize-repository-relative-path nil)))
        (t (push part parts))))
    (format nil "~{~A~^/~}" (nreverse parts))))

(defun changelog-local-target (target tag)
  (let* ((hash (position #\# target))
         (before-hash
           (if hash (subseq target 0 hash) target))
         (fragment
           (if hash (subseq target hash) ""))
         (query-position
           (position #\? before-hash))
         (path
           (if query-position
               (subseq before-hash 0 query-position)
               before-hash))
         (query
           (if query-position
               (subseq before-hash query-position)
               "")))
    (when (zerop (length path))
      (return-from changelog-local-target target))
    (let* ((joined
             (if (uiop:string-prefix-p "/" path)
                 (string-left-trim "/" path)
                 (format nil
                         "packages/coding-agent/~A"
                         path)))
           (repository-path
             (normalize-repository-relative-path joined)))
      (unless repository-path
        (return-from changelog-local-target target))
      (let ((directory-p
              (or (uiop:string-suffix-p path "/")
                  (not
                   (find #\.
                         (car
                          (last
                           (uiop:split-string
                            repository-path
                            :separator '(#\/)))))))))
        (format
         nil
         "~A/~A/~A/~A~:[~;/~]~A~A"
         (cadr-ai::cadr-canonical-repository-url)
         (if directory-p "tree" "blob")
         tag repository-path
         directory-p query fragment)))))

(defun normalize-changelog-target (target tag)
  (let ((canonical
          (cl-ppcre:regex-replace
           "^https://github\\.com/(?:badlogic/pi-mono|earendil-works/(?:pi|pi-mono))(?=/|$)"
           target
           (cadr-ai::cadr-canonical-repository-url))))
    (setf canonical
          (cl-ppcre:regex-replace
           "^https://github\\.com/artwalker/cadr/(blob|tree)/(?:main|master)/"
           canonical
           (format nil
                   "~A/\\1/~A/"
                   (cadr-ai::cadr-canonical-repository-url)
                   tag)))
    (if (or (uiop:string-prefix-p "#" canonical)
            (uiop:string-prefix-p "//" canonical)
            (cl-ppcre:scan
             "^[A-Za-z][A-Za-z0-9+.-]*:"
             canonical))
        canonical
        (changelog-local-target canonical tag))))

(defun normalize-changelog-links (markdown version)
  (let ((tag (normalize-version-tag version)))
    (cl-ppcre:regex-replace-all
     "(!?\\[[^]\\n]+\\]\\()([^\\s)]+)([^)]*\\))"
     markdown
     (lambda
         (target start end match-start match-end
          register-starts register-ends)
       (declare
        (ignore start end match-start match-end))
       (flet ((capture (index)
                (subseq
                 target
                 (aref register-starts index)
                 (aref register-ends index))))
         (format nil "~A~A~A"
                 (capture 0)
                 (normalize-changelog-target
                  (capture 1) tag)
                 (capture 2)))))))

(defun parse-changelog (path)
  (unless (probe-file path)
    (return-from parse-changelog nil))
  (handler-case
      (let ((entries nil)
            (current-version nil)
            (current-lines nil))
        (labels
            ((save-current ()
               (when (and current-version
                          current-lines)
                 (push
                  (list
                   :version current-version
                   :content
                   (string-trim
                    '(#\Space #\Tab #\Newline
                      #\Return)
                    (format nil
                            "~{~A~^~%~}"
                            (nreverse
                             current-lines))))
                  entries))))
          (dolist
              (line
               (uiop:split-string
                (uiop:read-file-string
                 path :external-format :utf-8)
                :separator '(#\Newline)))
            (if (uiop:string-prefix-p
                 "## " line)
                (progn
                  (save-current)
                  (multiple-value-bind
                        (match registers)
                      (cl-ppcre:scan-to-strings
                       "^##\\s+\\[?([0-9]+\\.[0-9]+\\.[0-9]+)\\]?"
                       line)
                    (declare (ignore match))
                    (if registers
                        (setf
                         current-version
                         (aref registers 0)
                         current-lines
                         (list line))
                        (setf
                         current-version nil
                         current-lines nil))))
                (when current-version
                  (push line current-lines))))
          (save-current)
          (nreverse entries)))
    (condition () nil)))

(defun changelog-version-triplet (version)
  (flet ((part (piece)
           (or (ignore-errors
                 (parse-integer piece :junk-allowed t))
               0)))
    (let ((parts
            (uiop:split-string
             (or version "")
             :separator '(#\.))))
      (values
       (part (or (first parts) "0"))
       (part (or (second parts) "0"))
       (part (or (third parts) "0"))))))

(defun changelog-version> (left right)
  (multiple-value-bind (left-major left-minor left-patch)
      (changelog-version-triplet left)
    (multiple-value-bind
          (right-major right-minor right-patch)
        (changelog-version-triplet right)
      (cond
        ((/= left-major right-major)
         (> left-major right-major))
        ((/= left-minor right-minor)
         (> left-minor right-minor))
        (t
         (> left-patch right-patch))))))

(defun get-new-changelog-entries (entries last-version)
  (remove-if-not
   (lambda (entry)
     (changelog-version>
      (getf entry :version)
      last-version))
   entries))

(defun default-share-command-runner (argv)
  (uiop:run-program
   argv
   :output :string
   :error-output :string
   :ignore-error-status t))

(defun share-viewer-url
    (gist-id &optional viewer-base-url)
  (let ((configured
          (uiop:getenv "CADR_SHARE_VIEWER_URL")))
    (format
     nil "~A#~A"
     (or viewer-base-url
         (and configured
              (plusp (length configured))
              configured)
         (cadr-ai::cadr-default-share-viewer-url))
     gist-id)))

(defvar *call-with-share-loader* nil
  "When bound, a function of (message upload). upload receives an abort predicate. Nil outside the interactive TUI.")

(defun share-phase-message (token)
  (if token
      "Uploading to Radius..."
      "Creating gist..."))

(defun share-aborted-p (abort-p)
  (cadr-core:cancellation-predicate-aborted-p abort-p))

(defun signal-share-aborted ()
  (error 'cadr-ai:request-aborted :message "Request was aborted"))

(defun ensure-share-not-aborted (abort-p)
  (when (share-aborted-p abort-p)
    (signal-share-aborted)))

(defun run-abortable-share-command (argv abort-p)
  (ensure-share-not-aborted abort-p)
  (let ((process
          (uiop:launch-program
           argv
           :input nil
           :output :stream
           :error-output :stream
           :ignore-error-status t)))
    (unwind-protect
         (progn
           (loop while (uiop:process-alive-p process)
                 do (when (share-aborted-p abort-p)
                      (uiop:terminate-process process :urgent t)
                      (signal-share-aborted))
                    (sleep 0.05d0))
           (let ((status (or (uiop:wait-process process) 1)))
             (values
              (or (ignore-errors
                    (uiop:slurp-stream-string
                     (uiop:process-info-output process)))
                  "")
              (or (ignore-errors
                    (uiop:slurp-stream-string
                     (uiop:process-info-error-output process)))
                  "")
              status)))
      (when (uiop:process-alive-p process)
        (ignore-errors
          (uiop:terminate-process process :urgent t))
        (ignore-errors
          (uiop:wait-process process))))))

(defun call-share-runner (runner argv abort-p)
  (ensure-share-not-aborted abort-p)
  (if (and abort-p
           (eq runner #'default-share-command-runner))
      (run-abortable-share-command argv abort-p)
      (funcall runner argv)))

(defun invoke-share-http (http request abort-p)
  (ensure-share-not-aborted abort-p)
  (handler-case
      (if (eq http #'cadr-ai:request-json)
          (cadr-ai:request-json request :abort-p abort-p)
          (funcall http request))
    (cadr-ai:request-aborted (condition)
      (error condition))
    (error (condition)
      (error "Failed to upload Radius artifact: ~A"
             condition))))

(defun share-session-as-gist
    (session
     &key
       (runner #'default-share-command-runner)
       viewer-base-url
       abort-p)
  (handler-case
      (multiple-value-bind
            (ignored error-output status)
          (call-share-runner
           runner
           '("gh" "auth" "status")
           abort-p)
        (declare (ignore ignored error-output))
        (unless (and (integerp status)
                     (zerop status))
          (error
           "GitHub CLI is not logged in. Run 'gh auth login' first.")))
    (file-error ()
      (error
       "GitHub CLI (gh) is not installed. Install it from https://cli.github.com/")))
  (let ((temporary
          (merge-pathnames
           (format nil
                   "cadr-session-~A.html"
                   (cadr-ai:uuid-v7))
           (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (cadr-agent:export-session-html
            session temporary)
           (multiple-value-bind
                 (stdout stderr status)
               (call-share-runner
                runner
                (list
                 "gh" "gist" "create"
                 "--public=false"
                 (namestring temporary))
                abort-p)
             (unless
                 (and (integerp status)
                      (zerop status))
               (error
                "Failed to create gist: ~A"
                (or
                 (and stderr
                      (string-trim
                       '(#\Space #\Tab #\Newline
                         #\Return)
                       stderr))
                 "Unknown error")))
             (let* ((gist-url
                      (and stdout
                           (string-trim
                            '(#\Space #\Tab
                              #\Newline #\Return)
                            stdout)))
                    (segments
                      (and gist-url
                           (remove
                            ""
                            (uiop:split-string
                             gist-url
                             :separator '(#\/))
                            :test #'string=)))
                    (gist-id
                      (car (last segments))))
               (unless
                   (and gist-id
                        (plusp
                         (length gist-id)))
                 (error
                  "Failed to parse gist ID from gh output"))
               (values
                (share-viewer-url
                 gist-id viewer-base-url)
                gist-url))))
      (when (probe-file temporary)
        (delete-file temporary)))))

(defun share-tool-record (tool)
  (cadr-ai::json-object
   "name" (cadr-ai:tool-name tool)
   "description" (cadr-ai:tool-description tool)
   "parameters"
   (cadr-agent::json-safe-value
    (cadr-ai:tool-parameters tool))))

(defun export-session-for-share
    (session path &key (system-prompt "") tools)
  (ensure-directories-exist path)
  (let ((timestamp
          (cadr-agent::session-timestamp-json
           (cadr-core:unix-milliseconds)))
        (parent-id nil))
    (with-open-file
        (stream path
                :direction :output
                :if-exists :supersede
                :if-does-not-exist :create
                :external-format :utf-8)
      (cadr-agent::write-jsonl-object
       stream
       (cadr-ai::json-object
        "type" "session"
        "version" 3
        "id" (cadr-agent:session-id session)
        "timestamp" timestamp
        "cwd" (cadr-agent:session-cwd session)))
      (dolist (entry (cadr-agent::session-path-entries session))
        (let ((object
                (cadr-agent::session-entry-to-json entry)))
          (cadr-ai::json-put
           object "parentId" (or parent-id 'null))
          (cadr-agent::write-jsonl-object stream object)
          (setf parent-id
                (cadr-agent:session-entry-id entry))))
      (cadr-agent::write-jsonl-object
       stream
       (cadr-ai::json-object
        "type" "custom"
        "customType" "pi.share"
        "id" (subseq (cadr-ai:uuid-v7) 0 8)
        "parentId" (or parent-id 'null)
        "timestamp" timestamp
        "data"
        (cadr-ai::json-object
         "systemPrompt" (or system-prompt "")
         "tools"
         (map 'vector #'share-tool-record tools))))))
  path)

(defun radius-share-refresh (credential)
  (cadr-ai::refresh-radius-oauth-credential
   (let ((configured (uiop:getenv "RADIUS_GATEWAY_URL")))
     (if (and configured (plusp (length configured)))
         configured
         (default-radius-gateway)))
   credential))

(defun radius-share-token
    (auth-path &key (refresh #'radius-share-refresh))
  (let* ((path (or auth-path (cadr-core:agent-auth-path)))
         (credential
           (cadr-ai:read-auth-credential path :radius)))
    (cond
      ((typep credential 'cadr-ai:oauth-credential)
       (let* ((resolved
                (cadr-ai:resolve-oauth-credential
                 path :radius refresh
                 :minimum-validity-milliseconds
                 (* 5 60 1000)))
              (access
                (cadr-ai:oauth-credential-access resolved)))
         (when (and (stringp access) (plusp (length access)))
           access)))
      ((typep credential 'cadr-ai:api-key-credential)
       (let ((key
               (cadr-ai:api-key-credential-key credential)))
         (when (and (stringp key) (plusp (length key)))
           key))))))

(defun default-radius-gateway ()
  (cadr-ai:provider-definition-base-url
   (cadr-ai:find-provider-definition :radius)))

(defun share-via-radius (jsonl-path token gateway http &key abort-p)
  (let* ((body (uiop:read-file-string jsonl-path))
         (title
           (format nil "~A session"
                   (cadr-ai::cadr-product-display-name)))
         (request
           (cadr-ai::make-request-spec
            :method :post
            :url
            (format nil
                    "~A/v1/artifacts?visibility=organization&title=~A"
                    (string-right-trim "/" gateway)
                    (cl-ppcre:regex-replace-all
                     " " title "%20"))
            :headers
            (list
             (cons "Authorization"
                   (format nil "Bearer ~A" token))
             (cons "Content-Type" "application/x-ndjson"))
            :raw-body body)))
    (let ((response (invoke-share-http http request abort-p)))
      (ensure-share-not-aborted abort-p)
      (let* ((artifact
               (cadr-ai::json-get response "artifact"))
             (url
               (and artifact
                    (cadr-ai::json-get artifact "canonical_url"))))
        (unless (and (stringp url) (plusp (length url)))
          (error
           "Failed to upload Radius artifact: response has no canonical_url"))
        url))))

(defun share-session
    (session
     &key
       agent
       (runner #'default-share-command-runner)
       viewer-base-url
       (auth-path nil auth-path-p)
       radius-token
       radius-gateway
       (refresh #'radius-share-refresh)
       (http #'cadr-ai:request-json))
  (let* ((token
           (or radius-token
               (and (not (and auth-path-p (null auth-path)))
                    (radius-share-token auth-path :refresh refresh))))
         (directory
           (merge-pathnames
            (format nil "cadr-share-~A/" (cadr-ai:uuid-v7))
            (uiop:temporary-directory)))
         (jsonl (merge-pathnames "session.jsonl" directory)))
    (ensure-directories-exist directory)
    (unwind-protect
         (progn
           (export-session-for-share
            session jsonl
            :system-prompt
            (or (and agent
                     (cadr-agent::agent-system-prompt agent))
                "")
            :tools
            (and agent
                 (cadr-agent::merged-agent-tools agent)))
           (flet ((upload (abort-p)
                    (handler-case
                        (if token
                            (values
                             (share-via-radius
                              jsonl token
                              (or radius-gateway
                                  (default-radius-gateway))
                              http
                              :abort-p abort-p)
                             nil)
                            (share-session-as-gist
                             session
                             :runner runner
                             :viewer-base-url viewer-base-url
                             :abort-p abort-p))
                      (cadr-ai:request-aborted ()
                        (values nil :cancelled)))))
             (if *call-with-share-loader*
                 (funcall *call-with-share-loader*
                          (share-phase-message token)
                          #'upload)
                 (upload nil))))
      (when (probe-file directory)
        (uiop:delete-directory-tree
         directory
         :validate t
         :if-does-not-exist :ignore)))))
