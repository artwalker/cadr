(load (merge-pathnames "support.lisp" *load-truename*))

(defun trigger-example-compaction (context)
  (cadr-agent:extension-context-notify context "Compaction started")
  (handler-case
      (progn
        (cadr-agent:extension-context-compact context :force-p t)
        (cadr-agent:extension-context-notify context "Compaction completed"))
    (error (condition)
      (cadr-agent:extension-context-notify
       context (format nil "Compaction failed: ~A" condition) :level :error))))

(cadr-agent:define-command
 "trigger-compact"
 :description "Force context compaction"
 :handler (lambda (arguments context)
            (declare (ignore arguments))
            (trigger-example-compaction context)))

(cadr-agent:define-event-hook
 :turn-end
 :handler
 (lambda (event context)
   (declare (ignore event))
   (let ((usage (cadr-agent:extension-context-context-usage context)))
     (when (and usage (> (or (getf usage :percent) 0) 90))
       (trigger-example-compaction context)))))
