(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(defun openai-mid-convo-model
    (&key (compat '(:supports-mid-convo-effort t
                    :supports-strict-mode t)))
  (make-model
   :id "gpt-6-luna"
   :name "GPT-6 Luna"
   :provider :openai
   :api :openai-responses
   :base-url "https://api.openai.com/v1"
   :max-tokens 128000
   :reasoning-p t
   :thinking-level-map
   '((:off . "none")
     (:minimal)
     (:low . "low")
     (:medium . "medium")
     (:high . "high")
     (:xhigh . "xhigh")
     (:max . "max"))
   :compat compat))

(defun openai-mid-convo-user (text)
  (make-user-message :content text :timestamp 0))

(defun openai-mid-convo-assistant (model &optional level)
  (cadr-ai:make-assistant-message
   :content (list (cadr-ai:make-text-content :text "answer"))
   :api :openai-responses
   :provider (cadr-ai:model-provider model)
   :model (cadr-ai:model-id model)
   :usage (cadr-ai:make-usage)
   :stop-reason :stop
   :timestamp 1
   :provider-thinking-level level))

(defun openai-mid-convo-request
    (model context &key (reasoning :high) (api-key "sk-test"))
  (build-request
   (make-openai-provider :api-key api-key)
   model
   context
   :stream-p t
   :max-tokens 128000
   :reasoning reasoning
   :cache-retention :none))

(defun openai-mid-convo-updates (payload)
  (loop for item across (cadr-ai::json-get payload "input")
        when (string= "configuration_update"
                      (or (cadr-ai::json-get item "type") ""))
          collect item))

(defun openai-mid-convo-update (effort)
  (cadr-ai::json-object
   "type" "configuration_update"
   "reasoning" (cadr-ai::json-object "effort" effort)))

(test openai-mid-convo-keeps-reasoning-effort-and-appends-updates
  ;; pi@71023aec1 openai-responses-mid-convo-effort.test.ts
  (let* ((model (openai-mid-convo-model))
         (history (list (openai-mid-convo-user "one")))
         (first
           (openai-mid-convo-request
            model (make-context :messages history) :reasoning :high))
         (first-payload (request-spec-payload first))
         (first-message
           (openai-mid-convo-assistant model "high"))
         (second
           (openai-mid-convo-request
            model
            (make-context
             :messages
             (list (openai-mid-convo-user "one")
                   first-message
                   (openai-mid-convo-user "two")))
            :reasoning :high))
         (second-payload (request-spec-payload second))
         (second-message
           (openai-mid-convo-assistant model "high"))
         (third
           (openai-mid-convo-request
            model
            (make-context
             :messages
             (list (openai-mid-convo-user "one")
                   first-message
                   (openai-mid-convo-user "two")
                   second-message
                   (openai-mid-convo-user "three")))
            :reasoning :low))
         (third-payload (request-spec-payload third))
         (first-input (cadr-ai::json-get first-payload "input"))
         (second-input (cadr-ai::json-get second-payload "input"))
         (third-input (cadr-ai::json-get third-payload "input")))
    (is (string=
         "medium"
         (cadr-ai::json-get
          (cadr-ai::json-get first-payload "reasoning")
          "effort")))
    (is (string=
         "medium"
         (cadr-ai::json-get
          (cadr-ai::json-get second-payload "reasoning")
          "effort")))
    (is (string=
         "medium"
         (cadr-ai::json-get
          (cadr-ai::json-get third-payload "reasoning")
          "effort")))
    (is (= 2 (length first-input)))
    (is (string= "user" (cadr-ai::json-get (aref first-input 0) "role")))
    (is (equalp (openai-mid-convo-update "high")
                (aref first-input 1)))
    (is (equalp
         (subseq first-input 0 (length first-input))
         (subseq second-input 0 (length first-input))))
    (is (equalp
         (subseq second-input 0 (length second-input))
         (subseq third-input 0 (length second-input))))
    (is (equalp
         (list (openai-mid-convo-update "high")
               (openai-mid-convo-update "high")
               (openai-mid-convo-update "low"))
         (openai-mid-convo-updates third-payload)))
    (is (equalp (openai-mid-convo-update "low")
                (aref third-input (1- (length third-input)))))
    (is (string=
         "high"
         (cadr-ai::mid-convo-thinking-level model :high)))
    (is (string=
         "low"
         (cadr-ai::mid-convo-thinking-level model :low)))
    (is (null (cadr-ai::mid-convo-thinking-level model nil)))))

(test openai-mid-convo-level-change-after-tool-result
  (let* ((model (openai-mid-convo-model))
         (assistant
           (cadr-ai:make-assistant-message
            :content
            (list
             (cadr-ai:make-tool-call
              :id "call_1|fc_1"
              :name "lookup"
              :arguments (cadr-ai::json-object)))
            :api :openai-responses
            :provider :openai
            :model "gpt-6-luna"
            :usage (cadr-ai:make-usage)
            :stop-reason :tool-use
            :provider-thinking-level "high"))
         (payload
           (request-spec-payload
            (openai-mid-convo-request
             model
             (make-context
              :messages
              (list
               (openai-mid-convo-user "one")
               assistant
               (cadr-ai:make-tool-result-message
                :tool-call-id "call_1|fc_1"
                :tool-name "lookup"
                :content
                (list (make-text-content :text "result")))))
             :reasoning :low)))
         (input (cadr-ai::json-get payload "input"))
         (tail (list (aref input (- (length input) 2))
                     (aref input (1- (length input))))))
    (is (string= "function_call_output"
                 (cadr-ai::json-get (first tail) "type")))
    (is (string= "call_1"
                 (cadr-ai::json-get (first tail) "call_id")))
    (is (equalp (openai-mid-convo-update "low") (second tail)))))

(test openai-mid-convo-only-before-same-model-replies
  (let* ((model (openai-mid-convo-model))
         (unstamped (openai-mid-convo-assistant model nil))
         (other-provider
           (let ((message (openai-mid-convo-assistant model "high")))
             (setf (cadr-ai:assistant-message-provider message)
                   :opencode)
             message))
         (other-model
           (let ((message (openai-mid-convo-assistant model "high")))
             (setf (cadr-ai:assistant-message-model message)
                   "gpt-6-sol")
             message))
         (recorded (openai-mid-convo-assistant model "high"))
         (payload
           (request-spec-payload
            (openai-mid-convo-request
             model
             (make-context
              :messages
              (list
               (openai-mid-convo-user "one")
               unstamped
               (openai-mid-convo-user "two")
               other-provider
               (openai-mid-convo-user "three")
               other-model
               (openai-mid-convo-user "four")
               recorded
               (openai-mid-convo-user "five")))
             :reasoning :low)))
         (types
           (map 'list
                (lambda (item)
                  (or (cadr-ai::json-get item "type")
                      (cadr-ai::json-get item "role")))
                (cadr-ai::json-get payload "input"))))
    (is (equal
         '("user" "message" "user" "message" "user" "message"
           "user" "configuration_update" "message" "user"
           "configuration_update")
         types))
    (is (equalp
         (list (openai-mid-convo-update "high")
               (openai-mid-convo-update "low"))
         (openai-mid-convo-updates payload)))))

(test openai-mid-convo-falls-back-to-reasoning-effort
  (dolist
      (case
          (list
           (list "Sign in with ChatGPT"
                 "chatgpt-access-token"
                 (openai-mid-convo-model)
                 :low
                 "low")
           (list "compat flag off"
                 "sk-test"
                 (openai-mid-convo-model
                  :compat '(:supports-mid-convo-effort nil))
                 :low
                 "low")
           (list "thinking off"
                 "sk-test"
                 (openai-mid-convo-model)
                 nil
                 "none")))
    (destructuring-bind (name api-key model reasoning expected-effort)
        case
      (declare (ignore name))
      (let* ((history
               (list
                (openai-mid-convo-user "one")
                (openai-mid-convo-assistant model "high")
                (openai-mid-convo-user "two")))
             (payload
               (request-spec-payload
                (openai-mid-convo-request
                 model (make-context :messages history)
                 :reasoning reasoning
                 :api-key api-key))))
        (is (string=
             expected-effort
             (cadr-ai::json-get
              (cadr-ai::json-get payload "reasoning")
              "effort")))
        (is (null (openai-mid-convo-updates payload)))
        (is (null
             (cadr-ai::mid-convo-thinking-level
              model reasoning api-key)))))))

(test openai-catalog-gpt-6-astra-supports-mid-convo-effort
  (let ((meta
          (cadr-ai:find-model-metadata :openai "gpt-6-astra")))
    (is (eq t
            (getf (cadr-ai:model-metadata-compat meta)
                  :supports-mid-convo-effort)))))

(test codex-gpt-6-1-sol-uses-a-500k-context-window
  ;; pi #10840: Codex reports 500k for gpt-6.1-sol. OpenAI and Azure stay
  ;; on the 272k short-context cap. Other Codex GPT-6 ids stay at 272k.
  (dolist (case
           '(("gpt-6.1-sol" :openai 272000
              (:low :medium :high :xhigh :max)
              2d0 10d0 0.1d0 2.5d0)
             ("gpt-6.1-sol" :openai-codex 500000
              (:minimal :low :medium :high :xhigh :max)
              2d0 10d0 0.1d0 2.5d0)
             ("gpt-6.1-sol" :azure 272000
              (:low :medium :high :xhigh :max)
              2d0 10d0 0.1d0 2.5d0)
             ("gpt-6-sol" :openai 272000
              (:off :low :medium :high :xhigh :max)
              2d0 10d0 0.2d0 2.5d0)
             ("gpt-6-sol" :openai-codex 272000
              (:off :minimal :low :medium :high :xhigh :max)
              2d0 10d0 0.2d0 2.5d0)
             ("gpt-6-luna" :openai 272000
              (:off :low :medium :high :xhigh :max)
              0.1d0 0.5d0 0.01d0 0.125d0)
             ("gpt-6-luna" :openai-codex 272000
              (:off :minimal :low :medium :high :xhigh :max)
              0.1d0 0.5d0 0.01d0 0.125d0)))
    (destructuring-bind
        (id provider window levels input output cache-read cache-write)
        case
      (let* ((meta (cadr-ai:find-model-metadata provider id))
             (compat (cadr-ai:model-metadata-compat meta))
             (tier (first (cadr-ai:model-metadata-cost-tiers meta))))
        (is (= window (cadr-ai:model-metadata-context-window meta)))
        (is (= 128000 (cadr-ai:model-metadata-max-output-tokens meta)))
        (is (eq t (cadr-ai:model-metadata-supports-images-p meta)))
        (is (= input (cadr-ai:model-metadata-input-price meta)))
        (is (= output (cadr-ai:model-metadata-output-price meta)))
        (is (= cache-read (cadr-ai:model-metadata-cache-read-price meta)))
        (is (= cache-write (cadr-ai:model-metadata-cache-write-price meta)))
        (is (equal levels
                   (cadr-ai:supported-thinking-levels
                    (cadr-ai::model-from-metadata meta))))
        (is (eq t (getf compat :supports-openai-grammar-tools)))
        (cond
          ((eq provider :azure)
           (is (null (getf compat :supports-mid-convo-effort)))
           (is (null tier)))
          (t
           (is (eq t (getf compat :supports-additional-tools)))
           (is (eq t (getf compat :supports-tool-search)))
           (is (eq t (getf compat :supports-mid-convo-system-messages)))
           (is (eq (eq provider :openai)
                   (eq t (getf compat :supports-mid-convo-effort))))
           (is (= 272000
                  (cadr-ai:model-cost-tier-input-tokens-above tier)))
           (is (= (cadr-ai::round-model-cost (* input 2d0))
                  (cadr-ai:model-cost-tier-input-price tier)))
           (is (= (cadr-ai::round-model-cost (* output 1.5d0))
                  (cadr-ai:model-cost-tier-output-price tier))))))))
  (is (= 272000
         (cadr-ai:model-metadata-context-window
          (cadr-ai:find-model-metadata :openai-codex "gpt-6-astra")))))
