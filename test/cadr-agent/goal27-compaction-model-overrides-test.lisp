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
