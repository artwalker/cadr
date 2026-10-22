(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(defun classifier-question (type &rest pairs)
  (apply #'cadr-ai::json-object "type" type pairs))

(defun classifier-sample-context (&key images)
  (cadr-ai:make-classifier-context
   :state
   (cadr-ai::json-object
    "message" "Help! My payouts have been failing for 3 days.")
   :questions
   (cadr-ai::json-object
    "is_urgent"
    (classifier-question
     "bool"
     "instructions" "Does this convey urgency?"
     "criteria"
     (cadr-ai::json-object
      "true" "Explicitly time-sensitive"
      "false" "No urgency expressed"))
    "department"
    (classifier-question
     "choice"
     "instructions" "Which team should handle this?"
     "criteria"
     (cadr-ai::json-object
      "billing" "Payments"
      "technical" "Bugs")))
   :images images))

(defun classifier-image (data mime-type)
  (cadr-ai::make-image-content :data data :mime-type mime-type))

(defparameter *clef-output*
  (cadr-ai::json-object
   "model" "clef"
   "answers"
   (cadr-ai::json-object
    "is_urgent"
    (cadr-ai::json-object "type" "noul" "noul" 0.9912d0)
    "department"
    (cadr-ai::json-object
     "type" "choice"
     "choice" "technical"
     "probabilities"
     (cadr-ai::json-object "billing" 0.1632d0 "technical" 0.8368d0)
     "confidence" 0.4538d0))
   "usage"
   (cadr-ai::json-object "input_tokens" 222 "output_tokens" 0)))

(defparameter *jev-output*
  (cadr-ai::json-object
   "model" "jev-1.13.0"
   "answers"
   (cadr-ai::json-object
    "is_urgent" (cadr-ai::json-object "type" "noul" "noul" 0.95d0)
    "department"
    (cadr-ai::json-object
     "type" "choice"
     "choice" "billing"
     "confidence" 0.8d0
     "probabilities"
     (cadr-ai::json-object "billing" 0.87d0 "technical" 0.13d0)))
   "usage"
   (cadr-ai::json-object "input_tokens" 426 "output_tokens" 73)))

(defun cloudflare-envelope (result &key (success t) errors state)
  (cadr-ai::json-object
   "result"
   (if state
       (cadr-ai::json-object "state" state "result" (or result 'null))
       result)
   "success" success
   "errors" (or errors #())
   "messages" #()))

(defun capture-classifier-http (body)
  (let ((calls nil))
    (values
     (lambda (url &key headers content &allow-other-keys)
       (push (list :url url
                   :headers headers
                   :body (cadr-ai::parse-json content))
             calls)
       (values body 200 nil))
     (lambda () (nreverse calls)))))

(defun header-present-p (headers name)
  (assoc name headers :test #'string-equal))

(defun json-same-p (left right)
  (equal (cadr-ai::stringify-json left)
         (cadr-ai::stringify-json right)))

(defun cloudflare-auth-env ()
  '(("CLOUDFLARE_ACCOUNT_ID" . "account-id")))

(test cloudflare-classifier-catalog-prices-and-context
  ;; pi@4a080252f packages/ai/scripts/generate-models.ts CLOUDFLARE_WORKERS_AI_CLASSIFIER_MODELS
  (let ((expected
          '(("@cf/cloudflare/clef" "Clef" 0.24d0 65536 :images)
            ("@cf/cloudflare/clef-flash" "Clef Flash" 0.038d0 24576 :images)
            ("@cf/cloudflare/clef-omni" "Clef Omni" 0.15d0 64000 :images)
            ("typesafe/jev" "Jev" 0.042d0 32000 :assets)
            ("typesafe/jev-1.14.0" "Jev 1.14" 0.042d0 32000 :assets))))
    (dolist (row expected)
      (destructuring-bind (id name price window image-input) row
        (let ((model
                (cadr-ai:find-classifier-model :cloudflare-workers-ai id)))
          (is (typep model 'cadr-ai:classifier-model))
          (is (string= name (cadr-ai:classifier-model-name model)))
          (is (eq :cloudflare-workers-ai-system-one
                  (cadr-ai:classifier-model-api model)))
          (is (equal '(:text :image) (cadr-ai:classifier-model-input model)))
          (is (= price (cadr-ai:classifier-model-input-price model)))
          (is (= 0d0 (cadr-ai:classifier-model-output-price model)))
          (is (= window (cadr-ai:classifier-model-context-window model)))
          (is (equal `((:image-input . ,image-input))
                     (cadr-ai:classifier-model-compat model)))
          (is (string=
               "https://api.cloudflare.com/client/v4/accounts/{CLOUDFLARE_ACCOUNT_ID}/ai"
               (cadr-ai:classifier-model-base-url model))))))
    (dolist (id (mapcar #'first expected))
      (handler-case
          (cadr-ai:find-model-metadata :cloudflare-workers-ai id)
        (cadr-ai:configuration-error ()
          (is (eq t t)))
        (:no-error (&rest ignored)
          (declare (ignore ignored))
          (is (eq t nil)))))))

(test cloudflare-clef-prices-the-direct-run-output
  ;; pi@4a080252f packages/ai/test/cloudflare-workers-ai-system-one.test.ts
  (dolist (row
           '(("@cf/cloudflare/clef" 0.24d0)
             ("@cf/cloudflare/clef-flash" 0.038d0)
             ("@cf/cloudflare/clef-omni" 0.15d0)))
    (destructuring-bind (id price) row
      (multiple-value-bind (http calls)
          (capture-classifier-http
           (cadr-ai::stringify-json
            (cloudflare-envelope *clef-output*)))
        (let* ((*http-request-function* http)
               (result
                 (cadr-ai:classify-model
                  (cadr-ai:find-classifier-model :cloudflare-workers-ai id)
                  (classifier-sample-context)
                  :api-key "cf-key"
                  :environment (cloudflare-auth-env)))
               (call (first (funcall calls)))
               (payload (getf call :body))
               (input (cadr-ai::json-get payload "input"))
               (usage (cadr-ai:classifier-result-usage result))
               (wire-answers
                 (cadr-ai::json-get
                  (cadr-ai::parse-json
                   (cadr-ai::stringify-json *clef-output*))
                  "answers")))
          (is (string=
               "https://api.cloudflare.com/client/v4/accounts/account-id/ai/run"
               (getf call :url)))
          (is (string= "Bearer cf-key"
                       (cdr (header-present-p
                             (getf call :headers)
                             "authorization"))))
          (is (string= id (cadr-ai::json-get payload "model")))
          (is (equal "noul"
                     (cadr-ai::json-get
                      (cadr-ai::json-get
                       (cadr-ai::json-get input "questions")
                       "is_urgent")
                      "type")))
          (is (eq :stop (cadr-ai:classifier-result-stop-reason result)))
          (is (= (cadr-ai::json-get
                  (cadr-ai::json-get wire-answers "is_urgent")
                  "noul")
                 (cadr-ai::json-get
                  (cadr-ai::json-get
                   (cadr-ai:classifier-result-answers result)
                   "is_urgent")
                  "probability")))
          (is (string=
               "technical"
               (cadr-ai::json-get
                (cadr-ai::json-get
                 (cadr-ai:classifier-result-answers result)
                 "department")
                "choice")))
          (is (= (cadr-ai::json-get
                  (cadr-ai::json-get wire-answers "department")
                  "confidence")
                 (cadr-ai::json-get
                  (cadr-ai::json-get
                   (cadr-ai:classifier-result-answers result)
                   "department")
                  "confidence")))
          (is (= 222 (cadr-ai:usage-input usage)))
          (is (= 0 (cadr-ai:usage-output usage)))
          (is (= 222 (cadr-ai:usage-total usage)))
          (is (< (abs (- (cadr-ai:cost-input (cadr-ai:usage-cost usage))
                         (* (/ 222d0 1000000d0) price)))
                 1d-15)))))))

(test cloudflare-clef-sends-images-as-data-urls
  (multiple-value-bind (http calls)
      (capture-classifier-http
       (cadr-ai::stringify-json (cloudflare-envelope *clef-output*)))
    (let* ((*http-request-function* http)
           (context (classifier-sample-context))
           (result
             (cadr-ai:classify-model
              (cadr-ai:find-classifier-model
               :cloudflare-workers-ai "@cf/cloudflare/clef")
              (classifier-sample-context
               :images
               (list (classifier-image "cG5n" "image/png")
                     (classifier-image "d2VicA==" "image/webp")))
              :api-key "cf-key"
              :environment (cloudflare-auth-env)))
           (call (first (funcall calls)))
           (input (cadr-ai::json-get (getf call :body) "input")))
      (is (eq :stop (cadr-ai:classifier-result-stop-reason result)))
      (is (json-same-p
           (cadr-ai:classifier-context-state context)
           (cadr-ai::json-get input "state")))
      (is (not (cadr-ai::json-present-p input "assets")))
      (is (equalp
           #("data:image/png;base64,cG5n" "data:image/webp;base64,d2VicA==")
           (cadr-ai::json-get input "images")))
      (is (not (header-present-p
                (getf call :headers)
                "typesafe-danger-zone-images"))))))

(test cloudflare-compat-image-form-beats-the-model-id
  (let* ((jev
           (cadr-ai:find-classifier-model
            :cloudflare-workers-ai "typesafe/jev"))
         (clef
           (cadr-ai:find-classifier-model
            :cloudflare-workers-ai "@cf/cloudflare/clef")))
    (is (equal '((:image-input . :images))
               (cadr-ai:classifier-model-compat clef)))
    (is (equal '((:image-input . :assets))
               (cadr-ai:classifier-model-compat jev))))
  (multiple-value-bind (http calls)
      (capture-classifier-http
       (cadr-ai::stringify-json (cloudflare-envelope *clef-output*)))
    (let* ((*http-request-function* http)
           (model
             (cadr-ai::copy-classifier-model
              (cadr-ai:find-classifier-model
               :cloudflare-workers-ai "typesafe/jev")))
           (result
             (progn
               (setf (cadr-ai:classifier-model-id model)
                     "@cf/acme/clef-finetune")
               (setf (cadr-ai:classifier-model-input model) '(:text :image))
               (setf (cadr-ai:classifier-model-compat model)
                     '((:image-input . :images)))
               (cadr-ai:classify-model
                model
                (classifier-sample-context
                 :images (list (classifier-image "cG5n" "image/png")))
                :api-key "cf-key"
                :environment (cloudflare-auth-env))))
           (input
             (cadr-ai::json-get
              (getf (first (funcall calls)) :body)
              "input")))
      (is (eq :stop (cadr-ai:classifier-result-stop-reason result)))
      (is (equalp #("data:image/png;base64,cG5n")
                  (cadr-ai::json-get input "images")))
      (is (not (cadr-ai::json-present-p input "assets"))))))

(test cloudflare-clef-rejects-a-fifth-image-before-sending
  (let ((attempts 0))
    (let* ((*http-request-function*
             (lambda (url &rest arguments)
               (declare (ignore url arguments))
               (incf attempts)
               (values "{}" 200 nil)))
           (image (classifier-image "cG5n" "image/png"))
           (result
             (cadr-ai:classify-model
              (cadr-ai:find-classifier-model
               :cloudflare-workers-ai "@cf/cloudflare/clef-flash")
              (classifier-sample-context
               :images (list image image image image image))
              :api-key "cf-key"
              :environment (cloudflare-auth-env))))
      (is (= 0 attempts))
      (is (eq :error (cadr-ai:classifier-result-stop-reason result)))
      (is (string=
           "Cloudflare Workers AI accepts at most 4 images for @cf/cloudflare/clef-flash, got 5"
           (cadr-ai:classifier-result-error-message result))))))

(test cloudflare-jev-sends-images-as-system-one-assets
  (dolist (id '("typesafe/jev" "typesafe/jev-1.14.0"))
    (multiple-value-bind (http calls)
        (capture-classifier-http
         (cadr-ai::stringify-json
          (cloudflare-envelope *jev-output* :state "Completed")))
      (let* ((*http-request-function* http)
             (context (classifier-sample-context))
             (result
               (cadr-ai:classify-model
                (cadr-ai:find-classifier-model :cloudflare-workers-ai id)
                (classifier-sample-context
                 :images (list (classifier-image "cG5n" "image/png")))
                :api-key "cf-key"
                :environment (cloudflare-auth-env)))
             (call (first (funcall calls)))
             (body (getf call :body))
             (input (cadr-ai::json-get body "input")))
        (is (eq :stop (cadr-ai:classifier-result-stop-reason result)))
        (is (string= id (cadr-ai::json-get body "model")))
        (is (json-same-p
             (cadr-ai::json-array
              "<image-1>"
              (cadr-ai:classifier-context-state context))
             (cadr-ai::json-get input "state")))
        (is (json-same-p
             (cadr-ai::json-object
              "<image-1>"
              (cadr-ai::json-object
               "type" "image"
               "format" "png"
               "data_base64" "cG5n"))
             (cadr-ai::json-get input "assets")))
        (is (not (header-present-p
                  (getf call :headers)
                  "typesafe-danger-zone-images")))))))

(test cloudflare-classifier-reports-incomplete-runs-and-envelope-errors
  (let* ((*http-request-function*
           (lambda (url &rest arguments)
             (declare (ignore url arguments))
             (values
              (cadr-ai::stringify-json
               (cloudflare-envelope nil :state "Queued"))
              200 nil)))
         (queued
           (cadr-ai:classify-model
            (cadr-ai:find-classifier-model
             :cloudflare-workers-ai "typesafe/jev")
            (classifier-sample-context)
            :api-key "cf-key"
            :environment (cloudflare-auth-env))))
    (is (eq :error (cadr-ai:classifier-result-stop-reason queued)))
    (is (search "run did not complete (state: Queued)"
                (cadr-ai:classifier-result-error-message queued))))
  (let* ((*http-request-function*
           (lambda (url &rest arguments)
             (declare (ignore url arguments))
             (values
              (cadr-ai::stringify-json
               (cloudflare-envelope
                'null
                :success nil
                :errors
                (cadr-ai::json-array
                 (cadr-ai::json-object
                  "code" 5007
                  "message" "No such model"))))
              200 nil)))
         (failed
           (cadr-ai:classify-model
            (cadr-ai:find-classifier-model
             :cloudflare-workers-ai "typesafe/jev")
            (classifier-sample-context)
            :api-key "cf-key"
            :environment (cloudflare-auth-env))))
    (is (eq :error (cadr-ai:classifier-result-stop-reason failed)))
    (is (search "Cloudflare Workers AI error: No such model"
                (cadr-ai:classifier-result-error-message failed)))))

(defun typesafe-jev ()
  (cadr-ai:make-classifier-model
   :id "jev-latest"
   :name "Jev"
   :provider :typesafe
   :api :typesafe-system-one
   :base-url "https://api.typesafe.ai/v1/"
   :input '(:text)
   :context-window 64000
   :input-price 0d0))

(defparameter *typesafe-answers*
  (cadr-ai::json-object
   "answers"
   (cadr-ai::json-object
    "is_urgent" (cadr-ai::json-object "type" "noul" "noul" 0.95d0)
    "department"
    (cadr-ai::json-object
     "type" "choice"
     "choice" "billing"
     "confidence" 0.8d0
     "probabilities"
     (cadr-ai::json-object "billing" 0.87d0 "technical" 0.13d0)))))

(test typesafe-rejects-images-for-text-only-models
  (let ((attempts 0))
    (let* ((*http-request-function*
             (lambda (url &rest arguments)
               (declare (ignore url arguments))
               (incf attempts)
               (values "{}" 200 nil)))
           (result
             (cadr-ai:classify-model
              (typesafe-jev)
              (classifier-sample-context
               :images (list (classifier-image "aW1hZ2U=" "image/png")))
              :api-key "secret")))
      (is (= 0 attempts))
      (is (eq :error (cadr-ai:classifier-result-stop-reason result)))
      (is (string=
           "System One API does not support image input for jev-latest"
           (cadr-ai:classifier-result-error-message result))))))

(test typesafe-sends-images-as-assets-with-the-opt-in-header
  ;; pi@4a080252f packages/ai/src/providers/data/typesafe.json jev-latest.
  (let ((model (cadr-ai:find-classifier-model :typesafe "jev-latest")))
    (is (eq :typesafe-system-one (cadr-ai:classifier-model-api model)))
    (is (equal '(:text :image) (cadr-ai:classifier-model-input model)))
    (is (= 64000 (cadr-ai:classifier-model-context-window model)))
    (is (= 0d0 (cadr-ai:classifier-model-input-price model)))
    (is (equal '((:image-input . :assets)
                 (:send-image-opt-in-header . t))
               (cadr-ai:classifier-model-compat model)))
    (is (string= "https://api.typesafe.ai/v1/"
                 (cadr-ai:classifier-model-base-url model)))
    (handler-case
        (cadr-ai:find-model-metadata :typesafe "jev-latest")
      (cadr-ai:configuration-error ()
        (is (eq t t)))
      (:no-error (&rest ignored)
        (declare (ignore ignored))
        (is (eq t nil)))))
  (multiple-value-bind (http calls)
      (capture-classifier-http (cadr-ai::stringify-json *typesafe-answers*))
    (let* ((*http-request-function* http)
           (model (cadr-ai:find-classifier-model :typesafe "jev-latest"))
           (context (classifier-sample-context)))
      (let ((result
              (cadr-ai:classify-model
               model
               (classifier-sample-context
                :images
                (list (classifier-image "cG5n" "image/png")
                      (classifier-image "anBlZw==" "image/jpeg")))
               :api-key "secret"))
            (plain
              (cadr-ai:classify-model
               model context :api-key "secret")))
        (is (eq :stop (cadr-ai:classifier-result-stop-reason result)))
        (is (eq :stop (cadr-ai:classifier-result-stop-reason plain)))
        (let* ((recorded (funcall calls))
               (first-call (first recorded))
               (second-call (second recorded))
               (body (getf first-call :body)))
          (is (string=
               "https://api.typesafe.ai/v1/systemone"
               (getf first-call :url)))
          (is (json-same-p
               (cadr-ai::json-array
                "<image-1>" "<image-2>"
                (cadr-ai:classifier-context-state context))
               (cadr-ai::json-get body "state")))
          (is (json-same-p
               (cadr-ai::json-object
                "<image-1>"
                (cadr-ai::json-object
                 "type" "image" "format" "png" "data_base64" "cG5n")
                "<image-2>"
                (cadr-ai::json-object
                 "type" "image" "format" "jpeg" "data_base64" "anBlZw=="))
               (cadr-ai::json-get body "assets")))
          (is (string=
               "true"
               (cdr (header-present-p
                     (getf first-call :headers)
                     "typesafe-danger-zone-images"))))
          (is (json-same-p
               (cadr-ai:classifier-context-state context)
               (cadr-ai::json-get (getf second-call :body) "state")))
          (is (not (cadr-ai::json-present-p (getf second-call :body) "assets")))
          (is (not (header-present-p
                    (getf second-call :headers)
                    "typesafe-danger-zone-images"))))))))

(test typesafe-rejects-webp-assets-before-sending
  (let ((attempts 0)
        (model (cadr-ai:find-classifier-model :typesafe "jev-latest")))
    (let* ((*http-request-function*
             (lambda (url &rest arguments)
               (declare (ignore url arguments))
               (incf attempts)
               (values "{}" 200 nil)))
           (result
             (cadr-ai:classify-model
              model
              (classifier-sample-context
               :images (list (classifier-image "d2VicA==" "image/webp")))
              :api-key "secret")))
      (is (= 0 attempts))
      (is (string=
           "System One API accepts PNG and JPEG images for jev-latest, got image/webp"
           (cadr-ai:classifier-result-error-message result))))))

(test openrouter-sends-classifier-images-as-state-image-urls
  ;; pi-ai@1.4.0 openrouter.json typesafe/jev-1.14.
  (let ((model
          (cadr-ai:find-classifier-model :openrouter "typesafe/jev-1.14")))
    (is (string= "TypeSafe: Jev 1.14" (cadr-ai:classifier-model-name model)))
    (is (eq :typesafe-system-one (cadr-ai:classifier-model-api model)))
    (is (equal '(:text :image) (cadr-ai:classifier-model-input model)))
    (is (= 0.042d0 (cadr-ai:classifier-model-input-price model)))
    (is (= 262144 (cadr-ai:classifier-model-context-window model)))
    (is (equal '((:image-input . :state-image-urls)
                 (:send-image-opt-in-header . nil))
               (cadr-ai:classifier-model-compat model)))
    (handler-case
        (cadr-ai:find-model-metadata :openrouter "typesafe/jev-1.14")
      (cadr-ai:configuration-error ()
        (is (eq t t)))
      (:no-error (&rest ignored)
        (declare (ignore ignored))
        (is (eq t nil)))))
  (multiple-value-bind (http calls)
      (capture-classifier-http (cadr-ai::stringify-json *typesafe-answers*))
    (let* ((*http-request-function* http)
           (context (classifier-sample-context))
           (model
             (cadr-ai:find-classifier-model :openrouter "typesafe/jev-1.14"))
           (result
             (cadr-ai:classify-model
              model
              (classifier-sample-context
               :images (list (classifier-image "cG5n" "image/png")))
              :api-key "secret"))
           (call (first (funcall calls)))
           (body (getf call :body)))
      (is (eq :stop (cadr-ai:classifier-result-stop-reason result)))
      (is (string=
           "https://openrouter.ai/api/v1/systemone"
           (getf call :url)))
      (is (string= "typesafe/jev-1.14" (cadr-ai::json-get body "model")))
      (is (not (cadr-ai::json-present-p body "assets")))
      (is (not (cadr-ai::json-present-p body "images")))
      (is (json-same-p
           (cadr-ai::json-array
            (cadr-ai::json-object
             "type" "image_url"
             "image_url"
             (cadr-ai::json-object "url" "data:image/png;base64,cG5n"))
            (cadr-ai:classifier-context-state context))
           (cadr-ai::json-get body "state")))
      (is (not (header-present-p
                (getf call :headers)
                "typesafe-danger-zone-images"))))))

(test openrouter-image-form-follows-provider-host-or-compat
  (dolist (overrides
           '((:provider :openrouter :base-url "https://proxy.example.com/v1")
             (:provider :custom :base-url "https://us.openrouter.ai/api/v1")
             (:provider :custom
              :base-url "https://proxy.example.com/v1"
              :compat ((:image-input . :state-image-urls)
                       (:send-image-opt-in-header . nil)))))
    (multiple-value-bind (http calls)
        (capture-classifier-http
         (cadr-ai::stringify-json *typesafe-answers*))
      (let* ((*http-request-function* http)
             (context (classifier-sample-context))
             (model
               (cadr-ai:make-classifier-model
                :id "typesafe/jev-1.14"
                :name "Jev 1.14"
                :provider (getf overrides :provider)
                :api :typesafe-system-one
                :base-url (getf overrides :base-url)
                :input '(:text :image)
                :context-window 32000
                :compat (getf overrides :compat)))
             (result
               (cadr-ai:classify-model
                model
                (classifier-sample-context
                 :images (list (classifier-image "cG5n" "image/png")))
                :api-key "secret"))
             (call (first (funcall calls)))
             (body (getf call :body)))
        (is (eq :stop (cadr-ai:classifier-result-stop-reason result)))
        (is (not (cadr-ai::json-present-p body "assets")))
        (is (json-same-p
             (cadr-ai::json-array
              (cadr-ai::json-object
               "type" "image_url"
               "image_url"
               (cadr-ai::json-object "url" "data:image/png;base64,cG5n"))
              (cadr-ai:classifier-context-state context))
             (cadr-ai::json-get body "state")))
        (is (not (header-present-p
                  (getf call :headers)
                  "typesafe-danger-zone-images")))))))

(test classifier-compat-overrides-one-image-field-at-a-time
  (multiple-value-bind (http calls)
      (capture-classifier-http (cadr-ai::stringify-json *typesafe-answers*))
    (let* ((*http-request-function* http)
           (model (typesafe-jev)))
      (setf (cadr-ai:classifier-model-input model) '(:text :image))
      (setf (cadr-ai:classifier-model-compat model)
            '((:send-image-opt-in-header . nil)))
      (cadr-ai:classify-model
       model
       (classifier-sample-context
        :images (list (classifier-image "cG5n" "image/png")))
       :api-key "secret")
      (let ((call (first (funcall calls))))
        (is (cadr-ai::json-present-p (getf call :body) "assets"))
        (is (not (header-present-p
                  (getf call :headers)
                  "typesafe-danger-zone-images")))))))

(defun detailed-classifier-user-agent ()
  ;; pi@4a080252f identity.ts formatUserAgent detailed form, cadr product
  ;; and SBCL runtime. Locked here so the classifier assertion does not
  ;; read the implementation back.
  (format nil "cadr/~A (~(~A~); sbcl/~A; ~(~A~))"
          (cadr-ai::cadr-version)
          (software-type)
          (lisp-implementation-version)
          (machine-type)))

(test cloudflare-classifier-sends-the-detailed-user-agent
  ;; pi@4a080252f classifier-shared.ts requestHeaders spreads
  ;; getIdentityHeaders. CHANGELOG 1.4.0: classifier requests send the
  ;; User-Agent. Cloudflare classification goes through classify-system-one.
  (multiple-value-bind (http calls)
      (capture-classifier-http
       (cadr-ai::stringify-json (cloudflare-envelope *clef-output*)))
    (let* ((*http-request-function* http))
      (cadr-ai:classify-model
       (cadr-ai:find-classifier-model
        :cloudflare-workers-ai "@cf/cloudflare/clef")
       (classifier-sample-context)
       :api-key "cf-key"
       :environment (cloudflare-auth-env))
      (is (string=
           (detailed-classifier-user-agent)
           (cdr (header-present-p
                 (getf (first (funcall calls)) :headers)
                 "User-Agent")))))))

(test classifier-headers-override-and-delete-the-identity
  ;; providerHeadersToRecord: model headers then caller headers. null deletes.
  (multiple-value-bind (http calls)
      (capture-classifier-http
       (cadr-ai::stringify-json (cloudflare-envelope *clef-output*)))
    (let* ((*http-request-function* http)
           (model
             (cadr-ai::copy-classifier-model
              (cadr-ai:find-classifier-model
               :cloudflare-workers-ai "@cf/cloudflare/clef"))))
      (setf (cadr-ai::classifier-model-headers model)
            '(("User-Agent" . "GitHubCopilotChat/0.35.0")))
      (cadr-ai:classify-model
       model (classifier-sample-context)
       :api-key "cf-key"
       :environment (cloudflare-auth-env)
       :identity (cadr-ai::client-identity :user-agent :short))
      (cadr-ai:classify-model
       model (classifier-sample-context)
       :api-key "cf-key"
       :environment (cloudflare-auth-env)
       :headers '(("User-Agent" . nil)))
      (let* ((recorded (funcall calls))
             (impersonated (getf (first recorded) :headers))
             (removed (getf (second recorded) :headers)))
        (is (string=
             "GitHubCopilotChat/0.35.0"
             (cdr (header-present-p impersonated "User-Agent"))))
        (is (not (header-present-p removed "User-Agent")))
        (is (string=
             "Bearer cf-key"
             (cdr (header-present-p removed "authorization"))))))))

(test classifier-attribution-is-off-until-the-identity-asks
  ;; pi-ai sends no attribution unless identity.attribution is set.
  ;; A null caller header still removes one name and leaves the rest.
  (multiple-value-bind (http calls)
      (capture-classifier-http (cadr-ai::stringify-json *typesafe-answers*))
    (let* ((*http-request-function* http)
           (model
             (cadr-ai:make-classifier-model
              :id "typesafe/jev-1.14"
              :name "Jev 1.14"
              :provider :openrouter
              :api :typesafe-system-one
              :base-url "https://openrouter.ai/api/v1"
              :context-window 32000)))
      (cadr-ai:classify-model
       model (classifier-sample-context) :api-key "secret")
      (cadr-ai:classify-model
       model (classifier-sample-context)
       :api-key "secret"
       :identity (cadr-ai::client-identity
                  :attribution cadr-ai::+cadr-attribution+))
      (cadr-ai:classify-model
       model (classifier-sample-context)
       :api-key "secret"
       :identity (cadr-ai::client-identity
                  :user-agent '(:custom "acme/1.0")
                  :attribution cadr-ai::+cadr-attribution+)
       :headers '(("HTTP-Referer" . nil)
                  ("X-OpenRouter-Title" . "kept")))
      (let* ((recorded (funcall calls))
             (plain (getf (first recorded) :headers))
             (attributed (getf (second recorded) :headers))
             (overridden (getf (third recorded) :headers)))
        (is (string=
             (detailed-classifier-user-agent)
             (cdr (header-present-p plain "User-Agent"))))
        (is (not (header-present-p plain "HTTP-Referer")))
        (is (string=
             "https://github.com/artwalker/cadr"
             (cdr (header-present-p attributed "HTTP-Referer"))))
        (is (string=
             "cadr"
             (cdr (header-present-p attributed "X-OpenRouter-Title"))))
        (is (string=
             "cli-agent"
             (cdr (header-present-p attributed "X-OpenRouter-Categories"))))
        (is (not (header-present-p overridden "HTTP-Referer")))
        (is (string=
             "kept"
             (cdr (header-present-p overridden "X-OpenRouter-Title"))))
        (is (string=
             "acme/1.0"
             (cdr (header-present-p overridden "User-Agent"))))
        (is (string=
             "cli-agent"
             (cdr (header-present-p overridden "X-OpenRouter-Categories"))))))))

(defparameter *openrouter-decision-catalog*
  ;; pi-ai@1.4.0 dist/providers/data/openrouter.json typesafe-system-one.
  '(("cloudflare/clef" "Cloudflare: Clef" (:text :image) 0.24d0 0d0 65536)
    ("cloudflare/clef-flash" "Cloudflare: Clef Flash" (:text :image) 0.038d0 0d0 24576)
    ("cloudflare/clef-omni" "Cloudflare: Clef Omni" (:text :image) 0.15d0 0d0 65536)
    ("inception/mercury-decide" "Inception: Mercury Decide" (:text :image) 0.02d0 0d0 65536)
    ("inception/mercury-decide:free" "Inception: Mercury Decide (free)" (:text :image) 0d0 0d0 65536)
    ("jaredpalmer/kev-4b" "Jared Palmer: Kev 4B" (:text) 0.042d0 0d0 8192)
    ("liquid/d1" "LiquidAI: d1" (:text :image) 0.02d0 0.02d0 65536)
    ("liquid/d1-ultra" "LiquidAI: d1-ultra" (:text :image) 0.042d0 0.042d0 32768)
    ("microsoft/microsoft-decision-1" "Microsoft: Microsoft-Decision-1" (:text) 0.042d0 0d0 32768)
    ("nace-ai/drex-max" "Nace.AI: Drex Max" (:text) 0.06d0 0d0 262144)
    ("nace-ai/drex-v1.5" "Nace.AI: Drex v1.5" (:text) 0.04d0 0d0 131072)
    ("nace-ai/drex-v2.0" "Nace.AI: Drex v2.0" (:text) 0.06d0 0d0 131072)
    ("openai/gpt-6-luna-decisions" "OpenAI: GPT-6 Luna Decisions" (:text :image) 0.1d0 0d0 1050000)
    ("perplexity/pplx-decider-flash-v1.2" "Perplexity: Decider Flash V1.2" (:text :image) 0.01d0 0d0 262144)
    ("perplexity/pplx-decider-v1.2" "Perplexity: Decider V1.2" (:text :image) 0.02d0 0d0 262144)
    ("respan/span-01" "Respan: Span-01" (:text) 0.02d0 0d0 4096)
    ("respan/span-01-lite" "Respan: Span-01 Lite" (:text) 0d0 0d0 4096)
    ("respan/span-01-lite:free" "Respan: Span-01 Lite (free)" (:text) 0d0 0d0 4096)
    ("respan/span-02" "Respan: Span-02" (:text :image) 0.01d0 0d0 131072)
    ("scaledown/classify-1" "ScaleDown: Classify-1" (:text :image) 0.04d0 0d0 1000000)
    ("togethercomputer/tev1-4b-experimental" "Together: Tev1 4B Experimental" (:text) 0.042d0 0d0 32768)
    ("typesafe/jev-1.13" "TypeSafe: Jev 1.13" (:text :image) 0.042d0 0d0 262144)
    ("typesafe/jev-1.14" "TypeSafe: Jev 1.14" (:text :image) 0.042d0 0d0 262144)
    ("upstage/solar-decide" "Upstage: Solar Decide" (:text) 0.05d0 0.05d0 524288)
    ("upstage/solar-decide-flash" "Upstage: Solar Decide Flash" (:text) 0.05d0 0.05d0 524288)
    ("~perplexity/pplx-decider-flash-latest" "Perplexity: Decider Flash Latest" (:text :image) 0.01d0 0d0 262144)
    ("~perplexity/pplx-decider-latest" "Perplexity: Decider Latest" (:text :image) 0.02d0 0d0 262144)
    ("~typesafe/jev-latest" "TypeSafe: Jev Latest" (:text :image) 0.042d0 0d0 262144)))

(test openrouter-decision-catalog-sets-state-image-urls
  ;; pi@4a080252f packages/ai/test/classifier-models.test.ts
  (let ((listed (cadr-ai:list-classifier-models :openrouter)))
    (is (= (length *openrouter-decision-catalog*) (length listed)))
    (is (equal (mapcar #'first *openrouter-decision-catalog*)
               (mapcar #'cadr-ai:classifier-model-id listed))))
  (dolist (row *openrouter-decision-catalog*)
    (destructuring-bind (id name input price cache-read window) row
      (let ((model (cadr-ai:find-classifier-model :openrouter id)))
        (is (string= name (cadr-ai:classifier-model-name model)))
        (is (eq :typesafe-system-one (cadr-ai:classifier-model-api model)))
        (is (string= "https://openrouter.ai/api/v1"
                     (cadr-ai:classifier-model-base-url model)))
        (is (equal input (cadr-ai:classifier-model-input model)))
        (is (= price (cadr-ai:classifier-model-input-price model)))
        (is (= 0d0 (cadr-ai:classifier-model-output-price model)))
        (is (= cache-read
               (cadr-ai::classifier-model-cache-read-price model)))
        (is (= window (cadr-ai:classifier-model-context-window model)))
        (is (equal '((:image-input . :state-image-urls)
                     (:send-image-opt-in-header . nil))
                   (cadr-ai:classifier-model-compat model)))
        (handler-case
            (cadr-ai:find-model-metadata :openrouter id)
          (cadr-ai:configuration-error ()
            (is (eq t t)))
          (:no-error (&rest ignored)
            (declare (ignore ignored))
            (is (eq t nil)))))))
  (let ((attempts 0))
    (let* ((*http-request-function*
             (lambda (url &rest arguments)
               (declare (ignore url arguments))
               (incf attempts)
               (values "{}" 200 nil)))
           (result
             (cadr-ai:classify-model
              (cadr-ai:find-classifier-model :openrouter "jaredpalmer/kev-4b")
              (classifier-sample-context
               :images (list (classifier-image "cG5n" "image/png")))
              :api-key "secret")))
      (is (= 0 attempts))
      (is (string=
           "System One API does not support image input for jaredpalmer/kev-4b"
           (cadr-ai:classifier-result-error-message result))))))
