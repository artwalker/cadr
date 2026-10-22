(in-package #:cadr-ai)

(defparameter +openai-chatgpt-oauth-metadata+
  (make-oauth-provider-metadata
   :is-subscription-p t
   :provider-name "OpenAI"
   :method-name "OpenAI (ChatGPT subscription)"
   :login-label "Sign in with ChatGPT"
   :auth-url-instructions
   "Complete sign-in in your browser. If the callback does not complete, paste the final redirect URL here."
   :manual-input-message
   "Complete login in your browser, or paste the final redirect URL here:"))

(defparameter +chatgpt-dynamic-client-id+ "dynamic_agent_client")
(defparameter +chatgpt-direct-token-scope+ "chatgpt.tokens.use.direct")
(defparameter +chatgpt-oauth-scope+
  "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct")
(defparameter +chatgpt-authorize-url+
  "https://auth.openai.com/api/accounts/authorize")
(defparameter +chatgpt-token-url+
  "https://auth.openai.com/api/accounts/oauth/token")
(defparameter +chatgpt-resource+ "https://api.openai.com/v1")
(defparameter +chatgpt-callback-port+ 1455)
(defparameter +chatgpt-callback-path+ "/auth/callback")
(defparameter +chatgpt-redirect-uri+
  "http://127.0.0.1:1455/auth/callback")
(defparameter +chatgpt-expiry-margin-ms+ (* 3 60 1000))
(defparameter +chatgpt-port-in-use-message+
  "Port 1455 is in use, probably by an unfinished login in another cadr session or by the Codex CLI. Cancel that login and try again.")
(defparameter +chatgpt-device-id-message+
  "Sign in with ChatGPT requires a device ID (UUID) for this installation")

(defun chatgpt-authentication-error (message)
  (error 'authentication-error :message message))

(defun chatgpt-uuid-p (value)
  (and (stringp value)
       (= (length value) 36)
       (loop for index from 0 below 36
             for character = (char value index)
             always
             (if (member index '(8 13 18 23))
                 (char= character #\-)
                 (digit-char-p character 16)))))

(defun chatgpt-agent-host-id (device-id)
  (unless (chatgpt-uuid-p device-id)
    (chatgpt-authentication-error +chatgpt-device-id-message+))
  (format nil "urn:uuid:~A" (string-downcase device-id)))

(defun chatgpt-random-token ()
  (base64url-encode (secure-random-bytes 32)))

(defun chatgpt-agent-name ()
  (if (and (stringp *oauth-login-agent-name*)
           (plusp (length *oauth-login-agent-name*)))
      *oauth-login-agent-name*
      (cadr-product-display-name)))

(defun chatgpt-authorize-url (challenge state nonce host-id)
  (format nil "~A?~A"
          +chatgpt-authorize-url+
          (form-encode
           `(("client_id" . ,+chatgpt-dynamic-client-id+)
             ("agent_name_hint" . ,(chatgpt-agent-name))
             ("ext_agent_host_id" . ,host-id)
             ("response_type" . "code")
             ("redirect_uri" . ,+chatgpt-redirect-uri+)
             ("resource" . ,+chatgpt-resource+)
             ("scope" . ,+chatgpt-oauth-scope+)
             ("state" . ,state)
             ("code_challenge" . ,challenge)
             ("code_challenge_method" . "S256")
             ("nonce" . ,nonce)))))

(defun chatgpt-query-value (query name)
  (let ((value (gethash name query)))
    (and (stringp value)
         (plusp (length (string-trim '(#\Space #\Tab #\Newline #\Return) value)))
         (string-trim '(#\Space #\Tab #\Newline #\Return) value))))

(defun chatgpt-authorization-result (query expected-state)
  (let ((code (chatgpt-query-value query "code"))
        (state (chatgpt-query-value query "state"))
        (client-id (chatgpt-query-value query "client_id")))
    (unless code
      (chatgpt-authentication-error "Missing authorization code"))
    (unless state
      (chatgpt-authentication-error "Missing OAuth state"))
    (unless (string= state expected-state)
      (chatgpt-authentication-error "OAuth state mismatch"))
    (unless client-id
      (chatgpt-authentication-error
       "OpenAI OAuth registration callback did not contain an issued client ID"))
    (list :code code :client-id client-id)))

(defun chatgpt-callback-location (text)
  (let* ((scheme-end (search "://" text))
         (after (and scheme-end (+ scheme-end 3)))
         (slash (and after (position #\/ text :start after)))
         (question (and after (position #\? text :start after)))
         (origin-end (or slash question (length text)))
         (path-end (or question (length text))))
    (values
     (subseq text 0 origin-end)
     (if slash (subseq text slash path-end) "/")
     (if question
         (let* ((rest (subseq text (1+ question)))
                (hash (position #\# rest)))
           (if hash (subseq rest 0 hash) rest))
         ""))))

(defun chatgpt-result-from-manual (input expected-state)
  (let ((text (string-trim '(#\Space #\Tab #\Newline #\Return) input)))
    (unless (or (uiop:string-prefix-p "http://" text)
                (uiop:string-prefix-p "https://" text)
                (uiop:string-prefix-p "HTTP://" text)
                (uiop:string-prefix-p "HTTPS://" text))
      (chatgpt-authentication-error
       "Paste the full callback URL from the browser"))
    (multiple-value-bind (origin path query)
        (chatgpt-callback-location text)
      (unless (and (string-equal origin "http://127.0.0.1:1455")
                   (string= path +chatgpt-callback-path+))
        (chatgpt-authentication-error
         (format nil "The pasted callback URL must start with ~A"
                 +chatgpt-redirect-uri+)))
      (let ((parsed (parse-query query)))
        (let ((failure (chatgpt-query-value parsed "error")))
          (when failure
            (chatgpt-authentication-error
             (format nil "ChatGPT authorization failed: ~A" failure))))
        (chatgpt-authorization-result parsed expected-state)))))

(defun open-chatgpt-callback-socket ()
  (handler-case
      (open-oauth-callback-socket +chatgpt-callback-port+)
    (sb-bsd-sockets:address-in-use-error ()
      (chatgpt-authentication-error +chatgpt-port-in-use-message+))))

(defun chatgpt-send-callback-html (stream status message &optional details)
  (write-oauth-http-response
   stream status
   (if (= status 200)
       (oauth-success-html message)
       (oauth-error-html message details))))

(defun accept-chatgpt-callback (socket expected-state)
  (multiple-value-bind (client address port)
      (sb-bsd-sockets:socket-accept socket)
    (declare (ignore address port))
    (unwind-protect
         (let ((stream
                 (sb-bsd-sockets:socket-make-stream
                  client
                  :input t :output t
                  :element-type 'character
                  :external-format :utf-8
                  :buffering :none)))
           (unwind-protect
                (let* ((request-line (or (read-line stream nil "") ""))
                       (parts
                         (uiop:split-string request-line :separator '(#\Space)))
                       (target (second parts))
                       (separator (and target (position #\? target)))
                       (path
                         (if separator (subseq target 0 separator) target))
                       (query
                         (if separator
                             (parse-query (subseq target (1+ separator)))
                             (make-hash-table :test #'equal))))
                  (cond
                    ((not (string= path +chatgpt-callback-path+))
                     (chatgpt-send-callback-html
                      stream 404 "Callback route not found.")
                     nil)
                    ((chatgpt-query-value query "error")
                     (let ((failure (chatgpt-query-value query "error")))
                       (chatgpt-send-callback-html
                        stream 400 "ChatGPT was not connected."
                        (format nil "Error: ~A" failure))
                       (chatgpt-authentication-error
                        (format nil "ChatGPT authorization failed: ~A"
                                failure))))
                    (t
                     (handler-case
                         (let ((result
                                 (chatgpt-authorization-result
                                  query expected-state)))
                           (chatgpt-send-callback-html
                            stream 200
                            "ChatGPT authentication completed. You can close this window.")
                           result)
                       (authentication-error (condition)
                         (chatgpt-send-callback-html
                          stream 400
                          (cadr-error-message condition))
                         nil)))))
             (close stream)))
      (ignore-errors (sb-bsd-sockets:socket-close client)))))

(defun read-chatgpt-callbacks (socket expected-state cancelled-p)
  (loop
    (when (funcall cancelled-p)
      (return nil))
    (when (sb-sys:wait-until-fd-usable
           (sb-bsd-sockets:socket-file-descriptor socket)
           :input 0.05)
      (let ((result (accept-chatgpt-callback socket expected-state)))
        (when result
          (return result))))))

(defun race-chatgpt-authorization (socket state interaction url)
  (let ((lock (sb-thread:make-mutex :name "cadr-chatgpt-authorization"))
        (waitq
          (sb-thread:make-waitqueue :name "cadr-chatgpt-authorization"))
        (done-p nil)
        (cancelled-p nil)
        (result nil)
        (failure nil))
    (labels ((cancelled-p ()
               (sb-thread:with-mutex (lock) cancelled-p))
             (finish (value error)
               (sb-thread:with-mutex (lock)
                 (unless done-p
                   (setf result value
                         failure error
                         done-p t
                         cancelled-p t)
                   (sb-thread:condition-broadcast waitq)
                   (ignore-errors
                     (sb-bsd-sockets:socket-close socket))))))
      (let ((callback-thread
              (sb-thread:make-thread
               (lambda ()
                 (handler-case
                     (let ((value
                             (read-chatgpt-callbacks
                              socket state #'cancelled-p)))
                       (when value
                         (finish value nil)))
                   (authentication-error (condition)
                     (finish nil condition))
                   (error ()
                     nil)))
               :name "cadr-chatgpt-callback"))
            (prompt-thread
              (sb-thread:make-thread
               (lambda ()
                 (handler-case
                     (finish
                      (chatgpt-result-from-manual
                       (runtime-auth-interaction-prompt
                        interaction
                        (list
                         :type :manual-code
                         :message
                         (oauth-provider-metadata-manual-input-message
                          +openai-chatgpt-oauth-metadata+)
                         :placeholder +chatgpt-redirect-uri+
                         :url url
                         :instructions
                         (oauth-provider-metadata-auth-url-instructions
                          +openai-chatgpt-oauth-metadata+)
                         :cancel-function
                         (lambda ()
                           (finish
                            nil
                            (make-condition
                             'authentication-cancelled
                             :message "Login cancelled")))
                         :cancelled-p-function #'cancelled-p))
                       state)
                      nil)
                   (authentication-cancelled (condition)
                     (finish nil condition))
                   (authentication-error (condition)
                     (finish nil condition))
                   (error (condition)
                     (finish
                      nil
                      (make-condition
                       'authentication-error
                       :message "OAuth authorization prompt failed"
                       :cause condition)))))
               :name "cadr-chatgpt-manual")))
        (sb-thread:with-mutex (lock)
          (loop until done-p
                do (sb-thread:condition-wait waitq lock)))
        (stop-thread-for-cleanup callback-thread :timeout 1d0)
        (stop-thread-for-cleanup prompt-thread :timeout 1d0)
        (when failure
          (error failure))
        result))))

(defun chatgpt-finite-positive-p (value)
  (and (realp value)
       (plusp value)
       (not (and (floatp value)
                 (or (sb-ext:float-infinity-p value)
                     (sb-ext:float-nan-p value))))))

(defun chatgpt-token-request (fields)
  (multiple-value-bind (object status)
      (funcall *oauth-flow-request-function*
               +chatgpt-token-url+
               :method :post
               :headers
               '(("accept" . "application/json")
                 ("content-type" . "application/x-www-form-urlencoded"))
               :content (form-encode fields)
               :connect-timeout 10
               :read-timeout 30)
    (unless (and (integerp status) (<= 200 status 299))
      (chatgpt-authentication-error
               (format nil "OpenAI OAuth token request failed (~D): ~A"
               status
               (cond
                 ((and (stringp object) (plusp (length object))) object)
                 ((hash-table-p object) (stringify-json object))
                 (t "")))))
    (unless (hash-table-p object)
      (chatgpt-authentication-error
       "OpenAI OAuth token response must be an object"))
    object))

(defun chatgpt-token-string (token field)
  (let ((value (json-get token field)))
    (unless (and (stringp value) (plusp (length (string-trim '(#\Space #\Tab #\Newline #\Return) value))))
      (chatgpt-authentication-error
       (format nil "OpenAI OAuth token response has invalid ~A" field)))
    value))

(defun chatgpt-scope-list (scope)
  (remove-if
   (lambda (part) (zerop (length part)))
   (uiop:split-string
    (string-trim '(#\Space #\Tab #\Newline #\Return) scope)
    :separator '(#\Space #\Tab #\Newline #\Return))))

(defun chatgpt-credential-from-token (token client-id)
  (let ((access (chatgpt-token-string token "access_token"))
        (refresh (chatgpt-token-string token "refresh_token"))
        (scope (chatgpt-token-string token "scope"))
        (expires-in (json-get token "expires_in")))
    (unless (chatgpt-finite-positive-p expires-in)
      (chatgpt-authentication-error
       "OpenAI OAuth token response has invalid expires_in"))
    (let ((scopes (chatgpt-scope-list scope)))
      (unless (member +chatgpt-direct-token-scope+ scopes :test #'string=)
        (chatgpt-authentication-error
         (format nil "OpenAI OAuth grant did not include ~A"
                 +chatgpt-direct-token-scope+)))
      (make-oauth-credential
       :provider :openai
       :access access
       :refresh refresh
       :expires
       (floor
        (+ (unix-milliseconds)
           (* expires-in 1000)
           (- +chatgpt-expiry-margin-ms+)))
       :metadata
       `(("clientId" . ,client-id)
         ("scopes" . ,scopes))))))

(defun chatgpt-credential-client-id (credential)
  (let ((value
          (cdr (assoc "clientId"
                      (oauth-credential-metadata credential)
                      :test #'string=))))
    (and (stringp value)
         (plusp (length (string-trim '(#\Space #\Tab #\Newline #\Return) value)))
         (string-trim '(#\Space #\Tab #\Newline #\Return) value))))

(defun exchange-chatgpt-authorization-code (code verifier client-id)
  (let ((token
          (chatgpt-token-request
           `(("grant_type" . "authorization_code")
             ("client_id" . ,client-id)
             ("code" . ,code)
             ("code_verifier" . ,verifier)
             ("redirect_uri" . ,+chatgpt-redirect-uri+)
             ("resource" . ,+chatgpt-resource+)))))
    (let ((id-token (json-get token "id_token")))
      (unless (and (stringp id-token)
                   (plusp (length (string-trim '(#\Space #\Tab #\Newline #\Return) id-token))))
        (chatgpt-authentication-error
         "OpenAI OAuth token response did not contain an ID token")))
    (chatgpt-credential-from-token token client-id)))

(defun refresh-openai-chatgpt-oauth-credential (credential)
  (let ((client-id (chatgpt-credential-client-id credential)))
    (unless client-id
      (chatgpt-authentication-error
       "Stored OpenAI OAuth credential does not contain an issued client ID; reconnect ChatGPT"))
    (chatgpt-credential-from-token
     (chatgpt-token-request
      `(("grant_type" . "refresh_token")
        ("client_id" . ,client-id)
        ("refresh_token" . ,(oauth-credential-refresh credential))
        ("resource" . ,+chatgpt-resource+)))
     client-id)))

(defun login-openai-chatgpt-oauth (interaction)
  (let ((host-id (chatgpt-agent-host-id *oauth-login-device-id*)))
    (when (runtime-auth-interaction-aborted-p interaction)
      (error 'authentication-cancelled :message "Login cancelled"))
    (multiple-value-bind (verifier challenge) (generate-pkce)
      (let* ((state (chatgpt-random-token))
             (nonce (chatgpt-random-token))
             (socket (open-chatgpt-callback-socket))
             (url (chatgpt-authorize-url challenge state nonce host-id)))
        (unwind-protect
             (handler-case
                 (progn
                   (runtime-auth-interaction-notify
                    interaction
                    (list :type :auth-url
                          :url url
                          :instructions
                          (oauth-provider-metadata-auth-url-instructions
                           +openai-chatgpt-oauth-metadata+)))
                   (handler-case
                       (funcall *oauth-browser-open-function* url)
                     (error () nil))
                   (let ((authorization
                           (race-chatgpt-authorization
                            socket state interaction url)))
                     (when (runtime-auth-interaction-aborted-p interaction)
                       (error 'authentication-cancelled
                              :message "Login cancelled"))
                     (runtime-auth-interaction-notify
                      interaction
                      '(:type :progress
                        :message "Exchanging authorization code for tokens..."))
                     (let ((*native-http-abort-p*
                             (lambda ()
                               (runtime-auth-interaction-aborted-p interaction))))
                       (exchange-chatgpt-authorization-code
                        (getf authorization :code)
                        verifier
                        (getf authorization :client-id)))))
               (request-aborted ()
                 (error 'authentication-cancelled :message "Login cancelled"))
               (authentication-cancelled (condition)
                 (error condition))
               (error (condition)
                 (if (runtime-auth-interaction-aborted-p interaction)
                     (error 'authentication-cancelled
                            :message "Login cancelled")
                     (error condition))))
          (ignore-errors (sb-bsd-sockets:socket-close socket)))))))
