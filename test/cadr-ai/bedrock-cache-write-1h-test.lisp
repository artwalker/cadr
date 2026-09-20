(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(defun bedrock-cache-details-usage
    (&key (cache-write 1000000)
          (details
           (list
            (cadr-ai::json-object
             "ttl" "1h" "inputTokens" 150000)
            (cadr-ai::json-object
             "ttl" "5m" "inputTokens" 600000)
            (cadr-ai::json-object
             "ttl" "1h" "inputTokens" 250000))))
  (apply
   #'cadr-ai::json-object
   (append
    (list
     "inputTokens" 100
     "outputTokens" 5
     "totalTokens" 1000105
     "cacheWriteInputTokens" cache-write)
    (when details
      (list
       "cacheDetails"
       (apply #'cadr-ai::json-array details))))))

(defun bedrock-pricing-metadata
    (&key (input-price 5d0) (cache-write-price 6.25d0))
  (cadr-ai:make-model-metadata
   :provider :amazon-bedrock
   :id "test-bedrock-cache-write-1h"
   :name "test-bedrock-cache-write-1h"
   :api :bedrock-converse-stream
   :input-price input-price
   :output-price 25d0
   :cache-read-price 0.5d0
   :cache-write-price cache-write-price))

(test bedrock-cache-write-1h-tokens-sums-one-hour-entries
  (let ((usage (bedrock-cache-details-usage)))
    (is (= 400000
           (cadr-ai::bedrock-cache-write-1h-tokens usage)))
    (is (= 0
           (cadr-ai::bedrock-cache-write-1h-tokens
            (cadr-ai::json-object
             "cacheWriteInputTokens" 1000))))
    (is (= 0
           (cadr-ai::bedrock-cache-write-1h-tokens
            (cadr-ai::json-object
             "cacheDetails" "not-a-vector"))))))

(test bedrock-cache-write-1h-prices-long-writes-at-two-times-input
  ;; models.lisp: long-write tokens charge (* 2 input-price).
  ;; 8882 tokens at $5/Mtok → 8882/1e6 * 10 = 0.08882
  (let* ((metadata (bedrock-pricing-metadata :input-price 5d0))
         (all-1h
           (cadr-ai:make-usage
            :input 100 :output 5
            :cache-write 8882 :cache-write-1h 8882))
         (only-5m
           (cadr-ai:make-usage
            :input 100 :output 5
            :cache-write 8882)))
    (cadr-ai:calculate-usage-cost all-1h metadata)
    (cadr-ai:calculate-usage-cost only-5m metadata)
    (is (<
         (abs
          (- 0.08882d0
             (cadr-ai:cost-cache-write
              (cadr-ai:usage-cost all-1h))))
         1d-12))
    (is (<
         (abs
          (- (* 8882d0 (/ 6.25d0 1000000d0))
             (cadr-ai:cost-cache-write
              (cadr-ai:usage-cost only-5m))))
         1d-12))))

(test bedrock-metadata-sets-cache-write-1h-before-cost
  (multiple-value-bind (provider model)
      (cadr-ai:instantiate-provider
       :amazon-bedrock
       :model-id "us.anthropic.claude-opus-4-8"
       :api-key "bearer")
    (declare (ignore model))
    (let* ((state
             (cadr-ai::make-provider-stream-state
              :message
              (cadr-ai:make-assistant-message
               :provider :amazon-bedrock
               :model "us.anthropic.claude-opus-4-8"
               :api :bedrock-converse-stream)))
           (usage (bedrock-cache-details-usage))
           (catalog-entry
             (cadr-ai:make-model-metadata
              :provider :amazon-bedrock
              :id "us.anthropic.claude-opus-4-8"
              :name "us.anthropic.claude-opus-4-8"
              :api :bedrock-converse-stream
              :input-price 10d0
              :output-price 50d0
              :cache-read-price 1d0
              :cache-write-price 6.25d0)))
      (let ((cadr-ai::*model-catalog*
              (make-hash-table :test #'equal)))
        (setf
         (gethash
          (cadr-ai::model-catalog-key
           :amazon-bedrock
           "us.anthropic.claude-opus-4-8")
          cadr-ai::*model-catalog*)
         catalog-entry)
        (cadr-ai::reduce-provider-sse-event
         provider state
         (cadr-ai::make-sse-event
          :event "metadata"
          :data
          (cadr-ai::stringify-json
           (cadr-ai::json-object "usage" usage)))
         (constantly nil))
        (let ((message-usage
                (cadr-ai:assistant-message-usage
                 (cadr-ai::provider-stream-state-message
                  state))))
          (is (= 1000000
                 (cadr-ai:usage-cache-write message-usage)))
          (is (= 400000
                 (cadr-ai:usage-cache-write-1h message-usage)))
          ;; 600k * 6.25/Mtok + 400k * 20/Mtok = 3.75 + 8.0 = 11.75
          (is (<
               (abs
                (- 11.75d0
                   (cadr-ai:cost-cache-write
                    (cadr-ai:usage-cost message-usage))))
               1d-10)))))))

(test bedrock-complete-response-sets-cache-write-1h
  (multiple-value-bind (provider model)
      (cadr-ai:instantiate-provider
       :amazon-bedrock
       :model-id "amazon.nova-lite-v1:0"
       :api-key "bearer")
    (let* ((usage (bedrock-cache-details-usage))
           (response
             (cadr-ai::json-object
              "output"
              (cadr-ai::json-object
               "message"
               (cadr-ai::json-object
                "content"
                (cadr-ai::json-array
                 (cadr-ai::json-object "text" "ok"))))
              "stopReason" "end_turn"
              "usage" usage))
           (message
             (cadr-ai:parse-complete-response
              provider model response)))
      (is (= 1000000
             (cadr-ai:usage-cache-write
              (cadr-ai:assistant-message-usage message))))
      (is (= 400000
             (cadr-ai:usage-cache-write-1h
              (cadr-ai:assistant-message-usage message)))))))
