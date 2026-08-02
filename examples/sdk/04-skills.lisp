(defpackage #:cadr-example-sdk-04
  (:use #:cl)
  (:export #:run))

(in-package #:cadr-example-sdk-04)

(defun run (&key (cwd (uiop:getcwd)) agent-directory session-options)
  "Discover skills, filter them, and merge one synthetic SDK skill."
  (let* ((skill
           (cadr-agent:make-skill
            :name "my-skill"
            :description "Custom project instructions"
            :content "Follow the embedding application's instructions."
            :file-path "/virtual/SKILL.md"))
         (loader
           (cadr-cli:make-sdk-resource-loader
            :cwd cwd
            :agent-directory
            (or agent-directory
                (merge-pathnames ".cadr/" (user-homedir-pathname)))
            :skills-override
            (lambda (skills diagnostics)
              (values
               (append
                (remove-if-not
                 (lambda (item)
                   (or (search "browser" (cadr-agent:skill-name item))
                       (search "search" (cadr-agent:skill-name item))))
                 skills)
                (list skill))
               diagnostics)))))
    (cadr-cli:sdk-resource-loader-reload loader)
    (multiple-value-bind (session)
        (apply #'cadr-cli:create-agent-session
               :cwd cwd
               :resource-loader loader
               :session-manager
               (cadr-cli:session-manager-in-memory cwd)
               session-options)
      (cadr-cli:agent-session-dispose session))
    (values
     (cadr-cli:sdk-resource-loader-skills loader)
     (cadr-cli:sdk-resource-loader-diagnostics loader))))
