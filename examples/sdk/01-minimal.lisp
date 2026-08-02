(defpackage #:cadr-example-sdk-01
  (:use #:cl)
  (:export #:run))

(in-package #:cadr-example-sdk-01)

(defun run (&key
              (prompt "What files are in the current directory?")
              (output *standard-output*)
              session-options)
  "Create an in-process session with defaults, stream one prompt, and dispose it."
  (multiple-value-bind (session extensions fallback)
      (apply #'cadr-cli:create-agent-session session-options)
    (declare (ignore extensions))
    (when fallback
      (format output "~A~%" fallback))
    (let ((unsubscribe
            (cadr-cli:agent-session-subscribe
             session
             (lambda (event)
               (let ((stream
                       (cadr-agent:agent-event-stream-event event)))
                 (when (and stream
                            (eq :text-delta
                                (cadr-ai:stream-event-type stream)))
                   (write-string
                    (or (cadr-ai:stream-event-delta stream) "")
                    output)
                   (finish-output output)))))))
      (unwind-protect
          (progn
            (cadr-cli:agent-session-prompt session prompt)
            (terpri output)
            (cadr-cli:agent-session-messages session))
        (funcall unsubscribe)
        (cadr-cli:agent-session-dispose session)))))
