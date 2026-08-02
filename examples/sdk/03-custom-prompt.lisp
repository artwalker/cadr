(defpackage #:cadr-example-sdk-03
  (:use #:cl)
  (:export #:run))

(in-package #:cadr-example-sdk-03)

(defun run (&key (cwd (uiop:getcwd)) agent-directory session-options)
  "Build replacement and append-only system-prompt loaders."
  (let* ((agent-dir
           (or agent-directory
               (merge-pathnames ".cadr/" (user-homedir-pathname))))
         (replacement
           (cadr-cli:make-sdk-resource-loader
            :cwd cwd :agent-directory agent-dir
            :system-prompt-override
            (lambda (base)
              (declare (ignore base))
              "You are a helpful assistant that speaks like a pirate.\nAlways end responses with \"Arrr!\"")
            :append-system-prompt-override
            (lambda (base)
              (declare (ignore base))
              nil)))
         (appending
           (cadr-cli:make-sdk-resource-loader
            :cwd cwd :agent-directory agent-dir
            :append-system-prompt-override
            (lambda (base)
              (append base
                      '("## Additional Instructions\n- Always be concise\n- Use bullet points when listing things"))))))
    (cadr-cli:sdk-resource-loader-reload replacement)
    (cadr-cli:sdk-resource-loader-reload appending)
    (multiple-value-bind (session)
        (apply #'cadr-cli:create-agent-session
               :cwd cwd
               :agent-directory agent-dir
               :resource-loader replacement
               :session-manager
               (cadr-cli:session-manager-in-memory cwd)
               session-options)
      (cadr-cli:agent-session-dispose session))
    (values replacement appending)))
