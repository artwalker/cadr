(in-package #:cadr-durable)

(defparameter *durable-submit-span* "pi.durable.submit")
(defparameter *durable-phase-span* "pi.durable.phase")
(defparameter *durable-entry-event* "pi.durable.entry")
(defparameter *durable-submission-event* "pi.durable.submission")
(defparameter *durable-report-event* "pi.durable.report")
(defparameter *durable-checkpoint-event* "pi.durable.checkpoint")
(defparameter *durable-replay-event* "pi.durable.replay")
(defparameter *durable-reports-metric* "pi.durable.reports")
(defparameter *durable-phase-duration-metric* "pi.durable.phase.duration")
(defparameter *durable-tasks-active-metric* "pi.durable.tasks.active")

(defvar *durable-span* nil)

(defun durable-attribute (type description &key required values cardinality)
  (cadr-telemetry:make-telemetry-attribute-definition
   :type type :description description :required required
   :values values :cardinality cardinality))

(defun durable-event (description attributes)
  (list :description description :attributes attributes))

(defun durable-utf16-slice (text limit)
  (let ((text (or text ""))
        (count 0)
        (end 0)
        (split nil))
    (loop for character across text
          for units = (if (> (char-code character) #xFFFF) 2 1)
          do (cond
               ((<= (+ count units) limit)
                (incf count units)
                (incf end))
               ((and (> units 1) (< count limit))
                (setf split
                      (code-char
                       (+ #xD800
                          (ldb (byte 10 10) (- (char-code character) #x10000)))))
                (loop-finish))
               (t (loop-finish))))
    (if split
        (concatenate 'string (subseq text 0 end) (string split))
        (subseq text 0 end))))

(defparameter *report-type-attribute*
  (durable-attribute
   "string" "ReportInfo type." :required t
   :values '("session_failed" "task_faulted" "task_parked" "migration_failed"
             "task_outdated" "task_error" "extension_error" "host_error"
             "listener_error")))

(defparameter *report-reason-attribute*
  (durable-attribute
   "string" "Fixed report reason, when present." :required nil
   :values '("threw" "restart_limit" "missing_task" "incompatible_task")))

(defparameter *report-extension-attribute*
  (durable-attribute "string" "Registered extension name, when present."
                     :required nil))

(defparameter *report-task-attribute*
  (durable-attribute "number" "Task ID, when present." :required nil
                     :cardinality "high"))

(defparameter *report-event-attributes*
  (list (cons "type" *report-type-attribute*)
        (cons "reason" *report-reason-attribute*)
        (cons "extension" *report-extension-attribute*)
        (cons "task.id" *report-task-attribute*)))

(defparameter *entry-event*
  (durable-event
   "A transcript entry was committed; content remains in the transcript."
   (list (cons "entry.id"
               (durable-attribute "number" "Transcript entry ID."
                                  :required t :cardinality "high"))
         (cons "entry.kind"
               (durable-attribute "string" "Entry kind." :required t)))))

(defparameter *submission-event*
  (durable-event
   "A submission was settled."
   (list (cons "submission.id"
               (durable-attribute "number" "Submission ID."
                                  :required t :cardinality "high"))
         (cons "status"
               (durable-attribute "string" "Settlement." :required t
                                  :values '("done" "unanswered")))
         (cons "answer.entry_id"
               (durable-attribute "number" "Answer entry ID."
                                  :required nil :cardinality "high")))))

(defparameter *report-event*
  (durable-event "A report was raised; no error payload is recorded."
                 *report-event-attributes*))

(defparameter *checkpoint-event*
  (durable-event
   "The running checkpoint's phase changed while the invocation continued."
   (list (cons "phase"
               (durable-attribute "string" "Committed checkpoint phase."
                                  :required t)))))

(defparameter *replay-event*
  (durable-event
   "A nested tool call was answered from its stored result."
   (list (cons "tool.name"
               (durable-attribute "string" "Called tool name." :required t)))))

(defparameter *durable-telemetry-schema*
  (cadr-telemetry:define-telemetry-schema
   (cadr-telemetry:make-telemetry-schema
    :version 1
    :spans
    (list (cons *durable-submit-span*
                (cadr-telemetry:make-telemetry-span-definition
                 :description
                 "Public submission admission and its commit. Inputs start root traces linked to their callers; writes are children. Internal admissions emit phase events only."
                 :parents (list :kind "any")
                 :start-attributes
                 (list (cons "submission.type"
                             (durable-attribute
                              "string" "Submission type." :required t
                              :values '("input" "write")))
                       (cons "conversation.id"
                             (durable-attribute
                              "number" "Conversation ID." :required t
                              :cardinality "high")))
                 :end-attributes
                 (list (cons "submission.id"
                             (durable-attribute
                              "number" "Admitted submission ID."
                              :cardinality "high"))
                       (cons "result"
                             (durable-attribute
                              "string"
                              "Admission result; stale writes report done."
                              :values '("queued" "placed" "done"))))
                 :events (list (cons *durable-entry-event* *entry-event*)
                               (cons *durable-submission-event* *submission-event*)
                               (cons *durable-report-event* *report-event*))
                 :status '(:default "ok" :error-when "Admission failed.")))
          (cons *durable-phase-span*
                (cadr-telemetry:make-telemetry-span-definition
                 :description
                 "One task phase invocation, including its decision commit, never a wait or restart."
                 :parents (list :kind "any")
                 :start-attributes
                 (list (cons "task.id"
                             (durable-attribute "number" "Task ID." :required t
                                                :cardinality "high"))
                       (cons "task.name"
                             (durable-attribute "string" "Registered task name."
                                                :required t))
                       (cons "phase"
                             (durable-attribute "string" "Invoked checkpoint phase."
                                                :required t))
                       (cons "kind"
                             (durable-attribute "string" "Invocation kind."
                                                :required t
                                                :values '("run" "abort")))
                       (cons "attempt"
                             (durable-attribute
                              "number" "Checkpoint attempt, when present."
                              :required nil))
                       (cons "resumed"
                             (durable-attribute
                              "boolean"
                              "First invocation of a task loaded in this process."
                              :required t)))
                 :end-attributes
                 (list (cons "outcome"
                             (durable-attribute
                              "string"
                              "next=<phase>, waiting, sleeping, done, faulted, or aborted."))
                       (cons "tool.name"
                             (durable-attribute "string" "Called tool name."))
                       (cons "tool.call_id"
                             (durable-attribute "string" "Transcript tool call ID."
                                                :cardinality "high")))
                 :events (list (cons *durable-entry-event* *entry-event*)
                               (cons *durable-submission-event* *submission-event*)
                               (cons *durable-report-event* *report-event*)
                               (cons *durable-checkpoint-event* *checkpoint-event*)
                               (cons *durable-replay-event* *replay-event*))
                 :status
                 '(:default "ok"
                   :error-when
                   "Faulted, failed, and orphaned outcomes use task_faulted, task_failed, and task_orphaned with a diagnostic capped at 500 characters. Aborted outcomes keep status ok."))))
    :metrics
    (list (cons *durable-reports-metric*
                (cadr-telemetry:make-telemetry-metric-definition
                 :kind "counter"
                 :description "Reports raised, grouped by their fixed ReportInfo type."
                 :attributes (list (cons "type" *report-type-attribute*))))
          (cons *durable-phase-duration-metric*
                (cadr-telemetry:make-telemetry-metric-definition
                 :kind "histogram"
                 :unit "ms"
                 :description "Duration of a phase invocation and its decision commit."
                 :attributes
                 (list (cons "task"
                             (durable-attribute "string" "Registered task name."
                                                :required t))
                       (cons "phase"
                             (durable-attribute "string" "Invoked checkpoint phase."
                                                :required t))
                       (cons "outcome"
                             (durable-attribute "string" "Phase outcome."
                                                :required t)))))
          (cons *durable-tasks-active-metric*
                (cadr-telemetry:make-telemetry-metric-definition
                 :kind "upDownCounter"
                 :description
                 "Live tasks held by this Harness; decremented at terminal settlement or close."
                 :attributes
                 (list (cons "task"
                             (durable-attribute "string" "Registered task name."
                                                :required t)))))))))

(defun emit-durable-event (span name attributes)
  (when span
    (cadr-telemetry:telemetry-add-event span name attributes)))

(defun note-durable-commit (writes)
  (when *durable-span*
    (dolist (write writes)
      (case (car write)
        (:entry
         (let ((entry (cdr write)))
           (emit-durable-event
            *durable-span* *durable-entry-event*
            (list (cons "entry.id" (entry-id entry))
                  (cons "entry.kind" (entry-kind entry))))))
        (:submission
         (let ((record (cdr write)))
           (when (member (submission-record-status record)
                         '("done" "unanswered") :test #'string=)
             (emit-durable-event
              *durable-span* *durable-submission-event*
              (list (cons "submission.id" (submission-record-id record))
                    (cons "status" (submission-record-status record))
                    (cons "answer.entry_id"
                          (or (submission-record-answer record)
                              :undefined)))))))))))

(defun note-durable-checkpoint (phase)
  (when (and *durable-span* phase)
    (emit-durable-event *durable-span* *durable-checkpoint-event*
                        (list (cons "phase" phase)))))

(defun note-durable-replay (name)
  (when (and *durable-span* name)
    (emit-durable-event *durable-span* *durable-replay-event*
                        (list (cons "tool.name" name)))))

(defun durable-report-attributes (type &key reason extension task)
  (let ((attributes (list (cons "type" type))))
    (cond
      ((member type '("task_faulted" "task_outdated") :test #'string=)
       (when reason
         (setf attributes (append attributes (list (cons "reason" reason)))))
       (when extension
         (setf attributes (append attributes (list (cons "extension" extension)))))
       (when task
         (setf attributes
               (append attributes
                       (list (cons "task.id" (task-record-id task)))))))
      ((member type '("task_parked" "migration_failed" "task_error"
                      "extension_error")
               :test #'string=)
       (when extension
         (setf attributes (append attributes (list (cons "extension" extension)))))
       (when task
         (setf attributes
               (append attributes
                       (list (cons "task.id" (task-record-id task)))))))
      ((string= type "host_error")
       (when task
         (setf attributes
               (append attributes
                       (list (cons "task.id" (task-record-id task))))))))
    attributes))

(defun durable-instruments (telemetry)
  (cadr-telemetry:create-typed-metrics
   (or (and telemetry (cadr-telemetry:telemetry-span-metrics telemetry))
       cadr-telemetry:*noop-telemetry-metrics*)
   (list *durable-telemetry-schema*)))
