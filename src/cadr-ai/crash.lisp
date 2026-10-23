(in-package #:cadr-ai)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defvar *handling-fatal-condition-p* nil)

(defvar *fatal-session-file* nil
  "Namestring of the file-backed session, or NIL when uncaughtCrash has no sessionFile.")

(defstruct fatal-condition-report
  program-name
  type-name
  error-name
  user-message
  frames
  extension-hint
  session-file
  log-path)

(defparameter +credential-environment-names+
  '("ANTHROPIC_AUTH_TOKEN"
    "ANTHROPIC_OAUTH_TOKEN"
    "AWS_ACCESS_KEY_ID"
    "AWS_BEARER_TOKEN_BEDROCK"
    "AWS_SECRET_ACCESS_KEY"
    "AWS_SESSION_TOKEN"
    "GOOGLE_CLOUD_API_KEY"
    "RADIUS_API_KEY"))

(defun command-line-api-key-secrets (arguments)
  (loop for tail on arguments
        for argument = (first tail)
        append
        (cond
          ((and (string= argument "--api-key")
                (second tail))
           (list (second tail)))
          ((uiop:string-prefix-p "--api-key=" argument)
           (list (subseq argument (length "--api-key="))))
          (t nil))))

(defun auth-object-secrets (path)
  (when (probe-file path)
    (handler-case
        (let ((secrets nil))
          (maphash
           (lambda (provider object)
             (declare (ignore provider))
             (when (hash-table-p object)
               (dolist (field '("key" "access" "refresh" "token"
                                "client_secret"))
                 (let ((value (json-get object field)))
                   (when (non-empty-string-p value)
                     (push value secrets))))))
           (read-auth-object path))
          secrets)
      (condition () nil))))

(defun runtime-known-secrets
    (&key
       (arguments (uiop:command-line-arguments))
       (auth-path
         (cadr-core:agent-auth-path))
       extra-secrets)
  (remove-duplicates
   (remove-if-not
    #'non-empty-string-p
    (append
     extra-secrets
     (command-line-api-key-secrets arguments)
     (auth-object-secrets auth-path)
     (loop for definition in (list-provider-definitions)
           for name =
             (provider-definition-key-environment definition)
           when name collect (uiop:getenv name))
     (loop for name in +credential-environment-names+
           collect (uiop:getenv name))))
   :test #'string=))

(defun default-crash-directory ()
  (cadr-core:agent-crash-directory))

(defun crash-log-path (directory program-name nonce)
  (merge-pathnames
   (format nil "~A-crash-~D-~D-~D.log"
           program-name
           (get-universal-time)
           (sb-posix:getpid)
           nonce)
   directory))

(defun write-private-crash-log (directory program-name diagnostic)
  (let ((directory
          (uiop:ensure-directory-pathname directory)))
    (ensure-directories-exist
     (merge-pathnames "anchor" directory))
    (ignore-errors
      (sb-posix:chmod (namestring directory) #o700))
    (loop for nonce from 0 below 1000
          for path = (crash-log-path directory program-name nonce)
          for descriptor =
            (handler-case
                (sb-posix:open
                 (namestring path)
                 (logior sb-posix:o-wronly
                         sb-posix:o-creat
                         sb-posix:o-excl)
                 #o600)
              (condition () nil))
          when descriptor
            do
               (let ((stream
                       (sb-sys:make-fd-stream
                        descriptor
                        :output t
                        :element-type 'character
                        :external-format :utf-8
                        :buffering :full
                        :auto-close t)))
                 (unwind-protect
                      (progn
                        (write-string diagnostic stream)
                        (finish-output stream))
                   (when (open-stream-p stream)
                     (close stream))))
               (return path)
          finally (return nil))))

(defun fatal-condition-type-name (condition)
  (string-upcase
   (princ-to-string (type-of condition))))

;; Node console.error prints error.name. The default is Error. These
;; condition types are the cadr counterparts of the standard Error
;; subclasses; every other condition stays Error.
(defun fatal-terminal-error-name (condition)
  (cond
    ((typep condition 'type-error) "TypeError")
    ((typep condition 'parse-error) "SyntaxError")
    ((or (typep condition 'unbound-variable)
         (typep condition 'undefined-function)
         (typep condition 'unbound-slot))
     "ReferenceError")
    ((typep condition 'arithmetic-error) "RangeError")
    (t "Error")))

(defun fatal-condition-message (condition)
  (cond
    ((typep condition 'cadr-error)
     (or (cadr-error-message condition) ""))
    #+sbcl
    ((typep condition 'sb-sys:interactive-interrupt)
     "Interactive interrupt")
    (t (princ-to-string condition))))

(defun default-fatal-user-message (condition secrets redactor)
  (funcall redactor (fatal-condition-message condition) secrets))

(defun fatal-reporter-frame-p (label)
  (and label
       (some (lambda (marker) (search marker label))
             '("PREPARE-FATAL-CONDITION-REPORT"
               "EMIT-FATAL-CONDITION-REPORT"
               "FATAL-TERMINAL-FRAMES"
               "FATAL-FRAME-"
               "CALL-WITH-FATAL-CONDITION-BOUNDARY"
               "REPORT-FATAL-CONDITION"
               "FATAL-CONDITION-DIAGNOSTIC"
               "FATAL-SOURCE-LINE"))))

(defun fatal-frame-label (name)
  (cond
    ((null name) nil)
    ((symbolp name) (symbol-name name))
    ((stringp name) name)
    (t (princ-to-string name))))

(defun fatal-source-line (file position)
  (when (and (stringp file) (integerp position) (not (minusp position))
             (probe-file file))
    (with-open-file (in file :external-format :utf-8)
      (loop for line-number from 1
            for start = 0 then (1+ end)
            for text = (read-line in nil nil)
            while text
            for end = (+ start (length text))
            when (<= start position end)
              return line-number))))

(defun fatal-frame-location (frame)
  (handler-case
      (let* ((location (sb-di:frame-code-location frame))
             (source (sb-di:code-location-debug-source location))
             (file (sb-di:debug-source-namestring source))
             (starts (sb-di:debug-source-start-positions source))
             (index (sb-di:code-location-toplevel-form-offset location)))
        (when (and (stringp file)
                   (vectorp starts)
                   (integerp index)
                   (<= 0 index (1- (length starts))))
          (let ((line (fatal-source-line file (aref starts index))))
            (when line
              (format nil "~A:~D" file line)))))
    (condition () nil)))

(defun fatal-terminal-frames ()
  (let ((frames nil)
        (count 0))
    (sb-debug:map-backtrace
     (lambda (frame)
       (when (>= count 100)
         (return-from fatal-terminal-frames (nreverse frames)))
       (let ((label
               (fatal-frame-label
                (ignore-errors
                  (sb-di:debug-fun-name
                   (sb-di:frame-debug-fun frame))))))
         (unless (or (null label) (fatal-reporter-frame-p label))
           (incf count)
           (let ((location (fatal-frame-location frame)))
             (push
              (if location
                  (format nil "    at ~A (~A)" label location)
                  (format nil "    at ~A" label))
              frames))))))
    (nreverse frames)))

(defun fatal-crash-report-instructions (program-name session-file)
  (let ((resume
          (if (and (stringp session-file) (plusp (length session-file)))
              (format nil "run `~A -r` to resume the session, then"
                      program-name)
              (format nil "start ~A and" program-name))))
    (format nil
            "To report this crash: ~A run /bug. The crash details are attached automatically."
            resume)))

(defun fatal-condition-diagnostic (condition)
  (with-output-to-string (output)
    (format output "Condition type: ~A~%Condition: ~A~%~%Backtrace:~%"
            (fatal-condition-type-name condition)
            condition)
    #+sbcl
    (sb-debug:print-backtrace :stream output :count 100)))

(defun prepare-fatal-condition-report
    (condition &key
                 (program-name "cadr")
                 (crash-directory (default-crash-directory))
                 secrets
                 (redactor #'redact-secrets)
                 (user-message-function #'default-fatal-user-message)
                 (diagnostic-annotation nil)
                 (exit-function #'uiop:quit))
  (if *handling-fatal-condition-p*
      (funcall exit-function 1)
      (let* ((*handling-fatal-condition-p* t)
             (all-secrets
               (runtime-known-secrets :extra-secrets secrets))
             (diagnostic
               (funcall redactor
                        (fatal-condition-diagnostic condition)
                        all-secrets))
             (path
               (handler-case
                   (write-private-crash-log
                    crash-directory program-name diagnostic)
                 (condition () nil)))
             (message
               (funcall user-message-function
                        condition all-secrets redactor))
             (frames (fatal-terminal-frames))
             (hint
               (when diagnostic-annotation
                 (let ((text
                         (funcall
                          diagnostic-annotation
                          (format nil "Error: ~A~%~{~A~%~}"
                                  message frames))))
                   (when (and (stringp text) (plusp (length text)))
                     text)))))
        (make-fatal-condition-report
         :program-name program-name
         :type-name (fatal-condition-type-name condition)
         :error-name (fatal-terminal-error-name condition)
         :user-message message
         :frames frames
         :extension-hint hint
         :session-file *fatal-session-file*
         :log-path path))))

(defvar *fatal-condition-side-effect* nil
  "Optional (report) callback after a fatal report is prepared for emit.")

(defun emit-fatal-condition-report
    (report &key (exit-function #'uiop:quit))
  (let* ((*handling-fatal-condition-p* t)
         (recorded
           (when *fatal-condition-side-effect*
             (ignore-errors
               (funcall *fatal-condition-side-effect* report)))))
    (format *error-output*
            "~A exiting due to uncaughtException:~%"
            (fatal-condition-report-program-name report))
    (format *error-output* "~A: ~A~%"
            (or (fatal-condition-report-error-name report) "Error")
            (fatal-condition-report-user-message report))
    (dolist (frame (fatal-condition-report-frames report))
      (write-line frame *error-output*))
    (let ((hint (fatal-condition-report-extension-hint report)))
      (when (and (stringp hint) (plusp (length hint)))
        (format *error-output* "~%~A~%" hint)))
    (when recorded
      (format *error-output* "~%~A~%"
              (fatal-crash-report-instructions
               (fatal-condition-report-program-name report)
               (fatal-condition-report-session-file report))))
    (finish-output *error-output*)
    (funcall exit-function 1)))

(defun report-fatal-condition
    (condition &key
                 (program-name "cadr")
                 (crash-directory (default-crash-directory))
                 secrets
                 (redactor #'redact-secrets)
                 (user-message-function #'default-fatal-user-message)
                 (diagnostic-annotation nil)
                 (exit-function #'uiop:quit))
  (emit-fatal-condition-report
   (prepare-fatal-condition-report
    condition
    :program-name program-name
    :crash-directory crash-directory
    :secrets secrets
    :redactor redactor
    :user-message-function user-message-function
    :diagnostic-annotation diagnostic-annotation
    :exit-function exit-function)
   :exit-function exit-function))

(defun dead-terminal-error-p (condition)
  (or (typep condition 'sb-int:broken-pipe)
      (let ((text (princ-to-string condition)))
        (or (search "Input/output error" text)
            (search "Inappropriate ioctl for device" text)
            (search "Transport endpoint is not connected" text)
            (search "Broken pipe" text)))))

(defun call-with-fatal-condition-boundary
    (function &key
                (program-name "cadr")
                (crash-directory (default-crash-directory))
                secrets
                (redactor #'redact-secrets)
                (user-message-function #'default-fatal-user-message)
                (diagnostic-annotation nil)
                (exit-function #'uiop:quit))
  ;; SBCL-only tree. The old #-sbcl branch copied this boundary
  ;; without *invoke-debugger-hook*.
  (let ((fatal-marker (gensym "FATAL-")))
    (labels ((fail (condition)
               (when (dead-terminal-error-p condition)
                 (return-from call-with-fatal-condition-boundary
                   (funcall exit-function 129)))
               (values
                fatal-marker
                (prepare-fatal-condition-report
                 condition
                 :program-name program-name
                 :crash-directory crash-directory
                 :secrets secrets
                 :redactor redactor
                 :user-message-function user-message-function
                 :diagnostic-annotation diagnostic-annotation
                 :exit-function exit-function))))
      (multiple-value-bind (marker values-or-report)
          (block fatal-boundary
            (let ((sb-ext:*invoke-debugger-hook*
                    (lambda (condition previous-hook)
                      (declare (ignore previous-hook))
                      (return-from fatal-boundary
                        (fail condition)))))
              (handler-bind
                  ((serious-condition
                     (lambda (condition)
                       ;; Prepare the redacted diagnostic at the failure site,
                       ;; then unwind terminal cleanup before user output.
                       (return-from fatal-boundary
                         (fail condition)))))
                (values nil
                        (multiple-value-list
                         (funcall function))))))
        (if (eq marker fatal-marker)
            (emit-fatal-condition-report
             values-or-report :exit-function exit-function)
            (values-list values-or-report))))))
