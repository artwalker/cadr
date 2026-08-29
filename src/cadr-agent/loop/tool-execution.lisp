(in-package #:cadr-agent)

(defun make-truncated-tool-result (call)
  (make-error-tool-result
   call
   (format
    nil
    "Tool call ~S was not executed: the response hit the output token limit, so its arguments may be truncated. Re-issue the tool call with complete arguments."
    (cadr-ai:tool-call-name call))))

(defun emit-tool-outcome (agent outcome)
  (let ((call (tool-outcome-call outcome))
        (result (tool-outcome-result outcome)))
    (run-agent-lifecycle
     agent :tool-execution-end
     (append
      (list
       :tool-call-id (cadr-ai:tool-call-id call)
       :tool-name (cadr-ai:tool-call-name call)
       :result result
       :error-p
       (cadr-ai:tool-result-message-is-error result))
      (when (tool-outcome-terminate-p outcome)
        (list :terminate-p t)))))
  (emit-agent-event
   agent :tool-execution-end
   :tool-call (tool-outcome-call outcome)
   :tool-result (tool-outcome-result outcome)))

(defun emit-tool-update (agent call partial-result)
  (run-agent-lifecycle
   agent :tool-execution-update
   (list
    :tool-call-id (cadr-ai:tool-call-id call)
    :tool-name (cadr-ai:tool-call-name call)
    :arguments (cadr-ai:tool-call-arguments call)
    :partial-result partial-result))
  (emit-agent-event
   agent :tool-execution-update
   :tool-call call
   :tool-result partial-result))

(defun finalize-tool-outcome (agent outcome turn-index)
  (if (not (agent-extension-host agent))
      outcome
      (multiple-value-bind
            (replacement appended blocked-p reason
             terminate-p terminate-supplied-p)
          (run-extension-hooks
           (agent-extension-host agent)
           :tool-call-after
           :turn-index turn-index
           :tool-call (tool-outcome-call outcome)
           :tool-result (tool-outcome-result outcome))
        (declare (ignore blocked-p reason))
        (setf
         (tool-outcome-result outcome) replacement
         (tool-outcome-appended-messages outcome)
         (nconc
          (tool-outcome-appended-messages outcome)
          appended))
        (when terminate-supplied-p
          (setf
           (tool-outcome-terminate-p outcome)
           (eq terminate-p t)))
        outcome)))

(defvar *tool-result-image-normalize-function* nil
  "When bound, called with a tool result's content blocks to
normalize image blocks entering session history (pi@b79e4cc83
core/agent-session.ts:517-520).  Bound by cadr-cli, where the image
pipeline lives.")

(defun complete-tool-outcome (agent outcome turn-index)
  (let ((final
          (finalize-tool-outcome
           agent outcome turn-index)))
    ;; Runs after the extension hook so images injected or replaced by
    ;; extensions are normalized too.
    (when *tool-result-image-normalize-function*
      (let* ((result (tool-outcome-result final))
             (content
               (cadr-ai:tool-result-message-content result))
             (normalized
               (and content
                    (funcall
                     *tool-result-image-normalize-function*
                     content))))
        (when (and normalized
                   (not (eq normalized content)))
          (setf
           (cadr-ai:tool-result-message-content result)
           normalized))))
    (emit-tool-outcome agent final)
    final))

(defun tool-outcomes-values (agent outcomes)
  (let ((results nil))
    (loop for outcome across outcomes
          do
          (let* ((initial
                   (tool-outcome-result outcome))
                 (result
                   (progn
                     (emit-message-start
                      agent initial)
                     (emit-message-end
                      agent initial))))
            (setf
             (tool-outcome-result outcome)
             result)
            (push result results)))
    (values
     (nreverse results)
     (loop
       for outcome across outcomes
       append
       (copy-list
        (tool-outcome-appended-messages outcome))))))

(defun tool-outcomes-terminate-p (outcomes)
  (and
   (plusp (length outcomes))
   (loop
     for outcome across outcomes
     always (tool-outcome-terminate-p outcome))))

(defstruct tool-restart-state
  agent
  original-call
  current-call
  current-arguments
  (current-appended-messages nil :type list)
  (prior-appended-messages nil :type list)
  (attempt 1 :type (integer 1 *))
  (abort-p nil :type boolean))

(defun make-tool-restart-state-for-call (agent call)
  (make-tool-restart-state
   :agent agent
   :original-call call
   :current-call call
   :current-arguments
   (cadr-ai:tool-call-arguments call)))

(defun tool-restart-state-effective-call
    (state call appended-messages)
  (setf
   (tool-restart-state-current-call state) call
   (tool-restart-state-current-arguments state)
   (cadr-ai:tool-call-arguments call)
   (tool-restart-state-current-appended-messages state)
   appended-messages))

(defun accumulate-tool-restart-messages (state)
  (setf
   (tool-restart-state-prior-appended-messages state)
   (nconc
    (tool-restart-state-prior-appended-messages state)
    (copy-list
     (tool-restart-state-current-appended-messages
      state)))
   (tool-restart-state-current-appended-messages state)
   nil))

(defun finish-tool-restart-outcome (state outcome)
  (setf
   (tool-outcome-appended-messages outcome)
   (nconc
    (copy-list
     (tool-restart-state-prior-appended-messages state))
    (tool-outcome-appended-messages outcome)))
  outcome)

(defun run-tool-call-error-hooks
    (state condition turn-index)
  (declare (ignore turn-index))
  (let* ((agent (tool-restart-state-agent state))
         (host (agent-extension-host agent)))
    (when host
      (let ((result
              (run-extension-lifecycle-hooks
               host :tool-call-error
               :payload
               (list
                :condition condition
                :tool-call
                (tool-restart-state-current-call state)
                :arguments
                (tool-restart-state-current-arguments state)
                :attempt
                (tool-restart-state-attempt state)
                :restart-names
                '(retry-tool-call
                  skip-tool-call
                  abort-agent-run)))))
        (when result
          (ecase (getf result :action)
            (:retry
             (invoke-restart
              'retry-tool-call
              (copy-extension-value
               (getf result :arguments))))
            (:skip
             (invoke-restart
              'skip-tool-call
              (getf result :reason)))
            (:abort
             (invoke-restart
              'abort-agent-run
              (getf result :reason)))))))))

(defun call-tool-operation-with-restarts
    (state turn-index function)
  (let ((failure nil)
        (failure-tag (gensym "TOOL-FAILURE"))
        (failure-marker (gensym "TOOL-FAILURE-MARKER")))
    (restart-case
        (let ((value
                (catch failure-tag
                  (let ((*tool-execution-error-fallback*
                          (lambda (condition)
                            (throw failure-tag
                              (cons failure-marker condition)))))
                    (handler-bind
                        ((tool-execution-error
                           (lambda (condition)
                             (setf failure condition)
                             (run-tool-call-error-hooks
                              state condition turn-index)
                             ;; Transfer before outer error handlers (including
                             ;; test runners) can mistake this continuable
                             ;; signal for an uncaught failure.
                             (funcall
                              *tool-execution-error-fallback*
                              condition))))
                      (funcall function))))))
          (if (and (consp value)
                   (eq failure-marker (car value)))
              (let ((condition (cdr value)))
                (setf failure condition)
                (values
                 (make-error-tool-result
                  (tool-restart-state-current-call state)
                  (cadr-ai:cadr-error-message condition)
                  (tool-restart-state-current-appended-messages
                   state))
                 nil))
              (values value nil)))
      (retry-tool-call (replacement-arguments)
        (unless (hash-table-p replacement-arguments)
          (error
           'cadr-ai:configuration-error
           :message
           "RETRY-TOOL-CALL requires a JSON object hash-table"))
        (accumulate-tool-restart-messages state)
        (incf (tool-restart-state-attempt state))
        (let ((original
                (tool-restart-state-original-call state)))
          (setf
           (tool-restart-state-current-call state)
           (cadr-ai:make-tool-call
            :id (cadr-ai:tool-call-id original)
            :name (cadr-ai:tool-call-name original)
            :arguments replacement-arguments)
           (tool-restart-state-current-arguments state)
           replacement-arguments))
        (values nil :retry))
      (skip-tool-call (&optional reason)
        (values
         (make-error-tool-result
          (tool-restart-state-current-call state)
          (or reason
              (and failure
                   (cadr-ai:cadr-error-message failure)))
          (tool-restart-state-current-appended-messages
           state))
         nil))
      (abort-agent-run (&optional reason)
        (setf (tool-restart-state-abort-p state) t)
        (agent-abort (tool-restart-state-agent state))
        (values
         (make-error-tool-result
          (tool-restart-state-current-call state)
          (or reason
              (and failure
                   (cadr-ai:cadr-error-message failure)))
          (tool-restart-state-current-appended-messages
           state))
         nil)))))

(defun prepare-tool-restart-state
    (state turn-index)
  (loop
    (multiple-value-bind (entry decision)
        (call-tool-operation-with-restarts
         state turn-index
         (lambda ()
           (prepare-tool-execution
            (tool-restart-state-agent state)
            (tool-restart-state-current-call state)
            :turn-index turn-index
            :on-effective-call
            (lambda (call appended-messages)
              (tool-restart-state-effective-call
               state call appended-messages)))))
      (unless (eq decision :retry)
        (return entry)))))

(defun execute-tool-restart-state
    (state prepared turn-index)
  (loop
    with entry = prepared
    do
    (when (typep entry 'tool-outcome)
      (return
       (finish-tool-restart-outcome state entry)))
    (setf
     (tool-restart-state-current-call state)
     (prepared-tool-call-call entry)
     (tool-restart-state-current-arguments state)
     (prepared-tool-call-arguments entry)
     (tool-restart-state-current-appended-messages state)
     (prepared-tool-call-appended-messages entry))
    (multiple-value-bind (outcome decision)
        (call-tool-operation-with-restarts
         state turn-index
         (lambda ()
           (let* ((agent
                    (tool-restart-state-agent state))
                  (signal
                    (make-extension-cancellation-signal
                     :aborted-function
                     (lambda ()
                       (agent-aborted-p agent))
                     :abort-function
                     (lambda ()
                       (agent-abort agent))))
                  (*tool-abort-p*
                    (lambda ()
                      (agent-aborted-p agent))))
             (execute-prepared-tool
              entry
              :cancellation-signal signal
              :on-update
              (lambda (partial-result)
                (emit-tool-update
                 agent
                 (prepared-tool-call-call entry)
                 partial-result))))))
      (if (eq decision :retry)
          (setf entry
                (prepare-tool-restart-state
                 state turn-index))
          (return
           (finish-tool-restart-outcome
            state outcome))))))

(defun execute-tool-batch
    (agent calls &key turn-index)
  (dolist (call calls)
    (run-agent-lifecycle
     agent :tool-execution-start
     (list
      :tool-call-id (cadr-ai:tool-call-id call)
      :tool-name (cadr-ai:tool-call-name call)
      :arguments (cadr-ai:tool-call-arguments call)))
    (emit-agent-event agent :tool-execution-start
                      :tool-call call))
  (let* ((states
           (mapcar
            (lambda (call)
              (make-tool-restart-state-for-call
               agent call))
            calls))
         (prepared
           (mapcar
            (lambda (state)
              (prepare-tool-restart-state
               state turn-index))
            states))
         (parallel-p
           (every
            (lambda (entry)
              (or (typep entry 'tool-outcome)
                  (eq :parallel
                      (cadr-ai:tool-execution-mode
                       (prepared-tool-call-tool entry)))))
            prepared))
         (runnable
           (count-if
            (lambda (entry)
              (not (typep entry 'tool-outcome)))
            prepared))
         (outcomes
           (make-array (length prepared)
                       :initial-element nil)))
    ;; pi executeToolCallsParallel is Promise.all on the same
    ;; event loop. One parallel tool still paid pthread_create
    ;; (sprof pthread_sigmask 53% of agent_tool_loop). Spawn
    ;; threads only when two or more calls actually run.
    (if (and parallel-p (> runnable 1))
        (let ((threads nil))
          (loop for entry in prepared
                for state in states
                for index from 0
                do
                (if (typep entry 'tool-outcome)
                    (progn
                      (setf
                       (aref outcomes index)
                      (complete-tool-outcome
                        agent
                        (finish-tool-restart-outcome
                         state entry)
                        turn-index)))
                    (let ((thread-entry entry)
                          (thread-state state)
                          (thread-index index))
                      (push
                       (sb-thread:make-thread
                        (lambda ()
                          (let ((outcome
                                  (complete-tool-outcome
                                   agent
                                   (execute-tool-restart-state
                                    thread-state
                                    thread-entry
                                    turn-index)
                                   turn-index)))
                            (setf (aref outcomes thread-index)
                                  outcome)))
                        :name
                        (format nil "cadr-tool-~A"
                                (cadr-ai:tool-call-name
                                 (prepared-tool-call-call
                                  thread-entry))))
                       threads))))
          (dolist (thread threads)
            (cadr-core:join-active-thread
             thread
             :reason
             "collect every parallel tool result before committing the turn")))
        (map-into
         outcomes
         (lambda (entry state)
           (complete-tool-outcome
            agent
            (if (typep entry 'tool-outcome)
                (finish-tool-restart-outcome
                 state entry)
                (execute-tool-restart-state
                 state entry turn-index))
            turn-index))
         prepared
         states))
    (multiple-value-bind (results appended)
        (tool-outcomes-values agent outcomes)
      (values
       results appended
       (some #'tool-restart-state-abort-p
             states)
       (tool-outcomes-terminate-p outcomes)))))

(defun execute-truncated-tool-batch
    (agent calls &key turn-index)
  (let ((outcomes
          (make-array (length calls)
                      :initial-element nil)))
    (map-into
     outcomes
     (lambda (call)
       (run-agent-lifecycle
        agent :tool-execution-start
        (list
         :tool-call-id (cadr-ai:tool-call-id call)
         :tool-name (cadr-ai:tool-call-name call)
         :arguments
         (cadr-ai:tool-call-arguments call)))
       (emit-agent-event
        agent :tool-execution-start
        :tool-call call)
       (complete-tool-outcome
        agent
        (make-truncated-tool-result call)
        turn-index))
     calls)
    (tool-outcomes-values agent outcomes)))

