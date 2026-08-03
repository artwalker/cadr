(in-package #:cadr-cli)

(define-condition credential-print-error (error)
  ((message :initarg :message
            :reader credential-print-error-message))
  (:report
   (lambda (condition stream)
     (write-string
      (credential-print-error-message condition)
      stream))))

(defun parse-duration-milliseconds (value)
  (multiple-value-bind (match groups)
      (cl-ppcre:scan-to-strings
       "^([0-9]+)(ms|s|m|h)?$" value)
    (unless match
      (error 'credential-print-error
             :message
             (format nil "Invalid duration: ~A" value)))
    (* (parse-integer (aref groups 0))
       (cond
         ((string= (aref groups 1) "h") 3600000)
         ((string= (aref groups 1) "m") 60000)
         ((string= (aref groups 1) "s") 1000)
         (t 1)))))

(defun parse-credential-print-command (arguments)
  (unless (and arguments
               (string= (first arguments)
                        "auth"))
    (return-from
        parse-credential-print-command nil))
  (let ((command (second arguments))
        (rest (cddr arguments))
        (kind nil)
        (minimum-expiry nil)
        (forwarded nil))
    (cond
      ((member command
               '("--help" "-h")
               :test #'string=)
       (return-from
           parse-credential-print-command
         (list :help-p t)))
      ((string= command "print-api-key")
       (setf kind :api-key))
      ((string= command "print-bearer-token")
       (setf kind :bearer-token))
      (t
       (error 'credential-print-error
              :message
              (format nil
                      "Unknown auth command: ~A"
                      command))))
    (loop while rest
          for argument = (pop rest)
          do
          (if (string= argument "--min-expiry")
              (progn
                (when (eq kind :api-key)
                  (error
                   'credential-print-error
                   :message
                   "--min-expiry is only supported by print-bearer-token"))
                (unless rest
                  (error
                   'credential-print-error
                   :message
                   "--min-expiry requires a value"))
                (setf minimum-expiry
                      (parse-duration-milliseconds
                       (pop rest))))
              (setf forwarded
                    (append forwarded
                            (list argument)))))
    (list :kind kind
          :arguments forwarded
          :minimum-expiry-ms minimum-expiry)))

(defun credential-for-print
    (storage provider kind
     &key refresh-function
       (minimum-expiry-ms 300000))
  (let ((credential
          (auth-storage-read storage provider)))
    (unless credential
      (error 'credential-print-error
             :message
             (format nil
                     "No credential configured for ~A"
                     provider)))
    (ecase kind
      (:api-key
       (unless
           (typep credential
                  'cadr-ai:api-key-credential)
         (error 'credential-print-error
                :message
                (format nil
                        "~A is configured with OAuth"
                        provider)))
       (cadr-ai:api-key-credential-key
        credential))
      (:bearer-token
       (unless
           (typep credential
                  'cadr-ai:oauth-credential)
         (error 'credential-print-error
                :message
                (format nil
                        "~A is not configured with OAuth"
                        provider)))
       (when
           (<=
            (cadr-ai:oauth-credential-expires
             credential)
            (+ (cadr-ai::unix-milliseconds)
               minimum-expiry-ms))
         (unless refresh-function
           (error 'credential-print-error
                  :message
                  "OAuth credential expires too soon"))
         (setf credential
               (auth-storage-modify
                storage provider
                (lambda (current)
                  (funcall refresh-function
                           current)))))
       (cadr-ai:oauth-credential-access
        credential)))))

(defun print-credential-command-usage
    (&optional
       (stream *standard-output*))
  (format
   stream
   "Usage:~%  cadr auth print-api-key --provider <name> --model <id>~%  cadr auth print-bearer-token --provider <name> --model <id> [--min-expiry <duration>]~%")
  (finish-output stream))

(defun run-credential-print-command
    (arguments
     &key
       (auth-path (default-auth-path))
       (output *standard-output*))
  (let ((parsed
          (parse-credential-print-command
           arguments)))
    (unless parsed
      (return-from
          run-credential-print-command
        (values nil nil)))
    (when (getf parsed :help-p)
      (print-credential-command-usage
       output)
      (return-from
          run-credential-print-command
        (values t 0)))
    (let* ((cli
             (parse-cli-arguments
              (getf parsed :arguments)))
           (model
             (cli-arguments-model cli)))
      (unless
          (and model
               (plusp (length model)))
        (error
         'credential-print-error
         :message
         "Credential printing requires --model"))
      (let* ((model-spec
               (parse-model-spec
                model
                (cli-arguments-provider cli)))
             (provider
               (or
                (getf model-spec :provider)
                (configured-provider-name nil))))
        (unless provider
          (error
           'credential-print-error
           :message
           "Credential printing requires --provider or a provider-qualified --model"))
        (let* ((provider-id
                 (provider-symbol-from-key
                  provider))
               (refresh
                 (and
                  (member
                   provider-id
                   '(:openai-codex :anthropic))
                  (oauth-refresh-function
                   provider-id)))
               (credential
                 (credential-for-print
                  (make-file-auth-storage
                   auth-path)
                  provider
                  (getf parsed :kind)
                  :refresh-function refresh
                  :minimum-expiry-ms
                  (or
                   (getf parsed
                         :minimum-expiry-ms)
                   300000))))
          (format output "~A~%"
                  credential)
          (finish-output output)
          (values t 0))))))
