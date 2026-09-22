(in-package #:cadr-ai)

(defstruct oauth-provider-metadata
  (provider-name "" :type string)
  (method-name "" :type string)
  login-label
  auth-url-instructions
  manual-input-message
  ;; pi@16787ad5b packages/ai/src/auth/oauth/*.ts — subscription-backed
  ;; OAuth access (footer "(sub)" marker via isUsingSubscription).
  (is-subscription-p nil :type boolean))

(defparameter +openai-codex-oauth-metadata+
  (make-oauth-provider-metadata
   :is-subscription-p t
   :provider-name "OpenAI Codex"
   :method-name "OpenAI (ChatGPT Plus/Pro)"
   :auth-url-instructions
   "A browser window should open. Complete login to finish."
   :manual-input-message
   "Complete login in your browser, or paste the authorization code / redirect URL here:"))

(defparameter +anthropic-oauth-metadata+
  (make-oauth-provider-metadata
   :is-subscription-p t
   :provider-name "Anthropic"
   :method-name "Anthropic (Claude Pro/Max)"
   :auth-url-instructions
   "Complete login in your browser. If the browser is on another machine, paste the final redirect URL here."
   :manual-input-message
   "Complete login in your browser, or paste the authorization code / redirect URL here:"))

(defun oauth-login-title (metadata)
  (format nil "Login to ~A"
          (oauth-provider-metadata-provider-name metadata)))

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
(defparameter +openai-device-user-code-url+
  "https://auth.openai.com/api/accounts/deviceauth/usercode")
(defparameter +openai-device-token-url+
  "https://auth.openai.com/api/accounts/deviceauth/token")
(defparameter +openai-device-verification-uri+
  "https://auth.openai.com/codex/device")
(defparameter +openai-device-redirect-uri+
  "https://auth.openai.com/deviceauth/callback")
(defparameter +openai-device-code-timeout-seconds+ 900)
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
