(in-package #:cadr-durable)

(defstruct task-definition name version initial phases abort restart-limit)
(defstruct tool-definition name execute)
(defstruct extension-definition name setup)
(defstruct (registry (:constructor %make-registry))
  (tasks (make-hash-table :test #'equal))
  (tools (make-hash-table :test #'equal))
  (extensions nil))
(defstruct harness storage registry model now-fn on-report
           (busy nil) (parked (make-hash-table :test #'eql)) root-id (clock 0)
           telemetry reports-counter active-counter duration-histogram
           (resumed (make-hash-table :test #'eql))
           (live-tasks (make-hash-table :test #'eql))
           (clock-reported nil)
           (failed nil))
(defstruct task-runtime harness task (decision nil) (settled nil) (committed-phase nil))

(defun assert-usable-harness (harness)
  (when (harness-failed harness)
    (fail-session)))

(defun define-task (name &key (version 1) initial phases abort
                           (restart-limit +default-restart-limit+))
  (make-task-definition :name name :version version :initial initial
                        :phases phases :abort abort :restart-limit restart-limit))

(defun define-tool (name execute)
  (make-tool-definition :name name :execute execute))

(defun define-extension (name setup)
  (make-extension-definition :name name :setup setup))

(defun make-registry ()
  (%make-registry))

(defun registry-install (registry definition)
  (etypecase definition
    (task-definition
     (setf (gethash (task-definition-name definition) (registry-tasks registry))
           definition))
    (tool-definition
     (setf (gethash (tool-definition-name definition) (registry-tools registry))
           definition))
    (extension-definition
     (push definition (registry-extensions registry))))
  definition)

(defun harness-now (harness)
  (if (harness-now-fn harness)
      (funcall (harness-now-fn harness))
      (incf (harness-clock harness))))

(defun report (harness type &key reason message task extension context)
  (when (harness-on-report harness)
    (handler-case
        (let ((event (cadr-chord:json-object "type" type)))
          (when reason (cadr-chord:json-put event "reason" reason))
          (when message (cadr-chord:json-put event "message" message))
          (when extension (cadr-chord:json-put event "extension" extension))
          (when task (cadr-chord:json-put event "task" (task-record-id task)))
          (funcall (harness-on-report harness) event))
      (error () nil)))
  (when (harness-reports-counter harness)
    (cadr-telemetry:telemetry-counter-add
     (harness-reports-counter harness) 1 (list (cons "type" type))))
  (when context
    (emit-durable-event context *durable-report-event*
                        (durable-report-attributes
                         type :reason reason :extension extension :task task))))

(defun each-task (storage function)
  (let ((cursor nil))
    (loop
      (let ((page (storage-scan-tasks storage :limit 100 :cursor cursor)))
        (mapc function (page-items page))
        (setf cursor (page-next page))
        (unless cursor (return))))))

(defun task-status (task)
  (hash-get (task-record-state task) "status"))

(defun save-task (storage task state &key restarts abort-requested)
  (let ((copy (copy-task-record task)))
    (setf (task-record-state copy) state)
    (setf (task-record-restarts copy) restarts)
    (when abort-requested
      (setf (task-record-abort-requested copy) t))
    (storage-commit storage (list (cons :task copy)))
    copy))

(defun pending-state (checkpoint)
  (let ((copy (cadr-chord:copy-json checkpoint)))
    (cadr-chord:json-put copy "status" "pending")
    copy))

(defun fault-task (harness task message reason)
  (let ((state (cadr-chord:json-object
                "status" "terminal"
                "outcome" (cadr-chord:json-object
                           "status" "faulted"
                           "error" (cadr-chord:json-object "message" message)))))
    (prog1 (save-task (harness-storage harness) task state :restarts nil)
      (report harness "task_faulted" :reason reason :message message :task task
              :context *durable-span*))))

(defun runtime-commit (runtime function)
  (when (task-runtime-settled runtime)
    (error "runtime commit after the invocation ended"))
  (let ((decision (funcall function)))
    (setf (task-runtime-decision runtime) decision)
    (let* ((phase (and decision (hash-get decision "phase")))
           (status (and decision (hash-get decision "status")))
           (current (or (task-runtime-committed-phase runtime)
                        (hash-get (task-record-state (task-runtime-task runtime)) "phase"))))
      (when (and (stringp status) (string= status "running")
                 (stringp phase) (stringp current)
                 (not (string= phase current)))
        (note-durable-checkpoint phase))
      (when (and (stringp status) (string= status "running") (stringp phase))
        (setf (task-runtime-committed-phase runtime) phase)))
    decision))

(defun runtime-sleep-until (runtime until checkpoint)
  (runtime-commit runtime
                  (lambda ()
                    (let ((copy (cadr-chord:copy-json checkpoint)))
                      (cadr-chord:json-put copy "status" "sleeping")
                      (cadr-chord:json-put copy "until" until)
                      copy))))

(defun runtime-now (runtime)
  (harness-now (task-runtime-harness runtime)))

(defun checkpoint-equal-p (left right)
  (let ((a (cadr-chord:copy-json left))
        (b (cadr-chord:copy-json right)))
    (remhash "status" a)
    (remhash "status" b)
    (string= (cadr-chord:canonical-json a) (cadr-chord:canonical-json b))))

(defun note-task-active (harness task)
  (let ((id (task-record-id task)))
    (unless (gethash id (harness-live-tasks harness))
      (setf (gethash id (harness-live-tasks harness)) (task-record-kind task))
      (when (harness-active-counter harness)
        (cadr-telemetry:telemetry-counter-add
         (harness-active-counter harness) 1
         (list (cons "task" (task-record-kind task))))))))

(defun note-task-inactive (harness task)
  (let* ((id (task-record-id task))
         (kind (gethash id (harness-live-tasks harness))))
    (when kind
      (remhash id (harness-live-tasks harness))
      (when (harness-active-counter harness)
        (cadr-telemetry:telemetry-counter-add
         (harness-active-counter harness) -1
         (list (cons "task" kind)))))))

(defun phase-outcome-text (task start-phase)
  (let* ((state (task-record-state task))
         (status (or (hash-get state "status") ""))
         (terminal (and (string= status "terminal") (hash-get state "outcome")))
         (name (and terminal (hash-get terminal "status"))))
    (cond
      ((and name (string= name "completed")) "done")
      ((and name (string= name "aborted")) "aborted")
      (name "faulted")
      ((member status '("waiting" "sleeping") :test #'string=) status)
      ((and (hash-get state "phase")
            (not (string= (hash-get state "phase") (or start-phase ""))))
       (format nil "next=~A" (hash-get state "phase")))
      ((string= status "pending")
       (format nil "next=~A" (or (hash-get state "phase") start-phase)))
      (t "aborted"))))

(defun finish-phase-span (harness task span started start-phase)
  (let* ((state (task-record-state task))
         (status (or (hash-get state "status") ""))
         (terminal (and (string= status "terminal") (hash-get state "outcome")))
         (name (and terminal (hash-get terminal "status")))
         (outcome (phase-outcome-text task start-phase)))
    (cadr-telemetry:telemetry-set-attributes span (list (cons "outcome" outcome)))
    (cond
      ((member name '("faulted" "failed" "orphaned") :test #'string=)
       (let* ((error-object (hash-get terminal "error"))
              (message (if (string= name "orphaned")
                           (or (hash-get terminal "reason") "")
                           (or (and error-object (hash-get error-object "message"))
                               (hash-get terminal "reason")
                               ""))))
         (cadr-telemetry:telemetry-set-status
          span :kind :error
          :error-name (format nil "task_~A" name)
          :error-message (durable-utf16-slice message 500))))
      ((string= outcome "aborted")
       (cadr-telemetry:telemetry-set-status span :kind :ok)))
    (when (harness-duration-histogram harness)
      (cadr-telemetry:telemetry-histogram-record
       (harness-duration-histogram harness)
       (- (cadr-telemetry:telemetry-monotonic-milliseconds) started)
       (list (cons "task" (task-record-kind task))
             (cons "phase" (or start-phase ""))
             (cons "outcome" outcome))
       span))
    (when (string= status "terminal")
      (note-task-inactive harness task))))

(defun phase-telemetry-parent (harness task)
  (let* ((root (or (harness-telemetry harness)
                   cadr-telemetry:*noop-telemetry-context*))
         (trace (task-record-trace task))
         (propagation (cadr-telemetry:telemetry-span-propagation root)))
    (if (or (null trace) (null propagation))
        root
        (or (cadr-telemetry:telemetry-extract propagation trace) root))))

(defun call-with-durable-phase (harness task kind start-phase body)
  (let* ((telemetry (phase-telemetry-parent harness task))
         (resumed (and (remhash (task-record-id task) (harness-resumed harness)) t))
         (attempt (hash-get (task-record-state task) "attempt"))
         (attributes (list (cons "task.id" (task-record-id task))
                           (cons "task.name" (or (task-record-kind task) ""))
                           (cons "phase" (or start-phase ""))
                           (cons "kind" kind)
                           (cons "resumed" resumed)))
         (started (cadr-telemetry:telemetry-monotonic-milliseconds)))
    (when (numberp attempt)
      (setf attributes (append attributes (list (cons "attempt" attempt)))))
    (cadr-telemetry:telemetry-start-span
     telemetry *durable-phase-span*
     (lambda (span)
       (let ((*durable-span* span)
             (observed task))
         (unwind-protect
              (setf observed (funcall body))
           (finish-phase-span harness observed span started start-phase))
         observed))
     :attributes attributes)))

(defun invoke-task (harness task)
  (when (gethash (task-record-id task) (harness-parked harness))
    (return-from invoke-task task))
  (let* ((definition (gethash (task-record-kind task)
                              (registry-tasks (harness-registry harness))))
         (runtime (make-task-runtime :harness harness :task task))
         (stop nil))
    (loop while (not stop)
          do (setf (task-runtime-decision runtime) nil
                   (task-runtime-committed-phase runtime) nil)
             (let* ((phase (hash-get (task-record-state task) "phase"))
                    (function (gethash phase (task-definition-phases definition))))
               (setf task
                     (call-with-durable-phase
                      harness task "run" phase
                      (lambda ()
                        (handler-case (funcall function task runtime)
                          (error (condition)
                            (unless (and (task-runtime-decision runtime)
                                         (equal (hash-get (task-runtime-decision runtime)
                                                          "status")
                                                "terminal"))
                              (setf task (fault-task harness task
                                                     (princ-to-string condition)
                                                     "threw"))
                              (setf (task-runtime-task runtime) task)
                              (setf stop t))))
                        (unless stop
                          (let ((decision (task-runtime-decision runtime)))
                            (cond
                              ((null decision)
                               (setf task
                                     (fault-task
                                      harness task
                                      (format nil "Task ~A phase ~A returned without durable progress"
                                              (task-record-kind task) phase)
                                      "threw"))
                               (setf stop t))
                              (t
                               (let ((status (or (hash-get decision "status") "pending")))
                                 (cond
                                   ((string= status "terminal")
                                    (setf task (save-task (harness-storage harness)
                                                          task decision))
                                    (setf stop t))
                                   ((or (string= status "sleeping")
                                        (string= status "waiting"))
                                    (setf task (save-task (harness-storage harness)
                                                          task decision))
                                    (setf stop t))
                                   ((checkpoint-equal-p decision
                                                        (task-record-state task))
                                    (setf task
                                          (fault-task
                                           harness task
                                           (format nil "Task ~A phase ~A returned without durable progress"
                                                   (task-record-kind task) phase)
                                           "threw"))
                                    (setf stop t))
                                   (t
                                    (setf task
                                          (save-task (harness-storage harness) task
                                                     (pending-state decision)))
                                    (when (string= (hash-get decision "phase") phase)
                                      (setf stop t)))))))))
                        (setf (task-runtime-task runtime) task)
                        task)))))
    (storage-task (harness-storage harness) (task-record-id task))))

(defun recover-task (harness task)
  (when (string= (task-status task) "running")
    (let* ((definition (gethash (task-record-kind task)
                                (registry-tasks (harness-registry harness))))
           (limit (if definition (task-definition-restart-limit definition)
                      +default-restart-limit+))
           (restarts (1+ (or (task-record-restarts task) 0)))
           (pending (pending-state (task-record-state task))))
      (if (>= restarts limit)
          (progn
            (setf (gethash (task-record-id task) (harness-parked harness)) t)
            (save-task (harness-storage harness) task pending :restarts restarts)
            (report harness "task_parked" :reason "restart_limit" :task task
                    :message (format nil "Task ~A (~A) was cut off ~A times without progress; it is parked until retryTask()"
                                     (task-record-id task) (task-record-kind task) restarts)))
          (save-task (harness-storage harness) task pending :restarts restarts)))))

(defun ensure-root (storage)
  (or (storage-conversation storage +root-conversation-id+)
      (progn
        (storage-commit storage
                        (list (cons :conversation
                                    (make-conversation :id +root-conversation-id+))))
        (storage-conversation storage +root-conversation-id+))))

(defun safe-clock (harness now)
  (lambda ()
    (handler-case (funcall now)
      (error (condition)
        (unless (harness-clock-reported harness)
          (setf (harness-clock-reported harness) t)
          (report harness "host_error" :message (princ-to-string condition)))
        (cadr-telemetry:telemetry-wall-milliseconds)))))

(defun open-harness (storage &key registry model now on-report telemetry)
  (let* ((span (or telemetry cadr-telemetry:*noop-telemetry-context*))
         (instruments (durable-instruments span))
         (harness (make-harness :storage storage
                                :registry (or registry (make-registry))
                                :model model :on-report on-report
                                :telemetry span
                                :reports-counter
                                (cadr-telemetry:typed-metrics-counter
                                 instruments *durable-reports-metric*)
                                :active-counter
                                (cadr-telemetry:typed-metrics-up-down-counter
                                 instruments *durable-tasks-active-metric*)
                                :duration-histogram
                                (cadr-telemetry:typed-metrics-histogram
                                 instruments *durable-phase-duration-metric*))))
    (when now
      (setf (harness-now-fn harness) (safe-clock harness now)))
    (ensure-root storage)
    (setf (harness-root-id harness) +root-conversation-id+)
    (each-task storage
               (lambda (task)
                 (setf (gethash (task-record-id task) (harness-resumed harness)) t)))
    (each-task storage (lambda (task) (recover-task harness task)))
    (each-task storage
               (lambda (task)
                 (unless (or (string= (task-status task) "terminal")
                             (gethash (task-record-id task) (harness-parked harness)))
                   (note-task-active harness task))))
    (dolist (extension (reverse (registry-extensions (harness-registry harness))))
      (funcall (extension-definition-setup extension) harness))
    harness))

(defun harness-root (harness)
  (harness-root-id harness))

(defun task-due-p (harness task)
  (let ((state (task-record-state task)))
    (cond
      ((gethash (task-record-id task) (harness-parked harness)) nil)
      ((string= (task-status task) "pending") t)
      ((string= (task-status task) "sleeping")
       (>= (harness-now harness) (or (hash-get state "until") 0)))
      ((string= (task-status task) "waiting")
       (let ((on (hash-get state "on")))
         (every (lambda (id)
                  (let ((other (storage-task (harness-storage harness) id)))
                    (and other (string= (task-status other) "terminal"))))
                (coerce (or on #()) 'list))))
      (t nil))))

(defun harness-resume (harness)
  (assert-usable-harness harness)
  (each-task (harness-storage harness)
             (lambda (task)
               (when (task-due-p harness task)
                 (invoke-task harness task)))))

(defun span-carrier (span)
  (let ((propagation (and span (cadr-telemetry:telemetry-span-propagation span))))
    (when propagation
      (cadr-telemetry:telemetry-inject propagation span))))

(defun resolve-task-trace (context-telemetry trace)
  (if (and (stringp trace) (string= trace "root"))
      nil
      (or trace (span-carrier context-telemetry))))

(defun harness-create-task (harness kind input &key conversation-id owner background
                                                   context-telemetry trace)
  (assert-usable-harness harness)
  (let* ((definition (gethash kind (registry-tasks (harness-registry harness))))
         (id (storage-mint-id (harness-storage harness)))
         (conversation (or conversation-id (harness-root harness)))
         (checkpoint (funcall (task-definition-initial definition) input))
         (state (pending-state checkpoint))
         (task (make-task-record :id id :kind kind
                                 :version (task-definition-version definition)
                                 :conversation-id conversation :owner owner
                                 :input input :state state :background background
                                 :trace (resolve-task-trace context-telemetry trace))))
    (cadr-chord:json-put state "status" "running")
    (storage-commit (harness-storage harness) (list (cons :task task)))
    (note-task-active harness task)
    (invoke-task harness task)))

(defun harness-retry-task (harness id)
  (assert-usable-harness harness)
  (remhash id (harness-parked harness))
  (let ((task (storage-task (harness-storage harness) id)))
    (setf task (save-task (harness-storage harness) task
                          (pending-state (task-record-state task))
                          :restarts nil))
    (invoke-task harness task)))

(defun harness-abort-task (harness id)
  (assert-usable-harness harness)
  (let* ((task (storage-task (harness-storage harness) id))
         (definition (gethash (task-record-kind task)
                              (registry-tasks (harness-registry harness))))
         (runtime (make-task-runtime :harness harness :task task))
         (phase (hash-get (task-record-state task) "phase"))
         (escaped nil))
    (setf (task-record-abort-requested task) t)
    (call-with-durable-phase
     harness task "abort" phase
     (lambda ()
       (if (and definition (task-definition-abort definition))
           (handler-case
               (progn
                 (funcall (task-definition-abort definition) task runtime)
                 (setf task
                       (if (and (task-runtime-decision runtime)
                                (equal (hash-get (task-runtime-decision runtime) "status")
                                       "terminal"))
                           (save-task (harness-storage harness) task
                                      (task-runtime-decision runtime)
                                      :abort-requested t)
                           (fault-task harness task
                                       (format nil "Abort handler of task ~A returned without a terminal outcome" id)
                                       "threw"))))
             (error (condition)
               (let ((restarts (1+ (or (task-record-restarts task) 0))))
                 (if (>= restarts (task-definition-restart-limit definition))
                     (setf task
                           (fault-task harness task
                                       (format nil "Abort handler of task ~A (~A) was cut off ~A times"
                                               id (task-record-kind task) restarts)
                                       "restart_limit"))
                     (progn
                       (setf task
                             (save-task (harness-storage harness) task
                                        (task-record-state task)
                                        :restarts restarts :abort-requested t))
                       (setf escaped condition))))))
           (setf task
                 (save-task (harness-storage harness) task
                            (cadr-chord:json-object
                             "status" "terminal"
                             "outcome" (cadr-chord:json-object "status" "aborted"))
                            :abort-requested t)))
       (setf (task-runtime-task runtime) task)
       task))
    (when escaped (error escaped))
    (storage-task (harness-storage harness) id)))

(defun conversation-messages (storage conversation-id)
  (let ((page (storage-scan-entries storage conversation-id :order "ascending" :limit 1000)))
    (remove nil
            (mapcar (lambda (entry)
                      (when (member (entry-kind entry)
                                    (list (user-entry-kind) (assistant-entry-kind))
                                    :test #'string=)
                        (entry-model entry)))
                    (page-items page)))))

(defun assistant-message (value now)
  (if (hash-table-p value)
      value
      (cadr-chord:json-object
       "role" "assistant"
       "content" (cadr-chord:json-array (cadr-chord:json-object "type" "text" "text" value))
       "api" "faux" "provider" "faux" "model" "faux"
       "usage" (cadr-chord:json-object "input" 0 "output" 0 "cacheRead" 0
                                       "cacheWrite" 0 "totalTokens" 0 "cost" 0)
       "stopReason" "stop"
       "timestamp" now)))

(defun submission-status (submission) (submission-record-status submission))
(defun submission-id (submission) (submission-record-id submission))
(defun submission-answer (submission) (submission-record-answer submission))
(defun submission-request-id (submission) (submission-record-request-id submission))

(defun admission-result (record)
  (if (string= (submission-record-status record) "unanswered")
      "done"
      (submission-record-status record)))

(defun submission-entry-field (entry key text-key)
  (cond
    ((hash-table-p entry) (hash-get entry text-key))
    ((listp entry) (getf entry key))))

(defun admit-harness-input (harness storage conversation content request-id when-busy span)
  (let ((existing (and request-id
                       (storage-submission-by-request storage conversation request-id))))
    (when existing
      (cadr-telemetry:telemetry-set-attributes
       span (list (cons "submission.id" (submission-record-id existing))
                  (cons "result" (admission-result existing))))
      (return-from admit-harness-input (cons existing nil))))
  (let ((busy (and (member conversation (harness-busy harness)) t)))
    (when (and busy (string= when-busy "reject"))
      (error 'conversation-busy :conversation-id conversation
             :text (format nil "Conversation ~A is busy" conversation)))
    (let* ((now (harness-now harness))
           (submission-id (storage-mint-id storage))
           (user-id (unless busy (storage-mint-id storage)))
           (writes nil)
           (submission (make-submission-record
                        :id submission-id :conversation-id conversation
                        :request-id request-id :type "input"
                        :status (if busy "queued" "placed")
                        :entry user-id
                        :trace (span-carrier span))))
      (unless busy
        (push (cons :entry
                    (make-entry :id user-id :conversation-id conversation
                                :kind (user-entry-kind)
                                :model (cadr-chord:json-object
                                        "role" "user" "content" content
                                        "timestamp" now)))
              writes))
      (push (cons :submission submission) writes)
      (storage-commit storage (nreverse writes))
      (cadr-telemetry:telemetry-set-attributes
       span (list (cons "submission.id" submission-id)
                  (cons "result" (if busy "queued" "placed"))))
      (cons submission (not busy)))))

(defun admit-harness-write (storage conversation entry request-id span)
  (let ((existing (and request-id
                       (storage-submission-by-request storage conversation request-id))))
    (when existing
      (cadr-telemetry:telemetry-set-attributes
       span (list (cons "submission.id" (submission-record-id existing))
                  (cons "result" (admission-result existing))))
      (return-from admit-harness-write existing)))
  (let* ((entry-id (storage-mint-id storage))
         (submission-id (storage-mint-id storage))
         (record (make-entry :id entry-id :conversation-id conversation
                             :kind (or (submission-entry-field entry :kind "kind") "")
                             :data (submission-entry-field entry :data "data")))
         (submission (make-submission-record
                      :id submission-id :conversation-id conversation
                      :request-id request-id :type "write" :status "done"
                      :entry entry-id :trace (span-carrier span))))
    (storage-commit storage (list (cons :entry record) (cons :submission submission)))
    (cadr-telemetry:telemetry-set-attributes
     span (list (cons "submission.id" submission-id)
                (cons "result" "done")))
    submission))

(defun generation-span-parent (harness carrier)
  (let* ((root (or (harness-telemetry harness)
                   cadr-telemetry:*noop-telemetry-context*))
         (propagation (cadr-telemetry:telemetry-span-propagation root)))
    (if (or (null carrier) (null propagation))
        root
        (or (cadr-telemetry:telemetry-extract propagation carrier) root))))

(defun record-generation-duration (harness span started outcome)
  (when (harness-duration-histogram harness)
    (cadr-telemetry:telemetry-histogram-record
     (harness-duration-histogram harness)
     (- (cadr-telemetry:telemetry-monotonic-milliseconds) started)
     (list (cons "task" "pi.generation")
           (cons "phase" "request")
           (cons "outcome" outcome))
     span)))

(defun finish-harness-input (harness storage conversation submission task-id trace)
  (let* ((reply (funcall (harness-model harness)
                         (conversation-messages storage conversation)))
         (assistant-id (storage-mint-id storage))
         (assistant (make-entry :id assistant-id :conversation-id conversation
                                :kind (assistant-entry-kind)
                                :model (assistant-message reply (harness-now harness))))
         (done (copy-submission-record submission))
         (task (make-task-record
                :id task-id :kind "pi.generation" :conversation-id conversation
                :trace trace
                :state (cadr-chord:json-object
                        "status" "terminal"
                        "phase" "request"
                        "outcome" (cadr-chord:json-object
                                   "status" "completed"
                                   "result" (cadr-chord:json-object
                                             "entryId" assistant-id))))))
    (setf (submission-record-status done) "done"
          (submission-record-answer done) assistant-id)
    (storage-commit storage (list (cons :entry assistant)
                                  (cons :submission done)
                                  (cons :task task)))
    done))

(defun run-placed-input (harness storage conversation submission carrier)
  (let ((task-id (storage-mint-id storage))
        (started (cadr-telemetry:telemetry-monotonic-milliseconds))
        (done nil))
    (push conversation (harness-busy harness))
    (unwind-protect
         (cadr-telemetry:telemetry-start-span
          (generation-span-parent harness carrier)
          *durable-phase-span*
          (lambda (span)
            (let ((*durable-span* span)
                  (failed nil))
              (unwind-protect
                   (handler-case
                       (setf done (finish-harness-input
                                   harness storage conversation submission
                                   task-id carrier))
                     (error (condition)
                       (setf failed t)
                       (cadr-telemetry:telemetry-set-status span :kind :error)
                       (error condition)))
                (let ((outcome (if failed "faulted" "done")))
                  (cadr-telemetry:telemetry-set-attributes
                   span (list (cons "outcome" outcome)))
                  (record-generation-duration harness span started outcome))))
            done)
          :attributes (list (cons "task.id" task-id)
                            (cons "task.name" "pi.generation")
                            (cons "phase" "request")
                            (cons "kind" "run")
                            (cons "attempt" 1)
                            (cons "resumed" nil)))
      (setf (harness-busy harness)
            (remove conversation (harness-busy harness) :count 1)))
    done))

(defun harness-submit (harness content &key conversation-id request-id (when-busy "queue")
                                         context-telemetry (type "input") entry)
  (assert-usable-harness harness)
  (let* ((conversation (or conversation-id (harness-root-id harness)))
         (storage (harness-storage harness))
         (input (string= type "input"))
         (parent (if input
                     (or (harness-telemetry harness)
                         cadr-telemetry:*noop-telemetry-context*)
                     (or context-telemetry cadr-telemetry:*noop-telemetry-context*)))
         (caller (or context-telemetry cadr-telemetry:*noop-telemetry-context*))
         (submit-span nil)
         (admitted nil))
    (cadr-telemetry:telemetry-start-span
     parent *durable-submit-span*
     (lambda (span)
       (setf submit-span span)
       (when input
         (cadr-telemetry:telemetry-add-link span caller))
       (let ((*durable-span* span))
         (handler-case
             (setf admitted
                   (if input
                       (admit-harness-input harness storage conversation content
                                            request-id when-busy span)
                       (admit-harness-write storage conversation entry
                                            request-id span)))
           (error (condition)
             (cadr-telemetry:telemetry-set-status span :kind :error)
             (error condition)))))
     :attributes (list (cons "submission.type" type)
                       (cons "conversation.id" conversation)))
    (if (and input (cdr admitted))
        (run-placed-input harness storage conversation (car admitted)
                          (span-carrier submit-span))
        (if input (car admitted) admitted))))

(defun owned-conversation-ids (storage task-id)
  (let ((page (storage-scan-conversations storage :owner-kind "task" :owner-id task-id
                                          :limit 1000 :order "ascending")))
    (mapcar #'conversation-id (page-items page))))

(defun graph-state (state)
  (let ((status (hash-get state "status"))
        (view (cadr-chord:json-object "status" (hash-get state "status"))))
    (cond
      ((member status '("pending" "running") :test #'string=)
       (cadr-chord:json-put view "phase" (hash-get state "phase")))
      ((string= status "sleeping")
       (cadr-chord:json-put view "phase" (hash-get state "phase"))
       (cadr-chord:json-put view "until" (hash-get state "until")))
      ((string= status "waiting")
       (cadr-chord:json-put view "phase" (hash-get state "phase"))
       (cadr-chord:json-put view "on" (hash-get state "on"))
       (cadr-chord:json-put view "policy" (or (hash-get state "policy") "allSettled")))
      ((string= status "terminal")
       (cadr-chord:json-put view "outcome" (hash-get (hash-get state "outcome") "status"))))
    view))

(defun harness-task-graph (harness)
  (assert-usable-harness harness)
  (let ((tasks (cadr-chord:json-object))
        (storage (harness-storage harness)))
    (each-task storage
               (lambda (task)
                 (unless (string= (task-status task) "terminal")
                   (let ((node (cadr-chord:json-object
                                "id" (task-record-id task)
                                "kind" (task-record-kind task)
                                "conversationId" (task-record-conversation-id task)
                                "background" (and (task-record-background task) t)
                                "abortRequested" (and (task-record-abort-requested task) t)
                                "state" (graph-state (task-record-state task))
                                "conversations"
                                (apply #'cadr-chord:json-array
                                       (owned-conversation-ids storage (task-record-id task))))))
                     (when (task-record-owner task)
                       (cadr-chord:json-put node "owner" (task-record-owner task)))
                     (when (gethash (task-record-id task) (harness-parked harness))
                       (cadr-chord:json-put node "blocked" "restart_limit"))
                     (setf (gethash (princ-to-string (task-record-id task)) tasks) node)))))
    (cadr-chord:json-object "tasks" tasks)))

(defun harness-active-count (harness)
  (assert-usable-harness harness)
  (let ((count 0))
    (each-task (harness-storage harness)
               (lambda (task)
                 (when (and (not (string= (task-status task) "terminal"))
                            (not (gethash (task-record-id task) (harness-parked harness))))
                   (incf count))))
    count))

(defun harness-close (harness)
  (let ((storage (harness-storage harness)))
    (when (storage-closed-p storage)
      (return-from harness-close nil))
    (unless (harness-failed harness)
      (each-task storage
                 (lambda (task)
                   (when (string= (task-status task) "running")
                     (save-task storage task
                                (pending-state (task-record-state task))
                                :restarts (task-record-restarts task)))
                   (note-task-inactive harness task))))
    (storage-close storage)))

(defun notify-session-failure (session condition)
  (let ((harness (session-harness session)))
    (when (and harness (not (harness-failed harness)))
      (setf (harness-failed harness) t)
      (handler-case (harness-close harness)
        (error () nil))
      (report harness "session_failed"
              :message (princ-to-string condition)
              :context *durable-span*))))

(setf *session-failure-reporter* #'notify-session-failure)
