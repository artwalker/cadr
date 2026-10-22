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

(defvar *openrouter-http-request-function* nil)

(defun openrouter-per-million (text fallback)
  (let ((parsed
          (and (stringp text)
               (plusp (length text))
               (ignore-errors
                 (let ((*read-eval* nil)
                       (*read-default-float-format* 'double-float))
                   (read-from-string text))))))
    (if (and (realp parsed) (>= parsed 0))
        (let ((scaled
                (* (coerce parsed 'double-float) 1000000d0)))
          (/ (round (* scaled 1000000d0)) 1000000d0))
        (coerce fallback 'double-float))))

(defun openrouter-positive-limit (value)
  (and (realp value)
       (plusp value)
       (round value)))

(defun openrouter-entry-context (entry fallback)
  (or (openrouter-positive-limit
       (json-get
        (json-get entry "top_provider")
        "context_length"))
      (openrouter-positive-limit
       (json-get entry "context_length"))
      fallback))

(defun openrouter-entry-max-tokens (entry fallback)
  (or (openrouter-positive-limit
       (json-get
        (json-get entry "top_provider")
        "max_completion_tokens"))
      fallback))

(defun apply-openrouter-pricing (metadata pricing)
  (let ((input
          (openrouter-per-million
           (json-get pricing "prompt") 0))
        (output
          (openrouter-per-million
           (json-get pricing "completion") 0))
        (cache-read
          (openrouter-per-million
           (json-get pricing "input_cache_read") 0))
        (cache-write
          (openrouter-per-million
           (json-get pricing "input_cache_write") 0))
        (tiers nil))
    (when (vectorp (json-get pricing "overrides"))
      (loop for override across (json-get pricing "overrides")
            when (and (hash-table-p override)
                      (json-present-p override "min_prompt_tokens")
                      (not (json-present-p override "utc_start"))
                      (not (json-present-p override "utc_end"))
                      (not (json-present-p override "utc_days"))
                      (realp (json-get override "min_prompt_tokens")))
              do (push
                  (make-model-cost-tier
                   :input-tokens-above
                   (round (json-get override "min_prompt_tokens"))
                   :input-price
                   (openrouter-per-million
                    (json-get override "prompt") input)
                   :output-price
                   (openrouter-per-million
                    (json-get override "completion") output)
                   :cache-read-price
                   (openrouter-per-million
                    (json-get override "input_cache_read") cache-read)
                   :cache-write-price
                   (openrouter-per-million
                    (json-get override "input_cache_write") cache-write))
                  tiers)))
    (setf (model-metadata-input-price metadata) input
          (model-metadata-output-price metadata) output
          (model-metadata-cache-read-price metadata) cache-read
          (model-metadata-cache-write-price metadata) cache-write
          (model-metadata-cost-tiers metadata) (nreverse tiers)))
  metadata)

(defun personalize-openrouter-metadata (metadata entry)
  (let ((copy (copy-model-metadata metadata)))
    (setf (model-metadata-context-window copy)
          (openrouter-entry-context
           entry (model-metadata-context-window metadata))
          (model-metadata-max-output-tokens copy)
          (openrouter-entry-max-tokens
           entry (model-metadata-max-output-tokens metadata)))
    (when (hash-table-p (json-get entry "pricing"))
      (apply-openrouter-pricing
       copy (json-get entry "pricing")))
    copy))

(defun personalize-openrouter-catalog (catalog status body)
  ;; pi@4a080252f openrouter.ts personalizeOpenRouterCatalog #10672.
  (when (member status '(401 403 404))
    (return-from personalize-openrouter-catalog catalog))
  (unless (and (integerp status) (<= 200 status 299))
    (error 'configuration-error
           :message
           (format nil
                   "OpenRouter model list request failed: ~A"
                   status)))
  (let ((data
          (and (hash-table-p body)
               (json-get body "data"))))
    (unless (and (vectorp data) (not (stringp data)))
      (error 'configuration-error
             :message "Invalid OpenRouter model list response"))
    (let ((allowed (make-hash-table :test #'equal)))
      (loop for entry across data
            for id = (and (hash-table-p entry)
                          (json-get entry "id"))
            when (stringp id)
              do (setf (gethash id allowed) entry))
      (loop for item in catalog
            for entry = (and (typep item 'model-metadata)
                             (gethash
                              (model-metadata-id item)
                              allowed))
            when (or (not (typep item 'model-metadata)) entry)
              collect (if (typep item 'model-metadata)
                          (personalize-openrouter-metadata item entry)
                          item)))))

(defun openrouter-credential-key (credential)
  (cond
    ((typep credential 'oauth-credential)
     (let ((access (oauth-credential-access credential)))
       (and (non-empty-string-p access) access)))
    ((typep credential 'api-key-credential)
     (let ((key (api-key-credential-key credential)))
       (and (non-empty-string-p key) key)))
    (t nil)))

(defun install-openrouter-metadata-overlay (metadata)
  (let ((table (make-hash-table :test #'equal)))
    (dolist (item metadata)
      (setf (gethash (model-metadata-id item) table) item))
    (setf *openrouter-metadata-overlay* table)))

(defun openrouter-stored-metadata-p (value)
  (and (consp value)
       (every
        (lambda (item)
          (and (typep item 'model-metadata)
               (eq :openrouter (model-metadata-provider item))))
        value)))

(defun fetch-openrouter-user-models (base-url key)
  (funcall
   (or *openrouter-http-request-function*
       #'native-http-request)
   (concatenate
    'string
    (strip-trailing-slash base-url)
    "/models/user")
   :method :get
   :headers
   `(("accept" . "application/json")
     ("authorization" . ,(format nil "Bearer ~A" key)))
   :connect-timeout 15
   :read-timeout 15
   :force-string t))
