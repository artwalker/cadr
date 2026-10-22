(in-package #:cadr-agent)

;;; pi@4a080252f core/mcp-servers.ts and extensions/mcp/config.ts.
;;; Validates mcp.json entries and merges a trusted project's overrides.
;;; Codemode execution stays out; `autoEnableCodemode` is only stored.

(defparameter +mcp-exposures+ '("codemode" "deferred" "direct" "hidden"))

(defparameter +mcp-exposure-aliases+ '(("codemode-deferred" . "codemode")))

(defparameter +mcp-override-keys+ '("enabled" "exposure" "toolExposure"))

(defparameter +mcp-loopback-hosts+ '("localhost" "127.0.0.1" "[::1]"))

(defstruct mcp-server-entry
  (name "" :type string)
  config
  (source "" :type string)
  (scope :global :type keyword)
  override)

(defstruct loaded-mcp-config
  (servers nil :type list)
  auto-enable-codemode
  (auto-enable-codemode-p nil :type boolean)
  (errors nil :type list)
  project-config)

(defstruct mcp-config-state
  (servers nil :type list)
  auto-enable-codemode
  (auto-enable-codemode-p nil :type boolean)
  (errors nil :type list))

(defun mcp-object-p (value)
  (cadr-ai::json-object-pairs-p value))

(defun mcp-get (object key)
  (unless (mcp-object-p object)
    (return-from mcp-get (values nil nil)))
  (loop for (pair-key pair-value) on (cdr object) by #'cddr
        when (and (stringp pair-key) (string= pair-key key))
          return (values pair-value t)
        finally (return (values nil nil))))

(defun mcp-put (object key value)
  (let ((pairs nil)
        (found nil))
    (loop for (pair-key pair-value) on (cdr object) by #'cddr
          do (if (and (stringp pair-key) (string= pair-key key))
                 (setf found t
                       pairs (nconc pairs (list key value)))
                 (setf pairs (nconc pairs (list pair-key pair-value)))))
    (unless found
      (setf pairs (nconc pairs (list key value))))
    (list* :json-object pairs)))

(defun mcp-delete (object key)
  (list* :json-object
         (loop for (pair-key pair-value) on (cdr object) by #'cddr
               unless (and (stringp pair-key) (string= pair-key key))
                 nconc (list pair-key pair-value))))

(defun mcp-key-name (key)
  (cond
    ((stringp key) key)
    ((symbolp key)
     (let ((parts
             (loop for start = 0 then (1+ split)
                   for split = (position #\- (string-downcase (symbol-name key))
                                         :start start)
                   collect (subseq (string-downcase (symbol-name key))
                                   start split)
                   while split)))
       (format nil "~A~{~:(~A~)~}" (or (first parts) "") (rest parts))))
    (t (princ-to-string key))))

(defun mcp-normalize (value)
  (cond
    ((mcp-object-p value)
     (list* :json-object
            (loop for (key item) on (cdr value) by #'cddr
                  nconc (list key (mcp-normalize item)))))
    ((hash-table-p value)
     (list* :json-object
            (loop for key being the hash-keys of value
                  using (hash-value item)
                  nconc (list key (mcp-normalize item)))))
    ((and (consp value) (keywordp (car value)))
     (list* :json-object
            (loop for (key item) on value by #'cddr
                  nconc (list (mcp-key-name key) (mcp-normalize item)))))
    ((and value
          (typep value 'sequence)
          (not (stringp value)))
     (map 'vector #'mcp-normalize value))
    (t value)))

(defun mcp-server-name-p (name)
  (and (stringp name)
       (plusp (length name))
       (every (lambda (character)
                (or (char<= #\A character #\Z)
                    (char<= #\a character #\z)
                    (digit-char-p character)
                    (char= character #\_)
                    (char= character #\-)))
              name)))

(defun mcp-namespace (server)
  (format nil "mcp__~A" (substitute #\_ #\- server)))

(defun mcp-wildcard-match-p (pattern text)
  (let ((star (position #\* pattern)))
    (if (null star)
        (string= pattern text)
        (and (uiop:string-prefix-p (subseq pattern 0 star) text)
             (let ((rest (subseq pattern (1+ star)))
                   (from (length (subseq pattern 0 star))))
               (if (zerop (length rest))
                   t
                   (loop for index from from to (length text)
                         thereis
                         (mcp-wildcard-match-p
                          rest (subseq text index)))))))))

(defun mcp-exposure-name (value)
  (cond
    ((stringp value) value)
    ((symbolp value) (string-downcase (symbol-name value)))
    (t nil)))

(defun mcp-resolve-alias (value)
  (let ((name (mcp-exposure-name value)))
    (or (cdr (assoc name +mcp-exposure-aliases+ :test #'string=))
        value)))

(defun mcp-resolve-exposure-aliases (object)
  (let ((resolved (list* :json-object (copy-list (cdr object)))))
    (multiple-value-bind (exposure present)
        (mcp-get resolved "exposure")
      (when present
        (setf resolved
              (mcp-put resolved "exposure" (mcp-resolve-alias exposure)))))
    (multiple-value-bind (tools present)
        (mcp-get resolved "toolExposure")
      (when (and present (mcp-object-p tools))
        (setf resolved
              (mcp-put
               resolved
               "toolExposure"
               (list* :json-object
                      (loop for (tool exposure) on (cdr tools) by #'cddr
                            nconc (list tool (mcp-resolve-alias exposure))))))))
    resolved))

(defun mcp-exposure-p (value)
  (member (mcp-exposure-name value) +mcp-exposures+ :test #'string=))

(defun mcp-exposure-list ()
  (format nil "~{\"~A\"~^, ~}" +mcp-exposures+))

(defun mcp-string-record-p (value)
  (and (mcp-object-p value)
       (loop for (key item) on (cdr value) by #'cddr
             always (and (stringp key) (stringp item)))))

(defun mcp-boolean-p (value present)
  (and present (or (eq value t) (null value))))

(defun parse-mcp-url (text)
  (unless (stringp text)
    (return-from parse-mcp-url nil))
  (let ((scheme-end (search "://" text)))
    (unless scheme-end
      (return-from parse-mcp-url nil))
    (let ((protocol (concatenate 'string (subseq text 0 scheme-end) ":"))
          (rest (subseq text (+ scheme-end 3)))
          (hostname "")
          (port "")
          (path-start 0))
      (cond
        ((and (plusp (length rest)) (char= (char rest 0) #\[))
         (let ((close (position #\] rest)))
           (unless close
             (return-from parse-mcp-url nil))
           (setf hostname (subseq rest 0 (1+ close))
                 path-start (1+ close))
           (when (and (< path-start (length rest))
                      (char= (char rest path-start) #\:))
             (let ((port-end
                     (or (position-if
                          (lambda (character)
                            (member character '(#\/ #\? #\#)))
                          rest :start (1+ path-start))
                         (length rest))))
               (setf port (subseq rest (1+ path-start) port-end)
                     path-start port-end)))))
        (t
         (let ((host-end
                 (or (position-if
                      (lambda (character)
                        (member character '(#\/ #\? #\#)))
                      rest)
                     (length rest))))
           (let ((colon (position #\: rest :end host-end)))
             (if colon
                 (setf hostname (subseq rest 0 colon)
                       port (subseq rest (1+ colon) host-end))
                 (setf hostname (subseq rest 0 host-end))))
           (setf path-start host-end))))
      (let* ((tail (subseq rest path-start))
             (hash (position #\# tail))
             (query (position #\? tail))
             (path-end
               (or (and query hash (min query hash))
                   query hash (length tail))))
        (list :protocol protocol
              :hostname hostname
              :port port
              :pathname (let ((path (subseq tail 0 path-end)))
                          (if (string= path "") "/" path))
              :search (if (and query (or (null hash) (< query hash)))
                          (subseq tail query (or hash (length tail)))
                          "")
              :hash (if hash (subseq tail hash) ""))))))

(defun mcp-url-part (url key)
  (getf url key))

(defun mcp-loopback-p (hostname)
  (member hostname +mcp-loopback-hosts+ :test #'string=))

(defun mcp-loopback-redirect-p (value)
  (let ((url (parse-mcp-url value)))
    (and url
         (string= (mcp-url-part url :protocol) "http:")
         (mcp-loopback-p (mcp-url-part url :hostname))
         (string= (mcp-url-part url :search) "")
         (string= (mcp-url-part url :hash) ""))))

(defun mcp-https-or-loopback-p (url)
  (or (string= (mcp-url-part url :protocol) "https:")
      (and (string= (mcp-url-part url :protocol) "http:")
           (mcp-loopback-p (mcp-url-part url :hostname)))))

(defun validate-mcp-oauth (value)
  (unless value
    (return-from validate-mcp-oauth nil))
  (unless (mcp-object-p value)
    (return-from validate-mcp-oauth "oauth must be an object"))
  (multiple-value-bind (client-id present)
      (mcp-get value "clientId")
    (when (and present (not (stringp client-id)))
      (return-from validate-mcp-oauth "oauth.clientId must be a string")))
  (multiple-value-bind (secret present)
      (mcp-get value "clientSecret")
    (when (and present (not (stringp secret)))
      (return-from validate-mcp-oauth "oauth.clientSecret must be a string")))
  (multiple-value-bind (port present)
      (mcp-get value "callbackPort")
    (when (and present
               (not (and (integerp port) (<= 1 port 65535))))
      (return-from validate-mcp-oauth "oauth.callbackPort must be a port number")))
  (multiple-value-bind (callback present)
      (mcp-get value "callbackUrl")
    (when present
      (unless (and (stringp callback) (mcp-loopback-redirect-p callback))
        (return-from validate-mcp-oauth
          "oauth.callbackUrl must be an http URI on localhost, 127.0.0.1, or [::1] without query or fragment"))
      (let ((url-port (mcp-url-part (parse-mcp-url callback) :port)))
        (multiple-value-bind (port port-present)
            (mcp-get value "callbackPort")
          (when (and (plusp (length url-port))
                     port-present
                     (not (equal port (ignore-errors (parse-integer url-port)))))
            (return-from validate-mcp-oauth
              "oauth.callbackUrl and oauth.callbackPort name different ports"))))))
  (multiple-value-bind (scope present)
      (mcp-get value "scope")
    (when (and present (not (stringp scope)))
      (return-from validate-mcp-oauth "oauth.scope must be a string")))
  (multiple-value-bind (client-name present)
      (mcp-get value "clientName")
    (when present
      (unless (and (stringp client-name)
                   (plusp (length (string-trim
                                   '(#\Space #\Tab #\Newline #\Return)
                                   client-name))))
        (return-from validate-mcp-oauth
          "oauth.clientName must be a non-empty string"))))
  (multiple-value-bind (registration present)
      (mcp-get value "clientRegistration")
    (when present
      (unless (or (string= registration "dcr") (string= registration "cimd"))
        (return-from validate-mcp-oauth
          "oauth.clientRegistration must be \"dcr\" or \"cimd\""))
      (when (string= registration "cimd")
        (multiple-value-bind (client-id id-present)
            (mcp-get value "clientId")
          (declare (ignore client-id))
          (multiple-value-bind (client-name name-present)
              (mcp-get value "clientName")
            (declare (ignore client-name))
            (when (or id-present name-present)
              (return-from validate-mcp-oauth
                "oauth.clientRegistration \"cimd\" cannot be combined with oauth.clientId or oauth.clientName"))))
        (multiple-value-bind (callback callback-present)
            (mcp-get value "callbackUrl")
          (when (and callback-present (stringp callback))
            (let ((url (parse-mcp-url callback)))
              (when (or (string= (mcp-url-part url :hostname) "[::1]")
                        (not (string= (mcp-url-part url :pathname) "/callback")))
                (return-from validate-mcp-oauth
                  "oauth.clientRegistration \"cimd\" requires oauth.callbackUrl on localhost or 127.0.0.1 with path /callback"))))))))
  (multiple-value-bind (metadata present)
      (mcp-get value "authServerMetadataUrl")
    (when present
      (let ((url (and (stringp metadata) (parse-mcp-url metadata))))
        (unless (and url (mcp-https-or-loopback-p url))
          (return-from validate-mcp-oauth
            "oauth.authServerMetadataUrl must be an https URL, or http on localhost, 127.0.0.1, or [::1]")))))
  nil)

(defun validate-mcp-server-config (name raw)
  (unless (mcp-server-name-p name)
    (return-from validate-mcp-server-config
      (format nil
              "invalid server name ~S (use letters, digits, \"_\" and \"-\")"
              name)))
  (let ((value (mcp-normalize raw)))
    (unless (mcp-object-p value)
      (return-from validate-mcp-server-config
        (format nil "server ~S must be an object" name)))
    (setf value (mcp-resolve-exposure-aliases value))
    (multiple-value-bind (type type-p) (mcp-get value "type")
      (declare (ignore type-p))
      (multiple-value-bind (exposure exposure-p) (mcp-get value "exposure")
        (when (and exposure-p (not (mcp-exposure-p exposure)))
          (return-from validate-mcp-server-config
            (format nil "server ~S: exposure must be one of ~A"
                    name (mcp-exposure-list)))))
      (multiple-value-bind (tools tools-p) (mcp-get value "toolExposure")
        (when tools-p
          (unless (mcp-object-p tools)
            (return-from validate-mcp-server-config
              (format nil
                      "server ~S: toolExposure must map tool names to exposures"
                      name)))
          (loop for (tool exposure) on (cdr tools) by #'cddr
                unless (mcp-exposure-p exposure)
                  do (return-from validate-mcp-server-config
                       (format nil
                               "server ~S: toolExposure ~S must be one of ~A"
                               name tool (mcp-exposure-list))))))
      (multiple-value-bind (enabled present) (mcp-get value "enabled")
        (when (and present (not (mcp-boolean-p enabled present)))
          (return-from validate-mcp-server-config
            (format nil "server ~S: enabled must be a boolean" name))))
      (multiple-value-bind (description present) (mcp-get value "description")
        (when (and present (not (stringp description)))
          (return-from validate-mcp-server-config
            (format nil "server ~S: description must be a string" name))))
      (multiple-value-bind (timeout present) (mcp-get value "timeout")
        (when (and present
                   (not (and (realp timeout)
                             (not (complexp timeout))
                             (> timeout 0))))
          (return-from validate-mcp-server-config
            (format nil
                    "server ~S: timeout must be a positive number of seconds"
                    name))))
      (when (and type (stringp type) (string= type "sse"))
        (return-from validate-mcp-server-config
          (format nil
                  "server ~S: legacy SSE transport is not supported; use the streamable HTTP URL"
                  name)))
      (multiple-value-bind (url url-present) (mcp-get value "url")
        (declare (ignore url-present))
        (when (and (stringp url)
                   (or (null type)
                       (and (stringp type)
                            (or (string= type "http")
                                (string= type "streamable-http")))))
          (let ((parsed (parse-mcp-url url)))
            (unless (and parsed
                         (or (string= (mcp-url-part parsed :protocol) "http:")
                             (string= (mcp-url-part parsed :protocol) "https:")))
              (return-from validate-mcp-server-config
                (format nil "server ~S: url must be an http or https URL" name))))
          (multiple-value-bind (headers present) (mcp-get value "headers")
            (when (and present (not (mcp-string-record-p headers)))
              (return-from validate-mcp-server-config
                (format nil "server ~S: headers must map names to strings" name))))
          (multiple-value-bind (oauth present) (mcp-get value "oauth")
            (when present
              (let ((oauth-error (validate-mcp-oauth oauth)))
                (when oauth-error
                  (return-from validate-mcp-server-config
                    (format nil "server ~S: ~A" name oauth-error))))))
          (multiple-value-bind (auth present) (mcp-get value "auth")
            (when present
              (multiple-value-bind (provider provider-p)
                  (and (mcp-object-p auth) (mcp-get auth "provider"))
                (unless (and provider-p (stringp provider) (plusp (length provider)))
                  (return-from validate-mcp-server-config
                    (format nil "server ~S: auth.provider must be a provider name" name))))
              (let ((parsed (parse-mcp-url url)))
                (unless (mcp-https-or-loopback-p parsed)
                  (return-from validate-mcp-server-config
                    (format nil
                            "server ~S: auth requires an https URL, or http on localhost, 127.0.0.1, or [::1]"
                            name))))))
          (return-from validate-mcp-server-config value)))
      (multiple-value-bind (command command-present) (mcp-get value "command")
        (declare (ignore command-present))
        (when (and (stringp command)
                   (or (null type) (and (stringp type) (string= type "stdio"))))
          (multiple-value-bind (args present) (mcp-get value "args")
            (when (and present
                       (not (and (typep args 'sequence)
                                 (not (stringp args))
                                 (every #'stringp args))))
              (return-from validate-mcp-server-config
                (format nil "server ~S: args must be an array of strings" name))))
          (multiple-value-bind (env present) (mcp-get value "env")
            (when (and present (not (mcp-string-record-p env)))
              (return-from validate-mcp-server-config
                (format nil "server ~S: env must map names to strings" name))))
          (multiple-value-bind (cwd present) (mcp-get value "cwd")
            (when (and present (not (stringp cwd)))
              (return-from validate-mcp-server-config
                (format nil "server ~S: cwd must be a string" name))))
          (return-from validate-mcp-server-config value))))
    (format nil
            "server ~S needs either \"command\" (stdio) or \"url\" (streamable HTTP)"
            name)))

(defun mcp-tool-exposure (config tool-name)
  (let ((config (mcp-normalize config)))
    (multiple-value-bind (overrides present) (mcp-get config "toolExposure")
      (when (and present (mcp-object-p overrides))
        (multiple-value-bind (exact exact-p) (mcp-get overrides tool-name)
          (when exact-p
            (return-from mcp-tool-exposure
              (mcp-exposure-name (mcp-resolve-alias exact)))))
        (loop for (pattern exposure) on (cdr overrides) by #'cddr
              when (and (stringp pattern)
                        (search "*" pattern)
                        (mcp-wildcard-match-p pattern tool-name))
                do (return-from mcp-tool-exposure
                     (mcp-exposure-name (mcp-resolve-alias exposure))))))
    (multiple-value-bind (exposure present) (mcp-get config "exposure")
      (if present
          (mcp-exposure-name (mcp-resolve-alias exposure))
          "codemode"))))

(defun mcp-tool-name-p (name)
  (or (uiop:string-prefix-p "mcp__" name)
      (member name
              '("list_mcp_resources"
                "list_mcp_resource_templates"
                "read_mcp_resource")
              :test #'string=)))

(defun read-mcp-json-object (text)
  (let ((pairs nil))
    (cadr-ai::parse-json-source
     text
     (lambda (key value)
       (push key pairs)
       (push value pairs))
     (lambda (key)
       (declare (ignore key))
       (let ((nested nil))
         (values
          (lambda (child value)
            (push child nested)
            (push value nested))
          (lambda ()
            (list* :json-object (nreverse nested)))))))
    (list* :json-object (nreverse pairs))))

(defun mcp-override-p (value)
  (and (mcp-object-p value)
       (not (nth-value 1 (mcp-get value "command")))
       (not (nth-value 1 (mcp-get value "url")))
       (not (nth-value 1 (mcp-get value "type")))))

(defun mcp-merge-object (base override)
  (let ((merged (list* :json-object (copy-list (cdr base)))))
    (loop for (key value) on (cdr override) by #'cddr
          do (setf merged (mcp-put merged key value)))
    merged))

(defun mcp-config-push-error (state message)
  (setf (mcp-config-state-errors state)
        (nconc (mcp-config-state-errors state) (list message))))

(defun mcp-config-set-server (state entry)
  (let ((found nil))
    (setf (mcp-config-state-servers state)
          (mapcar
           (lambda (existing)
             (if (string= (mcp-server-entry-name existing)
                          (mcp-server-entry-name entry))
                 (progn (setf found t) entry)
                 existing))
           (mcp-config-state-servers state)))
    (unless found
      (setf (mcp-config-state-servers state)
            (nconc (mcp-config-state-servers state) (list entry))))))

(defun mcp-strip-utf8-bom (text)
  ;; pi@4a080252f utils/text.ts stripBom. One leading U+FEFF only.
  (if (and (plusp (length text))
           (char= (char text 0) (code-char #xfeff)))
      (subseq text 1)
      text))

(defun read-mcp-config-file (path scope state)
  (unless (uiop:file-exists-p path)
    (return-from read-mcp-config-file nil))
  (let ((parsed
          (handler-case
              (read-mcp-json-object
               (mcp-strip-utf8-bom
                (uiop:read-file-string path :external-format :utf-8)))
            (error (condition)
              (mcp-config-push-error
               state
               (format nil "~A: ~A" path condition))
              (return-from read-mcp-config-file nil)))))
    (multiple-value-bind (servers servers-p) (mcp-get parsed "mcpServers")
      (unless (and (mcp-object-p parsed)
                   (or (not servers-p) (mcp-object-p servers)))
        (mcp-config-push-error
         state
         (format nil "~A: expected an object with an \"mcpServers\" object" path))
        (return-from read-mcp-config-file nil))
      (multiple-value-bind (flag present) (mcp-get parsed "autoEnableCodemode")
        (cond
          ((and present (or (eq flag t) (null flag)))
           (setf (mcp-config-state-auto-enable-codemode state) flag
                 (mcp-config-state-auto-enable-codemode-p state) t))
          (present
           (mcp-config-push-error
            state
            (format nil "~A: autoEnableCodemode must be a boolean" path)))))
      (loop for (name value) on (cdr (or servers '(:json-object))) by #'cddr
            do (cond
                 ((and (eq scope :project)
                       (mcp-object-p value)
                       (mcp-override-p value))
                  (let ((base
                          (find name (mcp-config-state-servers state)
                                :key #'mcp-server-entry-name
                                :test #'string=))
                        (extra
                          (loop for (key) on (cdr value) by #'cddr
                                unless (member key +mcp-override-keys+
                                               :test #'string=)
                                  collect key)))
                    (cond
                      ((null base)
                       (mcp-config-push-error
                        state
                        (format nil
                                "~A: server ~S needs \"command\" or \"url\", or a global server to override"
                                path name)))
                      (extra
                       (mcp-config-push-error
                        state
                        (format nil
                                "~A: server ~S: an override can only set ~{~A~^, ~}"
                                path name +mcp-override-keys+)))
                      (t
                       (let ((config
                               (validate-mcp-server-config
                                name
                                (mcp-merge-object
                                 (mcp-server-entry-config base)
                                 value))))
                         (if (stringp config)
                             (mcp-config-push-error
                              state (format nil "~A: ~A" path config))
                             (mcp-config-set-server
                              state
                              (make-mcp-server-entry
                               :name name
                               :config config
                               :source (mcp-server-entry-source base)
                               :scope (mcp-server-entry-scope base)
                               :override path))))))))
                 (t
                  (let ((config (validate-mcp-server-config name value)))
                    (cond
                      ((stringp config)
                       (mcp-config-push-error
                        state (format nil "~A: ~A" path config)))
                      (t
                       (let ((clash
                               (find-if
                                (lambda (other)
                                  (and (not (string= (mcp-server-entry-name other)
                                                     name))
                                       (string= (mcp-namespace
                                                 (mcp-server-entry-name other))
                                                (mcp-namespace name))))
                                (mcp-config-state-servers state))))
                         (cond
                           (clash
                            (mcp-config-push-error
                             state
                             (format nil
                                     "~A: server ~S conflicts with ~S"
                                     path name
                                     (mcp-server-entry-name clash))))
                           ((and (eq scope :project)
                                 (nth-value 1 (mcp-get config "url"))
                                 (nth-value 1 (mcp-get config "auth")))
                            (mcp-config-push-error
                             state
                             (format nil
                                     "~A: server ~S: auth is only allowed in the global mcp.json"
                                     path name)))
                           (t
                            (mcp-config-set-server
                             state
                             (make-mcp-server-entry
                              :name name
                              :config config
                              :source path
                              :scope scope))))))))))))))

(defun mcp-join (directory name)
  (namestring
   (merge-pathnames
    name
    (uiop:ensure-directory-pathname directory))))

(defun load-mcp-config (agent-dir cwd &key project-trusted)
  (let ((state (make-mcp-config-state))
        (project
          (and project-trusted
               (mcp-join (mcp-join cwd ".pi") "mcp.json"))))
    (read-mcp-config-file (mcp-join agent-dir "mcp.json") :global state)
    (when project
      (read-mcp-config-file project :project state))
    (make-loaded-mcp-config
     :servers (mcp-config-state-servers state)
     :auto-enable-codemode (mcp-config-state-auto-enable-codemode state)
     :auto-enable-codemode-p
     (mcp-config-state-auto-enable-codemode-p state)
     :errors (mcp-config-state-errors state)
     :project-config project)))

(defun mcp-json-indent (text)
  (or (and text
           (loop for start = 0 then (1+ end)
                 for end = (position #\Newline text :start start)
                 for line = (subseq text start (or end (length text)))
                 for content =
                   (position-if
                    (lambda (character)
                      (not (member character '(#\Space #\Tab))))
                    line)
                 when (and content (plusp content))
                   return (subseq line 0 content)
                 while end))
      "  "))

(defun write-mcp-json (value stream indent level)
  (cond
    ((mcp-object-p value)
     (let ((pairs (cdr value)))
       (write-char #\{ stream)
       (if (null pairs)
           (write-char #\} stream)
           (progn
             (loop for (key item) on pairs by #'cddr
                   for first-p = t then nil
                   do (unless first-p (write-char #\, stream))
                      (write-char #\Newline stream)
                      (dotimes (depth (1+ level))
                        (write-string indent stream))
                      (cadr-ai::write-json-string key stream)
                      (write-string ": " stream)
                      (write-mcp-json item stream indent (1+ level)))
             (write-char #\Newline stream)
             (dotimes (depth level)
               (write-string indent stream))
             (write-char #\} stream)))))
    ((and value (typep value 'sequence) (not (stringp value)))
     (write-char #\[ stream)
     (if (zerop (length value))
         (write-char #\] stream)
         (progn
           (loop for item across (coerce value 'vector)
                 for first-p = t then nil
                 do (unless first-p (write-char #\, stream))
                    (write-char #\Newline stream)
                    (dotimes (depth (1+ level))
                      (write-string indent stream))
                    (write-mcp-json item stream indent (1+ level)))
           (write-char #\Newline stream)
           (dotimes (depth level)
             (write-string indent stream))
           (write-char #\] stream))))
    (t
     (let ((cadr-ai::*json-sort-object-keys* nil))
       (cadr-ai::write-json-value value stream)))))

(defun edit-mcp-servers (path edit)
  (let* ((text
           (when (uiop:file-exists-p path)
             (mcp-strip-utf8-bom
              (uiop:read-file-string path :external-format :utf-8))))
         (parsed
           (if text
               (read-mcp-json-object text)
               '(:json-object))))
    (multiple-value-bind (servers servers-p) (mcp-get parsed "mcpServers")
      (when (and servers-p (not (mcp-object-p servers)))
        (error "~A: expected an object with an \"mcpServers\" object" path))
      (let ((next (funcall edit servers parsed)))
        (when next
          (let ((indent (mcp-json-indent text)))
            (ensure-directories-exist path)
            (with-open-file (out path
                                 :direction :output
                                 :if-exists :supersede
                                 :if-does-not-exist :create
                                 :external-format :utf-8)
              (write-mcp-json next out indent 0)
              (write-char #\Newline out))))))))

(defun add-mcp-server-config (path name config)
  ;; pi@4a080252f addMcpServerConfig. A missing file is created.
  ;; True means an entry with this name was replaced.
  (let ((replaced nil))
    (edit-mcp-servers
     path
     (lambda (servers parsed)
       (let ((servers (or servers '(:json-object))))
         (setf replaced (nth-value 1 (mcp-get servers name)))
         (mcp-put parsed
                  "mcpServers"
                  (mcp-put servers name (mcp-normalize config))))))
    replaced))

(defun remove-mcp-server-config (path name)
  ;; pi@4a080252f removeMcpServerConfig. False when the file is missing
  ;; or does not define the name. A miss does not rewrite the file.
  (unless (uiop:file-exists-p path)
    (return-from remove-mcp-server-config nil))
  (let ((removed nil))
    (edit-mcp-servers
     path
     (lambda (servers parsed)
       (if (and (mcp-object-p servers)
                (nth-value 1 (mcp-get servers name)))
           (progn
             (setf removed t)
             (mcp-put parsed "mcpServers" (mcp-delete servers name)))
           nil)))
    removed))

(defun update-mcp-server-config (path name patch &key override)
  (edit-mcp-servers
   path
   (lambda (servers parsed)
     (let ((server (and servers (nth-value 0 (mcp-get servers name))))
           (servers (or servers '(:json-object))))
       (when (and (not (mcp-object-p server)) override)
         (setf server '(:json-object)))
       (unless (mcp-object-p server)
         (error "~A does not define MCP server ~S" path name))
       (let ((keep-defaults (mcp-override-p server))
             (patch (mcp-normalize patch)))
         (multiple-value-bind (enabled present) (mcp-get patch "enabled")
           (when present
             (if (and (eq enabled t) (not keep-defaults))
                 (setf server (mcp-delete server "enabled"))
                 (setf server (mcp-put server "enabled" enabled)))))
         (multiple-value-bind (exposure present) (mcp-get patch "exposure")
           (when present
             (let ((exposure (mcp-exposure-name exposure)))
               (if (and (stringp exposure)
                        (string= exposure "codemode")
                        (not keep-defaults))
                   (setf server (mcp-delete server "exposure"))
                   (setf server (mcp-put server "exposure" exposure))))))
         (mcp-put parsed
                  "mcpServers"
                  (mcp-put servers name server)))))))

(defstruct mcp-server-listing
  (name "" :type string)
  (description nil :type (or null string))
  (exposure nil :type (or null string))
  (tool-exposures nil :type list)
  (enabled t :type boolean)
  (instructions nil :type (or null string)))

(defun mcp-sanitize-name (text)
  (with-output-to-string (out)
    (loop for character across text
          do (write-char
              (if (or (char<= #\A character #\Z)
                      (char<= #\a character #\z)
                      (digit-char-p character)
                      (char= character #\_))
                  character
                  #\_)
              out))))

(defun mcp-name-hash (server tool)
  (let ((digest
          (cadr-ai::sha256-bytes
           (sb-ext:string-to-octets
            (concatenate 'string server (string #\Nul) tool)
            :external-format :utf-8))))
    (with-output-to-string (out)
      (loop for index from 0 below 4
            do (format out "~(~2,'0x~)" (aref digest index))))))

(defun create-mcp-tool-name (server tool &optional (taken (constantly nil)))
  ;; pi@4a080252f createMcpToolName. Provider names are 64 characters of
  ;; [A-Za-z0-9_]. A collision or a longer name keeps a sha256 suffix.
  (let ((name (mcp-sanitize-name (format nil "mcp__~A__~A" server tool))))
    (if (and (<= (length name) 64)
             (not (funcall taken name)))
        name
        (let ((hash (mcp-name-hash server tool)))
          (format nil "~A_~A"
                  (subseq name 0 (min (length name)
                                      (- 64 (length hash) 1)))
                  hash)))))

(defun mcp-listing-exposures (listing)
  (let ((exposure (or (mcp-server-listing-exposure listing) "codemode")))
    (remove-duplicates
     (cons exposure (mcp-server-listing-tool-exposures listing))
     :test #'string=)))

(defun mcp-listing-indirect-p (listing)
  (let ((exposures (mcp-listing-exposures listing)))
    (or (member "codemode" exposures :test #'string=)
        (member "deferred" exposures :test #'string=))))

(defun mcp-listing-reach (listing)
  (if (member "codemode" (mcp-listing-exposures listing) :test #'string=)
      "codemode"
      "tool_search"))

(defun mcp-servers-intro (reaches)
  (concatenate
   'string
   "MCP servers whose tools are not declared to you."
   (if (member "codemode" reaches :test #'string=)
       " Call the tools of `codemode` servers from codemode scripts."
       "")
   (if (member "tool_search" reaches :test #'string=)
       " Load the tools of `tool_search` servers with `tool_search`."
       "")))

(defun mcp-trim (text)
  (string-trim '(#\Space #\Tab #\Newline #\Return) text))

(defun mcp-first-line (text)
  (let* ((newline (position #\Newline text))
         (line (if newline (subseq text 0 newline) text)))
    (mcp-trim line)))

(defun mcp-listing-summary (listing)
  (let* ((description (mcp-server-listing-description listing))
         (trimmed (and description (mcp-trim description)))
         (text (if (and trimmed (plusp (length trimmed)))
                   trimmed
                   (or (mcp-server-listing-instructions listing) ""))))
    (mcp-first-line text)))

(defun mcp-truncate (text max)
  (cond
    ((<= (length text) max) text)
    ((<= max 1) "")
    (t
     (concatenate 'string
                  (mcp-trim (subseq text 0 (1- max)))
                  (string #\…)))))

(defun mcp-omitted-line (count)
  (when (plusp count)
    (format nil
            "- … ~D more server~A; find their tools with searchTools()"
            count
            (if (= count 1) "" "s"))))

(defun mcp-section-size (intro heads total kept)
  (let ((lines (cons intro (subseq heads 0 kept)))
        (omitted (mcp-omitted-line (- total kept))))
    (length (format nil "~{~A~^~%~}"
                    (if omitted
                        (append lines (list omitted))
                        lines)))))

(defun render-mcp-servers-section (servers)
  ;; pi@4a080252f renderServersSection. Direct-only servers stay out.
  ;; Descriptions shrink, then the last servers are counted in the
  ;; closing line, so the section stays within 4096 characters.
  (let* ((listed
           (sort
            (remove-if-not
             (lambda (listing)
               (and (mcp-server-listing-enabled listing)
                    (mcp-listing-indirect-p listing)))
             (copy-list servers))
            #'string<
            :key #'mcp-server-listing-name))
         (reaches (mapcar #'mcp-listing-reach listed)))
    (when listed
      (let* ((intro (mcp-servers-intro reaches))
             (heads
               (loop for listing in listed
                     for reach in reaches
                     collect (format nil "- ~A (~A)"
                                     (mcp-namespace
                                      (mcp-server-listing-name listing))
                                     reach)))
             (kept (length listed)))
        (loop while (and (plusp kept)
                         (> (mcp-section-size intro heads (length listed) kept)
                            4096))
              do (decf kept))
        (let ((per-server
                (if (zerop kept)
                    0
                    (min 250
                         (- (floor (- 4096
                                      (mcp-section-size
                                       intro heads (length listed) kept))
                                   kept)
                            2)))))
          (format nil "~{~A~^~%~}"
                  (append
                   (list intro)
                   (loop for listing in listed
                         for head in heads
                         for index from 0 below kept
                         for summary = (if (plusp per-server)
                                           (mcp-truncate
                                            (mcp-listing-summary listing)
                                            per-server)
                                           "")
                         collect (if (plusp (length summary))
                                     (format nil "~A: ~A" head summary)
                                     head))
                   (let ((omitted
                           (mcp-omitted-line (- (length listed) kept))))
                     (if omitted (list omitted) nil)))))))))
