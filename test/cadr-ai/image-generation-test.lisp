(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

;;; pi@4a080252f IMAGE_MODELS via flattenImageModelCatalog on the
;;; pi-ai 1.4.0 provider-data snapshot. Ids are the openrouter-images
;;; group of test/fixtures/catalogs/provider-data/openrouter.json.
(defparameter *v140-openrouter-image-ids*
  '("black-forest-labs/flux-3-image"
    "black-forest-labs/flux-3-image-klein"
    "black-forest-labs/flux.2-flex"
    "black-forest-labs/flux.2-klein-4b"
    "black-forest-labs/flux.2-max"
    "black-forest-labs/flux.2-pro"
    "bytedance-seed/seedream-4.5"
    "bytedance-seed/seedream-5-0-flash"
    "bytedance-seed/seedream-5-0-lite"
    "bytedance-seed/seedream-5-0-pro"
    "google/gemini-2.5-flash-image"
    "google/gemini-3-pro-image"
    "google/gemini-3-pro-image-preview"
    "google/gemini-3.1-flash-image"
    "google/gemini-3.1-flash-image-preview"
    "google/gemini-3.1-flash-lite-image"
    "google/gemini-nano-banana-2.1"
    "krea/k3-edit"
    "krea/krea-2-large"
    "krea/krea-2-medium"
    "krea/krea-2-medium-turbo"
    "meta/muse-image"
    "microsoft/mai-image-2.5"
    "microsoft/mai-image-2.5-pro"
    "microsoft/mai-image-2.6"
    "microsoft/mai-image-2.6-flash"
    "openai/gpt-5-image"
    "openai/gpt-5-image-mini"
    "openai/gpt-5.4-image-2"
    "openai/gpt-image-1"
    "openai/gpt-image-1-mini"
    "openai/gpt-image-2"
    "openai/gpt-image-2.5-flare"
    "openai/gpt-image-2.5-sunburst"
    "openrouter/auto"
    "openrouter/auto-beta"
    "qwen/qwen-image-2.1-pro"
    "qwen/qwen-image-2.1-turbo"
    "qwen/qwen-image-3"
    "qwen/qwen-image-3-pro"
    "recraft/recraft-v3"
    "recraft/recraft-v4"
    "recraft/recraft-v4-pro"
    "recraft/recraft-v4-pro-vector"
    "recraft/recraft-v4-styles"
    "recraft/recraft-v4-styles-pro"
    "recraft/recraft-v4-styles-pro-vector"
    "recraft/recraft-v4-styles-vector"
    "recraft/recraft-v4-vector"
    "recraft/recraft-v4.1"
    "recraft/recraft-v4.1-flash"
    "recraft/recraft-v4.1-pro"
    "recraft/recraft-v4.1-pro-vector"
    "recraft/recraft-v4.1-utility"
    "recraft/recraft-v4.1-utility-pro"
    "recraft/recraft-v4.1-vector"
    "sourceful/riverflow-v2-fast"
    "sourceful/riverflow-v2-pro"
    "sourceful/riverflow-v2.5-fast"
    "sourceful/riverflow-v2.5-pro"
    "tencent/hy-image-v3.5-preview"
    "x-ai/grok-imagine-image-2.0"
    "x-ai/grok-imagine-image-quality"))

(test openrouter-image-catalog-is-exact
  (let ((models (cadr-ai:list-image-models :openrouter))
        (all (cadr-ai:list-image-models)))
    (is (= 63 (length models)))
    (is (equal (mapcar #'cadr-ai:image-model-id models)
               *v140-openrouter-image-ids*))
    (is (equal (mapcar #'cadr-ai:image-model-id all)
               *v140-openrouter-image-ids*))
    (is (null (cadr-ai:list-image-models :google)))
    (is (every
         (lambda (model)
           (and
            (eq :openrouter-images
                (cadr-ai:image-model-api model))
            (eq :openrouter
                (cadr-ai:image-model-provider model))
            (string=
             "https://openrouter.ai/api/v1"
             (cadr-ai:image-model-base-url model))
            (null (cadr-ai:image-model-headers model))))
         models))
    (let ((flux
            (cadr-ai:find-image-model
             :openrouter "black-forest-labs/flux-3-image")))
      (is (string=
           "Black Forest Labs: FLUX 3 Image"
           (cadr-ai:image-model-name flux)))
      (is (equal '(:text :image)
                 (cadr-ai:image-model-input flux)))
      (is (equal '(:image)
                 (cadr-ai:image-model-output flux)))
      (is (= 0d0 (cadr-ai:image-model-input-price flux)))
      (is (equal
           '(:images
             (:resize
              (:jpeg-quality 80 :max-bytes 4718592
               :max-height 2000 :max-width 2000)))
           (cadr-ai:image-model-input-limits flux))))
    (let ((gemini
            (cadr-ai:find-image-model
             :openrouter "google/gemini-2.5-flash-image")))
      (is (equal '(:image :text)
                 (cadr-ai:image-model-input gemini)))
      (is (equal '(:image :text)
                 (cadr-ai:image-model-output gemini)))
      (is (= 0.3d0 (cadr-ai:image-model-input-price gemini)))
      (is (= 2.5d0 (cadr-ai:image-model-output-price gemini)))
      (is (= 0.03d0
             (cadr-ai:image-model-cache-read-price gemini)))
      (is (= 0.083333d0
             (cadr-ai:image-model-cache-write-price gemini))))
    (let ((preview
            (cadr-ai:find-image-model
             :openrouter
             "google/gemini-3.1-flash-image-preview")))
      (is (member :text (cadr-ai:image-model-output preview)))
      (is (member :image (cadr-ai:image-model-output preview))))
    (let ((flash
            (cadr-ai:find-image-model
             :openrouter "recraft/recraft-v4.1-flash")))
      (is (equal '(:text) (cadr-ai:image-model-input flash)))
      (is (equal '(:image) (cadr-ai:image-model-output flash)))
      (is (null (cadr-ai:image-model-input-limits flash))))
    (let ((auto
            (cadr-ai:find-image-model
             :openrouter "openrouter/auto")))
      (is (equal '(:text :image)
                 (cadr-ai:image-model-output auto)))
      (is (= 0d0 (cadr-ai:image-model-input-price auto)))
      (is (= 0d0 (cadr-ai:image-model-output-price auto))))
    (let ((chat
            (cadr-ai:find-model-metadata
             :openrouter "google/gemini-3-pro-image"))
          (image
            (cadr-ai:find-image-model
             :openrouter "google/gemini-3-pro-image")))
      (is (typep chat 'cadr-ai:model-metadata))
      (is (equal '(:image :text)
                 (cadr-ai:image-model-output image))))))

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
