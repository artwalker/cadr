(in-package #:cadr-ai)

(defparameter +openrouter-oauth-metadata+
  (make-oauth-provider-metadata
   :provider-name "OpenRouter"
   :method-name "OpenRouter OAuth"
   :login-label "Sign in with OpenRouter"
   :auth-url-instructions
   "Complete sign-in in your browser. If the browser is on another machine, paste the final redirect URL here."
   :manual-input-message
   "Complete sign-in in your browser, or paste the authorization code / redirect URL here:"))

(defparameter +openrouter-authorize-url+ "https://openrouter.ai/auth")
(defparameter +openrouter-token-url+ "https://openrouter.ai/api/v1/auth/keys")

(defun parse-openrouter-authorization-input (input)
  (let* ((trimmed
           (string-trim '(#\Space #\Tab #\Return #\Newline) input))
         (question (position #\? trimmed))
         (query
           (cond
             (question (subseq trimmed (1+ question)))
             ((search "code=" trimmed) trimmed)
             (t nil))))
    (if query
        (gethash "code" (parse-query query))
        (and (non-empty-string-p trimmed) trimmed))))

(defun openrouter-exchange-code (code verifier)
  (multiple-value-bind (response status)
      (oauth-flow-post-json
       +openrouter-token-url+
       (json-object
        "code" code
        "code_verifier" verifier
        "code_challenge_method" "S256"))
    (ensure-oauth-response-success "OpenRouter" "key exchange"
                                   response status)
    (make-oauth-credential
     :provider :openrouter
     :access (required-oauth-string response "key" "OpenRouter")
     :refresh ""
     :expires most-positive-fixnum)))

(defun login-openrouter-oauth (interaction)
  (multiple-value-bind (verifier challenge) (generate-pkce)
    (let* ((callback
             (format nil "http://127.0.0.1:1457/oauth/callback/~A"
                     (oauth-state)))
           (url
             (format nil "~A?~A"
                     +openrouter-authorize-url+
                     (form-encode
                      `(("callback_url" . ,callback)
                        ("code_challenge" . ,challenge)
                        ("code_challenge_method" . "S256"))))))
      (runtime-auth-interaction-notify
       interaction
       (list :type :auth-url :url url
             :instructions
             (oauth-provider-metadata-auth-url-instructions
              +openrouter-oauth-metadata+)))
      (let ((code
              (parse-openrouter-authorization-input
               (runtime-auth-interaction-prompt
                interaction
                (list
                 :type :manual-code
                 :title
                 (oauth-login-title +openrouter-oauth-metadata+)
                 :url url
                 :instructions
                 (oauth-provider-metadata-auth-url-instructions
                  +openrouter-oauth-metadata+)
                 :message
                 (oauth-provider-metadata-manual-input-message
                  +openrouter-oauth-metadata+)
                 :placeholder callback)))))
        (unless code
          (error 'authentication-error
                 :message "Missing authorization code"))
        (runtime-auth-interaction-notify
         interaction
         '(:type :progress
           :message "Exchanging authorization code for an API key..."))
        (openrouter-exchange-code code verifier)))))

(defun refresh-openrouter-oauth-credential (credential)
  credential)
