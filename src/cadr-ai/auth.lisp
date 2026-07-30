(in-package #:cadr-ai)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defstruct api-key-credential
  (provider nil :type symbol)
  (key "" :type string)
  (environment nil :type list))

(defstruct oauth-credential
  (provider nil :type symbol)
  (access "" :type string)
  (refresh "" :type string)
  (expires 0 :type integer)
  (account-id nil :type (or null string)))

(defparameter *provider-auth-locks* (make-hash-table))
(defparameter *provider-auth-locks-lock*
  (sb-thread:make-mutex :name "cadr-ai provider auth lock table"))

(defun alist-json-object (entries)
  (let ((object (json-object)))
    (dolist (entry entries object)
      (json-put object
                (string (car entry))
                (cdr entry)))))

(defun json-object-alist (object)
  (when (hash-table-p object)
    (sort
     (loop for key being the hash-keys of object
           using (hash-value value)
           collect (cons key value))
     #'string<
     :key #'car)))

(defun provider-auth-lock (provider)
  (sb-thread:with-mutex (*provider-auth-locks-lock*)
    (or (gethash provider *provider-auth-locks*)
        (setf (gethash provider *provider-auth-locks*)
              (sb-thread:make-mutex
               :name (format nil "cadr-ai auth ~A" provider))))))

(defun auth-file-mode (path)
  (logand #o777 (sb-posix:stat-mode (sb-posix:stat path))))

(defun credential-json (credential)
  (etypecase credential
    (api-key-credential
     (let ((object
             (json-object
              "type" "api_key"
              "key" (api-key-credential-key credential))))
       (when (api-key-credential-environment credential)
         (json-put
          object "env"
          (alist-json-object
           (api-key-credential-environment credential))))
       object))
    (oauth-credential
     (let ((object
             (json-object
              "type" "oauth"
              "access" (oauth-credential-access credential)
              "refresh" (oauth-credential-refresh credential)
              "expires" (oauth-credential-expires credential))))
       (when (oauth-credential-account-id credential)
         (json-put object "accountId"
                   (oauth-credential-account-id credential)))
       object))))

(defun json-credential (provider object)
  (when (hash-table-p object)
    (let ((type (json-get object "type")))
      (cond
        ((string= type "api_key")
         (make-api-key-credential
          :provider provider
          :key (or (json-get object "key") "")
          :environment
          (json-object-alist (json-get object "env"))))
        ((string= type "oauth")
         (make-oauth-credential
          :provider provider
          :access (or (json-get object "access") "")
          :refresh (or (json-get object "refresh") "")
          :expires (or (json-get object "expires") 0)
          :account-id (json-get object "accountId")))
        (t nil)))))

(defun read-auth-object (path)
  (if (probe-file path)
      (handler-case
          (let ((object
                  (parse-json
                   (uiop:read-file-string path
                                          :external-format :utf-8))))
            (unless (hash-table-p object)
              (error 'authentication-error
                     :message "auth.json must contain a JSON object"))
            object)
        (cadr-error (condition)
          (error condition))
        (error (cause)
          (error 'authentication-error
                 :message (format nil "Cannot read auth.json: ~A" cause)
                 :cause cause)))
      (json-object)))

(defun auth-temp-path (path)
  (make-pathname
   :name
   (format nil ".~A.~D.~D"
           (or (pathname-name path) "auth")
           (sb-posix:getpid)
           (random 1000000000))
   :type "tmp"
   :defaults path))

(defun write-auth-object (path object)
  (ensure-directories-exist path)
  (let ((temporary (auth-temp-path path)))
    (unwind-protect
         (progn
           (with-open-file
               (stream temporary
                       :direction :output
                       :if-exists :error
                       :if-does-not-exist :create
                       :external-format :utf-8)
             (write-string (stringify-json object) stream)
             (terpri stream)
             (finish-output stream))
           (sb-posix:chmod temporary #o600)
           (uiop:rename-file-overwriting-target temporary path)
           (sb-posix:chmod path #o600))
      (when (probe-file temporary)
        (delete-file temporary))))
  path)

(defun read-auth-credential (path provider)
  (json-credential
   provider
   (json-get (read-auth-object path)
             (string-downcase (symbol-name provider)))))

(defun write-auth-credential (path credential)
  (let* ((provider
           (etypecase credential
             (api-key-credential
              (api-key-credential-provider credential))
             (oauth-credential
              (oauth-credential-provider credential))))
         (object (read-auth-object path)))
    (json-put object
              (string-downcase (symbol-name provider))
              (credential-json credential))
    (write-auth-object path object))
  credential)

(defun delete-auth-credential (path provider)
  (when (probe-file path)
    (let ((object (read-auth-object path)))
      (remhash (string-downcase (symbol-name provider)) object)
      (write-auth-object path object)))
  nil)

(defun resolve-oauth-credential
    (path provider refresh-function
     &key (minimum-validity-milliseconds 300000))
  (sb-thread:with-mutex ((provider-auth-lock provider))
    (let ((credential (read-auth-credential path provider)))
      (unless (typep credential 'oauth-credential)
        (error 'authentication-error
               :message
               (format nil "No OAuth credential stored for ~A" provider)))
      (when (<= (oauth-credential-expires credential)
                (+ (unix-milliseconds)
                   minimum-validity-milliseconds))
        (handler-case
            (let ((refreshed (funcall refresh-function credential)))
              (unless (typep refreshed 'oauth-credential)
                (error 'authentication-error
                       :message "OAuth refresh returned an invalid credential"))
              (write-auth-credential path refreshed)
              (setf credential refreshed))
          (error (cause)
            (let ((message
                    (redact-secrets
                     (princ-to-string cause)
                     (list
                      (oauth-credential-access credential)
                      (oauth-credential-refresh credential)))))
              (error 'authentication-error
                     :message
                     (format nil "OAuth refresh failed for ~A: ~A"
                             provider message)
                     :cause cause)))))
      credential)))
