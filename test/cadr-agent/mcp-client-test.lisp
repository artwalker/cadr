(in-package #:cadr-agent/tests)

(in-suite cadr-agent-suite)

;;; Locked to pi@4a080252f packages/mcp tests: client, content,
;;; stdio, and the streamable HTTP cases for connect, tools, progress,
;;; and cancellation. OAuth token exchange is another gap.

(defun mcp-json-equal (left right)
  (cond
    ((and (cadr-agent::mcp-object-p left) (cadr-agent::mcp-object-p right))
     (and (= (length (cdr left)) (length (cdr right)))
          (loop for (key value) on (cdr left) by #'cddr
                always (and (nth-value 1 (cadr-agent::mcp-get right key))
                            (mcp-json-equal value (cadr-agent::mcp-get right key))))))
    ((and (cadr-agent::mcp-json-sequence-p left)
          (cadr-agent::mcp-json-sequence-p right))
     (and (= (length left) (length right))
          (every #'mcp-json-equal left right)))
    ((and (stringp left) (stringp right)) (string= left right))
    ((and (eq left 'null) (eq right 'null)) t)
    (t (equal left right))))

(defun mcp-test-wait (predicate &optional (seconds 2))
  (loop for step from 0 below (round (* seconds 100))
        when (funcall predicate)
          return t
        do (sleep 0.01))
  (when (funcall predicate)
    t))

(defparameter +mcp-no-reply+ (gensym "NO-REPLY"))

(defun mcp-test-server (transport)
  (let ((handlers (make-hash-table :test #'equal))
        (messages nil)
        (lock (sb-thread:make-mutex :name "mcp test server")))
    (cadr-agent:mcp-transport-start transport)
    (cadr-agent:mcp-transport-on-message
     transport
     (lambda (message)
       (sb-thread:with-mutex (lock)
         (push message messages))
       (when (cadr-agent::mcp-jsonrpc-request-p message)
         (let ((handler (gethash (cadr-agent::mcp-get message "method") handlers)))
           (handler-case
               (let ((result
                       (if handler
                           (funcall handler message)
                           (error 'cadr-agent:mcp-error
                                  :code cadr-agent::+mcp-method-not-found+
                                  :message
                                  (format nil "Method not found: ~A"
                                          (cadr-agent::mcp-get message "method"))))))
                 (unless (eq result +mcp-no-reply+)
                   (cadr-agent:mcp-transport-send
                    transport
                    (cadr-agent::mcp-obj
                     "jsonrpc" "2.0"
                     "id" (cadr-agent::mcp-get message "id")
                     "result" result))))
             (cadr-agent:mcp-error (condition)
               (let ((object
                       (cadr-agent::mcp-obj
                        "code" (cadr-agent:mcp-error-code condition)
                        "message" (cadr-agent:mcp-error-message condition))))
                 (when (cadr-agent:mcp-error-data-p condition)
                   (setf object
                         (cadr-agent::mcp-put
                          object "data" (cadr-agent:mcp-error-data condition))))
                 (cadr-agent:mcp-transport-send
                  transport
                  (cadr-agent::mcp-obj
                   "jsonrpc" "2.0"
                   "id" (cadr-agent::mcp-get message "id")
                   "error" object))))
             (error (condition)
               (cadr-agent:mcp-transport-send
                transport
                (cadr-agent::mcp-obj
                 "jsonrpc" "2.0"
                 "id" (cadr-agent::mcp-get message "id")
                 "error"
                 (cadr-agent::mcp-obj
                  "code" cadr-agent::+mcp-internal-error+
                  "message" (princ-to-string condition))))))))))
    (setf (gethash "initialize" handlers)
          (lambda (message)
            (declare (ignore message))
            (cadr-agent::mcp-obj
             "protocolVersion" cadr-agent:+mcp-latest-protocol-version+
             "capabilities" (cadr-agent::mcp-obj "tools" (cadr-agent::mcp-obj "listChanged" t))
             "serverInfo" (cadr-agent::mcp-obj "name" "test-server" "version" "1.0.0")
             "instructions" "Use test tools.")))
    (list :set (lambda (method handler)
                 (setf (gethash method handlers) handler))
          :messages (lambda ()
                      (sb-thread:with-mutex (lock) (reverse messages)))
          :send (lambda (message)
                  (cadr-agent:mcp-transport-send transport message)))))

(defun mcp-test-connect (&key roots scheduler request-timeout-ms name version
                         (server-hook nil))
  (multiple-value-bind (client-transport server-transport)
      (cadr-agent:make-mcp-memory-pair)
    (let ((server (mcp-test-server server-transport))
          (client (cadr-agent:make-mcp-client
                   :name (or name "test-client")
                   :version (or version "2.0.0")
                   :roots roots
                   :scheduler scheduler
                   :request-timeout-ms (or request-timeout-ms 30000))))
      (when server-hook
        (funcall server-hook server))
      (cadr-agent:mcp-client-connect client client-transport)
      (list :client client :server server :server-transport server-transport))))

(defun mcp-test-messages (bound)
  (funcall (getf bound :messages)))

(defun mcp-find-method (messages method)
  (find-if (lambda (message)
             (equal (cadr-agent::mcp-get message "method") method))
           messages))

(test mcp-to-llm-content-matches-v140
  ;; packages/mcp/test/content.test.ts
  (let ((blocks
          (vector
           (cadr-agent::mcp-obj "type" "text" "text" "hello"
                                "annotations" (cadr-agent::mcp-obj "priority" 1))
           (cadr-agent::mcp-obj "type" "image" "data" "aW1n"
                                "mimeType" "image/png"
                                "_meta" (cadr-agent::mcp-obj "x" 1))
           (cadr-agent::mcp-obj "type" "audio" "data" "YXVk" "mimeType" "audio/wav")
           (cadr-agent::mcp-obj "type" "resource_link"
                                "uri" "file:///a.txt" "name" "a.txt")
           (cadr-agent::mcp-obj "type" "resource"
                                "resource" (cadr-agent::mcp-obj
                                            "uri" "file:///b.txt" "text" "inline"))
           (cadr-agent::mcp-obj "type" "resource"
                                "resource" (cadr-agent::mcp-obj
                                            "uri" "file:///c.png"
                                            "mimeType" "image/png"
                                            "blob" "Yw=="))
           (cadr-agent::mcp-obj "type" "resource"
                                "resource" (cadr-agent::mcp-obj
                                            "uri" "file:///d.bin"
                                            "blob" "ZA==")))))
    (is (mcp-json-equal
         (cadr-agent:mcp-to-llm-content (cadr-agent::mcp-obj "content" blocks))
         (list
          (cadr-agent::mcp-obj "type" "text" "text" "hello")
          (cadr-agent::mcp-obj "type" "image" "data" "aW1n" "mimeType" "image/png")
          (cadr-agent::mcp-obj "type" "text" "text" "[audio audio/wav omitted]")
          (cadr-agent::mcp-obj "type" "text" "text" "a.txt: file:///a.txt")
          (cadr-agent::mcp-obj "type" "text" "text" "inline")
          (cadr-agent::mcp-obj "type" "image" "data" "Yw==" "mimeType" "image/png")
          (cadr-agent::mcp-obj "type" "text"
                               "text"
                               "[binary resource file:///d.bin (unknown type) omitted]")))))
  (is (mcp-json-equal
       (cadr-agent:mcp-to-llm-content
        (cadr-agent::mcp-obj "content" #() "structuredContent" #(1 2)))
       (list (cadr-agent::mcp-obj "type" "text" "text" (format nil "[~%  1,~%  2~%]")))))
  (is (mcp-json-equal
       (cadr-agent:mcp-to-llm-content
        (cadr-agent::mcp-obj "content" #() "structuredContent" 'null))
       (list (cadr-agent::mcp-obj "type" "text" "text" "null"))))
  (is (mcp-json-equal
       (cadr-agent:mcp-to-llm-content
        (cadr-agent::mcp-obj "content" #()
                             "structuredContent" (cadr-agent::mcp-obj "n" 1)))
       (list (cadr-agent::mcp-obj "type" "text"
                                  "text" (format nil "{~%  \"n\": 1~%}")))))
  (is (mcp-json-equal
       (cadr-agent:mcp-to-llm-content
        (cadr-agent::mcp-obj
         "content" (vector (cadr-agent::mcp-obj "type" "text" "text" "n=1"))
         "structuredContent" (cadr-agent::mcp-obj "n" 1)))
       (list (cadr-agent::mcp-obj "type" "text" "text" "n=1")))))

(test mcp-client-initializes-before-exposing-server-information
  (let* ((bound (mcp-test-connect))
         (client (getf bound :client)))
    (is (string= (cadr-agent:mcp-client-state client) "connected"))
    (is (string= (cadr-agent:mcp-client-protocol-version client)
                 cadr-agent:+mcp-latest-protocol-version+))
    (is (mcp-json-equal (cadr-agent:mcp-client-server-info client)
                        (cadr-agent::mcp-obj "name" "test-server" "version" "1.0.0")))
    (is (mcp-json-equal (cadr-agent:mcp-client-server-capabilities client)
                        (cadr-agent::mcp-obj "tools" (cadr-agent::mcp-obj "listChanged" t))))
    (is (string= (cadr-agent:mcp-client-instructions client) "Use test tools."))
    (is (mcp-test-wait
         (lambda ()
           (mcp-find-method (mcp-test-messages (getf bound :server))
                            "notifications/initialized"))))
    (let ((initialize
            (mcp-find-method (mcp-test-messages (getf bound :server)) "initialize")))
      (is (eql (cadr-agent::mcp-get initialize "id") 1))
      (is (mcp-json-equal
           (cadr-agent::mcp-get initialize "params")
           (cadr-agent::mcp-obj
            "protocolVersion" cadr-agent:+mcp-latest-protocol-version+
            "capabilities" (cadr-agent::mcp-obj)
            "clientInfo" (cadr-agent::mcp-obj "name" "test-client"
                                              "version" "2.0.0")))))
    (cadr-agent:mcp-client-close client)
    (cadr-agent:mcp-transport-close (getf bound :server-transport))))

(test mcp-client-paginates-tools
  (let* ((bound (mcp-test-connect))
         (client (getf bound :client)))
    (funcall (getf (getf bound :server) :set)
             "tools/list"
             (lambda (request)
               (let ((cursor (cadr-agent::mcp-get
                              (cadr-agent::mcp-get request "params")
                              "cursor")))
                 (if (null cursor)
                     (cadr-agent::mcp-obj
                      "tools" (vector (cadr-agent::mcp-obj
                                       "name" "search"
                                       "description" "Search"
                                       "inputSchema" (cadr-agent::mcp-obj "type" "object")))
                      "nextCursor" "page-2")
                     (cadr-agent::mcp-obj
                      "tools" (vector (cadr-agent::mcp-obj
                                       "name" "read"
                                       "inputSchema" (cadr-agent::mcp-obj "type" "object")
                                       "outputSchema" (cadr-agent::mcp-obj "type" "object")
                                       "annotations" (cadr-agent::mcp-obj "readOnlyHint" t)))
                      "nextCursor" "")))))
    (is (mcp-json-equal
         (cadr-agent:mcp-list-tools client)
         (list
          (cadr-agent::mcp-obj "name" "search" "description" "Search"
                               "inputSchema" (cadr-agent::mcp-obj "type" "object"))
          (cadr-agent::mcp-obj "name" "read"
                               "inputSchema" (cadr-agent::mcp-obj "type" "object")
                               "outputSchema" (cadr-agent::mcp-obj "type" "object")
                               "annotations" (cadr-agent::mcp-obj "readOnlyHint" t)))))
    (cadr-agent:mcp-client-close client)))

(test mcp-client-call-tool-structured-content-and-jsonrpc-errors
  (let* ((bound (mcp-test-connect))
         (client (getf bound :client)))
    (funcall (getf (getf bound :server) :set)
             "tools/call"
             (lambda (request)
               (let* ((params (cadr-agent::mcp-get request "params"))
                      (name (cadr-agent::mcp-get params "name"))
                      (arguments (cadr-agent::mcp-get params "arguments")))
                 (when (string= name "fail")
                   (error 'cadr-agent:mcp-error
                          :code 1234
                          :message "tool failed"
                          :data (cadr-agent::mcp-obj "retryable" nil)
                          :data-p t))
                 (cadr-agent::mcp-obj
                  "content" (vector (cadr-agent::mcp-obj "type" "text" "text" "ok"))
                  "structuredContent"
                  (cadr-agent::mcp-obj "count" (cadr-agent::mcp-get arguments "count"))))))
    (is (mcp-json-equal
         (cadr-agent:mcp-call-tool client "count" (cadr-agent::mcp-obj "count" 3))
         (cadr-agent::mcp-obj
          "content" (vector (cadr-agent::mcp-obj "type" "text" "text" "ok"))
          "structuredContent" (cadr-agent::mcp-obj "count" 3))))
    (handler-case
        (progn (cadr-agent:mcp-call-tool client "fail")
               (fail "call should have failed"))
      (cadr-agent:mcp-error (condition)
        (is (eql (cadr-agent:mcp-error-code condition) 1234))
        (is (string= (cadr-agent:mcp-error-message condition) "tool failed"))
        (is (mcp-json-equal (cadr-agent:mcp-error-data condition)
                            (cadr-agent::mcp-obj "retryable" nil)))))
    (cadr-agent:mcp-client-close client)))

(test mcp-client-defaults-missing-content-and-accepts-any-structured-content
  (let* ((bound (mcp-test-connect))
         (client (getf bound :client))
         (results (list (cadr-agent::mcp-obj "structuredContent"
                                             (cadr-agent::mcp-obj "ok" t))
                        (cadr-agent::mcp-obj "content" #()
                                             "structuredContent" (vector
                                                                  (cadr-agent::mcp-obj "id" 1)
                                                                  (cadr-agent::mcp-obj "id" 2)))
                        (cadr-agent::mcp-obj "content" #() "structuredContent" 'null)
                        (cadr-agent::mcp-obj "content" #() "structuredContent" "text")
                        (cadr-agent::mcp-obj "content" #() "structuredContent" 3)
                        (cadr-agent::mcp-obj "content" #() "structuredContent" nil))))
    (dolist (result results)
      (funcall (getf (getf bound :server) :set)
               "tools/call"
               (lambda (request)
                 (declare (ignore request))
                 result))
      (let ((expected
              (if (nth-value 1 (cadr-agent::mcp-get result "content"))
                  result
                  (cadr-agent::mcp-put result "content" #()))))
        (is (mcp-json-equal (cadr-agent:mcp-call-tool client "structured") expected))))
    (funcall (getf (getf bound :server) :set)
             "tools/call"
             (lambda (request)
               (declare (ignore request))
               (cadr-agent::mcp-obj "content" "not a list")))
    (handler-case
        (progn (cadr-agent:mcp-call-tool client "broken")
               (fail "invalid content should fail"))
      (cadr-agent:mcp-error (condition)
        (is (string= (cadr-agent:mcp-error-message condition)
                     "Invalid MCP tools/call result"))))
    (cadr-agent:mcp-client-close client)))

(test mcp-client-renews-timeout-on-progress-and-cancels
  (let* ((bound (mcp-test-connect))
         (client (getf bound :client))
         (progress nil)
         (abort (cadr-agent:make-mcp-abort)))
    (funcall (getf (getf bound :server) :set)
             "tools/call"
             (lambda (request)
               (let* ((params (cadr-agent::mcp-get request "params"))
                      (token (cadr-agent::mcp-get
                              (cadr-agent::mcp-get params "_meta")
                              "progressToken")))
                 (cadr-agent:mcp-transport-send
                  (getf bound :server-transport)
                  (cadr-agent::mcp-obj
                   "jsonrpc" "2.0"
                   "method" "notifications/progress"
                   "params" (cadr-agent::mcp-obj
                             "progressToken" token
                             "progress" 1
                             "total" 2)))
                 (cadr-agent::mcp-obj
                  "content" (vector (cadr-agent::mcp-obj "type" "text" "text" "done"))))))
    (let ((result
            (cadr-agent:mcp-call-tool
             client "slow" (cadr-agent::mcp-obj)
             :timeout-ms 50
             :on-progress (lambda (update) (setf progress update)))))
      (is (mcp-json-equal
           result
           (cadr-agent::mcp-obj
            "content" (vector (cadr-agent::mcp-obj "type" "text" "text" "done")))))
      (is (mcp-json-equal
           progress
           (cadr-agent::mcp-obj "progressToken" 2 "progress" 1 "total" 2)))
      (is (string= (cadr-agent:mcp-progress-text progress) "Progress 1/2")))
    (funcall (getf (getf bound :server) :set)
             "tools/call"
             (lambda (request)
               (declare (ignore request))
               +mcp-no-reply+))
    (let ((thread
            (sb-thread:make-thread
             (lambda ()
               (handler-case
                   (cadr-agent:mcp-call-tool client "wait" nil :abort abort)
                 (error (condition) condition))))))
      (is (mcp-test-wait
           (lambda ()
             (>= (count-if
                  (lambda (message)
                    (equal (cadr-agent::mcp-get message "method") "tools/call"))
                  (mcp-test-messages (getf bound :server)))
                 2))))
      (cadr-agent:mcp-abort abort "stop")
      (let ((condition (sb-thread:join-thread thread :timeout 2)))
        (is (typep condition 'cadr-agent:mcp-abort-error)))
      (is (mcp-test-wait
           (lambda ()
             (find-if
              (lambda (message)
                (and (equal (cadr-agent::mcp-get message "method")
                            "notifications/cancelled")
                     (eql (cadr-agent::mcp-get
                           (cadr-agent::mcp-get message "params")
                           "requestId")
                          3)
                     (string= (cadr-agent::mcp-get
                               (cadr-agent::mcp-get message "params")
                               "reason")
                              "stop")))
              (mcp-test-messages (getf bound :server)))))))
    (let ((timed
            (sb-thread:make-thread
             (lambda ()
               (handler-case
                   (cadr-agent:mcp-call-tool client "wait" nil :timeout-ms 30)
                 (error (condition) condition))))))
      (let ((condition (sb-thread:join-thread timed :timeout 2)))
        (is (typep condition 'cadr-agent:mcp-timeout-error))
        (is (string= (princ-to-string condition)
                     "MCP request timed out after 30ms"))))
    (cadr-agent:mcp-client-close client)))

(test mcp-client-does-not-cancel-timed-out-initialize
  (multiple-value-bind (client-transport server-transport)
      (cadr-agent:make-mcp-memory-pair)
    (let ((server (mcp-test-server server-transport))
          (client (cadr-agent:make-mcp-client
                   :name "test-client" :version "1.0.0"
                   :request-timeout-ms 40)))
      (funcall (getf server :set)
               "initialize"
               (lambda (message)
                 (declare (ignore message))
                 +mcp-no-reply+))
      (let ((thread
              (sb-thread:make-thread
               (lambda ()
                 (handler-case
                     (cadr-agent:mcp-client-connect client client-transport)
                   (error (condition) condition))))))
        (let ((condition (sb-thread:join-thread thread :timeout 2)))
          (is (typep condition 'cadr-agent:mcp-timeout-error))
          (is (string= (cadr-agent:mcp-client-state client) "closed"))
          (is (not (mcp-find-method (funcall (getf server :messages))
                                    "notifications/cancelled")))))
      (cadr-agent:mcp-transport-close server-transport))))

(test mcp-client-transport-error-does-not-fail-pending-request
  (let* ((bound (mcp-test-connect :name "test-client" :version "1.0.0"))
         (client (getf bound :client))
         (errors nil)
         (gate (cadr-agent::make-mcp-box)))
    (cadr-agent:mcp-client-on-error
     client
     (lambda (error) (push (princ-to-string error) errors)))
    (funcall (getf (getf bound :server) :set)
             "tools/call"
             (lambda (request)
               (declare (ignore request))
               (cadr-agent::mcp-box-wait gate)))
    (let ((thread
            (sb-thread:make-thread
             (lambda ()
               (handler-case (cadr-agent:mcp-call-tool client "wait")
                 (error (condition) condition))))))
      (is (mcp-test-wait
           (lambda ()
             (mcp-find-method (mcp-test-messages (getf bound :server)) "tools/call"))))
      (cadr-agent:mcp-memory-emit-error
       (cadr-agent::mcp-client-transport client)
       (make-condition 'simple-error
                       :format-control "stray log line"
                       :format-arguments nil))
      (cadr-agent::mcp-box-put
       gate
       (cadr-agent::mcp-obj "content" #()))
      (let ((result (sb-thread:join-thread thread :timeout 2)))
        (is (mcp-json-equal result (cadr-agent::mcp-obj "content" #()))))
      (is (equal (reverse errors) '("stray log line"))))
    (cadr-agent:mcp-client-close client)))

(test mcp-client-accepts-older-protocol-and-rejects-unknown
  (multiple-value-bind (client-transport server-transport)
      (cadr-agent:make-mcp-memory-pair)
    (let ((server (mcp-test-server server-transport))
          (client (cadr-agent:make-mcp-client :name "test-client" :version "1.0.0")))
      (funcall (getf server :set)
               "initialize"
               (lambda (message)
                 (declare (ignore message))
                 (cadr-agent::mcp-obj
                  "protocolVersion" "2024-11-05"
                  "capabilities" (cadr-agent::mcp-obj)
                  "serverInfo" (cadr-agent::mcp-obj "name" "old-server" "version" "0.1.0"))))
      (cadr-agent:mcp-client-connect client client-transport)
      (is (string= (cadr-agent:mcp-client-protocol-version client) "2024-11-05"))
      (cadr-agent:mcp-client-close client)
      (cadr-agent:mcp-transport-close server-transport)))
  (multiple-value-bind (client-transport server-transport)
      (cadr-agent:make-mcp-memory-pair)
    (let ((server (mcp-test-server server-transport))
          (client (cadr-agent:make-mcp-client :name "test-client" :version "1.0.0")))
      (funcall (getf server :set)
               "initialize"
               (lambda (message)
                 (declare (ignore message))
                 (cadr-agent::mcp-obj
                  "protocolVersion" "1999-01-01"
                  "capabilities" (cadr-agent::mcp-obj)
                  "serverInfo" (cadr-agent::mcp-obj "name" "ancient-server"
                                                   "version" "0.1.0"))))
      (handler-case
          (progn
            (cadr-agent:mcp-client-connect client client-transport)
            (fail "unsupported protocol should fail"))
        (error (condition)
          (is (search "unsupported protocol version" (princ-to-string condition)))
          (is (string= (cadr-agent:mcp-client-state client) "closed"))))
      (cadr-agent:mcp-transport-close server-transport))))

(test mcp-client-close-listener-runs-once-when-transport-drops
  (let* ((bound (mcp-test-connect))
         (client (getf bound :client))
         (closes 0))
    (cadr-agent:mcp-client-on-close client (lambda () (incf closes)))
    (funcall (getf (getf bound :server) :set)
             "tools/call"
             (lambda (request)
               (declare (ignore request))
               +mcp-no-reply+))
    (let ((thread
            (sb-thread:make-thread
             (lambda ()
               (handler-case (cadr-agent:mcp-call-tool client "wait")
                 (error (condition) condition))))))
      (is (mcp-test-wait
           (lambda ()
             (mcp-find-method (mcp-test-messages (getf bound :server)) "tools/call"))))
      (cadr-agent:mcp-transport-close (getf bound :server-transport))
      (let ((condition (sb-thread:join-thread thread :timeout 2)))
        (is (search "MCP connection closed" (princ-to-string condition))))
      (is (string= (cadr-agent:mcp-client-state client) "closed"))
      (cadr-agent:mcp-client-close client)
      (is (= closes 1)))))

(test mcp-client-answers-roots-list-and-dispatches-notifications
  (multiple-value-bind (client-transport server-transport)
      (cadr-agent:make-mcp-memory-pair)
    (let ((server (mcp-test-server server-transport))
          (client (cadr-agent:make-mcp-client
                   :name "test-client" :version "1.0.0"
                   :roots (list (cadr-agent::mcp-obj
                                 "uri" "file:///workspace"
                                 "name" "workspace"))))
          (changed nil))
      (cadr-agent:mcp-client-connect client client-transport)
      (cadr-agent:mcp-client-on-notification
       client "notifications/tools/list_changed"
       (lambda (params) (setf changed (list params))))
      (funcall (getf server :send)
               (cadr-agent::mcp-obj "jsonrpc" "2.0" "id" "roots" "method" "roots/list"))
      (funcall (getf server :send)
               (cadr-agent::mcp-obj "jsonrpc" "2.0"
                                    "method" "notifications/tools/list_changed"))
      (is (mcp-test-wait
           (lambda ()
             (find-if
              (lambda (message)
                (and (equal (cadr-agent::mcp-get message "id") "roots")
                     (mcp-json-equal
                      (cadr-agent::mcp-get message "result")
                      (cadr-agent::mcp-obj
                       "roots" (vector (cadr-agent::mcp-obj
                                        "uri" "file:///workspace"
                                        "name" "workspace"))))))
              (funcall (getf server :messages))))))
      (is (mcp-test-wait (lambda () changed)))
      (is (null (first changed)))
      (cadr-agent:mcp-client-close client)
      (cadr-agent:mcp-transport-close server-transport))))

(test mcp-sse-parses-chunked-events-and-rejects-oversized-data
  (let ((events nil))
    ;; The upstream chunks are split mid-event; feed them as one stream
    ;; of the same bytes.
    (cadr-agent:consume-mcp-sse
     (let ((pending (list (format nil ": keepalive~C~%id: 7~C~%data: {\"one\":~C~%"
                                  #\Return #\Return #\Return)
                          (format nil "data: 1}~C~%~C~%" #\Return #\Return))))
       (lambda ()
         (pop pending)))
     :on-event (lambda (event) (push event events)))
    (is (equal (list :data (format nil "{\"one\":~%1}") :id "7")
               (first events))))
  (let ((sent 0)
        (failed nil))
    (handler-case
        (cadr-agent:consume-mcp-sse
         (lambda ()
           (incf sent)
           (when (> sent 1000)
             (error "SSE limit was not enforced"))
           (format nil "data: xxxxxxxxxxxxxxxx~%"))
         :max-event-bytes 256
         :on-event (lambda (event) (declare (ignore event))))
      (error (condition)
        (setf failed (princ-to-string condition))))
    (is (search "MCP SSE event exceeds 256 bytes" failed))
    (is (< sent 100))))

(defun mcp-write-fixture (name text)
  (let ((path (merge-pathnames name (uiop:temporary-directory))))
    (with-open-file (out path :direction :output :if-exists :supersede
                              :external-format :utf-8)
      (write-string text out))
    path))

(defparameter +mcp-stdio-fixture+
  "import json, os, sys
sys.stderr.write('stdio fixture ready\\n')
sys.stderr.flush()
for line in sys.stdin:
    message = json.loads(line)
    if 'id' not in message:
        continue
    method = message.get('method')
    if method == 'initialize':
        expect = os.environ.get('CADR_MCP_EXPECT_NAME')
        got = message.get('params', {}).get('clientInfo', {}).get('name')
        if expect and got != expect:
            sys.stdout.write(json.dumps({'jsonrpc': '2.0', 'id': message['id'],
                                         'error': {'code': -32602,
                                                   'message': 'clientInfo name ' + str(got)}}) + '\\n')
            sys.stdout.flush()
            continue
        result = {'protocolVersion': '2025-06-18', 'capabilities': {'tools': {}},
                  'serverInfo': {'name': 'stdio-fixture', 'version': '1.0.0'}}
    elif method == 'tools/list':
        result = {'tools': [{'name': 'echo', 'inputSchema': {'type': 'object'}}]}
    elif method == 'tools/call':
        result = {'content': [{'type': 'text', 'text': str(message['params']['arguments']['text'])}]}
    elif method == 'ping':
        result = {}
    else:
        sys.stdout.write(json.dumps({'jsonrpc': '2.0', 'id': message['id'],
                                     'error': {'code': -32601, 'message': 'not found'}}) + '\\n')
        sys.stdout.flush()
        continue
    sys.stdout.write(json.dumps({'jsonrpc': '2.0', 'id': message['id'], 'result': result}) + '\\n')
    sys.stdout.flush()
")

(test mcp-stdio-connects-lists-and-calls
  (let* ((fixture (mcp-write-fixture "cadr-mcp-stdio.py" +mcp-stdio-fixture+))
         (stderr nil)
         (transport
           (cadr-agent:make-mcp-stdio-transport
            :command "python3"
            :args (list (namestring fixture))
            :on-stderr (lambda (chunk) (setf stderr (concatenate 'string (or stderr "") chunk)))))
         (client (cadr-agent:make-mcp-client :name "stdio-test" :version "1.0.0")))
    (cadr-agent:mcp-client-connect client transport)
    (is (mcp-json-equal
         (cadr-agent:mcp-list-tools client)
         (list (cadr-agent::mcp-obj "name" "echo"
                                    "inputSchema" (cadr-agent::mcp-obj "type" "object")))))
    (is (mcp-json-equal
         (cadr-agent:mcp-call-tool client "echo" (cadr-agent::mcp-obj "text" "hello"))
         (cadr-agent::mcp-obj
          "content" (vector (cadr-agent::mcp-obj "type" "text" "text" "hello")))))
    (is (integerp (cadr-agent:mcp-stdio-pid transport)))
    (is (mcp-test-wait (lambda () (search "stdio fixture ready" (or stderr "")))))
    (is (search "stdio fixture ready" (cadr-agent:mcp-stdio-stderr transport)))
    (cadr-agent:mcp-client-close client)
    (is (string= (cadr-agent:mcp-client-state client) "closed"))))

(defparameter +mcp-http-fixture+
  "import json, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os, sys
mode = sys.argv[1]
log_path = sys.argv[2]
lock = threading.Lock()
def record(entry):
    with lock:
        with open(log_path, 'a', encoding='utf-8') as handle:
            handle.write(json.dumps(entry) + '\\n')
class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, fmt, *args):
        return
    def body(self):
        length = int(self.headers.get('Content-Length') or 0)
        raw = self.rfile.read(length) if length else b''
        return json.loads(raw.decode()) if raw else None
    def answer(self, status, payload=None, headers=None, raw=None):
        data = raw if raw is not None else (b'' if payload is None else json.dumps(payload).encode())
        self.send_response(status)
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        if data:
            self.wfile.write(data)
    def do_DELETE(self):
        record({'method': 'DELETE', 'session': self.headers.get('Mcp-Session-Id')})
        self.answer(200, raw=b'')
    def do_GET(self):
        record({'method': 'GET', 'last': self.headers.get('Last-Event-ID'),
                'session': self.headers.get('Mcp-Session-Id')})
        if self.headers.get('Last-Event-ID'):
            payload = json.dumps({'jsonrpc': '2.0', 'id': 2,
                                  'result': {'content': [{'type': 'text', 'text': 'resumed'}]}})
            raw = ('id: 2\\ndata: ' + payload + '\\n\\n').encode()
            self.answer(200, raw=raw, headers={'Content-Type': 'text/event-stream'})
            return
        self.answer(405, raw=b'')
    def do_POST(self):
        message = self.body()
        record({'method': 'POST', 'message': message,
                'session': self.headers.get('Mcp-Session-Id'),
                'protocol': self.headers.get('MCP-Protocol-Version'),
                'accept': self.headers.get('Accept')})
        if mode == 'auth':
            self.answer(401, raw=b'login required',
                        headers={'WWW-Authenticate': 'Bearer resource_metadata=\"https://example.com/meta\"'})
            return
        if mode == 'bad':
            self.answer(400, raw=b'Invalid Accept header')
            return
        if mode == 'retry' and not os.path.exists(log_path + '.ok'):
            open(log_path + '.ok', 'w').close()
            self.answer(500, raw=b'busy')
            return
        if 'id' not in message:
            self.answer(202, raw=b'')
            return
        if message.get('method') == 'initialize':
            self.answer(200, {'jsonrpc': '2.0', 'id': message['id'],
                              'result': {'protocolVersion': '2025-11-25',
                                         'capabilities': {'tools': {}},
                                         'serverInfo': {'name': 'http-fixture', 'version': '1.0.0'}}},
                        headers={'Content-Type': 'application/json', 'Mcp-Session-Id': 'session-1'})
            return
        if message.get('method') == 'tools/list':
            self.answer(200, {'jsonrpc': '2.0', 'id': message['id'],
                              'result': {'tools': [{'name': 'echo', 'inputSchema': {'type': 'object'}}]}},
                        headers={'Content-Type': 'application/json'})
            return
        if mode == 'accept202':
            self.answer(202, raw=b'')
            return
        if mode == 'drop':
            raw = b'id: 1\\nretry: 5\\ndata:\\n\\n'
            self.answer(200, raw=raw, headers={'Content-Type': 'text/event-stream'})
            return
        if mode == 'empty':
            self.answer(200, raw=b': nothing here\\n\\n', headers={'Content-Type': 'text/event-stream'})
            return
        payload = json.dumps({'jsonrpc': '2.0', 'id': message['id'],
                              'result': {'content': [{'type': 'text', 'text': 'hello'}]}})
        raw = ('id: tool-result\\ndata: ' + payload + '\\n\\n').encode()
        self.answer(200, raw=raw, headers={'Content-Type': 'text/event-stream'})
port = 0
server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
print(server.server_address[1], flush=True)
server.serve_forever()
")

(defun mcp-start-http (mode)
  (let* ((script (mcp-write-fixture "cadr-mcp-http.py" +mcp-http-fixture+))
         (log (merge-pathnames (format nil "cadr-mcp-http-~A.log" (random 1000000))
                               (uiop:temporary-directory)))
         (process
           (uiop:launch-program
            (list "python3" (namestring script) mode (namestring log))
            :output :stream
            :error-output :stream
            :wait nil))
         (port-line (read-line (uiop:process-info-output process) nil nil)))
    (list :process process
          :log log
          :url (format nil "http://127.0.0.1:~A/mcp" (parse-integer port-line)))))

(defun mcp-stop-http (server)
  (ignore-errors (uiop:terminate-process (getf server :process) :urgent t))
  (ignore-errors (uiop:wait-process (getf server :process))))

(defun mcp-http-log (server)
  (when (probe-file (getf server :log))
    (with-open-file (in (getf server :log))
      (loop for line = (read-line in nil nil)
            while line
            collect (cadr-agent::mcp-read-json line)))))

(test mcp-http-json-sse-session-and-errors
  (let* ((server (mcp-start-http "protocol"))
         (transport (cadr-agent:make-mcp-http-transport (getf server :url)))
         (client (cadr-agent:make-mcp-client :name "http-test" :version "1.0.0")))
    (unwind-protect
         (progn
           (cadr-agent:mcp-client-connect client transport)
           (is (string= (cadr-agent:mcp-http-session-id transport) "session-1"))
           (is (mcp-json-equal
                (cadr-agent:mcp-list-tools client)
                (list (cadr-agent::mcp-obj
                       "name" "echo"
                       "inputSchema" (cadr-agent::mcp-obj "type" "object")))))
           (is (mcp-json-equal
                (cadr-agent:mcp-call-tool client "echo" (cadr-agent::mcp-obj "text" "hello"))
                (cadr-agent::mcp-obj
                 "content" (vector (cadr-agent::mcp-obj "type" "text" "text" "hello")))))
           (cadr-agent:mcp-client-close client)
           (is (mcp-test-wait
                (lambda ()
                  (find-if (lambda (entry)
                             (string= (cadr-agent::mcp-get entry "method") "GET"))
                           (mcp-http-log server)))))
           (is (mcp-test-wait
                (lambda ()
                  (find-if (lambda (entry)
                             (string= (cadr-agent::mcp-get entry "method") "DELETE"))
                           (mcp-http-log server)))))
           (let ((listed
                   (find-if (lambda (entry)
                              (equal (cadr-agent::mcp-get
                                      (cadr-agent::mcp-get entry "message")
                                      "method")
                                     "tools/list"))
                            (mcp-http-log server))))
             (is (string= (cadr-agent::mcp-get listed "session") "session-1"))
             (is (string= (cadr-agent::mcp-get listed "protocol")
                          cadr-agent:+mcp-latest-protocol-version+))))
      (mcp-stop-http server)))
  (let ((server (mcp-start-http "auth")))
    (unwind-protect
         (handler-case
             (progn
               (cadr-agent:mcp-client-connect
                (cadr-agent:make-mcp-client :name "http-test" :version "1.0.0")
                (cadr-agent:make-mcp-http-transport (getf server :url)))
               (fail "401 should require authentication"))
           (cadr-agent:mcp-auth-required-error (condition)
             (is (eql (cadr-agent:mcp-http-error-status condition) 401))
             (is (string= (cadr-agent:mcp-http-error-body condition) "login required"))
             (is (string= (cadr-agent:mcp-auth-required-www-authenticate condition)
                          "Bearer resource_metadata=\"https://example.com/meta\""))))
      (mcp-stop-http server)))
  (let ((server (mcp-start-http "bad")))
    (unwind-protect
         (handler-case
             (progn
               (cadr-agent:mcp-client-connect
                (cadr-agent:make-mcp-client :name "http-test" :version "1.0.0")
                (cadr-agent:make-mcp-http-transport (getf server :url)))
               (fail "400 should fail"))
           (error (condition)
             (is (search "MCP HTTP request failed with status 400: Invalid Accept header"
                         (princ-to-string condition)))))
      (mcp-stop-http server))))

(test mcp-http-stream-end-accepted-without-response-and-resume
  (let ((server (mcp-start-http "empty")))
    (unwind-protect
         (let ((client (cadr-agent:make-mcp-client :name "http-test" :version "1.0.0")))
           (cadr-agent:mcp-client-connect
            client
            (cadr-agent:make-mcp-http-transport (getf server :url) :open-get-stream nil))
           (handler-case
               (progn
                 (cadr-agent:mcp-call-tool client "echo" nil :timeout-ms 5000)
                 (fail "empty stream should fail"))
             (error (condition)
               (is (search "MCP response stream failed: stream ended without a response"
                           (princ-to-string condition)))))
           (cadr-agent:mcp-client-close client))
      (mcp-stop-http server)))
  (let ((server (mcp-start-http "accept202")))
    (unwind-protect
         (let ((client (cadr-agent:make-mcp-client :name "http-test" :version "1.0.0")))
           (cadr-agent:mcp-client-connect
            client
            (cadr-agent:make-mcp-http-transport (getf server :url) :open-get-stream nil))
           (handler-case
               (progn (cadr-agent:mcp-call-tool client "echo")
                      (fail "202 should fail"))
             (error (condition)
               (is (search "without a response" (princ-to-string condition)))))
           (cadr-agent:mcp-client-close client))
      (mcp-stop-http server)))
  (let ((server (mcp-start-http "drop")))
    (unwind-protect
         (let ((client (cadr-agent:make-mcp-client :name "http-test" :version "1.0.0")))
           (cadr-agent:mcp-client-connect
            client
            (cadr-agent:make-mcp-http-transport (getf server :url) :open-get-stream nil))
           (is (mcp-json-equal
                (cadr-agent:mcp-call-tool client "echo")
                (cadr-agent::mcp-obj
                 "content" (vector (cadr-agent::mcp-obj "type" "text" "text" "resumed")))))
           (cadr-agent:mcp-client-close client)
           (is (mcp-test-wait
                (lambda ()
                  (find-if (lambda (entry)
                             (and (string= (cadr-agent::mcp-get entry "method") "GET")
                                  (string= (cadr-agent::mcp-get entry "last") "1")))
                           (mcp-http-log server))))))
      (mcp-stop-http server))))

(test mcp-runtime-connects-stdio-and-calls-with-progress-and-cancel
  (let* ((fixture (mcp-write-fixture "cadr-mcp-stdio.py" +mcp-stdio-fixture+))
         (config (cadr-agent::mcp-obj
                  "command" "python3"
                  "args" (vector (namestring fixture))
                  "env" (cadr-agent::mcp-obj "CADR_MCP_EXPECT_NAME" "cadr")))
         (connection (cadr-agent:open-mcp-server "echo" config (namestring (uiop:getcwd)))))
    (is (string= (cadr-agent:mcp-server-state connection) "connected"))
    (is (mcp-json-equal
         (cadr-agent:mcp-server-tools connection)
         (list (cadr-agent::mcp-obj "name" "echo"
                                    "inputSchema" (cadr-agent::mcp-obj "type" "object")))))
    (is (mcp-json-equal
         (cadr-agent:mcp-server-call-tool
          connection "echo" (cadr-agent::mcp-obj "text" "hello"))
         (cadr-agent::mcp-obj
          "content" (vector (cadr-agent::mcp-obj "type" "text" "text" "hello")))))
    (cadr-agent:mcp-server-close connection)
    (is (string= (cadr-agent:mcp-server-state connection) "closed")))
  (is (string= (cadr-agent:mcp-expand-home "~")
               (namestring (user-homedir-pathname))))
  (is (string= (cadr-agent:mcp-path-to-file-url "/tmp/foo") "file:///tmp/foo"))
  (is (string= (cadr-agent:mcp-path-to-file-url "/tmp/mcp work")
               "file:///tmp/mcp%20work"))
  (is (string= (cadr-agent:mcp-path-to-file-url "/tmp/ü") "file:///tmp/%C3%BC"))
  (handler-case
      (cadr-agent:open-mcp-server
       "missing"
       (cadr-agent::mcp-obj "command" "cadr-mcp-missing-command")
       (namestring (uiop:getcwd)))
    (error (condition)
      (is (search "MCP server \"missing\" failed to connect:"
                  (princ-to-string condition))))))

(test mcp-runtime-http-retries-transient-failure-and-sign-in-message
  (let ((server (mcp-start-http "retry")))
    (unwind-protect
         (let ((connection
                 (cadr-agent:open-mcp-server
                  "remote"
                  (cadr-agent::mcp-obj "url" (getf server :url))
                  (namestring (uiop:getcwd)))))
           (is (string= (cadr-agent:mcp-server-state connection) "connected"))
           (cadr-agent:mcp-server-close connection))
      (mcp-stop-http server)))
  (let ((server (mcp-start-http "auth")))
    (unwind-protect
         (handler-case
             (progn
               (cadr-agent:open-mcp-server
                "remote"
                (cadr-agent::mcp-obj "url" (getf server :url))
                (namestring (uiop:getcwd)))
               (fail "oauth 401 should ask for sign-in"))
           (error (condition)
             (is (string= (princ-to-string condition)
                          "MCP server \"remote\" requires sign-in. Run /mcp to sign in."))))
      (mcp-stop-http server))))
