(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(test goal20-l-xai-has-default-model-and-empty-snapshot-is-not-unconfigured
  ;; L0/L2/M2: xAI ships grok-4.5. An empty available-models snapshot
  ;; after login must be "no models are available", not the
  ;; unconfigured-default branch.
  (let ((definition (cadr-ai:find-provider-definition :xai)))
    (is (string= "grok-4.5"
                 (cadr-ai:provider-definition-default-model definition)))
    (is (string= "grok-4.5" (cadr-cli:provider-default-model-id :xai))))
  (multiple-value-bind (model kind extra)
      (cadr-cli:classify-post-login-model :xai '())
    (declare (ignore extra))
    (is (null model))
    (is (eq kind :no-models-available))
    (is (not (eq kind :no-default-model)))
    (let ((text
            (cadr-cli:post-login-selection-error
             "Logged in to" "xAI" :xai kind nil)))
      (is (search "no models are available for that provider" text))
      (is (null (search "no default model is configured" text))))))

(test goal20-l-missing-default-model-branch-still-exists
  (multiple-value-bind (model kind extra)
      (cadr-cli:classify-post-login-model :not-a-provider '())
    (declare (ignore extra))
    (is (null model))
    (is (eq kind :no-default-model))
    (is (search
         "no default model is configured for provider"
         (cadr-cli:post-login-selection-error
          "Logged in to" "Unknown" :not-a-provider kind nil)))))

(test goal20-l-no-models-string-is-reachable-not-a-dead-constant
  ;; L2.5.1: the string must come from the executed classifier, not a
  ;; parked defparameter.
  (let ((source
          (uiop:read-file-string
           (merge-pathnames
            "src/cadr-cli/models/login-selection.lisp"
            (asdf:system-source-directory "cadr-cli"))
           :external-format :utf-8)))
    (is (search "no models are available for that provider" source))
    (is (search "classify-post-login-model" source)))
  (is (search
       "no models are available for that provider"
       (cadr-cli:post-login-selection-error
        "Logged in to" "xAI" :xai :no-models-available nil))))

(test goal20-l-custom-entry-without-renderer-does-not-print-nil
  ;; L0 snake Q: fallback used to princ-to-string NIL.
  (let* ((entry
           (cadr-cli::make-tui-entry
            :type :custom-entry
            :custom-type "snake-save"
            :custom-payload '(:custom-type "snake-save" :data nil)))
         (lines
           (cadr-cli::render-extension-custom-entry entry 80 nil)))
    (is (null lines)))
  (let ((lines (cadr-cli::extension-render-value-lines nil 80)))
    (is (null lines)))
  (let ((lines (cadr-cli::extension-render-value-lines '(:snake 1) 80)))
    (is (null lines))
    (is (null (find "NIL" lines :test #'string=)))))
