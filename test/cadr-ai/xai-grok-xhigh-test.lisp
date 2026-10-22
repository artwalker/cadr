(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

;;; Locked to pi v1.4.0 packages/ai/test/xai-responses.test.ts
;;; getSupportedThinkingLevels(XAI_MODELS["grok-4.3"|"grok-4.5"])
;;; and the published xai catalog thinkingLevelMap (xhigh: "xhigh").

(defun xai-grok-model (id)
  (nth-value 1
             (cadr-ai:instantiate-provider
              :xai :model-id id :api-key "xai-test-token")))

(defun xai-grok-payload (id reasoning)
  (multiple-value-bind (provider model)
      (cadr-ai:instantiate-provider
       :xai :model-id id :api-key "xai-test-token")
    (cadr-ai:request-spec-payload
     (cadr-ai:build-request
      provider model
      (cadr-ai:make-context
       :messages
       (list (cadr-ai:make-user-message :content "hello" :timestamp 1)))
      :stream-p t
      :reasoning reasoning))))

(test xai-grok-43-and-45-offer-xhigh
  (let ((grok-43 (xai-grok-model "grok-4.3"))
        (grok-45 (xai-grok-model "grok-4.5"))
        (grok-46 (xai-grok-model "grok-4.6")))
    (is (equal '(:off :low :medium :high :xhigh)
               (cadr-ai:supported-thinking-levels grok-43)))
    (is (equal '(:low :medium :high :xhigh)
               (cadr-ai:supported-thinking-levels grok-45)))
    (is (equal '(:low :medium :high :xhigh)
               (cadr-ai:supported-thinking-levels grok-46)))
    (is (string= "xhigh"
                 (cdr (assoc :xhigh
                             (cadr-ai::model-thinking-level-map grok-43)))))
    (is (string= "xhigh"
                 (cdr (assoc :xhigh
                             (cadr-ai::model-thinking-level-map grok-45)))))
    (is (string= "none"
                 (cdr (assoc :off
                             (cadr-ai::model-thinking-level-map grok-43)))))
    (is (null (cdr (assoc :off
                          (cadr-ai::model-thinking-level-map grok-45)))))
    (is (null (cdr (assoc :max
                          (cadr-ai::model-thinking-level-map grok-43)))))
    (is (null (cdr (assoc :max
                          (cadr-ai::model-thinking-level-map grok-45)))))
    (is (eq :xhigh (cadr-ai:clamp-thinking-level grok-43 :xhigh)))
    (is (eq :xhigh (cadr-ai:clamp-thinking-level grok-45 :xhigh)))
    (is (eq :xhigh (cadr-ai:clamp-thinking-level grok-45 :max)))
    (dolist (id '("grok-4.3" "grok-4.5"))
      (let* ((payload (xai-grok-payload id :xhigh))
             (reasoning (cadr-ai::json-get payload "reasoning"))
             (include (cadr-ai::json-get payload "include")))
        (is (string= "xhigh" (cadr-ai::json-get reasoning "effort")))
        (is (find "reasoning.encrypted_content" include :test #'string=))))))
