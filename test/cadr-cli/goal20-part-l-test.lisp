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

(test typesafe-login-reports-no-configured-chat-default
  ;; v1.4.0 model-resolver.ts defaultModelPerProvider omits typesafe.
  ;; interactive-mode.ts completeProviderAuthentication checks
  ;; hasDefaultModelProvider before the chat catalog, and
  ;; deferSelection stays false, so the catalog is not refreshed.
  (is (string= ""
               (cadr-ai:provider-definition-default-model
                (cadr-ai:find-provider-definition :typesafe))))
  (is (null (cadr-cli:provider-default-model-id :typesafe)))
  (multiple-value-bind (model kind extra)
      (cadr-cli:classify-post-login-model :typesafe '())
    (is (null model))
    (is (eq kind :no-default-model))
    (is (null extra)))
  (is (string=
       "Saved API key for TypeSafe, but no default model is configured for provider \"typesafe\". Use /model to select a model."
       (cadr-cli:post-login-selection-error
        "Saved API key for" "TypeSafe" :typesafe
        :no-default-model nil)))
  (let* ((chat
           (cadr-ai:make-model
            :id "custom-chat"
            :name "custom-chat"
            :api :openai-completions
            :provider :typesafe
            :base-url "https://api.typesafe.ai/v1/"
            :context-window 1
            :max-tokens 1))
         (refreshed-p nil)
         (result
           (cadr-cli:post-login-selection-result
            :typesafe
            (list chat)
            (lambda (model)
              (declare (ignore model))
              (error "select must not run"))
            :refresh-models-function
            (lambda (provider)
              (declare (ignore provider))
              (setf refreshed-p t)
              '()))))
    (is (null refreshed-p))
    (is (equal '(:no-default-model nil) result))
    (is (string=
         "Saved API key for TypeSafe, but no default model is configured for provider \"typesafe\". Use /model to select a model."
         (cadr-cli:post-login-selection-error
          "Saved API key for" "TypeSafe" :typesafe
          (first result) (second result))))))

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
  ;; princ-to-string of '(nil) is "(NIL)". Do not assert (null lines)
  ;; first: that made the NIL search dead (find on NIL is always NIL).
  (let* ((lines (cadr-cli::extension-render-value-lines '(nil) 80))
         (text (format nil "~{~A~}" (or lines '()))))
    (is (null (search "NIL" text)))))
