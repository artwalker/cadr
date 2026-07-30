(in-package #:cadr-agent)

(defstruct agent-event
  type
  message
  messages
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
  final-error)

(defstruct (agent
            (:constructor %make-agent))
  provider
  model
  (system-prompt nil :type (or null string))
  (messages nil :type list)
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
                           final-error)
  (let ((event
          (make-agent-event
           :type type
           :message message
           :messages messages
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
           :final-error final-error)))
    (when (agent-on-event agent)
      (sb-thread:with-recursive-lock
          ((agent-event-lock agent))
        (funcall (agent-on-event agent) event)))
    event))

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

(defun agent-aborted-p (agent)
  (or
   (sb-thread:with-mutex
       ((agent-state-lock agent))
     (agent-abort-requested-p agent))
   (let ((predicate (agent-abort-p agent)))
     (and predicate (funcall predicate)))))

(defun agent-abort (agent)
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
    (loop while (agent-busy-p agent)
          do
          (sb-thread:condition-wait
           (agent-idle-condition agent)
           (agent-state-lock agent))))
  agent)
