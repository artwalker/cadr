(in-package #:cadr-agent)

(defstruct agent-event
  type
  message
  stream-event
  tool-call
  tool-result
  tool-results
  error-message)

(defstruct (agent
            (:constructor %make-agent))
  provider
  model
  (system-prompt nil :type (or null string))
  (messages nil :type list)
  (base-tools nil :type list)
  tool-registry
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
  (busy-p nil :type boolean)
  (state-lock
    (sb-thread:make-mutex :name "cadr-agent-state"))
  (event-lock
    (sb-thread:make-mutex :name "cadr-agent-events")))

(defun emit-agent-event (agent type
                         &key
                           message
                           stream-event
                           tool-call
                           tool-result
                           tool-results
                           error-message)
  (let ((event
          (make-agent-event
           :type type
           :message message
           :stream-event stream-event
           :tool-call tool-call
           :tool-result tool-result
           :tool-results tool-results
           :error-message error-message)))
    (when (agent-on-event agent)
      (sb-thread:with-mutex
          ((agent-event-lock agent))
        (funcall (agent-on-event agent) event)))
    event))
