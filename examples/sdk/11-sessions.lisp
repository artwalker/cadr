(defpackage #:cadr-example-sdk-11
  (:use #:cl)
  (:export #:run))

(in-package #:cadr-example-sdk-11)

(defun run (&key (cwd (uiop:getcwd)) directory session-options)
  "Exercise memory, create, continue, list, and open session policies."
  (let ((memory nil)
        (persistent nil)
        (continued nil))
    (unwind-protect
        (progn
          (setf memory
                (apply #'cadr-cli:create-agent-session
                       :cwd cwd
                       :session-manager
                       (cadr-cli:session-manager-in-memory cwd)
                       session-options)
                persistent
                (apply #'cadr-cli:create-agent-session
                       :cwd cwd
                       :session-manager
                       (cadr-cli:session-manager-create cwd directory)
                       session-options)
                continued
                (apply #'cadr-cli:create-agent-session
                       :cwd cwd
                       :session-manager
                       (cadr-cli:session-manager-continue-recent cwd directory)
                       session-options))
          (let ((sessions
                  (cadr-cli:session-manager-list cwd directory)))
            (values sessions
                    (and sessions
                         (cadr-cli:session-manager-open
                          (cadr-agent:session-list-info-path
                           (first sessions)))))))
      (dolist (session (list memory persistent continued))
        (when session
          (cadr-cli:agent-session-dispose session))))))
