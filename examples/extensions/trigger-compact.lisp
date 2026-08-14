(load (merge-pathnames "support.lisp" *load-truename*))

(defparameter +compact-threshold-tokens+ 100000)

;; :UNSET mirrors the baseline's `previousTokens: number | null | undefined`
;; seed: the first turn only records a reading, it never compacts.
(defvar *trigger-compact-previous-tokens* :unset)

(defun trigger-example-compaction (context)
  (when (cadr-agent:extension-context-has-ui-p context)
    (cadr-agent:extension-context-notify context "Compaction started"))
  (handler-case
      (progn
        (cadr-agent:extension-context-compact context :force-p t)
        (when (cadr-agent:extension-context-has-ui-p context)
          (cadr-agent:extension-context-notify
           context "Compaction completed")))
    (error (condition)
      (when (cadr-agent:extension-context-has-ui-p context)
        (cadr-agent:extension-context-notify
         context (format nil "Compaction failed: ~A" condition)
         :level :error))))
  nil)

(cadr-agent:define-command
 "trigger-compact"
 :description "Trigger compaction immediately"
 :handler (lambda (arguments context)
            (declare (ignore arguments))
            (trigger-example-compaction context)))

(cadr-agent:define-event-hook
 :turn-end
 :handler
 (lambda (event context)
   (declare (ignore event))
   (let* ((usage (cadr-agent:extension-context-context-usage context))
          (current (and usage (getf usage :tokens))))
     (when (realp current)
       (let ((crossed-p
               (and (realp *trigger-compact-previous-tokens*)
                    (<= *trigger-compact-previous-tokens*
                        +compact-threshold-tokens+))))
         (setf *trigger-compact-previous-tokens* current)
         (when (and crossed-p (> current +compact-threshold-tokens+))
           (trigger-example-compaction context)))))
   nil))
