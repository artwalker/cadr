(defpackage #:cadr-example-sdk-02
  (:use #:cl)
  (:export #:run))

(in-package #:cadr-example-sdk-02)

(defun run (&key provider model-id (thinking-level :medium)
              (prompt "Say hello in one sentence.")
              (output *standard-output*) runtime-options session-options)
  "Inspect the canonical model runtime and optionally prompt a selected model."
  (let* ((runtime
           (apply #'cadr-cli:make-sdk-model-runtime runtime-options))
         (model
           (and provider model-id
                (cadr-cli:sdk-model-runtime-model
                 runtime provider model-id)))
         (available
           (cadr-cli:sdk-model-runtime-available-models runtime)))
    (format output "Available models:~{ ~A~}~%"
            (mapcar
             (lambda (item)
               (format nil "~(~A~)/~A"
                       (cadr-ai:model-provider item)
                       (cadr-ai:model-id item)))
             available))
    (when model
      (multiple-value-bind (session)
          (apply #'cadr-cli:create-agent-session
                 :model-runtime runtime
                 :model model
                 :thinking-level thinking-level
                 session-options)
        (unwind-protect
            (cadr-cli:agent-session-prompt session prompt)
          (cadr-cli:agent-session-dispose session))))
    (values model available)))
