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