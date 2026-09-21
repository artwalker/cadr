(in-package #:cadr-cli)

(define-condition cli-session-abort (condition)
  ((status
    :initarg :status :initform 0
    :reader cli-session-abort-status))
  (:documentation
   "Signals a clean CLI exit with a status code (baseline process.exit(0))."))

(defun session-argument-path-p (argument)
  (or
   (position #\/ argument)
   (position #\\ argument)
   (uiop:string-suffix-p argument ".jsonl")))

(defun find-session-by-id-or-prefix
    (argument candidates)
  (flet ((candidate-id (candidate)
           (cond
             ((typep candidate 'cadr-agent:session)
              (cadr-agent:session-id candidate))
             ((typep candidate 'cadr-agent:session-list-info)
              (cadr-agent:session-list-info-id candidate))
             (t "")))
         (materialize (candidate)
           (cond
             ((typep candidate 'cadr-agent:session)
              candidate)
             ((typep candidate 'cadr-agent:session-list-info)
              (cadr-agent:load-session
               (cadr-agent:session-list-info-path
                candidate)))
             (t nil))))
    (or
     (let ((exact
             (find
              argument candidates
              :key #'candidate-id
              :test #'string=)))
       (and exact (materialize exact)))
     (let ((prefix
             (find-if
              (lambda (candidate)
                (uiop:string-prefix-p
                 argument
                 (candidate-id candidate)))
              candidates)))
       (and prefix (materialize prefix))))))

(defun resolve-session-reference
    (argument directory cwd)
  ;; Baseline main.ts resolveSessionPath: path, local, then global;
  ;; NIL when nothing matches (callers own the not-found message).
  (if (session-argument-path-p argument)
      (cadr-agent:load-session
       (merge-pathnames
        (pathname argument)
        (uiop:ensure-directory-pathname cwd)))
      (or
       (find-session-by-id-or-prefix
        argument
        (cadr-agent:list-session-infos
         :directory directory :cwd cwd))
       (find-session-by-id-or-prefix
        argument
        (cadr-agent:list-session-infos
         :directory directory)))))

(defun resolve-fork-source-session
    (argument directory cwd)
  (or
   (resolve-session-reference argument directory cwd)
   (error
    'cadr-ai:configuration-error
    :message
    (format nil "No session found matching '~A'" argument))))

(defun fork-cli-session-into
    (source directory cwd session-id)
  ;; Baseline SessionManager.forkFrom: a new session in the target
  ;; project with the full source history.
  (let ((target
          (cadr-agent:create-session
           :directory directory
           :cwd cwd
           :id session-id
           :parent-session
           (cadr-agent:session-id source))))
    (dolist
        (message
         (cadr-agent:session-messages source))
      (cadr-agent:session-append-message
       target message))
    target))

(defun validate-cli-session-flags
    (&key
       continue-p
       resume-selector-p
       no-session-p
       session-path
       session-id
       fork-source)
  ;; Baseline main.ts:253-284 — validateForkFlags/validateSessionIdFlags
  ;; are the only selector conflict checks; each lists the flags actually
  ;; present, in baseline order.  main calls this before running the
  ;; content migrations (baseline main.ts:605-607 order);
  ;; resolve-cli-session re-runs it on the session path itself.
  (when fork-source
    (let ((conflicts
            (remove
             nil
             (list
              (and session-path "--session")
              (and continue-p "--continue")
              (and resume-selector-p "--resume")
              (and no-session-p "--no-session")))))
      (when conflicts
        (error
         'cadr-ai:configuration-error
         :message
         (format
          nil
          "Error: --fork cannot be combined with ~{~A~^, ~}"
          conflicts)))))
  (when session-id
    (let ((conflicts
            (remove
             nil
             (list
              (and session-path "--session")
              (and continue-p "--continue")
              (and resume-selector-p "--resume")))))
      (when conflicts
        (error
         'cadr-ai:configuration-error
         :message
         (format
          nil
          "Error: --session-id cannot be combined with ~{~A~^, ~}"
          conflicts))))))

(defun resolve-cli-session
    (&key
       continue-p
       resume-selector-p
       no-session-p
       session-path
       session-id
       fork-source
       cwd
       (directory (cadr-agent:default-session-directory))
       (output *error-output*)
       picker-function)
  (validate-cli-session-flags
   :continue-p continue-p
   :resume-selector-p resume-selector-p
   :no-session-p no-session-p
   :session-path session-path
   :session-id session-id
   :fork-source fork-source)
  (when session-id
    ;; Baseline session-manager.ts:212-218 — alphanumeric at both ends,
    ;; '-', '_', and '.' inside, no length cap.
    (unless
        (and
         (plusp (length session-id))
         (alphanumericp (char session-id 0))
         (alphanumericp
          (char session-id (1- (length session-id))))
         (every
          (lambda (character)
            (or
             (alphanumericp character)
             (member character
                     '(#\- #\_ #\.))))
          session-id))
      (error
       'cadr-ai:configuration-error
       :message
       "Error: Session id must be non-empty, contain only alphanumeric characters, '-', '_', and '.', and start and end with an alphanumeric character")))
  (when no-session-p
    (return-from resolve-cli-session nil))
  (cond
    (fork-source
     (progn
       ;; Baseline main.ts:324-330 — forking onto an existing local
       ;; session id is a hard error.
       (when
           (and
            session-id
            (find
             session-id
             (cadr-agent:list-session-infos
              :directory directory :cwd cwd)
             :key #'cadr-agent:session-list-info-id
             :test #'string=))
         (error
          'cadr-ai:configuration-error
          :message
          (format
           nil
           "Session already exists with id '~A'"
           session-id)))
       (fork-cli-session-into
        (resolve-fork-source-session
         fork-source directory cwd)
        directory cwd session-id)))
    (session-path
     (let ((session
             (resolve-session-reference
              session-path directory cwd)))
       (cond
         ((null session)
          (error
           'cadr-ai:configuration-error
           :message
           (format
            nil
            "No session found matching '~A'"
            session-path)))
         ((and
           (cadr-agent:session-cwd session)
           (not
            (string=
             (cadr-agent:session-cwd session)
             (cadr-agent::canonical-session-cwd cwd))))
          ;; Baseline main.ts:349-359 — a session from another project
          ;; requires an explicit fork confirmation.
          (format
           *standard-output*
           "~A~%"
           (cli-warning-text
            *standard-output*
            (format
             nil
             "Session found in different project: ~A"
             (cadr-agent:session-cwd session))))
          (format
           *standard-output*
           "Fork this session into current directory? [y/N] ")
          (finish-output *standard-output*)
          (let ((answer
                  (read-line *standard-input* nil nil)))
            (if (and
                 answer
                 (member
                  (string-downcase
                   (string-trim
                    '(#\Space #\Tab #\Newline #\Return)
                    answer))
                  '("y" "yes")
                  :test #'string=))
                (fork-cli-session-into
                 session directory cwd session-id)
                (progn
                  (format
                   *standard-output*
                   "~A~%"
                   (cli-dim-text *standard-output* "Aborted."))
                  (finish-output *standard-output*)
                  (error 'cli-session-abort :status 0)))))
         (t session))))
    (resume-selector-p
     ;; Baseline main.ts:368-382 + cli/session-picker.ts — the pre-TUI
     ;; selector resolves a session PATH; cancel prints dim
     ;; "No session selected" on stdout and exits 0, ctrl+c exits 0
     ;; silently (selectSession onExit).
     (multiple-value-bind (path exit-p)
         (funcall
          (or picker-function #'run-resume-session-picker)
          cwd directory)
       (cond
         (exit-p
          (error 'cli-session-abort :status 0))
         ((null path)
          (format
           *standard-output*
           "~A~%"
           (cli-dim-text
            *standard-output* "No session selected"))
          (finish-output *standard-output*)
          (error 'cli-session-abort :status 0))
         (t
          (cadr-agent:load-session path)))))
    (continue-p
     ;; Baseline SessionManager.continueRecent falls back to a fresh
     ;; session silently.
     (or
      (cadr-agent:continue-session
       :directory directory :cwd cwd)
      (cadr-agent:create-session
       :directory directory :cwd cwd)))
    (session-id
     (let ((info
             (find
              session-id
              (cadr-agent:list-session-infos
               :directory directory :cwd cwd)
              :key #'cadr-agent:session-list-info-id
              :test #'string=)))
       (or
        (and info
             (cadr-agent:load-session
              (cadr-agent:session-list-info-path info)))
        (progn
          ;; Baseline main.ts:393-399 — yellow warning on stderr.
          (format
           output
           "~A~%"
           (cli-warning-text
            output
            (format
             nil
             "Warning: No project session found with id '~A'; creating a new session with that id."
             session-id)))
          (finish-output output)
          (cadr-agent:create-session
           :directory directory :cwd cwd
           :id session-id)))))
    (t
     (cadr-agent:create-session
      :directory directory :cwd cwd))))

(defun run-resume-session-picker
    (cwd directory
     &key (input *standard-input*) (output *standard-output*)
          (user-keybindings
           (keybindings-file-bindings
            (default-agent-directory))))
  "Baseline cli/session-picker.ts selectSession: the standalone pre-TUI
session selector behind the --resume flag.  Returns (values PATH NIL)
when the user confirms a session, (values NIL NIL) on cancel (baseline
prints dim \"No session selected\" and exits 0), or (values NIL T) on
interrupt (baseline selectSession onExit: silent exit 0)."
  (unless (and (cadr-tui:terminal-stream-p input :input)
               (cadr-tui:terminal-stream-p output :output))
    ;; Baseline crashes on a raw-mode failure here; a clean error keeps
    ;; the crash channel free of a stack dump.
    (error
     'cadr-ai:configuration-error
     :message
     "Error: --resume requires an interactive terminal"))
  (let* ((terminal
           (cadr-tui:make-process-terminal
            :input input :output output))
         (renderer
           (cadr-tui:make-terminal-renderer
            terminal :alt-p nil :mouse-p nil))
         (decoder (cadr-tui:make-input-decoder))
         (state
           (make-session-selector-state
            :current-sessions
            (mapcar
             #'session-list-info-to-search-record
             (cadr-agent:list-session-infos
              :directory directory :cwd cwd))
            :all-sessions nil
            :delete-function #'delete-session-file
            :keybindings
            (make-session-selector-keybindings
             user-keybindings)))
         (done-p nil)
         (selected-path nil)
         (exit-p nil)
         (loader-thread nil))
    (labels
        ((render ()
           (multiple-value-bind (lines row column)
               (render-session-selector
                state (cadr-tui:terminal-columns terminal))
             (cadr-tui:render-frame
              renderer lines
              :cursor-row row :cursor-column column)))
         (start-all-load (token)
           (setf
            loader-thread
            (sb-thread:make-thread
             (lambda ()
               (handler-case
                   (session-selector-complete-all-load
                    state token
                    (mapcar
                     #'session-list-info-to-search-record
                     (cadr-agent:list-session-infos
                      :directory directory)))
                 (condition (condition)
                   (session-selector-fail-all-load
                    state token condition))))
             :name "cadr-resume-picker-load")))
         (handle-action (action value)
           (case action
             (:select
              (setf
               selected-path
               (namestring
                (cond
                  ((typep value 'cadr-agent:session)
                   (cadr-agent:session-path value))
                  ((typep value 'cadr-agent:session-list-info)
                   (cadr-agent:session-list-info-path value))
                  (t value)))
               done-p t))
             (:cancel
              (setf done-p t))
             (:load-all
              (start-all-load value))))
         (handle-event (event)
           (if
               (eq
                :interrupt
                (cadr-tui:input-event-kind event))
               (setf exit-p t
                     done-p t)
               (multiple-value-bind (action value)
                   (session-selector-handle-event state event)
                 (handle-action action value)))))
      (cadr-tui:call-with-terminal
       terminal
       (lambda ()
         (render)
         (loop until done-p
               do
               (when (cadr-tui:terminal-resized-p terminal)
                 (cadr-tui:invalidate-renderer renderer))
               (let ((chunk
                       (cadr-tui:terminal-read-input terminal)))
                 (if (plusp (length chunk))
                     (multiple-value-bind
                           (action value handled-p)
                         (session-selector-handle-raw-input
                          state chunk)
                       (if handled-p
                           (handle-action action value)
                           (dolist
                               (event
                                (cadr-tui:feed-input
                                 decoder chunk))
                             (handle-event event))))
                     (dolist
                         (event
                          (cadr-tui:flush-input decoder))
                       (handle-event event))))
               (render)
               (sleep 0.005d0)))
       :before-start
       (lambda () (cadr-tui:renderer-start renderer))
       :before-stop
       (lambda () (cadr-tui:renderer-before-stop renderer))
       :after-stop
       (lambda () (cadr-tui:renderer-after-stop renderer))))
    ;; The loader only reads session files; a bounded cleanup wait keeps
    ;; a slow disk from blocking the picker exit path.
    (cadr-core:stop-thread-for-cleanup
     loader-thread :timeout 2 :terminate-p nil)
    (values selected-path exit-p)))

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

(defun path-command-argument
    (line command)
  (let ((trimmed
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           line)))
    (unless
        (and
         (> (length trimmed) (length command))
         (string=
          command trimmed
          :end2 (length command))
         (member
          (char trimmed (length command))
          '(#\Space #\Tab)))
      (return-from path-command-argument nil))
    (let ((arguments
            (string-left-trim
             '(#\Space #\Tab)
             (subseq
              trimmed
              (1+ (length command))))))
      (when (zerop (length arguments))
        (return-from path-command-argument nil))
      (let ((quote
              (and
               (member
                (char arguments 0)
                '(#\' #\"))
               (char arguments 0))))
        (if quote
            (let ((end
                    (position quote arguments
                              :start 1)))
              (and end
                   (subseq arguments 1 end)))
            (let ((end
                    (position-if
                     (lambda (character)
                       (member character
                               '(#\Space #\Tab)))
                     arguments)))
              (if end
                  (subseq arguments 0 end)
                  arguments)))))))

(defun last-assistant-text (agent)
  (let ((message
          (find-if
           (lambda (candidate)
             (and
              (typep
               candidate
               'cadr-ai:assistant-message)
              (not
               (and
                (eq
                 :aborted
                 (cadr-ai:assistant-message-stop-reason
                  candidate))
                (null
                 (cadr-ai:assistant-message-content
                  candidate))))))
           (cadr-agent:agent-messages agent)
           :from-end t)))
    (when message
      (let ((text
              (format
               nil "~{~A~}"
               (loop
                 for block
                 in
                 (cadr-ai:assistant-message-content
                  message)
                 when
                   (typep block 'cadr-ai:text-content)
                   collect
                   (cadr-ai:text-content-text
                    block)))))
        (let ((trimmed
                (string-trim
                 '(#\Space #\Tab #\Newline #\Return)
                 text)))
          (and
           (plusp (length trimmed))
           trimmed))))))

(defun cli-platform ()
  #+darwin :darwin
  #+win32 :windows
  #-(or darwin win32) :linux)

(defun default-copy-text (text)
  (let ((environment nil))
    (copy-to-clipboard
     text
     :platform (cli-platform)
     :termux-p
     (not
      (null
       (clipboard-environment-value
        environment "TERMUX_VERSION")))
     :wayland-p
     (not
      (null
       (clipboard-wayland-p environment)))
     :wayland-display-p
     (not
      (null
       (clipboard-environment-value
        environment "WAYLAND_DISPLAY")))
     :x11-display-p
     (not
      (null
       (clipboard-environment-value
        environment "DISPLAY")))
     :remote-p
     (not
      (null
       (or
        (clipboard-environment-value
         environment "SSH_CONNECTION")
        (clipboard-environment-value
         environment "SSH_CLIENT")
        (clipboard-environment-value
         environment "MOSH_CONNECTION")))))))

(defun assistant-tool-call-only-p (message)
  (let ((content
          (cadr-ai:assistant-message-content
           message)))
    (and
     (some
      (lambda (block)
        (typep block 'cadr-ai:tool-call))
      content)
     (not
      (some
       (lambda (block)
         (and
          (typep block 'cadr-ai:text-content)
          (plusp
           (length
            (cadr-ai:text-content-text
             block)))))
       content)))))

(defun session-tree-label-timestamps (session)
  (let ((result
          (make-hash-table :test #'equal)))
    (dolist (entry
             (cadr-agent:session-entries session))
      (when
          (eq :label
              (cadr-agent:session-entry-type
               entry))
        (let ((target
                (cadr-agent:session-entry-target-id
                 entry)))
          (if
              (and
               (cadr-agent:session-entry-label entry)
               (plusp
                (length
                 (cadr-agent:session-entry-label
                  entry))))
              (setf
               (gethash target result)
               (cadr-agent::milliseconds-to-iso8601
                (cadr-agent:session-entry-timestamp
                 entry)))
              (remhash target result)))))
    result))

(defun session-tree-tool-calls (session)
  (let ((result
          (make-hash-table :test #'equal)))
    (dolist (entry
             (cadr-agent:session-entries session))
      (let ((message
              (cadr-agent:session-entry-message
               entry)))
        (when
            (typep message
                   'cadr-ai:assistant-message)
          (dolist (block
                   (cadr-ai:assistant-message-content
                    message))
            (when (typep block 'cadr-ai:tool-call)
              (setf
               (gethash (cadr-ai:tool-call-id block)
                        result)
               (list
                :name (cadr-ai:tool-call-name block)
                :arguments
                (cadr-ai:tool-call-arguments
                 block))))))))
    result))

(defun session-display-messages (session)
  "Project the active session context into typed transcript messages.

Unlike SESSION-MESSAGES, this projection is display-facing: branch and
compaction summaries retain their component types instead of being converted
to provider-facing user messages containing <summary> wrappers."
  (when session
    (loop
      for entry in (cadr-agent::session-context-entries session)
      for message =
        (case (cadr-agent:session-entry-type entry)
          (:message
           (cadr-agent:session-entry-message entry))
          (:custom-message
           (cadr-agent:make-custom-agent-message
            :custom-type
            (cadr-agent:session-entry-custom-type entry)
            :content
            (cadr-agent:session-entry-content entry)
            :display-p
            (cadr-agent:session-entry-display-p entry)
            :details
            (cadr-agent:session-entry-details entry)
            :timestamp
            (cadr-agent:session-entry-timestamp entry)))
          (:branch-summary
           (cadr-agent:make-branch-summary-message
            :summary
            (cadr-agent:session-entry-summary entry)
            :from-id
            (cadr-agent:session-entry-from-id entry)
            :timestamp
            (cadr-agent:session-entry-timestamp entry)))
          (:compaction
           (cadr-agent:make-compaction-summary-agent-message
            :summary
            (cadr-agent:session-entry-summary entry)
            :tokens-before
            (cadr-agent:session-entry-tokens-before entry)
            :timestamp
            (cadr-agent:session-entry-timestamp entry))))
      when message collect message)))

(defun session-compaction-display-state (session)
  "Return the compaction-aware transcript projection consumed by the TUI.

The typed compaction summary is already part of SESSION-DISPLAY-MESSAGES, so
the legacy separate summary values stay NIL to prevent a duplicate entry."
  (values (session-display-messages session) nil nil))

(defun session-compaction-status (session)
  (when session
    (let ((count
            (count :compaction
                   (cadr-agent:session-entries session)
                   :key #'cadr-agent:session-entry-type)))
      (when (plusp count)
        (format nil "Session compacted ~D time~:P" count)))))

(defun session-entry-tree-selector-data
    (session entry label-timestamps tool-calls)
  (let* ((type
           (cadr-agent:session-entry-type entry))
         (message
           (cadr-agent:session-entry-message entry))
         (role
           (typecase message
             (cadr-ai:user-message :user)
             (cadr-ai:assistant-message :assistant)
             (cadr-ai:tool-result-message
              :tool-result)
             (cadr-agent:bash-execution-message
              :bash-execution)
             (otherwise nil)))
         (id
           (cadr-agent:session-entry-id entry))
         (tool-call
           (and
            (typep message
                   'cadr-ai:tool-result-message)
            (gethash
             (cadr-ai:tool-result-message-tool-call-id
              message)
             tool-calls))))
    (list
     :id id
     :parent-id
     (cadr-agent:session-entry-parent-id entry)
     :type type
     :role role
     :text
     (cond
       ((typep message
               'cadr-agent:bash-execution-message)
        (cadr-agent:bash-execution-message-command
         message))
       (message
        (session-message-search-text message))
       ((member type
                '(:compaction :branch-summary)
                :test #'eq)
        (or
         (cadr-agent:session-entry-summary entry)
         ""))
       ((eq type :model-change)
        (format
         nil "~A / ~A"
         (cadr-agent:session-entry-provider entry)
         (cadr-agent:session-entry-model-id entry)))
       ((eq type :thinking-level-change)
        (princ-to-string
         (cadr-agent:session-entry-thinking-level
          entry)))
       ((eq type :custom-message)
        (let ((content
                (cadr-agent:session-entry-content
                 entry)))
          (if (stringp content)
              content
              (cadr-ai::content-text content))))
       (t ""))
     :label
     (cadr-agent:session-label session id)
     :entry-label
     (and
      (eq type :label)
      (cadr-agent:session-entry-label entry))
     :label-timestamp
     (gethash id label-timestamps)
     :tool-call-only-p
     (and
      (typep message 'cadr-ai:assistant-message)
      (assistant-tool-call-only-p message))
     :stop-reason
     (and
      (typep message 'cadr-ai:assistant-message)
      (cadr-ai:assistant-message-stop-reason message))
     :error-message
     (and
      (typep message 'cadr-ai:assistant-message)
      (cadr-ai:assistant-message-error-message message))
     :error-p
     (or
      (and
       (typep message 'cadr-ai:assistant-message)
       (member
        (cadr-ai:assistant-message-stop-reason
         message)
        '(:error :aborted)
        :test #'eq))
      (and
       (typep message 'cadr-ai:tool-result-message)
       (cadr-ai:tool-result-message-is-error
        message)))
     :summary
     (cadr-agent:session-entry-summary entry)
     :tokens-before
     (cadr-agent:session-entry-tokens-before entry)
     :name
     (cadr-agent:session-entry-name entry)
     :model-id
     (cadr-agent:session-entry-model-id entry)
     :thinking-level
     (cadr-agent:session-entry-thinking-level
      entry)
     :custom-type
     (cadr-agent:session-entry-custom-type
      entry)
     :tool-call-name
     (and
      (typep message 'cadr-ai:tool-result-message)
      (or (getf tool-call :name)
          (cadr-ai:tool-result-message-tool-name
           message)))
     :tool-call-arguments
     (getf tool-call :arguments))))

(defun session-tree-selector-data (session)
  (if (null session)
      (values nil nil)
      (let ((label-timestamps
              (session-tree-label-timestamps
               session))
            (tool-calls
              (session-tree-tool-calls session)))
        (values
         (mapcar
          (lambda (entry)
            (session-entry-tree-selector-data
             session entry label-timestamps
             tool-calls))
          (cadr-agent:session-entries session))
         (cadr-agent:session-leaf-id session)))))

(defun run-session-lifecycle
    (agent event &rest payload)
  (let ((host
          (cadr-agent::agent-extension-host
           agent)))
    (and
     host
     (cadr-agent::run-extension-lifecycle-hooks
     host event :payload payload))))

(defun apply-cli-model-selection
    (agent registry model settings-manager
     &key api-key base-url
       (config-path (default-config-path))
       (auth-path (default-auth-path))
       (source :interactive)
       (persist nil)
       (thinking-level nil thinking-level-p))
  (let* ((previous-model
           (cadr-agent:agent-model agent))
         (previous-thinking
           (cadr-agent::agent-thinking-level
            agent))
         (config
           (provider-config-for-model
            registry model
            :api-key api-key
            :base-url base-url
            :config-path config-path
            :auth-path auth-path
            :allow-missing-auth-p t))
         (provider
           (provider-config-provider config))
         (selected
           (provider-config-model config))
         (thinking
           (cadr-ai:clamp-thinking-level
            selected
            (if thinking-level-p
                thinking-level
                (cli-thinking-level-for-model-switch
                 agent settings-manager selected))))
         (host
           (cadr-agent::agent-extension-host
            agent))
         (session
           (cadr-agent:agent-session agent)))
    (setf
     (cadr-agent:agent-provider agent) provider
     (cadr-agent:agent-model agent) selected
     (cadr-agent::agent-thinking-level agent)
     thinking)
    (when host
      (setf
       (cadr-agent::extension-host-base-agent-provider
        host)
       provider
       (cadr-agent::extension-host-base-agent-model
        host)
       selected))
    (when session
      (cadr-agent:session-append-model-change
       session
       (provider-key
        (cadr-ai:model-provider selected))
       (cadr-ai:model-id selected))
      (unless (eq previous-thinking thinking)
        (cadr-agent:session-append-thinking-level-change
         session
         (string-downcase
          (symbol-name thinking)))))
    (when persist
      (settings-set-default-model-and-provider
       settings-manager
       (provider-key
        (cadr-ai:model-provider selected))
       (cadr-ai:model-id selected))
      (add-persisted-default-to-non-empty-scope
       settings-manager selected))
    (unless
        (cadr-ai:models-equal-p
         previous-model selected)
      (run-session-lifecycle
       agent :model-select
       :model selected
       :previous-model previous-model
       :source source))
    config))

(defun refresh-agent-model-from-registry
    (agent registry
     &key api-key base-url
       (config-path (default-config-path))
       (auth-path (default-auth-path)))
  (let* ((current
           (cadr-agent:agent-model agent))
         (refreshed
           (and
            current
            (model-registry-find
             registry
             (cadr-ai:model-provider current)
             (cadr-ai:model-id current)))))
    (when refreshed
      (let* ((config
               (provider-config-for-model
                registry refreshed
                :api-key api-key
                :base-url base-url
                :config-path config-path
                :auth-path auth-path
                :allow-missing-auth-p t))
             (provider
               (provider-config-provider config))
             (model
               (provider-config-model config))
             (host
               (cadr-agent::agent-extension-host
                agent)))
        (setf
         (cadr-agent:agent-provider agent)
         provider
         (cadr-agent:agent-model agent)
         model
         (cadr-agent::agent-thinking-level
          agent)
         (cadr-ai:clamp-thinking-level
          model
          (cadr-agent::agent-thinking-level
           agent)))
        (when host
          (setf
           (cadr-agent::extension-host-base-agent-provider
            host)
           provider
           (cadr-agent::extension-host-base-agent-model
            host)
           model))
        config))))

(defun session-restored-model
    (session registry available-models)
  (when session
    (let* ((change
             (find
              :model-change
              (cadr-agent:session-entries session)
              :from-end t
              :key #'cadr-agent:session-entry-type))
           (assistant
             (find-if
              (lambda (message)
                (typep
                 message
                 'cadr-ai:assistant-message))
              (cadr-agent:session-messages session)
              :from-end t))
           (provider
             (or
              (and change
                   (cadr-agent:session-entry-provider
                    change))
              (and assistant
                   (cadr-ai:assistant-message-provider
                    assistant))))
           (model-id
             (or
              (and change
                   (cadr-agent:session-entry-model-id
                    change))
              (and assistant
                   (cadr-ai:assistant-message-model
                    assistant))))
           (model
             (and
              provider model-id
              (model-registry-find
               registry provider model-id))))
      (and
       model
       (find model available-models
             :test #'cadr-ai:models-equal-p)))))

(defun refuse-unflushed-persisted-fork (session)
  (let ((path
          (and session
               (cadr-agent:session-path session))))
    (when (and path (not (probe-file path)))
      (error
       'cadr-ai:configuration-error
       :message
       "This session has not been saved yet. Wait for the first assistant response before cloning or forking it."))))

(defun clone-agent-session
    (agent directory)
  (let* ((source
           (cadr-agent:agent-session agent))
         (leaf-id
           (and source
                (cadr-agent:session-leaf-id
                 source))))
    (unless leaf-id
      (return-from clone-agent-session nil))
    (let ((before
            (run-session-lifecycle
             agent :session-before-fork
             :entry-id leaf-id
             :position :at)))
      (when (getf before :cancel-p)
        (return-from clone-agent-session
          :cancelled)))
    (refuse-unflushed-persisted-fork source)
    (cadr-agent:agent-abort-and-idle agent)
    (let ((clone
            (cadr-agent:create-session
             :directory directory
             :cwd (cadr-agent:session-cwd
                   source)
             :parent-session
             (namestring
              (cadr-agent:session-path
               source)))))
      (dolist
          (entry
           (cadr-agent::session-path-entries
            source leaf-id))
        (cadr-agent::append-session-entry
         clone
         (cadr-agent::copy-session-entry
          entry)))
      (setf (cadr-agent:session-name clone)
            (cadr-agent:session-name source))
      (run-session-lifecycle
       agent :session-shutdown
       :reason :fork
       :target-session-file
       (namestring
        (cadr-agent:session-path clone)))
      (let ((previous
              (namestring
               (cadr-agent:session-path source))))
        (switch-agent-session agent clone)
        (run-session-lifecycle
         agent :session-start
         :reason :fork
         :previous-session-file previous))
      clone)))

(defun session-entry-user-text (entry)
  (when
      (and
       (eq :message
           (cadr-agent:session-entry-type entry))
       (typep
        (cadr-agent:session-entry-message entry)
        'cadr-ai:user-message))
    (let ((content
            (cadr-ai:user-message-content
             (cadr-agent:session-entry-message
              entry))))
      (if (stringp content)
          content
          (format
           nil "~{~A~^~%~}"
           (loop for block in content
                 when
                 (typep block 'cadr-ai:text-content)
                   collect
                   (cadr-ai:text-content-text
                    block)))))))

(defun session-user-messages-for-forking (session)
  (loop
    for entry in
    (and session
         (cadr-agent:session-entries session))
    for text = (session-entry-user-text entry)
    when
      (and text
           (plusp
            (length
             (string-trim
              '(#\Space #\Tab #\Newline #\Return)
              text))))
      collect
      (list :entry-id
            (cadr-agent:session-entry-id entry)
            :text text)))

(defun new-agent-session
    (agent directory cwd &key parent-session)
  (let* ((old
           (cadr-agent:agent-session agent))
         (previous
           (and old
                (namestring
                 (cadr-agent:session-path old))))
         (before
           (run-session-lifecycle
            agent :session-before-switch
            :reason :new
            :target-session-file nil)))
    (when (getf before :cancel-p)
      (return-from new-agent-session
        :cancelled))
    (run-session-lifecycle
     agent :session-shutdown
     :reason :new)
    (let ((new
            (cadr-agent:create-session
             :directory directory
             :cwd
             (or
              (and old
                   (cadr-agent:session-cwd old))
              cwd)
             :parent-session parent-session)))
      (switch-agent-session agent new)
      (run-session-lifecycle
       agent :session-start
       :reason :new
       :previous-session-file previous)
      new)))

(defun fork-agent-session
    (agent entry-id directory)
  (let* ((source
           (cadr-agent:agent-session agent))
         (entry
           (and source
                (find
                 entry-id
                 (cadr-agent:session-entries source)
                 :key #'cadr-agent:session-entry-id
                 :test #'string=)))
         (selected-text
           (and entry
                (session-entry-user-text entry))))
    (unless selected-text
      (error
       'cadr-ai:configuration-error
       :message
       "Invalid user message entry for forking"))
    (let ((before
            (run-session-lifecycle
             agent :session-before-fork
             :entry-id entry-id
             :position :before)))
      (when (getf before :cancel-p)
        (return-from fork-agent-session
          (values :cancelled nil))))
    (when (cadr-agent:session-entry-parent-id entry)
      (refuse-unflushed-persisted-fork source))
    (cadr-agent:agent-abort-and-idle agent)
    (let* ((previous
             (namestring
              (cadr-agent:session-path source)))
           (new
             (cadr-agent:create-session
              :directory directory
              :cwd
              (cadr-agent:session-cwd source)
              :parent-session previous))
           (target-id
             (cadr-agent:session-entry-parent-id
              entry)))
      (when target-id
        (dolist
            (candidate
             (cadr-agent::session-path-entries
              source target-id))
          (cadr-agent::append-session-entry
           new
           (cadr-agent::copy-session-entry
            candidate))))
      (run-session-lifecycle
       agent :session-shutdown
       :reason :fork
       :target-session-file
       (namestring
        (cadr-agent:session-path new)))
      (switch-agent-session agent new)
      (run-session-lifecycle
       agent :session-start
       :reason :fork
       :previous-session-file previous)
      (values new selected-text))))

(defun session-command-stats (session)
  (let ((user 0)
        (assistant 0)
        (tool-results 0)
        (tool-calls 0)
        (input 0)
        (output 0)
        (cache-read 0)
        (cache-write 0)
        (cost 0d0))
    (labels
        ((add-usage (usage)
           (when usage
             (incf input
                   (cadr-ai:usage-input usage))
             (incf output
                   (cadr-ai:usage-output usage))
             (incf cache-read
                   (cadr-ai:usage-cache-read usage))
             (incf cache-write
                   (cadr-ai:usage-cache-write usage))
             (incf cost
                   (cadr-ai:cost-total
                    (cadr-ai:usage-cost usage))))))
      (dolist
          (entry
           (cadr-agent:session-entries session))
        (let ((type
                (cadr-agent:session-entry-type
                 entry)))
          (when
              (member type
                      '(:compaction :branch-summary))
            (add-usage
             (cadr-agent:session-entry-usage
              entry)))
          (when (eq :message type)
            (let ((message
                    (cadr-agent:session-entry-message
                     entry)))
              (cond
                ((typep
                  message 'cadr-ai:user-message)
                 (incf user))
                ((typep
                  message
                  'cadr-ai:tool-result-message)
                 (incf tool-results))
                ((typep
                  message
                  'cadr-ai:assistant-message)
                 (incf assistant)
                 (incf
                  tool-calls
                  (count-if
                   (lambda (block)
                     (typep block
                            'cadr-ai:tool-call))
                   (cadr-ai:assistant-message-content
                    message)))
                 (add-usage
                  (cadr-ai:assistant-message-usage
                   message)))))))))
    (list
     :user user
     :assistant assistant
     :tool-results tool-results
     :tool-calls tool-calls
     :input input
     :output output
     :cache-read cache-read
     :cache-write cache-write
     :cost cost)))

(defun session-usage-breakdown (session)
  (let ((totals (make-hash-table :test #'equal))
        (order nil))
    (flet
        ((record (key usage)
           (when (and key usage)
             (unless (gethash key totals)
               (setf (gethash key totals)
                     (list :cost 0d0 :tokens 0))
               (push key order))
             (let ((entry (gethash key totals)))
               (incf
                (getf entry :cost)
                (cadr-ai:cost-total
                 (cadr-ai:usage-cost usage)))
               (incf
                (getf entry :tokens)
                (+ (cadr-ai:usage-input usage)
                   (cadr-ai:usage-output usage)
                   (cadr-ai:usage-cache-read usage)
                   (cadr-ai:usage-cache-write usage)))
               (setf (gethash key totals) entry)))))
      (dolist (session-entry
               (cadr-agent:session-entries session))
        (let ((message
                (cadr-agent:session-entry-message
                 session-entry)))
          (cond
            ((typep message 'cadr-ai:assistant-message)
             (record
              (format
               nil "~(~A~)/~A"
               (cadr-ai:assistant-message-provider message)
               (or
                (cadr-ai:assistant-message-response-model
                 message)
                (cadr-ai:assistant-message-model message)))
              (cadr-ai:assistant-message-usage message)))
            ((member
              (cadr-agent:session-entry-type session-entry)
              '(:compaction :branch-summary))
             (record
              "Tools/summaries"
              (cadr-agent:session-entry-usage
               session-entry)))))))
    (stable-sort
     (loop for key in (nreverse order)
           for entry = (gethash key totals)
           when (or
                 (plusp (getf entry :cost))
                 (plusp (getf entry :tokens)))
             collect
             (list :key key
                   :cost (getf entry :cost)
                   :tokens (getf entry :tokens)))
     #'> :key (lambda (entry) (getf entry :cost)))))

(defun session-info-style (text kind ansi-theme-p)
  (case kind
    (:heading
     (cadr-tui:theme-bold
      text :enabled-p ansi-theme-p))
    (:label
     (cadr-tui:theme-foreground
      :dim text :enabled-p ansi-theme-p))
    (otherwise text)))

(defun write-session-command-info
    (session output
     &key ansi-theme-p model-price-function)
  (let* ((stats
           (session-command-stats session))
         (input
           (+ (getf stats :input)
              (getf stats :cache-read)
              (getf stats :cache-write)))
         (total
           (+ input
              (getf stats :output)))
         (breakdown
           (session-usage-breakdown session))
         (cache-waste
           (compute-cache-waste
            (cadr-agent:session-entries session)
            :model-price-function
            model-price-function)))
    (format output "~A~%~%"
            (session-info-style
             "Session Info" :heading ansi-theme-p))
    (when (cadr-agent:session-name session)
      (format output "~A ~A~%"
              (session-info-style
               "Name:" :label ansi-theme-p)
              (cadr-agent:session-name session)))
    (format
     output
     "~A ~A~%~A ~A~%~%~A~%~A ~:D~%~A ~:D~%~A ~:D~%~A ~:D calls, ~:D results~%~%~A~%~A ~:D~%"
     (session-info-style "File:" :label ansi-theme-p)
     (namestring
      (cadr-agent:session-path session))
     (session-info-style "ID:" :label ansi-theme-p)
     (cadr-agent:session-id session)
     (session-info-style "Messages" :heading ansi-theme-p)
     (session-info-style "Total:" :label ansi-theme-p)
     (+ (getf stats :user)
        (getf stats :assistant)
        (getf stats :tool-results))
     (session-info-style "User:" :label ansi-theme-p)
     (getf stats :user)
     (session-info-style "Assistant:" :label ansi-theme-p)
     (getf stats :assistant)
     (session-info-style "Tools:" :label ansi-theme-p)
     (getf stats :tool-calls)
     (getf stats :tool-results)
     (session-info-style "Tokens" :heading ansi-theme-p)
     (session-info-style "Input:" :label ansi-theme-p)
     input)
    (when
        (plusp
         (+ (getf stats :cache-read)
            (getf stats :cache-write)))
      (format
       output
       "  ~A ~:D ~A~%  ~A ~:D"
       (session-info-style "Cached:" :label ansi-theme-p)
       (getf stats :cache-read)
       (session-info-style
        (format nil "(~,1F%)"
                (* 100d0
                   (/ (getf stats :cache-read)
                      input)))
        :label ansi-theme-p)
       (session-info-style "Uncached:" :label ansi-theme-p)
       (+ (getf stats :input)
          (getf stats :cache-write)))
      (when (plusp
             (getf stats :cache-write))
        (format
         output " ~A"
         (session-info-style
          (format nil "(~:D written to cache)"
                  (getf stats :cache-write))
          :label ansi-theme-p)))
      (terpri output))
    (format
     output
     "~A ~:D~%~A ~:D~%"
     (session-info-style "Output:" :label ansi-theme-p)
     (getf stats :output)
     (session-info-style "Total:" :label ansi-theme-p)
     total)
    ;; Baseline interactive-mode.ts:6387-6390 — /session always prints the
    ;; Cache Warming block. Goal 24 defers the warmer dispatch; the inactive
    ;; default matches the baseline CacheWarmer before the first request.
    (format
     output
     "~%~A~%~A ~A~%~A ~A~%"
     (session-info-style "Cache Warming" :heading ansi-theme-p)
     (session-info-style "Mode:" :label ansi-theme-p)
     "streaming"
     (session-info-style "Status:" :label ansi-theme-p)
     "Inactive (waiting for first request)")
    (when
        (or
         (plusp (getf stats :cost))
         (plusp
          (cache-waste-missed-tokens cache-waste)))
      (format
       output
       "~%~A~%~A $~,3F"
       (session-info-style "Cost" :heading ansi-theme-p)
       (session-info-style "Total:" :label ansi-theme-p)
       (getf stats :cost))
      (when (> (length breakdown) 1)
        (dolist (entry breakdown)
          (format
           output "~%  ~A $~,3F ~A"
           (session-info-style
            (format nil "~A:" (getf entry :key))
            :label ansi-theme-p)
           (getf entry :cost)
           (session-info-style
            (format nil "(~A tokens)"
                    (cadr-tui::format-footer-tokens
                     (getf entry :tokens)))
            :label ansi-theme-p))))
      (when
          (plusp
           (cache-waste-missed-tokens cache-waste))
        (let* ((count
                 (cache-waste-miss-count cache-waste))
               (detail
                 (format nil "(~:D tokens, ~D ~A)"
                         (cache-waste-missed-tokens cache-waste)
                         count
                         (if (= count 1) "miss" "misses"))))
          (if (>= (cache-waste-missed-cost cache-waste)
                  0.0001d0)
              (format
               output "~%~A $~,3F ~A"
               (session-info-style
                "Cache Re-billed:" :label ansi-theme-p)
               (cache-waste-missed-cost cache-waste)
               (session-info-style
                detail :label ansi-theme-p))
              (format
               output "~%~A ~A"
               (session-info-style
                "Cache Re-billed:" :label ansi-theme-p)
               detail))))
      (terpri output))))

(defun default-changelog-path ()
  (or
   (let ((value
           (uiop:getenv
            "CADR_CHANGELOG_PATH")))
     (and value
          (plusp (length value))
          (pathname value)))
   (handler-case
       (merge-pathnames
        "CHANGELOG.md"
        (cadr-ai::cadr-cli-source-directory))
     (condition () nil))
   #p"CHANGELOG.md"))

(defun changelog-for-display
    (settings-manager messages
     &key
       (changelog-path (default-changelog-path))
       (current-version (cadr-ai::cadr-version)))
  (when (plusp (length messages))
    (return-from changelog-for-display nil))
  (let ((last-version
          (settings-last-changelog-version
           settings-manager))
        (entries (parse-changelog changelog-path)))
    (unless last-version
      (settings-set
       settings-manager
       "lastChangelogVersion"
       current-version)
      (return-from changelog-for-display nil))
    (let ((new-entries
            (get-new-changelog-entries
             entries last-version)))
      (when new-entries
        (settings-set
         settings-manager
         "lastChangelogVersion"
         current-version)
        (format
         nil "~{~A~^~%~%~}"
         (mapcar
          (lambda (entry)
            (normalize-changelog-links
             (getf entry :content)
             (getf entry :version)))
          new-entries))))))

(defun apply-changelog-to-startup-compact-lines
    (lines settings-manager messages
     &key
       (changelog-path (default-changelog-path))
       (current-version (cadr-ai::cadr-version)))
  (let ((text
          (changelog-for-display
           settings-manager messages
           :changelog-path changelog-path
           :current-version current-version)))
    (if text
        (append lines (list text))
        lines)))

(defparameter +interactive-hotkey-definitions+
  '(("escape" . "Cancel or abort")
    ("ctrl+c" . "Clear editor; press again to exit")
    ("ctrl+d" . "Exit when the editor is empty")
    ("ctrl+z" . "Suspend to background")
    ("ctrl+o" . "Toggle tool output")
    ("ctrl+v" . "Paste image or text from clipboard")
    ("/" . "Slash commands")
    ("!" . "Run bash command")
    ("!!" . "Run bash command without adding it to context")))

(defparameter +hotkeys-markdown-sections+
  '(("Navigation"
     ("Move cursor / browse history"
      "tui.editor.cursorUp" "tui.editor.cursorDown"
      "tui.editor.cursorLeft" "tui.editor.cursorRight")
     ("Move by word"
      "tui.editor.cursorWordLeft" "tui.editor.cursorWordRight")
     ("Start of line" "tui.editor.cursorLineStart")
     ("End of line" "tui.editor.cursorLineEnd")
     ("Jump forward to character" "tui.editor.jumpForward")
     ("Jump backward to character" "tui.editor.jumpBackward")
     ("Scroll by page" "tui.editor.pageUp" "tui.editor.pageDown"))
    ("Editing"
     ("Send message" "tui.input.submit")
     ("New line" "tui.input.newLine")
     ("Delete word backwards" "tui.editor.deleteWordBackward")
     ("Delete word forwards" "tui.editor.deleteWordForward")
     ("Delete to start of line" "tui.editor.deleteToLineStart")
     ("Delete to end of line" "tui.editor.deleteToLineEnd")
     ("Paste the most-recently-deleted text" "tui.editor.yank")
     ("Cycle through the deleted text after pasting" "tui.editor.yankPop")
     ("Undo" "tui.editor.undo"))
    ("Other"
     ("Path completion / accept autocomplete" "tui.input.tab")
     ("Cancel autocomplete / abort streaming" "app.interrupt")
     ("Clear editor (first) / exit (second)" "app.clear")
     ("Exit (when editor is empty)" "app.exit")
     ("Suspend to background" "app.suspend")
     ("Cycle thinking level" "app.thinking.cycle")
     ("Cycle models" "app.model.cycleForward" "app.model.cycleBackward")
     ("Open model selector" "app.model.select")
     ("Toggle tool output expansion" "app.tools.expand")
     ("Toggle thinking block visibility" "app.thinking.toggle")
     ("Edit message in external editor" "app.editor.external")
     ("Copy selection or last assistant message" "app.message.copy")
     ("Queue follow-up message" "app.message.followUp")
     ("Restore queued messages" "app.message.dequeue")
     ("Paste image or text from clipboard" "app.clipboard.pasteImage")
     (:literal "/" "Slash commands")
     (:literal "!" "Run bash command")
     (:literal "!!" "Run bash command (excluded from context)"))))

(defun hotkeys-command-markdown (&optional user-bindings)
  (let ((manager
          (cadr-tui:make-keybindings-manager
           :user-bindings user-bindings)))
    (labels
        ((display (name)
           (format-key-text*
            (cadr-tui:keybinding-keys manager name)
            :capitalize-p t)))
      (with-output-to-string (out)
        (loop for (title . rows) in +hotkeys-markdown-sections+
              for rest-sections on +hotkeys-markdown-sections+
              for first = t then nil
              do
              (unless first (write-char #\Newline out))
              (format out "**~A**~%| Key | Action |~%|-----|--------|~%"
                      title)
              (loop for row in rows
                    for rest-rows on rows
                    for line =
                    (if (eq (first row) :literal)
                        (format nil "| `~A` | ~A |"
                                (second row) (third row))
                        (format nil "| ~{`~A`~^ / ~} | ~A |"
                                (mapcar #'display (rest row))
                                (first row)))
                    do
                    (write-string line out)
                    (when (or (cdr rest-rows) (cdr rest-sections))
                      (write-char #\Newline out))))))))

(defun write-hotkeys-command
    (output &optional user-bindings)
  (format output "Keyboard Shortcuts~%~%")
  (dolist (entry
           +interactive-hotkey-definitions+)
    (format output "~A  ~A~%"
            (car entry) (cdr entry)))
  (when user-bindings
    (format output "~%Configured bindings~%")
    (dolist (binding user-bindings)
      (format output "~{~A~^, ~}  ~A~%"
              (cdr binding)
              (car binding)))))

(defun same-session-file-p (left right)
  (and
   (probe-file left)
   (probe-file right)
   (equal
    (namestring (truename left))
    (namestring (truename right)))))

(defun unique-import-session-path (source session-directory)
  ;; Baseline agent-session-runtime.ts importFromJsonl: keep the
  ;; basename when free, else name-1.ext, name-2.ext, ...
  (let* ((session-directory
           (uiop:ensure-directory-pathname session-directory))
         (destination
           (merge-pathnames
            (file-namestring source)
            session-directory)))
    (when (same-session-file-p source destination)
      (return-from unique-import-session-path destination))
    (let* ((name (pathname-name destination))
           (type (pathname-type destination))
           (suffix 1))
      (loop while (probe-file destination)
            do (setf destination
                     (merge-pathnames
                      (make-pathname
                       :name (format nil "~A-~D" name suffix)
                       :type type
                       :defaults destination)
                      session-directory)
                     suffix (1+ suffix)))
      destination)))

(define-condition session-import-file-not-found-error (error)
  ((file-path
    :initarg :file-path
    :reader session-import-file-not-found-error-file-path))
  (:report
   (lambda (condition stream)
     (format
      stream
      "File not found: ~A"
      (namestring
       (session-import-file-not-found-error-file-path
        condition))))))

(define-condition missing-session-cwd-error (error)
  ((session-cwd
    :initarg :session-cwd
    :reader missing-session-cwd-error-session-cwd))
  (:report
   (lambda (condition stream)
     (format
      stream
      "Session working directory does not exist: ~A"
      (missing-session-cwd-error-session-cwd condition)))))

(defun missing-session-cwd-issue (session fallback-cwd)
  (let ((stored (cadr-agent:session-cwd session)))
    (when (and stored
               (not
                (probe-file
                 (uiop:ensure-directory-pathname stored))))
      (list :session-cwd (namestring stored)
            :fallback-cwd (namestring fallback-cwd)
            :session-file
            (and (cadr-agent:session-path session)
                 (namestring
                  (cadr-agent:session-path session)))))))

(defun missing-session-cwd-prompt (session-cwd fallback-cwd)
  (format nil
          "cwd from session file does not exist~%~A~%~%continue in current cwd~%~A"
          session-cwd fallback-cwd))

(defun import-agent-session
    (agent input directory cwd &key cwd-override)
  (let* ((source
           (resolve-general-path input cwd)))
    (unless (probe-file source)
      (error
       'session-import-file-not-found-error
       :file-path source))
    (let* ((session-directory
             (uiop:ensure-directory-pathname
              directory))
           (destination
             (unique-import-session-path
              source session-directory)))
      (ensure-directories-exist
       (merge-pathnames "anchor"
                        session-directory))
      (let ((before
              (run-session-lifecycle
               agent :session-before-switch
               :reason :resume
               :target-session-file
               (namestring destination))))
        (when (getf before :cancel-p)
          (return-from import-agent-session
            (values :cancelled nil))))
      (unless
          (same-session-file-p source destination)
        (cadr-core:atomic-copy-file
         source destination :durability :flush))
      (handler-case
          (let* ((previous
                   (and
                    (cadr-agent:agent-session agent)
                    (namestring
                     (cadr-agent:session-path
                      (cadr-agent:agent-session
                       agent)))))
                 (imported
                   (cadr-agent:load-session
                    destination)))
            (unless
                (or cwd-override
                    (probe-file
                     (uiop:ensure-directory-pathname
                      (cadr-agent:session-cwd
                       imported))))
              (error
               'missing-session-cwd-error
               :session-cwd
               (cadr-agent:session-cwd imported)))
            (when cwd-override
              (setf (cadr-agent:session-cwd imported)
                    (cadr-agent::canonical-session-cwd
                     cwd-override)))
            (run-session-lifecycle
             agent :session-shutdown
             :reason :resume
             :target-session-file
             (namestring destination))
            (switch-agent-session
             agent imported)
            (run-session-lifecycle
             agent :session-start
             :reason :resume
             :previous-session-file previous)
            (values imported nil))
        (condition (condition)
          (values
           nil
           (format nil "~A" condition)
           (and (typep condition 'missing-session-cwd-error)
                condition)))))))

(defun switch-agent-session (agent session)
  (let ((host
          (cadr-agent::agent-extension-host agent)))
    (when host
      (cadr-agent::invalidate-extension-host-generation
       host)))
  (setf (cadr-agent:agent-session agent) session
        (cadr-agent:agent-messages agent)
        (cadr-agent:session-messages session))
  session)

(defun session-export-basename (session)
  (format
   nil "cadr-session-~A_~A.html"
   (cl-ppcre:regex-replace-all
    "[:.]"
    (cadr-core:milliseconds-to-utc-iso8601
     (cadr-agent:session-timestamp session))
    "-")
   (cadr-agent:session-id session)))

(defun session-export-path (session argument cwd)
  (resolve-general-path
   (or argument (session-export-basename session))
   cwd))

(defun handle-session-command
    (line agent
     &key
       (directory (cadr-agent:default-session-directory))
       (cwd (uiop:getcwd))
       (output *standard-output*)
       (copy-function #'default-copy-text)
       (share-runner
         #'default-share-command-runner)
       changelog-path
       keybindings
       status-function
       export-options-function
       ansi-theme-p
       model-price-function
       (confirm-function
         (lambda (title message)
           (declare (ignore title message))
           t))
       cwd-confirm-function)
  (multiple-value-bind (command argument)
      (split-command line)
    (cond
      ((string= command "/name")
       (unless (cadr-agent:agent-session agent)
         (error
          'cadr-ai:configuration-error
          :message "The agent has no persistent session"))
       (let* ((session
                (cadr-agent:agent-session agent))
              (host
                (cadr-agent::agent-extension-host
                 agent)))
         (if argument
             (let ((name
                     (if host
                         (cadr-agent::extension-host-set-session-name
                          host argument)
                         (progn
                           (cadr-agent:session-set-name
                            session argument)
                           (cadr-agent:session-name
                            session)))))
               (format output
                       "Session name set: ~A~%"
                       (or name argument)))
             (if (cadr-agent:session-name session)
                 (format
                  output
                  "Session name: ~A~%"
                  (cadr-agent:session-name session))
                 (if status-function
                     (funcall
                      status-function
                      "Usage: /name <name>"
                      :warning)
                     (format output
                             "Usage: /name <name>~%")))))
       (finish-output output)
       t)
      ((string= command "/session")
       (unless (cadr-agent:agent-session agent)
         (error
          'cadr-ai:configuration-error
          :message "The agent has no persistent session"))
       (write-session-command-info
        (cadr-agent:agent-session agent)
        output
        :ansi-theme-p ansi-theme-p
        :model-price-function model-price-function)
       (finish-output output)
       t)
      ((string= command "/share")
       (unless (cadr-agent:agent-session agent)
         (error
          'cadr-ai:configuration-error
          :message "The agent has no persistent session"))
       (multiple-value-bind
             (viewer-url gist-url)
           (share-session
            (cadr-agent:agent-session agent)
            :agent agent
            :runner share-runner)
         (unless (eq gist-url :cancelled)
           (format output "Share URL: ~A~%" viewer-url)
           (when (and gist-url (plusp (length gist-url)))
             (format output "Gist: ~A~%" gist-url))))
       (finish-output output)
       t)
      ((string= command "/bug")
       (let* ((id (cadr-ai:uuid-v7))
              (path
                (merge-pathnames
                 (bug-report-archive-file-name id)
                 (uiop:getcwd)))
              (metadata
                (list
                 :schema-version +bug-report-schema-version+
                 :id id
                 :created-at (cadr-core:current-utc-iso8601)
                 :hint (and argument
                            (plusp (length argument))
                            argument)
                 :environment
                 (bug-report-collect-environment)
                 :session
                 (list
                  :id
                  (and (cadr-agent:agent-session agent)
                       (cadr-agent:session-id
                        (cadr-agent:agent-session agent)))
                  :included nil
                  :summary-included nil)))
              (diagnostics
                (list
                 :schema-version +bug-report-schema-version+
                 :session-id
                 (getf (getf metadata :session) :id)
                 :entry-count 0
                 :assistant-message-count 0
                 :assistant nil
                 :crashes nil)))
         (bug-report-write-zip
          path
          (list
           (cons
            "report.json"
            (with-output-to-string (out)
              (cadr-ai::write-json-value
               (cadr-agent::json-safe-value metadata)
               out)
              (terpri out)))
           (cons
            "diagnostics.json"
            (with-output-to-string (out)
              (cadr-ai::write-json-value
               (cadr-agent::json-safe-value diagnostics)
               out)
              (terpri out)))))
         (if status-function
             (funcall
              status-function
              (format nil "Bug report written: ~A" path)
              :success)
             (format output "Bug report written: ~A~%"
                     (uiop:native-namestring path)))
         (finish-output output)
         t))
      ((string= command "/changelog")
       (let ((entries
               (parse-changelog
                (or changelog-path
                    (default-changelog-path)))))
         (let ((markdown
                 (if entries
                     (format
                      nil "~{~A~^~%~%~}"
                      (mapcar
                       (lambda (entry)
                         (normalize-changelog-links
                          (getf entry :content)
                          (getf entry :version)))
                       (reverse entries)))
                     "No changelog entries found.")))
           (if status-function
               (funcall
                status-function
                (list :title "What's New"
                      :markdown markdown)
                :rich)
               (format output "What's New~%~%~A~%"
                       markdown))))
       (finish-output output)
       t)
      ((string= command "/hotkeys")
       (if status-function
           (funcall
            status-function
            (list
             :title "Keyboard Shortcuts"
             :markdown
             (hotkeys-command-markdown keybindings))
            :rich)
           (write-hotkeys-command
            output keybindings))
       (finish-output output)
       t)
      ((string= command "/new")
       (let ((new
               (new-agent-session
                agent directory cwd)))
         (unless (eq new :cancelled)
           (if status-function
               (funcall status-function
                        "New session started" :success)
               (format output
                       "✓ New session started~%"))))
       (finish-output output)
       t)
      ((string= command "/compact")
       (unless (cadr-agent:compact-agent
                agent
                :force-p t
                :custom-instructions argument)
         (if status-function
             (funcall
              status-function
              "Compaction failed: Nothing to compact (session too small)"
              :error)
             (format
              output
              "Error: Compaction failed: Nothing to compact (session too small)~%")))
       (finish-output output)
       t)
      ((string= command "/copy")
       (let ((text
               (last-assistant-text agent)))
         (if text
             (handler-case
                 (progn
                   (funcall copy-function text)
                   ;; pi@13cbf77df interactive-mode.ts:5956-5960 —
                   ;; fullscreen flashes; regular mode keeps the status.
                   (if *alt-screen-flash-function*
                       (funcall *alt-screen-flash-function*
                                "Copied!")
                       (format
                        output
                        "Copied last agent message to clipboard~%")))
               (condition (condition)
                 (format output "~A~%"
                         condition)))
             (if status-function
                 (funcall status-function
                          "No agent messages to copy yet."
                          :error)
                 (format
                  output
                  "Error: No agent messages to copy yet.~%"))))
       (finish-output output)
       t)
      ((string= command "/clone")
       (let ((clone
               (clone-agent-session
                agent directory)))
         (cond
           ((null clone)
            (format output
                    "Nothing to clone yet~%"))
           ((eq clone :cancelled)
            nil)
           (t
            (format output
                    "Cloned to new session~%"))))
       (finish-output output)
       t)
      ((string= command "/import")
       (let ((path
               (path-command-argument
                line "/import")))
         (if (null path)
             (if status-function
                 (funcall status-function
                          "Usage: /import <path.jsonl>"
                          :error)
                 (format output
                         "Error: Usage: /import <path.jsonl>~%"))
             (if
                 (not
                  (funcall
                   confirm-function
                   "Import session"
                   (format
                    nil
                    "Replace current session with ~A?"
                    path)))
                 (format output
                         "Import cancelled~%")
                 (handler-case
                     (multiple-value-bind
                           (imported error-message missing)
                         (import-agent-session
                          agent path directory cwd)
                       (when (and (null imported) missing
                                  cwd-confirm-function)
                         (let ((override
                                 (funcall
                                  cwd-confirm-function
                                  (missing-session-cwd-error-session-cwd
                                   missing)
                                  cwd)))
                           (when override
                             (multiple-value-setq
                                 (imported error-message missing)
                               (import-agent-session
                                agent path directory cwd
                                :cwd-override override)))))
                       (cond
                         ((eq imported :cancelled)
                          (format output
                                  "Import cancelled~%"))
                         (imported
                          (format
                           output
                           "Session imported from: ~A~%"
                           path))
                         ((and missing
                               (null cwd-confirm-function))
                          (format
                           output
                           "Failed to import session: ~A~%"
                           error-message))
                         ((and missing (null imported))
                          (format output
                                  "Import cancelled~%"))
                         (t
                          (format
                           output
                           "Failed to import session: ~A~%"
                           error-message))))
                   (session-import-file-not-found-error
                       (condition)
                     (format
                      output
                      "Failed to import session: ~A~%"
                      condition))))))
       (finish-output output)
       t)
      ((string= command "/export")
       (unless (cadr-agent:agent-session agent)
         (error
          'cadr-ai:configuration-error
          :message "The agent has no persistent session"))
       (let ((path
               (session-export-path
                (cadr-agent:agent-session agent)
                argument cwd)))
         (apply
          #'cadr-agent:export-session-html
          (cadr-agent:agent-session agent)
          path
          (if export-options-function
              (or (funcall export-options-function)
                  nil)
              nil))
         (let ((message
                 (format nil "Session exported to: ~A"
                         (file-namestring path))))
           (if status-function
               (funcall status-function message)
               (progn
                 (format output "~A~%" message)
                 (finish-output output))))
         t))
      (t nil))))
