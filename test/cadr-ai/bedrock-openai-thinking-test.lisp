(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(defun bedrock-openai-request-fields (id name reasoning &key thinking-map)
  (let* ((provider (cadr-ai:make-bedrock-provider :api-key "bearer"))
         (model
           (cadr-ai:make-model
            :id id
            :name name
            :provider :amazon-bedrock
            :api :bedrock-converse-stream
            :base-url "https://bedrock.example"
            :reasoning-p t
            :thinking-level-map thinking-map))
         (request
           (cadr-ai:build-request
            provider model
            (cadr-ai:make-context
             :messages
             (list (cadr-ai:make-user-message :content "hello")))
            :reasoning reasoning)))
    (cadr-ai::json-get
     (cadr-ai:request-spec-payload request)
     "additionalModelRequestFields")))

(test bedrock-openai-thinking-level-reaches-the-request
  ;; pi@71023aec1 bedrock-converse-stream.ts #9331.
  (dolist (pair '((:minimal . "low")
                  (:low . "low")
                  (:medium . "medium")
                  (:high . "high")
                  (:xhigh . "xhigh")
                  (:max . "max")))
    (dolist (id '("global.openai.gpt-6-sol"
                  "us.openai.gpt-6-luna"
                  "global.openai.gpt-5.6-sol"))
      (let ((fields
              (bedrock-openai-request-fields
               id "GPT" (car pair))))
        (is (string=
             (cdr pair)
             (cadr-ai::json-get
              (cadr-ai::json-get fields "reasoning")
              "effort"))))))
  (let ((fields
          (bedrock-openai-request-fields
           "arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/my-profile"
           "GPT-6 Sol"
           :medium)))
    (is (string=
         "medium"
         (cadr-ai::json-get
          (cadr-ai::json-get fields "reasoning")
          "effort"))))
  (let ((fields
          (bedrock-openai-request-fields
           "global.openai.gpt-6-sol"
           "GPT-6 Sol"
           :medium
           :thinking-map '((:medium . "low")))))
    (is (string=
         "low"
         (cadr-ai::json-get
          (cadr-ai::json-get fields "reasoning")
          "effort"))))
  (dolist (pair '((:minimal . "low")
                  (:medium . "medium")
                  (:xhigh . "high")
                  (:max . "high")))
    (let ((fields
            (bedrock-openai-request-fields
             "openai.gpt-oss-120b-1:0"
             "gpt-oss"
             (car pair))))
      (is (string= (cdr pair)
                   (cadr-ai::json-get fields "reasoning_effort")))
      (is (null (cadr-ai::json-get fields "reasoning")))))
  (is (null
       (bedrock-openai-request-fields
        "global.openai.gpt-6-sol" "GPT-6 Sol" :off)))
  (is (null
       (bedrock-openai-request-fields
        "global.openai.gpt-6-sol" "GPT-6 Sol" nil))))
