(in-package #:cadr-cli)

;;; pi@4a080252f packages/coding-agent/src/extensions/index.ts and the
;;; builtin: half of resource-loader.ts / package-manager.ts.
;;; llama.cpp is a built-in. codemode, tool-search, and mcp are
;;; built-ins that another extension can replace by registering the
;;; same tool, command, or flag.

(defparameter +builtin-extension-prefix+ "builtin:")

(defun builtin-extension-path (name)
  (concatenate 'string +builtin-extension-prefix+ name))

(defun builtin-extension-path-p (entry)
  (and (stringp entry)
       (uiop:string-prefix-p +builtin-extension-prefix+ entry)
       (> (length entry) (length +builtin-extension-prefix+))))

(defun builtin-extension-name (path)
  (subseq path (length +builtin-extension-prefix+)))

(defun extension-override-entry-p (entry)
  (and (stringp entry)
       (plusp (length entry))
       (member (char entry 0) '(#\+ #\- #\!) :test #'char=)))

(defun extension-manager-file-paths (manager)
  ;; CLI -e paths, then trusted project settings paths, then global
  ;; settings paths. Override patterns and builtin: paths are not files.
  ;; --no-extensions keeps only the CLI paths.
  (append
   (remove-if-not
    #'extension-file-path-p
    (cli-extension-manager-explicit-paths manager))
   (unless (cli-extension-manager-no-discovery-p manager)
     (append
      (when (cli-extension-manager-project-trusted-p manager)
        (remove-if-not
         #'extension-file-path-p
         (cli-extension-manager-project-extension-entries manager)))
      (remove-if-not
       #'extension-file-path-p
       (cli-extension-manager-global-extension-entries manager))))))

(defun extension-file-path-p (entry)
  ;; Discovery receives both settings strings and pathname objects from
  ;; callers that already resolved a file.
  (typecase entry
    (pathname t)
    (string
     (and (plusp (length entry))
          (not (extension-override-entry-p entry))
          (not (builtin-extension-path-p entry))))
    (t nil)))

(defun settings-extension-entry-list (manager scope)
  (let* ((table
           (ecase scope
             (:global (settings-manager-global manager))
             (:project (settings-manager-project manager))))
         (value (cadr-ai::json-get table "extensions" :missing)))
    (if (and (vectorp value) (every #'stringp value))
        (coerce value 'list)
        nil)))

(defun builtin-path-basename (path)
  (let ((slash (position #\/ path :from-end t)))
    (if slash
        (subseq path (1+ slash))
        path)))

(defun builtin-pattern-matches-p (path pattern)
  ;; pi@4a080252f matchesAnyPattern. minimatch against the path and its
  ;; basename, so !*.cpp matches builtin:llama.cpp. * does not cross /.
  (let ((scanner (glob-scanner pattern)))
    (or (cl-ppcre:scan scanner path)
        (cl-ppcre:scan scanner (builtin-path-basename path)))))

(defun builtin-enabled-by-overrides-p (path entries)
  ;; pi@4a080252f isEnabledByOverrides. Default enabled. Every !
  ;; pattern, then every exact +, then every exact -. List order
  ;; inside one phase does not matter, so - before + in the list
  ;; still ends disabled.
  (let ((enabled t)
        (excludes nil)
        (force-includes nil)
        (force-excludes nil))
    (dolist (entry entries)
      (when (extension-override-entry-p entry)
        (let ((prefix (char entry 0))
              (target (subseq entry 1)))
          (cond
            ((char= prefix #\!) (push target excludes))
            ((char= prefix #\+) (push target force-includes))
            ((char= prefix #\-) (push target force-excludes))))))
    (when (some (lambda (pattern)
                  (builtin-pattern-matches-p path pattern))
                excludes)
      (setf enabled nil))
    (when (some (lambda (target) (string= path target))
                force-includes)
      (setf enabled t))
    (when (some (lambda (target) (string= path target))
                force-excludes)
      (setf enabled nil))
    enabled))

(defun builtin-project-override (path entries)
  ;; pi@4a080252f applyAutoloadDisabledPatterns. :unset when no
  ;; project pattern names this path. The last match wins.
  (let ((found :unset))
    (dolist (entry entries found)
      (when (extension-override-entry-p entry)
        (let* ((prefix (char entry 0))
               (target (subseq entry 1))
               (exact (or (char= prefix #\+) (char= prefix #\-))))
          (when (if exact
                    (string= path target)
                    (builtin-pattern-matches-p path target))
            (setf found
                  (not (or (char= prefix #\-)
                           (char= prefix #\!))))))))))

(defun builtin-extension-enabled-p (manager path)
  (let ((project
          (when (cli-extension-manager-project-trusted-p manager)
            (builtin-project-override
             path
             (cli-extension-manager-project-extension-entries
              manager)))))
    (if (eq project :unset)
        (builtin-enabled-by-overrides-p
         path
         (cli-extension-manager-global-extension-entries manager))
        project)))

(defun builtin-factory-entry-p (entry)
  (and (listp entry)
       (eq (getf entry :builtin-p) t)
       (stringp (getf entry :name))
       (functionp (getf entry :factory))))

(defun ordered-builtin-entries (extra)
  (let ((ordered nil)
        (seen (make-hash-table :test #'equal)))
    (dolist (entry (append (standard-builtin-extensions)
                           (remove-if-not #'builtin-factory-entry-p extra)))
      (let ((name (getf entry :name)))
        (if (gethash name seen)
            (setf (gethash name seen) entry)
            (progn
              (setf (gethash name seen) entry)
              (push name ordered)))))
    (mapcar (lambda (name) (gethash name seen))
            (nreverse ordered))))

(defun builtin-path-disabled-p (manager path)
  (member (builtin-extension-name path)
          (cli-extension-manager-disabled-builtin-extensions manager)
          :test #'string-equal))

(defun default-builtin-paths (manager)
  ;; Settings-enabled built-ins. --no-extensions and the pre-trust
  ;; pass omit them. --no-mcp drops builtin:mcp here and on -e.
  (unless (or (cli-extension-manager-no-discovery-p manager)
              (cli-extension-manager-defer-builtin-extensions-p manager))
    (loop for entry in (cli-extension-manager-builtin-extensions manager)
          for path = (builtin-extension-path (getf entry :name))
          when (and (builtin-extension-enabled-p manager path)
                    (not (builtin-path-disabled-p manager path)))
          collect path)))

(defun cli-extension-resolved-entry (manager path)
  (let ((resolved
          (merge-pathnames
           (pathname path)
           (cli-extension-manager-cwd manager))))
    (unless (probe-file resolved)
      (return-from cli-extension-resolved-entry nil))
    (let ((entry (truename resolved)))
      (if (uiop:directory-pathname-p entry)
          (let ((file (merge-pathnames "extension.lisp" entry)))
            (when (probe-file file)
              (namestring (truename file))))
          (namestring entry)))))

(defun cli-extension-load-steps (manager file-sources)
  ;; pi@4a080252f mergePaths(cliPaths, resolvedPaths). CLI paths,
  ;; files and builtin: names in the order given, come first. Other
  ;; files follow. The remaining built-ins stay in llama.cpp,
  ;; codemode, tool-search, mcp order.
  (let ((seen-files (make-hash-table :test #'equal))
        (seen-builtins (make-hash-table :test #'equal))
        (steps nil)
        (defer (cli-extension-manager-defer-builtin-extensions-p manager)))
    (dolist (path (cli-extension-manager-explicit-paths manager))
      (cond
        ((builtin-extension-path-p path)
         (unless (or defer (gethash path seen-builtins))
           (setf (gethash path seen-builtins) t)
           (unless (builtin-path-disabled-p manager path)
             (push (list :builtin path) steps))))
        ((extension-file-path-p path)
         (let* ((namestring (cli-extension-resolved-entry manager path))
                (source
                  (and namestring
                       (find namestring file-sources
                             :key #'extension-source-record-path
                             :test #'string=))))
           (when (and source (not (gethash namestring seen-files)))
             (setf (gethash namestring seen-files) t)
             (push (list :file source) steps))))))
    (dolist (source file-sources)
      (let ((namestring (extension-source-record-path source)))
        (unless (gethash namestring seen-files)
          (setf (gethash namestring seen-files) t)
          (push (list :file source) steps))))
    (unless defer
      (dolist (path (default-builtin-paths manager))
        (unless (gethash path seen-builtins)
          (setf (gethash path seen-builtins) t)
          (push (list :builtin path) steps))))
    (nreverse steps)))

(defun find-builtin-extension-entry (manager name)
  (find name
        (cli-extension-manager-builtin-extensions manager)
        :key (lambda (entry) (getf entry :name))
        :test #'string=))

(defun load-one-builtin-extension (manager entry order)
  (let* ((name (getf entry :name))
         (path (builtin-extension-path name))
         (bundle
           (cadr-agent::make-extension-bundle
            :id path
            :path path
            :scope :builtin
            :rank 4
            :order order
            :hidden-p t
            :replaceable-p (eq t (getf entry :replaceable-p)))))
    (call-with-extension-output-boundary
     manager
     (lambda ()
       (cadr-agent::call-with-extension-load
        (cli-extension-manager-host manager)
        bundle
        (lambda ()
          (funcall (getf entry :factory)
                   (cadr-agent:current-extension-api))))))
    bundle))

(defun load-builtin-extension-path (manager path order)
  "Return (values bundle issue). Unknown names keep the loader sentence."
  (let ((entry
          (find-builtin-extension-entry
           manager (builtin-extension-name path))))
    (unless entry
      (return-from load-builtin-extension-path
        (values nil
                (list :type :error
                      :path path
                      :message
                      (format nil "Unknown built-in extension: ~A" path)))))
    (handler-case
        (values (load-one-builtin-extension manager entry order) nil)
      (error (condition)
        (values nil
                (list :type :error
                      :path path
                      :message
                      (format nil
                              "Failed to load extension: ~A"
                              condition)))))))

(defun extension-registration-names (bundle)
  (append
   (mapcar
    (lambda (definition)
      (cons "tool"
            (cadr-agent::extension-tool-definition-name definition)))
    (cadr-agent::extension-bundle-tools bundle))
   (mapcar
    (lambda (definition)
      (cons "command"
            (cadr-agent::extension-command-definition-name definition)))
    (cadr-agent::extension-bundle-commands bundle))
   (mapcar
    (lambda (definition)
      (cons "flag"
            (cadr-agent::extension-flag-definition-name definition)))
    (cadr-agent::extension-bundle-flags bundle))))

(defun builtin-replacement-registered-name (kind raw)
  (cond
    ((string= kind "command") (format nil "/~A" raw))
    ((string= kind "flag") (format nil "--~A" raw))
    (t raw)))

(defun builtin-replacement-warning (winner-path kind registered builtin-name)
  ;; pi@4a080252f omitReplacedExtensions. The product command is cadr.
  (format nil
          "Extension ~A registers ~A `~A`, so built-in extension `~A` was not loaded. To use `~A`, run `~A config` and make sure it is enabled under Built-in extensions, then disable or remove the existing extension. We recommend only having one or the other loaded at a time."
          winner-path
          kind
          registered
          builtin-name
          builtin-name
          (cadr-ai::cadr-product-slug)))

(defun omit-replaced-extensions (bundles)
  ;; pi@4a080252f omitReplacedExtensions. Non-replaceable registrations
  ;; occupy the name. A replaceable extension that uses one is left out.
  (let ((taken (make-hash-table :test #'equal)))
    (dolist (bundle bundles)
      (unless (cadr-agent::extension-bundle-replaceable-p bundle)
        (dolist (name (extension-registration-names bundle))
          (setf (gethash
                 (concatenate 'string (car name) ":" (cdr name))
                 taken)
                bundle))))
    (let ((kept nil)
          (warnings nil))
      (dolist (bundle bundles)
        (if (not (cadr-agent::extension-bundle-replaceable-p bundle))
            (push bundle kept)
            (let ((hit
                    (find-if
                     (lambda (name)
                       (gethash
                        (concatenate 'string (car name) ":" (cdr name))
                        taken))
                     (extension-registration-names bundle))))
              (cond
                ((null hit) (push bundle kept))
                ((builtin-extension-path-p
                  (cadr-agent::extension-bundle-path bundle))
                 (let* ((winner (gethash
                                 (concatenate 'string (car hit) ":" (cdr hit))
                                 taken))
                        (builtin-name
                          (builtin-extension-name
                           (cadr-agent::extension-bundle-path bundle))))
                   (push (list :type :warning
                               :path (cadr-agent::extension-bundle-path bundle)
                               :message
                               (builtin-replacement-warning
                                (cadr-agent::extension-bundle-path winner)
                                (car hit)
                                (builtin-replacement-registered-name
                                 (car hit) (cdr hit))
                                builtin-name))
                         warnings)))))))
      (values (nreverse kept) (nreverse warnings)))))

(defun tool-search-reaches-tools (input)
  ;; pi@4a080252f createToolSearchToolDefinition reachesTools.
  (declare (ignore input))
  "all")

(defun tool-search-extension-factory (api)
  (declare (ignore api))
  (let ((tool (cadr-agent:make-tool-search-tool)))
    (cadr-agent::register-rich-extension-tool
     "tool_search"
     :label "tool_search"
     :description (cadr-ai:tool-description tool)
     :prompt-snippet
     "Search for tools that are not loaded yet and load the matches"
     :parameters (cadr-ai:tool-parameters tool)
     :execution-mode :parallel
     :exposure :model-only
     :default-active nil
     :reaches-tools #'tool-search-reaches-tools
     :handler
     (lambda (call-id arguments signal update context)
       (declare (ignore signal update context))
       (funcall (cadr-ai:tool-executor tool) call-id arguments)))))

(defun codemode-empty-description ()
  ;; pi@4a080252f createCodemodeDescription([], { models: true }).
  (format nil
          "Run JavaScript that calls other tools. The input is raw JavaScript (not JSON, no code fence), run as an async function body in a QuickJS sandbox: top-level `await` and `return` work. No Node, file system, network, or timers.
- `await tools.<name>({ ...args })` resolves to a string, or an object if the tool's declaration says so, and rejects with an Error on failure. A tool whose declaration returns an object resolves on failure too when it returned that object; check its fields. Calls still running when the script ends are cancelled.
- Optional first line: `// @options: {\"max_output_tokens\": 10000, \"timeout_ms\": 60000}`

Globals:
- `text(value)`, `image(dataUrlOrImageBlock)`, `console.log(...)`, and top-level `return` add output; `exit()` ends the script. With several text items, each starts with a `==> text N/M <==` line, and `console` lines follow the other output in one `<console_output>` block. `image()` also saves the image to a temp file and the result names its path.
- `store(key, value)` and `load(key)` keep JSON values across codemode calls.
- `ALL_TOOLS`, `await searchTools(query, { limit?, namespace? })`, `await describeTool(name)`, `await describeNamespace(name)`: find unlisted tools, such as MCP tools.
- `models`: classifiers and image generation. Read ~A first."
          (cadr-agent::mcp-join
           (cadr-ai::cadr-docs-directory)
           "codemode.md")))

(defun codemode-tool-parameters ()
  (let ((parameters (cadr-ai::json-object))
        (properties (cadr-ai::json-object))
        (code (cadr-ai::json-object)))
    (setf (gethash "type" code) "string"
          (gethash "description" code) "Raw JavaScript source."
          (gethash "code" properties) code
          (gethash "type" parameters) "object"
          (gethash "properties" parameters) properties
          (gethash "required" parameters) (vector "code")
          (gethash "additionalProperties" parameters) nil)
    parameters))

(defun codemode-extension-factory (api)
  ;; pi@4a080252f createCodemodeExtension. Inactive until --tools or
  ;; defaultTools names it. The QuickJS module loads on the first script.
  (cadr-agent::register-rich-extension-tool
   "codemode"
   :label "codemode"
   :description (codemode-empty-description)
   :prompt-snippet "Run JavaScript that calls other tools"
   :prompt-guidelines
   (list "Use codemode to batch independent tool calls (Promise.allSettled), chain them, or filter large output, instead of many separate calls.")
   :parameters (codemode-tool-parameters)
   :execution-mode :parallel
   :exposure :model-only
   :default-active nil
   :prepare-loadout #'codemode-prepare-loadout
   :handler
   (lambda (call-id arguments signal update context)
     (handler-case
         (execute-codemode api call-id arguments signal update context)
       (codemode-source-error (condition)
         (error 'cadr-agent:extension-execution-error
                :message (codemode-source-error-text condition)))))))

(defparameter +mcp-command-usage+
  "Usage: /mcp, /mcp login [server], /mcp logout [server], /mcp reconnect [server]")

(defparameter +mcp-oauth-none-message+
  "No enabled MCP server uses OAuth. Only HTTP servers without an Authorization header do.")

(defun mcp-command-words (arguments)
  (let ((text
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           (or arguments "")))
        (parts nil)
        (start nil))
    (when (plusp (length text))
      (loop for index from 0 below (length text)
            for character = (char text index)
            do (if (member character
                           '(#\Space #\Tab #\Newline #\Return)
                           :test #'char=)
                   (when start
                     (push (subseq text start index) parts)
                     (setf start nil))
                   (unless start
                     (setf start index))))
      (when start
        (push (subseq text start) parts)))
    (nreverse parts)))

(defun mcp-status-text (context)
  (let* ((agent-dir (cadr-core:coding-agent-directory))
         (loaded
           (cadr-agent::load-mcp-config
            agent-dir
            (cadr-agent::extension-context-cwd context)
            :project-trusted nil))
         (servers (cadr-agent::loaded-mcp-config-servers loaded))
         (errors (cadr-agent::loaded-mcp-config-errors loaded)))
    (if (and (null servers) (null errors))
        (format nil
                "No MCP servers configured. Add them to ~A or .pi/mcp.json."
                (cadr-agent::mcp-join agent-dir "mcp.json"))
        (with-output-to-string (output)
          (loop for server in servers
                for first = t then nil
                do (unless first (terpri output))
                   (let ((config
                           (cadr-agent::mcp-server-entry-config server)))
                     (format output "~A: starting (~A)"
                             (cadr-agent::mcp-server-entry-name server)
                             (or (cadr-agent::mcp-get config "exposure")
                                 "codemode"))))
          (dolist (config-error errors)
            (terpri output)
            (format output "config error: ~A" config-error))))))

(defun mcp-find-server (servers name)
  (find name servers
        :key #'cadr-agent::mcp-server-entry-name
        :test #'string=))

(defun handle-mcp-command (arguments context)
  (let* ((words (mcp-command-words arguments))
         (action (first words))
         (name (second words))
         (loaded
           (cadr-agent::load-mcp-config
            (cadr-core:coding-agent-directory)
            (cadr-agent::extension-context-cwd context)
            :project-trusted nil))
         (servers (cadr-agent::loaded-mcp-config-servers loaded)))
    (cond
      ((> (length words) 2)
       (cadr-agent::extension-context-notify
        context +mcp-command-usage+ :level :warning))
      ((null action)
       (cadr-agent::extension-context-notify
        context (mcp-status-text context) :level :info))
      ((not (member action '("login" "logout" "reconnect") :test #'string=))
       (cadr-agent::extension-context-notify
        context +mcp-command-usage+ :level :warning))
      ((and name (not (mcp-find-server servers name)))
       (cadr-agent::extension-context-notify
        context
        (format nil "No MCP server named ~S." name)
        :level :error))
      ((and (null name)
            (member action '("login" "logout") :test #'string=)
            (not (find-if
                  (lambda (server)
                    (cadr-agent::mcp-uses-oauth-p
                     (cadr-agent::mcp-server-entry-config server)))
                  servers)))
       (cadr-agent::extension-context-notify
        context +mcp-oauth-none-message+ :level :error))
      ((and (null name) (string= action "reconnect") (null servers))
       (cadr-agent::extension-context-notify
        context "No enabled MCP server to reconnect." :level :info))
      ((and name
            (string= action "login")
            (not (cadr-agent::extension-context-has-ui-p context)))
       (cadr-agent::extension-context-notify
        context
        (format nil
                "Signing in to MCP server ~S requires interactive mode."
                name)
        :level :error))
      (t
       (cadr-agent::extension-context-notify
        context (mcp-status-text context) :level :info)))))

(defun mcp-extension-factory (api)
  (declare (ignore api))
  (cadr-agent:define-command
      "mcp"
    :description
    "Manage MCP servers: sign in, reconnect, enable or disable, and change exposure"
    :handler #'handle-mcp-command))

(defun standard-builtin-extensions ()
  ;; pi@4a080252f extensions/index.ts builtInExtensions.
  (list
   (list :name "llama.cpp"
         :factory #'llama-extension-factory
         :builtin-p t)
   (list :name "codemode"
         :factory #'codemode-extension-factory
         :builtin-p t
         :replaceable-p t)
   (list :name "tool-search"
         :factory #'tool-search-extension-factory
         :builtin-p t
         :replaceable-p t)
   (list :name "mcp"
         :factory #'mcp-extension-factory
         :builtin-p t
         :replaceable-p t)))
