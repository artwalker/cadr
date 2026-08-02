(defpackage #:cadr-example-sdk-07
  (:use #:cl)
  (:export #:run))

(in-package #:cadr-example-sdk-07)

(defun run (&key (cwd (uiop:getcwd)) agent-directory session-options)
  "Discover AGENTS.md files and append one virtual context file."
  (let ((loader
          (cadr-cli:make-sdk-resource-loader
           :cwd cwd
           :agent-directory
           (or agent-directory
               (merge-pathnames ".cadr/" (user-homedir-pathname)))
           :context-files-override
           (lambda (files)
             (append
              files
              (list
               (list
                :path "/virtual/AGENTS.md"
                :content
                "# Project Guidelines\n\n- Use strict types\n- Prefer immutable bindings")))))))
    (cadr-cli:sdk-resource-loader-reload loader)
    (multiple-value-bind (session)
        (apply #'cadr-cli:create-agent-session
               :cwd cwd
               :resource-loader loader
               :session-manager
               (cadr-cli:session-manager-in-memory cwd)
               session-options)
      (cadr-cli:agent-session-dispose session))
    (cadr-cli:sdk-resource-loader-context-files loader)))
