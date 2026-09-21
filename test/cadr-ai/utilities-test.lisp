(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(defun utility-error-message (text &optional (reason :error))
  (cadr-ai:make-assistant-message
   :content nil
   :api :test
   :provider :test
   :model "test"
   :stop-reason reason
   :error-message text))

(test content-text-matches-baseline
  (let ((content
          (list
           (cadr-ai:make-thinking-content :thinking "reasoning")
           (cadr-ai:make-text-content :text "first")
           (cadr-ai:make-tool-call :id "1" :name "read")
           (cadr-ai:make-text-content :text "second"))))
    (is (string= "first
second" (cadr-ai:content-text content)))
    (is (string= "firstsecond" (cadr-ai:content-text content "")))
    (is (string= "hello" (cadr-ai:content-text "hello")))))

(test token-estimation-counts-javascript-utf16-code-units
  ;; The fixed TypeScript baseline estimates tokens with text.length / 4.
  ;; JavaScript length counts non-BMP characters as two UTF-16 code units.
  (is (= 2 (cadr-ai:estimate-text-tokens "abc🙂")))
  (is (= 2 (cadr-ai::estimate-content-tokens "abc🙂")))
  (is (= 2
         (cadr-ai:estimate-message-tokens
          (cadr-ai:make-user-message :content "abc🙂"))))
  (is (= 3 (cadr-ai:estimate-text-tokens "🙂🙂🙂🙂🙂")))
  (is (= 1 (cadr-ai:estimate-text-tokens "中文"))))

(test assistant-retry-classification-and-bounded-loop
  (dolist
      (text
       '("overloaded_error"
         "520 status code (no body)"
         "524 status code (no body)"
         "getaddrinfo ENOTFOUND api.example.com"
         "The socket connection was closed unexpectedly"
         "OpenAI Responses stream ended before a terminal response event"
         "ResourceExhausted: Worker request limit"))
    (is (cadr-ai:retryable-assistant-error-p
         (utility-error-message text))))
  (dolist
      (text
       '("429 quota exceeded"
         "insufficient_quota"
         "Monthly usage limit reached"
         "billing failure"))
    (is (not
         (cadr-ai:retryable-assistant-error-p
          (utility-error-message text)))))
  (let ((calls 0)
        (events nil))
    (let ((result
            (cadr-ai:retry-assistant-call
             (lambda ()
               (incf calls)
               (if (< calls 3)
                   (utility-error-message "terminated")
                   (utility-error-message nil :stop)))
             (cadr-ai:make-retry-policy
              :max-retries 3
              :base-delay-milliseconds 0)
             :on-retry-scheduled
             (lambda (attempt maximum delay text)
               (declare (ignore maximum delay text))
               (push (list :scheduled attempt) events))
             :on-retry-attempt-start
             (lambda () (push :started events))
             :on-retry-finished
             (lambda (success attempt error)
               (declare (ignore error))
               (push (list :finished success attempt)
                     events)))))
      (is (eq :stop
              (cadr-ai:assistant-message-stop-reason result)))
      (is (= 3 calls))
      (is (equal
           '((:scheduled 1) :started
             (:scheduled 2) :started
             (:finished t 2))
           (nreverse events))))))

(test goal17-retry-classifier-matches-the-baseline-transient-pattern-matrix
  (dolist
      (text
       '("rate_limit"
         "service_unavailable"
         "upstream server-error"
         "internal_server_error"
         "provider_returned_error"
         "network:error"
         "connection.error"
         "request time out"
         "websocket_closed"
         "websocket:error"))
    (is-true
     (cadr-ai:retryable-assistant-error-p
      (utility-error-message text)))))

(test context-token-estimation-rejects-usage-older-than-a-prefix-message
  ;; pi@13cbf77df packages/ai/src/utils/estimate.ts:63-84 treats a newer
  ;; prefix message (for example, a compaction summary) as invalidating usage
  ;; reported by an older assistant response.
  (let* ((old
           (cadr-ai:make-assistant-message
            :content (list (cadr-ai:make-text-content :text "kept"))
            :usage (cadr-ai:make-usage :input 9500)
            :stop-reason :stop
            :timestamp 100))
         (context
           (cadr-ai:make-context
            :system-prompt "system"
            :messages
            (list
             (cadr-ai:make-user-message
              :content "summary" :timestamp 200)
             old
             (cadr-ai:make-user-message
              :content (make-string 4000 :initial-element #\x)
              :timestamp 300)))))
    (let ((estimate (cadr-ai:estimate-context-tokens context)))
      (is (= 1005 (cadr-ai:context-usage-estimate-tokens estimate)))
      (is (= 0
             (cadr-ai:context-usage-estimate-usage-tokens estimate)))
      (is (= 1005
             (cadr-ai:context-usage-estimate-trailing-tokens estimate)))
      (is (null
           (cadr-ai:context-usage-estimate-last-usage-index estimate))))))

(test context-token-estimation-uses-latest-applicable-usage
  (let ((context
          (cadr-ai:make-context
           :messages
           (list
            (cadr-ai:make-user-message
             :content "summary" :timestamp 200)
            (cadr-ai:make-assistant-message
             :usage (cadr-ai:make-usage :input 9500)
             :stop-reason :stop :timestamp 100)
            (cadr-ai:make-user-message
             :content "new prompt" :timestamp 300)
            (cadr-ai:make-assistant-message
             :usage (cadr-ai:make-usage :input 2000)
             :stop-reason :stop :timestamp 400)
            (cadr-ai:make-user-message
             :content "tail" :timestamp 500)))))
    (let ((estimate (cadr-ai:estimate-context-tokens context)))
      (is (= 2001 (cadr-ai:context-usage-estimate-tokens estimate)))
      (is (= 2000
             (cadr-ai:context-usage-estimate-usage-tokens estimate)))
      (is (= 1
             (cadr-ai:context-usage-estimate-trailing-tokens estimate)))
      (is (= 3
             (cadr-ai:context-usage-estimate-last-usage-index estimate))))))

(test overflow-detection-matches-provider-matrix
  (dolist
      (text
       '("400 `prompt too long; exceeded max context length by 100918 tokens`"
         "400 The input (516368 tokens) is longer than the model's context length (262144 tokens)."
         "Requested token count exceeds the model's maximum context length of 131072 tokens."
         "Input length (265330) exceeds model's maximum context length (262144)."
         "Input length 131393 exceeds the maximum allowed input length of 131040 tokens."
         "Prompt has 5,958,968 tokens, but the configured context size is 256,000 tokens"
         "413 status code (no body)"))
    (is-true
     (cadr-ai:context-overflow-p
      (utility-error-message text)
      262144)))
  (dolist
      (text
       '("500 `model runner crashed unexpectedly`"
         "Throttling error: Too many tokens, please wait before trying again."
         "Service unavailable: The service is temporarily unavailable."
         "Rate limit exceeded, please retry after 30 seconds."
         "Too many requests. Please slow down."))
    (is-false
     (cadr-ai:context-overflow-p
      (utility-error-message text)
      200000)))
  (is-true
   (cadr-ai:context-overflow-p
    (cadr-ai:make-assistant-message
     :stop-reason :length
     :usage
     (cadr-ai:make-usage
      :input 58 :cache-read 1048512 :output 0))
    1048576))
  (is-false
   (cadr-ai:context-overflow-p
    (cadr-ai:make-assistant-message
     :stop-reason :length
     :usage (cadr-ai:make-usage :input 1000 :output 4096))
    200000)))

(test grammar-input-json-deltas-are-append-only
  (let ((buffer (cadr-ai:make-grammar-json-buffer)))
    (let ((first
            (cadr-ai:append-grammar-json-delta
             buffer "payload" "a\"" nil))
          (second
            (cadr-ai:append-grammar-json-delta
             buffer "payload" (format nil "a\"~%b") t)))
      (let ((decoded (cadr-ai::parse-json
                      (concatenate 'string first second))))
        (is (string= (format nil "a\"~%b")
                     (cadr-ai::json-get decoded "payload")))))
    (is (null
         (cadr-ai:append-grammar-json-delta
          buffer "payload" (format nil "a\"~%b") t)))
    (signals error
      (cadr-ai:append-grammar-json-delta
       buffer "payload" "changed" t))))

(test json-schema-tool-arguments-coerce-and-validate
  (flet ((validate-case (schema value)
           (let* ((parameters
                    (cadr-ai::json-object
                     "type" "object"
                     "properties"
                     (cadr-ai::json-object "value" schema)
                     "required" (vector "value")))
                  (tool
                    (cadr-ai:make-tool
                     :name "echo"
                     :parameters parameters))
                  (call
                    (cadr-ai:make-tool-call
                     :id "tool-1"
                     :name "echo"
                     :arguments
                     (cadr-ai::json-object "value" value))))
             (cadr-ai:validate-tool-arguments tool call))))
    (dolist
        (case
         (list
          (list "number" "42" 42)
          (list "number" t 1)
          (list "integer" "42" 42)
          (list "boolean" "true" t)
          (list "boolean" 0 nil)
          (list "string" t "true")
          (list "null" "" 'cadr-ai::null)))
      (let ((result
              (validate-case
               (cadr-ai::json-object "type" (first case))
               (second case))))
        (is (equalp (third case)
                    (cadr-ai::json-get result "value")))))
    (dolist
        (case
         (list
          (list "boolean" "1")
          (list "boolean" "0")
          (list "null" "null")
          (list "integer" "42.1")))
      (signals error
        (validate-case
         (cadr-ai::json-object "type" (first case))
         (second case))))
    (let ((result
            (validate-case
             (cadr-ai::json-object
              "type" (vector "array" "null")
              "items" (cadr-ai::json-object "type" "string"))
             'cadr-ai::null)))
      (is (cadr-ai::json-null-p
           (cadr-ai::json-get result "value"))))))

(test uuid-v7-layout-and-monotonic-order
  (let* ((timestamp #x0123456789ab)
         (first-random
           (make-array
            16 :element-type '(unsigned-byte 8)
            :initial-contents
            '(0 0 0 0 0 0 255 255 255 254 1 17 34 51 68 85)))
         (zero-random
           (make-array 16 :element-type '(unsigned-byte 8)
                      :initial-element 0))
         (cadr-ai::*uuid-last-timestamp* -1)
         (cadr-ai::*uuid-sequence* 0)
         (values (list first-random zero-random zero-random)))
    (flet ((random-source (count)
             (declare (ignore count))
             (pop values)))
      (let ((first
              (cadr-ai:uuid-v7
               :timestamp timestamp
               :random-source #'random-source))
            (second
              (cadr-ai:uuid-v7
               :timestamp timestamp
               :random-source #'random-source))
            (third
              (cadr-ai:uuid-v7
               :timestamp timestamp
               :random-source #'random-source)))
        (is (string= "01234567-89ab-7fff-bfff-f91122334455"
                     first))
        (is (string= "01234567-89ab-7fff-bfff-fc0000000000"
                     second))
        (is (string= "01234567-89ac-7000-8000-000000000000"
                     third))
        (is (string< first second))
        (is (string< second third))))))

(test uuid-v7-default-entropy-is-v7-layout-and-not-constant
  ;; scripts/goal20-paired-paths.lisp session_compact.compact:
  ;; complete-summarization -> make-session-id -> uuid-v7.
  ;; Drives shipped uuid-v7 / default-random-octets, not a reimplementation.
  (let ((first (cadr-ai:uuid-v7))
        (second (cadr-ai:uuid-v7))
        (octets (cadr-ai::default-random-octets 16)))
    (is (= 16 (length octets)))
    (is (equal '(unsigned-byte 8) (array-element-type octets)))
    (is (= 36 (length first)))
    (is (char= #\7 (char first 14)))
    (is (char= #\7 (char second 14)))
    (is (not (string= first second)))))

(test retry-abort-during-wait-uses-one-owner
  (let ((calls 0)
        (finished nil))
    (let ((result
            (cadr-ai:retry-assistant-call
             (lambda ()
               (incf calls)
               (utility-error-message "terminated"))
             (cadr-ai:make-retry-policy
              :max-retries 3
              :base-delay-milliseconds 10)
             :abort-p (constantly t)
             :sleep-function
             (lambda (seconds)
               (declare (ignore seconds)))
             :on-retry-finished
             (lambda (success attempt error)
               (declare (ignore success attempt error))
               (setf finished t)))))
      (is (eq :aborted
              (cadr-ai:assistant-message-stop-reason result)))
      (is (= 1 calls))
      (is-true finished))))
