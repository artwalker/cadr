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
  (account-id nil :type (or null string))
  ;; Provider-owned fields from the baseline OAuthCredential index signature.
  ;; Keys are JSON field names; values must be JSON-serializable.
  (metadata nil :type list))

(cadr-core:define-redacted-print-object
    (api-key-credential value stream)
  (format stream ":provider ~A :key [REDACTED]"
          (api-key-credential-provider value)))

(cadr-core:define-redacted-print-object
    (oauth-credential value stream)
  (format stream ":provider ~A :access [REDACTED] :refresh [REDACTED]"
          (oauth-credential-provider value)))

(defparameter +oauth-reserved-credential-keys+
  '("type" "access" "refresh" "expires" "accountId"))

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
  (when (json-object-p object)
    (sort
     (let ((entries nil))
       (json-map-entries
        object
        (lambda (key value)
          (push (cons key value) entries)))
       entries)
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
       (dolist (entry (oauth-credential-metadata credential))
         (unless (member (car entry)
                         +oauth-reserved-credential-keys+
                         :test #'string=)
           (json-put object (car entry) (cdr entry))))
       object))))

(defun json-credential (provider object)
  (when (json-object-p object)
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
          :account-id (json-get object "accountId")
          :metadata
          (remove-if
           (lambda (entry)
             (member (car entry)
                     +oauth-reserved-credential-keys+
                     :test #'string=))
           (json-object-alist object))))
        (t nil)))))

(defun read-auth-object (path)
  (if (probe-file path)
      (handler-case
          (let ((object
                  (parse-json
                   (uiop:read-file-string path
                                          :external-format :utf-8))))
            (unless (json-object-p object)
              (error 'authentication-error
                     :message "auth.json must contain a JSON object"))
            (json-as-hash-table object))
        (cadr-error (condition)
          (error condition))
        (error (cause)
          (error 'authentication-error
                 :message (format nil "Cannot read auth.json: ~A" cause)
                 :cause cause)))
      (json-object)))

(defun write-auth-object (path object)
  (cadr-core:call-with-atomic-output-file
   path
   (lambda (stream)
     (write-string (stringify-json object) stream)
     (terpri stream))
   :mode #o600
   :durability :flush)
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
