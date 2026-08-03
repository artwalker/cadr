(in-package #:cadr-ai)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-bsd-sockets))

(defparameter +openai-oauth-client-id+
  "app_EMoamEEZ73f0CkXaXp7hrann")
(defparameter +openai-oauth-authorize-url+
  "https://auth.openai.com/oauth/authorize")
(defparameter +openai-oauth-token-url+
  "https://auth.openai.com/oauth/token")
(defparameter +openai-oauth-redirect-uri+
  "http://localhost:1455/auth/callback")
(defparameter +openai-originator+ "cadr")

(defparameter +anthropic-oauth-client-id+
  "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
(defparameter +anthropic-oauth-authorize-url+
  "https://claude.ai/oauth/authorize")
(defparameter +anthropic-oauth-token-url+
  "https://platform.claude.com/v1/oauth/token")
(defparameter +anthropic-oauth-redirect-uri+
  "http://localhost:53692/callback")
(defparameter +anthropic-oauth-scopes+
  "org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload")

(defparameter *oauth-http-request-function*
  #'native-http-request)
(defparameter *oauth-browser-open-function*
  (lambda (url)
    (uiop:launch-program
     (list "xdg-open" url)
     :output nil
     :error-output nil)))

(defparameter +sha256-constants+
  #(#x428a2f98 #x71374491 #xb5c0fbcf #xe9b5dba5
    #x3956c25b #x59f111f1 #x923f82a4 #xab1c5ed5
    #xd807aa98 #x12835b01 #x243185be #x550c7dc3
    #x72be5d74 #x80deb1fe #x9bdc06a7 #xc19bf174
    #xe49b69c1 #xefbe4786 #x0fc19dc6 #x240ca1cc
    #x2de92c6f #x4a7484aa #x5cb0a9dc #x76f988da
    #x983e5152 #xa831c66d #xb00327c8 #xbf597fc7
    #xc6e00bf3 #xd5a79147 #x06ca6351 #x14292967
    #x27b70a85 #x2e1b2138 #x4d2c6dfc #x53380d13
    #x650a7354 #x766a0abb #x81c2c92e #x92722c85
    #xa2bfe8a1 #xa81a664b #xc24b8b70 #xc76c51a3
    #xd192e819 #xd6990624 #xf40e3585 #x106aa070
    #x19a4c116 #x1e376c08 #x2748774c #x34b0bcb5
    #x391c0cb3 #x4ed8aa4a #x5b9cca4f #x682e6ff3
    #x748f82ee #x78a5636f #x84c87814 #x8cc70208
    #x90befffa #xa4506ceb #xbef9a3f7 #xc67178f2))

(defun u32 (value)
  (logand value #xffffffff))

(defun rotate-right-32 (value count)
  (let ((value (u32 value)))
    (u32
     (logior (ash value (- count))
             (ash value (- 32 count))))))

(defun sha256-bytes (octets)
  (let* ((original-length (length octets))
         (bit-length (* original-length 8))
         (padding
           (mod (- 56 (mod (1+ original-length) 64)) 64))
         (message
           (make-array (+ original-length 1 padding 8)
                       :element-type '(unsigned-byte 8)
                       :initial-element 0))
         (hash
           (vector #x6a09e667 #xbb67ae85 #x3c6ef372 #xa54ff53a
                   #x510e527f #x9b05688c #x1f83d9ab #x5be0cd19)))
    (replace message octets)
    (setf (aref message original-length) #x80)
    (dotimes (index 8)
      (setf
       (aref message (- (length message) 1 index))
       (ldb (byte 8 (* index 8)) bit-length)))
    (loop for offset from 0 below (length message) by 64
          do
          (let ((words
                  (make-array 64
                              :element-type '(unsigned-byte 32)
                              :initial-element 0)))
            (dotimes (index 16)
              (let ((base (+ offset (* index 4))))
                (setf
                 (aref words index)
                 (u32
                  (logior
                   (ash (aref message base) 24)
                   (ash (aref message (+ base 1)) 16)
                   (ash (aref message (+ base 2)) 8)
                   (aref message (+ base 3)))))))
            (loop for index from 16 below 64
                  for previous-15 = (aref words (- index 15))
                  for previous-2 = (aref words (- index 2))
                  for s0 = (logxor
                            (rotate-right-32 previous-15 7)
                            (rotate-right-32 previous-15 18)
                            (ash previous-15 -3))
                  for s1 = (logxor
                            (rotate-right-32 previous-2 17)
                            (rotate-right-32 previous-2 19)
                            (ash previous-2 -10))
                  do
                  (setf (aref words index)
                        (u32 (+ (aref words (- index 16))
                                s0
                                (aref words (- index 7))
                                s1))))
            (let ((a (aref hash 0))
                  (b (aref hash 1))
                  (c (aref hash 2))
                  (d (aref hash 3))
                  (e (aref hash 4))
                  (f (aref hash 5))
                  (g (aref hash 6))
                  (h (aref hash 7)))
              (dotimes (index 64)
                (let* ((sum1
                         (logxor
                          (rotate-right-32 e 6)
                          (rotate-right-32 e 11)
                          (rotate-right-32 e 25)))
                       (choice
                         (logxor (logand e f)
                                 (logand (lognot e) g)))
                       (temp1
                         (u32 (+ h sum1 choice
                                 (aref +sha256-constants+ index)
                                 (aref words index))))
                       (sum0
                         (logxor
                          (rotate-right-32 a 2)
                          (rotate-right-32 a 13)
                          (rotate-right-32 a 22)))
                       (majority
                         (logxor (logand a b)
                                 (logand a c)
                                 (logand b c)))
                       (temp2 (u32 (+ sum0 majority))))
                  (setf h g
                        g f
                        f e
                        e (u32 (+ d temp1))
                        d c
                        c b
                        b a
                        a (u32 (+ temp1 temp2)))))
              (setf
               (aref hash 0) (u32 (+ (aref hash 0) a))
               (aref hash 1) (u32 (+ (aref hash 1) b))
               (aref hash 2) (u32 (+ (aref hash 2) c))
               (aref hash 3) (u32 (+ (aref hash 3) d))
               (aref hash 4) (u32 (+ (aref hash 4) e))
               (aref hash 5) (u32 (+ (aref hash 5) f))
               (aref hash 6) (u32 (+ (aref hash 6) g))
               (aref hash 7) (u32 (+ (aref hash 7) h))))))
    (let ((result
            (make-array 32 :element-type '(unsigned-byte 8))))
      (dotimes (word-index 8)
        (dotimes (byte-index 4)
          (setf
           (aref result (+ (* word-index 4) byte-index))
           (ldb (byte 8 (* 8 (- 3 byte-index)))
                (aref hash word-index)))))
      result)))

(defparameter +base64-url-alphabet+
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

(defun base64url-encode (octets)
  (with-output-to-string (output)
    (loop for index from 0 below (length octets) by 3
          for remaining = (- (length octets) index)
          for first = (aref octets index)
          for second = (if (> remaining 1)
                           (aref octets (1+ index)) 0)
          for third = (if (> remaining 2)
                          (aref octets (+ index 2)) 0)
          for bits = (logior (ash first 16)
                             (ash second 8)
                             third)
          do
          (write-char
           (char +base64-url-alphabet+ (ldb (byte 6 18) bits))
           output)
          (write-char
           (char +base64-url-alphabet+ (ldb (byte 6 12) bits))
           output)
          (when (> remaining 1)
            (write-char
             (char +base64-url-alphabet+ (ldb (byte 6 6) bits))
             output))
          (when (> remaining 2)
            (write-char
             (char +base64-url-alphabet+ (ldb (byte 6 0) bits))
             output)))))

(defun pkce-challenge (verifier)
  (base64url-encode
   (sha256-bytes
    (utf8-octets verifier))))

(defun secure-random-bytes (count)
  (let ((bytes
          (make-array count :element-type '(unsigned-byte 8))))
    (with-open-file
        (stream #P"/dev/urandom"
                :direction :input
                :element-type '(unsigned-byte 8))
      (unless (= count (read-sequence bytes stream))
        (error 'authentication-error
               :message "Could not read secure random bytes")))
    bytes))

(defun generate-pkce ()
  (let ((verifier (base64url-encode (secure-random-bytes 32))))
    (values verifier (pkce-challenge verifier))))

(defun oauth-state ()
  (base64url-encode (secure-random-bytes 16)))

(defun unreserved-octet-p (octet)
  (or (<= (char-code #\A) octet (char-code #\Z))
      (<= (char-code #\a) octet (char-code #\z))
      (<= (char-code #\0) octet (char-code #\9))
      (member octet
              (mapcar #'char-code '(#\- #\_ #\. #\~)))))

(defun percent-encode (value)
  (with-output-to-string (output)
    (loop for octet across
            (utf8-octets value)
          do
          (if (unreserved-octet-p octet)
              (write-char (code-char octet) output)
              (format output "%~2,'0X" octet)))))

(defun form-encode (pairs)
  (format nil "~{~A~^&~}"
          (loop for (key . value) in pairs
                collect
                (format nil "~A=~A"
                        (percent-encode key)
                        (percent-encode value)))))

(defun openai-authorization-url (challenge state)
  (format
   nil "~A?~A"
   +openai-oauth-authorize-url+
   (form-encode
    `(("response_type" . "code")
      ("client_id" . ,+openai-oauth-client-id+)
      ("redirect_uri" . ,+openai-oauth-redirect-uri+)
      ("scope" . "openid profile email offline_access")
      ("code_challenge" . ,challenge)
      ("code_challenge_method" . "S256")
      ("state" . ,state)
      ("id_token_add_organizations" . "true")
      ("codex_cli_simplified_flow" . "true")
      ("originator" . ,+openai-originator+)))))

(defun anthropic-authorization-url (challenge state)
  (format
   nil "~A?~A"
   +anthropic-oauth-authorize-url+
   (form-encode
    `(("code" . "true")
      ("client_id" . ,+anthropic-oauth-client-id+)
      ("response_type" . "code")
      ("redirect_uri" . ,+anthropic-oauth-redirect-uri+)
      ("scope" . ,+anthropic-oauth-scopes+)
      ("code_challenge" . ,challenge)
      ("code_challenge_method" . "S256")
      ("state" . ,state)))))

(defun hex-value (character)
  (or (digit-char-p character 16)
      (error 'authentication-error
             :message "Invalid percent escape in OAuth callback")))

(defun percent-decode (value)
  (let ((octets
          (make-array (length value)
                      :element-type '(unsigned-byte 8)
                      :adjustable t
                      :fill-pointer 0)))
    (loop for index from 0 below (length value)
          for character = (char value index)
          do
          (cond
            ((char= character #\%)
             (when (> (+ index 2) (1- (length value)))
               (error 'authentication-error
                      :message "Truncated percent escape"))
             (vector-push-extend
              (+ (* 16 (hex-value (char value (1+ index))))
                 (hex-value (char value (+ index 2))))
              octets)
             (incf index 2))
            ((char= character #\+)
             (vector-push-extend (char-code #\Space) octets))
            (t
             (let ((encoded
                     (utf8-octets
                      (string character))))
               (loop for octet across encoded
                     do (vector-push-extend octet octets))))))
    (utf8-string octets)))

(defun parse-query (query)
  (let ((result (make-hash-table :test #'equal)))
    (dolist (part (uiop:split-string query :separator '(#\&)))
      (let ((separator (position #\= part)))
        (setf
         (gethash (percent-decode
                   (if separator (subseq part 0 separator) part))
                  result)
         (percent-decode
          (if separator (subseq part (1+ separator)) "")))))
    result))

(defun parse-oauth-authorization-input (value)
  (let* ((text
           (string-trim '(#\Space #\Tab #\Newline #\Return)
                        value))
         (query-start (position #\? text))
         (query-text
           (cond
             (query-start (subseq text (1+ query-start)))
             ((or (uiop:string-prefix-p "code=" text)
                  (search "&code=" text))
              text)
             (t nil))))
    (cond
      (query-text
       (let* ((fragment-start (position #\# query-text))
              (query
                (parse-query
                 (if fragment-start
                     (subseq query-text 0 fragment-start)
                     query-text))))
         (values (gethash "code" query)
                 (gethash "state" query))))
      ((position #\# text)
       (let ((separator (position #\# text)))
         (values (subseq text 0 separator)
                 (subseq text (1+ separator)))))
      (t
       (values text nil)))))

(defun parse-oauth-callback-request
    (request-line expected-path expected-state
     &key provider-name)
  (handler-case
      (let* ((parts (uiop:split-string request-line :separator '(#\Space)))
             (target (second parts))
             (separator (and target (position #\? target)))
             (path (if separator (subseq target 0 separator) target))
             (query (if separator
                        (parse-query (subseq target (1+ separator)))
                        (make-hash-table :test #'equal))))
        (cond
          ((not (string= path expected-path))
           (values nil 404 :route-not-found nil))
          ((and provider-name
                (string-equal provider-name "Anthropic")
                (non-empty-string-p (gethash "error" query)))
           (values
            nil 400 :provider-error
            (format nil "Error: ~A" (gethash "error" query))))
          ((and provider-name
                (string-equal provider-name "Anthropic")
                (or
                 (not (non-empty-string-p (gethash "code" query)))
                 (not (non-empty-string-p (gethash "state" query)))))
           (values nil 400 :missing-code-or-state nil))
          ((not (string= (or (gethash "state" query) "")
                         expected-state))
           (values nil 400 :state-mismatch nil))
          ((and provider-name
                (string-equal provider-name "Radius")
                (non-empty-string-p (gethash "error" query)))
           (values
            nil 400 :provider-error
            (or (gethash "error_description" query)
                (gethash "error" query))))
          ((not (non-empty-string-p (gethash "code" query)))
           (values nil 400 :missing-authorization-code nil))
          (t
           (values (gethash "code" query) 200 :success nil))))
    (error ()
      (values nil 500 :internal-error nil))))

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

(defun base64url-value (character)
  (position character +base64-url-alphabet+))

(defun base64url-decode (string)
  (let ((octets
          (make-array (ceiling (* (length string) 3) 4)
                      :element-type '(unsigned-byte 8)
                      :adjustable t
                      :fill-pointer 0)))
    (loop for index from 0 below (length string) by 4
          for remaining = (- (length string) index)
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
            (vector-push-extend (ldb (byte 8 16) bits) octets)
            (when c
              (vector-push-extend (ldb (byte 8 8) bits) octets))
            (when d
              (vector-push-extend (ldb (byte 8 0) bits) octets))))
    octets))

(defun openai-account-id-from-token (token)
  (handler-case
      (let* ((parts (uiop:split-string token :separator '(#\.)))
             (payload
               (parse-json
                (utf8-string
                 (base64url-decode
                  (second parts)))))
             (auth
               (json-get payload "https://api.openai.com/auth")))
        (json-get auth "chatgpt_account_id"))
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

(defun exchange-openai-authorization-code (code verifier)
  (token-response-credential
   :openai-codex
   (oauth-token-request
    +openai-oauth-token-url+
    `(("grant_type" . "authorization_code")
      ("client_id" . ,+openai-oauth-client-id+)
      ("code" . ,code)
      ("code_verifier" . ,verifier)
      ("redirect_uri" . ,+openai-oauth-redirect-uri+))
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

(defparameter +oauth-logo-svg+
  "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 800 800\" aria-hidden=\"true\"><path fill=\"#fff\" fill-rule=\"evenodd\" d=\"M47.93 165.29 H400.01 V517.37 H47.93 Z M400.01 165.29 H752.09 V517.37 H400.01 Z M165.29 282.65 H282.65 V400.01 H165.29 Z M517.37 282.65 H634.73 V165.29 H752.09 V517.37 H634.73 V400.01 H517.37 Z\"/></svg>")

(defun escape-oauth-html (value)
  (with-output-to-string (output)
    (loop for character across (or value "")
          do
          (case character
            (#\& (write-string "&amp;" output))
            (#\< (write-string "&lt;" output))
            (#\> (write-string "&gt;" output))
            (#\" (write-string "&quot;" output))
            (#\' (write-string "&#39;" output))
            (otherwise (write-char character output))))))

(defun render-oauth-page
    (title heading message &optional details)
  (let ((title (escape-oauth-html title))
        (heading (escape-oauth-html heading))
        (message (escape-oauth-html message))
        (details
          (and details
               (plusp (length details))
               (escape-oauth-html details))))
    (format
     nil
     "<!doctype html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\" />
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
  <title>~A</title>
  <style>
    :root {
      --text: #fafafa;
      --text-dim: #a1a1aa;
      --page-bg: #09090b;
      --font-sans: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, \"Helvetica Neue\", Arial, \"Noto Sans\", sans-serif, \"Apple Color Emoji\", \"Segoe UI Emoji\", \"Segoe UI Symbol\", \"Noto Color Emoji\";
      --font-mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\", monospace;
    }
    * { box-sizing: border-box; }
    html { color-scheme: dark; }
    body {
      margin: 0;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
      background: var(--page-bg);
      color: var(--text);
      font-family: var(--font-sans);
      text-align: center;
    }
    main {
      width: 100%;
      max-width: 560px;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
    }
    .logo {
      width: 72px;
      height: 72px;
      display: block;
      margin-bottom: 24px;
    }
    h1 {
      margin: 0 0 10px;
      font-size: 28px;
      line-height: 1.15;
      font-weight: 650;
      color: var(--text);
    }
    p {
      margin: 0;
      line-height: 1.7;
      color: var(--text-dim);
      font-size: 15px;
    }
    .details {
      margin-top: 16px;
      font-family: var(--font-mono);
      font-size: 13px;
      color: var(--text-dim);
      white-space: pre-wrap;
      word-break: break-word;
    }
  </style>
</head>
<body>
  <main>
    <div class=\"logo\">~A</div>
    <h1>~A</h1>
    <p>~A</p>
    ~A
  </main>
</body>
</html>"
     title +oauth-logo-svg+ heading message
     (if details
         (format nil "<div class=\"details\">~A</div>" details)
         ""))))

(defun oauth-success-html (message)
  (render-oauth-page
   "Authentication successful"
   "Authentication successful"
   message))

(defun oauth-error-html (message &optional details)
  (render-oauth-page
   "Authentication failed"
   "Authentication failed"
   message details))

(defun oauth-callback-response-copy
    (provider-name status reason details)
  (declare (ignore status))
  (values
   (case reason
     (:success
      (cond
        ((string-equal provider-name "Radius")
         "Signed in to Radius. You may now close this page.")
        (t
         (format nil
                 "~A authentication completed. You can close this window."
                 provider-name))))
     (:route-not-found "Callback route not found.")
     (:state-mismatch
      (if (string-equal provider-name "Radius")
          "OAuth state mismatch."
          "State mismatch."))
     (:provider-error
      (if (string-equal provider-name "Anthropic")
          "Anthropic authentication did not complete."
          (or details "OAuth authentication did not complete.")))
     (:missing-code-or-state "Missing code or state parameter.")
     (:missing-authorization-code "Missing authorization code.")
     (:internal-error
      "Internal error while processing OAuth callback.")
     (otherwise "OAuth authentication did not complete."))
   (and (eq reason :provider-error)
        (string-equal provider-name "Anthropic")
        details)))

(defun oauth-http-status-text (status)
  (case status
    (200 "OK")
    (400 "Bad Request")
    (404 "Not Found")
    (500 "Internal Server Error")
    (otherwise "Error")))

(defun write-oauth-http-response (stream status body)
  (format stream
          "HTTP/1.1 ~D ~A~C~CContent-Type: text/html; charset=utf-8~C~CContent-Length: ~D~C~CConnection: close~C~C~C~C~A"
          status
          (oauth-http-status-text status)
          #\Return #\Linefeed
          #\Return #\Linefeed
          (length
           (utf8-octets body))
          #\Return #\Linefeed
          #\Return #\Linefeed
          #\Return #\Linefeed
          body)
  (finish-output stream))

(defun wait-for-oauth-code
    (state port path provider-name &optional cancelled-p)
  (let ((socket
          (make-instance 'sb-bsd-sockets:inet-socket
                         :type :stream
                         :protocol :tcp)))
    (unwind-protect
         (progn
           (setf (sb-bsd-sockets:sockopt-reuse-address socket) t)
           (sb-bsd-sockets:socket-bind socket
                                       #(127 0 0 1) port)
           (sb-bsd-sockets:socket-listen socket 1)
           (when cancelled-p
             (loop
               (when (funcall cancelled-p)
                 (return-from wait-for-oauth-code nil))
               (when
                   (sb-sys:wait-until-fd-usable
                    (sb-bsd-sockets:socket-file-descriptor socket)
                    :input 0.05)
                 (return))))
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
                         (let ((request-line (read-line stream nil "")))
                           (multiple-value-bind
                                 (code status reason details)
                               (parse-oauth-callback-request
                                request-line path state
                                :provider-name provider-name)
                             (multiple-value-bind
                                   (message response-details)
                                 (oauth-callback-response-copy
                                  provider-name status reason details)
                               (write-oauth-http-response
                                stream status
                                (if (= status 200)
                                    (oauth-success-html message)
                                    (oauth-error-html
                                     message response-details))))
                             (unless (= status 200)
                               (error 'authentication-error
                                      :message
                                      "OAuth callback validation failed"))
                             code))
                      (close stream)))
               (ignore-errors
                 (sb-bsd-sockets:socket-close client)))))
      (ignore-errors
        (sb-bsd-sockets:socket-close socket)))))

(defun wait-for-openai-oauth-code (state &optional cancelled-p)
  (wait-for-oauth-code
   state 1455 "/auth/callback" "OpenAI" cancelled-p))

(defun wait-for-oauth-authorization
    (expected-state callback-function prompt-function prompt)
  (unless prompt-function
    (return-from wait-for-oauth-authorization
      (funcall callback-function (constantly nil))))
  (let ((lock
          (sb-thread:make-mutex
           :name "cadr-oauth-authorization"))
        (condition
          (sb-thread:make-waitqueue
           :name "cadr-oauth-authorization"))
        (cancelled-p nil)
        (done-p nil)
        (result nil)
        (failure nil)
        (callback-thread nil)
        (prompt-thread nil))
    (labels
        ((cancelled-p ()
           (sb-thread:with-mutex (lock)
             cancelled-p))
         (complete (value error)
           (sb-thread:with-mutex (lock)
             (unless done-p
               (setf result value
                     failure error
                     done-p t
                     cancelled-p t)
               (sb-thread:condition-broadcast condition))))
         (cancel ()
           (complete
            nil
            (make-condition
             'authentication-error
             :message "Login cancelled")))
         (callback-worker ()
           (handler-case
               (let ((code
                       (funcall callback-function
                                #'cancelled-p)))
                 (when code
                   (complete code nil)))
             (error ()
               ;; A failed loopback listener does not invalidate the manual
               ;; authorization-code path.
               nil)))
         (prompt-worker ()
           (handler-case
               (let* ((prompt-value (copy-list prompt))
                      (_
                        (setf
                         (getf prompt-value :cancel-function)
                         #'cancel
                         (getf prompt-value :cancelled-p-function)
                         #'cancelled-p))
                      (input
                        (funcall prompt-function prompt-value)))
                 (declare (ignore _))
                 (unless input
                   (cancel)
                   (return-from prompt-worker nil))
                 (multiple-value-bind (code state)
                     (parse-oauth-authorization-input input)
                   (when (and state
                              (not (string= state expected-state)))
                     (error 'authentication-error
                            :message "State mismatch"))
                   (unless (non-empty-string-p code)
                     (error 'authentication-error
                            :message "Missing authorization code"))
                   (complete code nil)))
             (error (cause)
               (complete
                nil
                (if (typep cause 'authentication-error)
                    cause
                    (make-condition
                     'authentication-error
                     :message "Login cancelled"
                     :cause cause)))))))
      (setf
       callback-thread
       (sb-thread:make-thread
        #'callback-worker
        :name "cadr-oauth-loopback-callback")
       prompt-thread
       (sb-thread:make-thread
        #'prompt-worker
        :name "cadr-oauth-manual-code"))
      (sb-thread:with-mutex (lock)
        (loop until done-p
              do (sb-thread:condition-wait condition lock)))
      (stop-thread-for-cleanup callback-thread :timeout 1d0)
      (stop-thread-for-cleanup prompt-thread :timeout 1d0)
      (when failure
        (error failure))
      result)))

(defun present-oauth-auth-url
    (url output auth-url-function)
  (if auth-url-function
      (funcall auth-url-function url)
      (format output
              "Open this URL in your browser:~%~A~%"
              url))
  (finish-output output)
  url)

(defun login-openai-oauth (auth-path
                           &key
                             (output *standard-output*)
                             (open-browser *oauth-browser-open-function*)
                             auth-url-function
                             auth-prompt-function)
  (multiple-value-bind (verifier challenge)
      (generate-pkce)
    (let* ((state (oauth-state))
           (url (openai-authorization-url challenge state)))
      (unless auth-prompt-function
        (present-oauth-auth-url
         url output auth-url-function))
      (handler-case
          (funcall open-browser url)
        (error ()
          (format output
                  "Could not open a browser automatically; use the URL above.~%")
          (finish-output output)))
      (let ((credential
              (exchange-openai-authorization-code
               (if auth-prompt-function
                   (wait-for-oauth-authorization
                    state
                    (lambda (cancelled-p)
                      (wait-for-openai-oauth-code
                       state cancelled-p))
                    auth-prompt-function
                    (list
                     :type :manual-code
                     :title "Login to OpenAI (ChatGPT Plus/Pro)"
                     :url url
                     :instructions
                     "A browser window should open. Complete login to finish."
                     :message
                     "Complete login in your browser, or paste the authorization code / redirect URL here:"
                     :placeholder +openai-oauth-redirect-uri+))
                   (wait-for-openai-oauth-code state))
               verifier)))
        (unless (non-empty-string-p
                 (oauth-credential-account-id credential))
          (error 'authentication-error
                 :message
                 "OpenAI OAuth token does not contain chatgpt_account_id"))
        (when auth-path
          (write-auth-credential auth-path credential))
        credential))))

(defun login-anthropic-oauth
    (auth-path
     &key
       (output *standard-output*)
       (open-browser *oauth-browser-open-function*)
       auth-url-function
       auth-prompt-function)
  ;; This mirrors the fixed reference implementation but remains live-unverified.
  (multiple-value-bind (verifier challenge)
      (generate-pkce)
    (let* ((state verifier)
           (url (anthropic-authorization-url challenge state)))
      (format output
              "Anthropic subscription OAuth is unverified and may violate provider terms.~%")
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
                      (wait-for-oauth-code
                       state 53692 "/callback" "Anthropic"
                       cancelled-p))
                    auth-prompt-function
                    (list
                     :type :manual-code
                     :title "Login to Anthropic (Claude Pro/Max)"
                     :url url
                     :instructions
                     "A browser window should open. Complete login to finish."
                     :message
                     "Complete login in your browser, or paste the authorization code / redirect URL here:"
                     :placeholder +anthropic-oauth-redirect-uri+))
                   (wait-for-oauth-code
                    state 53692 "/callback" "Anthropic")))
             (credential
               (exchange-anthropic-authorization-code
                code state verifier)))
        (when auth-path
          (write-auth-credential auth-path credential))
        credential))))
