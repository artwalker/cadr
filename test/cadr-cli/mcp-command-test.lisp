(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

;;; Locked to pi@4a080252f packages/coding-agent/test/mcp-command.test.ts
;;; and extensions/mcp/cli.ts. Product name is cadr. The project MCP
;;; file is .pi/mcp.json, the path load-mcp-config already reads.

(defparameter +mcp-command-stdio-fixture+
  "import json, sys
for line in sys.stdin:
    message = json.loads(line)
    if 'id' not in message:
        continue
    method = message.get('method')
    if method == 'initialize':
        result = {'protocolVersion': '2025-06-18', 'capabilities': {'tools': {}},
                  'serverInfo': {'name': 'stdio-fixture', 'version': '1.0.0'}}
    elif method == 'tools/list':
        result = {'tools': [{'name': 'echo', 'inputSchema': {'type': 'object'}}]}
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

(defun mcp-command-temp-dir ()
  (let ((dir (merge-pathnames
              (format nil "cadr-mcp-command-~A-~A/"
                      (get-universal-time)
                      (random 1000000))
              (uiop:temporary-directory))))
    (ensure-directories-exist dir)
    dir))

(defun mcp-command-write (path text)
  (ensure-directories-exist path)
  (with-open-file (out path :direction :output :if-exists :supersede
                            :if-does-not-exist :create
                            :external-format :utf-8)
    (write-string text out))
  path)

(defun mcp-command-run (args servers dir)
  (when servers
    (mcp-command-write (merge-pathnames "mcp.json" dir) servers))
  (let ((output nil))
    (let ((code
            (cadr-cli::run-mcp-command
             args
             :cwd (namestring dir)
             :agent-dir (namestring dir)
             :log (lambda (line) (push line output))
             :error (lambda (line) (push line output)))))
      (values code (format nil "~{~A~^~%~}" (nreverse output))))))

(defun mcp-command-read-json (path)
  (cadr-agent::read-mcp-json-object
   (uiop:read-file-string path :external-format :utf-8)))

(test mcp-command-lists-state-tools-and-errors
  ;; mcp-command.test.ts "lists servers with their state, tools, and errors"
  (let ((dir (mcp-command-temp-dir))
        (fixture (merge-pathnames "echo-server.py"
                                  (mcp-command-temp-dir))))
    (unwind-protect
         (progn
           (mcp-command-write fixture +mcp-command-stdio-fixture+)
           (multiple-value-bind (code output)
               (mcp-command-run
                '("list")
                (format nil
                        "{\"mcpServers\":{\"fixture\":{\"command\":\"python3\",\"args\":[\"~A\"]},\"broken\":{\"command\":\"pi-test-missing-mcp-server\"},\"parked\":{\"command\":\"python3\",\"args\":[\"~A\"],\"enabled\":false},\"bad\":{\"args\":[\"no command\"]}}}"
                        (namestring fixture)
                        (namestring fixture))
                dir)
             (is (= 1 code))
             (is (search (format nil "fixture: connected, 1 tool (codemode, global)~%")
                         (format nil "~A~%" output)))
             (is (search "  tools: echo" output))
             (is (search (format nil "broken: failed (codemode, global)~%  pi-test-missing-mcp-server~%")
                         (format nil "~A~%" output)))
             (is (search "parked: disabled (codemode, global)" output))
             (is (search "config error: " output))
             (is (search "server \"bad\" needs either \"command\"" output)))
           (multiple-value-bind (code output)
               (mcp-command-run
                '("list")
                (format nil
                        "{\"mcpServers\":{\"fixture\":{\"command\":\"python3\",\"args\":[\"~A\"]}}}"
                        (namestring fixture))
                dir)
             (declare (ignore output))
             (is (= 0 code))))
      (uiop:delete-directory-tree dir :validate t)
      (when (probe-file fixture)
        (delete-file fixture)
        (ignore-errors
         (uiop:delete-directory-tree
          (uiop:pathname-directory-pathname fixture)
          :validate t))))))

(test mcp-command-prints-json-for-scripts
  (let ((dir (mcp-command-temp-dir))
        (fixture (merge-pathnames "echo-server.py" (mcp-command-temp-dir))))
    (unwind-protect
         (progn
           (mcp-command-write fixture +mcp-command-stdio-fixture+)
           (multiple-value-bind (code output)
               (mcp-command-run
                '("list" "--json")
                (format nil
                        "{\"mcpServers\":{\"fixture\":{\"command\":\"python3\",\"args\":[\"~A\"]},\"parked\":{\"command\":\"python3\",\"args\":[\"~A\"],\"enabled\":false}}}"
                        (namestring fixture)
                        (namestring fixture))
                dir)
             (is (= 0 code))
             (let* ((parsed (cadr-ai::parse-json output))
                    (servers (cadr-ai::json-get parsed "servers")))
               (is (vectorp servers))
               (is (string= "fixture"
                            (cadr-ai::json-get (aref servers 0) "name")))
               (is (string= "connected"
                            (cadr-ai::json-get (aref servers 0) "state")))
               (is (equal '("echo")
                          (coerce (cadr-ai::json-get (aref servers 0) "tools")
                                  'list)))
               (is (string= "parked"
                            (cadr-ai::json-get (aref servers 1) "name")))
               (is (string= "disabled"
                            (cadr-ai::json-get (aref servers 1) "state")))
               (is (equal '()
                          (coerce (cadr-ai::json-get (aref servers 1) "tools")
                                  'list))))))
      (uiop:delete-directory-tree dir :validate t)
      (when (probe-file fixture)
        (delete-file fixture)
        (ignore-errors
         (uiop:delete-directory-tree
          (uiop:pathname-directory-pathname fixture)
          :validate t))))))

(test mcp-command-rejects-unknown-and-non-oauth-login
  (let ((dir (mcp-command-temp-dir)))
    (unwind-protect
         (progn
           (multiple-value-bind (code output)
               (mcp-command-run
                '("login" "nope")
                "{\"mcpServers\":{\"fixture\":{\"command\":\"python3\"},\"broken\":{\"command\":\"missing\"},\"parked\":{\"command\":\"python3\",\"enabled\":false},\"bad\":{\"args\":[\"no command\"]}}}"
                dir)
             (is (= 1 code))
             (is (string= "No MCP server named \"nope\". Configured: fixture, broken, parked."
                          output)))
           (multiple-value-bind (code output)
               (mcp-command-run
                '("logout" "fixture")
                "{\"mcpServers\":{\"fixture\":{\"command\":\"python3\"}}}"
                dir)
             (is (= 1 code))
             (is (string= "MCP server \"fixture\" does not use OAuth. Only HTTP servers without an Authorization header do."
                          output)))
           (multiple-value-bind (code output)
               (mcp-command-run '("frobnicate") nil dir)
             (declare (ignore output))
             (is (= 1 code))))
      (uiop:delete-directory-tree dir :validate t))))

(test mcp-command-adds-stdio-and-passes-command-options-through
  (let ((dir (mcp-command-temp-dir)))
    (unwind-protect
         (progn
           (multiple-value-bind (code output)
               (mcp-command-run
                '("add" "--env" "A=1" "--env" "B=x=y" "files" "--"
                  "npx" "-y" "server" "--root" ".")
                nil dir)
             (is (= 0 code))
             (is (search "Added global MCP server \"files\"" output))
             (let* ((config (mcp-command-read-json
                             (merge-pathnames "mcp.json" dir)))
                    (files (cadr-agent::mcp-get
                            (cadr-agent::mcp-get config "mcpServers")
                            "files")))
               (is (string= "npx" (cadr-agent::mcp-get files "command")))
               (is (equal '("-y" "server" "--root" ".")
                          (coerce (cadr-agent::mcp-get files "args") 'list)))
               (let ((env (cadr-agent::mcp-get files "env")))
                 (is (string= "1" (cadr-agent::mcp-get env "A")))
                 (is (string= "x=y" (cadr-agent::mcp-get env "B"))))))
           (multiple-value-bind (code output)
               (mcp-command-run
                '("add" "files" "node" "server.js" "--port" "1")
                nil dir)
             (declare (ignore code))
             (is (search "Replaced global MCP server \"files\"" output))
             (let ((files (cadr-agent::mcp-get
                           (cadr-agent::mcp-get
                            (mcp-command-read-json
                             (merge-pathnames "mcp.json" dir))
                            "mcpServers")
                           "files")))
               (is (string= "node" (cadr-agent::mcp-get files "command")))
               (is (equal '("server.js" "--port" "1")
                          (coerce (cadr-agent::mcp-get files "args") 'list))))))
      (uiop:delete-directory-tree dir :validate t))))

(test mcp-command-adds-http-servers-and-keeps-other-content
  (let ((dir (mcp-command-temp-dir)))
    (unwind-protect
         (progn
           (multiple-value-bind (code output)
               (mcp-command-run
                '("add" "docs" "--url" "https://example.com/mcp"
                  "--bearer-token-env-var" "DOCS_TOKEN"
                  "--header" "X-Team=core"
                  "--exposure" "direct"
                  "--description" "Product docs")
                "{\"mcpServers\":{\"fixture\":{\"command\":\"python3\",\"args\":[\"fixture.js\"]}}}"
                dir)
             (is (= 0 code))
             (is (null (search "mcp login" output)))
             (let* ((servers (cadr-agent::mcp-get
                              (mcp-command-read-json
                               (merge-pathnames "mcp.json" dir))
                              "mcpServers"))
                    (docs (cadr-agent::mcp-get servers "docs"))
                    (headers (cadr-agent::mcp-get docs "headers")))
               (is (string= "python3"
                            (cadr-agent::mcp-get
                             (cadr-agent::mcp-get servers "fixture")
                             "command")))
               (is (string= "https://example.com/mcp"
                            (cadr-agent::mcp-get docs "url")))
               (is (string= "core" (cadr-agent::mcp-get headers "X-Team")))
               (is (string= "Bearer ${DOCS_TOKEN}"
                            (cadr-agent::mcp-get headers "Authorization")))
               (is (string= "direct" (cadr-agent::mcp-get docs "exposure")))
               (is (string= "Product docs"
                            (cadr-agent::mcp-get docs "description")))))
           (multiple-value-bind (code output)
               (mcp-command-run
                '("add" "sentry" "--url" "https://mcp.sentry.dev/mcp"
                  "--oauth-client-id" "pi"
                  "--oauth-client-name" "Claude Code")
                nil dir)
             (declare (ignore code))
             (is (search "If it requires sign-in: cadr mcp login sentry" output))
             (let ((sentry (cadr-agent::mcp-get
                            (cadr-agent::mcp-get
                             (mcp-command-read-json
                              (merge-pathnames "mcp.json" dir))
                             "mcpServers")
                            "sentry")))
               (is (string= "https://mcp.sentry.dev/mcp"
                            (cadr-agent::mcp-get sentry "url")))
               (let ((oauth (cadr-agent::mcp-get sentry "oauth")))
                 (is (string= "pi" (cadr-agent::mcp-get oauth "clientId")))
                 (is (string= "Claude Code"
                              (cadr-agent::mcp-get oauth "clientName")))))))
      (uiop:delete-directory-tree dir :validate t))))

(test mcp-command-rejects-invalid-add-without-writing
  (let ((cases
          '(("add" "x")
            ("add" "x" "--url" "https://example.com" "--" "cmd")
            ("add" "bad name" "--" "cmd")
            ("add" "x" "--url" "ftp://example.com")
            ("add" "x" "--env" "A=1" "--url" "https://example.com")
            ("add" "x" "--header" "A=1" "--" "cmd")
            ("add" "x" "--env" "NOVALUE" "--" "cmd")
            ("add" "x" "--exposure" "loud" "--" "cmd"))))
    (dolist (args cases)
      (let ((dir (mcp-command-temp-dir)))
        (unwind-protect
             (multiple-value-bind (code output)
                 (mcp-command-run args nil dir)
               (declare (ignore output))
               (is (= 1 code) "exit for ~A" args)
               (is (null (probe-file (merge-pathnames "mcp.json" dir)))
                   "wrote config for ~A" args))
          (uiop:delete-directory-tree dir :validate t))))))

(test mcp-command-adds-and-removes-project-servers
  (let ((dir (mcp-command-temp-dir)))
    (unwind-protect
         (progn
           (multiple-value-bind (code output)
               (mcp-command-run
                '("add" "-l" "local" "--" "node" "server.js")
                nil dir)
             (declare (ignore code))
             (is (search "The project is not trusted" output))
             (let ((project (merge-pathnames ".pi/mcp.json" dir)))
               (is (equal '("server.js")
                          (coerce
                           (cadr-agent::mcp-get
                            (cadr-agent::mcp-get
                             (cadr-agent::mcp-get
                              (mcp-command-read-json project)
                              "mcpServers")
                             "local")
                            "args")
                           'list)))
               (multiple-value-bind (code output)
                   (mcp-command-run '("remove" "local") nil dir)
                 (is (= 1 code))
                 (is (search (format nil "It is defined in ~A; use --local."
                                     (cadr-cli::mcp-cli-project-config
                                      (namestring dir)))
                             output)))
               (multiple-value-bind (code output)
                   (mcp-command-run '("remove" "local" "--local") nil dir)
                 (is (= 0 code))
                 (is (search "Removed project MCP server \"local\"" output))
                 (is (null (cdr (cadr-agent::mcp-get
                                 (mcp-command-read-json project)
                                 "mcpServers"))))))))
      (uiop:delete-directory-tree dir :validate t))))

(test mcp-command-removes-global-servers
  (let ((dir (mcp-command-temp-dir)))
    (unwind-protect
         (progn
           (multiple-value-bind (code output)
               (mcp-command-run
                '("remove" "broken")
                "{\"mcpServers\":{\"fixture\":{\"command\":\"python3\"},\"broken\":{\"command\":\"missing\"},\"parked\":{\"command\":\"python3\",\"enabled\":false},\"bad\":{\"args\":[\"no command\"]}}}"
                dir)
             (declare (ignore output))
             (is (= 0 code))
             (let ((names
                     (loop for (key) on
                           (cdr (cadr-agent::mcp-get
                                 (mcp-command-read-json
                                  (merge-pathnames "mcp.json" dir))
                                 "mcpServers"))
                           by #'cddr
                           collect key)))
               (is (equal '("fixture" "parked" "bad") names))))
           (multiple-value-bind (code output)
               (mcp-command-run '("remove" "broken") nil dir)
             (is (= 1 code))
             (is (search "No global MCP server named \"broken\"" output))))
      (uiop:delete-directory-tree dir :validate t))))

(test mcp-command-logout-removes-stored-oauth-credentials
  ;; oauth.ts storeKeys: mcp__<name>|<url href>, legacy key is the href.
  (let ((dir (mcp-command-temp-dir)))
    (unwind-protect
         (progn
           (mcp-command-run
            '("add" "docs" "--url" "https://example.com/mcp")
            nil dir)
           (mcp-command-write
            (merge-pathnames "mcp-auth.json" dir)
            "{\"mcp__docs|https://example.com/mcp\":{\"tokens\":{\"access_token\":\"secret\"}}}")
           (multiple-value-bind (code output)
               (mcp-command-run '("logout" "docs") nil dir)
             (is (= 0 code))
             (is (string= "Signed out of MCP server \"docs\"." output))
             (is (null (cadr-agent::mcp-get
                        (mcp-command-read-json
                         (merge-pathnames "mcp-auth.json" dir))
                        "mcp__docs|https://example.com/mcp"))))
           (multiple-value-bind (code output)
               (mcp-command-run '("logout" "docs") nil dir)
             (is (= 0 code))
             (is (string= "No stored credentials for MCP server \"docs\"." output)))
           (mcp-command-write
            (merge-pathnames "mcp-auth.json" dir)
            "{\"https://example.com/mcp\":{\"tokens\":{\"access_token\":\"legacy\"}}}")
           (multiple-value-bind (code output)
               (mcp-command-run '("logout" "docs") nil dir)
             (is (= 0 code))
             (is (search "Signed out of MCP server \"docs\"." output))
             (is (null (cadr-agent::mcp-get
                        (mcp-command-read-json
                         (merge-pathnames "mcp-auth.json" dir))
                        "https://example.com/mcp")))))
      (uiop:delete-directory-tree dir :validate t))))

(test mcp-command-login-rejects-a-non-positive-timeout
  (let ((dir (mcp-command-temp-dir)))
    (unwind-protect
         (progn
           (mcp-command-run
            '("add" "docs" "--url" "https://example.com/mcp")
            nil dir)
           (dolist (timeout '("0" "-1" "abc"))
             (multiple-value-bind (code output)
                 (mcp-command-run
                  (list "login" "docs" "--timeout" timeout)
                  nil dir)
               (is (= 1 code))
               (is (string= "--timeout must be a positive number of seconds."
                            output)))))
      (uiop:delete-directory-tree dir :validate t))))

(test mcp-command-help-lists-the-five-commands
  (let ((dir (mcp-command-temp-dir)))
    (unwind-protect
         (multiple-value-bind (code output)
             (mcp-command-run nil nil dir)
           (is (= 0 code))
           (is (search "cadr mcp list [--json]" output))
           (is (search "cadr mcp login <server> [--timeout <seconds>]" output))
           (is (search "cadr mcp logout <server>" output))
           (is (not (nth-value 0
                               (cadr-cli::maybe-run-mcp-command '("auth" "check"))))))
      (uiop:delete-directory-tree dir :validate t))))
