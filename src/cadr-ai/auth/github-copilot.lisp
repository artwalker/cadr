(in-package #:cadr-ai)

(defun parse-github-device-authorization (object)
  (let ((verification
          (required-oauth-string
           object "verification_uri" "GitHub")))
    (unless (trusted-oauth-url-p verification)
      (error 'authentication-error
             :message
             "Untrusted verification_uri in device code response"))
    (list
     :device-code
     (required-oauth-string object "device_code" "GitHub")
     :user-code
     (required-oauth-string object "user_code" "GitHub")
     :verification-uri verification
     :interval
     (let ((value (json-get object "interval")))
       (and (numberp value) value))
     :expires-in
     (positive-oauth-number object "expires_in" "GitHub"))))

(defun github-copilot-base-url (token &optional enterprise-domain)
  (let* ((marker "proxy-ep=")
         (start (and token (search marker token)))
         (host
           (and start
                (let* ((value-start (+ start (length marker)))
                       (end (or (position #\; token
                                          :start value-start)
                                (length token))))
                  (subseq token value-start end)))))
    (cond
      ((non-empty-string-p host)
       (format nil "https://~A"
               (if (uiop:string-prefix-p "proxy." host)
                   (concatenate
                    'string "api."
                    (subseq host (length "proxy.")))
                   host)))
      ((non-empty-string-p enterprise-domain)
       (format nil "https://copilot-api.~A"
               enterprise-domain))
      (t
       "https://api.individual.githubcopilot.com"))))

(defun selectable-github-copilot-model-ids (response)
  (let ((data (json-get response "data")))
    (unless (vectorp data)
      (error 'authentication-error
             :message "Invalid Copilot models response"))
    (loop for item across data
          for policy = (json-get item "policy")
          for capabilities = (json-get item "capabilities")
          for supports = (json-get capabilities "supports")
          when
          (and
           (stringp (json-get item "id"))
           (eq t (json-get item "model_picker_enabled"))
           (not
            (string= "disabled"
                     (or (json-get policy "state") "")))
           (not
            (eq nil
                (json-get supports "tool_calls" t))))
            collect (json-get item "id"))))
