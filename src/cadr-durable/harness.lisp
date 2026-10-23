(in-package #:cadr-durable)

(defstruct task-definition name version initial phases abort restart-limit)
(defstruct tool-definition name execute)
(defstruct extension-definition name setup)
(defstruct (registry (:constructor %make-registry))
  (tasks (make-hash-table :test #'equal))
  (tools (make-hash-table :test #'equal))
  (extensions nil))
(defstruct harness storage registry model now-fn on-report
           (busy nil) (parked (make-hash-table :test #'eql)) root-id (clock 0))
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

(defun report (harness type &key reason message task)
  (when (harness-on-report harness)
    (let ((event (cadr-chord:json-object "type" type)))
      (when reason (cadr-chord:json-put event "reason" reason))
      (when message (cadr-chord:json-put event "message" message))
      (when task (cadr-chord:json-put event "task" (task-record-id task)))
      (funcall (harness-on-report harness) event))))

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
    (save-task (harness-storage harness) task state :restarts nil)
    (report harness "task_faulted" :reason reason :message message :task task)))

(defun runtime-commit (runtime function)
  (when (task-runtime-settled runtime)
    (error "runtime commit after the invocation ended"))
  (setf (task-runtime-decision runtime) (funcall function)))

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

(defun invoke-task (harness task)
  (when (gethash (task-record-id task) (harness-parked harness))
    (return-from invoke-task task))
  (let* ((definition (gethash (task-record-kind task)
                              (registry-tasks (harness-registry harness))))
         (runtime (make-task-runtime :harness harness :task task)))
    (loop
      (setf (task-runtime-decision runtime) nil)
      (let* ((phase (hash-get (task-record-state task) "phase"))
             (function (gethash phase (task-definition-phases definition))))
        (handler-case (funcall function task runtime)
          (error (condition)
            (unless (and (task-runtime-decision runtime)
                         (equal (hash-get (task-runtime-decision runtime) "status")
                                "terminal"))
              (fault-task harness task (princ-to-string condition) "threw")
              (return))))
        (let ((decision (task-runtime-decision runtime)))
          (unless decision
            (fault-task harness task
                        (format nil "Task ~A phase ~A returned without durable progress"
                                (task-record-kind task) phase)
                        "no_progress")
            (return))
          (let ((status (or (hash-get decision "status") "pending")))
            (cond
              ((string= status "terminal")
               (setf task (save-task (harness-storage harness) task decision))
               (return))
              ((or (string= status "sleeping") (string= status "waiting"))
               (setf task (save-task (harness-storage harness) task decision))
               (return))
              ((checkpoint-equal-p decision (task-record-state task))
               (fault-task harness task
                           (format nil "Task ~A phase ~A returned without durable progress"
                                   (task-record-kind task) phase)
                           "no_progress")
               (return))
              (t
               (setf task (save-task (harness-storage harness) task
                                     (pending-state decision)))
               (unless (string/= (hash-get decision "phase") phase)
                 (return))))))))
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

(defun open-harness (storage &key registry model now on-report)
  (let ((harness (make-harness :storage storage
                               :registry (or registry (make-registry))
                               :model model :now-fn now :on-report on-report)))
    (ensure-root storage)
    (setf (harness-root-id harness) +root-conversation-id+)
    (each-task storage (lambda (task) (recover-task harness task)))
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
         (runtime (make-task-runtime :harness harness :task task)))
    (setf (task-record-abort-requested task) t)
    (if (and definition (task-definition-abort definition))
        (handler-case
            (progn
              (funcall (task-definition-abort definition) task runtime)
              (if (and (task-runtime-decision runtime)
                       (equal (hash-get (task-runtime-decision runtime) "status") "terminal"))
                  (save-task (harness-storage harness) task (task-runtime-decision runtime)
                             :abort-requested t)
                  (fault-task harness task
                              (format nil "Abort handler of task ~A returned without a terminal outcome" id)
                              "abort")))
          (error (condition)
            (let ((restarts (1+ (or (task-record-restarts task) 0))))
              (if (>= restarts (task-definition-restart-limit definition))
                  (fault-task harness task
                              (format nil "Abort handler of task ~A (~A) was cut off ~A times"
                                      id (task-record-kind task) restarts)
                              "restart_limit")
                  (progn
                    (save-task (harness-storage harness) task (task-record-state task)
                               :restarts restarts :abort-requested t)
                    (error condition))))))
        (save-task (harness-storage harness) task
                   (cadr-chord:json-object
                    "status" "terminal"
                    "outcome" (cadr-chord:json-object "status" "aborted"))
                   :abort-requested t))
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

(defun harness-submit (harness content &key conversation-id request-id (when-busy "queue"))
  (let ((conversation (or conversation-id (harness-root-id harness)))
        (storage (harness-storage harness)))
    (when (and (member conversation (harness-busy harness))
               (string= when-busy "reject"))
      (error 'conversation-busy :conversation-id conversation
             :text (format nil "Conversation ~A is busy" conversation)))
    (let ((existing (and request-id
                         (storage-submission-by-request storage conversation request-id))))
      (when existing (return-from harness-submit existing)))
    (push conversation (harness-busy harness))
    (unwind-protect
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
      (setf (harness-busy harness) (remove conversation (harness-busy harness))))))

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
       (cadr-chord:json-put view "until" (hash-get state "until")))
      ((string= status "waiting")
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
                            :restarts (task-record-restarts task)))))
  (storage-close (harness-storage harness)))
