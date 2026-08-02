(defpackage #:cadr-example-sdk-09
  (:use #:cl)
  (:export #:run))

(in-package #:cadr-example-sdk-09)

(defun run (&key auth-path models-path provider api-key session-options)
  "Use canonical auth storage with optional per-runtime API-key override."
  (let ((runtime
          (cadr-cli:make-sdk-model-runtime
           :auth-path (or auth-path (cadr-cli:default-auth-path))
           :models-path models-path)))
    (when api-key
      (cadr-cli:sdk-model-runtime-set-api-key
       runtime provider api-key))
    (multiple-value-bind (session)
        (apply #'cadr-cli:create-agent-session
               :model-runtime runtime
               :session-manager
               (cadr-cli:session-manager-in-memory)
               session-options)
      (unwind-protect
          (cadr-cli:sdk-model-runtime-check-auth runtime provider)
        (cadr-cli:agent-session-dispose session)))))
