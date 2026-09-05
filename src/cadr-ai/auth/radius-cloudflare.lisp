(in-package #:cadr-ai)

(defparameter +radius-oauth-client-id+ "pi-gateway")
(defparameter +radius-oauth-scope+ "gateway offline_access")

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
      ("client_id" . ,+radius-oauth-client-id+)
      ("redirect_uri" . ,redirect-uri)
      ("scope" . ,+radius-oauth-scope+)
      ("code_challenge" . ,challenge)
      ("code_challenge_method" . "S256")
      ("handoff" . "url")
      ("state" . ,state)))))

(defun materialize-cloudflare-url
    (base-url account-id gateway-id)
  ;; One brace scan: validate required ids and rewrite placeholders
  ;; without four search + four replace-all string copies.
  (let ((n (length base-url))
        (need-account nil)
        (need-gateway nil)
        (has-brace nil))
    (let ((i 0))
      (loop while (< i n)
            do (if (char= (char base-url i) #\{)
                   (cond
                     ((and
                       (<= (+ i 23) n)
                       (string=
                        base-url "{CLOUDFLARE_ACCOUNT_ID}"
                        :start1 i :end1 (+ i 23)))
                      (setf has-brace t need-account t)
                      (incf i 23))
                     ((and
                       (<= (+ i 23) n)
                       (string=
                        base-url "{CLOUDFLARE_GATEWAY_ID}"
                        :start1 i :end1 (+ i 23)))
                      (setf has-brace t need-gateway t)
                      (incf i 23))
                     ((and
                       (<= (+ i 11) n)
                       (string=
                        base-url "{accountId}"
                        :start1 i :end1 (+ i 11)))
                      (setf has-brace t need-account t)
                      (incf i 11))
                     ((and
                       (<= (+ i 11) n)
                       (string=
                        base-url "{gatewayId}"
                        :start1 i :end1 (+ i 11)))
                      (setf has-brace t need-gateway t)
                      (incf i 11))
                     (t
                      (setf has-brace t)
                      (incf i)))
                   (incf i))))
    (when (and need-account
               (not (non-empty-string-p account-id)))
      (error 'configuration-error
             :message "CLOUDFLARE_ACCOUNT_ID is not set"))
    (when (and need-gateway
               (not (non-empty-string-p gateway-id)))
      (error 'configuration-error
             :message "CLOUDFLARE_GATEWAY_ID is not set"))
    (if (not has-brace)
        base-url
        (with-output-to-string (out)
          (let ((i 0))
            (loop while (< i n)
                  do (if (char= (char base-url i) #\{)
                         (cond
                           ((and
                             account-id
                             (<= (+ i 23) n)
                             (string=
                              base-url "{CLOUDFLARE_ACCOUNT_ID}"
                              :start1 i :end1 (+ i 23)))
                            (write-string account-id out)
                            (incf i 23))
                           ((and
                             gateway-id
                             (<= (+ i 23) n)
                             (string=
                              base-url "{CLOUDFLARE_GATEWAY_ID}"
                              :start1 i :end1 (+ i 23)))
                            (write-string gateway-id out)
                            (incf i 23))
                           ((and
                             account-id
                             (<= (+ i 11) n)
                             (string=
                              base-url "{accountId}"
                              :start1 i :end1 (+ i 11)))
                            (write-string account-id out)
                            (incf i 11))
                           ((and
                             gateway-id
                             (<= (+ i 11) n)
                             (string=
                              base-url "{gatewayId}"
                              :start1 i :end1 (+ i 11)))
                            (write-string gateway-id out)
                            (incf i 11))
                           (t
                            (write-char #\{ out)
                            (incf i)))
                         (progn
                           (write-char (char base-url i) out)
                           (incf i)))))))))

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
