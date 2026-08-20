(in-package #:cadr-cli)

(defparameter +default-llama-server-url+
  "http://127.0.0.1:8080")

(defstruct llama-model-info
  (id "" :type string)
  (status :unloaded :type keyword)
  (arguments nil :type list)
  (input-modalities nil :type list)
  context-window
  training-context-window
  (failed-p nil :type boolean)
  exit-code
  progress)

(defstruct (llama-client
            (:constructor %make-llama-client))
  (server-url +default-llama-server-url+
              :type string)
  api-key)

(cadr-core:define-redacted-print-object (llama-client value stream)
  (format stream ":server-url ~A :api-key [REDACTED]"
          (llama-client-server-url value)))

(defun trim-trailing-slashes (value)
  (string-right-trim '(#\/) value))

(defun normalize-llama-server-url (value)
  (unless (stringp value)
    (error
     'cadr-ai:configuration-error
     :message "llama.cpp server URL must be a string"))
  (let* ((trimmed
           (string-trim
            '(#\Space #\Tab #\Newline #\Return)
            value))
         (scheme-end (search "://" trimmed))
         (scheme
           (and scheme-end
                (string-downcase
                 (subseq trimmed 0 scheme-end)))))
    (unless (member scheme '("http" "https")
                    :test #'string=)
      (error
       'cadr-ai:configuration-error
       :message
       "llama.cpp server URL must use http or https"))
    (let* ((without-fragment
             (subseq
              trimmed 0
              (or (position #\# trimmed)
                  (length trimmed))))
           (without-query
             (subseq
              without-fragment 0
              (or (position #\? without-fragment)
                  (length without-fragment))))
           (without-slash
             (trim-trailing-slashes without-query))
           (without-v1
             (if
                 (and
                  (>= (length without-slash) 3)
                  (string-equal
                   "/v1" without-slash
                   :start2 (- (length without-slash) 3)))
                 (subseq without-slash
                         0 (- (length without-slash) 3))
                 without-slash))
           (result
             (trim-trailing-slashes without-v1)))
      (when
          (or
           (null scheme-end)
           (<= (length result) (+ scheme-end 3)))
        (error
         'cadr-ai:configuration-error
         :message "llama.cpp server URL has no host"))
      result)))

(defun llama-inference-url (server-url)
  (format nil "~A/v1"
          (normalize-llama-server-url server-url)))

(defun make-llama-client
    (&key
       (server-url +default-llama-server-url+)
       api-key)
  (%make-llama-client
   :server-url
   (normalize-llama-server-url server-url)
   :api-key api-key))

(defun llama-client-headers (client body-p)
  (append
   (and body-p
        '(("Content-Type" . "application/json")))
   (and
    (llama-client-api-key client)
    (plusp
     (length (llama-client-api-key client)))
    (list
     (cons
      "Authorization"
      (format nil "Bearer ~A"
              (llama-client-api-key client)))))))

(defun llama-request-json
    (client path &key (method :get) payload)
  (cadr-ai:request-json
   (cadr-ai::make-request-spec
    :url
    (format nil "~A~A"
            (llama-client-server-url client)
            path)
    :method method
    :headers
    (llama-client-headers client
                          (not (null payload)))
    :payload
    (or payload (cadr-ai::json-object))
    :provider :llama.cpp)
   :read-timeout 15))

(defun valid-llama-status (value)
  (find
   value
   '("unloaded" "loading" "loaded"
     "downloading" "sleeping" "missing")
   :test #'string=))

(defun json-number-or-nil (value)
  (and (numberp value) value))

(defun json-string-vector-list (value)
  (and
   (vectorp value)
   (loop for entry across value
         when (stringp entry)
           collect entry)))

(defun parse-llama-model-info (object)
  (unless (hash-table-p object)
    (error
     'cadr-ai:transport-error
     :message "llama.cpp returned an invalid model catalog"))
  (let* ((id (cadr-ai::json-get object "id"))
         (status-object
           (cadr-ai::json-get object "status"))
         (status
           (and
            (hash-table-p status-object)
            (cadr-ai::json-get status-object "value")))
         (architecture
           (cadr-ai::json-get object "architecture"))
         (metadata
           (cadr-ai::json-get object "meta")))
    (unless
        (and
         (stringp id)
         (stringp status)
         (valid-llama-status status))
      (error
       'cadr-ai:transport-error
       :message
       "Server is not running in llama.cpp router mode"))
    (make-llama-model-info
     :id id
     :status
     (intern (string-upcase status) :keyword)
     :arguments
     (or
      (json-string-vector-list
       (cadr-ai::json-get status-object "args"))
      nil)
     :input-modalities
     (or
      (and
       (hash-table-p architecture)
       (json-string-vector-list
        (cadr-ai::json-get
         architecture "input_modalities")))
      nil)
     :context-window
     (and
      (hash-table-p metadata)
      (json-number-or-nil
       (cadr-ai::json-get metadata "n_ctx")))
     :training-context-window
     (and
      (hash-table-p metadata)
      (json-number-or-nil
       (cadr-ai::json-get metadata "n_ctx_train")))
     :failed-p
     (eq t
         (cadr-ai::json-get status-object "failed"))
     :exit-code
     (json-number-or-nil
      (cadr-ai::json-get status-object
                         "exit_code"))
     :progress
     (cadr-ai::json-get status-object
                        "progress"))))

(defun llama-client-list
    (client &key reload-p)
  (let* ((payload
           (llama-request-json
            client
            (if reload-p
                "/models?reload=1"
                "/models")))
         (data
           (and
            (hash-table-p payload)
            (cadr-ai::json-get payload "data"))))
    (unless (vectorp data)
      (error
       'cadr-ai:transport-error
       :message
       "llama.cpp returned an invalid model catalog"))
    (loop for model across data
          collect
          (parse-llama-model-info model))))

(defun llama-client-model-action
    (client path model)
  (llama-request-json
   client path
   :method :post
   :payload
   (cadr-ai::json-object "model" model))
  nil)

(defun llama-client-load (client model)
  (llama-client-model-action
   client "/models/load" model))

(defun llama-client-unload (client model)
  (llama-client-model-action
   client "/models/unload" model))

(defun llama-client-download (client model)
  (llama-client-model-action
   client "/models" model))

(defun format-llama-bytes (bytes)
  (if (< bytes 1024)
      (format nil "~D B" bytes)
      (let ((units '("KiB" "MiB" "GiB" "TiB"))
            (value (/ bytes 1024.0d0))
            (unit "KiB"))
        (dolist (candidate units)
          (setf unit candidate)
          (when (< value 1024.0d0)
            (return))
          (unless (string= candidate "TiB")
            (setf value (/ value 1024.0d0))))
        (format nil
                (if (>= value 10.0d0)
                    "~,1F ~A"
                    "~,2F ~A")
                value unit))))

(defun bounded-ratio (value)
  (and
   (numberp value)
   (max 0.0d0
        (min 1.0d0
             (coerce value 'double-float)))))

(defun llama-load-progress (data)
  (let* ((progress
           (and
            (hash-table-p data)
            (cadr-ai::json-get data "progress")))
         (stage
           (and
            (hash-table-p progress)
            (or
             (cadr-ai::json-get progress "current")
             (cadr-ai::json-get progress "stage"))))
         (stages
           (and
            (hash-table-p progress)
            (cadr-ai::json-get progress "stages")))
         (stage-ratio
           (and
            (hash-table-p progress)
            (bounded-ratio
             (cadr-ai::json-get progress "value"))))
         (ratio stage-ratio))
    (when
        (and
         (stringp stage)
         (vectorp stages))
      (let ((position
              (position stage stages
                        :test #'string=)))
        (when position
          (setf
           ratio
           (/ (+ position
                 (or stage-ratio 0.0d0))
              (length stages))))))
    (and
     (or stage ratio)
     (list
      :message
      (if (stringp stage)
          (format
           nil "Loading ~A"
           (substitute #\Space #\_ stage))
          "Loading model")
      :ratio ratio))))

(defun llama-download-progress (data)
  (let* ((nested
           (and
            (hash-table-p data)
            (cadr-ai::json-get data "progress")))
         (files
           (if (hash-table-p nested)
               nested data))
         (done 0)
         (total 0))
    (when (hash-table-p files)
      (maphash
       (lambda (name value)
         (declare (ignore name))
         (when (hash-table-p value)
           (let ((entry-done
                   (cadr-ai::json-get value "done"))
                 (entry-total
                   (cadr-ai::json-get value "total")))
             (when (and (numberp entry-done)
                        (numberp entry-total))
               (incf done entry-done)
               (incf total entry-total)))))
       files))
    (and
     (plusp total)
     (list
      :message "Downloading model"
      :ratio
      (coerce (/ done total) 'double-float)
      :detail
      (format nil "~A / ~A"
              (format-llama-bytes done)
              (format-llama-bytes total))))))

(defun llama-watch-operation
    (client model operation on-progress)
  (catch 'llama-operation-finished
    (cadr-ai:request-sse
     (cadr-ai::make-request-spec
      :url
      (format nil "~A/models/sse"
              (llama-client-server-url client))
      :method :get
      :headers
      (llama-client-headers client nil)
      :provider :llama.cpp
      :stream-p t)
     (lambda (event)
       (handler-case
           (let* ((payload
                    (cadr-ai::parse-json
                     (cadr-ai:sse-event-data event)))
                  (event-model
                    (and
                     (hash-table-p payload)
                     (cadr-ai::json-get payload "model")))
                  (event-name
                    (and
                     (hash-table-p payload)
                     (cadr-ai::json-get payload "event")))
                  (data
                    (and
                     (hash-table-p payload)
                     (cadr-ai::json-get payload "data"))))
             (when (and (stringp event-model)
                        (string= event-model model)
                        (stringp event-name))
               (let ((progress
                       (case operation
                         (:load
                          (llama-load-progress data))
                         (:download
                          (llama-download-progress
                           data)))))
                 (when (and progress on-progress)
                   (funcall on-progress progress)))
               (when
                   (case operation
                     (:load
                      (and
                       (member
                        event-name
                        '("model_status"
                          "status_change")
                        :test #'string=)
                       (member
                        (cadr-ai::json-get
                         data "status")
                        '("loaded" "unloaded")
                        :test #'string=)))
                     (:download
                      (member
                       event-name
                       '("download_finished"
                         "download_failed")
                       :test #'string=)))
                 (throw
                  'llama-operation-finished
                  event-name))))
         (condition () nil))))))

(defun llama-client-load-and-wait
    (client model on-progress)
  (llama-client-load client model)
  (when on-progress
    (funcall on-progress
             '(:message "Loading model")))
  (llama-watch-operation
   client model :load on-progress)
  (let ((entry
          (find
           model
           (llama-client-list client)
           :key #'llama-model-info-id
           :test #'string=)))
    (unless entry
      (error
       'cadr-ai:transport-error
       :message
       (format nil
               "llama.cpp did not return model ~A"
               model)))
    (when
        (or
         (llama-model-info-failed-p entry)
         (not
          (eq :loaded
              (llama-model-info-status entry))))
      (error
       'cadr-ai:transport-error
       :message
       (if (llama-model-info-exit-code entry)
           (format nil
                   "Model exited with code ~D"
                   (llama-model-info-exit-code
                    entry))
           "Model failed to load")))
    entry))

(defun llama-client-download-and-wait
    (client model on-progress)
  (llama-client-download client model)
  (when on-progress
    (funcall on-progress
             '(:message "Downloading model")))
  (let ((terminal
          (llama-watch-operation
           client model :download on-progress)))
    (when (string= terminal "download_failed")
      (error
       'cadr-ai:transport-error
       :message "Model download failed")))
  (llama-client-list client :reload-p t))
