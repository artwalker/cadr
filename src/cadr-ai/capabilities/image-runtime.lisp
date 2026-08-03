(in-package #:cadr-ai)

;;; Image-provider runtime

(defstruct images-api-provider
  api generate-function source-id)

(defparameter *images-api-providers* (make-hash-table :test #'eq))

(defun register-images-api-provider (api generate-function &key source-id)
  (setf (gethash api *images-api-providers*)
        (make-images-api-provider
         :api api :generate-function generate-function :source-id source-id))
  nil)

(defun get-images-api-provider (api)
  (gethash api *images-api-providers*))

(defun clear-images-api-providers ()
  (clrhash *images-api-providers*)
  nil)

(defstruct images-provider
  id name (models nil) models-function refresh-function auth-resolver
  generate-function)

(defstruct (images-models (:constructor %make-images-models))
  (provider-table (make-hash-table :test #'eq))
  (provider-order nil)
  credential-store
  environment)

(defun make-images-models (&key credential-store environment)
  (%make-images-models
   :credential-store credential-store
   :environment environment))

(defun images-models-set-provider (runtime provider)
  (unless (gethash (images-provider-id provider) (images-models-provider-table runtime))
    (setf (images-models-provider-order runtime)
          (append (images-models-provider-order runtime)
                  (list (images-provider-id provider)))))
  (setf (gethash (images-provider-id provider) (images-models-provider-table runtime)) provider)
  provider)

(defun images-models-delete-provider (runtime id)
  (remhash id (images-models-provider-table runtime))
  (setf (images-models-provider-order runtime)
        (remove id (images-models-provider-order runtime)))
  nil)

(defun images-models-clear-providers (runtime)
  (clrhash (images-models-provider-table runtime))
  (setf (images-models-provider-order runtime) nil)
  nil)

(defun images-models-provider (runtime id)
  (gethash id (images-models-provider-table runtime)))

(defun images-models-providers (runtime)
  (loop for id in (images-models-provider-order runtime)
        collect (images-models-provider runtime id)))

(defun images-provider-current-models (provider)
  (handler-case
      (copy-list (if (images-provider-models-function provider)
                     (funcall (images-provider-models-function provider))
                     (images-provider-models provider)))
    (error () nil)))

(defun images-models-models (runtime &optional provider-id)
  (if provider-id
      (let ((provider (images-models-provider runtime provider-id)))
        (and provider (images-provider-current-models provider)))
      (loop for id in (images-models-provider-order runtime)
            append (images-provider-current-models
                    (images-models-provider runtime id)))))

(defun images-models-model (runtime provider-id model-id)
  (find model-id (images-models-models runtime provider-id)
        :key #'image-model-id :test #'string=))

(defun images-models-refresh (runtime &optional provider-id)
  (let ((providers
          (if provider-id
              (let ((provider (images-models-provider runtime provider-id)))
                (and provider (list provider)))
              (loop for id in (images-models-provider-order runtime)
                    collect (images-models-provider runtime id))))
        (errors nil))
    (dolist (provider providers)
      (when (images-provider-refresh-function provider)
        (handler-case
            (funcall (images-provider-refresh-function provider))
          (error (condition)
            (if provider-id (error condition) (push condition errors))))))
    (nreverse errors)))

(defun images-models-generate (runtime model context &rest options)
  (handler-case
      (let ((provider (images-models-provider runtime (image-model-provider model))))
        (unless provider
          (error "Unknown provider: ~A" (image-model-provider model)))
        (let ((function
                (or (images-provider-generate-function provider)
                    (let ((api (get-images-api-provider (image-model-api model))))
                      (and api (images-api-provider-generate-function api))))))
          (unless function
            (error "Unknown image API: ~A" (image-model-api model)))
          (funcall function model context options)))
    (error (condition)
      (make-assistant-images
       :api (image-model-api model)
       :provider (image-model-provider model)
       :model (image-model-id model)
       :output nil :stop-reason :error
       :error-message (princ-to-string condition)))))
