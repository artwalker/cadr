(in-package #:cadr-ai)

(defun image-output-modalities (model)
  (if (member :text (image-model-output model))
      #("image" "text")
      #("image")))

(defun openrouter-image-content (content)
  (cond
    ((typep content 'text-content)
     (json-object
      "type" "text"
      "text" (text-content-text content)))
    ((typep content 'image-content)
     (json-object
      "type" "image_url"
      "image_url"
      (json-object "url" (data-url content))))
    (t
     (error 'unsupported-content-error
            :message
            (format nil
                    "Unsupported image-generation input: ~S"
                    content)))))

(defun build-openrouter-image-request (model context api-key headers)
  (unless (non-empty-string-p api-key)
    (error 'authentication-error
           :message
           (format nil "No API key for provider: ~A"
                   (image-model-provider model))))
  (make-request-spec
   :url
   (format nil "~A/chat/completions"
           (strip-trailing-slash
            (image-model-base-url model)))
   :headers
   (append
    `(("content-type" . "application/json")
      ("accept" . "application/json")
      ("authorization" . ,(format nil "Bearer ~A" api-key)))
    headers
    (image-model-headers model))
   :payload
   (json-object
    "model" (image-model-id model)
    "messages"
    (vector
     (json-object
      "role" "user"
      "content"
      (list-json-array
       (mapcar
        #'openrouter-image-content
        (images-context-input context)))))
    "stream" nil
    "modalities" (image-output-modalities model))
   :provider :openrouter))

(defun parse-data-image (value)
  (let* ((prefix "data:")
         (marker ";base64,")
         (marker-position
           (and (stringp value)
                (uiop:string-prefix-p prefix value)
                (search marker value))))
    (when marker-position
      (make-image-content
       :mime-type
       (subseq value
               (length prefix)
               marker-position)
       :data
       (subseq value
               (+ marker-position (length marker)))))))

(defun openrouter-image-usage (raw model)
  (let* ((prompt (or (json-get raw "prompt_tokens") 0))
         (output (or (json-get raw "completion_tokens") 0))
         (details (json-get raw "prompt_tokens_details"))
         (reported-cached
           (or (json-get details "cached_tokens") 0))
         (cache-write
           (or (json-get details "cache_write_tokens") 0))
         (cache-read
           (if (plusp cache-write)
               (max 0 (- reported-cached cache-write))
               reported-cached))
         (input (max 0 (- prompt cache-read cache-write)))
         (usage
           (make-usage
            :input input
            :output output
            :cache-read cache-read
            :cache-write cache-write)))
    (setf
     (usage-cost usage)
     (let* ((input-cost
              (* (/ input 1000000d0)
                 (image-model-input-price model)))
            (output-cost
              (* (/ output 1000000d0)
                 (image-model-output-price model)))
            (cache-read-cost
              (* (/ cache-read 1000000d0)
                 (image-model-cache-read-price model)))
            (cache-write-cost
              (* (/ cache-write 1000000d0)
                 (image-model-cache-write-price model))))
       (make-cost
        :input input-cost
        :output output-cost
        :cache-read cache-read-cost
        :cache-write cache-write-cost
        :total
        (+ input-cost output-cost
           cache-read-cost cache-write-cost))))
    usage))

(defun parse-openrouter-images (model response)
  (let ((result
          (make-assistant-images
           :api (image-model-api model)
           :provider (image-model-provider model)
           :model (image-model-id model)
           :response-id (json-get response "id"))))
    (let ((raw-usage (json-get response "usage")))
      (when raw-usage
        (setf
         (assistant-images-usage result)
         (openrouter-image-usage raw-usage model))))
    (let* ((choices (json-get response "choices"))
           (choice
             (and (vectorp choices)
                  (plusp (length choices))
                  (aref choices 0)))
           (message (and choice (json-get choice "message")))
           (text (and message (json-get message "content")))
           (images (and message (json-get message "images"))))
      (when (non-empty-string-p text)
        (setf
         (assistant-images-output result)
         (append
          (assistant-images-output result)
          (list (make-text-content :text text)))))
      (when (vectorp images)
        (loop for image across images
              for raw = (json-get image "image_url")
              for url =
              (if (stringp raw)
                  raw
                  (json-get raw "url"))
              for parsed = (parse-data-image url)
              when parsed
                do
                (setf
                 (assistant-images-output result)
                 (append
                  (assistant-images-output result)
                  (list parsed))))))
    result))

(defun image-error-result (model condition abort-p)
  (make-assistant-images
   :api (image-model-api model)
   :provider (image-model-provider model)
   :model (image-model-id model)
   :stop-reason
   (if (or (and abort-p (funcall abort-p))
           (typep condition 'request-aborted))
       :aborted
       :error)
   :error-message
   (if (typep condition 'cadr-error)
       (cadr-error-message condition)
       (princ-to-string condition))))

(defun generate-images
    (model context
     &key api-key headers abort-p
       on-payload on-response
       (max-retries *max-provider-retries*)
       max-retry-delay-ms)
  (let ((*max-provider-retries* max-retries))
    (handler-case
        (progn
          (check-abort abort-p)
          (let ((request
                  (build-openrouter-image-request
                   model context api-key headers)))
            (when on-payload
              (let ((replacement
                      (funcall
                       on-payload
                       (request-spec-payload request)
                       model)))
                (when replacement
                  (setf
                   (request-spec-payload request)
                   replacement))))
            (multiple-value-bind (response status response-headers)
                (call-with-provider-retries
                 (lambda ()
                   (check-abort abort-p)
                   (request-json request :abort-p abort-p))
                 :retry-allowed-p
                 (lambda (condition)
                   (let ((delay
                           (retry-after-seconds condition)))
                     (or
                      (null max-retry-delay-ms)
                      (zerop max-retry-delay-ms)
                      (null delay)
                      (<= (* 1000 delay)
                          max-retry-delay-ms)))))
              (check-abort abort-p)
              (when on-response
                (funcall on-response
                         status response-headers model))
              (parse-openrouter-images model response))))
      (error (condition)
        (image-error-result model condition abort-p)))))
