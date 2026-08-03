(in-package #:cadr-ai)

(defparameter +openai-device-slow-down-timeout-message+
  "Device flow timed out after one or more slow_down responses. This is often caused by clock drift in WSL or VM environments. Please sync or restart the VM clock and try again.")

(defun oauth-response-json-copy (object)
  (if (and (hash-table-p object)
           (plusp (hash-table-count object)))
      (stringify-json object)
      ""))

(defun openai-device-interval-seconds (response)
  (let* ((raw (json-get response "interval"))
         (value
           (cond
             ((numberp raw) raw)
             ((stringp raw)
              (parse-coercible-number
               (string-trim '(#\Space #\Tab) raw)
               nil))
             (t nil))))
    (unless
        (and
         (realp value)
         (not (minusp value))
         (or
          (not (floatp value))
          (and
           (not (sb-ext:float-infinity-p value))
           (not (sb-ext:float-nan-p value)))))
      (error 'authentication-error
             :message
             (format
              nil "Invalid OpenAI Codex device code response: ~A"
              (stringify-json response))))
    value))

(defun start-openai-codex-device-authorization ()
  (multiple-value-bind (response status)
      (oauth-flow-post-json
       +openai-device-user-code-url+
       (json-object "client_id" +openai-oauth-client-id+))
    (unless (<= 200 status 299)
      (when (= status 404)
        (error
         'authentication-error
         :message
         "OpenAI Codex device code login is not enabled for this server. Use browser login or verify the server URL."))
      (let ((body (oauth-response-json-copy response)))
        (error
         'authentication-error
         :message
         (format
          nil "OpenAI Codex device code request failed with status ~D~A"
          status
          (if (plusp (length body))
              (format nil ": ~A" body)
              "")))))
    (let ((device-auth-id (json-get response "device_auth_id"))
          (user-code (json-get response "user_code"))
          (interval (openai-device-interval-seconds response)))
      (unless (and (non-empty-string-p device-auth-id)
                   (non-empty-string-p user-code))
        (error
         'authentication-error
         :message
         (format
          nil "Invalid OpenAI Codex device code response: ~A"
          (stringify-json response))))
      (list
       :device-auth-id device-auth-id
       :user-code user-code
       :verification-uri +openai-device-verification-uri+
       :interval interval
       :expires-in +openai-device-code-timeout-seconds+))))

(defun poll-openai-codex-device-authorization (device cancelled-p)
  (poll-device-authorization
   (lambda ()
     (multiple-value-bind (response status)
         (oauth-flow-post-json
          +openai-device-token-url+
          (json-object
           "device_auth_id" (getf device :device-auth-id)
           "user_code" (getf device :user-code)))
       (cond
         ((<= 200 status 299)
          (let ((authorization-code
                  (json-get response "authorization_code"))
                (code-verifier
                  (json-get response "code_verifier")))
            (if (and (non-empty-string-p authorization-code)
                     (non-empty-string-p code-verifier))
                (list
                 :status :complete
                 :value
                 (list
                  :authorization-code authorization-code
                  :code-verifier code-verifier))
                (list
                 :status :failed
                 :message
                 (format
                  nil
                  "Invalid OpenAI Codex device auth token response: ~A"
                  (stringify-json response))))))
         ((member status '(403 404))
          (list :status :pending))
         (t
          (let* ((error-value (json-get response "error"))
                 (error-code
                   (if (hash-table-p error-value)
                       (json-get error-value "code")
                       error-value)))
            (cond
              ((and (stringp error-code)
                    (string=
                     error-code
                     "deviceauth_authorization_pending"))
               (list :status :pending))
              ((and (stringp error-code)
                    (string= error-code "slow_down"))
               (list :status :slow-down))
              (t
               (let ((body (oauth-response-json-copy response)))
                 (list
                  :status :failed
                  :message
                  (format
                   nil
                   "OpenAI Codex device auth failed with status ~D~A"
                   status
                   (if (plusp (length body))
                       (format nil ": ~A" body)
                       "")))))))))))
   :interval (getf device :interval)
   :expires-in +openai-device-code-timeout-seconds+
   :cancelled-p cancelled-p
   :timeout-message "Device flow timed out"
   :slow-down-timeout-message
   +openai-device-slow-down-timeout-message+
   :sleep-function *oauth-flow-sleep-function*))

(defun login-openai-codex-device-oauth (interaction)
  (let ((cancelled-p
          (lambda ()
            (runtime-auth-interaction-aborted-p interaction))))
    (handler-case
        (let ((*native-http-abort-p* cancelled-p))
          (when (funcall cancelled-p)
            (signal-device-authorization-cancelled))
          (let ((device
                  (start-openai-codex-device-authorization)))
            (notify-device-authorization interaction device)
            (let ((authorization
                    (poll-openai-codex-device-authorization
                     device cancelled-p)))
              (exchange-openai-authorization-code
               (getf authorization :authorization-code)
               (getf authorization :code-verifier)
               +openai-device-redirect-uri+))))
      (request-aborted ()
        (signal-device-authorization-cancelled)))))

;;; Existing OAuth flows adapted to the runtime interaction contract.

(defun login-openai-runtime-oauth (interaction)
  (let ((method
          (runtime-auth-interaction-prompt
           interaction
           '(:type :select
             :message "Select OpenAI Codex login method:"
             :options
             ((:id "browser" :label "Browser login (default)")
              (:id "device_code"
               :label "Device code login (headless)"))))))
    (cond
      ((string= method "device_code")
       (login-openai-codex-device-oauth interaction))
      ((string= method "browser")
       (login-openai-oauth
        nil
        :auth-url-function
        (lambda (url)
          (runtime-auth-interaction-notify
           interaction
           (list :type :auth-url :url url
                 :instructions
                 (oauth-provider-metadata-auth-url-instructions
                  +openai-codex-oauth-metadata+))))
        :auth-prompt-function
        (lambda (prompt)
          (runtime-auth-interaction-prompt interaction prompt))))
      (t
       (error 'authentication-error
              :message
              (format nil
                      "Unknown OpenAI Codex login method: ~A"
                      method))))))
