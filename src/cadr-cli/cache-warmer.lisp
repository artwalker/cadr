(in-package #:cadr-cli)

;;; Baseline: packages/coding-agent/src/core/cache-warmer.ts (13cbf77df).
;;; Live agent-settle / stream dispatch is a follow-up.

(defconstant +max-warming-age-ms+ (* 60 60 1000))
(defconstant +max-idle-warming-age-ms+ (* 30 60 1000))
(defconstant +cache-warming-minimum-expected-savings+ 0.05d0)
(defconstant +idle-continuation-probability+ 0.15d0)

(defstruct cache-warm-model
  (id "" :type string)
  (provider :anthropic)
  (api :anthropic-messages)
  prompt-cache
  cost
  compat)

(defstruct cache-warming-decision
  (phase :streaming)
  (warm-cost 0d0 :type double-float)
  (miss-cost 0d0 :type double-float)
  (continuation-probability 1d0 :type double-float)
  (expected-savings 0d0 :type double-float)
  (economics-available nil :type boolean)
  (action :stop))

(defstruct cache-warming-status
  (state :inactive)
  reason
  next-warm-at
  decision
  extension-override)

(defstruct cache-warm-request
  model
  context
  options)

(defstruct cache-warm-usage-entry
  (kind "cache_warm" :type string)
  provider
  model-id
  usage
  note)

(defstruct cache-warm-run
  model
  context
  options
  is-current
  (delay-ms 0 :type integer)
  (started-at 0 :type integer)
  (aborted-p nil :type boolean)
  (phase :streaming)
  (next-warm-at 0 :type integer)
  (extension-override nil :type boolean)
  cancel-timer)

(defstruct (cache-warmer
            (:constructor %make-cache-warmer))
  stream-simple
  get-branch
  append-usage
  get-mode
  decide
  on-warmed
  now-fn
  schedule-fn
  run
  (inactive
   (make-cache-warming-status
    :state :inactive
    :reason "waiting for first request")))

(defun get-cache-warming-delay-ms (ttl-ms)
  (when (> ttl-ms 10000)
    (max 1
         (floor
          (min (* ttl-ms 0.9d0)
               (- ttl-ms 10000))))))

(defun %cache-retention-keyword (value)
  (cond
    ((null value) nil)
    ((eq value :none) :none)
    ((eq value :long) :long)
    ((eq value :short) :short)
    ((stringp value)
     (cond
       ((string= value "none") :none)
       ((string= value "long") :long)
       ((string= value "short") :short)
       (t nil)))
    (t nil)))

(defun %cache-retention-from-env (environment)
  (let ((value
          (or (and environment
                   (cadr-ai::environment-value
                    environment "CADR_CACHE_RETENTION"))
              (uiop:getenv "CADR_CACHE_RETENTION")
              "")))
    (when (string= value "long")
      :long)))

(defun get-prompt-cache-ttl-ms (model options)
  (let* ((options (or options '()))
         (retention
           (or (%cache-retention-keyword
                (getf options :cache-retention))
               (%cache-retention-from-env
                (getf options :env))
               :short))
         (prompt-cache (cache-warm-model-prompt-cache model)))
    (when (eq retention :none)
      (return-from get-prompt-cache-ttl-ms nil))
    (when prompt-cache
      (let ((seconds (getf prompt-cache retention)))
        (when seconds
          (* seconds 1000))))))

(defun is-replayable (model options)
  (let ((options (or options '())))
    (or (null (getf options :reasoning))
        (not (eq (cache-warm-model-api model)
                 :anthropic-messages))
        (eq (getf (cache-warm-model-compat model)
                  :force-adaptive-thinking)
            t))))

(defun %usage-total-cost (usage)
  (cond
    ((typep usage 'cadr-ai:usage)
     (cadr-ai:cost-total (cadr-ai:usage-cost usage)))
    ((listp usage)
     (let ((cost (getf usage :cost)))
       (if (listp cost)
           (coerce (or (getf cost :total) 0) 'double-float)
           (coerce (or cost 0) 'double-float))))
    (t 0d0)))

(defun %warm-price (model tokens)
  (let* ((cost (or (cache-warm-model-cost model) '()))
         (input (coerce (or (getf tokens :input) 0) 'double-float))
         (output (coerce (or (getf tokens :output) 0) 'double-float))
         (cache-read
           (coerce (or (getf tokens :cache-read) 0) 'double-float))
         (cache-write
           (coerce (or (getf tokens :cache-write) 0) 'double-float))
         (input-price
           (coerce (or (getf cost :input) 0) 'double-float))
         (output-price
           (coerce (or (getf cost :output) 0) 'double-float))
         (cache-read-price
           (coerce (or (getf cost :cache-read) 0) 'double-float))
         (cache-write-price
           (coerce (or (getf cost :cache-write) 0) 'double-float)))
    (+ (* (/ input 1000000d0) input-price)
       (* (/ output 1000000d0) output-price)
       (* (/ cache-read 1000000d0) cache-read-price)
       (* (/ cache-write 1000000d0) cache-write-price))))

(defun %entry-assistant-usage (entry)
  (cond
    ((typep entry 'cadr-agent:session-entry)
     (when (eq (cadr-agent:session-entry-type entry) :message)
       (let ((message (cadr-agent:session-entry-message entry)))
         (when (typep message 'cadr-ai:assistant-message)
           (cadr-ai:assistant-message-usage message)))))
    ((listp entry)
     (when (eq (getf entry :type) :message)
       (let ((message (getf entry :message)))
         (cond
           ((typep message 'cadr-ai:assistant-message)
            (cadr-ai:assistant-message-usage message))
           ((listp message)
            (when (eq (getf message :role) :assistant)
              (getf message :usage)))
           (t nil)))))
    (t nil)))

(defun %usage-prompt-tokens (usage)
  (cond
    ((typep usage 'cadr-ai:usage)
     (+ (cadr-ai:usage-input usage)
        (cadr-ai:usage-cache-read usage)
        (cadr-ai:usage-cache-write usage)))
    ((listp usage)
     (+ (or (getf usage :input) 0)
        (or (getf usage :cache-read) 0)
        (or (getf usage :cache-write) 0)))
    (t 0)))

(defun last-prompt-tokens (entries)
  (loop for entry in (reverse entries)
        for usage = (%entry-assistant-usage entry)
        when usage
          return (%usage-prompt-tokens usage)
        finally (return 0)))

(defun %default-now-ms ()
  (cadr-core:unix-milliseconds))

(defun %default-schedule (delay-ms thunk)
  (let* ((stop-p nil)
         (thread
           (sb-thread:make-thread
            (lambda ()
              (unless stop-p
                (sleep (/ (max 0 delay-ms) 1000d0)))
              (unless stop-p
                (funcall thunk)))
            :name "cadr-cache-warmer")))
    (lambda ()
      (setf stop-p t)
      (ignore-errors
        (sb-thread:terminate-thread thread)))))

(defun make-cache-warmer
    (stream-simple get-branch append-usage get-mode
     &key
       (decide
        (lambda (event)
          (getf event :action)))
       on-warmed
       (now-fn #'%default-now-ms)
       (schedule-fn #'%default-schedule))
  (%make-cache-warmer
   :stream-simple stream-simple
   :get-branch get-branch
   :append-usage append-usage
   :get-mode get-mode
   :decide decide
   :on-warmed on-warmed
   :now-fn now-fn
   :schedule-fn schedule-fn))

(defun %normalize-mode (mode)
  (cond
    ((null mode) "streaming")
    ((stringp mode) mode)
    ((eq mode :off) "off")
    ((eq mode :streaming) "streaming")
    ((eq mode :idle) "idle")
    (t (string-downcase (string mode)))))

(defun cache-warmer-mode (warmer)
  (%normalize-mode
   (funcall (cache-warmer-get-mode warmer))))

(defun %clear-run (warmer)
  (let ((run (cache-warmer-run warmer)))
    (when run
      (setf (cache-warmer-run warmer) nil
            (cache-warm-run-aborted-p run) t)
      (when (cache-warm-run-cancel-timer run)
        (funcall (cache-warm-run-cancel-timer run))
        (setf (cache-warm-run-cancel-timer run) nil)))))

(defun %stop-warmer (warmer reason &key decision extension-override)
  (%clear-run warmer)
  (setf (cache-warmer-inactive warmer)
        (make-cache-warming-status
         :state :inactive
         :reason reason
         :decision decision
         :extension-override extension-override)))

(defun %evaluate-run (warmer run)
  (let* ((model (cache-warm-run-model run))
         (prompt-tokens
           (last-prompt-tokens
            (funcall (cache-warmer-get-branch warmer))))
         (cache-hit-cost
           (%warm-price model (list :cache-read prompt-tokens)))
         (cache-write-price
           (or (getf (cache-warm-model-cost model) :cache-write)
               0))
         (cache-miss-cost
           (%warm-price
            model
            (if (> cache-write-price 0)
                (list :cache-write prompt-tokens)
                (list :input prompt-tokens))))
         (warm-cost
           (%warm-price
            model
            (list :cache-read prompt-tokens :output 1)))
         (miss-cost (max 0d0 (- cache-miss-cost cache-hit-cost)))
         (continuation-probability
           (if (eq (cache-warm-run-phase run) :idle)
               +idle-continuation-probability+
               1d0))
         (economics-available
           (and (> prompt-tokens 0)
                (or (> cache-hit-cost 0d0)
                    (> cache-miss-cost 0d0))))
         (expected-savings
           (- (* continuation-probability miss-cost) warm-cost)))
    (make-cache-warming-decision
     :phase (cache-warm-run-phase run)
     :warm-cost warm-cost
     :miss-cost miss-cost
     :continuation-probability continuation-probability
     :expected-savings expected-savings
     :economics-available economics-available
     :action
     (if (>= expected-savings
             +cache-warming-minimum-expected-savings+)
         :warm
         :stop))))

(defun %mode-stop-reason (warmer run)
  (let ((mode (cache-warmer-mode warmer)))
    (cond
      ((string= mode "off") "cache warming disabled")
      ((and (string= mode "streaming")
            (eq (cache-warm-run-phase run) :idle))
       "agent run settled")
      (t nil))))

(defun %validate-run (warmer run)
  (cond
    ((not (eq (cache-warmer-run warmer) run)) nil)
    (t
     (let ((reason
             (or (%mode-stop-reason warmer run)
                 (unless (funcall (cache-warm-run-is-current run))
                   "conversation context changed"))))
       (if reason
           (progn
             (%stop-warmer warmer reason)
             nil)
           t)))))

(defun cache-warmer-status (warmer)
  (when (string= (cache-warmer-mode warmer) "off")
    (return-from cache-warmer-status
      (make-cache-warming-status
       :state :inactive
       :reason "cache warming disabled")))
  (let ((run (cache-warmer-run warmer)))
    (unless run
      (return-from cache-warmer-status
        (cache-warmer-inactive warmer)))
    (unless (funcall (cache-warm-run-is-current run))
      (return-from cache-warmer-status
        (make-cache-warming-status
         :state :inactive
         :reason "conversation context changed")))
    (let* ((decision (%evaluate-run warmer run))
           (refreshing
             (null (cache-warm-run-cancel-timer run))))
      (when (and (not (cache-warming-decision-economics-available
                       decision))
                 (not refreshing))
        (return-from cache-warmer-status
          (make-cache-warming-status
           :state :inactive
           :reason "cache economics unavailable")))
      (make-cache-warming-status
       :state (if refreshing :refreshing :scheduled)
       :next-warm-at (cache-warm-run-next-warm-at run)
       :decision decision
       :extension-override
       (cache-warm-run-extension-override run)))))

(defun %schedule-run (warmer run)
  (setf (cache-warm-run-extension-override run) nil
        (cache-warm-run-next-warm-at run)
        (+ (funcall (cache-warmer-now-fn warmer))
           (cache-warm-run-delay-ms run)))
  (let* ((now (funcall (cache-warmer-now-fn warmer)))
         (deadline
           (+ (cache-warm-run-started-at run)
              (if (eq (cache-warm-run-phase run) :idle)
                  +max-idle-warming-age-ms+
                  +max-warming-age-ms+))))
    (when (or (> (cache-warm-run-next-warm-at run) deadline)
              (>= now deadline))
      (%stop-warmer
       warmer
       (if (eq (cache-warm-run-phase run) :idle)
           "30-minute idle safety limit reached"
           "one-hour safety limit reached"))
      (return-from %schedule-run))
    (setf (cache-warm-run-cancel-timer run)
          (funcall
           (cache-warmer-schedule-fn warmer)
           (max 0
                (- (cache-warm-run-next-warm-at run) now))
           (lambda ()
             (%refresh-run warmer run))))))

(defun %refresh-run (warmer run)
  (setf (cache-warm-run-cancel-timer run) nil)
  (unless (%validate-run warmer run)
    (return-from %refresh-run))
  (let* ((decision (%evaluate-run warmer run))
         (action (cache-warming-decision-action decision)))
    (handler-case
        (setf action
              (funcall
               (cache-warmer-decide warmer)
               (list :type :cache-warming-decision
                     :warm-cost
                     (cache-warming-decision-warm-cost decision)
                     :miss-cost
                     (cache-warming-decision-miss-cost decision)
                     :continuation-probability
                     (cache-warming-decision-continuation-probability
                      decision)
                     :action action)))
      (condition ()
        nil))
    (setf action
          (cond
            ((eq action :warm) :warm)
            ((eq action :stop) :stop)
            ((and (stringp action) (string= action "warm")) :warm)
            ((and (stringp action) (string= action "stop")) :stop)
            (t action)))
    (unless (%validate-run warmer run)
      (return-from %refresh-run))
    (let ((extension-override
            (not (eq action
                     (cache-warming-decision-action decision)))))
      (when (eq action :stop)
        (%stop-warmer
         warmer
         (cond
           (extension-override "stopped by extension")
           ((cache-warming-decision-economics-available decision)
            "expected savings below threshold")
           (t "cache economics unavailable"))
         :decision decision
         :extension-override extension-override)
        (return-from %refresh-run))
      (setf (cache-warm-run-extension-override run)
            extension-override)
      (handler-case
          (let* ((options
                   (append
                    (copy-list (cache-warm-run-options run))
                    (list :max-tokens 1
                          :max-retries 0
                          :abort-p
                          (lambda ()
                            (cache-warm-run-aborted-p run)))))
                 (message
                   (funcall
                    (cache-warmer-stream-simple warmer)
                    (cache-warm-run-model run)
                    (cache-warm-run-context run)
                    options)))
            (unless (%validate-run warmer run)
              (return-from %refresh-run))
            (when (and message
                       (typep message 'cadr-ai:assistant-message)
                       (not
                        (member
                         (cadr-ai:assistant-message-stop-reason
                          message)
                         '(:error :aborted))))
              (let ((entry
                      (funcall
                       (cache-warmer-append-usage warmer)
                       "cache_warm"
                       (cadr-ai:assistant-message-provider message)
                       (or (cadr-ai:assistant-message-response-model
                            message)
                           (cadr-ai:assistant-message-model message))
                       (cadr-ai:assistant-message-usage message)
                       (when extension-override
                         "extension override"))))
                (when (cache-warmer-on-warmed warmer)
                  (funcall (cache-warmer-on-warmed warmer) entry)))))
        (condition ()
          nil))
      (when (eq (cache-warmer-run warmer) run)
        (%schedule-run warmer run)))))

(defun cache-warmer-start (warmer request is-current)
  (%clear-run warmer)
  (let* ((mode (cache-warmer-mode warmer))
         (model (cache-warm-request-model request))
         (options (or (cache-warm-request-options request) '())))
    (when (string= mode "off")
      (%stop-warmer warmer "cache warming disabled")
      (return-from cache-warmer-start))
    (unless (is-replayable model options)
      (%stop-warmer warmer "request cannot be replayed safely")
      (return-from cache-warmer-start))
    (let ((ttl-ms (get-prompt-cache-ttl-ms model options)))
      (unless ttl-ms
        (%stop-warmer
         warmer
         (if (eq (%cache-retention-keyword
                  (getf options :cache-retention))
                 :none)
             "request disabled prompt caching"
             "cache lifetime unavailable"))
        (return-from cache-warmer-start))
      (let ((delay-ms (get-cache-warming-delay-ms ttl-ms)))
        (unless delay-ms
          (%stop-warmer warmer "cache lifetime unavailable")
          (return-from cache-warmer-start))
        (let ((run
                (make-cache-warm-run
                 :model model
                 :context (cache-warm-request-context request)
                 :options options
                 :is-current is-current
                 :delay-ms delay-ms
                 :started-at
                 (funcall (cache-warmer-now-fn warmer))
                 :phase :streaming
                 :next-warm-at 0
                 :extension-override nil)))
          (setf (cache-warmer-run warmer) run)
          (%schedule-run warmer run))))))

(defun cache-warmer-on-agent-settled (warmer)
  (let ((run (cache-warmer-run warmer)))
    (when run
      (when (string= (cache-warmer-mode warmer) "streaming")
        (%stop-warmer warmer "agent run settled")
        (return-from cache-warmer-on-agent-settled))
      (setf (cache-warm-run-phase run) :idle)
      (let* ((now (funcall (cache-warmer-now-fn warmer)))
             (deadline
               (+ (cache-warm-run-started-at run)
                  +max-idle-warming-age-ms+)))
        (when (or (> (cache-warm-run-next-warm-at run) deadline)
                  (>= now deadline))
          (%stop-warmer
           warmer
           "30-minute idle safety limit reached"))))))

(defun cache-warmer-on-mode-changed (warmer)
  (let ((run (cache-warmer-run warmer)))
    (when run
      (let ((reason (%mode-stop-reason warmer run)))
        (when reason
          (%stop-warmer warmer reason))))))

(defun cache-warmer-cancel (warmer)
  (%stop-warmer warmer "inactive"))

(defun format-dollars (value)
  (let ((number (coerce value 'double-float)))
    (if (< number 0d0)
        (format nil "-$~,3F" (abs number))
        (format nil "$~,3F" number))))

(defun format-cache-warming-economics (decision)
  (unless (cache-warming-decision-economics-available decision)
    (return-from format-cache-warming-economics
      "cache economics unavailable"))
  (let* ((probability
           (round
            (* (cache-warming-decision-continuation-probability
                decision)
               100)))
         (probability-text
           (if (eq (cache-warming-decision-phase decision)
                   :streaming)
               (format
                nil
                "~D% continuation probability while agent is running"
                probability)
               (format nil "~D% continuation probability" probability)))
         (comparison
           (if (eq (cache-warming-decision-action decision) :warm)
               ">="
               "<")))
    (format
     nil
     "~A, expected savings ~A ~A $~,3F"
     probability-text
     (format-dollars
      (cache-warming-decision-expected-savings decision))
     comparison
     +cache-warming-minimum-expected-savings+)))

(defun format-cache-warming-decision-time (next-warm-at now)
  (if (or (null next-warm-at) (<= next-warm-at now))
      "Decision now"
      (let* ((remaining-seconds
               (ceiling (/ (- next-warm-at now) 1000d0)))
             (hours (floor remaining-seconds 3600))
             (remaining (mod remaining-seconds 3600))
             (minutes (floor remaining 60))
             (seconds (mod remaining 60))
             (parts '()))
        (when (> hours 0)
          (push (format nil "~Dh" hours) parts))
        (when (> minutes 0)
          (push (format nil "~Dm" minutes) parts))
        (when (or (> seconds 0) (null parts))
          (push (format nil "~Ds" seconds) parts))
        (format nil "Decision in ~{~A~^ ~}" (nreverse parts)))))

(defun format-cache-warming-status (status &optional (now (%default-now-ms)))
  (let ((decision (cache-warming-status-decision status)))
    (when (or (null decision)
              (and (eq (cache-warming-status-state status) :inactive)
                   (not
                    (cache-warming-decision-economics-available
                     decision))
                   (not (cache-warming-status-extension-override
                         status))))
      (return-from format-cache-warming-status
        (format
         nil
         "Inactive (~A)"
         (or (cache-warming-status-reason status)
             "unknown reason"))))
    (let ((details
            (if (cache-warming-status-extension-override status)
                (format
                 nil
                 "extension override, ~A"
                 (format-cache-warming-economics decision))
                (format
                 nil
                 "~A -> ~A"
                 (format-cache-warming-economics decision)
                 (string-downcase
                  (symbol-name
                   (cache-warming-decision-action decision)))))))
      (case (cache-warming-status-state status)
        (:inactive
         (format nil "Stopped (~A)" details))
        (:refreshing
         (format nil "Warming cache (~A)" details))
        (otherwise
         (format
          nil
          "~A (~A)"
          (format-cache-warming-decision-time
           (cache-warming-status-next-warm-at status)
           now)
          details))))))

(defun format-cache-warming-usage (entry)
  (let* ((note
           (cond
             ((typep entry 'cache-warm-usage-entry)
              (cache-warm-usage-entry-note entry))
             ((listp entry) (getf entry :note))
             (t nil)))
         (usage
           (cond
             ((typep entry 'cache-warm-usage-entry)
              (cache-warm-usage-entry-usage entry))
             ((listp entry) (getf entry :usage))
             (t nil)))
         (cost (%usage-total-cost usage))
         (cost-text
           (let ((raw (format nil "~,6F" cost)))
             (cl-ppcre:regex-replace
              "(\\.[0-9]{3}[0-9]*?)0+$"
              raw
              "\\1")))
         (note-text
           (if note
               (format nil " (~A)" note)
               "")))
    (format nil "Cache warmed~A: $~A" note-text cost-text)))
