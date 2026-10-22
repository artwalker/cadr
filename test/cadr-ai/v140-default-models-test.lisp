(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

;;; Locked to pi@4a080252f model-resolver.ts defaultModelPerProvider and
;;; packages/ai/test/xiaomi-models.test.ts, plus the published pi-ai 1.4.0
;;; provider catalogs
;;; (github-copilot gpt-6.1-sol, nvidia/nemotron-3.5-super-vl-120b-a12b,
;;; Xiaomi v2.6 replacements).

(defparameter *v140-default-model-ids*
  '((:github-copilot . "gpt-6.1-sol")
    (:nvidia . "nvidia/nemotron-3.5-super-vl-120b-a12b")
    (:xiaomi . "mimo-v2.6-pro")
    (:xiaomi-token-plan-cn . "mimo-v2.6-pro")
    (:xiaomi-token-plan-ams . "mimo-v2.6-pro")
    (:xiaomi-token-plan-sgp . "mimo-v2.6-pro")))

(defparameter *v140-xiaomi-mimo-v26-rows*
  '((:xiaomi "mimo-v2.6-flash" "MiMo-V2.6-Flash"
     "https://api.xiaomimimo.com/v1" 0.14d0 0.28d0 0.0028d0)
    (:xiaomi "mimo-v2.6-pro" "MiMo-V2.6-Pro"
     "https://api.xiaomimimo.com/v1" 0.435d0 0.87d0 0.0036d0)
    (:xiaomi "mimo-v2.6-pro-ultraspeed" "MiMo-V2.6-Pro-UltraSpeed"
     "https://api.xiaomimimo.com/v1" 4.35d0 8.7d0 0.036d0)
    (:xiaomi-token-plan-cn "mimo-v2.6-flash" "MiMo-V2.6-Flash"
     "https://token-plan-cn.xiaomimimo.com/v1" 0d0 0d0 0d0)
    (:xiaomi-token-plan-cn "mimo-v2.6-pro" "MiMo-V2.6-Pro"
     "https://token-plan-cn.xiaomimimo.com/v1" 0d0 0d0 0d0)
    (:xiaomi-token-plan-ams "mimo-v2.6-flash" "MiMo-V2.6-Flash"
     "https://token-plan-ams.xiaomimimo.com/v1" 0d0 0d0 0d0)
    (:xiaomi-token-plan-ams "mimo-v2.6-pro" "MiMo-V2.6-Pro"
     "https://token-plan-ams.xiaomimimo.com/v1" 0d0 0d0 0d0)
    (:xiaomi-token-plan-sgp "mimo-v2.6-flash" "MiMo-V2.6-Flash"
     "https://token-plan-sgp.xiaomimimo.com/v1" 0d0 0d0 0d0)
    (:xiaomi-token-plan-sgp "mimo-v2.6-pro" "MiMo-V2.6-Pro"
     "https://token-plan-sgp.xiaomimimo.com/v1" 0d0 0d0 0d0)))

(defparameter *v140-xiaomi-model-ids*
  '((:xiaomi
     "mimo-v2.6-flash"
     "mimo-v2.6-pro"
     "mimo-v2.6-pro-ultraspeed")
    (:xiaomi-token-plan-cn
     "mimo-v2.6-flash"
     "mimo-v2.6-pro")
    (:xiaomi-token-plan-ams
     "mimo-v2.6-flash"
     "mimo-v2.6-pro")
    (:xiaomi-token-plan-sgp
     "mimo-v2.6-flash"
     "mimo-v2.6-pro")))

(defun v140-thinking-value (metadata level)
  (cdr (assoc level
              (cadr-ai:model-metadata-thinking-level-map metadata)
              :test #'eq)))

(test v140-provider-defaults-resolve-published-models
  (dolist (entry *v140-default-model-ids*)
    (let* ((provider (car entry))
           (model-id (cdr entry))
           (definition (cadr-ai:find-provider-definition provider)))
      (is (string= model-id
                   (cadr-ai:provider-definition-default-model definition)))
      (is (cadr-ai:find-model-metadata provider model-id))
      (multiple-value-bind (adapter model)
          (cadr-ai:instantiate-provider
           provider :api-key "fixture-key")
        (declare (ignore adapter))
        (is (string= model-id (cadr-ai:model-id model)))))))

(test v140-github-copilot-gpt-6.1-sol-matches-published-catalog
  (let ((metadata
          (cadr-ai:find-model-metadata :github-copilot "gpt-6.1-sol"))
        (tier nil))
    (is (string= "GPT-6.1 Sol" (cadr-ai:model-metadata-name metadata)))
    (is (eq :openai-responses (cadr-ai:model-metadata-api metadata)))
    (is (string= "https://api.individual.githubcopilot.com"
                 (cadr-ai:model-metadata-base-url metadata)))
    (is (= 1050000 (cadr-ai:model-metadata-context-window metadata)))
    (is (= 128000 (cadr-ai:model-metadata-max-output-tokens metadata)))
    (is (eq t (cadr-ai:model-metadata-supports-images-p metadata)))
    (is (eq t (cadr-ai:model-metadata-reasoning-p metadata)))
    (is (null (v140-thinking-value metadata :off)))
    (is (null (v140-thinking-value metadata :minimal)))
    (is (string= "low" (v140-thinking-value metadata :low)))
    (is (string= "medium" (v140-thinking-value metadata :medium)))
    (is (string= "high" (v140-thinking-value metadata :high)))
    (is (string= "xhigh" (v140-thinking-value metadata :xhigh)))
    (is (string= "max" (v140-thinking-value metadata :max)))
    (is (equal '(:supports-additional-tools t
                 :supports-mid-convo-system-messages t
                 :supports-openai-grammar-tools t)
               (cadr-ai:model-metadata-compat metadata)))
    (is (equal '(("Copilot-Integration-Id" . "vscode-chat")
                 ("Editor-Plugin-Version" . "copilot-chat/0.35.0")
                 ("Editor-Version" . "vscode/1.107.0")
                 ("User-Agent" . "GitHubCopilotChat/0.35.0"))
               (cadr-ai:model-metadata-headers metadata)))
    (is (= 2d0 (cadr-ai:model-metadata-input-price metadata)))
    (is (= 10d0 (cadr-ai:model-metadata-output-price metadata)))
    (is (= 0.1d0 (cadr-ai:model-metadata-cache-read-price metadata)))
    (is (= 2.5d0 (cadr-ai:model-metadata-cache-write-price metadata)))
    (is (= 1 (length (cadr-ai:model-metadata-cost-tiers metadata))))
    (setf tier (first (cadr-ai:model-metadata-cost-tiers metadata)))
    (is (= 272000 (cadr-ai:model-cost-tier-input-tokens-above tier)))
    (is (= 4d0 (cadr-ai:model-cost-tier-input-price tier)))
    (is (= 15d0 (cadr-ai:model-cost-tier-output-price tier)))
    (is (= 0.2d0 (cadr-ai:model-cost-tier-cache-read-price tier)))
    (is (= 5d0 (cadr-ai:model-cost-tier-cache-write-price tier)))))

(test v140-github-copilot-omits-reasoning-when-off
  (dolist (id '("gpt-6.1-sol" "gpt-6-sol"))
    (multiple-value-bind (provider model)
        (cadr-ai:instantiate-provider
         :github-copilot
         :api-key "fixture-key"
         :model-id id)
      (let ((payload
              (request-spec-payload
               (build-request
                provider model (sample-context)
                :stream-p t
                :reasoning nil))))
        (is (not (cadr-ai::json-present-p payload "reasoning")))))))

(test v140-nvidia-nemotron-3.5-matches-published-catalog
  (let ((metadata
          (cadr-ai:find-model-metadata
           :nvidia "nvidia/nemotron-3.5-super-vl-120b-a12b")))
    (is (string= "Nemotron 3.5 Super VL 120B A12B"
                 (cadr-ai:model-metadata-name metadata)))
    (is (eq :openai-completions (cadr-ai:model-metadata-api metadata)))
    (is (string= "https://integrate.api.nvidia.com/v1"
                 (cadr-ai:model-metadata-base-url metadata)))
    (is (= 1048576 (cadr-ai:model-metadata-context-window metadata)))
    (is (= 8192 (cadr-ai:model-metadata-max-output-tokens metadata)))
    (is (eq t (cadr-ai:model-metadata-supports-images-p metadata)))
    (is (eq t (cadr-ai:model-metadata-reasoning-p metadata)))
    (is (null (cadr-ai:model-metadata-thinking-level-map metadata)))
    (is (equal '(("NVCF-POLL-SECONDS" . "3600"))
               (cadr-ai:model-metadata-headers metadata)))
    (is (equal '(:max-tokens-field :max-tokens
                 :supports-developer-role nil
                 :supports-long-cache-retention nil
                 :supports-reasoning-effort nil
                 :supports-store nil
                 :supports-strict-mode nil)
               (cadr-ai:model-metadata-compat metadata)))
    (is (= 0d0 (cadr-ai:model-metadata-input-price metadata)))
    (is (= 0d0 (cadr-ai:model-metadata-output-price metadata)))
    (is (= 0d0 (cadr-ai:model-metadata-cache-read-price metadata)))
    (is (= 0d0 (cadr-ai:model-metadata-cache-write-price metadata)))
    (is (null (cadr-ai:model-metadata-cost-tiers metadata)))))

(test v140-xiaomi-catalog-replaces-v25-models
  (dolist (row *v140-xiaomi-model-ids*)
    (is (equal (cdr row)
               (sort
                (mapcar #'cadr-ai:model-metadata-id
                        (cadr-ai:list-model-metadata (car row)))
                #'string<)))))

(test v140-xiaomi-mimo-v26-models-match-published-catalog
  (dolist (row *v140-xiaomi-mimo-v26-rows*)
    (destructuring-bind
        (provider id name base-url input output cache-read)
        row
      (let ((metadata
              (cadr-ai:find-model-metadata provider id)))
        (is (string= name (cadr-ai:model-metadata-name metadata)))
        (is (eq :openai-completions (cadr-ai:model-metadata-api metadata)))
        (is (string= base-url (cadr-ai:model-metadata-base-url metadata)))
        (is (= 1048576 (cadr-ai:model-metadata-context-window metadata)))
        (is (= 131072 (cadr-ai:model-metadata-max-output-tokens metadata)))
        (is (eq t (cadr-ai:model-metadata-supports-images-p metadata)))
        (is (eq t (cadr-ai:model-metadata-reasoning-p metadata)))
        (is (string= "off" (v140-thinking-value metadata :off)))
        (is (null (v140-thinking-value metadata :minimal)))
        (is (null (v140-thinking-value metadata :low)))
        (is (null (v140-thinking-value metadata :medium)))
        (is (string= "high" (v140-thinking-value metadata :high)))
        (is (null (v140-thinking-value metadata :xhigh)))
        (is (null (v140-thinking-value metadata :max)))
        (is (equal '(:requires-reasoning-content-on-assistant-messages t
                     :supports-reasoning-effort nil
                     :supports-strict-mode t
                     :thinking-format :deepseek)
                   (cadr-ai:model-metadata-compat metadata)))
        (is (= input (cadr-ai:model-metadata-input-price metadata)))
        (is (= output (cadr-ai:model-metadata-output-price metadata)))
        (is (= cache-read
               (cadr-ai:model-metadata-cache-read-price metadata)))
        (is (= 0d0
               (cadr-ai:model-metadata-cache-write-price metadata)))))))
