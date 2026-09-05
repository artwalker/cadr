(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(defun mid-convo-model (&key (compat '(:supports-mid-convo-effort t
                                       :force-adaptive-thinking t)))
  (make-model
   :id "claude-fable-5-1"
   :name "Claude Fable 5.1"
   :provider :anthropic
   :api :anthropic-messages
   :base-url "https://api.anthropic.com"
   :max-tokens 32000
   :reasoning-p t
   :thinking-level-map
   '((:off . nil)
     (:minimal . "low")
     (:low . "low")
     (:medium . "medium")
     (:high . "high")
     (:max . "max"))
   :compat compat))

(defun mid-convo-user (text timestamp)
  (make-user-message :content text :timestamp timestamp))

(defun mid-convo-assistant (model &optional level)
  (cadr-ai:make-assistant-message
   :content
   (list
    (cadr-ai:make-thinking-content
     :thinking "reasoning"
     :signature "signature")
    (cadr-ai:make-text-content :text "answer"))
   :api :anthropic-messages
   :provider (cadr-ai:model-provider model)
   :model (cadr-ai:model-id model)
   :usage (cadr-ai:make-usage)
   :stop-reason :stop
   :timestamp 1
   :provider-thinking-level level))

(defun mid-convo-context (messages)
  (make-context :messages messages))

(defun mid-convo-request (model context &optional reasoning)
  (build-request
   (make-anthropic-provider :api-key "test-key")
   model
   context
   :stream-p t
   :max-tokens 32000
   :reasoning reasoning
   :cache-retention :none))

(defun mid-convo-effort-marker (effort)
  (cadr-ai::json-object
   "role" "system"
   "content" (cadr-ai::json-array)
   "output_config" (cadr-ai::json-object "effort" effort)))

(defun mid-convo-effort-messages (payload)
  (loop for message across (cadr-ai::json-get payload "messages")
        when (string= "system" (cadr-ai::json-get message "role"))
          collect message))

(defun mid-convo-beta-header (headers)
  (cdr (assoc "anthropic-beta" headers :test #'string-equal)))

(test anthropic-mid-convo-reconstructs-historical-marker-and-appends-current
  (let* ((model (mid-convo-model))
         (first (mid-convo-request
                 model
                 (mid-convo-context (list (mid-convo-user "one" 1)))
                 :low))
         (second (mid-convo-request
                  model
                  (mid-convo-context
                   (list
                    (mid-convo-user "one" 1)
                    (mid-convo-assistant model "low")
                    (mid-convo-user "two" 2)))
                  :high))
         (first-messages
           (cadr-ai::json-get (request-spec-payload first) "messages"))
         (second-messages
           (cadr-ai::json-get (request-spec-payload second) "messages"))
         (first-payload (request-spec-payload first))
         (second-payload (request-spec-payload second)))
    (is (= 2 (length first-messages)))
    (is (string= "user" (cadr-ai::json-get (aref first-messages 0) "role")))
    (is (string= "one" (cadr-ai::json-get (aref first-messages 0) "content")))
    (is (json-equal-p
         (mid-convo-effort-marker "low")
         (aref first-messages 1)))
    (loop for index below (length first-messages)
          do (is (json-equal-p
                  (aref first-messages index)
                  (aref second-messages index))))
    (is (json-equal-p
         (mid-convo-effort-marker "high")
         (aref second-messages (1- (length second-messages)))))
    (is (json-equal-p
         (cadr-ai::json-object "effort" "high")
         (cadr-ai::json-get first-payload "output_config")))
    (is (json-equal-p
         (cadr-ai::json-object "effort" "high")
         (cadr-ai::json-get second-payload "output_config")))
    (is (json-equal-p
         (cadr-ai::json-object
          "type" "adaptive"
          "display" "summarized"
          "block_binding"
          (cadr-ai::json-object "prefix_mismatch_behavior" "drop_block"))
         (cadr-ai::json-get second-payload "thinking")))))

(test anthropic-mid-convo-preserves-native-efforts
  (let ((model (mid-convo-model)))
    (dolist (effort '("low" "medium" "high" "xhigh" "max"))
      (let* ((reasoning (intern (string-upcase effort) :keyword))
             (payload
               (request-spec-payload
                (mid-convo-request
                 model
                 (mid-convo-context (list (mid-convo-user "one" 1)))
                 reasoning))))
        (is (json-equal-p
             (list (mid-convo-effort-marker effort))
             (mid-convo-effort-messages payload))
            "native effort ~A" effort)))))

(test anthropic-mid-convo-defaults-omitted-effort-to-high
  (let* ((payload
           (request-spec-payload
            (mid-convo-request
             (mid-convo-model)
             (mid-convo-context (list (mid-convo-user "one" 1))))))
         (messages (cadr-ai::json-get payload "messages")))
    (is (json-equal-p
         (mid-convo-effort-marker "high")
         (aref messages (1- (length messages)))))
    (is (string=
         "drop_block"
         (cadr-ai::json-get
          (cadr-ai::json-get
           (cadr-ai::json-get payload "thinking")
           "block_binding")
          "prefix_mismatch_behavior")))))

(test anthropic-mid-convo-skips-legacy-and-other-provider-assistants
  (let* ((model (mid-convo-model))
         (legacy (mid-convo-assistant model))
         (other (mid-convo-assistant model "low"))
         (payload
           (request-spec-payload
            (mid-convo-request
             model
             (mid-convo-context
              (list
               (mid-convo-user "one" 1)
               legacy
               (mid-convo-user "two" 2)
               (progn
                 (setf (cadr-ai:assistant-message-provider other) :openai)
                 other)
               (mid-convo-user "three" 3)))
             :medium))))
    (is (json-equal-p
         (list (mid-convo-effort-marker "medium"))
         (mid-convo-effort-messages payload)))))

(test anthropic-non-mid-convo-keeps-top-level-effort
  (let* ((model
           (mid-convo-model
            :compat '(:force-adaptive-thinking t)))
         (payload
           (request-spec-payload
            (mid-convo-request
             model
             (mid-convo-context (list (mid-convo-user "one" 1)))
             :low)))
         (messages (cadr-ai::json-get payload "messages")))
    (is (= 1 (length messages)))
    (is (string= "user" (cadr-ai::json-get (aref messages 0) "role")))
    (is (json-equal-p
         (cadr-ai::json-object "effort" "low")
         (cadr-ai::json-get payload "output_config")))
    (is (json-equal-p
         (cadr-ai::json-object "type" "adaptive" "display" "summarized")
         (cadr-ai::json-get payload "thinking")))
    (is (not (cadr-ai::json-present-p
              (cadr-ai::json-get payload "thinking")
              "block_binding")))))

(test anthropic-mid-convo-sends-effort-and-binding-beta-headers
  (let* ((request
           (mid-convo-request
            (mid-convo-model)
            (mid-convo-context (list (mid-convo-user "one" 1)))
            :high))
         (beta (mid-convo-beta-header (request-spec-headers request))))
    (is (search "mid-conversation-output-config-2026-07-01" beta))
    (is (search "thinking-binding-controls-2026-08-01" beta))))

(test anthropic-mid-convo-complete-stores-provider-thinking-level
  (let* ((model (mid-convo-model))
         (*http-request-function*
           (lambda (url &rest arguments)
             (declare (ignore url arguments))
             (values
              (read-fixture "test/fixtures/responses/anthropic-complete.json")
              200
              '(("content-type" . "application/json"))))))
    (let ((message
            (complete-chat
             (make-anthropic-provider :api-key "test-key")
             model
             (mid-convo-context (list (mid-convo-user "one" 1)))
             :max-tokens 32000
             :reasoning :low
             :cache-retention :none)))
      (is (string= "low"
                   (assistant-message-provider-thinking-level message))))))

(test anthropic-mid-convo-stream-stores-provider-thinking-level
  (let* ((model (mid-convo-model))
         (events nil)
         (*http-request-function*
           (lambda (url &rest arguments)
             (declare (ignore url arguments))
             (values
              (open
               (fixture-path
                "test/fixtures/goal20-paired-paths/anthropic-messages.sse")
               :direction :input
               :element-type '(unsigned-byte 8))
              200
              '(("content-type" . "text/event-stream"))))))
    (let ((message
            (stream-chat
             (make-anthropic-provider :api-key "test-key")
             model
             (mid-convo-context (list (mid-convo-user "one" 1)))
             (lambda (event) (push event events))
             :max-tokens 32000
             :reasoning :low
             :cache-retention :none)))
      (is (string= "low"
                   (assistant-message-provider-thinking-level message))))))
