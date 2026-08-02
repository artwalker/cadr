(load (merge-pathnames "support.lisp" *load-truename*))

(defvar *git-checkpoints* (make-hash-table :test #'equal))
(defvar *git-checkpoint-entry-id* nil)

(cadr-agent:define-event-hook
 :tool-call-after
 :handler
 (lambda (event context)
   (declare (ignore event))
   (let* ((branch (example-session-branch context))
          (entry (car (last branch))))
     (when entry
       (setf *git-checkpoint-entry-id*
             (cadr-agent:session-entry-id entry))))))

(cadr-agent:define-event-hook
 :turn-start
 :handler
 (lambda (event context)
   (declare (ignore event context))
   (let* ((result (example-exec "git" '("stash" "create")))
          (reference (example-trim (example-exec-output result))))
     (when (and (zerop (example-exec-code result))
                (plusp (length reference))
                *git-checkpoint-entry-id*)
       (setf (gethash *git-checkpoint-entry-id* *git-checkpoints*)
             reference)))))

(cadr-agent:define-event-hook
 :session-before-fork
 :handler
 (lambda (event context)
   (let ((reference
           (gethash (example-event-value event :entry-id)
                    *git-checkpoints*)))
     (when (and reference
                (cadr-agent:extension-context-has-ui-p context)
                (uiop:string-prefix-p
                 "Yes"
                 (or (cadr-agent:extension-context-select
                      context "Restore code state?"
                      '("Yes, restore code to that point"
                        "No, keep current code"))
                     "No")))
       (example-exec "git" (list "stash" "apply" reference))
       (cadr-agent:extension-context-notify
        context "Code restored to checkpoint")))
   nil))

(cadr-agent:define-event-hook
 :agent-end
 :handler
 (lambda (event context)
   (declare (ignore event context))
   (clrhash *git-checkpoints*)))
