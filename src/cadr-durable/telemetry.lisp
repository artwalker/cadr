(in-package #:cadr-durable)

(defun durable-attribute (description &key (required nil))
  (cadr-telemetry:make-telemetry-attribute-definition
   :type "string" :description description :required required))

(defun durable-event (description)
  (cadr-telemetry:make-telemetry-span-definition :description description))

(defparameter *durable-telemetry-schema*
  (cadr-telemetry:define-telemetry-schema
   (cadr-telemetry:make-telemetry-schema
    :version 1
    :spans
    (list
     (cons "pi.durable.submit"
           (cadr-telemetry:make-telemetry-span-definition
            :description "One harness submission."
            :start-attributes
            (list (cons "submission.id" (durable-attribute "Submission id." :required t))
                  (cons "conversation.id" (durable-attribute "Conversation id." :required t)))))
     (cons "pi.durable.phase"
           (cadr-telemetry:make-telemetry-span-definition
            :description "One task phase invocation."
            :events
            (list (cons "pi.durable.entry" (durable-event "A transcript entry was committed."))
                  (cons "pi.durable.submission" (durable-event "A submission changed status."))
                  (cons "pi.durable.report" (durable-event "A harness report was published."))
                  (cons "pi.durable.checkpoint" (durable-event "A task checkpoint was committed."))
                  (cons "pi.durable.replay" (durable-event "A code-mode call was replayed."))))))
    :metrics
    (list
     (cons "pi.durable.reports"
           (cadr-telemetry:make-telemetry-metric-definition
            :kind "counter" :description "Harness reports." :unit "1"))
     (cons "pi.durable.phase.duration"
           (cadr-telemetry:make-telemetry-metric-definition
            :kind "histogram" :description "Phase duration." :unit "ms"))
     (cons "pi.durable.tasks.active"
           (cadr-telemetry:make-telemetry-metric-definition
            :kind "up-down" :description "Live tasks." :unit "1"))))))

(defun emit-durable-event (span name attributes)
  (when span
    (cadr-telemetry:telemetry-add-event span name attributes)))
