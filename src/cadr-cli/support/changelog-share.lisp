(in-package #:cadr-cli)

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
