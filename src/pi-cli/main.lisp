(in-package #:pi-cli)

(defun make-coding-tools (cwd)
  (list (make-read-tool cwd)
        (make-write-tool cwd)
        (make-edit-tool cwd)
        (make-bash-tool cwd)
        (make-glob-tool cwd)
        (make-grep-tool cwd)))

(defun make-agent-event-renderer (&optional
                                    (output *standard-output*))
  (let ((current-message nil)
        (printed-p nil))
    (lambda (event)
      (let ((type (pi-agent:agent-event-type event))
            (message (pi-agent:agent-event-message event))
            (stream-event
              (pi-agent:agent-event-stream-event event)))
        (cond
          ((and (eq type :message-start)
                (typep message 'pi-ai:assistant-message))
           (setf current-message message
                 printed-p nil))
          ((and (eq type :message-update)
                (eq message current-message)
                stream-event
                (eq :text-delta
                    (pi-ai:stream-event-type stream-event)))
           (unless printed-p
             (format output "~&assistant> ")
             (setf printed-p t))
           (write-string
            (or (pi-ai:stream-event-delta stream-event) "")
            output)
           (finish-output output))
          ((and (eq type :message-end)
                (eq message current-message))
           (when printed-p
             (terpri output)
             (finish-output output))
           (when (and (not printed-p)
                      (member
                       (pi-ai:assistant-message-stop-reason message)
                       '(:error :aborted)))
             (format
              output "error> ~A~%"
              (or
               (pi-ai:assistant-message-error-message message)
               (pi-ai:assistant-message-stop-reason message)))
             (finish-output output))
           (setf current-message nil
                 printed-p nil))
          ((eq type :compaction-start)
           (format output "~&session> compacting context...~%")
           (finish-output output))
          ((eq type :compaction-end)
           (format output "~&session> context compacted~%")
           (finish-output output))
          ((eq type :compaction-error)
           (format
            output "~&error> Context compaction failed: ~A~%"
            (pi-agent:agent-event-error-message event))
           (finish-output output)))))))

(defun resolve-cli-session
    (&key
       continue-p
       resume-id
       cwd
       (directory (pi-agent:default-session-directory))
       (output *error-output*))
  (when (and continue-p resume-id)
    (error
     'pi-ai:configuration-error
     :message "--continue and --resume are mutually exclusive"))
  (cond
    (resume-id
     (let ((session
             (pi-agent:resume-session
              resume-id :directory directory)))
       (unless
           (string=
            (pi-agent:session-cwd session)
            (pi-agent::canonical-session-cwd cwd))
         (error
          'pi-ai:configuration-error
          :message
          (format nil
                  "Session ~A belongs to ~A, not ~A"
                  resume-id
                  (pi-agent:session-cwd session)
                  (pi-agent::canonical-session-cwd cwd))))
       session))
    (continue-p
     (or
      (pi-agent:continue-session
       :directory directory :cwd cwd)
      (progn
        (format output
                "pi-cl: no previous session for ~A; starting a new session~%"
                (namestring
                 (truename
                  (uiop:ensure-directory-pathname cwd))))
        (finish-output output)
        (pi-agent:create-session
         :directory directory :cwd cwd))))
    (t
     (pi-agent:create-session
      :directory directory :cwd cwd))))

(defun split-command (line)
  (let* ((trimmed
           (string-trim
            '(#\Space #\Tab #\Newline #\Return)
            line))
         (separator
           (position-if
            (lambda (character)
              (member character '(#\Space #\Tab)))
            trimmed)))
    (values
     (if separator
         (subseq trimmed 0 separator)
         trimmed)
     (and separator
          (let ((argument
                  (string-trim
                   '(#\Space #\Tab)
                   (subseq trimmed (1+ separator)))))
            (unless (zerop (length argument))
              argument))))))

(defun switch-agent-session (agent session)
  (setf (pi-agent:agent-session agent) session
        (pi-agent:agent-messages agent)
        (pi-agent:session-messages session))
  session)

(defun handle-session-command
    (line agent
     &key
       (directory (pi-agent:default-session-directory))
       (cwd (uiop:getcwd))
       (output *standard-output*))
  (multiple-value-bind (command argument)
      (split-command line)
    (cond
      ((string= command "/sessions")
       (dolist
           (session
            (pi-agent:list-sessions
             :directory directory :cwd cwd))
         (format
          output "~A ~A ~D messages~%"
          (if (and (pi-agent:agent-session agent)
                   (string=
                    (pi-agent:session-id session)
                    (pi-agent:session-id
                     (pi-agent:agent-session agent))))
              "*"
              " ")
          (pi-agent:session-id session)
          (length (pi-agent:session-messages session))))
       (finish-output output)
       t)
      ((string= command "/switch")
       (unless argument
         (error
          'pi-ai:configuration-error
          :message "Usage: /switch <session-id>"))
       (let ((session
               (find
                argument
                (pi-agent:list-sessions
                 :directory directory :cwd cwd)
                :key #'pi-agent:session-id
                :test #'string=)))
         (unless session
           (error
            'pi-agent:session-error
            :path directory
            :message
            (format nil "Session not found for this cwd: ~A"
                    argument)))
         (switch-agent-session agent session)
         (format output "Switched to session ~A~%"
                 argument)
         (finish-output output)
         t))
      ((string= command "/branch")
       (unless argument
         (error
          'pi-ai:configuration-error
          :message "Usage: /branch <entry-id>"))
       (unless (pi-agent:agent-session agent)
         (error
          'pi-ai:configuration-error
          :message "The agent has no persistent session"))
       (pi-agent:session-branch
        (pi-agent:agent-session agent)
        argument)
       (setf
        (pi-agent:agent-messages agent)
        (pi-agent:session-messages
         (pi-agent:agent-session agent)))
       (format output "Branch point set to ~A~%" argument)
       (finish-output output)
       t)
      ((string= command "/compact")
       (unless (pi-agent:compact-agent
                agent :force-p t)
         (format output
                 "session> Nothing to compact~%"))
       (finish-output output)
       t)
      ((string= command "/export")
       (unless (pi-agent:agent-session agent)
         (error
          'pi-ai:configuration-error
          :message "The agent has no persistent session"))
       (let ((path
               (pathname
                (or argument
                    (format nil "~A.html"
                            (pi-agent:session-id
                             (pi-agent:agent-session
                              agent)))))))
         (pi-agent:export-session-html
          (pi-agent:agent-session agent) path)
         (format output "Exported ~A~%"
                 (namestring path))
         (finish-output output)
         t))
      (t nil))))

(defun cli-handler (command)
  (let* ((tui-p
           (should-use-tui-p
            (cli-arguments-no-tui-p command)))
         (event-consumer nil)
         (notice-consumer nil)
         (abort-requested-p nil)
         (frontend-output
           (if tui-p
               (make-notification-output-stream
                (lambda (text)
                  (when notice-consumer
                    (funcall notice-consumer text))))
               *standard-output*))
         (config
           (resolve-provider-config
            :provider
            (or (cli-arguments-provider command) "openai")
            :model (cli-arguments-model command)
            :base-url (cli-arguments-base-url command)
            :allow-missing-auth-p t))
         (cwd (uiop:getcwd))
         (session
           (resolve-cli-session
            :continue-p
            (cli-arguments-continue-p command)
            :resume-id
            (cli-arguments-resume command)
            :cwd cwd))
         (renderer (make-agent-event-renderer))
         (extension-manager
           (make-cli-extension-manager
            :cwd cwd
            :output frontend-output
            :mode (if tui-p :tui :repl)
            :explicit-paths
            (cli-arguments-extensions command)
            :secret-function
            (lambda ()
              (provider-config-secrets config))))
         (_extension-report
           (reload-cli-extensions extension-manager))
         (agent
           (pi-agent:make-agent
            :provider (provider-config-provider config)
            :model (provider-config-model config)
            :system-prompt
            (resolve-system-prompt
             (cli-arguments-system-prompt command))
            :tools (make-coding-tools cwd)
            :extension-host
            (cli-extension-manager-host
             extension-manager)
            :session session
            :abort-p
            (lambda () abort-requested-p)
            :on-event
            (lambda (event)
              (when event-consumer
                (funcall event-consumer event))))))
    (declare (ignore _extension-report))
    (labels
        ((refresh-auth (provider)
           (declare (ignore provider))
           (let ((updated
                   (resolve-provider-config
                    :provider (provider-config-name config)
                    :model
                    (pi-ai:model-id
                     (provider-config-model config))
                    :base-url
                    (cli-arguments-base-url command)
                    :allow-missing-auth-p t)))
             (setf config updated
                   (pi-agent:agent-provider agent)
                   (provider-config-provider updated)
                   (pi-agent:agent-model agent)
                   (provider-config-model updated))))
         (run-prompt (prompt)
           (let ((*bash-live-output*
                   (if tui-p
                       frontend-output
                       *standard-output*)))
             (pi-agent:agent-prompt agent prompt)))
         (handle-command (line)
           (or
            (handle-auth-command
             line
             :output frontend-output
             :on-change #'refresh-auth)
            (handle-session-command
             line agent
             :cwd cwd
             :output frontend-output)
            (handle-extension-command
             line extension-manager)))
         (expand-template (line)
           (expand-cli-extension-prompt
            extension-manager line))
         (model-items ()
           (loop
             for metadata in
             (pi-ai:list-model-metadata)
             collect
             (pi-tui:make-select-item
              :label
              (format nil "~(~A~) / ~A"
                      (pi-ai:model-metadata-provider
                       metadata)
                      (pi-ai:model-metadata-id
                       metadata))
              :value metadata)))
         (select-model (metadata)
           (let* ((provider
                    (pi-ai:model-metadata-provider
                     metadata))
                  (provider-name
                    (string-downcase
                     (symbol-name provider)))
                  (same-provider-p
                    (string=
                     provider-name
                     (provider-config-name config)))
                  (updated
                    (resolve-provider-config
                     :provider provider-name
                     :model
                     (pi-ai:model-metadata-id
                      metadata)
                     :base-url
                     (and
                      same-provider-p
                      (cli-arguments-base-url
                       command))
                     :allow-missing-auth-p t)))
             (setf
              config updated
              (pi-agent:agent-provider agent)
              (provider-config-provider updated)
              (pi-agent:agent-model agent)
              (provider-config-model updated))
             (pi-ai:model-id
              (provider-config-model updated))))
         (session-items ()
           (loop
             for candidate in
             (pi-agent:list-sessions
              :cwd cwd)
             collect
             (pi-tui:make-select-item
              :label
              (format nil "~A  ~D messages"
                      (pi-agent:session-id
                       candidate)
                      (length
                       (pi-agent:session-messages
                        candidate)))
              :value candidate)))
         (select-session (candidate)
           (switch-agent-session agent candidate)
           (values
            (pi-agent:session-id candidate)
            (pi-agent:session-messages
             candidate))))
      (if tui-p
          (run-tui
           #'run-prompt
           :command-function #'handle-command
           :template-function #'expand-template
           :set-event-consumer
           (lambda (consumer)
             (setf event-consumer consumer))
           :set-notice-consumer
           (lambda (consumer)
             (setf notice-consumer consumer))
           :model-items-function #'model-items
           :session-items-function #'session-items
           :on-model-selected #'select-model
           :on-session-selected #'select-session
           :abort-function
           (lambda ()
             (setf abort-requested-p t))
           :reset-abort-function
           (lambda ()
             (setf abort-requested-p nil))
           :model
           (pi-ai:model-id
            (pi-agent:agent-model agent))
           :session
           (and
            (pi-agent:agent-session agent)
            (pi-agent:session-id
             (pi-agent:agent-session agent)))
           :messages
           (copy-list
            (pi-agent:agent-messages agent)))
          (progn
            (setf event-consumer renderer)
            (run-repl
             #'run-prompt
             :command-function #'handle-command
             :template-function #'expand-template
             :render-response nil))))))

(defun main (&optional
               (argv
                 (uiop:command-line-arguments)))
  (handler-case
      (let ((arguments
              (parse-cli-arguments argv)))
        (cond
          ((cli-arguments-help-p arguments)
           (print-cli-usage)
           0)
          ((cli-arguments-version-p arguments)
           (format t "pi-cl 0.1.0~%")
           0)
          (t
           (cli-handler arguments)
           0)))
    (pi-ai:pi-error (condition)
      (format *error-output* "pi-cl: ~A~%" condition)
      (finish-output *error-output*)
      1)
    (error (condition)
      (format *error-output* "pi-cl: ~A~%" condition)
      (finish-output *error-output*)
      1)))
