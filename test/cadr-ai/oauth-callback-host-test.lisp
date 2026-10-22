(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

;;; pi@4a080252f packages/ai/src/auth/oauth/anthropic.ts CALLBACK_HOST
;;; packages/ai/src/auth/oauth/openai-chatgpt.ts CALLBACK_HOST
;;; packages/ai/src/auth/oauth/openai-codex.ts getCallbackHost
;;; packages/ai/src/auth/oauth/openrouter.ts getCallbackHost
;;; packages/ai/src/auth/oauth/callback-server.ts redirectHost
;;; packages/ai/src/auth/oauth/radius.ts hardcodes 127.0.0.1
;;; packages/ai/test/openrouter-oauth.test.ts
;;; "uses the configured OAuth callback host"
;;; Product identity reads CADR_OAUTH_CALLBACK_HOST and not PI_*.

(defun call-with-oauth-callback-host (cadr upstream function)
  (let ((saved-cadr (uiop:getenv "CADR_OAUTH_CALLBACK_HOST"))
        (saved-upstream (uiop:getenv "PI_OAUTH_CALLBACK_HOST")))
    (unwind-protect
         (progn
           (if (eq cadr :unset)
               (sb-posix:unsetenv "CADR_OAUTH_CALLBACK_HOST")
               (setf (uiop:getenv "CADR_OAUTH_CALLBACK_HOST") cadr))
           (if (eq upstream :unset)
               (sb-posix:unsetenv "PI_OAUTH_CALLBACK_HOST")
               (setf (uiop:getenv "PI_OAUTH_CALLBACK_HOST") upstream))
           (funcall function))
      (if saved-cadr
          (setf (uiop:getenv "CADR_OAUTH_CALLBACK_HOST") saved-cadr)
          (sb-posix:unsetenv "CADR_OAUTH_CALLBACK_HOST"))
      (if saved-upstream
          (setf (uiop:getenv "PI_OAUTH_CALLBACK_HOST") saved-upstream)
          (sb-posix:unsetenv "PI_OAUTH_CALLBACK_HOST")))))

(defun oauth-callback-socket-address (socket)
  (nth-value 0 (sb-bsd-sockets:socket-name socket)))

(defun oauth-callback-tcp-open-p (host port)
  (let ((socket
          (make-instance 'sb-bsd-sockets:inet-socket
                         :type :stream
                         :protocol :tcp)))
    (handler-case
        (progn
          (sb-bsd-sockets:socket-connect
           socket (sb-bsd-sockets:make-inet-address host) port)
          (sb-bsd-sockets:socket-close socket)
          t)
      (error ()
        (ignore-errors (sb-bsd-sockets:socket-close socket))
        nil))))

(defun oauth-callback-url-port (url)
  (let* ((start (+ (search "://" url) 3))
         (path (position #\/ url :start start))
         (colon (position #\: url :start start :end path)))
    (parse-integer url :start (1+ colon) :end path)))

(test oauth-callback-host-defaults-to-loopback-and-ignores-pi
  ;; Empty and unset are falsy in `value || "127.0.0.1"`. A space is kept.
  (call-with-oauth-callback-host
   :unset :unset
   (lambda ()
     (is (string= "127.0.0.1" (cadr-ai::oauth-callback-host)))
     (let ((socket (cadr-ai::open-oauth-callback-socket 0)))
       (unwind-protect
            (is (equalp #(127 0 0 1)
                        (oauth-callback-socket-address socket)))
         (ignore-errors (sb-bsd-sockets:socket-close socket))))))
  (call-with-oauth-callback-host
   "" "127.0.0.2"
   (lambda ()
     (is (string= "127.0.0.1" (cadr-ai::oauth-callback-host)))))
  (call-with-oauth-callback-host
   :unset "127.0.0.2"
   (lambda ()
     (is (string= "127.0.0.1" (cadr-ai::oauth-callback-host)))))
  (call-with-oauth-callback-host
   " " :unset
   (lambda ()
     (is (string= " " (cadr-ai::oauth-callback-host)))))
  (is (string= "[::1]" (cadr-ai::oauth-callback-url-host "::1")))
  (is (string= "localhost" (cadr-ai::oauth-callback-url-host "localhost")))
  (is (string= "127.0.0.1" (cadr-ai::oauth-callback-url-host "127.0.0.1"))))

(test oauth-callback-host-binds-the-configured-ipv4-address
  (call-with-oauth-callback-host
   "127.0.0.2" "10.1.2.3"
   (lambda ()
     (let ((socket
             (cadr-ai::open-oauth-callback-socket
              0 (cadr-ai::oauth-callback-host))))
       (unwind-protect
            (is (equalp #(127 0 0 2)
                        (oauth-callback-socket-address socket)))
         (ignore-errors (sb-bsd-sockets:socket-close socket))))))
  (call-with-oauth-callback-host
   "127.0.0.2" :unset
   (lambda ()
     (let ((socket (cadr-ai::open-oauth-callback-socket 0)))
       (unwind-protect
            (is (equalp #(127 0 0 1)
                        (oauth-callback-socket-address socket)))
         (ignore-errors (sb-bsd-sockets:socket-close socket)))))))

(test anthropic-oauth-binds-the-callback-host-and-redirects-localhost
  (call-with-oauth-callback-host
   "127.0.0.2" :unset
   (lambda ()
     (let ((placeholder nil)
           (url nil)
           (bound nil)
           (other nil))
       (signals cadr-ai:authentication-cancelled
         (cadr-ai:login-anthropic-oauth
          nil
          :output (make-string-output-stream)
          :open-browser (constantly nil)
          :auth-prompt-function
          (lambda (prompt)
            (setf placeholder (getf prompt :placeholder)
                  url (getf prompt :url))
            (let ((port (oauth-callback-url-port placeholder)))
              (setf bound (oauth-callback-tcp-open-p "127.0.0.2" port)
                    other (oauth-callback-tcp-open-p "127.0.0.1" port)))
            (funcall (getf prompt :cancel-function))
            nil)))
       (is (uiop:string-prefix-p "http://localhost:" placeholder))
       (is (uiop:string-suffix-p placeholder "/callback"))
       (is (search "redirect_uri=http%3A%2F%2Flocalhost%3A" url))
       (is (not (search "127.0.0.2" url)))
       (is (eq t bound))
       (is (eq nil other))))))

(test chatgpt-oauth-binds-the-callback-host-and-keeps-the-paste-origin
  (call-with-oauth-callback-host
   "127.0.0.2" :unset
   (lambda ()
     (let ((cadr-ai::*oauth-login-device-id*
             "e61bbe28-07ef-466d-8e5d-a344f94ab305")
           (cadr-ai::*oauth-browser-open-function* (constantly nil))
           (placeholder nil)
           (bound nil)
           (other nil))
       (signals cadr-ai:authentication-cancelled
         (cadr-ai::login-openai-chatgpt-oauth
          (cadr-ai:make-runtime-auth-interaction
           :prompt-function
           (lambda (prompt)
             (setf placeholder (getf prompt :placeholder)
                   bound (oauth-callback-tcp-open-p "127.0.0.2" 1455)
                   other (oauth-callback-tcp-open-p "127.0.0.1" 1455))
             nil))))
       (is (string= "http://127.0.0.1:1455/auth/callback" placeholder))
       (is (eq t bound))
       (is (eq nil other))))))

(test codex-oauth-binds-the-callback-host-and-keeps-localhost-redirect
  (call-with-oauth-callback-host
   "127.0.0.2" :unset
   (lambda ()
     (let ((cadr-ai::*oauth-browser-open-function* (constantly nil))
           (url nil)
           (bound nil)
           (other nil))
       (signals cadr-ai:authentication-cancelled
         (cadr-ai:login-openai-oauth
          nil
          :output (make-string-output-stream)
          :open-browser (constantly nil)
          :auth-prompt-function
          (lambda (prompt)
            (setf url (getf prompt :url)
                  bound
                  (loop repeat 50
                        for open = (oauth-callback-tcp-open-p "127.0.0.2" 1455)
                        when open
                          return t
                        do (sleep 0.02))
                  other (oauth-callback-tcp-open-p "127.0.0.1" 1455))
            (funcall (getf prompt :cancel-function))
            nil)))
       (is (search
            "redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback"
            url))
       (is (not (search "127.0.0.2" url)))
       (is (eq t bound))
       (is (eq nil other))))))

(test openrouter-oauth-callback-url-uses-the-configured-host
  ;; packages/ai/test/openrouter-oauth.test.ts hostname is the env value.
  ;; The listener resolves localhost to 127.0.0.1 and the URL keeps the name.
  (call-with-oauth-callback-host
   "localhost" :unset
   (lambda ()
     (let ((placeholder nil)
           (progress nil)
           (url nil)
           (bound nil))
       (signals cadr-ai:authentication-cancelled
         (cadr-ai::login-openrouter-oauth
          (cadr-ai:make-runtime-auth-interaction
           :notify-function
           (lambda (event)
             (case (getf event :type)
               (:progress
                (unless progress
                  (setf progress (getf event :message))))
               (:auth-url
                (setf url (getf event :url)))))
           :prompt-function
           (lambda (prompt)
             (setf placeholder (getf prompt :placeholder))
             (setf bound
                   (oauth-callback-tcp-open-p
                    "127.0.0.1"
                    (oauth-callback-url-port placeholder)))
             nil))))
       (is (uiop:string-prefix-p "http://localhost:" placeholder))
       (is (search "/oauth/callback/" placeholder))
       (is (string=
            (format nil
                    "Listening for OpenRouter OAuth callback on ~A"
                    placeholder)
            progress))
       (is (search "localhost" url))
       (is (not (search "127.0.0.1" placeholder)))
       (is (eq t bound)))))
  (call-with-oauth-callback-host
   "127.0.0.2" :unset
   (lambda ()
     (let ((placeholder nil)
           (bound nil)
           (other nil))
       (signals cadr-ai:authentication-cancelled
         (cadr-ai::login-openrouter-oauth
          (cadr-ai:make-runtime-auth-interaction
           :notify-function (constantly nil)
           :prompt-function
           (lambda (prompt)
             (setf placeholder (getf prompt :placeholder))
             (let ((port (oauth-callback-url-port placeholder)))
               (setf bound (oauth-callback-tcp-open-p "127.0.0.2" port)
                     other (oauth-callback-tcp-open-p "127.0.0.1" port)))
             nil))))
       (is (uiop:string-prefix-p "http://127.0.0.2:" placeholder))
       (is (eq t bound))
       (is (eq nil other)))))
  (call-with-oauth-callback-host
   :unset :unset
   (lambda ()
     (let ((placeholder nil))
       (signals cadr-ai:authentication-cancelled
         (cadr-ai::login-openrouter-oauth
          (cadr-ai:make-runtime-auth-interaction
           :notify-function (constantly nil)
           :prompt-function
           (lambda (prompt)
             (setf placeholder (getf prompt :placeholder))
             nil))))
       (is (uiop:string-prefix-p "http://127.0.0.1:" placeholder))))))

(defun oauth-callback-listen-entry-p (address port)
  (let* ((ip (format nil "~2,'0X~2,'0X~2,'0X~2,'0X"
                     (aref address 3) (aref address 2)
                     (aref address 1) (aref address 0)))
         (needle (format nil "~A:~4,'0X" ip port)))
    (and (search needle (uiop:read-file-string "/proc/net/tcp")) t)))

(test radius-oauth-callback-stays-on-127-0-0-1
  ;; radius.ts CALLBACK_HOST is the literal "127.0.0.1".
  ;; /proc/net/tcp avoids accepting the listener's one queued connection.
  (call-with-oauth-callback-host
   "127.0.0.2" :unset
   (lambda ()
     (let* ((ready nil)
            (thread
              (sb-thread:make-thread
               (lambda ()
                 (cadr-ai::wait-for-oauth-code
                  "state" 1456 "/oauth/callback" "Radius"
                  (lambda () ready))))))
       (unwind-protect
            (progn
              (loop repeat 50
                    until (oauth-callback-listen-entry-p #(127 0 0 1) 1456)
                    do (sleep 0.02))
              (is (eq t (oauth-callback-listen-entry-p #(127 0 0 1) 1456)))
              (is (eq nil (oauth-callback-listen-entry-p #(127 0 0 2) 1456))))
         (setf ready t)
         (handler-case
             (sb-thread:join-thread thread :timeout 2)
           (error () nil)))))))
