(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defparameter +wave2-extension-events+
  '(:session-start
    :session-info-changed
    :session-before-switch
    :session-before-fork
    :session-before-compact
    :session-compact
    :session-shutdown
    :session-before-tree
    :session-tree
    :context
    :before-agent-start
    :agent-start
    :agent-end
    :agent-settled
    :message-start
    :message-update
    :message-end
    :input
    :tool-execution-start
    :tool-execution-update
    :tool-execution-end
    :model-select
    :thinking-level-select))

(defun wave2-call (name &rest arguments)
  (apply
   (or (find-symbol name :cadr-agent)
       (error "Missing CADR-AGENT symbol ~A" name))
   arguments))

(defun wave2-context-action-bundle (id handler)
  (make-test-extension-bundle
   id
   (lambda ()
     (cadr-agent:define-event-hook
      :session-start
      :handler handler))))

(test wave2-extension-events-register-and-expose-copied-plist-payloads
  (let ((seen nil))
    (let* ((bundle
             (make-test-extension-bundle
              "wave2-events"
              (lambda ()
                (dolist (event +wave2-extension-events+)
                  (cadr-agent:define-event-hook
                   event
                   :handler
                   (lambda (value context)
                     (declare (ignore context))
                     (let ((payload
                             (wave2-call
                              "EXTENSION-EVENT-PAYLOAD"
                              value)))
                       (push
                        (list
                         (cadr-agent:extension-event-type value)
                         (progn
                           (when payload
                             (setf (first payload) :mutated))
                           (wave2-call
                            "EXTENSION-EVENT-PAYLOAD"
                            value)))
                        seen)
                       )
                     nil))))))
           (host (make-test-extension-host (list bundle))))
      (dolist (event +wave2-extension-events+)
        (wave2-call
         "RUN-EXTENSION-LIFECYCLE-HOOKS"
         host event :payload (list :marker event)))
      (is (= (length +wave2-extension-events+)
             (length seen)))
      (is
       (equal
        +wave2-extension-events+
        (sort
         (mapcar #'first seen)
         #'<
         :key
         (lambda (event)
           (position event +wave2-extension-events+)))))
      (dolist (entry seen)
        (is
         (not
          (eq :mutated
              (first (second entry)))))))))

(test wave2-lifecycle-result-merging-matches-the-reference-runner
  (let* ((first-message
           (cadr-ai:make-user-message :content "first"))
         (second-message
           (cadr-ai:make-user-message :content "second"))
         (assistant-one
           (assistant
            (list (make-text-content :text "one"))))
         (assistant-two
           (assistant
            (list (make-text-content :text "two"))))
         (bundle
           (make-test-extension-bundle
            "wave2-results"
            (lambda ()
              (cadr-agent:define-event-hook
               :session-before-switch
               :priority -10
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 '(:cancel-p nil)))
              (cadr-agent:define-event-hook
               :session-before-switch
               :priority 0
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 '(:cancel-p t)))
              (cadr-agent:define-event-hook
               :session-before-switch
               :priority 10
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 (error "must short-circuit")))
              (cadr-agent:define-event-hook
               :context
               :priority -10
               :handler
               (lambda (event context)
                 (declare (ignore context))
                 (is (equal
                      (list first-message)
                      (getf
                       (wave2-call
                        "EXTENSION-EVENT-PAYLOAD"
                        event)
                       :messages)))
                 (list :messages (list second-message))))
              (cadr-agent:define-event-hook
               :context
               :priority 10
               :handler
               (lambda (event context)
                 (declare (ignore context))
                 (is (equal
                      (list second-message)
                      (getf
                       (wave2-call
                        "EXTENSION-EVENT-PAYLOAD"
                        event)
                       :messages)))
                 nil))
              (cadr-agent:define-event-hook
               :before-agent-start
               :priority -10
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 (list
                  :message first-message
                  :system-prompt "changed")))
              (cadr-agent:define-event-hook
               :before-agent-start
               :priority 10
               :handler
               (lambda (event context)
                 (declare (ignore context))
                 (is
                  (string=
                   "changed"
                   (getf
                    (wave2-call
                     "EXTENSION-EVENT-PAYLOAD"
                     event)
                    :system-prompt)))
                 (list :message second-message)))
              (cadr-agent:define-event-hook
               :message-end
               :priority -10
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 (list :message assistant-two)))
              (cadr-agent:define-event-hook
               :message-end
               :priority 10
               :handler
               (lambda (event context)
                 (declare (ignore context))
                 (is
                  (eq
                   assistant-two
                   (getf
                    (wave2-call
                     "EXTENSION-EVENT-PAYLOAD"
                     event)
                    :message)))
                 nil))
              (cadr-agent:define-event-hook
               :input
               :priority -10
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 '(:action :transform
                   :text "changed"
                   :images ("image"))))
              (cadr-agent:define-event-hook
               :input
               :priority 10
               :handler
               (lambda (event context)
                 (declare (ignore context))
                 (is
                  (string=
                   "changed"
                   (getf
                    (wave2-call
                     "EXTENSION-EVENT-PAYLOAD"
                     event)
                    :text)))
                 '(:action :handled))))))
         (host (make-test-extension-host (list bundle))))
    (is
     (equal
      '(:cancel-p t)
      (wave2-call
       "RUN-EXTENSION-LIFECYCLE-HOOKS"
       host :session-before-switch
       :payload '(:reason :new))))
    (is
     (equal
      (list second-message)
      (getf
       (wave2-call
        "RUN-EXTENSION-LIFECYCLE-HOOKS"
        host :context
        :payload (list :messages (list first-message)))
       :messages)))
    (let ((result
            (wave2-call
             "RUN-EXTENSION-LIFECYCLE-HOOKS"
             host :before-agent-start
             :payload
             '(:prompt "hello"
               :system-prompt "original"))))
      (is (equal (list first-message second-message)
                 (getf result :messages)))
      (is (string= "changed"
                   (getf result :system-prompt))))
    (is
     (eq
      assistant-two
      (getf
       (wave2-call
        "RUN-EXTENSION-LIFECYCLE-HOOKS"
        host :message-end
        :payload (list :message assistant-one))
       :message)))
    (is
     (equal
      '(:action :handled)
      (wave2-call
       "RUN-EXTENSION-LIFECYCLE-HOOKS"
       host :input
       :payload
       '(:text "original"
         :source :interactive))))))

(test input-lifecycle-preserves-images-sources-and-streaming-behavior
  (let ((seen nil)
        (image
          (cadr-ai:make-image-content
           :mime-type "image/png"
           :data "AA==")))
    (let* ((bundle
             (make-test-extension-bundle
              "input-contract"
              (lambda ()
                (cadr-agent:define-event-hook
                 :input
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (let ((payload
                           (cadr-agent:extension-event-payload
                            event)))
                     (push
                      (list
                       (getf payload :source)
                       (getf payload
                             :streaming-behavior)
                       (copy-list
                        (getf payload :images)))
                      seen))
                   '(:action :transform
                     :text "changed"))))))
           (host
             (make-test-extension-host
              (list bundle)))
           (agent
             (make-agent
              :provider :mock
              :model (mock-model)
              :extension-host host
              :auto-compact-p nil))
           (message
             (cadr-ai:make-user-message
              :content
              (list
               (cadr-ai:make-text-content
                :text "original")
               image))))
      (multiple-value-bind
            (transformed handled-p)
          (cadr-agent::apply-agent-input-hooks
           agent message :rpc
           :streaming-behavior :follow-up)
        (is (null handled-p))
        (let ((content
                (cadr-ai:user-message-content
                 transformed)))
          (is (string=
               "changed"
               (cadr-ai:text-content-text
                (first content))))
          (is (eq image (second content)))))
      (is
       (equal
        (list
         (list :rpc :follow-up
               (list image)))
        seen)))))

(test wave2-lifecycle-invalid-results-are-isolated-and-transactional
  (let ((*notifications* nil))
    (declare (special *notifications*))
    (let* ((message
             (cadr-ai:make-user-message :content "original"))
           (bundle
             (make-test-extension-bundle
              "wave2-invalid"
              (lambda ()
                (cadr-agent:define-event-hook
                 :agent-start
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   '(:unexpected t)))
                (cadr-agent:define-event-hook
                 :context
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   '(:messages "not-a-list")))
                (cadr-agent:define-event-hook
                 :message-end
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   (list
                    :message
                    (assistant
                     (list
                      (make-text-content
                       :text "wrong-role")))))))))
           (host
             (make-test-extension-host
              (list bundle)
              :notifications '*notifications*)))
      (is
       (null
        (wave2-call
         "RUN-EXTENSION-LIFECYCLE-HOOKS"
         host :agent-start)))
      (is
       (equal
        (list message)
        (getf
         (wave2-call
          "RUN-EXTENSION-LIFECYCLE-HOOKS"
          host :context
          :payload (list :messages (list message)))
         :messages)))
      (is
       (eq
        message
        (getf
         (wave2-call
          "RUN-EXTENSION-LIFECYCLE-HOOKS"
          host :message-end
          :payload (list :message message))
         :message)))
      (is (= 3 (length *notifications*))))))

(test wave2-ui-context-surface-delegates-and-defaults-without-ui
  (let ((requests nil))
    (let* ((bundle
             (wave2-context-action-bundle
              "wave2-ui"
              (lambda (event context)
                (declare (ignore event))
                (push
                 (list
                  :select
                  (wave2-call
                   "EXTENSION-CONTEXT-SELECT"
                   context "Pick" '("a" "b")
                   :timeout-ms 50))
                 requests)
                (push
                 (list
                  :confirm
                  (wave2-call
                   "EXTENSION-CONTEXT-CONFIRM"
                   context "Sure?" "Message"))
                 requests)
                (push
                 (list
                  :input
                  (wave2-call
                   "EXTENSION-CONTEXT-INPUT"
                   context "Input"
                   :placeholder "value"))
                 requests)
                (push
                 (list
                  :editor
                  (wave2-call
                   "EXTENSION-CONTEXT-EDITOR"
                   context "Edit" :prefill "old"))
                 requests)
                (wave2-call
                 "EXTENSION-CONTEXT-SET-STATUS"
                 context "build" "running")
                (wave2-call
                 "EXTENSION-CONTEXT-SET-WIDGET"
                 context "notes" '("one" "two")
                 :placement :below-editor)
                (wave2-call
                 "EXTENSION-CONTEXT-SET-TITLE"
                 context "Wave 2")
                (wave2-call
                 "EXTENSION-CONTEXT-SET-EDITOR-TEXT"
                 context "replacement")
                nil)))
           (host
             (cadr-agent::make-extension-host
              :cwd #P"/tmp/"
              :ui-function
              (lambda (method arguments)
                (push (list method arguments) requests)
                (case method
                  (:select "b")
                  (:confirm t)
                  (:input "typed")
                  (:editor "edited"))))))
      (cadr-agent::replace-extension-bundles host (list bundle))
      (wave2-call
       "RUN-EXTENSION-LIFECYCLE-HOOKS"
       host :session-start)
      (is (find '(:select "b") requests :test #'equal))
      (is (find '(:confirm t) requests :test #'equal))
      (is (find '(:input "typed") requests :test #'equal))
      (is (find '(:editor "edited") requests :test #'equal))
      (dolist (method
               '(:set-status
                 :set-widget
                 :set-title
                 :set-editor-text))
        (is (find method requests :key #'first))))
    (let* ((bundle
             (wave2-context-action-bundle
              "wave2-ui-default"
              (lambda (event context)
                (declare (ignore event))
                (is
                 (null
                  (wave2-call
                   "EXTENSION-CONTEXT-SELECT"
                   context "Pick" '("a"))))
                (is
                 (null
                  (wave2-call
                   "EXTENSION-CONTEXT-CONFIRM"
                   context "Sure?" "Message")))
                nil)))
           (host (make-test-extension-host (list bundle))))
      (wave2-call
       "RUN-EXTENSION-LIFECYCLE-HOOKS"
       host :session-start))))

(test wave2-runtime-tool-and-provider-registration-take-effect-immediately
  (let* ((dynamic-tool
           (make-tool
            :name "dynamic"
            :description "Dynamic"
            :parameters (object-schema)
            :executor
            (lambda (call-id arguments)
              (declare (ignore call-id arguments))
              (values
               (list
                (make-text-content :text "dynamic-ok"))
               nil))))
         (provider-definition
           (cadr-ai:make-provider-definition
            :id :openai
            :name "OpenAI override"
            :protocol :openai-responses
            :base-url "https://proxy.invalid"
            :default-model "mock"))
         (bundle
           (wave2-context-action-bundle
            "wave2-runtime-registration"
            (lambda (event context)
              (declare (ignore event))
              (wave2-call
               "EXTENSION-CONTEXT-REGISTER-TOOL"
               context dynamic-tool)
              (wave2-call
               "EXTENSION-CONTEXT-REGISTER-PROVIDER"
               context provider-definition)
              nil)))
         (host (make-test-extension-host (list bundle)))
         (agent
           (make-agent
            :provider :mock
            :model (mock-model)
            :extension-host host
            :auto-compact-p nil)))
    (is
     (null
      (cadr-agent:find-tool
       (cadr-agent::agent-tool-registry agent)
       "dynamic")))
    (wave2-call
     "RUN-EXTENSION-LIFECYCLE-HOOKS"
     host :session-start)
    (is
     (not
      (null
       (cadr-agent:find-tool
        (cadr-agent::agent-tool-registry agent)
        "dynamic"))))
    (is
     (string=
      "https://proxy.invalid"
      (cadr-ai:model-base-url
       (cadr-agent:agent-model agent))))))

(test wave2-cancellation-signal-is-opaque-and-observable
  (let ((signal
          (wave2-call
           "MAKE-EXTENSION-CANCELLATION-SIGNAL")))
    (is
     (not
      (wave2-call
       "EXTENSION-CANCELLATION-ABORTED-P"
       signal)))
    (wave2-call
     "ABORT-EXTENSION-CANCELLATION-SIGNAL"
     signal)
    (is
     (wave2-call
      "EXTENSION-CANCELLATION-ABORTED-P"
      signal))))

(test wave2-lifecycle-and-runtime-actions-drive-the-real-agent-loop
  (let* ((seen nil)
         (queued-p nil)
         (hook-message
           (cadr-ai:make-user-message
            :content "hook-message"))
         (bundle
           (make-test-extension-bundle
            "wave2-real-loop"
            (lambda ()
              (cadr-agent:define-event-hook
               :input
               :handler
               (lambda (event context)
                 (declare (ignore context))
                 (push :input seen)
                 (is
                  (string=
                   "original"
                   (getf
                    (cadr-agent:extension-event-payload
                     event)
                    :text)))
                 '(:action :transform
                   :text "transformed")))
              (cadr-agent:define-event-hook
               :before-agent-start
               :handler
               (lambda (event context)
                 (declare (ignore context))
                 (push :before-agent-start seen)
                 (is
                  (string=
                   "base-system"
                   (getf
                    (cadr-agent:extension-event-payload
                     event)
                    :system-prompt)))
                 (list
                  :message hook-message
                  :system-prompt "hook-system")))
              (cadr-agent:define-event-hook
               :agent-start
               :handler
               (lambda (event context)
                 (declare (ignore event))
                 (push :agent-start seen)
                 (unless queued-p
                   (setf queued-p t)
                   (cadr-agent:extension-context-send-user-message
                    context "steered"
                    :deliver-as :steer))
                 nil))
              (dolist
                  (event
                   '(:context
                     :message-start
                     :message-update
                     :tool-execution-start
                     :tool-execution-end
                     :agent-end
                     :agent-settled))
                (cadr-agent:define-event-hook
                 event
                 :handler
                 (lambda (value context)
                   (declare (ignore context))
                   (push
                    (cadr-agent:extension-event-type value)
                    seen)
                   nil)))
              (cadr-agent:define-event-hook
               :message-end
               :handler
               (lambda (event context)
                 (declare (ignore context))
                 (push :message-end seen)
                 (let ((message
                         (getf
                          (cadr-agent:extension-event-payload
                           event)
                          :message)))
                   (if
                       (typep
                        message
                        'cadr-ai:assistant-message)
                       (list
                        :message
                        (assistant
                         (list
                          (make-text-content
                           :text "replaced"))))
                       nil)))))))
         (host (make-test-extension-host (list bundle)))
         (*responses*
           (list
            (assistant
             (list (make-text-content :text "first")))
            (assistant
             (list (make-text-content :text "second")))))
         (*contexts* nil))
    (declare (special *responses* *contexts*))
    (let ((agent
            (make-agent
             :provider :mock
             :model (mock-model)
             :system-prompt "base-system"
             :extension-host host
             :stream-function
             (faux-stream '*responses* '*contexts*))))
      (agent-prompt agent "original")
      (is
       (equal
        '("transformed" "hook-message" "steered")
        (loop for message in (agent-messages agent)
              when (typep message 'cadr-ai:user-message)
                collect (user-text message))))
      (is
       (every
        (lambda (context)
          (string=
           "hook-system"
           (cadr-ai:context-system-prompt context)))
        *contexts*))
      (is
       (equal
        '("replaced" "replaced")
        (loop for message in (agent-messages agent)
              when
              (typep message 'cadr-ai:assistant-message)
                collect
                (cadr-ai:text-content-text
                 (first
                  (cadr-ai:assistant-message-content
                   message))))))
      (dolist
          (event
           '(:input
             :before-agent-start
             :agent-start
             :context
             :message-start
             :message-update
             :message-end
             :agent-end
             :agent-settled))
        (is (member event seen))))))

(test wave2-send-message-and-session-name-actions-persist
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions
              :cwd cwd
              :id "wave2-actions"))
           (bundle
             (wave2-context-action-bundle
              "wave2-actions"
              (lambda (event context)
                (declare (ignore event))
                (cadr-agent:extension-context-send-message
                 context
                 '(:custom-type "notice"
                   :content "persisted"
                   :details (:source :extension)
                   :display-p t))
                (cadr-agent:extension-context-set-session-name
                 context
                 (format nil "wave~%two"))
                nil)))
           (host (make-test-extension-host (list bundle)))
           (agent
             (make-agent
              :provider :mock
              :model (mock-model)
              :session session
              :extension-host host
              :auto-compact-p nil)))
      (declare (ignore agent))
      (wave2-call
       "RUN-EXTENSION-LIFECYCLE-HOOKS"
       host :session-start
       :payload '(:reason :startup))
      (is (string= "wave two"
                   (cadr-agent:session-name session)))
      (let ((custom
              (find
               :custom-message
               (cadr-agent:session-entries session)
               :key #'cadr-agent:session-entry-type)))
        (is (not (null custom)))
        (is (string=
             "notice"
             (cadr-agent:session-entry-custom-type custom)))
        (is (string=
             "persisted"
             (cadr-agent:session-entry-content custom)))))))

(test tree-navigation-cancellation-and-busy-guard-preserve-the-active-leaf
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions
              :cwd cwd
              :id "tree-navigation"))
           (target-id
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message
               :content "first")))
           (reply-id
             (cadr-agent:session-append-message
              session
              (assistant
               (list
                (make-text-content
                 :text "reply")))))
           (current-id
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message
               :content "second")))
           (bundle
             (make-test-extension-bundle
              "cancel-tree"
              (lambda ()
                (cadr-agent:define-event-hook
                 :session-before-tree
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   '(:cancel-p t))))))
           (host
             (make-test-extension-host
              (list bundle)))
           (agent
             (make-agent
              :provider :mock
              :model (mock-model)
              :session session
              :extension-host host
              :auto-compact-p nil)))
      (declare (ignore reply-id))
      (multiple-value-bind (messages cancelled-p)
          (cadr-agent:agent-navigate-tree
           agent target-id)
        (is (null messages))
        (is (eq t cancelled-p)))
      (is
       (string=
        current-id
        (cadr-agent:session-leaf-id session)))
      (setf
       (cadr-agent::agent-busy-p agent)
       t)
      (signals cadr-agent::agent-busy-error
        (cadr-agent:agent-navigate-tree
         agent target-id))
      (is
       (string=
        current-id
        (cadr-agent:session-leaf-id session))))))

(test message-end-replacement-persists-finalized-usage-cost
  (let* ((bundle
           (make-test-extension-bundle
            "usage-cost"
            (lambda ()
              (cadr-agent:define-event-hook
               :message-end
               :handler
               (lambda (event context)
                 (declare (ignore context))
                 (let ((message
                         (getf
                          (cadr-agent:extension-event-payload
                           event)
                          :message)))
                   (when
                       (typep
                        message
                        'cadr-ai:assistant-message)
                     (list
                      :message
                      (cadr-ai:make-assistant-message
                       :content
                       (copy-list
                        (cadr-ai:assistant-message-content
                         message))
                       :api
                       (cadr-ai:assistant-message-api
                        message)
                       :provider
                       (cadr-ai:assistant-message-provider
                        message)
                       :model
                       (cadr-ai:assistant-message-model
                        message)
                       :usage
                       (cadr-ai:make-usage
                        :cost
                        (cadr-ai:make-cost
                         :total 0.123d0))
                       :stop-reason
                       (cadr-ai:assistant-message-stop-reason
                        message))))))))))
         (host
           (make-test-extension-host
            (list bundle)))
         (*responses*
           (list
            (assistant
             (list
              (make-text-content
               :text "hello")))))
         (*contexts* nil)
         (events nil))
    (declare (special *responses* *contexts*))
    (let ((agent
            (make-agent
             :provider :mock
             :model (mock-model)
             :extension-host host
             :stream-function
             (faux-stream
              '*responses* '*contexts*)
             :on-event
             (lambda (event)
               (push event events)))))
      (agent-prompt agent "hi")
      (let* ((assistant-message
               (find-if
                (lambda (message)
                  (typep
                   message
                   'cadr-ai:assistant-message))
                (agent-messages agent)))
             (message-end
               (find
                :message-end events
                :key #'agent-event-type)))
        (is
         (= 0.123d0
            (cadr-ai:cost-total
             (cadr-ai:usage-cost
              (cadr-ai:assistant-message-usage
               assistant-message)))))
        (is
         (= 0.123d0
            (cadr-ai:cost-total
             (cadr-ai:usage-cost
              (cadr-ai:assistant-message-usage
               (agent-event-message
                message-end))))))))))

(test goal10-tool-call-error-hook-retries-at-the-live-condition-site
  (let ((sequence nil)
        (payload-argument-after-mutation nil)
        (executions 0)
        (events nil)
        (notifications nil))
    (let* ((bundle
             (make-test-extension-bundle
              "tool-call-error-retry"
              (lambda ()
                (cadr-agent:define-event-hook
                 :tool-call-before
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (push :before sequence)
                   (cadr-agent:make-extension-hook-result
                    :replacement
                    (cadr-agent:extension-event-tool-call event))))
                (cadr-agent:define-event-hook
                 :tool-call-error
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (push :error sequence)
                   (let* ((payload
                            (cadr-agent:extension-event-payload event))
                          (arguments (getf payload :arguments)))
                     (is (typep
                          (getf payload :condition)
                          'cadr-agent:tool-execution-error))
                     (is (= 1 (getf payload :attempt)))
                     (is
                      (equal
                       '(cadr-agent:retry-tool-call
                         cadr-agent:skip-tool-call
                         cadr-agent:abort-agent-run)
                       (getf payload :restart-names)))
                     (setf (gethash "value" arguments) "mutated")
                     (setf
                      payload-argument-after-mutation
                      (cadr-ai::json-get
                       (getf
                        (cadr-agent:extension-event-payload event)
                        :arguments)
                       "value"))
                     (list
                      :action :retry
                      :arguments
                      (cadr-ai::json-object "value" "good")))))
                (cadr-agent:define-event-hook
                 :tool-call-after
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   (push :after sequence)
                   nil)))))
           (host
             (let ((value
                     (cadr-agent::make-extension-host
                      :cwd #P"/tmp/"
                      :mode :repl
                      :notify-function
                      (lambda (message level)
                        (push (list level message)
                              notifications)))))
               (cadr-agent::replace-extension-bundles
                value (list bundle))
               value))
           (tool
             (make-tool
              :name "retry-hook"
              :description "Retry hook"
              :parameters (object-schema "value")
              :execution-mode :sequential
              :executor
              (lambda (call-id arguments)
                (declare (ignore call-id))
                (incf executions)
                (let ((value
                        (cadr-ai::json-get arguments "value")))
                  (if (string= value "bad")
                      (error "bad attempt")
                      (list (make-text-content :text value)))))))
           (*responses*
             (list
              (assistant
               (list
                (make-tool-call
                 :id "hook-retry-1" :name "retry-hook"
                 :arguments
                 (cadr-ai::json-object "value" "bad")))
               :tool-use)
              (assistant
               (list (make-text-content :text "done")))))
           (*contexts* nil)
           (agent
             (make-agent
              :provider :mock
              :model (mock-model)
              :tools (list tool)
              :extension-host host
              :stream-function
              (faux-stream '*responses* '*contexts*)
              :on-event
              (lambda (event)
                (push (agent-event-type event) events)))))
      (declare (special *responses* *contexts*))
      (agent-prompt agent "run")
      (is (= 2 executions))
      (is (string= "bad" payload-argument-after-mutation))
      (is (equal '(:before :error :before :after)
                 (nreverse sequence)))
      (is (= 1 (count :tool-execution-start events)))
      (is (= 1 (count :tool-execution-end events)))
      (is (not (member :tool-call-error events)))
      (is (null notifications)
          "Unexpected hook failure: ~S"
          notifications)
      (let ((result (third (agent-messages agent))))
        (is-false (tool-result-message-is-error result))
        (is (string= "good" (text-result result)))))))

(test goal10-parallel-tool-error-restarts-are-call-local
  (let ((seen nil))
    (let* ((bundle
             (make-test-extension-bundle
              "parallel-tool-errors"
              (lambda ()
                (cadr-agent:define-event-hook
                 :tool-call-error
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (let* ((payload
                            (cadr-agent:extension-event-payload event))
                          (call (getf payload :tool-call))
                          (id (cadr-ai:tool-call-id call)))
                     (push
                      (list
                       id
                       (cadr-ai::json-get
                        (getf payload :arguments) "value")
                       (mapcar
                        (lambda (name)
                          (not (null (find-restart name))))
                        (getf payload :restart-names)))
                      seen)
                     (list
                      :action :retry
                      :arguments
                      (cadr-ai::json-object
                       "value" (format nil "~A-ok" id)))))))))
           (tool
             (make-tool
              :name "parallel-fail"
              :description "Parallel fail"
              :parameters (object-schema "value")
              :execution-mode :parallel
              :executor
              (lambda (call-id arguments)
                (let ((value
                        (cadr-ai::json-get arguments "value")))
                  (if (string= value "fail")
                      (error "~A failed" call-id)
                      (list (make-text-content :text value)))))))
           (host (make-test-extension-host (list bundle)))
           (*responses*
             (list
              (assistant
               (list
                (make-tool-call
                 :id "left" :name "parallel-fail"
                 :arguments
                 (cadr-ai::json-object "value" "fail"))
                (make-tool-call
                 :id "right" :name "parallel-fail"
                 :arguments
                 (cadr-ai::json-object "value" "fail")))
               :tool-use)
              (assistant
               (list (make-text-content :text "done")))))
           (*contexts* nil)
           (agent
             (make-agent
              :provider :mock
              :model (mock-model)
              :tools (list tool)
              :extension-host host
              :stream-function
              (faux-stream '*responses* '*contexts*))))
      (declare (special *responses* *contexts*))
      (agent-prompt agent "run")
      (is (= 2 (length seen)))
      (dolist (entry seen)
        (is (string= "fail" (second entry)))
        (is (equal '(t t t) (third entry))))
      (is
       (equal
        '("left-ok" "right-ok")
        (loop for message in (agent-messages agent)
              when (typep message 'tool-result-message)
                collect (text-result message)))))))

(test goal10-schema-retry-revalidates-every-attempt-and-finalizes-once
  (let ((sequence nil)
        (executions 0)
        (events nil))
    (let* ((bundle
             (make-test-extension-bundle
              "schema-retry"
              (lambda ()
                (cadr-agent:define-event-hook
                 :tool-call-before
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   (push :before sequence)
                   nil))
                (cadr-agent:define-event-hook
                 :tool-call-error
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (let* ((payload
                            (cadr-agent:extension-event-payload event))
                          (attempt (getf payload :attempt)))
                     (push (list :error attempt) sequence)
                     (list
                      :action :retry
                      :arguments
                      (if (= attempt 1)
                          (cadr-ai::json-object "value" 7)
                          (cadr-ai::json-object "value" "valid"))))))
                (cadr-agent:define-event-hook
                 :tool-call-after
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   (push :after sequence)
                   nil)))))
           (tool
             (make-tool
              :name "schema-retry"
              :description "Schema retry"
              :parameters
              (cadr-ai::json-object
               "type" "object"
               "properties"
               (cadr-ai::json-object
                "value"
                (cadr-ai::json-object "type" "string"))
               "required" (vector "value"))
              :execution-mode :sequential
              :executor
              (lambda (call-id arguments)
                (declare (ignore call-id))
                (incf executions)
                (list
                 (make-text-content
                  :text
                  (cadr-ai::json-get arguments "value"))))))
           (host (make-test-extension-host (list bundle)))
           (*responses*
             (list
              (assistant
               (list
                (make-tool-call
                 :id "schema-retry-1"
                 :name "schema-retry"
                 :arguments (cadr-ai::json-object)))
               :tool-use)
              (assistant
               (list (make-text-content :text "done")))))
           (*contexts* nil)
           (agent
             (make-agent
              :provider :mock
              :model (mock-model)
              :tools (list tool)
              :extension-host host
              :stream-function
              (faux-stream '*responses* '*contexts*)
              :on-event
              (lambda (event)
                (push (agent-event-type event) events)))))
      (declare (special *responses* *contexts*))
      (agent-prompt agent "run")
      (is (= 1 executions))
      (is
       (equal
        '(:before (:error 1) :before (:error 2) :before :after)
        (nreverse sequence)))
      (is (= 1 (count :tool-execution-start events)))
      (is (= 1 (count :tool-execution-end events)))
      (let ((result (third (agent-messages agent))))
        (is-false (tool-result-message-is-error result))
        (is (string= "valid" (text-result result)))))))
