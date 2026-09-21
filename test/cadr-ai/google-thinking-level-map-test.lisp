(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(defun google-thinking-test-model (id &optional thinking-level-map)
  (make-model
   :id id
   :provider :test-google
   :api :google-generative-ai
   :base-url "https://example.invalid/v1beta"
   :max-tokens 4096
   :reasoning-p t
   :thinking-level-map (or thinking-level-map '())))

(test resolve-google-thinking-level-exhaustively-resolves-supported-levels
  (let ((model (google-thinking-test-model "gemini-3.7-flash")))
    (is (eq :high (cadr-ai::resolve-google-thinking-level model :off)))
    (is (eq :minimal (cadr-ai::resolve-google-thinking-level model :minimal)))
    (is (eq :low (cadr-ai::resolve-google-thinking-level model :low)))
    (is (eq :medium (cadr-ai::resolve-google-thinking-level model :medium)))
    (is (eq :high (cadr-ai::resolve-google-thinking-level model :high)))))

(test resolve-google-thinking-level-honors-provider-mapped-values
  (let ((model
          (google-thinking-test-model
           "gemini-3.7-flash"
           '((:high . "high")
             (:xhigh . "MINIMAL")
             (:max . "LOW")))))
    (is (eq :minimal (cadr-ai::resolve-google-thinking-level model :xhigh)))
    (is (eq :low (cadr-ai::resolve-google-thinking-level model :max)))
    (is (eq :high (cadr-ai::resolve-google-thinking-level model :high)))))

(test resolve-google-thinking-level-rejects-invalid-mappings
  (let ((model
          (google-thinking-test-model
           "gemini-3.7-flash"
           '((:xhigh . "extreme")))))
    (signals error
      (cadr-ai::resolve-google-thinking-level model :xhigh))
    (signals error
      (cadr-ai::resolve-google-thinking-level
       (google-thinking-test-model "gemini-3.7-flash")
       :max))))

(test google-generative-ai-honors-uppercase-thinking-level-map
  (let* ((model
           (google-thinking-test-model
            "gemini-3.7-flash"
            '((:high . "LOW"))))
         (payload
           (cadr-ai::request-spec-payload
            (build-request
             (make-google-provider :api-key "key")
             model
             (sample-context)
             :stream-p t
             :max-tokens 4096
             :reasoning :high))))
    (is (string=
         "LOW"
         (cadr-ai::json-get
          (cadr-ai::json-get payload "thinkingConfig")
          "thinkingLevel")))))

(test google-generative-ai-maps-extended-levels-through-thinking-level-map
  (let* ((model
           (google-thinking-test-model
            "gemini-3.7-flash"
            '((:xhigh . "high")
              (:max . "high"))))
         (payload
           (cadr-ai::request-spec-payload
            (build-request
             (make-google-provider :api-key "key")
             model
             (sample-context)
             :stream-p t
             :max-tokens 4096
             :reasoning :xhigh))))
    (is (string=
         "HIGH"
         (cadr-ai::json-get
          (cadr-ai::json-get payload "thinkingConfig")
          "thinkingLevel")))))

(test google-disabled-thinking-avoids-unsupported-minimal-on-gemini-3.8
  (let* ((model
           (cadr-ai::model-from-metadata
            (cadr-ai:find-model-metadata :google "gemini-3.8-flash")))
         (config (cadr-ai::google-thinking-config model nil)))
    (is (null (cadr-ai::json-get config "thinkingBudget")))
    (is (string= "LOW" (cadr-ai::json-get config "thinkingLevel"))))
  (let* ((legacy
           (google-thinking-test-model
            "gemini-3.6-flash"
            '((:off)
              (:minimal . "minimal")
              (:low . "low")
              (:medium . "medium")
              (:high . "high"))))
         (config (cadr-ai::google-thinking-config legacy nil)))
    (is (string= "MINIMAL" (cadr-ai::json-get config "thinkingLevel"))))
  (let* ((budget-model
           (google-thinking-test-model "gemini-2.5-flash"))
         (config (cadr-ai::google-thinking-config budget-model nil)))
    (is (= 0 (cadr-ai::json-get config "thinkingBudget")))))
