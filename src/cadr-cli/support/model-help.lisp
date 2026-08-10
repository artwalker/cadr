(in-package #:cadr-cli)

(defparameter +default-thinking-level+ :medium)

(defun docs-directory ()
  (cadr-ai::cadr-docs-directory))

(defun get-provider-login-help ()
  (cadr-ai::provider-login-help-text))

(defun format-no-models-available-message ()
  (format nil "No models available. ~A" (get-provider-login-help)))

(defun format-no-model-selected-message ()
  (format nil "No model selected.~%~%~A~%~%Then use /model to select a model."
          (get-provider-login-help)))

(defun format-no-api-key-found-message (provider)
  (cadr-ai::no-api-key-found-message provider))
