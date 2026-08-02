(in-package #:cadr-ai)

(defparameter +websocket-guid+ "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
(defparameter +codex-websocket-beta+ "responses_websockets=2026-02-06")
(defconstant +codex-websocket-idle-seconds+ 300)
(defconstant +codex-websocket-max-age-seconds+ 3300)

(defparameter *zstd-compress-function* nil)

(defun compress-request-body-zstd (body)
  "Return compressed BODY octets when optional zstd support is installed.
NIL means that the caller must send the original, uncompressed body."
  (when *zstd-compress-function*
    (handler-case
        (funcall *zstd-compress-function* (utf8-octets body))
      (error () nil))))

(defmethod prepare-provider-sse-request
    ((provider openai-codex-provider) request)
  (declare (ignore provider))
  (let ((compressed
          (compress-request-body-zstd
           (stringify-json (request-spec-payload request)))))
    (when compressed
      (setf (request-spec-raw-body request) compressed
            (request-spec-headers request)
            (acons "content-encoding" "zstd"
                   (remove "content-encoding"
                           (request-spec-headers request)
                           :key #'car :test #'string-equal))))
    request))

(defun rotate-left-32 (value count)
  (let ((word (ldb (byte 32 0) value)))
    (ldb (byte 32 0)
         (logior (ash word count)
                 (ash word (- count 32))))))

(defun sha1-bytes (octets)
  (let* ((length (length octets))
         (bit-length (* length 8))
         (padding (mod (- 56 (1+ length)) 64))
         (message (make-array (+ length 1 padding 8)
                              :element-type '(unsigned-byte 8)
                              :initial-element 0))
         (h0 #x67452301)
         (h1 #xefcdab89)
         (h2 #x98badcfe)
         (h3 #x10325476)
         (h4 #xc3d2e1f0))
    (replace message octets)
    (setf (aref message length) #x80)
    (dotimes (index 8)
      (setf (aref message (- (length message) 1 index))
            (ldb (byte 8 (* index 8)) bit-length)))
    (loop for offset from 0 below (length message) by 64
          do
          (let ((words (make-array 80 :element-type '(unsigned-byte 32))))
            (dotimes (index 16)
              (setf (aref words index)
                    (logior
                     (ash (aref message (+ offset (* index 4))) 24)
                     (ash (aref message (+ offset (* index 4) 1)) 16)
                     (ash (aref message (+ offset (* index 4) 2)) 8)
                     (aref message (+ offset (* index 4) 3)))))
            (loop for index from 16 below 80
                  do (setf (aref words index)
                           (rotate-left-32
                            (logxor (aref words (- index 3))
                                    (aref words (- index 8))
                                    (aref words (- index 14))
                                    (aref words (- index 16)))
                            1)))
            (let ((a h0) (b h1) (c h2) (d h3) (e h4))
              (dotimes (index 80)
                (multiple-value-bind (function constant)
                    (cond
                      ((< index 20)
                       (values (logior (logand b c)
                                       (logand (lognot b) d))
                               #x5a827999))
                      ((< index 40)
                       (values (logxor b c d) #x6ed9eba1))
                      ((< index 60)
                       (values (logior (logand b c)
                                       (logand b d)
                                       (logand c d))
                               #x8f1bbcdc))
                      (t (values (logxor b c d) #xca62c1d6)))
                  (let ((temporary
                          (ldb (byte 32 0)
                               (+ (rotate-left-32 a 5)
                                  function e constant
                                  (aref words index)))))
                    (setf e d
                          d c
                          c (rotate-left-32 b 30)
                          b a
                          a temporary))))
              (setf h0 (ldb (byte 32 0) (+ h0 a))
                    h1 (ldb (byte 32 0) (+ h1 b))
                    h2 (ldb (byte 32 0) (+ h2 c))
                    h3 (ldb (byte 32 0) (+ h3 d))
                    h4 (ldb (byte 32 0) (+ h4 e))))))
    (let ((result (make-array 20 :element-type '(unsigned-byte 8))))
      (loop for word in (list h0 h1 h2 h3 h4)
            for offset from 0 by 4
            do (dotimes (index 4)
                 (setf (aref result (+ offset index))
                       (ldb (byte 8 (* 8 (- 3 index))) word))))
      result)))

(defun standard-base64-encode (octets)
  (let ((encoded (base64url-encode octets)))
    (setf encoded (substitute #\+ #\- encoded)
          encoded (substitute #\/ #\_ encoded))
    (concatenate 'string encoded
                 (make-string (mod (- 4 (mod (length encoded) 4)) 4)
                              :initial-element #\=))))

(defun websocket-accept-value (key)
  (standard-base64-encode
   (sha1-bytes
    (utf8-octets (concatenate 'string key +websocket-guid+)))))

(defun write-websocket-length (stream length marker)
  (write-byte marker stream)
  (loop for shift downfrom (* 8 (1- (if (= marker 126) 2 8))) to 0 by 8
        do (write-byte (ldb (byte 8 shift) length) stream)))

(defun write-websocket-frame (stream opcode payload &key (mask-p t))
  (let* ((length (length payload))
         (mask (and mask-p (secure-random-bytes 4))))
    (write-byte (logior #x80 opcode) stream)
    (cond
      ((< length 126)
       (write-byte (logior (if mask-p #x80 0) length) stream))
      ((<= length #xffff)
       (write-byte (logior (if mask-p #x80 0) 126) stream)
       (write-byte (ldb (byte 8 8) length) stream)
       (write-byte (ldb (byte 8 0) length) stream))
      (t
       (write-byte (logior (if mask-p #x80 0) 127) stream)
       (loop for shift downfrom 56 to 0 by 8
             do (write-byte (ldb (byte 8 shift) length) stream))))
    (when mask-p (write-sequence mask stream))
    (dotimes (index length)
      (write-byte
       (if mask-p
           (logxor (aref payload index) (aref mask (mod index 4)))
           (aref payload index))
       stream))
    (finish-output stream)))

(defun read-websocket-exactly (stream count)
  (let ((result (make-array count :element-type '(unsigned-byte 8))))
    (loop with offset = 0
          while (< offset count)
          for next = (read-sequence result stream :start offset)
          do (when (= next offset)
               (error 'sse-protocol-error :message "Truncated WebSocket frame"))
             (setf offset next))
    result))

(defun read-websocket-frame (stream)
  (let ((first (read-byte stream nil :eof))
        (second (read-byte stream nil :eof)))
    (when (or (eq first :eof) (eq second :eof))
      (error 'network-error :message "WebSocket connection closed"
             :retryable-p t))
    (let* ((opcode (logand first #x0f))
           (masked-p (logbitp 7 second))
           (marker (logand second #x7f))
           (length
             (cond
               ((< marker 126) marker)
               ((= marker 126)
                (logior (ash (read-byte stream) 8) (read-byte stream)))
               (t
                (loop repeat 8
                      for value = 0 then (logior (ash value 8)
                                                  (read-byte stream))
                      finally (return value)))))
           (mask (and masked-p (read-websocket-exactly stream 4)))
           (payload (read-websocket-exactly stream length)))
      (when mask
        (dotimes (index length)
          (setf (aref payload index)
                (logxor (aref payload index)
                        (aref mask (mod index 4))))))
      (values opcode payload))))

(defstruct codex-websocket
  stream socket created-at last-used)

(defstruct codex-websocket-cache-entry
  connection
  request-body
  response-items
  response-id
  (busy-p nil))

(defparameter *codex-websocket-cache* (make-hash-table :test #'equal))
(defparameter *codex-websocket-cache-lock*
  (sb-thread:make-mutex :name "cadr Codex WebSocket cache"))
(defparameter *codex-websocket-fallback-sessions* (make-hash-table :test #'equal))
(defparameter *codex-websocket-debug-stats* (make-hash-table :test #'equal))

(defun codex-stats (session-id)
  (or (gethash session-id *codex-websocket-debug-stats*)
      (setf (gethash session-id *codex-websocket-debug-stats*)
            (list :requests 0 :connections-created 0
                  :connections-reused 0 :delta-requests 0
                  :websocket-failures 0 :sse-fallbacks 0))))

(defun increment-codex-stat (session-id key)
  (let ((stats (codex-stats session-id)))
    (incf (getf stats key 0))
    (setf (gethash session-id *codex-websocket-debug-stats*) stats)))

(defun get-openai-codex-websocket-debug-stats (session-id)
  (sb-thread:with-mutex (*codex-websocket-cache-lock*)
    (copy-list (codex-stats session-id))))

(defun reset-openai-codex-websocket-debug-stats ()
  (sb-thread:with-mutex (*codex-websocket-cache-lock*)
    (clrhash *codex-websocket-debug-stats*))
  nil)

(defun close-codex-websocket (connection)
  (when connection
    (ignore-errors
      (write-websocket-frame
       (codex-websocket-stream connection) #x8 #()))
    (ignore-errors (close (codex-websocket-stream connection) :abort t))
    (ignore-errors
      (sb-bsd-sockets:socket-close (codex-websocket-socket connection)))))

(defun close-openai-codex-websocket-sessions (&optional session-id)
  (let ((connections nil))
    (sb-thread:with-mutex (*codex-websocket-cache-lock*)
      (if session-id
          (let ((entry (gethash session-id *codex-websocket-cache*)))
            (when entry
              (push (codex-websocket-cache-entry-connection entry) connections)
              (remhash session-id *codex-websocket-cache*))
            (remhash session-id *codex-websocket-fallback-sessions*))
          (progn
            (maphash
             (lambda (key entry)
               (declare (ignore key))
               (push (codex-websocket-cache-entry-connection entry) connections))
             *codex-websocket-cache*)
            (clrhash *codex-websocket-cache*)
            (clrhash *codex-websocket-fallback-sessions*))))
    (mapc #'close-codex-websocket connections))
  nil)

(register-session-resource-cleanup #'close-openai-codex-websocket-sessions)

(defun websocket-url-as-http-url (url)
  (cond
    ((uiop:string-prefix-p "https://" url)
     (concatenate 'string "https://" (subseq url 8)))
    ((uiop:string-prefix-p "http://" url)
     (concatenate 'string "http://" (subseq url 7)))
    (t url)))

(defun connect-codex-websocket (request abort-p environment)
  (let* ((url (websocket-url-as-http-url (request-spec-url request)))
         (target (parse-http-url url))
         (proxy (resolve-http-proxy-url-for-target url environment)))
    (multiple-value-bind (stream socket request-target)
        (connect-native-http-stream target url proxy 10 nil abort-p)
      (handler-case
          (let* ((key (standard-base64-encode (secure-random-bytes 16)))
                 (headers
                   (append
                    (remove-if
                     (lambda (header)
                       (member (string-downcase (car header))
                               '("content-type" "accept" "content-length"
                                 "connection" "upgrade" "sec-websocket-key"
                                 "sec-websocket-version")
                               :test #'string=))
                     (request-spec-headers request))
                    `(("Host" . ,(parsed-url-authority target))
                      ("Upgrade" . "websocket")
                      ("Connection" . "Upgrade")
                      ("Sec-WebSocket-Key" . ,key)
                      ("Sec-WebSocket-Version" . "13")
                      ("OpenAI-Beta" . ,+codex-websocket-beta+)))))
            (write-http-request stream target :get headers nil request-target)
            (multiple-value-bind (status response-headers)
                (parse-response-headers stream)
              (unless (= status 101)
                (error 'network-error
                       :message (format nil "WebSocket handshake failed with status ~D" status)
                       :retryable-p t))
              (unless (string=
                       (or (header-value response-headers "sec-websocket-accept") "")
                       (websocket-accept-value key))
                (error 'sse-protocol-error
                       :message "WebSocket handshake returned an invalid accept key")))
            (make-codex-websocket
             :stream stream :socket socket
             :created-at (get-universal-time)
             :last-used (get-universal-time)))
        (error (condition)
          (ignore-errors (close stream :abort t))
          (ignore-errors (sb-bsd-sockets:socket-close socket))
          (error condition))))))

(defun codex-websocket-expired-p (connection)
  (let ((now (get-universal-time)))
    (or (> (- now (codex-websocket-last-used connection))
           +codex-websocket-idle-seconds+)
        (> (- now (codex-websocket-created-at connection))
           +codex-websocket-max-age-seconds+))))

(defun acquire-codex-websocket (session-id request abort-p environment cached-p)
  (let ((reused-p nil) (old nil) (entry nil))
    (when cached-p
      (sb-thread:with-mutex (*codex-websocket-cache-lock*)
        (setf entry (gethash session-id *codex-websocket-cache*))
        (when (and entry
                   (or (codex-websocket-cache-entry-busy-p entry)
                       (codex-websocket-expired-p
                        (codex-websocket-cache-entry-connection entry))))
          (unless (codex-websocket-cache-entry-busy-p entry)
            (setf old (codex-websocket-cache-entry-connection entry)))
          (setf entry nil)
          (remhash session-id *codex-websocket-cache*))
        (when entry
          (setf (codex-websocket-cache-entry-busy-p entry) t
                reused-p t))))
    (when old (close-codex-websocket old))
    (unless entry
      (let ((connection
              (connect-codex-websocket request abort-p environment)))
        (setf entry (make-codex-websocket-cache-entry :connection connection
                                                      :busy-p cached-p))
        (when cached-p
          (sb-thread:with-mutex (*codex-websocket-cache-lock*)
            (setf (gethash session-id *codex-websocket-cache*) entry)))))
    (values entry reused-p)))

(defun json-value-equal-p (left right)
  (string= (stringify-json left) (stringify-json right)))

(defun vector-prefix-p (prefix value)
  (and (vectorp prefix) (vectorp value)
       (<= (length prefix) (length value))
       (loop for index below (length prefix)
             always (json-value-equal-p (aref prefix index)
                                        (aref value index)))))

(defun codex-continuation-payload (entry payload session-id)
  (let ((previous-body (codex-websocket-cache-entry-request-body entry))
        (previous-response (codex-websocket-cache-entry-response-items entry))
        (previous-id (codex-websocket-cache-entry-response-id entry)))
    (when (and previous-body previous-response previous-id
               (let ((left (copy-json-value previous-body))
                     (right (copy-json-value payload)))
                 (remhash "input" left)
                 (remhash "input" right)
                 (json-value-equal-p left right)))
      (let* ((old-input (json-get previous-body "input" #()))
             (expected (concatenate 'vector old-input previous-response))
             (current (json-get payload "input" #())))
        (when (vector-prefix-p expected current)
          (json-put payload "input" (subseq current (length expected)))
          (json-put payload "previous_response_id" previous-id)
          (increment-codex-stat session-id :delta-requests))))
    payload))

(defun codex-response-items (model message)
  (let* ((context (make-context :messages (list message)))
         (items (openai-input-items model context)))
    items))

(defun read-codex-websocket-events
    (provider model entry state emit abort-p on-first-event)
  (declare (ignore model))
  (let ((stream
          (codex-websocket-stream
           (codex-websocket-cache-entry-connection entry))))
    (loop
      (check-abort abort-p)
      (multiple-value-bind (opcode payload)
          (read-websocket-frame stream)
        (case opcode
          (#x1
           (let* ((object
                    (parse-json (utf8-string payload)))
                  (type (json-get object "type")))
             (funcall on-first-event)
             (when (string= type "response.done")
               (setf (gethash "type" object) "response.completed"))
             (reduce-provider-sse-event
              provider state
              (make-sse-event :data (stringify-json object)) emit)
             (when (provider-stream-state-terminal-p state)
               (return))))
          (#x8
           (error 'network-error :message "WebSocket connection closed"
                  :retryable-p t))
          (#x9 (write-websocket-frame stream #xA payload))
          (#xA nil)
          (otherwise
           (error 'sse-protocol-error
                  :message (format nil "Unsupported WebSocket opcode ~D" opcode))))))))

(defun finish-codex-websocket-entry
    (entry model original-payload message cached-p)
  (setf (codex-websocket-last-used
         (codex-websocket-cache-entry-connection entry))
        (get-universal-time))
  (if cached-p
      (setf (codex-websocket-cache-entry-request-body entry)
            (copy-json-value original-payload)
            (codex-websocket-cache-entry-response-items entry)
            (codex-response-items model message)
            (codex-websocket-cache-entry-response-id entry)
            (assistant-message-response-id message)
            (codex-websocket-cache-entry-busy-p entry) nil)
      (close-codex-websocket
       (codex-websocket-cache-entry-connection entry))))

(defmethod build-request :around
    ((provider openai-codex-provider) model context
     &key &allow-other-keys)
  (let* ((request (call-next-method))
         (payload (request-spec-payload request))
         (input (json-get payload "input" #()))
         (first (and (plusp (length input)) (aref input 0))))
    (when (and first
               (member (json-get first "role") '("system" "developer")
                       :test #'string=))
      (json-put payload "input" (subseq input 1)))
    (json-put payload "instructions"
              (or (context-system-prompt context)
                  "You are a helpful assistant."))
    (json-put payload "text" (json-object "verbosity" "low"))
    (json-put payload "include" (json-array "reasoning.encrypted_content"))
    (unless (json-present-p payload "tool_choice")
      (json-put payload "tool_choice" "auto"))
    (json-put payload "parallel_tool_calls" t)
    request))

(defmethod try-provider-websocket-stream
    ((provider openai-codex-provider) model context request state emit
     &key transport session-id abort-p on-response)
  (declare (ignore context))
  (let* ((mode (or transport :auto))
         (cached-p (eq mode :websocket-cached))
         (session-key (or session-id "default"))
         (entry nil)
         (websocket-started-p nil))
    (when (or (eq mode :sse)
              (and (eq mode :auto)
                   (gethash session-key *codex-websocket-fallback-sessions*)))
      (return-from try-provider-websocket-stream (values nil nil)))
    (unless (member mode '(:auto :websocket :websocket-cached))
      (error 'configuration-error
             :message (format nil "Invalid Codex transport: ~A" mode)))
    (increment-codex-stat session-key :requests)
    (handler-case
        (multiple-value-bind (acquired-entry reused-p)
            (acquire-codex-websocket
             session-key request abort-p
             (getf (provider-options provider) :environment)
             cached-p)
          (setf entry acquired-entry)
          (if reused-p
              (increment-codex-stat session-key :connections-reused)
              (increment-codex-stat session-key :connections-created))
          (let* ((original (copy-json-value (request-spec-payload request)))
                 (payload
                   (if cached-p
                       (codex-continuation-payload
                        entry (copy-json-value original) session-key)
                       original))
                 (wire (copy-json-value payload)))
            (json-put wire "type" "response.create")
            (when on-response (notify-provider-response on-response 101 nil model))
            (write-websocket-frame
             (codex-websocket-stream
              (codex-websocket-cache-entry-connection entry))
             #x1 (utf8-octets (stringify-json wire)))
            (read-codex-websocket-events
             provider model entry state emit abort-p
             (lambda ()
               (unless websocket-started-p
                 (setf websocket-started-p t)
                 (emit-event emit :start
                             (provider-stream-state-message state)))))
            (finalize-provider-stream provider model state emit)
            (let ((message (provider-stream-state-message state)))
              (unless (member (assistant-message-stop-reason message)
                              '(:stop :length :tool-use))
                (error 'sse-protocol-error
                       :message "Provider WebSocket stream failed"))
              (finish-codex-websocket-entry
               entry model original message cached-p)
              (emit-event emit :done message
                          :reason (assistant-message-stop-reason message))
              (values t message))))
      (error (condition)
        (increment-codex-stat session-key :websocket-failures)
        (if cached-p
            (close-openai-codex-websocket-sessions session-key)
            (when entry
              (close-codex-websocket
               (codex-websocket-cache-entry-connection entry))))
        (let ((message (provider-stream-state-message state)))
          (setf (assistant-message-diagnostics message)
                (append
                 (assistant-message-diagnostics message)
                 (list
                  (make-assistant-message-diagnostic
                   :type :provider-transport-failure
                   :error (condition-text condition provider)
                   :details
                   (list :configured-transport mode
                         :fallback-transport
                         (and (not websocket-started-p) :sse)
                         :events-emitted websocket-started-p
                         :phase (if websocket-started-p
                                    :after-message-stream-start
                                    :before-message-stream-start)))))))
        (if (and (eq mode :auto) (not websocket-started-p))
            (progn
              (sb-thread:with-mutex (*codex-websocket-cache-lock*)
                (setf (gethash session-key *codex-websocket-fallback-sessions*) t))
              (increment-codex-stat session-key :sse-fallbacks)
              (values nil nil))
            (error condition))))))
