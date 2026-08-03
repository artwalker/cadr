(in-package #:cadr-cli)

(defparameter +default-thinking-level+ :medium)

(defun docs-directory ()
  (merge-pathnames "docs/" (asdf:system-source-directory "cadr-cli")))

(defun get-provider-login-help ()
  (format nil
          "Use /login to log into a provider via OAuth or API key. See:~%  ~A~%  ~A"
          (namestring (merge-pathnames "providers.md" (docs-directory)))
          (namestring (merge-pathnames "models.md" (docs-directory)))))

(defun format-no-models-available-message ()
  (format nil "No models available. ~A" (get-provider-login-help)))

(defun format-no-model-selected-message ()
  (format nil "No model selected.~%~%~A~%~%Then use /model to select a model."
          (get-provider-login-help)))

(defun format-no-api-key-found-message (provider)
  (format nil "No API key found for ~A.~%~%~A"
          (if (string= provider "unknown") "the selected model" provider)
          (get-provider-login-help)))
