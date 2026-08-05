(in-package #:cadr-cli)

(defstruct (status-log
            (:constructor make-status-log ()))
  (entries nil :type list)
  last-status-index)

(defun status-log-add-content (log text)
  (setf
   (status-log-entries log)
   (append
    (status-log-entries log)
    (list (cons :content text)))
   (status-log-last-status-index log)
   nil)
  log)

(defun status-log-show (log text)
  (let ((index
          (status-log-last-status-index log)))
    (if (and index
             (= index
                (1- (length
                     (status-log-entries log)))))
        (setf
         (nth index (status-log-entries log))
         (cons :status text))
        (progn
          (setf
           (status-log-entries log)
           (append
            (status-log-entries log)
            (list (cons :status text))))
          (setf
           (status-log-last-status-index log)
           (1-
            (length
             (status-log-entries log)))))))
  log)

(defstruct (startup-input-queue
            (:constructor make-startup-input-queue
                ()))
  (items nil :type list)
  (lock
    (sb-thread:make-mutex
     :name "cadr startup input")))

(defun queue-startup-input (queue text)
  (let ((trimmed
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           text)))
    (when (plusp (length trimmed))
      (sb-thread:with-mutex
          ((startup-input-queue-lock queue))
        (setf
         (startup-input-queue-items queue)
         (append
          (startup-input-queue-items queue)
          (list trimmed))))))
  queue)

(defun pop-startup-input (queue)
  (sb-thread:with-mutex
      ((startup-input-queue-lock queue))
    (when
        (startup-input-queue-items queue)
      (pop
       (startup-input-queue-items queue)))))

(defparameter +anthropic-subscription-auth-warning+
  "Anthropic subscription auth is active. Third-party harness usage draws from extra usage and is billed per token, not your Claude plan limits. Manage extra usage at https://claude.ai/settings/usage. Disable this warning in /settings.")

(defstruct anthropic-warning-state
  (shown-p nil :type boolean))

(defun anthropic-provider-p (provider)
  (string=
   "anthropic"
   (string-downcase
    (typecase provider
      (symbol (symbol-name provider))
      (string provider)
      (otherwise "")))))

(defun anthropic-warning-enabled-p
    (settings)
  (let ((warnings
          (and
           (hash-table-p settings)
           (cadr-ai::json-get
            settings "warnings"))))
    (not
     (and
      (hash-table-p warnings)
      (null
       (cadr-ai::json-get
        warnings
        "anthropicExtraUsage"
        t))))))

(defun anthropic-subscription-credential-p
    (credential)
  (or
   (eq credential :oauth)
   (typep credential
          'cadr-ai:oauth-credential)
   (let ((key
           (cond
             ((stringp credential)
              credential)
             ((typep
               credential
               'cadr-ai:api-key-credential)
              (cadr-ai:api-key-credential-key
               credential))
             (t nil))))
     (and
      key
      (uiop:string-prefix-p
       "sk-ant-oat" key)))))

(defun maybe-anthropic-subscription-warning
    (state provider settings
     credential-function)
  (when
      (or
       (anthropic-warning-state-shown-p
        state)
       (not
        (anthropic-warning-enabled-p
         settings))
       (not
        (anthropic-provider-p provider)))
    (return-from
        maybe-anthropic-subscription-warning
      nil))
  (handler-case
      (when
          (anthropic-subscription-credential-p
           (funcall credential-function))
        (setf
         (anthropic-warning-state-shown-p
          state)
         t)
        +anthropic-subscription-auth-warning+)
    (condition () nil)))

(defparameter +tui-spinner-frames+
  #("⠋" "⠙" "⠹" "⠸" "⠼"
    "⠴" "⠦" "⠧" "⠇" "⠏"))

(defconstant +tui-spinner-interval-seconds+
  0.08d0)

(defconstant +tui-min-render-interval-seconds+
  0.016d0)

(defun tui-monotonic-seconds ()
  (/ (get-internal-real-time)
     (coerce internal-time-units-per-second
             'double-float)))

(defstruct (tui-render-coordinator
            (:constructor
                %make-tui-render-coordinator))
  (lock
    (sb-thread:make-mutex
     :name "cadr-tui-render-coordinator"))
  (clock-function #'tui-monotonic-seconds
                  :type function)
  (interval +tui-min-render-interval-seconds+
            :type double-float)
  last-render-at
  (pending-p nil :type boolean)
  (force-p nil :type boolean)
  (stopped-p nil :type boolean))

(defun make-tui-render-coordinator
    (&key
       (clock-function #'tui-monotonic-seconds)
       (interval +tui-min-render-interval-seconds+))
  (%make-tui-render-coordinator
   :clock-function clock-function
   :interval (coerce interval 'double-float)))

(defun request-tui-render
    (coordinator &optional force-p)
  (sb-thread:with-mutex
      ((tui-render-coordinator-lock coordinator))
    (unless
        (tui-render-coordinator-stopped-p
         coordinator)
      (setf
       (tui-render-coordinator-pending-p
        coordinator)
       t
       (tui-render-coordinator-force-p
        coordinator)
       (or force-p
           (tui-render-coordinator-force-p
            coordinator)))))
  nil)

(defun flush-tui-render
    (coordinator render-function
     &key force-p)
  (let ((render-p nil))
    (sb-thread:with-mutex
        ((tui-render-coordinator-lock coordinator))
      (unless
          (tui-render-coordinator-stopped-p
           coordinator)
        (let* ((now
                 (funcall
                  (tui-render-coordinator-clock-function
                   coordinator)))
               (last-render-at
                 (tui-render-coordinator-last-render-at
                  coordinator))
               (due-p
                 (or force-p
                     (tui-render-coordinator-force-p
                      coordinator)
                     (null last-render-at)
                     (>= (- now last-render-at)
                         (tui-render-coordinator-interval
                          coordinator)))))
          (when
              (and
               (or force-p
                   (tui-render-coordinator-pending-p
                    coordinator))
               due-p)
            (setf
             render-p t
             (tui-render-coordinator-pending-p
              coordinator)
             nil
             (tui-render-coordinator-force-p
              coordinator)
             nil
             (tui-render-coordinator-last-render-at
              coordinator)
             now)))))
    (when render-p
      ;; Rendering takes the independent TUI state mutex.  Never
      ;; call it while holding the coordinator mutex: a render may
      ;; itself enqueue the next, final frame.
      (funcall render-function))
    render-p))

(defun stop-tui-render-coordinator (coordinator)
  (sb-thread:with-mutex
      ((tui-render-coordinator-lock coordinator))
    (setf
     (tui-render-coordinator-stopped-p coordinator)
     t
     (tui-render-coordinator-pending-p coordinator)
     nil
     (tui-render-coordinator-force-p coordinator)
     nil))
  nil)

(defstruct tui-status-animation
  (active-p nil :type boolean)
  (frame-index 0 :type (integer 0 *))
  (frame (aref +tui-spinner-frames+ 0)
         :type string)
  next-frame-at
  tracked-status
  retry-attempt
  retry-maximum
  retry-deadline
  retry-seconds)

(defun parse-tui-retry-status (message)
  (when message
    (multiple-value-bind (match registers)
        (cl-ppcre:scan-to-strings
         "^Retrying \\(([0-9]+)/([0-9]+)\\) in ([0-9]+)s\\.\\.\\.$"
         message)
      (declare (ignore match))
      (when registers
        (values
         (parse-integer (aref registers 0))
         (parse-integer (aref registers 1))
         (parse-integer (aref registers 2)))))))

(defun reset-tui-status-animation
    (animation message now)
  (setf
   (tui-status-animation-active-p animation) t
   (tui-status-animation-frame-index animation) 0
   (tui-status-animation-frame animation)
   (aref +tui-spinner-frames+ 0)
   (tui-status-animation-next-frame-at animation)
   (+ now +tui-spinner-interval-seconds+)
   (tui-status-animation-tracked-status animation)
   message
   (tui-status-animation-retry-attempt animation)
   nil
   (tui-status-animation-retry-maximum animation)
   nil
   (tui-status-animation-retry-deadline animation)
   nil
   (tui-status-animation-retry-seconds animation)
   nil)
  (multiple-value-bind (attempt maximum seconds)
      (parse-tui-retry-status message)
    (when attempt
      (setf
       (tui-status-animation-retry-attempt animation)
       attempt
       (tui-status-animation-retry-maximum animation)
       maximum
       (tui-status-animation-retry-deadline animation)
       (+ now seconds)
       (tui-status-animation-retry-seconds animation)
       seconds))))

(defun advance-tui-status-animation
    (animation state busy-p now)
  (let* ((message
           (tui-state-status-message state))
         (active-p
           (not (null (or message busy-p))))
         (changed-p nil))
    (cond
      ((not active-p)
       (when
           (tui-status-animation-active-p animation)
         (setf changed-p t))
       (setf
        (tui-status-animation-active-p animation)
        nil
        (tui-status-animation-frame-index animation)
        0
        (tui-status-animation-frame animation)
        (aref +tui-spinner-frames+ 0)
        (tui-status-animation-next-frame-at animation)
        nil
        (tui-status-animation-tracked-status animation)
        nil
        (tui-status-animation-retry-deadline animation)
        nil))
      ((or
        (not
         (tui-status-animation-active-p animation))
        (not
         (equal message
                (tui-status-animation-tracked-status
                 animation))))
       (reset-tui-status-animation
        animation message now)
       (setf changed-p t)))
    (when
        (tui-status-animation-active-p animation)
      (let ((next
              (tui-status-animation-next-frame-at
               animation)))
        (when (and next (>= now next))
          (let ((steps
                  (1+
                   (floor
                    (- now next)
                    +tui-spinner-interval-seconds+))))
            (setf
             (tui-status-animation-frame-index
              animation)
             (mod
              (+
               (tui-status-animation-frame-index
                animation)
               steps)
              (length +tui-spinner-frames+))
             (tui-status-animation-next-frame-at
              animation)
             (+ next
                (* steps
                   +tui-spinner-interval-seconds+))
             (tui-status-animation-frame animation)
             (aref
              +tui-spinner-frames+
              (tui-status-animation-frame-index
               animation))
             changed-p t))))
      (let ((deadline
              (tui-status-animation-retry-deadline
               animation)))
        (when deadline
          (let ((seconds
                  (max 0
                       (ceiling (- deadline now)))))
            (unless
                (eql
                 seconds
                 (tui-status-animation-retry-seconds
                  animation))
              (let ((updated
                      (format
                       nil "Retrying (~D/~D) in ~Ds..."
                       (tui-status-animation-retry-attempt
                        animation)
                       (tui-status-animation-retry-maximum
                        animation)
                       seconds)))
                (setf
                 (tui-status-animation-retry-seconds
                  animation)
                 seconds
                 (tui-status-animation-tracked-status
                  animation)
                 updated
                 (tui-state-status-message state)
                 updated
                 changed-p t)))))))
    changed-p))

(defun render-tui-status-indicator
    (message width &key
                     (reserve-idle-p t)
                     (spinner-frame
                       (aref
                        +tui-spinner-frames+ 0)))
  (let ((blank
          (make-string width
                       :initial-element #\Space)))
    (if message
        (let* ((frame
                 (or spinner-frame ""))
               (separator
                 (if (plusp (length frame))
                     " " ""))
               (spinner-token
                 (if
                     (uiop:string-prefix-p
                      "Retrying (" message)
                     :warning
                     :accent)))
          (cons
           ""
           (component-text-lines
            (concatenate
             'string
             (cadr-tui:theme-foreground
              spinner-token frame
              :enabled-p t)
             separator
             (cadr-tui:theme-foreground
              :muted message
              :enabled-p t))
            width)))
        (and reserve-idle-p
             (list blank blank)))))
