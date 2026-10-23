(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

;;; Numbers below are Node's labelProbabilities / peakConfidence /
;;; calculateCost for the fixtures in
;;; packages/ai/test/openai-decisions.test.ts and
;;; packages/ai/test/llama-cpp-classify.test.ts at v1.4.0.

(defun apis-close (actual expected)
  (< (abs (- (coerce actual 'double-float)
             (coerce expected 'double-float)))
     1.0d-9))

(defun apis-header (headers name)
  (cdr (assoc name headers :test #'string-equal)))

(defun apis-url-path (url)
  (let ((scheme (search "://" url)))
    (subseq url (position #\/ url :start (if scheme (+ scheme 3) 0)))))

(defun apis-record-http (responder)
  (let ((calls nil))
    (values
     (lambda (url &key headers content &allow-other-keys)
       (let ((body (cadr-ai::parse-json content)))
         (push (list :url url :headers headers :body body) calls)
         (funcall responder url body)))
     (lambda () (reverse calls)))))

(defun apis-openai-model ()
  (cadr-ai:find-classifier-model :openai "gpt-6-luna"))

(defun apis-decision-context ()
  (cadr-ai:make-classifier-context
   :state (cadr-ai::json-object
           "text" "The deployment succeeded, thank you.")
   :questions
   (cadr-ai::json-object
    "category"
    (cadr-ai::json-object
     "type" "choice"
     "instructions" "Classify the message"
     "criteria" (cadr-ai::json-object
                 "success" "Successful"
                 "failure" ""))
    "satisfaction"
    (cadr-ai::json-object
     "type" "score"
     "instructions" "Score satisfaction"
     "criteria" (cadr-ai::json-array "low" "neutral" "high"))
    "approved"
    (cadr-ai::json-object
     "type" "bool"
     "instructions" "Does the user approve?"
     "criteria" (cadr-ai::json-object
                 "true" "Approval"
                 "false" "No approval")))))

(defun apis-wire-answers ()
  (cadr-ai::json-array
   (cadr-ai::json-object
    "type" "choice"
    "name" "category"
    "choice" "success"
    "probabilities"
    (cadr-ai::json-array
     (cadr-ai::json-object "value" "success" "probability" 0.9d0)
     (cadr-ai::json-object "value" "failure" "probability" 0.1d0))
    "confidence" 0.8d0)
   (cadr-ai::json-object
    "type" "score"
    "name" "satisfaction"
    "score" 1.8d0
    "probabilities"
    (cadr-ai::json-array
     (cadr-ai::json-object "value" 0 "label" "low" "probability" 0.05d0)
     (cadr-ai::json-object "value" 1 "label" "neutral" "probability" 0.1d0)
     (cadr-ai::json-object "value" 2 "label" "high" "probability" 0.85d0))
    "confidence" 0.7d0)
   (cadr-ai::json-object
    "type" "predicate"
    "name" "approved"
    "probability" 0.95d0)))

(defun apis-wire-usage (&key (input 164))
  (cadr-ai::json-object
   "input_tokens" input
   "input_tokens_details"
   (cadr-ai::json-object "cached_tokens" 0 "cache_write_tokens" 0)
   "output_tokens" 0
   "output_tokens_details" (cadr-ai::json-object "reasoning_tokens" 0)
   "total_tokens" input))

(defun apis-decision-json (answers &optional usage)
  (cadr-ai::stringify-json
   (if usage
       (cadr-ai::json-object "model" "gpt-6-luna"
                             "answers" answers
                             "usage" usage)
       (cadr-ai::json-object "answers" answers))))

(defparameter *apis-llama-servers* 0)

(defun apis-llama-model (&key (api :llama-cpp-classify))
  (incf *apis-llama-servers*)
  (cadr-ai:make-classifier-model
   :id "qwen"
   :name "qwen"
   :api api
   :provider :llama.cpp
   :base-url (format nil "http://llama-~A.test:8080/v1" *apis-llama-servers*)
   :input '(:text)
   :context-window 32768))

(defun apis-char-tokens (content)
  (map 'list #'char-code content))

(defun apis-newline-parts (text)
  (let ((parts nil)
        (start 0))
    (loop for index from 0 below (length text)
          when (char= (char text index) #\Newline)
            do (when (< start index)
                 (push (subseq text start index) parts))
               (push (string #\Newline) parts)
               (setf start (1+ index)))
    (when (< start (length text))
      (push (subseq text start) parts))
    (nreverse parts)))

(defun apis-word-tokens (content)
  (let ((tokens nil))
    (dolist (part (apis-newline-parts content))
      (cond
        ((string= part "Yes") (push 89 tokens))
        ((string= part "No") (push 78 tokens))
        (t (dolist (code (apis-char-tokens part))
             (push code tokens)))))
    (nreverse tokens)))

(defun apis-top-logprobs (pairs)
  (cadr-ai::list-json-array
   (mapcar (lambda (pair)
             (cadr-ai::json-object
              "id" (char-code (char (car pair) 0))
              "token" (car pair)
              "bytes" (cadr-ai::json-array)
              "logprob" (cdr pair)))
           pairs)))

(defun apis-llama-server (&key next template tokenize)
  (apis-record-http
   (lambda (url body)
     (let ((path (apis-url-path url))
           (tokenize (or tokenize #'apis-char-tokens)))
       (cond
         ((string= path "/tokenize")
          (values
           (cadr-ai::stringify-json
            (cadr-ai::json-object
             "tokens"
             (cadr-ai::list-json-array
              (funcall tokenize
                       (cadr-ai::json-get body "content")))))
           200 nil))
         ((string= path "/apply-template")
          (let ((messages (cadr-ai::json-get body "messages")))
            (values
             (cadr-ai::stringify-json
              (cadr-ai::json-object
               "prompt"
               (if template
                   (funcall template messages)
                   (format nil "~{~A~}<|assistant|>~%"
                           (loop for message across messages
                                 collect
                                 (format nil "<|~A|>~%~A~%"
                                         (cadr-ai::json-get message "role")
                                         (cadr-ai::json-get
                                          message "content")))))))
             200 nil)))
         ((string= path "/completion")
          (let ((pairs
                  (if next
                      (funcall next
                               (cadr-ai::json-get body "prompt")
                               (cadr-ai::json-get body "n_probs"))
                      '(("A" . -0.1d0) ("B" . -2.5d0)))))
            (values
             (cadr-ai::stringify-json
              (cadr-ai::json-object
               "content" "A"
               "completion_probabilities"
               (cadr-ai::json-array
                (cadr-ai::json-object
                 "id" 65
                 "token" "A"
                 "top_logprobs" (apis-top-logprobs pairs)))))
             200 nil)))
         (t (values "not found" 404 nil)))))))

(defun apis-answer-by-prompt (prompt depth)
  (declare (ignore depth))
  (cond
    ((search "Answer Yes or No." prompt) '(("Y" . -0.05d0) ("N" . -3d0)))
    ((search "Answer with one level number." prompt)
     '(("2" . -0.2d0) ("1" . -1.8d0) ("0" . -4d0)))
    (t '(("B" . -0.3d0) ("A" . -1.5d0) ("C" . -3d0)))))

(defun apis-llama-context ()
  (cadr-ai:make-classifier-context
   :state (cadr-ai::json-object
           "message" "Help! My payouts have been failing for 3 days.")
   :questions
   (cadr-ai::json-object
    "team"
    (cadr-ai::json-object
     "type" "choice"
     "instructions" "Which team should handle this?"
     "criteria" (cadr-ai::json-object
                 "billing" "Payments and refunds"
                 "technical" "Bugs and outages"
                 "sales" ""))
    "urgent"
    (cadr-ai::json-object
     "type" "bool"
     "instructions" "Does this convey urgency?"
     "criteria" (cadr-ai::json-object
                 "true" "The user needs help soon"
                 "false" "No time pressure"))
    "severity"
    (cadr-ai::json-object
     "type" "score"
     "instructions" "How severe is this?"
     "criteria" (cadr-ai::json-array "low" "medium" "high")))))

(defun apis-pick-context ()
  (cadr-ai:make-classifier-context
   :state (cadr-ai::json-object)
   :questions
   (cadr-ai::json-object
    "pick"
    (cadr-ai::json-object
     "type" "choice"
     "instructions" "Pick one"
     "criteria" (cadr-ai::json-object "a" "" "b" "")))))

(defun apis-completion-depths (calls)
  (loop for call in calls
        when (string= (apis-url-path (getf call :url)) "/completion")
          collect (cadr-ai::json-get (getf call :body) "n_probs")))

(defun apis-join-lines (lines)
  (format nil "~{~A~^~%~}" lines))

(test classifier-apis-openai-catalog-and-long-context-tier
  (let* ((model (apis-openai-model))
         (tier (first (cadr-ai::classifier-model-cost-tiers model))))
    (is (eq :openai-decisions (cadr-ai:classifier-model-api model)))
    (is (string= "https://api.openai.com/v1"
                 (cadr-ai:classifier-model-base-url model)))
    (is (= 922000 (cadr-ai:classifier-model-context-window model)))
    (is (apis-close (cadr-ai:classifier-model-input-price model) 0.1d0))
    (is (= 272000 (cadr-ai:model-cost-tier-input-tokens-above tier)))
    (is (apis-close (cadr-ai:model-cost-tier-input-price tier) 0.2d0))
    (is (apis-close (cadr-ai:model-cost-tier-output-price tier) 0d0))))

(test classifier-apis-openai-maps-questions-and-answers-by-name
  (let ((answers (apis-wire-answers)))
    (multiple-value-bind (http calls)
        (apis-record-http
         (lambda (url body)
           (declare (ignore url body))
           (values
            (apis-decision-json
             (cadr-ai::list-json-array
              (nreverse (coerce answers 'list)))
             (apis-wire-usage))
            200 nil)))
      (let* ((*http-request-function* http)
             (result
               (cadr-ai:classify-model
                (apis-openai-model)
                (apis-decision-context)
                :api-key "secret"
                :temperature 1.5d0))
             (call (first (funcall calls)))
             (body (getf call :body))
             (questions (cadr-ai::json-get body "questions"))
             (category (cadr-ai::json-get
                        (cadr-ai:classifier-result-answers result)
                        "category"))
             (satisfaction (cadr-ai::json-get
                            (cadr-ai:classifier-result-answers result)
                            "satisfaction"))
             (approved (cadr-ai::json-get
                        (cadr-ai:classifier-result-answers result)
                        "approved"))
             (usage (cadr-ai:classifier-result-usage result)))
        (is (= 1 (length (funcall calls))))
        (is (string= "https://api.openai.com/v1/decisions"
                     (getf call :url)))
        (is (string= "Bearer secret"
                     (apis-header (getf call :headers) "authorization")))
        (is (not (cadr-ai::json-present-p body "temperature")))
        (is (string= "{\"text\":\"The deployment succeeded, thank you.\"}"
                     (cadr-ai::json-get body "input")))
        (is (string= "gpt-6-luna" (cadr-ai::json-get body "model")))
        (is (= 3 (length questions)))
        (is (string= "choice"
                     (cadr-ai::json-get (aref questions 0) "type")))
        (is (string= "category"
                     (cadr-ai::json-get (aref questions 0) "name")))
        (is (string= "Successful"
                     (cadr-ai::json-get
                      (aref (cadr-ai::json-get
                             (aref questions 0) "choices")
                            0)
                      "description")))
        (is (not (cadr-ai::json-present-p
                  (aref (cadr-ai::json-get (aref questions 0) "choices") 1)
                  "description")))
        (is (string= "score"
                     (cadr-ai::json-get (aref questions 1) "type")))
        (is (equal '("low" "neutral" "high")
                   (map 'list
                        (lambda (level)
                          (cadr-ai::json-get level "label"))
                        (cadr-ai::json-get (aref questions 1) "levels"))))
        (is (string= "predicate"
                     (cadr-ai::json-get (aref questions 2) "type")))
        (is (string=
             (format nil "Does the user approve?~%~%True means: Approval~%False means: No approval")
             (cadr-ai::json-get (aref questions 2) "instructions")))
        (is (eq :stop (cadr-ai:classifier-result-stop-reason result)))
        (is (string= "success" (cadr-ai::json-get category "choice")))
        (is (apis-close 0.9d0
                        (cadr-ai::json-get
                         (cadr-ai::json-get category "probabilities")
                         "success")))
        (is (apis-close 0.1d0
                        (cadr-ai::json-get
                         (cadr-ai::json-get category "probabilities")
                         "failure")))
        (is (apis-close 0.8d0 (cadr-ai::json-get category "confidence")))
        (is (apis-close 1.8d0 (cadr-ai::json-get satisfaction "score")))
        (is (apis-close 0.7d0
                        (cadr-ai::json-get satisfaction "confidence")))
        (is (string= "bool" (cadr-ai::json-get approved "type")))
        (is (apis-close 0.95d0 (cadr-ai::json-get approved "probability")))
        (is (= 164 (usage-input usage)))
        (is (= 0 (usage-output usage)))
        (is (= 0 (usage-cache-read usage)))
        (is (= 164 (usage-total usage)))
        (is (apis-close 0.0000164d0
                        (cadr-ai:cost-total (cadr-ai:usage-cost usage))))))))

(test classifier-apis-openai-long-context-price
  (dolist (row '((300000 0.06d0) (272000 0.0272d0) (272001 0.0544002d0)))
    (destructuring-bind (tokens expected) row
      (let ((*http-request-function*
              (lambda (url &key &allow-other-keys)
                (declare (ignore url))
                (values
                 (apis-decision-json
                  (apis-wire-answers)
                  (apis-wire-usage :input tokens))
                 200 nil))))
        (let ((usage
                (cadr-ai:classifier-result-usage
                 (cadr-ai:classify-model
                  (apis-openai-model)
                  (apis-decision-context)
                  :api-key "secret"))))
          (is (apis-close expected
                          (cadr-ai:cost-total
                           (cadr-ai:usage-cost usage)))))))))

(test classifier-apis-openai-sends-images-in-one-user-message
  (multiple-value-bind (http calls)
      (apis-record-http
       (lambda (url body)
         (declare (ignore url body))
         (values (apis-decision-json (apis-wire-answers)) 200 nil)))
    (let* ((*http-request-function* http)
           (result
             (cadr-ai:classify-model
              (apis-openai-model)
              (cadr-ai:make-classifier-context
               :state (cadr-ai::json-object
                       "text" "The deployment succeeded, thank you.")
               :questions (cadr-ai:classifier-context-questions
                           (apis-decision-context))
               :images (list (classifier-image "aW1hZ2U=" "image/png")
                             (classifier-image "aW1hZ2U=" "image/jpeg")))
              :api-key "secret"))
           (input (cadr-ai::json-get (getf (first (funcall calls)) :body)
                                     "input"))
           (content (cadr-ai::json-get (aref input 0) "content")))
      (is (eq :stop (cadr-ai:classifier-result-stop-reason result)))
      (is (string= "user" (cadr-ai::json-get (aref input 0) "role")))
      (is (string= "input_text" (cadr-ai::json-get (aref content 0) "type")))
      (is (string= "{\"text\":\"The deployment succeeded, thank you.\"}"
                   (cadr-ai::json-get (aref content 0) "text")))
      (is (string= "data:image/png;base64,aW1hZ2U="
                   (cadr-ai::json-get (aref content 1) "image_url")))
      (is (string= "data:image/jpeg;base64,aW1hZ2U="
                   (cadr-ai::json-get (aref content 2) "image_url"))))))

(test classifier-apis-openai-rejects-129-images-before-sending
  (let ((calls 0))
    (let* ((*http-request-function*
             (lambda (url &key &allow-other-keys)
               (declare (ignore url))
               (incf calls)
               (values (apis-decision-json (apis-wire-answers)) 200 nil)))
           (result
             (cadr-ai:classify-model
              (apis-openai-model)
              (cadr-ai:make-classifier-context
               :state (cadr-ai::json-object "text" "x")
               :questions (cadr-ai:classifier-context-questions
                           (apis-decision-context))
               :images (loop repeat 129
                             collect (classifier-image "aW1hZ2U=" "image/png")))
              :api-key "secret")))
      (is (= 0 calls))
      (is (eq :error (cadr-ai:classifier-result-stop-reason result)))
      (is (search "at most 128 images, got 129"
                  (cadr-ai:classifier-result-error-message result))))))

(test classifier-apis-openai-refusal-keeps-billed-usage
  (let* ((answers (coerce (apis-wire-answers) 'list))
         (*http-request-function*
           (lambda (url &key &allow-other-keys)
             (declare (ignore url))
             (values
              (apis-decision-json
               (cadr-ai::list-json-array
                (list (first answers)
                      (second answers)
                      (cadr-ai::json-object
                       "type" "refusal"
                       "name" "approved")))
               (apis-wire-usage))
              200 nil)))
         (result
           (cadr-ai:classify-model
            (apis-openai-model) (apis-decision-context) :api-key "secret")))
    (is (eq :error (cadr-ai:classifier-result-stop-reason result)))
    (is (= 0 (hash-table-count
              (cadr-ai:classifier-result-answers result))))
    (is (string= "OpenAI Decisions refused to answer approved"
                 (cadr-ai:classifier-result-error-message result)))
    (is (= 164 (usage-input (cadr-ai:classifier-result-usage result))))))

(test classifier-apis-openai-missing-and-mistyped-answers
  (let* ((answers (coerce (apis-wire-answers) 'list))
         missing
         mistyped)
    (let ((*http-request-function*
            (lambda (url &key &allow-other-keys)
              (declare (ignore url))
              (values
               (apis-decision-json
                (cadr-ai::list-json-array (subseq answers 0 2)))
               200 nil))))
      (setf missing
            (cadr-ai:classify-model
             (apis-openai-model)
             (apis-decision-context)
             :api-key "secret")))
    (let ((*http-request-function*
            (lambda (url &key &allow-other-keys)
              (declare (ignore url))
              (values
               (apis-decision-json
                (cadr-ai::list-json-array
                 (list (first answers)
                       (second answers)
                       (cadr-ai::json-object
                        "type" "score"
                        "name" "approved"))))
               200 nil))))
      (setf mistyped
            (cadr-ai:classify-model
             (apis-openai-model)
             (apis-decision-context)
             :api-key "secret")))
    (is (eq :error (cadr-ai:classifier-result-stop-reason missing)))
    (is (search "did not return an answer for approved"
                (cadr-ai:classifier-result-error-message missing)))
    (is (eq :error (cadr-ai:classifier-result-stop-reason mistyped)))
    (is (search "did not return a predicate answer for approved"
                (cadr-ai:classifier-result-error-message mistyped)))))

(test classifier-apis-openai-keeps-prototype-question-ids
  (let* ((questions (cadr-ai::json-object))
         (*http-request-function*
           (lambda (url &key &allow-other-keys)
             (declare (ignore url))
             (values
              (apis-decision-json
               (cadr-ai::json-array
                (cadr-ai::json-object
                 "type" "predicate"
                 "name" "__proto__"
                 "probability" 0.75d0)))
              200 nil))))
    (setf (gethash "__proto__" questions)
          (cadr-ai::json-object
           "type" "bool"
           "instructions" "Is this true?"
           "criteria" (cadr-ai::json-object "true" "Yes" "false" "No")))
    (let* ((result
             (cadr-ai:classify-model
              (apis-openai-model)
              (cadr-ai:make-classifier-context
               :state (cadr-ai::json-object)
               :questions questions)
              :api-key "secret"))
           (answers (cadr-ai:classifier-result-answers result)))
      (is (eq :stop (cadr-ai:classifier-result-stop-reason result)))
      (is (cadr-ai::json-present-p answers "__proto__"))
      (is (string= "bool"
                   (cadr-ai::json-get
                    (cadr-ai::json-get answers "__proto__")
                    "type")))
      (is (apis-close
           0.75d0
           (cadr-ai::json-get
            (cadr-ai::json-get answers "__proto__")
            "probability"))))))

(test classifier-apis-openai-504-is-not-retried
  (let ((calls 0))
    (let* ((*http-request-function*
             (lambda (url &key &allow-other-keys)
               (declare (ignore url))
               (incf calls)
               (values "<!DOCTYPE html><html>Gateway time-out</html>"
                       504
                       '(("retry-after-ms" . "0")))))
           (cadr-ai::*retry-sleep-function*
             (lambda (seconds)
               (error "504 must not sleep, got ~A" seconds)))
           (result
             (cadr-ai:classify-model
              (apis-openai-model) (apis-decision-context) :api-key "secret"))
           (message (cadr-ai:classifier-result-error-message result)))
      (is (= 1 calls))
      (is (eq :error (cadr-ai:classifier-result-stop-reason result)))
      (is (search "OpenAI Decisions error (504): the request timed out at the gateway"
                  message))
      (is (not (search "<html>" message))))))

(test classifier-apis-openai-retries-other-5xx
  (let ((calls 0)
        (slept nil))
    (let* ((*http-request-function*
             (lambda (url &key &allow-other-keys)
               (declare (ignore url))
               (incf calls)
               (if (= calls 1)
                   (values "busy" 503 '(("retry-after-ms" . "0")))
                   (values (apis-decision-json (apis-wire-answers)) 200 nil))))
           (cadr-ai::*retry-sleep-function*
             (lambda (seconds)
               (when (> seconds 0.001d0)
                 (error "retry-after-ms 0 slept ~A" seconds))
               (push seconds slept)))
           (result
             (cadr-ai:classify-model
              (apis-openai-model) (apis-decision-context) :api-key "secret")))
      (is (= 2 calls))
      (is (= 1 (length slept)))
      (is (eq :stop (cadr-ai:classifier-result-stop-reason result))))))

(test classifier-apis-openai-includes-http-error-body
  (let* ((*http-request-function*
           (lambda (url &key &allow-other-keys)
             (declare (ignore url))
             (values
              "{\"error\":{\"message\":\"Decision input exceeds the token limit.\",\"type\":\"invalid_request_error\"}}"
              400 nil)))
         (result
           (cadr-ai:classify-model
            (apis-openai-model)
            (apis-decision-context)
            :api-key "secret"
            :max-retries 0))
         (message (cadr-ai:classifier-result-error-message result)))
    (is (eq :error (cadr-ai:classifier-result-stop-reason result)))
    (is (search "OpenAI Decisions error (400)" message))
    (is (search "Decision input exceeds the token limit." message))))

(test classifier-apis-openai-rejects-other-api-and-missing-key
  (let ((calls 0))
    (let* ((*http-request-function*
             (lambda (url &key &allow-other-keys)
               (declare (ignore url))
               (incf calls)
               (values (apis-decision-json (apis-wire-answers)) 200 nil)))
           (other
             (cadr-ai::classify-openai-decisions
              (cadr-ai:make-classifier-model
               :id "gpt-6-luna"
               :name "GPT-6 Luna"
               :provider :openai
               :api :typesafe-system-one
               :base-url "https://api.openai.com/v1")
              (apis-decision-context)
              :api-key "secret"))
           (no-key
             (cadr-ai:classify-model
              (apis-openai-model) (apis-decision-context))))
      (is (= 0 calls))
      (is (search "Unsupported classifier API: typesafe-system-one"
                  (cadr-ai:classifier-result-error-message other)))
      (is (search "No API key for provider: openai"
                  (cadr-ai:classifier-result-error-message no-key))))))

(test classifier-apis-llama-answers-from-label-logprobs
  (multiple-value-bind (http calls)
      (apis-llama-server :next #'apis-answer-by-prompt
                         :tokenize #'apis-word-tokens)
    (let* ((model (apis-llama-model))
           (*http-request-function* http)
           (result
             (cadr-ai:classify-model
              model (apis-llama-context) :api-key "local"))
           (answers (cadr-ai:classifier-result-answers result))
           (team (cadr-ai::json-get answers "team"))
           (urgent (cadr-ai::json-get answers "urgent"))
           (severity (cadr-ai::json-get answers "severity"))
           (probabilities (cadr-ai::json-get team "probabilities"))
           (root (cadr-ai::llama-server-root
                  (cadr-ai:classifier-model-base-url model)))
           (recorded (funcall calls))
           (completion
             (find-if (lambda (call)
                        (string= (apis-url-path (getf call :url))
                                 "/completion"))
                      recorded))
           (template
             (find-if (lambda (call)
                        (string= (apis-url-path (getf call :url))
                                 "/apply-template"))
                      recorded)))
      (is (null (cadr-ai:classifier-result-error-message result)))
      (is (eq :stop (cadr-ai:classifier-result-stop-reason result)))
      (is (string= "technical" (cadr-ai::json-get team "choice")))
      (is (apis-close 0.2201068931001209d0
                      (cadr-ai::json-get probabilities "billing")))
      (is (apis-close 0.7307806205926757d0
                      (cadr-ai::json-get probabilities "technical")))
      (is (apis-close 0.0491124863072033d0
                      (cadr-ai::json-get probabilities "sales")))
      (is (apis-close 0.5961709308890135d0
                      (cadr-ai::json-get team "confidence")))
      (is (string= "bool" (cadr-ai::json-get urgent "type")))
      (is (apis-close 0.9502634884414434d0
                      (cadr-ai::json-get urgent "probability")))
      (is (apis-close 1.798542308733055d0
                      (cadr-ai::json-get severity "score")))
      (is (apis-close 0.7252226392349155d0
                      (cadr-ai::json-get severity "confidence")))
      (dolist (call recorded)
        (is (eql 0 (search (concatenate 'string root "/")
                           (getf call :url))))
        (is (string= "qwen"
                     (cadr-ai::json-get (getf call :body) "model")))
        (is (string= "Bearer local"
                     (apis-header (getf call :headers) "authorization"))))
      (is (= 1 (cadr-ai::json-get (getf completion :body) "n_predict")))
      (is (= 256 (cadr-ai::json-get (getf completion :body) "n_probs")))
      (is (cadr-ai::json-present-p (getf completion :body)
                                   "post_sampling_probs"))
      (is (null (cadr-ai::json-get (getf completion :body)
                                   "post_sampling_probs")))
      (is (eq t (cadr-ai::json-get (getf completion :body) "cache_prompt")))
      (let ((kwargs (cadr-ai::json-get (getf template :body)
                                       "chat_template_kwargs")))
        (is (cadr-ai::json-present-p kwargs "enable_thinking"))
        (is (null (cadr-ai::json-get kwargs "enable_thinking")))))))

(test classifier-apis-llama-prompt-repeats-state
  (let* ((context (apis-llama-context))
         (rendered (cadr-ai::llama-render-question context "team"))
         (state
           (format nil "State:~%{~% \"message\": \"Help! My payouts have been failing for 3 days.\"~%}")))
    (is (equal '("A" "B" "C")
               (cadr-ai::llama-labeled-question-labels rendered)))
    (is (equal '("billing" "technical" "sales")
               (cadr-ai::llama-labeled-question-keys rendered)))
    (is (string=
         (apis-join-lines
          (list
           state
           ""
           "Task: answer each of the following questions about the state."
           ""
           "Question: Which team should handle this?"
           ""
           "Options:"
           "- billing: Payments and refunds"
           "- technical: Bugs and outages"
           "- sales"
           ""
           "Question: Does this convey urgency?"
           ""
           "Yes means: The user needs help soon"
           "No means: No time pressure"
           ""
           "Question: How severe is this?"
           ""
           "Levels:"
           "0. low"
           "1. medium"
           "2. high"
           ""
           state
           ""
           "Question: Which team should handle this?"
           ""
           "Options:"
           "A. billing: Payments and refunds"
           "B. technical: Bugs and outages"
           "C. sales"
           ""
           "Answer with one letter."))
         (cadr-ai::llama-labeled-question-content rendered)))))

(test classifier-apis-llama-state-numbers-match-json-stringify
  ;; Right-hand sides are Node JSON.stringify of the same literals.
  ;; v1.4.0 renderState is `State:\n${JSON.stringify(state, null, 1)}`.
  ;; parse-json reads 1.5 as 3/2 and 0.1 as 1/10.
  (is (eql 3/2 (cadr-ai::parse-json "1.5")))
  (is (eql 1/10 (cadr-ai::parse-json "0.1")))
  (is (string= "1.5" (cadr-ai::js-json-text 3/2)))
  (is (string= "0.1" (cadr-ai::js-json-text 1/10)))
  (is (string= "1.5" (cadr-ai::js-json-text 1.5d0)))
  (is (string= "0.1" (cadr-ai::js-json-text 0.1d0)))
  (is (string= "0" (cadr-ai::js-json-text -0.0d0)))
  (dolist (pair '(("1.5" . "1.5")
                  ("0.1" . "0.1")
                  ("-1.5" . "-1.5")
                  ("0" . "0")
                  ("1e-7" . "1e-7")
                  ("0.000001" . "0.000001")
                  ("1e20" . "100000000000000000000")
                  ("1e21" . "1e+21")
                  ("1e22" . "1e+22")
                  ("9007199254740993" . "9007199254740992")
                  ("5.9604644775390625e-8" . "5.960464477539063e-8")
                  ("1.0000000000000002" . "1.0000000000000002")
                  ("0.30000000000000004" . "0.30000000000000004")))
    (is (string= (cdr pair)
                 (cadr-ai::js-json-text
                  (cadr-ai::parse-json (car pair))))))
  (let* ((state
           (cadr-ai::parse-json
            "{\"n\":1.5,\"p\":0.1,\"tiny\":1e-7,\"big\":1e21}"))
         (expected
           (format nil "{~% \"n\": 1.5,~% \"p\": 0.1,~% \"tiny\": 1e-7,~% \"big\": 1e+21~%}"))
         (rendered
           (cadr-ai::llama-render-question
            (cadr-ai:make-classifier-context
             :state state
             :questions
             (cadr-ai::json-object
              "urgent"
              (cadr-ai::json-object
               "type" "bool"
               "instructions" "Does this convey urgency?"
               "criteria" (cadr-ai::json-object
                           "true" "soon"
                           "false" "later"))))
            "urgent"))
         (content (cadr-ai::llama-labeled-question-content rendered)))
    (is (string= expected (cadr-ai::js-json-text state)))
    (is (string= (format nil "State:~%~A" expected)
                 (cadr-ai::llama-render-state state)))
    (is (search expected content))
    (is (null (search "1.5e0" content)))
    (is (null (search "0.1e0" content)))))

(test classifier-apis-llama-shares-prompt-prefix
  (let* ((context (apis-llama-context))
         (prefix
           (lambda (id)
             (let* ((content
                      (cadr-ai::llama-labeled-question-content
                       (cadr-ai::llama-render-question context id)))
                    (at (search "Question:" content :from-end t)))
               (subseq content 0 at)))))
    (is (string= (funcall prefix "urgent") (funcall prefix "team")))
    (is (string= (funcall prefix "severity") (funcall prefix "team")))
    (is (string-suffix-p
         (format nil "No means: No time pressure~%~%Answer Yes or No.")
         (cadr-ai::llama-labeled-question-content
          (cadr-ai::llama-render-question context "urgent"))))
    (is (string-suffix-p
         (format nil "2. high~%~%Answer with one level number.")
         (cadr-ai::llama-labeled-question-content
          (cadr-ai::llama-render-question context "severity"))))))

(test classifier-apis-llama-divides-logprobs-by-temperature
  (multiple-value-bind (http calls)
      (apis-llama-server)
    (let* ((*http-request-function* http)
           (result
             (cadr-ai:classify-model
              (apis-llama-model)
              (cadr-ai:make-classifier-context
               :state (cadr-ai::json-object)
               :questions
               (cadr-ai::json-object
                "pick"
                (cadr-ai::json-object
                 "type" "choice"
                 "instructions" "Pick one"
                 "criteria" (cadr-ai::json-object "a" "" "b" ""))))
              :temperature 2))
           (probabilities
             (cadr-ai::json-get
              (cadr-ai::json-get
               (cadr-ai:classifier-result-answers result) "pick")
              "probabilities")))
      (is (plusp (length (funcall calls))))
      (is (apis-close 0.7685247834990175d0
                      (cadr-ai::json-get probabilities "a")))
      (is (apis-close 0.23147521650098232d0
                      (cadr-ai::json-get probabilities "b")))
      (is (not (apis-header
                (getf (first (funcall calls)) :headers)
                "authorization"))))))

(test classifier-apis-llama-rejects-non-positive-temperature
  (multiple-value-bind (http calls)
      (apis-llama-server)
    (let* ((*http-request-function* http)
           (result
             (cadr-ai:classify-model
              (apis-llama-model)
              (apis-llama-context)
              :temperature 0)))
      (is (eq :error (cadr-ai:classifier-result-stop-reason result)))
      (is (search "Temperature must be a positive number, got 0"
                  (cadr-ai:classifier-result-error-message result)))
      (is (null (funcall calls))))))

(test classifier-apis-llama-deepens-readout
  (multiple-value-bind (http calls)
      (apis-llama-server
       :next (lambda (prompt depth)
               (declare (ignore prompt))
               (if (< depth 4096)
                   '(("A" . -0.1d0))
                   '(("A" . -0.1d0) ("B" . -9d0)))))
    (let* ((*http-request-function* http)
           (recovered
             (cadr-ai:classify-model
              (apis-llama-model) (apis-pick-context))))
      (is (eq :stop (cadr-ai:classifier-result-stop-reason recovered)))
      (is (equal '(256 4096) (apis-completion-depths (funcall calls))))))
  (multiple-value-bind (http calls)
      (apis-llama-server
       :next (lambda (prompt depth)
               (declare (ignore prompt depth))
               '(("A" . -0.1d0))))
    (let* ((*http-request-function* http)
           (failed
             (cadr-ai:classify-model
              (apis-llama-model) (apis-pick-context))))
      (is (eq :error (cadr-ai:classifier-result-stop-reason failed)))
      (is (= 0 (hash-table-count
                (cadr-ai:classifier-result-answers failed))))
      (is (search "did not rank labels B for pick within the top 32768 tokens"
                  (cadr-ai:classifier-result-error-message failed)))
      (is (equal '(256 4096 32768)
                 (apis-completion-depths (funcall calls)))))))

(test classifier-apis-llama-closes-open-think-block
  (multiple-value-bind (http calls)
      (apis-llama-server
       :template (lambda (messages)
                   (declare (ignore messages))
                   (format nil "<|assistant|>~%<think>")))
    (let ((*http-request-function* http))
      (cadr-ai:classify-model (apis-llama-model) (apis-pick-context))
      (let ((completion
              (find-if (lambda (call)
                         (string= (apis-url-path (getf call :url))
                                  "/completion"))
                       (funcall calls))))
        (is (string= (format nil "<|assistant|>~%<think></think>")
                     (cadr-ai::json-get (getf completion :body)
                                        "prompt")))))))

(test classifier-apis-llama-label-must-be-one-token
  (multiple-value-bind (http calls)
      (apis-llama-server
       :tokenize (lambda (content)
                   (if (and (plusp (length content))
                            (char= (char content 0) #\Newline)
                            (> (length content) 1))
                       '(1000)
                       (apis-char-tokens content))))
    (declare (ignore calls))
    (let* ((*http-request-function* http)
           (merged
             (cadr-ai:classify-model
              (apis-llama-model) (apis-pick-context))))
      (is (eq :stop (cadr-ai:classifier-result-stop-reason merged)))))
  (multiple-value-bind (http calls)
      (apis-llama-server)
    (declare (ignore calls))
    (let* ((*http-request-function* http)
           (result
             (cadr-ai:classify-model
              (apis-llama-model)
              (cadr-ai:make-classifier-context
               :state (cadr-ai::json-object)
               :questions
               (cadr-ai::json-object
                "ok"
                (cadr-ai::json-object
                 "type" "bool"
                 "instructions" "OK?"
                 "criteria" (cadr-ai::json-object
                             "true" ""
                             "false" "")))))))
      (is (eq :error (cadr-ai:classifier-result-stop-reason result)))
      (is (search "Label \"Yes\" is not a single token for qwen"
                  (cadr-ai:classifier-result-error-message result))))))

(test classifier-apis-llama-caches-label-tokens
  (multiple-value-bind (http calls)
      (apis-llama-server)
    (let* ((*http-request-function* http)
           (model (apis-llama-model))
           (context (apis-pick-context)))
      (cadr-ai:classify-model model context)
      (let ((first
              (count-if (lambda (call)
                          (string= (apis-url-path (getf call :url))
                                   "/tokenize"))
                        (funcall calls))))
        (cadr-ai:classify-model model context)
        (is (plusp first))
        (is (= first
               (count-if (lambda (call)
                           (string= (apis-url-path (getf call :url))
                                    "/tokenize"))
                         (funcall calls))))))))

(test classifier-apis-llama-validates-option-counts
  (multiple-value-bind (http calls)
      (apis-llama-server)
    (let* ((*http-request-function* http)
           (criteria (cadr-ai::json-object)))
      (loop for index below 63
            do (setf (gethash (format nil "option~A" index) criteria) ""))
      (let ((too-many
              (cadr-ai:classify-model
               (apis-llama-model)
               (cadr-ai:make-classifier-context
                :state (cadr-ai::json-object)
                :questions
                (cadr-ai::json-object
                 "pick"
                 (cadr-ai::json-object
                  "type" "choice"
                  "instructions" "Pick"
                  "criteria" criteria)))))
            (too-few
              (cadr-ai:classify-model
               (apis-llama-model)
               (cadr-ai:make-classifier-context
                :state (cadr-ai::json-object)
                :questions
                (cadr-ai::json-object
                 "rate"
                 (cadr-ai::json-object
                  "type" "score"
                  "instructions" "Rate"
                  "criteria" (cadr-ai::json-array "only")))))))
        (is (search "A choice question needs 2 to 62 options, got 63"
                    (cadr-ai:classifier-result-error-message too-many)))
        (is (search "A score question needs 2 to 10 levels, got 1"
                    (cadr-ai:classifier-result-error-message too-few)))
        (is (null (funcall calls)))))))

(test classifier-apis-llama-hooks-only-completion
  (multiple-value-bind (http calls)
      (apis-llama-server)
    (let* ((payloads nil)
           (statuses nil)
           (*http-request-function* http))
      (cadr-ai:classify-model
       (apis-llama-model)
       (apis-pick-context)
       :on-payload
       (lambda (payload model)
         (declare (ignore model))
         (push payload payloads)
         (let ((copy (cadr-ai::copy-json-object payload)))
           (setf (gethash "id_slot" copy) 1)
           copy))
       :on-response
       (lambda (response model)
         (declare (ignore model))
         (push (getf response :status) statuses)))
      (let ((completion
              (find-if (lambda (call)
                         (string= (apis-url-path (getf call :url))
                                  "/completion"))
                       (funcall calls))))
        (is (= 1 (length payloads)))
        (is (= 1 (cadr-ai::json-get (first payloads) "n_predict")))
        (is (equal '(200) statuses))
        (is (= 1 (cadr-ai::json-get (getf completion :body) "id_slot")))))))

(test classifier-apis-llama-server-error-and-abort
  (let* ((*http-request-function*
           (lambda (url &key &allow-other-keys)
             (declare (ignore url))
             (values "{\"error\":{\"message\":\"context overflow\"}}"
                     400 nil)))
         (failing
           (cadr-ai:classify-model
            (apis-llama-model)
            (apis-llama-context)
            :max-retries 0)))
    (is (eq :error (cadr-ai:classifier-result-stop-reason failing)))
    (is (search "llama.cpp error (400)"
                (cadr-ai:classifier-result-error-message failing)))
    (is (search "context overflow"
                (cadr-ai:classifier-result-error-message failing))))
  (let* ((*http-request-function*
           (lambda (url &key &allow-other-keys)
             (declare (ignore url))
             (error 'cadr-ai:request-aborted :message "Request aborted")))
         (aborted
           (cadr-ai:classify-model
            (apis-llama-model)
            (apis-llama-context)
            :abort-p (constantly t))))
    (is (eq :aborted (cadr-ai:classifier-result-stop-reason aborted)))
    (is (string= "Request aborted"
                 (cadr-ai:classifier-result-error-message aborted)))))

(test classifier-apis-llama-rejects-other-api-and-images
  (multiple-value-bind (http calls)
      (apis-llama-server)
    (let* ((*http-request-function* http)
           (other
             (cadr-ai::classify-llama-cpp
              (apis-llama-model :api :typesafe-system-one)
              (apis-llama-context)))
           (images
             (cadr-ai:classify-model
              (apis-llama-model)
              (cadr-ai:make-classifier-context
               :state (cadr-ai::json-object "message" "x")
               :questions (cadr-ai:classifier-context-questions
                           (apis-llama-context))
               :images (list (classifier-image "aW1hZ2U=" "image/png"))))))
      (is (search "Unsupported classifier API: typesafe-system-one"
                  (cadr-ai:classifier-result-error-message other)))
      (is (search "llama.cpp classification does not support image input"
                  (cadr-ai:classifier-result-error-message images)))
      (is (null (funcall calls))))))

(test classifier-apis-llama-server-root
  (is (string= "http://127.0.0.1:8080"
               (cadr-ai::llama-server-root "http://127.0.0.1:8080/v1/")))
  (is (string= "https://example.com/prefix"
               (cadr-ai::llama-server-root "https://example.com/prefix/v1")))
  (is (string= "http://127.0.0.1:8080"
               (cadr-ai::llama-server-root "http://127.0.0.1:8080"))))

(test classifier-apis-llama-confidence-and-underflow
  (is (apis-close 0.835d0
                  (cadr-ai::llama-peak-confidence '(0.89d0 0.06d0 0.05d0))))
  (is (apis-close 0d0 (cadr-ai::llama-peak-confidence '(0.5d0 0.5d0))))
  (is (apis-close 1d0 (cadr-ai::llama-peak-confidence '(1d0 0d0 0d0))))
  (let ((answer
          (cadr-ai::llama-answer-from-probabilities
           (cadr-ai::json-object
            "type" "score"
            "instructions" ""
            "criteria" (cadr-ai::json-array "a" "b" "c"))
           '("0" "1" "2")
           '(0.2d0 0.3d0 0.5d0))))
    (is (apis-close 1.3d0 (cadr-ai::json-get answer "score")))
    (is (apis-close 0.25d0 (cadr-ai::json-get answer "confidence"))))
  (multiple-value-bind (http calls)
      (apis-llama-server
       :next (lambda (prompt depth)
               (declare (ignore prompt depth))
               '(("A" . -1.0d30) ("B" . -1.0d30))))
    (declare (ignore calls))
    (let* ((*http-request-function* http)
           (result
             (cadr-ai:classify-model
              (apis-llama-model) (apis-pick-context))))
      (is (eq :error (cadr-ai:classifier-result-stop-reason result)))
      (is (search "gave no probability to any answer label for pick"
                  (cadr-ai:classifier-result-error-message result))))))

(defun string-suffix-p (suffix text)
  (let ((start (- (length text) (length suffix))))
    (and (>= start 0)
         (string= text suffix :start1 start))))
