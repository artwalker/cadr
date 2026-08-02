(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(defun goal12-codex-response-events (response-id text)
  (list (cadr-ai::json-object
         "type" "response.created"
         "response" (cadr-ai::json-object "id" response-id))
        (cadr-ai::json-object
         "type" "response.output_item.added" "output_index" 0
         "item" (cadr-ai::json-object "type" "message"))
        (cadr-ai::json-object
         "type" "response.output_text.delta" "output_index" 0
         "delta" text)
        (cadr-ai::json-object
         "type" "response.output_item.done" "output_index" 0
         "item"
         (cadr-ai::json-object
          "type" "message" "id" (format nil "msg-~A" response-id)
          "content"
          (vector
           (cadr-ai::json-object "type" "output_text" "text" text))))
        (cadr-ai::json-object
         "type" "response.completed"
         "response"
         (cadr-ai::json-object
          "id" response-id "status" "completed"
          "usage"
          (cadr-ai::json-object
           "input_tokens" 1 "output_tokens" 1
           "input_tokens_details"
           (cadr-ai::json-object "cached_tokens" 0))))))

(defun goal12-websocket-response-events (stream response-id text)
  (dolist (event (goal12-codex-response-events response-id text))
    (cadr-ai::write-websocket-frame
     stream #x1
     (babel:string-to-octets
      (cadr-ai::stringify-json event) :encoding :utf-8)
     :mask-p nil)))

(defun goal12-codex-sse-stream (response-id text)
  (flexi-streams:make-in-memory-input-stream
   (babel:string-to-octets
    (with-output-to-string (output)
      (dolist (event (goal12-codex-response-events response-id text))
        (format output "data: ~A~%~%" (cadr-ai::stringify-json event))))
    :encoding :utf-8)))

(defun goal12-codex-provider-and-model (port)
  (values
   (cadr-ai:make-openai-codex-provider
    :oauth-access-token "token" :oauth-account-id "account")
   (cadr-ai:make-model
    :id "gpt-test" :provider :openai-codex
    :api :openai-codex-responses
    :base-url (format nil "http://127.0.0.1:~D" port)
    :max-tokens 4096)))

(defun goal12-accept-websocket (listener)
  (let* ((client
           (usocket:socket-accept
            listener :element-type '(unsigned-byte 8)))
         (stream (usocket:socket-stream client))
         (key nil))
    (cadr-ai::read-http-line stream)
    (loop for line = (cadr-ai::read-http-line stream)
          until (zerop (length line))
          when (uiop:string-prefix-p "Sec-WebSocket-Key:" line)
            do (setf key
                     (string-trim '(#\Space #\Tab)
                                  (subseq line (1+ (position #\: line))))))
    (write-http-string
     stream
     (format nil
             "HTTP/1.1 101 Switching Protocols~C~CUpgrade: websocket~C~CConnection: Upgrade~C~CSec-WebSocket-Accept: ~A~C~C~C~C"
             #\Return #\Linefeed #\Return #\Linefeed
             #\Return #\Linefeed
             (cadr-ai::websocket-accept-value key)
             #\Return #\Linefeed #\Return #\Linefeed))
    (values client stream)))

(test goal12-codex-websocket-cached-reuses-one-connection-and-sends-input-delta
  (cadr-ai:close-openai-codex-websocket-sessions)
  (cadr-ai:reset-openai-codex-websocket-debug-stats)
  (let* ((listener
           (usocket:socket-listen
            "127.0.0.1" 0 :reuse-address t
            :element-type '(unsigned-byte 8)))
         (port (usocket:get-local-port listener))
         (requests nil)
         (server-error nil)
         (server
           (bt:make-thread
            (lambda ()
              (handler-case
                  (multiple-value-bind (client stream)
                      (goal12-accept-websocket listener)
                    (unwind-protect
                         (dotimes (index 2)
                           (multiple-value-bind (opcode payload)
                               (cadr-ai::read-websocket-frame stream)
                             (unless (= #x1 opcode)
                               (error "Expected text frame, got opcode ~D" opcode))
                             (push
                              (cadr-ai::parse-json
                               (babel:octets-to-string
                                payload :encoding :utf-8))
                              requests))
                           (goal12-websocket-response-events
                            stream
                            (if (zerop index) "response-1" "response-2")
                            (if (zerop index) "alpha" "beta")))
                      (usocket:socket-close client)))
                (error (condition)
                  (setf server-error condition))))
            :name "cadr-test-codex-websocket"))
         (provider
           (cadr-ai:make-openai-codex-provider
            :oauth-access-token "token"
            :oauth-account-id "account"))
         (model
           (cadr-ai:make-model
            :id "gpt-test" :provider :openai-codex
            :api :openai-codex-responses
            :base-url (format nil "http://127.0.0.1:~D" port)
            :max-tokens 4096))
         (first-context
           (cadr-ai:make-context
            :system-prompt "system"
            :messages
            (list (cadr-ai:make-user-message :content "one"))))
         (first-message nil)
         (second-message nil))
    (unwind-protect
         (progn
           (setf first-message
                 (cadr-ai:stream-chat
                  provider model first-context
                  (lambda (event) (declare (ignore event)))
                  :transport :websocket-cached
                  :session-id "session-1"))
           (unless (eq :stop
                       (cadr-ai:assistant-message-stop-reason first-message))
             (error "First WebSocket request failed: ~A"
                    (cadr-ai:assistant-message-error-message first-message)))
           (setf second-message
                 (cadr-ai:stream-chat
                  provider model
                  (cadr-ai:make-context
                   :system-prompt "system"
                   :messages
                   (list
                    (cadr-ai:make-user-message :content "one")
                    first-message
                    (cadr-ai:make-user-message :content "two")))
                  (lambda (event) (declare (ignore event)))
                  :transport :websocket-cached
                  :session-id "session-1"))
           (bt:join-thread server)
           (when server-error (error server-error))
           (is (string= "alpha"
                        (cadr-ai:content-text
                         (cadr-ai:assistant-message-content first-message))))
           (is (string= "beta"
                        (cadr-ai:content-text
                         (cadr-ai:assistant-message-content second-message))))
           (let* ((sent (nreverse requests))
                  (second (second sent))
                  (stats
                    (cadr-ai:get-openai-codex-websocket-debug-stats
                     "session-1")))
             (is (= 2 (length sent)))
             (is (string= "response-1"
                          (cadr-ai::json-get second "previous_response_id")))
             (is (= 1 (length (cadr-ai::json-get second "input"))))
             (is (= 1 (getf stats :connections-reused)))
             (is (= 2 (getf stats :cached-context-requests)))
             (is (zerop (getf stats :store-true-requests)))
             (is (= 1 (getf stats :full-context-requests)))
             (is (= 1 (getf stats :delta-requests)))
             (is (= 1 (getf stats :last-input-items)))
             (is (= 1 (getf stats :last-delta-input-items)))
             (is (string= "response-1"
                          (getf stats :last-previous-response-id)))))
      (cadr-ai:close-openai-codex-websocket-sessions)
      (ignore-errors (usocket:socket-close listener))
      (when (bt:thread-alive-p server)
        (bt:join-thread server)))))

(test goal12-codex-request-compression-falls-back-without-zstd-support
  (let ((cadr-ai::*zstd-compress-function* nil))
    (is (null (cadr-ai::compress-request-body-zstd "{\"ok\":true}")))))

(test goal12-codex-debug-stats-reset-is-session-scoped-and-non-creating
  (cadr-ai:reset-openai-codex-websocket-debug-stats)
  (is (null
       (cadr-ai:get-openai-codex-websocket-debug-stats "not-created")))
  (cadr-ai::increment-codex-stat "one" :requests)
  (cadr-ai::increment-codex-stat "two" :requests)
  (cadr-ai:reset-openai-codex-websocket-debug-stats "one")
  (is (null (cadr-ai:get-openai-codex-websocket-debug-stats "one")))
  (is (= 1
         (getf (cadr-ai:get-openai-codex-websocket-debug-stats "two")
               :requests)))
  (cadr-ai:reset-openai-codex-websocket-debug-stats))

(test goal12-codex-sse-request-uses-optional-zstd-with-exact-wire-headers
  (multiple-value-bind (provider model)
      (goal12-codex-provider-and-model 1)
    (let* ((cadr-ai::*zstd-compress-function*
             (lambda (octets)
               (is (plusp (length octets)))
               (make-array 4 :element-type '(unsigned-byte 8)
                             :initial-contents '(40 181 47 253))))
           (request
             (cadr-ai:build-request
              provider model
              (cadr-ai:make-context
               :messages (list (cadr-ai:make-user-message :content "one")))
              :stream-p t))
           (prepared (cadr-ai::prepare-provider-sse-request provider request)))
      (is (equalp #(40 181 47 253)
                  (cadr-ai:request-spec-raw-body prepared)))
      (is (string= "zstd"
                   (cdr (assoc "content-encoding"
                               (cadr-ai:request-spec-headers prepared)
                               :test #'string-equal)))))))

(test goal12-codex-auto-falls-back-to-sse-only-before-first-websocket-event
  (cadr-ai:close-openai-codex-websocket-sessions)
  (cadr-ai:reset-openai-codex-websocket-debug-stats)
  (let* ((listener
           (usocket:socket-listen
            "127.0.0.1" 0 :reuse-address t
            :element-type '(unsigned-byte 8)))
         (port (usocket:get-local-port listener))
         (server-error nil)
         (server
           (bt:make-thread
            (lambda ()
              (handler-case
                  (multiple-value-bind (client stream)
                      (goal12-accept-websocket listener)
                    (declare (ignore stream))
                    (usocket:socket-close client))
                (error (condition) (setf server-error condition))))))
         (http-calls 0)
         (events nil))
    (unwind-protect
         (multiple-value-bind (provider model)
             (goal12-codex-provider-and-model port)
           (let* ((cadr-ai:*http-request-function*
                    (lambda (url &key method headers content connect-timeout
                                   read-timeout want-stream force-string force-binary)
                      (declare (ignore url method headers content connect-timeout
                                       read-timeout want-stream force-string force-binary))
                      (incf http-calls)
                      (values (goal12-codex-sse-stream "sse-1" "fallback")
                              200 '(("content-type" . "text/event-stream")))))
                  (message
                    (cadr-ai:stream-chat
                     provider model
                     (cadr-ai:make-context
                      :messages (list (cadr-ai:make-user-message :content "one")))
                     (lambda (event) (push event events))
                     :transport :auto :session-id "fallback-before")))
             (bt:join-thread server)
             (when server-error (error server-error))
             (is (= 1 http-calls))
             (is (eq :stop (cadr-ai:assistant-message-stop-reason message)))
             (is (string= "fallback"
                          (cadr-ai:content-text
                           (cadr-ai:assistant-message-content message))))
             (is (= 1 (count :start events
                             :key #'cadr-ai:stream-event-type)))
             (let ((stats
                     (cadr-ai:get-openai-codex-websocket-debug-stats
                      "fallback-before")))
               (is (= 1 (getf stats :websocket-failures)))
               (is (= 1 (getf stats :sse-fallbacks))))))
      (cadr-ai:close-openai-codex-websocket-sessions)
      (ignore-errors (usocket:socket-close listener))
      (when (bt:thread-alive-p server) (bt:join-thread server)))))

(test goal12-codex-auto-does-not-replay-over-sse-after-first-websocket-event
  (cadr-ai:close-openai-codex-websocket-sessions)
  (cadr-ai:reset-openai-codex-websocket-debug-stats)
  (let* ((listener
           (usocket:socket-listen
            "127.0.0.1" 0 :reuse-address t
            :element-type '(unsigned-byte 8)))
         (port (usocket:get-local-port listener))
         (server-error nil)
         (server
           (bt:make-thread
            (lambda ()
              (handler-case
                  (multiple-value-bind (client stream)
                      (goal12-accept-websocket listener)
                    (unwind-protect
                         (progn
                           (cadr-ai::read-websocket-frame stream)
                           (cadr-ai::write-websocket-frame
                            stream #x1
                            (babel:string-to-octets
                             (cadr-ai::stringify-json
                              (first (goal12-codex-response-events "partial" "")))
                             :encoding :utf-8)
                            :mask-p nil))
                      (usocket:socket-close client)))
                (error (condition) (setf server-error condition))))))
         (http-calls 0)
         (events nil))
    (unwind-protect
         (multiple-value-bind (provider model)
             (goal12-codex-provider-and-model port)
           (let* ((cadr-ai:*http-request-function*
                    (lambda (&rest arguments)
                      (declare (ignore arguments))
                      (incf http-calls)
                      (error "SSE must not be called after a WebSocket event")))
                  (message
                    (cadr-ai:stream-chat
                     provider model
                     (cadr-ai:make-context
                      :messages (list (cadr-ai:make-user-message :content "one")))
                     (lambda (event) (push event events))
                     :transport :auto :session-id "fallback-after")))
             (bt:join-thread server)
             (when server-error (error server-error))
             (is (zerop http-calls))
             (is (eq :error (cadr-ai:assistant-message-stop-reason message)))
             (is (equal '(:start :error)
                        (mapcar #'cadr-ai:stream-event-type (nreverse events))))
             (let ((stats
                     (cadr-ai:get-openai-codex-websocket-debug-stats
                      "fallback-after")))
               (is (= 1 (getf stats :websocket-failures)))
               (is (zerop (getf stats :sse-fallbacks))))))
      (cadr-ai:close-openai-codex-websocket-sessions)
      (ignore-errors (usocket:socket-close listener))
      (when (bt:thread-alive-p server) (bt:join-thread server)))))

(test goal12-websocket-handshake-matches-rfc6455-vector
  (is (string=
       "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
       (cadr-ai::websocket-accept-value
       "dGhlIHNhbXBsZSBub25jZQ=="))))

(test goal12-codex-websocket-cached-probe-cli-matches-baseline-options
  (multiple-value-bind (output error-output status)
      (uiop:run-program
       (list "sbcl" "--script"
             (namestring
              (fixture-path "scripts/codex-websocket-cached-probe.lisp"))
             "--help")
       :output :string :error-output :string :ignore-error-status t)
    (is (zerop status) "~A" error-output)
    (dolist (fragment
             '("--turns <n>" "--transport <mode>" "websocket-cached"
               "--reasoning <level>" "--max-tokens <n>" "--session-id <id>"))
      (is-true (search fragment output)))))
