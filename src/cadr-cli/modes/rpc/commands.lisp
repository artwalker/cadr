(in-package #:cadr-cli)

(defun parse-queue-mode (mode noun)
  (cond
    ((string= mode "all") :all)
    ((string= mode "one-at-a-time") :one-at-a-time)
    (t (error "Invalid ~A mode: ~A" noun mode))))

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
       (rpc-apply-input-hooks-off-reader
        state agent id type
        (rpc-prompt-message object)
        :steer))
      ((string= type "follow_up")
       (rpc-apply-input-hooks-off-reader
        state agent id type
        (rpc-prompt-message object)
        :follow-up))
      ((string= type "abort")
       (cadr-agent:agent-abort agent)
       (cadr-agent:agent-wait-for-idle agent)
       (rpc-success id type))
      ((string= type "clear_queue")
       (multiple-value-bind (steering follow-up)
           (cadr-agent::clear-live-agent-queues agent)
         (rpc-success
          id type
          (cadr-ai::json-object
           "steering"
           (coerce
            (mapcar #'tui-queued-message-text steering)
            'vector)
           "followUp"
           (coerce
            (mapcar #'tui-queued-message-text follow-up)
            'vector)))))
      ((string= type "new_session")
       (rpc-success
        id type
        (rpc-new-session state object)))
      ((string= type "get_state")
       (let ((data
               (cadr-ai::json-object
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
         (let ((model
                 (cadr-agent:agent-model
                  agent)))
           (when model
             (cadr-ai::json-put
              data "model"
              (model-to-rpc-json model))))
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
        (parse-queue-mode
         (require-rpc-string object "mode")
         "steering"))
       (rpc-success id type))
      ((string= type "set_follow_up_mode")
       (setf
        (cadr-agent:agent-follow-up-mode agent)
        (parse-queue-mode
         (require-rpc-string object "mode")
         "follow-up"))
       (rpc-success id type))
      ((string= type "compact")
       (let ((result
               (cadr-agent:compact-agent
                agent :force-p t
                :custom-instructions
                (cadr-ai::json-get
                 object "customInstructions"))))
         (rpc-success
          id type
          (if result
              (compaction-result-to-json result)
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
