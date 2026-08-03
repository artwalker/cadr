(in-package #:cadr-ai)

(defun radius-authorization-url
    (endpoint challenge state
     &key
       (redirect-uri
         "http://127.0.0.1:1456/oauth/callback"))
  (format
   nil "~A?~A"
   endpoint
   (form-encode
    `(("response_type" . "code")
      ("client_id" . "pi-gateway")
      ("redirect_uri" . ,redirect-uri)
      ("scope" . "gateway offline_access")
      ("code_challenge" . ,challenge)
      ("code_challenge_method" . "S256")
      ("handoff" . "url")
      ("state" . ,state)))))

(defun materialize-cloudflare-url
    (base-url account-id gateway-id)
  (when (and
         (or (search "{CLOUDFLARE_ACCOUNT_ID}" base-url)
             (search "{accountId}" base-url))
         (not (non-empty-string-p account-id)))
    (error 'configuration-error
           :message "CLOUDFLARE_ACCOUNT_ID is not set"))
  (when (and
         (or (search "{CLOUDFLARE_GATEWAY_ID}" base-url)
             (search "{gatewayId}" base-url))
         (not (non-empty-string-p gateway-id)))
    (error 'configuration-error
           :message "CLOUDFLARE_GATEWAY_ID is not set"))
  (let ((result base-url))
    (dolist (entry
             `(("{CLOUDFLARE_ACCOUNT_ID}" . ,account-id)
               ("{CLOUDFLARE_GATEWAY_ID}" . ,gateway-id)
               ("{accountId}" . ,account-id)
               ("{gatewayId}" . ,gateway-id)))
      (when (cdr entry)
        (setf result
              (replace-all result (car entry) (cdr entry)))))
    result))

(defun radius-required-field (object field predicate)
  (let ((value (json-get object field)))
    (unless (and (json-present-p object field)
                 (funcall predicate value))
      (error 'configuration-error
             :message
             (format nil "Invalid Radius model field: ~A" field)))
    value))

(defun radius-models-from-config (provider config)
  (let ((base-url
          (radius-required-field
           config "baseUrl" #'non-empty-string-p))
        (models
          (radius-required-field
           config "models" #'vectorp)))
    (loop for model across models
          for id =
          (radius-required-field model "id" #'non-empty-string-p)
          for name =
          (radius-required-field model "name" #'non-empty-string-p)
          for reasoning =
          (radius-required-field
           model "reasoning"
           (lambda (value)
             (or (eq value t) (eq value nil))))
          for input =
          (radius-required-field model "input" #'vectorp)
          for cost =
          (radius-required-field model "cost" #'hash-table-p)
          for context-window =
          (radius-required-field
           model "contextWindow"
           (lambda (value)
             (and (integerp value) (plusp value))))
          for max-tokens =
          (radius-required-field
           model "maxTokens"
           (lambda (value)
             (and (integerp value) (plusp value))))
          collect
          (make-model-metadata
           :provider provider
           :id id
           :name name
           :api :pi-messages
           :base-url base-url
           :context-window context-window
           :max-output-tokens max-tokens
           :supports-images-p
           (not (null (find "image" input :test #'string=)))
           :supports-tools-p t
           :reasoning-p reasoning
           :thinking-level-map
           (let ((map (json-get model "thinkingLevelMap")))
             (when (hash-table-p map)
               (loop for key being the hash-keys of map
                       using (hash-value value)
                     collect
                     (cons
                      (intern (string-upcase key) :keyword)
                      (if (json-null-p value) nil value)))))
           :input-price
           (coerce (or (json-get cost "input") 0) 'double-float)
           :output-price
           (coerce (or (json-get cost "output") 0) 'double-float)
           :cache-read-price
           (coerce (or (json-get cost "cacheRead") 0) 'double-float)
           :cache-write-price
           (coerce (or (json-get cost "cacheWrite") 0) 'double-float)))))
