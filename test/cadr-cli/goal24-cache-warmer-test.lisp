(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

;;; Locks packages/coding-agent/test/cache-warmer.test.ts at baseline
;;; ecac0a9c4 (eligibility, economics, stop reasons, format strings).

(defun goal24-adaptive-model ()
  (cadr-cli:make-cache-warm-model
   :id "claude-opus-4-6"
   :provider :anthropic
   :api :anthropic-messages
   :prompt-cache '(:short 300 :long 3600)
   :cost '(:input 5d0 :output 25d0 :cache-read 0.5d0 :cache-write 6.25d0)
   :compat '(:force-adaptive-thinking t)))

(defun goal24-budget-model ()
  (cadr-cli:make-cache-warm-model
   :id "claude-sonnet-4-5"
   :provider :anthropic
   :api :anthropic-messages
   :prompt-cache '(:short 300 :long 3600)
   :cost '(:input 3d0 :output 15d0 :cache-read 0.3d0 :cache-write 3.75d0)
   :compat '()))

(defun goal24-openai-model ()
  (cadr-cli:make-cache-warm-model
   :id "gpt-5"
   :provider :openai
   :api :openai-responses
   :prompt-cache '(:short 300 :long 86400)
   :cost '(:input 1.25d0 :output 10d0 :cache-read 0.125d0 :cache-write 0d0)
   :compat '()))

(defun goal24-unknown-model ()
  (let ((model (goal24-adaptive-model)))
    (setf (cadr-cli::cache-warm-model-prompt-cache model) nil)
    model))

(defun goal24-warm-usage ()
  (cadr-ai:make-usage
   :input 0 :output 1 :cache-read 100 :cache-write 0 :total 101
   :cost
   (cadr-ai:make-cost
    :input 0d0 :output 0d0 :cache-read 0.01d0 :cache-write 0d0
    :total 0.01d0)))

(defun goal24-response (model &optional (stop-reason :length))
  (cadr-ai:make-assistant-message
   :content nil
   :api (cadr-cli::cache-warm-model-api model)
   :provider (cadr-cli::cache-warm-model-provider model)
   :model (cadr-cli::cache-warm-model-id model)
   :usage (goal24-warm-usage)
   :stop-reason stop-reason
   :timestamp 0))

(defun goal24-branch-with-prompt (prompt-tokens)
  (list
   (list
    :type :message
    :message
    (list
     :role :assistant
     :usage
     (list :input 0 :output 10 :cache-read prompt-tokens
           :cache-write 0)))))

(defun goal24-fake-runtime
    (&key result decide (mode "idle") branch)
  (let* ((calls-box (cons nil nil))
         (events-box (cons nil nil))
         (warmed-box (cons nil nil))
         (appended-box (cons nil nil))
         (state
           (list
            :mode (or mode "idle")
            :branch (or branch (goal24-branch-with-prompt 100000))
            :block-refresh nil
            :release-refresh nil))
         (clock (list :now 0 :pending nil))
         (schedule-fn
           (lambda (delay-ms thunk)
             (let ((item
                     (list :at (+ (getf clock :now) delay-ms)
                           :fn thunk
                           :cancelled nil)))
               (push item (getf clock :pending))
               (lambda ()
                 (setf (getf item :cancelled) t)))))
         (now-fn (lambda () (getf clock :now)))
         (advance
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
                 (funcall (getf item :fn))))))
         (warmer
           (cadr-cli:make-cache-warmer
            (lambda (model context options)
              (declare (ignore context))
              (push (list :model model :options options)
                    (car calls-box))
              (when (getf state :block-refresh)
                (loop until (or (getf state :release-refresh)
                                (let ((abort-p
                                        (getf options :abort-p)))
                                  (and abort-p (funcall abort-p))))
                      do (sleep 0.01)))
              (let ((fn (or result
                            (lambda (m options)
                              (declare (ignore options))
                              (goal24-response m)))))
                (funcall fn model options)))
            (lambda () (getf state :branch))
            (lambda (kind provider model-id usage note)
              (let ((entry
                      (cadr-cli:make-cache-warm-usage-entry
                       :kind kind
                       :provider provider
                       :model-id model-id
                       :usage usage
                       :note note)))
                (push entry (car appended-box))
                entry))
            (lambda () (getf state :mode))
            :decide
            (lambda (event)
              (push event (car events-box))
              (if decide
                  (funcall decide event)
                  (getf event :action)))
            :on-warmed
            (lambda (entry)
              (push entry (car warmed-box)))
            :now-fn now-fn
            :schedule-fn schedule-fn)))
    (list
     :warmer warmer
     :state state
     :clock clock
     :advance advance
     :get-calls
     (lambda () (reverse (car calls-box)))
     :get-events
     (lambda () (reverse (car events-box)))
     :get-warmed
     (lambda () (reverse (car warmed-box)))
     :get-appended
     (lambda () (reverse (car appended-box))))))

(defun goal24-request
    (&optional (model (goal24-adaptive-model)) (options '()))
  (cadr-cli:make-cache-warm-request
   :model model
   :context (cadr-ai:make-context :messages nil)
   :options options))

(defun goal24-current ()
  t)

(test goal24-cache-warmer-eligibility-and-timing
  (let ((adaptive (goal24-adaptive-model))
        (budget (goal24-budget-model))
        (openai (goal24-openai-model))
        (unknown (goal24-unknown-model)))
    (is
     (equal
      (list
       (cadr-cli:get-prompt-cache-ttl-ms adaptive nil)
       (cadr-cli:get-prompt-cache-ttl-ms
        adaptive (list :cache-retention :long))
       (cadr-cli:get-prompt-cache-ttl-ms
        adaptive (list :cache-retention :none))
       (cadr-cli:get-prompt-cache-ttl-ms
        adaptive
        (list :env '(("CADR_CACHE_RETENTION" . "long"))))
       (cadr-cli:get-prompt-cache-ttl-ms
        openai (list :cache-retention :long))
       (cadr-cli:get-prompt-cache-ttl-ms unknown nil))
      '(300000 3600000 nil 3600000 86400000 nil)))
    (is
     (equal
      (list
       (cadr-cli:get-cache-warming-delay-ms 300000)
       (cadr-cli:get-cache-warming-delay-ms 60000)
       (cadr-cli:get-cache-warming-delay-ms 10000))
      '(270000 50000 nil)))
    (is
     (equal
      (list
       (cadr-cli:is-replayable budget (list :reasoning "medium"))
       (cadr-cli:is-replayable budget nil)
       (cadr-cli:is-replayable adaptive (list :reasoning "medium"))
       (cadr-cli:is-replayable openai (list :reasoning "medium")))
      '(nil t t t)))))

(test goal24-cache-warmer-profitable-replay
  (let* ((model (goal24-adaptive-model))
         (runtime (goal24-fake-runtime))
         (warmer (getf runtime :warmer))
         (advance (getf runtime :advance)))
    (cadr-cli:cache-warmer-start
     warmer
     (goal24-request
      model
      (list :reasoning "high" :session-id "s"))
     #'goal24-current)
    (funcall advance 270000)
    (let* ((calls (funcall (getf runtime :get-calls)))
           (events (funcall (getf runtime :get-events)))
           (first-call (first calls))
           (first-event (first events))
           (options (getf first-call :options)))
      (is (= 1 (length calls)))
      (is (eq (getf first-call :model) model))
      (is (string= (getf options :reasoning) "high"))
      (is (string= (getf options :session-id) "s"))
      (is (= 1 (getf options :max-tokens)))
      (is (= 0 (getf options :max-retries)))
      (is (functionp (getf options :abort-p)))
      (is (eq (getf first-event :type) :cache-warming-decision))
      (is (= 1d0 (getf first-event :continuation-probability)))
      (is (eq (getf first-event :action) :warm))
      (is (< (abs (- (getf first-event :miss-cost) 0.575d0)) 1d-9))
      (is (< (abs (- (getf first-event :warm-cost) 0.050025d0)) 1d-9))
      (let ((appended (funcall (getf runtime :get-appended))))
        (is (= 1 (length appended)))
        (is
         (null
          (cadr-cli::cache-warm-usage-entry-note
           (first appended)))))
      (funcall advance 270000)
      (is (= 2 (length (funcall (getf runtime :get-calls)))))
      (cadr-cli:cache-warmer-cancel warmer))))

(test goal24-cache-warmer-economics-and-overrides
  (let* ((unprofitable
           (goal24-fake-runtime
            :branch (goal24-branch-with-prompt 5000)))
         (forced
           (goal24-fake-runtime
            :branch (goal24-branch-with-prompt 5000)
            :decide (lambda (event)
                      (declare (ignore event))
                      :warm)))
         (vetoed
           (goal24-fake-runtime
            :decide (lambda (event)
                      (declare (ignore event))
                      :stop)))
         (unavailable
           (goal24-fake-runtime
            :branch (goal24-branch-with-prompt 0))))
    (cadr-cli:cache-warmer-start
     (getf unprofitable :warmer) (goal24-request) #'goal24-current)
    (funcall (getf unprofitable :advance) 270000)
    (is (zerop (length (funcall (getf unprofitable :get-calls)))))
    (let ((status
            (cadr-cli:cache-warmer-status
             (getf unprofitable :warmer))))
      (is (eq (cadr-cli:cache-warming-status-state status)
              :inactive))
      (is (eq (cadr-cli:cache-warming-decision-action
               (cadr-cli:cache-warming-status-decision status))
              :stop))
      (is (cadr-cli:cache-warming-decision-economics-available
           (cadr-cli:cache-warming-status-decision status)))
      (is (null
           (cadr-cli:cache-warming-status-extension-override
            status))))

    (cadr-cli:cache-warmer-start
     (getf forced :warmer) (goal24-request) #'goal24-current)
    (funcall (getf forced :advance) 270000)
    (is (= 1 (length (funcall (getf forced :get-calls)))))
    (is
     (string=
      (cadr-cli::cache-warm-usage-entry-note
       (first (funcall (getf forced :get-warmed))))
      "extension override"))
    (cadr-cli:cache-warmer-cancel (getf forced :warmer))

    (cadr-cli:cache-warmer-start
     (getf vetoed :warmer) (goal24-request) #'goal24-current)
    (funcall (getf vetoed :advance) 270000)
    (is (zerop (length (funcall (getf vetoed :get-calls)))))
    (is
     (cadr-cli:cache-warming-status-extension-override
      (cadr-cli:cache-warmer-status (getf vetoed :warmer))))

    (cadr-cli:cache-warmer-start
     (getf unavailable :warmer) (goal24-request) #'goal24-current)
    (is
     (string=
      (cadr-cli:cache-warming-status-reason
       (cadr-cli:cache-warmer-status
        (getf unavailable :warmer)))
      "cache economics unavailable"))
    (funcall (getf unavailable :advance) 270000)
    (is
     (zerop
      (length (funcall (getf unavailable :get-calls)))))))

(test goal24-cache-warmer-stop-reasons
  (let* ((runtime (goal24-fake-runtime))
         (warmer (getf runtime :warmer))
         (state (getf runtime :state))
         (advance (getf runtime :advance))
         (still-current t))
    (setf (getf state :mode) "off")
    (cadr-cli:cache-warmer-start
     warmer (goal24-request) #'goal24-current)
    (is
     (string=
      (cadr-cli:cache-warming-status-reason
       (cadr-cli:cache-warmer-status warmer))
      "cache warming disabled"))

    (setf (getf state :mode) "idle")
    (cadr-cli:cache-warmer-start
     warmer
     (goal24-request (goal24-unknown-model))
     #'goal24-current)
    (is
     (string=
      (cadr-cli:cache-warming-status-reason
       (cadr-cli:cache-warmer-status warmer))
      "cache lifetime unavailable"))

    (cadr-cli:cache-warmer-start
     warmer
     (goal24-request
      (goal24-budget-model)
      (list :reasoning "high"))
     #'goal24-current)
    (is
     (string=
      (cadr-cli:cache-warming-status-reason
       (cadr-cli:cache-warmer-status warmer))
      "request cannot be replayed safely"))

    (cadr-cli:cache-warmer-start
     warmer
     (goal24-request)
     (lambda () still-current))
    (setf still-current nil)
    (is
     (string=
      (cadr-cli:cache-warming-status-reason
       (cadr-cli:cache-warmer-status warmer))
      "conversation context changed"))
    (funcall advance 270000)
    (is (zerop (length (funcall (getf runtime :get-calls)))))

    (setf still-current t)
    (cadr-cli:cache-warmer-start
     warmer (goal24-request) #'goal24-current)
    (setf (getf state :mode) "off")
    (funcall advance 270000)
    (is (zerop (length (funcall (getf runtime :get-calls)))))

    (let ((streaming
            (goal24-fake-runtime
             :mode "streaming"
             :branch (goal24-branch-with-prompt 400000))))
      (cadr-cli:cache-warmer-start
       (getf streaming :warmer) (goal24-request) #'goal24-current)
      (cadr-cli:cache-warmer-on-agent-settled
       (getf streaming :warmer))
      (is
       (string=
        (cadr-cli:cache-warming-status-reason
         (cadr-cli:cache-warmer-status
          (getf streaming :warmer)))
        "agent run settled")))))

(test goal24-cache-warmer-abort-and-failed-refresh
  (let* ((pending (goal24-fake-runtime))
         (failed
           (goal24-fake-runtime
            :result
            (lambda (model options)
              (declare (ignore options))
              (goal24-response model :error)))))
    (setf (getf (getf pending :state) :block-refresh) t)
    (cadr-cli:cache-warmer-start
     (getf pending :warmer) (goal24-request) #'goal24-current)
    (let ((advance-thread
            (sb-thread:make-thread
             (lambda ()
               (funcall (getf pending :advance) 270000))
             :name "goal24-cache-warm-advance")))
      (loop repeat 100
            until (plusp
                   (length
                    (funcall (getf pending :get-calls))))
            do (sleep 0.01))
      (is (= 1 (length (funcall (getf pending :get-calls)))))
      (let* ((first-options
               (getf
                (first (funcall (getf pending :get-calls)))
                :options))
             (abort-p (getf first-options :abort-p)))
        (cadr-cli:cache-warmer-start
         (getf pending :warmer) (goal24-request) #'goal24-current)
        (is (funcall abort-p))
        (setf (getf (getf pending :state) :release-refresh) t)
        (sb-thread:join-thread advance-thread)
        (cadr-cli:cache-warmer-cancel (getf pending :warmer))
        (funcall (getf pending :advance) 600000)
        (is (= 1 (length (funcall (getf pending :get-calls)))))))

    (cadr-cli:cache-warmer-start
     (getf failed :warmer) (goal24-request) #'goal24-current)
    (funcall (getf failed :advance) 270000)
    (is
     (zerop
      (length (funcall (getf failed :get-appended)))))
    (cadr-cli:cache-warmer-cancel (getf failed :warmer))))

(test goal24-cache-warmer-format-status-and-usage
  (let ((decision
          (cadr-cli:make-cache-warming-decision
           :phase :idle
           :warm-cost 0.013d0
           :miss-cost 0.621d0
           :continuation-probability 0.6d0
           :expected-savings 0.36d0
           :economics-available t
           :action :warm)))
    (is
     (string=
      (cadr-cli:format-cache-warming-status
       (cadr-cli:make-cache-warming-status
        :state :scheduled
        :next-warm-at 222000
        :decision decision)
       0)
      "Decision in 3m 42s (60% continuation probability, expected savings $0.360 >= $0.050 -> warm)"))
    (is
     (string=
      (cadr-cli:format-cache-warming-usage
       (cadr-cli:make-cache-warm-usage-entry
        :note "extension override"
        :usage
        (cadr-ai:make-usage
         :input 0 :output 1 :cache-read 100
         :cost
         (cadr-ai:make-cost
          :input 0.00004d0
          :output 0.00005d0
          :cache-read 0.02940725d0
          :cache-write 0d0
          :total 0.02949725d0))))
      "Cache warmed (extension override): $0.029497"))))

(test goal24-session-info-uses-cache-warming-formatter
  (with-test-directory (directory)
    (let* ((cwd (namestring directory))
           (session
             (cadr-agent:create-session
              :cwd cwd
              :directory directory))
           (output (make-string-output-stream))
           (status
             (cadr-cli:make-cache-warming-status
              :state :inactive
              :reason "waiting for first request")))
      (cadr-cli::write-session-command-info
       session output
       :cache-warming-mode "idle"
       :cache-warming-status status)
      (let ((plain
              (cadr-tui:strip-terminal-sequences
               (get-output-stream-string output))))
        (is (search (format nil "Cache Warming~%Mode: idle") plain))
        (is
         (search
          "Status: Inactive (waiting for first request)"
          plain))))))
