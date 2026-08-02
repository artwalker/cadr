(defpackage #:cadr-example-sdk-08
  (:use #:cl)
  (:export #:run))

(in-package #:cadr-example-sdk-08)

(defun run (&key (cwd (uiop:getcwd)) agent-directory session-options)
  "Discover prompt templates and merge one synthetic deploy template."
  (let* ((template
           (cadr-agent:make-prompt-template
            :name "deploy"
            :description "Deploy the application"
            :content
            "# Deploy Instructions\n\n1. Build\n2. Test\n3. Deploy"))
         (loader
           (cadr-cli:make-sdk-resource-loader
            :cwd cwd
            :agent-directory
            (or agent-directory
                (merge-pathnames ".cadr/" (user-homedir-pathname)))
            :prompts-override
            (lambda (prompts diagnostics)
              (values (append prompts (list template)) diagnostics)))))
    (cadr-cli:sdk-resource-loader-reload loader)
    (multiple-value-bind (session)
        (apply #'cadr-cli:create-agent-session
               :cwd cwd
               :resource-loader loader
               :session-manager
               (cadr-cli:session-manager-in-memory cwd)
               session-options)
      (cadr-cli:agent-session-dispose session))
    (cadr-cli:sdk-resource-loader-prompts loader)))
