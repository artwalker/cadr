(in-package #:cadr-cli)

(defun stop-thread-for-cleanup
    (thread &key (timeout 0.5d0) (terminate-p t))
  (cond
    ((null thread) :absent)
    ((eq thread sb-thread:*current-thread*) :current)
    ((not (sb-thread:thread-alive-p thread))
     (ignore-errors
       (sb-thread:join-thread thread :timeout timeout :default nil))
     :joined)
    (t
     (let* ((timed-out (list :timed-out))
            (result
              (handler-case
                  (sb-thread:join-thread
                   thread :timeout timeout :default timed-out)
                (condition () timed-out))))
       (if (not (eq result timed-out))
           :joined
           (if (not terminate-p)
               :abandoned
               (progn
                 (ignore-errors
                   (sb-thread:terminate-thread thread))
                 (let ((terminated
                         (handler-case
                             (sb-thread:join-thread
                              thread :timeout timeout
                              :default timed-out)
                           (condition () timed-out))))
                   (if (or (not (eq terminated timed-out))
                           (not (sb-thread:thread-alive-p thread)))
                       :terminated
               :abandoned)))))))))

(defun atomic-write-utf8 (path content)
  (let* ((name (or (pathname-name path) "file"))
         (temporary
           (make-pathname
            :name (format nil ".~A.cadr-~D"
                          name (random most-positive-fixnum))
            :type "tmp"
            :defaults path)))
    (ensure-directories-exist path)
    (unwind-protect
         (progn
           (write-utf8-file temporary content)
           (uiop:rename-file-overwriting-target temporary path))
      (when (probe-file temporary)
        (delete-file temporary)))))

(defun strip-ansi (value)
  (unless (stringp value)
    (error 'type-error
           :datum value
           :expected-type 'string))
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
              (or (uiop:string-suffix-p "/" path)
                  (not
                   (find #\.
                         (car
                          (last
                           (uiop:split-string
                            repository-path
                            :separator '(#\/)))))))))
        (format
         nil
         "https://github.com/earendil-works/pi/~A/~A/~A~:[~;/~]~A~A"
         (if directory-p "tree" "blob")
         tag repository-path
         directory-p query fragment)))))

(defun normalize-changelog-target (target tag)
  (let ((canonical
          (cl-ppcre:regex-replace
           "^https://github\\.com/(?:badlogic|earendil-works)/pi-mono(?=/|$)"
           target
           "https://github.com/earendil-works/pi")))
    (setf canonical
          (cl-ppcre:regex-replace
           "^https://github\\.com/earendil-works/pi/(blob|tree)/(?:main|master)/"
           canonical
           (format nil
                   "https://github.com/earendil-works/pi/\\1/~A/"
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

(defun default-share-command-runner (argv)
  (uiop:run-program
   argv
   :output :string
   :error-output :string
   :ignore-error-status t))

(defun share-viewer-url
    (gist-id &optional viewer-base-url)
  (format
   nil "~A#~A"
   (or viewer-base-url
       (uiop:getenv "PI_SHARE_VIEWER_URL")
       (uiop:getenv "CADR_SHARE_VIEWER_URL")
       "https://pi.dev/session/")
   gist-id))

(defun share-session-as-gist
    (session
     &key
       (runner #'default-share-command-runner)
       viewer-base-url)
  (handler-case
      (multiple-value-bind
            (ignored error-output status)
          (funcall runner
                   '("gh" "auth" "status"))
        (declare (ignore ignored))
        (unless (and (integerp status)
                     (zerop status))
          (error
           "GitHub CLI is not logged in. Run 'gh auth login' first.~@[ (~A)~]"
           (let ((trimmed
                   (and
                    error-output
                    (string-trim
                     '(#\Space #\Tab #\Newline
                       #\Return)
                     error-output))))
             (and trimmed
                  (plusp (length trimmed))
                  trimmed)))))
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
               (funcall
                runner
                (list
                 "gh" "gist" "create"
                 "--public=false"
                 (namestring temporary)))
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

(defun escape-html (text)
  (with-output-to-string (output)
    (loop for character across text
          do
          (case character
            (#\& (write-string "&amp;" output))
            (#\< (write-string "&lt;" output))
            (#\> (write-string "&gt;" output))
            (#\" (write-string "&quot;" output))
            (#\' (write-string "&#39;" output))
            (otherwise
             (write-char character output))))))

(defun strip-c0-controls (text)
  (remove-if
   (lambda (character)
     (let ((code (char-code character)))
       (or (< code #x20)
           (= code #x7f))))
   text))

(defun safe-html-url (url &key image-p)
  (let* ((clean (strip-c0-controls url))
         (lower (string-downcase clean))
         (colon (position #\: lower)))
    (when
        (or
         (null colon)
         (uiop:string-prefix-p "#" lower)
         (uiop:string-prefix-p "/" lower)
         (some
          (lambda (prefix)
            (uiop:string-prefix-p prefix lower))
          '("http:" "https:" "mailto:"))
         (and image-p
              (some
               (lambda (prefix)
                 (uiop:string-prefix-p prefix lower))
               '("data:image/png;base64,"
                 "data:image/jpeg;base64,"
                 "data:image/gif;base64,"
                 "data:image/webp;base64,"))))
      (escape-html clean))))

(defun experimental-features-enabled-p
    (&optional
       (value (or (uiop:getenv "CADR_EXPERIMENTAL")
                  (uiop:getenv "PI_EXPERIMENTAL"))))
  (string= (or value "") "1"))

(defun shell-quote (text)
  (if (and
       (plusp (length text))
       (every
        (lambda (character)
          (or (alphanumericp character)
              (find character "_./:-")))
        text))
      text
      (format nil "'~A'"
              (cadr-ai::replace-all
               text "'" "'\\''"))))

(defun format-resume-command
    (session-id
     &key persisted-p session-file
       session-file-exists-p terminal-p
       default-session-directory-p
       session-directory)
  (when
      (and terminal-p persisted-p session-file
           session-file-exists-p)
    (if default-session-directory-p
        (format nil "cadr --session ~A"
                (shell-quote session-id))
        (format nil
                "cadr --session-dir ~A --session ~A"
                (shell-quote session-directory)
                (shell-quote session-id)))))

(defun write-session-resume-hint
    (session session-directory
     &key
       (output *standard-output*)
       terminal-p
       default-session-directory-p)
  (let* ((path (cadr-agent:session-path session))
         (command
           (format-resume-command
            (cadr-agent:session-id session)
            :persisted-p
            (cadr-agent::session-persisted-p session)
            :session-file path
            :session-file-exists-p
            (not (null (and path (probe-file path))))
            :terminal-p terminal-p
            :default-session-directory-p
            default-session-directory-p
            :session-directory
            (namestring
             (uiop:ensure-directory-pathname
              session-directory)))))
    (when command
      (format
       output "~A ~A~%"
       (cadr-tui:theme-foreground
        :dim "To resume this session:"
        :enabled-p terminal-p)
       command)
      (finish-output output))
    command))

(defun numeric-version-token-p (text)
  (and (plusp (length text))
       (every #'digit-char-p text)))

(defun version-tokens (version)
  (uiop:split-string version
                     :separator '(#\. #\- #\+)))

(defun compare-package-versions (first second)
  (let ((left (version-tokens first))
        (right (version-tokens second)))
    (loop for index below
          (max (length left) (length right))
          for a = (or (nth index left) "0")
          for b = (or (nth index right) "0")
          unless (string= a b)
            do
            (return
              (cond
                ((and (numeric-version-token-p a)
                      (numeric-version-token-p b))
                 (signum
                  (- (parse-integer a)
                     (parse-integer b))))
                ((numeric-version-token-p a) 1)
                ((numeric-version-token-p b) -1)
                (t
                 (if (string< a b) -1 1))))
          finally (return 0))))

(defun pi-user-agent (version)
  (format nil "pi/~A (~(~A~); sbcl/~A; ~(~A~))"
          version
          (software-type)
          (lisp-implementation-version)
          (machine-type)))

(defun git-source-safe-part-p (value &key allow-slash-p)
  (handler-case
      (let ((decoded
              (percent-decode-path value)))
        (and
         (not (find (code-char 0) value))
         (not (find #\\ value))
         (not (uiop:string-prefix-p "/" value))
         (not (find (code-char 0) decoded))
         (not (find #\\ decoded))
         (not (uiop:string-prefix-p "/" decoded))
         (or allow-slash-p
             (not (find #\/ decoded)))
         (not
          (member
           ".."
           (uiop:split-string decoded
                              :separator '(#\/))
           :test #'string=))))
    (condition () nil)))

(defun split-git-ref (repository path-start)
  (let ((separator
          (position #\@ repository
                    :start path-start)))
    (if separator
        (values
         (concatenate
          'string
          (subseq repository 0 separator))
         (subseq repository (1+ separator)))
        (values repository nil))))

(defun parse-git-source (source)
  (let* ((trimmed
           (string-trim '(#\Space #\Tab) source))
         (prefixed-p
           (uiop:string-prefix-p "git:" trimmed))
         (value
           (if prefixed-p
               (string-trim
                '(#\Space #\Tab)
                (subseq trimmed 4))
               trimmed)))
    (unless
        (or prefixed-p
            (cl-ppcre:scan
             "^(?i:https?|ssh|git)://"
             value))
      (return-from parse-git-source nil))
    (handler-case
        (multiple-value-bind
              (repository ref)
            (let ((path-start
                    (cond
                      ((uiop:string-prefix-p "git@" value)
                       (1+
                        (or (position #\: value)
                            (length value))))
                      ((search "://" value)
                       (let* ((scheme-end
                                (+ (search "://" value) 3))
                              (slash
                                (position #\/ value
                                          :start scheme-end)))
                         (if slash (1+ slash)
                             (length value))))
                      (t
                       (1+
                        (or (position #\/ value)
                            (length value)))))))
              (split-git-ref value path-start))
          (let (host path normalized-repository)
            (cond
              ((uiop:string-prefix-p "git@" repository)
               (let ((colon (position #\: repository)))
                 (unless colon
                   (return-from parse-git-source nil))
                 (setf host
                       (subseq repository
                               (length "git@") colon)
                       path (subseq repository (1+ colon))
                       normalized-repository repository)))
              ((search "://" repository)
               (let* ((scheme-end
                        (+ (search "://" repository) 3))
                      (slash
                        (position #\/ repository
                                  :start scheme-end)))
                 (unless slash
                   (return-from parse-git-source nil))
                 (let* ((authority
                          (subseq repository
                                  scheme-end slash))
                        (at
                          (position #\@ authority
                                    :from-end t)))
                   (setf host
                         (if at
                             (subseq authority (1+ at))
                             authority)
                         path
                         (subseq repository (1+ slash))
                         normalized-repository
                         repository))))
              (t
               (let ((slash (position #\/ repository)))
                 (unless slash
                   (return-from parse-git-source nil))
                 (setf host (subseq repository 0 slash)
                       path (subseq repository (1+ slash))
                       normalized-repository
                       (format nil "https://~A"
                               repository)))))
            (setf path
                  (if (uiop:string-suffix-p ".git" path)
                      (subseq path 0 (- (length path) 4))
                      path))
            (when
                (and
                 (find #\. host)
                 (>= (length
                      (uiop:split-string path
                                         :separator '(#\/)))
                     2)
                 (git-source-safe-part-p host)
                 (git-source-safe-part-p
                  path :allow-slash-p t)
                 (or (null ref)
                     (git-source-safe-part-p
                      ref :allow-slash-p t)))
              (list
               :type :git
               :repository normalized-repository
               :host host
               :path path
               :ref ref
               :pinned-p (not (null ref))))))
      (condition () nil))))

(defun header-put (headers name value)
  (acons
   name value
   (remove name headers
           :key #'car
           :test #'string-equal)))

(defun merge-header-sources (&rest sources)
  (let ((result nil))
    (dolist (source sources result)
      (dolist (header source)
        (setf result
              (header-put result
                          (car header)
                          (cdr header)))))))

(defun provider-attribution-headers
    (&key provider base-url telemetry-p
       session-id provider-headers
       request-headers)
  (let ((defaults
          (when telemetry-p
            (cond
              ((or (eq provider :openrouter)
                   (search "openrouter.ai"
                           (or base-url "")))
               '(("HTTP-Referer" . "https://pi.dev")
                 ("X-OpenRouter-Title" . "pi")
                 ("X-OpenRouter-Categories" . "cli-agent")))
              ((or (eq provider :nvidia)
                   (search "integrate.api.nvidia.com"
                           (or base-url "")))
               '(("X-BILLING-INVOKE-ORIGIN" . "Pi")))
              ((or
                (member provider
                        '(:cloudflare-workers-ai
                          :cloudflare-ai-gateway))
                (search "api.cloudflare.com"
                        (or base-url ""))
                (search "gateway.ai.cloudflare.com"
                        (or base-url "")))
               '(("User-Agent" . "pi-coding-agent"))))))
        (session
          (when
              (and session-id
                   (or
                    (member provider
                            '(:opencode :opencode-go))
                    (search "opencode.ai"
                            (or base-url ""))))
            `(("x-opencode-session" . ,session-id)
              ("x-opencode-client" . "pi")))))
    (merge-header-sources
     session defaults provider-headers
     request-headers)))

(defun merge-stream-settings (settings request)
  (let ((result (copy-list request)))
    (unless (getf result :timeout-ms)
      (setf (getf result :timeout-ms)
            (getf settings
                  :http-idle-timeout-ms)))
    (unless (getf result
                  :websocket-connect-timeout-ms)
      (setf
       (getf result
             :websocket-connect-timeout-ms)
       (getf settings
             :websocket-connect-timeout-ms)))
    (unless (getf result :retry)
      (setf (getf result :retry)
            (getf settings :retry)))
    result))

(defun edit-in-external-editor (content runner)
  (uiop:with-temporary-file
      (:pathname path
       :stream stream
       :direction :output
       :external-format :utf-8
       :keep t)
    (write-string content stream)
    (finish-output stream)
    (close stream)
    (sb-posix:chmod path #o600)
    (unwind-protect
         (if (zerop (funcall runner path))
             (uiop:read-file-string
              path :external-format :utf-8)
             content)
      (when (probe-file path)
        (delete-file path)))))
