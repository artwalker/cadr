(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal24-model-registry-stream-host (registry)
  (cadr-agent::make-extension-host
   :cwd #P"/tmp/"
   :mode :print
   :action-function
   (lambda (action arguments)
     (case action
       (:model-registry-find
        (cadr-cli:model-registry-find
         registry (first arguments) (second arguments)))
       (:model-registry-resolve-auth
        (cadr-cli::provider-config-for-model
         registry (first arguments)
         :allow-missing-auth-p nil))
       (:model-registry-stream
        (apply #'cadr-cli:model-registry-stream
               registry arguments))
       (:model-registry-stream-simple
        (apply #'cadr-cli:model-registry-stream
               registry
               (append arguments '(:simple-p t))))
       (otherwise
        (error 'cadr-agent:extension-execution-error
               :message
               (format nil "Unsupported extension action: ~(~A~)"
                       action)))))))

(defun goal24-drain-stream-text (stream)
  (let ((text ""))
    (loop
      (multiple-value-bind (event done-p)
          (cadr-ai:event-stream-next stream)
        (when done-p (return))
        (when (and event
                   (eq :text-delta
                       (cadr-ai:stream-event-type event)))
          (setf text
                (concatenate
                 'string text
                 (or (cadr-ai:stream-event-delta event)
                     ""))))))
    text))

(defun goal24-assert-extension-provider-stream (method)
  (let* ((received-api-key nil)
         (handle
           (cadr-ai:make-faux-provider
            :api :issue-8964-extension-api
            :provider-id :extension-provider
            :model-definitions
            '((:id "faux-1" :name "Faux 8964" :reasoning-p nil))))
         (runtime (cadr-ai:make-models-runtime))
         (registry
           (cadr-cli::%make-model-registry
            :path nil
            :credentials nil
            :native-runtime runtime))
         (host (goal24-model-registry-stream-host registry))
         (bundle
           (cadr-agent::make-extension-bundle
            :id "goal24-8964"
            :path "/tmp/goal24-8964/"))
         (context
           (cadr-agent::%make-extension-context
            :host host
            :bundle bundle
            :kind :command
            :source-path #P"/tmp/goal24-8964/"))
         (model (cadr-ai:faux-get-model handle)))
    (cadr-ai:models-runtime-set-provider
     runtime (cadr-ai:faux-handle-provider handle))
    (cadr-cli::merge-native-runtime-models registry)
    (cadr-ai:credential-store-modify
     (cadr-ai::models-runtime-credential-store runtime)
     :extension-provider
     (lambda (old)
       (declare (ignore old))
       (cadr-ai:make-api-key-credential
        :provider :extension-provider
        :key "extension-key")))
    (cadr-ai:faux-set-responses
     handle
     (list
      (lambda (stream-context options state model-arg)
        (declare (ignore stream-context state model-arg))
        (setf received-api-key (getf options :api-key))
        (cadr-ai:faux-assistant-message
         "custom provider response"))))
    (let* ((found
             (cadr-agent:extension-context-model-registry-find
              context :extension-provider "faux-1"))
           (stream-context
             (cadr-ai:make-context
              :messages
              (list
               (cadr-ai:make-user-message
                :content "Hello"))))
           (stream
             (ecase method
               (:stream
                (cadr-agent:extension-context-model-registry-stream
                 context found stream-context))
               (:stream-simple
                (cadr-agent:extension-context-model-registry-stream-simple
                 context found stream-context))))
           (streamed-text (goal24-drain-stream-text stream))
           (result (cadr-ai:event-stream-result stream)))
      (is (eq model found))
      (is (string= "extension-key" received-api-key))
      (is (string= "custom provider response" streamed-text))
      (is (eq :stop (cadr-ai:assistant-message-stop-reason result)))
      (is (string=
           "custom provider response"
           (cadr-ai:text-content-text
            (first
             (cadr-ai:assistant-message-content result))))))))

(test goal24-extension-model-registry-stream-passes-api-key
  ;; Baseline #8964: ctx.modelRegistry.stream resolves registerProvider
  ;; apiKey and streams text_delta / final assistant message.
  (goal24-assert-extension-provider-stream :stream))

(test goal24-extension-model-registry-stream-simple-passes-api-key
  ;; Baseline #8964 streamSimple shares the same runtime stream + auth
  ;; path as stream (cadr has one models-runtime-stream entry).
  (goal24-assert-extension-provider-stream :stream-simple))
