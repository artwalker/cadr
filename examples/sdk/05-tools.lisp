(defpackage #:cadr-example-sdk-05
  (:use #:cl)
  (:export #:run))

(in-package #:cadr-example-sdk-05)

(defun make-tool-session (cwd names session-options)
  (multiple-value-bind (session)
      (apply #'cadr-cli:create-agent-session
             :cwd cwd
             :tools names
             :session-manager
             (cadr-cli:session-manager-in-memory cwd)
             session-options)
    session))

(defun run (&key (cwd (uiop:getcwd)) session-options)
  "Create read-only and explicit-tool sessions using the same SDK bootstrap."
  (let ((read-only
          (make-tool-session
           cwd '("read" "grep" "find" "ls") session-options))
        (selected
          (make-tool-session
           cwd '("read" "bash" "grep") session-options)))
    (unwind-protect
        (values read-only selected)
      (cadr-cli:agent-session-dispose read-only)
      (cadr-cli:agent-session-dispose selected))))
