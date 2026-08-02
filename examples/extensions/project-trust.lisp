(load (merge-pathnames "support.lisp" *load-truename*))

(defvar *project-trust-load-count* 0)
(incf *project-trust-load-count*)

(cadr-agent:define-event-hook
 :project-trust
 :handler
 (lambda (event context)
   (if (not (cadr-agent:extension-context-has-ui-p context))
       (list :trusted :undecided)
       (let ((choice
               (cadr-agent:extension-context-select
                context
                (format nil "Project trust for:~%~A"
                        (example-event-value event :cwd))
                '("Trust and remember"
                  "Trust with note and remember"
                  "Trust this session"
                  "Do not trust this session"
                  "Let built-in prompt decide"))))
         (cond
           ((string= choice "Trust with note and remember")
            (let ((note
                    (cadr-agent:extension-context-input
                     context "Project trust note"
                     :placeholder "Optional note for this demo")))
              (cadr-agent:extension-context-notify
               context
               (if (and note (plusp (length note)))
                   (format nil "Recorded demo note: ~A" note)
                   "No demo note entered")))
            (list :trusted :yes :remember-p t))
           ((string= choice "Trust and remember")
            (list :trusted :yes :remember-p t))
           ((string= choice "Trust this session") (list :trusted :yes))
           ((string= choice "Do not trust this session") (list :trusted :no))
           (t (list :trusted :undecided)))))))

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (cadr-agent:extension-context-notify
    context
    (format nil "project-trust example loaded after trust resolution in ~A"
            (cadr-agent:extension-context-cwd context)))))
