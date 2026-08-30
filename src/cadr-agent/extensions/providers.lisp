(in-package #:cadr-agent)

(defun extension-host-tools (host)
  (let ((snapshot
          (extension-host-current-snapshot host)))
    (loop
      for definition in
      (extension-snapshot-tools snapshot)
      collect
      (let ((captured definition)
            (captured-snapshot snapshot))
        (cadr-ai:make-tool
         :name
         (extension-tool-definition-name captured)
         :description
         (extension-tool-definition-description captured)
         :parameters
         (extension-tool-definition-parameters captured)
         :constrained-sampling
         (extension-tool-definition-constrained-sampling captured)
         :execution-mode
         (extension-tool-definition-execution-mode captured)
         :executor
         (lambda (call-id arguments)
           (handler-case
               (call-with-extension-definition
                host captured-snapshot captured
                (lambda (context)
                  (let* ((prepared
                           (if (extension-tool-definition-prepare-arguments
                                captured)
                               (funcall
                                (extension-tool-definition-prepare-arguments captured)
                                arguments)
                               arguments))
                         (signal
                           (or (current-tool-cancellation-signal)
                               (make-extension-cancellation-signal)))
                         (update (current-tool-update-function)))
                    (if (extension-tool-definition-full-handler-p captured)
                        (funcall
                         (extension-tool-definition-handler captured)
                         call-id prepared signal update context)
                        (funcall
                         (extension-tool-definition-handler captured)
                         call-id prepared context)))))
             (extension-execution-error (condition)
               (error condition))
             (condition (condition)
               (error
                'extension-execution-error
                :cause condition
                :message
                (format nil
                        "Extension tool ~A from ~A failed: ~A"
                        (extension-tool-definition-name
                         captured)
                        (extension-definition-origin captured)
                        condition))))))))))

(defun extension-host-tool-metadata (host tool-name)
  (let ((definition
          (find tool-name
                (extension-snapshot-tools
                 (extension-host-current-snapshot host))
                :key #'extension-tool-definition-name
                :test #'string=)))
    (and definition
         (list :name (extension-tool-definition-name definition)
               :label (extension-tool-definition-label definition)
               :prompt-snippet
               (extension-tool-definition-prompt-snippet definition)
               :prompt-guidelines
               (copy-list
                (extension-tool-definition-prompt-guidelines definition))
               :render-shell
               (extension-tool-definition-render-shell definition)
               :source
               (extension-definition-origin definition)))))

(defun extension-host-current-active-tools (host)
  (let ((agent (extension-host-agent host)))
    (unless agent
      (error
       'extension-execution-error
       :message
       "get-active-tools requires an attached agent"))
    (mapcar
     #'cadr-ai:tool-name
     (registry-tools
      (agent-tool-registry agent)))))

(defun extension-host-set-active-tools
    (host names)
  (let ((agent (extension-host-agent host)))
    (unless agent
      (error
       'extension-execution-error
       :message
       "set-active-tools requires an attached agent"))
    (let* ((available
             (mapcar
              #'cadr-ai:tool-name
              (merged-agent-tools agent)))
           (unknown
             (set-difference
              names available :test #'string=)))
      (when unknown
        (error
         'extension-execution-error
         :message
         (format nil
                 "~D unknown active tool~:P: ~{~A~^, ~}"
                 (length unknown) unknown)))
      (setf
       (extension-host-active-tool-names host)
       (copy-list names)
       (extension-host-active-tools-overridden-p host)
       t)
      (refresh-agent-extension-tools agent)
      (copy-list names))))

(defun invalidate-extension-host-generation (host)
  (sb-thread:with-mutex
      ((extension-host-lock host))
    (incf
     (extension-host-attachment-generation host)))
  host)

(defun attach-extension-host (host agent)
  (when
      (and
       (extension-host-agent host)
       (not (eq (extension-host-agent host)
                agent)))
    (invalidate-extension-host-generation host))
  (setf (extension-host-agent host) agent
        (extension-host-base-agent-provider host)
        (agent-provider agent)
        (extension-host-base-agent-model host)
        (agent-model agent)
        (agent-extension-host agent) host)
  (unless (extension-host-send-message-function host)
    (setf
     (extension-host-send-message-function host)
     (lambda (message &key trigger-turn-p deliver-as)
       (extension-host-send-message
        host message
        :trigger-turn-p trigger-turn-p
        :deliver-as deliver-as))))
  (unless (extension-host-send-user-message-function host)
    (setf
     (extension-host-send-user-message-function host)
     (lambda (content &key deliver-as)
       (extension-host-send-user-message
        host content :deliver-as deliver-as))))
  (unless (extension-host-set-session-name-function host)
    (setf
     (extension-host-set-session-name-function host)
     (lambda (name)
       (extension-host-set-session-name host name))))
  (unless (extension-host-get-flag-function host)
    (setf
     (extension-host-get-flag-function host)
     (lambda (name)
       (gethash name
                (extension-host-flag-values host)))))
  (unless (extension-host-get-active-tools-function host)
    (setf
     (extension-host-get-active-tools-function host)
     (lambda ()
       (extension-host-current-active-tools host))))
  (unless (extension-host-set-active-tools-function host)
    (setf
     (extension-host-set-active-tools-function host)
     (lambda (names)
       (extension-host-set-active-tools
        host names))))
  (refresh-agent-extension-tools agent)
  (apply-extension-provider-overlays host)
  host)

(defun extension-custom-message-value
    (message key &optional default)
  (getf message key default))

(defun extension-custom-message-p (message)
  (and
   (listp message)
   (stringp
    (extension-custom-message-value
     message :custom-type))
   (valid-custom-message-content-p
    (extension-custom-message-value
     message :content))))

(defun extension-custom-message-as-user-message (message)
  (cadr-ai:make-user-message
   :content
   (extension-custom-message-value
    message :content)))

(defun persist-extension-custom-message (agent message)
  (let ((session (agent-session agent)))
    (when session
      (session-append-custom-message
       session
       (extension-custom-message-value
        message :custom-type)
       (extension-custom-message-value
        message :content)
       :details
       (extension-custom-message-value
        message :details)
       :display-p
       (extension-custom-message-value
        message :display-p))))
  message)

(defun append-extension-custom-message (host agent message)
  (persist-extension-custom-message agent message)
  (when
      (and
       (extension-custom-message-value message :display-p)
       (extension-host-ui-function host))
    (funcall
     (extension-host-ui-function host)
     :append-custom-message
     (copy-tree message)))
  message)

(defun flush-pending-custom-messages (host)
  ;; pi@b79e4cc83 agent-session.ts #8537: context-only custom messages
  ;; queued during a run land after the turn's tool results.
  (unless host
    (return-from flush-pending-custom-messages nil))
  (let ((pending
          (nreverse
           (extension-host-pending-custom-messages host)))
        (agent (extension-host-agent host)))
    (setf (extension-host-pending-custom-messages host) nil)
    (when agent
      (dolist (message pending)
        (append-extension-custom-message host agent message)))))

(defun flush-agent-pending-custom-messages (agent)
  (when agent
    (flush-pending-custom-messages
     (agent-extension-host agent))))

(defun deliver-extension-message
    (agent message deliver-as)
  (ecase deliver-as
    (:steer (agent-steer agent message))
    (:follow-up (agent-follow-up agent message))
    (:next-turn (agent-next-turn agent message))))

(defun extension-host-send-message
    (host message &key trigger-turn-p deliver-as)
  (let ((agent (extension-host-agent host)))
    (unless agent
      (error
       'extension-execution-error
       :message "send-message requires an attached agent"))
    (let ((queued-message
            (cond
              ((extension-custom-message-p message)
               (if (and (agent-busy-p agent)
                        (not trigger-turn-p)
                        (null deliver-as))
                   (progn
                     (setf
                      (extension-host-pending-custom-messages host)
                      (nconc
                       (extension-host-pending-custom-messages host)
                       (list (copy-tree message))))
                     (extension-custom-message-as-user-message
                      message))
                   (progn
                     (append-extension-custom-message
                      host agent message)
                     (extension-custom-message-as-user-message
                      message))))
              ((typep message 'cadr-ai:user-message)
               message)
              (t
               (error
                'extension-execution-error
                :message
                "send-message requires a custom message plist or USER-MESSAGE")))))
      (cond
        (deliver-as
         (deliver-extension-message
          agent queued-message deliver-as))
        ((and trigger-turn-p
              (agent-busy-p agent))
         ;; Baseline agent-session.ts:1452-1457: isStreaming + triggerTurn
         ;; without deliverAs followUp steers. cadr used to error with
         ;; DELIVER-AS, which left a half-played tic-tac-toe board.
         (deliver-extension-message
          agent queued-message :steer))
        (trigger-turn-p
         (agent-prompt agent queued-message))
        (t message)))))

(defun extension-host-send-user-message
    (host content &key deliver-as)
  (let ((agent (extension-host-agent host)))
    (unless agent
      (error
       'extension-execution-error
       :message
       "send-user-message requires an attached agent"))
    (let ((message
            (if (typep content 'cadr-ai:user-message)
                content
                (handler-case
                    (cadr-ai:make-user-message
                     :content content)
                  (error (condition)
                    (error
                     'extension-execution-error
                     :cause condition
                     :message
                     "send-user-message requires valid user content"))))))
      (cond
        (deliver-as
         (multiple-value-bind
               (processed handled-p)
             (apply-agent-input-hooks
              agent message :extension
              :streaming-behavior deliver-as)
           (unless handled-p
             (deliver-extension-message
              agent processed deliver-as))))
        ((agent-busy-p agent)
         (error
          'extension-execution-error
          :message
          "send-user-message requires DELIVER-AS while the agent is running"))
        (t
         (agent-prompt
          agent message
          :source :extension))))))

(defun extension-host-set-session-name (host name)
  (let* ((agent (extension-host-agent host))
         (session (and agent (agent-session agent))))
    (unless session
      (error
       'extension-execution-error
       :message
       "set-session-name requires an attached session"))
    (session-set-name session name)
    (run-extension-lifecycle-hooks
     host :session-info-changed
     :payload (list :name (session-name session)))
    (session-name session)))

(defun extension-host-provider-definitions (host)
  (let ((seen (make-hash-table))
        (result nil))
    (dolist
        (bundle
         (extension-snapshot-bundles
          (extension-host-current-snapshot host)))
      (dolist (entry (extension-bundle-providers bundle))
        (unless (gethash (extension-provider-id entry) seen)
          (setf
           (gethash (extension-provider-id entry) seen)
           t)
          (push entry result))))
    (nreverse result)))

(defun extension-host-native-providers (host)
  (mapcar
   #'extension-native-provider-definition-provider
   (extension-snapshot-native-providers
    (extension-host-current-snapshot host))))

(defun metadata-model-copy (metadata)
  (cadr-ai:make-model
   :id (cadr-ai:model-metadata-id metadata)
   :name (cadr-ai:model-metadata-name metadata)
   :provider (cadr-ai:model-metadata-provider metadata)
   :api (cadr-ai:model-metadata-api metadata)
   :base-url (cadr-ai:model-metadata-base-url metadata)
   :max-tokens
   (cadr-ai:model-metadata-max-output-tokens metadata)
   :context-window
   (cadr-ai:model-metadata-context-window metadata)
   :supports-images-p
   (cadr-ai:model-metadata-supports-images-p metadata)
   :supports-tools-p
   (cadr-ai:model-metadata-supports-tools-p metadata)
   :reasoning-p
   (cadr-ai:model-metadata-reasoning-p metadata)
   :thinking-level-map
   (cadr-ai:model-metadata-thinking-level-map metadata)
   :headers (cadr-ai:model-metadata-headers metadata)
   :compat (cadr-ai:model-metadata-compat metadata)))

(defun provider-overlay-model
    (entry model)
  (let* ((definition
           (extension-provider-definition-definition entry))
         (metadata
           (find
            (cadr-ai:model-id model)
            (extension-provider-definition-models entry)
            :key #'cadr-ai:model-metadata-id
            :test #'string=)))
    (if metadata
        (metadata-model-copy metadata)
        (cadr-ai:make-model
         :id (cadr-ai:model-id model)
         :name (cadr-ai::model-name model)
         :provider (cadr-ai:model-provider model)
         :api
         (or
          (cadr-ai:provider-definition-protocol definition)
          (cadr-ai:model-api model))
         :base-url
         (cadr-ai:provider-definition-base-url definition)
         :max-tokens (cadr-ai:model-max-tokens model)
         :context-window (cadr-ai:model-context-window model)
         :supports-images-p
         (cadr-ai:provider-definition-supports-images-p
          definition)
         :supports-tools-p
         (cadr-ai:provider-definition-supports-tools-p
          definition)
         :reasoning-p
         (cadr-ai:provider-definition-reasoning-p
          definition)
         :thinking-level-map
         (cadr-ai::model-thinking-level-map model)
         :headers (cadr-ai::model-headers model)
         :compat (cadr-ai::model-compat model)))))

(defun apply-extension-provider-overlays (host)
  (let ((agent (extension-host-agent host)))
    (when agent
      (let* ((baseline
               (or
                (extension-host-base-agent-model host)
                (agent-model agent)))
             (entry
               (and
                baseline
                (find
                 (cadr-ai:model-provider baseline)
                 (extension-host-provider-definitions host)
                 :key #'extension-provider-id))))
        (setf
         (agent-model agent)
         (if entry
             (provider-overlay-model entry baseline)
             baseline)
         (agent-provider agent)
         (or
          (extension-host-base-agent-provider host)
          (agent-provider agent))))))
  host)

(defun extension-context-register-tool
    (context tool
     &key label prompt-snippet prompt-guidelines
       constrained-sampling render-shell prepare-arguments
       render-call render-result)
  (assert-active-extension-context context)
  (unless (typep tool 'cadr-ai:tool)
    (error
     'extension-execution-error
     :message "register-tool requires a CADR-AI:TOOL"))
  (let* ((host (%extension-context-host context))
         (bundle (%extension-context-bundle context))
         (name (cadr-ai:tool-name tool))
         (definition
           (make-extension-tool-definition
            :name name
            :label (or label name)
            :description (cadr-ai:tool-description tool)
            :prompt-snippet prompt-snippet
            :prompt-guidelines (copy-list prompt-guidelines)
            :parameters (cadr-ai:tool-parameters tool)
            :constrained-sampling constrained-sampling
            :render-shell render-shell
            :prepare-arguments prepare-arguments
            :execution-mode
            (cadr-ai:tool-execution-mode tool)
            :handler
            (lambda (call-id arguments ignored-context)
              (declare (ignore ignored-context))
              (funcall
               (cadr-ai:tool-executor tool)
               call-id arguments))
            :render-call render-call
            :render-result render-result
            :bundle bundle)))
    (validate-extension-resource-name "tool" name)
    (validate-extension-schema
     name (cadr-ai:tool-parameters tool))
    (unless (and (stringp (or label name))
                 (or (null prompt-snippet) (stringp prompt-snippet))
                 (listp prompt-guidelines)
                 (every #'stringp prompt-guidelines)
                 (or (null prepare-arguments)
                     (functionp prepare-arguments))
                 (or (null render-call) (functionp render-call))
                 (or (null render-result) (functionp render-result)))
      (error 'extension-execution-error
             :message "register-tool metadata is invalid"))
    (setf
     (extension-bundle-tools bundle)
     (nconc
      (remove
       name
       (extension-bundle-tools bundle)
       :key #'extension-tool-definition-name
       :test #'string=)
      (list definition)))
    (replace-extension-bundles
     host
     (extension-snapshot-bundles
      (extension-host-current-snapshot host)))
    tool))

(defun extension-context-register-provider
    (context definition &key models)
  (assert-active-extension-context context)
  (handler-case
      (validate-extension-provider definition models)
    (extension-registration-error (condition)
      (error
       'extension-execution-error
       :cause condition
       :message (princ-to-string condition))))
  (let* ((host (%extension-context-host context))
         (bundle (%extension-context-bundle context))
         (id (cadr-ai:provider-definition-id definition))
         (entry
           (make-extension-provider-definition
            :definition definition
            :models (copy-list models)
            :bundle bundle)))
    (setf
     (extension-bundle-providers bundle)
     (nconc
      (remove
       id
       (extension-bundle-providers bundle)
       :key #'extension-provider-id)
      (list entry)))
    (replace-extension-bundles
     host
     (extension-snapshot-bundles
      (extension-host-current-snapshot host)))
    definition))
