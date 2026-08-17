(in-package #:cadr-ai)

(defun device-authorization-cancelled-p (cancelled-p)
  (and cancelled-p
       (not (null (ignore-errors (funcall cancelled-p))))))

(defun signal-device-authorization-cancelled ()
  (error 'authentication-cancelled :message "Login cancelled"))

(defun sleep-for-device-authorization
    (seconds sleep-function cancelled-p)
  (if (and cancelled-p
           (eq sleep-function (symbol-function 'sleep)))
      (loop with remaining = seconds
            while (plusp remaining)
            do
            (when (device-authorization-cancelled-p cancelled-p)
              (signal-device-authorization-cancelled))
            (let ((slice (min remaining 0.05d0)))
              (sleep slice)
              (decf remaining slice)))
      (funcall sleep-function seconds))
  (when (device-authorization-cancelled-p cancelled-p)
    (signal-device-authorization-cancelled)))

(defun poll-device-authorization
    (poll &key (interval 5) (expires-in 900)
                 wait-before-first-poll-p
                 cancelled-p
                 (timeout-message "Device authorization expired")
                 slow-down-timeout-message
                 (sleep-function #'sleep)
                 (time-function #'get-universal-time))
  (unless (and (numberp interval)
               (not (minusp interval))
               (numberp expires-in)
               (plusp expires-in))
    (error 'configuration-error
           :message
           "Device authorization interval must be non-negative and expiry must be positive"))
  (let ((started-at (funcall time-function))
        (next-interval (max 1 interval))
        (first-p t)
        (slow-down-count 0))
    (loop
      (when (device-authorization-cancelled-p cancelled-p)
        (signal-device-authorization-cancelled))
      (when (>= (- (funcall time-function) started-at)
                expires-in)
        (error 'authentication-error
               :message
               (if (and slow-down-timeout-message
                        (plusp slow-down-count))
                   slow-down-timeout-message
                   timeout-message)))
      (when (or (not first-p) wait-before-first-poll-p)
        (sleep-for-device-authorization
         next-interval sleep-function cancelled-p))
      (setf first-p nil)
      (let* ((result (funcall poll))
             (status (getf result :status)))
        (case status
          (:complete
           (return (getf result :value)))
          (:pending
           (setf next-interval (max 1 interval)))
          (:slow-down
           (incf slow-down-count)
           (setf next-interval
                 (let ((server-interval
                         (getf result :interval)))
                   (if (and (numberp server-interval)
                            (plusp server-interval))
                       (max 1 server-interval)
                       (+ next-interval 5)))))
          (:failed
           (error 'authentication-error
                  :message
                  (or (getf result :message)
                      "Device authorization failed")))
          (:expired
           (error 'authentication-error
                  :message "Device authorization expired"))
          (:denied
           (error 'authentication-error
                  :message "Device authorization denied"))
          (:cancelled
           (signal-device-authorization-cancelled))
          (otherwise
           (error 'authentication-error
                  :message
                  (format nil
                          "Unexpected device authorization state: ~A"
                          status))))))))

(defun trusted-oauth-url-p (value &key https-only-p)
  (and
   (non-empty-string-p value)
   (or (uiop:string-prefix-p "https://" value)
       (and (not https-only-p)
            (uiop:string-prefix-p "http://" value)))
   (handler-case
       (progn (parse-http-url value) t)
     (error () nil))))

(defun required-oauth-string (object field provider)
  (let ((value (json-get object field)))
    (unless (non-empty-string-p value)
      (error 'authentication-error
             :message
             (format nil
                     "Invalid ~A OAuth response field: ~A"
                     provider field)))
    value))

(defun positive-oauth-number (object field provider)
  (let ((value (json-get object field)))
    (unless (and (numberp value) (plusp value))
      (error 'authentication-error
             :message
             (format nil
                     "Invalid ~A OAuth response field: ~A"
                     provider field)))
    value))

(defun device-authorization-interval
    (object policy &optional default)
  (let ((value (json-get object "interval")))
    (ecase policy
      (:positive
       (and (numberp value) (plusp value) value))
      (:number
       (and (numberp value) value))
      (:or-default
       (or value default))
      (:positive-or-default
       (if (and (numberp value) (plusp value))
           value
           default)))))

(defun parse-device-authorization
    (object provider
     &key https-only-p
       (complete :omit)
       (interval-policy :positive)
       default-interval
       default-expires-in
       untrusted-message)
  ;; One parse for xAI / Kimi / GitHub / Radius. Keyword options
  ;; keep the four wire contracts; they do not re-copy the field
  ;; walk.
  (let* ((verification
           (required-oauth-string
            object "verification_uri" provider))
         (complete-value
           (ecase complete
             (:omit nil)
             (:optional
              (json-get object "verification_uri_complete"))
             (:required
              (required-oauth-string
               object "verification_uri_complete" provider))))
         (message
           (or untrusted-message
               (format nil
                       "Untrusted verification URI in ~A OAuth response"
                       provider))))
    (unless (trusted-oauth-url-p verification
                                 :https-only-p https-only-p)
      (error 'authentication-error :message message))
    (when (and complete-value
               (not (trusted-oauth-url-p
                     complete-value
                     :https-only-p https-only-p)))
      (error 'authentication-error :message message))
    (list
     :device-code
     (required-oauth-string object "device_code" provider)
     :user-code
     (required-oauth-string object "user_code" provider)
     :verification-uri verification
     :verification-uri-complete complete-value
     :interval
     (device-authorization-interval
      object interval-policy default-interval)
     :expires-in
     (if default-expires-in
         (let ((expires (json-get object "expires_in")))
           (if (and (numberp expires) (plusp expires))
               expires
               default-expires-in))
         (positive-oauth-number
          object "expires_in" provider)))))

(defun parse-xai-device-authorization (object)
  (parse-device-authorization
   object "xAI"
   :https-only-p t
   :complete :optional
   :interval-policy :positive
   :untrusted-message
   "Untrusted verification URI in xAI OAuth response"))

(defun oauth-token-credential
    (provider object
     &key previous-refresh-token
       (default-expires-in 3600)
       (expiry-skew-milliseconds 0))
  (let* ((access
           (required-oauth-string
            object "access_token" provider))
         (refresh
           (or (and (not (json-present-p object "refresh_token"))
                    previous-refresh-token)
               (required-oauth-string
                object "refresh_token" provider)))
         (expires-in
           (if (json-present-p object "expires_in")
               (positive-oauth-number
                object "expires_in" provider)
               default-expires-in)))
    (make-oauth-credential
     :provider provider
     :access access
     :refresh refresh
     :expires
     (- (+ (unix-milliseconds)
           (round (* expires-in 1000)))
        expiry-skew-milliseconds))))

(defun parse-kimi-device-authorization (object)
  (parse-device-authorization
   object "Kimi Code"
   :complete :required
   :interval-policy :positive-or-default
   :default-interval 5
   :default-expires-in 900
   :untrusted-message
   "Invalid Kimi Code device authorization response"))
