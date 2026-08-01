(in-package #:cadr-cli)

(defparameter +default-coding-tool-names+
  '("read" "bash" "edit" "write"))

(defparameter +builtin-coding-tool-names+
  '("read" "bash" "edit" "write" "grep" "find" "ls"))

(defun make-baseline-coding-tools (cwd)
  (list (make-read-tool cwd)
        (make-bash-tool cwd)
        (make-edit-tool cwd)
        (make-write-tool cwd)))

(defun make-coding-tools (cwd)
  (make-baseline-coding-tools cwd))

(defun make-all-coding-tools (cwd)
  (append
   (make-baseline-coding-tools cwd)
   (list
    (make-grep-tool cwd)
    (make-find-tool cwd)
    (make-ls-tool cwd))))

(defun select-coding-tools
    (tools &key allow exclude no-builtin-p builtin-names)
  (let ((selected
          (if allow
              (remove-if-not
               (lambda (tool)
                 (member (cadr-ai:tool-name tool)
                         allow :test #'string=))
               tools)
              (copy-list tools))))
    (when no-builtin-p
      (setf selected
            (remove-if
             (lambda (tool)
               (member (cadr-ai:tool-name tool)
                       builtin-names :test #'string=))
             selected)))
    (remove-if
     (lambda (tool)
       (member (cadr-ai:tool-name tool)
               exclude :test #'string=))
     selected)))

(defun make-agent-event-renderer (&optional
                                    (output *standard-output*))
  (let ((current-message nil)
        (printed-p nil))
    (lambda (event)
      (let ((type (cadr-agent:agent-event-type event))
            (message (cadr-agent:agent-event-message event))
            (stream-event
              (cadr-agent:agent-event-stream-event event)))
        (cond
          ((and (eq type :message-start)
                (typep message 'cadr-ai:assistant-message))
           (setf current-message message
                 printed-p nil))
          ((and (eq type :message-update)
                (eq message current-message)
                stream-event
                (eq :text-delta
                    (cadr-ai:stream-event-type stream-event)))
           (unless printed-p
             (format output "~&assistant> ")
             (setf printed-p t))
           (write-string
            (or (cadr-ai:stream-event-delta stream-event) "")
            output)
           (finish-output output))
          ((and (eq type :message-end)
                (eq message current-message))
           (when printed-p
             (terpri output)
             (finish-output output))
           (when (and (not printed-p)
                      (member
                       (cadr-ai:assistant-message-stop-reason message)
                       '(:error :aborted)))
             (format
              output "error> ~A~%"
              (or
               (cadr-ai:assistant-message-error-message message)
               (cadr-ai:assistant-message-stop-reason message)))
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
            (cadr-agent:agent-event-error-message event))
           (finish-output output)))))))

(defun session-argument-path-p (argument)
  (or
   (position #\/ argument)
   (position #\\ argument)
   (uiop:string-suffix-p ".jsonl" argument)))

(defun find-session-by-id-or-prefix
    (argument sessions)
  (or
   (find
    argument sessions
    :key #'cadr-agent:session-id
    :test #'string=)
   (find-if
    (lambda (session)
      (uiop:string-prefix-p
       argument
       (cadr-agent:session-id session)))
    sessions)))

(defun resolve-fork-source-session
    (argument directory cwd)
  (if (session-argument-path-p argument)
      (cadr-agent:load-session
       (merge-pathnames
        (pathname argument)
        (uiop:ensure-directory-pathname cwd)))
      (or
       (find-session-by-id-or-prefix
        argument
        (cadr-agent:list-sessions
         :directory directory :cwd cwd))
       (find-session-by-id-or-prefix
        argument
        (cadr-agent:list-sessions
         :directory directory))
       (cadr-agent:resume-session
        argument :directory directory))))

(defun resolve-cli-session
    (&key
       continue-p
       resume-id
       resume-selector-p
       no-session-p
       session-path
       session-id
       fork-source
       cwd
       (directory (cadr-agent:default-session-directory))
       (output *error-output*))
  (let ((selectors
          (remove
           nil
           (list
            (and continue-p "--continue")
            (and resume-id "--resume")
            (and resume-selector-p "--resume")
            (and session-path "--session")
            (and fork-source "--fork")))))
    (when (> (length selectors) 1)
      (error
       'cadr-ai:configuration-error
       :message
       (format nil "~{~A~^ and ~} are mutually exclusive"
               selectors))))
  (when (and session-id
             (or continue-p resume-id
                 resume-selector-p session-path))
    (error
     'cadr-ai:configuration-error
     :message
     "--session-id cannot be combined with --session, --continue, or --resume"))
  (when (and fork-source no-session-p)
    (error
     'cadr-ai:configuration-error
     :message "--fork cannot be combined with --no-session"))
  (when session-id
    (unless
        (and
         (plusp (length session-id))
         (<= (length session-id) 128)
         (every
          (lambda (character)
            (or
             (alphanumericp character)
             (member character
                     '(#\- #\_ #\.))))
          session-id)
         (not (member session-id
                      '("." "..")
                      :test #'string=)))
      (error
       'cadr-ai:configuration-error
       :message
       (format nil "Invalid session id: ~S"
               session-id))))
  (when no-session-p
    (return-from resolve-cli-session nil))
  (cond
    (fork-source
     (let* ((source
              (resolve-fork-source-session
               fork-source directory cwd))
            (target
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
    (session-path
     (cadr-agent:load-session
      (merge-pathnames
       (pathname session-path)
       (uiop:ensure-directory-pathname
        cwd))))
    (resume-id
     (let ((session
             (cadr-agent:resume-session
              resume-id :directory directory)))
       (unless
           (string=
            (cadr-agent:session-cwd session)
            (cadr-agent::canonical-session-cwd cwd))
         (error
          'cadr-ai:configuration-error
          :message
          (format nil
                  "Session ~A belongs to ~A, not ~A"
                  resume-id
                  (cadr-agent:session-cwd session)
                  (cadr-agent::canonical-session-cwd cwd))))
       session))
    (resume-selector-p
     (first
      (cadr-agent:list-sessions
       :directory directory :cwd cwd)))
    (continue-p
     (or
      (cadr-agent:continue-session
       :directory directory :cwd cwd)
      (progn
        (format output
                "cadr: no previous session for ~A; starting a new session~%"
                (namestring
                 (truename
                  (uiop:ensure-directory-pathname cwd))))
        (finish-output output)
        (cadr-agent:create-session
         :directory directory :cwd cwd))))
    (session-id
     (or
      (find
       session-id
       (cadr-agent:list-sessions
        :directory directory :cwd cwd)
       :key #'cadr-agent:session-id
       :test #'string=)
      (progn
        (format
         output
         "cadr: no project session with id ~A; creating it~%"
         session-id)
        (finish-output output)
        (cadr-agent:create-session
         :directory directory :cwd cwd
         :id session-id))))
    (t
     (cadr-agent:create-session
      :directory directory :cwd cwd))))

(defun process-cli-file-arguments
    (paths &optional (cwd (uiop:getcwd)))
  (let ((text
          (make-array
           0 :element-type 'character
           :adjustable t :fill-pointer 0))
        (images nil))
    (dolist (raw paths)
      (let ((path
              (resolve-readable-tool-path
               cwd raw)))
        (unless
            (zerop
             (with-open-file
                 (stream path
                         :direction :input
                         :element-type
                         '(unsigned-byte 8))
               (file-length stream)))
          (multiple-value-bind
                (bytes mime-type hints)
              (process-image-file path)
            (if mime-type
                (progn
                  (format
                   text
                   "<file name=\"~A\">~{~A~^~%~}</file>~%"
                   (namestring path)
                   hints)
                  (push
                   (cadr-ai:make-image-content
                    :mime-type mime-type
                    :data
                    (encode-base64-bytes bytes))
                   images))
                (format
                 text
                 "<file name=\"~A\">~%~A~%</file>~%"
                 (namestring path)
                 (uiop:read-file-string
                  path :external-format :utf-8)))))))
    (values
     (coerce text 'string)
     (nreverse images))))

(defun print-cli-models
    (pattern &optional
               (output *standard-output*))
  (let ((needle
          (and
           (stringp pattern)
           (string-downcase pattern))))
    (dolist
        (metadata
         (sort
          (copy-list
           (cadr-ai:list-model-metadata))
          #'string<
          :key
          (lambda (item)
            (format nil "~(~A~)/~A"
                    (cadr-ai:model-metadata-provider
                     item)
                    (cadr-ai:model-metadata-id
                     item)))))
      (let ((name
              (format nil "~(~A~)/~A"
                      (cadr-ai:model-metadata-provider
                       metadata)
                      (cadr-ai:model-metadata-id
                       metadata))))
        (when
            (or
             (null needle)
             (search needle
                     (string-downcase name)))
          (format output "~A~%" name)))))
  (finish-output output))

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
     :label-timestamp
     (gethash id label-timestamps)
     :tool-call-only-p
     (and
      (typep message 'cadr-ai:assistant-message)
      (assistant-tool-call-only-p message))
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
       (source :interactive))
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
            selected previous-thinking))
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
    (settings-set-default-model-and-provider
     settings-manager
     (provider-key
      (cadr-ai:model-provider selected))
     (cadr-ai:model-id selected))
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
    (agent directory cwd)
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
              cwd))))
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

(defun write-session-command-info
    (session output)
  (let* ((stats
           (session-command-stats session))
         (input
           (+ (getf stats :input)
              (getf stats :cache-read)
              (getf stats :cache-write)))
         (total
           (+ input
              (getf stats :output))))
    (format output "Session Info~%~%")
    (when (cadr-agent:session-name session)
      (format output "Name: ~A~%"
              (cadr-agent:session-name session)))
    (format
     output
     "File: ~A~%ID: ~A~%~%Messages~%Total: ~:D~%User: ~:D~%Assistant: ~:D~%Tools: ~:D calls, ~:D results~%~%Tokens~%Input: ~:D~%"
     (namestring
      (cadr-agent:session-path session))
     (cadr-agent:session-id session)
     (+ (getf stats :user)
        (getf stats :assistant)
        (getf stats :tool-results))
     (getf stats :user)
     (getf stats :assistant)
     (getf stats :tool-calls)
     (getf stats :tool-results)
     input)
    (when
        (plusp
         (+ (getf stats :cache-read)
            (getf stats :cache-write)))
      (format
       output
       "  Cached: ~:D~%  Uncached: ~:D"
       (getf stats :cache-read)
       (+ (getf stats :input)
          (getf stats :cache-write)))
      (when (plusp
             (getf stats :cache-write))
        (format output
                " (~:D written to cache)"
                (getf stats :cache-write)))
      (terpri output))
    (format
     output
     "Output: ~:D~%Total: ~:D~%"
     (getf stats :output)
     total)
    (when
        (plusp (getf stats :cost))
      (format
       output
       "~%Cost~%Total: $~,3F~%"
       (getf stats :cost)))))

(defun default-changelog-path ()
  (or
   (let ((value
           (uiop:getenv
            "CADR_CHANGELOG_PATH")))
     (and value
          (plusp (length value))
          (pathname value)))
   (handler-case
       (asdf:system-relative-pathname
        "cadr-cli" "CHANGELOG.md")
     (condition () nil))
   #p"CHANGELOG.md"))

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

(defun import-agent-session
    (agent input directory cwd)
  (let* ((source
           (resolve-general-path input cwd)))
    (unless (probe-file source)
      (return-from import-agent-session
        (values nil
                (format nil "File not found: ~A"
                        (namestring source)))))
    (let* ((session-directory
             (uiop:ensure-directory-pathname
              directory))
           (destination
             (merge-pathnames
              (file-namestring source)
              session-directory)))
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
        (let ((temporary
                (merge-pathnames
                 (format nil ".~A-import-~A.tmp"
                         (or
                          (pathname-name destination)
                          "session")
                         (cadr-ai:uuid-v7))
                 session-directory)))
          (unwind-protect
               (progn
                 (uiop:copy-file
                  source temporary)
                 (uiop:rename-file-overwriting-target
                  temporary destination))
            (when (probe-file temporary)
              (delete-file temporary)))))
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
                (probe-file
                 (uiop:ensure-directory-pathname
                  (cadr-agent:session-cwd
                   imported)))
              (error
               "Session working directory does not exist: ~A"
               (cadr-agent:session-cwd imported)))
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
           (format nil "~A" condition)))))))

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
       (confirm-function
         (lambda (title message)
           (declare (ignore title message))
           t)))
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
                 (format output
                         "Usage: /name <name>~%"))))
       (finish-output output)
       t)
      ((string= command "/session")
       (unless (cadr-agent:agent-session agent)
         (error
          'cadr-ai:configuration-error
          :message "The agent has no persistent session"))
       (write-session-command-info
        (cadr-agent:agent-session agent)
        output)
       (finish-output output)
       t)
      ((string= command "/share")
       (unless (cadr-agent:agent-session agent)
         (error
          'cadr-ai:configuration-error
          :message "The agent has no persistent session"))
       (multiple-value-bind
             (viewer-url gist-url)
           (share-session-as-gist
            (cadr-agent:agent-session agent)
            :runner share-runner)
         (format
          output
          "Share URL: ~A~%Gist: ~A~%"
          viewer-url gist-url))
       (finish-output output)
       t)
      ((string= command "/changelog")
       (let ((entries
               (parse-changelog
                (or changelog-path
                    (default-changelog-path)))))
         (format output "What's New~%~%")
         (if entries
             (loop
               for entry
               in (reverse entries)
               do
               (format
                output "~A~@[~%~]"
                (normalize-changelog-links
                 (getf entry :content)
                 (getf entry :version))
                (not
                 (eq entry
                     (first entries)))))
             (format output
                     "No changelog entries found.~%")))
       (finish-output output)
       t)
      ((string= command "/hotkeys")
       (write-hotkeys-command
        output keybindings)
       (finish-output output)
       t)
      ((string= command "/new")
       (let ((new
               (new-agent-session
                agent directory cwd)))
         (unless (eq new :cancelled)
           (format output
                   "New session started~%")))
       (finish-output output)
       t)
      ((string= command "/compact")
       (unless (cadr-agent:compact-agent
                agent
                :force-p t
                :custom-instructions argument)
         (format output
                 "session> Nothing to compact~%"))
       (finish-output output)
       t)
      ((string= command "/copy")
       (let ((text
               (last-assistant-text agent)))
         (if text
             (handler-case
                 (progn
                   (funcall copy-function text)
                   (format
                    output
                    "Copied last agent message to clipboard~%"))
               (condition (condition)
                 (format output "~A~%"
                         condition)))
             (format
              output
              "No agent messages to copy yet.~%")))
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
             (format output
                     "Usage: /import <path.jsonl>~%")
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
                 (multiple-value-bind
                       (imported error-message)
                     (import-agent-session
                      agent path directory cwd)
                   (cond
                     ((eq imported :cancelled)
                      (format output
                              "Import cancelled~%"))
                     (imported
                      (format
                       output
                       "Session imported from: ~A~%"
                       path))
                     (t
                      (format
                       output
                       "Failed to import session: ~A~%"
                       error-message)))))))
       (finish-output output)
       t)
      ((string= command "/export")
       (unless (cadr-agent:agent-session agent)
         (error
          'cadr-ai:configuration-error
          :message "The agent has no persistent session"))
       (let ((path
               (pathname
                (or argument
                    (format nil "~A.html"
                            (cadr-agent:session-id
                             (cadr-agent:agent-session
                              agent)))))))
         (cadr-agent:export-session-html
          (cadr-agent:agent-session agent) path)
         (format output "Exported ~A~%"
                 (namestring path))
         (finish-output output)
         t))
      (t nil))))

(defun call-with-cli-signal-handlers (agent function)
  #+sbcl
  (catch 'cadr-cli-signal
    (sb-sys:with-interrupt-bindings
      (flet ((exit-on-signal (exit-code)
               (lambda (signal code context)
                 (declare (ignore signal code context))
                 (cadr-agent:agent-abort agent)
                 (throw 'cadr-cli-signal exit-code))))
        (sb-sys:enable-interrupt
         sb-unix:sigterm
         (exit-on-signal 143))
        #-win32
        (sb-sys:enable-interrupt
         sb-unix:sighup
         (exit-on-signal 129)))
      (funcall function)))
  #-sbcl
  (funcall function))

(defun default-agent-directory ()
  (merge-pathnames
   ".cadr/"
   (user-homedir-pathname)))

(defun prompt-project-trust
    (directory
     &optional
       (input *standard-input*)
       (output *standard-output*))
  (format
   output
   "Trust project resources in ~A? [y/N] "
   (namestring
    (uiop:ensure-directory-pathname
     directory)))
  (finish-output output)
  (let ((answer
          (read-line input nil "")))
    (member
     (string-downcase
      (string-trim
       '(#\Space #\Tab)
       answer))
     '("y" "yes")
     :test #'string=)))

(defun tool-prompt-snippets (tools)
  (let ((baseline
          '(("read" . "Read file contents")
            ("bash"
             . "Execute bash commands (ls, grep, find, etc.)")
            ("edit"
             . "Make precise file edits with exact text replacement, including multiple disjoint edits in one call")
            ("write" . "Create or overwrite files")
            ("grep"
             . "Search file contents for patterns (respects .gitignore)")
            ("find"
             . "Find files by glob pattern (respects .gitignore)")
            ("ls" . "List directory contents"))))
    (mapcar
     (lambda (tool)
       (let* ((name (cadr-ai:tool-name tool))
              (snippet
                (cdr (assoc name baseline :test #'string=))))
         (cons
          name
          (or snippet
              (cadr-ai:tool-description tool)))))
     tools)))

(defun tool-prompt-guidelines (tools)
  (loop for tool in tools
        append
        (cond
          ((string= "read" (cadr-ai:tool-name tool))
           (list
            "Use read to examine files instead of cat or sed."))
          ((string= "edit" (cadr-ai:tool-name tool))
           (list
            "Use edit for precise changes (edits[].oldText must match exactly)"
            "When changing multiple separate locations in one file, use one edit call with multiple entries in edits[] instead of multiple edit calls"
            "Each edits[].oldText is matched against the original file, not after earlier edits are applied. Do not emit overlapping or nested edits. Merge nearby changes into one edit."
            "Keep edits[].oldText as small as possible while still being unique in the file. Do not pad with large unchanged regions."))
          ((string= "write" (cadr-ai:tool-name tool))
           (list
            "Use write only for new files or complete rewrites."))
          (t nil))))

(defun settings-boolean-value
    (manager key default &optional nested-key)
  (let ((value
          (if nested-key
              (settings-nested-value
               manager key nested-key :missing)
              (settings-value
               manager key :missing))))
    (if (eq value :missing)
        default
        (eq value t))))

(defun settings-show-terminal-progress-p (manager)
  (let ((terminal-settings
          (settings-value
           manager "terminal"
           (empty-json-object))))
    (and
     (hash-table-p terminal-settings)
     (eq t
         (cadr-ai::json-get
          terminal-settings
          "showTerminalProgress"
          nil)))))

(defun settings-terminal-theme-mode (manager)
  (let ((configured
          (settings-value manager "theme" nil)))
    (cond
      ((null configured) :detect-once)
      ((parse-auto-theme-setting configured) :auto)
      (t :fixed))))

(defun settings-choice-value
    (manager key choices default)
  (let ((value
          (settings-value manager key default)))
    (if (member value choices :test #'equal)
        value
        default)))

(defun http-idle-timeout-label (timeout-ms)
  (or
   (cdr
    (assoc timeout-ms
           '((30000 . "30 sec")
             (60000 . "1 min")
             (120000 . "2 min")
             (300000 . "5 min")
             (0 . "disabled"))))
   (format nil "~,3G sec"
           (/ timeout-ms 1000.0))))

(defun default-project-trust-label (value)
  (cond
    ((string= value "always") "Always trust")
    ((string= value "never") "Never trust")
    (t "Ask")))

(defun set-cli-thinking-level
    (agent settings-manager level)
  (let* ((previous
           (cadr-agent::agent-thinking-level agent))
         (effective
           (cadr-ai:clamp-thinking-level
            (cadr-agent:agent-model agent)
            level)))
    (unless (eq previous effective)
      (setf
       (cadr-agent::agent-thinking-level agent)
       effective)
      (when (cadr-agent:agent-session agent)
        (cadr-agent:session-append-thinking-level-change
         (cadr-agent:agent-session agent)
         (string-downcase
          (symbol-name effective))))
      (when
          (or
           (cadr-ai:model-reasoning-p
            (cadr-agent:agent-model agent))
           (not (eq effective :off)))
        (settings-set
         settings-manager
         "defaultThinkingLevel"
         (string-downcase
          (symbol-name effective))
         :scope :global))
      (run-session-lifecycle
       agent :thinking-level-select
       :level effective
       :previous-level previous))
    effective))

(defun sync-agent-settings-from-manager
    (agent settings-manager)
  (setf
   (cadr-agent::agent-auto-compact-p agent)
   (settings-boolean-value
    settings-manager
    "compaction" t "enabled")
   (cadr-agent:agent-steering-mode agent)
   (if
       (string=
        "all"
        (settings-choice-value
         settings-manager "steeringMode"
         '("one-at-a-time" "all")
         "one-at-a-time"))
       :all
       :one-at-a-time)
   (cadr-agent:agent-follow-up-mode agent)
   (if
       (string=
        "all"
        (settings-choice-value
         settings-manager "followUpMode"
         '("one-at-a-time" "all")
         "one-at-a-time"))
       :all
       :one-at-a-time))
  agent)

(defun reload-cli-runtime
    (agent settings-manager
     &key
       extension-reload-function
       resource-reload-function
       system-prompt-function
       model-refresh-function
       keybindings-reload-function
       completion-function)
  (run-session-lifecycle
   agent :session-shutdown
   :reason :reload)
  (settings-reload settings-manager)
  (clear-config-value-cache)
  (sync-agent-settings-from-manager
   agent settings-manager)
  (when extension-reload-function
    (funcall extension-reload-function))
  (let ((resources
          (and resource-reload-function
               (funcall
                resource-reload-function))))
    (when system-prompt-function
      (setf
       (cadr-agent::agent-system-prompt agent)
       (funcall
        system-prompt-function resources)))
    (when model-refresh-function
      (funcall model-refresh-function))
    (when keybindings-reload-function
      (funcall keybindings-reload-function))
    (run-session-lifecycle
     agent :session-start
     :reason :reload)
    (when completion-function
      (funcall
       completion-function
       "Reloaded keybindings, extensions, skills, prompts, themes, and context files"))
    resources))

(defun make-cli-settings-selector-state
    (settings-manager agent resources
     &key keybindings
       (supports-images-p
         (not
          (null
           (cadr-tui:terminal-capabilities-images
            (cadr-tui:get-terminal-capabilities))))))
  (let* ((terminal
           (settings-value
            settings-manager
            "terminal"
            (empty-json-object)))
         (images
           (settings-value
            settings-manager
            "images"
            (empty-json-object)))
         (theme-names
           (remove-duplicates
            (cons
             "dark"
             (loop
               for theme
                 in (and resources
                         (resource-snapshot-themes
                          resources))
               for name = (getf theme :name)
               when (stringp name)
                 collect name))
            :test #'string=))
         (current-theme
           (let ((configured
                   (settings-value
                    settings-manager "theme" "dark")))
             (if (or (member configured theme-names
                             :test #'string=)
                     (parse-auto-theme-setting configured))
                 configured
                 "dark")))
         (follow-up-key
           (or
            (and keybindings
                 (first
                  (cadr-tui:keybinding-keys
                   keybindings "app.message.followUp")))
            (and keybindings
                 (let ((binding
                         (assoc
                          "app.message.followUp"
                          (cadr-tui::keybindings-manager-user-bindings
                           keybindings)
                          :test #'string=)))
                   (let ((value (cdr binding)))
                     (if (listp value)
                         (first value)
                         value))))
            "alt+enter"))
         (options
           (list
            (make-settings-option
             :id "autocompact"
             :label "Auto-compact"
             :description
             "Automatically compact context when it gets too large"
             :value
             (cadr-agent::agent-auto-compact-p agent)
             :values (list t nil))
            (make-settings-option
             :id "auto-resize-images"
             :label "Auto-resize images"
             :description
             "Resize large images to 2000x2000 max for better model compatibility"
             :value
             (if (hash-table-p images)
                 (eq t
                     (cadr-ai::json-get
                      images "autoResize" t))
                 t)
             :values (list t nil))
            (make-settings-option
             :id "block-images"
             :label "Block images"
             :description
             "Prevent images from being sent to LLM providers"
             :value
             (if (hash-table-p images)
                 (eq t
                     (cadr-ai::json-get
                      images "blockImages" nil))
                 nil)
             :values (list t nil))
            (make-settings-option
             :id "skill-commands"
             :label "Skill commands"
             :description
             "Register skills as /skill:name commands"
             :value
             (settings-boolean-value
              settings-manager
              "enableSkillCommands" t)
             :values (list t nil))
            (make-settings-option
             :id "show-hardware-cursor"
             :label "Show hardware cursor"
             :description
             "Show the terminal cursor while still positioning it for IME support"
             :value
             (settings-boolean-value
              settings-manager
              "showHardwareCursor" nil)
             :values (list t nil))
            (make-settings-option
             :id "editor-padding"
             :label "Editor padding"
             :description
             "Horizontal padding for input editor (0-3)"
             :value
             (settings-choice-value
              settings-manager "editorPaddingX"
              '(0 1 2 3) 0)
             :values '(0 1 2 3))
            (make-settings-option
             :id "output-padding"
             :label "Output padding"
             :description
             "Horizontal padding for user messages, assistant messages, and thinking"
             :value
             (settings-output-padding
              settings-manager)
             :values '(0 1))
            (make-settings-option
             :id "autocomplete-max-visible"
             :label "Autocomplete max items"
             :description
             "Max visible items in autocomplete dropdown (3-20)"
             :value
             (settings-choice-value
              settings-manager
              "autocompleteMaxVisible"
              '(3 5 7 10 15 20) 5)
             :values '(3 5 7 10 15 20))
            (make-settings-option
             :id "clear-on-shrink"
             :label "Clear on shrink"
             :description
             "Clear empty rows when content shrinks (may cause flicker)"
             :value
             (if (hash-table-p terminal)
                 (eq t
                     (cadr-ai::json-get
                      terminal "clearOnShrink" nil))
                 nil)
             :values (list t nil))
            (make-settings-option
             :id "terminal-progress"
             :label "Terminal progress"
             :description
             "Show OSC 9;4 progress indicators in the terminal tab bar"
             :value
             (if (hash-table-p terminal)
                 (eq t
                     (cadr-ai::json-get
                      terminal "showTerminalProgress"
                      nil))
                 nil)
             :values (list t nil))
            (make-settings-option
             :id "steering-mode"
             :label "Steering mode"
             :description
             "Enter while streaming queues steering messages. 'one-at-a-time': deliver one, wait for response. 'all': deliver all at once."
             :value
             (cadr-agent:agent-steering-mode agent)
             :values '(:one-at-a-time :all))
            (make-settings-option
             :id "follow-up-mode"
             :label "Follow-up mode"
             :description
             (format
              nil
              "~A queues follow-up messages until agent stops. 'one-at-a-time': deliver one, wait for response. 'all': deliver all at once."
              follow-up-key)
             :value
             (cadr-agent:agent-follow-up-mode agent)
             :values '(:one-at-a-time :all))
            (make-settings-option
             :id "transport"
             :label "Transport"
             :description
             "Preferred transport for providers that support multiple transports"
             :value
             (settings-choice-value
              settings-manager "transport"
              '("sse" "websocket"
                "websocket-cached" "auto")
              "auto")
             :values
             '("sse" "websocket"
               "websocket-cached" "auto"))
            (make-settings-option
             :id "http-idle-timeout"
             :label "HTTP idle timeout"
             :description
             "Maximum idle gap while waiting for HTTP headers or body chunks. Disable for local models that pause longer than five minutes."
             :value
             (settings-http-idle-timeout-ms
              settings-manager)
             :values
             '(30000 60000 120000 300000 0)
             :format-function
             #'http-idle-timeout-label)
            (make-settings-option
             :id "hide-thinking"
             :label "Hide thinking"
             :description
             "Hide thinking blocks in assistant responses"
             :value
             (settings-boolean-value
              settings-manager
              "hideThinkingBlock" nil)
             :values (list t nil))
            (make-settings-option
             :id "cache-miss-notices"
             :label "Cache miss notices"
             :description
             "Show transcript notices for significant prompt-cache misses"
             :value
             (settings-boolean-value
              settings-manager
              "showCacheMissNotices" nil)
             :values (list t nil))
            (make-settings-option
             :id "collapse-changelog"
             :label "Collapse changelog"
             :description
             "Show condensed changelog after updates"
             :value
             (settings-boolean-value
              settings-manager
              "collapseChangelog" nil)
             :values (list t nil))
            (make-settings-option
             :id "quiet-startup"
             :label "Quiet startup"
             :description
             "Disable verbose printing at startup"
             :value
             (settings-boolean-value
              settings-manager
              "quietStartup" nil)
             :values (list t nil))
            (make-settings-option
             :id "install-telemetry"
             :label "Install telemetry"
             :description
             "Send an anonymous version/update ping after changelog-detected updates"
             :value
             (settings-boolean-value
              settings-manager
              "enableInstallTelemetry" t)
             :values (list t nil))
            (make-settings-option
             :id "default-project-trust"
             :label "Default project trust"
             :description
             "Fallback behavior when no extension or saved trust decision decides project trust"
             :value
             (settings-choice-value
              settings-manager
              "defaultProjectTrust"
              '("ask" "always" "never")
              "ask")
             :values '("ask" "always" "never")
             :format-function
             #'default-project-trust-label)
            (make-settings-option
             :id "double-escape-action"
             :label "Double-escape action"
             :description
             "Action when pressing Escape twice with empty editor"
             :value
             (settings-choice-value
              settings-manager
              "doubleEscapeAction"
              '("tree" "fork" "none")
              "tree")
             :values '("tree" "fork" "none"))
            (make-settings-option
             :id "tree-filter-mode"
             :label "Tree filter mode"
             :description
             "Default filter when opening /tree"
             :value
             (settings-choice-value
              settings-manager
              "treeFilterMode"
              '("default" "no-tools" "user-only"
                "labeled-only" "all")
              "default")
             :values
             '("default" "no-tools" "user-only"
               "labeled-only" "all"))
            (make-settings-option
             :id "warnings"
             :label "Warnings"
             :description
             "Enable or disable individual warnings"
             :value
             (list
              :anthropic-extra-usage
              (settings-boolean-value
               settings-manager
               "warnings" t
               "anthropicExtraUsage"))
             :format-function
             (lambda (value)
               (declare (ignore value))
               "configure")
             :submenu :warnings)
            (make-settings-option
             :id "thinking"
             :label "Thinking level"
             :description
             "Reasoning depth for thinking-capable models"
             :value
             (cadr-agent::agent-thinking-level agent)
             :values
             (cadr-ai:supported-thinking-levels
              (cadr-agent:agent-model agent))
             :submenu :thinking)
            (make-settings-option
             :id "theme"
             :label "Theme"
             :description
             "Color theme for the interface"
             :value current-theme
             :values theme-names
             :submenu :theme))))
    (when supports-images-p
      (setf
       options
       (append
        (subseq options 0 1)
        (list
         (make-settings-option
          :id "show-images"
          :label "Show images"
          :description "Render images inline in terminal"
          :value
          (if (hash-table-p terminal)
              (eq t
                  (cadr-ai::json-get
                   terminal "showImages" t))
              t)
          :values (list t nil))
         (make-settings-option
          :id "image-width-cells"
          :label "Image width"
          :description
          "Preferred inline image width in terminal cells"
          :value
          (let ((value
                  (and
                   (hash-table-p terminal)
                   (cadr-ai::json-get
                    terminal "imageWidthCells" 60))))
            (if (member value '(60 80 120)) value 60))
          :values '(60 80 120)))
        (subseq options 1))))
    (make-settings-selector-state
     :options options
     :theme-names theme-names
     :current-theme current-theme
     :terminal-theme
     (theme-detection-theme
      (detect-background-from-environment))
     :keybindings keybindings
     :change-callback
     (lambda (id value)
       (cond
         ((string= id "autocompact")
          (settings-set-nested
           settings-manager
           "compaction" "enabled" value
           :scope :global)
          (setf
           (cadr-agent::agent-auto-compact-p agent)
           value))
         ((string= id "auto-resize-images")
          (settings-set-nested
           settings-manager
           "images" "autoResize" value
           :scope :global))
         ((string= id "show-images")
          (settings-set-nested
           settings-manager
           "terminal" "showImages" value
           :scope :global))
         ((string= id "image-width-cells")
          (settings-set-nested
           settings-manager
           "terminal" "imageWidthCells" value
           :scope :global))
         ((string= id "block-images")
          (settings-set-nested
           settings-manager
           "images" "blockImages" value
           :scope :global))
         ((string= id "clear-on-shrink")
          (settings-set-nested
           settings-manager
           "terminal" "clearOnShrink" value
           :scope :global))
         ((string= id "terminal-progress")
          (settings-set-nested
           settings-manager
           "terminal" "showTerminalProgress"
           value :scope :global))
         ((string= id "anthropic-extra-usage")
          (settings-set-nested
           settings-manager
           "warnings" "anthropicExtraUsage"
           value :scope :global))
         ((string= id "steering-mode")
          (setf
           (cadr-agent:agent-steering-mode agent)
           value)
          (settings-set
           settings-manager "steeringMode"
           (string-downcase
            (symbol-name value))
           :scope :global))
         ((string= id "follow-up-mode")
          (setf
           (cadr-agent:agent-follow-up-mode agent)
           value)
          (settings-set
           settings-manager "followUpMode"
           (string-downcase
            (symbol-name value))
           :scope :global))
         ((string= id "thinking")
          (set-cli-thinking-level
           agent settings-manager value))
         (t
          (let ((key
                  (cdr
                   (assoc
                    id
                    '(("skill-commands"
                       . "enableSkillCommands")
                      ("show-hardware-cursor"
                       . "showHardwareCursor")
                      ("editor-padding"
                       . "editorPaddingX")
                      ("output-padding"
                       . "outputPad")
                      ("autocomplete-max-visible"
                       . "autocompleteMaxVisible")
                      ("transport" . "transport")
                      ("http-idle-timeout"
                       . "httpIdleTimeoutMs")
                      ("hide-thinking"
                       . "hideThinkingBlock")
                      ("cache-miss-notices"
                       . "showCacheMissNotices")
                      ("collapse-changelog"
                       . "collapseChangelog")
                      ("quiet-startup"
                       . "quietStartup")
                      ("install-telemetry"
                       . "enableInstallTelemetry")
                      ("default-project-trust"
                       . "defaultProjectTrust")
                      ("double-escape-action"
                       . "doubleEscapeAction")
                      ("tree-filter-mode"
                       . "treeFilterMode")
                      ("theme" . "theme"))
                    :test #'string=))))
            (when key
              (settings-set
               settings-manager key value
               :scope :global)))))))))

(defun resolve-cli-system-prompt
    (command snapshot tools cwd)
  (let* ((snapshot-system
           (resource-snapshot-system-prompt-path
            snapshot))
         (custom-source
           (or
            (cli-arguments-system-prompt command)
            snapshot-system))
         (append-sources
           (append
            (when
                (resource-snapshot-append-system-prompt-path
                 snapshot)
              (list
               (resource-snapshot-append-system-prompt-path
                snapshot)))
            (cli-arguments-append-system-prompts
             command)))
         (append-text
           (when append-sources
             (format
              nil "~{~A~^~%~%~}"
              (mapcar
               #'resolve-system-prompt
               append-sources)))))
    (build-system-prompt
     :custom-prompt
     (and custom-source
          (resolve-system-prompt custom-source))
     :append-system-prompt append-text
     :selected-tools
     (mapcar #'cadr-ai:tool-name tools)
     :tool-snippets
     (tool-prompt-snippets tools)
     :prompt-guidelines
     (tool-prompt-guidelines tools)
     :context-files
     (resource-snapshot-context-files snapshot)
     :skills
     (resource-snapshot-skills snapshot)
     :cwd
     (namestring
      (uiop:ensure-directory-pathname cwd)))))

(defun cli-handler (command)
  (let* ((input-terminal-p
           (cadr-tui:terminal-stream-p
            *standard-input* :input))
         (output-terminal-p
           (cadr-tui:terminal-stream-p
            *standard-output* :output))
         (mode
           (resolve-cli-mode
            command
            input-terminal-p
            output-terminal-p))
         (tui-p (eq mode :tui))
         (repl-p (eq mode :repl))
         (event-consumer nil)
         (notice-consumer nil)
         (status-consumer nil)
         (auth-url-consumer nil)
         (model-consumer nil)
         (abort-requested-p nil)
         (frontend-output
           (if tui-p
               (make-notification-output-stream
                (lambda (text)
                  (when notice-consumer
                    (funcall notice-consumer text))))
               (if repl-p
                   *standard-output*
                   *error-output*)))
         (startup-cwd (uiop:getcwd))
         (session-directory
           (if
               (cli-arguments-session-directory
                command)
               (uiop:ensure-directory-pathname
                (merge-pathnames
                 (pathname
                  (cli-arguments-session-directory
                   command))
                 startup-cwd))
               (cadr-agent:default-session-directory)))
         (session
           (resolve-cli-session
            :continue-p
            (cli-arguments-continue-p command)
            :resume-id
            (cli-arguments-resume command)
            :resume-selector-p
            (cli-arguments-resume-p command)
            :no-session-p
            (cli-arguments-no-session-p command)
            :session-path
            (cli-arguments-session command)
            :session-id
            (cli-arguments-session-id command)
            :fork-source
            (cli-arguments-fork command)
            :cwd startup-cwd
            :directory session-directory))
         (cwd
           (if session
               (uiop:ensure-directory-pathname
                (pathname
                 (cadr-agent:session-cwd session)))
               startup-cwd))
         (config
           (resolve-provider-config
            :provider
            (or (cli-arguments-provider command) "openai")
            :model (cli-arguments-model command)
            :reasoning (cli-arguments-thinking command)
            :base-url (cli-arguments-base-url command)
            :api-key (cli-arguments-api-key command)
            :allow-missing-auth-p t))
         (renderer (make-agent-event-renderer))
         (extension-manager
           (make-cli-extension-manager
            :cwd cwd
            :output frontend-output
            :mode mode
            :explicit-paths
            (cli-arguments-extensions command)
            :no-discovery-p
            (cli-arguments-no-extensions-p command)
            :secret-function
            (lambda ()
              (provider-config-secrets config))))
         (_extension-report
           (reload-cli-extensions extension-manager))
         (agent-directory
           (default-agent-directory))
         (trust-store
           (make-project-trust-store
            (merge-pathnames
             "trust.json" agent-directory)))
         (project-trusted-p
           (resolve-project-trusted
            trust-store cwd
            :override
            (cli-arguments-project-trust-override
             command)
            :override-supplied-p
            (cli-arguments-project-trust-override-supplied-p
             command)
            :extension-host
            (cli-extension-manager-host
             extension-manager)
            :default :ask
            :has-ui-p
            (or tui-p repl-p)
            :prompt-function
            (lambda (directory)
              (prompt-project-trust
               directory))))
         (settings-manager
           (make-settings-manager
            :global-path
            (merge-pathnames
             "settings.json" agent-directory)
            :project-path
            (merge-pathnames
             ".cadr/settings.json" cwd)
            :project-trusted-p project-trusted-p))
         (model-registry
           (make-model-registry
            :path
            (merge-pathnames
             "models.json" agent-directory)
            :credentials
            (make-file-auth-storage
             (default-auth-path))))
         (available-models
           (model-registry-available-models
            model-registry
            :explicit-provider
            (cli-arguments-provider command)
            :api-key
            (cli-arguments-api-key command)))
         (scope-patterns
           (or
            (cli-arguments-models command)
            (let ((configured
                    (settings-enabled-models
                     settings-manager)))
              (unless (eq configured :all)
                configured))))
         (scope-resolution
           (if scope-patterns
               (multiple-value-list
                (resolve-scoped-models-with-diagnostics
                 (%make-model-registry
                  :models available-models)
                 scope-patterns))
               (list nil nil)))
         (scoped-model-entries
           (first scope-resolution))
         (scope-diagnostics
           (second scope-resolution))
         (current-enabled-model-ids
           (if scope-patterns
               (enabled-model-ids-for-patterns
                scoped-model-entries
                scope-diagnostics)
               :all))
         (existing-session-p
           (and
            session
            (plusp
             (length
              (cadr-agent:session-messages
               session)))))
         (initial-scope-entry
           (initial-scoped-model-entry
            scoped-model-entries
            (settings-default-provider
             settings-manager)
            (settings-default-model
             settings-manager)
            :existing-session-p
            existing-session-p
            :explicit-model-p
            (not
             (null
              (cli-arguments-model command)))))
         (restored-model
           (and
            (null
             (cli-arguments-model command))
            existing-session-p
            (session-restored-model
             session model-registry
             available-models)))
         (saved-default-model
           (and
            (null
             (cli-arguments-model command))
            (null
             (cli-arguments-provider command))
            (settings-default-provider
             settings-manager)
            (settings-default-model
             settings-manager)
            (let ((candidate
                    (model-registry-find
                     model-registry
                     (settings-default-provider
                      settings-manager)
                     (settings-default-model
                      settings-manager))))
              (and
               candidate
               (find
                candidate
                available-models
                :test
                #'cadr-ai:models-equal-p)))))
         (startup-model
           (or
            (getf initial-scope-entry :model)
            restored-model
            saved-default-model
            (and
             (null
              (cli-arguments-model command))
             (null
              (cli-arguments-provider command))
             (first available-models))))
         (startup-thinking
           (and initial-scope-entry
                (getf initial-scope-entry
                      :thinking)))
         (_startup-model-config
           (when startup-model
             (setf
              config
              (provider-config-for-model
               model-registry startup-model
               :api-key
               (and
                (cli-arguments-provider command)
                (string-equal
                 (provider-key
                  (cadr-ai:model-provider
                   startup-model))
                 (provider-key
                  (cli-arguments-provider command)))
                (cli-arguments-api-key command))
               :base-url
               (and
                (cli-arguments-provider command)
                (string-equal
                 (provider-key
                  (cadr-ai:model-provider
                   startup-model))
                 (provider-key
                  (cli-arguments-provider command)))
                (cli-arguments-base-url
                 command))
               :allow-missing-auth-p t))))
         (_scope-diagnostic-report
           (dolist (diagnostic scope-diagnostics)
             (format
              frontend-output
              "Warning: ~A~%"
              (getf diagnostic :message))
             (finish-output frontend-output)))
         (package-global-root
           (merge-pathnames
            "packages/" agent-directory))
         (package-project-root
           (merge-pathnames
            ".cadr/packages/" cwd))
         (package-records
           (materialize-package-records
            (configured-package-records
             settings-manager
             :global-base agent-directory
             :project-base
             (merge-pathnames ".cadr/" cwd))
            package-global-root
            package-project-root))
         (package-resources
           (package-resource-paths
            package-records))
         (_package-extension-report
           (progn
             (setf
              (cli-extension-manager-configured-package-paths
               extension-manager)
              (unless
                  (cli-arguments-no-extensions-p
                   command)
                (append
                 (mapcar
                  (lambda (path)
                    (cons :project path))
                  (getf package-resources
                        :project-extensions))
                 (mapcar
                  (lambda (path)
                    (cons :global path))
                  (getf package-resources
                        :global-extensions)))))
             (reload-cli-extensions
              extension-manager)))
         (resource-loader
           (make-default-resource-loader
            :cwd cwd
            :agent-directory agent-directory
            :project-trusted-p
            project-trusted-p
            :no-context-files-p
            (cli-arguments-no-context-files-p
             command)
            :no-skills-p
            (cli-arguments-no-skills-p command)
            :no-prompts-p
            (cli-arguments-no-prompt-templates-p
             command)
            :no-themes-p
            (cli-arguments-no-themes-p command)
            :explicit-skill-paths
            (cli-arguments-skills command)
            :explicit-prompt-paths
            (cli-arguments-prompt-templates command)
            :explicit-theme-paths
            (cli-arguments-themes command)
            :package-global-skill-paths
            (getf package-resources
                  :global-skills)
            :package-project-skill-paths
            (getf package-resources
                  :project-skills)
            :package-global-prompt-paths
            (getf package-resources
                  :global-prompts)
            :package-project-prompt-paths
            (getf package-resources
                  :project-prompts)
            :package-global-theme-paths
            (getf package-resources
                  :global-themes)
            :package-project-theme-paths
            (getf package-resources
                  :project-themes)
            :extension-host
            (cli-extension-manager-host
             extension-manager)))
         (resources
           (reload-resources resource-loader))
         (baseline-tools
           (make-all-coding-tools cwd))
         (builtin-names
           +builtin-coding-tool-names+)
         (tool-filter
           (lambda (tools)
             (if
                 (cli-arguments-no-tools-p
                  command)
                 nil
                 (select-coding-tools
                  tools
                  :allow
                  (or
                   (cli-arguments-tools command)
                   (append
                    +default-coding-tool-names+
                    (mapcar
                     #'cadr-ai:tool-name
                     (remove-if
                      (lambda (tool)
                        (member
                         (cadr-ai:tool-name tool)
                         builtin-names
                         :test #'string=))
                      tools))))
                  :exclude
                  (cli-arguments-exclude-tools
                   command)
                  :no-builtin-p
                  (cli-arguments-no-builtin-tools-p
                   command)
                  :builtin-names builtin-names))))
         (selected-baseline-tools
           (funcall tool-filter baseline-tools))
         (agent
           (cadr-agent:make-agent
            :provider (provider-config-provider config)
            :model (provider-config-model config)
            :system-prompt
            (resolve-cli-system-prompt
             command resources
             selected-baseline-tools cwd)
            :tools baseline-tools
            :tool-filter-function tool-filter
            :extension-host
            (cli-extension-manager-host
             extension-manager)
            :stream-function
            (make-extension-aware-stream-function
             (cli-extension-manager-host
              extension-manager)
             :session-id
             (and session
                  (cadr-agent:session-id
                   session)))
            :session session
            :auto-compact-p
            (settings-boolean-value
             settings-manager
             "compaction" t "enabled")
            :abort-p
            (lambda () abort-requested-p)
            :on-event
            (lambda (event)
              (when event-consumer
                (funcall event-consumer event)))))
         (anthropic-warning-state
           (make-anthropic-warning-state)))
    (declare
     (ignore _extension-report
             _package-extension-report
             _startup-model-config
             _scope-diagnostic-report))
    (sync-agent-settings-from-manager
     agent settings-manager)
    (cadr-tui:set-keybindings
     (cadr-tui:make-keybindings-manager
      :user-bindings
      (settings-keybindings
       settings-manager)))
    (when (or
           (cli-arguments-thinking command)
           startup-thinking
           (let ((configured
                   (settings-value
                    settings-manager
                    "defaultThinkingLevel")))
             (and
              (stringp configured)
              (valid-thinking-level-p configured))))
      (setf
       (cadr-agent::agent-thinking-level agent)
       (cadr-ai:clamp-thinking-level
        (cadr-agent:agent-model agent)
        (or
         (cli-arguments-thinking command)
         startup-thinking
         (intern
          (string-upcase
           (settings-value
            settings-manager
            "defaultThinkingLevel"))
          :keyword)))))
    (when (cli-arguments-name command)
      (let ((name
              (string-trim
               '(#\Space #\Tab #\Newline #\Return)
               (cli-arguments-name command))))
        (when (zerop (length name))
          (error
           'cadr-ai:configuration-error
           :message "--name requires a non-empty value"))
        (when session
          (cadr-agent:session-set-name
           session name))))
    (labels
        ((anthropic-warning ()
           (maybe-anthropic-subscription-warning
            anthropic-warning-state
            (cadr-ai:model-provider
             (provider-config-model config))
            (settings-effective-object
             settings-manager)
            (lambda ()
              (let ((provider
                      (provider-config-provider
                       config)))
                (if
                    (cadr-ai::provider-oauth-access-token
                     provider)
                    :oauth
                    (cadr-ai::provider-api-key
                     provider))))))
         (config-subscription-p ()
           (let ((provider
                   (provider-config-provider config)))
             (or
              (and
               provider
               (cadr-ai::provider-oauth-access-token
                provider))
              (string-equal
               (provider-key
                (provider-config-name config))
               "kimi-coding"))))
         (valid-context-assistant-entry-p (entry)
           (and
            (eq
             :message
             (cadr-agent:session-entry-type entry))
            (let ((message
                    (cadr-agent:session-entry-message
                     entry)))
              (and
               (typep
                message
                'cadr-ai:assistant-message)
               (not
                (member
                 (cadr-ai:assistant-message-stop-reason
                  message)
                 '(:aborted :error)))
               (plusp
                (cadr-ai:usage-total
                 (cadr-ai:assistant-message-usage
                  message)))))))
         (current-context-percent ()
           (let* ((model
                    (cadr-agent:agent-model agent))
                  (window
                    (cadr-ai:model-context-window model))
                  (current
                    (cadr-agent:agent-session agent))
                  (entries
                    (and
                     current
                     (cadr-agent::session-path-entries
                      current)))
                  (compaction
                    (and
                     entries
                     (cadr-agent::latest-compaction-entry
                      entries)))
                  (compaction-position
                    (and
                     compaction
                     (position compaction entries
                               :test #'eq))))
             (when
                 (and
                  (plusp window)
                  (or
                   (null compaction)
                   (find-if
                    #'valid-context-assistant-entry-p
                    entries
                    :start
                    (1+ compaction-position))))
               (let ((estimate
                       (cadr-ai:estimate-context-tokens
                        (cadr-agent:agent-messages
                         agent))))
                 (* 100d0
                    (/ (cadr-ai:context-usage-estimate-tokens
                        estimate)
                       window))))))
         (current-cache-hit-rate ()
           (let ((current
                   (cadr-agent:agent-session agent)))
             (when current
               (loop
                 for entry in
                 (reverse
                  (cadr-agent:session-entries
                   current))
                 when
                   (and
                    (eq
                     :message
                     (cadr-agent:session-entry-type
                      entry))
                    (typep
                     (cadr-agent:session-entry-message
                      entry)
                     'cadr-ai:assistant-message))
                   do
                   (let* ((usage
                            (cadr-ai:assistant-message-usage
                             (cadr-agent:session-entry-message
                              entry)))
                          (prompt
                            (+ (cadr-ai:usage-input usage)
                               (cadr-ai:usage-cache-read
                                usage)
                               (cadr-ai:usage-cache-write
                                usage))))
                     (return
                       (and
                        (plusp prompt)
                        (* 100d0
                           (/ (cadr-ai:usage-cache-read
                               usage)
                              prompt)))))))))
         (current-footer-state ()
           (let* ((model
                    (cadr-agent:agent-model agent))
                  (current
                    (cadr-agent:agent-session agent))
                  (stats
                    (and
                     current
                     (session-command-stats current)))
                  (providers
                    (remove-duplicates
                     (mapcar
                      #'cadr-ai:model-provider
                      available-models)
                     :test #'eq))
                  (messages
                    (and
                     current
                     (cadr-agent:session-messages
                      current))))
             (list
              :model (cadr-ai:model-id model)
              :provider
              (provider-config-name config)
              :thinking
              (and
               (cadr-ai:model-reasoning-p model)
               (cadr-agent::agent-thinking-level
                agent))
              :context-window
              (cadr-ai:model-context-window model)
              :context-percent
              (current-context-percent)
              :session-name
              (and
               current
               (cadr-agent:session-name current))
              :multiple-providers-p
              (> (length providers) 1)
              :subscription-p
              (not (null (config-subscription-p)))
              :auto-compact-p
              (cadr-agent::agent-auto-compact-p agent)
              :input (or (getf stats :input) 0)
              :output (or (getf stats :output) 0)
              :cache-read
              (or (getf stats :cache-read) 0)
              :cache-write
              (or (getf stats :cache-write) 0)
              :latest-cache-hit-rate
              (current-cache-hit-rate)
              :cost (or (getf stats :cost) 0d0)
              :cost-known-p
              (some
               (lambda (message)
                 (and
                  (typep
                   message
                   'cadr-ai:assistant-message)
                  (ignore-errors
                    (cadr-ai:find-model-metadata
                     (cadr-ai:assistant-message-provider
                      message)
                     (cadr-ai:assistant-message-model
                      message)))))
               messages))))
         (authentication-status (provider)
           (let ((credential
                   (and
                    (model-registry-credentials model-registry)
                    (auth-storage-read
                     (model-registry-credentials model-registry)
                     provider))))
             (when credential
               (list
                :type
                (if (typep credential
                           'cadr-ai:oauth-credential)
                    :oauth
                    :api-key)
                :source "stored credential"))))
         (stored-logout-options ()
           (logout-provider-options
            (cadr-ai:list-provider-definitions)
            (auth-storage-list
             (model-registry-credentials model-registry))))
         (refresh-auth (provider action)
           (let ((previous-auth-source
                   (provider-config-auth-source
                    config)))
             (refresh-available-models)
             (if
                 (and
                  (eq action :login)
                  (or
                   (eq previous-auth-source :none)
                   (not
                    (eq
                     provider
                     (cadr-ai:model-provider
                      (provider-config-model
                       config))))))
                 (let* ((definition
                          (cadr-ai:find-provider-definition
                           provider))
                        (model
                          (model-registry-find
                           model-registry
                           provider
                           (cadr-ai:provider-definition-default-model
                            definition))))
                   (unless
                       (and model
                            (find
                             model available-models
                             :test
                             #'cadr-ai:models-equal-p))
                     (error
                      'cadr-ai:configuration-error
                      :message
                      (format
                       nil
                       "No default model is available for provider ~A"
                       provider)))
                   (select-model model))
                 (let ((updated
                         (resolve-provider-config
                          :provider
                          (provider-config-name config)
                          :model
                          (cadr-ai:model-id
                           (provider-config-model config))
                          :base-url
                          (cli-arguments-base-url command)
                          :api-key
                          (cli-arguments-api-key command)
                          :allow-missing-auth-p t)))
                   (setf
                    config updated
                    (cadr-agent:agent-provider agent)
                    (provider-config-provider updated)
                    (cadr-agent:agent-model agent)
                    (provider-config-model updated))))))
         (select-logout-provider (provider)
           (auth-storage-delete
            (model-registry-credentials model-registry)
            provider)
           (refresh-auth provider :logout)
           provider)
         (run-prompt (prompt)
           (let ((*bash-live-output*
                   (bash-live-output-for-mode
                    mode frontend-output)))
             (cadr-agent:agent-prompt
              agent prompt
              :source
              (if (eq mode :rpc)
                  :rpc
                  :interactive))))
         (run-user-bash (command exclude-p)
           (multiple-value-bind (content details)
               (execute-user-bash
                (cli-extension-manager-host
                 extension-manager)
                cwd command
                :exclude-from-context-p
                exclude-p
                :abort-p
                (lambda () abort-requested-p))
             (declare (ignore details))
             (if content
                 (cadr-ai:text-content-text
                  (first content))
                 "")))
         (refresh-package-resources ()
           (setf
            package-records
            (materialize-package-records
             (configured-package-records
              settings-manager
              :global-base agent-directory
              :project-base
              (merge-pathnames ".cadr/" cwd))
             package-global-root
             package-project-root)
            package-resources
            (package-resource-paths
             package-records)
            (cli-extension-manager-configured-package-paths
             extension-manager)
            (unless
                (cli-arguments-no-extensions-p command)
              (append
               (mapcar
                (lambda (path)
                  (cons :project path))
                (getf package-resources
                      :project-extensions))
               (mapcar
                (lambda (path)
                  (cons :global path))
                (getf package-resources
                      :global-extensions))))
            (default-resource-loader-package-global-skill-paths
             resource-loader)
            (getf package-resources :global-skills)
            (default-resource-loader-package-project-skill-paths
             resource-loader)
            (getf package-resources :project-skills)
            (default-resource-loader-package-global-prompt-paths
             resource-loader)
            (getf package-resources :global-prompts)
            (default-resource-loader-package-project-prompt-paths
             resource-loader)
            (getf package-resources :project-prompts)
            (default-resource-loader-package-global-theme-paths
             resource-loader)
            (getf package-resources :global-themes)
            (default-resource-loader-package-project-theme-paths
             resource-loader)
            (getf package-resources :project-themes))
           package-resources)
         (handle-command (line)
           (or
            (handle-auth-command
             line
             :output frontend-output
             :auth-url-function
             auth-url-consumer
             :on-change #'refresh-auth)
            (handle-session-command
             line agent
             :directory session-directory
             :cwd cwd
             :output frontend-output
             :keybindings
             (settings-keybindings
              settings-manager))
            (if
                (string=
                 (string-trim
                  '(#\Space #\Tab #\Newline #\Return)
                  line)
                "/reload")
                (progn
                  (setf
                   resources
                   (reload-cli-runtime
                    agent settings-manager
                    :extension-reload-function
                    (lambda ()
                      (refresh-package-resources)
                      (reload-cli-extensions
                       extension-manager))
                    :resource-reload-function
                    (lambda ()
                      (reload-resources
                       resource-loader))
                    :system-prompt-function
                    (lambda (snapshot)
                      (resolve-cli-system-prompt
                       command snapshot
                       (cadr-agent::registry-tools
                        (cadr-agent::agent-tool-registry
                         agent))
                       cwd))
                    :model-refresh-function
                    (lambda ()
                      (refresh-available-models)
                      (refresh-agent-model-from-registry
                       agent model-registry
                       :api-key
                       (cli-arguments-api-key command)
                       :base-url
                       (cli-arguments-base-url command))
                      (update-session-scope
                       current-enabled-model-ids))
                    :keybindings-reload-function
                    (lambda ()
                      (cadr-tui:set-keybindings
                       (cadr-tui:make-keybindings-manager
                        :user-bindings
                        (settings-keybindings
                         settings-manager))))
                    :completion-function
                    (lambda (message)
                      (if status-consumer
                          (funcall status-consumer message)
                          (progn
                            (format frontend-output "~A~%" message)
                            (finish-output frontend-output))))))
                  t)
                (handle-extension-command
                 line extension-manager))))
         (expand-template (line)
           (expand-cli-extension-prompt
            extension-manager line))
         (model-items ()
           (loop
             for model in available-models
             collect
             (cadr-tui:make-select-item
              :label
              (format nil "~(~A~) / ~A"
                      (cadr-ai:model-provider model)
                      (cadr-ai:model-id model))
              :value model)))
         (refresh-available-models ()
           (refresh-model-registry model-registry)
           (setf
            available-models
            (model-registry-available-models
             model-registry
             :explicit-provider
             (cli-arguments-provider command)
             :api-key
             (cli-arguments-api-key command)))
           available-models)
         (select-model (model)
           (let ((updated
                   (apply-cli-model-selection
                    agent model-registry model
                    settings-manager
                    :api-key
                    (and
                     (cli-arguments-provider command)
                     (string-equal
                      (provider-key
                       (cadr-ai:model-provider model))
                      (provider-key
                       (cli-arguments-provider
                        command)))
                     (cli-arguments-api-key command))
                    :base-url
                    (and
                     (cli-arguments-provider command)
                     (string-equal
                      (provider-key
                       (cadr-ai:model-provider model))
                      (provider-key
                       (cli-arguments-provider
                        command)))
                     (cli-arguments-base-url
                      command))
                    :source :interactive)))
             (setf config updated)
             (let* ((model-id
                      (cadr-ai:model-id
                       (provider-config-model updated)))
                    (warning
                      (anthropic-warning)))
               (when model-consumer
                 (funcall
                  model-consumer model-id
                  (provider-config-name
                   updated)
                  (cadr-ai:model-context-window
                   (provider-config-model updated))
                  (and
                   (cadr-ai:model-reasoning-p
                    (provider-config-model updated))
                   (cadr-agent::agent-thinking-level
                    agent))
                  (if
                      (config-subscription-p)
                      t
                      :not-subscription)))
               (when
                   (and warning
                        notice-consumer)
                 (funcall
                  notice-consumer warning))
               model-id)))
         (resolve-model-reference (reference)
           (refresh-available-models)
           (exact-model-reference-match
            reference
            (if scoped-model-entries
                (mapcar
                 (lambda (entry)
                   (getf entry :model))
                 scoped-model-entries)
                available-models)))
         (model-selector (&optional query)
           (refresh-available-models)
           (let ((selector
                   (make-model-selector-state
                    :all-models available-models
                    :scoped-models
                    (mapcar
                     (lambda (entry)
                       (getf entry :model))
                     scoped-model-entries)
                    :current-model
                    (cadr-agent:agent-model agent)
                    :refresh-status-message
                    (and
                     (null
                      (model-registry-error
                       model-registry))
                     "Model catalogs refreshed.")
                    :keybindings
                    (make-models-selector-keybindings
                     (settings-keybindings
                      settings-manager)))))
             (when query
               (model-selector-set-query
                selector query))
             selector))
         (update-session-scope (enabled-ids)
           (setf
            current-enabled-model-ids
            (if (eq enabled-ids :all)
                :all
                (copy-list enabled-ids))
            scoped-model-entries
            (mapcar
             (lambda (model)
               (list :model model
                     :thinking nil))
             (session-scoped-models
              available-models enabled-ids))))
         (persist-model-scope (enabled-ids)
           (settings-set-enabled-models
            settings-manager enabled-ids)
           (when notice-consumer
             (funcall
              notice-consumer
              "Model selection saved to settings")))
         (scoped-models-selector ()
           (refresh-available-models)
           (when
               (or available-models
                   (and
                    (listp current-enabled-model-ids)
                    current-enabled-model-ids))
             (make-scoped-models-selector-state
              :all-models available-models
              :enabled-ids
              current-enabled-model-ids
              :change-callback
              #'update-session-scope
              :persist-callback
              #'persist-model-scope
              :keybindings
              (make-models-selector-keybindings
               (settings-keybindings
                settings-manager)))))
         (trust-selector ()
           (make-trust-selector-state
            :cwd cwd
            :saved-entry
            (project-trust-entry
             trust-store cwd)
            :project-trusted-p
            project-trusted-p
            :keybindings
            (cadr-tui:make-keybindings-manager
             :user-bindings
             (settings-keybindings
              settings-manager))))
         (settings-selector ()
           (make-cli-settings-selector-state
            settings-manager agent resources
            :keybindings
            (cadr-tui:make-keybindings-manager
             :user-bindings
             (settings-keybindings
              settings-manager))))
         (select-trust (selection)
           (project-trust-set-many
            trust-store
            (getf selection :updates))
           (when notice-consumer
             (funcall
              notice-consumer
              (format
               nil
               "Saved trust decision: ~A. Restart cadr for this to take effect."
               (if
                   (getf selection :trusted-p)
                   "trusted"
                   "untrusted"))))
           (getf selection :trusted-p))
         (confirm-import (line)
           (handle-session-command
            line agent
            :directory session-directory
            :cwd cwd
            :output frontend-output
            :confirm-function
            (lambda (title message)
              (declare (ignore title message))
              t)))
         (fork-items ()
           (loop
             for item in
             (session-user-messages-for-forking
              (cadr-agent:agent-session agent))
             collect
             (cadr-tui:make-select-item
              :label (getf item :text)
              :value (getf item :entry-id))))
         (select-fork-entry (entry-id)
           (multiple-value-bind
                 (fork selected-text)
               (fork-agent-session
                agent entry-id
                session-directory)
             (if (eq fork :cancelled)
                 (values nil nil nil nil)
                 (values
                  (cadr-agent:session-id fork)
                  (copy-list
                   (cadr-agent:session-messages
                    fork))
                  (cadr-agent:session-path fork)
                  selected-text))))
         (start-new-session ()
           (let ((new
                   (new-agent-session
                    agent session-directory cwd)))
             (if (eq new :cancelled)
                 (values nil nil nil)
                 (values
                  (cadr-agent:session-id new)
                  (copy-list
                   (cadr-agent:session-messages new))
                  (cadr-agent:session-path new)))))
         (session-items ()
           (loop
             for candidate in
             (cadr-agent:list-sessions
              :directory session-directory
              :cwd cwd)
             collect
             (cadr-tui:make-select-item
              :label
              (format nil "~A  ~D messages"
                      (cadr-agent:session-id
                       candidate)
                      (length
                       (cadr-agent:session-messages
                        candidate)))
              :value candidate)))
         (all-session-items ()
           (loop
             for candidate in
             (cadr-agent:list-sessions
              :directory session-directory)
             collect
             (cadr-tui:make-select-item
              :label
              (format nil "~A  ~D messages"
                      (cadr-agent:session-id
                       candidate)
                      (length
                       (cadr-agent:session-messages
                        candidate)))
              :value candidate)))
         (current-session-display-state ()
           (let ((current
                   (cadr-agent:agent-session
                    agent)))
             (if (null current)
                 (values nil nil nil)
                 (let* ((entries
                          (cadr-agent::session-path-entries
                           current))
                        (compaction
                          (find
                           :compaction entries
                           :from-end t
                           :key
                           #'cadr-agent:session-entry-type)))
                   (values
                    (loop
                      for entry in entries
                      when
                        (eq
                         :message
                         (cadr-agent:session-entry-type
                          entry))
                        collect
                        (cadr-agent:session-entry-message
                         entry))
                    (and
                     compaction
                     (cadr-agent:session-entry-summary
                      compaction))
                    (and
                     compaction
                     (cadr-agent:session-entry-tokens-before
                      compaction)))))))
         (select-session (candidate)
           (switch-agent-session agent candidate)
           (values
            (cadr-agent:session-id candidate)
            (cadr-agent:session-messages
             candidate)
            (cadr-agent:session-path candidate)))
         (current-session-tree ()
           (session-tree-selector-data
            (cadr-agent:agent-session agent)))
         (select-tree-entry (entry-id)
           (multiple-value-bind
                 (messages cancelled-p)
               (cadr-agent:agent-navigate-tree
                agent entry-id)
             (unless cancelled-p
               messages)))
         (set-tree-label (entry-id label)
           (let ((session
                   (cadr-agent:agent-session agent)))
             (unless session
               (error
                'cadr-ai:configuration-error
                :message
                "The agent has no persistent session"))
             (cadr-agent:session-set-label
              session entry-id label))))
      (call-with-remote-repl
       agent
       (cli-arguments-slynk-port command)
       (lambda ()
         (call-with-cli-signal-handlers
          agent
          (lambda ()
            (case mode
           (:tui
            (multiple-value-bind
                  (file-text file-images)
                (process-cli-file-arguments
                 (cli-arguments-file-arguments
                  command)
                 cwd)
              (multiple-value-bind
                    (initial messages)
                  (build-cli-print-prompts
                   command nil
                   :file-text file-text
                   :file-images file-images)
                (when initial
                  (run-prompt initial))
                (dolist (message messages)
                  (run-prompt message))))
            (multiple-value-bind
                  (startup-compact
                   startup-expanded)
                (if
                    (or
                     (cli-arguments-verbose-p command)
                     (not
                      (settings-value
                       settings-manager
                       "quietStartup" nil)))
                    (make-tui-startup-lines resources)
                    (values nil nil))
              (run-tui
           #'run-prompt
           :command-function #'handle-command
           :template-function #'expand-template
           :bash-function #'run-user-bash
           :set-event-consumer
           (lambda (consumer)
             (setf event-consumer consumer))
           :set-notice-consumer
           (lambda (consumer)
             (setf notice-consumer consumer))
           :set-status-consumer
           (lambda (consumer)
             (setf status-consumer consumer))
           :set-auth-url-consumer
           (lambda (consumer)
             (setf auth-url-consumer consumer))
           :set-model-consumer
           (lambda (consumer)
             (setf model-consumer consumer))
           :set-extension-ui-function
           (lambda (function)
             (setf
              (cadr-agent::extension-host-ui-function
               (cli-extension-manager-host
                extension-manager))
              function))
           :footer-state-function
           #'current-footer-state
           :footer-cwd cwd
           :available-provider-count
           (length
            (remove-duplicates
             (mapcar
              #'cadr-ai:model-provider
              available-models)
             :test #'eq))
           :subscription-p
           (not (null (config-subscription-p)))
           :autocomplete-max-visible
           (settings-choice-value
            settings-manager
            "autocompleteMaxVisible"
            '(3 5 7 10 15 20) 5)
           :show-terminal-progress-function
           (lambda ()
             (settings-show-terminal-progress-p
              settings-manager))
           :theme-function
           (lambda ()
             (let* ((configured
                      (settings-value
                       settings-manager
                       "theme" nil))
                    (background
                      (theme-detection-theme
                       (detect-background-from-environment)))
                    (name
                      (or
                       (and
                        configured
                        (resolve-theme-setting
                         configured background))
                       (string-downcase
                        (symbol-name
                         background)))))
               (or
                (find
                 name
                 (resource-snapshot-themes
                  resources)
                 :key
                 (lambda (theme)
                   (getf theme :name))
                 :test #'string=)
                (list :name name :path nil))))
           :preview-theme-function
           (lambda (theme-setting)
             (let* ((background
                      (theme-detection-theme
                       (detect-background-from-environment)))
                    (name
                      (or
                       (resolve-theme-setting
                        theme-setting background)
                       (string-downcase
                        (symbol-name background)))))
               (or
                (find
                 name
                 (resource-snapshot-themes resources)
                 :key
                 (lambda (theme)
                   (getf theme :name))
                 :test #'string=)
                (list :name name :path nil))))
           :theme-mode-function
           (lambda ()
             (settings-terminal-theme-mode
              settings-manager))
           :detected-theme-function
           (lambda (background)
             (let* ((configured
                      (settings-value
                       settings-manager
                       "theme" nil))
                    (name
                      (or
                       (and
                        configured
                        (resolve-theme-setting
                         configured background))
                       (string-downcase
                        (symbol-name
                         background)))))
               (or
                (find
                 name
                 (resource-snapshot-themes
                  resources)
                 :key
                 (lambda (theme)
                   (getf theme :name))
                 :test #'string=)
                (list :name name :path nil))))
           :all-themes-function
           (lambda ()
             (let ((themes
                     (copy-list
                      (resource-snapshot-themes
                       resources))))
               (dolist (name '("light" "dark"))
                 (unless
                     (find
                      name themes
                      :key
                      (lambda (theme)
                        (getf theme :name))
                      :test #'string=)
                   (push
                    (list :name name :path nil)
                    themes)))
               (nreverse themes)))
           :get-theme-function
           (lambda (name)
             (or
              (find
               name
               (resource-snapshot-themes resources)
               :key
               (lambda (theme)
                 (getf theme :name))
               :test #'string=)
              (and
               (member name '("dark" "light")
                       :test #'string=)
               (list :name name :path nil))))
           :set-theme-function
           (lambda (theme)
             (let* ((name
                      (cond
                        ((stringp theme) theme)
                        ((hash-table-p theme)
                         (cadr-ai::json-get
                          theme "name"))
                        ((listp theme)
                         (getf theme :name))))
                    (known
                      (and
                       (stringp name)
                       (or
                        (member
                         name '("dark" "light")
                         :test #'string=)
                        (find
                         name
                         (resource-snapshot-themes
                          resources)
                         :key
                         (lambda (entry)
                           (getf entry :name))
                         :test #'string=)))))
               (if known
                   (progn
                     (settings-set
                      settings-manager
                      "theme" name
                      :scope :global)
                     (list :success t))
                   (list
                    :success nil
                    :error
                    (format nil
                            "Theme not found: ~A"
                            name)))))
           :session-state-function
           #'current-session-display-state
           :busy-input-function
           (lambda (text)
             (multiple-value-bind
                   (message handled-p)
                 (cadr-agent::apply-agent-input-hooks
                  agent text :interactive
                  :streaming-behavior :steer)
               (unless handled-p
                 (cadr-agent:agent-steer
                  agent message))))
           :follow-up-input-function
           (lambda (text)
             (multiple-value-bind
                   (message handled-p)
                 (cadr-agent::apply-agent-input-hooks
                  agent text :interactive
                  :streaming-behavior :follow-up)
               (unless handled-p
                 (cadr-agent:agent-follow-up
                  agent message))))
           :dequeue-function
           (lambda ()
             (multiple-value-bind (steering follow-up)
                 (cadr-agent::clear-live-agent-queues
                  agent)
               (mapcar
                (lambda (message)
                  (cadr-ai::content-text
                   (cadr-ai:user-message-content
                    message)))
                (append steering follow-up))))
           :model-items-function #'model-items
           :model-selector-function
           #'model-selector
           :scoped-models-selector-function
           #'scoped-models-selector
           :trust-selector-function
           #'trust-selector
           :settings-selector-function
           #'settings-selector
           :extension-host
           (cli-extension-manager-host
            extension-manager)
           :fork-items-function #'fork-items
           :session-items-function #'session-items
           :all-session-items-function
           #'all-session-items
           :tree-state-function
           #'current-session-tree
           :api-key-login-function
           (lambda (provider key)
             (model-registry-login-api-key
              model-registry provider key)
             (refresh-auth provider :login))
           :auth-status-function #'authentication-status
           :logout-options-function #'stored-logout-options
           :on-model-selected #'select-model
           :on-logout-selected #'select-logout-provider
           :resolve-model-reference-function
           #'resolve-model-reference
           :on-trust-selected #'select-trust
           :on-import-confirmed #'confirm-import
           :on-fork-selected #'select-fork-entry
           :on-new-session #'start-new-session
           :on-session-selected #'select-session
           :on-tree-selected #'select-tree-entry
           :on-tree-label #'set-tree-label
           :tree-copy-function #'default-copy-text
           :current-session-path
           (and
            (cadr-agent:agent-session agent)
            (cadr-agent:session-path
             (cadr-agent:agent-session agent)))
           :session-selector-keybindings-function
           (lambda ()
             (make-session-selector-keybindings
              (settings-keybindings
               settings-manager)))
           :tree-selector-keybindings-function
           (lambda ()
             (make-tree-selector-keybindings
              (settings-keybindings
               settings-manager)))
           :abort-function
           (lambda ()
             (setf abort-requested-p t)
             (cadr-agent:agent-abort agent))
           :reset-abort-function
           (lambda ()
             (setf abort-requested-p nil))
           :model
           (cadr-ai:model-id
            (cadr-agent:agent-model agent))
           :provider
           (provider-config-name config)
           :thinking
           (cadr-agent::agent-thinking-level
            agent)
           :cwd
           (format-cwd-for-footer
            (namestring
             (uiop:ensure-directory-pathname
              cwd))
            (namestring
             (uiop:ensure-directory-pathname
              (user-homedir-pathname))))
           :branch
           (ignore-errors
             (let ((paths
                     (find-git-footer-paths
                      cwd)))
               (and paths
                    (resolve-git-footer-branch
                     paths))))
           :session-name
           (and
            (cadr-agent:agent-session agent)
            (cadr-agent:session-name
             (cadr-agent:agent-session
              agent)))
           :context-window
           (cadr-ai:model-context-window
            (cadr-agent:agent-model agent))
           :session
           (and
            (cadr-agent:agent-session agent)
            (cadr-agent:session-id
             (cadr-agent:agent-session agent)))
           :messages
           (copy-list
            (cadr-agent:agent-messages agent))
           :startup-compact-lines
           startup-compact
           :startup-expanded-lines
           startup-expanded
           :alt-p
           (cli-arguments-alt-p command)
           :show-hardware-cursor-p
           (or
            (settings-value
             settings-manager
             "showHardwareCursor" nil)
            (string=
             (or
              (uiop:getenv
               "CADR_HARDWARE_CURSOR")
              "")
             "1"))
           :initial-notices
           (let ((warning
                   (anthropic-warning)))
             (and warning
                  (list warning)))))
            0)
           (:repl
            (setf event-consumer renderer)
            (multiple-value-bind
                  (file-text file-images)
                (process-cli-file-arguments
                 (cli-arguments-file-arguments
                  command)
                 cwd)
              (multiple-value-bind
                    (initial messages)
                  (build-cli-print-prompts
                   command nil
                   :file-text file-text
                   :file-images file-images)
                (when initial
                  (run-prompt initial))
                (dolist (message messages)
                  (run-prompt message))))
            (run-repl
             #'run-prompt
             :command-function #'handle-command
             :template-function #'expand-template
             :bash-function #'run-user-bash
             :render-response nil)
            0)
           ((:text :json)
            (multiple-value-bind
                  (file-text file-images)
                (process-cli-file-arguments
                 (cli-arguments-file-arguments
                  command)
                 cwd)
              (multiple-value-bind
                 (initial messages)
                  (build-cli-print-prompts
                   command
                   (unless input-terminal-p
                     (let ((text
                             (uiop:slurp-stream-string
                              *standard-input*)))
                       (and
                        (plusp (length text))
                        text)))
                   :file-text file-text
                   :file-images file-images)
                (run-print-mode
                 agent initial messages
                 :mode mode))))
              (:rpc
               (run-rpc-mode
                agent extension-manager
                :input *standard-input*
                :output *standard-output*
                :error-output *error-output*))))))))))

(defun main (&optional
               (argv
                 (uiop:command-line-arguments)))
  (handler-case
      (progn
        (ensure-user-data-migrated :argv argv)
        (multiple-value-bind
              (handled-p status)
            (handle-package-command
             argv
             :offline-p
             (or
              (member "--offline" argv
                      :test #'string=)
              (string=
               "1"
               (or
                (uiop:getenv
                 "CADR_OFFLINE")
                ""))))
          (when handled-p
            (return-from main status)))
        (multiple-value-bind
              (handled-p status)
            (run-credential-print-command
             argv)
          (when handled-p
            (return-from main status)))
        (let ((arguments
                (parse-cli-arguments argv)))
          (dolist
              (diagnostic
               (cli-arguments-diagnostics
                arguments))
            (format
             *error-output*
             "~:(~A~): ~A~%"
             (getf diagnostic :type)
             (getf diagnostic :message)))
          (when
              (find
               :error
               (cli-arguments-diagnostics
                arguments)
               :key
               (lambda (diagnostic)
                 (getf diagnostic :type)))
            (return-from main 1))
          (cond
            ((cli-arguments-help-p arguments)
             (print-cli-usage)
             0)
            ((cli-arguments-version-p arguments)
             (format t "~A~%"
                     (cadr-ai::cadr-release-identity))
             0)
            ((cli-arguments-list-models arguments)
             (print-cli-models
              (let ((value
                      (cli-arguments-list-models
                       arguments)))
                (and (stringp value)
                     value)))
             0)
            ((cli-arguments-export arguments)
             (let* ((session
                      (cadr-agent:load-session
                       (cli-arguments-export
                        arguments)))
                    (target
                      (pathname
                       (or
                        (first
                         (cli-arguments-messages
                          arguments))
                        (format
                         nil "~A.html"
                         (cadr-agent:session-id
                          session))))))
               (cadr-agent:export-session-html
                session target)
               (format t "Exported to: ~A~%"
                       (namestring target))
               0))
            ((and
              (eq
               (cli-arguments-mode arguments)
               :rpc)
              (cli-arguments-file-arguments
               arguments))
             (format
              *error-output*
              "cadr: @file arguments are not supported in RPC mode~%")
             1)
            (t
             (cli-handler arguments)))))
    (cadr-ai:cadr-error (condition)
      (format *error-output* "cadr: ~A~%" condition)
      (finish-output *error-output*)
      1)
    (error (condition)
      (format *error-output* "cadr: ~A~%" condition)
      (finish-output *error-output*)
      1)))
