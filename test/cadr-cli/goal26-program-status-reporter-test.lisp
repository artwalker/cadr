(in-package #:cadr-cli/tests)

;;; Goal 26: OSC 7501 ProgramStatusReporter (pi #10607).

(defclass fake-program-status-terminal (cadr-tui:terminal)
  ((reports
    :initform nil
    :accessor fake-program-status-reports)))

(defmethod cadr-tui:terminal-set-program-status
    ((terminal fake-program-status-terminal) status)
  (push status (fake-program-status-reports terminal))
  status)

(defun goal26-program-status-setup
    (&optional (session-name nil))
  (let* ((session (list :name session-name))
         (terminal
           (make-instance
            'fake-program-status-terminal))
         (reporter
           (cadr-cli::make-program-status-reporter
            (lambda () terminal)
            (lambda () (getf session :name)))))
    (list :session session
          :terminal terminal
          :reporter reporter)))

(defun goal26-program-status-send (env &rest events)
  (dolist (event events)
    (cadr-cli::program-status-reporter-handle-event
     (getf env :reporter) event)))

(defun goal26-program-status-last (env)
  (let* ((status
           (first
            (fake-program-status-reports
             (getf env :terminal))))
         (state
           (cadr-tui:program-status-state status))
         (kind (cadr-tui:program-status-kind status))
         (message
           (cadr-tui:program-status-message status)))
    (append
     (list :state state)
     (when kind (list :kind kind))
     (when message (list :message message)))))

(defun goal26-assistant-end
    (stop-reason &optional error-message)
  (cadr-agent::make-agent-event
   :type :message-end
   :message
   (cadr-ai:make-assistant-message
    :content
    (list
     (cadr-ai:make-text-content
      :text "secret assistant output"))
    :stop-reason stop-reason
    :error-message error-message)))

(defun goal26-settled (&optional aborted-p)
  (cadr-agent::make-agent-event
   :type :agent-settled
   :aborted (and aborted-p t)))

(defun goal26-compaction-end
    (reason &key aborted error-message)
  (cadr-agent::make-agent-event
   :type :compaction-end
   :reason reason
   :aborted (and aborted t)
   :error-message error-message))

;; #10607
(fiveam:test
    goal26-program-status-reports-idle-working-done
  (let ((env (goal26-program-status-setup "Fix login")))
    (cadr-cli::program-status-reporter-report
     (getf env :reporter))
    (let ((first
            (first
             (fake-program-status-reports
              (getf env :terminal)))))
      (fiveam:is
       (eq :idle
           (cadr-tui:program-status-state first)))
      (fiveam:is
       (string=
        "cadr"
        (cadr-tui:program-status-app first))))
    (goal26-program-status-send
     env
     (cadr-agent::make-agent-event :type :agent-start))
    (fiveam:is
     (equal
      '(:state :working :message "Fix login")
      (goal26-program-status-last env)))
    (goal26-program-status-send
     env
     (goal26-assistant-end :tool-use)
     (goal26-assistant-end :stop))
    (fiveam:is
     (equal
      '(:state :working :message "Fix login")
      (goal26-program-status-last env)))
    (goal26-program-status-send env (goal26-settled))
    (fiveam:is
     (equal
      '(:state :done :message "Fix login")
      (goal26-program-status-last env)))
    (fiveam:is
     (not
      (search
       "secret assistant output"
       (princ-to-string
        (fake-program-status-reports
         (getf env :terminal))))))))

(fiveam:test
    goal26-program-status-reports-run-outcomes
  (let ((env (goal26-program-status-setup)))
    (goal26-program-status-send
     env
     (cadr-agent::make-agent-event :type :agent-start)
     (goal26-assistant-end :error "overloaded")
     (goal26-assistant-end :stop)
     (goal26-settled))
    (fiveam:is
     (equal '(:state :done)
            (goal26-program-status-last env)))
    (goal26-program-status-send
     env
     (cadr-agent::make-agent-event :type :agent-start)
     (goal26-assistant-end
      :error
      (format nil "Invalid API key~%{details}"))
     (goal26-settled))
    (fiveam:is
     (equal
      '(:state :error :message "Invalid API key")
      (goal26-program-status-last env)))
    (goal26-program-status-send
     env
     (cadr-agent::make-agent-event :type :agent-start)
     (goal26-assistant-end :aborted)
     (goal26-settled t))
    (fiveam:is
     (equal '(:state :idle)
            (goal26-program-status-last env)))
    (goal26-program-status-send
     env
     (cadr-agent::make-agent-event :type :agent-start)
     (goal26-assistant-end :stop)
     (goal26-settled t))
    (fiveam:is
     (equal '(:state :idle)
            (goal26-program-status-last env)))))

(fiveam:test
    goal26-program-status-reports-blocked-dialogs
  (let ((env (goal26-program-status-setup))
        (reporter nil))
    (setf reporter (getf env :reporter))
    (goal26-program-status-send
     env
     (cadr-agent::make-agent-event :type :agent-start))
    (cadr-cli::program-status-reporter-set-blocked
     reporter
     "extension-selector"
     (list :kind :permission :message "Allow bash?"))
    (cadr-cli::program-status-reporter-set-blocked
     reporter
     "login"
     (list :kind :auth :message "Log in to Anthropic"))
    (fiveam:is
     (equal
      '(:state :blocked :kind :auth
        :message "Log in to Anthropic")
      (goal26-program-status-last env)))
    (cadr-cli::program-status-reporter-set-blocked
     reporter "login" nil)
    (goal26-program-status-send
     env
     (goal26-assistant-end :stop)
     (goal26-settled))
    (fiveam:is
     (equal
      '(:state :blocked :kind :permission
        :message "Allow bash?")
      (goal26-program-status-last env)))
    (cadr-cli::program-status-reporter-set-blocked
     reporter
     "extension-selector"
     (list :kind :question :message "Pick one"))
    (fiveam:is
     (equal
      '(:state :blocked :kind :question
        :message "Pick one")
      (goal26-program-status-last env)))
    (cadr-cli::program-status-reporter-set-blocked
     reporter "extension-selector" nil)
    (fiveam:is
     (equal '(:state :done)
            (goal26-program-status-last env)))))

(fiveam:test
    goal26-program-status-reset-returns-idle
  (let ((env (goal26-program-status-setup)))
    (goal26-program-status-send
     env
     (cadr-agent::make-agent-event :type :agent-start)
     (goal26-assistant-end :stop)
     (goal26-settled))
    (cadr-cli::program-status-reporter-reset
     (getf env :reporter))
    (fiveam:is
     (equal '(:state :idle)
            (goal26-program-status-last env)))))
