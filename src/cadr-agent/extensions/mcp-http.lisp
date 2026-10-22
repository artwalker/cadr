(in-package #:cadr-agent)

;;; pi@4a080252f StreamableHttpTransport. POST JSON-RPC, read JSON or
;;; SSE, keep a GET stream after initialize, DELETE the session on close.
;;; OAuth token refresh stays out; a 401 is McpAuthRequiredError.

(defparameter +mcp-error-body-bytes+ (* 8 1024))
(defparameter +mcp-error-message-body-chars+ 500)

(defun consume-mcp-sse (next-chunk &key on-event on-id on-retry
                                    (max-event-bytes +mcp-max-message-bytes+))
  (let ((buffered "")
        (event-name nil)
        (event-id nil)
        (data-lines nil)
        (data-bytes 0))
    (labels ((dispatch ()
               (when data-lines
                 (let ((data (format nil "~{~A~^~%~}" (nreverse data-lines))))
                   (when on-event
                     (funcall on-event
                              (append (when event-name (list :event event-name))
                                      (list :data data)
                                      (when event-id (list :id event-id))))))
                 (setf event-name nil
                       event-id nil
                       data-lines nil
                       data-bytes 0)))
             (process-line (raw)
               (let ((line (if (and (plusp (length raw))
                                    (char= (char raw (1- (length raw))) #\Return))
                               (subseq raw 0 (1- (length raw)))
                               raw)))
                 (cond
                   ((zerop (length line))
                    (dispatch))
                   ((char= (char line 0) #\:)
                    nil)
                   (t
                    (let* ((colon (position #\: line))
                           (field (if colon (subseq line 0 colon) line))
                           (value (if colon (subseq line (1+ colon)) "")))
                      (when (and (plusp (length value)) (char= (char value 0) #\Space))
                        (setf value (subseq value 1)))
                      (cond
                        ((string= field "data")
                         (setf data-bytes
                               (+ data-bytes
                                  (mcp-utf8-length value)
                                  (if data-lines 1 0)))
                         (when (> data-bytes max-event-bytes)
                           (error "MCP SSE event exceeds ~A bytes" max-event-bytes))
                         (push value data-lines))
                        ((string= field "event")
                         (setf event-name value))
                        ((and (string= field "id")
                              (not (find #\Nul value)))
                         (setf event-id value)
                         (when on-id (funcall on-id value)))
                        ((and (string= field "retry")
                              (plusp (length value))
                              (every #'digit-char-p value))
                         (when on-retry
                           (funcall on-retry (parse-integer value))))))))))
             (drain (text)
               (setf buffered (concatenate 'string buffered text))
               (loop for newline = (position #\Newline buffered)
                     while newline
                     do (process-line (subseq buffered 0 newline))
                        (setf buffered (subseq buffered (1+ newline))))
               (when (> (mcp-utf8-length buffered) max-event-bytes)
                 (error "MCP SSE event exceeds ~A bytes" max-event-bytes))))
      (loop for chunk = (funcall next-chunk)
            while chunk
            do (drain chunk))
      (when (plusp (length buffered))
        (process-line buffered)
        (setf buffered ""))
      (dispatch)))
  nil)

(defun mcp-http-content-type (headers)
  (let ((value (cadr-ai::header-value headers "content-type")))
    (when (stringp value)
      (let ((semi (position #\; value)))
        (string-downcase
         (string-trim '(#\Space #\Tab)
                      (if semi (subseq value 0 semi) value)))))))

(defun mcp-describe-http-failure (status body)
  (let* ((text (string-trim '(#\Space #\Tab #\Newline #\Return) (or body "")))
         (snippet (if (> (length text) +mcp-error-message-body-chars+)
                      (concatenate 'string
                                   (subseq text 0 (- +mcp-error-message-body-chars+ 3))
                                   "...")
                      text)))
    (if (plusp (length snippet))
        (format nil "MCP HTTP request failed with status ~A: ~A" status snippet)
        (format nil "MCP HTTP request failed with status ~A" status))))

(defun mcp-read-bounded-text (stream max-bytes)
  (let ((octets (make-array 256
                            :element-type '(unsigned-byte 8)
                            :adjustable t
                            :fill-pointer 0)))
    (loop for byte = (read-byte stream nil :eof)
          until (or (eq byte :eof)
                    (and max-bytes (>= (length octets) max-bytes)))
          do (vector-push-extend byte octets))
    (cadr-ai::utf8-string octets)))

(defun mcp-stream-chunk-reader (stream)
  ;; http-body-stream implements stream-read-byte only. read-sequence
  ;; on that gray stream returns immediately and drops the body.
  (lambda ()
    (let ((octets (make-array 256
                              :element-type '(unsigned-byte 8)
                              :adjustable t
                              :fill-pointer 0)))
      (loop for byte = (read-byte stream nil :eof)
            until (or (eq byte :eof) (>= (length octets) 4096))
            do (vector-push-extend byte octets))
      (when (plusp (length octets))
        (cadr-ai::utf8-string octets)))))

(defstruct (mcp-http-transport (:constructor %make-mcp-http-transport))
  (url "" :type string)
  headers
  (open-get-stream-p t :type boolean)
  (max-message-bytes +mcp-max-message-bytes+ :type integer)
  (initial-delay-ms 1000 :type integer)
  (max-delay-ms 30000 :type integer)
  (max-retries 5 :type integer)
  session-id
  protocol-version
  (started-p nil :type boolean)
  (closed-p nil :type boolean)
  (get-started-p nil :type boolean)
  (close-emitted-p nil :type boolean)
  (message-listeners nil :type list)
  (error-listeners nil :type list)
  (close-listeners nil :type list)
  (streams nil :type list)
  (lock (sb-thread:make-mutex :name "mcp http"))
  (abort (make-mcp-abort))
  auth-token
  auth-unauthorized)

(defun make-mcp-http-transport (url &key headers
                                    (open-get-stream t)
                                    (max-message-bytes +mcp-max-message-bytes+)
                                    (initial-delay-ms 1000)
                                    (max-delay-ms 30000)
                                    (max-retries 5)
                                    auth-token auth-unauthorized)
  (%make-mcp-http-transport
   :url url
   :headers headers
   :open-get-stream-p open-get-stream
   :max-message-bytes max-message-bytes
   :initial-delay-ms initial-delay-ms
   :max-delay-ms max-delay-ms
   :max-retries max-retries
   :auth-token auth-token
   :auth-unauthorized auth-unauthorized))

(defun mcp-http-session-id (transport)
  (mcp-http-transport-session-id transport))

(defun mcp-http-listeners (transport slot)
  (sb-thread:with-mutex ((mcp-http-transport-lock transport))
    (copy-list (slot-value transport slot))))

(defun mcp-http-emit-message (transport message)
  (dolist (listener (mcp-http-listeners transport 'message-listeners))
    (funcall listener message)))

(defun mcp-http-emit-error (transport error)
  (let ((normalized
          (if (typep error 'error)
              error
              (make-condition 'simple-error
                              :format-control "~A"
                              :format-arguments (list error)))))
    (dolist (listener (mcp-http-listeners transport 'error-listeners))
      (funcall listener normalized))))

(defun mcp-http-emit-close (transport)
  (let ((emit nil))
    (sb-thread:with-mutex ((mcp-http-transport-lock transport))
      (unless (mcp-http-transport-close-emitted-p transport)
        (setf (mcp-http-transport-close-emitted-p transport) t
              emit t)))
    (when emit
      (dolist (listener (mcp-http-listeners transport 'close-listeners))
        (funcall listener)))))

(defmethod mcp-transport-on-message ((transport mcp-http-transport) listener)
  (sb-thread:with-mutex ((mcp-http-transport-lock transport))
    (push listener (mcp-http-transport-message-listeners transport)))
  (lambda ()
    (sb-thread:with-mutex ((mcp-http-transport-lock transport))
      (setf (mcp-http-transport-message-listeners transport)
            (remove listener
                    (mcp-http-transport-message-listeners transport))))))

(defmethod mcp-transport-on-error ((transport mcp-http-transport) listener)
  (sb-thread:with-mutex ((mcp-http-transport-lock transport))
    (push listener (mcp-http-transport-error-listeners transport)))
  (lambda ()
    (sb-thread:with-mutex ((mcp-http-transport-lock transport))
      (setf (mcp-http-transport-error-listeners transport)
            (remove listener
                    (mcp-http-transport-error-listeners transport))))))

(defmethod mcp-transport-on-close ((transport mcp-http-transport) listener)
  (sb-thread:with-mutex ((mcp-http-transport-lock transport))
    (push listener (mcp-http-transport-close-listeners transport)))
  (lambda ()
    (sb-thread:with-mutex ((mcp-http-transport-lock transport))
      (setf (mcp-http-transport-close-listeners transport)
            (remove listener
                    (mcp-http-transport-close-listeners transport))))))

(defmethod mcp-transport-set-protocol-version ((transport mcp-http-transport) version)
  (setf (mcp-http-transport-protocol-version transport) version)
  nil)

(defmethod mcp-transport-start ((transport mcp-http-transport))
  (when (mcp-http-transport-started-p transport)
    (error "MCP Streamable HTTP transport already started"))
  (when (mcp-http-transport-closed-p transport)
    (error 'mcp-connection-closed-error))
  (setf (mcp-http-transport-started-p transport) t)
  nil)

(defun mcp-http-header-alist (transport extra)
  (let ((headers nil))
    (when (mcp-object-p (mcp-http-transport-headers transport))
      (loop for (key value) on (cdr (mcp-http-transport-headers transport)) by #'cddr
            do (push (cons key value) headers)))
    (loop for (key . value) in extra
          do (setf headers
                   (cons (cons key value)
                         (remove key headers :key #'car :test #'string-equal))))
    (when (mcp-http-transport-session-id transport)
      (push (cons "Mcp-Session-Id" (mcp-http-transport-session-id transport))
            headers))
    (when (mcp-http-transport-protocol-version transport)
      (push (cons "MCP-Protocol-Version"
                  (mcp-http-transport-protocol-version transport))
            headers))
    headers))

(defun mcp-http-capture-session (transport headers)
  (let ((session (cadr-ai::header-value headers "mcp-session-id")))
    (when (and (stringp session) (plusp (length session)))
      (setf (mcp-http-transport-session-id transport) session))))

(defun mcp-http-remember-stream (transport stream)
  (sb-thread:with-mutex ((mcp-http-transport-lock transport))
    (push stream (mcp-http-transport-streams transport))))

(defun mcp-http-with-bearer (headers token)
  (let ((rest (remove "authorization" headers :key #'car :test #'string-equal)))
    (if (and (stringp token) (plusp (length token)))
        (acons "Authorization" (format nil "Bearer ~A" token) rest)
        rest)))

(defun mcp-http-insufficient-scope-p (headers)
  (let ((header (cadr-ai::header-value headers "www-authenticate")))
    (and (stringp header)
         (cl-ppcre:scan "(?i)(?:^|[\\s,])error=\"?insufficient_scope\"?" header))))

(defun mcp-http-needs-authorization-p (status headers)
  (or (eql status 401)
      (and (eql status 403) (mcp-http-insufficient-scope-p headers))))

(defun mcp-http-issue (transport method extra-headers body allow-closed)
  (unless allow-closed
    (when (or (mcp-abort-aborted-p (mcp-http-transport-abort transport))
              (mcp-http-transport-closed-p transport))
      (error 'mcp-abort-error)))
  (let ((cadr-ai::*native-http-abort-p*
          (if allow-closed
              nil
              (lambda ()
                (or (mcp-http-transport-closed-p transport)
                    (mcp-abort-aborted-p
                     (mcp-http-transport-abort transport)))))))
    (multiple-value-bind (stream status headers)
        (cadr-ai::native-http-request
         (mcp-http-transport-url transport)
         :method method
         :headers (mcp-http-header-alist transport extra-headers)
         :content body
         :want-stream t
         :connect-timeout 10
         :read-timeout 120)
      (mcp-http-remember-stream transport stream)
      (values stream status headers))))

(defun mcp-http-request (transport method extra-headers body &key allow-closed)
  ;; v1.4.0 streamable-http authorizedFetch. A stored access token
  ;; overrides a caller Authorization header. One 401, or a 403 whose
  ;; challenge is insufficient_scope, goes through the auth provider
  ;; and the request is sent again.
  (let* ((token-fn (mcp-http-transport-auth-token transport))
         (token (when token-fn (funcall token-fn)))
         (headers (if token-fn
                      (mcp-http-with-bearer extra-headers token)
                      extra-headers)))
    (multiple-value-bind (stream status response-headers)
        (mcp-http-issue transport method headers body allow-closed)
      (let ((recover (mcp-http-transport-auth-unauthorized transport)))
        (unless (and recover
                     (mcp-http-needs-authorization-p status response-headers))
          (return-from mcp-http-request
            (values stream status response-headers)))
        (ignore-errors (close stream))
        (funcall recover
                 (list :server-url (mcp-http-transport-url transport)
                       :headers response-headers
                       :token token))
        (let ((next (when token-fn (funcall token-fn))))
          (mcp-http-issue transport method
                          (mcp-http-with-bearer extra-headers next)
                          body allow-closed))))))

(defun mcp-http-fail (transport stream status headers)
  (let ((body (handler-case
                  (mcp-read-bounded-text stream +mcp-error-body-bytes+)
                (error () ""))))
    (ignore-errors (close stream))
    (cond
      ((= status 401)
       (error 'mcp-auth-required-error
              :status 401
              :message "MCP server requires authentication"
              :body body
              :www-authenticate (cadr-ai::header-value headers "www-authenticate")))
      ((and (= status 404) (mcp-http-transport-session-id transport))
       (error 'mcp-session-expired-error
              :status 404
              :message "MCP session expired"
              :body body))
      (t
       (error 'mcp-http-error
              :status status
              :body body
              :message (mcp-describe-http-failure status body))))))

(defun mcp-http-ok-p (status)
  (and (integerp status) (<= 200 status 299)))

(defun mcp-http-consume-stream (transport stream on-message)
  (let ((cursor-id nil)
        (cursor-retry nil)
        (cursor-received nil))
    (consume-mcp-sse
     (mcp-stream-chunk-reader stream)
     :max-event-bytes (mcp-http-transport-max-message-bytes transport)
     :on-id (lambda (id) (setf cursor-id id))
     :on-retry (lambda (delay) (setf cursor-retry delay))
     :on-event
     (lambda (event)
       (setf cursor-received t)
       (let ((data (getf event :data))
             (name (getf event :event)))
         (unless (or (null data)
                     (zerop (length (string-trim
                                     '(#\Space #\Tab #\Newline #\Return)
                                     data)))
                     (and name (not (string= name "message"))))
           (handler-case
               (let ((message (mcp-parse-jsonrpc (mcp-read-json data))))
                 (when on-message
                   (funcall on-message message))
                 (mcp-http-emit-message transport message))
             (error (condition)
               (mcp-http-emit-error transport condition)))))))
    (values cursor-id cursor-retry cursor-received)))

(defun mcp-http-delay (transport attempt server-delay)
  (if server-delay
      server-delay
      (min (* (mcp-http-transport-initial-delay-ms transport)
              (expt 2 attempt))
           (mcp-http-transport-max-delay-ms transport))))

(defun mcp-http-sleep (transport milliseconds)
  (loop for remaining = (/ milliseconds 1000.0) then (- remaining 0.01)
        while (plusp remaining)
        do (when (or (mcp-http-transport-closed-p transport)
                     (mcp-abort-aborted-p (mcp-http-transport-abort transport)))
             (return-from mcp-http-sleep nil))
           (sleep (min 0.01 remaining)))
  (not (mcp-http-transport-closed-p transport)))

(defun mcp-http-retryable-p (error)
  (cond
    ((typep error 'mcp-http-error)
     (let ((status (mcp-http-error-status error)))
       (or (= status 408)
           (= status 429)
           (>= status 500))))
    ((typep error 'cadr-ai:network-error) t)
    (t nil)))

(defun mcp-http-open-sse (transport last-event-id)
  (let ((extra (list (cons "Accept" "text/event-stream"))))
    (when last-event-id
      (setf extra (append extra (list (cons "Last-Event-ID" last-event-id)))))
    (multiple-value-bind (stream status headers)
        (mcp-http-request transport :get extra nil)
      (when (= status 405)
        (ignore-errors (close stream))
        (return-from mcp-http-open-sse nil))
      (unless (mcp-http-ok-p status)
        (mcp-http-fail transport stream status headers))
      (mcp-http-capture-session transport headers)
      (unless (equal (mcp-http-content-type headers) "text/event-stream")
        (ignore-errors (close stream))
        (error 'mcp-http-error
               :status status
               :message (format nil "Unsupported MCP GET response content type: ~A"
                                (or (mcp-http-content-type headers) "missing"))))
      stream)))

(defun mcp-http-fail-request (transport request-id failure)
  (let ((reason (if failure
                    (princ-to-string failure)
                    "stream ended without a response")))
    (mcp-http-emit-message
     transport
     (mcp-obj "jsonrpc" "2.0"
              "id" request-id
              "error"
              (mcp-obj "code" +mcp-internal-error+
                       "message"
                       (format nil "MCP response stream failed: ~A" reason))))))

(defun mcp-http-follow-response (transport stream request-id)
  (let ((answered nil)
        (failure nil)
        (last-id nil)
        (retry nil)
        (received nil)
        (attempt 0))
    (loop
      (when stream
        (handler-case
            (multiple-value-bind (id delay got)
                (mcp-http-consume-stream
                 transport stream
                 (lambda (message)
                   (when (and (mcp-jsonrpc-response-p message)
                              (equal (mcp-get message "id") request-id))
                     (setf answered t))))
              (setf last-id id
                    retry delay
                    received got
                    failure nil))
          (error (condition)
            (setf failure condition))))
      (when (or answered (mcp-http-transport-closed-p transport))
        (return))
      (when (and failure (not (mcp-http-retryable-p failure)))
        (return))
      (when (or (null last-id)
                (>= attempt (mcp-http-transport-max-retries transport)))
        (return))
      (when received
        (setf attempt 0))
      (setf received nil)
      (unless (mcp-http-sleep transport (mcp-http-delay transport attempt retry))
        (return))
      (incf attempt)
      (handler-case
          (setf stream (mcp-http-open-sse transport last-id))
        (error (condition)
          (setf failure condition
                stream nil)
          (unless (mcp-http-retryable-p condition)
            (return)))))
    (unless (or answered (mcp-http-transport-closed-p transport))
      (mcp-http-fail-request transport request-id failure))))

(defun mcp-http-run-get (transport)
  (let ((last-id nil)
        (retry nil)
        (attempt 0))
    (loop until (mcp-http-transport-closed-p transport)
          do (handler-case
                 (let ((stream (mcp-http-open-sse transport last-id)))
                   (unless stream
                     (return))
                   (multiple-value-bind (id delay got)
                       (mcp-http-consume-stream transport stream nil)
                     (declare (ignore got))
                     (setf last-id id
                           retry delay
                           attempt 0)))
               (error (condition)
                 (when (mcp-http-transport-closed-p transport)
                   (return))
                 (unless (mcp-http-retryable-p condition)
                   (mcp-http-emit-error transport condition)
                   (return))))
             (when (>= attempt (mcp-http-transport-max-retries transport))
               (mcp-http-emit-error
                transport
                (make-condition
                 'simple-error
                 :format-control
                 "MCP server-to-client stream dropped and could not be reopened"
                 :format-arguments nil))
               (return))
             (unless (mcp-http-sleep
                      transport
                      (mcp-http-delay transport attempt retry))
               (return))
             (incf attempt))))

(defun mcp-http-start-get (transport)
  (when (or (not (mcp-http-transport-open-get-stream-p transport))
            (mcp-http-transport-get-started-p transport)
            (mcp-http-transport-closed-p transport))
    (return-from mcp-http-start-get nil))
  (setf (mcp-http-transport-get-started-p transport) t)
  (sb-thread:make-thread
   (lambda () (mcp-http-run-get transport))
   :name "mcp http get")
  nil)

(defmethod mcp-transport-send ((transport mcp-http-transport) message &key abort)
  (when (or (not (mcp-http-transport-started-p transport))
            (mcp-http-transport-closed-p transport))
    (error 'mcp-connection-closed-error))
  (when (and abort (mcp-abort-aborted-p abort))
    (error 'mcp-abort-error))
  (multiple-value-bind (stream status headers)
      (mcp-http-request
       transport :post
       (list (cons "Accept" "application/json, text/event-stream")
             (cons "Content-Type" "application/json"))
       (mcp-write-json message))
    (unwind-protect
         (progn
           (unless (mcp-http-ok-p status)
             (mcp-http-fail transport stream status headers))
           (mcp-http-capture-session transport headers)
           (cond
             ((not (mcp-jsonrpc-request-p message))
              (ignore-errors (close stream))
              (when (and (stringp (mcp-get message "method"))
                         (string= (mcp-get message "method")
                                  "notifications/initialized"))
                (mcp-http-start-get transport)))
             ((or (= status 202) (= status 204))
              (error 'mcp-http-error
                     :status status
                     :message
                     (format nil
                             "MCP server accepted request ~A without a response"
                             (mcp-get message "method"))))
             ((string= (mcp-http-content-type headers) "application/json")
              (let ((body (mcp-read-bounded-text stream nil)))
                (ignore-errors (close stream))
                (let ((parsed (mcp-read-json body)))
                  (dolist (item (if (mcp-json-sequence-p parsed)
                                    (coerce parsed 'list)
                                    (list parsed)))
                    (mcp-http-emit-message transport (mcp-parse-jsonrpc item))))))
             ((string= (mcp-http-content-type headers) "text/event-stream")
              (let ((body stream)
                    (request-id (mcp-get message "id")))
                (setf stream nil)
                (sb-thread:make-thread
                 (lambda ()
                   (mcp-http-follow-response transport body request-id))
                 :name "mcp http response")))
             (t
              (error 'mcp-http-error
                     :status status
                     :message
                     (format nil "Unsupported MCP response content type: ~A"
                             (or (mcp-http-content-type headers) "missing"))))))
      (when stream
        (ignore-errors (close stream)))))
  nil)

(defmethod mcp-transport-close ((transport mcp-http-transport))
  (when (mcp-http-transport-closed-p transport)
    (return-from mcp-transport-close nil))
  (setf (mcp-http-transport-closed-p transport) t)
  (mcp-abort (mcp-http-transport-abort transport))
  (dolist (stream (mcp-http-listeners transport 'streams))
    (ignore-errors (close stream :abort t)))
  (when (and (mcp-http-transport-started-p transport)
             (mcp-http-transport-session-id transport))
    (handler-case
        (multiple-value-bind (stream status headers)
            (mcp-http-request transport :delete nil nil :allow-closed t)
          (declare (ignore status headers))
          (ignore-errors (close stream)))
      (error () nil)))
  (mcp-http-emit-close transport)
  nil)
