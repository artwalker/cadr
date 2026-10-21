(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defun virtual-model-physical ()
  (cadr-ai:make-model
   :id "gpt"
   :name "gpt"
   :provider :openai
   :api :openai-completions
   :reasoning-p t
   :thinking-level-map
   '((:off . :off)
     (:minimal . nil)
     (:low . :low)
     (:medium . nil)
     (:high . nil)
     (:xhigh . nil)
     (:max . nil))))

(test virtual-model-routes-one-request-and-holds-the-selection
  ;; pi@71023aec1 virtual-models.ts. The selected model stays virtual.
  ;; The provider call sees the physical model the router returned.
  (let ((cadr-agent::*virtual-models*
          (make-hash-table :test #'equal))
        (reasons nil)
        (physical (virtual-model-physical)))
    (let ((virtual
            (cadr-agent:register-virtual-model
             :provider :openai
             :id "router"
             :name "Router"
             :context-window 0
             :max-tokens 0
             :thinking-levels '(:off :low)
             :route
             (lambda (request)
               (push (cadr-agent:virtual-model-route-request-reason
                      request)
                     reasons)
               (cadr-agent:make-virtual-model-route
                :model physical
                :thinking-level :max
                :state "s1")))))
      (is (eq :pi-virtual (cadr-ai:model-api virtual)))
      (is (zerop (cadr-ai:model-context-window virtual)))
      (is (zerop (cadr-ai:model-max-tokens virtual)))
      (is (search
           "conflicts"
           (handler-case
               (progn
                 (cadr-agent:register-virtual-model
                  :provider :openai
                  :id "router"
                  :route (lambda (request) (declare (ignore request)))
                  :physical-model physical)
                 "")
             (error (condition) (princ-to-string condition)))))
      (let* ((session
               (cadr-agent::create-session
                :persist-p nil :id "virtual-route"))
             (seen nil)
             (agent
               (cadr-agent:make-agent
                :provider :openai
                :model virtual
                :session session
                :messages
                (list (cadr-ai:make-user-message :content "hi"))
                :stream-function
                (lambda (provider model context callback
                         &key &allow-other-keys)
                  (declare (ignore provider context callback))
                  (push (cadr-ai:model-id model) seen)
                  (cadr-ai:make-assistant-message
                   :api (cadr-ai:model-api model)
                   :provider (cadr-ai:model-provider model)
                   :model (cadr-ai:model-id model)
                   :stop-reason :stop
                   :content
                   (list (cadr-ai:make-text-content :text "ok")))))))
        (cadr-agent:agent-set-model agent virtual)
        (let ((message (cadr-agent::stream-assistant agent)))
          (is (string= "gpt" (cadr-ai:assistant-message-model message)))
          (is (eq :openai
                  (cadr-ai:assistant-message-provider message)))
          (is (eq virtual (cadr-agent:agent-model agent)))
          (is (equal '("gpt") seen))
          (is (eq :user (first reasons)))
          (is (string= "s1"
                       (cadr-agent:virtual-model-state
                        (cadr-agent::session-path-entries session)
                        :openai "router"))))
        (cadr-agent::session-append-message
         session
         (cadr-ai:make-assistant-message
          :provider :openai
          :api :openai-completions
          :model "gpt"
          :stop-reason :stop
          :content (list (cadr-ai:make-text-content :text "ok"))))
        (let ((held
                (cadr-agent:branch-selection
                 (cadr-agent::session-path-entries session)
                 (lambda (provider id)
                   (cadr-agent:registered-virtual-model
                    provider id)))))
          (is (string= "router"
                       (cadr-agent:branch-selection-model-id held))))
        (cadr-agent:unregister-virtual-model :openai "router")
        (let ((held
                (cadr-agent:branch-selection
                 (cadr-agent::session-path-entries session)
                 (lambda (provider id)
                   (cadr-agent:registered-virtual-model
                    provider id)))))
          (is (string= "gpt"
                       (cadr-agent:branch-selection-model-id held))))))
    (is (search
         "not registered"
         (handler-case
             (progn
               (cadr-agent:resolve-virtual-model
                (cadr-agent:create-virtual-model
                 :provider :openai :id "missing")
                nil)
               "")
           (error (condition) (princ-to-string condition)))))
    (let ((virtual
            (cadr-agent:register-virtual-model
             :provider :openai
             :id "again"
             :route
             (lambda (request)
               (declare (ignore request))
               (cadr-agent:make-virtual-model-route
                :model
                (cadr-agent:create-virtual-model
                 :provider :openai :id "still-virtual")
                :thinking-level :off)))))
      (is (search
           "not a physical model"
           (handler-case
               (progn
                 (cadr-agent:resolve-virtual-model virtual nil)
                 "")
             (error (condition) (princ-to-string condition))))))
    (let ((virtual
            (cadr-agent:register-virtual-model
             :provider :openai
             :id "locked"
             :route
             (lambda (request)
               (declare (ignore request))
               (cadr-agent:make-virtual-model-route
                :model (virtual-model-physical)
                :thinking-level :low)))))
      (is (search
           "no credentials"
           (handler-case
               (progn
                 (cadr-agent:resolve-virtual-model
                  virtual nil
                  :has-auth-p (constantly nil))
                 "")
             (error (condition) (princ-to-string condition)))))
      (let ((route
              (cadr-agent:resolve-virtual-model
               virtual nil
               :thinking-level :max
               :has-auth-p (constantly t))))
        (is (eq :low
                (cadr-agent:virtual-model-route-thinking-level
                 route)))))
    (is (search
         "must be routed"
         (handler-case
             (progn
               (cadr-ai:stream-chat
                nil
                (cadr-agent:create-virtual-model
                 :provider :openai :id "bare")
                (cadr-ai:make-context)
                (lambda (event) (declare (ignore event))))
               "")
           (error (condition) (princ-to-string condition)))))))
