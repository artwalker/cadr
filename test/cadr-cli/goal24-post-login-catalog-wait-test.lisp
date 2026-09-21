(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(defun goal24-post-login-model (provider id)
  (cadr-ai:make-model
   :id id
   :name id
   :api :openai-completions
   :provider provider
   :base-url "http://127.0.0.1:1/v1"
   :context-window 128000
   :max-tokens 8192))

(test goal24-radius-missing-default-selects-first-provider-model
  ;; pi 9767ba275: Radius catalogs vary; when the configured default is
  ;; absent but the provider list is non-empty, take providerModels[0].
  (let* ((first (goal24-post-login-model :radius "fast"))
         (second (goal24-post-login-model :radius "max"))
         (selected nil))
    (multiple-value-bind (model kind extra)
        (cadr-cli:classify-post-login-model
         :radius (list first second))
      (declare (ignore extra))
      (is (null kind))
      (is (eq model first)))
    (is (string=
         "fast"
         (cadr-cli:post-login-selection-result
          :radius
          (list first second)
          (lambda (model)
            (setf selected model)))))
    (is (eq selected first))))

(test goal24-empty-snapshot-refresh-then-selects-default
  (let* ((default-id (cadr-cli:provider-default-model-id :openai))
         (refreshed
           (list (goal24-post-login-model :openai default-id)))
         (refresh-count 0)
         (selected nil))
    (is (stringp default-id))
    (is (string=
         default-id
         (cadr-cli:post-login-selection-result
          :openai
          '()
          (lambda (model)
            (setf selected model))
          :refresh-models-function
          (lambda (provider)
            (is (eq provider :openai))
            (incf refresh-count)
            refreshed))))
    (is (= 1 refresh-count))
    (is (string= default-id (cadr-ai:model-id selected)))))

(test goal24-still-empty-after-refresh-keeps-no-models-error
  (let ((refresh-count 0))
    (let ((result
            (cadr-cli:post-login-selection-result
             :xai
             '()
             (lambda (model)
               (declare (ignore model))
               (error "select must not run"))
             :refresh-models-function
             (lambda (provider)
               (declare (ignore provider))
               (incf refresh-count)
               '()))))
      (is (= 1 refresh-count))
      (is (consp result))
      (is (eq (first result) :no-models-available))
      (is (search
           "no models are available for that provider"
           (cadr-cli:post-login-selection-error
            "Logged in to" "xAI" :xai
            (first result)
            (second result)))))))
