(in-package #:cadr-agent/tests)

(in-suite cadr-agent-suite)

;;; Locked to pi@4a080252f packages/mcp/test/client.test.ts "lists and
;;; reads resources", packages/coding-agent/test/suite/agent-session-mcp.test.ts
;;; "lists and reads resources with Codex's resource tools", and
;;; resources.ts / runtime.ts (app resources, templates method-not-found,
;;; read-only retry, no list at connect).

(defun mcp-resource-text (result)
  (cadr-agent::mcp-get
   (first (cadr-agent:mcp-resource-call-result-content result))
   "text"))

(defun mcp-run-tool (tools name params)
  (funcall (cadr-agent:mcp-resource-tool-executor
            (find name tools
                  :key #'cadr-agent:mcp-resource-tool-name
                  :test #'string=))
           params))

(defun mcp-tool-error (tools name params)
  (handler-case
      (progn (mcp-run-tool tools name params) nil)
    (error (condition)
      (princ-to-string condition))))

(defun mcp-params (&rest pairs)
  (apply #'cadr-agent::mcp-obj pairs))

(defun mcp-fake-server (name &key resources templates reader fail
                               (timeout-ms 1000))
  (cadr-agent::make-mcp-resource-server
   :name name
   :timeout-ms timeout-ms
   :resources-page
   (lambda (cursor abort)
     (declare (ignore abort))
     (if (null cursor)
         (values resources nil)
         (values nil nil)))
   :templates-page
   (lambda (cursor abort)
     (declare (ignore cursor abort))
     (values (or templates nil) nil))
   :all-resources
   (lambda (abort)
     (declare (ignore abort))
     (if fail
         (error "~A" fail)
         resources))
   :all-templates
   (lambda (abort)
     (declare (ignore abort))
     (or templates nil))
   :read-resource
   (or reader
       (lambda (uri abort)
         (declare (ignore abort))
         (cadr-agent::mcp-obj
          "contents"
          (vector (cadr-agent::mcp-obj "uri" uri "text" "body")))))))

(test mcp-client-lists-and-reads-resources
  ;; packages/mcp/test/client.test.ts
  (let* ((bound (mcp-test-connect))
         (client (getf bound :client))
         (server (getf bound :server)))
    (funcall (getf server :set)
             "resources/list"
             (lambda (request)
               (if (cadr-agent::mcp-get
                    (cadr-agent::mcp-get request "params") "cursor")
                   (cadr-agent::mcp-obj
                    "resources" (vector (cadr-agent::mcp-obj "uri" "file:///b")))
                   (cadr-agent::mcp-obj
                    "resources"
                    (vector (cadr-agent::mcp-obj
                             "uri" "file:///a" "name" "a"
                             "mimeType" "text/plain"))
                    "nextCursor" "2"))))
    (funcall (getf server :set)
             "resources/templates/list"
             (lambda (request)
               (declare (ignore request))
               (cadr-agent::mcp-obj
                "resourceTemplates"
                (vector (cadr-agent::mcp-obj
                         "uriTemplate" "repo://{owner}/{repo}"
                         "name" "repo")))))
    (funcall (getf server :set)
             "resources/read"
             (lambda (request)
               (cadr-agent::mcp-obj
                "contents"
                (vector (cadr-agent::mcp-obj
                         "uri" (cadr-agent::mcp-get
                                (cadr-agent::mcp-get request "params") "uri")
                         "text" "hello")))))
    (is (mcp-json-equal
         (cadr-agent:mcp-list-resources client)
         (list (cadr-agent::mcp-obj "uri" "file:///a" "name" "a"
                                    "mimeType" "text/plain")
               (cadr-agent::mcp-obj "uri" "file:///b" "name" "file:///b"))))
    (is (mcp-json-equal
         (cadr-agent:mcp-list-resource-templates client)
         (list (cadr-agent::mcp-obj "uriTemplate" "repo://{owner}/{repo}"
                                    "name" "repo"))))
    (is (mcp-json-equal
         (cadr-agent:mcp-list-resources-page client)
         (cadr-agent::mcp-obj
          "resources"
          (vector (cadr-agent::mcp-obj "uri" "file:///a" "name" "a"
                                       "mimeType" "text/plain"))
          "nextCursor" "2")))
    (is (mcp-json-equal
         (cadr-agent:mcp-list-resources-page client "2")
         (cadr-agent::mcp-obj
          "resources"
          (vector (cadr-agent::mcp-obj "uri" "file:///b" "name" "file:///b")))))
    (is (mcp-json-equal
         (cadr-agent:mcp-read-resource client "file:///a")
         (cadr-agent::mcp-obj
          "contents"
          (vector (cadr-agent::mcp-obj "uri" "file:///a" "text" "hello")))))
    (funcall (getf server :set)
             "resources/read"
             (lambda (request)
               (declare (ignore request))
               (cadr-agent::mcp-obj
                "contents" (vector (cadr-agent::mcp-obj "uri" "file:///a")))))
    (is (string= (handler-case
                     (progn (cadr-agent:mcp-read-resource client "file:///a") "")
                   (cadr-agent:mcp-error (condition)
                     (cadr-agent:mcp-error-message condition)))
                 "Invalid contents in MCP resources/read result"))
    (funcall (getf server :set)
             "resources/list"
             (lambda (request)
               (declare (ignore request))
               (cadr-agent::mcp-obj
                "resources" (vector (cadr-agent::mcp-obj "name" "no uri")))))
    (is (string= (handler-case
                     (progn (cadr-agent:mcp-list-resources client) "")
                   (cadr-agent:mcp-error (condition)
                     (cadr-agent:mcp-error-message condition)))
                 "Invalid entry in MCP resources/list result"))
    (cadr-agent:mcp-client-close client)
    (cadr-agent:mcp-transport-close (getf bound :server-transport))))

(test mcp-resource-list-ends-on-null-or-empty-cursor
  (let* ((bound (mcp-test-connect))
         (client (getf bound :client))
         (server (getf bound :server))
         (parsed-null
           (cadr-agent::mcp-get
            (cadr-agent::mcp-read-json
             "{\"resources\":[{\"uri\":\"file:///a\",\"name\":\"a\"}],\"nextCursor\":null}")
            "nextCursor")))
    (dolist (end (list parsed-null ""))
      (funcall (getf server :set)
               "resources/list"
               (lambda (request)
                 (declare (ignore request))
                 (cadr-agent::mcp-obj
                  "resources"
                  (vector (cadr-agent::mcp-obj "uri" "file:///a" "name" "a"))
                  "nextCursor" end)))
      (let ((before (count "resources/list"
                           (mcp-test-messages server)
                           :key (lambda (message)
                                  (cadr-agent::mcp-get message "method"))
                           :test #'equal)))
        (is (mcp-json-equal
             (cadr-agent:mcp-list-resources client)
             (list (cadr-agent::mcp-obj "uri" "file:///a" "name" "a"))))
        (is (= (1+ before)
               (count "resources/list"
                      (mcp-test-messages server)
                      :key (lambda (message)
                             (cadr-agent::mcp-get message "method"))
                      :test #'equal)))))
    (cadr-agent:mcp-client-close client)
    (cadr-agent:mcp-transport-close (getf bound :server-transport))))

(test mcp-resource-list-rejects-a-duplicate-cursor
  (let* ((bound (mcp-test-connect))
         (client (getf bound :client)))
    (funcall (getf (getf bound :server) :set)
             "resources/list"
             (lambda (request)
               (declare (ignore request))
               (cadr-agent::mcp-obj
                "resources" (vector (cadr-agent::mcp-obj
                                     "uri" "file:///a" "name" "a"))
                "nextCursor" "2")))
    (is (string= (handler-case
                     (progn (cadr-agent:mcp-list-resources client) "")
                   (error (condition) (princ-to-string condition)))
                 "MCP resources/list returned duplicate cursor: 2"))
    (cadr-agent:mcp-client-close client)
    (cadr-agent:mcp-transport-close (getf bound :server-transport))))

(test mcp-connect-does-not-list-resources
  (let* ((bound (mcp-test-connect
                 :server-hook
                 (lambda (server)
                   (funcall (getf server :set)
                            "initialize"
                            (lambda (message)
                              (declare (ignore message))
                              (cadr-agent::mcp-obj
                               "protocolVersion"
                               cadr-agent:+mcp-latest-protocol-version+
                               "capabilities"
                               (cadr-agent::mcp-obj
                                "tools" (cadr-agent::mcp-obj)
                                "resources" (cadr-agent::mcp-obj))
                               "serverInfo"
                               (cadr-agent::mcp-obj "name" "docs"
                                                    "version" "1.0.0")))))))
         (client (getf bound :client))
         (connection (cadr-agent::make-mcp-server-connection
                      :name "docs"
                      :config (cadr-agent::mcp-obj)
                      :cwd "/tmp"
                      :state "connected"
                      :client client)))
    (cadr-agent:mcp-connection-note-resources connection client)
    (is (cadr-agent:mcp-server-has-resources connection))
    (is (null (mcp-find-method (mcp-test-messages (getf bound :server))
                               "resources/list")))
    (cadr-agent:mcp-client-close client)
    (cadr-agent:mcp-transport-close (getf bound :server-transport))))

(test mcp-absent-resource-capability-is-not-a-resource-server
  (let* ((bound (mcp-test-connect))
         (connection (cadr-agent::make-mcp-server-connection
                      :name "docs"
                      :config (cadr-agent::mcp-obj)
                      :cwd "/tmp")))
    (cadr-agent:mcp-connection-note-resources connection (getf bound :client))
    (is (null (cadr-agent:mcp-server-has-resources connection)))
    (cadr-agent:mcp-client-close (getf bound :client))
    (cadr-agent:mcp-transport-close (getf bound :server-transport))))

(test mcp-resource-tools-list-and-read-like-codex
  ;; agent-session-mcp.test.ts "lists and reads resources with Codex's resource tools"
  (let* ((bound (mcp-test-connect))
         (client (getf bound :client))
         (reads nil))
    (funcall (getf (getf bound :server) :set)
             "resources/list"
             (lambda (request)
               (declare (ignore request))
               (cadr-agent::mcp-obj
                "resources"
                (vector
                 (cadr-agent::mcp-obj
                  "uri" "docs://intro" "name" "intro"
                  "mimeType" "text/markdown"
                  "_meta" (cadr-agent::mcp-obj "x" 1))
                 (cadr-agent::mcp-obj
                  "uri" "ui://docs/viewer" "name" "viewer"
                  "mimeType" "text/html;profile=mcp-app")
                 (cadr-agent::mcp-obj
                  "uri" "docs://panel" "name" "panel"
                  "mimeType" "text/html; profile=\"mcp-app\"")))))
    (funcall (getf (getf bound :server) :set)
             "resources/templates/list"
             (lambda (request)
               (declare (ignore request))
               (cadr-agent::mcp-obj
                "resourceTemplates"
                (vector
                 (cadr-agent::mcp-obj
                  "uriTemplate" "docs://pages/{slug}" "name" "page"
                  "icons" (vector (cadr-agent::mcp-obj
                                   "src" "data:image/png;base64,AAAA")))))))
    (funcall (getf (getf bound :server) :set)
             "resources/read"
             (lambda (request)
               (let ((uri (cadr-agent::mcp-get
                           (cadr-agent::mcp-get request "params") "uri")))
                 (push (format nil "read:~A" uri) reads)
                 (cadr-agent::mcp-obj
                  "contents"
                  (vector (cadr-agent::mcp-obj
                           "uri" uri "mimeType" "text/markdown"
                           "text" (format nil "# ~A" uri)
                           "_meta" (cadr-agent::mcp-obj "hidden" t)))))))
    (let* ((tools (cadr-agent:create-mcp-resource-tools
                   :exposure "direct"
                   :servers (lambda ()
                              (list (cadr-agent:mcp-client-resource-server
                                     "docs" client)))))
           (listed (mcp-run-tool tools "list_mcp_resources" (mcp-params)))
           (templates (mcp-run-tool
                       tools "list_mcp_resource_templates"
                       (mcp-params "server" "docs")))
           (read (mcp-run-tool
                  tools "read_mcp_resource"
                  (mcp-params "server" "docs" "uri" "docs://pages/setup")))
           (reader (find "read_mcp_resource" tools
                         :key #'cadr-agent:mcp-resource-tool-name
                         :test #'string=)))
      (is (equal (mapcar #'cadr-agent:mcp-resource-tool-name tools)
                 '("list_mcp_resources"
                   "list_mcp_resource_templates"
                   "read_mcp_resource")))
      (is (eql (cadr-agent::mcp-get
                (cadr-agent:mcp-resource-tool-annotations reader)
                "readOnlyHint")
               t))
      (is (string= (cadr-agent:mcp-resource-tool-exposure reader) "direct"))
      (is (string=
           (cadr-agent:mcp-resource-tool-description reader)
           "Read a specific resource from an MCP server given the server name and resource URI."))
      (is (mcp-json-equal
           (cadr-agent::mcp-read-json (mcp-resource-text listed))
           (cadr-agent::mcp-obj
            "resources"
            (vector (cadr-agent::mcp-obj
                     "server" "docs" "uri" "docs://intro" "name" "intro"
                     "mimeType" "text/markdown")))))
      (is (mcp-json-equal
           (cadr-agent::mcp-read-json (mcp-resource-text templates))
           (cadr-agent::mcp-obj
            "server" "docs"
            "resourceTemplates"
            (vector (cadr-agent::mcp-obj
                     "server" "docs"
                     "uriTemplate" "docs://pages/{slug}"
                     "name" "page")))))
      (is (string= (mcp-resource-text read) "# docs://pages/setup"))
      (is (mcp-json-equal
           (cadr-agent:mcp-resource-call-result-structured-content read)
           (cadr-agent::mcp-obj
            "server" "docs" "uri" "docs://pages/setup"
            "contents"
            (vector (cadr-agent::mcp-obj
                     "uri" "docs://pages/setup"
                     "mimeType" "text/markdown"
                     "text" "# docs://pages/setup")))))
      (is (string= (mcp-tool-error tools "read_mcp_resource"
                                   (mcp-params "server" "nope"
                                               "uri" "docs://x"))
                   "MCP server \"nope\" has no resources. Servers with resources: docs"))
      (is (equal (reverse reads) '("read:docs://pages/setup"))))
    (cadr-agent:mcp-client-close client)
    (cadr-agent:mcp-transport-close (getf bound :server-transport))))

(test mcp-resource-tools-sort-servers-and-keep-listing-errors
  (let* ((alpha (mcp-fake-server
                 "alpha"
                 :resources (list (cadr-agent::mcp-obj
                                   "uri" "a://1" "name" "one"))))
         (beta (mcp-fake-server
                "Alpha"
                :resources (list (cadr-agent::mcp-obj
                                  "uri" "A://1" "name" "two"))
                :fail "listing failed"))
         (tools (cadr-agent:create-mcp-resource-tools
                 :exposure "codemode"
                 :servers (lambda () (list beta alpha))))
         (listed (mcp-run-tool tools "list_mcp_resources" (mcp-params))))
    (is (string= (cadr-agent:mcp-resource-tool-exposure
                  (first tools))
                 "deferred"))
    (is (equal (cadr-agent:mcp-widest-resource-exposure
                '("deferred" "hidden" "codemode" "direct"))
               "direct"))
    (is (equal (cadr-agent:mcp-widest-resource-exposure '("hidden"))
               "hidden"))
    (is (mcp-json-equal
         (cadr-agent::mcp-read-json (mcp-resource-text listed))
         (cadr-agent::mcp-obj
          "resources"
          (vector (cadr-agent::mcp-obj
                   "server" "alpha" "uri" "a://1" "name" "one"))
          "errors"
          (vector (cadr-agent::mcp-obj
                   "server" "Alpha" "error" "listing failed")))))))

(test mcp-resource-tools-reject-a-cursor-without-a-server
  (let ((tools (cadr-agent:create-mcp-resource-tools
                :servers (lambda ()
                           (list (mcp-fake-server "docs" :resources nil))))))
    (is (string= (mcp-tool-error tools "list_mcp_resources"
                                 (mcp-params "cursor" "2"))
                 "cursor can only be used when a server is specified"))
    (is (string= (mcp-tool-error tools "list_mcp_resources"
                                 (mcp-params "server" 1))
                 "server must be a string"))
    (is (string= (mcp-tool-error tools "read_mcp_resource" (mcp-params))
                 "server must be provided"))
    (is (string= (mcp-tool-error tools "read_mcp_resource"
                                 (mcp-params "server" "docs"))
                 "uri must be provided"))
    (is (string= (mcp-tool-error tools "read_mcp_resource"
                                 (mcp-params "server" "missing" "uri" "x"))
                 "MCP server \"missing\" has no resources. Servers with resources: docs"))))

(test mcp-resource-read-renders-text-images-binaries-and-empty
  (let* ((saved nil)
         (reader
           (lambda (uri abort)
             (declare (ignore abort))
             (cond
               ((string= uri "docs://many")
                (cadr-agent::mcp-obj
                 "contents"
                 (vector
                  (cadr-agent::mcp-obj "uri" "docs://a" "text" "one")
                  (cadr-agent::mcp-obj "uri" "docs://b" "text" "two"))))
               ((string= uri "docs://empty")
                (cadr-agent::mcp-obj "contents" #()))
               ((string= uri "docs://png")
                (cadr-agent::mcp-obj
                 "contents"
                 (vector (cadr-agent::mcp-obj
                          "uri" uri "mimeType" "image/png" "blob" "AAAA"))))
               ((string= uri "docs://json")
                (cadr-agent::mcp-obj
                 "contents"
                 (vector (cadr-agent::mcp-obj
                          "uri" uri "mimeType" "application/json"
                          "blob" "eyJhIjoxfQ=="))))
               ((string= uri "file:///r/report.pdf")
                (cadr-agent::mcp-obj
                 "contents"
                 (vector (cadr-agent::mcp-obj
                          "uri" uri "mimeType" "application/pdf"
                          "blob" "JVBERg=="))))
               (t
                (cadr-agent::mcp-obj
                 "contents"
                 (vector (cadr-agent::mcp-obj
                          "uri" uri "blob" "ZA==")))))))
         (server (mcp-fake-server "docs" :reader reader))
         (tools (cadr-agent:create-mcp-resource-tools
                 :servers (lambda () (list server))
                 :save-output
                 (lambda (data extension)
                   (push (list data extension) saved)
                   (format nil "/tmp/saved~A" extension))))
         (many (mcp-run-tool tools "read_mcp_resource"
                            (mcp-params "server" "docs" "uri" "docs://many")))
         (empty (mcp-run-tool tools "read_mcp_resource"
                              (mcp-params "server" "docs" "uri" "docs://empty")))
         (png (mcp-run-tool tools "read_mcp_resource"
                            (mcp-params "server" "docs" "uri" "docs://png")))
         (json (mcp-run-tool tools "read_mcp_resource"
                             (mcp-params "server" "docs" "uri" "docs://json")))
         (pdf (mcp-run-tool tools "read_mcp_resource"
                            (mcp-params "server" "docs"
                                        "uri" "file:///r/report.pdf")))
         (bin (mcp-run-tool tools "read_mcp_resource"
                            (mcp-params "server" "docs" "uri" "docs://bin"))))
    (is (equal (mapcar (lambda (block)
                         (cadr-agent::mcp-get block "text"))
                       (cadr-agent:mcp-resource-call-result-content many))
               '("docs://a:" "one" "docs://b:" "two")))
    (is (string= (mcp-resource-text empty) "Resource docs://empty is empty."))
    (is (mcp-json-equal
         (first (cadr-agent:mcp-resource-call-result-content png))
         (cadr-agent::mcp-obj "type" "image" "data" "AAAA"
                              "mimeType" "image/png")))
    (is (string= (mcp-resource-text json) "{\"a\":1}"))
    (is (string= (mcp-resource-text pdf)
                 "[Binary resource file:///r/report.pdf (application/pdf, 4B) saved to /tmp/saved.pdf]"))
    (let ((pdf-save (find ".pdf" saved :key #'second :test #'string=)))
      (is (equalp (first pdf-save) #(37 80 68 70))))
    (is (string= (mcp-resource-text bin)
                 "[Binary resource docs://bin (unknown type, 1B) saved to /tmp/saved.bin]"))))

(test mcp-resource-read-saves-a-private-temp-file
  (let* ((server (mcp-fake-server
                  "docs"
                  :reader
                  (lambda (uri abort)
                    (declare (ignore abort))
                    (cadr-agent::mcp-obj
                     "contents"
                     (vector (cadr-agent::mcp-obj
                              "uri" uri "mimeType" "application/pdf"
                              "blob" "JVBERg=="))))))
         (tools (cadr-agent:create-mcp-resource-tools
                 :servers (lambda () (list server))))
         (result (mcp-run-tool tools "read_mcp_resource"
                               (mcp-params "server" "docs"
                                           "uri" "file:///r/report.pdf")))
         (text (mcp-resource-text result)))
    (let* ((marker "saved to ")
           (start (+ (search marker text) (length marker)))
           (file (string-right-trim "]" (subseq text start))))
      (unwind-protect
           (progn
             (is (search "cadr-mcp-" file))
             (is (search ".pdf" file))
             (is (= (logand (sb-posix:stat-mode (sb-posix:stat file)) #o777)
                    #o600))
             (is (= (with-open-file (stream file :element-type '(unsigned-byte 8))
                      (file-length stream))
                    4)))
        (when (probe-file file)
          (delete-file file))))))

(test mcp-resource-templates-are-empty-when-the-method-is-missing
  (let* ((bound (mcp-test-connect))
         (client (getf bound :client))
         (connection (cadr-agent::make-mcp-server-connection
                      :name "docs"
                      :config (cadr-agent::mcp-obj "timeout" 1)
                      :cwd "/tmp"
                      :state "connected"
                      :client client))
         (tools (cadr-agent:create-mcp-resource-tools
                 :servers (lambda ()
                            (list (cadr-agent:mcp-connection-resource-server
                                   connection)))))
         (listed (mcp-run-tool tools "list_mcp_resource_templates"
                               (mcp-params))))
    (is (null (cadr-agent:mcp-server-all-resource-templates connection)))
    (is (mcp-json-equal
         (cadr-agent:mcp-server-resource-templates-page connection)
         (cadr-agent::mcp-obj "resourceTemplates" #())))
    (is (mcp-json-equal
         (cadr-agent::mcp-read-json (mcp-resource-text listed))
         (cadr-agent::mcp-obj "resourceTemplates" #())))
    (cadr-agent:mcp-client-close client)
    (cadr-agent:mcp-transport-close (getf bound :server-transport))))

(test mcp-resource-read-retries-once-after-a-transient-http-error
  (let ((calls 0))
    (is (equal (cadr-agent:mcp-call-read-only
                (lambda ()
                  (incf calls)
                  (when (= calls 1)
                    (error 'cadr-agent:mcp-http-error
                           :status 429
                           :message "too many"))
                  "ok"))
               "ok"))
    (is (= calls 2)))
  (let ((calls 0))
    (is (string= (handler-case
                     (cadr-agent:mcp-call-read-only
                      (lambda ()
                        (incf calls)
                        (error 'cadr-agent:mcp-http-error
                               :status 404
                               :message "missing")))
                   (cadr-agent:mcp-http-error (condition)
                     (cadr-agent:mcp-error-message condition)))
                 "missing"))
    (is (= calls 1))))

(test mcp-long-resource-text-is-truncated-around-the-middle
  (let* ((body (make-string 30000 :initial-element #\a))
         (saved nil)
         (server (mcp-fake-server
                  "docs"
                  :reader
                  (lambda (uri abort)
                    (declare (ignore abort))
                    (cadr-agent::mcp-obj
                     "contents"
                     (vector (cadr-agent::mcp-obj "uri" uri "text" body))))))
         (tools (cadr-agent:create-mcp-resource-tools
                 :servers (lambda () (list server))
                 :save-output
                 (lambda (data extension)
                   (setf saved (list data extension))
                   "/tmp/full.txt")))
         (result (mcp-run-tool tools "read_mcp_resource"
                               (mcp-params "server" "docs" "uri" "docs://big")))
         (text (mcp-resource-text result)))
    (is (search "Warning: truncated output (original token count: 7500)" text))
    (is (search "Total output lines: 1" text))
    (is (search "chars truncated" text))
    (is (search "[Full output: /tmp/full.txt (read it with offset/limit)]" text))
    (is (string= (first saved) body))
    (is (string= (second saved) ".txt"))
    (is (string= (cadr-agent::mcp-get
                  (cadr-agent:mcp-resource-call-result-details result)
                  "fullOutputPath")
                 "/tmp/full.txt"))))
