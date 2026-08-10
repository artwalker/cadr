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

(defun json-key-present-p (object key)
  (and (hash-table-p object)
       (nth-value 1 (gethash key object))))

(defun json-vector-list (value)
  (if (vectorp value) (coerce value 'list) nil))

(defun json-double (object key)
  (coerce (json-get object key 0) 'double-float))

(defun find-scenario (manifest scenario-id)
  (or
   (find scenario-id
         (json-vector-list (json-get manifest "scenarios"))
         :test #'string=
         :key (lambda (candidate) (json-get candidate "id")))
   (error "Unknown render-diff scenario: ~A" scenario-id)))

(defun fixture-root
    (name cwd agent-directory session-directory)
  (cond
    ((string= name "workspace") cwd)
    ((string= name "agent") agent-directory)
    ((string= name "sessions") session-directory)
    ((string= name "projectConfig")
     (merge-pathnames ".cadr/" cwd))
    (t (error "Unsupported render fixture root: ~A" name))))

(defun safe-fixture-relative-pathname (value)
  (let* ((path (pathname value))
         (directory (pathname-directory path)))
    (when
        (or (uiop:absolute-pathname-p path)
            (null (pathname-name path))
            (member :up directory)
            (member :back directory))
      (error "Render fixture path must be a safe relative file: ~A"
             value))
    path))

(defun materialize-fixture-files
    (scenario cwd agent-directory session-directory)
  (dolist
      (spec
       (json-vector-list
        (json-get (json-get scenario "setup")
                  "fixtureFiles")))
    (let* ((root
             (fixture-root
              (json-get spec "root")
              cwd agent-directory session-directory))
           (path
             (merge-pathnames
              (safe-fixture-relative-pathname
               (json-get spec "path"))
              root)))
      (ensure-directories-exist path)
      (with-open-file
          (stream path :direction :output
                       :if-exists :supersede
                       :if-does-not-exist :create
                       :external-format :utf-8)
        (write-string (json-get spec "content" "") stream))))
  nil)

(defun render-resource-snapshot
    (scenario cwd agent-directory)
  (let* ((setup (json-get scenario "setup"))
         (options (json-get setup "resources")))
    (if options
        (cadr-cli::reload-resources
         (cadr-cli::make-default-resource-loader
          :cwd cwd
          :agent-directory agent-directory
          :project-trusted-p
          (not (null (json-get setup "projectTrusted" t)))
          :no-context-files-p
          (null (json-get options "contextFiles"))
          :no-skills-p
          (null (json-get options "skills"))
          :no-prompts-p
          (null (json-get options "promptTemplates"))
          :no-themes-p
          (null (json-get options "themes"))))
        (cadr-cli::make-resource-snapshot))))

(defun render-initial-notices (scenario)
  (let* ((startup
           (json-get (json-get scenario "setup") "startup"))
         (providers
           (json-vector-list
            (json-get startup "migratedProviders")))
         (fallback (json-get startup "modelFallbackMessage"))
         (notices nil))
    (when providers
      (push
       (format nil "Migrated credentials to auth.json: ~{~A~^, ~}"
               providers)
       notices))
    (when fallback
      (push fallback notices))
    (nreverse notices)))

(defun comparison-providers-enabled-p (scenario)
  (or
   (not
    (null
     (json-get (json-get scenario "setup")
               "comparisonProviders")))
   (member
    (json-get scenario "id")
    '("overlays-core" "overlays-secondary" "local-status-sweep")
    :test #'string=)))

(defun auth-provider-enabled-p (scenario)
  (or
   (not
    (null
     (json-get (json-get scenario "setup")
               "authProvider")))
   (uiop:string-prefix-p
    "overlays-auth" (json-get scenario "id"))
   (string= "overlays-logout" (json-get scenario "id"))))

(defun run-runtime-actions (agent actions)
  (dolist (action actions)
    (let ((type (json-get action "type")))
      (cond
        ((string= type "pause")
         (sleep (/ (json-get action "milliseconds" 0) 1000d0)))
        ((string= type "prompt")
         (if (json-get action "background")
             (sb-thread:make-thread
              (lambda ()
                (cadr-agent:agent-prompt
                 agent (json-get action "text" "")
                 :source :interactive))
              :name "render-diff-runtime-prompt")
             (cadr-agent:agent-prompt
              agent (json-get action "text" "")
              :source :interactive)))
        ((string= type "steer")
         (cadr-agent:agent-steer
          agent (json-get action "text" "")))
        ((string= type "followUp")
         (cadr-agent:agent-follow-up
          agent (json-get action "text" "")))
        ((string= type "compact")
         (let ((run
                 (lambda ()
                   (cadr-agent:compact-agent
                    agent :force-p t
                    :custom-instructions
                    (json-get action "customInstructions")))))
           (if (json-get action "background")
               (sb-thread:make-thread
                run :name "render-diff-runtime-compaction")
               (funcall run))))
        ((string= type "abort")
         (cadr-agent:agent-abort agent))
        ((string= type "waitForIdle")
         (cadr-agent:agent-wait-for-idle agent))
        (t
         (error "Unsupported render runtime action: ~A" type)))))
  nil)

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

(defun append-ready-marker (marker)
  (let ((path (uiop:getenv "RENDER_DIFF_READY_PATH")))
    (when (and path (plusp (length path)))
      (with-open-file (stream path :direction :output
                                  :if-exists :append
                                  :if-does-not-exist :create)
        (write-line marker stream)
        (finish-output stream)))))

(defun seed-message (spec index
                     &optional
                       (base-timestamp
                         +fixed-timestamp+))
  (let ((role (json-get spec "role"))
        (text (json-get spec "text" ""))
        (timestamp (+ base-timestamp index)))
    (cond
      ((string= role "user")
       (cadr-ai:make-user-message
        :content text :timestamp timestamp))
      ((string= role "assistant")
       (let* ((usage-spec (json-get spec "usage"))
              (cost-spec (json-get usage-spec "cost")))
         (cadr-ai:make-assistant-message
        :content (list (cadr-ai:make-text-content :text text))
        :api :faux
        :provider
        (intern (string-upcase (json-get spec "provider" "faux"))
                :keyword)
        :model (json-get spec "model" "faux-1")
        :response-model (json-get spec "responseModel")
        :usage
        (cadr-ai:make-usage
         :input (json-get usage-spec "input" 0)
         :output (json-get usage-spec "output" 0)
         :cache-read (json-get usage-spec "cacheRead" 0)
         :cache-write (json-get usage-spec "cacheWrite" 0)
         :cost
         (cadr-ai:make-cost
          :input (json-double cost-spec "input")
          :output (json-double cost-spec "output")
          :cache-read (json-double cost-spec "cacheRead")
          :cache-write (json-double cost-spec "cacheWrite")
          :total (json-double cost-spec "total")))
        :stop-reason :stop
        :response-id (format nil "render-seed-~D" index)
        :timestamp timestamp)))
      (t (error "Unsupported seed role: ~A" role)))))

(defun append-seed-messages
    (session setup
     &optional
       (base-timestamp +fixed-timestamp+))
  (loop for spec in
          (json-vector-list (json-get setup "seedMessages"))
        for index from 0
        do (cadr-agent:session-append-message
            session
            (seed-message spec index base-timestamp)))
  session)

(defun seed-entry-assistant-message (spec index)
  (let ((content
          (cond
            ((json-key-present-p spec "content")
             (mapcar
              #'response-block
              (json-vector-list (json-get spec "content"))))
            ((json-key-present-p spec "text")
             (list
              (cadr-ai:make-text-content
               :text (json-get spec "text" ""))))
            (t nil))))
    (cadr-ai:make-assistant-message
     :content content
     :api :faux
     :provider
     (intern (string-upcase (json-get spec "provider" "faux"))
             :keyword)
     :model (json-get spec "model" "faux-1")
     :response-model (json-get spec "responseModel")
     :response-id (format nil "render-seed-entry-~D" index)
     :usage (cadr-ai:make-usage)
     :stop-reason (stop-reason (json-get spec "stopReason"))
     :error-message (json-get spec "errorMessage")
     :timestamp (+ +fixed-timestamp+ 100000 index))))

(defun seed-entry-tool-result-message (spec index)
  (cadr-ai:make-tool-result-message
   :tool-call-id (json-get spec "toolCallId" "")
   :tool-name (json-get spec "toolName" "")
   :content
   (list
    (cadr-ai:make-text-content
     :text (json-get spec "text" "")))
   :details (json-get spec "details")
   :added-tool-names
   (json-vector-list (json-get spec "addedToolNames"))
   :is-error (not (null (json-get spec "isError")))
   :timestamp (+ +fixed-timestamp+ 100000 index)))

(defun seed-entry-reference (references key)
  (or (gethash key references)
      (error "Unknown seed entry reference: ~A" key)))

(defun append-seed-entries (session setup)
  (let ((references (make-hash-table :test #'equal)))
    (loop for spec in
            (json-vector-list (json-get setup "seedEntries"))
          for index from 0
          for type = (json-get spec "type")
          for key = (json-get spec "key")
          do
          (when key
            (unless (and (stringp key) (plusp (length key)))
              (error "Seed entry key must be a non-empty string"))
            (when (gethash key references)
              (error "Duplicate seed entry key: ~A" key)))
          (let
              ((id
                 (cond
                   ((string= type "user")
                    (cadr-agent:session-append-message
                     session
                     (cadr-ai:make-user-message
                      :content (json-get spec "text" "")
                      :timestamp
                      (+ +fixed-timestamp+ 100000 index))))
                   ((string= type "assistant")
                    (cadr-agent:session-append-message
                     session
                     (seed-entry-assistant-message spec index)))
                   ((string= type "toolResult")
                    (cadr-agent:session-append-message
                     session
                     (seed-entry-tool-result-message spec index)))
                   ((string= type "compaction")
                    (cadr-agent:session-append-compaction
                     session
                     (json-get spec "summary" "")
                     nil
                     (seed-entry-reference
                      references (json-get spec "firstKept"))
                     (json-get spec "tokensBefore" 0)
                     :details (json-get spec "details")
                     :from-hook-p
                     (not (null (json-get spec "fromHook")))))
                   ((string= type "branchSummary")
                    (let
                        ((from-id
                           (seed-entry-reference
                            references (json-get spec "from"))))
                      (cadr-agent:session-branch session from-id)
                      (cadr-agent:session-append-branch-summary
                       session from-id
                       (json-get spec "summary" "")
                       :details (json-get spec "details")
                       :from-hook-p
                       (not (null (json-get spec "fromHook"))))))
                   ((string= type "modelChange")
                    (cadr-agent:session-append-model-change
                     session
                     (json-get spec "provider" "")
                     (json-get spec "modelId" "")))
                   ((string= type "thinkingLevelChange")
                    (cadr-agent:session-append-thinking-level-change
                     session
                     (json-get spec "thinkingLevel" "")))
                   ((string= type "custom")
                    (cadr-agent:session-append-custom
                     session
                     (json-get spec "customType" "")
                     (json-get spec "data")))
                   ((string= type "customMessage")
                    (cadr-agent:session-append-custom-message
                     session
                     (json-get spec "customType" "")
                     (json-get spec "content" "")
                     :details (json-get spec "details")
                     :display-p
                     (not (null (json-get spec "display")))))
                   ((string= type "label")
                    (cadr-agent:session-set-label
                     session
                     (seed-entry-reference
                      references (json-get spec "target"))
                     (json-get spec "label")))
                   ((string= type "title")
                    (cadr-agent:session-set-name
                     session (json-get spec "name" "")))
                   (t
                    (error "Unsupported seed entry type: ~A" type)))))
            (when key
              (setf (gethash key references) id)))))
  session)

(defun make-render-session (cwd session-directory scenario)
  (let* ((setup (json-get scenario "setup"))
         (persistent-p
           (not (null (json-get setup "persistentSession"))))
         (directory
           (uiop:ensure-directory-pathname session-directory))
         (session
           (cadr-agent:create-session
            :directory directory
            :cwd cwd
            :id "render-session"
            :timestamp +fixed-timestamp+))
         (sessions (list session)))
    (setf (cadr-agent:session-path session)
          (merge-pathnames
           "2023-11-14T22-13-20-000Z_render-session.jsonl"
           directory))
    ;; Pi's persistent render fixture opens the current session file before
    ;; any messages are appended.  Mirror that public state so an otherwise
    ;; empty session still has a resumable session id at process exit.
    (when persistent-p
      (ensure-directories-exist (cadr-agent:session-path session))
      (with-open-file
          (stream (cadr-agent:session-path session)
                  :direction :output
                  :if-exists :supersede
                  :if-does-not-exist :create
                  :external-format :utf-8)
        (cadr-agent::write-jsonl-object
         stream
         (cadr-agent::session-header-to-json session)))
      (setf (cadr-agent::session-persisted-p session) t))
    (append-seed-messages session setup)
    (append-seed-entries session setup)
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
    (loop for spec in
            (json-vector-list
             (json-get setup "extraSessions"))
          for index from 0
          for id = (json-get spec "id")
          do
          (unless
              (and
               (stringp id)
               (plusp (length id))
               (every
                (lambda (character)
                  (or (alphanumericp character)
                      (char= character #\-)
                      (char= character #\_)))
                id))
            (error "Invalid render session fixture id: ~A" id))
          (let* ((extra-cwd
                   (or (json-get spec "cwd")
                       (namestring cwd)))
                 (age-seconds
                   (json-get spec "ageSeconds"))
                 (timestamp
                   (if age-seconds
                       (- (cadr-ai::unix-milliseconds)
                          (* age-seconds 1000))
                       (+ +fixed-timestamp+ index 1)))
                 (extra
                   (cadr-agent:create-session
                    :directory directory
                    :cwd extra-cwd
                    :id id
                    :timestamp timestamp)))
            (setf
             (cadr-agent:session-path extra)
             (merge-pathnames
              (format nil
                      "2023-11-14T22-13-20-000Z_extra-~2,'0D-~A.jsonl"
                      index id)
              directory))
            (loop for message in
                    (json-vector-list
                     (json-get spec "messages"))
                  for message-index from 0
                  do
                  (cadr-agent:session-append-message
                   extra
                   (seed-message
                    message message-index timestamp)))
            (let ((name (json-get spec "name")))
              (when name
                (cadr-agent:session-set-name extra name)))
            (setf sessions (append sessions (list extra)))))
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

(defun render-comparison-model-count (scenario)
  (let ((count
          (json-get
           (json-get scenario "setup")
           "comparisonModelCount" 1)))
    (unless (and (integerp count) (plusp count))
      (error "comparisonModelCount must be a positive integer: ~A"
             count))
    count))

(defun render-models (&optional scenario)
  (let ((count
          (if scenario
              (render-comparison-model-count scenario)
              1)))
    (cons
     (cadr-ai:make-model
      :id "faux-1" :name "Faux Model"
      :provider :faux :api :faux
      :base-url "http://localhost:0"
      :reasoning-p t :context-window 128000
      :max-tokens 16384)
     (loop for ordinal from 1 to count
           collect
           (cadr-ai:make-model
            :id (format nil "other-~D" ordinal)
            :name
            (if (= count 1)
                "Other Model"
                (format nil "Other Model ~D" ordinal))
            :provider :other :api :openai-completions
            :base-url "https://render.invalid/v1"
            :context-window 64000 :max-tokens 8192)))))

(defun render-enabled-model-ids (scenario)
  (let ((setup (json-get scenario "setup")))
    (if (json-key-present-p setup "enabledModelIds")
        (json-vector-list
         (json-get setup "enabledModelIds"))
        '("faux/faux-1" "other/other-1"))))

(defun render-scoped-models (scenario)
  ;; Mirrors pi-driver.ts: scopedModels is [faux-1, other-1] exactly
  ;; when the scenario does not pin enabledModelIds and the comparison
  ;; providers are registered; otherwise the session has no model
  ;; scope and the selector shows no scoped tab.
  (let ((setup (json-get scenario "setup")))
    (when (and (not (json-key-present-p setup "enabledModelIds"))
               (comparison-providers-enabled-p scenario))
      (let ((models (render-models scenario)))
        (list (first models) (second models))))))

(defun render-trust-saved-entry (scenario cwd)
  (let ((spec
          (json-get
           (json-get scenario "setup")
           "trustSavedDecision")))
    (when spec
      (let* ((scope (json-get spec "scope"))
             (path
               (if (string= scope "parent")
                   (cadr-cli::parent-directory cwd)
                   cwd)))
        (list
         :path (cadr-cli::canonical-directory-name path)
         :decision
         (not (null (json-get spec "decision"))))))))

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
      :status '(:type :api-key :source "configured provider")))
    (list
     (cadr-cli::make-oauth-selector-option
      :id :render-device :name "Render Device"
      :auth-type :oauth
      :method-name "Render Device account"
      :status '(:type :api-key :source "configured provider"))
     (cadr-cli::make-oauth-selector-option
      :id :render-device :name "Render Device"
      :auth-type :api-key
      :method-name "Render Device API key"
      :status '(:type :api-key :source "configured provider")))
    (list
     (cadr-cli::make-oauth-selector-option
      :id :render-loopback :name "Render Loopback"
      :auth-type :oauth
      :method-name "Render Loopback account"
      :status '(:type :api-key :source "configured provider"))
     (cadr-cli::make-oauth-selector-option
      :id :render-loopback :name "Render Loopback"
      :auth-type :api-key
      :method-name "Render Loopback API key"
      :status '(:type :api-key :source "configured provider"))))
   #'string-lessp
   :key #'cadr-cli::oauth-selector-option-name))

(defun render-logout-options ()
  (list
   (cadr-cli::make-oauth-selector-option
    :id :faux :name "faux"
    :auth-type :api-key
    :method-name "faux API key"
    :status '(:type :api-key :source "stored credential"))))

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
     "/pi00/workspace")))

(defun render-fixture-login (provider-id interaction)
  ;; Fixture OAuth flows matching the pi-driver's registered render
  ;; providers: authorization-code-with-paste and device-code.  Both emit
  ;; real runtime auth events so the production login dialog renders them.
  (cond
    ((eq provider-id :render-loopback)
     ;; Browser-callback flow: listen on the fixed loopback port and
     ;; complete when the harness delivers the callback.
     (let ((socket
             (make-instance 'sb-bsd-sockets:inet-socket
                            :type :stream :protocol :tcp)))
       (unwind-protect
            (progn
              (setf (sb-bsd-sockets:sockopt-reuse-address socket) t)
              (sb-bsd-sockets:socket-bind socket #(127 0 0 1) 1459)
              (sb-bsd-sockets:socket-listen socket 1)
              (cadr-ai:runtime-auth-interaction-notify
               interaction
               (list :type :progress
                     :message "Listening for OAuth callback on http://127.0.0.1:1459/callback"))
              (cadr-ai:runtime-auth-interaction-notify
               interaction
               (list :type :auth-url
                     :url "https://auth.invalid/authorize?state=render-loopback"
                     :instructions "Continue in your browser."))
              (loop
                (when (cadr-ai:runtime-auth-interaction-aborted-p interaction)
                  (error 'cadr-ai:authentication-cancelled
                         :message "Login cancelled"))
                (when (sb-sys:wait-until-fd-usable
                       (sb-bsd-sockets:socket-file-descriptor socket)
                       :input 0.05)
                  (return)))
              (let ((client (sb-bsd-sockets:socket-accept socket)))
                (unwind-protect
                     (let ((stream
                             (sb-bsd-sockets:socket-make-stream
                              client :input t :output t
                              :element-type 'character
                              :external-format :utf-8
                              :buffering :none)))
                       (read-line stream nil "")
                       (loop for header = (read-line stream nil "")
                           until (zerop
                                  (length
                                   (string-trim '(#\Return) header))))
                       (write-string
                        "HTTP/1.1 200 OK
content-type: text/plain
connection: close

render loopback login received
" stream)
                       (finish-output stream))
                  (ignore-errors
                    (sb-bsd-sockets:socket-close client))))
              (cadr-ai:make-oauth-credential
               :provider provider-id
               :access "render-access"
               :refresh "render-refresh"
               :expires 1800000000000
               :account-id "render-account"))
         (ignore-errors
           (sb-bsd-sockets:socket-close socket)))))
    ((eq provider-id :render-device)
     (cadr-ai:runtime-auth-interaction-notify
      interaction
      (list :type :device-code
            :user-code "RENDER-42"
            :verification-uri "https://auth.invalid/device"))
     (loop
       (when (cadr-ai:runtime-auth-interaction-aborted-p interaction)
         (error 'cadr-ai:authentication-cancelled
                :message "Login cancelled"))
       (sleep 0.05)))
    (t
     (cadr-ai:runtime-auth-interaction-notify
      interaction
      (list :type :auth-url
            :url "https://auth.invalid/authorize?state=render-fixed"
            :instructions
            "A browser window should open. Complete login to finish."))
     (let ((code
             (cadr-ai:runtime-auth-interaction-prompt
              interaction
              (list :type :manual-code
                    :message "Paste the authorization code"))))
       (unless (cadr-ai::non-empty-string-p code)
         (error 'cadr-ai:authentication-cancelled
                :message "Login cancelled"))
       (cadr-ai:make-oauth-credential
        :provider provider-id
        :access "render-access"
        :refresh "render-refresh"
        :expires 1800000000000
        :account-id "render-account")))))

(defun command-dispatcher
    (agent cwd agent-directory session-directory settings-manager
     auth-prompt-consumer auth-event-consumer status-consumer
     abort-predicate)
  (lambda (line)
    (cond
      ((member line
               '("/login render-auth" "/login render-device"
                 "/login render-loopback")
               :test #'string=)
       ;; Drive the production OAuth event surface: the controller routes
       ;; these events into the login dialog overlay, exactly as a real
       ;; provider login would.  Nothing here synthesizes dialog content.
       (let ((provider-id
               (cond
                 ((string= line "/login render-device") :render-device)
                 ((string= line "/login render-loopback") :render-loopback)
                 (t :render-auth))))
         (render-fixture-login
          provider-id
          (cadr-ai:make-runtime-auth-interaction
           :prompt-function
           (lambda (prompt)
             (if auth-prompt-consumer
                 (funcall auth-prompt-consumer prompt)
                 (error
                  'cadr-ai:configuration-error
                  :message
                  "Interactive authentication prompt is unavailable")))
           :notify-function
           (lambda (event)
             (when auth-event-consumer
               (funcall auth-event-consumer event)))
           :abort-p abort-predicate))
         ;; A completed fixture login prints the baseline status line.
         ;; (The harness starts with a known model selected, so the
         ;; baseline's no-default-model caveat does not fire here.)
         (let ((display-name
                 (cadr-cli::oauth-selector-option-name
                  (find provider-id (render-auth-options)
                        :key #'cadr-cli::oauth-selector-option-id))))
           (when status-consumer
             (funcall
              status-consumer
              (format nil "Logged in to ~A. Credentials saved to ~A"
                      display-name
                      (merge-pathnames "auth.json" agent-directory)))))
       (values t nil)))
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
              :ansi-theme-p t
              :changelog-path
              (uiop:getenv "RENDER_DIFF_REFERENCE_CHANGELOG")
              :status-function status-consumer)
             (values t (get-output-stream-string output))
             (values nil nil)))))))

(defun run-scenario (scenario cwd agent-dir session-directory)
  (materialize-fixture-files
   scenario cwd agent-dir session-directory)
  (when
      (string=
       (json-get (json-get scenario "setup")
                 "entrypoint" "interactive")
       "main")
    ;; Goal 18 adjudicated main()-path surfaces: the pre-TUI resume
    ;; picker and the bare-environment no-model sentinel only exist on
    ;; the real main() path, so drive cadr main directly — no faux
    ;; provider, no registered auth.
    (uiop:chdir cwd)
    (loop for fixture in
            (json-vector-list
             (json-get (json-get scenario "setup") "pickerSessions"))
          for index from 0
          for timestamp = (+ +fixed-timestamp+ (* index 60000))
          for session =
            (cadr-agent:create-session
             :directory (merge-pathnames "sessions/" agent-dir)
             :cwd (or (json-get fixture "cwd") cwd)
             :id (json-get fixture "id")
             :timestamp timestamp)
          do (loop for spec in
                       (json-vector-list
                        (json-get fixture "messages"))
                   for m-index from 0
                   do (cadr-agent:session-append-message
                       session
                       (seed-message spec m-index timestamp)))
             (let ((name (json-get fixture "name")))
               (when name
                 (cadr-agent:session-set-name session name))))
    (finish-output *standard-output*)
    (finish-output *error-output*)
    (uiop:quit
     (cadr-cli::main
      (json-vector-list
       (json-get (json-get scenario "setup") "mainArgv")))))
  (when
      (string=
       (json-get (json-get scenario "setup")
                 "entrypoint" "interactive")
       "cli-help")
    (cadr-cli::print-cli-usage
     *standard-output*
     (list
      (list :name "render-flag" :type :string
            :description "Render differential extension flag"
            :extension-path "render-diff")))
    (dolist (command '("install" "remove" "update" "list" "config"))
      (multiple-value-bind (handled-p status)
          (cadr-cli::handle-package-command
           (list command "--help")
           :cwd cwd
           :agent-directory agent-dir
           :output *standard-output*
           :error-output *error-output*)
        (unless handled-p
          (error "Cadr help entrypoint did not handle ~A" command))
        (unless (zerop status)
          (error "Cadr help entrypoint failed for ~A: ~A" command status))))
    (finish-output *standard-output*)
    (finish-output *error-output*)
    (uiop:quit 0))
  (when
      (string=
       (json-get (json-get scenario "setup")
                 "entrypoint" "interactive")
       "cli-errors")
    ;; Goal 18 I7: the same CLI error/warning argv list as the pi
    ;; driver's cli-errors entrypoint, through the real cadr main.
    (uiop:chdir cwd)
    ;; Persist the scenario's trust decision for the package-command
    ;; trust checks.
    (let ((trust-entry
            (render-trust-saved-entry scenario cwd)))
      (when trust-entry
        (cadr-cli::project-trust-set
         (cadr-cli::make-project-trust-store
          (merge-pathnames "trust.json" agent-dir))
         (getf trust-entry :path)
         (getf trust-entry :decision)
         :store-negative-p
         (not (getf trust-entry :decision)))))
    ;; Seed a local session so --fork onto an existing id reports the
    ;; baseline "Session already exists" error (main.ts:324-330).
    ;; cadr lists sessions flat under the session root and filters by
    ;; the recorded cwd (session/discovery.lisp list-sessions).
    (let* ((sessions-dir
             (merge-pathnames "sessions/" agent-dir)))
      (ensure-directories-exist sessions-dir)
      (with-open-file
          (out
           (merge-pathnames
            "2023-11-14T22-13-20-000Z_sweep-existing.jsonl"
            sessions-dir)
           :direction :output :if-exists :supersede)
        (write-line
         (cadr-ai::stringify-json
          (cadr-ai::json-object
           "type" "session"
           "version" 3
           "id" "sweep-existing"
           "timestamp" "2023-11-14T22:13:20.000Z"
           "cwd"
           (namestring
            (uiop:ensure-directory-pathname cwd))))
         out)))
    (dolist
        (argv
         '(;; Startup content migrations (migrations.ts:144,214) run
           ;; before the metadata commands; this case must stay first.
           ("--list-models")
           ("--fork" "x" "--session" "y")
           ("--fork" "x" "--no-session")
           ("--fork" "x" "--session" "y" "--continue")
           ("--session-id" "abc" "--continue")
           ("--session-id" "BAD ID!")
           ("--name" "")
           ("--mode" "rpc" "@foo.txt")
           ("--fork" "nonexistent-session")
           ("--session" "nonexistent-session")
           ("--export" "/nonexistent-session.jsonl")
           ("auth" "bogus")
           ("auth" "print-api-key" "--provider" "bogus"
            "--model" "gpt-5.5")
           ("install")
           ("config" "--bogus")
           ("remove" "nonexistent-package")
           ("update" "--all" "--self")
           ("install" "x" "y")
           ("update" "--extension")
           ("-p" "@/nonexistent-file.txt")
           ("install" "--bogus")
           ("config" "-l")
           ("install" "-l" "./x")
           ("--fork" "x" "--session-id" "sweep-existing")
           ("--session-id" "fresh-sweep-1" "-p" "hi")))
      (cadr-cli::main argv))
    (sb-posix:setenv "CADR_STARTUP_BENCHMARK" "1" 1)
    (cadr-cli::main '("-p" "hi"))
    (sb-posix:unsetenv "CADR_STARTUP_BENCHMARK")
    ;; Goal 18 I7: corrupt models.json warns and falls back to the
    ;; empty availability guidance (list-models.ts:30-33,40-42).
    (with-open-file
        (out
         (merge-pathnames "models.json" agent-dir)
         :direction :output :if-exists :supersede)
      (write-string "{ not valid json " out))
    (cadr-cli::main '("--list-models"))
    (with-open-file
        (out
         (merge-pathnames "models.json" agent-dir)
         :direction :output :if-exists :supersede)
      (write-string (cadr-ai::stringify-json
                     (cadr-ai::json-object "providers" (cadr-ai::json-object)))
                    out))
    ;; Goal 18 I7: a broken extension is a fatal startup diagnostic
    ;; with the -ne hint (main.ts:843-849).
    (ensure-directories-exist
     (merge-pathnames "extensions/broken/" agent-dir))
    (with-open-file
        (out
         (merge-pathnames
          "extensions/broken/extension.lisp" agent-dir)
         :direction :output :if-exists :supersede)
      (write-line "(error \"render-drive-broken\")" out))
    (cadr-cli::main '("-p" "hi"))
    (finish-output *standard-output*)
    (finish-output *error-output*)
    (uiop:quit 0))
  (when
      (string=
       (json-get (json-get scenario "setup")
                 "entrypoint" "interactive")
       "config")
    (multiple-value-bind (handled-p status)
        (cadr-cli::handle-package-command
         '("config" "--approve")
         :cwd cwd
         :agent-directory agent-dir
         :output *standard-output*
         :error-output *error-output*)
      (unless handled-p
        (error "Cadr config entrypoint was not handled"))
      (finish-output *standard-output*)
      (finish-output *error-output*)
      (uiop:quit status)))
  (multiple-value-bind
        (session session-directory persistent-p sessions)
      (make-render-session cwd session-directory scenario)
    (let* ((stream (json-get scenario "stream"))
           (chunk-characters
             (or (json-get stream "chunkCharacters") 4096))
           (tokens-per-second
             (or (json-get stream "tokensPerSecond") 0))
           (handle
             (cadr-ai:make-faux-provider
              :model-definitions
              (list
               (list :id "faux-1" :name "Faux Model"
                     :reasoning-p
                     (string= (json-get scenario "id")
                              "local-status-sweep")
                     :context-window 128000
                     :max-tokens 16384))
              :token-min 4096 :token-max 4096))
           (event-consumer nil)
           (auth-url-consumer nil)
           (auth-event-consumer nil)
           (auth-prompt-consumer nil)
           (status-consumer nil)
           (extension-ui-consumer nil)
           (extension-ui-worker nil)
           (injected-event-worker nil)
           (runtime-action-worker nil)
           (abort-requested-p nil)
           (settings-manager
             (cadr-cli::make-memory-settings-manager
              (cadr-ai::json-object
               "collapseChangelog" t)))
           (resources
             (render-resource-snapshot
              scenario cwd agent-dir))
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
      ;; pi@74caa2649 sdk.ts:362-374 records model/thinking only for a new
      ;; session.  Existing sessions restore their graph and append thinking
      ;; only when the active branch has no thinking-level entry.
      (if (cadr-agent:agent-messages agent)
          (unless
              (find
               :thinking-level-change
               (cadr-agent::session-path-entries session)
               :key #'cadr-agent:session-entry-type)
            (cadr-agent:session-append-thinking-level-change
             session "high"))
          (progn
            (cadr-agent:session-append-model-change
             session "faux" "faux-1")
            (cadr-agent:session-append-thinking-level-change
             session "high")))
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
          (cadr-cli::make-tui-startup-lines
           resources
           :extensions
           (mapcar
            (lambda (record)
              (list
               :path (cadr-cli::extension-source-record-path record)
               :scope (cadr-cli::extension-source-record-scope record)))
            (cadr-cli::discover-extensions-in-directory
             (merge-pathnames "extensions/" agent-dir)
             :global 0)))
        (let ((main-thread sb-thread:*current-thread*)
              (crash-after-ms
                (json-get (json-get scenario "setup")
                          "crashAfterMs"))
              (scope-line
                (and
                 (comparison-providers-enabled-p scenario)
                 (cadr-cli::model-scope-startup-line
                  (mapcar
                   (lambda (model)
                     (list :model model :thinking nil))
                   (render-scoped-models scenario))
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
         (let ((crash-trigger
                 (concatenate
                  'string
                  (uiop:getenv "RENDER_DIFF_READY_PATH")
                  ".crash")))
           (sb-thread:make-thread
            (lambda ()
              (loop
                (when (probe-file crash-trigger)
                  (sb-thread:interrupt-thread
                   main-thread
                   (lambda ()
                     (error "render-diff crash sentinel")))
                  (return))
                (sleep 0.02)))
            :name "render-diff-crash-watch"))
          (let ((setup (json-get scenario "setup")))
            (when (json-key-present-p setup "hyperlinks")
              (let ((capabilities
                      (cadr-tui:get-terminal-capabilities)))
                (cadr-tui:set-terminal-capabilities
                 (cadr-tui:make-terminal-capabilities
                  :images
                  (cadr-tui:terminal-capabilities-images capabilities)
                  :true-color-p
                  (cadr-tui:terminal-capabilities-true-color-p capabilities)
                  :hyperlinks-p
                  (not (null (json-get setup "hyperlinks"))))))))
          (cadr-cli:run-tui
           (lambda (line)
             (cadr-agent:agent-prompt
              agent line :source :interactive))
           :command-function
           (lambda (line)
             (funcall
              (command-dispatcher
               agent cwd agent-dir session-directory settings-manager
               auth-prompt-consumer auth-event-consumer status-consumer
               (lambda () abort-requested-p))
              line))
           :bash-function
           (lambda (command exclude-p)
             (cadr-cli::record-user-bash-result
              agent
              (cadr-cli::execute-user-bash-for-tui
               nil cwd command
               :exclude-from-context-p exclude-p
               :abort-p (lambda () abort-requested-p))))
           :set-event-consumer
           (lambda (consumer)
             (setf event-consumer consumer)
             (let ((reason
                     (json-get
                      (json-get scenario "setup")
                      "injectedCompactionReason")))
               (when (and consumer reason
                          (not injected-event-worker))
                 (setf
                  injected-event-worker
                  (sb-thread:make-thread
                   (lambda ()
                     (sleep 0.1)
                     (funcall
                      consumer
                      (cadr-agent::make-agent-event
                       :type :compaction-start
                       :reason (intern (string-upcase reason) :keyword))))
                   :name "render-diff-injected-event"))))
             (let ((actions
                     (json-vector-list
                      (json-get
                       (json-get scenario "setup")
                       "runtimeActions"))))
               (when (and consumer actions
                          (not runtime-action-worker))
                 (setf
                  runtime-action-worker
                  (sb-thread:make-thread
                   (lambda ()
                     (run-runtime-actions agent actions))
                   :name "render-diff-runtime-actions")))))
           :work-rendered-function
           (lambda ()
             (append-ready-marker "agent-settled"))
           :set-auth-url-consumer
           (lambda (consumer) (setf auth-url-consumer consumer))
           :set-auth-event-consumer
           (lambda (consumer) (setf auth-event-consumer consumer))
           :set-auth-prompt-consumer
           (lambda (consumer) (setf auth-prompt-consumer consumer))
           :set-status-consumer
           (lambda (consumer) (setf status-consumer consumer))
           :version-update-check-function
           (when
               (json-get
                (json-get scenario "setup")
                "updateNotifications")
             (lambda ()
               (let ((release (make-hash-table :test #'equal)))
                 (cadr-ai::json-put release "version" "9.9.9")
                 (cadr-ai::json-put release "note" "Release note")
                 release)))
           :package-update-check-function
           (when
               (json-get
                (json-get scenario "setup")
                "updateNotifications")
             (lambda () '("alpha" "beta")))
           :set-extension-ui-function
           (lambda (consumer)
             (setf extension-ui-consumer consumer)
             (when
                 (and consumer
                      (not extension-ui-worker)
                      (not (null
                            (json-get
                             (json-get scenario "setup")
                             "extensionSurfaces"))))
               (setf
                extension-ui-worker
                (sb-thread:make-thread
                 (lambda ()
                   (sleep 0.1)
                   (funcall extension-ui-consumer :select
                            '(:title "Extension Select"
                              :options ("alpha" "beta")))
                   (funcall extension-ui-consumer :input
                            '(:title "Extension Input"
                              :placeholder "type here"))
                   (funcall extension-ui-consumer :editor
                            '(:title "Extension Editor"
                              :prefill "prefill")))
                 :name "render-diff-extension-ui"))))
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
           :cycle-model-function
           (lambda (direction)
             (let* ((models (render-models scenario))
                    (current
                      (cadr-agent:agent-model agent))
                    (current-index
                      (or
                       (position
                        current models
                        :test #'cadr-ai:models-equal-p)
                       0))
                    (offset
                      (if (eq direction :backward)
                          -1 1))
                    (next
                      (nth
                       (mod (+ current-index offset)
                            (length models))
                       models)))
               (cadr-agent:agent-set-model agent next)
               (cadr-agent:agent-set-thinking-level
                agent
                (if (cadr-ai:model-reasoning-p next)
                    :high :off))
               (format
                nil "Switched to ~A~A"
                (or (cadr-ai::model-name next)
                    (cadr-ai:model-id next))
                (if (cadr-ai:model-reasoning-p next)
                    " (thinking: high)"
                    ""))))
           :model-items-function
           (lambda () (render-models scenario))
           :model-selector-function
           (lambda (&optional query)
             (let* ((models (render-models scenario))
                    (state
                     (cadr-cli::make-model-selector-state
                      :all-models models
                      :scoped-models
                      (render-scoped-models scenario)
                      :current-model (first models)
                      :refresh-status-message
                      "Model catalogs refreshed.")))
               (cadr-cli::model-selector-set-query
                state (or query ""))))
           :scoped-models-selector-function
           (lambda ()
             (cadr-cli::make-scoped-models-selector-state
              :all-models (render-models scenario)
              :enabled-ids
              (render-enabled-model-ids scenario)))
           :settings-selector-function
           (lambda ()
             (cadr-cli::make-cli-settings-selector-state
              settings-manager agent resources
              :supports-images-p
              (not
               (null
                (json-get
                 (json-get scenario "setup")
                 "supportsImages")))))
           :trust-selector-function
           (lambda ()
             (cadr-cli::make-trust-selector-state
              :cwd (namestring cwd)
              :saved-entry
              (render-trust-saved-entry scenario cwd)
              :project-trusted-p
              (not
               (null
                (json-get
                 (json-get scenario "setup")
                 "projectTrusted" t)))))
           :on-trust-selected
           (lambda (selection)
             (when status-consumer
               (funcall
                status-consumer
                (format nil
                        "Saved trust decision: ~A. Restart cadr for this to take effect."
                        (if (getf selection :trusted-p)
                            "trusted"
                            "untrusted")))))
           :fork-items-function
           (lambda ()
             (list
              (cadr-tui:make-select-item
               :label "overlay question" :value "u1")))
           :session-items-function
           (lambda ()
             (render-session-items sessions))
           :session-selector-show-rename-hint-p t
           :all-session-items-function
           (lambda ()
             (render-session-items sessions))
           :tree-state-function
           (lambda ()
             (cadr-cli::session-tree-selector-data session))
           :login-options-function #'render-auth-options
           :logout-options-function #'render-logout-options
           :on-logout-selected (constantly nil)
           :on-import-confirmed (constantly nil)
           :on-clone-session
           (lambda ()
             (let ((clone
                     (cadr-cli::clone-agent-session
                      agent session-directory)))
               (if (or (null clone)
                       (eq clone :cancelled))
                   (values nil nil nil)
                   (values
                    (cadr-agent:session-id clone)
                    (copy-list
                     (cadr-agent:session-messages clone))
                    (cadr-agent:session-path clone)))))
           :on-new-session
           (lambda ()
             (let ((new
                     (cadr-agent:create-session
                      :directory session-directory
                      :cwd cwd
                      :id "render-new-session"
                      :timestamp +fixed-timestamp+)))
               (cadr-cli::switch-agent-session agent new)
               (values new nil
                       (and persistent-p
                            (namestring
                             (cadr-agent:session-path new))))))
           :model "faux-1"
           :provider "faux"
           :thinking
           (cadr-cli::model-footer-thinking-level
            (cadr-agent:agent-model agent) :high)
           :footer-state-function
           (lambda ()
             (let* ((current
                      (cadr-agent:agent-session agent))
                    (current-model
                      (cadr-agent:agent-model agent))
                    (empty-p
                      (null
                       (and current
                            (cadr-agent:session-messages current))))
                    (context-percent
                      (* 100d0
                         (/
                          (cadr-agent::context-estimated-tokens
                           (cadr-agent:agent-messages agent))
                          (cadr-ai:model-context-window
                           current-model)))))
               (append
                (list
                 :model
                 (cadr-ai:model-id current-model)
                 :provider
                 (string-downcase
                  (symbol-name
                   (cadr-ai:model-provider current-model)))
                 :thinking
                 (cadr-cli::model-footer-thinking-level
                  current-model :high)
                 :context-window
                 (cadr-ai:model-context-window current-model)
                 :context-percent context-percent
                 :session-name
                 (and current
                      (cadr-agent:session-name current)))
                (when empty-p
                  (list
                   :context-percent 0d0
                   :input 0 :output 0
                   :cache-read 0 :cache-write 0
                   :latest-cache-hit-rate nil
                   :cost 0d0 :cost-known-p nil)))))
           :cwd
           (cadr-cli::format-cwd-for-footer
            (namestring cwd)
            (namestring (user-homedir-pathname)))
           :footer-cwd (namestring cwd)
           :available-provider-count
           (if (or (comparison-providers-enabled-p scenario)
                   (auth-provider-enabled-p scenario))
               2
               1)
           :context-window 128000
           :session session
           :messages (cadr-cli::session-display-messages session)
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
           :initial-notices
           (render-initial-notices scenario)
           :initial-statuses
           (let ((status
                   (cadr-cli::session-compaction-status session)))
             (and status (list status)))
           :alt-p nil
           :show-hardware-cursor-p nil))
        (when persistent-p
          (let ((current
                  (cadr-agent:agent-session agent)))
            (cadr-cli::write-session-resume-hint
             current session-directory
             :terminal-p t
             :default-session-directory-p nil))))
      (cadr-agent:agent-shutdown agent))))

(defun main ()
  (destructuring-bind
      (project quicklisp manifest-path scenario-id cwd-path agent-dir-path
       session-directory-path)
      (subseq cl-user::*render-diff-arguments* 0 7)
    (declare (ignore project quicklisp))
    (let* ((manifest
             (cadr-ai::parse-json
              (uiop:read-file-string manifest-path)))
           (scenario (find-scenario manifest scenario-id))
           (cwd (uiop:ensure-directory-pathname (pathname cwd-path)))
           (agent-dir
             (uiop:ensure-directory-pathname
              (pathname agent-dir-path)))
           (session-directory
             (uiop:ensure-directory-pathname
              (pathname session-directory-path))))
      (run-scenario scenario cwd agent-dir session-directory))))

(cadr-cli::call-with-fatal-condition-boundary #'main)
