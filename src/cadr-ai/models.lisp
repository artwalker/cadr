(in-package #:cadr-ai)

(defstruct model-cost-tier
  (input-tokens-above 0 :type (integer 0 *))
  (input-price 0d0 :type double-float)
  (output-price 0d0 :type double-float)
  (cache-read-price 0d0 :type double-float)
  (cache-write-price 0d0 :type double-float))

(defstruct model-metadata
  (provider nil :type symbol)
  (id "" :type string)
  (name "" :type string)
  (api nil :type symbol)
  (base-url "" :type string)
  (context-window 0 :type (integer 0 *))
  (max-output-tokens 4096 :type (integer 1 *))
  (supports-images-p nil :type boolean)
  (supports-tools-p t :type boolean)
  (reasoning-p nil :type boolean)
  (thinking-level-map nil :type list)
  (headers nil :type list)
  (compat nil :type list)
  (prompt-cache nil :type list)
  (input-price 0d0 :type double-float)
  (output-price 0d0 :type double-float)
  (cache-read-price 0d0 :type double-float)
  (cache-write-price 0d0 :type double-float)
  (cost-tiers nil :type list))

(cadr-core:define-redacted-print-object
    (model-metadata value stream)
  (format stream ":provider ~A :id ~S :headers [REDACTED]"
          (model-metadata-provider value)
          (model-metadata-id value)))

(defparameter *model-catalog* (make-hash-table :test #'equal))
(defvar *openrouter-metadata-overlay* nil)
(defparameter *image-model-catalog*
  (make-hash-table :test #'equal))

;; Replaced by the generated catalog at load time. Keeping the generation stamp
;; in the image makes catalog provenance available without shipping fixtures.
(defparameter *generated-model-data-generated-at* nil)

(defun model-catalog-key (provider id)
  (cons provider id))

(defun register-image-model (model)
  (setf
   (gethash
    (model-catalog-key
     (image-model-provider model)
     (image-model-id model))
    *image-model-catalog*)
   model)
  model)

(defun find-image-model (provider id)
  (or
   (gethash
    (model-catalog-key provider id)
    *image-model-catalog*)
   (error 'configuration-error
          :message
          (format nil "Unknown image model: ~A/~A" provider id))))

(defun list-image-models (&optional provider)
  (sort
   (loop for model being the hash-values
           of *image-model-catalog*
         when
         (or (null provider)
             (eq provider (image-model-provider model)))
           collect model)
   #'string<
   :key #'image-model-id))

(defun register-generated-image-models (rows)
  (clrhash *image-model-catalog*)
  (dolist (row rows)
    (register-image-model
     (apply #'make-image-model row))))

(defun register-model-metadata (metadata)
  (setf (gethash
         (model-catalog-key
          (model-metadata-provider metadata)
          (model-metadata-id metadata))
         *model-catalog*)
        metadata)
  metadata)

(defun find-model-metadata (provider id)
  (or (and (eq provider :openrouter)
           (hash-table-p *openrouter-metadata-overlay*)
           (gethash id *openrouter-metadata-overlay*))
      (gethash (model-catalog-key provider id) *model-catalog*)
      (error 'configuration-error
             :message
             (format nil "Unknown model: ~A/~A" provider id))))

(defun list-model-metadata (&optional provider)
  (sort
   (loop for metadata being the hash-values of *model-catalog*
         when (or (null provider)
                  (eq provider (model-metadata-provider metadata)))
           collect metadata)
   #'string<
   :key #'model-metadata-id))

(defun calculate-usage-cost (usage metadata)
  (let* ((request-input
           (+ (usage-input usage)
              (usage-cache-read usage)
              (usage-cache-write usage)))
         (tier
           (loop with best = nil
                 for candidate in
                 (model-metadata-cost-tiers metadata)
                 when
                 (and
                  (> request-input
                     (model-cost-tier-input-tokens-above candidate))
                  (or
                   (null best)
                   (>
                    (model-cost-tier-input-tokens-above candidate)
                    (model-cost-tier-input-tokens-above best))))
                   do (setf best candidate)
                 finally (return best)))
         (input-price
           (if tier
               (model-cost-tier-input-price tier)
               (model-metadata-input-price metadata)))
         (output-price
           (if tier
               (model-cost-tier-output-price tier)
               (model-metadata-output-price metadata)))
         (cache-read-price
           (if tier
               (model-cost-tier-cache-read-price tier)
               (model-metadata-cache-read-price metadata)))
         (cache-write-price
           (if tier
               (model-cost-tier-cache-write-price tier)
               (model-metadata-cache-write-price metadata))))
    (flet ((charge (tokens price)
           (* (/ (coerce tokens 'double-float) 1000000d0)
              price)))
      (let* ((input
             (charge (usage-input usage)
                     input-price))
           (output
             (charge (usage-output usage)
                     output-price))
           (cache-read
             (charge (usage-cache-read usage)
                     cache-read-price))
           (long-write
             (or (usage-cache-write-1h usage) 0))
           (short-write
             (- (usage-cache-write usage) long-write))
           (cache-write
             (+
              (charge short-write cache-write-price)
              (charge long-write (* 2d0 input-price)))))
        (setf (usage-cost usage)
              (make-cost
               :input input
               :output output
               :cache-read cache-read
               :cache-write cache-write
               :total (+ input output cache-read cache-write))))))
  usage)

(defun model-from-metadata (metadata)
  (make-model
   :id (model-metadata-id metadata)
   :name (model-metadata-name metadata)
   :provider (model-metadata-provider metadata)
   :api (model-metadata-api metadata)
   :base-url (model-metadata-base-url metadata)
   :max-tokens (model-metadata-max-output-tokens metadata)
   :context-window (model-metadata-context-window metadata)
   :supports-images-p (model-metadata-supports-images-p metadata)
   :supports-tools-p (model-metadata-supports-tools-p metadata)
   :reasoning-p (model-metadata-reasoning-p metadata)
   :thinking-level-map (model-metadata-thinking-level-map metadata)
   :headers (model-metadata-headers metadata)
   :compat (model-metadata-compat metadata)
   :prompt-cache (model-metadata-prompt-cache metadata)))

(defparameter +extended-thinking-levels+
  '(:off :minimal :low :medium :high :xhigh :max))

(defun supported-thinking-levels (model)
  (if (or (null model)
          (not (model-reasoning-p model)))
      '(:off)
      (remove-if-not
       (lambda (level)
         (let ((entry
                 (assoc
                  level (model-thinking-level-map model))))
           (cond
             ((and entry (null (cdr entry))) nil)
             ((member level '(:xhigh :max))
              (and entry (not (null (cdr entry)))))
             (t t))))
       +extended-thinking-levels+)))

(defun clamp-thinking-level (model level)
  (let ((available (supported-thinking-levels model))
        (requested
          (position level +extended-thinking-levels+)))
    (cond
      ((member level available) level)
      ((null requested) (or (first available) :off))
      (t
       (or
        (loop for index from requested
              below (length +extended-thinking-levels+)
              for candidate =
              (nth index +extended-thinking-levels+)
              when (member candidate available)
                return candidate)
        (loop for index downfrom (1- requested) to 0
              for candidate =
              (nth index +extended-thinking-levels+)
              when (member candidate available)
                return candidate)
        (first available)
        :off)))))

(defun models-equal-p (left right)
  (and left right
       (string= (model-id left) (model-id right))
       (eq (model-provider left) (model-provider right))))

(defun round-model-cost (value)
  (/ (round (* value 1000000d0))
     1000000d0))

(defun apply-fireworks-effort-override (row)
  (unless (eq (getf row :provider) :fireworks)
    (return-from apply-fireworks-effort-override row))
  (labels ((plist-key-p (plist key)
             (loop for (candidate) on plist by #'cddr
                   thereis (eq candidate key)))
           (copy-map (map)
             (mapcar (lambda (entry)
                       (cons (car entry) (cdr entry)))
                     map))
           (clear-levels (levels)
             (let ((map (copy-map (getf row :thinking-level-map))))
               (dolist (level levels)
                 (let ((entry (assoc level map :test #'eq)))
                   (when entry
                     (setf (cdr entry) nil))))
               (setf (getf row :thinking-level-map) map))))
    (let ((id (getf row :id))
          (deepseek-map
            '((:off . "none") (:minimal) (:medium)
              (:max . "max") (:xhigh)))
          (qwen-map
            '((:off . "none") (:minimal) (:high)
              (:max) (:xhigh . "xhigh"))))
      (when (and (eq (getf row :api) :anthropic-messages)
                 (not (plist-key-p (getf row :compat)
                                   :allow-empty-signature)))
        (setf (getf row :compat)
              (list* :allow-empty-signature t (getf row :compat))))
      (let ((adaptive
              (cond
                ((member id
                         '("accounts/fireworks/models/deepseek-v4-flash-0731"
                           "accounts/fireworks/models/deepseek-v4-flash-vision-exp"
                           "accounts/fireworks/models/deepseek-v4-pro-0813")
                         :test #'string=)
                 deepseek-map)
                ((member id
                         '("accounts/fireworks/models/qwen3p8-max"
                           "accounts/fireworks/models/qwen3p8-2p4t-a95b")
                         :test #'string=)
                 qwen-map))))
        (when adaptive
          (unless (plist-key-p (getf row :compat)
                               :force-adaptive-thinking)
            (setf (getf row :compat)
                  (list* :force-adaptive-thinking t
                         (getf row :compat))))
          (when (null (getf row :thinking-level-map))
            (setf (getf row :thinking-level-map)
                  (copy-map adaptive)))))
      (when (search "glm-5p2" id)
        (clear-levels '(:low :medium)))
      (when (search "kimi-k3" id)
        (clear-levels '(:medium)))))
  row)

(defun apply-gpt-5-6-pricing-override (row)
  (when
      (member
       (getf row :provider)
       '(:openai :openai-codex :cloudflare-ai-gateway))
    (let ((prices
            (cond
              ((string= (getf row :id) "gpt-5.6-luna")
               '(0.2d0 1.2d0 0.02d0 0.25d0))
              ((string= (getf row :id) "gpt-5.6-terra")
               '(2d0 12d0 0.2d0 2.5d0)))))
      (when prices
        (destructuring-bind
            (input output cache-read cache-write)
            prices
          (setf
           (getf row :input-price) input
           (getf row :output-price) output
           (getf row :cache-read-price) cache-read
           (getf row :cache-write-price) cache-write
           (getf row :cost-tiers)
           (list
            (list
             :input-tokens-above 272000
             :input-price
             (round-model-cost (* input 2d0))
             :output-price
             (round-model-cost (* output 1.5d0))
             :cache-read-price
             (round-model-cost (* cache-read 2d0))
             :cache-write-price
             (round-model-cost (* cache-write 2d0)))))))))
  row)

(defun apply-anthropic-prompt-cache-override (row)
  (when (and (eq (getf row :provider) :anthropic)
             (eq (getf row :api) :anthropic-messages)
             (null (get-properties row '(:prompt-cache))))
    (setf (getf row :prompt-cache) '(:short 300 :long 3600)))
  row)

(defun apply-fireworks-tool-references-override (row)
  (when (and (eq (getf row :provider) :fireworks)
             (eq (getf row :api) :anthropic-messages))
    (let ((compat (getf row :compat)))
      (unless (loop for (key) on compat by #'cddr
                    thereis (eq key :supports-tool-references))
        (setf (getf row :compat)
              (list* :supports-tool-references t compat)))))
  row)

(defun apply-vercel-ai-gateway-empty-signature (row)
  (when (eq (getf row :provider) :vercel-ai-gateway)
    (let ((compat (getf row :compat)))
      (unless (get-properties compat '(:allow-empty-signature))
        (setf (getf row :compat)
              (list* :allow-empty-signature t compat)))))
  row)

(defun apply-azure-provider-id (row)
  ;; pi@71023aec1 generate-models.ts publishes these rows as provider "azure".
  (when (eq (getf row :provider) :azure-openai-responses)
    (setf (getf row :provider) :azure))
  row)

(defun opencode-inference-base-url (url)
  ;; pi@71023aec1 generate-models.ts: Zen and Go left /zen for /inference.
  ;; Replace the /go host first so a later /zen rewrite cannot eat it.
  (cond
    ((not (stringp url)) url)
    ((uiop:string-prefix-p "https://opencode.ai/zen/go" url)
     (concatenate
      'string
      "https://opencode.ai/inference/go"
      (subseq url (length "https://opencode.ai/zen/go"))))
    ((uiop:string-prefix-p "https://opencode.ai/zen" url)
     (concatenate
      'string
      "https://opencode.ai/inference"
      (subseq url (length "https://opencode.ai/zen"))))
    (t url)))

(defun anthropic-disabled-thinking-model-p (model-id)
  ;; pi@71023aec1 ANTHROPIC_DISABLED_THINKING_MODELS. Dated snapshots
  ;; and an OpenRouter anthropic/ prefix do not change the decision.
  (let* ((lower (string-downcase model-id))
         (stripped
           (cond
             ((uiop:string-prefix-p "~anthropic/" lower)
              (subseq lower (length "~anthropic/")))
             ((uiop:string-prefix-p "anthropic/" lower)
              (subseq lower (length "anthropic/")))
             (t lower)))
         (base
           (if (and (>= (length stripped) 9)
                    (char= (char stripped (- (length stripped) 9)) #\-)
                    (every #'digit-char-p
                           (subseq stripped (- (length stripped) 8))))
               (subseq stripped 0 (- (length stripped) 9))
               stripped)))
    (member base
            '("claude-opus-5" "claude-haiku-5-5" "claude-haiku-5.5")
            :test #'string=)))

(defparameter +xiaomi-thinking-level-map+
  '((:off . "off")
    (:minimal)
    (:low)
    (:medium)
    (:high . "high")
    (:xhigh)
    (:max)))

(defun apply-xiaomi-thinking-toggle (row)
  ;; pi@71023aec1 #10818. MiMo Chat Completions documents only
  ;; thinking.type enabled/disabled and rejects reasoning_effort
  ;; "minimal". Every effort level is treated the same, so the catalog
  ;; exposes off and high and the request omits reasoning_effort.
  (when (member (getf row :provider)
                '(:xiaomi :xiaomi-token-plan-ams
                  :xiaomi-token-plan-cn :xiaomi-token-plan-sgp))
    (let ((compat (copy-list (getf row :compat))))
      (setf (getf compat :supports-reasoning-effort) nil)
      (setf (getf row :compat) compat))
    (when (getf row :reasoning-p)
      (setf (getf row :thinking-level-map)
            (mapcar (lambda (entry) (cons (car entry) (cdr entry)))
                    +xiaomi-thinking-level-map+))))
  row)

(defun apply-anthropic-disabled-thinking (row)
  ;; The catalog snapshot still records off: null for these models, which
  ;; means "cannot turn thinking off". The pin stopped merging that entry.
  (when (and (stringp (getf row :id))
             (anthropic-disabled-thinking-model-p (getf row :id)))
    (setf (getf row :thinking-level-map)
          (remove-if
           (lambda (entry)
             (and (consp entry)
                  (eq (car entry) :off)
                  (null (cdr entry))))
           (getf row :thinking-level-map))))
  row)

(defun apply-opencode-inference-endpoints (row)
  (when (member (getf row :provider) '(:opencode :opencode-go))
    (setf (getf row :base-url)
          (opencode-inference-base-url (getf row :base-url)))
    ;; The catalog snapshot still forces MiniMax M2.7 through
    ;; openai-completions. The pin removed that override: OpenCode Go
    ;; rejects the completions protocol for this model.
    (when (and (eq (getf row :provider) :opencode-go)
               (string= (getf row :id) "minimax-m2.7"))
      (setf (getf row :api) :anthropic-messages)
      (let ((base (getf row :base-url)))
        (when (and (stringp base)
                   (uiop:string-suffix-p base "/v1"))
          (setf (getf row :base-url)
                (subseq base 0 (- (length base) 3)))))))
  row)

(defun register-azure-deepseek-model ()
  ;; pi@71023aec1 generate-models.ts azureDeepSeekModels. Foundry rejects
  ;; DeepSeek's thinking field and prompt-cache parameters, and it keeps
  ;; mid-conversation system messages.
  (let ((source (find-model-metadata :deepseek "deepseek-v4-pro")))
    (when source
      (let ((compat (copy-list (model-metadata-compat source)))
            (levels
              (mapcar #'copy-list
                      (model-metadata-thinking-level-map source))))
        (setf (getf compat :thinking-format) :openai)
        (setf (getf compat :supports-developer-role) nil)
        (setf (getf compat :supports-mid-convo-system-messages) t)
        (setf (getf compat :supports-long-cache-retention) nil)
        (let ((max (assoc :max levels)))
          (if max
              (setf (cdr max) "high")
              (setf levels (acons :max "high" levels))))
        (register-model-metadata
         (make-model-metadata
          :provider :azure
          :id "deepseek-v4-pro"
          :name "DeepSeek V4 Pro"
          :api :openai-completions
          :base-url ""
          :context-window (model-metadata-context-window source)
          :max-output-tokens (model-metadata-max-output-tokens source)
          :supports-images-p nil
          :supports-tools-p t
          :reasoning-p t
          :thinking-level-map levels
          :compat compat
          :input-price 1.925d0
          :output-price 3.828d0
          :cache-read-price 0.165d0
          :cache-write-price 0d0))))))

(defun gpt-6-official-prices (id)
  (cond
    ((string= id "gpt-6.1-sol") (values 2d0 10d0 0.1d0 2.5d0))
    ((string= id "gpt-6-sol") (values 2d0 10d0 0.2d0 2.5d0))
    ((string= id "gpt-6-luna") (values 0.1d0 0.5d0 0.01d0 0.125d0))))

(defun gpt-6-official-name (id)
  (cond
    ((string= id "gpt-6.1-sol") "GPT-6.1 Sol")
    ((string= id "gpt-6-sol") "GPT-6 Sol")
    ((string= id "gpt-6-luna") "GPT-6 Luna")))

(defun gpt-6-official-thinking-map (id codex-p)
  ;; pi@71023aec1 applyThinkingLevelMetadata. Astra and GPT-6.1 Sol reject
  ;; reasoning.effort "none". Codex remaps minimal to "low" for xhigh models.
  (list
   (cons :off
         (if (or (string= id "gpt-6-astra")
                 (string= id "gpt-6.1-sol"))
             nil
             "none"))
   (cons :minimal (if codex-p "low" nil))
   (cons :low "low")
   (cons :medium "medium")
   (cons :high "high")
   (cons :xhigh "xhigh")
   (cons :max "max")))

(defun gpt-6-official-compat (provider)
  (cond
    ((eq provider :openai)
     '(:supports-additional-tools t
       :supports-explicit-prompt-cache-mode t
       :supports-mid-convo-effort t
       :supports-mid-convo-system-messages t
       :supports-openai-grammar-tools t
       :supports-tool-search t))
    ((eq provider :openai-codex)
     '(:supports-additional-tools t
       :supports-mid-convo-system-messages t
       :supports-openai-grammar-tools t
       :supports-tool-search t))
    (t '(:supports-openai-grammar-tools t))))

(defun register-gpt-6-official-model (provider id)
  (let ((existing
          (gethash (model-catalog-key provider id) *model-catalog*)))
    (when (and existing
               (eq provider :openai-codex)
               (string= id "gpt-6.1-sol"))
      (setf (model-metadata-context-window existing) 500000))
    (when existing
      (return-from register-gpt-6-official-model nil)))
  (multiple-value-bind (input output cache-read cache-write)
      (gpt-6-official-prices id)
    (let ((codex-p (eq provider :openai-codex)))
      (register-model-metadata
       (make-model-metadata
        :provider provider
        :id id
        :name (gpt-6-official-name id)
        :api (cond
               (codex-p :openai-codex-responses)
               ((eq provider :azure) :azure-openai-responses)
               (t :openai-responses))
        :base-url (cond
                    (codex-p "https://chatgpt.com/backend-api")
                    ((eq provider :azure) "")
                    (t "https://api.openai.com/v1"))
        :context-window
        (if (and codex-p (string= id "gpt-6.1-sol"))
            500000
            272000)
        :max-output-tokens 128000
        :supports-images-p t
        :supports-tools-p t
        :reasoning-p t
        :thinking-level-map (gpt-6-official-thinking-map id codex-p)
        :compat (gpt-6-official-compat provider)
        :input-price input
        :output-price output
        :cache-read-price cache-read
        :cache-write-price cache-write
        :cost-tiers
        (unless (eq provider :azure)
          (list
           (make-model-cost-tier
            :input-tokens-above 272000
            :input-price (round-model-cost (* input 2d0))
            :output-price (round-model-cost (* output 1.5d0))
            :cache-read-price (round-model-cost (* cache-read 2d0))
            :cache-write-price
            (round-model-cost (* cache-write 2d0))))))))))

(defun register-gpt-6-official-models ()
  ;; pi@71023aec1 #10840. These ids are an explicit catalog, not a
  ;; models.dev import. Codex reports 500k only for gpt-6.1-sol.
  (dolist (id '("gpt-6.1-sol" "gpt-6-sol" "gpt-6-luna"))
    (dolist (provider '(:openai :openai-codex :azure))
      (register-gpt-6-official-model provider id))))

(defparameter +github-copilot-catalog-headers+
  '(("Copilot-Integration-Id" . "vscode-chat")
    ("Editor-Plugin-Version" . "copilot-chat/0.35.0")
    ("Editor-Version" . "vscode/1.107.0")
    ("User-Agent" . "GitHubCopilotChat/0.35.0")))

(defparameter +github-copilot-extended-context-ids+
  '("claude-fable-5"
    "claude-opus-4.6"
    "claude-opus-4.7"
    "claude-opus-4.8"
    "claude-opus-5"
    "claude-opus-5.5"
    "claude-sonnet-4.6"
    "claude-sonnet-5"
    "gpt-5.3-codex"
    "gpt-5.4"
    "gpt-5.5"
    "gpt-6-astra"
    "gpt-6-luna"
    "gpt-6-sol"))

(defun github-copilot-long-context-tiers (input output cache-read cache-write)
  (list
   (make-model-cost-tier
    :input-tokens-above 272000
    :input-price (round-model-cost (* input 2d0))
    :output-price (round-model-cost (* output 1.5d0))
    :cache-read-price (round-model-cost (* cache-read 2d0))
    :cache-write-price (round-model-cost (* cache-write 2d0)))))

(defun register-github-copilot-gpt-6 (id input output cache-read cache-write)
  (when (gethash (model-catalog-key :github-copilot id) *model-catalog*)
    (return-from register-github-copilot-gpt-6 nil))
  (register-model-metadata
   (make-model-metadata
    :provider :github-copilot
    :id id
    :name (gpt-6-official-name id)
    :api :openai-responses
    :base-url "https://api.individual.githubcopilot.com"
    :context-window 1000000
    :max-output-tokens 128000
    :supports-images-p t
    :supports-tools-p t
    :reasoning-p t
    :thinking-level-map
    '((:off . "none")
      (:minimal)
      (:low . "low")
      (:medium . "medium")
      (:high . "high")
      (:xhigh . "xhigh")
      (:max . "max"))
    :headers (copy-tree +github-copilot-catalog-headers+)
    :compat '(:supports-openai-grammar-tools t)
    :input-price input
    :output-price output
    :cache-read-price cache-read
    :cache-write-price cache-write
    :cost-tiers
    (github-copilot-long-context-tiers
     input output cache-read cache-write))))

(defun register-github-copilot-opus-5-5 ()
  (when (gethash
         (model-catalog-key :github-copilot "claude-opus-5.5")
         *model-catalog*)
    (return-from register-github-copilot-opus-5-5 nil))
  (register-model-metadata
   (make-model-metadata
    :provider :github-copilot
    :id "claude-opus-5.5"
    :name "Claude Opus 5.5"
    :api :anthropic-messages
    :base-url "https://api.individual.githubcopilot.com"
    :context-window 1000000
    :max-output-tokens 128000
    :supports-images-p t
    :supports-tools-p t
    :reasoning-p t
    :thinking-level-map
    '((:off)
      (:minimal)
      (:low . "low")
      (:medium . "medium")
      (:high . "high")
      (:xhigh . "xhigh")
      (:max . "max"))
    :headers (copy-tree +github-copilot-catalog-headers+)
    :compat '(:force-adaptive-thinking t
              :supports-temperature nil
              :supports-mid-convo-system-messages t)
    :input-price 4d0
    :output-price 20d0
    :cache-read-price 0.2d0
    :cache-write-price 5d0)))

(defun apply-github-copilot-extended-context ()
  (dolist (id +github-copilot-extended-context-ids+)
    (let ((metadata
            (gethash
             (model-catalog-key :github-copilot id)
             *model-catalog*)))
      (when metadata
        (setf (model-metadata-context-window metadata) 1000000)))))

(defun register-github-copilot-pin-models ()
  ;; pi@71023aec1 generate-models.ts. Copilot advertised these before
  ;; models.dev did. The extended-context ids are 1_000_000 even when an
  ;; import reports a larger window.
  (register-github-copilot-opus-5-5)
  (register-github-copilot-gpt-6 "gpt-6-sol" 2d0 10d0 0.2d0 2.5d0)
  (register-github-copilot-gpt-6 "gpt-6-luna" 0.1d0 0.5d0 0.01d0 0.125d0)
  (apply-github-copilot-extended-context))

(defun register-generated-models (rows)
  (clrhash *model-catalog*)
  (dolist (row rows)
    (let ((copy
            (apply-xiaomi-thinking-toggle
             (apply-anthropic-disabled-thinking
              (apply-opencode-inference-endpoints
              (apply-azure-provider-id
              (apply-vercel-ai-gateway-empty-signature
               (apply-fireworks-effort-override
                (apply-fireworks-tool-references-override
                 (apply-anthropic-prompt-cache-override
                  (apply-gpt-5-6-pricing-override
                   (copy-list row))))))))))))
      (setf
       (getf copy :cost-tiers)
       (mapcar
        (lambda (tier)
          (if (typep tier 'model-cost-tier)
              tier
              (apply #'make-model-cost-tier tier)))
        (getf copy :cost-tiers)))
      (register-model-metadata
       (apply #'make-model-metadata copy))))
  (register-azure-deepseek-model)
  (register-gpt-6-official-models)
  (register-github-copilot-pin-models))
