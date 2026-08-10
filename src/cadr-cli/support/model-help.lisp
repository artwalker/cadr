(in-package #:cadr-cli)

(defparameter +default-thinking-level+ :medium)

(defun docs-directory ()
  (cadr-ai::cadr-docs-directory))

(defun get-provider-login-help ()
  (cadr-ai::provider-login-help-text))

(defun format-no-models-available-message ()
  (cadr-ai::no-models-available-message))

(defun format-no-model-selected-message ()
  (cadr-ai::no-model-selected-message))

(defun format-no-api-key-found-message (provider)
  (cadr-ai::no-api-key-found-message provider))
