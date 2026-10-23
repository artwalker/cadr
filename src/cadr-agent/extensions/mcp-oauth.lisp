(in-package #:cadr-agent)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-bsd-sockets)
  (require :sb-posix))

;;; Adapted from modelcontextprotocol/typescript-sdk v1.29.0. Copyright (c) 2024 Anthropic, PBC. Licensed under MIT; see docs/third-party/modelcontextprotocol-typescript-sdk-LICENSE.txt.
;;; One JSON state record per server URL. HTTP is a boundary the caller
;;; can replace; the flow itself does not keep a second copy of the grant.

(defparameter +mcp-oauth-callback-host+ "127.0.0.1")
(defparameter +mcp-oauth-callback-path+ "/callback")
(defparameter +mcp-oauth-client-metadata-base+ "https://pi.dev/oauth")
(defparameter +mcp-oauth-fallback-redirect+ "http://127.0.0.1/callback")
(defparameter +mcp-oauth-refresh-skew-ms+ 30000)
(defparameter +mcp-oauth-request-timeout-ms+ 15000)
(defparameter +mcp-oauth-refresh-lock-stale-seconds+ 20)
(defparameter +mcp-oauth-refresh-lock-wait-seconds+ 25)

(define-condition mcp-oauth-error (error)
  ((code :initarg :code :reader mcp-oauth-error-code)
   (description :initarg :description :reader mcp-oauth-error-description)
   (error-uri :initarg :error-uri :initform nil :reader mcp-oauth-error-uri))
  (:report (lambda (condition stream)
             (write-string (mcp-oauth-error-description condition) stream))))

(define-condition mcp-oauth-issuer-mismatch-error (error)
  ((expected :initarg :expected :reader mcp-oauth-issuer-expected)
   (received :initarg :received :reader mcp-oauth-issuer-received))
  (:report (lambda (condition stream)
             (format stream "OAuth issuer mismatch: expected ~A, received ~A"
                     (mcp-oauth-issuer-text (mcp-oauth-issuer-expected condition))
                     (mcp-oauth-issuer-text (mcp-oauth-issuer-received condition))))))

(define-condition mcp-oauth-insecure-endpoint-error (error)
  ((endpoint :initarg :endpoint :reader mcp-oauth-insecure-endpoint))
  (:report (lambda (condition stream)
             (format stream
                     "Refusing to send OAuth credentials to non-HTTPS endpoint ~A"
                     (mcp-oauth-insecure-endpoint condition)))))

(define-condition mcp-oauth-registration-error (error)
  ((status :initarg :status :reader mcp-oauth-registration-status)
   (body :initarg :body :reader mcp-oauth-registration-body))
  (:report (lambda (condition stream)
             (format stream
                     "OAuth dynamic client registration failed with status ~A: ~A"
                     (mcp-oauth-registration-status condition)
                     (mcp-oauth-registration-body condition)))))

(define-condition mcp-oauth-authorization-required-error (error) ()
  (:report (lambda (condition stream)
             (declare (ignore condition))
             (write-string "MCP OAuth authorization requires user interaction"
                           stream))))

(define-condition mcp-oauth-sign-in-cancelled (error) ()
  (:report (lambda (condition stream)
             (declare (ignore condition))
             (write-string "Sign-in cancelled" stream))))

(define-condition mcp-oauth-abort-error (error) ()
  (:report (lambda (condition stream)
             (declare (ignore condition))
             (write-string "This operation was aborted" stream))))

(defun mcp-oauth-issuer-text (issuer)
  (if issuer
      (cadr-ai::stringify-json issuer)
      "none"))

(defun mcp-oauth-absent-p (value present)
  (or (not present)
      (eq value 'null)
      (and (stringp value) (zerop (length value)))))

(defun mcp-oauth-object (&rest pairs)
  (list* :json-object
         (loop for (key value) on pairs by #'cddr
               unless (eq value :omit)
                 nconc (list key value))))

(defun mcp-oauth-string-list (value)
  (when (mcp-json-sequence-p value)
    (coerce value 'list)))

(defun mcp-oauth-require-string (value name)
  (unless (and (stringp value) (plusp (length value)))
    (error "Invalid ~A" name))
  value)

(defun mcp-oauth-optional-string (value present name)
  (cond
    ((mcp-oauth-absent-p value present) :omit)
    ((and (stringp value) (plusp (length value))) value)
    (t (error "Invalid ~A" name))))

(defun mcp-oauth-optional-strings (value present name)
  (cond
    ((or (not present) (eq value 'null)) :omit)
    ((and (mcp-json-sequence-p value)
          (every #'stringp (coerce value 'list)))
     (coerce value 'vector))
    (t (error "Invalid ~A" name))))

(defun mcp-oauth-parse-url (text)
  (unless (stringp text)
    (return-from mcp-oauth-parse-url nil))
  (let ((parsed (parse-mcp-url text)))
    (when parsed
      (return-from mcp-oauth-parse-url parsed))
    (let ((colon (position #\: text)))
      (unless (and colon (plusp colon))
        (return-from mcp-oauth-parse-url nil))
      (let* ((rest (subseq text (1+ colon)))
             (path (if (and (plusp (length rest)) (char= (char rest 0) #\/))
                       rest
                       (concatenate 'string "/" rest))))
        (list :protocol (concatenate 'string (subseq text 0 (1+ colon)))
              :hostname ""
              :port ""
              :pathname path
              :search ""
              :hash "")))))

(defun mcp-oauth-href (text)
  (let ((url (mcp-oauth-parse-url text)))
    (unless url
      (return-from mcp-oauth-href text))
    (let ((protocol (mcp-url-part url :protocol))
          (host (string-downcase (mcp-url-part url :hostname)))
          (port (mcp-url-part url :port)))
      (when (or (and (string= protocol "https:") (string= port "443"))
                (and (string= protocol "http:") (string= port "80")))
        (setf port ""))
      (if (zerop (length host))
          (format nil "~A~A~A~A"
                  protocol
                  (mcp-url-part url :pathname)
                  (mcp-url-part url :search)
                  (mcp-url-part url :hash))
          (format nil "~A//~A~@[~A~]~A~A~A"
                  protocol
                  host
                  (and (plusp (length port)) (format nil ":~A" port))
                  (mcp-url-part url :pathname)
                  (mcp-url-part url :search)
                  (mcp-url-part url :hash))))))

(defun mcp-oauth-origin (text)
  (let ((url (mcp-oauth-parse-url text)))
    (unless url
      (error "Invalid ~A" text))
    (let ((protocol (mcp-url-part url :protocol))
          (host (string-downcase (mcp-url-part url :hostname)))
          (port (mcp-url-part url :port)))
      (when (or (and (string= protocol "https:") (string= port "443"))
                (and (string= protocol "http:") (string= port "80")))
        (setf port ""))
      (format nil "~A//~A~@[~A~]"
              protocol host
              (and (plusp (length port)) (format nil ":~A" port))))))

(defun mcp-oauth-join (origin path)
  (format nil "~A~A" origin (if (and (plusp (length path))
                                     (char= (char path 0) #\/))
                                path
                                (concatenate 'string "/" path))))

(defun mcp-oauth-replace-path (text pathname)
  (let ((url (mcp-oauth-parse-url text)))
    (unless url
      (return-from mcp-oauth-replace-path text))
    (setf (getf url :pathname) pathname)
    (mcp-oauth-href
     (format nil "~A//~A~@[~A~]~A~A~A"
             (mcp-url-part url :protocol)
             (mcp-url-part url :hostname)
             (and (plusp (length (mcp-url-part url :port)))
                  (format nil ":~A" (mcp-url-part url :port)))
             pathname
             (mcp-url-part url :search)
             (mcp-url-part url :hash)))))

(defun mcp-oauth-safe-url (value name)
  (let ((text (mcp-oauth-require-string value name)))
    (let ((url (mcp-oauth-parse-url text)))
      (unless url
        (error "Invalid ~A" name))
      (when (member (mcp-url-part url :protocol)
                    '("javascript:" "data:" "vbscript:")
                    :test #'string=)
        (error "Invalid ~A" name))
      text)))

(defun mcp-oauth-loopback-p (hostname)
  (member hostname '("localhost" "127.0.0.1" "[::1]" "::1") :test #'string=))

(defun mcp-oauth-form-encode (text)
  (with-output-to-string (output)
    (loop for octet across (cadr-ai::utf8-octets (or text ""))
          do (cond
               ((or (<= 48 octet 57)
                    (<= 65 octet 90)
                    (<= 97 octet 122)
                    (member octet '(42 45 46 95)))
                (write-char (code-char octet) output))
               ((= octet 32)
                (write-char #\+ output))
               (t (format output "%~2,'0X" octet))))))

(defun mcp-oauth-form-decode (text)
  (let ((octets (make-array 0
                            :element-type '(unsigned-byte 8)
                            :adjustable t
                            :fill-pointer 0))
        (index 0))
    (loop while (< index (length text))
          do (let ((character (char text index)))
               (cond
                 ((char= character #\+)
                  (vector-push-extend 32 octets)
                  (incf index))
                 ((and (char= character #\%)
                       (<= (+ index 2) (1- (length text)))
                       (digit-char-p (char text (1+ index)) 16)
                       (digit-char-p (char text (+ index 2)) 16))
                  (vector-push-extend
                   (parse-integer text :start (1+ index) :end (+ index 3) :radix 16)
                   octets)
                  (incf index 3))
                 (t
                  (loop for octet across (cadr-ai::utf8-octets (string character))
                        do (vector-push-extend octet octets))
                  (incf index)))))
    (cadr-ai::utf8-string octets)))

(defun mcp-oauth-query (pairs)
  (with-output-to-string (output)
    (loop for (key . value) in pairs
          for separator = "" then "&"
          do (format output "~A~A=~A"
                     separator
                     (mcp-oauth-form-encode key)
                     (mcp-oauth-form-encode (or value ""))))))

(defun mcp-oauth-query-alist (text)
  (let ((pairs nil))
    (loop for piece in (uiop:split-string (or text "") :separator '(#\&))
          unless (zerop (length piece))
            do (let ((equal (position #\= piece)))
                 (push (cons (mcp-oauth-form-decode
                              (if equal (subseq piece 0 equal) piece))
                             (mcp-oauth-form-decode
                              (if equal (subseq piece (1+ equal)) "")))
                       pairs)))
    (nreverse pairs)))

(defun mcp-oauth-query-get (pairs name)
  (cdr (assoc name pairs :test #'string=)))

(defun mcp-oauth-standard-base64 (octets)
  (let ((alphabet
          "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"))
    (with-output-to-string (output)
      (loop for index from 0 below (length octets) by 3
            for remaining = (- (length octets) index)
            for first = (aref octets index)
            for second = (if (> remaining 1) (aref octets (1+ index)) 0)
            for third = (if (> remaining 2) (aref octets (+ index 2)) 0)
            for bits = (logior (ash first 16) (ash second 8) third)
            do (write-char (char alphabet (ldb (byte 6 18) bits)) output)
               (write-char (char alphabet (ldb (byte 6 12) bits)) output)
               (if (> remaining 1)
                   (write-char (char alphabet (ldb (byte 6 6) bits)) output)
                   (write-char #\= output))
               (if (> remaining 2)
                   (write-char (char alphabet (ldb (byte 6 0) bits)) output)
                   (write-char #\= output))))))

(defun mcp-oauth-hex (octets)
  (with-output-to-string (output)
    (loop for byte across octets
          do (format output "~2,'0x" byte))))

(defun mcp-oauth-pkce ()
  (let* ((verifier (cadr-ai::base64url-encode (cadr-ai::secure-random-bytes 32)))
         (challenge (cadr-ai:pkce-challenge verifier)))
    (values verifier challenge)))

(defun mcp-oauth-aborted-p (signal)
  (and signal (funcall signal)))

(defun mcp-oauth-check-abort (signal)
  (when (mcp-oauth-aborted-p signal)
    (error 'mcp-oauth-abort-error)))

(defun mcp-oauth-http (url &key (method :get) headers body signal
                           (timeout-ms +mcp-oauth-request-timeout-ms+))
  (mcp-oauth-check-abort signal)
  (let ((cadr-ai::*native-http-abort-p*
          (lambda () (mcp-oauth-aborted-p signal))))
    (handler-case
        (multiple-value-bind (payload status response-headers)
            (cadr-ai::native-http-request
             url
             :method method
             :headers headers
             :content body
             :force-string t
             :connect-timeout (max 1 (ceiling timeout-ms 1000))
             :read-timeout (max 1 (ceiling timeout-ms 1000)))
          (mcp-oauth-check-abort signal)
          (values status (or payload "") response-headers))
      (mcp-oauth-abort-error (condition)
        (error condition))
      (cadr-ai:network-error (condition)
        (if (mcp-oauth-aborted-p signal)
            (error 'mcp-oauth-abort-error)
            (error condition))))))

(defun mcp-oauth-call-fetch (fetch url &key (method :get) headers body signal)
  (mcp-oauth-check-abort signal)
  (if fetch
      (funcall fetch url :method method :headers headers :body body :signal signal)
      (mcp-oauth-http url :method method :headers headers :body body :signal signal)))

(defun mcp-oauth-header-field (header name)
  (let ((match
          (nth-value
           1
           (cl-ppcre:scan-to-strings
            (format nil "(?i)(?:^|[,\\s])~A=(?:\"([^\"]*)\"|([^\\s,]+))" name)
            (or header "")))))
    (when match
      (let ((value (or (and (aref match 0) (not (zerop (length (aref match 0))))
                            (aref match 0))
                       (and (aref match 1) (not (zerop (length (aref match 1))))
                            (aref match 1)))))
        value))))

(defun mcp-oauth-parse-www-authenticate (header)
  (unless (and (stringp header) (plusp (length (string-trim '(#\Space #\Tab) header))))
    (return-from mcp-oauth-parse-www-authenticate
      (mcp-oauth-object "resourceMetadataUrl" :omit "scope" :omit
                        "error" :omit "errorDescription" :omit)))
  (let* ((trimmed (string-left-trim '(#\Space #\Tab) header))
         (space (position-if (lambda (character)
                               (member character '(#\Space #\Tab #\Newline #\Return)))
                             trimmed))
         (scheme (string-downcase (if space (subseq trimmed 0 space) trimmed))))
    (unless (or (string= scheme "bearer") (string= scheme "dpop"))
      (return-from mcp-oauth-parse-www-authenticate
        (mcp-oauth-object "resourceMetadataUrl" :omit "scope" :omit
                          "error" :omit "errorDescription" :omit)))
    (let ((resource (mcp-oauth-header-field header "resource_metadata")))
      (mcp-oauth-object
       "resourceMetadataUrl"
       (if (and resource (mcp-oauth-parse-url resource)) resource :omit)
       "scope" (or (mcp-oauth-header-field header "scope") :omit)
       "error" (or (mcp-oauth-header-field header "error") :omit)
       "errorDescription"
       (or (mcp-oauth-header-field header "error_description") :omit)))))

(defun mcp-oauth-path-suffix (pathname)
  (if (and (plusp (length pathname))
           (char= (char pathname (1- (length pathname))) #\/))
      (subseq pathname 0 (1- (length pathname)))
      pathname))

(defun mcp-oauth-discovery-miss-p (status)
  (or (and (>= status 400) (< status 500)) (= status 502)))

(defun mcp-oauth-trim-slash (text)
  (if (and (plusp (length text)) (char= (char text (1- (length text))) #\/))
      (subseq text 0 (1- (length text)))
      text))

(defun mcp-oauth-parse-protected-resource (value)
  (unless (mcp-object-p value)
    (error "Invalid OAuth protected resource metadata"))
  (let ((result (mcp-copy-json value)))
    (setf result
          (mcp-put result "resource"
                   (mcp-oauth-safe-url (mcp-get value "resource")
                                       "OAuth protected resource metadata resource")))
    (multiple-value-bind (servers present)
        (mcp-get value "authorization_servers")
      (let ((parsed (mcp-oauth-optional-strings servers present "authorization_servers")))
        (if (eq parsed :omit)
            (setf result (mcp-delete result "authorization_servers"))
            (setf result
                  (mcp-put result "authorization_servers"
                           (map 'vector
                                (lambda (url)
                                  (mcp-oauth-safe-url url "authorization server URL"))
                                parsed))))))
    (multiple-value-bind (scopes present) (mcp-get value "scopes_supported")
      (let ((parsed (mcp-oauth-optional-strings scopes present "scopes_supported")))
        (if (eq parsed :omit)
            (setf result (mcp-delete result "scopes_supported"))
            (setf result (mcp-put result "scopes_supported" parsed)))))
    result))

(defun mcp-oauth-parse-authorization-metadata (value)
  (unless (mcp-object-p value)
    (error "Invalid authorization server metadata"))
  (multiple-value-bind (response-types present)
      (mcp-get value "response_types_supported")
    (let ((types (mcp-oauth-optional-strings response-types present
                                             "response_types_supported")))
      (when (eq types :omit)
        (error "Invalid response_types_supported"))
      (let ((result (mcp-copy-json value)))
        (setf result
              (mcp-put result "issuer"
                       (mcp-oauth-safe-url (mcp-get value "issuer")
                                           "authorization server issuer")))
        (setf result
              (mcp-put result "authorization_endpoint"
                       (mcp-oauth-safe-url (mcp-get value "authorization_endpoint")
                                           "authorization endpoint")))
        (setf result
              (mcp-put result "token_endpoint"
                       (mcp-oauth-safe-url (mcp-get value "token_endpoint")
                                           "token endpoint")))
        (setf result (mcp-put result "response_types_supported" types))
        (flet ((optional-url (key name)
                 (multiple-value-bind (item item-p) (mcp-get value key)
                   (let ((parsed (mcp-oauth-optional-string item item-p name)))
                     (if (eq parsed :omit)
                         (setf result (mcp-delete result key))
                         (setf result
                               (mcp-put result key (mcp-oauth-safe-url parsed name)))))))
               (optional-list (key)
                 (multiple-value-bind (item item-p) (mcp-get value key)
                   (let ((parsed (mcp-oauth-optional-strings item item-p key)))
                     (if (eq parsed :omit)
                         (setf result (mcp-delete result key))
                         (setf result (mcp-put result key parsed)))))))
          (optional-url "registration_endpoint" "registration endpoint")
          (optional-list "scopes_supported")
          (optional-list "grant_types_supported")
          (optional-list "token_endpoint_auth_methods_supported")
          (optional-list "code_challenge_methods_supported"))
        (dolist (key '("client_id_metadata_document_supported"
                       "authorization_response_iss_parameter_supported"))
          (multiple-value-bind (item item-p) (mcp-get value key)
            (if (and item-p (or (eq item t) (null item)) (not (eq item 'null)))
                (setf result (mcp-put result key item))
                (setf result (mcp-delete result key)))))
        result))))

(defun mcp-oauth-parse-tokens (value)
  (unless (mcp-object-p value)
    (error "Invalid OAuth token response"))
  (multiple-value-bind (expires present) (mcp-get value "expires_in")
    (let ((expires-in
            (cond
              ((mcp-oauth-absent-p expires present) :omit)
              ((realp expires) expires)
              ((and (stringp expires)
                    (every (lambda (character)
                             (or (digit-char-p character) (char= character #\.)))
                           expires)
                    (plusp (length expires)))
               (read-from-string expires))
              (t (error "Invalid expires_in")))))
      (when (and (not (eq expires-in :omit))
                 (not (mcp-oauth-finite-p expires-in)))
        (error "Invalid expires_in"))
      (mcp-oauth-object
       "access_token" (mcp-oauth-require-string (mcp-get value "access_token")
                                                "access_token")
       "token_type" (mcp-oauth-require-string (mcp-get value "token_type")
                                              "token_type")
       "expires_in" expires-in
       "scope" (mcp-oauth-optional-string
                (mcp-get value "scope")
                (nth-value 1 (mcp-get value "scope"))
                "scope")
       "refresh_token" (mcp-oauth-optional-string
                        (mcp-get value "refresh_token")
                        (nth-value 1 (mcp-get value "refresh_token"))
                        "refresh_token")
       "id_token" (mcp-oauth-optional-string
                   (mcp-get value "id_token")
                   (nth-value 1 (mcp-get value "id_token"))
                   "id_token")))))

(defun mcp-oauth-parse-client-information (value)
  (unless (mcp-object-p value)
    (error "Invalid OAuth client registration response"))
  (let ((result (mcp-copy-json value)))
    (setf result
          (mcp-put result "client_id"
                   (mcp-oauth-require-string (mcp-get value "client_id") "client_id")))
    (dolist (key '("client_secret"))
      (multiple-value-bind (item item-p) (mcp-get value key)
        (let ((parsed (mcp-oauth-optional-string item item-p key)))
          (if (eq parsed :omit)
              (setf result (mcp-delete result key))
              (setf result (mcp-put result key parsed))))))
    (dolist (key '("client_id_issued_at" "client_secret_expires_at"))
      (multiple-value-bind (item item-p) (mcp-get value key)
        (if (and item-p (realp item))
            (setf result (mcp-put result key item))
            (setf result (mcp-delete result key)))))
    (multiple-value-bind (uris present) (mcp-get value "redirect_uris")
      (let ((parsed (mcp-oauth-optional-strings uris present "redirect_uris")))
        (setf result
              (mcp-put result "redirect_uris"
                       (if (eq parsed :omit)
                           (make-array 0 :element-type t)
                           parsed)))))
    result))

(defun mcp-oauth-build-authorization-discovery-urls (issuer-url)
  (let* ((issuer (mcp-oauth-parse-url issuer-url))
         (origin (mcp-oauth-origin issuer-url))
         (path (mcp-oauth-path-suffix (or (mcp-url-part issuer :pathname) "/")))
         (urls (list (cons (mcp-oauth-join origin (format nil "/.well-known/oauth-authorization-server~A" path))
                           "oauth")
                     (cons (mcp-oauth-join origin (format nil "/.well-known/openid-configuration~A" path))
                           "oidc"))))
    (when (plusp (length path))
      (setf urls
            (append urls
                    (list (cons (mcp-oauth-join origin
                                                (format nil "~A/.well-known/openid-configuration" path))
                                "oidc")))))
    urls))

(defun mcp-oauth-discover-protected-resource
    (server-url &key resource-metadata-url fetch signal)
  (let* ((server (mcp-oauth-parse-url server-url))
         (origin (mcp-oauth-origin server-url))
         (suffix (mcp-oauth-path-suffix (mcp-url-part server :pathname)))
         (first (or resource-metadata-url
                    (mcp-oauth-join
                     origin
                     (format nil "/.well-known/oauth-protected-resource~A" suffix)))))
    (multiple-value-bind (status body headers)
        (mcp-oauth-call-fetch
         fetch first
         :headers (list (cons "Accept" "application/json")
                        (cons "MCP-Protocol-Version" +mcp-latest-protocol-version+))
         :signal signal)
      (declare (ignorable headers))
      (when (and (not resource-metadata-url)
                 (not (string= (mcp-url-part server :pathname) "/"))
                 (mcp-oauth-discovery-miss-p status))
        (multiple-value-setq (status body headers)
          (mcp-oauth-call-fetch
           fetch
           (mcp-oauth-join origin "/.well-known/oauth-protected-resource")
           :headers (list (cons "Accept" "application/json")
                          (cons "MCP-Protocol-Version" +mcp-latest-protocol-version+))
           :signal signal)))
      (unless (<= 200 status 299)
        (error "HTTP ~A loading OAuth protected resource metadata" status))
      (mcp-oauth-parse-protected-resource (mcp-read-json body)))))

(defun mcp-oauth-discover-authorization-metadata
    (authorization-server-url &key fetch signal skip-issuer-validation)
    (loop for url in (mapcar #'car
                             (mcp-oauth-build-authorization-discovery-urls
                              authorization-server-url))
        do (multiple-value-bind (status body)
               (mcp-oauth-call-fetch
                fetch url
                :headers (list (cons "Accept" "application/json")
                               (cons "MCP-Protocol-Version" +mcp-latest-protocol-version+))
                :signal signal)
             (cond
               ((<= 200 status 299)
                (let ((metadata (mcp-oauth-parse-authorization-metadata
                                 (mcp-read-json body))))
                  (unless skip-issuer-validation
                    (let ((expected (if (stringp authorization-server-url)
                                        authorization-server-url
                                        (mcp-oauth-href authorization-server-url))))
                      (unless (string= (mcp-oauth-trim-slash (mcp-get metadata "issuer"))
                                       (mcp-oauth-trim-slash expected))
                        (error 'mcp-oauth-issuer-mismatch-error
                               :expected expected
                               :received (mcp-get metadata "issuer")))))
                  (return-from mcp-oauth-discover-authorization-metadata metadata)))
               ((mcp-oauth-discovery-miss-p status) nil)
               (t (error "HTTP ~A loading authorization server metadata from ~A"
                         status url)))))
  nil)

(defun mcp-oauth-discover-server-info
    (server-url &key resource-metadata-url authorization-server-metadata-url
                fetch signal skip-issuer-validation)
  (let ((resource nil))
    (handler-case
        (setf resource
              (mcp-oauth-discover-protected-resource
               server-url
               :resource-metadata-url resource-metadata-url
               :fetch fetch
               :signal signal))
      (mcp-oauth-abort-error (condition) (error condition))
      (cadr-ai:network-error (condition) (error condition))
      (error ()
        (setf resource nil)))
    (when authorization-server-metadata-url
      (multiple-value-bind (status body)
          (mcp-oauth-call-fetch
           fetch authorization-server-metadata-url
           :headers (list (cons "Accept" "application/json")
                          (cons "MCP-Protocol-Version" +mcp-latest-protocol-version+))
           :signal signal)
        (unless (<= 200 status 299)
          (error "HTTP ~A loading authorization server metadata from ~A"
                 status authorization-server-metadata-url))
        (let ((metadata (mcp-oauth-parse-authorization-metadata (mcp-read-json body))))
          (return-from mcp-oauth-discover-server-info
            (list :authorization-server-url (mcp-get metadata "issuer")
                  :metadata metadata
                  :resource resource)))))
    (let* ((servers (and resource (mcp-oauth-string-list
                                   (mcp-get resource "authorization_servers"))))
           (authorization-server
             (or (first servers)
                 (mcp-oauth-join (mcp-oauth-origin server-url) "/"))))
      (list :authorization-server-url authorization-server
            :metadata (mcp-oauth-discover-authorization-metadata
                       authorization-server
                       :fetch fetch
                       :signal signal
                       :skip-issuer-validation skip-issuer-validation)
            :resource resource))))

(defun mcp-oauth-select-resource (server-url metadata)
  (unless metadata
    (return-from mcp-oauth-select-resource nil))
  (let* ((requested (mcp-oauth-href
                     (let ((url (mcp-oauth-parse-url server-url)))
                       (setf (getf url :hash) "")
                       (mcp-oauth-href
                        (format nil "~A//~A~@[~A~]~A~A"
                                (mcp-url-part url :protocol)
                                (mcp-url-part url :hostname)
                                (and (plusp (length (mcp-url-part url :port)))
                                     (format nil ":~A" (mcp-url-part url :port)))
                                (mcp-url-part url :pathname)
                                (mcp-url-part url :search))))))
         (configured (mcp-get metadata "resource"))
         (requested-url (mcp-oauth-parse-url requested))
         (configured-url (mcp-oauth-parse-url configured)))
    (unless (and configured-url
                 (string= (mcp-oauth-origin requested)
                          (mcp-oauth-origin configured)))
      (error "Protected resource ~A does not match MCP server ~A"
             configured requested))
    (let ((requested-path
            (let ((path (mcp-url-part requested-url :pathname)))
              (if (and (plusp (length path))
                       (char= (char path (1- (length path))) #\/))
                  path
                  (concatenate 'string path "/"))))
          (configured-path
            (let ((path (mcp-url-part configured-url :pathname)))
              (if (and (plusp (length path))
                       (char= (char path (1- (length path))) #\/))
                  path
                  (concatenate 'string path "/")))))
      (unless (uiop:string-prefix-p configured-path requested-path)
        (error "Protected resource ~A does not match MCP server ~A"
               configured requested))
      configured)))

(defun mcp-oauth-application-type (redirect-uris)
  (if (some (lambda (uri)
              (let ((url (mcp-oauth-parse-url uri)))
                (and url
                     (or (not (member (mcp-url-part url :protocol)
                                      '("http:" "https:") :test #'string=))
                         (mcp-oauth-loopback-p (mcp-url-part url :hostname))))))
            redirect-uris)
      "native"
      "web"))

(defun mcp-oauth-secure-endpoint (value)
  (let* ((text (if (stringp value) value (mcp-oauth-href value)))
         (url (mcp-oauth-parse-url text)))
    (unless (and url
                 (or (string= (mcp-url-part url :protocol) "https:")
                     (mcp-oauth-loopback-p (mcp-url-part url :hostname))))
      (error 'mcp-oauth-insecure-endpoint-error :endpoint (mcp-oauth-href text)))
    (mcp-oauth-href text)))

(defun mcp-oauth-select-client-auth (information supported)
  (let ((hinted (when (nth-value 1 (mcp-get information "token_endpoint_auth_method"))
                  (mcp-get information "token_endpoint_auth_method")))
        (secret (and (nth-value 1 (mcp-get information "client_secret"))
                     (mcp-get information "client_secret"))))
    (when (and (stringp hinted)
               (member hinted '("client_secret_basic" "client_secret_post" "none")
                       :test #'string=)
               (or (null supported) (member hinted supported :test #'string=)))
      (return-from mcp-oauth-select-client-auth hinted))
    (cond
      ((null supported) (if secret "client_secret_basic" "none"))
      ((and secret (member "client_secret_basic" supported :test #'string=))
       "client_secret_basic")
      ((and secret (member "client_secret_post" supported :test #'string=))
       "client_secret_post")
      ((member "none" supported :test #'string=) "none")
      (secret "client_secret_post")
      (t "none"))))

(defun mcp-oauth-apply-client-auth (method information headers params)
  (cond
    ((string= method "client_secret_basic")
     (unless (mcp-get information "client_secret")
       (error "client_secret_basic requires a client secret"))
     (values (acons "Authorization"
                    (format nil "Basic ~A"
                            (mcp-oauth-standard-base64
                             (cadr-ai::utf8-octets
                              (format nil "~A:~A"
                                      (mcp-get information "client_id")
                                      (mcp-get information "client_secret")))))
                    headers)
             params))
    (t
     (push (cons "client_id" (mcp-get information "client_id")) params)
     (when (and (string= method "client_secret_post")
                (mcp-get information "client_secret"))
       (push (cons "client_secret" (mcp-get information "client_secret")) params))
     (values headers params))))

(defun mcp-oauth-start-authorization
    (authorization-server-url &key metadata client redirect-url scope state resource)
  (when (and metadata
             (not (member "code"
                          (mcp-oauth-string-list
                           (mcp-get metadata "response_types_supported"))
                          :test #'string=)))
    (error "Authorization server does not support authorization codes"))
  (let ((methods (and metadata
                      (nth-value 1 (mcp-get metadata "code_challenge_methods_supported"))
                      (mcp-oauth-string-list
                       (mcp-get metadata "code_challenge_methods_supported")))))
    (when (and methods (not (member "S256" methods :test #'string=)))
      (error "Authorization server does not support PKCE S256")))
  (multiple-value-bind (verifier challenge) (mcp-oauth-pkce)
    (let* ((endpoint (or (and metadata (mcp-get metadata "authorization_endpoint"))
                         (mcp-oauth-join (mcp-oauth-origin authorization-server-url)
                                         "/authorize")))
           (pairs (list (cons "response_type" "code")
                        (cons "client_id" (mcp-get client "client_id"))
                        (cons "code_challenge" challenge)
                        (cons "code_challenge_method" "S256")
                        (cons "redirect_uri" redirect-url))))
      (when state
        (setf pairs (append pairs (list (cons "state" state)))))
      (when scope
        (setf pairs (append pairs (list (cons "scope" scope)))))
      (when (and scope (member "offline_access"
                               (uiop:split-string scope :separator '(#\Space))
                               :test #'string=))
        (setf pairs (append pairs (list (cons "prompt" "consent")))))
      (when resource
        (setf pairs (append pairs (list (cons "resource" resource)))))
      (values (format nil "~A?~A" endpoint (mcp-oauth-query pairs)) verifier))))

(defun mcp-oauth-token-request (authorization-server-url params
                                &key metadata client resource add-authentication
                                  fetch signal)
  (let* ((endpoint (mcp-oauth-secure-endpoint
                    (or (and metadata (mcp-get metadata "token_endpoint"))
                        (mcp-oauth-join (mcp-oauth-origin authorization-server-url)
                                        "/token"))))
         (headers (list (cons "Accept" "application/json")
                        (cons "Content-Type" "application/x-www-form-urlencoded")))
         (body-pairs (copy-list params)))
    (when resource
      (setf body-pairs (append body-pairs (list (cons "resource" resource)))))
    (if add-authentication
        (funcall add-authentication headers body-pairs endpoint metadata)
        (multiple-value-bind (next-headers next-pairs)
            (mcp-oauth-apply-client-auth
             (mcp-oauth-select-client-auth
              client
              (or (and metadata
                       (mcp-oauth-string-list
                        (mcp-get metadata "token_endpoint_auth_methods_supported")))
                  nil))
             client headers body-pairs)
          (setf headers next-headers
                body-pairs next-pairs)))
    (multiple-value-bind (status text)
        (mcp-oauth-call-fetch fetch endpoint
                              :method :post
                              :headers headers
                              :body (mcp-oauth-query body-pairs)
                              :signal signal)
      (let ((value (ignore-errors (mcp-read-json text))))
        (when (and (mcp-object-p value) (stringp (mcp-get value "error")))
          (error 'mcp-oauth-error
                 :code (mcp-get value "error")
                 :description (let ((description (mcp-get value "error_description")))
                                (if (stringp description)
                                    description
                                    (mcp-get value "error")))
                 :error-uri (let ((uri (mcp-get value "error_uri")))
                              (when (stringp uri) uri))))
        (unless (<= 200 status 299)
          (error 'mcp-oauth-error
                 :code "server_error"
                 :description (format nil "HTTP ~A: ~A" status text)))
        (mcp-oauth-parse-tokens value)))))

(defun mcp-oauth-register-client (authorization-server-url &key metadata client-metadata
                                                              scope fetch signal)
  (let ((endpoint (and metadata (mcp-get metadata "registration_endpoint"))))
    (when (and metadata (not endpoint))
      (error "Authorization server does not support dynamic client registration"))
    (let* ((redirects (mcp-oauth-string-list (mcp-get client-metadata "redirect_uris")))
           (body (mcp-copy-json client-metadata))
           (application
             (or (and (nth-value 1 (mcp-get client-metadata "application_type"))
                      (mcp-get client-metadata "application_type"))
                 (mcp-oauth-application-type redirects))))
      (setf body (mcp-put body "application_type" application))
      (when (and scope (plusp (length scope)))
        (setf body (mcp-put body "scope" scope)))
      (multiple-value-bind (status text)
          (mcp-oauth-call-fetch
           fetch
           (or endpoint
               (mcp-oauth-join (mcp-oauth-origin authorization-server-url) "/register"))
           :method :post
           :headers (list (cons "Accept" "application/json")
                          (cons "Content-Type" "application/json"))
           :body (mcp-write-json body)
           :signal signal)
        (unless (<= 200 status 299)
          (error 'mcp-oauth-registration-error :status status :body text))
        (mcp-oauth-parse-client-information (mcp-read-json text))))))

(defun mcp-oauth-exchange-code (authorization-server-url &key metadata client code
                                                          verifier redirect-url resource
                                                          fetch signal add-authentication)
  (mcp-oauth-token-request
   authorization-server-url
   (list (cons "grant_type" "authorization_code")
         (cons "code" code)
         (cons "code_verifier" verifier)
         (cons "redirect_uri" redirect-url))
   :metadata metadata
   :client client
   :resource resource
   :fetch fetch
   :signal signal
   :add-authentication add-authentication))

(defun mcp-oauth-refresh (authorization-server-url refresh-token &key metadata client
                                                                    resource fetch signal
                                                                    add-authentication)
  (let ((tokens
          (mcp-oauth-token-request
           authorization-server-url
           (list (cons "grant_type" "refresh_token")
                 (cons "refresh_token" refresh-token))
           :metadata metadata
           :client client
           :resource resource
           :fetch fetch
           :signal signal
           :add-authentication add-authentication)))
    (if (nth-value 1 (mcp-get tokens "refresh_token"))
        tokens
        (mcp-put tokens "refresh_token" refresh-token))))

(defun mcp-oauth-with-scope (tokens scope)
  (if (and (not (nth-value 1 (mcp-get tokens "scope")))
           (stringp scope)
           (plusp (length scope)))
      (mcp-put tokens "scope" scope)
      tokens))

(defun mcp-oauth-step-up-scope (granted challenged)
  (unless (and (stringp challenged) (plusp (length challenged)))
    (return-from mcp-oauth-step-up-scope nil))
  (let ((scopes nil))
    (dolist (source (list granted challenged))
      (when (stringp source)
        (dolist (piece (uiop:split-string source :separator '(#\Space #\Tab)))
          (when (and (plusp (length piece))
                     (not (member piece scopes :test #'string=)))
            (setf scopes (append scopes (list piece)))))))
    (format nil "~{~A~^ ~}" scopes)))

(defun mcp-oauth-merge-scopes (&rest scopes)
  (mcp-oauth-step-up-scope nil
                           (format nil "~{~A~^ ~}"
                                   (remove nil scopes))))

(defstruct (mcp-oauth-provider (:constructor %make-mcp-oauth-provider))
  server-url
  redirect-url
  client-metadata
  client-metadata-document
  configured-client
  store
  on-redirect
  add-authentication
  (lock (sb-thread:make-mutex :name "mcp oauth provider")))

(defstruct mcp-oauth-memory-state
  value
  (lock (sb-thread:make-mutex :name "mcp oauth memory")))

(defun mcp-oauth-memory-state-load (store)
  (sb-thread:with-mutex ((mcp-oauth-memory-state-lock store))
    (when (mcp-oauth-memory-state-value store)
      (mcp-copy-json (mcp-oauth-memory-state-value store)))))

(defun mcp-oauth-memory-state-save (store state)
  (sb-thread:with-mutex ((mcp-oauth-memory-state-lock store))
    (setf (mcp-oauth-memory-state-value store) (mcp-copy-json state)))
  nil)

(defun make-mcp-oauth-memory-store ()
  (let ((state (make-mcp-oauth-memory-state)))
    (list :load (lambda () (mcp-oauth-memory-state-load state))
          :save (lambda (value) (mcp-oauth-memory-state-save state value)))))

(defun mcp-oauth-store-load (store)
  (funcall (getf store :load)))

(defun mcp-oauth-store-save (store state)
  (funcall (getf store :save) state))

(defun mcp-oauth-provider-own (provider state)
  (if (and (mcp-object-p state)
           (string= (mcp-get state "serverUrl") (mcp-oauth-provider-server-url provider)))
      state
      (mcp-oauth-object "serverUrl" (mcp-oauth-provider-server-url provider))))

(defun mcp-oauth-provider-update (provider updater)
  (sb-thread:with-mutex ((mcp-oauth-provider-lock provider))
    (let ((next (funcall updater
                         (mcp-oauth-provider-own
                          provider
                          (mcp-oauth-store-load (mcp-oauth-provider-store provider))))))
      (mcp-oauth-store-save (mcp-oauth-provider-store provider) next))))

(defun mcp-oauth-provider-state (provider)
  (let ((existing (mcp-get (mcp-oauth-provider-own
                            provider
                            (mcp-oauth-store-load (mcp-oauth-provider-store provider)))
                           "oauthState")))
    (when (and (stringp existing) (plusp (length existing)))
      (return-from mcp-oauth-provider-state existing))
    (let ((state (mcp-oauth-hex (cadr-ai::secure-random-bytes 32))))
      (mcp-oauth-provider-update
       provider
       (lambda (value) (mcp-put value "oauthState" state)))
      state)))

(defun mcp-oauth-provider-client (provider)
  (or (mcp-oauth-provider-configured-client provider)
      (let ((state (mcp-oauth-provider-own
                    provider
                    (mcp-oauth-store-load (mcp-oauth-provider-store provider)))))
        (when (nth-value 1 (mcp-get state "clientInformation"))
          (mcp-get state "clientInformation")))))

(defun mcp-oauth-provider-save-client (provider information)
  (when (mcp-oauth-provider-configured-client provider)
    (return-from mcp-oauth-provider-save-client nil))
  (mcp-oauth-provider-update
   provider
   (lambda (value) (mcp-put value "clientInformation" information))))

(defun mcp-oauth-provider-tokens (provider)
  (let ((state (mcp-oauth-provider-own
                provider
                (mcp-oauth-store-load (mcp-oauth-provider-store provider)))))
    (when (nth-value 1 (mcp-get state "tokens"))
      (mcp-get state "tokens"))))

(defun mcp-oauth-provider-save-tokens (provider tokens)
  (let ((expires (when (nth-value 1 (mcp-get tokens "expires_in"))
                   (+ (cadr-core:unix-milliseconds)
                      (round (* (mcp-get tokens "expires_in") 1000))))))
    (mcp-oauth-provider-update
     provider
     (lambda (value)
       (setf value (mcp-put value "tokens" tokens))
       (if expires
           (mcp-put value "tokensExpireAt" expires)
           (mcp-delete value "tokensExpireAt"))))))

(defun mcp-oauth-provider-verifier (provider)
  (let ((verifier (mcp-get (mcp-oauth-provider-own
                            provider
                            (mcp-oauth-store-load (mcp-oauth-provider-store provider)))
                           "codeVerifier")))
    (unless (and (stringp verifier) (plusp (length verifier)))
      (error "No OAuth PKCE code verifier is stored"))
    verifier))

(defun mcp-oauth-provider-invalidate (provider kind)
  (mcp-oauth-provider-update
   provider
   (lambda (value)
     (when (or (string= kind "all") (string= kind "client"))
       (setf value (mcp-delete value "clientInformation")))
     (when (or (string= kind "all") (string= kind "tokens"))
       (setf value (mcp-delete (mcp-delete value "tokens") "tokensExpireAt")))
     (when (or (string= kind "all") (string= kind "verifier"))
       (setf value (mcp-delete value "codeVerifier")))
     (when (or (string= kind "all") (string= kind "discovery"))
       (setf value (mcp-delete value "discovery")))
     (when (string= kind "all")
       (setf value (mcp-delete value "oauthState")))
     value)))

(defun make-mcp-oauth-provider (&key server-url redirect-url client-metadata
                                  client-metadata-document client-id client-secret
                                  store on-redirect add-authentication)
  (%make-mcp-oauth-provider
   :server-url (mcp-oauth-href server-url)
   :redirect-url (if (stringp redirect-url) redirect-url (mcp-oauth-href redirect-url))
   :client-metadata
   (mcp-oauth-object
    "client_name" (or (and client-metadata (mcp-get client-metadata "client_name"))
                      cadr-ai::+cadr-product-display-name+)
    "redirect_uris" (or (and client-metadata
                             (nth-value 1 (mcp-get client-metadata "redirect_uris"))
                             (mcp-get client-metadata "redirect_uris"))
                        (vector redirect-url))
    "grant_types" (or (and client-metadata
                           (nth-value 1 (mcp-get client-metadata "grant_types"))
                           (mcp-get client-metadata "grant_types"))
                      (vector "authorization_code" "refresh_token"))
    "response_types" (or (and client-metadata
                              (nth-value 1 (mcp-get client-metadata "response_types"))
                              (mcp-get client-metadata "response_types"))
                         (vector "code"))
    "token_endpoint_auth_method"
    (or (and client-metadata
             (nth-value 1 (mcp-get client-metadata "token_endpoint_auth_method"))
             (mcp-get client-metadata "token_endpoint_auth_method"))
        (if client-secret "client_secret_post" "none")))
   :client-metadata-document client-metadata-document
   :configured-client (when client-id
                        (mcp-oauth-object "client_id" client-id
                                          "client_secret" (or client-secret :omit)))
   :store (or store (make-mcp-oauth-memory-store))
   :on-redirect (or on-redirect (lambda (url) (declare (ignore url)) nil))
   :add-authentication add-authentication))

(defun mcp-oauth-scope-fallback (&rest values)
  (loop for value in values
        when (and (stringp value) (plusp (length value)))
          return value))

(defun mcp-oauth-run-flow (provider &key server-url authorization-code iss scope
                                     resource-metadata-url authorization-server-metadata-url
                                     fetch signal skip-issuer-validation skip-refresh)
  (let* ((metadata-url (when authorization-server-metadata-url
                         (mcp-oauth-secure-endpoint authorization-server-metadata-url)))
         (cached (unless metadata-url
                   (let ((state (mcp-oauth-provider-own
                                 provider
                                 (mcp-oauth-store-load (mcp-oauth-provider-store provider)))))
                     (when (nth-value 1 (mcp-get state "discovery"))
                       (mcp-get state "discovery")))))
         (discovered
           (if (and cached (mcp-get cached "authorizationServerUrl"))
               (list :authorization-server-url (mcp-get cached "authorizationServerUrl")
                     :metadata (or (and (nth-value 1
                                                   (mcp-get cached "authorizationServerMetadata"))
                                        (mcp-get cached "authorizationServerMetadata"))
                                   (mcp-oauth-discover-authorization-metadata
                                    (mcp-get cached "authorizationServerUrl")
                                    :fetch fetch
                                    :signal signal
                                    :skip-issuer-validation skip-issuer-validation))
                     :resource (when (nth-value 1 (mcp-get cached "resourceMetadata"))
                                 (mcp-get cached "resourceMetadata")))
               (mcp-oauth-discover-server-info
                server-url
                :resource-metadata-url resource-metadata-url
                :authorization-server-metadata-url metadata-url
                :fetch fetch
                :signal signal
                :skip-issuer-validation skip-issuer-validation))))
    (unless metadata-url
      (let ((record
              (mcp-oauth-object
               "authorizationServerUrl" (getf discovered :authorization-server-url)
               "authorizationServerMetadata" (or (getf discovered :metadata) :omit)
               "resourceMetadata" (or (getf discovered :resource) :omit)
               "resourceMetadataUrl" (or resource-metadata-url :omit))))
        (mcp-oauth-provider-update
         provider
         (lambda (value) (mcp-put value "discovery" record)))))
    (let* ((metadata (getf discovered :metadata))
           (resource (mcp-oauth-select-resource server-url (getf discovered :resource)))
           (chosen (mcp-oauth-scope-fallback
                    scope
                    (when (getf discovered :resource)
                      (let ((scopes (mcp-oauth-string-list
                                     (mcp-get (getf discovered :resource) "scopes_supported"))))
                        (when scopes (format nil "~{~A~^ ~}" scopes))))
                    (mcp-get (mcp-oauth-provider-client-metadata provider) "scope")))
           (stored (mcp-oauth-provider-client provider))
           (document (unless stored
                       (let ((builder (mcp-oauth-provider-client-metadata-document provider)))
                         (when builder (funcall builder metadata)))))
           (client stored))
      (when document
        (let ((url (mcp-oauth-parse-url (getf document :url))))
          (unless (and url
                       (string= (mcp-url-part url :protocol) "https:")
                       (not (string= (mcp-url-part url :pathname) "/")))
            (error "Invalid OAuth client metadata URL"))))
      (unless client
        (when document
          (setf client (mcp-oauth-object "client_id" (getf document :url)))))
      (unless client
        (when authorization-code
          (error "OAuth client information is missing during code exchange"))
        (setf client
              (mcp-oauth-register-client
               (getf discovered :authorization-server-url)
               :metadata metadata
               :client-metadata (mcp-oauth-provider-client-metadata provider)
               :scope chosen
               :fetch fetch
               :signal signal))
        (mcp-oauth-provider-save-client provider client))
      (let ((redirect (or (and document (getf document :redirect))
                          (mcp-oauth-provider-redirect-url provider))))
        (when authorization-code
          (when (or iss
                    (and metadata
                         (eq (mcp-get metadata
                                      "authorization_response_iss_parameter_supported")
                             t)))
            (unless (equal iss (and metadata (mcp-get metadata "issuer")))
              (error 'mcp-oauth-issuer-mismatch-error
                     :expected (and metadata (mcp-get metadata "issuer"))
                     :received iss)))
          (let ((tokens
                  (mcp-oauth-exchange-code
                   (getf discovered :authorization-server-url)
                   :metadata metadata
                   :client client
                   :code authorization-code
                   :verifier (mcp-oauth-provider-verifier provider)
                   :redirect-url redirect
                   :resource resource
                   :fetch fetch
                   :signal signal
                   :add-authentication (mcp-oauth-provider-add-authentication provider))))
            (mcp-oauth-provider-save-tokens provider (mcp-oauth-with-scope tokens chosen))
            (return-from mcp-oauth-run-flow "AUTHORIZED")))
        (let ((existing (unless skip-refresh (mcp-oauth-provider-tokens provider))))
          (when (and existing (mcp-get existing "refresh_token"))
            (handler-case
                (let ((tokens
                        (mcp-oauth-refresh
                         (getf discovered :authorization-server-url)
                         (mcp-get existing "refresh_token")
                         :metadata metadata
                         :client client
                         :resource resource
                         :fetch fetch
                         :signal signal
                         :add-authentication
                         (mcp-oauth-provider-add-authentication provider))))
                  (mcp-oauth-provider-save-tokens
                   provider
                   (mcp-oauth-with-scope tokens (mcp-get existing "scope")))
                  (return-from mcp-oauth-run-flow "AUTHORIZED"))
              (mcp-oauth-abort-error (condition) (error condition))
              (mcp-oauth-insecure-endpoint-error (condition) (error condition))
              (mcp-oauth-error (condition)
                (unless (string= (mcp-oauth-error-code condition) "server_error")
                  (error condition)))
              (cadr-ai:network-error ()
                (when (mcp-oauth-aborted-p signal)
                  (error 'mcp-oauth-abort-error))))))
          (let ((state (mcp-oauth-provider-state provider)))
            (multiple-value-bind (authorization verifier)
                (mcp-oauth-start-authorization
                 (getf discovered :authorization-server-url)
                 :metadata metadata
                 :client client
                 :redirect-url redirect
                 :scope chosen
                 :state state
                 :resource resource)
              (mcp-oauth-provider-update
               provider
               (lambda (value) (mcp-put value "codeVerifier" verifier)))
              (funcall (mcp-oauth-provider-on-redirect provider) authorization)
              "REDIRECT"))))))

(defun mcp-oauth-authorize (provider &rest args &key &allow-other-keys)
  (handler-case
      (apply #'mcp-oauth-run-flow provider args)
    (mcp-oauth-error (condition)
      (cond
        ((member (mcp-oauth-error-code condition)
                 '("invalid_client" "unauthorized_client") :test #'string=)
         (mcp-oauth-provider-invalidate provider "all")
         (apply #'mcp-oauth-run-flow provider args))
        ((string= (mcp-oauth-error-code condition) "invalid_grant")
         (mcp-oauth-provider-invalidate provider "tokens")
         (apply #'mcp-oauth-run-flow provider args))
        (t (error condition))))))

(defun mcp-oauth-share-flight (box work)
  (let ((mutex (svref box 0))
        (queue (svref box 1))
        (runner nil))
    (sb-thread:with-mutex (mutex)
      (cond
        ((svref box 2)
         (loop while (svref box 2)
               do (sb-thread:condition-wait queue mutex)))
        (t
         (setf (svref box 2) t
               (svref box 3) nil
               runner t))))
    (when runner
      (unwind-protect
           (handler-case (funcall work)
             (error (condition)
               (setf (svref box 3) condition)))
        (sb-thread:with-mutex (mutex)
          (setf (svref box 2) nil)
          (sb-thread:condition-broadcast queue))))
    (when (svref box 3)
      (error (svref box 3)))))

(defun mcp-oauth-adapt-provider (provider)
  (let ((box (vector (sb-thread:make-mutex :name "mcp oauth adapt")
                     (sb-thread:make-waitqueue :name "mcp oauth adapt")
                     nil
                     nil)))
    (make-mcp-oauth-auth
     :token (lambda ()
              (let ((tokens (mcp-oauth-provider-tokens provider)))
                (when tokens (mcp-get tokens "access_token"))))
     :unauthorized
     (lambda (context)
       (block recover
         (let* ((challenge (mcp-oauth-parse-www-authenticate
                            (cadr-ai::header-value (getf context :headers)
                                                   "www-authenticate")))
                (insufficient (equal (mcp-get challenge "error") "insufficient_scope"))
                (running (sb-thread:with-mutex ((svref box 0)) (svref box 2))))
           (when (and (not insufficient)
                      (not running)
                      (getf context :token))
             (let* ((tokens (mcp-oauth-provider-tokens provider))
                    (current (and tokens (mcp-get tokens "access_token"))))
               (when (and current (not (equal current (getf context :token))))
                 (return-from recover nil))))
         (mcp-oauth-share-flight
          box
          (lambda ()
            (let* ((granted (when insufficient (mcp-oauth-provider-tokens provider)))
                   (result
                     (mcp-oauth-authorize
                      provider
                      :server-url (getf context :server-url)
                      :resource-metadata-url (let ((url (mcp-get challenge "resourceMetadataUrl")))
                                               (unless (eq url :omit) url))
                      :scope (if insufficient
                                 (mcp-oauth-step-up-scope
                                  (and granted (mcp-get granted "scope"))
                                  (let ((scope (mcp-get challenge "scope")))
                                    (unless (eq scope :omit) scope)))
                                 (let ((scope (mcp-get challenge "scope")))
                                   (unless (eq scope :omit) scope)))
                      :fetch (getf context :fetch)
                      :skip-refresh insufficient)))
              (when (string= result "REDIRECT")
                (error 'mcp-oauth-authorization-required-error)))))))))))

(defstruct (mcp-oauth-auth (:constructor %make-mcp-oauth-auth))
  (token (lambda () nil) :type function)
  (unauthorized (lambda (context) (declare (ignore context)) nil) :type function)
  (settled (lambda () nil) :type function))

(defun make-mcp-oauth-auth (&key token unauthorized settled)
  (%make-mcp-oauth-auth
   :token (or token (lambda () nil))
   :unauthorized (or unauthorized (lambda (context) (declare (ignore context)) nil))
   :settled (or settled (lambda () nil))))

(defun mcp-oauth-finite-p (value)
  (and (realp value)
       (not (and (floatp value)
                 (or (sb-ext:float-infinity-p value)
                     (sb-ext:float-nan-p value))))))

(defun mcp-oauth-callback-id (server-url)
  (let* ((href (mcp-oauth-href server-url))
         (hash (position #\# href))
         (text (if hash (subseq href 0 hash) href))
         (digest (cadr-ai::sha256-bytes (cadr-ai::utf8-octets text)))
         (prefix (make-array 9 :element-type '(unsigned-byte 8))))
    (replace prefix digest)
    (cadr-ai::base64url-encode prefix)))

(defun mcp-oauth-client-document (server-url redirect-url metadata)
  (let ((methods (and metadata
                      (mcp-oauth-string-list
                       (mcp-get metadata "token_endpoint_auth_methods_supported")))))
    (unless (and metadata
                 (eq (mcp-get metadata "client_id_metadata_document_supported") t)
                 (member "none" methods :test #'string=))
      (error "The authorization server does not support Client ID Metadata Documents for public clients; remove oauth.clientRegistration \"cimd\""))
    (if (eq (mcp-get metadata "authorization_response_iss_parameter_supported") t)
        (list :url (format nil "~A/client.json" +mcp-oauth-client-metadata-base+)
              :redirect redirect-url)
        (let ((id (mcp-oauth-callback-id server-url)))
          (list :url (format nil "~A/~A/client.json" +mcp-oauth-client-metadata-base+ id)
                :redirect (mcp-oauth-replace-path
                           redirect-url
                           (format nil "~A/~A" +mcp-oauth-callback-path+ id)))))))

(defstruct mcp-oauth-settings
  client-id
  client-secret
  callback-port
  callback-url
  scope
  client-name
  client-registration
  auth-server-metadata-url)

(defun mcp-oauth-settings-from-config (config name)
  (let ((oauth (mcp-get config "oauth")))
    (unless (mcp-object-p oauth)
      (return-from mcp-oauth-settings-from-config (make-mcp-oauth-settings)))
    (make-mcp-oauth-settings
     :client-id (let ((value (mcp-get oauth "clientId")))
                  (when (stringp value) value))
     :client-secret (when (nth-value 1 (mcp-get oauth "clientSecret"))
                      (mcp-resolve-config-value
                       (mcp-get oauth "clientSecret")
                       (format nil "MCP server ~S oauth.clientSecret" name)))
     :callback-port (let ((value (mcp-get oauth "callbackPort")))
                      (when (integerp value) value))
     :callback-url (let ((value (mcp-get oauth "callbackUrl")))
                     (when (stringp value) value))
     :scope (let ((value (mcp-get oauth "scope")))
              (when (stringp value) value))
     :client-name (let ((value (mcp-get oauth "clientName")))
                    (when (stringp value) value))
     :client-registration (let ((value (mcp-get oauth "clientRegistration")))
                            (when (stringp value) value))
     :auth-server-metadata-url
     (let ((value (mcp-get oauth "authServerMetadataUrl")))
       (when (stringp value) value)))))

(defun mcp-oauth-callback-settings (settings)
  (let* ((text (or (mcp-oauth-settings-callback-url settings)
                   (format nil "http://~A~A"
                           +mcp-oauth-callback-host+
                           +mcp-oauth-callback-path+)))
         (url (mcp-oauth-parse-url text))
         (address (remove #\[ (remove #\] (mcp-url-part url :hostname))))
         (url-port (mcp-url-part url :port))
         (port (if (plusp (length url-port))
                   (parse-integer url-port)
                   (mcp-oauth-settings-callback-port settings)))
         (fixed nil))
    (cond
      ((plusp (length url-port))
       (setf fixed (mcp-oauth-settings-callback-url settings)))
      (port
       (setf (getf url :port) (princ-to-string port))
       (setf fixed
             (format nil "~A//~A:~A~A~A~A"
                     (mcp-url-part url :protocol)
                     (mcp-url-part url :hostname)
                     port
                     (mcp-url-part url :pathname)
                     (mcp-url-part url :search)
                     (mcp-url-part url :hash)))))
    (list :host (if (string= address "localhost") +mcp-oauth-callback-host+ address)
          :redirect-host address
          :port port
          :path (mcp-url-part url :pathname)
          :fixed fixed)))

(defstruct mcp-oauth-callback
  host
  redirect-url
  paths
  timeout-ms
  render-page
  (pending (make-hash-table :test #'equal))
  (lock (sb-thread:make-mutex :name "mcp oauth callback"))
  socket
  thread
  (closed-p nil :type boolean))

(defun mcp-oauth-callback-reply (stream status page render)
  (let* ((html (and render (funcall render page)))
         (body (or html
                   (if (getf page :ok)
                       "Authorization complete. You may close this window."
                       (if (getf page :details)
                           (format nil "~A~%~%~A" (getf page :message) (getf page :details))
                           (getf page :message)))))
         (octets (cadr-ai::utf8-octets body))
         (reason (case status
                   (200 "OK")
                   (400 "Bad Request")
                   (404 "Not Found")
                   (t "Error"))))
    (format stream "HTTP/1.1 ~A ~A~C~C" status reason #\Return #\Newline)
    (if html
        (format stream "content-type: text/html; charset=utf-8~C~Ccache-control: no-store~C~C"
                #\Return #\Newline #\Return #\Newline)
        (format stream "content-type: text/plain; charset=utf-8~C~C" #\Return #\Newline))
    (format stream "content-length: ~A~C~Cconnection: close~C~C~C~C"
            (length octets) #\Return #\Newline #\Return #\Newline #\Return #\Newline)
    (write-string body stream)
    (finish-output stream)))

(defun mcp-oauth-callback-handle (server raw-path stream)
  (let* ((slash (or (position #\? raw-path) (length raw-path)))
         (path (subseq raw-path 0 slash))
         (query (if (< slash (length raw-path)) (subseq raw-path (1+ slash)) ""))
         (params (mcp-oauth-query-alist query)))
    (unless (member path (mcp-oauth-callback-paths server) :test #'string=)
      (mcp-oauth-callback-reply stream 404 (list :ok nil :message "Not found")
                                (mcp-oauth-callback-render-page server))
      (return-from mcp-oauth-callback-handle nil))
    (let* ((state (mcp-oauth-query-get params "state"))
           (pending (when state
                      (sb-thread:with-mutex ((mcp-oauth-callback-lock server))
                        (gethash state (mcp-oauth-callback-pending server))))))
      (unless pending
        (mcp-oauth-callback-reply
         stream 400 (list :ok nil :message "Invalid or expired OAuth state")
         (mcp-oauth-callback-render-page server))
        (return-from mcp-oauth-callback-handle nil))
      (sb-thread:with-mutex ((mcp-oauth-callback-lock server))
        (remhash state (mcp-oauth-callback-pending server)))
      (let ((expected (getf pending :path)))
        (when (and expected (not (string= path expected)))
          (setf (getf pending :error)
                (make-condition 'simple-error
                                :format-control
                                "The authorization response arrived on another redirect URI"
                                :format-arguments nil))
          (sb-thread:signal-semaphore (getf pending :semaphore))
          (mcp-oauth-callback-reply
           stream 400 (list :ok nil :message "Unexpected redirect URI")
           (mcp-oauth-callback-render-page server))
          (return-from mcp-oauth-callback-handle nil)))
      (let ((oauth-error (mcp-oauth-query-get params "error")))
        (when oauth-error
          (let ((description (or (mcp-oauth-query-get params "error_description")
                                 oauth-error)))
            (setf (getf pending :error)
                  (make-condition 'simple-error
                                  :format-control "~A"
                                  :format-arguments (list description)))
            (sb-thread:signal-semaphore (getf pending :semaphore))
            (mcp-oauth-callback-reply
             stream 200
             (list :ok nil
                   :message "Authorization failed. You may close this window."
                   :details description)
             (mcp-oauth-callback-render-page server))
            (return-from mcp-oauth-callback-handle nil))))
      (let ((code (mcp-oauth-query-get params "code")))
        (unless (and code (plusp (length code)))
          (setf (getf pending :error)
                (make-condition 'simple-error
                                :format-control
                                "OAuth callback did not include an authorization code"
                                :format-arguments nil))
          (sb-thread:signal-semaphore (getf pending :semaphore))
          (mcp-oauth-callback-reply
           stream 400 (list :ok nil :message "Missing authorization code")
           (mcp-oauth-callback-render-page server))
          (return-from mcp-oauth-callback-handle nil))
        (setf (getf pending :result)
              (list :code code :state state :iss (mcp-oauth-query-get params "iss")))
        (sb-thread:signal-semaphore (getf pending :semaphore))
        (mcp-oauth-callback-reply stream 200 (list :ok t)
                                  (mcp-oauth-callback-render-page server))))))

(defun mcp-oauth-callback-read-line (stream)
  (let ((line (make-array 0 :element-type 'character :adjustable t :fill-pointer 0)))
    (loop for character = (read-char stream nil nil)
          while (and character (not (char= character #\Newline)))
          do (unless (char= character #\Return)
               (vector-push-extend character line)))
    line))

(defun mcp-oauth-callback-accept (server)
  (loop until (mcp-oauth-callback-closed-p server)
        do (handler-case
               (let ((client (sb-bsd-sockets:socket-accept
                              (mcp-oauth-callback-socket server))))
                 (sb-thread:make-thread
                  (lambda ()
                    (unwind-protect
                         (handler-case
                             (let ((stream (sb-bsd-sockets:socket-make-stream
                                            client
                                            :input t :output t
                                            :element-type 'character
                                            :external-format :utf-8
                                            :buffering :none)))
                               (unwind-protect
                                    (let ((line (mcp-oauth-callback-read-line stream)))
                                      (loop for header = (mcp-oauth-callback-read-line stream)
                                            while (plusp (length header)))
                                      (when (uiop:string-prefix-p "GET " line)
                                        (let ((target (second (uiop:split-string
                                                               line :separator '(#\Space)))))
                                          (when target
                                            (mcp-oauth-callback-handle server target stream)))))
                                 (close stream)))
                           (error () nil))
                      (ignore-errors (sb-bsd-sockets:socket-close client))))
                  :name "mcp oauth callback request"))
             (error ()
               (return)))))

(defun mcp-oauth-callback-listen (&key host redirect-host port path extra-paths
                                    timeout-ms render-page)
  (let* ((host (or host +mcp-oauth-callback-host+))
         (redirect-host (or redirect-host host))
         (path (or path +mcp-oauth-callback-path+))
         (socket (make-instance 'sb-bsd-sockets:inet-socket
                                :type :stream :protocol :tcp)))
    (setf (sb-bsd-sockets:sockopt-reuse-address socket) t)
    (sb-bsd-sockets:socket-bind socket #(127 0 0 1) (or port 0))
    (sb-bsd-sockets:socket-listen socket 16)
    (let* ((bound (nth-value 1 (sb-bsd-sockets:socket-name socket)))
           (shown (if (find #\: redirect-host)
                      (format nil "[~A]" redirect-host)
                      redirect-host))
           (server
             (make-mcp-oauth-callback
              :host host
              :redirect-url (format nil "http://~A:~A~A" shown bound path)
              :paths (cons path (copy-list extra-paths))
              :timeout-ms (or timeout-ms (* 5 60 1000))
              :render-page render-page
              :socket socket)))
      (setf (mcp-oauth-callback-thread server)
            (sb-thread:make-thread
             (lambda () (mcp-oauth-callback-accept server))
             :name "mcp oauth callback"))
      server)))

(defun mcp-oauth-callback-wait (server state &optional expected-path)
  (let ((pending nil))
    (sb-thread:with-mutex ((mcp-oauth-callback-lock server))
      (when (gethash state (mcp-oauth-callback-pending server))
        (error "OAuth state is already pending"))
      (setf pending (list :path expected-path
                          :semaphore (sb-thread:make-semaphore :name "mcp oauth wait")
                          :result nil
                          :error nil))
      (setf (gethash state (mcp-oauth-callback-pending server)) pending))
    (sb-thread:make-thread
     (lambda ()
       (sleep (/ (mcp-oauth-callback-timeout-ms server) 1000.0))
       (sb-thread:with-mutex ((mcp-oauth-callback-lock server))
         (when (eq (gethash state (mcp-oauth-callback-pending server)) pending)
           (remhash state (mcp-oauth-callback-pending server))
           (setf (getf pending :error)
                 (make-condition 'simple-error
                                 :format-control "OAuth callback timed out"
                                 :format-arguments nil))
           (sb-thread:signal-semaphore (getf pending :semaphore)))))
     :name "mcp oauth callback timer")
    (sb-thread:wait-on-semaphore (getf pending :semaphore))
    (when (getf pending :error)
      (error (getf pending :error)))
    (getf pending :result)))

(defun mcp-oauth-callback-close (server)
  (setf (mcp-oauth-callback-closed-p server) t)
  (sb-thread:with-mutex ((mcp-oauth-callback-lock server))
    (maphash (lambda (state pending)
               (declare (ignore state))
               (setf (getf pending :error)
                     (make-condition 'simple-error
                                     :format-control "OAuth callback server closed"
                                     :format-arguments nil))
               (sb-thread:signal-semaphore (getf pending :semaphore)))
             (mcp-oauth-callback-pending server))
    (clrhash (mcp-oauth-callback-pending server)))
  (ignore-errors (sb-bsd-sockets:socket-close (mcp-oauth-callback-socket server)))
  nil)

(defun mcp-oauth-redirect-urls (client)
  (when (and (mcp-object-p client)
             (nth-value 1 (mcp-get client "redirect_uris")))
    (mcp-oauth-string-list (mcp-get client "redirect_uris"))))

(defun mcp-oauth-response-from-redirect (input state redirect-url)
  (let ((url (mcp-oauth-parse-url (string-trim '(#\Space #\Tab #\Newline #\Return) input))))
    (unless url
      (error "Expected the full redirect URL from the browser address bar"))
    (let ((expected (mcp-oauth-parse-url redirect-url)))
      (unless (and (string= (mcp-oauth-origin input) (mcp-oauth-origin redirect-url))
                   (string= (mcp-url-part url :pathname)
                            (mcp-url-part expected :pathname)))
        (error "The redirect URL does not match this sign-in's redirect URI")))
    (let ((params (mcp-oauth-query-alist
                   (string-left-trim '(#\?) (mcp-url-part url :search)))))
      (let ((oauth-error (mcp-oauth-query-get params "error")))
        (when oauth-error
          (error "~A" (or (mcp-oauth-query-get params "error_description") oauth-error))))
      (unless (equal (mcp-oauth-query-get params "state") state)
        (error "The redirect URL belongs to a different sign-in"))
      (let ((code (mcp-oauth-query-get params "code")))
        (unless (and code (plusp (length code)))
          (error "The redirect URL does not contain an authorization code"))
        (list :code code :iss (mcp-oauth-query-get params "iss"))))))

(defun mcp-oauth-sign-in (server-url store settings &key challenge show-url paste
                                                     fetch signal timeout-ms)
  (when (mcp-oauth-aborted-p signal)
    (error 'mcp-oauth-sign-in-cancelled))
  (let* ((stored (mcp-oauth-store-load store))
         (step-up (and challenge (equal (mcp-get challenge "error") "insufficient_scope")))
         (callback-options (mcp-oauth-callback-settings settings))
         (registered (first (mcp-oauth-redirect-urls
                             (and stored (mcp-get stored "clientInformation")))))
         (preferred (or (getf callback-options :port)
                        (when registered
                          (let ((port (mcp-url-part (mcp-oauth-parse-url registered) :port)))
                            (when (plusp (length port)) (parse-integer port))))))
         (cimd (equal (mcp-oauth-settings-client-registration settings) "cimd"))
         (render (lambda (page)
                   (if (getf page :ok)
                       (cadr-ai::oauth-success-html
                        "Signed in to the MCP server. You may now close this page.")
                       (cadr-ai::oauth-error-html (getf page :message) (getf page :details)))))
         (callback
           (handler-case
               (mcp-oauth-callback-listen
                :host (getf callback-options :host)
                :redirect-host (getf callback-options :redirect-host)
                :port preferred
                :path (getf callback-options :path)
                :extra-paths (when cimd
                               (list (format nil "~A/~A"
                                             +mcp-oauth-callback-path+
                                             (mcp-oauth-callback-id server-url))))
                :timeout-ms timeout-ms
                :render-page render)
             (error (condition)
               (if (or (getf callback-options :port) (null preferred))
                   (error condition)
                   (mcp-oauth-callback-listen
                    :host (getf callback-options :host)
                    :redirect-host (getf callback-options :redirect-host)
                    :path (getf callback-options :path)
                    :extra-paths (when cimd
                                   (list (format nil "~A/~A"
                                                 +mcp-oauth-callback-path+
                                                 (mcp-oauth-callback-id server-url))))
                    :timeout-ms timeout-ms
                    :render-page render))))))
    (unwind-protect
         (handler-case
             (let ((redirect (or (getf callback-options :fixed)
                                 (mcp-oauth-callback-redirect-url callback))))
               (when stored
                 (let ((next (mcp-copy-json stored)))
                   (setf next (mcp-delete next "oauthState"))
                   (let ((keep (or (mcp-oauth-settings-client-id settings)
                                   (if cimd
                                       (not (nth-value 1 (mcp-get stored "clientInformation")))
                                       (member redirect
                                               (mcp-oauth-redirect-urls
                                                (mcp-get stored "clientInformation"))
                                               :test #'string=)))))
                     (unless keep
                       (setf next (mcp-delete next "clientInformation"))
                       (setf next (mcp-delete next "tokens"))
                       (setf next (mcp-delete next "tokensExpireAt"))))
                   (mcp-oauth-store-save store next)))
               (let* ((authorization nil)
                      (provider
                        (make-mcp-oauth-provider
                        :server-url server-url
                        :redirect-url redirect
                        :client-metadata
                        (mcp-oauth-object
                         "client_name"
                         (or (mcp-oauth-settings-client-name settings)
                             cadr-ai::+cadr-product-display-name+))
                        :client-metadata-document
                        (when cimd
                          (lambda (metadata)
                            (mcp-oauth-client-document server-url redirect metadata)))
                        :client-id (mcp-oauth-settings-client-id settings)
                        :client-secret (mcp-oauth-settings-client-secret settings)
                        :store store
                        :on-redirect (lambda (url) (setf authorization url)))))
                 (let ((flow-scope
                         (mcp-oauth-merge-scopes
                          (mcp-oauth-settings-scope settings)
                          (if step-up
                              (mcp-oauth-step-up-scope
                               (and stored
                                    (mcp-get stored "tokens")
                                    (mcp-get (mcp-get stored "tokens") "scope"))
                               (and challenge (mcp-get challenge "scope")))
                              (and challenge (mcp-get challenge "scope"))))))
                   (when (string= (mcp-oauth-authorize
                                   provider
                                   :server-url server-url
                                   :fetch fetch
                                   :signal signal
                                   :resource-metadata-url
                                   (and challenge (mcp-get challenge "resourceMetadataUrl"))
                                   :authorization-server-metadata-url
                                   (mcp-oauth-settings-auth-server-metadata-url settings)
                                   :scope flow-scope
                                   :skip-refresh step-up)
                                  "AUTHORIZED")
                     (return-from mcp-oauth-sign-in nil))
                   (unless authorization
                     (error "OAuth flow did not produce an authorization URL"))
                     (let* ((state (mcp-oauth-provider-state provider))
                          (redirect-param
                            (or (mcp-oauth-query-get
                                 (mcp-oauth-query-alist
                                  (let ((query (subseq authorization
                                                       (or (position #\? authorization)
                                                           (length authorization)))))
                                    (string-left-trim '(#\?) query)))
                                 "redirect_uri")
                                redirect))
                          (aborted nil)
                          (prompt-signal (lambda ()
                                           (or aborted (mcp-oauth-aborted-p signal))))
                          (waiters
                            (list (lambda ()
                                    (mcp-oauth-callback-wait
                                     callback state
                                     (mcp-url-part (mcp-oauth-parse-url redirect-param)
                                                   :pathname))))))
                     (when paste
                       (setf waiters
                             (append waiters
                                     (list (lambda ()
                                             (let ((input (funcall paste prompt-signal)))
                                               (unless (and (stringp input)
                                                            (plusp (length (string-trim
                                                                            '(#\Space #\Tab #\Newline #\Return)
                                                                            input))))
                                                 (error 'mcp-oauth-sign-in-cancelled))
                                               (mcp-oauth-response-from-redirect
                                                input state redirect-param)))))))
                     (when show-url
                       (funcall show-url authorization))
                     (let ((result (mcp-oauth-first-result waiters)))
                       (setf aborted t)
                       (mcp-oauth-authorize
                        provider
                        :server-url server-url
                        :fetch fetch
                        :signal signal
                        :resource-metadata-url
                        (and challenge (mcp-get challenge "resourceMetadataUrl"))
                        :authorization-server-metadata-url
                        (mcp-oauth-settings-auth-server-metadata-url settings)
                        :scope flow-scope
                        :authorization-code (getf result :code)
                        :iss (getf result :iss))
                       nil)))))
           (mcp-oauth-sign-in-cancelled (condition)
             (error condition))
           (error (condition)
             (if (mcp-oauth-aborted-p signal)
                 (error 'mcp-oauth-sign-in-cancelled)
                 (error condition))))
      (mcp-oauth-callback-close callback))))

(defun mcp-oauth-first-result (thunks)
  (let ((mutex (sb-thread:make-mutex :name "mcp oauth race"))
        (semaphore (sb-thread:make-semaphore :name "mcp oauth race"))
        (winner nil))
    (dolist (thunk thunks)
      (sb-thread:make-thread
       (lambda ()
         (handler-case
             (let ((value (funcall thunk)))
               (sb-thread:with-mutex (mutex)
                 (unless winner
                   (setf winner (list :ok value))
                   (sb-thread:signal-semaphore semaphore))))
           (error (condition)
             (sb-thread:with-mutex (mutex)
               (unless winner
                 (setf winner (list :error condition))
                 (sb-thread:signal-semaphore semaphore))))))
       :name "mcp oauth race"))
    (sb-thread:wait-on-semaphore semaphore)
    (if (eq (first winner) :ok)
        (second winner)
        (error (second winner)))))

(defun mcp-oauth-parse-states (text)
  (when (or (null text) (zerop (length (string-trim '(#\Space #\Tab #\Newline #\Return) text))))
    (return-from mcp-oauth-parse-states (mcp-obj)))
  (let ((parsed (ignore-errors (mcp-read-json text))))
    (if (mcp-object-p parsed) parsed (mcp-obj))))

(defun mcp-oauth-serialize-states (states)
  (concatenate 'string (mcp-json-pretty states) (string #\Newline)))

(defstruct mcp-oauth-file-backend
  path
  (text nil)
  (memory-p nil :type boolean)
  (lock (sb-thread:make-mutex :name "mcp oauth file")))

(defun make-mcp-oauth-memory-backend ()
  (make-mcp-oauth-file-backend :memory-p t))

(defun mcp-oauth-backend-call (backend updater)
  (sb-thread:with-mutex ((mcp-oauth-file-backend-lock backend))
    (let ((current
            (cond
              ((mcp-oauth-file-backend-memory-p backend)
               (mcp-oauth-file-backend-text backend))
              ((uiop:file-exists-p (mcp-oauth-file-backend-path backend))
               (uiop:read-file-string (mcp-oauth-file-backend-path backend)
                                      :external-format :utf-8))
              (t nil))))
      (multiple-value-bind (result next) (funcall updater current)
        (when next
          (if (mcp-oauth-file-backend-memory-p backend)
              (setf (mcp-oauth-file-backend-text backend) next)
              (cadr-core:call-with-atomic-output-file
               (mcp-oauth-file-backend-path backend)
               (lambda (stream) (write-string next stream))
               :mode #o600)))
        result))))

(defstruct (mcp-oauth-credential-store
            (:constructor %make-mcp-oauth-credential-store))
  backend
  lock-dir)

(defun mcp-oauth-store-keys (name server-url)
  (let ((href (mcp-oauth-href server-url)))
    (values (format nil "~A|~A" (mcp-namespace name) href) href)))

(defun mcp-oauth-with-refresh-lock (lock-dir key function)
  (unless lock-dir
    (return-from mcp-oauth-with-refresh-lock (funcall function)))
  (ensure-directories-exist (uiop:ensure-directory-pathname lock-dir))
  (ignore-errors
    (sb-posix:chmod (uiop:ensure-directory-pathname lock-dir) #o700))
  (let* ((digest (cadr-ai::sha256-bytes (cadr-ai::utf8-octets key)))
         (hash (subseq (mcp-oauth-hex digest) 0 16))
         (path (merge-pathnames (format nil "mcp-auth-refresh-~A" hash)
                                (uiop:ensure-directory-pathname lock-dir)))
         (deadline (+ (get-internal-real-time)
                      (* +mcp-oauth-refresh-lock-wait-seconds+
                         internal-time-units-per-second))))
    (loop for stream = (open path :direction :output
                             :if-exists nil
                             :if-does-not-exist :create
                             :element-type 'character)
          when stream
            do (unwind-protect (return (funcall function))
                 (close stream)
                 (ignore-errors (delete-file path)))
          when (> (get-internal-real-time) deadline)
            do (error "OAuth refresh lock timed out")
          do (let ((age (ignore-errors
                          (- (get-universal-time) (file-write-date path)))))
               (when (and age (>= age +mcp-oauth-refresh-lock-stale-seconds+))
                 (ignore-errors (delete-file path))))
             (sleep 0.1))))

(defun mcp-oauth-credential-server (credentials name server-url)
  (multiple-value-bind (key legacy) (mcp-oauth-store-keys name server-url)
    (list :load
          (lambda ()
            (mcp-oauth-backend-call
             (mcp-oauth-credential-store-backend credentials)
             (lambda (current)
               (let ((states (mcp-oauth-parse-states current)))
                 (cond
                   ((nth-value 1 (mcp-get states key))
                    (values (mcp-get states key) nil))
                   ((nth-value 1 (mcp-get states legacy))
                    (let ((taken (mcp-get states legacy)))
                      (setf states (mcp-put (mcp-delete states legacy) key taken))
                      (values taken (mcp-oauth-serialize-states states))))
                   (t (values nil nil)))))))
          :save
          (lambda (state)
            (mcp-oauth-backend-call
             (mcp-oauth-credential-store-backend credentials)
             (lambda (current)
               (let ((states (mcp-oauth-parse-states current)))
                 (values nil
                         (mcp-oauth-serialize-states (mcp-put states key state)))))))
          :refresh
          (lambda (function)
            (mcp-oauth-with-refresh-lock
             (mcp-oauth-credential-store-lock-dir credentials)
             key
             function))
          :tokens
          (lambda ()
            (mcp-oauth-backend-call
             (mcp-oauth-credential-store-backend credentials)
             (lambda (current)
               (let* ((states (mcp-oauth-parse-states current))
                      (state (if (nth-value 1 (mcp-get states key))
                                 (mcp-get states key)
                                 (mcp-get states legacy))))
                 (values (when state (mcp-get state "tokens")) nil)))))
          :remove
          (lambda ()
            (mcp-oauth-backend-call
             (mcp-oauth-credential-store-backend credentials)
             (lambda (current)
               (let* ((states (mcp-oauth-parse-states current))
                      (stored (cond
                                ((nth-value 1 (mcp-get states key)) key)
                                ((nth-value 1 (mcp-get states legacy)) legacy)
                                (t nil))))
                 (if stored
                     (values t (mcp-oauth-serialize-states (mcp-delete states stored)))
                     (values nil nil)))))))))

(defun mcp-oauth-server-tokens (view)
  (when (getf view :tokens)
    (funcall (getf view :tokens))))

(defun mcp-oauth-server-remove (view)
  (when (getf view :remove)
    (funcall (getf view :remove))))

(defun make-mcp-oauth-credential-store (path &optional lock-dir)
  (%make-mcp-oauth-credential-store
   :backend (if path
                (make-mcp-oauth-file-backend :path path)
                (make-mcp-oauth-memory-backend))
   :lock-dir lock-dir))

(defun mcp-oauth-create-auth (server-url store settings-fn on-challenge)
  (let ((box (vector (sb-thread:make-mutex :name "mcp oauth refresh")
                     (sb-thread:make-waitqueue :name "mcp oauth refresh")
                     nil
                     nil)))
    (labels ((refresh (stale fetch challenge)
               (mcp-oauth-share-flight
                box
                (lambda ()
                  (funcall
                   (or (getf store :refresh) (lambda (function) (funcall function)))
                   (lambda ()
                     (let ((state (mcp-oauth-store-load store)))
                       (let ((access (and state
                                          (mcp-get state "tokens")
                                          (mcp-get (mcp-get state "tokens") "access_token"))))
                         (unless (equal access stale)
                           (return-from refresh nil)))
                       (unless (and state
                                    (mcp-get state "tokens")
                                    (stringp (mcp-get (mcp-get state "tokens") "refresh_token")))
                         (error 'mcp-oauth-authorization-required-error))
                       (let* ((settings (funcall settings-fn))
                              (options (mcp-oauth-callback-settings settings))
                              (redirect
                                (or (getf options :fixed)
                                    (first (mcp-oauth-redirect-urls
                                            (mcp-get state "clientInformation")))
                                    +mcp-oauth-fallback-redirect+))
                              (provider
                                (make-mcp-oauth-provider
                                 :server-url server-url
                                 :redirect-url redirect
                                 :client-metadata
                                 (mcp-oauth-object
                                  "client_name"
                                  (or (mcp-oauth-settings-client-name settings)
                                      cadr-ai::+cadr-product-display-name+))
                                 :client-id (mcp-oauth-settings-client-id settings)
                                 :client-secret (mcp-oauth-settings-client-secret settings)
                                 :store store))
                              (result
                                (mcp-oauth-authorize
                                 provider
                                 :server-url server-url
                                 :resource-metadata-url
                                 (and challenge (mcp-get challenge "resourceMetadataUrl"))
                                 :authorization-server-metadata-url
                                 (mcp-oauth-settings-auth-server-metadata-url settings)
                                 :scope (and challenge (mcp-get challenge "scope"))
                                 :fetch fetch)))
                         (when (string= result "REDIRECT")
                           (error 'mcp-oauth-authorization-required-error))))))))))
      (make-mcp-oauth-auth
       :token
       (lambda ()
         (sb-thread:with-mutex ((svref box 0))
           (loop while (svref box 2)
                 do (sb-thread:condition-wait (svref box 1) (svref box 0))))
         (let* ((state (mcp-oauth-store-load store))
                (tokens (and state (mcp-get state "tokens")))
                (token (and tokens (mcp-get tokens "access_token")))
                (expires (and state (mcp-get state "tokensExpireAt")))
                (expired (and (realp expires)
                              (<= (- expires +mcp-oauth-refresh-skew-ms+)
                                  (cadr-core:unix-milliseconds)))))
           (when (and expired tokens (stringp (mcp-get tokens "refresh_token")))
             (ignore-errors (refresh token nil nil)))
           (let ((latest (mcp-oauth-store-load store)))
             (when latest
               (let ((latest-tokens (mcp-get latest "tokens")))
                 (when latest-tokens (mcp-get latest-tokens "access_token")))))))
       :unauthorized
       (lambda (context)
         (let ((challenge (mcp-oauth-parse-www-authenticate
                           (cadr-ai::header-value (getf context :headers)
                                                  "www-authenticate"))))
           (when on-challenge
             (funcall on-challenge challenge))
           (when (equal (mcp-get challenge "error") "insufficient_scope")
             (error 'mcp-oauth-authorization-required-error))
           (refresh (getf context :token)
                    (getf context :fetch)
                    challenge)))
       :settled
       (lambda ()
         (sb-thread:with-mutex ((svref box 0))
           (loop while (svref box 2)
                 do (sb-thread:condition-wait (svref box 1) (svref box 0))))
         (when (svref box 3)
           (error (svref box 3))))))))
