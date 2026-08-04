(require :asdf)

(defparameter *render-diff-arguments* (uiop:command-line-arguments))

(when (< (length *render-diff-arguments*) 6)
  (format *error-output*
          "usage: cadr-driver.lisp PROJECT QUICKLISP MANIFEST SCENARIO CWD AGENT-DIR~%")
  (uiop:quit 2))

(let* ((project
         (uiop:ensure-directory-pathname
          (pathname (first *render-diff-arguments*))))
       (quicklisp (pathname (second *render-diff-arguments*)))
       (sink (make-broadcast-stream)))
  (let ((*standard-output* sink)
        (*error-output* sink)
        (*trace-output* sink))
    (load quicklisp)
    (dolist (name '("cadr-core.asd" "cadr-ai.asd" "cadr-agent.asd"
                    "cadr-tui.asd" "cadr-cli.asd"))
      (asdf:load-asd (truename (merge-pathnames name project))))
    (asdf:load-system "cadr-cli")))

(defpackage #:goal15-render-diff-cadr-driver
  (:use #:cl))

(in-package #:goal15-render-diff-cadr-driver)

(defconstant +fixed-timestamp+ 1700000000000)

(defun json-get (object key &optional default)
  (if (hash-table-p object)
      (multiple-value-bind (value present-p) (gethash key object)
        (if present-p value default))
      default))

(defun json-vector-list (value)
  (if (vectorp value) (coerce value 'list) nil))

(defun find-scenario (manifest scenario-id)
  (or
   (find scenario-id
         (json-vector-list (json-get manifest "scenarios"))
         :test #'string=
         :key (lambda (candidate) (json-get candidate "id")))
   (error "Unknown render-diff scenario: ~A" scenario-id)))

(defun stop-reason (value)
  (cond
    ((or (null value) (string= value "stop")) :stop)
    ((string= value "toolUse") :tool-use)
    ((string= value "length") :length)
    ((string= value "error") :error)
    ((string= value "aborted") :aborted)
    (t (error "Unsupported faux stop reason: ~A" value))))

(defun response-block (spec)
  (let ((type (json-get spec "type")))
    (cond
      ((string= type "text")
       (cadr-ai:faux-text (json-get spec "text" "")))
      ((string= type "thinking")
       (cadr-ai:faux-thinking (json-get spec "text" "")))
      ((string= type "toolCall")
       (cadr-ai:faux-tool-call
        (json-get spec "name" "")
        (or (json-get spec "arguments") (cadr-ai::json-object))
        :id (json-get spec "id")))
      (t (error "Unsupported faux block type: ~A" type)))))

(defun response-message (spec)
  (cadr-ai:faux-assistant-message
   (mapcar #'response-block
           (json-vector-list (json-get spec "content")))
   :stop-reason (stop-reason (json-get spec "stopReason"))
   :error-message (json-get spec "errorMessage")
   :response-id "render-diff-response"
   :timestamp +fixed-timestamp+))

(defun write-ready-marker ()
  (let ((path (uiop:getenv "RENDER_DIFF_READY_PATH")))
    (when (and path (plusp (length path)))
      (with-open-file (stream path :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
        (write-line "ready" stream)
        (finish-output stream)))))

(defun seed-message (spec index)
  (let ((role (json-get spec "role"))
        (text (json-get spec "text" ""))
        (timestamp (+ +fixed-timestamp+ index)))
    (cond
      ((string= role "user")
       (cadr-ai:make-user-message
        :content text :timestamp timestamp))
      ((string= role "assistant")
       (cadr-ai:make-assistant-message
        :content (list (cadr-ai:make-text-content :text text))
        :api :faux :provider :faux :model "faux-1"
        :usage (cadr-ai:make-usage)
        :stop-reason :stop
        :response-id (format nil "render-seed-~D" index)
        :timestamp timestamp))
      (t (error "Unsupported seed role: ~A" role)))))

(defun append-seed-messages (session setup)
  (loop for spec in
          (json-vector-list (json-get setup "seedMessages"))
        for index from 0
        do (cadr-agent:session-append-message
            session (seed-message spec index)))
  session)

(defun make-render-session (cwd agent-dir scenario)
  (let* ((setup (json-get scenario "setup"))
         (persistent-p
           (not (null (json-get setup "persistentSession"))))
         (directory
           (uiop:ensure-directory-pathname
            (merge-pathnames "render-sessions/" agent-dir)))
         (session
           (cadr-agent:create-session
            :directory directory
            :cwd cwd
            :id "render-session"
            :timestamp +fixed-timestamp+))
         (sessions (list session)))
    (append-seed-messages session setup)
    (when persistent-p
      (let ((other
              (cadr-agent:create-session
               :directory directory
               :cwd cwd
               :id "other-session"
               :timestamp +fixed-timestamp+)))
        (dolist
            (message
             (list
              (cadr-ai:make-user-message
               :content "other session question"
               :timestamp +fixed-timestamp+)
              (cadr-ai:make-assistant-message
               :content
               (list
                (cadr-ai:make-text-content
                 :text "other session answer"))
               :api :faux :provider :faux :model "faux-1"
               :usage (cadr-ai:make-usage)
               :stop-reason :stop
               :timestamp (1+ +fixed-timestamp+))))
          (cadr-agent:session-append-message other message))
        (setf sessions (append sessions (list other)))))
    (values session directory persistent-p sessions)))

(defun stream-aborted-p (options)
  (cadr-core:cancellation-predicate-aborted-p
   (getf options :abort-p)))

(defun emit-stream-abort (handle model on-event)
  (let ((message
          (cadr-ai::faux-error-message
           handle model "Request was aborted" t)))
    (cadr-ai::faux-emit
     on-event :error message :reason :aborted)
    message))

(defun slow-faux-stream
    (handle model context on-event options
     chunk-characters tokens-per-second)
  (let* ((message
          (if (stream-aborted-p options)
              nil
              (cadr-ai::faux-resolve
               handle model context options)))
         (partial
           (and
            message
            (cadr-ai:make-assistant-message
             :api (cadr-ai:assistant-message-api message)
             :provider (cadr-ai:assistant-message-provider message)
             :model (cadr-ai:assistant-message-model message)
             :content nil
             :usage (cadr-ai:assistant-message-usage message)
             :stop-reason :pending
             :response-id
             (cadr-ai:assistant-message-response-id message)
             :timestamp
             (cadr-ai:assistant-message-timestamp message)))))
    (unless message
      (return-from slow-faux-stream
        (emit-stream-abort handle model on-event)))
    (when (member (cadr-ai:assistant-message-stop-reason message)
                  '(:error :aborted))
      (cadr-ai::faux-emit
       on-event :error message
       :reason (cadr-ai:assistant-message-stop-reason message))
      (return-from slow-faux-stream message))
    (cadr-ai::faux-emit on-event :start partial)
    (loop for block in (cadr-ai:assistant-message-content message)
          for index from 0
          do
          (cond
            ((typep block 'cadr-ai:text-content)
             (let* ((text (cadr-ai:text-content-text block))
                    (partial-block
                      (cadr-ai:make-text-content :text "")))
               (setf
                (cadr-ai:assistant-message-content partial)
                (append
                 (cadr-ai:assistant-message-content partial)
                 (list partial-block)))
               (cadr-ai::faux-emit
                on-event :text-start partial :content-index index)
               (loop for start from 0 below (length text)
                     by chunk-characters
                     for end = (min (length text)
                                    (+ start chunk-characters))
                     do
                     (sleep
                      (/ (max 1 (ceiling (- end start) 4))
                         (coerce tokens-per-second 'double-float)))
                     (when (stream-aborted-p options)
                       (return-from slow-faux-stream
                         (emit-stream-abort handle model on-event)))
                     (let ((chunk (subseq text start end)))
                       (setf
                        (cadr-ai:text-content-text partial-block)
                        (concatenate
                         'string
                         (cadr-ai:text-content-text partial-block)
                         chunk))
                       (cadr-ai::faux-emit
                        on-event :text-delta partial
                        :content-index index :delta chunk)))
               (cadr-ai::faux-emit
                on-event :text-end partial
                :content-index index :content text)))
            (t
             (error
              "Slow render-diff stream only supports text blocks"))))
    (cadr-ai::faux-emit
     on-event :done message
     :reason (cadr-ai:assistant-message-stop-reason message))
    message))

(defun render-models ()
  (list
   (cadr-ai:make-model
    :id "faux-1" :name "Faux Model"
    :provider :faux :api :faux
    :base-url "http://localhost:0"
    :reasoning-p t :context-window 128000
    :max-tokens 16384)
   (cadr-ai:make-model
    :id "other-1" :name "Other Model"
    :provider :other :api :openai-completions
    :base-url "https://render.invalid/v1"
    :context-window 64000 :max-tokens 8192)))

(defun render-auth-options ()
  (stable-sort
   (append
    (cadr-cli::login-provider-options
     (cadr-ai:list-provider-definitions))
    (list
     (cadr-cli::make-oauth-selector-option
      :id :render-auth :name "Render Auth"
      :auth-type :oauth
      :method-name "Render Auth account"
      :status '(:type :api-key :source "configured provider"))
     (cadr-cli::make-oauth-selector-option
      :id :render-auth :name "Render Auth"
      :auth-type :api-key
      :method-name "Render Auth API key"
      :status '(:type :api-key :source "configured provider"))))
   #'string-lessp
   :key #'cadr-cli::oauth-selector-option-name))

(defun render-session-items (sessions)
  (mapcar
   (lambda (session)
     (cadr-tui:make-select-item
      :label
      (format nil "~A  ~D messages"
              (cadr-agent:session-id session)
              (length (cadr-agent:session-messages session)))
      :value session))
   sessions))

(defun render-string-property (&optional description)
  (if description
      (cadr-ai::json-object
       "type" "string" "description" description)
      (cadr-ai::json-object "type" "string")))

(defun render-number-property (&optional description)
  (if description
      (cadr-ai::json-object
       "type" "number" "description" description)
      (cadr-ai::json-object "type" "number")))

(defun render-boolean-property (&optional description)
  (if description
      (cadr-ai::json-object
       "type" "boolean" "description" description)
      (cadr-ai::json-object "type" "boolean")))

(defun render-object-schema (properties required)
  (let ((schema
          (cadr-ai::json-object
           "type" "object"
           "properties" properties)))
    (when required
      (setf (gethash "required" schema)
            (cadr-ai::list-json-array required)))
    schema))

(defun render-baseline-tool-contract (name)
  (cond
    ((string= name "read")
     (values
      "Read the contents of a file. Supports text files and images (jpg, png, gif, webp, bmp). Images are sent as attachments. For text files, output is truncated to 2000 lines or 50KB (whichever is hit first). Use offset/limit for large files. When you need the full file, continue with offset until complete."
      (render-object-schema
       (cadr-ai::json-object
        "path" (render-string-property
                "Path to the file to read (relative or absolute)")
        "offset" (render-number-property
                  "Line number to start reading from (1-indexed)")
        "limit" (render-number-property
                 "Maximum number of lines to read"))
       '("path"))))
    ((string= name "bash")
     (values
      "Execute a bash command in the current working directory. Returns stdout and stderr. Output is truncated to last 2000 lines or 50KB (whichever is hit first). If truncated, full output is saved to a temp file. Optionally provide a timeout in seconds."
      (render-object-schema
       (cadr-ai::json-object
        "command" (render-string-property "Bash command to execute")
        "timeout" (render-number-property
                   "Timeout in seconds (optional, no default timeout)"))
       '("command"))))
    ((string= name "edit")
     (values
      "Edit a single file using exact text replacement. Every edits[].oldText must match a unique, non-overlapping region of the original file. If two changes affect the same block or nearby lines, merge them into one edit instead of emitting overlapping edits. Do not include large unchanged regions just to connect distant changes."
      (render-object-schema
       (cadr-ai::json-object
        "path" (render-string-property
                "Path to the file to edit (relative or absolute)")
        "edits"
        (let ((array
                (cadr-ai::json-object
                 "type" "array"
                 "items"
                 (render-object-schema
                  (cadr-ai::json-object
                   "oldText"
                   (render-string-property
                    "Exact text for one targeted replacement. It must be unique in the original file and must not overlap with any other edits[].oldText in the same call.")
                   "newText"
                   (render-string-property
                    "Replacement text for this targeted edit."))
                  '("oldText" "newText"))
                 "description"
                 "One or more targeted replacements. Each edit is matched against the original file, not incrementally. Do not include overlapping or nested edits. If two changes touch the same block or nearby lines, merge them into one edit instead.")))
          array))
       '("path" "edits"))))
    ((string= name "write")
     (values
      "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Automatically creates parent directories."
      (render-object-schema
       (cadr-ai::json-object
        "path" (render-string-property
                "Path to the file to write (relative or absolute)")
        "content" (render-string-property
                   "Content to write to the file"))
       '("path" "content"))))
    ((string= name "grep")
     (values
      "Search file contents for a pattern. Returns matching lines with file paths and line numbers. Respects .gitignore. Output is truncated to 100 matches or 50KB (whichever is hit first). Long lines are truncated to 500 chars."
      (render-object-schema
       (cadr-ai::json-object
        "pattern" (render-string-property
                   "Search pattern (regex or literal string)")
        "path" (render-string-property
                "Directory or file to search (default: current directory)")
        "glob" (render-string-property
                "Filter files by glob pattern, e.g. '*.ts' or '**/*.spec.ts'")
        "ignoreCase" (render-boolean-property
                      "Case-insensitive search (default: false)")
        "literal" (render-boolean-property
                   "Treat pattern as literal string instead of regex (default: false)")
        "context" (render-number-property
                   "Number of lines to show before and after each match (default: 0)")
        "limit" (render-number-property
                 "Maximum number of matches to return (default: 100)"))
       '("pattern"))))
    ((string= name "find")
     (values
      "Search for files by glob pattern. Returns matching file paths relative to the search directory. Respects .gitignore. Output is truncated to 1000 results or 50KB (whichever is hit first)."
      (render-object-schema
       (cadr-ai::json-object
        "pattern" (render-string-property
                   "Glob pattern to match files, e.g. '*.ts', '**/*.json', or 'src/**/*.spec.ts'")
        "path" (render-string-property
                "Directory to search in (default: current directory)")
        "limit" (render-number-property
                 "Maximum number of results (default: 1000)"))
       '("pattern"))))
    ((string= name "ls")
     (values
      "List directory contents. Returns entries sorted alphabetically, with '/' suffix for directories. Includes dotfiles. Output is truncated to 500 entries or 50KB (whichever is hit first)."
      (render-object-schema
       (cadr-ai::json-object
        "path" (render-string-property
                "Directory to list (default: current directory)")
        "limit" (render-number-property
                 "Maximum number of entries to return (default: 500)"))
       nil)))
    (t (error "Missing render-diff tool contract: ~A" name))))

(defun render-tools (cwd)
  (mapcar
   (lambda (tool)
     (multiple-value-bind (description parameters)
         (render-baseline-tool-contract
          (cadr-ai:tool-name tool))
       (cadr-ai:make-tool
        :name (cadr-ai:tool-name tool)
        :description description
        :parameters parameters
        :execution-mode
        (cadr-ai::tool-execution-mode tool)
        :executor (cadr-ai::tool-executor tool))))
   (cadr-cli::make-all-coding-tools cwd)))

(defun render-baseline-cwd (cwd)
  ;; Faux usage must see byte-identical fixture context on both sides.  The
  ;; tools still execute in Cadr's real isolated cwd; only the scripted faux
  ;; provider's prompt estimate uses the peer path.
  (let* ((value (namestring cwd))
         (marker "/cadr/workspace/")
         (position (search marker value)))
    (unless position
      (error "Unexpected render-diff cwd: ~A" value))
    (concatenate
     'string
     (subseq value 0 position)
     "/pi/workspace")))

(defun command-dispatcher
    (agent cwd session-directory settings-manager
     auth-prompt-consumer status-consumer)
  (lambda (line)
    (cond
      ((string= line "/login render-auth")
       (when auth-prompt-consumer
         (funcall
          auth-prompt-consumer
          (list
           :type :manual-code
           :title "Login to Render Auth"
           :url "https://auth.invalid/authorize?state=render-fixed"
           :instructions
           "A browser window should open. Complete login to finish."
           :message
           "Paste the authorization code"
           :cancel-function (constantly nil))))
       (values t nil))
      ((string= line "/reload")
       (cadr-cli::reload-cli-runtime
        agent settings-manager
        :completion-function status-consumer)
       (values t nil))
      (t
       (let ((output (make-string-output-stream)))
         (if
             (cadr-cli::handle-session-command
              line agent
              :directory session-directory
              :cwd cwd
              :output output
              :status-function status-consumer)
             (values t (get-output-stream-string output))
             (values nil nil)))))))

(defun run-scenario (scenario cwd agent-dir)
  (multiple-value-bind
        (session session-directory persistent-p sessions)
      (make-render-session cwd agent-dir scenario)
    (let* ((stream (json-get scenario "stream"))
           (chunk-characters
             (or (json-get stream "chunkCharacters") 4096))
           (tokens-per-second
             (or (json-get stream "tokensPerSecond") 0))
           (handle
             (cadr-ai:make-faux-provider
              :model-definitions
              '((:id "faux-1" :name "Faux Model"
                 :reasoning-p nil :context-window 128000
                 :max-tokens 16384))
              :token-min 4096 :token-max 4096))
           (event-consumer nil)
           (auth-url-consumer nil)
           (auth-prompt-consumer nil)
           (status-consumer nil)
           (abort-requested-p nil)
           (settings-manager
             (cadr-cli::make-memory-settings-manager))
           (resources (cadr-cli::make-resource-snapshot))
           (tools (render-tools cwd))
           (base-stream-function
             (lambda (provider model context on-event &rest options)
               (declare (ignore provider))
               (if (plusp tokens-per-second)
                   (slow-faux-stream
                    handle model context on-event options
                    chunk-characters tokens-per-second)
                   (apply #'cadr-ai:faux-stream
                          handle model context on-event options))))
           (agent
             (cadr-agent:make-agent
              :provider :faux
              :model (cadr-ai:faux-get-model handle)
              :system-prompt
              (format
               nil
               "Render differential fixed system prompt.~%Current working directory: ~A"
               (render-baseline-cwd cwd))
              :tools tools
              :session session
              :auto-compact-p t
              :abort-p (lambda () abort-requested-p)
              :stream-function
              (cadr-cli::make-extension-aware-stream-function
               nil
               :stream-function base-stream-function
               :session-id (cadr-agent:session-id session))
              :on-event
              (lambda (event)
                (when event-consumer
                  (funcall event-consumer event))))))
      (cadr-ai:faux-set-responses
       handle
       (mapcar #'response-message
               (json-vector-list (json-get scenario "responses"))))
      (cadr-tui:set-current-theme :dark)
      (cadr-tui:set-keybindings
       (cadr-tui:make-keybindings-manager
        :user-bindings
        (cadr-cli::settings-keybindings settings-manager)))
      (multiple-value-bind (compact expanded)
          (cadr-cli::make-tui-startup-lines resources)
        (let ((main-thread sb-thread:*current-thread*)
              (crash-after-ms
                (json-get (json-get scenario "setup")
                          "crashAfterMs"))
              (scope-line
                (and
                 (string= (json-get scenario "id") "overlays-core")
                 (cadr-cli::model-scope-startup-line
                  (mapcar
                   (lambda (model)
                     (list :model model :thinking nil))
                   (render-models))
                  (cadr-tui:get-keybindings)
                  :verbose-p nil :quiet-startup-p nil))))
          (write-ready-marker)
          (when scope-line
            (write-line scope-line)
            (finish-output))
          (when crash-after-ms
            (sb-thread:make-thread
             (lambda ()
               (sleep (/ crash-after-ms 1000d0))
               (sb-thread:interrupt-thread
                main-thread
                (lambda ()
                  (error "render-diff crash sentinel"))))
             :name "render-diff-crash-trigger"))
          (cadr-cli:run-tui
           (lambda (line)
             (cadr-agent:agent-prompt
              agent line :source :interactive))
           :command-function
           (lambda (line)
             (funcall
              (command-dispatcher
               agent cwd session-directory settings-manager
               auth-prompt-consumer status-consumer)
              line))
           :set-event-consumer
           (lambda (consumer) (setf event-consumer consumer))
           :set-auth-url-consumer
           (lambda (consumer) (setf auth-url-consumer consumer))
           :set-auth-prompt-consumer
           (lambda (consumer) (setf auth-prompt-consumer consumer))
           :set-status-consumer
           (lambda (consumer) (setf status-consumer consumer))
           :abort-function
           (lambda ()
             (setf abort-requested-p t)
             (cadr-agent:agent-abort agent))
           :reset-abort-function
           (lambda () (setf abort-requested-p nil))
           :busy-input-function
           (lambda (text)
             (cadr-agent:agent-steer agent text))
           :follow-up-input-function
           (lambda (text)
             (cadr-agent:agent-follow-up agent text))
           :dequeue-function
           (lambda ()
             (multiple-value-bind (steering follow-up)
                 (cadr-agent::clear-live-agent-queues agent)
               (mapcar
                (lambda (message)
                  (cadr-ai::content-text
                   (cadr-ai:user-message-content message)))
                (append steering follow-up))))
           :model-items-function #'render-models
           :model-selector-function
           (lambda (&optional query)
             (let ((state
                     (cadr-cli::make-model-selector-state
                      :all-models (render-models)
                      :scoped-models (render-models)
                      :current-model (first (render-models))
                      :refresh-status-message
                      "Model catalogs refreshed.")))
               (cadr-cli::model-selector-set-query
                state (or query ""))))
           :settings-selector-function
           (lambda ()
             (cadr-cli::make-cli-settings-selector-state
              settings-manager agent resources
              :supports-images-p nil))
           :trust-selector-function
           (lambda ()
             (cadr-cli::make-trust-selector-state
              :cwd (namestring cwd)
              :project-trusted-p
              (not
               (null
                (json-get
                 (json-get scenario "setup")
                 "projectTrusted" t)))))
           :fork-items-function
           (lambda ()
             (list
              (cadr-tui:make-select-item
               :label "overlay question" :value "u1")))
           :session-items-function
           (lambda ()
             (render-session-items sessions))
           :all-session-items-function
           (lambda ()
             (render-session-items sessions))
           :tree-state-function
           (lambda ()
             (cadr-cli::session-tree-selector-data session))
           :login-options-function #'render-auth-options
           :model "faux-1"
           :provider "faux"
           :thinking
           (cadr-cli::model-footer-thinking-level
            (cadr-agent:agent-model agent) :high)
           :cwd
           (cadr-cli::format-cwd-for-footer
            (namestring cwd)
            (namestring (user-homedir-pathname)))
           :footer-cwd (namestring cwd)
           :available-provider-count
           (if (member (json-get scenario "id")
                       '("overlays-core" "overlays-auth")
                       :test #'string=)
               2
               1)
           :context-window 128000
           :session session
           :messages (cadr-agent:agent-messages agent)
           :project-trust-warning
           (cadr-cli::project-trust-warning-text
            (not
             (null
              (json-get
               (json-get scenario "setup")
               "projectTrusted" t)))
            cwd
            :home-directory
            (uiop:pathname-parent-directory-pathname
             agent-dir))
           :current-session-path
           (and persistent-p
                (namestring (cadr-agent:session-path session)))
           :startup-compact-lines compact
           :startup-expanded-lines expanded
           :alt-p nil
           :show-hardware-cursor-p nil))
        (when persistent-p
          (cadr-cli::write-session-resume-hint
           session session-directory
           :terminal-p t
           :default-session-directory-p nil)))
      (cadr-agent:agent-shutdown agent))))

(defun main ()
  (destructuring-bind
      (project quicklisp manifest-path scenario-id cwd-path agent-dir-path)
      (subseq cl-user::*render-diff-arguments* 0 6)
    (declare (ignore project quicklisp))
    (let* ((manifest
             (cadr-ai::parse-json
              (uiop:read-file-string manifest-path)))
           (scenario (find-scenario manifest scenario-id))
           (cwd (uiop:ensure-directory-pathname (pathname cwd-path)))
           (agent-dir
             (uiop:ensure-directory-pathname
              (pathname agent-dir-path))))
      (run-scenario scenario cwd agent-dir))))

(cadr-cli::call-with-fatal-condition-boundary #'main)
