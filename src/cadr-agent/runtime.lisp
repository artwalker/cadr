(in-package #:cadr-agent)

(defstruct agent-event
  type
  message
  messages
  result
  aborted
  stream-event
  tool-call
  tool-result
  tool-results
  error-message
  steering
  follow-up
  next-turn
  will-retry
  attempt
  max-attempts
  delay-ms
  success
  final-error
  source
  reason)

(defstruct (agent
            (:constructor %make-agent))
  provider
  model
  (system-prompt nil :type (or null string))
  (system-prompt-options nil :type list)
  (messages nil :type list)
  messages-tail
  messages-tail-head
  (base-tools nil :type list)
  tool-registry
  (tool-filter-function #'identity :type function)
  extension-host
  session
  stream-function
  on-event
  (max-turns 100 :type (integer 1 *))
  (auto-compact-p t :type boolean)
  (compaction-reserve-tokens 16384
                             :type (integer 1 *))
  (compaction-keep-recent-tokens 20000
                                 :type (integer 1 *))
  abort-p
  (abort-requested-p nil :type boolean)
  (busy-p nil :type boolean)
  (shutdown-p nil :type boolean)
  (operation-count 0 :type (integer 0 *))
  (mutation-count 0 :type (integer 0 *))
  (operation-threads nil :type list)
  (thinking-level :off
                  :type (member :off :minimal :low :medium
                                :high :xhigh :max))
  (auto-retry-p t :type boolean)
  (auto-retry-max-attempts 3
                           :type (integer 0 *))
  (auto-retry-base-delay 2
                         :type (real 0 *))
  (retry-attempt 0 :type (integer 0 *))
  (retry-in-progress-p nil :type boolean)
  (retry-abort-requested-p nil :type boolean)
  (steering-mode :one-at-a-time
                 :type (member :all :one-at-a-time))
  (follow-up-mode :one-at-a-time
                  :type (member :all :one-at-a-time))
  (steering-queue nil :type list)
  (follow-up-queue nil :type list)
  (next-turn-queue nil :type list)
  (state-lock
    (sb-thread:make-mutex :name "cadr-agent-state"))
  (queue-lock
    (sb-thread:make-mutex :name "cadr-agent-queues"))
  (idle-condition
    (sb-thread:make-waitqueue :name "cadr-agent-idle"))
  (retry-condition
    (sb-thread:make-waitqueue :name "cadr-agent-retry"))
  (event-lock
    (sb-thread:make-mutex :name "cadr-agent-events")))

(defun emit-agent-event (agent type
                         &key
                           message
                           messages
                           result
                           aborted
                           stream-event
                           tool-call
                           tool-result
                           tool-results
                           error-message
                           steering
                           follow-up
                           next-turn
                           will-retry
                           attempt
                           max-attempts
                           delay-ms
                           success
                           final-error
                           source
                           reason)
  (let ((event
          (make-agent-event
           :type type
           :message message
           :messages messages
           :result result
           :aborted aborted
           :stream-event stream-event
           :tool-call tool-call
           :tool-result tool-result
           :tool-results tool-results
           :error-message error-message
           :steering steering
           :follow-up follow-up
           :next-turn next-turn
           :will-retry will-retry
           :attempt attempt
           :max-attempts max-attempts
           :delay-ms delay-ms
           :success success
           :final-error final-error
           :source source
           :reason reason)))
    (when (agent-on-event agent)
      (sb-thread:with-recursive-lock
          ((agent-event-lock agent))
        (funcall (agent-on-event agent) event)))
    event))

(defun replace-agent-system-prompt
    (agent system-prompt system-prompt-options)
  (unless (or (null system-prompt) (stringp system-prompt))
    (error 'cadr-ai:configuration-error
           :message "Agent system prompt must be a string or NIL"))
  (unless (listp system-prompt-options)
    (error 'cadr-ai:configuration-error
           :message "Agent system prompt options must be a list"))
  (sb-thread:with-mutex ((agent-state-lock agent))
    (setf
     (agent-system-prompt agent) system-prompt
     (agent-system-prompt-options agent)
     (copy-tree system-prompt-options)))
  agent)

(defun normalize-agent-queue-message (message)
  (etypecase message
    (string
     (cadr-ai:make-user-message :content message))
    (cadr-ai:user-message message)))

(defun agent-queue-snapshot (agent)
  (sb-thread:with-mutex
      ((agent-queue-lock agent))
    (values
     (copy-list (agent-steering-queue agent))
     (copy-list (agent-follow-up-queue agent))
     (copy-list (agent-next-turn-queue agent)))))

(defun emit-agent-queue-update (agent)
  (multiple-value-bind
        (steering follow-up next-turn)
      (agent-queue-snapshot agent)
    (emit-agent-event
     agent :queue-update
     :steering steering
     :follow-up follow-up
     :next-turn next-turn)))

(defun enqueue-agent-message (agent queue message)
  (assert-agent-not-shutdown agent)
  (let ((normalized
          (normalize-agent-queue-message message)))
    (sb-thread:with-mutex
        ((agent-queue-lock agent))
      (ecase queue
        (:steering
         (setf
          (agent-steering-queue agent)
          (nconc
           (agent-steering-queue agent)
           (list normalized))))
        (:follow-up
         (setf
          (agent-follow-up-queue agent)
          (nconc
           (agent-follow-up-queue agent)
           (list normalized))))
        (:next-turn
         (setf
          (agent-next-turn-queue agent)
          (nconc
           (agent-next-turn-queue agent)
           (list normalized))))))
    (emit-agent-queue-update agent)
    normalized))

(defun agent-steer (agent message)
  (enqueue-agent-message agent :steering message))

(defun agent-follow-up (agent message)
  (enqueue-agent-message agent :follow-up message))

(defun agent-next-turn (agent message)
  (enqueue-agent-message agent :next-turn message))

(defun drain-agent-queue (agent queue)
  (let ((drained nil)
        (changed-p nil))
    (sb-thread:with-mutex
        ((agent-queue-lock agent))
      (let* ((messages
               (ecase queue
                 (:steering
                  (agent-steering-queue agent))
                 (:follow-up
                  (agent-follow-up-queue agent))
                 (:next-turn
                  (agent-next-turn-queue agent))))
             (mode
               (ecase queue
                 (:steering
                  (agent-steering-mode agent))
                 (:follow-up
                  (agent-follow-up-mode agent))
                 (:next-turn :all))))
        (when messages
          (setf changed-p t)
          (if (eq mode :all)
              (setf drained (copy-list messages)
                    messages nil)
              (setf drained (list (first messages))
                    messages (rest messages)))
          (ecase queue
            (:steering
             (setf (agent-steering-queue agent) messages))
            (:follow-up
             (setf (agent-follow-up-queue agent) messages))
            (:next-turn
             (setf (agent-next-turn-queue agent) messages))))))
    (when changed-p
      (emit-agent-queue-update agent))
    drained))

(defun clear-live-agent-queues (agent)
  (let ((steering nil)
        (follow-up nil))
    (sb-thread:with-mutex
        ((agent-queue-lock agent))
      (setf
       steering (copy-list (agent-steering-queue agent))
       follow-up (copy-list (agent-follow-up-queue agent))
       (agent-steering-queue agent) nil
       (agent-follow-up-queue agent) nil))
    (emit-agent-queue-update agent)
    (values steering follow-up)))

(defun clear-all-agent-queues (agent)
  (sb-thread:with-mutex
      ((agent-queue-lock agent))
    (setf
     (agent-steering-queue agent) nil
     (agent-follow-up-queue agent) nil
     (agent-next-turn-queue agent) nil))
  (emit-agent-queue-update agent)
  agent)

(defun shutdown-agent-error ()
  (error
   'agent-shutdown-error
   :message "Agent has been shut down"))

(defun assert-agent-not-shutdown (agent)
  (sb-thread:with-mutex
      ((agent-state-lock agent))
    (when (agent-shutdown-p agent)
      (shutdown-agent-error)))
  agent)

(defun begin-agent-operation (agent)
  (sb-thread:with-mutex
      ((agent-state-lock agent))
    (when (agent-shutdown-p agent)
      (shutdown-agent-error))
    (incf (agent-operation-count agent))
    (push sb-thread:*current-thread*
          (agent-operation-threads agent)))
  agent)

(defun end-agent-operation (agent)
  (sb-thread:with-mutex
      ((agent-state-lock agent))
    (decf (agent-operation-count agent))
    (setf
     (agent-operation-threads agent)
     (delete
      sb-thread:*current-thread*
      (agent-operation-threads agent)
      :count 1
      :test #'eq))
    (sb-thread:condition-broadcast
     (agent-idle-condition agent)))
  agent)

(defun call-with-agent-operation (agent function)
  (begin-agent-operation agent)
  (unwind-protect
       (funcall function)
    (end-agent-operation agent)))

(defun call-with-agent-mutation (agent function)
  (sb-thread:with-mutex
      ((agent-state-lock agent))
    (when (agent-shutdown-p agent)
      (shutdown-agent-error))
    (incf (agent-mutation-count agent)))
  (unwind-protect
       (funcall function)
    (sb-thread:with-mutex
        ((agent-state-lock agent))
      (decf (agent-mutation-count agent))
      (sb-thread:condition-broadcast
       (agent-idle-condition agent)))))

(defun agent-append-message (agent message)
  (call-with-agent-mutation
   agent
   (lambda ()
     (append-agent-message agent message))))

(defun agent-set-model (agent model)
  (call-with-agent-mutation
   agent
   (lambda ()
     (when (agent-session agent)
       (session-append-model-change
        (agent-session agent)
        (string-downcase
         (symbol-name
          (cadr-ai:model-provider model)))
        (cadr-ai:model-id model)))
     (setf (agent-model agent) model)
     model)))

(defun agent-set-thinking-level (agent level)
  (unless
      (member level
              '(:off :minimal :low :medium
                :high :xhigh :max))
    (error
     'cadr-ai:configuration-error
     :message
     (format nil "Invalid thinking level: ~A" level)))
  (call-with-agent-mutation
   agent
   (lambda ()
     (when (agent-session agent)
       (session-append-thinking-level-change
        (agent-session agent)
        (string-downcase (symbol-name level))))
     (setf (agent-thinking-level agent) level)
     level)))

(defun agent-aborted-p (agent)
  (or
   (sb-thread:with-mutex
       ((agent-state-lock agent))
     (agent-abort-requested-p agent))
   (let ((predicate (agent-abort-p agent)))
     (and predicate (funcall predicate)))))

(defun agent-abort (agent)
  (assert-agent-not-shutdown agent)
  (agent-abort-retry agent)
  (sb-thread:with-mutex
      ((agent-state-lock agent))
    (setf (agent-abort-requested-p agent) t))
  (clear-live-agent-queues agent))

(defun agent-abort-retry (agent)
  (sb-thread:with-mutex
      ((agent-state-lock agent))
    (when (agent-retry-in-progress-p agent)
      (setf
       (agent-retry-abort-requested-p agent)
       t)
      (sb-thread:condition-broadcast
       (agent-retry-condition agent))))
  agent)

(defun agent-wait-for-idle (agent)
  (sb-thread:with-mutex
      ((agent-state-lock agent))
    (loop while (plusp
                 (agent-operation-count agent))
          do
          (sb-thread:condition-wait
           (agent-idle-condition agent)
           (agent-state-lock agent))))
  agent)

(defun agent-shutdown (agent)
  (let ((called-from-operation-p nil))
    (sb-thread:with-mutex
        ((agent-state-lock agent))
      (setf
       (agent-shutdown-p agent) t
       (agent-abort-requested-p agent) t
       (agent-retry-abort-requested-p agent) t
       called-from-operation-p
       (member
        sb-thread:*current-thread*
        (agent-operation-threads agent)
        :test #'eq))
      (sb-thread:condition-broadcast
       (agent-retry-condition agent)))
    (clear-all-agent-queues agent)
    (unless called-from-operation-p
      (sb-thread:with-mutex
          ((agent-state-lock agent))
        (loop while
              (or
               (plusp
                (agent-operation-count agent))
               (plusp
                (agent-mutation-count agent)))
              do
              (sb-thread:condition-wait
               (agent-idle-condition agent)
               (agent-state-lock agent))))))
  nil)
