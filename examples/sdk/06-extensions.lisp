(defpackage #:cadr-example-sdk-06
  (:use #:cl)
  (:export #:run))

(in-package #:cadr-example-sdk-06)

(defun run (&key (cwd (uiop:getcwd)) agent-directory extension-paths
              session-options (output *standard-output*))
  "Combine discovered, explicit-path, and inline extensions in an SDK session."
  (let ((loader
          (cadr-cli:make-sdk-resource-loader
           :cwd cwd
           :agent-directory
           (or agent-directory
               (merge-pathnames ".cadr/" (user-homedir-pathname)))
           :additional-extension-paths extension-paths
           :extension-factories
           (list
            (lambda (api)
              (declare (ignore api))
              (cadr-agent:define-event-hook
               :agent-start
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 (format output "[Inline Extension] Agent starting~%"))))))))
    (cadr-cli:sdk-resource-loader-reload loader)
    (multiple-value-bind (session extensions)
        (apply #'cadr-cli:create-agent-session
               :cwd cwd
               :resource-loader loader
               :session-manager
               (cadr-cli:session-manager-in-memory cwd)
               session-options)
      (unwind-protect
          extensions
        (cadr-cli:agent-session-dispose session)))))
