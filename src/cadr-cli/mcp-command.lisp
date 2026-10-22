(in-package #:cadr-cli)

;;; pi@4a080252f packages/coding-agent/src/extensions/mcp/cli.ts.
;;; `cadr mcp` edits mcp.json and reports server state outside a session.
;;; OAuth token exchange stays with the MCP OAuth client; this command
;;; deletes stored credentials and reports when a sign-in does not finish.

(defparameter +mcp-help-hint+
  "Use \"cadr mcp --help\" for usage.")

(defparameter +mcp-login-timeout-seconds+ 300)

(defparameter +mcp-option-aliases+
  '(("-l" . "--local")))

(defparameter +mcp-command-help+
  "Usage:
  cadr mcp add <server> [options] -- <command> [args...]
  cadr mcp add <server> [options] --url <url>
  cadr mcp remove <server> [-l]
  cadr mcp list [--json]
  cadr mcp login <server> [--timeout <seconds>]
  cadr mcp logout <server>

Configure and check MCP servers and sign in to OAuth servers without starting a session.
Reads ~/.cadr/agent/mcp.json and, in trusted projects, .pi/mcp.json.

Commands:
  add <server>            Add or replace a server in mcp.json
  remove <server>         Remove a server from mcp.json
  list                    Show state, tools, and errors (exits 1 on failure)
  login <server>          Sign in through the browser
  logout <server>         Delete the stored OAuth credentials

Options for add and remove:
  -l, --local             Use .pi/mcp.json in the current project instead of the global file

Options for add:
  --url <url>             Streamable HTTP server URL (instead of a command)
  --env <KEY=VALUE>       Environment variable for a stdio server (repeatable)
  --cwd <dir>             Working directory for a stdio server
  --header <KEY=VALUE>    HTTP header (repeatable)
  --bearer-token-env-var <NAME>
                          Send \"Authorization: Bearer ${NAME}\"
  --oauth-client-id <id>  Pre-registered OAuth client id
  --oauth-client-secret <secret>
                          OAuth client secret (may be ${NAME} or !command)
  --oauth-callback-port <port>
                          Fixed OAuth callback port
  --oauth-client-name <name>
                          Client name sent when registering with the OAuth server
  --exposure <mode>       codemode (default), deferred, direct, or hidden
  --description <text>    What the server offers, shown in the system prompt

Other options:
  --json                  Print the list as JSON
  --timeout <seconds>     Time limit for the whole sign-in (default: 300)")

(defstruct mcp-parsed-options
  (positional nil :type list)
  (values nil :type list)
  (lists nil :type list))

(define-condition mcp-sign-in-cancelled (error) ()
  (:report (lambda (condition stream)
             (declare (ignore condition))
             (write-string "MCP sign-in cancelled" stream))))

(define-condition mcp-sign-in-error (error)
  ((message :initarg :message :reader mcp-sign-in-error-message))
  (:report (lambda (condition stream)
             (write-string (mcp-sign-in-error-message condition) stream))))

(defun mcp-cli-project-config (cwd)
  ;; Same path load-mcp-config reads. The project file stays .pi/mcp.json.
  (cadr-agent::mcp-join (cadr-agent::mcp-join cwd ".pi") "mcp.json"))

(defun mcp-cli-global-config (agent-dir)
  (cadr-agent::mcp-join agent-dir "mcp.json"))

(defun mcp-cli-auth-path (agent-dir)
  (cadr-agent::mcp-join agent-dir "mcp-auth.json"))

(defun mcp-cli-trusted-p (agent-dir cwd)
  (eql t
       (project-trust-get
        (make-project-trust-store
         (cadr-agent::mcp-join agent-dir "trust.json"))
        cwd)))

(defun mcp-cli-option (parsed name)
  (let ((found (assoc name (mcp-parsed-options-values parsed) :test #'string=)))
    (when (and found (stringp (cdr found)))
      (cdr found))))

(defun mcp-cli-flag-p (parsed name)
  (assoc name (mcp-parsed-options-values parsed) :test #'string=))

(defun mcp-cli-option-list (parsed name)
  (cdr (assoc name (mcp-parsed-options-lists parsed) :test #'string=)))

(defun mcp-cli-append-list (lists name value)
  (let ((cell (assoc name lists :test #'string=)))
    (if cell
        (progn
          (setf (cdr cell) (append (cdr cell) (list value)))
          lists)
        (acons name (list value) lists))))

(defun mcp-parse-options (args known error
                          &optional (max-positionals most-positive-fixnum))
  ;; pi@4a080252f parseOptions. `--` or maxPositionals ends option parsing
  ;; so a server command can keep its own flags.
  (let ((positional nil)
        (values nil)
        (lists nil)
        (index 0)
        (argv (coerce args 'vector)))
    (loop while (< index (length argv))
          for raw = (aref argv index)
          for arg = (or (cdr (assoc raw +mcp-option-aliases+ :test #'string=))
                        raw)
          do (cond
               ((or (string= arg "--")
                    (>= (length positional) max-positionals))
                (setf positional
                      (nconc positional
                             (coerce (subseq argv
                                             (if (string= arg "--")
                                                 (1+ index)
                                                 index))
                                     'list)))
                (setf index (length argv)))
               ((not (uiop:string-prefix-p "--" arg))
                (setf positional (nconc positional (list arg)))
                (incf index))
               (t
                (let* ((name (subseq arg 2))
                       (kind (cdr (assoc name known :test #'string=))))
                  (unless kind
                    (funcall error
                             (format nil "Unknown option ~A.~%~A"
                                     arg +mcp-help-hint+))
                    (return-from mcp-parse-options nil))
                  (cond
                    ((eq kind :flag)
                     (setf values (acons name t values))
                     (incf index))
                    (t
                     (incf index)
                     (when (>= index (length argv))
                       (funcall error (format nil "~A needs a value." arg))
                       (return-from mcp-parse-options nil))
                     (let ((value (aref argv index)))
                       (if (eq kind :list)
                           (setf lists (mcp-cli-append-list lists name value))
                           (setf values (acons name value values)))
                       (incf index))))))))
    (make-mcp-parsed-options :positional positional
                             :values values
                             :lists lists)))

(defun mcp-cli-pairs (option pairs error)
  (let ((record (cadr-agent::mcp-obj)))
    (dolist (pair pairs record)
      (let ((separator (position #\= pair)))
        (when (or (null separator) (zerop separator))
          (funcall error
                   (format nil "--~A expects KEY=VALUE, got \"~A\"."
                           option pair))
          (return-from mcp-cli-pairs nil))
        (setf record
              (cadr-agent::mcp-put record
                                   (subseq pair 0 separator)
                                   (subseq pair (1+ separator))))))))

(defun mcp-cli-js-number (text)
  ;; Number(text) for a finite decimal. NIL is NaN.
  (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return #\Page) text))
        (index 0)
        (sign 1))
    (when (zerop (length trimmed))
      (return-from mcp-cli-js-number nil))
    (when (member (char trimmed 0) '(#\+ #\-))
      (when (char= (char trimmed 0) #\-)
        (setf sign -1))
      (incf index))
    (when (>= index (length trimmed))
      (return-from mcp-cli-js-number nil))
    (let ((saw-digit nil)
          (int 0)
          (frac 0)
          (frac-div 1)
          (saw-dot nil))
      (loop while (< index (length trimmed))
            for character = (char trimmed index)
            do (cond
                 ((digit-char-p character)
                  (setf saw-digit t)
                  (if saw-dot
                      (setf frac (+ (* frac 10) (digit-char-p character))
                            frac-div (* frac-div 10))
                      (setf int (+ (* int 10) (digit-char-p character))))
                  (incf index))
                 ((and (char= character #\.) (not saw-dot))
                  (setf saw-dot t)
                  (incf index))
                 (t (return-from mcp-cli-js-number nil))))
      (unless saw-digit
        (return-from mcp-cli-js-number nil))
      (* sign (if saw-dot
                  (float (+ int (/ frac frac-div)) 1.0d0)
                  int)))))

(defun mcp-cli-js-round (value)
  ;; Math.round for a non-negative number. CL round is round-to-even.
  (let ((truncated (truncate value)))
    (if (>= (- value truncated) 0.5d0)
        (1+ truncated)
        truncated)))

(defun mcp-cli-url-href (text)
  ;; String(new URL(text)). Default ports are omitted. An unparsable
  ;; value stays as written so the credential key still has a stable form.
  (let ((url (cadr-agent::parse-mcp-url text)))
    (unless url
      (return-from mcp-cli-url-href text))
    (let ((protocol (getf url :protocol))
          (host (string-downcase (getf url :hostname)))
          (port (getf url :port)))
      (when (or (and (string= protocol "https:") (string= port "443"))
                (and (string= protocol "http:") (string= port "80")))
        (setf port ""))
      (format nil "~A//~A~@[~A~]~A~A~A"
              protocol
              host
              (and (plusp (length port)) (format nil ":~A" port))
              (getf url :pathname)
              (getf url :search)
              (getf url :hash)))))

(defun mcp-oauth-store-keys (name url)
  ;; pi@4a080252f storeKeys. The legacy key is the URL alone.
  (let ((href (mcp-cli-url-href url)))
    (values (format nil "~A|~A" (cadr-agent:mcp-namespace name) href)
            href)))

(defun mcp-oauth-credentials-remove (path name url)
  ;; pi@4a080252f McpOAuthCredentialStore.remove. True when a current or
  ;; legacy entry was stored.
  (unless (uiop:file-exists-p path)
    (return-from mcp-oauth-credentials-remove nil))
  (let ((object
          (cadr-agent::read-mcp-json-object
           (uiop:read-file-string path :external-format :utf-8))))
    (unless (cadr-agent::mcp-object-p object)
      (return-from mcp-oauth-credentials-remove nil))
    (multiple-value-bind (key legacy) (mcp-oauth-store-keys name url)
      (let ((stored
              (cond
                ((nth-value 1 (cadr-agent::mcp-get object key)) key)
                ((nth-value 1 (cadr-agent::mcp-get object legacy)) legacy)
                (t nil))))
        (unless stored
          (return-from mcp-oauth-credentials-remove nil))
        (cadr-core:call-with-atomic-output-file
         path
         (lambda (stream)
           (write-string
            (cadr-agent::mcp-json-pretty
             (cadr-agent::mcp-delete object stored))
            stream)
           (terpri stream))
         :mode #o600)
        t))))

(defun mcp-cli-scope-name (entry)
  (string-downcase
   (symbol-name (cadr-agent:mcp-server-entry-scope entry))))

(defun mcp-cli-transport (entry)
  (let ((config (cadr-agent:mcp-server-entry-config entry)))
    (multiple-value-bind (url present) (cadr-agent::mcp-get config "url")
      (if present
          url
          (format nil "~A~{ ~A~}"
                  (cadr-agent::mcp-get config "command")
                  (cadr-agent::mcp-config-string-list
                   (cadr-agent::mcp-get config "args")))))))

(defun mcp-cli-enabled-p (config)
  (multiple-value-bind (enabled present) (cadr-agent::mcp-get config "enabled")
    (or (not present) (not (null enabled)))))

(defun mcp-cli-exposure (config)
  (or (cadr-agent::mcp-get config "exposure") "codemode"))

(defun mcp-cli-tool-names (connection)
  (loop for tool in (cadr-agent:mcp-server-tools connection)
        for name = (cadr-agent::mcp-get tool "name")
        when (stringp name)
          collect name))

(defun mcp-cli-join-lines (text)
  (let ((pieces nil)
        (start 0))
    (loop for end = (position #\Newline text :start start)
          do (push (subseq text start (or end (length text))) pieces)
             (unless end
               (return))
             (setf start (1+ end)))
    (format nil "~{  ~A~^~%~}" (nreverse pieces))))

(defun mcp-cli-credentials (agent-dir)
  (cadr-agent::make-mcp-oauth-credential-store (mcp-cli-auth-path agent-dir)))

(defun mcp-cli-probe (entry cwd &optional credentials)
  (cadr-agent:open-mcp-server
   (cadr-agent:mcp-server-entry-name entry)
   (cadr-agent:mcp-server-entry-config entry)
   cwd
   :probe t
   :credentials credentials))

(defun mcp-cli-report (entry cwd &optional credentials)
  (let* ((config (cadr-agent:mcp-server-entry-config entry))
         (enabled (mcp-cli-enabled-p config))
         (exposure (mcp-cli-exposure config))
         (report
           (list :name (cadr-agent:mcp-server-entry-name entry)
                 :scope (mcp-cli-scope-name entry)
                 :source (cadr-agent:mcp-server-entry-source entry)
                 :override (cadr-agent:mcp-server-entry-override entry)
                 :enabled enabled
                 :exposure exposure
                 :transport (mcp-cli-transport entry)
                 :state "disabled"
                 :tools nil
                 :tool-exposure nil
                 :resources nil
                 :error nil)))
    (when enabled
      (let ((connection (mcp-cli-probe entry cwd credentials)))
        (unwind-protect
             (let ((tools (mcp-cli-tool-names connection))
                   (overrides nil))
               (setf (getf report :state) (cadr-agent:mcp-server-state connection)
                     (getf report :tools) tools)
               (dolist (tool tools)
                 (let ((tool-exposure
                         (cadr-agent:mcp-tool-exposure config tool)))
                   (unless (string= tool-exposure exposure)
                     (setf overrides
                           (nconc overrides (list tool tool-exposure))))))
               (when overrides
                 (setf (getf report :tool-exposure) overrides))
               (when (cadr-agent:mcp-server-has-resources connection)
                 (setf (getf report :resources) t))
               (when (and (not (string= (getf report :state) "connected"))
                          (cadr-agent:mcp-server-error connection))
                 (setf (getf report :error)
                       (cadr-agent:mcp-server-error connection))))
          (ignore-errors (cadr-agent:mcp-server-close connection)))))
    report))

(defun mcp-cli-report-json (report)
  (let ((pairs
          (list "name" (getf report :name)
                "scope" (getf report :scope)
                "source" (getf report :source))))
    (when (getf report :override)
      (setf pairs (append pairs (list "override" (getf report :override)))))
    (setf pairs
          (append pairs
                  (list "enabled" (if (getf report :enabled) t nil)
                        "exposure" (getf report :exposure)
                        "transport" (getf report :transport)
                        "state" (getf report :state)
                        "tools" (coerce (getf report :tools) 'vector))))
    (when (getf report :tool-exposure)
      (setf pairs
            (append pairs
                    (list "toolExposure"
                          (apply #'cadr-agent::mcp-obj
                                 (getf report :tool-exposure))))))
    (when (getf report :resources)
      (setf pairs (append pairs (list "resources" t))))
    (when (getf report :error)
      (setf pairs (append pairs (list "error" (getf report :error)))))
    (apply #'cadr-agent::mcp-obj pairs)))

(defun mcp-cli-state-label (report)
  (cond
    ((string= (getf report :state) "connected")
     (let ((count (length (getf report :tools))))
       (format nil "connected, ~D tool~A"
               count
               (if (= count 1) "" "s"))))
    ((string= (getf report :state) "needs-auth")
     "needs sign-in")
    (t (getf report :state))))

(defun mcp-cli-print-report (report log)
  (funcall log
           (format nil "~A: ~A (~A, ~A)"
                   (getf report :name)
                   (mcp-cli-state-label report)
                   (getf report :exposure)
                   (getf report :scope)))
  (funcall log (format nil "  ~A" (getf report :transport)))
  (when (getf report :override)
    (funcall log (format nil "  project override: ~A" (getf report :override))))
  (when (string= (getf report :state) "needs-auth")
    (funcall log
             (format nil "  sign in with: cadr mcp login ~A"
                     (getf report :name))))
  (when (getf report :tools)
    (funcall log
             (format nil "  tools: ~{~A~^, ~}"
                     (loop for tool in (getf report :tools)
                           for exposure = (cadr-agent::mcp-get
                                           (or (apply #'cadr-agent::mcp-obj
                                                      (getf report :tool-exposure))
                                               (cadr-agent::mcp-obj))
                                           tool)
                           collect (if exposure
                                       (format nil "~A [~A]" tool exposure)
                                       tool)))))
  (when (getf report :resources)
    (funcall log "  offers resources"))
  (when (getf report :error)
    (funcall log (mcp-cli-join-lines (getf report :error)))))

(defun mcp-cli-list (loaded json-p note agent-dir cwd log)
  (let* ((credentials (mcp-cli-credentials agent-dir))
         (reports
           (mapcar (lambda (entry) (mcp-cli-report entry cwd credentials))
                   (cadr-agent:loaded-mcp-config-servers loaded)))
         (errors (cadr-agent:loaded-mcp-config-errors loaded))
         (failed
           (or errors
               (some (lambda (report)
                       (and (getf report :enabled)
                            (not (string= (getf report :state) "connected"))))
                     reports))))
    (if json-p
        (funcall log
                 (cadr-agent::mcp-json-pretty
                  (apply #'cadr-agent::mcp-obj
                         "servers"
                         (map 'vector #'mcp-cli-report-json reports)
                         "errors"
                         (coerce errors 'vector)
                         (when note (list "note" note)))))
        (progn
          (when (and (null reports) (null errors))
            (funcall log
                     (format nil
                             "No MCP servers configured. Add them to ~A or .pi/mcp.json."
                             (mcp-cli-global-config agent-dir))))
          (dolist (report reports)
            (mcp-cli-print-report report log))
          (dolist (config-error errors)
            (funcall log (format nil "config error: ~A" config-error)))
          (when note
            (funcall log note))))
    (if failed 1 0)))

(defun mcp-cli-authorization-p (headers)
  (and (cadr-agent::mcp-object-p headers)
       (loop for (key) on (cdr headers) by #'cddr
             thereis (string-equal key "authorization"))))

(defun mcp-cli-add (args project-config cwd agent-dir log error)
  (let ((usage
          (format nil
                  "Usage: cadr mcp add <server> [options] (--url <url> | -- <command> [args...])~%~A"
                  +mcp-help-hint+))
        (parsed
          (mcp-parse-options
           args
           '(("local" . :flag)
             ("url" . :value)
             ("env" . :list)
             ("cwd" . :value)
             ("header" . :list)
             ("bearer-token-env-var" . :value)
             ("oauth-client-id" . :value)
             ("oauth-client-secret" . :value)
             ("oauth-callback-port" . :value)
             ("oauth-client-name" . :value)
             ("exposure" . :value)
             ("description" . :value))
           error
           2)))
    (unless parsed
      (return-from mcp-cli-add 1))
    (let* ((positional (mcp-parsed-options-positional parsed))
           (name (first positional))
           (command (rest positional))
           (url (mcp-cli-option parsed "url")))
      (when (or (null name)
                (eq (null url) (null command)))
        (funcall error usage)
        (return-from mcp-cli-add 1))
      (let* ((http-only
               '("header" "bearer-token-env-var" "oauth-client-id"
                 "oauth-client-secret" "oauth-callback-port"
                 "oauth-client-name"))
             (stdio-only '("env" "cwd"))
             (misplaced
               (find-if (lambda (option)
                          (or (mcp-cli-flag-p parsed option)
                              (mcp-cli-option-list parsed option)
                              (mcp-cli-option parsed option)))
                        (if url stdio-only http-only))))
        (when misplaced
          (funcall error
                   (format nil "--~A only applies to ~A."
                           misplaced
                           (if url
                               "stdio servers"
                               "HTTP servers (--url)")))
          (return-from mcp-cli-add 1))
        (let ((config nil))
          (if url
              (let ((headers (mcp-cli-pairs "header"
                                            (mcp-cli-option-list parsed "header")
                                            error))
                    (bearer (mcp-cli-option parsed "bearer-token-env-var"))
                    (port-text (mcp-cli-option parsed "oauth-callback-port"))
                    (oauth (cadr-agent::mcp-obj)))
                (unless headers
                  (return-from mcp-cli-add 1))
                (when bearer
                  (setf headers
                        (cadr-agent::mcp-put headers
                                             "Authorization"
                                             (format nil "Bearer ${~A}" bearer))))
                (when (mcp-cli-option parsed "oauth-client-id")
                  (setf oauth
                        (cadr-agent::mcp-put oauth "clientId"
                                             (mcp-cli-option parsed "oauth-client-id"))))
                (when (mcp-cli-option parsed "oauth-client-secret")
                  (setf oauth
                        (cadr-agent::mcp-put oauth "clientSecret"
                                             (mcp-cli-option parsed "oauth-client-secret"))))
                (when port-text
                  (let ((port (mcp-cli-js-number port-text)))
                    (setf oauth
                          (cadr-agent::mcp-put oauth "callbackPort"
                                               (or port port-text)))))
                (when (mcp-cli-option parsed "oauth-client-name")
                  (setf oauth
                        (cadr-agent::mcp-put oauth "clientName"
                                             (mcp-cli-option parsed "oauth-client-name"))))
                (setf config
                      (apply #'cadr-agent::mcp-obj
                             "url" url
                             (append
                              (when (cdr headers) (list "headers" headers))
                              (when (cdr oauth) (list "oauth" oauth))))))
              (let ((env (mcp-cli-pairs "env" (mcp-cli-option-list parsed "env") error)))
                (unless env
                  (return-from mcp-cli-add 1))
                (setf config
                      (apply #'cadr-agent::mcp-obj
                             "command" (first command)
                             (append
                              (when (rest command)
                                (list "args" (coerce (rest command) 'vector)))
                              (when (cdr env) (list "env" env))
                              (when (mcp-cli-option parsed "cwd")
                                (list "cwd" (mcp-cli-option parsed "cwd"))))))))
          (when (mcp-cli-option parsed "exposure")
            (setf config
                  (cadr-agent::mcp-put config "exposure"
                                       (mcp-cli-option parsed "exposure"))))
          (when (mcp-cli-option parsed "description")
            (setf config
                  (cadr-agent::mcp-put config "description"
                                       (mcp-cli-option parsed "description"))))
          (let ((validated (cadr-agent:validate-mcp-server-config name config)))
            (when (stringp validated)
              (funcall error validated)
              (return-from mcp-cli-add 1))
            (let* ((project (mcp-cli-flag-p parsed "local"))
                   (path (if project
                             project-config
                             (mcp-cli-global-config agent-dir)))
                   (scope (if project "project" "global"))
                   (replaced
                     (handler-case
                         (cadr-agent:add-mcp-server-config path name validated)
                       (error (condition)
                         (funcall error
                                  (format nil "Could not update ~A: ~A"
                                          path condition))
                         (return-from mcp-cli-add 1)))))
              (funcall log
                       (format nil "~A ~A MCP server ~S in ~A."
                               (if replaced "Replaced" "Added")
                               scope name path))
              (when (and project (not (mcp-cli-trusted-p agent-dir cwd)))
                (funcall log
                         (format nil
                                 "The project is not trusted, so ~A is ignored until you start cadr in the project and trust it."
                                 path)))
              (let ((sign-in
                      (and (nth-value 1 (cadr-agent::mcp-get validated "url"))
                           (not (mcp-cli-authorization-p
                                 (cadr-agent::mcp-get validated "headers"))))))
                (funcall log
                         (format nil "Check it with: cadr mcp list~A"
                                 (if sign-in
                                     (format nil
                                             ". If it requires sign-in: cadr mcp login ~A"
                                             name)
                                     ""))))
              0)))))))

(defun mcp-cli-remove (args project-config cwd agent-dir log error)
  (let ((parsed (mcp-parse-options args '(("local" . :flag)) error)))
    (unless parsed
      (return-from mcp-cli-remove 1))
    (let ((name (first (mcp-parsed-options-positional parsed)))
          (extra (rest (mcp-parsed-options-positional parsed))))
      (when (or (null name) extra)
        (funcall error
                 (format nil "Usage: cadr mcp remove <server> [-l]~%~A"
                         +mcp-help-hint+))
        (return-from mcp-cli-remove 1))
      (let* ((project (mcp-cli-flag-p parsed "local"))
             (path (if project
                       project-config
                       (mcp-cli-global-config agent-dir)))
             (scope (if project "project" "global"))
             (removed
               (handler-case
                   (cadr-agent:remove-mcp-server-config path name)
                 (error (condition)
                   (funcall error
                            (format nil "Could not update ~A: ~A" path condition))
                   (return-from mcp-cli-remove 1)))))
        (when removed
          (funcall log
                   (format nil "Removed ~A MCP server ~S from ~A."
                           scope name path))
          (return-from mcp-cli-remove 0))
        (let ((other
                (find-if
                 (lambda (server)
                   (and (string= (cadr-agent:mcp-server-entry-name server) name)
                        (not (string= (mcp-cli-scope-name server) scope))))
                 (cadr-agent:loaded-mcp-config-servers
                  (cadr-agent:load-mcp-config agent-dir cwd :project-trusted t)))))
          (funcall error
                   (format nil "No ~A MCP server named ~S in ~A.~@[ It is defined in ~A; ~A.~]"
                           scope name path
                           (and other
                                (cadr-agent:mcp-server-entry-source other))
                           (and other
                                (if (string= (mcp-cli-scope-name other) "project")
                                    "use --local"
                                    "omit --local"))))
          1)))))

(defun mcp-cli-wait-for-redirect (signal interactive)
  ;; pi@4a080252f waitForRedirectUrl. A non-TTY sign-in finishes only
  ;; through the browser callback. Abort resolves to an empty result.
  (if (not interactive)
      (progn
        (loop until (funcall signal) do (sleep 0.05))
        nil)
      (handler-case
          (progn
            (format *error-output*
                    "If the browser cannot reach this machine, paste the URL it was redirected to: ")
            (finish-output *error-output*)
            (loop until (or (funcall signal) (listen *standard-input*))
                  do (sleep 0.05))
            (when (funcall signal)
              (return-from mcp-cli-wait-for-redirect nil))
            (read-line *standard-input* nil nil))
        (error () nil))))

(defun mcp-cli-sign-in (&key name server-url store settings challenge prompt timeout-ms
                          open-url interactive)
  (let* ((deadline (+ (get-internal-real-time)
                      (round (* (/ (or timeout-ms 300000) 1000.0)
                                internal-time-units-per-second))))
         (signal (lambda ()
                   (>= (get-internal-real-time) deadline)))
         (interactive (if interactive
                          t
                          (and (interactive-stream-p *standard-input*)
                               (null open-url)))))
    (handler-case
        (cadr-agent::mcp-oauth-sign-in
         server-url store settings
         :challenge challenge
         :timeout-ms timeout-ms
         :signal signal
         :show-url (lambda (url)
                     (funcall prompt
                              (format nil "Sign in to MCP server ~S in your browser:~%~A"
                                      name url))
                     (funcall (or open-url #'open-tui-url) url))
         :paste (lambda (aborted-p)
                  (mcp-cli-wait-for-redirect
                   (lambda () (or (funcall aborted-p) (funcall signal)))
                   interactive)))
      (cadr-agent::mcp-oauth-sign-in-cancelled ()
        (error 'mcp-sign-in-cancelled)))))

(defun mcp-cli-login (entry connection url timeout-ms log error &key credentials open-url)
  (let ((name (cadr-agent:mcp-server-entry-name entry)))
    (unwind-protect
         (progn
           (let ((probed (mcp-cli-probe entry
                                        (cadr-agent::mcp-server-connection-cwd
                                         connection)
                                        credentials)))
             (setf connection probed))
           (cond
             ((string= (cadr-agent:mcp-server-state connection) "connected")
              (funcall log
                       (format nil "Already signed in to MCP server ~S (~D tools)."
                               name
                               (length (cadr-agent:mcp-server-tools connection))))
              0)
             ((not (string= (cadr-agent:mcp-server-state connection) "needs-auth"))
              (funcall error
                       (format nil "MCP server ~S failed to connect: ~A"
                               name
                               (or (cadr-agent:mcp-server-error connection)
                                   "unknown error")))
              1)
             (t
              (handler-case
                  (mcp-cli-sign-in
                   :name name
                   :server-url url
                   :store (cadr-agent::mcp-oauth-credential-server
                           credentials name url)
                   :settings (cadr-agent::mcp-oauth-settings-from-config
                              (cadr-agent:mcp-server-entry-config entry)
                              name)
                   :challenge (cadr-agent::mcp-server-connection-challenge
                               connection)
                   :prompt log
                   :timeout-ms timeout-ms
                   :open-url open-url)
                (mcp-sign-in-cancelled ()
                  (funcall error
                           (format nil
                                   "Sign-in to MCP server ~S was cancelled or not completed within ~D seconds."
                                   name
                                   (mcp-cli-js-round (/ timeout-ms 1000.0d0))))
                  (return-from mcp-cli-login 1))
                (error (condition)
                  (funcall error
                           (format nil "Sign-in to MCP server ~S failed: ~A"
                                   name condition))
                  (return-from mcp-cli-login 1)))
              (setf (cadr-agent::mcp-server-connection-challenge connection) nil)
              (handler-case
                  (progn
                    (cadr-agent::mcp-connection-connect-once connection nil)
                    (funcall log
                             (format nil "Signed in to MCP server ~S (~D tools)."
                                     name
                                     (length (cadr-agent:mcp-server-tools connection))))
                    0)
                (error (condition)
                  (funcall error (format nil "Signed in, but ~A" condition))
                  1)))))
      (when connection
        (ignore-errors (cadr-agent:mcp-server-close connection))))))

(defun mcp-cli-configured-names (loaded)
  (let ((names (mapcar #'cadr-agent:mcp-server-entry-name
                       (cadr-agent:loaded-mcp-config-servers loaded))))
    (if names
        (format nil "~{~A~^, ~}" names)
        "none")))

(defun mcp-cli-find-server (loaded name)
  (find name (cadr-agent:loaded-mcp-config-servers loaded)
        :key #'cadr-agent:mcp-server-entry-name
        :test #'string=))

(defun run-mcp-command (args &key cwd agent-dir log error open-url)
  ;; pi@4a080252f runMcpCommand. Returns the process exit code.
  (let* ((cwd (namestring (or cwd (uiop:getcwd))))
         (agent-dir (namestring (or agent-dir (cadr-core:coding-agent-directory))))
         (log (or log
                  (lambda (line)
                    (format *standard-output* "~A~%" line)
                    (finish-output *standard-output*))))
         (error (or error
                    (lambda (line)
                      (format *error-output* "~A~%" line)
                      (finish-output *error-output*))))
         (command (first args))
         (rest (rest args)))
    (when (or (null command)
              (string= command "help")
              (member "--help" args :test #'string=)
              (member "-h" args :test #'string=))
      (funcall log +mcp-command-help+)
      (return-from run-mcp-command 0))
    (let ((project-config (mcp-cli-project-config cwd)))
      (cond
        ((or (string= command "add") (string= command "remove"))
         (if (string= command "add")
             (mcp-cli-add rest project-config cwd agent-dir log error)
             (mcp-cli-remove rest project-config cwd agent-dir log error)))
        (t
         (let* ((trusted (mcp-cli-trusted-p agent-dir cwd))
                (loaded (cadr-agent:load-mcp-config agent-dir cwd
                                                    :project-trusted trusted))
                (note
                  (when (and (not trusted)
                             (uiop:file-exists-p project-config))
                    (format nil
                            "~A is ignored because the project is not trusted. Start cadr in the project to trust it."
                            project-config))))
           (cond
             ((string= command "list")
              (let ((parsed (mcp-parse-options rest '(("json" . :flag)) error)))
                (unless parsed
                  (return-from run-mcp-command 1))
                (when (mcp-parsed-options-positional parsed)
                  (funcall error
                           (format nil "Usage: cadr mcp list [--json]~%~A"
                                   +mcp-help-hint+))
                  (return-from run-mcp-command 1))
                (mcp-cli-list loaded
                              (mcp-cli-flag-p parsed "json")
                              note agent-dir cwd log)))
             ((or (string= command "login") (string= command "logout"))
              (let ((parsed
                      (mcp-parse-options
                       rest
                       (if (string= command "login")
                           '(("timeout" . :value))
                           nil)
                       error)))
                (unless parsed
                  (return-from run-mcp-command 1))
                (let ((name (first (mcp-parsed-options-positional parsed)))
                      (extra (rest (mcp-parsed-options-positional parsed))))
                  (when (or (null name) extra)
                    (funcall error
                             (format nil "Usage: cadr mcp ~A <server>~%~A"
                                     command +mcp-help-hint+))
                    (return-from run-mcp-command 1))
                  (let ((entry (mcp-cli-find-server loaded name)))
                    (unless entry
                      (funcall error
                               (format nil
                                       "No MCP server named ~S.~@[ ~A~] Configured: ~A."
                                       name note
                                       (mcp-cli-configured-names loaded)))
                      (return-from run-mcp-command 1))
                    (let ((url (when (cadr-agent::mcp-uses-oauth-p
                                      (cadr-agent:mcp-server-entry-config entry))
                                 (cadr-agent::mcp-get
                                  (cadr-agent:mcp-server-entry-config entry)
                                  "url"))))
                      (unless url
                        (funcall error
                                 (format nil
                                         "MCP server ~S does not use OAuth. Only HTTP servers without an Authorization header do."
                                         name))
                        (return-from run-mcp-command 1))
                      (when (string= command "logout")
                        (let ((removed
                                (mcp-oauth-credentials-remove
                                 (mcp-cli-auth-path agent-dir)
                                 name url)))
                          (funcall log
                                   (format nil
                                           "~A MCP server ~S."
                                           (if removed
                                               "Signed out of"
                                               "No stored credentials for")
                                           name))
                          (return-from run-mcp-command 0)))
                      (let ((timeout
                              (mcp-cli-js-number
                               (or (mcp-cli-option parsed "timeout")
                                   (princ-to-string +mcp-login-timeout-seconds+)))))
                        (unless (and timeout (realp timeout) (plusp timeout))
                          (funcall error
                                   "--timeout must be a positive number of seconds.")
                          (return-from run-mcp-command 1))
                        (let ((connection
                                (cadr-agent::make-mcp-server-connection
                                 :name name
                                 :config (cadr-agent:mcp-server-entry-config entry)
                                 :cwd cwd
                                 :state "connecting")))
                          (mcp-cli-login entry connection url
                                         (* timeout 1000) log error
                                         :credentials (mcp-cli-credentials agent-dir)
                                         :open-url open-url))))))))
             (t
              (funcall error
                       (format nil "Unknown mcp command ~S.~%~A"
                               command +mcp-help-hint+))
              1))))))))

(defun maybe-run-mcp-command (argv &key cwd agent-dir)
  ;; pi@4a080252f main.ts: the first argument `mcp` never starts a session.
  (unless (and argv (string= (first argv) "mcp"))
    (return-from maybe-run-mcp-command (values nil nil)))
  (values t
          (run-mcp-command (rest argv)
                           :cwd (or cwd (namestring (uiop:getcwd)))
                           :agent-dir (or agent-dir
                                          (namestring
                                           (cadr-core:coding-agent-directory))))))
