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

(defun refresh-agent-extension-tools (agent)
  (let* ((filtered
           (funcall
            (agent-tool-filter-function agent)
            (merged-agent-tools agent)))
         (host (agent-extension-host agent))
         (effective
           (if
               (and
                host
                (extension-host-active-tools-overridden-p
                 host))
               (remove-if-not
                (lambda (tool)
                  (member
                   (cadr-ai:tool-name tool)
                   (extension-host-active-tool-names
                    host)
                   :test #'string=))
                filtered)
               filtered)))
    (setf
     (agent-tool-registry agent)
     (make-tool-registry effective)))
  agent)

(defun make-agent (&key
                         provider
                         model
                         system-prompt
                         messages
                         tools
                         (tool-filter-function #'identity)
                         extension-host
                         session
                         (stream-function #'cadr-ai:stream-chat)
                         on-event
                         (max-turns 100)
                         (auto-compact-p t)
                         (compaction-reserve-tokens 16384)
                         (compaction-keep-recent-tokens 20000)
                         abort-p)
  (let ((agent
          (%make-agent
           :provider provider
           :model model
           :system-prompt system-prompt
           :messages
           (copy-list
            (or messages
                (and session
                     (session-messages session))))
           :base-tools (copy-list tools)
           :tool-registry (make-tool-registry tools)
           :tool-filter-function tool-filter-function
           :extension-host extension-host
           :session session
           :stream-function stream-function
           :on-event on-event
           :max-turns max-turns
           :auto-compact-p auto-compact-p
           :compaction-reserve-tokens
           compaction-reserve-tokens
           :compaction-keep-recent-tokens
           compaction-keep-recent-tokens
           :abort-p abort-p)))
    (when extension-host
      (attach-extension-host extension-host agent))
    agent))

(defstruct prepared-tool-call
  call
  tool
  arguments
  appended-messages)

(defstruct tool-outcome
  call
  result
  appended-messages)

(defun make-error-tool-result
    (call text &optional appended-messages)
  (make-tool-outcome
   :call call
   :appended-messages appended-messages
   :result
   (cadr-ai:make-tool-result-message
    :tool-call-id (cadr-ai:tool-call-id call)
    :tool-name (cadr-ai:tool-call-name call)
    :content (list (cadr-ai:make-text-content :text text))
    :is-error t)))

(defun prepare-tool-execution
    (agent call &key turn-index)
  (let ((effective-call call)
        (appended-messages nil))
    (when (agent-extension-host agent)
      (multiple-value-bind
            (replacement appended blocked-p reason)
          (run-extension-hooks
           (agent-extension-host agent)
           :tool-call-before
           :turn-index turn-index
           :tool-call effective-call)
        (setf effective-call replacement
              appended-messages appended)
        (when blocked-p
          (return-from prepare-tool-execution
            (make-error-tool-result
             effective-call
             (or reason "Tool execution was blocked")
             appended-messages)))))
    (let ((tool
            (find-tool
             (agent-tool-registry agent)
             (cadr-ai:tool-call-name effective-call))))
    (unless tool
      (return-from prepare-tool-execution
        (make-error-tool-result
         effective-call
         (format nil "Tool ~A not found"
                 (cadr-ai:tool-call-name effective-call))
         appended-messages)))
    (handler-case
        (let ((arguments
                (validate-tool-arguments
                 tool
                 (cadr-ai:tool-call-arguments
                  effective-call))))
          (make-prepared-tool-call
           :call effective-call
           :tool tool
           :arguments arguments
           :appended-messages appended-messages))
      (error (condition)
        (make-error-tool-result
         effective-call
         (if (typep condition 'cadr-ai:cadr-error)
             (cadr-ai:cadr-error-message condition)
             (princ-to-string condition))
         appended-messages))))))

(defun execute-prepared-tool (prepared)
  (let ((call (prepared-tool-call-call prepared))
        (tool (prepared-tool-call-tool prepared)))
    (handler-case
        (multiple-value-bind (content details)
            (funcall
             (cadr-ai:tool-executor tool)
             (cadr-ai:tool-call-id call)
             (prepared-tool-call-arguments prepared))
          (make-tool-outcome
           :call call
           :appended-messages
           (prepared-tool-call-appended-messages
            prepared)
           :result
           (cadr-ai:make-tool-result-message
            :tool-call-id (cadr-ai:tool-call-id call)
            :tool-name (cadr-ai:tool-call-name call)
            :content (or content nil)
            :details details
            :is-error nil)))
      (error (condition)
        (make-error-tool-result
         call
         (princ-to-string condition)
         (prepared-tool-call-appended-messages
          prepared))))))
