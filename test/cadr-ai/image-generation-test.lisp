(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(test openrouter-image-catalog-is-exact
  (let ((models (cadr-ai:list-image-models :openrouter)))
    (is (= 43 (length models)))
    (is (every
         (lambda (model)
           (and
            (eq :openrouter-images
                (cadr-ai:image-model-api model))
            (eq :openrouter
                (cadr-ai:image-model-provider model))))
         models))
    (let ((gemini
            (cadr-ai:find-image-model
             :openrouter
             "google/gemini-3.1-flash-image-preview")))
      (is (member :text
                  (cadr-ai:image-model-output gemini)))
      (is (member :image
                  (cadr-ai:image-model-output gemini))))))

(test openrouter-image-request-and-response-match-baseline
  (let* ((model
           (cadr-ai:find-image-model
            :openrouter
            "google/gemini-3.1-flash-image-preview"))
         (context
           (cadr-ai:make-images-context
            :input
            (list
             (cadr-ai:make-text-content
              :text "Generate a dog")
             (cadr-ai:make-image-content
              :mime-type "image/png"
              :data "aW1hZ2U="))))
         (response
           (cadr-ai::json-object
            "id" "img-1"
            "usage"
            (cadr-ai::json-object
             "prompt_tokens" 12
             "completion_tokens" 34
             "prompt_tokens_details"
             (cadr-ai::json-object "cached_tokens" 0))
            "choices"
            (vector
             (cadr-ai::json-object
              "message"
              (cadr-ai::json-object
               "content" "Here is your image."
               "images"
               (vector
                (cadr-ai::json-object
                 "image_url"
                 "data:image/png;base64,ZmFrZS1wbmc=")))))))
         (captured nil)
         (cadr-ai:*http-request-function*
           (lambda (url &key method headers content
                          connect-timeout read-timeout
                          want-stream force-string force-binary)
             (declare
              (ignore connect-timeout read-timeout
                      want-stream force-string force-binary))
             (setf captured
                   (list url method headers
                         (cadr-ai::parse-json content)))
             (values (cadr-ai::stringify-json response)
                     200
                     '(("x-request-id" . "fixture"))))))
    (let ((result
            (cadr-ai:generate-images
             model context :api-key "test")))
      (is (eq :stop
              (cadr-ai:assistant-images-stop-reason result)))
      (is (string=
           "img-1"
           (cadr-ai:assistant-images-response-id result)))
      (is (= 2
             (length
              (cadr-ai:assistant-images-output result))))
      (is (typep
           (first (cadr-ai:assistant-images-output result))
           'cadr-ai:text-content))
      (is (typep
           (second (cadr-ai:assistant-images-output result))
           'cadr-ai:image-content))
      (is (string=
           "https://openrouter.ai/api/v1/chat/completions"
           (first captured)))
      (let* ((payload (fourth captured))
             (modalities
               (cadr-ai::json-get payload "modalities"))
             (message
               (aref (cadr-ai::json-get payload "messages") 0))
             (content
               (cadr-ai::json-get message "content")))
        (is (equalp #("image" "text") modalities))
        (is (string=
             "Generate a dog"
             (cadr-ai::json-get (aref content 0) "text")))
        (is (string=
             "data:image/png;base64,aW1hZ2U="
             (cadr-ai::json-get
              (cadr-ai::json-get
               (aref content 1) "image_url")
              "url")))))))

(test openrouter-image-errors-are-results
  (let ((model
          (cadr-ai:find-image-model
           :openrouter "black-forest-labs/flux.2-pro"))
        (context
          (cadr-ai:make-images-context
           :input
           (list
            (cadr-ai:make-text-content :text "Generate a dog")))))
    (let ((missing
            (cadr-ai:generate-images model context)))
      (is (eq :error
              (cadr-ai:assistant-images-stop-reason missing)))
      (is (search
           "No API key"
           (cadr-ai:assistant-images-error-message missing))))
    (let ((aborted
            (cadr-ai:generate-images
             model context
             :api-key "test"
             :abort-p (constantly t))))
      (is (eq :aborted
              (cadr-ai:assistant-images-stop-reason aborted))))))
