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
           (clock-reported nil))
(defstruct task-runtime harness task (decision nil) (settled nil))

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
    (let ((phase (and decision (hash-get decision "phase")))
          (status (and decision (hash-get decision "status")))
          (current (hash-get (task-record-state (task-runtime-task runtime)) "phase")))
      (when (and (string= (or status "") "running")
                 phase current
                 (not (string= phase current)))
        (note-durable-checkpoint phase)))
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
      (name name)
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
              (message (or (and error-object (hash-get error-object "message"))
                           (hash-get terminal "reason")
                           "")))
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

(defun call-with-durable-phase (harness task kind start-phase body)
  (let* ((telemetry (or (harness-telemetry harness)
                        cadr-telemetry:*noop-telemetry-context*))
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
          do (setf (task-runtime-decision runtime) nil)
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
                                      "no_progress"))
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
                                           "no_progress"))
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
  (each-task (harness-storage harness)
             (lambda (task)
               (when (task-due-p harness task)
                 (invoke-task harness task)))))

(defun harness-create-task (harness kind input &key conversation-id owner background)
  (let* ((definition (gethash kind (registry-tasks (harness-registry harness))))
         (id (storage-mint-id (harness-storage harness)))
         (conversation (or conversation-id (harness-root harness)))
         (checkpoint (funcall (task-definition-initial definition) input))
         (state (pending-state checkpoint))
         (task (make-task-record :id id :kind kind
                                 :version (task-definition-version definition)
                                 :conversation-id conversation :owner owner
                                 :input input :state state :background background)))
    (cadr-chord:json-put state "status" "running")
    (storage-commit (harness-storage harness) (list (cons :task task)))
    (note-task-active harness task)
    (invoke-task harness task)))

(defun harness-retry-task (harness id)
  (remhash id (harness-parked harness))
  (let ((task (storage-task (harness-storage harness) id)))
    (setf task (save-task (harness-storage harness) task
                          (pending-state (task-record-state task))
                          :restarts nil))
    (invoke-task harness task)))

(defun harness-abort-task (harness id)
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
                                       "abort"))))
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

(defun admit-harness-input (harness storage conversation content request-id when-busy span)
  (when (and (member conversation (harness-busy harness))
             (string= when-busy "reject"))
    (error 'conversation-busy :conversation-id conversation
           :text (format nil "Conversation ~A is busy" conversation)))
  (let ((existing (and request-id
                       (storage-submission-by-request storage conversation request-id))))
    (when existing
      (cadr-telemetry:telemetry-set-attributes
       span (list (cons "submission.id" (submission-record-id existing))
                  (cons "result" (admission-result existing))))
      (return-from admit-harness-input (cons existing nil))))
  (push conversation (harness-busy harness))
  (let* ((now (harness-now harness))
         (user-id (storage-mint-id storage))
         (submission-id (storage-mint-id storage))
         (user (make-entry :id user-id :conversation-id conversation
                           :kind (user-entry-kind)
                           :model (cadr-chord:json-object
                                   "role" "user" "content" content
                                   "timestamp" now)))
         (submission (make-submission-record
                      :id submission-id :conversation-id conversation
                      :request-id request-id :type "input" :status "queued"
                      :entry user-id)))
    (storage-commit storage (list (cons :entry user) (cons :submission submission)))
    (cadr-telemetry:telemetry-set-attributes
     span (list (cons "submission.id" submission-id)
                (cons "result" "placed")))
    (cons submission t)))

(defun finish-harness-input (harness storage conversation submission)
  (let* ((reply (funcall (harness-model harness)
                         (conversation-messages storage conversation)))
         (assistant-id (storage-mint-id storage))
         (assistant (make-entry :id assistant-id :conversation-id conversation
                                :kind (assistant-entry-kind)
                                :model (assistant-message reply (harness-now harness))))
         (done (copy-submission-record submission)))
    (setf (submission-record-status done) "done"
          (submission-record-answer done) assistant-id)
    (storage-commit storage (list (cons :entry assistant) (cons :submission done)))
    done))

(defun harness-submit (harness content &key conversation-id request-id (when-busy "queue")
                                         context-telemetry)
  (let* ((conversation (or conversation-id (harness-root-id harness)))
         (storage (harness-storage harness))
         (parent (or (harness-telemetry harness)
                     cadr-telemetry:*noop-telemetry-context*))
         (caller (or context-telemetry cadr-telemetry:*noop-telemetry-context*))
         (admitted
           (cadr-telemetry:telemetry-start-span
            parent *durable-submit-span*
            (lambda (span)
              (cadr-telemetry:telemetry-add-link span caller)
              (let ((*durable-span* span))
                (handler-case
                    (admit-harness-input harness storage conversation content
                                         request-id when-busy span)
                  (error (condition)
                    (setf (harness-busy harness)
                          (remove conversation (harness-busy harness)))
                    (cadr-telemetry:telemetry-set-status span :kind :error)
                    (error condition)))))
            :attributes (list (cons "submission.type" "input")
                              (cons "conversation.id" conversation)))))
    (if (cdr admitted)
        (unwind-protect
             (finish-harness-input harness storage conversation (car admitted))
          (setf (harness-busy harness)
                (remove conversation (harness-busy harness))))
        (car admitted))))

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
  (let ((count 0))
    (each-task (harness-storage harness)
               (lambda (task)
                 (when (and (not (string= (task-status task) "terminal"))
                            (not (gethash (task-record-id task) (harness-parked harness))))
                   (incf count))))
    count))

(defun harness-close (harness)
  (each-task (harness-storage harness)
             (lambda (task)
               (when (string= (task-status task) "running")
                 (save-task (harness-storage harness) task
                            (pending-state (task-record-state task))
                            :restarts (task-record-restarts task)))
               (note-task-inactive harness task)))
  (storage-close (harness-storage harness)))
