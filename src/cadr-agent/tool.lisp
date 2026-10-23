(in-package #:cadr-agent)

(defstruct (tool-registry
            (:constructor %make-tool-registry))
  (by-name (make-hash-table :test #'equal) :type hash-table)
  (ordered nil :type list))

(defun make-tool-registry (&optional tools)
  (let ((registry (%make-tool-registry)))
    (dolist (tool tools)
      (register-tool registry tool))
    registry))

(defun register-tool (registry tool)
  (let ((name (cadr-ai:tool-name tool)))
    (when (gethash name (tool-registry-by-name registry))
      (error 'cadr-ai:configuration-error
             :message (format nil "Tool already registered: ~A" name)))
    (setf (gethash name (tool-registry-by-name registry)) tool
          (tool-registry-ordered registry)
          (nconc (tool-registry-ordered registry) (list tool)))
    tool))

(defun find-tool (registry name)
  (gethash name (tool-registry-by-name registry)))

(defun registry-tools (registry)
  (copy-list (tool-registry-ordered registry)))

(defun merged-agent-tools (agent)
  (let* ((extension-tools
           (if (agent-extension-host agent)
               (extension-host-tools
                (agent-extension-host agent))
               nil))
         (extension-names
           (mapcar #'cadr-ai:tool-name extension-tools)))
    (nconc
     (remove-if
      (lambda (tool)
        (member
         (cadr-ai:tool-name tool)
         extension-names
         :test #'string=))
      (copy-list (agent-base-tools agent)))
     extension-tools)))

(defun extension-tool-exposure (host name)
  (let ((definition
          (and host
               (find name
                     (extension-snapshot-tools
                      (extension-host-current-snapshot host))
                     :key #'extension-tool-definition-name
                     :test #'string=))))
    (if definition
        (extension-tool-definition-exposure definition)
        :direct)))

(defun find-extension-tool-definition (host name)
  (and host
       (find name
             (extension-snapshot-tools
              (extension-host-current-snapshot host))
             :key #'extension-tool-definition-name
             :test #'string=)))

(defun extension-tool-activates-on-registration-p (host name)
  ;; pi@4a080252f agent-session.ts _isActivatedOnRegistration.
  ;; direct and model-only tools activate unless default-active is nil.
  (let ((definition (find-extension-tool-definition host name)))
    (and definition
         (member (extension-tool-definition-exposure definition)
                 '(:direct :model-only))
         (extension-tool-definition-default-active definition))))

(defun tool-declared-by-default-p (host tool)
  (member (extension-tool-exposure host (cadr-ai:tool-name tool))
          '(:direct :model-only)))

(defun extension-tool-kept-without-override-p (agent host tool)
  (let ((name (cadr-ai:tool-name tool)))
    (and (tool-declared-by-default-p host tool)
         (or (null (find-extension-tool-definition host name))
             (extension-tool-activates-on-registration-p host name)
             (member name
                     (agent-named-tool-names agent)
                     :test #'string=)))))

(defun active-hidden-tool-names (agent)
  ;; pi@4a080252f #10343. Hidden tools stay callable through another
  ;; tool, so the prompt still knows they exist, but they are not
  ;; declared to the model.
  (let ((host (agent-extension-host agent))
        (filter (agent-tool-filter-function agent)))
    (unless host
      (return-from active-hidden-tool-names nil))
    (loop for tool in (funcall filter (merged-agent-tools agent))
          for name = (cadr-ai:tool-name tool)
          when (eq :hidden (extension-tool-exposure host name))
          collect name)))

(defun refresh-agent-extension-tools (agent)
  (let* ((merged (merged-agent-tools agent))
         (filtered
           (funcall
            (agent-tool-filter-function agent)
            merged))
         (host (agent-extension-host agent))
         (effective
           (if
               (and
                host
                (extension-host-active-tools-overridden-p
                 host))
               ;; pi@4a080252f: setActiveTools / resume restore pick
               ;; from the full registry, not the defaultTools filter.
               ;; Intersecting with the filter dropped transcript tools
               ;; like grep that are builtin but outside the defaults.
               (remove-if-not
                (lambda (tool)
                  (member
                   (cadr-ai:tool-name tool)
                   (extension-host-active-tool-names
                    host)
                   :test #'string=))
                merged)
               ;; Deferred, codemode, and hidden tools stay out of the
               ;; model declaration until something activates them.
               (remove-if-not
                (lambda (tool)
                  (extension-tool-kept-without-override-p
                   agent host tool))
                filtered))))
    (setf
     (agent-tool-registry agent)
     (make-tool-registry effective)))
  agent)

(defun recorded-tool-name (entry)
  (cond
    ((typep entry 'cadr-ai:tool) (cadr-ai:tool-name entry))
    ((typep entry 'cadr-ai:tool-reference)
     (cadr-ai:tool-reference-name entry))
    ((stringp entry) entry)))

(defun branch-system-messages (session)
  ;; pi@4a080252f agent-session.ts _restoreToolsFromTranscript. The
  ;; whole branch, including system messages before a compaction.
  ;; Compaction checkpoints are derived and are not replayed here.
  (when session
    (loop for entry in (session-path-entries session)
          when (and (eq (session-entry-type entry) :message)
                    (cadr-ai:system-message-p
                     (session-entry-message entry)))
          collect (session-entry-message entry))))

(defun branch-mentioned-tool-names (messages)
  (loop for message in messages
        append
        (loop for entry in
              (append
               (cadr-ai:system-message-tools-added message)
               (cadr-ai:system-message-tools-removed message))
              for name = (recorded-tool-name entry)
              when name
              collect name)))

(defun tool-allowed-in-registry-p (agent name)
  (when (member name
                (agent-excluded-tool-names agent)
                :test #'string=)
    (return-from tool-allowed-in-registry-p nil))
  (cond
    ((not (agent-tool-allowlist-p agent)) t)
    ((member name (agent-tool-allowlist agent) :test #'string=) t)
    ((and (mcp-tool-name-p name)
          (not (agent-tool-allowlist-filters-mcp-p agent)))
     t)
    (t nil)))

(defun restored-tool-activatable-p (agent name)
  ;; pi@4a080252f _isActivatable plus the hidden-tool drop in
  ;; _applyToolLoadout. An allowlist keeps non-matching MCP tools
  ;; registered and inactive unless tool_search can load them.
  (let* ((host (agent-extension-host agent))
         (exposure (extension-tool-exposure host name)))
    (when (eq exposure :hidden)
      (return-from restored-tool-activatable-p nil))
    (unless (agent-tool-allowlist-p agent)
      (return-from restored-tool-activatable-p t))
    (or (member name (agent-tool-allowlist agent) :test #'string=)
        (not (mcp-tool-name-p name))
        (and (not (eq exposure :direct))
             (find "tool_search"
                   (merged-agent-tools agent)
                   :key #'cadr-ai:tool-name
                   :test #'string=)))))

(defun unmentioned-extension-tool-names (agent mentioned)
  (let ((host (agent-extension-host agent))
        (base-names
          (mapcar #'cadr-ai:tool-name (agent-base-tools agent))))
    (loop for tool in (merged-agent-tools agent)
          for name = (cadr-ai:tool-name tool)
          when (and (not (member name mentioned :test #'string=))
                    (not (member name base-names :test #'string=))
                    (tool-allowed-in-registry-p agent name)
                    (extension-tool-activates-on-registration-p
                     host name))
          collect name)))

(defun agent-restore-tools-from-transcript
    (agent &key (modifiers '()) modifier-function exclude-tools)
  ;; pi@4a080252f agent-session.ts _restoreToolsFromTranscript (#11062 #11075).
  (let ((excluded
          (if exclude-tools
              exclude-tools
              (agent-excluded-tool-names agent)))
        (messages
          (branch-system-messages (agent-session agent))))
    (unless messages
      (return-from agent-restore-tools-from-transcript nil))
    (let* ((mentioned (branch-mentioned-tool-names messages))
           (current
             (mapcar
              #'cadr-ai:tool-name
              (cadr-ai:get-current-tools messages)))
           (names
             (append
              current
              (unmentioned-extension-tool-names agent mentioned))))
      (when modifier-function
        (setf names (funcall modifier-function names modifiers)))
      (setf names
            (remove-if
             (lambda (name)
               (or (member name excluded :test #'string=)
                   (not (tool-allowed-in-registry-p agent name))
                   (not (restored-tool-activatable-p agent name))))
             names))
      (let* ((available
               (mapcar
                #'cadr-ai:tool-name
                (merged-agent-tools agent)))
             (known
               (remove-if-not
                (lambda (name)
                  (member name available :test #'string=))
                names))
             (host (agent-extension-host agent)))
        (if host
            (cadr-agent::extension-host-set-active-tools host known)
            (progn
              (setf (agent-tool-filter-function agent)
                    (lambda (candidates)
                      (remove-if-not
                       (lambda (tool)
                         (member (cadr-ai:tool-name tool)
                                 known :test #'string=))
                       candidates)))
              (refresh-agent-extension-tools agent)))
        known))))

(defun make-agent (&key
                         provider
                         model
                         system-prompt
                         system-prompt-options
                         messages
                         tools
                         (tool-filter-function #'identity)
                         prepare-prompt-loadout-function
                         extension-host
                         session
                         (stream-function #'cadr-ai:stream-chat)
                         summarization-auth-function
                         on-event
                         (max-turns 100)
                         (auto-compact-p t)
                         (compaction-reserve-tokens 16384)
                         (compaction-keep-recent-tokens 20000)
                         compaction-settings-function
                         (auto-retry-p t)
                         (auto-retry-max-attempts 3)
                         (auto-retry-base-delay 2)
                         (auto-retry-max-delay-ms 60000)
                         finish-turn-function
                         abort-p
                         named-tool-names
                         tool-allowlist
                         tool-allowlist-p
                         tool-allowlist-filters-mcp-p
                         excluded-tool-names)
  (let* ((initial-messages
           (copy-list
            (or messages
                (and session
                     (session-messages session)))))
         (agent
          (%make-agent
           :provider provider
           :model model
           :system-prompt system-prompt
           :system-prompt-options
           (copy-tree system-prompt-options)
           :messages initial-messages
           :messages-tail (last initial-messages)
           :messages-tail-head initial-messages
           :base-tools (copy-list tools)
           :tool-registry (make-tool-registry tools)
           :tool-filter-function tool-filter-function
           :prepare-prompt-loadout-function
           prepare-prompt-loadout-function
           :extension-host extension-host
           :session session
           :stream-function stream-function
           :summarization-auth-function
           summarization-auth-function
           :on-event on-event
           :max-turns max-turns
           :auto-compact-p auto-compact-p
           :compaction-reserve-tokens
           compaction-reserve-tokens
           :compaction-keep-recent-tokens
           compaction-keep-recent-tokens
           :compaction-settings-function
           compaction-settings-function
           :auto-retry-p auto-retry-p
           :auto-retry-max-attempts auto-retry-max-attempts
           :auto-retry-base-delay auto-retry-base-delay
           :auto-retry-max-delay-ms auto-retry-max-delay-ms
           :finish-turn-function finish-turn-function
           :abort-p abort-p
           :named-tool-names (copy-list named-tool-names)
           :tool-allowlist (copy-list tool-allowlist)
           :tool-allowlist-p (not (null tool-allowlist-p))
           :tool-allowlist-filters-mcp-p
           (not (null tool-allowlist-filters-mcp-p))
           :excluded-tool-names (copy-list excluded-tool-names))))
    (when extension-host
      (attach-extension-host extension-host agent))
    (unless
        (and
         (agent-messages agent)
         (cadr-ai:system-message-p
          (first (agent-messages agent))))
      (let ((initial
              (cadr-ai:create-initial-system-message
               nil
               (mapcar
                #'cadr-ai:to-tool-declaration
                (registry-tools
                 (agent-tool-registry agent))))))
        (when initial
          ;; Persist the seeded toolsAdded declaration so resume can
          ;; restore the active loadout (pi@4a080252f #10785). Agent
          ;; messages alone are not enough: declare-tool-changes treats
          ;; in-memory tools as already declared and skips the session.
          (when (agent-session agent)
            (session-append-message
             (agent-session agent) initial))
          (let ((seeded
                  (cons initial (agent-messages agent))))
            (setf
             (agent-messages agent) seeded
             (agent-messages-tail agent) (last seeded)
             (agent-messages-tail-head agent) seeded)))))
    agent))

(defstruct prepared-tool-call
  call
  tool
  arguments
  appended-messages)

(defstruct tool-execution-result
  (content nil :type list)
  details
  (terminate-p nil :type boolean))

(defstruct tool-outcome
  call
  result
  appended-messages
  (terminate-p nil :type boolean)
  ;; A tool_call block. pi@4a080252f agent-loop.ts skips afterToolCall.
  (blocked-p nil :type boolean))

(defun make-error-tool-result
    (call text &optional appended-messages duration-ms)
  (make-tool-outcome
   :call call
   :appended-messages appended-messages
   :result
   (cadr-ai:make-tool-result-message
    :tool-call-id (cadr-ai:tool-call-id call)
    :tool-name (cadr-ai:tool-call-name call)
    :content (list (cadr-ai:make-text-content :text text))
    :is-error t
    :duration-ms duration-ms)))

(defvar *tool-execution-error-fallback* nil)

(defvar *tool-abort-p* nil)

(defvar *tool-cancellation-signal* nil)

(defvar *tool-update-function* nil)

(defun current-tool-aborted-p ()
  (and *tool-abort-p*
       (funcall *tool-abort-p*)))

(defun current-tool-cancellation-signal ()
  *tool-cancellation-signal*)

(defun current-tool-update-function ()
  *tool-update-function*)

(defun report-tool-update
    (content &optional details terminate-p)
  (let ((update *tool-update-function*))
    (when update
      (funcall
       update content details (eq terminate-p t)))))

(defun tool-elapsed-ms (started)
  (max
   0
   (round
    (* 1000d0
       (/ (- (get-internal-real-time) started)
          internal-time-units-per-second)))))

(defun signal-tool-execution-error
    (message condition tool call &key duration-ms)
  (let ((wrapped
          (make-condition
           'tool-execution-error
           :message message
           :cause condition
           :tool tool
           :tool-call-id
           (cadr-ai:tool-call-id call)
           :duration-ms duration-ms)))
    (signal wrapped)
    (if *tool-execution-error-fallback*
        (funcall
         *tool-execution-error-fallback* wrapped)
        (error wrapped))))

(defun hook-tool-call-copy (call)
  ;; pi@4a080252f validateToolArguments clones before tool_call, so
  ;; mutating event.input does not rewrite the assistant message.
  (let ((copy (cadr-ai::copy-tool-call call))
        (arguments (cadr-ai:tool-call-arguments call)))
    (when (hash-table-p arguments)
      (setf (cadr-ai:tool-call-arguments copy)
            (cadr-ai::copy-json-value arguments)))
    copy))

(defun tool-exposure-callable-from-execute-p (exposure active-p)
  ;; pi@4a080252f agent-session.ts _getCallableTools. Active direct
  ;; tools, plus every codemode or deferred tool. model-only and
  ;; hidden stay out, even when the model can see the tool.
  (or (eq exposure :codemode)
      (eq exposure :deferred)
      (and (eq exposure :direct) active-p)))

(defun agent-callable-tools (agent)
  (let* ((host (agent-extension-host agent))
         (active-names
           (mapcar #'cadr-ai:tool-name
                   (registry-tools (agent-tool-registry agent)))))
    (remove-if-not
     (lambda (tool)
       (tool-exposure-callable-from-execute-p
        (extension-tool-exposure host (cadr-ai:tool-name tool))
        (member (cadr-ai:tool-name tool)
                active-names
                :test #'string=)))
     (merged-agent-tools agent))))

(defun prepare-tool-execution
    (agent call &key turn-index on-effective-call
                  (tools nil tools-supplied-p))
  (let ((effective-call call)
        (appended-messages nil))
    (when (agent-extension-host agent)
      (multiple-value-bind
            (replacement appended blocked-p reason
             terminate-p terminate-supplied-p)
          (run-extension-hooks
           (agent-extension-host agent)
           :tool-call-before
           :turn-index turn-index
           :tool-call (hook-tool-call-copy call))
        (setf effective-call replacement
              appended-messages appended)
        (when blocked-p
          (return-from prepare-tool-execution
            (let ((blocked
                    (make-error-tool-result
                     effective-call
                     (or reason "Tool execution was blocked")
                     appended-messages)))
              (setf (tool-outcome-blocked-p blocked) t)
              ;; pi@4a080252f agent-loop.ts:637-640 — a before-hook
              ;; terminate on a blocked call marks the result so the
              ;; batch termination rule can stop the agent.
              (when (and terminate-supplied-p
                         (eq terminate-p t))
                (setf (tool-outcome-terminate-p blocked) t))
              blocked)))))
    (when on-effective-call
      (funcall
       on-effective-call
       effective-call appended-messages))
    (let ((tool
            (if tools-supplied-p
                (find (cadr-ai:tool-call-name effective-call)
                      tools
                      :key #'cadr-ai:tool-name
                      :test #'string=)
                (find-tool
                 (agent-tool-registry agent)
                 (cadr-ai:tool-call-name effective-call)))))
    (unless tool
      (return-from prepare-tool-execution
        (make-error-tool-result
         effective-call
         (format nil "Tool ~A not found"
                 (cadr-ai:tool-call-name effective-call))
         appended-messages)))
    (let ((arguments
            (handler-bind
                ((error
                   (lambda (condition)
                     (unless
                         (typep condition
                                'tool-execution-error)
                       (signal-tool-execution-error
                        (if
                            (typep condition
                                   'cadr-ai:cadr-error)
                            (cadr-ai:cadr-error-message
                             condition)
                            (princ-to-string condition))
                        condition tool effective-call)))))
              (let ((arguments-error
                      (cadr-ai:tool-call-arguments-error
                       effective-call)))
                (when (and (stringp arguments-error)
                           (plusp (length arguments-error)))
                  (error
                   "Invalid arguments for tool \"~A\": ~A"
                   (cadr-ai:tool-call-name effective-call)
                   arguments-error)))
              (validate-tool-arguments
               tool
               (cadr-ai:tool-call-arguments
                effective-call)))))
      (make-prepared-tool-call
       :call effective-call
       :tool tool
       :arguments arguments
       :appended-messages appended-messages)))))

(defvar *tool-call-cwd* nil
  "Directory for the tool call in progress. Nil keeps the directory captured when the tool was built.")

(defvar *tool-search-agent* nil
  "Agent whose tool set tool_search reads and updates.")

(defun execute-prepared-tool
    (prepared &key cancellation-signal on-update execution-cwd)
  (let* ((call (prepared-tool-call-call prepared))
         (tool (prepared-tool-call-tool prepared))
         (accepting-updates-p t)
         (update-lock
           (sb-thread:make-mutex
            :name "cadr-tool-update-scope"))
         (scoped-update
           (lambda (content details terminate-p)
             (sb-thread:with-recursive-lock
                 (update-lock)
               (when
                   (and accepting-updates-p on-update)
                 (funcall
                  on-update
                  (make-tool-execution-result
                   ;; (or content nil) is the TS ?? identity.
                   :content content
                   :details details
                   :terminate-p (eq terminate-p t))))))))
    (unwind-protect
         (let ((*tool-cancellation-signal*
                 cancellation-signal)
               (*tool-update-function* scoped-update)
               (started (get-internal-real-time)))
           (handler-bind
               ((error
                  (lambda (condition)
                    (unless
                        (typep condition 'tool-execution-error)
                      (signal-tool-execution-error
                       (princ-to-string condition)
                       condition tool call
                       :duration-ms
                       (tool-elapsed-ms started))))))
             (let ((*tool-call-cwd*
                     (or execution-cwd *tool-call-cwd*))
                   (*nested-tool-caller-id*
                     (or *nested-tool-caller-id*
                         (cadr-ai:tool-call-id call))))
               (multiple-value-bind
                     (content details terminate-p
                      structured-content usage)
                   (funcall
                    (cadr-ai:tool-executor tool)
                    (cadr-ai:tool-call-id call)
                    (prepared-tool-call-arguments prepared))
                 (make-tool-outcome
                  :call call
                  :appended-messages
                  (prepared-tool-call-appended-messages
                   prepared)
                  :terminate-p (eq terminate-p t)
                  :result
                  (cadr-ai:make-tool-result-message
                   :tool-call-id
                   (cadr-ai:tool-call-id call)
                   :tool-name
                   (cadr-ai:tool-call-name call)
                   :content content
                   :details details
                   :structured-content structured-content
                   :usage usage
                   :is-error nil
                   :duration-ms
                   (tool-elapsed-ms started)))))))
      (sb-thread:with-recursive-lock
          (update-lock)
        (setf accepting-updates-p nil)))))

(defun emit-nested-tool-event (agent type tool-call parent-id outcome)
  (run-agent-lifecycle
   agent type
   (append
    (list
     :tool-call-id (cadr-ai:tool-call-id tool-call)
     :tool-name (cadr-ai:tool-call-name tool-call)
     :arguments (cadr-ai:tool-call-arguments tool-call)
     :parent-tool-call-id parent-id)
    (when (and outcome (eq type :tool-execution-end))
      (list
       :result (nested-tool-call-outcome-result outcome)
       :error-p (nested-tool-call-outcome-is-error outcome)))))
  (emit-agent-event
   agent type
   :tool-call tool-call
   :tool-result
   (and outcome (nested-tool-call-outcome-result outcome))
   :parent-tool-call-id parent-id))

(defun run-agent-nested-tool (agent tool-call parent-id signal on-update)
  (let* ((*nested-tool-caller-id* (cadr-ai:tool-call-id tool-call))
         (prepared
           (handler-case
               (prepare-tool-execution
                agent tool-call
                :tools (agent-callable-tools agent))
             (error (condition)
               (make-error-tool-result
                tool-call (princ-to-string condition))))))
    (let ((outcome
            (if (typep prepared 'tool-outcome)
                prepared
                (handler-case
                    (let ((*tool-search-agent* agent))
                      (execute-prepared-tool
                       prepared
                       :cancellation-signal signal
                     :on-update
                     (when on-update
                       (lambda (partial)
                         (funcall on-update partial)
                         (emit-nested-tool-event
                          agent :tool-execution-update
                          tool-call parent-id nil)))))
                  (error (condition)
                    (make-error-tool-result
                     tool-call (princ-to-string condition)))))))
      (when (agent-extension-host agent)
        (setf outcome
              (finalize-tool-outcome agent outcome nil)))
      (make-nested-tool-call-outcome
       :tool-call (tool-outcome-call outcome)
       :result (tool-outcome-result outcome)
       :is-error
       (cadr-ai:tool-result-message-is-error
        (tool-outcome-result outcome))))))

(defun make-agent-nested-tool-runner (agent)
  (make-nested-tool-call-runner
   :tools-function
   (lambda ()
     (agent-callable-tools agent))
   :emit-function
   (lambda (type tool-call parent-id outcome)
     (emit-nested-tool-event
      agent type tool-call parent-id outcome))
   :run-function
   (lambda (tool-call parent-id signal on-update)
     (run-agent-nested-tool
      agent tool-call parent-id signal on-update))))
