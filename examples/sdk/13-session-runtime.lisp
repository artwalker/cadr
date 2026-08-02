(defpackage #:cadr-example-sdk-13
  (:use #:cl)
  (:export #:make-runtime #:replace-with-new-session #:run))

(in-package #:cadr-example-sdk-13)

(defun make-runtime (&key (cwd (uiop:getcwd)) agent-directory session-options)
  "Create a replaceable runtime whose factory reuses explicit SDK services."
  (let ((services
          (cadr-cli:create-agent-session-services
           :cwd cwd :agent-directory
           (or agent-directory
               (merge-pathnames ".cadr/" (user-homedir-pathname))))))
    (cadr-cli:create-agent-session-runtime
     (lambda (&key cwd agent-directory session-manager session-start-event)
       (declare (ignore cwd agent-directory))
       (multiple-value-bind (session extensions fallback)
           (apply #'cadr-cli:create-agent-session-from-services
                  services
                  :session-manager session-manager
                  :session-start-event session-start-event
                  session-options)
         (declare (ignore fallback))
         (values session
                 (cadr-cli:agent-session-services-diagnostics services)
                 (list :services services :extensions extensions))))
     :cwd cwd :agent-directory
     (or agent-directory
         (merge-pathnames ".cadr/" (user-homedir-pathname)))
     :session-manager (cadr-cli:session-manager-create cwd))))

(defun replace-with-new-session (runtime)
  (let ((old (cadr-cli:agent-session-runtime-session runtime)))
    (cadr-cli:agent-session-bind-extensions old)
    (let ((next
            (cadr-cli:agent-session-runtime-new-session runtime)))
      (cadr-cli:agent-session-bind-extensions next)
      next)))

(defun run (&rest options)
  (let ((runtime (apply #'make-runtime options)))
    (unwind-protect
        (replace-with-new-session runtime)
      (cadr-cli:agent-session-runtime-dispose runtime))))
