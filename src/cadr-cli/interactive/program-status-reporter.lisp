(in-package #:cadr-cli)

;;; Interactive OSC 7501 reporter (pi@71023aec program-status-reporter.ts).
;;; Reports working/blocked/done/error/idle; never prompts or assistant text.

(defparameter +program-status-app-name+ "cadr")

(defstruct (program-status-reporter
            (:constructor %make-program-status-reporter)
            (:copier nil))
  (get-terminal nil :type function)
  (get-session-name nil :type function)
  (run-active-p nil :type boolean)
  (compacting-p nil :type boolean)
  (run-result
   (cadr-tui:make-program-status :state :done)
   :type cadr-tui:program-status)
  (resting-status
   (cadr-tui:make-program-status :state :idle)
   :type cadr-tui:program-status)
  (blocked nil :type list)
  (last-report nil :type (or null string)))

(defun make-program-status-reporter
    (get-terminal get-session-name)
  (%make-program-status-reporter
   :get-terminal get-terminal
   :get-session-name get-session-name))

(defun program-status-first-line (text)
  (let* ((raw (or text ""))
         (end
           (or (position #\Newline raw) (length raw)))
         (line
           (string-trim
            '(#\Space #\Tab #\Return)
            (subseq raw 0 end))))
    (if (plusp (length line)) line "Error")))

(defun program-status-reporter-current
    (reporter)
  (let* ((blocked-entry
           (car
            (last
             (program-status-reporter-blocked
              reporter))))
         (blocked
           (and blocked-entry (cdr blocked-entry))))
    (cond
      (blocked
       (cadr-tui:make-program-status
        :state :blocked
        :kind (getf blocked :kind)
        :message (getf blocked :message)))
      ((program-status-reporter-compacting-p reporter)
       (cadr-tui:make-program-status
        :state :working
        :message "Compacting context"))
      (t
       (let ((status
               (if (program-status-reporter-run-active-p
                    reporter)
                   (cadr-tui:make-program-status
                    :state :working)
                   (program-status-reporter-resting-status
                    reporter))))
         (if (member
              (cadr-tui:program-status-state status)
              '(:working :done))
             (cadr-tui:make-program-status
              :state (cadr-tui:program-status-state status)
              :message
              (or
               (cadr-tui:program-status-message status)
               (funcall
                (program-status-reporter-get-session-name
                 reporter))))
             status))))))

(defun program-status-report-key (status)
  (format nil "~A/~A/~A/~A"
          (cadr-tui:program-status-state status)
          (or (cadr-tui:program-status-app status) "")
          (or (cadr-tui:program-status-kind status) "")
          (or (cadr-tui:program-status-message status) "")))

(defun program-status-reporter-report (reporter)
  (let* ((status
           (let ((current
                   (program-status-reporter-current
                    reporter)))
             (cadr-tui:make-program-status
              :state (cadr-tui:program-status-state current)
              :app +program-status-app-name+
              :kind (cadr-tui:program-status-kind current)
              :message
              (cadr-tui:program-status-message current))))
         (key (program-status-report-key status)))
    (unless (equal key
                   (program-status-reporter-last-report
                    reporter))
      (setf
       (program-status-reporter-last-report reporter)
       key)
      (cadr-tui:terminal-set-program-status
       (funcall
        (program-status-reporter-get-terminal reporter))
       status))
    status))

(defun program-status-reporter-set-blocked
    (reporter source status)
  (setf
   (program-status-reporter-blocked reporter)
   (remove source
           (program-status-reporter-blocked reporter)
           :key #'car
           :test #'equal))
  (when status
    (setf
     (program-status-reporter-blocked reporter)
     (append
      (program-status-reporter-blocked reporter)
      (list (cons source status)))))
  (program-status-reporter-report reporter))

(defun program-status-reporter-reset (reporter)
  (setf
   (program-status-reporter-run-active-p reporter) nil
   (program-status-reporter-compacting-p reporter) nil
   (program-status-reporter-run-result reporter)
   (cadr-tui:make-program-status :state :done)
   (program-status-reporter-resting-status reporter)
   (cadr-tui:make-program-status :state :idle))
  (program-status-reporter-report reporter))

(defun program-status-reporter-handle-event
    (reporter event)
  (let ((event-type
          (cadr-agent:agent-event-type event)))
    (case event-type
      (:agent-start
       (setf
        (program-status-reporter-run-active-p reporter) t
        (program-status-reporter-run-result reporter)
        (cadr-tui:make-program-status :state :done)))
      (:message-end
       (let ((message
               (cadr-agent:agent-event-message event)))
         (unless (typep message
                        'cadr-ai:assistant-message)
           (return-from
            program-status-reporter-handle-event
            nil))
         (setf
          (program-status-reporter-run-result reporter)
          (if (eq :error
                  (cadr-ai:assistant-message-stop-reason
                   message))
              (cadr-tui:make-program-status
               :state :error
               :message
               (program-status-first-line
                (cadr-ai:assistant-message-error-message
                 message)))
              (cadr-tui:make-program-status
               :state :done)))))
      (:compaction-start
       (setf
        (program-status-reporter-compacting-p reporter)
        t))
      (:compaction-end
       (setf
        (program-status-reporter-compacting-p reporter)
        nil)
       (let ((aborted-p
               (cadr-agent:agent-event-aborted event))
             (error-message
               (cadr-agent:agent-event-error-message
                event))
             (reason
               (cadr-agent:agent-event-reason event)))
         (if (program-status-reporter-run-active-p
              reporter)
             (cond
               (aborted-p
                (setf
                 (program-status-reporter-run-result
                  reporter)
                 (cadr-tui:make-program-status
                  :state :idle)))
               (error-message
                (setf
                 (program-status-reporter-run-result
                  reporter)
                 (cadr-tui:make-program-status
                  :state :error
                  :message
                  (program-status-first-line
                   error-message)))))
             (cond
               (aborted-p
                (setf
                 (program-status-reporter-resting-status
                  reporter)
                 (cadr-tui:make-program-status
                  :state :idle)))
               ((eq reason :manual)
                (setf
                 (program-status-reporter-resting-status
                  reporter)
                 (if error-message
                     (cadr-tui:make-program-status
                      :state :error
                      :message
                      (program-status-first-line
                       error-message))
                     (cadr-tui:make-program-status
                      :state :done))))))))
      (:agent-settled
       (setf
        (program-status-reporter-run-active-p reporter)
        nil
        (program-status-reporter-resting-status reporter)
        (if (cadr-agent:agent-event-aborted event)
            (cadr-tui:make-program-status :state :idle)
            (program-status-reporter-run-result
             reporter))))
      (:session-info-changed)
      (otherwise
       (return-from
        program-status-reporter-handle-event
        nil)))
    (program-status-reporter-report reporter)))
