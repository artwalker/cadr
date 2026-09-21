(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

;;; Live settle/stream dispatch for cache-warmer (Goal 24 knife).
;;; Locks sdk.ts streamFn gate + agent-session settle/dispose at ecac0a9c4.

(defun goal24-dispatch-anthropic-model ()
  (cadr-ai:make-model
   :id "claude-opus-4-6"
   :name "Claude Opus 4.6"
   :provider :anthropic
   :api :anthropic-messages
   :compat '(:force-adaptive-thinking t)))

(defun goal24-dispatch-fake-clock ()
  (let ((clock (list :now 0 :pending nil)))
    (list
     :clock clock
     :now-fn (lambda () (getf clock :now))
     :schedule-fn
     (lambda (delay-ms thunk)
       (let ((item
               (list :at (+ (getf clock :now) delay-ms)
                     :fn thunk
                     :cancelled nil)))
         (push item (getf clock :pending))
         (lambda ()
           (setf (getf item :cancelled) t))))
     :advance
     (lambda (ms)
       (incf (getf clock :now) ms)
       (let* ((now (getf clock :now))
              (due
                (remove-if
                 (lambda (item)
                   (or (getf item :cancelled)
                       (> (getf item :at) now)))
                 (copy-list (getf clock :pending)))))
         (setf (getf clock :pending)
               (remove-if
                (lambda (item)
                  (member item due :test #'eq))
                (getf clock :pending)))
         (dolist
             (item
              (sort due #'<
                    :key (lambda (i) (getf i :at))))
           (funcall (getf item :fn))))))))

(defun goal24-dispatch-fixture
    (&key (mode "streaming") (session-id "sess-dispatch-1"))
  (let* ((settings
           (cadr-cli::make-memory-settings-manager
            (let ((obj (cadr-cli::empty-json-object)))
              (cadr-ai::json-put obj "cacheWarming" mode)
              obj)))
         (clock (goal24-dispatch-fake-clock))
         (model (goal24-dispatch-anthropic-model))
         (messages
           (list
            (cadr-ai:make-user-message
             :content
             (list (cadr-ai:make-text-content :text "hi")))))
         (agent-cell (cons nil nil))
         (session-id-cell (cons session-id nil))
         (stream-calls (cons nil nil))
         (branch
           (list
            (list
             :type :message
             :message
             (list
              :role :assistant
              :usage
              (list :input 0 :output 10
                    :cache-read 100000
                    :cache-write 0)))))
         (inner
           (lambda (provider live-model context on-event
                    &rest options)
             (declare (ignore on-event))
             (push
              (list :provider provider
                    :model live-model
                    :context context
                    :options options)
              (car stream-calls))
             (cadr-ai:make-assistant-message
              :content nil
              :api (cadr-ai:model-api live-model)
              :provider (cadr-ai:model-provider live-model)
              :model (cadr-ai:model-id live-model)
              :usage
              (cadr-ai:make-usage
               :input 0 :output 1 :cache-read 100
               :cache-write 0 :total 101)
              :stop-reason :length
              :timestamp 0)))
         (agent
           (cadr-agent:make-agent
            :provider :anthropic
            :model model
            :stream-function
            (lambda (&rest args)
              (declare (ignore args))
              (error "unwrapped stream should not run"))
            :on-event (lambda (event) (declare (ignore event)))))
         (_set-messages
           (setf (cadr-agent:agent-messages agent) messages))
         (warmer
           (cadr-cli:make-live-cache-warmer
            settings
            (lambda () (car agent-cell))
            (lambda () branch)
            inner
            :now-fn (getf clock :now-fn)
            :schedule-fn (getf clock :schedule-fn)))
         (wrapped
           (cadr-cli:wrap-stream-function-with-cache-warmer
            warmer
            (lambda () (car session-id-cell))
            (lambda () (car agent-cell))
            inner)))
    (declare (ignore _set-messages))
    (setf (car agent-cell) agent
          (cadr-agent::agent-stream-function agent) wrapped)
    (list
     :settings settings
     :agent agent
     :warmer warmer
     :wrapped wrapped
     :model model
     :session-id session-id
     :stream-calls stream-calls
     :advance (getf clock :advance))))

(test goal24-cache-warmer-dispatch-start-on-matching-session
  (let* ((fix (goal24-dispatch-fixture))
         (warmer (getf fix :warmer))
         (wrapped (getf fix :wrapped))
         (model (getf fix :model))
         (context
           (cadr-ai:make-context
            :system-prompt "sys"
            :messages (cadr-agent:agent-messages
                       (getf fix :agent)))))
    (funcall
     wrapped
     :anthropic model context
     (lambda (event) (declare (ignore event)))
     :session-id (getf fix :session-id))
    (let ((status (cadr-cli:cache-warmer-status warmer)))
      (is (eq (cadr-cli:cache-warming-status-state status)
              :scheduled)))
    (funcall
     wrapped
     :anthropic model context
     (lambda (event) (declare (ignore event)))
     :session-id "other-session")
    (is (eq
         (cadr-cli:cache-warming-status-state
          (cadr-cli:cache-warmer-status warmer))
         :scheduled))))

(test goal24-cache-warmer-dispatch-settle-stops-streaming
  (let* ((fix (goal24-dispatch-fixture :mode "streaming"))
         (warmer (getf fix :warmer))
         (wrapped (getf fix :wrapped))
         (model (getf fix :model))
         (context
           (cadr-ai:make-context
            :system-prompt "sys"
            :messages (cadr-agent:agent-messages
                       (getf fix :agent)))))
    (funcall
     wrapped
     :anthropic model context
     (lambda (event) (declare (ignore event)))
     :session-id (getf fix :session-id))
    (cadr-cli:cache-warmer-on-agent-settled warmer)
    (is
     (equal
      (cadr-cli:cache-warming-status-reason
       (cadr-cli:cache-warmer-status warmer))
      "agent run settled"))))

(test goal24-cache-warmer-dispatch-cancel-clears-run
  (let* ((fix (goal24-dispatch-fixture))
         (warmer (getf fix :warmer))
         (wrapped (getf fix :wrapped))
         (model (getf fix :model))
         (context
           (cadr-ai:make-context
            :system-prompt "sys"
            :messages (cadr-agent:agent-messages
                       (getf fix :agent)))))
    (funcall
     wrapped
     :anthropic model context
     (lambda (event) (declare (ignore event)))
     :session-id (getf fix :session-id))
    (cadr-cli:cache-warmer-cancel warmer)
    (is
     (equal
      (cadr-cli:cache-warming-status-reason
       (cadr-cli:cache-warmer-status warmer))
      "inactive"))))

(test goal24-cache-warmer-dispatch-mode-off-disables
  (let* ((fix (goal24-dispatch-fixture :mode "off"))
         (warmer (getf fix :warmer))
         (wrapped (getf fix :wrapped))
         (model (getf fix :model))
         (context
           (cadr-ai:make-context
            :system-prompt "sys"
            :messages (cadr-agent:agent-messages
                       (getf fix :agent)))))
    (funcall
     wrapped
     :anthropic model context
     (lambda (event) (declare (ignore event)))
     :session-id (getf fix :session-id))
    (is
     (equal
      (cadr-cli:cache-warming-status-reason
       (cadr-cli:cache-warmer-status warmer))
      "cache warming disabled"))))

(test goal24-cache-warmer-dispatch-mode-setter-notifies
  (let* ((fix (goal24-dispatch-fixture :mode "streaming"))
         (warmer (getf fix :warmer))
         (wrapped (getf fix :wrapped))
         (model (getf fix :model))
         (context
           (cadr-ai:make-context
            :system-prompt "sys"
            :messages (cadr-agent:agent-messages
                       (getf fix :agent)))))
    (funcall
     wrapped
     :anthropic model context
     (lambda (event) (declare (ignore event)))
     :session-id (getf fix :session-id))
    (cadr-cli:set-cache-warming-mode
     (getf fix :settings) "off" warmer)
    (is
     (equal
      (cadr-cli:cache-warming-status-reason
       (cadr-cli:cache-warmer-status warmer))
      "cache warming disabled"))))

(test goal24-model-as-cache-warm-model-anthropic-prompt-cache
  (let* ((model (goal24-dispatch-anthropic-model))
         (warm (cadr-cli:model-as-cache-warm-model model)))
    (is (equal (cadr-cli::cache-warm-model-id warm)
               "claude-opus-4-6"))
    (is (eq (cadr-cli::cache-warm-model-provider warm)
            :anthropic))
    (is (equal (cadr-cli::cache-warm-model-prompt-cache warm)
               '(:short 300 :long 3600))))
  (let* ((openai
           (cadr-ai:make-model
            :id "gpt-5"
            :name "GPT-5"
            :provider :openai
            :api :openai-responses))
         (warm (cadr-cli:model-as-cache-warm-model openai)))
    (is (null (cadr-cli::cache-warm-model-prompt-cache warm)))))
