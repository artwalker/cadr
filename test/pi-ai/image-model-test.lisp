(in-package #:pi-ai/tests)
(in-suite pi-ai-suite)

(defun image-context ()
  (pi-ai:make-context
   :messages
   (list
    (pi-ai:make-user-message
     :content
     (list
      (pi-ai:make-text-content :text "Describe")
      (pi-ai:make-image-content
       :mime-type "image/png"
       :data "iVBORw0KGgo="))))))

(test each-wire-protocol-encodes-image-content
  (flet ((image-model (provider api base-url)
           (pi-ai:make-model
            :id "vision-test"
            :provider provider
            :api api
            :base-url base-url
            :supports-images-p t)))
    (let* ((request
             (pi-ai:build-request
              (pi-ai:make-anthropic-provider :api-key "key")
              (image-model :anthropic :anthropic-messages
                           "https://api.anthropic.com")
              (image-context) :stream-p nil))
           (message
             (aref (pi-ai::json-get
                    (pi-ai:request-spec-payload request) "messages")
                   0))
           (source
             (pi-ai::json-get
              (aref (pi-ai::json-get message "content") 1)
              "source")))
      (is (string= "base64" (pi-ai::json-get source "type")))
      (is (string= "iVBORw0KGgo=" (pi-ai::json-get source "data"))))
    (let* ((request
             (pi-ai:build-request
              (pi-ai:make-openai-provider :api-key "key")
              (image-model :openai :openai-responses
                           "https://api.openai.com")
              (image-context) :stream-p nil))
           (item
             (aref (pi-ai::json-get
                    (pi-ai:request-spec-payload request) "input")
                   0))
           (image (aref (pi-ai::json-get item "content") 1)))
      (is (string=
           "data:image/png;base64,iVBORw0KGgo="
           (pi-ai::json-get image "image_url"))))
    (let* ((request
             (pi-ai:build-request
              (pi-ai:make-openai-completions-provider :api-key "key")
              (image-model :deepseek :openai-completions
                           "https://api.deepseek.com")
              (image-context) :stream-p nil))
           (message
             (aref (pi-ai::json-get
                    (pi-ai:request-spec-payload request) "messages")
                   0))
           (image (aref (pi-ai::json-get message "content") 1)))
      (is (string=
           "data:image/png;base64,iVBORw0KGgo="
           (pi-ai::json-get
            (pi-ai::json-get image "image_url") "url"))))
    (let* ((request
             (pi-ai:build-request
              (pi-ai:make-google-provider :api-key "key")
              (image-model :google :google-generative-ai
                           "https://generativelanguage.googleapis.com/v1beta")
              (image-context) :stream-p nil))
           (content
             (aref (pi-ai::json-get
                    (pi-ai:request-spec-payload request) "contents")
                   0))
           (inline
             (pi-ai::json-get
              (aref (pi-ai::json-get content "parts") 1)
              "inlineData")))
      (is (string= "image/png" (pi-ai::json-get inline "mimeType")))
      (is (string= "iVBORw0KGgo=" (pi-ai::json-get inline "data"))))))

(test unsupported-image-input-fails-before-transport
  (let ((model
          (pi-ai:make-model
           :id "text-only"
           :provider :deepseek
           :api :openai-completions
           :base-url "https://api.deepseek.com"
           :supports-images-p nil)))
    (signals pi-ai:unsupported-content-error
      (pi-ai:build-request
       (pi-ai:make-openai-completions-provider :api-key "key")
       model (image-context) :stream-p nil))))

(test static-model-catalog-calculates-cost
  (let* ((metadata (pi-ai:find-model-metadata :deepseek "deepseek-v4-flash"))
         (usage (pi-ai:make-usage :input 1000000
                                  :output 2000000
                                  :cache-read 500000)))
    (is (= 1000000 (pi-ai:model-metadata-context-window metadata)))
    (pi-ai:calculate-usage-cost usage metadata)
    (is (> (pi-ai:cost-total (pi-ai:usage-cost usage)) 0d0))
    (is (= (pi-ai:cost-total (pi-ai:usage-cost usage))
           (+ (pi-ai:cost-input (pi-ai:usage-cost usage))
              (pi-ai:cost-output (pi-ai:usage-cost usage))
              (pi-ai:cost-cache-read (pi-ai:usage-cost usage))
               (pi-ai:cost-cache-write
                (pi-ai:usage-cost usage)))))))

(test refreshed-catalog-includes-gemini-3.6-and-current-deepseek-default
  (let ((gemini
          (pi-ai:find-model-metadata :google "gemini-3.6-flash"))
        (deepseek
          (pi-ai:find-model-metadata :deepseek
                                     "deepseek-v4-flash")))
    (is (= 1048576
           (pi-ai:model-metadata-context-window gemini)))
    (is (= 384000
           (pi-ai:model-metadata-max-output-tokens deepseek)))
    (is (string=
         "deepseek-v4-flash"
         (pi-ai:provider-definition-default-model
          (pi-ai:find-provider-definition :deepseek))))))
