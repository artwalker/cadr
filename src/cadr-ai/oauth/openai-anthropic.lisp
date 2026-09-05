(in-package #:cadr-ai)

(defun oauth-token-request (url pairs secrets)
  (handler-case
      (multiple-value-bind (body status)
          (funcall *oauth-http-request-function*
                   url
                   :method :post
                   :headers
                   '(("content-type"
                      . "application/x-www-form-urlencoded")
                     ("accept" . "application/json"))
                   :content (form-encode pairs)
                   :connect-timeout 10
                   :read-timeout 30
                   :force-string t)
        (unless (<= 200 status 299)
          (error 'authentication-error
                 :message
                 (format nil "OAuth token endpoint returned HTTP ~D"
                         status)))
        (parse-json (normalize-response-body body)))
    (error (cause)
      (if (typep cause 'authentication-error)
          (error cause)
          (error 'authentication-error
                 :message
                 (format nil "OAuth token request failed: ~A"
                         (redact-secrets
                          (princ-to-string cause) secrets))
                 :cause cause)))))

(defun oauth-json-token-request (url object secrets)
  (handler-case
      (multiple-value-bind (body status)
          (funcall *oauth-http-request-function*
                   url
                   :method :post
                   :headers
                   '(("content-type" . "application/json")
                     ("accept" . "application/json"))
                   :content (stringify-json object)
                   :connect-timeout 10
                   :read-timeout 30
                   :force-string t)
        (unless (<= 200 status 299)
          (error 'authentication-error
                 :message
                 (format nil "OAuth token endpoint returned HTTP ~D"
                         status)))
        (parse-json (normalize-response-body body)))
    (error (cause)
      (if (typep cause 'authentication-error)
          (error cause)
          (error 'authentication-error
                 :message
                 (format nil "OAuth token request failed: ~A"
                         (redact-secrets
                          (princ-to-string cause) secrets))
                 :cause cause)))))

(defparameter +base64-url-decode-table+
  (let ((table
          (make-array 256
                      :element-type '(signed-byte 16)
                      :initial-element -1)))
    (loop for index from 0
          for character across +base64-url-alphabet+
          do (setf (aref table (char-code character)) index))
    table))

(defun base64url-value (character)
  (let ((code (char-code character)))
    (when (< code 256)
      (let ((value (aref +base64-url-decode-table+ code)))
        (and (>= value 0) value)))))

(defun base64url-decode (string)
  (let* ((length (length string))
         (capacity (ceiling (* length 3) 4))
         (octets
           (make-array capacity
                       :element-type '(unsigned-byte 8)))
         (out 0))
    (loop for index from 0 below length by 4
          for remaining = (- length index)
          for a = (base64url-value (char string index))
          for b = (and (> remaining 1)
                       (base64url-value (char string (1+ index))))
          for c = (and (> remaining 2)
                       (base64url-value (char string (+ index 2))))
          for d = (and (> remaining 3)
                       (base64url-value (char string (+ index 3))))
          do
          (unless (and a b)
            (error 'authentication-error
                   :message "Invalid base64url token"))
          (let ((bits
                  (logior (ash a 18)
                          (ash b 12)
                          (ash (or c 0) 6)
                          (or d 0))))
            (setf (aref octets out) (ldb (byte 8 16) bits))
            (incf out)
            (when c
              (setf (aref octets out) (ldb (byte 8 8) bits))
              (incf out))
            (when d
              (setf (aref octets out) (ldb (byte 8 0) bits))
              (incf out))))
    (if (= out capacity)
        octets
        (subseq octets 0 out))))

(defun openai-account-id-from-token (token)
  (handler-case
      (let* ((dot1 (position #\. token))
             (dot2
               (and dot1
                    (position #\. token :start (1+ dot1))))
             (dot3
               (and dot2
                    (position #\. token :start (1+ dot2)))))
        (unless (and dot1 dot2 (null dot3)
                     (< (1+ dot1) dot2)
                     (< (1+ dot2) (length token)))
          (return-from openai-account-id-from-token nil))
        (let* ((payload
                 (parse-json
                  (utf8-string
                   (base64url-decode
                    (subseq token (1+ dot1) dot2)))))
               (auth
                 (json-get payload "https://api.openai.com/auth")))
          (json-get auth "chatgpt_account_id")))
    (error ()
      nil)))

(defun token-response-credential (provider response old-refresh)
  (let ((access (json-get response "access_token"))
        (refresh (or (json-get response "refresh_token") old-refresh))
        (expires-in (json-get response "expires_in")))
    (unless (and (non-empty-string-p access)
                 (non-empty-string-p refresh)
                 (numberp expires-in))
      (error 'authentication-error
             :message "OAuth token response is missing required fields"))
    (make-oauth-credential
     :provider provider
     :access access
     :refresh refresh
     :expires (+ (unix-milliseconds)
                 (round (* expires-in 1000)))
     :account-id
     (and (eq provider :openai-codex)
          (openai-account-id-from-token access)))))

(defun exchange-openai-authorization-code
    (code verifier &optional (redirect-uri +openai-oauth-redirect-uri+))
  (token-response-credential
   :openai-codex
   (oauth-token-request
    +openai-oauth-token-url+
    `(("grant_type" . "authorization_code")
      ("client_id" . ,+openai-oauth-client-id+)
      ("code" . ,code)
      ("code_verifier" . ,verifier)
      ("redirect_uri" . ,redirect-uri))
    (list code verifier))
   nil))

(defun refresh-openai-oauth-credential (credential)
  (token-response-credential
   :openai-codex
   (oauth-token-request
    +openai-oauth-token-url+
    `(("grant_type" . "refresh_token")
      ("refresh_token" . ,(oauth-credential-refresh credential))
      ("client_id" . ,+openai-oauth-client-id+))
    (list (oauth-credential-access credential)
          (oauth-credential-refresh credential)))
   (oauth-credential-refresh credential)))

(defun exchange-anthropic-authorization-code
    (code state verifier)
  (token-response-credential
   :anthropic
   (oauth-json-token-request
    +anthropic-oauth-token-url+
    (json-object
     "grant_type" "authorization_code"
     "client_id" +anthropic-oauth-client-id+
     "code" code
     "state" state
     "redirect_uri" +anthropic-oauth-redirect-uri+
     "code_verifier" verifier)
    (list code verifier))
   nil))

(defun refresh-anthropic-oauth-credential (credential)
  (token-response-credential
   :anthropic
   (oauth-json-token-request
    +anthropic-oauth-token-url+
    (json-object
     "grant_type" "refresh_token"
     "client_id" +anthropic-oauth-client-id+
     "refresh_token" (oauth-credential-refresh credential))
    (list (oauth-credential-access credential)
          (oauth-credential-refresh credential)))
   (oauth-credential-refresh credential)))

(defun login-pkce-browser-oauth
    (auth-path
     &key
       (output *standard-output*)
       (open-browser *oauth-browser-open-function*)
       auth-url-function
       auth-prompt-function
       warning
       state-function
       authorization-url
       metadata
       placeholder
       wait
       exchange
       after-credential)
  ;; Shared PKCE + browser + optional manual-code prompt. OpenAI and
  ;; Anthropic only differ in state, URL, wait, and exchange.
  (multiple-value-bind (verifier challenge)
      (generate-pkce)
    (let* ((state (funcall state-function verifier))
           (url (funcall authorization-url challenge state)))
      (when warning
        (format output "~A~%" warning)
        (finish-output output))
      (unless auth-prompt-function
        (present-oauth-auth-url
         url output auth-url-function))
      (handler-case
          (funcall open-browser url)
        (error ()
          (format output
                  "Could not open a browser automatically; use the URL above.~%")
          (finish-output output)))
      (let* ((code
               (if auth-prompt-function
                   (wait-for-oauth-authorization
                    state
                    (lambda (cancelled-p)
                      (funcall wait state cancelled-p))
                    auth-prompt-function
                    (list
                     :type :manual-code
                     :title (oauth-login-title metadata)
                     :url url
                     :instructions
                     (oauth-provider-metadata-auth-url-instructions
                      metadata)
                     :message
                     (oauth-provider-metadata-manual-input-message
                      metadata)
                     :placeholder placeholder))
                   (funcall wait state nil)))
             (credential
               (funcall exchange code state verifier)))
        (when after-credential
          (funcall after-credential credential))
        (when auth-path
          (write-auth-credential auth-path credential))
        credential))))

(defun login-openai-oauth (auth-path
                           &key
                             (output *standard-output*)
                             (open-browser *oauth-browser-open-function*)
                             auth-url-function
                             auth-prompt-function)
  (login-pkce-browser-oauth
   auth-path
   :output output
   :open-browser open-browser
   :auth-url-function auth-url-function
   :auth-prompt-function auth-prompt-function
   :state-function (lambda (verifier)
                     (declare (ignore verifier))
                     (oauth-state))
   :authorization-url #'openai-authorization-url
   :metadata +openai-codex-oauth-metadata+
   :placeholder +openai-oauth-redirect-uri+
   :wait
   (lambda (state cancelled-p)
     (wait-for-openai-oauth-code state cancelled-p))
   :exchange
   (lambda (code state verifier)
     (declare (ignore state))
     (exchange-openai-authorization-code code verifier))
   :after-credential
   (lambda (credential)
     (unless (non-empty-string-p
              (oauth-credential-account-id credential))
       (error 'authentication-error
              :message
              "OpenAI OAuth token does not contain chatgpt_account_id")))))

(defun login-anthropic-oauth
    (auth-path
     &key
       (output *standard-output*)
       (open-browser *oauth-browser-open-function*)
       auth-url-function
       auth-prompt-function)
  ;; This mirrors the fixed reference implementation but remains live-unverified.
  (login-pkce-browser-oauth
   auth-path
   :output output
   :open-browser open-browser
   :auth-url-function auth-url-function
   :auth-prompt-function auth-prompt-function
   :warning
   "Anthropic subscription OAuth is unverified and may violate provider terms."
   :state-function #'identity
   :authorization-url #'anthropic-authorization-url
   :metadata +anthropic-oauth-metadata+
   :placeholder +anthropic-oauth-redirect-uri+
   :wait
   (lambda (state cancelled-p)
     (wait-for-oauth-code
      state 53692 "/callback" "Anthropic" cancelled-p))
   :exchange
   (lambda (code state verifier)
     (exchange-anthropic-authorization-code
      code state verifier))))
