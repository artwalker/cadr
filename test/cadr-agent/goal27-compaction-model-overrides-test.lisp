(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defun goal22-summary-message (text model-id)
  (make-assistant-message
   :content (list (make-text-content :text text))
   :api :openai-responses
   :provider :provider
   :model model-id
   :usage (cadr-ai:make-usage :input 1 :output 1 :total 2)
   :stop-reason :stop))

(defun goal22-record-stream (state)
  ;; STATE is (seen . responses). The stream may run while the test's
  ;; bindings are only lexical, so record through this cons.
  (lambda (provider model context on-event
           &key max-tokens temperature abort-p
             cache-retention session-id reasoning)
    (declare (ignore provider context on-event max-tokens
                     temperature cache-retention session-id
                     reasoning))
    (push (cadr-ai:model-id model) (car state))
    (if (and abort-p (funcall abort-p))
        (goal22-summary-message "" (cadr-ai:model-id model))
        (pop (cdr state)))))

(test goal22-compaction-reads-the-model-settings-function
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "goal22-overrides"))
           (preparations nil))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message
        :content (make-string 80 :initial-element #\a)))
      (cadr-agent:session-append-message
       session
       (goal22-summary-message
        (make-string 80 :initial-element #\b)
        "small"))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message :content "keep"))
      (let* ((small
               (make-model
                :id "small" :provider :provider
                :api :openai-responses
                :base-url "https://example.invalid"
                :max-tokens 32 :context-window 4000))
             (big
               (make-model
                :id "big" :provider :provider
                :api :openai-responses
                :base-url "https://example.invalid"
                :max-tokens 32 :context-window 10000))
             (bundle
               (make-test-extension-bundle
                "goal22-before-compact"
                (lambda ()
                  (cadr-agent:define-event-hook
                   :session-before-compact
                   :handler
                   (lambda (event context)
                     (declare (ignore context))
                     (let ((payload
                             (cadr-agent::extension-event-payload
                              event)))
                       (push (getf payload :preparation)
                             preparations)
                       (list
                        :compaction
                        (list
                         :summary "model override summary"
                         :first-kept-entry-id
                         (getf (getf payload :preparation)
                               :first-kept-entry-id)
                         :tokens-before
                         (getf (getf payload :preparation)
                               :tokens-before)))))))))
             (agent
               (cadr-agent:make-agent
                :provider :provider
                :model small
                :session session
                :extension-host
                (make-test-extension-host (list bundle))
                :compaction-reserve-tokens 10
                :compaction-keep-recent-tokens 20000
                :compaction-settings-function
                (lambda (model)
                  (if (and model
                           (string= (cadr-ai:model-id model) "big"))
                      (values 8000 1 t)
                      (values 10 20000 t)))
                :stream-function
                (goal22-record-stream (cons nil nil)))))
        (is (null
             (cadr-agent:compact-agent agent :force-p t)))
        (is (null preparations))
        (setf (cadr-agent:agent-model agent) big)
        (is-true
         (cadr-agent:compact-agent agent :force-p t))
        (let ((settings
                (getf (first preparations) :settings)))
          (is (eq t (getf settings :enabled-p)))
          (is (= 8000 (getf settings :reserve-tokens)))
          (is (= 1 (getf settings :keep-recent-tokens))))
        (is (= 10
               (cadr-agent::agent-compaction-reserve-tokens
                agent)))))))

(test goal22-compaction-keeps-the-model-captured-before-auth
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "goal22-capture"))
           (state
             (cons nil
                   (list (goal22-summary-message "summary" "first")))))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message
        :content (make-string 80 :initial-element #\a)))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message :content "keep"))
      (let* ((first
               (make-model
                :id "first" :provider :provider
                :api :openai-responses
                :base-url "https://example.invalid"
                :max-tokens 32 :context-window 4000))
             (second
               (make-model
                :id "second" :provider :provider
                :api :openai-responses
                :base-url "https://example.invalid"
                :max-tokens 32 :context-window 4000))
             (agent
               (cadr-agent:make-agent
                :provider :provider
                :model first
                :session session
                :compaction-keep-recent-tokens 1
                :summarization-auth-function
                (lambda (agent model signal)
                  (declare (ignore signal))
                  (is (string= "first" (cadr-ai:model-id model)))
                  (setf (cadr-agent:agent-model agent) second))
                :stream-function
                (goal22-record-stream state))))
        (is-true (cadr-agent:compact-agent agent :force-p t))
        (is (equal '("first") (car state)))
        (is (string= "second"
                     (cadr-ai:model-id
                      (cadr-agent:agent-model agent))))))))

(defun goal22-user-texts (messages)
  (loop for message in messages
        when (typep message 'cadr-ai:user-message)
          collect (cadr-ai:user-message-content message)))

(test goal22-compaction-routes-the-captured-virtual-model
  ;; v1.4.0 agent-session.ts _getSummarizationRequestAuth. A virtual
  ;; selection is resolveModel(captured, convertToLlm(this.messages),
  ;; {reason:"direct", thinkingLevel:this.thinkingLevel}). getAuth and
  ;; session_before_compact may replace this.model afterwards. The
  ;; summary request stays on the routed physical model.
  (let ((cadr-agent::*virtual-models* (make-hash-table :test #'equal)))
    (with-session-directories (sessions cwd other-cwd)
      (values other-cwd)
      (let* ((session
               (cadr-agent:create-session
                :directory sessions :cwd cwd
                :id "goal22-virtual-capture"))
             (routes nil)
             (streamed nil)
             (routed
               (make-model
                :id "routed" :provider :provider
                :api :openai-responses
                :base-url "https://example.invalid"
                :reasoning-p t
                :thinking-level-map
                '((:off . :off) (:low . :low) (:high . :high))
                :max-tokens 32 :context-window 4000))
             (during-auth
               (make-model
                :id "switched-during-auth" :provider :provider
                :api :openai-responses
                :base-url "https://example.invalid"
                :max-tokens 32 :context-window 4000))
             (during-hook
               (make-model
                :id "switched-during-hook" :provider :provider
                :api :openai-responses
                :base-url "https://example.invalid"
                :max-tokens 32 :context-window 4000))
             (virtual
               (cadr-agent:register-virtual-model
                :provider :provider
                :id "captured-router"
                :name "Captured"
                :context-window 4000
                :max-tokens 32
                :thinking-levels '(:off :high)
                :route
                (lambda (request)
                  (push (list
                         (cadr-ai:model-id
                          (cadr-agent::virtual-model-route-request-model
                           request))
                         (cadr-agent:virtual-model-route-request-reason
                          request)
                         (cadr-agent::virtual-model-route-request-thinking-level
                          request)
                         (cadr-agent:virtual-model-route-request-state
                          request)
                         (goal22-user-texts
                          (cadr-agent:virtual-model-route-request-messages
                           request)))
                        routes)
                  (cadr-agent:make-virtual-model-route
                   :model routed
                   :thinking-level :low
                   :state "must-not-persist")))))
        (cadr-agent:session-append-message
         session
         (cadr-ai:make-user-message
          :content "alpha-session-marker"))
        (cadr-agent:session-append-message
         session
         (cadr-ai:make-user-message :content "keep"))
        (let* ((holder (list nil))
               (bundle
                 (make-test-extension-bundle
                  "goal22-virtual-before-compact"
                  (lambda ()
                    (cadr-agent:define-event-hook
                     :session-before-compact
                     :handler
                     (lambda (event context)
                       (declare (ignore event context))
                       (setf (cadr-agent:agent-model (first holder))
                             during-hook)
                       nil)))))
               (agent
                 (cadr-agent:make-agent
                  :provider :provider
                  :model virtual
                  :session session
                  :extension-host
                  (make-test-extension-host (list bundle))
                  :compaction-keep-recent-tokens 1
                  :summarization-auth-function
                  (lambda (agent model signal)
                    (declare (ignore model signal))
                    (setf (cadr-agent:agent-model agent) during-auth))
                  :stream-function
                  (lambda (provider model context on-event
                           &key reasoning &allow-other-keys)
                    (declare (ignore provider on-event))
                    (push (list (cadr-ai:model-id model)
                                reasoning
                                (goal22-user-texts
                                 (cadr-ai:context-messages context)))
                          streamed)
                    (goal22-summary-message
                     "summary" (cadr-ai:model-id model))))))
          (setf (first holder) agent)
          (cadr-agent:agent-set-thinking-level agent :high)
          (let ((session-texts
                  (goal22-user-texts
                   (cadr-agent:convert-agent-messages-to-llm
                    (cadr-agent:agent-messages agent)))))
          (is-true (cadr-agent:compact-agent agent :force-p t))
          (is (equal
               '(("captured-router" :direct :high nil
                  ("alpha-session-marker" "keep")))
               (reverse routes)))
          (is (equal session-texts
                     '("alpha-session-marker" "keep")))
          (is (equal '(("routed" :low))
                     (mapcar (lambda (call)
                               (list (first call) (second call)))
                             (reverse streamed))))
          (is (search
               "The messages above are a conversation to summarize"
               (first (third (first streamed)))))
          (is (string= "switched-during-hook"
                       (cadr-ai:model-id
                        (cadr-agent:agent-model agent))))
          (is (null
               (cadr-agent:virtual-model-state
                (cadr-agent::session-path-entries session)
                :provider "captured-router")))))))))
