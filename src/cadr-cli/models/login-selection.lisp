(in-package #:cadr-cli)

;;; Post-login model selection. Baseline interactive-mode.ts
;;; completeProviderAuthentication (71023aec1:5424-5445) has four
;;; failure branches plus success. Radius uses the first provider model
;;; when the configured default is absent. An empty or missing-default
;;; catalog defers once for an authenticated refresh before erroring.
;;; cadr used to collapse the first two into :no-default-model, so xAI
;;; (which has default-model grok-4.5) printed "no default model is
;;; configured" when the snapshot was empty.

(defun provider-default-model-id (provider)
  (let ((definition (gethash provider cadr-ai::*provider-definitions*)))
    (and definition
         (let ((id (cadr-ai:provider-definition-default-model definition)))
           (and (stringp id) (plusp (length id)) id)))))

(defun radius-post-login-provider-p (provider)
  (or (eq provider :radius)
      (and (symbolp provider)
           (string-equal (symbol-name provider) "RADIUS"))
      (and (stringp provider)
           (string-equal provider "radius"))))

(defun post-login-provider-key (provider)
  (if (radius-post-login-provider-p provider)
      :radius
      provider))

(defun catalog-incomplete-post-login-kind-p (kind)
  (member kind '(:no-models-available :default-model-unavailable)))

(defun classify-post-login-model (provider available-models)
  "Return (values model kind extra). KIND is NIL on success."
  (let* ((provider-key (post-login-provider-key provider))
         (default-id (provider-default-model-id provider-key))
         (provider-models
           (remove provider-key available-models
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
         (cond
           (model
            (values model nil nil))
           ((radius-post-login-provider-p provider-key)
            (values (first provider-models) nil nil))
           (t
            (values nil :default-model-unavailable default-id))))))))

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

(defun post-login-selection-result
    (provider available-models select-function
     &key refresh-models-function model-unchanged-p)
  "SELECT-FUNCTION is called with the chosen model. Returns a model id
   string or (KIND EXTRA) for the login-status consumers.

   When classification fails only because the catalog snapshot is
   incomplete (:NO-MODELS-AVAILABLE or :DEFAULT-MODEL-UNAVAILABLE) and
   REFRESH-MODELS-FUNCTION is supplied, call it once with PROVIDER,
   then re-classify on the returned list. MODEL-UNCHANGED-P, when
   supplied, must return true to allow that second selection. The
   session model must still be the model captured before the refresh."
  (labels ((apply-selection (models)
             (multiple-value-bind (model kind extra)
                 (classify-post-login-model provider models)
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
                   (list kind extra)))))
    (let ((first (apply-selection available-models)))
      (if (and (consp first)
               (catalog-incomplete-post-login-kind-p (first first))
               refresh-models-function)
          (let ((refreshed (funcall refresh-models-function provider)))
            (if (or (null model-unchanged-p)
                    (funcall model-unchanged-p))
                (apply-selection (or refreshed '()))
                nil))
          first))))
