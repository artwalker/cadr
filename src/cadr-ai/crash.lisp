(in-package #:cadr-ai)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defvar *handling-fatal-condition-p* nil)

(defstruct fatal-condition-report
  program-name
  type-name
  user-message
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

(defun default-fatal-user-message (condition secrets redactor)
  (funcall
   redactor
   (cond
     ((typep condition 'cadr-error)
      (cadr-error-message condition))
     #+sbcl
     ((typep condition 'sb-sys:interactive-interrupt)
      "Interactive interrupt")
     (t "Unexpected internal error"))
   secrets))

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
                 (condition () nil))))
        (make-fatal-condition-report
         :program-name program-name
         :type-name (fatal-condition-type-name condition)
         :user-message
         (let ((base
                 (funcall user-message-function
                          condition all-secrets redactor))
               (extra
                 (and diagnostic-annotation
                      (funcall diagnostic-annotation diagnostic))))
           (if (and (stringp extra) (plusp (length extra)))
               (format nil "~A~%~%~A" base extra)
               base))
         :log-path path))))

(defvar *fatal-condition-side-effect* nil
  "Optional (report) callback after a fatal report is prepared for emit.")

(defun emit-fatal-condition-report
    (report &key (exit-function #'uiop:quit))
  (let ((*handling-fatal-condition-p* t))
    (when *fatal-condition-side-effect*
      (ignore-errors
        (funcall *fatal-condition-side-effect* report)))
    (format *error-output*
            "~A exiting due to uncaught ~A: ~A~%"
            (fatal-condition-report-program-name report)
            (fatal-condition-report-type-name report)
            (fatal-condition-report-user-message report))
    (let ((path (fatal-condition-report-log-path report)))
      (if path
          (format *error-output* "Crash log: ~A~%"
                  (namestring path))
          (format *error-output*
                  "Crash log could not be written.~%")))
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
