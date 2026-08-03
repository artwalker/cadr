(in-package #:cadr-cli)

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
