(in-package #:cadr-ai)

(defun octets-hex (octets)
  (let ((digits "0123456789abcdef"))
    (with-output-to-string (output)
      (loop for octet across octets
            do
            (write-char (char digits (ldb (byte 4 4) octet))
                        output)
            (write-char (char digits (ldb (byte 4 0) octet))
                        output)))))

(defun ensure-octets (value)
  (etypecase value
    (string (utf8-octets value))
    ((vector (unsigned-byte 8)) value)))

(defun hmac-sha256 (key message)
  "RFC 2104 HMAC using cadr's existing pure-Lisp SHA-256 implementation."
  (let* ((block-size 64)
         (source-key (ensure-octets key))
         (normalized
           (if (> (length source-key) block-size)
               (sha256-bytes source-key)
               source-key))
         (padded
           (make-array block-size
                       :element-type '(unsigned-byte 8)
                       :initial-element 0))
         (inner-pad
           (make-array block-size
                       :element-type '(unsigned-byte 8)))
         (outer-pad
           (make-array block-size
                       :element-type '(unsigned-byte 8))))
    (replace padded normalized)
    (loop for index below block-size
          for byte = (aref padded index)
          do (setf (aref inner-pad index) (logxor byte #x36)
                   (aref outer-pad index) (logxor byte #x5c)))
    (sha256-bytes
     (concatenate
      '(vector (unsigned-byte 8))
      outer-pad
      (sha256-bytes
       (concatenate
        '(vector (unsigned-byte 8))
        inner-pad
        (ensure-octets message)))))))

(defun sigv4-unreserved-p (character)
  (or (alphanumericp character)
      (find character "-_.~" :test #'char=)))

(defun sigv4-percent-encode (text &key preserve-slash-p)
  (with-output-to-string (output)
    (loop for byte across (utf8-octets text)
          for character = (code-char byte)
          do
          (cond
            ((sigv4-unreserved-p character)
             (write-char character output))
            ((and preserve-slash-p (= byte (char-code #\/)))
             (write-char #\/ output))
            (t
             (format output "%~2,'0X" byte))))))

(defun split-on-character (text character)
  (loop with start = 0
        for end = (position character text :start start)
        collect (subseq text start end)
        while end
        do (setf start (1+ end))))

(defun collapse-http-whitespace (value)
  (with-output-to-string (output)
    (loop with pending-space-p = nil
          for character across
          (string-trim '(#\Space #\Tab #\Return #\Linefeed) value)
          do
          (if (find character '(#\Space #\Tab #\Return #\Linefeed))
              (setf pending-space-p t)
              (progn
                (when (and pending-space-p
                           (plusp
                            (file-position output)))
                  (write-char #\Space output))
                (setf pending-space-p nil)
                (write-char character output))))))

(defun canonical-query-string (query)
  (let ((entries
          (loop for part in
                (if (zerop (length query))
                    nil
                    (split-on-character query #\&))
                for equals = (position #\= part)
                collect
                (cons
                 (sigv4-percent-encode
                  (subseq part 0 equals))
                 (sigv4-percent-encode
                  (if equals
                      (subseq part (1+ equals))
                      ""))))))
    (format nil "~{~A~^&~}"
            (mapcar
             (lambda (entry)
               (format nil "~A=~A" (car entry) (cdr entry)))
             (sort entries
                   (lambda (left right)
                     (or (string< (car left) (car right))
                         (and (string= (car left) (car right))
                              (string< (cdr left) (cdr right))))))))))

(defun sigv4-url-components (url)
  (let* ((parsed (parse-http-url url))
         (path-and-query (parsed-url-path parsed))
         (question (position #\? path-and-query))
         (path (subseq path-and-query 0 question))
         (query (if question
                    (subseq path-and-query (1+ question))
                    ""))
         (host
           (if (or (= (parsed-url-port parsed) 80)
                   (= (parsed-url-port parsed) 443))
               (parsed-url-host parsed)
               (format nil "~A:~D"
                       (parsed-url-host parsed)
                       (parsed-url-port parsed)))))
    (values
     (if (zerop (length path)) "/" path)
     query host)))

(defun canonical-sigv4-headers (headers)
  (let ((merged (make-hash-table :test #'equal)))
    (dolist (header headers)
      (let* ((name (string-downcase (car header)))
             (value (collapse-http-whitespace (princ-to-string (cdr header))))
             (old (gethash name merged)))
        (unless (string= name "authorization")
          (setf (gethash name merged)
                (if old
                    (format nil "~A,~A" old value)
                    value)))))
    (let ((names
            (sort
             (loop for name being the hash-keys of merged collect name)
             #'string<)))
      (values
       (with-output-to-string (output)
         (dolist (name names)
           (format output "~A:~A~%" name (gethash name merged))))
       (format nil "~{~A~^;~}" names)))))

(defun aws-sigv4-authorization
    (&key method url headers payload access-key-id secret-access-key
            session-token region service timestamp)
  (unless (and (non-empty-string-p access-key-id)
               (non-empty-string-p secret-access-key)
               (non-empty-string-p region)
               (non-empty-string-p service)
               (= 16 (length timestamp)))
    (error 'configuration-error
           :message "Incomplete AWS SigV4 configuration"))
  (multiple-value-bind (path query host)
      (sigv4-url-components url)
    (let* ((date (subseq timestamp 0 8))
           (request-headers
             (append
              headers
              `(("host" . ,host)
                ("x-amz-date" . ,timestamp))
              (when (non-empty-string-p session-token)
                `(("x-amz-security-token" . ,session-token)))))
           (payload-hash
             (octets-hex
              (sha256-bytes (ensure-octets (or payload ""))))))
      (multiple-value-bind (canonical-headers signed-headers)
          (canonical-sigv4-headers request-headers)
        (let* ((canonical-request
                 (format nil "~A~%~A~%~A~%~A~%~A~%~A"
                         (string-upcase method)
                         (sigv4-percent-encode path :preserve-slash-p t)
                         (canonical-query-string query)
                         canonical-headers
                         signed-headers
                         payload-hash))
               (scope
                 (format nil "~A/~A/~A/aws4_request"
                         date region service))
               (string-to-sign
                 (format nil "AWS4-HMAC-SHA256~%~A~%~A~%~A"
                         timestamp scope
                         (octets-hex
                          (sha256-bytes
                           (utf8-octets canonical-request)))))
               (date-key
                 (hmac-sha256
                  (concatenate 'string "AWS4" secret-access-key)
                  date))
               (region-key (hmac-sha256 date-key region))
               (service-key (hmac-sha256 region-key service))
               (signing-key
                 (hmac-sha256 service-key "aws4_request"))
               (signature
                 (octets-hex
                  (hmac-sha256 signing-key string-to-sign))))
          (values
           (format nil
                   "AWS4-HMAC-SHA256 Credential=~A/~A, SignedHeaders=~A, Signature=~A"
                   access-key-id scope signed-headers signature)
           request-headers))))))

(cffi:defcfun ("BIO_new_mem_buf" %bio-new-mem-buf)
    :pointer
  (buffer :pointer)
  (length :int))

(cffi:defcfun ("BIO_free" %bio-free) :int
  (bio :pointer))

(cffi:defcfun ("PEM_read_bio_PrivateKey" %pem-read-private-key)
    :pointer
  (bio :pointer)
  (key :pointer)
  (callback :pointer)
  (user-data :pointer))

(cffi:defcfun ("EVP_PKEY_free" %evp-pkey-free) :void
  (key :pointer))

(cffi:defcfun ("EVP_MD_CTX_new" %evp-md-context-new)
    :pointer)

(cffi:defcfun ("EVP_MD_CTX_free" %evp-md-context-free) :void
  (context :pointer))

(cffi:defcfun ("EVP_sha256" %evp-sha256) :pointer)

(cffi:defcfun ("EVP_DigestSignInit" %evp-digest-sign-init)
    :int
  (context :pointer)
  (key-context :pointer)
  (digest :pointer)
  (engine :pointer)
  (key :pointer))

(cffi:defcfun ("EVP_DigestSignUpdate" %evp-digest-sign-update)
    :int
  (context :pointer)
  (data :pointer)
  (length :size))

(cffi:defcfun ("EVP_DigestSignFinal" %evp-digest-sign-final)
    :int
  (context :pointer)
  (signature :pointer)
  (signature-length :pointer))

(defun openssl-check (result operation)
  (unless (= 1 result)
    (error 'configuration-error
           :message
           (format nil "OpenSSL ~A failed" operation))))

(defun openssl-rs256-sign (private-key-pem message)
  "Sign MESSAGE with RSA PKCS#1 v1.5/SHA-256 through libcrypto EVP."
  (cl+ssl:ensure-initialized)
  (let* ((pem (utf8-octets private-key-pem))
         (data (ensure-octets message)))
    (cffi:with-pointer-to-vector-data (pem-pointer pem)
      (let ((bio (%bio-new-mem-buf pem-pointer (length pem))))
        (when (cffi:null-pointer-p bio)
          (error 'configuration-error
                 :message "OpenSSL could not allocate a PEM BIO"))
        (unwind-protect
             (let ((key
                     (%pem-read-private-key
                      bio (cffi:null-pointer)
                      (cffi:null-pointer) (cffi:null-pointer))))
               (when (cffi:null-pointer-p key)
                 (error 'configuration-error
                        :message
                        "Invalid or encrypted service-account private key"))
               (unwind-protect
                    (let ((context (%evp-md-context-new)))
                      (when (cffi:null-pointer-p context)
                        (error 'configuration-error
                               :message
                               "OpenSSL could not allocate a signing context"))
                      (unwind-protect
                           (progn
                             (openssl-check
                              (%evp-digest-sign-init
                               context (cffi:null-pointer)
                               (%evp-sha256)
                               (cffi:null-pointer) key)
                              "EVP_DigestSignInit")
                             (cffi:with-pointer-to-vector-data
                                 (data-pointer data)
                               (openssl-check
                                (%evp-digest-sign-update
                                 context data-pointer (length data))
                                "EVP_DigestSignUpdate"))
                             (cffi:with-foreign-object
                                 (length-pointer :size)
                               (setf
                                (cffi:mem-ref length-pointer :size)
                                0)
                               (openssl-check
                                (%evp-digest-sign-final
                                 context (cffi:null-pointer)
                                 length-pointer)
                                "EVP_DigestSignFinal(size)")
                               (let* ((length
                                       (cffi:mem-ref length-pointer :size))
                                      (signature
                                        (make-array
                                         length
                                         :element-type '(unsigned-byte 8))))
                                 (cffi:with-pointer-to-vector-data
                                     (signature-pointer signature)
                                   (openssl-check
                                    (%evp-digest-sign-final
                                     context signature-pointer
                                     length-pointer)
                                    "EVP_DigestSignFinal"))
                                 (subseq
                                  signature 0
                                  (cffi:mem-ref
                                   length-pointer :size)))))
                        (%evp-md-context-free context)))
                 (%evp-pkey-free key)))
          (%bio-free bio))))))

(defun make-service-account-jwt
    (client-email private-key scope audience issued-at
     &key (lifetime 3600))
  (unless (and (non-empty-string-p client-email)
               (non-empty-string-p private-key)
               (non-empty-string-p scope)
               (non-empty-string-p audience)
               (integerp issued-at)
               (plusp lifetime))
    (error 'configuration-error
           :message "Incomplete service-account JWT configuration"))
  (let* ((header
           (base64url-encode
            (utf8-octets
             (stringify-json
              (json-object "alg" "RS256" "typ" "JWT")))))
         (claims
           (base64url-encode
            (utf8-octets
             (stringify-json
              (json-object
               "iss" client-email
               "scope" scope
               "aud" audience
               "iat" issued-at
               "exp" (+ issued-at lifetime))))))
         (input (format nil "~A.~A" header claims))
         (signature
           (base64url-encode
            (openssl-rs256-sign private-key input))))
    (format nil "~A.~A" input signature)))
