(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test anthropic-model-override-replaces-allowed-fallback-metadata
  ;; Baseline model-registry.test.ts:
  ;; "Anthropic model override replaces allowed fallback metadata"
  (with-test-directory (root)
    (let ((models-path
            (merge-pathnames "agent/models.json" root)))
      (write-json
       models-path
       (args
        "providers"
        (args
         "anthropic"
         (args
          "modelOverrides"
          (args
           "claude-fable-5"
           (args
            "compat"
            (args
             "allowedFallbackModels"
             (vector
              (args
               "provider" "anthropic"
               "model" "claude-opus-5"
               "cost"
               (args
                "input" 5
                "output" 25
                "cacheRead" 0.5
                "cacheWrite" 6.25))
              (args
               "provider" "anthropic"
               "model" "claude-sonnet-4-6"
               "cost"
               (args
                "input" 4
                "output" 20
                "cacheRead" 0.5
                "cacheWrite" 5))))))))))
      (let* ((registry
               (cadr-cli:make-model-registry
                :path models-path))
             (model
               (cadr-cli:model-registry-find
                registry :anthropic "claude-fable-5"))
             (fallbacks
               (cadr-ai::model-compat-value
                model :allowed-fallback-models :missing)))
        (is (null (cadr-cli:model-registry-error registry)))
        (is (not (null model)))
        (is
         (equal
          '((:provider "anthropic"
             :model "claude-opus-5"
             :cost
             (:input 5.0d0 :output 25.0d0
              :cache-read 0.5d0 :cache-write 6.25d0))
            (:provider "anthropic"
             :model "claude-sonnet-4-6"
             :cost
             (:input 4.0d0 :output 20.0d0
              :cache-read 0.5d0 :cache-write 5.0d0)))
          fallbacks))))))

(test empty-allowed-fallback-model-override-disables
  ;; Baseline model-registry.test.ts:
  ;; "empty allowed fallback model override disables"
  (with-test-directory (root)
    (let ((models-path
            (merge-pathnames "agent/models.json" root)))
      (write-json
       models-path
       (args
        "providers"
        (args
         "anthropic"
         (args
          "modelOverrides"
          (args
           "claude-fable-5"
           (args
            "compat"
            (args "allowedFallbackModels" (vector))))))))
      (let* ((registry
               (cadr-cli:make-model-registry
                :path models-path))
             (model
               (cadr-cli:model-registry-find
                registry :anthropic "claude-fable-5")))
        (is (null (cadr-cli:model-registry-error registry)))
        (is (not (null model)))
        (multiple-value-bind (value present-p)
            (cadr-ai::plist-entry
             (cadr-ai::model-compat model)
             :allowed-fallback-models)
          (is-true present-p)
          (is (equal '() value)))
        (is
         (equal
          '()
          (cadr-ai::model-compat-value
           model :allowed-fallback-models :missing)))
        (is
         (not
          (eq :missing
              (cadr-ai::model-compat-value
               model :allowed-fallback-models
               :missing))))))))
