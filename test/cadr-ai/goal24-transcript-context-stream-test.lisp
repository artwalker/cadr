(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(defclass goal24-recording-provider (cadr-ai::provider)
  ((seen-context
    :initform nil
    :accessor goal24-seen-context)))

(defmethod cadr-ai:build-request :around
    ((provider goal24-recording-provider) model context &rest args)
  (setf (goal24-seen-context provider) context)
  (apply #'call-next-method provider model context args))

(defmethod cadr-ai:build-request
    ((provider goal24-recording-provider) model context
     &key stream-p &allow-other-keys)
  (declare (ignore model context))
  (cadr-ai::make-request-spec
   :url "https://example.test/v1/chat"
   :method :post
   :headers '(("content-type" . "application/json"))
   :payload (cadr-ai::json-object "ok" t)
   :stream-p (and stream-p t)
   :provider (or (cadr-ai::provider-id provider) :openai)))

(defmethod cadr-ai::try-provider-websocket-stream
    ((provider goal24-recording-provider) model context request state emit
     &key &allow-other-keys)
  (declare (ignore context request))
  (let ((message (cadr-ai::empty-assistant-message model)))
    (setf (cadr-ai:assistant-message-stop-reason message) :stop)
    (cadr-ai::emit-event emit :start message)
    (cadr-ai::emit-event emit :done message :reason :stop)
    (setf (cadr-ai::provider-stream-state-message state) message)
    (values t message)))

(defmethod cadr-ai:parse-complete-response
    ((provider goal24-recording-provider) model response)
  (declare (ignore provider response))
  (let ((message (cadr-ai::empty-assistant-message model)))
    (setf (cadr-ai:assistant-message-stop-reason message) :stop)
    message))

(test goal24-normalize-context-yields-messages-only-transcript
  ;; Baseline packages/ai/src/utils/transcript.ts normalizeContext and
  ;; packages/agent/test/agent-loop.test.ts
  ;; "should build provider context exclusively from transcript messages".
  (let* ((tool
           (make-tool
            :name "read"
            :description "Read a file."
            :parameters (sample-schema)))
         (user (make-user-message :content "Hello" :timestamp 1))
         (transcript
           (cadr-ai:normalize-context
            (make-context
             :system-prompt "Transcript prompt"
             :messages (list user)
             :tools (list tool)))))
    (is (typep transcript 'cadr-ai:transcript-context))
    (is (not (typep transcript 'cadr-ai:context)))
    (let ((messages (cadr-ai:transcript-context-messages transcript)))
      (is (= 2 (length messages)))
      (is (typep (first messages) 'cadr-ai:system-message))
      (is (string= "Transcript prompt"
                   (cadr-ai:system-message-content (first messages))))
      (is (eq tool
              (first (cadr-ai:system-message-tools-added
                      (first messages)))))
      (is (eq user (second messages))))))

(test goal24-stream-and-complete-normalize-context-to-transcript
  (let* ((provider
           (make-instance 'goal24-recording-provider
                          :api-key "test-key"
                          :provider-id :openai
                          :authentication-required-p nil))
         (model
           (make-model
            :id "gpt-test"
            :provider :openai
            :api :openai-responses
            :base-url "https://example.test"
            :compat nil))
         (context
           (make-context
            :system-prompt "Be precise."
            :messages
            (list (make-user-message :content "Ping" :timestamp 1))
            :tools
            (list
             (make-tool
              :name "read"
              :description "Read a file."
              :parameters (sample-schema))))))
    (stream-chat provider model context (lambda (event)
                                          (declare (ignore event))))
    (is (typep (goal24-seen-context provider)
               'cadr-ai:transcript-context))
    (let ((head
            (first
             (cadr-ai:transcript-context-messages
              (goal24-seen-context provider)))))
      (is (typep head 'cadr-ai:system-message))
      (is (string= "Be precise."
                   (cadr-ai:system-message-content head))))
    (setf (goal24-seen-context provider) nil)
    (let ((*http-request-function*
            (lambda (url &rest arguments)
              (declare (ignore url arguments))
              (values
               (cadr-ai::json-object "ok" t)
               200
               '(("content-type" . "application/json"))))))
      (complete-chat provider model context)
      (is (typep (goal24-seen-context provider)
                 'cadr-ai:transcript-context))
      (is (string=
           "Be precise."
           (cadr-ai:system-message-content
            (first
             (cadr-ai:transcript-context-messages
              (goal24-seen-context provider)))))))))

(test goal24-resolve-transcript-collapses-when-compat-false
  ;; Baseline packages/ai/src/utils/transcript.ts resolveTranscript /
  ;; collapseSystemMessages; default supportsMidConvoSystemMessages is false.
  (let* ((leading
           (cadr-ai:make-system-message
            :content "Base"
            :tools-added
            (list
             (make-tool
              :name "read"
              :description "Read a file."
              :parameters (sample-schema)))
            :timestamp 1))
         (mid
           (cadr-ai:make-system-message
            :content "Extra mid-convo"
            :timestamp 2))
         (user (make-user-message :content "Hi" :timestamp 3))
         (transcript
           (cadr-ai:make-transcript-context
            :messages (list leading mid user)))
         (collapsed
           (cadr-ai:resolve-transcript transcript nil))
         (kept
           (cadr-ai:resolve-transcript transcript t)))
    (is (eq transcript kept))
    (let ((messages (cadr-ai:transcript-context-messages collapsed)))
      (is (= 2 (length messages)))
      (is (typep (first messages) 'cadr-ai:system-message))
      (is (string= (format nil "Base~%~%Extra mid-convo")
                   (cadr-ai:system-message-content (first messages))))
      (is (eq user (second messages))))))
