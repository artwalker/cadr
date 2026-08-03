(in-package #:cadr-ai)

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
             'authentication-cancelled
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
             (authentication-cancelled (cause)
               (complete nil cause))
             (authentication-error (cause)
               (complete nil cause))
             (error (cause)
               (complete
                nil
                (make-condition
                 'authentication-error
                 :message "OAuth authorization prompt failed"
                 :cause cause))))))
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
