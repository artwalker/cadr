(in-package #:cadr-ai)

(defparameter +default-radius-gateway+ "https://radius.pi.dev")

(defparameter *radius-public-models*
  (mapcar
   (lambda (row)
     (model-from-metadata (apply #'make-model-metadata row)))
   *radius-public-model-metadata*))

(defun radius-default-gateway-p (gateway)
  (string=
   (normalize-radius-gateway gateway)
   (normalize-radius-gateway +default-radius-gateway+)))

(defun radius-baseline-models (provider-id gateway)
  (when (radius-default-gateway-p gateway)
    (mapcar
     (lambda (model)
       (let ((copy (copy-structure model)))
         (setf (model-provider copy) provider-id)
         copy))
     *radius-public-models*)))

(defun merge-radius-models (baseline dynamic)
  (let ((merged (copy-list baseline)))
    (dolist (model dynamic merged)
      (let ((index
              (position (model-id model) merged
                        :key #'model-id :test #'string=)))
        (if index
            (setf (nth index merged) model)
            (setf merged (nconc merged (list model))))))))

(defun radius-models-from-metadata-list (entries)
  (mapcar #'model-from-metadata entries))

(defun radius-credential-gateway-config (credential)
  (when (typep credential 'oauth-credential)
    (cdr (assoc "gatewayConfig"
                (oauth-credential-metadata credential)
                :test #'string=))))

(defun radius-models-from-credential (provider-id credential)
  (let ((config (radius-credential-gateway-config credential)))
    (if (hash-table-p config)
        (radius-models-from-metadata-list
         (radius-models-from-config provider-id config))
        nil)))

(defun radius-refresh-api-key (credential)
  (cond
    ((typep credential 'oauth-credential)
     (oauth-credential-access credential))
    ((typep credential 'api-key-credential)
     (api-key-credential-key credential))
    (t nil)))

(defun truncate-radius-http-body (body)
  (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) body)))
    (if (> (length trimmed) 512)
        (concatenate 'string (subseq trimmed 0 512) "...")
        trimmed)))

(defun load-radius-gateway-config
    (gateway &optional api-key abort-p)
  (let* ((normalized (normalize-radius-gateway gateway))
         (url (format nil "~A/v1/config" normalized))
         (headers
           (append
            '(("accept" . "application/json"))
            (when (non-empty-string-p api-key)
              (list
               (cons "authorization"
                     (format nil "Bearer ~A" api-key))))))
         (request
           (make-request-spec
            :url url
            :method :get
            :headers headers
            :provider :radius)))
    (multiple-value-bind (config status)
        (handler-case
            (request-json request :abort-p abort-p)
          (api-error (cause)
            (error
             'configuration-error
             :message
             (format
              nil
              "Could not load Radius config from ~A: ~A: ~A"
              normalized
              (api-error-status cause)
              (truncate-radius-http-body
               (or (cadr-error-message cause) ""))))))
      (declare (ignore status))
      (unless (and (hash-table-p config)
                   (non-empty-string-p (json-get config "baseUrl"))
                   (vectorp (json-get config "models")))
        (error 'configuration-error
               :message
               (format nil "Invalid Radius config from ~A" normalized)))
      config)))

(defun radius-stored-models-p (provider-id value)
  (and (listp value)
       (every
        (lambda (model)
          (and (typep model 'model)
               (eq provider-id (model-provider model))
               (eq :pi-messages (model-api model))))
        value)))

(defun make-radius-runtime-provider-parts
    (definition environment radius-gateway)
  (declare (ignore environment))
  (let* ((provider-id (provider-definition-id definition))
         (baseline (radius-baseline-models provider-id radius-gateway))
         (dynamic nil))
    (list
     :models-function
     (lambda ()
       (merge-radius-models baseline dynamic))
     :refresh-context-function
     (lambda (context)
       (let* ((store (runtime-refresh-context-store context))
              (credential
                (runtime-refresh-context-credential context))
              (stored (funcall store :read)))
         (when (radius-stored-models-p provider-id stored)
           (setf dynamic (copy-list stored)))
         (when (and (null stored)
                    (typep credential 'oauth-credential))
           (let ((legacy
                   (radius-models-from-credential
                    provider-id credential)))
             (when legacy
               (setf dynamic legacy)
               (unless (runtime-refresh-context-aborted-p context)
                 (funcall store :write (copy-list dynamic))))))
         (unless
             (or (not (runtime-refresh-context-allow-network-p context))
                 (runtime-refresh-context-aborted-p context))
           (let* ((api-key (radius-refresh-api-key credential))
                  (config
                    (load-radius-gateway-config
                     radius-gateway
                     api-key
                     (runtime-refresh-context-abort-p context)))
                  (refreshed
                    (radius-models-from-metadata-list
                     (radius-models-from-config
                      provider-id config))))
             (unless (runtime-refresh-context-aborted-p context)
               (setf dynamic refreshed)
               (funcall store :write (copy-list dynamic))))))))))
