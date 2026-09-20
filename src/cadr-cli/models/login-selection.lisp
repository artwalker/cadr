(in-package #:cadr-cli)

;;; Post-login model selection. Baseline interactive-mode.ts
;;; completeProviderAuthentication (ecac0a9c4:5424-5445) has four
;;; failure branches plus success. cadr used to collapse the first two
;;; into :no-default-model, so xAI (which has default-model grok-4.5)
;;; printed "no default model is configured" when the snapshot was empty.

(defun provider-default-model-id (provider)
  (let ((definition (gethash provider cadr-ai::*provider-definitions*)))
    (and definition
         (let ((id (cadr-ai:provider-definition-default-model definition)))
           (and (stringp id) (plusp (length id)) id)))))

(defun classify-post-login-model (provider available-models)
  "Return (values model kind extra). KIND is NIL on success."
  (let* ((default-id (provider-default-model-id provider))
         (provider-models
           (remove provider available-models
                   :test-not #'eq
                   :key #'cadr-ai:model-provider)))
    (cond
      ((null default-id)
       (values nil :no-default-model nil))
      ((null provider-models)
       (values nil :no-models-available nil))
      (t
       (let ((model
               (find default-id provider-models
                     :key #'cadr-ai:model-id
                     :test #'string=)))
         (if model
             (values model nil nil)
             (values nil :default-model-unavailable default-id)))))))

(defun post-login-selection-error
    (action-label display-name provider-id kind extra)
  (ecase kind
    (:no-default-model
     (format
      nil
      "~A ~A, but no default model is configured for provider \"~(~A~)\". Use /model to select a model."
      action-label display-name provider-id))
    (:no-models-available
     (format
      nil
      "~A ~A, but no models are available for that provider. Use /model to select a model."
      action-label display-name))
    (:default-model-unavailable
     (format
      nil
      "~A ~A, but its default model \"~A\" is not available. Use /model to select a model."
      action-label display-name extra))
    (:select-failed
     (format
      nil
      "~A ~A, but selecting its default model failed: ~A. Use /model to select a model."
      action-label display-name extra))))

(defun post-login-selection-result (provider available-models select-function)
  "SELECT-FUNCTION is called with the chosen model. Returns a model id
   string or (KIND EXTRA) for the login-status consumers."
  (multiple-value-bind (model kind extra)
      (classify-post-login-model provider available-models)
    (if (null kind)
        (handler-case
            (progn
              (funcall select-function model)
              (cadr-ai:model-id model))
          (error (condition)
            (list :select-failed
                  (if (typep condition 'cadr-ai:cadr-error)
                      (cadr-ai:cadr-error-message condition)
                      (princ-to-string condition)))))
        (list kind extra))))
