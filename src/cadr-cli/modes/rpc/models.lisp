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
