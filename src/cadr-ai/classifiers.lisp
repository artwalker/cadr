(in-package #:cadr-ai)

;; Classifier models stay in their own catalog. A chat lookup of the same
;; id stays unknown, which is what keeps them out of /model.
(defparameter *classifier-catalog* (make-hash-table :test #'equal))

(defstruct classifier-model
  (id "" :type string)
  (name "" :type string)
  (provider nil :type symbol)
  (api nil :type symbol)
  (base-url "" :type string)
  (input '(:text) :type list)
  (context-window 0 :type (integer 0 *))
  (input-price 0d0 :type double-float)
  (output-price 0d0 :type double-float)
  (cache-read-price 0d0 :type double-float)
  (cache-write-price 0d0 :type double-float)
  (headers nil :type list)
  ;; Alist. A present key wins over detection even when the value is nil,
  ;; so send-image-opt-in-header false is distinct from leaving it unset.
  (compat nil :type list))

(defstruct classifier-context
  state
  (questions (make-hash-table :test #'equal) :type hash-table)
  (images nil :type list))

(defstruct classifier-result
  (api nil :type symbol)
  (provider nil :type symbol)
  (model "" :type string)
  (answers (make-hash-table :test #'equal) :type hash-table)
  (stop-reason :stop :type symbol)
  (error-message nil :type (or null string))
  (usage nil :type (or null usage))
  (timestamp (unix-milliseconds) :type integer))

(defstruct system-one-transport
  (api nil :type symbol)
  (label "" :type string)
  (detect-compat nil :type (or null function))
  (endpoint "" :type string)
  (wrap-payload nil :type (or null function))
  (unwrap-output nil :type (or null function)))

(defparameter +cloudflare-workers-ai-rest-base-url+
  "https://api.cloudflare.com/client/v4/accounts/{CLOUDFLARE_ACCOUNT_ID}/ai")

(defparameter +clef-image-limit+ 4)

(defun classifier-catalog-key (provider id)
  (cons provider id))

(defun register-classifier-model (model)
  (setf (gethash
         (classifier-catalog-key
          (classifier-model-provider model)
          (classifier-model-id model))
         *classifier-catalog*)
        model)
  model)

(defun find-classifier-model (provider id)
  (gethash (classifier-catalog-key provider id) *classifier-catalog*))

(defun list-classifier-models (&optional provider)
  (sort
   (loop for model being the hash-values of *classifier-catalog*
         when (or (null provider)
                  (eq provider (classifier-model-provider model)))
           collect model)
   #'string<
   :key #'classifier-model-id))

(defun provider-wire-name (provider)
  (string-downcase (symbol-name provider)))

(defun finite-real-p (value)
  (and (realp value)
       (or (not (floatp value))
           (and (not (sb-ext:float-infinity-p value))
                (not (sb-ext:float-nan-p value))))))

(defun classifier-condition-text (condition)
  (typecase condition
    (cadr-error (cadr-error-message condition))
    (simple-condition
     (apply #'format nil
            (simple-condition-format-control condition)
            (simple-condition-format-arguments condition)))
    (t (princ-to-string condition))))

(defun classifier-accepts-images-p (model)
  (member :image (classifier-model-input model)))

(defun compat-field (model key)
  (assoc key (classifier-model-compat model)))

(defun join-endpoint (base endpoint)
  (concatenate 'string (string-right-trim "/" base) "/" endpoint))

(defun upsert-header (headers name value)
  (let ((found (assoc name headers :test #'string-equal)))
    (if found
        (progn (setf (cdr found) value) headers)
        (append headers (list (cons name value))))))

(defun classifier-request-headers (model api-key extra)
  (let ((headers
          (list (cons "content-type" "application/json")
                (cons "authorization"
                      (format nil "Bearer ~A" api-key)))))
    (dolist (pair (append (classifier-model-headers model) extra) headers)
      (setf headers (upsert-header headers (car pair) (cdr pair))))))

(defun copy-json-object (object)
  (let ((copy (make-hash-table :test #'equal)))
    (maphash (lambda (key value) (setf (gethash key copy) value)) object)
    copy))

(defun wire-question (question)
  (if (equal (json-get question "type") "bool")
      (let ((copy (copy-json-object question)))
        (setf (gethash "type" copy) "noul")
        copy)
      question))

(defun wire-questions (questions)
  (let ((wired (make-hash-table :test #'equal)))
    (maphash
     (lambda (id question)
       (setf (gethash id wired) (wire-question question)))
     questions)
    wired))

(defun system-one-request (context)
  (json-object
   "state" (classifier-context-state context)
   "questions" (wire-questions (classifier-context-questions context))))

(defun asset-format (mime-type)
  (cond
    ((string= mime-type "image/png") "png")
    ((string= mime-type "image/jpeg") "jpeg")
    (t nil)))

(defun data-url-mime-p (mime-type)
  (member mime-type '("image/png" "image/jpeg" "image/webp")
          :test #'string=))

(defun add-classifier-images (label model image-input images request)
  (cond
    ((eq image-input :images)
     (when (> (length images) +clef-image-limit+)
       (error "~A accepts at most ~A images for ~A, got ~A"
              label +clef-image-limit+
              (classifier-model-id model)
              (length images)))
     (setf (gethash "images" request)
           (list-json-array
            (mapcar
             (lambda (image)
               (let ((mime-type (image-content-mime-type image)))
                 (unless (data-url-mime-p mime-type)
                   (error "~A accepts PNG, JPEG, and WebP images for ~A, got ~A"
                          label (classifier-model-id model) mime-type))
                 (format nil "data:~A;base64,~A"
                         mime-type (image-content-data image))))
             images))))
    ((eq image-input :state-image-urls)
     (setf (gethash "state" request)
           (list-json-array
            (append
             (mapcar
              (lambda (image)
                (json-object
                 "type" "image_url"
                 "image_url"
                 (json-object
                  "url"
                  (format nil "data:~A;base64,~A"
                          (image-content-mime-type image)
                          (image-content-data image)))))
              images)
             (list (json-get request "state"))))))
    (t
     (let ((assets (make-hash-table :test #'equal))
           (names nil))
       (loop for image in images
             for index from 1
             for format = (asset-format (image-content-mime-type image))
             for name = (format nil "<image-~A>" index)
             do (unless format
                  (error "~A accepts PNG and JPEG images for ~A, got ~A"
                         label
                         (classifier-model-id model)
                         (image-content-mime-type image)))
                (setf (gethash name assets)
                      (json-object
                       "type" "image"
                       "format" format
                       "data_base64" (image-content-data image)))
                (setf names (nconc names (list name))))
       (setf (gethash "assets" request) assets
             (gethash "state" request)
             (list-json-array
              (append names (list (json-get request "state")))))))))

(defun required-classifier-number (label value field)
  (unless (finite-real-p value)
    (error "~A returned an invalid ~A" label field))
  value)

(defun parse-probability-table (label id value)
  (unless (hash-table-p value)
    (error "~A returned invalid probabilities for ~A" label id))
  (let ((parsed (make-hash-table :test #'equal)))
    (maphash
     (lambda (key probability)
       (setf (gethash key parsed)
             (required-classifier-number
              label probability
              (format nil "probability for ~A.~A" id key))))
     value)
    parsed))

(defun parse-classifier-answer (label id question answer)
  (unless (hash-table-p answer)
    (error "~A did not return an answer for ~A" label id))
  (cond
    ((equal (json-get question "type") "choice")
     (unless (and (equal (json-get answer "type") "choice")
                  (stringp (json-get answer "choice")))
       (error "~A did not return a choice answer for ~A" label id))
     (json-object
      "type" "choice"
      "choice" (json-get answer "choice")
      "probabilities"
      (parse-probability-table
       label id (json-get answer "probabilities"))
      "confidence"
      (required-classifier-number
       label (json-get answer "confidence")
       (format nil "confidence for ~A" id))))
    ((equal (json-get question "type") "score")
     (unless (equal (json-get answer "type") "score")
       (error "~A did not return a score answer for ~A" label id))
     (json-object
      "type" "score"
      "score"
      (required-classifier-number
       label (json-get answer "score")
       (format nil "score for ~A" id))
      "confidence"
      (required-classifier-number
       label (json-get answer "confidence")
       (format nil "confidence for ~A" id))))
    (t
     (unless (equal (json-get answer "type") "noul")
       (error "~A did not return a bool answer for ~A" label id))
     (json-object
      "type" "bool"
      "probability"
      (required-classifier-number
       label (json-get answer "noul")
       (format nil "probability for ~A" id))))))

(defun parse-classifier-answers (label value context)
  (unless (hash-table-p value)
    (error "~A returned an unexpected response" label))
  (let ((answers (make-hash-table :test #'equal)))
    (maphash
     (lambda (id question)
       (setf (gethash id answers)
             (parse-classifier-answer
              label id question (json-get value id))))
     (classifier-context-questions context))
    answers))

(defun token-count (value)
  (if (and (finite-real-p value) (plusp value))
      (truncate value)
      0))

(defun classifier-token-charge (tokens price)
  (* (/ (coerce tokens 'double-float) 1000000d0) price))

(defun parse-classifier-usage (value model)
  (unless (and (hash-table-p value)
               (or (json-present-p value "input_tokens")
                   (json-present-p value "output_tokens")))
    (return-from parse-classifier-usage nil))
  (let* ((input (token-count (json-get value "input_tokens")))
         (output (token-count (json-get value "output_tokens")))
         (input-cost
           (classifier-token-charge
            input (classifier-model-input-price model)))
         (output-cost
           (classifier-token-charge
            output (classifier-model-output-price model)))
         (cache-read-cost
           (classifier-token-charge
            0 (classifier-model-cache-read-price model)))
         (cache-write-cost
           (classifier-token-charge
            0 (classifier-model-cache-write-price model))))
    (make-usage
     :input input
     :output output
     :cache-read 0
     :cache-write 0
     :total (+ input output)
     :cost
     (make-cost
      :input input-cost
      :output output-cost
      :cache-read cache-read-cost
      :cache-write cache-write-cost
      :total
      (+ input-cost output-cost cache-read-cost cache-write-cost)))))

(defun cloudflare-error-message (errors)
  (let ((messages
          (and (vectorp errors)
               (loop for item across errors
                     for message = (and (hash-table-p item)
                                        (json-get item "message"))
                     when (stringp message)
                       collect message))))
    (if messages
        (format nil "Cloudflare Workers AI error: ~{~A~^; ~}" messages)
        "Cloudflare Workers AI request failed")))

(defun cloudflare-system-one-output (body)
  (unless (hash-table-p body)
    (error "Cloudflare Workers AI returned an unexpected response"))
  (when (and (json-present-p body "success")
             (not (json-get body "success")))
    (error "~A" (cloudflare-error-message (json-get body "errors"))))
  (let ((result (json-get body "result")))
    (unless (hash-table-p result)
      (error "Cloudflare Workers AI returned an unexpected response"))
    (cond
      ((json-present-p result "answers") result)
      ((not (equal (json-get result "state") "Completed"))
       (error "Cloudflare Workers AI run did not complete (state: ~A)"
              (let ((state (json-get result "state")))
                (if (stringp state) state (princ-to-string state)))))
      ((hash-table-p (json-get result "result"))
       (json-get result "result"))
      (t
       (error "Cloudflare Workers AI returned an unexpected response")))))

(defun cloudflare-detect-compat (model)
  (values
   (if (uiop:string-prefix-p
        "@cf/cloudflare/clef"
        (classifier-model-id model))
       :images
       :assets)
   nil))

(defun cloudflare-wrap-payload (model request)
  (json-object "model" (classifier-model-id model) "input" request))

(defun typesafe-detect-compat (model)
  (if (or (eq (classifier-model-provider model) :openrouter)
          (search "openrouter.ai" (classifier-model-base-url model)))
      (values :state-image-urls nil)
      (values :assets t)))

(defun typesafe-wrap-payload (model request)
  (let ((payload (copy-json-object request)))
    (setf (gethash "model" payload) (classifier-model-id model))
    payload))

(defun typesafe-system-one-output (body)
  (unless (hash-table-p body)
    (error "System One API returned an unexpected response"))
  body)

(defparameter *cloudflare-system-one-transport*
  (make-system-one-transport
   :api :cloudflare-workers-ai-system-one
   :label "Cloudflare Workers AI"
   :detect-compat #'cloudflare-detect-compat
   :endpoint "run"
   :wrap-payload #'cloudflare-wrap-payload
   :unwrap-output #'cloudflare-system-one-output))

(defparameter *typesafe-system-one-transport*
  (make-system-one-transport
   :api :typesafe-system-one
   :label "System One API"
   :detect-compat #'typesafe-detect-compat
   :endpoint "systemone"
   :wrap-payload #'typesafe-wrap-payload
   :unwrap-output #'typesafe-system-one-output))

(defun classifier-transport (api)
  (case api
    (:cloudflare-workers-ai-system-one *cloudflare-system-one-transport*)
    (:typesafe-system-one *typesafe-system-one-transport*)
    (otherwise nil)))

(defun resolved-image-form (model transport)
  (multiple-value-bind (detected-input detected-header)
      (funcall (system-one-transport-detect-compat transport) model)
    (let ((input-cell (compat-field model :image-input))
          (header-cell (compat-field model :send-image-opt-in-header)))
      (values
       (if input-cell (cdr input-cell) detected-input)
       (if header-cell (cdr header-cell) detected-header)))))

(defun classify-system-one (transport model context api-key headers environment)
  (unless (eq (classifier-model-api model)
              (system-one-transport-api transport))
    (error "Unsupported classifier API: ~A"
           (provider-wire-name (classifier-model-api model))))
  (let ((request (system-one-request context))
        (extra nil))
    (when (classifier-context-images context)
      (unless (classifier-accepts-images-p model)
        (error "~A does not support image input for ~A"
               (system-one-transport-label transport)
               (classifier-model-id model)))
      (multiple-value-bind (image-input send-header)
          (resolved-image-form model transport)
        (add-classifier-images
         (system-one-transport-label transport)
         model image-input
         (classifier-context-images context)
         request)
        (when send-header
          (setf extra
                (upsert-header
                 extra "TypeSafe-Danger-Zone-Images" "true")))))
    (dolist (pair headers)
      (setf extra (upsert-header extra (car pair) (cdr pair))))
    (let* ((base
             (materialize-cloudflare-url
              (classifier-model-base-url model)
              (environment-value environment "CLOUDFLARE_ACCOUNT_ID")
              (environment-value environment "CLOUDFLARE_GATEWAY_ID")))
           (body
             (post-classifier-json
              model
              (join-endpoint base (system-one-transport-endpoint transport))
              (funcall (system-one-transport-wrap-payload transport)
                       model request)
              (classifier-request-headers model api-key extra)
              api-key))
           (output
             (funcall (system-one-transport-unwrap-output transport) body)))
      output)))

(defun post-classifier-json (model url payload headers api-key)
  (unless (non-empty-string-p api-key)
    (error "No API key for provider: ~A"
           (provider-wire-name (classifier-model-provider model))))
  (request-json
   (make-request-spec
    :url url
    :method :post
    :headers headers
    :payload payload
    :provider (classifier-model-provider model))))

(defun classify-model
    (model context &key api-key headers environment)
  (let ((result
          (make-classifier-result
           :api (classifier-model-api model)
           :provider (classifier-model-provider model)
           :model (classifier-model-id model)
           :stop-reason :stop)))
    (handler-case
        (let ((transport
                (or (classifier-transport (classifier-model-api model))
                    (error "Unsupported classifier API: ~A"
                           (provider-wire-name
                            (classifier-model-api model))))))
          (multiple-value-bind (output)
              (classify-system-one
               transport model context api-key headers environment)
            (let ((usage
                    (parse-classifier-usage
                     (json-get output "usage") model)))
              (when usage
                (setf (classifier-result-usage result) usage)))
            (setf (classifier-result-answers result)
                  (parse-classifier-answers
                   (system-one-transport-label transport)
                   (json-get output "answers")
                   context)))
          result)
      (error (condition)
        (setf (classifier-result-stop-reason result) :error
              (classifier-result-error-message result)
              (classifier-condition-text condition))
        result))))

(defun make-cloudflare-classifier
    (id name input-price context-window image-input)
  (make-classifier-model
   :id id
   :name name
   :provider :cloudflare-workers-ai
   :api :cloudflare-workers-ai-system-one
   :base-url +cloudflare-workers-ai-rest-base-url+
   :input '(:text :image)
   :context-window context-window
   :input-price input-price
   :output-price 0d0
   :cache-read-price 0d0
   :cache-write-price 0d0
   :compat `((:image-input . ,image-input))))

(defun register-builtin-classifier-models ()
  ;; Prices and windows are Cloudflare's published Clef and Jev pages,
  ;; as pinned by pi v1.4.0 generate-models.ts.
  (dolist (row
           (list
            (make-cloudflare-classifier
             "@cf/cloudflare/clef" "Clef" 0.24d0 65536 :images)
            (make-cloudflare-classifier
             "@cf/cloudflare/clef-flash" "Clef Flash" 0.038d0 24576 :images)
            (make-cloudflare-classifier
             "@cf/cloudflare/clef-omni" "Clef Omni" 0.15d0 64000 :images)
            (make-cloudflare-classifier
             "typesafe/jev" "Jev" 0.042d0 32000 :assets)
            (make-cloudflare-classifier
             "typesafe/jev-1.14.0" "Jev 1.14" 0.042d0 32000 :assets)))
    (register-classifier-model row)))

(register-builtin-classifier-models)
