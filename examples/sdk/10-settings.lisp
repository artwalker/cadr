(defpackage #:cadr-example-sdk-10
  (:use #:cl)
  (:export #:run))

(in-package #:cadr-example-sdk-10)

(defun run (&key (cwd (uiop:getcwd)) global-path project-path session-options)
  "Apply non-persistent overrides while preserving disk-backed settings."
  (let ((settings
          (if global-path
              (cadr-cli:make-sdk-settings-manager
               :global-path global-path
               :project-path project-path)
              (cadr-cli:make-memory-sdk-settings-manager))))
    (let ((overrides (make-hash-table :test #'equal))
          (compaction (make-hash-table :test #'equal))
          (retry (make-hash-table :test #'equal)))
      (setf (gethash "enabled" compaction) nil
            (gethash "enabled" retry) t
            (gethash "maxRetries" retry) 5
            (gethash "baseDelayMs" retry) 1000
            (gethash "compaction" overrides) compaction
            (gethash "retry" overrides) retry)
      (cadr-cli:sdk-settings-apply-overrides settings overrides))
    (multiple-value-bind (session)
        (apply #'cadr-cli:create-agent-session
               :cwd cwd
               :settings-manager settings
               :session-manager
               (cadr-cli:session-manager-in-memory cwd)
               session-options)
      (cadr-cli:agent-session-dispose session))
    (cadr-cli:sdk-settings-flush settings)
    (values settings
            (cadr-cli:sdk-settings-drain-errors settings))))
