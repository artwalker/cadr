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
    (signals error
      (cadr-ai::resolve-google-thinking-level model :off))
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

(defun google-thinking-config-of (id map &key reasoning thinking-budgets)
  (cadr-ai::json-get
   (cadr-ai::request-spec-payload
    (build-request
     (make-google-provider :api-key "key")
     (google-thinking-test-model id map)
     (sample-context)
     :stream-p t
     :max-tokens 16
     :reasoning reasoning
     :thinking-budgets thinking-budgets))
   "thinkingConfig"))

(test google-omitted-reasoning-clamps-disabled-level-from-the-map
  ;; pi #9455: off and minimal are unsupported, so the disabled request
  ;; uses the next mapped level and does not include thoughts.
  (let ((config
          (google-thinking-config-of
           "gemini-3.8-flash"
           '((:off) (:minimal) (:low . "low")
             (:medium . "medium") (:high . "high")
             (:xhigh) (:max)))))
    (is (string= "LOW" (cadr-ai::json-get config "thinkingLevel")))
    (is (null (cadr-ai::json-get config "includeThoughts")))))

(test google-3-1-pro-keeps-medium-thinking-level
  (let ((config
          (google-thinking-config-of
           "gemini-3.1-pro-preview"
           '((:off) (:minimal) (:low . "low")
             (:medium . "medium") (:high . "high"))
           :reasoning :medium)))
    (is (string= "MEDIUM" (cadr-ai::json-get config "thinkingLevel")))
    (is (eq t (cadr-ai::json-get config "includeThoughts")))))

(test google-2-5-omitted-reasoning-uses-zero-budget
  (let ((config (google-thinking-config-of "gemini-2.5-flash" '())))
    (is (= 0 (cadr-ai::json-get config "thinkingBudget")))))

(test google-4-uses-thinking-level
  (let ((config
          (google-thinking-config-of "gemini-4-argon" '()
                                     :reasoning :medium)))
    (is (string= "MEDIUM" (cadr-ai::json-get config "thinkingLevel")))))

(test google-2-5-maps-extended-level-onto-custom-budget
  (let ((config
          (google-thinking-config-of
           "gemini-2.5-flash"
           '((:xhigh . "high"))
           :reasoning :xhigh
           :thinking-budgets '(:high 1234))))
    (is (= 1234 (cadr-ai::json-get config "thinkingBudget")))))
