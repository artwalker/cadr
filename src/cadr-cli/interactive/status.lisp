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

