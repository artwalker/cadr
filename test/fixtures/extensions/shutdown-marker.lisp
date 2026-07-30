(in-package #:cl-user)

(cadr-agent:define-event-hook
 :session-shutdown
 :handler
 (lambda (event context)
   (declare (ignore event context))
   (let ((path
           (uiop:getenv
            "CADR_SHUTDOWN_MARKER")))
     (when path
       (with-open-file
           (stream path
                   :direction :output
                   :if-exists :supersede
                   :if-does-not-exist :create
                   :external-format :utf-8)
         (write-line "shutdown" stream))))
   nil))
