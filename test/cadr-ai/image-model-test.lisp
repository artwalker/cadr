(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(defun image-context ()
  (cadr-ai:make-context
   :messages
   (list
    (cadr-ai:make-user-message
     :content
     (list
      (cadr-ai:make-text-content :text "Describe")
      (cadr-ai:make-image-content
       :mime-type "image/png"
       :data "iVBORw0KGgo="))))))

(test each-wire-protocol-encodes-image-content
  (flet ((image-model (provider api base-url)
           (cadr-ai:make-model
            :id "vision-test"
            :provider provider
            :api api
            :base-url base-url
            :supports-images-p t)))
    (let* ((request
             (cadr-ai:build-request
              (cadr-ai:make-anthropic-provider :api-key "key")
              (image-model :anthropic :anthropic-messages
                           "https://api.anthropic.com")
              (image-context) :stream-p nil))
           (message
             (aref (cadr-ai::json-get
                    (cadr-ai:request-spec-payload request) "messages")
                   0))
           (source
             (cadr-ai::json-get
              (aref (cadr-ai::json-get message "content") 1)
              "source")))
      (is (string= "base64" (cadr-ai::json-get source "type")))
      (is (string= "iVBORw0KGgo=" (cadr-ai::json-get source "data"))))
    (let* ((request
             (cadr-ai:build-request
              (cadr-ai:make-openai-provider :api-key "key")
              (image-model :openai :openai-responses
                           "https://api.openai.com")
              (image-context) :stream-p nil))
           (item
             (aref (cadr-ai::json-get
                    (cadr-ai:request-spec-payload request) "input")
                   0))
           (image (aref (cadr-ai::json-get item "content") 1)))
      (is (string=
           "data:image/png;base64,iVBORw0KGgo="
           (cadr-ai::json-get image "image_url"))))
    (let* ((request
             (cadr-ai:build-request
              (cadr-ai:make-openai-completions-provider :api-key "key")
              (image-model :deepseek :openai-completions
                           "https://api.deepseek.com")
              (image-context) :stream-p nil))
           (message
             (aref (cadr-ai::json-get
                    (cadr-ai:request-spec-payload request) "messages")
                   0))
           (image (aref (cadr-ai::json-get message "content") 1)))
      (is (string=
           "data:image/png;base64,iVBORw0KGgo="
           (cadr-ai::json-get
            (cadr-ai::json-get image "image_url") "url"))))
    (let* ((request
             (cadr-ai:build-request
              (cadr-ai:make-google-provider :api-key "key")
              (image-model :google :google-generative-ai
                           "https://generativelanguage.googleapis.com/v1beta")
              (image-context) :stream-p nil))
           (content
             (aref (cadr-ai::json-get
                    (cadr-ai:request-spec-payload request) "contents")
                   0))
           (inline
             (cadr-ai::json-get
              (aref (cadr-ai::json-get content "parts") 1)
              "inlineData")))
      (is (string= "image/png" (cadr-ai::json-get inline "mimeType")))
      (is (string= "iVBORw0KGgo=" (cadr-ai::json-get inline "data"))))))

(test unsupported-image-input-fails-before-transport
  (let ((model
          (cadr-ai:make-model
           :id "text-only"
           :provider :deepseek
           :api :openai-completions
           :base-url "https://api.deepseek.com"
           :supports-images-p nil)))
    (signals cadr-ai:unsupported-content-error
      (cadr-ai:build-request
       (cadr-ai:make-openai-completions-provider :api-key "key")
       model (image-context) :stream-p nil))))

(test static-model-catalog-calculates-cost
  (let* ((metadata (cadr-ai:find-model-metadata :deepseek "deepseek-v4-flash"))
         (usage (cadr-ai:make-usage :input 1000000
                                  :output 2000000
                                  :cache-read 500000)))
    (is (= 1000000 (cadr-ai:model-metadata-context-window metadata)))
    (cadr-ai:calculate-usage-cost usage metadata)
    (is (> (cadr-ai:cost-total (cadr-ai:usage-cost usage)) 0d0))
    (is (= (cadr-ai:cost-total (cadr-ai:usage-cost usage))
           (+ (cadr-ai:cost-input (cadr-ai:usage-cost usage))
              (cadr-ai:cost-output (cadr-ai:usage-cost usage))
              (cadr-ai:cost-cache-read (cadr-ai:usage-cost usage))
               (cadr-ai:cost-cache-write
                (cadr-ai:usage-cost usage)))))))

(test refreshed-catalog-includes-gemini-3.6-and-current-deepseek-default
  (let ((gemini
          (cadr-ai:find-model-metadata :google "gemini-3.6-flash"))
        (deepseek
          (cadr-ai:find-model-metadata :deepseek
                                     "deepseek-v4-pro")))
    (is (= 1048576
           (cadr-ai:model-metadata-context-window gemini)))
    (is (= 384000
           (cadr-ai:model-metadata-max-output-tokens deepseek)))
    (is (string=
         "deepseek-v4-pro"
         (cadr-ai:provider-definition-default-model
          (cadr-ai:find-provider-definition :deepseek))))))

(test catalog-pricing-tiers-apply-to-the-whole-request
  (let* ((metadata
           (cadr-ai:find-model-metadata
            :openai-codex "gpt-5.6-sol"))
         (short
           (cadr-ai:make-usage
            :input 200000 :output 100000 :cache-read 72000))
         (long
           (cadr-ai:make-usage
            :input 200000 :output 100000
            :cache-read 72000 :cache-write 1)))
    (cadr-ai:calculate-usage-cost short metadata)
    (cadr-ai:calculate-usage-cost long metadata)
    (is (= 1d0
           (cadr-ai:cost-input (cadr-ai:usage-cost short))))
    (is (= 3d0
           (cadr-ai:cost-output (cadr-ai:usage-cost short))))
    (is (= 2d0
           (cadr-ai:cost-input (cadr-ai:usage-cost long))))
    (is (= 4.5d0
           (cadr-ai:cost-output (cadr-ai:usage-cost long))))
    (is (<
         (abs
          (- 0.0000125d0
             (cadr-ai:cost-cache-write
              (cadr-ai:usage-cost long))))
         1d-16))))

(test catalog-thinking-level-support-is-exact
  (flet ((levels (provider id)
           (cadr-ai:supported-thinking-levels
            (cadr-ai::model-from-metadata
             (cadr-ai:find-model-metadata provider id)))))
    (is (equal '(:off :minimal :low :medium :high :max)
               (levels :anthropic "claude-opus-4-6")))
    (is (equal '(:off :minimal :low :medium :high :xhigh :max)
               (levels :anthropic "claude-opus-4-8")))
    (is (equal '(:medium :high :xhigh)
               (levels :openai "gpt-5.5-pro")))
    (is (equal '(:off :high :max)
               (levels :deepseek "deepseek-v4-flash")))
    (is (equal '(:low :high :max)
               (levels :kimi-coding "k3")))))
