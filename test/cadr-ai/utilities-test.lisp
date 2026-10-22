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
  ;; JavaScript length counts non-BMP characters as two UTF-16 code units.
  ;; pi@4a080252f divides those units by 3.5.
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
         "524 status code (no body)"
         "getaddrinfo ENOTFOUND api.example.com"
         "The socket connection was closed unexpectedly"
         "OpenAI Responses stream ended before a terminal response event"
         "ResourceExhausted: Worker request limit"
         "The system is currently experiencing high demand and cannot process your request. Your request exceeds the maximum usage size allowed during peak load. For improved capacity reliability, consider switching to Provisioned Throughput."))
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

(test assistant-retry-matches-v130-transient-and-limit-wording
  ;; pi@4a080252f packages/ai/src/utils/retry.ts
  ;; #10965, #10920, #10379, #9627. A 429 that names the ChatGPT
  ;; subscription limit stays terminal.
  (dolist
      (text
       '("The service is temporarily unavailable. Please retry later."
         "Service unavailable: The service is temporarily unavailable."
         "Unable to forward upstream stream"
         "The upstream provider returned an error"
         "The pending stream has been canceled"
         "520 status code (no body)"
         "subscription_sharing_usage_unavailable: Usage cannot be checked."
         "subscription_sharing_user_unavailable: User cannot be loaded."
         "server_busy"
         "servers are currently busy"
         "model is at capacity"))
    (is (cadr-ai:retryable-assistant-error-p
         (utility-error-message text))))
  (is (not
       (cadr-ai:retryable-assistant-error-p
        (utility-error-message
         "OpenAI API error (429): {\"code\":\"subscription_sharing_usage_limit_exceeded\",\"message\":\"Usage limit reached.\"}")))))

(test chatgpt-business-workspace-usage-limit-is-not-retryable
  ;; pi@4a080252f packages/ai/test/retry.test.ts
  ;; "keeps the ChatGPT Business workspace usage limit non-retryable".
  ;; The 429 in the formatted message must not win.
  (is (not
       (cadr-ai:retryable-assistant-error-p
        (utility-error-message
         "OpenAI API error (429): {\"code\":\"subscription_sharing_workplace_individual_usage_limit_exceeded\",\"message\":\"Usage limit reached.\"}")))))

(test v140-retry-matches-gateway-vertex-and-codex-disconnect-wording
  ;; pi@4a080252f packages/ai/test/retry.test.ts
  ;; #10920 gateway upstream failures, #10996 node-fetch Vertex token
  ;; refresh, #11057 Codex CLI stream disconnect relayed by proxies.
  (dolist
      (text
       '("request to https://oauth2.googleapis.com/token failed, reason:"
         "request to https://oauth2.googleapis.com/token failed, reason: connect ECONNREFUSED 127.0.0.1:9"
         "unknown: Unable to forward upstream stream"
         "upstream_error: Upstream request failed"
         "upstream_stream_read_error: Upstream response stream was interrupted"
         "Upstream HTTP/2 stream failed"
         "stream disconnected before completion: stream closed before response.completed"))
    (is (cadr-ai:retryable-assistant-error-p
         (utility-error-message text)))))

(test v140-retry-ignores-status-digits-inside-ids-and-byte-counts
  ;; pi@4a080252f packages/ai/test/retry.test.ts #11057
  ;; Status codes inside request ids or longer numbers are not statuses.
  (dolist
      (text
       '("401 {\"type\":\"error\",\"error\":{\"type\":\"authentication_error\",\"message\":\"invalid x-api-key\"},\"request_id\":\"req_011CU503xyz\"}"
         "400 image exceeds 5 MB maximum: 5316784 bytes > 5242880 bytes"))
    (is (not
         (cadr-ai:retryable-assistant-error-p
          (utility-error-message text))))))

(test v140-http-status-boundary-is-ascii-letters-and-digits
  ;; pi@4a080252f packages/ai/src/utils/retry.ts
  ;; (?<![a-z0-9])(?:429|500|502|503|504|520|524)(?![a-z0-9]) with flag i
  ;; and no u flag. é, CJK, and fullwidth digit five (U+FF15) are outside
  ;; that class, so the 503 is a status. An ASCII letter or digit is not.
  (dolist
      (text
       (list
        (format nil "~C503" (code-char #x00E9))
        (format nil "~C503" (code-char #x00C9))
        "错误503"
        (format nil "503~C" (code-char #xFF15))
        (format nil "~C503" (code-char #xFF15))))
    (is (cadr-ai:retryable-assistant-error-p
         (utility-error-message text))))
  (dolist
      (text
       '("503a" "a503" "503A" "A503" "5035" "5503"))
    (is (not
         (cadr-ai:retryable-assistant-error-p
          (utility-error-message text))))))

(test v140-node-fetch-url-breaks-on-javascript-whitespace
  ;; pi@4a080252f packages/ai/src/utils/retry.ts
  ;; "request to \\S+ failed, reason:" — JavaScript \S is the complement
  ;; of /\s/ with no u flag (WhiteSpace and LineTerminator).
  (dolist
      (text
       '("request to https://oauth2.googleapis.com/token failed, reason:"
         "Request To https://oauth2.googleapis.com/token Failed, Reason:"
         "request to x failed, reason:"))
    (is (cadr-ai:retryable-assistant-error-p
         (utility-error-message text))))
  (dolist
      (code
       '(#x0009 #x000A #x000B #x000C #x000D #x0020
         #x00A0 #x1680
         #x2000 #x2001 #x2002 #x2003 #x2004 #x2005
         #x2006 #x2007 #x2008 #x2009 #x200A
         #x2028 #x2029 #x202F #x205F #x3000 #xFEFF))
    (is (not
         (cadr-ai:retryable-assistant-error-p
          (utility-error-message
           (format nil
                   "request to https://oauth2.googleapis.com/to~Cken failed, reason:"
                   (code-char code))))))))

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
  ;; pi@4a080252f packages/ai/src/utils/estimate.ts:63-84 treats a newer
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
      (is (= 1149 (cadr-ai:context-usage-estimate-tokens estimate)))
      (is (= 0
             (cadr-ai:context-usage-estimate-usage-tokens estimate)))
      (is (= 1149
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
      (is (= 2002 (cadr-ai:context-usage-estimate-tokens estimate)))
      (is (= 2000
             (cadr-ai:context-usage-estimate-usage-tokens estimate)))
      (is (= 2
             (cadr-ai:context-usage-estimate-trailing-tokens estimate)))
      (is (= 3
             (cadr-ai:context-usage-estimate-last-usage-index estimate))))))

(test output-limit-reserves-3-5-characters-per-token
  ;; pi #10497. 3500 new characters are 1000 tokens, so a 10000-token
  ;; window with a 4096 safety margin leaves 2904 for the reply.
  (let* ((model
           (cadr-ai:make-model
            :id "test-model"
            :provider :openai
            :api :openai-responses
            :context-window 10000
            :max-tokens 8000))
         (context
           (cadr-ai:make-context
            :messages
            (list
             (cadr-ai:make-assistant-message
              :content (list (cadr-ai:make-text-content :text "kept"))
              :usage (cadr-ai:make-usage :input 2000)
              :stop-reason :stop
              :timestamp 100)
             (cadr-ai:make-user-message
              :content (make-string 3500 :initial-element #\x)
              :timestamp 200))))
         (estimate (cadr-ai:estimate-context-tokens context)))
    (is (= 3000 (cadr-ai:context-usage-estimate-tokens estimate)))
    (is (= 2000
           (cadr-ai:context-usage-estimate-usage-tokens estimate)))
    (is (= 1000
           (cadr-ai:context-usage-estimate-trailing-tokens estimate)))
    (is (= 0
           (cadr-ai:context-usage-estimate-last-usage-index estimate)))
    (is (= 2904
           (cadr-ai::clamp-max-tokens-to-context
            model context 8000)))))

(test overflow-detection-matches-provider-matrix
  (dolist
      (text
       '("400 `prompt too long; exceeded max context length by 100918 tokens`"
         "400 {\"code\":\"1261\",\"message\":\"Prompt too long\"}"
         "400 The input (516368 tokens) is longer than the model's context length (262144 tokens)."
         "Requested token count exceeds the model's maximum context length of 131072 tokens."
         "Input length (265330) exceeds model's maximum context length (262144)."
         "Input length 131393 exceeds the maximum allowed input length of 131040 tokens."
         "Prompt has 5,958,968 tokens, but the configured context size is 256,000 tokens"))
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
  ;; pi@4a080252f #9482. Bodyless HTTP 400 is overflow only for Cerebras.
  ;; pi@4a080252f #11016. Bodyless HTTP 413 is overflow for every provider.
  (let ((bodyless-400 "400 status code (no body)"))
    (is-true
     (cadr-ai:context-overflow-p
      (cadr-ai:make-assistant-message
       :provider :cerebras
       :stop-reason :error
       :error-message bodyless-400)))
    (is-false
     (cadr-ai:context-overflow-p
      (cadr-ai:make-assistant-message
       :provider :opencode-go
       :stop-reason :error
       :error-message bodyless-400))))
  (dolist (provider '(:cerebras :opencode-go :github-copilot))
    (is-true
     (cadr-ai:context-overflow-p
      (cadr-ai:make-assistant-message
       :provider provider
       :stop-reason :error
       :error-message "413 status code (no body)"))))
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

(test http-413-is-request-size-overflow-for-every-provider
  ;; pi@4a080252f packages/ai/test/overflow.test.ts. Zero usage and a
  ;; large window still overflow: the limit is bytes, not tokens.
  (dolist
      (text
       '("github-copilot API error (413): {\"message\":\"failed to parse request\",\"code\":\"\"}"
         "custom-provider API error (413): Payload Too Large"
         "413 {\"error\":{\"message\":\"failed to parse request\",\"code\":\"\"}}"
         "413"))
    (let ((message (utility-error-message text)))
      (is-true (cadr-ai:context-overflow-p message 1000000))
      (is-true (cadr-ai:context-overflow-p message))))
  (dolist
      (text
       '("github-copilot API error (400): {\"message\":\"failed to parse request\",\"code\":\"\"}"
         "custom-provider API error (429): Too many requests"
         "github-copilot API error (400): {\"message\":\"failed to parse request: invalid value 413\"}"
         "custom-provider API error (400): upstream mentioned OpenAI API error (413): invalid input"
         "custom-provider API error (4130): invalid input"
         "4130 failed to parse request"))
    (is-false
     (cadr-ai:context-overflow-p
      (utility-error-message text))))
  (let ((message
          (utility-error-message
           "OpenAI API error (413): {\"message\":\"failed to parse request\"}")))
    (is-false
     (cadr-ai:context-overflow-p
      (utility-error-message
       (cadr-ai:assistant-message-error-message message)
       :aborted)))
    (is-false
     (cadr-ai:context-overflow-p
      (utility-error-message
       (cadr-ai:assistant-message-error-message message)
       :stop)))))

(defun copilot-413-http-body (nested-p)
  (if nested-p
      "{\"error\":{\"message\":\"failed to parse request\",\"code\":\"\"}}"
      "{\"message\":\"failed to parse request\",\"code\":\"\"}"))

(test github-copilot-http-413-stream-is-context-overflow
  ;; pi@4a080252f packages/ai/test/github-copilot-request-size-overflow.test.ts
  (dolist
      (case
       '((413 t t) (413 nil t) (400 t nil)))
    (destructuring-bind (status nested-p overflow-p) case
      (let ((calls 0))
        (multiple-value-bind (provider model)
            (cadr-ai:instantiate-provider
             :github-copilot
             :model-id "copilot-test-model"
             :api-key "test-key"
             :base-url "https://copilot.invalid")
          (let* ((*http-request-function*
                   (lambda (url &rest arguments)
                     (declare (ignore url arguments))
                     (incf calls)
                     (values
                      (make-string-input-stream
                       (copilot-413-http-body nested-p))
                      status
                      '(("content-type" . "application/json")))))
                 (message
                   (cadr-ai:stream-chat
                    provider model
                    (cadr-ai:make-context
                     :messages
                     (list
                      (cadr-ai:make-user-message
                       :content "Continue"
                       :timestamp 0)))
                    (lambda (event) (declare (ignore event)))
                    :max-retries 0)))
            (is (= 1 calls))
            (is (eq :github-copilot
                    (cadr-ai:assistant-message-provider message)))
            (is (eq :error
                    (cadr-ai:assistant-message-stop-reason message)))
            (is (= 0
                   (cadr-ai:usage-total
                    (cadr-ai:assistant-message-usage message))))
            (is (search
                 "failed to parse request"
                 (cadr-ai:assistant-message-error-message message)))
            (when (= status 413)
              (is (search
                   "(413)"
                   (cadr-ai:assistant-message-error-message message))))
            (is (eq overflow-p
                    (cadr-ai:context-overflow-p
                     message 1000000)))))))))

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
