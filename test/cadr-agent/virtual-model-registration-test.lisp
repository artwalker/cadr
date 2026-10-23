(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defun registration-model (id &key (provider :faux))
  (cadr-ai:make-model
   :id id
   :name id
   :provider provider
   :api :openai-completions
   :reasoning-p t
   :thinking-level-map '((:off . :off) (:low . :low) (:high . :high))))

(defun registration-host (notes &key models)
  (cadr-agent::make-extension-host
   :cwd #P"/tmp/"
   :notify-function
   (lambda (message level)
     (push (list level message) (car notes)))
   :action-function
   (lambda (action arguments)
     (when (eq action :model-registry-find)
       (find-if
        (lambda (model)
          (and (string-equal
                (cadr-agent::virtual-model-provider-name
                 (cadr-ai:model-provider model))
                (cadr-agent::virtual-model-provider-name
                 (first arguments)))
               (string= (cadr-ai:model-id model) (second arguments))))
        models)))))

(defun registration-bundle (id)
  (cadr-agent::make-extension-bundle
   :id id
   :path (format nil "/tmp/~A.lisp" id)))

(defun registration-route (model &optional (seen nil))
  (lambda (request context)
    (let ((found
            (cadr-agent:extension-context-model-registry-find
             context "faux" (cadr-ai:model-id model))))
      (when seen
        (push (list request
                    (cadr-agent:virtual-model-route-request-reason request)
                    found)
              (car seen)))
      (cadr-agent:make-virtual-model-route
       :model (or found model)
       :thinking-level :low
       :state "phase"))))

(test define-virtual-model-queues-until-the-extension-set-is-installed
  ;; pi@4a080252f loader.ts pendingVirtualModelRegistrations and
  ;; model-runtime.ts registerVirtualModel. The factory queues. Bind
  ;; flushes. The same provider and id replaces. Blank ids and a
  ;; physical collision are reported and do not enter the catalog.
  (let ((cadr-agent::*virtual-models* (make-hash-table :test #'equal))
        (cadr-agent::*extension-virtual-models*
          (make-hash-table :test #'eq :weakness :key))
        (notes (list nil))
        (seen (list nil))
        (small (registration-model "small"))
        (large (registration-model "large")))
    (let* ((host (registration-host notes :models (list small large)))
           (bundle (registration-bundle "router"))
           (api nil))
      (cadr-agent:register-virtual-model
       :provider "kept"
       :id "auto"
       :name "Kept"
       :route (registration-route small))
      (cadr-agent::call-with-extension-load
       host bundle
       (lambda ()
         (setf api (cadr-agent:current-extension-api))
         (cadr-agent:define-virtual-model
          "router" "auto"
          :name "Auto"
          :thinking-levels '(:low :high)
          :route (registration-route small seen))
         (cadr-agent:define-virtual-model
          "router" "auto"
          :name "Auto"
          :thinking-levels '(:low :high)
          :context-window 1000
          :max-tokens 200
          :input '("text")
          :route (registration-route small seen))
         (cadr-agent:define-virtual-model
          "router" "   "
          :route (registration-route small))
         (cadr-agent:define-virtual-model
          "faux" "large"
          :name "Hidden"
          :route (registration-route small))
         (cadr-agent:extension-api-unregister-virtual-model
          (cadr-agent:current-extension-api) "kept" "auto")))
      (is (null (cadr-agent:registered-virtual-model "router" "auto")))
      (is (cadr-agent:registered-virtual-model "kept" "auto"))
      (cadr-agent::replace-extension-bundles host (list bundle))
      (is (cadr-agent:registered-virtual-model "kept" "auto"))
      (is (null (cadr-agent:registered-virtual-model "router" "   ")))
      (is (null (cadr-agent:registered-virtual-model "faux" "large")))
      (is (find-if
           (lambda (note)
             (and (eq (first note) :error)
                  (search
                   "Extension \"/tmp/router.lisp\" error: Virtual model provider and id must not be empty."
                   (second note))))
           (car notes)))
      (is (find-if
           (lambda (note)
             (and (eq (first note) :error)
                  (search
                   "Extension \"/tmp/router.lisp\" error: Virtual model faux/large conflicts with a physical model."
                   (second note))))
           (car notes)))
      (let ((virtual (cadr-agent:registered-virtual-model "router" "auto")))
        (is (eq :pi-virtual (cadr-ai:model-api virtual)))
        (is (string= "Auto" (cadr-ai::model-name virtual)))
        (is (= 1000 (cadr-ai:model-context-window virtual)))
        (is (= 200 (cadr-ai:model-max-tokens virtual)))
        (is (cadr-ai:model-reasoning-p virtual))
        (is (not (cadr-ai:model-supports-images-p virtual))))
      (let ((route
              (cadr-agent:resolve-virtual-model
               (cadr-agent:registered-virtual-model "router" "auto")
               nil
               :reason :user
               :thinking-level :high
               :state "plan"
               :has-auth-p (constantly t))))
        (is (eq small (cadr-agent:virtual-model-route-model route)))
        (is (eq :low (cadr-agent:virtual-model-route-thinking-level route)))
        (is (string= "phase" (cadr-agent:virtual-model-route-state route))))
      (is (eq small (third (first (car seen)))))
      (is (eq :user (second (first (car seen)))))
      (is (string= "plan"
                   (cadr-agent:virtual-model-route-request-state
                    (first (first (car seen))))))
      (let ((plain (registration-bundle "plain")))
        (cadr-agent::call-with-extension-load
         host plain
         (lambda ()
           (cadr-agent:define-virtual-model
            "router" "plain"
            :name "Plain"
            :route (registration-route small))))
        (cadr-agent::replace-extension-bundles host (list plain)))
      (let ((plain-model
              (cadr-agent:registered-virtual-model "router" "plain")))
        (is (not (cadr-ai:model-reasoning-p plain-model)))
        (is (cadr-ai:model-supports-images-p plain-model))
        (is (zerop (cadr-ai:model-context-window plain-model)))
        (is (zerop (cadr-ai:model-max-tokens plain-model))))
      (is (cadr-agent:registered-virtual-model "router" "auto"))
      (cadr-agent::replace-extension-bundles
       host (list (registration-bundle "empty")))
      (is (cadr-agent:registered-virtual-model "router" "auto"))
      (cadr-agent::replace-extension-bundles host (list bundle))
      (cadr-agent:extension-api-unregister-virtual-model
       api "router" "auto")
      (cadr-agent::replace-extension-bundles host (list bundle))
      (is (null (cadr-agent:registered-virtual-model "router" "auto"))))))

(test extension-api-registers-a-virtual-model-immediately-after-install
  ;; pi@4a080252f runner.ts. After bind, register and unregister hit
  ;; the catalog. A physical id throws. unregisterProvider does not
  ;; remove the virtual model.
  (let ((cadr-agent::*virtual-models* (make-hash-table :test #'equal))
        (cadr-agent::*extension-virtual-models*
          (make-hash-table :test #'eq :weakness :key))
        (notes (list nil))
        (small (registration-model "small"))
        (large (registration-model "large")))
    (let* ((host (registration-host notes :models (list small large)))
           (bundle (registration-bundle "live"))
           (api nil))
      (cadr-agent::call-with-extension-load
       host bundle
       (lambda ()
         (setf api (cadr-agent:current-extension-api))
         (cadr-agent:define-provider
          (cadr-ai:make-provider-definition
           :id :faux :name "Faux" :protocol :openai-completions)
          :models nil)))
      (cadr-agent::replace-extension-bundles host (list bundle))
      (is (null (car notes)))
      (cadr-agent:extension-api-register-virtual-model
       api "router" "late"
       :name "Late"
       :route (registration-route small))
      (is (cadr-agent:registered-virtual-model "router" "late"))
      (is (search
           "Virtual model faux/large conflicts with a physical model."
           (handler-case
               (progn
                 (cadr-agent:extension-api-register-virtual-model
                  api "faux" "large"
                  :name "Nope"
                  :route (registration-route small))
                 "")
             (error (condition) (princ-to-string condition)))))
      (is (null (car notes)))
      (is (null (cadr-agent:registered-virtual-model "faux" "large")))
      (setf (cadr-agent::extension-bundle-providers bundle) nil)
      (cadr-agent::replace-extension-bundles host (list bundle))
      (is (cadr-agent:registered-virtual-model "router" "late"))
      (let ((context
              (cadr-agent::%make-extension-context
               :host host
               :bundle bundle
               :source-path "/tmp/live.lisp"
               :kind :provider)))
        (cadr-agent:extension-context-unregister-virtual-model
         context "router" "late")
        (setf (cadr-agent::%extension-context-active-p context) nil))
      (is (null (cadr-agent:registered-virtual-model "router" "late"))))))

(test virtual-model-direct-request-drops-state-and-carries-abort
  ;; pi@4a080252f docs/virtual-models.md. direct has no state. The
  ;; route sees the request abort signal.
  (let ((cadr-agent::*virtual-models* (make-hash-table :test #'equal))
        (seen nil)
        (physical (registration-model "gpt" :provider :openai)))
    (cadr-agent:register-virtual-model
     :provider :openai
     :id "router"
     :name "Router"
     :route
     (lambda (request)
       (push request seen)
       (cadr-agent:make-virtual-model-route
        :model physical
        :thinking-level :off
        :state "ignored")))
    (cadr-agent:resolve-virtual-model
     (cadr-agent:registered-virtual-model :openai "router")
     nil
     :reason :direct
     :state "plan"
     :has-auth-p (constantly t))
    (is (null (cadr-agent:virtual-model-route-request-state (first seen))))
    (let ((agent
            (cadr-agent:make-agent
             :provider :openai
             :model (cadr-agent:registered-virtual-model :openai "router"))))
      (cadr-agent:agent-abort agent)
      (cadr-agent::agent-stream-target agent nil :reason :direct)
      (is (cadr-agent:extension-cancellation-aborted-p
           (cadr-agent:virtual-model-route-request-signal (first seen))))
      (is (null
           (cadr-agent:virtual-model-route-request-state (first seen)))))))
