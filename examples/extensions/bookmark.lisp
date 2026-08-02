(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-command
 "bookmark"
 :description "Bookmark last message (usage: /bookmark [label])"
 :handler
 (lambda (arguments context)
   (let* ((session (cadr-agent:extension-context-session context))
          (entry
            (find :assistant (example-session-entries context)
                  :key #'example-entry-role :from-end t))
          (label
            (if (plusp (length (example-trim arguments)))
                (example-trim arguments)
                (format nil "bookmark-~D" (cadr-ai::unix-milliseconds)))))
     (if entry
         (progn
           (cadr-agent:session-set-label
            session (cadr-agent:session-entry-id entry) label)
           (cadr-agent:extension-context-notify
            context (format nil "Bookmarked as: ~A" label)))
         (cadr-agent:extension-context-notify
          context "No assistant message to bookmark" :level :warning)))))

(cadr-agent:define-command
 "unbookmark"
 :description "Remove bookmark from last labeled entry"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (let* ((session (cadr-agent:extension-context-session context))
          (entry
            (find-if
             (lambda (candidate)
               (cadr-agent:session-label
                session (cadr-agent:session-entry-id candidate)))
             (example-session-entries context)
             :from-end t)))
     (if entry
         (let ((label
                 (cadr-agent:session-label
                  session (cadr-agent:session-entry-id entry))))
           (cadr-agent:session-set-label
            session (cadr-agent:session-entry-id entry) nil)
           (cadr-agent:extension-context-notify
            context (format nil "Removed bookmark: ~A" label)))
         (cadr-agent:extension-context-notify
          context "No bookmarked entry found" :level :warning)))))
