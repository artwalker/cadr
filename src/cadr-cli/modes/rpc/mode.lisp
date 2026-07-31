(in-package #:cadr-cli)

(defparameter +rpc-thinking-levels+
  '(:off :minimal :low :medium :high :xhigh :max))

(defun model-to-rpc-json (model)
  (cadr-ai::json-object
   "id" (cadr-ai:model-id model)
   "name" (cadr-ai::model-name model)
   "provider"
   (string-downcase
    (symbol-name
     (cadr-ai:model-provider model)))
   "api"
   (rpc-symbol-name
    (cadr-ai:model-api model))
   "baseUrl" (cadr-ai:model-base-url model)
   "reasoning" (cadr-ai:model-reasoning-p model)
   "contextWindow"
   (cadr-ai:model-context-window model)
   "maxTokens" (cadr-ai:model-max-tokens model)))

(defun metadata-to-model (metadata)
  (cadr-agent::metadata-model-copy metadata))

(defun rpc-extension-models (state)
  (let* ((host
           (cli-extension-manager-host
            (rpc-state-extension-manager state)))
         (entries
           (cadr-agent::extension-host-provider-definitions
            host)))
    (loop
      for entry in entries
      append
      (mapcar
       #'metadata-to-model
       (cadr-agent::extension-provider-definition-models
        entry)))))

(defun rpc-available-models (state)
  (let ((seen (make-hash-table :test #'equal))
        (models nil))
    (dolist
        (model
         (nconc
          (mapcar
           #'metadata-to-model
           (cadr-ai:list-model-metadata))
          (rpc-extension-models state)))
      (let ((key
              (cons
               (cadr-ai:model-provider model)
               (cadr-ai:model-id model))))
        (unless (gethash key seen)
          (setf (gethash key seen) t)
          (push model models))))
    (sort
     models
     #'string<
     :key
     (lambda (model)
       (format nil "~A/~A"
               (cadr-ai:model-provider model)
               (cadr-ai:model-id model))))))

(defun rpc-find-extension-provider-entry
    (state provider)
  (find
   provider
   (cadr-agent::extension-host-provider-definitions
    (cli-extension-manager-host
     (rpc-state-extension-manager state)))
   :key #'cadr-agent::extension-provider-id))

(defun rpc-resolve-model (state provider-name model-id)
  (let* ((provider
           (intern
            (string-upcase provider-name)
            :keyword))
         (extension-entry
           (rpc-find-extension-provider-entry
            state provider)))
    (if extension-entry
        (let* ((definition
                 (cadr-agent::extension-provider-definition-definition
                  extension-entry))
               (metadata
                 (find
                  model-id
                  (cadr-agent::extension-provider-definition-models
                   extension-entry)
                  :key #'cadr-ai:model-metadata-id
                  :test #'string=)))
          (unless metadata
            (error "Model not found: ~A/~A"
                   provider-name model-id))
          (values
           (cadr-ai::make-protocol-provider
            (cadr-ai:provider-definition-protocol definition)
            definition
            (let ((name
                    (cadr-ai:provider-definition-key-environment
                     definition)))
              (and name (uiop:getenv name)))
            nil nil nil)
           (metadata-to-model metadata)))
        (let ((config
                (resolve-provider-config
                 :provider provider-name
                 :model model-id
                 :allow-missing-auth-p t)))
          (values
           (provider-config-provider config)
           (provider-config-model config))))))

(defun rpc-run-lifecycle (agent event &rest payload)
  (when (cadr-agent::agent-extension-host agent)
    (cadr-agent::run-extension-lifecycle-hooks
     (cadr-agent::agent-extension-host agent)
     event :payload payload)))

(defun rpc-set-model
    (state provider-name model-id source)
  (let* ((agent (rpc-state-agent state))
         (previous (cadr-agent:agent-model agent)))
    (multiple-value-bind (provider model)
        (rpc-resolve-model
         state provider-name model-id)
      (setf
       (cadr-agent:agent-provider agent) provider
       (cadr-agent:agent-model agent) model)
      (let ((host
              (cadr-agent::agent-extension-host agent)))
        (when host
          (setf
           (cadr-agent::extension-host-base-agent-provider host)
           provider
           (cadr-agent::extension-host-base-agent-model host)
           model)))
      (when (cadr-agent:agent-session agent)
        (cadr-agent:session-append-model-change
         (cadr-agent:agent-session agent)
         provider-name model-id))
      (rpc-run-lifecycle
       agent :model-select
       :model model
       :previous-model previous
       :source source)
      model)))

(defun rpc-supported-thinking-levels (agent)
  (let ((model (cadr-agent:agent-model agent)))
    (if (not (cadr-ai:model-reasoning-p model))
        '(:off)
        (remove-if
         (lambda (level)
           (and
            (member level '(:xhigh :max))
            (not
             (cadr-ai::model-thinking-level-present-p
              model level))))
         +rpc-thinking-levels+))))

(defun rpc-clamp-thinking-level (requested available)
  (or
   (find requested available)
   (let ((position
           (position requested +rpc-thinking-levels+)))
     (and position
          (or
           (find-if
            (lambda (candidate)
              (member candidate available))
            (nthcdr position +rpc-thinking-levels+))
           (find-if
            (lambda (candidate)
              (member candidate available))
            (reverse
             (subseq +rpc-thinking-levels+
                     0 position))))))
   :off))

(defun rpc-set-thinking-level (agent level)
  (unless (member level +rpc-thinking-levels+)
    (error "Unknown thinking level: ~A" level))
  (let* ((previous
           (cadr-agent::agent-thinking-level agent))
         (effective
           (rpc-clamp-thinking-level
            level
            (rpc-supported-thinking-levels agent))))
    (unless (eq previous effective)
      (setf
       (cadr-agent::agent-thinking-level agent)
       effective)
      (when (cadr-agent:agent-session agent)
        (cadr-agent:session-append-thinking-level-change
         (cadr-agent:agent-session agent)
         (string-downcase
          (symbol-name effective))))
      (rpc-run-lifecycle
       agent :thinking-level-select
       :level effective
       :previous-level previous))
    effective))

(defun rpc-cycle-thinking-level (agent)
  (let ((levels
          (rpc-supported-thinking-levels agent)))
    (when (> (length levels) 1)
      (let* ((current
               (position
                (cadr-agent::agent-thinking-level agent)
                levels))
             (next
               (nth
                (mod (1+ (or current -1))
                     (length levels))
                levels)))
        (rpc-set-thinking-level agent next)))))

(defun rpc-images-from-json (value)
  (unless value
    (return-from rpc-images-from-json nil))
  (unless (vectorp value)
    (error "RPC field images must be an array"))
  (loop
    for object across value
    collect
    (progn
      (require-rpc-object object)
      (cadr-ai:make-image-content
       :mime-type
       (require-rpc-string object "mimeType")
       :data
       (require-rpc-string object "data")))))

(defun rpc-prompt-message (object)
  (let ((text
          (require-rpc-string object "message"))
        (images
          (rpc-images-from-json
           (cadr-ai::json-get object "images"))))
    (if images
        (cadr-ai:make-user-message
         :content
         (nconc
          (list
           (cadr-ai:make-text-content :text text))
          images))
        (cadr-ai:make-user-message :content text))))

(defun rpc-start-prompt (state object)
  (let* ((agent (rpc-state-agent state))
         (id (rpc-command-id object))
         (message (rpc-prompt-message object))
         (behavior
           (cadr-ai::json-get
            object "streamingBehavior")))
    (sb-thread:with-mutex
        ((rpc-state-activity-lock state))
      (when
          (or
           (cadr-agent:agent-busy-p agent)
           (and
            (rpc-state-prompt-thread state)
            (sb-thread:thread-alive-p
             (rpc-state-prompt-thread state))))
        (cond
          ((string= behavior "steer")
           (multiple-value-bind
                 (processed handled-p)
               (cadr-agent::apply-agent-input-hooks
                agent message :rpc
                :streaming-behavior :steer)
             (unless handled-p
               (cadr-agent:agent-steer
                agent processed))))
          ((string= behavior "followUp")
           (multiple-value-bind
                 (processed handled-p)
               (cadr-agent::apply-agent-input-hooks
                agent message :rpc
                :streaming-behavior :follow-up)
             (unless handled-p
               (cadr-agent:agent-follow-up
                agent processed))))
          (t
           (error
            "Agent is already processing a prompt; streamingBehavior is required")))
        (return-from rpc-start-prompt
          (rpc-success id "prompt")))
      (let ((acknowledged-p nil))
        (setf
         (rpc-state-prompt-thread state)
         (sb-thread:make-thread
          (lambda ()
            (unwind-protect
                 (handler-case
                     (cadr-agent:agent-prompt
                      agent message
                      :source :rpc
                      :preflight-function
                      (lambda ()
                        (setf acknowledged-p t)
                        (rpc-write-object
                         state
                         (rpc-success
                          id "prompt"))))
                   (error (condition)
                     (unless acknowledged-p
                       (rpc-write-object
                        state
                        (rpc-failure
                         id "prompt" condition)))))
              (sb-thread:with-mutex
                  ((rpc-state-activity-lock state))
                (setf
                 (rpc-state-prompt-thread state)
                 nil))))
          :name "cadr-rpc-prompt")))
    +rpc-async-response+)))

(defun rpc-bash-result-json
    (content details &key cancelled-p)
  (let* ((exit-code
           (getf details :exit-code))
         (text
           (if content
               (cadr-ai:text-content-text
                (first content))
               ""))
         (object
           (cadr-ai::json-object
            "output"
            (if exit-code
                (bash-strip-exit-footer
                 text exit-code)
                text)
            "exitCode"
            (or exit-code 'null)
            "cancelled"
            (not (null cancelled-p))
            "truncated"
            (not
             (null
              (getf details :truncated))))))
    (when (getf details :full-output-path)
      (cadr-ai::json-put
       object "fullOutputPath"
       (getf details :full-output-path)))
    object))

(defun rpc-claim-bash (state token)
  (sb-thread:with-mutex
      ((rpc-state-activity-lock state))
    (when (eq token (rpc-state-bash-token state))
      (setf
       (rpc-state-bash-thread state) nil
       (rpc-state-bash-token state) nil
       (rpc-state-bash-request-id state) nil)
      t)))

(defun rpc-cancel-bash (state &key respond-p)
  (multiple-value-bind (thread id claimed-p)
      (sb-thread:with-mutex
          ((rpc-state-activity-lock state))
        (when (rpc-state-bash-token state)
          (multiple-value-prog1
              (values
               (rpc-state-bash-thread state)
               (rpc-state-bash-request-id state)
               t)
            (setf
             (rpc-state-bash-thread state) nil
             (rpc-state-bash-token state) nil
             (rpc-state-bash-request-id state)
             nil))))
    (when claimed-p
      (when
          (and
           thread
           (sb-thread:thread-alive-p thread))
        (sb-thread:terminate-thread thread))
      (when respond-p
        (rpc-write-object
         state
         (rpc-success
          id "bash"
          (rpc-bash-result-json
           nil nil :cancelled-p t))))
      t)))

(defun rpc-start-bash (state object)
  (let ((id (rpc-command-id object))
        (command
          (require-rpc-string object "command"))
        (token (list :bash-operation)))
    (sb-thread:with-mutex
        ((rpc-state-activity-lock state))
      (when
          (and
           (rpc-state-bash-thread state)
           (sb-thread:thread-alive-p
            (rpc-state-bash-thread state)))
        (error "A bash command is already running"))
      (setf
       (rpc-state-bash-token state) token
       (rpc-state-bash-request-id state) id
       (rpc-state-bash-thread state)
       (sb-thread:make-thread
        (lambda ()
          (handler-case
              (multiple-value-bind
                    (content details)
                  (execute-user-bash
                   (cli-extension-manager-host
                    (rpc-state-extension-manager
                     state))
                   (cli-extension-manager-cwd
                    (rpc-state-extension-manager
                     state))
                   command
                   :exclude-from-context-p
                   (not
                    (null
                     (cadr-ai::json-get
                      object
                      "excludeFromContext"))))
                (when (rpc-claim-bash state token)
                  (rpc-write-object
                   state
                   (rpc-success
                    id "bash"
                    (rpc-bash-result-json
                     content details)))))
            (error (condition)
              (when (rpc-claim-bash state token)
                (rpc-write-object
                 state
                 (rpc-failure
                  id "bash" condition))))))
        :name "cadr-rpc-bash")))
    +rpc-async-response+))

(defun rpc-session-directory (session)
  (make-pathname
   :name nil :type nil
   :defaults
   (cadr-agent:session-path session)))

(defun rpc-switch-agent-session
    (agent session reason previous-file)
  (let ((host
          (cadr-agent::agent-extension-host agent)))
    (when host
      (cadr-agent::invalidate-extension-host-generation
       host)))
  (setf
   (cadr-agent:agent-session agent) session
   (cadr-agent:agent-messages agent)
   (cadr-agent:session-messages session))
  (rpc-run-lifecycle
   agent :session-start
   :reason reason
   :previous-session-file previous-file)
  session)

(defun rpc-before-session-switch
    (agent reason target)
  (let ((result
          (rpc-run-lifecycle
           agent :session-before-switch
           :reason reason
           :target-session-file target)))
    (not (null (getf result :cancel-p)))))

(defun rpc-new-session (state object)
  (let* ((agent (rpc-state-agent state))
         (old (cadr-agent:agent-session agent))
         (parent
           (cadr-ai::json-get
            object "parentSession"))
         (directory
           (rpc-session-directory old)))
    (if
        (rpc-before-session-switch
         agent :new nil)
        (cadr-ai::json-object "cancelled" t)
        (progn
          (rpc-run-lifecycle
           agent :session-shutdown
           :reason :new)
          (let ((session
                  (cadr-agent:create-session
                   :directory directory
                   :cwd (cadr-agent:session-cwd old)
                   :parent-session
                   (and
                    (stringp parent)
                    parent))))
            (rpc-switch-agent-session
             agent session :new
             (namestring
              (cadr-agent:session-path old)))
            (cadr-ai::json-object
             "cancelled" nil))))))

(defun rpc-switch-session-command (state object)
  (let* ((agent (rpc-state-agent state))
         (old (cadr-agent:agent-session agent))
         (path
           (require-rpc-string
            object "sessionPath")))
    (if
        (rpc-before-session-switch
         agent :resume path)
        (cadr-ai::json-object "cancelled" t)
        (let ((session
                (cadr-agent:load-session path)))
          (rpc-run-lifecycle
           agent :session-shutdown
           :reason :resume
           :target-session-file path)
          (rpc-switch-agent-session
           agent session :resume
           (namestring
            (cadr-agent:session-path old)))
          (cadr-ai::json-object
           "cancelled" nil)))))

(defun rpc-entry-user-text (entry)
  (when
      (and
       (eq :message
           (cadr-agent:session-entry-type entry))
       (typep
        (cadr-agent:session-entry-message entry)
        'cadr-ai:user-message))
    (let ((content
            (cadr-ai:user-message-content
             (cadr-agent:session-entry-message
              entry))))
      (if (stringp content)
          content
          (format
           nil "~{~A~^~%~}"
           (loop for block in content
                 when
                 (typep block 'cadr-ai:text-content)
                   collect
                   (cadr-ai:text-content-text
                    block)))))))

(defun rpc-copy-session-branch
    (source target leaf-id)
  (dolist
      (entry
       (cadr-agent::session-path-entries
        source leaf-id))
    (when
        (eq :message
            (cadr-agent:session-entry-type entry))
      (cadr-agent:session-append-message
       target
       (cadr-agent:session-entry-message entry))))
  target)

(defun rpc-fork-session
    (state entry-id position)
  (let* ((agent (rpc-state-agent state))
         (old (cadr-agent:agent-session agent))
         (entry
           (find
            entry-id
            (cadr-agent:session-entries old)
            :key #'cadr-agent:session-entry-id
            :test #'string=)))
    (unless entry
      (error "Entry not found: ~A" entry-id))
    (let ((before
            (rpc-run-lifecycle
             agent :session-before-fork
             :entry-id entry-id
             :position position)))
      (when (getf before :cancel-p)
        (return-from rpc-fork-session
          (values nil t))))
    (let* ((leaf-id
             (if (eq position :before)
                 (cadr-agent:session-entry-parent-id
                  entry)
                 entry-id))
           (new
             (cadr-agent:create-session
              :directory
              (rpc-session-directory old)
              :cwd
              (cadr-agent:session-cwd old)
              :parent-session
              (namestring
               (cadr-agent:session-path old)))))
      (when leaf-id
        (rpc-copy-session-branch
         old new leaf-id))
      (rpc-run-lifecycle
       agent :session-shutdown
       :reason :fork
       :target-session-file
       (namestring
        (cadr-agent:session-path new)))
      (rpc-switch-agent-session
       agent new :fork
       (namestring
        (cadr-agent:session-path old)))
      (values
       (or (rpc-entry-user-text entry) "")
       nil))))

(defun rpc-session-stats (session)
  (let ((user 0)
        (assistant 0)
        (tool-results 0)
        (tool-calls 0)
        (input 0)
        (output 0)
        (cache-read 0)
        (cache-write 0))
    (dolist (entry (cadr-agent:session-entries session))
      (when
          (eq :message
              (cadr-agent:session-entry-type entry))
        (let ((message
                (cadr-agent:session-entry-message
                 entry)))
          (cond
            ((typep message 'cadr-ai:user-message)
             (incf user))
            ((typep message
                    'cadr-ai:tool-result-message)
             (incf tool-results))
            ((typep message
                    'cadr-ai:assistant-message)
             (incf assistant)
             (incf
              tool-calls
              (count-if
               (lambda (block)
                 (typep block 'cadr-ai:tool-call))
               (cadr-ai:assistant-message-content
                message)))
             (let ((usage
                     (cadr-ai:assistant-message-usage
                      message)))
               (incf input
                     (cadr-ai:usage-input usage))
               (incf output
                     (cadr-ai:usage-output usage))
               (incf cache-read
                     (cadr-ai:usage-cache-read usage))
               (incf cache-write
                     (cadr-ai:usage-cache-write
                      usage))))))))
    (cadr-ai::json-object
     "sessionFile"
     (namestring (cadr-agent:session-path session))
     "sessionId" (cadr-agent:session-id session)
     "userMessages" user
     "assistantMessages" assistant
     "toolCalls" tool-calls
     "toolResults" tool-results
     "totalMessages"
     (+ user assistant tool-results)
     "tokens"
     (cadr-ai::json-object
      "input" input
      "output" output
      "cacheRead" cache-read
      "cacheWrite" cache-write
      "total"
      (+ input output cache-read cache-write)))))

(defun rpc-session-tree (session)
  (let ((nodes (make-hash-table :test #'equal))
        (roots nil))
    (dolist (entry (cadr-agent:session-entries session))
      (setf
       (gethash
        (cadr-agent:session-entry-id entry)
        nodes)
       (cadr-ai::json-object
        "entry"
        (cadr-agent::session-entry-to-json
         entry)
        "children" (make-array
                    0 :adjustable t
                    :fill-pointer 0))))
    (dolist (entry (cadr-agent:session-entries session))
      (let* ((node
               (gethash
                (cadr-agent:session-entry-id entry)
                nodes))
             (parent
               (and
                (cadr-agent:session-entry-parent-id
                 entry)
                (gethash
                 (cadr-agent:session-entry-parent-id
                  entry)
                 nodes))))
        (when
            (cadr-agent:session-label
             session
             (cadr-agent:session-entry-id entry))
          (cadr-ai::json-put
           node "label"
           (cadr-agent:session-label
            session
            (cadr-agent:session-entry-id entry))))
        (if parent
            (vector-push-extend
             node
             (cadr-ai::json-get
              parent "children"))
            (push node roots))))
    (coerce (nreverse roots) 'vector)))

(defun rpc-last-assistant-text (agent)
  (let ((message
          (find-if
           (lambda (candidate)
             (typep candidate
                    'cadr-ai:assistant-message))
           (cadr-agent:agent-messages agent)
           :from-end t)))
    (and message
         (format
          nil "~{~A~^~%~}"
          (assistant-text-content message)))))

(defun rpc-command-list (state)
  (let* ((snapshot
           (cadr-agent::extension-host-current-snapshot
            (cli-extension-manager-host
             (rpc-state-extension-manager state))))
         (commands nil))
    (dolist
        (definition
         (cadr-agent::extension-snapshot-commands
          snapshot))
      (push
       (cadr-ai::json-object
        "name"
        (cadr-agent::extension-command-definition-name
         definition)
        "description"
        (or
         (cadr-agent::extension-command-definition-description
          definition)
         "")
        "source" "extension"
        "sourceInfo"
        (cadr-ai::json-object
         "path"
         (cadr-agent::extension-definition-origin
          definition)))
       commands))
    (dolist
        (definition
         (cadr-agent::extension-snapshot-templates
          snapshot))
      (push
       (cadr-ai::json-object
        "name"
        (cadr-agent::extension-template-definition-name
         definition)
        "description"
        (or
         (cadr-agent::extension-template-definition-description
          definition)
         "")
        "source" "prompt"
        "sourceInfo"
        (cadr-ai::json-object
         "path"
         (cadr-agent::extension-definition-origin
          definition)))
       commands))
    (coerce (nreverse commands) 'vector)))

(defun rpc-handle-command (state object)
  (require-rpc-object object)
  (let* ((id (rpc-command-id object))
         (type
           (require-rpc-string object "type"))
         (agent (rpc-state-agent state))
         (session
           (cadr-agent:agent-session agent)))
    (cond
      ((string= type "prompt")
       (rpc-start-prompt state object))
      ((string= type "steer")
       (multiple-value-bind
             (message handled-p)
           (cadr-agent::apply-agent-input-hooks
            agent
            (rpc-prompt-message object)
            :rpc
            :streaming-behavior :steer)
         (unless handled-p
           (cadr-agent:agent-steer
            agent message)))
       (rpc-success id type))
      ((string= type "follow_up")
       (multiple-value-bind
             (message handled-p)
           (cadr-agent::apply-agent-input-hooks
            agent
            (rpc-prompt-message object)
            :rpc
            :streaming-behavior :follow-up)
         (unless handled-p
           (cadr-agent:agent-follow-up
            agent message)))
       (rpc-success id type))
      ((string= type "abort")
       (cadr-agent:agent-abort agent)
       (rpc-success id type))
      ((string= type "new_session")
       (rpc-success
        id type
        (rpc-new-session state object)))
      ((string= type "get_state")
       (let ((data
               (cadr-ai::json-object
                "model"
                (model-to-rpc-json
                 (cadr-agent:agent-model agent))
                "thinkingLevel"
                (rpc-symbol-name
                 (cadr-agent::agent-thinking-level
                  agent))
                "isStreaming"
                (cadr-agent:agent-busy-p agent)
                "isCompacting" nil
                "steeringMode"
                (rpc-symbol-name
                 (cadr-agent:agent-steering-mode
                  agent))
                "followUpMode"
                (rpc-symbol-name
                 (cadr-agent:agent-follow-up-mode
                  agent))
                "sessionFile"
                (namestring
                 (cadr-agent:session-path session))
                "sessionId"
                (cadr-agent:session-id session)
                "autoCompactionEnabled"
                (cadr-agent::agent-auto-compact-p
                 agent)
                "messageCount"
                (length
                 (cadr-agent:agent-messages agent))
                "pendingMessageCount"
                (multiple-value-bind
                      (steering follow-up next-turn)
                    (cadr-agent::agent-queue-snapshot
                     agent)
                  (+
                   (length steering)
                   (length follow-up)
                   (length next-turn))))))
         (when (cadr-agent:session-name session)
           (cadr-ai::json-put
            data "sessionName"
            (cadr-agent:session-name session)))
         (rpc-success id type data)))
      ((string= type "set_model")
       (rpc-success
        id type
        (model-to-rpc-json
         (rpc-set-model
          state
          (require-rpc-string
           object "provider")
          (require-rpc-string
           object "modelId")
          :set))))
      ((string= type "cycle_model")
       (let* ((models
                (rpc-available-models state))
              (current
                (position-if
                 (lambda (model)
                   (and
                    (eq
                     (cadr-ai:model-provider model)
                     (cadr-ai:model-provider
                      (cadr-agent:agent-model
                       agent)))
                    (string=
                     (cadr-ai:model-id model)
                     (cadr-ai:model-id
                      (cadr-agent:agent-model
                       agent)))))
                 models))
              (next
                (and models
                     (nth
                      (mod
                       (1+ (or current -1))
                       (length models))
                      models))))
         (rpc-success
          id type
          (if next
              (let ((selected
                      (rpc-set-model
                       state
                       (string-downcase
                        (symbol-name
                         (cadr-ai:model-provider
                          next)))
                       (cadr-ai:model-id next)
                       :cycle)))
                (cadr-ai::json-object
                 "model"
                 (model-to-rpc-json selected)
                 "thinkingLevel"
                 (rpc-symbol-name
                  (cadr-agent::agent-thinking-level
                   agent))
                 "isScoped" nil))
              'null))))
      ((string= type "get_available_models")
       (rpc-success
        id type
        (cadr-ai::json-object
         "models"
         (coerce
          (mapcar
           #'model-to-rpc-json
           (rpc-available-models state))
          'vector))))
      ((string= type "set_thinking_level")
       (rpc-set-thinking-level
        agent
        (intern
         (string-upcase
          (require-rpc-string
           object "level"))
         :keyword))
       (rpc-success id type))
      ((string= type "cycle_thinking_level")
       (let ((level
               (rpc-cycle-thinking-level agent)))
         (rpc-success
          id type
          (if level
              (cadr-ai::json-object
               "level" (rpc-symbol-name level))
              'null))))
      ((string= type
                "get_available_thinking_levels")
       (rpc-success
        id type
        (cadr-ai::json-object
         "levels"
         (coerce
          (mapcar
           #'rpc-symbol-name
           (rpc-supported-thinking-levels
            agent))
          'vector))))
      ((string= type "set_steering_mode")
       (setf
        (cadr-agent:agent-steering-mode agent)
        (let ((mode
                (require-rpc-string
                 object "mode")))
          (cond
            ((string= mode "all") :all)
            ((string= mode "one-at-a-time")
             :one-at-a-time)
            (t
             (error "Invalid steering mode: ~A"
                    mode)))))
       (rpc-success id type))
      ((string= type "set_follow_up_mode")
       (setf
        (cadr-agent:agent-follow-up-mode agent)
        (let ((mode
                (require-rpc-string
                 object "mode")))
          (cond
            ((string= mode "all") :all)
            ((string= mode "one-at-a-time")
             :one-at-a-time)
            (t
             (error "Invalid follow-up mode: ~A"
                    mode)))))
       (rpc-success id type))
      ((string= type "compact")
       (let ((compacted-p
               (cadr-agent:compact-agent
                agent :force-p t)))
         (rpc-success
          id type
          (if compacted-p
              (cadr-agent::session-entry-to-json
               (car
                (last
                 (cadr-agent:session-entries
                  session))))
              'null))))
      ((string= type "set_auto_compaction")
       (setf
        (cadr-agent::agent-auto-compact-p agent)
        (require-rpc-boolean object "enabled"))
       (rpc-success id type))
      ((string= type "set_auto_retry")
       (setf
        (cadr-agent::agent-auto-retry-p agent)
        (require-rpc-boolean object "enabled"))
       (rpc-success id type))
      ((string= type "abort_retry")
       (cadr-agent::agent-abort-retry agent)
       (rpc-success id type))
      ((string= type "bash")
       (rpc-start-bash state object))
      ((string= type "abort_bash")
       (rpc-write-object
        state (rpc-success id type))
       (rpc-cancel-bash
        state :respond-p t)
       +rpc-async-response+)
      ((string= type "get_session_stats")
       (rpc-success
        id type
        (rpc-session-stats session)))
      ((string= type "export_html")
       (let ((path
               (pathname
                (or
                 (cadr-ai::json-get
                  object "outputPath")
                 (format nil "~A.html"
                         (cadr-agent:session-id
                          session))))))
         (cadr-agent:export-session-html
          session path)
         (rpc-success
          id type
          (cadr-ai::json-object
           "path" (namestring path)))))
      ((string= type "switch_session")
       (rpc-success
        id type
        (rpc-switch-session-command
         state object)))
      ((string= type "fork")
       (multiple-value-bind (text cancelled-p)
           (rpc-fork-session
            state
            (require-rpc-string
             object "entryId")
            :before)
         (rpc-success
          id type
          (cadr-ai::json-object
           "text" (or text "")
           "cancelled"
           (not (null cancelled-p))))))
      ((string= type "clone")
       (let ((leaf
               (cadr-agent:session-leaf-id
                session)))
         (unless leaf
           (error
            "Cannot clone session: no current entry selected"))
         (multiple-value-bind (text cancelled-p)
             (rpc-fork-session
              state leaf :at)
           (declare (ignore text))
           (rpc-success
            id type
            (cadr-ai::json-object
             "cancelled"
             (not (null cancelled-p)))))))
      ((string= type "get_fork_messages")
       (rpc-success
        id type
        (cadr-ai::json-object
         "messages"
         (coerce
          (loop
            for entry in
            (cadr-agent:session-entries session)
            for text =
              (rpc-entry-user-text entry)
            when
            (and text
                 (plusp (length text)))
              collect
              (cadr-ai::json-object
               "entryId"
               (cadr-agent:session-entry-id
                entry)
               "text" text))
          'vector))))
      ((string= type "get_entries")
       (let* ((entries
                (cadr-agent:session-entries session))
              (since
                (cadr-ai::json-get
                 object "since")))
         (when since
           (let ((position
                   (position
                    since entries
                    :key
                    #'cadr-agent:session-entry-id
                    :test #'string=)))
             (unless position
               (error "Entry not found: ~A"
                      since))
             (setf entries
                   (nthcdr
                    (1+ position)
                    entries))))
         (rpc-success
          id type
          (cadr-ai::json-object
           "entries"
           (coerce
            (mapcar
             #'cadr-agent::session-entry-to-json
             entries)
            'vector)
           "leafId"
           (rpc-json-nullable
            (cadr-agent:session-leaf-id
             session))))))
      ((string= type "get_tree")
       (rpc-success
        id type
        (cadr-ai::json-object
         "tree"
         (rpc-session-tree session)
         "leafId"
         (rpc-json-nullable
          (cadr-agent:session-leaf-id
           session)))))
      ((string= type "get_last_assistant_text")
       (rpc-success
        id type
        (cadr-ai::json-object
         "text"
         (rpc-json-nullable
          (rpc-last-assistant-text
           agent)))))
      ((string= type "set_session_name")
       (let ((name
               (string-trim
                '(#\Space #\Tab
                  #\Newline #\Return)
                (require-rpc-string
                 object "name"))))
         (when (zerop (length name))
           (error
            "Session name cannot be empty"))
         (if (cadr-agent::agent-extension-host
              agent)
             (cadr-agent::extension-host-set-session-name
              (cadr-agent::agent-extension-host
               agent)
              name)
             (cadr-agent:session-set-name
              session name))
         (rpc-success id type)))
      ((string= type "get_messages")
       (rpc-success
        id type
        (cadr-ai::json-object
         "messages"
         (coerce
          (mapcar
           #'cadr-agent::message-to-json
           (cadr-agent:agent-messages
            agent))
          'vector))))
      ((string= type "get_commands")
       (rpc-success
        id type
        (cadr-ai::json-object
         "commands"
         (rpc-command-list state))))
      (t
       (rpc-failure
        id type
        (format nil "Unknown command: ~A"
                type))))))

(defun rpc-handle-line (state line)
  (handler-case
      (let ((object
              (cadr-ai::parse-json line)))
        (require-rpc-object object)
        (if
            (string=
             (or
              (cadr-ai::json-get object "type")
              "")
             "extension_ui_response")
            (rpc-handle-ui-response
             state object)
            (handler-case
                (let ((response
                        (rpc-handle-command
                         state object)))
                  (unless
                      (eq response
                          +rpc-async-response+)
                    (rpc-write-object
                     state response)))
              (error (condition)
                (rpc-write-object
                 state
                 (rpc-failure
                  (rpc-command-id object)
                  (or
                   (cadr-ai::json-get
                    object "type")
                   "unknown")
                  condition))))))
    (error (condition)
      (rpc-write-object
       state
       (rpc-failure
        nil "parse"
        (format nil
                "Failed to parse command: ~A"
                condition))))))

(defun rpc-shutdown (state)
  (rpc-close-pending-dialogs state)
  (rpc-cancel-bash state)
  (cadr-agent:agent-abort
   (rpc-state-agent state))
  (let ((host
          (cadr-agent::agent-extension-host
           (rpc-state-agent state))))
    (when host
      (cadr-agent::run-extension-lifecycle-hooks
       host :session-shutdown
       :payload '(:reason :quit))))
  0)

(defun run-rpc-mode
    (agent extension-manager
     &key
       (input *standard-input*)
       (output *standard-output*)
       (error-output *error-output*))
  (let ((state
          (%make-rpc-state
           :agent agent
           :extension-manager extension-manager
           :input input
           :output output
           :error-output error-output)))
    (setf
     (cadr-agent::extension-host-ui-function
      (cli-extension-manager-host
       extension-manager))
     (rpc-extension-ui-callback state))
    (let ((previous
            (cadr-agent::agent-on-event agent)))
      (unwind-protect
           (progn
             (setf
              (cadr-agent::agent-on-event agent)
              (lambda (event)
                (when previous
                  (funcall previous event))
                (rpc-write-object
                 state
                 (agent-event-to-json event))))
             (read-rpc-jsonl-lines
              input
              (lambda (line)
                (rpc-handle-line state line))))
        (setf
         (cadr-agent::agent-on-event agent)
         previous)
        (rpc-shutdown state)))))
