(in-package #:cadr-cli)

(defstruct cache-miss
  (missed-tokens 0 :type (integer 0 *))
  (missed-cost 0d0 :type double-float)
  (idle-milliseconds 0 :type integer)
  (model-changed-p nil :type boolean)
  message)

(defstruct cache-waste
  (missed-tokens 0 :type (integer 0 *))
  (missed-cost 0d0 :type double-float)
  (miss-count 0 :type (integer 0 *))
  (misses nil :type list))

(defun assistant-cache-usage (message)
  (let ((usage
          (cadr-ai:assistant-message-usage
           message)))
    (values
     (cadr-ai:usage-input usage)
     (cadr-ai:usage-cache-read usage)
     (cadr-ai:usage-cache-write usage)
     (cadr-ai:cost-cache-read
      (cadr-ai:usage-cost usage))
     (cadr-ai:cost-cache-write
      (cadr-ai:usage-cost usage)))))

(defun cache-read-price-per-million
    (message model-price-function)
  (or
   (and model-price-function
        (funcall
         model-price-function
         (cadr-ai:assistant-message-provider
          message)
         (cadr-ai:assistant-message-model
          message)))
   0d0))

(defun detect-cache-miss
    (prior-messages current-message
     &key model-price-function)
  (let ((previous
          (find-if
           (lambda (item)
             (typep item
                    'cadr-ai:assistant-message))
           prior-messages
           :from-end t)))
    (unless previous
      (return-from detect-cache-miss nil))
    (multiple-value-bind
          (previous-input previous-read
           previous-write ignored-read-cost
           ignored-write-cost)
        (assistant-cache-usage previous)
      (declare
       (ignore previous-input
               ignored-read-cost
               ignored-write-cost))
      (multiple-value-bind
            (current-input current-read
             current-write current-read-cost
             current-write-cost)
          (assistant-cache-usage current-message)
        (declare
         (ignore current-input current-read-cost))
        (let ((cacheable
                (+ previous-read previous-write)))
          (unless
              (and
               (plusp cacheable)
               (zerop current-read)
               (plusp current-write))
            (return-from detect-cache-miss nil))
          (let* ((write-price
                   (*
                    (/ current-write-cost
                       current-write)
                    1000000d0))
                 (read-price
                   (cache-read-price-per-million
                    current-message
                    model-price-function))
                 (missed-cost
                   (*
                    (/ cacheable 1000000d0)
                    (max 0d0
                         (- write-price
                            read-price)))))
            (make-cache-miss
             :missed-tokens cacheable
             :missed-cost missed-cost
             :idle-milliseconds
             (-
              (cadr-ai:assistant-message-timestamp
               current-message)
              (cadr-ai:assistant-message-timestamp
               previous))
             :model-changed-p
             (not
              (and
               (eq
                (cadr-ai:assistant-message-provider
                 previous)
                (cadr-ai:assistant-message-provider
                 current-message))
               (string=
                (cadr-ai:assistant-message-model
                 previous)
                (cadr-ai:assistant-message-model
                 current-message))))
             :message current-message)))))))

(defun compute-cache-waste
    (items &key model-price-function)
  (let ((prior nil)
        (reset-p nil)
        (misses nil))
    (dolist (item items)
      (cond
        ((eq item :compaction)
         (setf reset-p t
               prior nil))
        ((typep item
                'cadr-ai:assistant-message)
         (if reset-p
             (setf reset-p nil)
             (let ((miss
                     (detect-cache-miss
                      prior item
                      :model-price-function
                      model-price-function)))
               (when miss
                 (push miss misses))))
         (setf prior
               (append prior (list item))))))
    (setf misses (nreverse misses))
    (make-cache-waste
     :missed-tokens
     (loop for miss in misses
           sum (cache-miss-missed-tokens miss))
     :missed-cost
     (coerce
      (loop for miss in misses
            sum (cache-miss-missed-cost miss))
      'double-float)
     :miss-count (length misses)
     :misses misses)))

(defun should-run-first-time-setup-p
    (settings-path
     &key experimental-value
       custom-agent-directory-p
       forked-package-p)
  (and
   (experimental-features-enabled-p
    experimental-value)
   (not custom-agent-directory-p)
   (not forked-package-p)
   (not (probe-file settings-path))))

(defun settings-analytics-enabled-p (manager)
  (eq t
      (settings-value
       manager "enableAnalytics" nil)))

(defun settings-tracking-id (manager)
  (settings-value manager "trackingId"))

(defun settings-set-analytics
    (manager enabled-p)
  (when
      (and enabled-p
           (null
            (settings-tracking-id manager)))
    (settings-set
     manager "trackingId"
     (cadr-ai:uuid-v7)))
  (settings-set
   manager "enableAnalytics"
   (not (null enabled-p)))
  enabled-p)

(defun apply-http-proxy-setting
    (proxy &optional environment)
  (let ((trimmed
          (and proxy
               (string-trim
                '(#\Space #\Tab #\Newline #\Return)
                proxy))))
    (when (and trimmed
               (plusp (length trimmed)))
      (if environment
          (dolist (name
                   '("HTTP_PROXY" "HTTPS_PROXY"))
            (unless
                (assoc name environment
                       :test #'string=)
              (setf environment
                    (acons name trimmed
                           environment))))
          (dolist (name
                   '("HTTP_PROXY" "HTTPS_PROXY"))
            (unless (uiop:getenv name)
              (sb-posix:setenv
               name trimmed 0))))))
  environment)

(defun parse-null-environment (contents)
  (let ((environment nil))
    (dolist
        (entry
         (uiop:split-string
          contents :separator
          (list (code-char 0))))
      (let ((equals (position #\= entry)))
        (when (and equals
                   (plusp equals))
          (push
           (cons
            (subseq entry 0 equals)
            (subseq entry (1+ equals)))
           environment))))
    (nreverse environment)))

(defun restore-empty-sandbox-environment
    (&key bun-p environment
       (environ-path #p"/proc/self/environ"))
  (if (or (not bun-p)
          environment
          (not (probe-file environ-path)))
      environment
      (parse-null-environment
       (uiop:read-file-string
        environ-path
        :external-format :latin-1))))

(defun version-check-request (version)
  (list
   :url "https://pi.dev/api/latest-version"
   :headers
   `(("User-Agent" . ,(pi-user-agent version))
     ("Accept" . "application/json"))))

(defparameter *version-check-http-function* nil)

(defun nonempty-environment-value-p (value)
  (and (stringp value)
       (plusp (length value))))

(defun release-string-field (release key)
  (let ((value
          (and
           (hash-table-p release)
           (cadr-ai::json-get release key))))
    (when (stringp value)
      (let ((trimmed
              (string-trim
               '(#\Space #\Tab #\Newline #\Return)
               value)))
        (and (plusp (length trimmed))
             trimmed)))))

(defun normalize-latest-pi-release (release)
  (let ((version
          (release-string-field
           release "version")))
    (when version
      (let ((normalized
              (make-hash-table :test #'equal))
            (package-name
              (release-string-field
               release "packageName"))
            (note
              (release-string-field
               release "note")))
        (cadr-ai::json-put
         normalized "version" version)
        (when package-name
          (cadr-ai::json-put
           normalized "packageName"
           package-name))
        (when note
          (cadr-ai::json-put
           normalized "note" note))
        normalized))))

(defun get-latest-pi-release
    (current-version
     &key
       (timeout-milliseconds 10000)
       (offline-value
         (uiop:getenv "PI_OFFLINE")))
  (when (nonempty-environment-value-p
         offline-value)
    (return-from get-latest-pi-release
      nil))
  (let* ((request
           (version-check-request
            current-version))
         (timeout-seconds
           (/ timeout-milliseconds
              1000d0))
         (http-function
           (or *version-check-http-function*
               cadr-ai:*http-request-function*)))
    (multiple-value-bind
          (body status headers)
        (funcall
         http-function
         (getf request :url)
         :method :get
         :headers (getf request :headers)
         :connect-timeout timeout-seconds
         :read-timeout timeout-seconds
         :want-stream nil
         :force-string t)
      (declare (ignore headers))
      (when (and
             (integerp status)
             (<= 200 status 299))
        (normalize-latest-pi-release
         (cadr-ai::parse-json body))))))

(defun get-latest-pi-version
    (current-version
     &rest options
     &key &allow-other-keys)
  (let ((release
          (apply #'get-latest-pi-release
                 current-version
                 options)))
    (and release
         (cadr-ai::json-get
          release "version"))))

(defun newer-package-version-p
    (candidate current)
  (let ((comparison
          (compare-package-versions
           candidate current)))
    (if (numberp comparison)
        (plusp comparison)
        (not
         (string=
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           candidate)
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           current))))))

(defun check-for-new-pi-version
    (current-version
     &key
       (skip-value
         (uiop:getenv
          "PI_SKIP_VERSION_CHECK"))
       (offline-value
         (uiop:getenv "PI_OFFLINE"))
       (timeout-milliseconds 10000))
  (when (nonempty-environment-value-p
         skip-value)
    (return-from check-for-new-pi-version
      nil))
  (handler-case
      (let ((release
              (get-latest-pi-release
               current-version
               :offline-value offline-value
               :timeout-milliseconds
               timeout-milliseconds)))
        (and
         release
         (newer-package-version-p
          (cadr-ai::json-get
           release "version")
          current-version)
         release))
    (condition () nil)))

(defun newer-release (current release
                      &key automatic-p
                        skip-value)
  (when (and
         (or (not automatic-p)
             (not
              (nonempty-environment-value-p
               skip-value)))
         (hash-table-p release)
         (stringp
          (cadr-ai::json-get release "version"))
         (plusp
          (compare-package-versions
           (cadr-ai::json-get release
                              "version")
           current)))
    (let ((copy
            (cadr-ai::copy-json-value
             release)))
      (let ((note
              (cadr-ai::json-get copy "note")))
        (when (stringp note)
          (cadr-ai::json-put
           copy "note"
           (string-trim
            '(#\Space #\Tab #\Newline #\Return)
            note))))
      copy)))

(defun valid-thinking-level-p (value)
  (not
   (null
    (member
     (string-downcase value)
     +thinking-level-names+
     :test #'string=))))

(defun thinking-theme-color-name
    (theme level)
  (let* ((colors
           (cadr-ai::json-get theme "colors"))
         (name
           (format nil
                   "thinking~:(~A~)"
                   (string-downcase
                    (etypecase level
                      (symbol (symbol-name level))
                      (string level))))))
    (or
     (cadr-ai::json-get colors name)
     (and
      (string-equal
       (etypecase level
         (symbol (symbol-name level))
         (string level))
       "max")
      (cadr-ai::json-get
       colors "thinkingXhigh")))))

(defun dedupe-prompt-guidelines (guidelines)
  (let ((seen (make-hash-table :test #'equal))
        (result nil))
    (dolist (guideline guidelines)
      (let ((trimmed
              (string-trim
               '(#\Space #\Tab #\Newline #\Return)
               guideline)))
        (when (and
               (plusp (length trimmed))
               (not (gethash trimmed seen)))
          (setf (gethash trimmed seen) t)
          (push trimmed result))))
    (nreverse result)))

(defun build-system-prompt
    (&key
       (selected-tools nil selected-tools-p)
       tool-snippets
       prompt-guidelines context-files
       skills cwd custom-prompt
       append-system-prompt
       (readme-path
         "/usr/local/share/cadr/README.md")
       (docs-directory
         "/usr/local/share/cadr/docs")
       (examples-directory
         "/usr/local/share/cadr/examples"))
  (let* ((selected
           (if selected-tools-p
               selected-tools
               '("read" "bash" "edit" "write")))
         (described
           (remove-if-not
            (lambda (name)
              (assoc name tool-snippets
                     :test #'string=))
            selected))
         (guidelines
           (dedupe-prompt-guidelines
            (append
             (when
                 (and
                  (member "bash" selected
                          :test #'string=)
                  (not
                   (intersection
                    '("grep" "find" "ls")
                    selected
                    :test #'string=)))
               (list
                "Use bash for file operations like ls, rg, find"))
             prompt-guidelines
             (list
              "Be concise in your responses"
              "Show file paths clearly when working with files")))))
    (with-output-to-string (output)
      (if custom-prompt
          (write-string custom-prompt output)
          (progn
            (write-string
             "You are an expert coding assistant operating inside cadr, a coding agent harness. You help users by reading files, executing commands, editing code, and writing new files."
             output)
            (terpri output)
            (terpri output)
            (format output "Available tools:~%")
            (if described
                (dolist (name described)
                  (format
                   output "- ~A: ~A~%"
                   name
                   (cdr
                    (assoc name tool-snippets
                           :test #'string=))))
                (format output "(none)~%"))
            (format
             output
             "~%In addition to the tools above, you may have access to other custom tools depending on the project.~%~%Guidelines:~%")
            (dolist (guideline guidelines)
              (format output "- ~A~%" guideline))
            (format
             output
             "~%Cadr documentation (read only when the user asks about cadr itself, its SDK, extensions, themes, skills, or TUI):~%- Main documentation: ~A~%- Additional docs: ~A~%- Examples: ~A (extensions, custom tools, SDK)~%"
             readme-path docs-directory
             examples-directory)
            (format
             output
             "- When reading cadr docs or examples, resolve docs/... under Additional docs and examples/... under Examples, not the current working directory~%- When asked about: extensions (docs/extensions.md, examples/extensions/), themes (docs/themes.md), skills (docs/skills.md), prompt templates (docs/prompt-templates.md), TUI components (docs/tui.md), keybindings (docs/keybindings.md), SDK integrations (docs/sdk.md), custom providers (docs/custom-provider.md), adding models (docs/models.md), cadr packages (docs/packages.md), environment variables (docs/environment-variables.md)~%- When working on cadr topics, read the docs and examples, and follow .md cross-references before implementing~%- Always read cadr .md files completely and follow links to related docs (e.g., tui.md for TUI API details)")))
      (when append-system-prompt
        (format output "~%~%~A"
                append-system-prompt))
      (when context-files
        (format
         output
         "~%~%<project_context>~%~%Project-specific instructions and guidelines:~%~%")
        (dolist (context context-files)
          (let* ((path
                   (if (listp context)
                       (getf context :path)
                       context))
                 (content
                   (if (listp context)
                       (getf context :content)
                       (uiop:read-file-string
                        path :external-format :utf-8))))
            (format
             output
             "<project_instructions path=\"~A\">~%~A~%</project_instructions>~%~%"
             path content)))
        (format output "</project_context>~%"))
      (when
          (and
           (member "read" selected
                   :test #'string=)
           skills)
        (write-string
         (cadr-agent:format-skills-for-system-prompt
          skills)
         output))
      (format output
              "~%Current working directory: ~A"
              (or cwd ".")))))

(defun provider-header-table (headers)
  (let ((table
          (make-hash-table :test #'equalp)))
    (dolist (header headers table)
      (setf
       (gethash (car header) table)
       (cdr header)))))

(defun provider-header-alist (table)
  (let ((headers nil))
    (maphash
     (lambda (name value)
       (when value
         (push (cons name value)
               headers)))
     table)
    (nreverse headers)))

(defun make-extension-aware-stream-function
    (extension-host
     &key
       (stream-function #'cadr-ai:stream-chat)
       session-id
       (telemetry-p t))
  (lambda
      (provider model context on-event
       &rest options)
    (let ((callbacks
            (list
             :on-payload
             (lambda (payload callback-model)
               (declare (ignore callback-model))
               (values
                (if extension-host
                    (cadr-agent::run-extension-lifecycle-hooks
                     extension-host
                     :before-provider-request
                     :payload
                     (list :payload payload))
                    payload)
                t))
             :transform-headers
             (lambda (request-headers)
               (let* ((merged
                        (provider-attribution-headers
                         :provider
                         (cadr-ai:model-provider model)
                         :base-url
                         (cadr-ai:model-base-url model)
                         :telemetry-p telemetry-p
                         :session-id session-id
                         :request-headers
                         request-headers))
                      (table
                        (provider-header-table
                         merged)))
                 (when extension-host
                   (cadr-agent::run-extension-lifecycle-hooks
                    extension-host
                    :before-provider-headers
                    :payload
                    (list :headers table)))
                 (provider-header-alist table)))
             :on-response
             (lambda (response callback-model)
               (declare (ignore callback-model))
               (when extension-host
                 (cadr-agent::run-extension-lifecycle-hooks
                  extension-host
                  :after-provider-response
                  :payload response))))))
      (apply
       stream-function
       provider model context on-event
       (append options callbacks)))))

;;; In-process SDK service facades.  These objects deliberately wrap the same
;;; settings, resource, auth, and model services used by the CLI; they do not
;;; invoke the command-line entry point or start a child cadr process.

(defclass sdk-settings-manager ()
  ((backend
    :initarg :backend
    :reader sdk-settings-manager-backend)
   (overrides
    :initarg :overrides
    :initform (empty-json-object)
    :accessor sdk-settings-manager-overrides)))

(defun make-sdk-settings-manager
    (&key global-path project-path
          (project-trusted-p t))
  (make-instance
   'sdk-settings-manager
   :backend
   (make-settings-manager
    :global-path global-path
    :project-path project-path
    :project-trusted-p project-trusted-p)))

(defun make-memory-sdk-settings-manager
    (&optional initial)
  (make-instance
   'sdk-settings-manager
   :backend
   (make-memory-settings-manager initial)))

(defun sdk-settings-effective-object (manager)
  (merge-json-objects
   (settings-effective-object
    (sdk-settings-manager-backend manager))
   (sdk-settings-manager-overrides manager)))

(defun sdk-settings-value
    (manager key &optional default)
  (cadr-ai::json-get
   (sdk-settings-effective-object manager)
   key default))

(defun sdk-settings-apply-overrides
    (manager overrides)
  (unless (hash-table-p overrides)
    (error
     'cadr-ai:configuration-error
     :message "SDK settings overrides must be a JSON object"))
  (setf
   (sdk-settings-manager-overrides manager)
   (merge-json-objects
    (sdk-settings-manager-overrides manager)
    overrides))
  manager)

(defun sdk-settings-set
    (manager key value &key (scope :global))
  (settings-set
   (sdk-settings-manager-backend manager)
   key value :scope scope))

(defun sdk-settings-remove
    (manager key &key (scope :global))
  (settings-remove
   (sdk-settings-manager-backend manager)
   key :scope scope))

(defun sdk-settings-reload (manager)
  (settings-reload
   (sdk-settings-manager-backend manager))
  manager)

(defun sdk-settings-flush (manager)
  ;; The native backend writes synchronously and atomically.  Keep the SDK
  ;; durability boundary explicit even though there is no pending promise.
  manager)

(defun sdk-settings-drain-errors (manager)
  (settings-drain-errors
   (sdk-settings-manager-backend manager)))

(defun sdk-nonempty-setting-string
    (manager key)
  (let ((value (sdk-settings-value manager key)))
    (and (stringp value)
         (plusp (length value))
         value)))

(defun sdk-settings-default-provider (manager)
  (sdk-nonempty-setting-string
   manager "defaultProvider"))

(defun sdk-settings-default-model (manager)
  (sdk-nonempty-setting-string
   manager "defaultModel"))

(defun sdk-settings-default-thinking-level
    (manager)
  (let ((value
          (sdk-settings-value
           manager "defaultThinkingLevel"
           "medium")))
    (if (and (stringp value)
             (valid-thinking-level-p value))
        (intern (string-upcase value) :keyword)
        +default-thinking-level+)))

(defun sdk-settings-boolean
    (manager key default &optional nested-key)
  (let ((value (sdk-settings-value manager key :missing)))
    (when (and nested-key (hash-table-p value))
      (setf value
            (cadr-ai::json-get
             value nested-key :missing)))
    (if (eq value :missing)
        default
        (eq value t))))

(defun sdk-settings-compaction-enabled-p
    (manager)
  (sdk-settings-boolean
   manager "compaction" t "enabled"))

(defun sdk-settings-enabled-tools (manager)
  (let ((value
          (sdk-settings-value manager "tools" nil)))
    (cond
      ((vectorp value) (coerce value 'list))
      ((and (listp value)
            (every #'stringp value))
       (copy-list value))
      (t nil))))

(defun sdk-settings-retry-settings (manager)
  (let* ((retry
           (sdk-settings-value
            manager "retry" (empty-json-object)))
         (provider
           (and (hash-table-p retry)
                (cadr-ai::json-get
                 retry "provider"
                 (empty-json-object))))
         (source
           (if (hash-table-p provider)
               (merge-json-objects retry provider)
               retry)))
    (list
     :enabled-p
     (if (hash-table-p source)
         (eq t (cadr-ai::json-get source "enabled" t))
         t)
     :max-retries
     (if (hash-table-p source)
         (cadr-ai::json-get source "maxRetries" 3)
         3)
     :base-delay-ms
     (if (hash-table-p source)
         (cadr-ai::json-get source "baseDelayMs" 2000)
         2000)
     :max-retry-delay-ms
     (if (hash-table-p source)
         (cadr-ai::json-get
          source "maxRetryDelayMs" 60000)
         60000)
     :timeout-ms
     (if (hash-table-p source)
         (cadr-ai::json-get source "timeoutMs")
         nil))))

(defun sdk-settings-http-idle-timeout-ms
    (manager)
  (let ((value
          (sdk-settings-value
           manager "httpIdleTimeoutMs" 300000)))
    (unless (and (integerp value) (>= value 0))
      (error
       'cadr-ai:configuration-error
       :message
       (format nil
               "Invalid httpIdleTimeoutMs setting: ~S"
               value)))
    value))

(defclass sdk-resource-loader ()
  ((cwd
    :initarg :cwd
    :reader sdk-resource-loader-cwd)
   (agent-directory
    :initarg :agent-directory
    :reader sdk-resource-loader-agent-directory)
   (settings-manager
    :initarg :settings-manager
    :reader sdk-resource-loader-settings-manager)
   (core-loader
    :initarg :core-loader
    :reader sdk-resource-loader-core-loader)
   (extension-manager
    :initarg :extension-manager
    :reader sdk-resource-loader-extension-manager)
   (system-prompt-source
    :initarg :system-prompt-source
    :initform :discover
    :reader sdk-resource-loader-system-prompt-source)
   (append-system-prompt-source
    :initarg :append-system-prompt-source
    :initform :discover
    :reader sdk-resource-loader-append-system-prompt-source)
   (system-prompt-override
    :initarg :system-prompt-override
    :initform nil
    :reader sdk-resource-loader-system-prompt-override)
   (append-system-prompt-override
    :initarg :append-system-prompt-override
    :initform nil
    :reader sdk-resource-loader-append-system-prompt-override)
   (skills-override
    :initarg :skills-override
    :initform nil
    :reader sdk-resource-loader-skills-override)
   (prompts-override
    :initarg :prompts-override
    :initform nil
    :reader sdk-resource-loader-prompts-override)
   (themes-override
    :initarg :themes-override
    :initform nil
    :reader sdk-resource-loader-themes-override)
   (context-files-override
    :initarg :context-files-override
    :initform nil
    :reader sdk-resource-loader-context-files-override)
   (snapshot
    :initform nil
    :accessor sdk-resource-loader-snapshot)
   (extension-report
    :initform nil
    :accessor sdk-resource-loader-extension-report)
   (skills
    :initform nil
    :accessor sdk-resource-loader-skills)
   (prompts
    :initform nil
    :accessor sdk-resource-loader-prompts)
   (themes
    :initform nil
    :accessor sdk-resource-loader-themes)
   (context-files
    :initform nil
    :accessor sdk-resource-loader-context-files)
   (system-prompt
    :initform nil
    :accessor sdk-resource-loader-system-prompt)
   (append-system-prompt
    :initform nil
    :accessor sdk-resource-loader-append-system-prompt)
   (diagnostics
    :initform nil
    :accessor sdk-resource-loader-diagnostics)))

(defun make-sdk-resource-loader
    (&key
       (cwd (uiop:getcwd))
       (agent-directory
         (merge-pathnames
          ".cadr/" (user-homedir-pathname)))
       settings-manager
       additional-extension-paths
       extension-factories
       additional-skill-paths
       additional-prompt-paths
       additional-theme-paths
       no-extensions-p no-skills-p no-prompts-p
       no-themes-p no-context-files-p
       (project-trusted-p t)
       (system-prompt nil system-prompt-p)
       (append-system-prompt nil append-system-prompt-p)
       system-prompt-override
       append-system-prompt-override
       skills-override prompts-override themes-override
       context-files-override
       (output (make-broadcast-stream)))
  (let* ((resolved-cwd
           (uiop:ensure-directory-pathname
            (uiop:ensure-absolute-pathname cwd)))
         (resolved-agent
           (uiop:ensure-directory-pathname
            (uiop:ensure-absolute-pathname
             agent-directory)))
         (settings
           (or settings-manager
               (make-sdk-settings-manager
                :global-path
                (merge-pathnames
                 "settings.json" resolved-agent)
                :project-path
                (merge-pathnames
                 ".cadr/settings.json"
                 resolved-cwd)
                :project-trusted-p
                project-trusted-p)))
         (extension-manager
           (make-cli-extension-manager
            :cwd resolved-cwd
            :global-directory
            (merge-pathnames
             "extensions/" resolved-agent)
            :explicit-paths
            additional-extension-paths
            :extension-factories extension-factories
            :no-discovery-p no-extensions-p
            :output output
            :mode :sdk))
         (core-loader
           (make-default-resource-loader
            :cwd resolved-cwd
            :agent-directory resolved-agent
            :project-trusted-p project-trusted-p
            :no-context-files-p no-context-files-p
            :no-skills-p no-skills-p
            :no-prompts-p no-prompts-p
            :no-themes-p no-themes-p
            :explicit-skill-paths
            additional-skill-paths
            :explicit-prompt-paths
            additional-prompt-paths
            :explicit-theme-paths
            additional-theme-paths
            :extension-host
            (cli-extension-manager-host
             extension-manager))))
    (apply
     #'make-instance 'sdk-resource-loader
     :cwd resolved-cwd
     :agent-directory resolved-agent
     :settings-manager settings
     :extension-manager extension-manager
     :core-loader core-loader
     :system-prompt-override system-prompt-override
     :append-system-prompt-override
     append-system-prompt-override
     :skills-override skills-override
     :prompts-override prompts-override
     :themes-override themes-override
     :context-files-override context-files-override
     (append
      (when system-prompt-p
        (list :system-prompt-source system-prompt))
      (when append-system-prompt-p
        (list :append-system-prompt-source
              append-system-prompt))))))

(defun sdk-resolve-prompt-input (input)
  (cond
    ((null input) nil)
    ((pathnamep input)
     (uiop:read-file-string input
                            :external-format :utf-8))
    ((and (stringp input) (probe-file input))
     (uiop:read-file-string input
                            :external-format :utf-8))
    ((stringp input) input)
    (t
     (error
      'cadr-ai:configuration-error
      :message
      (format nil "Invalid system prompt input: ~S"
              input)))))

(defun sdk-context-file-records (paths)
  (mapcar
   (lambda (path)
     (list
      :path path
      :content
      (uiop:read-file-string
       path :external-format :utf-8)))
   paths))

(defun sdk-apply-resource-list-override
    (function items diagnostics)
  (if function
      (multiple-value-bind
            (next-items next-diagnostics)
          (funcall function
                   (copy-list items)
                   (copy-list diagnostics))
        (values
         (or next-items nil)
         (if (null next-diagnostics)
             diagnostics
             next-diagnostics)))
      (values items diagnostics)))

(defgeneric sdk-resource-loader-reload (loader))

(defmethod sdk-resource-loader-reload
    ((loader sdk-resource-loader))
  (let* ((report
           (reload-cli-extensions
            (sdk-resource-loader-extension-manager
             loader)))
         (snapshot
           (reload-resources
            (sdk-resource-loader-core-loader
             loader)))
         (diagnostics
           (append
            (copy-list
             (resource-snapshot-diagnostics
              snapshot))
            (copy-list (getf report :errors))))
         (context-files
           (sdk-context-file-records
            (resource-snapshot-context-files
             snapshot)))
         (system-source
           (sdk-resource-loader-system-prompt-source
            loader))
         (append-source
           (sdk-resource-loader-append-system-prompt-source
            loader))
         (system
           (sdk-resolve-prompt-input
            (if (eq system-source :discover)
                (resource-snapshot-system-prompt-path
                 snapshot)
                system-source)))
         (append-prompts
           (if (eq append-source :discover)
               (let ((path
                       (resource-snapshot-append-system-prompt-path
                        snapshot)))
                 (if path
                     (list
                      (sdk-resolve-prompt-input path))
                     nil))
               (mapcar
                #'sdk-resolve-prompt-input
                (etypecase append-source
                  (null nil)
                  (list append-source)
                  ((or string pathname)
                   (list append-source)))))))
    (multiple-value-bind (skills skill-diagnostics)
        (sdk-apply-resource-list-override
         (sdk-resource-loader-skills-override loader)
         (resource-snapshot-skills snapshot)
         diagnostics)
      (multiple-value-bind (prompts prompt-diagnostics)
          (sdk-apply-resource-list-override
           (sdk-resource-loader-prompts-override loader)
           (resource-snapshot-prompts snapshot)
           skill-diagnostics)
        (multiple-value-bind (themes final-diagnostics)
            (sdk-apply-resource-list-override
             (sdk-resource-loader-themes-override loader)
             (resource-snapshot-themes snapshot)
             prompt-diagnostics)
          (setf
           (sdk-resource-loader-extension-report loader)
           report
           (sdk-resource-loader-snapshot loader)
           snapshot
           (sdk-resource-loader-skills loader)
           skills
           (sdk-resource-loader-prompts loader)
           prompts
           (sdk-resource-loader-themes loader)
           themes
           (sdk-resource-loader-context-files loader)
           (if
               (sdk-resource-loader-context-files-override
                loader)
               (funcall
                (sdk-resource-loader-context-files-override
                 loader)
                (copy-tree context-files))
               context-files)
           (sdk-resource-loader-system-prompt loader)
           (if
               (sdk-resource-loader-system-prompt-override
                loader)
               (funcall
                (sdk-resource-loader-system-prompt-override
                 loader)
                system)
               system)
           (sdk-resource-loader-append-system-prompt
            loader)
           (if
               (sdk-resource-loader-append-system-prompt-override
                loader)
               (funcall
                (sdk-resource-loader-append-system-prompt-override
                 loader)
                (copy-list append-prompts))
               append-prompts)
           (sdk-resource-loader-diagnostics loader)
           final-diagnostics)))))
  loader)

(defgeneric sdk-resource-loader-extensions (loader))

(defmethod sdk-resource-loader-extensions
    ((loader sdk-resource-loader))
  (let ((report
          (sdk-resource-loader-extension-report
           loader))
        (manager
          (sdk-resource-loader-extension-manager
           loader)))
    (list
     :loaded (getf report :loaded 0)
     :active (getf report :active 0)
     :errors (copy-list (getf report :errors))
     :runtime
     (cli-extension-manager-host manager))))

(defgeneric sdk-resource-loader-extend-resources
    (loader &key skill-paths prompt-paths theme-paths))

(defmethod sdk-resource-loader-extend-resources
    ((loader sdk-resource-loader)
     &key skill-paths prompt-paths theme-paths)
  (let ((core
          (sdk-resource-loader-core-loader loader)))
    (setf
     (default-resource-loader-explicit-skill-paths core)
     (append
      (default-resource-loader-explicit-skill-paths core)
      skill-paths)
     (default-resource-loader-explicit-prompt-paths core)
     (append
      (default-resource-loader-explicit-prompt-paths core)
      prompt-paths)
     (default-resource-loader-explicit-theme-paths core)
     (append
      (default-resource-loader-explicit-theme-paths core)
      theme-paths)))
  (sdk-resource-loader-reload loader))

(defgeneric sdk-resource-loader-extension-host
    (loader))

(defmethod sdk-resource-loader-extension-host
    ((loader sdk-resource-loader))
  (cli-extension-manager-host
   (sdk-resource-loader-extension-manager
    loader)))

(defclass sdk-model-runtime ()
  ((registry
    :initarg :registry
    :reader sdk-model-runtime-registry)
   (credentials
    :initarg :credentials
    :reader sdk-model-runtime-credentials)
   (persistent-storage
    :initarg :persistent-storage
    :reader sdk-model-runtime-persistent-storage)
   (native-runtime
    :initarg :native-runtime
    :reader sdk-model-runtime-native-runtime)
   (lock
    :initform
    (sb-thread:make-mutex
     :name "cadr SDK model runtime")
    :reader sdk-model-runtime-lock)))

(defun sdk-copy-credential-into-store
    (store provider credential)
  (let ((provider-id
          (provider-symbol-from-key provider)))
    (if credential
        (cadr-ai:credential-store-modify
         store provider-id
         (lambda (current)
           (declare (ignore current))
           (credential-with-provider
            credential provider-id)))
        (cadr-ai:credential-store-delete
         store provider-id))))

(defun sdk-seed-native-credentials (runtime)
  (let* ((credentials
           (sdk-model-runtime-credentials runtime))
         (store
           (cadr-ai::models-runtime-credential-store
            (sdk-model-runtime-native-runtime
             runtime))))
    (dolist (entry (auth-storage-list credentials))
      (sdk-copy-credential-into-store
       store (car entry)
       (auth-storage-read credentials (car entry)))))
  runtime)

(defun make-sdk-model-runtime
    (&key
       (auth-path (default-auth-path))
       (models-path
         (merge-pathnames
          "models.json"
          (uiop:pathname-directory-pathname
           (default-auth-path))))
       credential-storage environment)
  (let* ((persistent
           (or credential-storage
               (make-file-auth-storage auth-path)))
         (credentials
           (make-runtime-credentials persistent))
         (native
           (cadr-ai:make-built-in-models-runtime
            :credential-store
            (cadr-ai:make-memory-credential-store)
            :environment environment))
         (registry
           (make-model-registry
            :path models-path
            :credentials credentials))
         (runtime
           (make-instance
            'sdk-model-runtime
            :registry registry
            :credentials credentials
            :persistent-storage persistent
            :native-runtime native)))
    (sdk-seed-native-credentials runtime)
    runtime))

(defun sdk-model-runtime-providers (runtime)
  (cadr-ai:models-runtime-providers
   (sdk-model-runtime-native-runtime runtime)))

(defun sdk-model-runtime-models
    (runtime &optional provider)
  (let* ((native
           (cadr-ai:models-runtime-models
            (sdk-model-runtime-native-runtime runtime)
            (and provider
                 (provider-symbol-from-key provider))))
         (native-provider-ids
           (mapcar
            #'cadr-ai:runtime-provider-id
            (sdk-model-runtime-providers runtime)))
         (configured
           (remove-if
            (lambda (model)
              (or
               (member
                (cadr-ai:model-provider model)
                native-provider-ids)
               (and provider
                    (not
                     (eq
                      (cadr-ai:model-provider model)
                      (provider-symbol-from-key
                       provider))))))
            (model-registry-all
             (sdk-model-runtime-registry runtime)))))
    (append native configured)))

(defun sdk-model-runtime-model
    (runtime provider model-id)
  (or
   (cadr-ai:models-runtime-model
    (sdk-model-runtime-native-runtime runtime)
    (provider-symbol-from-key provider)
    model-id)
   (model-registry-find
    (sdk-model-runtime-registry runtime)
    provider model-id)))

(defun sdk-model-runtime-register-provider
    (runtime provider)
  (sb-thread:with-mutex
      ((sdk-model-runtime-lock runtime))
    (cadr-ai:models-runtime-set-provider
     (sdk-model-runtime-native-runtime runtime)
     provider)
    (let ((credential
            (auth-storage-read
             (sdk-model-runtime-credentials runtime)
             (cadr-ai:runtime-provider-id provider))))
      (sdk-copy-credential-into-store
       (cadr-ai::models-runtime-credential-store
        (sdk-model-runtime-native-runtime runtime))
       (cadr-ai:runtime-provider-id provider)
       credential)))
  provider)

(defun sdk-model-runtime-check-auth
    (runtime provider)
  (sb-thread:with-mutex
      ((sdk-model-runtime-lock runtime))
    (cadr-ai:models-runtime-check-auth
     (sdk-model-runtime-native-runtime runtime)
     (provider-symbol-from-key provider))))

(defun sdk-sync-refreshed-oauth
    (runtime provider)
  (let* ((provider-id
           (provider-symbol-from-key provider))
         (store
           (cadr-ai::models-runtime-credential-store
            (sdk-model-runtime-native-runtime runtime)))
         (credential
           (cadr-ai:credential-store-read
            store provider-id)))
    (when (typep credential 'cadr-ai:oauth-credential)
      (auth-storage-modify
       (sdk-model-runtime-persistent-storage runtime)
       provider-id
       (lambda (current)
         (declare (ignore current))
         credential))))
  runtime)

(defun sdk-model-runtime-auth
    (runtime provider-or-model
     &key api-key environment)
  (sb-thread:with-mutex
      ((sdk-model-runtime-lock runtime))
    (let ((auth
            (cadr-ai:models-runtime-auth
             (sdk-model-runtime-native-runtime runtime)
             (if (typep provider-or-model 'cadr-ai:model)
                 provider-or-model
                 (provider-symbol-from-key
                  provider-or-model))
             :api-key api-key
             :environment environment)))
      (sdk-sync-refreshed-oauth
       runtime
       (if (typep provider-or-model 'cadr-ai:model)
           (cadr-ai:model-provider provider-or-model)
           provider-or-model))
      auth)))

(defun sdk-model-runtime-set-api-key
    (runtime provider key)
  (unless (and (stringp key) (plusp (length key)))
    (error
     'cadr-ai:configuration-error
     :message "Runtime API key must not be empty"))
  (sb-thread:with-mutex
      ((sdk-model-runtime-lock runtime))
    (runtime-credentials-set-api-key
     (sdk-model-runtime-credentials runtime)
     provider key)
    (sdk-copy-credential-into-store
     (cadr-ai::models-runtime-credential-store
      (sdk-model-runtime-native-runtime runtime))
     provider
     (auth-storage-read
      (sdk-model-runtime-credentials runtime)
      provider)))
  key)

(defun sdk-model-runtime-remove-api-key
    (runtime provider)
  (sb-thread:with-mutex
      ((sdk-model-runtime-lock runtime))
    (runtime-credentials-remove-api-key
     (sdk-model-runtime-credentials runtime)
     provider)
    (sdk-copy-credential-into-store
     (cadr-ai::models-runtime-credential-store
      (sdk-model-runtime-native-runtime runtime))
     provider
     (auth-storage-read
      (sdk-model-runtime-credentials runtime)
      provider)))
  nil)

(defun sdk-model-runtime-login
    (runtime provider auth-type interaction)
  (sb-thread:with-mutex
      ((sdk-model-runtime-lock runtime))
    (let* ((provider-id
             (provider-symbol-from-key provider))
           (credential
             (cadr-ai:models-runtime-login
              (sdk-model-runtime-native-runtime runtime)
              provider-id auth-type interaction)))
      (auth-storage-modify
       (sdk-model-runtime-persistent-storage runtime)
       provider-id
       (lambda (current)
         (declare (ignore current))
         credential))
      credential)))

(defun sdk-model-runtime-refresh
    (runtime &key (allow-network t) force abort-p)
  (sb-thread:with-mutex
      ((sdk-model-runtime-lock runtime))
    (sdk-seed-native-credentials runtime)
    (let ((result
            (cadr-ai:models-runtime-refresh
             (sdk-model-runtime-native-runtime runtime)
             :allow-network allow-network
             :force force :abort-p abort-p)))
      (dolist
          (provider
           (sdk-model-runtime-providers runtime))
        (sdk-sync-refreshed-oauth
         runtime
         (cadr-ai:runtime-provider-id provider)))
      (refresh-model-registry
       (sdk-model-runtime-registry runtime))
      result)))

(defun sdk-model-runtime-available-models
    (runtime &optional provider)
  (sb-thread:with-mutex
      ((sdk-model-runtime-lock runtime))
    (let* ((provider-id
             (and provider
                  (provider-symbol-from-key provider)))
           (native
             (cadr-ai:models-runtime-available-models
              (sdk-model-runtime-native-runtime runtime)
              provider-id))
           (native-provider-ids
             (mapcar
              #'cadr-ai:runtime-provider-id
              (sdk-model-runtime-providers runtime)))
           (configured
             (remove-if
              (lambda (model)
                (or
                 (member
                  (cadr-ai:model-provider model)
                  native-provider-ids)
                 (and provider-id
                      (not
                       (eq provider-id
                           (cadr-ai:model-provider
                            model))))))
              (model-registry-available-models
               (sdk-model-runtime-registry runtime)))))
      (append native configured))))

(defun sdk-model-runtime-list-credentials (runtime)
  (auth-storage-list
   (sdk-model-runtime-credentials runtime)))

(defun sdk-model-runtime-provider-config
    (runtime model &key allow-missing-auth-p)
  (let* ((provider-id
           (cadr-ai:model-provider model))
         (native-provider
           (cadr-ai:models-runtime-provider
            (sdk-model-runtime-native-runtime runtime)
            provider-id)))
    (if native-provider
        (let ((auth
                (sdk-model-runtime-auth runtime model)))
          (when (and (null auth)
                     (not allow-missing-auth-p))
            (error
             'cadr-ai:configuration-error
             :message
             (format nil
                     "No authentication configured for provider ~A"
                     (provider-key provider-id))))
          (make-provider-config
           :name (provider-key provider-id)
           :provider
           (funcall
            (model-provider-constructor
             (cadr-ai:model-api model))
            :api-key
            (and auth
                 (cadr-ai:runtime-auth-result-api-key
                  auth))
            :provider-id provider-id
            :authentication-required-p nil)
           :model
           (if (and auth
                    (cadr-ai:runtime-auth-result-base-url
                     auth))
               (copy-model-with-overrides
                model :base-url
                (cadr-ai:runtime-auth-result-base-url
                 auth))
               model)
           :auth-source
           (if auth :sdk-runtime :none)))
        (provider-config-for-model
         (sdk-model-runtime-registry runtime)
         model
         :allow-missing-auth-p
         allow-missing-auth-p))))

(defun sdk-model-runtime-stream-function (runtime)
  (lambda (provider model context on-event
           &rest options)
    (declare (ignore provider))
    (apply
     #'cadr-ai:models-runtime-stream
     (sdk-model-runtime-native-runtime runtime)
     model context on-event options)))
